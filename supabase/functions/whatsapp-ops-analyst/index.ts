/**
 * WhatsApp Ops Analyst — دورة AIOps كل 5 دقائق.
 * المصنّف الحتمي يفتح الحوادث؛ DeepSeek يُثري فقط؛ Healthchecks عند النجاح.
 */
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import {
  DELIVERY_WINDOW_MS,
  FLAP_WINDOW_MS,
  P1_SLA_MS,
  PLAYBOOK,
  RESOLVE_STABLE_MS,
  type Severity,
} from './constants.ts';
import {
  classifyTenant,
  countFlapTransitions,
  detect463Then401,
  type ClassifiedCondition,
} from './classifier.ts';
import { applyPersistenceGate } from './persistence.ts';
import { dispatchIncidentAlerts } from './alerts.ts';
import {
  retrieveSimilarLessons,
  upsertLessonFromIncident,
} from './lessons.ts';
import { enrichWithDeepSeek } from './enrich.ts';
import { pingHealthchecks } from './heartbeat.ts';
import { writeOpsFact } from './facts.ts';
import { incidentFingerprint } from './fingerprint.ts';
import {
  classifyDeliveryAlerts,
  type DeliveryLogRow,
  STUCK_QUEUED_LOOKBACK_MS,
} from './delivery_alerts.ts';

type GateRow = {
  user_id: string;
  evolution_instance_name: string;
  status: string | null;
  repair_needed: boolean | null;
  disconnect_cause: string | null;
};

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const secret =
    Deno.env.get('WHATSAPP_OPS_ANALYST_SECRET') ??
    Deno.env.get('CRON_SECRET') ??
    '';
  if (!secret) {
    return Response.json({ ok: false, error: 'misconfigured' }, { status: 500 });
  }
  const auth =
    req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '') ??
    req.headers.get('x-cron-secret') ??
    '';
  if (auth !== secret) {
    return new Response('Unauthorized', { status: 401 });
  }

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  if (body.action === 'test_email') {
    const to = String(body.to ?? '').trim().toLowerCase();
    if (!to || !to.includes('@')) {
      return Response.json({ ok: false, error: 'to required' }, { status: 400 });
    }
    const subject = String(body.subject ?? 'اختبار تنبيه واتساب — نبّو').slice(0, 120);
    const text = String(
      body.text ??
        [
          'هذه رسالة اختبار من نظام مراقبة واتساب.',
          'إذا وصلتك هذه الرسالة فإن مسار الإيميل يعمل بشكل صحيح.',
          'النص يجب أن يظهر بالعربية بوضوح ومن اليمين إلى اليسار.',
        ].join('\n'),
    );
    // جسر Auth معطّل عمداً — لا يُلمس قالب رمز الدخول.
    const relayUrl = (Deno.env.get('OPS_MAIL_RELAY_URL') ?? '').replace(/\/$/, '');
    const relaySecret = Deno.env.get('OPS_MAIL_RELAY_SECRET') ?? '';
    if (!relayUrl || !relaySecret) {
      return Response.json({
        ok: false,
        detail: 'auth_smtp_bridge_disabled_set_OPS_MAIL_RELAY',
        to,
      });
    }
    const res = await fetch(`${relayUrl}/send`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Ops-Mail-Secret': relaySecret,
      },
      body: JSON.stringify({ to, subject, text }),
    });
    const detail = await res.text();
    return Response.json({
      ok: res.ok,
      detail: res.ok ? `relay:${to}` : detail.slice(0, 200),
      to,
    });
  }

  const sb = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: runRow } = await sb
    .from('whatsapp_ops_monitor_runs')
    .insert({ started_at: new Date().toISOString() })
    .select('id')
    .maybeSingle();
  const runId = runRow?.id as number | undefined;

  try {
    const stats = await runAnalystCycle(sb);
    const hb = await pingHealthchecks();
    if (runId != null) {
      await sb
        .from('whatsapp_ops_monitor_runs')
        .update({
          finished_at: new Date().toISOString(),
          ok: true,
          heartbeat_pinged: hb.ok,
          stats: { ...stats, heartbeat: hb },
        })
        .eq('id', runId);
    }
    return Response.json({ ok: true, ...stats, heartbeat: hb });
  } catch (e) {
    const msg = String(e).slice(0, 500);
    console.error('whatsapp-ops-analyst failed', msg);
    if (runId != null) {
      await sb
        .from('whatsapp_ops_monitor_runs')
        .update({
          finished_at: new Date().toISOString(),
          ok: false,
          error: msg,
          heartbeat_pinged: false,
        })
        .eq('id', runId);
    }
    // لا ping عند الفشل → Dead Man's Switch
    return Response.json({ ok: false, error: msg }, { status: 500 });
  }
});

