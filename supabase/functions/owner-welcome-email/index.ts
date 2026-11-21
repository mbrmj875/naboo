/**
 * ترحيب صاحب الحساب مرة واحدة بعد اكتمال فتح الحساب.
 * يستدعيه التطبيق فقط من verifyOtpAndRegister و completeGoogleOwnerProfile.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { welcomeEmailCopy } from '../whatsapp-events/owner_email_copy.ts';
import { deliverOwnerCard } from '../whatsapp-events/owner_email_notify.ts';

function corsHeaders(req: Request): HeadersInit {
  const origin = req.headers.get('Origin') ?? '*';
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders(req) });
  }
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405, headers: corsHeaders(req) });
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) {
    return Response.json({ ok: false, error: 'unauthorized' }, {
      status: 401,
      headers: corsHeaders(req),
    });
  }

  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!url || !anon || !serviceKey) {
    return Response.json({ ok: false, error: 'server_misconfigured' }, {
      status: 500,
      headers: corsHeaders(req),
    });
  }

  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  const user = userData?.user;
  if (userErr || !user) {
    return Response.json({ ok: false, error: 'unauthorized' }, {
      status: 401,
      headers: corsHeaders(req),
    });
  }

  let channel: 'email' | 'google' = 'email';
  try {
    const body = await req.json() as { channel?: string };
    if (body.channel === 'google') channel = 'google';
    else if (body.channel === 'email') channel = 'email';
    else {
      return Response.json({ ok: false, error: 'bad_channel' }, {
        status: 400,
        headers: corsHeaders(req),
      });
    }
  } catch {
    return Response.json({ ok: false, error: 'invalid_json' }, {
      status: 400,
      headers: corsHeaders(req),
    });
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const email = String(user.email ?? '').trim().toLowerCase();
  const meta = (user.user_metadata ?? {}) as Record<string, unknown>;
  const displayName = String(meta.full_name ?? meta.name ?? '').trim();

  const { data: profile } = await admin
    .from('profiles')
    .select('welcome_email_sent_at')
    .eq('id', user.id)
    .maybeSingle();
  if (profile?.welcome_email_sent_at) {
    return Response.json({ ok: true, skipped: 'already_sent' }, {
      headers: corsHeaders(req),
    });
  }

  const now = new Date().toISOString();
  let claimed = false;
  if (profile) {
    const { data: updated } = await admin
      .from('profiles')
      .update({ welcome_email_sent_at: now })
      .eq('id', user.id)
      .is('welcome_email_sent_at', null)
      .select('id');
    claimed = (updated?.length ?? 0) > 0;
  } else {
    const { error } = await admin.from('profiles').insert({
      id: user.id,
      email: email || null,
      welcome_email_sent_at: now,
    });
    claimed = !error;
  }
  if (!claimed) {
    return Response.json({ ok: true, skipped: 'already_sent' }, {
      headers: corsHeaders(req),
    });
  }

  let recreated = false;
  let previousTrial: string | null = null;
  if (email) {
    const { data: trace } = await admin
      .from('account_deletion_traces')
      .select('previous_trial_started_at, deleted_at')
      .eq('email', email)
      .order('deleted_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (trace) {
      recreated = true;
      previousTrial = trace.previous_trial_started_at
        ? String(trace.previous_trial_started_at)
        : null;
    }
  }

  const built = welcomeEmailCopy({
    channel,
    displayName,
    recreated,
    previousTrialStartedAt: previousTrial,
  });
  const sent = await deliverOwnerCard(admin, {
    userId: user.id,
    instanceName: 'welcome',
    reasonCode: recreated ? 'welcome:recreated' : `welcome:${channel}`,
    subject: built.subject,
    text: built.text,
    html: built.html,
    mode: 'always',
  });
  if (!sent.sent) {
    await admin
      .from('profiles')
      .update({ welcome_email_sent_at: null })
      .eq('id', user.id);
    return Response.json({ ok: true, sent: false, detail: sent.detail }, {
      headers: corsHeaders(req),
    });
  }
  return Response.json({ ok: true, sent: true }, { headers: corsHeaders(req) });
});
