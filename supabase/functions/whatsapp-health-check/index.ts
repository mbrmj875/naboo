/**
 * شبكة أمان ثانوية — فحص جلسات واتساب المفصولة مؤقتاً كل ~5 دقائق.
 *
 * Deploy:
 *   supabase functions deploy whatsapp-health-check --no-verify-jwt
 *
 * Schedule (every 5 minutes): 0,5,10,15,20,25,30,35,40,45,50,55 * * * *
 *
 * Secrets:
 *   CRON_SECRET (required Bearer — fail closed if missing)
 *   WAHA_API_KEY / WAHA_BASE_URL
 *   FCM_SERVICE_ACCOUNT_JSON (لإشعار فشل الإيقاظ)
 *
 * لا يلمس صفوفاً عليها repair_needed = true.
 */
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { sendFcmDataMessage } from '../owner-alert-push-cron/fcm.ts';
import {
  canAttemptRestart,
  FCM_ALERT_COOLDOWN_MS,
  RESTART_MAX_ATTEMPTS,
} from '../whatsapp-gateway/disconnect_classify.ts';
import { writeDiagnostic } from '../whatsapp-gateway/diagnostics.ts';
import {
  readEvolutionLiveState,
  softReconnectEvolutionSession,
} from '../whatsapp-gateway/waha.ts';

const BATCH_LIMIT = 50;

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  const cronSecret = (Deno.env.get('CRON_SECRET') ?? '').trim();
  const authHeader = req.headers.get('Authorization') ?? '';
  if (!cronSecret || authHeader !== `Bearer ${cronSecret}`) {
    return new Response('Unauthorized', { status: 401 });
  }

  const sb = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: rows, error } = await sb
    .from('tenant_whatsapp_gateways')
    .select(
      'user_id, evolution_instance_name, status, repair_needed, restart_attempts, last_restart_at, disconnect_cause, last_disconnected_at, updated_at',
    )
    .eq('status', 'disconnected')
    .eq('repair_needed', false)
    .order('updated_at', { ascending: true })
    .limit(BATCH_LIMIT);

  if (error) {
    return Response.json({ ok: false, error: error.message }, { status: 500 });
  }

  const summary = {
    scanned: rows?.length ?? 0,
    healed: 0,
    restarted_ok: 0,
    restarted_fail: 0,
    skipped: 0,
    notified: 0,
    marked_removed: 0,
  };

  for (const row of rows ?? []) {
    const userId = row.user_id as string;
    const instanceName = row.evolution_instance_name as string;
    const now = new Date().toISOString();

    const live = await readEvolutionLiveState(instanceName);

    if (live.notFound) {
      // جلسة محذوفة = دائم — علّم repair بدون restart
      await sb.from('tenant_whatsapp_gateways').update({
        status: 'disconnected',
        repair_needed: true,
        restart_attempts: 0,
        disconnect_cause: 'removed',
        last_disconnected_at: now,
        updated_at: now,
        whatsapp_phone: null,
      }).eq('user_id', userId);

      const push = await notifyOwner(sb, {
        userId,
        alertId: 'whatsapp_gateway_repair_needed',
        titleAr: 'يلزم إعادة ربط واتساب المحل',
        bodyAr:
          'جلسة واتساب غير موجودة على السيرفر — امسح QR من جديد.',
      });
      summary.marked_removed += 1;
      summary.notified += push > 0 ? 1 : 0;
      await writeDiagnostic({
        userId,
        instanceName,
        eventType: 'health_check',
        severity: 'error',
        connectionState: 'removed',
        outcome: 'repair_needed',
        reasonCode: 'instance_removed',
        meta: { push_sent: push },
      });
      continue;
    }

    if (live.ok && live.mapped.connected) {
      await sb.from('tenant_whatsapp_gateways').update({
        status: 'connected',
        whatsapp_phone: live.mapped.phone,
        last_connected_at: now,
        updated_at: now,
        repair_needed: false,
        restart_attempts: 0,
        disconnect_cause: null,
      }).eq('user_id', userId);
      summary.healed += 1;
      await writeDiagnostic({
        userId,
        instanceName,
        eventType: 'health_check',
        severity: 'info',
        connectionState: 'open',
        outcome: 'healed_already_open',
      });
      continue;
    }

    const attempts = Number(row.restart_attempts ?? 0);
    const gate = canAttemptRestart({
      restartAttempts: attempts,
      lastRestartAt: (row.last_restart_at as string | null) ?? null,
    });

    if (!gate.ok) {
      summary.skipped += 1;
      if (gate.reason === 'max_attempts') {
        const push = await notifyOwner(sb, {
          userId,
          alertId: 'whatsapp_gateway_reconnect_failed',
          titleAr: 'تعذّر إيقاظ واتساب المحل',
          bodyAr:
            'انقطع واتساب مؤقتاً وتعذّر الإيقاظ التلقائي — افتح ربط واتساب من الإعدادات.',
        });
        if (push > 0) summary.notified += 1;
      }
      continue;
    }

    const soft = await softReconnectEvolutionSession(instanceName, {
      timeoutMs: 10_000,
    });
    const newAttempts = attempts + 1;

    if (soft.ok) {
      await sb.from('tenant_whatsapp_gateways').update({
        status: 'connected',
        last_connected_at: now,
        updated_at: now,
        repair_needed: false,
        restart_attempts: 0,
        last_restart_at: now,
        disconnect_cause: null,
      }).eq('user_id', userId);
      summary.restarted_ok += 1;
      await writeDiagnostic({
        userId,
        instanceName,
        eventType: 'soft_reconnect',
        severity: 'info',
        connectionState: 'connected',
        outcome: 'reconnected',
        technicalDetail: `health_check;attempt=${newAttempts};elapsedMs=${soft.elapsedMs}`,
        meta: { source: 'whatsapp-health-check' },
      });
      continue;
    }

    await sb.from('tenant_whatsapp_gateways').update({
      status: 'disconnected',
      updated_at: now,
      restart_attempts: newAttempts,
      last_restart_at: now,
      repair_needed: false,
      disconnect_cause: (row.disconnect_cause as string | null) ??
        soft.finalState.slice(0, 120),
    }).eq('user_id', userId);

    summary.restarted_fail += 1;
    await writeDiagnostic({
      userId,
      instanceName,
      eventType: 'soft_reconnect',
      severity: 'warn',
      connectionState: soft.finalState,
      outcome: 'failed',
      reasonCode: 'soft_reconnect_failed',
      technicalDetail: `health_check;attempt=${newAttempts};final=${soft.finalState}`,
      meta: { source: 'whatsapp-health-check' },
    });

    if (newAttempts >= RESTART_MAX_ATTEMPTS) {
      const push = await notifyOwner(sb, {
        userId,
        alertId: 'whatsapp_gateway_reconnect_failed',
        titleAr: 'تعذّر إيقاظ واتساب المحل',
        bodyAr:
          'انقطع واتساب مؤقتاً وتعذّر الإيقاظ التلقائي — افتح ربط واتساب من الإعدادات.',
      });
      if (push > 0) summary.notified += 1;
    }
  }

  return Response.json({ ok: true, ...summary });
});