async function runAnalystCycle(sb: SupabaseClient): Promise<Record<string, unknown>> {
  const now = Date.now();
  const nowIso = new Date(now).toISOString();
  const since1h = new Date(now - FLAP_WINDOW_MS).toISOString();

  // 1) استيراد حقائق من diagnostics الحديثة (عواصف audit)
  await ingestDiagnosticsIntoFacts(sb, since1h);

  // 2) بوّابات المستأجرين
  const { data: gates } = await sb
    .from('tenant_whatsapp_gateways')
    .select(
      'user_id, evolution_instance_name, status, repair_needed, disconnect_cause',
    );

  let opened = 0;
  let updated = 0;
  let resolved = 0;
  let escalated = 0;
  let enriched = 0;
  let candidatesTracked = 0;

  for (const gate of (gates ?? []) as GateRow[]) {
    const userId = gate.user_id;
    const sessionName = gate.evolution_instance_name;
    if (!userId || !sessionName) continue;

    const { data: facts } = await sb
      .from('whatsapp_ops_facts')
      .select('fact_type, code, created_at, meta')
      .eq('user_id', userId)
      .eq('session_name', sessionName)
      .gte('created_at', since1h)
      .order('created_at', { ascending: true })
      .limit(2000);

    const factRows = (facts ?? []) as Array<{
      fact_type: string;
      code: string | null;
      created_at: string;
      meta: Record<string, unknown> | null;
    }>;

    const flapCount = countFlapTransitions(factRows);
    const sendAccepted = countType(factRows, 'send_accepted');
    const deliveryAck = countType(factRows, 'delivery_ack');
    const sendFailed = countType(factRows, 'send_error');
    const auth401 = countType(factRows, 'auth_401') +
      factRows.filter((f) => f.code === '401').length;
    const code463 = factRows.filter(
      (f) => f.code === '463' || (f.fact_type === 'send_error' && f.code === '463'),
    ).length;
    const provisionStorm = countType(factRows, 'provision_storm');
    const falseAlarm = countType(factRows, 'false_alarm');
    const chain463Then401 = detect463Then401(factRows);
    const numberLock = chain463Then401 ||
      factRows.some((f) =>
        String(f.meta?.number_lock ?? '').length > 0 ||
        String(f.code ?? '').includes('timelock') ||
        String(f.code ?? '').includes('reachout')
      );

    const silentUndelivered = Math.max(0, sendAccepted - deliveryAck);

    const bucketMs = 5 * 60_000;
    const windowEndMs = Math.floor(now / bucketMs) * bucketMs;
    const windowStartIso = new Date(windowEndMs - DELIVERY_WINDOW_MS).toISOString();
    const windowEndIso = new Date(windowEndMs).toISOString();

    await sb.from('whatsapp_ops_delivery_stats').upsert({
      user_id: userId,
      session_name: sessionName,
      window_start: windowStartIso,
      window_end: windowEndIso,
      send_accepted: sendAccepted,
      delivery_ack: deliveryAck,
      send_failed: sendFailed,
      silent_undelivered: silentUndelivered,
    }, { onConflict: 'user_id,session_name,window_start,window_end' });

    const deliveryHealth =
      sendAccepted === 0
        ? 'unknown'
        : deliveryAck / sendAccepted >= 0.5
        ? 'healthy'
        : deliveryAck / sendAccepted >= 0.2
        ? 'degraded'
        : 'silent_fail';

    const conditions = classifyTenant({
      userId,
      sessionName,
      repairNeeded: gate.repair_needed === true,
      liveStatus: gate.status,
      flapCount1h: flapCount,
      auth401Count1h: auth401,
      code463Count1h: code463,
      provisionStorm1h: provisionStorm,
      falseAlarm1h: falseAlarm,
      sendAccepted1h: sendAccepted,
      deliveryAck1h: deliveryAck,
      sendFailed1h: sendFailed,
      numberLockSignal: numberLock,
      chain463Then401,
    });

    const gateResult = await applyPersistenceGate({
      sb,
      userId,
      sessionName,
      conditions,
      nowMs: now,
    });
    candidatesTracked += gateResult.tracked.length;

    for (const item of gateResult.toOpen) {
      const r = await openOrBumpIncident({
        sb,
        userId,
        sessionName,
        fingerprint: item.fingerprint,
        condition: item.condition,
        nowMs: now,
        factsDigestAr: digestFacts(factRows),
      });
      if (r === 'opened') opened += 1;
      if (r === 'bumped') updated += 1;
      if (r === 'enriched') enriched += 1;
    }

    await sb.from('whatsapp_tenant_dossier').upsert({
      user_id: userId,
      session_name: sessionName,
      live_status: gate.status,
      repair_needed: gate.repair_needed === true,
      flap_count_1h: flapCount,
      sends_accepted_24h: sendAccepted,
      delivery_acks_24h: deliveryAck,
      send_failures_24h: sendFailed,
      delivery_health: deliveryHealth,
      report_ar: buildDossierReportAr({
        status: gate.status,
        repairNeeded: gate.repair_needed === true,
        flapCount,
        sendAccepted,
        deliveryAck,
        code463,
        deliveryHealth,
      }),
      last_analyst_at: nowIso,
      updated_at: nowIso,
      meta: {
        auth401,
        provisionStorm,
        falseAlarm,
        chain463Then401,
        conditions: conditions.map((c) => c.ruleId),
      },
    }, { onConflict: 'user_id' });

    // SLA + resolve
    const sla = await tickSlaAndResolve({
      sb,
      userId,
      sessionName,
      liveStatus: gate.status,
      repairNeeded: gate.repair_needed === true,
      nowMs: now,
    });
    escalated += sla.escalated;
    resolved += sla.resolved;
  }

  // خطأ يتكرر، أو «مُرسلة» بلا معرّف، أو طابور عالق. الفشل هنا لا يوقف الدورة.
  try {
    const { data: logs } = await sb
      .from('whatsapp_message_logs')
      .select(
        'tenant_user_id, status, error, provider_message_id, order_ref, created_at',
      )
      .in('status', ['failed', 'queued', 'sent', 'delivered', 'read'])
      .gte('created_at', new Date(now - STUCK_QUEUED_LOOKBACK_MS).toISOString())
      .limit(5000);
    const byTenant = new Map<string, DeliveryLogRow[]>();
    for (const r of (logs ?? []) as DeliveryLogRow[]) {
      const list = byTenant.get(r.tenant_user_id) ?? [];
      list.push(r);
      byTenant.set(r.tenant_user_id, list);
    }
    for (const gate of (gates ?? []) as GateRow[]) {
      const rows = byTenant.get(gate.user_id);
      if (!rows || !gate.evolution_instance_name) continue;
      for (const condition of classifyDeliveryAlerts(rows, now)) {
        const fingerprint = await incidentFingerprint({
          ruleId: condition.ruleId,
          sessionName: gate.evolution_instance_name,
          patternKey: condition.patternKey,
          severity: condition.severity,
        });
        const r = await openOrBumpIncident({
          sb,
          userId: gate.user_id,
          sessionName: gate.evolution_instance_name,
          fingerprint,
          condition,
          nowMs: now,
          factsDigestAr: condition.summaryAr,
        });
        if (r === 'opened') opened += 1;
        if (r === 'bumped') updated += 1;
      }
    }
  } catch (e) {
    console.warn('delivery alerts failed', String(e).slice(0, 160));
  }

  // safe-fix عبر health-check فقط (استدعاء داخلي إن وُجد السر)
  let healthCheck: Record<string, unknown> | null = null;
  try {
    healthCheck = await invokeHealthCheckSafe();
  } catch (e) {
    healthCheck = { ok: false, error: String(e).slice(0, 120) };
  }

  return {
    tenants: (gates ?? []).length,
    opened,
    updated,
    resolved,
    escalated,
    enriched,
    candidates_tracked: candidatesTracked,
    health_check: healthCheck,
  };
}

