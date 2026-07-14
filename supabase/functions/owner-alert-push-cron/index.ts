// Owner Command Center v3.3 — cron Push (FCM)
//
// Deploy:
//   supabase functions deploy owner-alert-push-cron --no-verify-jwt
//
// Schedule (pg_cron or Dashboard): */15 * * * *
//
// Secrets:
//   FCM_SERVICE_ACCOUNT_JSON
//   CRON_SECRET (optional Bearer guard)
//   SUPABASE_SERVICE_ROLE_KEY (auto in Edge runtime)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { filterWithCooldown, recordSentAlerts } from './cooldown.ts';
import { evaluateAlertsFromSnapshot } from './evaluate_alerts.ts';
import { sendFcmDataMessage } from './fcm.ts';
import { loadSnapshotTables } from './snapshot_loader.ts';
import type { OwnerAlertPrefs, OwnerFcmToken } from './types.ts';

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  const cronSecret = Deno.env.get('CRON_SECRET');
  const authHeader = req.headers.get('Authorization') ?? '';
  if (cronSecret && authHeader !== `Bearer ${cronSecret}`) {
    return new Response('Unauthorized', { status: 401 });
  }

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
    const pushIds = Array.isArray(prefs.push_alert_ids)
      ? prefs.push_alert_ids.map(String)
      : [];
    if (pushIds.length === 0) {
      skipped.push(`${prefs.user_id}:${prefs.local_tenant_id}:no_push_ids`);
      continue;
    }

    const { data: tokens } = await admin
      .from('owner_fcm_tokens')
      .select('token, platform')
      .eq('user_id', prefs.user_id)
      .eq('local_tenant_id', prefs.local_tenant_id);

    if (!tokens?.length) {
      skipped.push(`${prefs.user_id}:${prefs.local_tenant_id}:no_tokens`);
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

    const delivered: PushAlertCandidate[] = [];
    for (const alert of toSend) {
      for (const row of tokens as OwnerFcmToken[]) {
        const ok = await sendFcmDataMessage(row.token, alert);
        if (ok) {
          sent.push(`${alert.alertId}→${row.platform}`);
          if (!delivered.some((d) => d.alertId === alert.alertId)) {
            delivered.push(alert);
          }
        }
      }
    }

    if (delivered.length) {
      await recordSentAlerts(
        admin,
        prefs.user_id,
        prefs.local_tenant_id,
        delivered,
      );
    }
  }

  return Response.json({ ok: true, sent, skipped });
});
