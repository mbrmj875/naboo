/**
 * التحقق من رمز PIN المالك على السيرفر.
 *
 * يأخذ { pin } مع جلسة المالك (JWT)، ويقارنه بالـ hash المحفوظ في
 * owner_auth_secrets دون أن يُرسل الـ hash إلى الجهاز. خمس محاولات خاطئة
 * تقفل الحساب 15 دقيقة، ويتضاعف القفل حتى 12 ساعة. تعيين PIN جديد يفكّه.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { type PinStore, verifyOwnerPin } from './verify.ts';

const CORS: HeadersInit = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ ok: false, reason: 'method' }, 405);

  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json({ ok: false, reason: 'unauthorized' }, 401);
  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  const userId = userData?.user?.id;
  if (userErr || !userId) return json({ ok: false, reason: 'unauthorized' }, 401);

  let body: { pin?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, reason: 'bad_pin' }, 400);
  }

  const db = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const store: PinStore = {
    async begin(uid) {
      const { data, error } = await db.rpc('owner_pin_attempt_begin', { p_user_id: uid });
      if (error) throw error;
      return data as { allowed: boolean; locked_until: string | null; remaining: number };
    },
    async success(uid) {
      const { error } = await db.rpc('owner_pin_attempt_success', { p_user_id: uid });
      if (error) throw error;
    },
    async secret(uid) {
      const { data, error } = await db
        .from('owner_auth_secrets')
        .select('phone, pin_hash, pin_salt')
        .eq('user_id', uid)
        .maybeSingle();
      if (error) throw error;
      return data;
    },
  };

  try {
    const r = await verifyOwnerPin(store, userId, body.pin);
    return json(r.body, r.status);
  } catch (e) {
    console.error('owner-pin-verify', e instanceof Error ? e.message : String(e));
    return json({ ok: false, reason: 'server_error' }, 500);
  }
});