function countType(
  rows: Array<{ fact_type: string }>,
  type: string,
): number {
  return rows.filter((r) => r.fact_type === type).length;
}

function digestFacts(
  rows: Array<{ fact_type: string; code: string | null; created_at: string }>,
): string {
  const last = rows.slice(-12);
  if (last.length === 0) return 'لا حقائق خلال الساعة.';
  return last
    .map(
      (r) =>
        `${r.created_at}: ${r.fact_type}${r.code ? `(${r.code})` : ''}`,
    )
    .join('\n');
}

function buildDossierReportAr(args: {
  status: string | null;
  repairNeeded: boolean;
  flapCount: number;
  sendAccepted: number;
  deliveryAck: number;
  code463: number;
  deliveryHealth: string;
}): string {
  const parts = [
    `الحالة: ${args.status ?? 'unknown'}`,
    args.repairNeeded ? 'يلزم إعادة ربط.' : 'لا repair_needed.',
    `تذبذب ساعة: ${args.flapCount}`,
    `إرسال مقبول/ack: ${args.sendAccepted}/${args.deliveryAck} (${args.deliveryHealth})`,
  ];
  if (args.code463 > 0) parts.push(`أخطاء 463: ${args.code463}`);
  return parts.join(' ');
}

async function ingestDiagnosticsIntoFacts(
  sb: SupabaseClient,
  sinceIso: string,
): Promise<void> {
  const { data: diags } = await sb
    .from('whatsapp_diagnostic_events')
    .select(
      'user_id, instance_name, event_type, outcome, reason_code, technical_detail, recipient_phone, created_at',
    )
    .gte('created_at', sinceIso)
    .order('created_at', { ascending: false })
    .limit(1500);

  // تجنّب إعادة إدخال نفس النافذة بالكامل: نعتمد على raw_ref = diag timestamp+type
  for (const d of diags ?? []) {
    const mapped = mapDiagRow(d as Record<string, unknown>);
    if (!mapped) continue;
    const userId = String(d.user_id ?? '');
    const session = String(d.instance_name ?? '');
    if (!userId || !session) continue;
    const rawRef = `diag:${d.created_at}:${d.event_type}:${d.outcome ?? ''}`;
    const { count } = await sb
      .from('whatsapp_ops_facts')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', userId)
      .eq('raw_ref', rawRef);
    if ((count ?? 0) > 0) continue;
    await writeOpsFact(sb, {
      userId,
      sessionName: session,
      factType: mapped.factType,
      code: mapped.code,
      phone: (d.recipient_phone as string) ?? null,
      rawRef,
      meta: { source: 'diagnostic_ingest' },
    });
  }
}

