/**
 * طلب اعتماد اسم العرض Naboo على رقم المرسِل المشترك + تحديث ملف الأعمال.
 * يُستدعى مرة واحدة من الإدارة — ليس من التطبيق.
 *
 * بعد APPROVED من Meta يلزم إعادة تسجيل الرقم (register + PIN) لتفعيل الاسم.
 */

import { sharedSenderConfig } from '../whatsapp-gateway/shared_sender.ts';

const GRAPH = 'https://graph.facebook.com/v21.0';
const TARGET_NAME = 'Naboo';

function cloudToken(): string | null {
  return Deno.env.get('WHATSAPP_CLOUD_TOKEN')?.trim() || null;
}

function opsAuthorized(req: Request): boolean {
  const got = req.headers.get('x-ops-token')?.trim() ||
    req.headers.get('authorization')?.replace(/^Bearer\s+/i, '').trim() ||
    new URL(req.url).searchParams.get('token')?.trim() ||
    '';

  const setup = Deno.env.get('DISPLAY_NAME_SETUP_TOKEN')?.trim();
  if (setup && got && got === setup) return true;

  const expected = Deno.env.get('OPS_MGMT_TOKEN')?.trim();
  if (expected && got && got === expected) return true;

  const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?.trim();
  if (serviceRole && got && got === serviceRole) return true;
  return false;
}

async function graphGet(
  path: string,
  token: string,
): Promise<{ ok: boolean; data: Record<string, unknown>; detail?: string }> {
  const res = await fetch(`${GRAPH}/${path}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const data = await res.json().catch(() => ({})) as Record<string, unknown>;
  if (!res.ok) {
    const err = data.error as Record<string, unknown> | undefined;
    return {
      ok: false,
      data,
      detail: String(err?.message ?? JSON.stringify(data)).slice(0, 400),
    };
  }
  return { ok: true, data };
}

async function graphPostQuery(
  pathAndQuery: string,
  token: string,
  body?: Record<string, unknown>,
): Promise<{ ok: boolean; data: Record<string, unknown>; detail?: string }> {
  const res = await fetch(`${GRAPH}/${pathAndQuery}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => ({})) as Record<string, unknown>;
  if (!res.ok) {
    const err = data.error as Record<string, unknown> | undefined;
    return {
      ok: false,
      data,
      detail: String(err?.message ?? JSON.stringify(data)).slice(0, 400),
    };
  }
  return { ok: true, data };
}

Deno.serve(async (req) => {
  if (req.method === 'GET') {
    return Response.json({ ok: true, service: 'whatsapp-set-display-name' });
  }
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }
  if (!opsAuthorized(req)) {
    return Response.json({ ok: false, error: 'unauthorized' }, { status: 401 });
  }

  const token = cloudToken();
  const shared = sharedSenderConfig();
  if (!token) {
    return Response.json({ ok: false, error: 'WHATSAPP_CLOUD_TOKEN missing' }, {
      status: 500,
    });
  }
  if (!shared?.phoneNumberId) {
    return Response.json({
      ok: false,
      error: 'SHARED_SENDER_PHONE_NUMBER_ID missing',
    }, { status: 500 });
  }

  const phoneId = shared.phoneNumberId;
  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const displayName = String(body.display_name ?? TARGET_NAME).trim() ||
    TARGET_NAME;
  const doRegister = body.register === true;
  const pin = String(body.pin ?? Deno.env.get('WHATSAPP_CLOUD_PIN') ?? '')
    .trim();

  const before = await graphGet(
    `${phoneId}?fields=verified_name,name_status,new_display_name,new_name_status,display_phone_number`,
    token,
  );

  const requestName = await graphPostQuery(
    `${phoneId}?new_display_name=${encodeURIComponent(displayName)}`,
    token,
  );

  const profile = await graphPostQuery(
    `${phoneId}/whatsapp_business_profile`,
    token,
    {
      messaging_product: 'whatsapp',
      about: 'Naboo — نظام إدارة المحلات والخدمات',
      description:
        'Naboo ERP — بطاقات الخدمة والرد الذكي لعملاء المحل عبر واتساب.',
      vertical: 'OTHER',
    },
  );

  const after = await graphGet(
    `${phoneId}?fields=verified_name,name_status,new_display_name,new_name_status,display_phone_number`,
    token,
  );

  let registerResult: Record<string, unknown> | null = null;
  if (doRegister && pin.length === 6) {
    const reg = await graphPostQuery(`${phoneId}/register`, token, {
      messaging_product: 'whatsapp',
      pin,
    });
    registerResult = { ok: reg.ok, detail: reg.detail, data: reg.data };
  }

  return Response.json({
    ok: requestName.ok,
    target_display_name: displayName,
    phone_number_id: phoneId,
    before: before.ok ? before.data : { error: before.detail },
    request_display_name: requestName.ok
      ? requestName.data
      : { error: requestName.detail },
    business_profile: profile.ok ? profile.data : { error: profile.detail },
    after: after.ok ? after.data : { error: after.detail },
    register: registerResult,
    next_steps_ar: [
      'انتظر اعتماد Meta لاسم العرض (new_name_status → APPROVED).',
      'بعد الاعتماد أعد استدعاء هذه الدالة مع {"register":true,"pin":"XXXXXX"} أو سجّل الرقم من WhatsApp Manager.',
      'إن حفظ الزبون الرقم باسم آخر على جهازه، سيظهر اسمه المحفوظ عنده لا اسم Naboo.',
    ],
  });
});