async function notifyOwner(
  sb: SupabaseClient,
  args: {
    userId: string;
    alertId: string;
    titleAr: string;
    bodyAr: string;
  },
): Promise<number> {
  const { data: prev } = await sb
    .from('owner_push_alert_log')
    .select('sent_at')
    .eq('user_id', args.userId)
    .eq('local_tenant_id', 1)
    .eq('alert_id', args.alertId)
    .maybeSingle();
  if (prev?.sent_at) {
    const t = Date.parse(String(prev.sent_at));
    if (Number.isFinite(t) && Date.now() - t < FCM_ALERT_COOLDOWN_MS) {
      return 0;
    }
  }

  const { data: tokens } = await sb
    .from('owner_fcm_tokens')
    .select('token')
    .eq('user_id', args.userId);

  const alert = {
    alertId: args.alertId,
    actionKind: 'openWhatsappConnect',
    titleAr: args.titleAr,
    bodyAr: args.bodyAr,
    tenantId: 1,
    metricCount: 1,
  };

  let sent = 0;
  for (const row of tokens ?? []) {
    const ok = await sendFcmDataMessage(row.token, alert);
    if (ok) sent += 1;
  }
  if (sent > 0) {
    await sb.from('owner_push_alert_log').upsert({
      user_id: args.userId,
      local_tenant_id: 1,
      alert_id: args.alertId,
      metric_count: 1,
      sent_at: new Date().toISOString(),
    }, { onConflict: 'user_id,local_tenant_id,alert_id' });
  }
  return sent;
}