function mapDiagRow(
  d: Record<string, unknown>,
): { factType: string; code: string | null } | null {
  const et = String(d.event_type ?? '').toLowerCase();
  const outcome = String(d.outcome ?? '').toLowerCase();
  const reason = String(d.reason_code ?? '').toLowerCase();
  const detail = String(d.technical_detail ?? '').toLowerCase();
  const blob = `${outcome} ${reason} ${detail}`;

  if (et === 'send_accepted' || outcome === 'accepted' || outcome === 'send_accepted') {
    return { factType: 'send_accepted', code: null };
  }
  if (et === 'delivery_update' || outcome.includes('delivered') || outcome.includes('ack')) {
    return { factType: 'delivery_ack', code: null };
  }
  if (blob.includes('463')) return { factType: 'send_error', code: '463' };
  if (blob.includes('401') || reason.includes('401')) {
    return { factType: 'auth_401', code: '401' };
  }
  if (reason.includes('repair_needed') || outcome.includes('disconnect_permanent')) {
    return { factType: 'repair_needed', code: 'repair_needed' };
  }
  if (reason.includes('hard_reset') || et.includes('provision') || reason.includes('provision')) {
    return {
      factType: 'provision_storm',
      code: reason.includes('hard_reset') ? 'hard_reset' : 'provision',
    };
  }
  if (outcome === 'connected') return { factType: 'session_working', code: 'WORKING' };
  if (outcome.includes('disconnect') || blob.includes('failed') || blob.includes('stopped')) {
    return {
      factType: 'session_down',
      code: blob.includes('failed')
        ? 'FAILED'
        : blob.includes('stopped')
        ? 'STOPPED'
        : 'disconnected',
    };
  }
  if (blob.includes('waha_error') || reason.includes('false')) {
    return { factType: 'false_alarm', code: reason || 'waha_error' };
  }
  return null;
}

