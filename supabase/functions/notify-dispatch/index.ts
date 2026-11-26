// notify-dispatch — دالة الإرسال الواحدة (خطة الإشعارات، المرحلة 1، البند 2).
//
// تستدعيها قاعدة البيانات عند إدراج صف في notifications حان موعده
// (trg_notifications_kick_dispatch، الجسم {"ids":[...]})، والمهمة المجدولة
// لما تأجل أو فشل أو دُمج (الجسم {}).
//
// Deploy: supabase functions deploy notify-dispatch --no-verify-jwt
// Secrets: CRON_SECRET، PUSH_FCM_SERVICE_ACCOUNT_JSON، PUSH_ALLOWED_USER_IDS (فارغ = لا إرسال).

import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { getGoogleAccessToken, pushAllowedForUser } from '../owner-alert-push-cron/fcm.ts';
import {
  buildSendUnits,
  channelFor,
  DEFAULT_PREFS,
  gate,
  HOURLY_LIMIT,
  lockScreenText,
  MAX_ATTEMPTS,
  type NotificationRow,
  type Prefs,
  type PushDevice,
  retryAt,
  selectRecipients,
  type SendUnit,
} from './decide.ts';

const BATCH = 200;

type Account = { hasOwnerPhone: boolean; prefs: Prefs; devices: PushDevice[]; sentLastHour: number };

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 });

  const cronSecret = (Deno.env.get('CRON_SECRET') ?? '').trim();
  if (!cronSecret || req.headers.get('Authorization') !== `Bearer ${cronSecret}`) {
    return new Response('Unauthorized', { status: 401 });
  }

  let ids: number[] | null = null;
  try {
    const body = await req.json();
    if (Array.isArray(body?.ids)) ids = body.ids.map(Number).filter(Number.isFinite);
  } catch {
    // جسم فارغ: دورة المهمة المجدولة
  }

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  const now = new Date();

  let q = admin
    .from('notifications')
    .select(
      'id, user_id, local_tenant_id, category, type, priority, title_ar, body_ar, route, entity_id, audience, source_device_id, attempts',
    )
    .lte('deliver_after', now.toISOString())
    .order('id', { ascending: true })
    .limit(BATCH);
  q = ids?.length
    ? q.in('id', ids).eq('status', 'pending')
    : q.in('status', ['pending', 'quiet_deferred', 'failed']).lt('attempts', MAX_ATTEMPTS);

  const { data: rows, error } = await q;
  if (error) return Response.json({ ok: false, error: error.message }, { status: 500 });

  const summary: Record<string, number> = {};
  const bump = (k: string, n = 1) => (summary[k] = (summary[k] ?? 0) + n);
  const ctx = new AccountCache(admin);

  // 1) قرار كل صف وحده: مفتاح التشغيل، الحجب، الإطفاء، الهدوء.
  const ready = new Map<string, NotificationRow[]>();
  for (const row of (rows ?? []) as NotificationRow[]) {
    if (!pushAllowedForUser(row.user_id)) {
      await setStatus(admin, [row.id], { status: 'gated' });
      bump('gated');
      continue;
    }
    const acct = await ctx.get(row.user_id, row.local_tenant_id);
    const g = gate(row, acct.hasOwnerPhone, acct.prefs, now);
    if (g.kind === 'quiet_deferred') {
      await setStatus(admin, [row.id], { status: 'quiet_deferred', deliver_after: g.until.toISOString() });
      bump(g.kind);
      continue;
    }
    if (g.kind !== 'send') {
      await setStatus(admin, [row.id], { status: g.kind });
      bump(g.kind);
      continue;
    }
    const k = `${row.user_id}:${row.local_tenant_id}`;
    ready.set(k, [...(ready.get(k) ?? []), row]);
  }

  // 2) الدمج ثم الإرسال، وحدة بوحدة.
  let accessToken: { token: string; projectId: string } | null | undefined;
  for (const [key, accountRows] of ready) {
    const [userId, tenant] = key.split(':');
    const acct = await ctx.get(userId, Number(tenant));
    for (const unit of buildSendUnits(accountRows)) {
      const unitIds = unit.rows.map((r) => r.id);
      if (acct.sentLastHour >= HOURLY_LIMIT) {
        await setStatus(admin, unitIds, { status: 'rate_limited' });
        bump('rate_limited', unitIds.length);
        continue;
      }
      const targets = selectRecipients(
        { ...unit.lead, source_device_id: unit.sourceDeviceId },
        acct.devices,
      );
      if (!targets.length) {
        await setStatus(admin, unitIds, { status: 'no_devices' });
        bump('no_devices', unitIds.length);
        continue;
      }

      if (accessToken === undefined) accessToken = await loadAccessToken();
      if (!accessToken) {
        await markFailed(admin, unit, now);
        bump('no_fcm_key', unitIds.length);
        continue;
      }

      const text = lockScreenText(
        { category: unit.lead.category, title_ar: unit.title, body_ar: unit.body },
        acct.prefs,
        acct.hasOwnerPhone,
      );
      let sent = 0;
      for (const d of targets) {
        const res = await sendOne(accessToken, d, unit, text);
        if (res === 'ok') sent++;
        if (res === 'invalid') {
          await admin
            .from('push_devices')
            .update({ invalid_at: now.toISOString(), enabled: false })
            .eq('user_id', userId)
            .eq('device_id', d.device_id);
        }
      }

      if (sent > 0) {
        acct.sentLastHour++;
        await setStatus(admin, unitIds, { status: 'sent', sent_count: sent, sent_at: now.toISOString() });
        bump('sent', unitIds.length);
        if (unitIds.length > 1) bump('merged', unitIds.length - 1);
      } else {
        await markFailed(admin, unit, now);
        bump('failed', unitIds.length);
      }
    }
  }

  return Response.json({ ok: true, processed: rows?.length ?? 0, ...summary });
});

