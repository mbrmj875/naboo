import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import type { PushAlertCandidate } from './types.ts';

const COOLDOWN_HOURS = 6;

/** يفلتر التنبيهات المُرسلة مؤخراً بنفس العدد — يقلّل fatigue. */
export async function filterWithCooldown(
  admin: SupabaseClient,
  userId: string,
  localTenantId: number,
  candidates: PushAlertCandidate[],
): Promise<PushAlertCandidate[]> {
  if (!candidates.length) return [];

  const { data: rows } = await admin
    .from('owner_push_alert_log')
    .select('alert_id, metric_count, sent_at')
    .eq('user_id', userId)
    .eq('local_tenant_id', localTenantId);

  const log = new Map<string, { metricCount: number; sentAt: number }>();
  for (const r of rows ?? []) {
    log.set(String(r.alert_id), {
      metricCount: Number(r.metric_count ?? 0),
      sentAt: Date.parse(String(r.sent_at ?? '')),
    });
  }

  const cutoff = Date.now() - COOLDOWN_HOURS * 3600 * 1000;
  const fresh: PushAlertCandidate[] = [];

  for (const c of candidates) {
    const prev = log.get(c.alertId);
    if (!prev) {
      fresh.push(c);
      continue;
    }
    if (c.metricCount !== prev.metricCount) {
      fresh.push(c);
      continue;
    }
    if (!Number.isFinite(prev.sentAt) || prev.sentAt < cutoff) {
      fresh.push(c);
    }
  }
  return fresh;
}

export async function recordSentAlerts(
  admin: SupabaseClient,
  userId: string,
  localTenantId: number,
  alerts: PushAlertCandidate[],
): Promise<void> {
  if (!alerts.length) return;
  const now = new Date().toISOString();
  const rows = alerts.map((a) => ({
    user_id: userId,
    local_tenant_id: localTenantId,
    alert_id: a.alertId,
    metric_count: a.metricCount,
    sent_at: now,
  }));
  await admin.from('owner_push_alert_log').upsert(rows, {
    onConflict: 'user_id,local_tenant_id,alert_id',
  });
}