async function openOrBumpIncident(args: {
  sb: SupabaseClient;
  userId: string;
  sessionName: string;
  fingerprint: string;
  condition: ClassifiedCondition;
  nowMs: number;
  factsDigestAr: string;
}): Promise<'opened' | 'bumped' | 'enriched' | 'noop'> {
  const { data: existing } = await args.sb
    .from('whatsapp_ops_incidents')
    .select('*')
    .eq('fingerprint', args.fingerprint)
    .eq('status', 'open')
    .maybeSingle();

  const nowIso = new Date(args.nowMs).toISOString();
  const pb = PLAYBOOK[args.condition.playbookStepId];
  const reportAr = [
    args.condition.titleAr,
    args.condition.summaryAr,
    `الدليل: ${pb.title_ar} — ${pb.steps_ar.join('؛ ')}`,
  ].join('\n');

  if (existing?.id) {
    await args.sb
      .from('whatsapp_ops_incidents')
      .update({
        times_seen: Number(existing.times_seen ?? 1) + 1,
        last_seen_at: nowIso,
        stable_since: null,
      })
      .eq('id', existing.id);
    return 'bumped';
  }

  const slaDeadline =
    args.condition.severity === 'P1'
      ? new Date(args.nowMs + P1_SLA_MS).toISOString()
      : null;

  const { data: inserted, error } = await args.sb
    .from('whatsapp_ops_incidents')
    .insert({
      fingerprint: args.fingerprint,
      user_id: args.userId,
      session_name: args.sessionName,
      severity: args.condition.severity,
      pattern_key: args.condition.patternKey,
      playbook_step_id: args.condition.playbookStepId,
      rule_id: args.condition.ruleId,
      status: 'open',
      opened_at: nowIso,
      sla_deadline_at: slaDeadline,
      times_seen: 1,
      last_seen_at: nowIso,
      report_ar: reportAr,
      meta: { immediate: args.condition.immediate },
    })
    .select('id')
    .maybeSingle();

  if (error || !inserted?.id) {
    console.warn('incident insert failed', error?.message);
    return 'noop';
  }

  const incidentId = inserted.id as string;
  const alertKind =
    args.condition.patternKey === 'session_flapping' ? 'flapping' : 'open';

  await dispatchIncidentAlerts({
    sb: args.sb,
    incidentId,
    userId: args.userId,
    severity: args.condition.severity as Severity,
    alertKind,
    sessionName: args.sessionName,
    patternKey: args.condition.patternKey,
    titleAr: args.condition.titleAr,
    summaryAr: args.condition.summaryAr,
    playbookStepId: args.condition.playbookStepId,
  });

  const lessonId = await upsertLessonFromIncident({
    sb: args.sb,
    incidentId,
    patternKey: args.condition.patternKey,
    severity: args.condition.severity,
    titleAr: args.condition.titleAr,
    summaryAr: args.condition.summaryAr,
    playbookStepId: args.condition.playbookStepId,
    rootCauseAr: args.condition.summaryAr,
    resolutionAr: pb.steps_ar.join(' '),
    evalFixtureId: fixtureIdForPattern(args.condition.patternKey),
  });

  const lessons = await retrieveSimilarLessons({
    sb: args.sb,
    patternKey: args.condition.patternKey,
    severity: args.condition.severity,
  });

  const enrich = await enrichWithDeepSeek({
    severity: args.condition.severity,
    patternKey: args.condition.patternKey,
    playbookStepId: args.condition.playbookStepId,
    titleAr: args.condition.titleAr,
    summaryAr: args.condition.summaryAr,
    sessionName: args.sessionName,
    factsDigestAr: args.factsDigestAr,
    lessons,
  });

  if (!enrich.skipped && enrich.enrichmentAr) {
    await args.sb
      .from('whatsapp_ops_incidents')
      .update({
        enrichment_ar: enrich.enrichmentAr,
        enrichment_at: nowIso,
        lesson_ids: lessonId ? [lessonId] : [],
      })
      .eq('id', incidentId);
    return 'enriched';
  }

  if (lessonId) {
    await args.sb
      .from('whatsapp_ops_incidents')
      .update({ lesson_ids: [lessonId] })
      .eq('id', incidentId);
  }

  return 'opened';
}

