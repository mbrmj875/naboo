// notify-daily-summary — الملخص اليومي (خطة الإشعارات، المرحلة 4).
//
// تستدعيها المهمة notify-daily-summary كل 15 دقيقة، فقط حين يحين ملخص حساب
// (notify_summary_due_accounts). تقرأ نسخة بيانات ذلك الحساب وحده مرة في اليوم،
// وتكتب صفا في notifications، وnotify-dispatch يرسله.
//
// Deploy: supabase functions deploy notify-daily-summary --no-verify-jwt
// Secrets: CRON_SECRET، PUSH_ALLOWED_USER_IDS.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { pushAllowedForUser } from '../owner-alert-push-cron/fcm.ts';
import { loadSnapshotTables } from '../owner-alert-push-cron/snapshot_loader.ts';
import { computeDailySummary, summaryText } from './summary.ts';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 });
  const cronSecret = (Deno.env.get('CRON_SECRET') ?? '').trim();
  if (!cronSecret || req.headers.get('Authorization') !== `Bearer ${cronSecret}`) {
    return new Response('Unauthorized', { status: 401 });
  }

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: due, error } = await admin.rpc('notify_summary_due_accounts');
  if (error) return Response.json({ ok: false, error: error.message }, { status: 500 });

  const now = new Date();
  const done: string[] = [];
  const skipped: string[] = [];
  const snapshots = new Map<string, Awaited<ReturnType<typeof loadSnapshotTables>>>();

  for (const acc of (due ?? []) as { user_id: string; local_tenant_id: number }[]) {
    if (!pushAllowedForUser(acc.user_id)) {
      skipped.push(`${acc.user_id}:gated`);
      continue;
    }
    if (!snapshots.has(acc.user_id)) {
      snapshots.set(acc.user_id, await loadSnapshotTables(admin, acc.user_id));
    }
    const tables = snapshots.get(acc.user_id);
    if (!tables) {
      skipped.push(`${acc.user_id}:no_snapshot`);
      continue;
    }
    const s = computeDailySummary(tables, acc.local_tenant_id, now);
    const text = summaryText(s);
    const { error: wErr } = await admin.rpc('notify_write_summary', {
      p_user_id: acc.user_id,
      p_tenant: acc.local_tenant_id,
      p_ymd: s.ymd,
      p_title: text.title,
      p_body: text.body,
      p_details: s,
      p_has_activity: s.hasActivity,
    });
    if (wErr) {
      console.error('notify_write_summary', acc.user_id, wErr.message);
      skipped.push(`${acc.user_id}:write_failed`);
      continue;
    }
    done.push(`${acc.user_id}:${acc.local_tenant_id}:${s.hasActivity ? 'sent' : 'no_activity'}`);
  }

  return Response.json({ ok: true, done, skipped });
});