async function setStatus(admin: SupabaseClient, ids: number[], patch: Record<string, unknown>) {
  if (!ids.length) return;
  await admin.from('notifications').update(patch).in('id', ids);
}

async function markFailed(admin: SupabaseClient, unit: SendUnit, now: Date) {
  for (const r of unit.rows) {
    await setStatus(admin, [r.id], {
      status: 'failed',
      attempts: r.attempts + 1,
      deliver_after: retryAt(now, r.attempts).toISOString(),
    });
  }
}

class AccountCache {
  private cache = new Map<string, Account>();
  constructor(private admin: SupabaseClient) {}

  async get(userId: string, tenantId: number): Promise<Account> {
    const key = `${userId}:${tenantId}`;
    const hit = this.cache.get(key);
    if (hit) return hit;

    const [devs, flags, prefs, recent] = await Promise.all([
      this.admin
        .from('push_devices')
        .select('device_id, fcm_token, platform, role_key, permission_keys')
        .eq('user_id', userId)
        .eq('enabled', true)
        .is('invalid_at', null),
      this.admin
        .from('account_devices')
        .select('device_id, owner_notify, access_status')
        .eq('user_id', userId),
      this.admin
        .from('notification_preferences')
        .select('disabled_types, quiet_start, quiet_end, hide_lock_details')
        .eq('user_id', userId)
        .eq('local_tenant_id', tenantId)
        .maybeSingle(),
      this.admin
        .from('notifications')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', userId)
        .eq('status', 'sent')
        .gte('sent_at', new Date(Date.now() - 3600_000).toISOString()),
    ]);

    const active = new Map<string, boolean>();
    for (const r of flags.data ?? []) {
      if (String(r.access_status ?? 'active').toLowerCase() === 'active') {
        active.set(String(r.device_id), r.owner_notify === true);
      }
    }
    const devices: PushDevice[] = [];
    for (const d of devs.data ?? []) {
      // الجهاز المفصول أو المحذوف من account_devices لا يستلم.
      if (!active.has(String(d.device_id))) continue;
      devices.push({ ...(d as Omit<PushDevice, 'owner_notify'>), owner_notify: active.get(String(d.device_id))! });
    }

    const value: Account = {
      hasOwnerPhone: [...active.values()].some(Boolean),
      prefs: { ...DEFAULT_PREFS, ...(prefs.data ?? {}) } as Prefs,
      devices,
      sentLastHour: recent.count ?? 0,
    };
    this.cache.set(key, value);
    return value;
  }
}

async function loadAccessToken(): Promise<{ token: string; projectId: string } | null> {
  const raw = Deno.env.get('PUSH_FCM_SERVICE_ACCOUNT_JSON');
  if (!raw) {
    console.warn('PUSH_FCM_SERVICE_ACCOUNT_JSON missing');
    return null;
  }
  try {
    const sa = JSON.parse(raw);
    return { token: await getGoogleAccessToken(sa), projectId: sa.project_id };
  } catch (e) {
    console.error('google access token failed', e);
    return null;
  }
}

async function sendOne(
  auth: { token: string; projectId: string },
  device: PushDevice,
  unit: SendUnit,
  text: { title: string; body: string },
): Promise<'ok' | 'invalid' | 'error'> {
  const row = unit.lead;
  const message = {
    token: device.fcm_token,
    notification: { title: text.title, body: text.body },
    data: {
      notification_id: String(row.id),
      notification_ids: unit.rows.map((r) => r.id).join(','),
      tenant_id: String(row.local_tenant_id),
      category: row.category,
      priority: unit.priority,
      type: row.type,
      route: unit.route ?? '',
      entity_id: unit.entityId ?? '',
      title_ar: text.title,
      body_ar: text.body,
    },
    android: {
      priority: unit.priority === 'low' ? 'NORMAL' : 'HIGH',
      notification: { channel_id: channelFor(row.category, unit.priority), tag: `n${row.id}` },
    },
    apns: {
      headers: { 'apns-priority': unit.priority === 'low' ? '5' : '10' },
      payload: { aps: { sound: 'default' } },
    },
  };
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${auth.projectId}/messages:send`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${auth.token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ message }),
    },
  );
  if (res.ok) return 'ok';
  const t = await res.text();
  console.error('FCM send failed', row.id, res.status, t.slice(0, 300));
  return res.status === 404 || t.includes('UNREGISTERED') ? 'invalid' : 'error';
}