function fixtureIdForPattern(patternKey: string): string | null {
  if (patternKey === 'number_activity_lock' || patternKey === 'waha_463_chain') {
    return 'baqir_463_to_401';
  }
  if (patternKey === 'session_flapping') return 'session_flapping_6';
  if (patternKey === 'silent_undelivered_spike') return 'persistence_silent_fail';
  return null;
}

async function tickSlaAndResolve(args: {
  sb: SupabaseClient;
  userId: string;
  sessionName: string;
  liveStatus: string | null;
  repairNeeded: boolean;
  nowMs: number;
}): Promise<{ escalated: number; resolved: number }> {
  let escalated = 0;
  let resolved = 0;
  const nowIso = new Date(args.nowMs).toISOString();

  const { data: openIncidents } = await args.sb
    .from('whatsapp_ops_incidents')
    .select('*')
    .eq('user_id', args.userId)
    .eq('session_name', args.sessionName)
    .eq('status', 'open');

  const healthy =
    !args.repairNeeded &&
    (args.liveStatus === 'connected' ||
      String(args.liveStatus).toUpperCase() === 'WORKING');

  for (const inc of openIncidents ?? []) {
    // تصعيد SLA لـ P1 مرة واحدة
    if (
      inc.severity === 'P1' &&
      !inc.escalated_at &&
      inc.sla_deadline_at &&
      new Date(inc.sla_deadline_at as string).getTime() <= args.nowMs
    ) {
      await args.sb
        .from('whatsapp_ops_incidents')
        .update({ escalated_at: nowIso })
        .eq('id', inc.id);
      await dispatchIncidentAlerts({
        sb: args.sb,
        incidentId: inc.id as string,
        userId: args.userId,
        severity: 'P1',
        alertKind: 'escalate',
        sessionName: args.sessionName,
        patternKey: String(inc.pattern_key),
        titleAr: 'تصعيد SLA — حادث واتساب P1',
        summaryAr: String(inc.report_ar ?? inc.pattern_key).slice(0, 300),
        playbookStepId: String(inc.playbook_step_id),
        forceDualChannel: true,
      });
      escalated += 1;
    }

    if (healthy) {
      const stableSince = inc.stable_since
        ? new Date(inc.stable_since as string).getTime()
        : null;
      if (!stableSince) {
        await args.sb
          .from('whatsapp_ops_incidents')
          .update({ stable_since: nowIso })
          .eq('id', inc.id);
        continue;
      }
      if (args.nowMs - stableSince >= RESOLVE_STABLE_MS) {
        await args.sb
          .from('whatsapp_ops_incidents')
          .update({
            status: 'resolved',
            resolved_at: nowIso,
            last_seen_at: nowIso,
          })
          .eq('id', inc.id);
        await dispatchIncidentAlerts({
          sb: args.sb,
          incidentId: inc.id as string,
          userId: args.userId,
          severity: inc.severity as Severity,
          alertKind: 'resolved',
          sessionName: args.sessionName,
          patternKey: String(inc.pattern_key),
          titleAr: 'إغلاق حادث واتساب بعد استقرار',
          summaryAr: `استقرار ${RESOLVE_STABLE_MS / 60000} دقيقة دون فشل حرج.`,
          playbookStepId: String(inc.playbook_step_id),
        });
        resolved += 1;
      }
    } else if (inc.stable_since) {
      await args.sb
        .from('whatsapp_ops_incidents')
        .update({ stable_since: null })
        .eq('id', inc.id);
    }
  }

  return { escalated, resolved };
}

async function invokeHealthCheckSafe(): Promise<Record<string, unknown>> {
  const base = Deno.env.get('SUPABASE_URL') ?? '';
  const cronSecret = Deno.env.get('CRON_SECRET') ?? '';
  if (!base) return { skipped: true, reason: 'missing_url' };
  if (!cronSecret) return { skipped: true, reason: 'CRON_SECRET missing' };

  const res = await fetch(`${base}/functions/v1/whatsapp-health-check`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${cronSecret}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ source: 'whatsapp-ops-analyst' }),
  });
  const text = await res.text();
  try {
    return { status: res.status, body: JSON.parse(text) };
  } catch {
    return { status: res.status, body: text.slice(0, 200) };
  }
}
