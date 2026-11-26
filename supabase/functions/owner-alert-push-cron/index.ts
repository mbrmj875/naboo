// Owner Command Center v3.3 — تنبيهات العمل التسعة (تُكتب في notifications، وnotify-dispatch يرسلها)
//
// Deploy:
//   supabase functions deploy owner-alert-push-cron --no-verify-jwt
//
// Schedule (pg_cron or Dashboard): */15 * * * *
//
// Secrets:
//   PUSH_FCM_SERVICE_ACCOUNT_JSON + PUSH_ALLOWED_USER_IDS (فارغ = لا إرسال)
//   CRON_SECRET (required Bearer guard — fail closed if missing)
//   SUPABASE_SERVICE_ROLE_KEY (auto in Edge runtime)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { filterWithCooldown, recordSentAlerts } from './cooldown.ts';
import { evaluateAlertsFromSnapshot } from './evaluate_alerts.ts';
import { audienceForAlert } from './audience.ts';
import { pushAllowedForUser } from './fcm.ts';
import { shouldEvaluateSnapshot } from './schedule.ts';
import { loadSnapshotTables } from './snapshot_loader.ts';
import type { OwnerAlertPrefs, PushAlertCandidate } from './types.ts';

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  const cronSecret = (Deno.env.get('CRON_SECRET') ?? '').trim();
  const authHeader = req.headers.get('Authorization') ?? '';
  if (!cronSecret || authHeader !== `Bearer ${cronSecret}`) {
    return new Response('Unauthorized', { status: 401 });
  }

  // {"force": true} من الاستدعاء اليدوي: يقيّم كل حساب مسموح حتى لو لم تتغير بياناته.
  let force = false;
  try {
    const body = await req.json();
    force = body?.force === true;
  } catch {
    // جسم فارغ أو غير JSON
  }
  const now = new Date();

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin = createClient(supabaseUrl, serviceKey);

  const { data: prefsRows, error: prefsErr } = await admin
    .from('owner_alert_preferences')
    .select(
      'user_id, local_tenant_id, vertical, thresholds, push_alert_ids, feature_flags',
    );

  if (prefsErr) {
    return Response.json({ ok: false, error: prefsErr.message }, { status: 500 });
  }

  const sent: string[] = [];
  const skipped: string[] = [];

  for (const prefs of (prefsRows ?? []) as OwnerAlertPrefs[]) {
    // قبل أي قراءة: الحساب خارج قائمة الإرسال لا يُحمَّل له شيء.
    if (!pushAllowedForUser(prefs.user_id)) {
      skipped.push(`${prefs.user_id}:${prefs.local_tenant_id}:gated`);
      continue;
    }

    const pushIds = Array.isArray(prefs.push_alert_ids)
      ? prefs.push_alert_ids.map(String)
      : [];
    if (pushIds.length === 0) {
      skipped.push(`${prefs.user_id}:${prefs.local_tenant_id}:no_push_ids`);
      continue;
    }

    // لا جهاز مسجل بالنسخة الجديدة أو لا هاتف مالك: الإشعار سيُحجب على أي حال،
    // فلا تُحمَّل نسخة بيانات الحساب أصلا (قاعدة «لا إشعارات قبل تحديد هاتف المالك»).
    const [{ count: deviceCount }, { count: ownerPhones }] = await Promise.all([
      admin.from('push_devices').select('id', { count: 'exact', head: true })
        .eq('user_id', prefs.user_id).eq('enabled', true),
      admin.from('account_devices').select('id', { count: 'exact', head: true })
        .eq('user_id', prefs.user_id).eq('owner_notify', true),
    ]);
    if (!deviceCount) {
      skipped.push(`${prefs.user_id}:${prefs.local_tenant_id}:no_devices`);
      continue;
    }
    if (!ownerPhones) {
      skipped.push(`${prefs.user_id}:${prefs.local_tenant_id}:no_owner_phone`);
      continue;
    }

    // نسخة لم تتغير منذ الدورة السابقة تُقيَّم مرة في الساعة فقط.
    const { data: snapMeta } = await admin
      .from('app_snapshots')
      .select('updated_at')
      .eq('user_id', prefs.user_id)
      .maybeSingle();
    if (!shouldEvaluateSnapshot(snapMeta?.updated_at as string | undefined, now, force)) {
      skipped.push(`${prefs.user_id}:${prefs.local_tenant_id}:unchanged`);
      continue;
    }

    const tables = await loadSnapshotTables(admin, prefs.user_id);
    if (!tables) {
      skipped.push(`${prefs.user_id}:${prefs.local_tenant_id}:no_snapshot`);
      continue;
    }

    const candidates = evaluateAlertsFromSnapshot(prefs, tables, pushIds);
    const toSend = await filterWithCooldown(
      admin,
      prefs.user_id,
      prefs.local_tenant_id,
      candidates,
    );

    if (!toSend.length) {
      skipped.push(`${prefs.user_id}:${prefs.local_tenant_id}:cooldown_or_clear`);
      continue;
    }

    // المرحلة 1، البند 3: التنبيه يُكتب في السجل الموحد، وnotify-dispatch يرسله
    // (الجمهور، الهدوء، الحد، الأجهزة). الإرسال المباشر لرموز owner_fcm_tokens توقف.
    const bucket = Math.floor(now.getTime() / (6 * 3600_000));
    const written: PushAlertCandidate[] = [];
    for (const alert of toSend) {
      const { error } = await admin.rpc('notify_write_business_alert', {
        p_user_id: prefs.user_id,
        p_tenant: prefs.local_tenant_id,
        p_type: alert.alertId,
        p_title: alert.titleAr,
        p_body: alert.bodyAr,
        p_route: alert.actionKind,
        p_audience: audienceForAlert(alert.alertId),
        p_dedupe: `alert:${prefs.local_tenant_id}:${alert.alertId}:${alert.metricCount}:${bucket}`,
      });
      if (error) {
        console.error('notify_write_business_alert', alert.alertId, error.message);
        continue;
      }
      sent.push(`${prefs.user_id}:${alert.alertId}`);
      written.push(alert);
    }

    if (written.length) {
      await recordSentAlerts(
        admin,
        prefs.user_id,
        prefs.local_tenant_id,
        written,
      );
    }
  }

  return Response.json({ ok: true, sent, skipped });
});
