/**
 * Ops-only: list WABA phones, register a number on Cloud API, bind to one tenant.
 *
 * Auth (any one):
 * - Bearer / x-ops-token = PHONE_REGISTER_OPS_TOKEN (temporary; unset after use)
 * - Bearer / x-ops-token = OPS_MGMT_TOKEN
 * - Bearer = SUPABASE_SERVICE_ROLE_KEY (Edge runtime value)
 *
 * Actions:
 * - list: { "action":"list", "waba_id"? }
 * - register: { "action":"register", "phone_e164"|phone_number_id, "pin":"XXXXXX",
 *               "bind"?:true, "tenant_user_id"?:uuid, "waba_id"? }
 * - bind: { "action":"bind", "tenant_user_id", "phone_number_id"|phone_e164,
 *           "waba_id"? }  — DB only when Meta register already succeeded
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

const GRAPH = 'https://graph.facebook.com/v21.0';

function opsAuthorized(req: Request): boolean {
  const got = req.headers.get('x-ops-token')?.trim() ||
    req.headers.get('authorization')?.replace(/^Bearer\s+/i, '').trim() ||
    '';
  const phoneOps = Deno.env.get('PHONE_REGISTER_OPS_TOKEN')?.trim();
  if (phoneOps && got && got === phoneOps) return true;
  const expected = Deno.env.get('OPS_MGMT_TOKEN')?.trim();
  if (expected && got && got === expected) return true;
  const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?.trim();
  if (serviceRole && got && got === serviceRole) return true;
  return false;
}

function digits(raw: string): string {
  return String(raw || '').replace(/\D/g, '');
}

function phoneMatch(display: string, want: string): boolean {
  const a = digits(display);
  const b = digits(want);
  if (!a || !b) return false;
  return a === b || a.endsWith(b) || b.endsWith(a);
}

function toE164(displayPhone: string): string {
  return displayPhone.startsWith('+')
    ? displayPhone
    : `+${digits(displayPhone)}`;
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
      detail: String(err?.message ?? JSON.stringify(data)).slice(0, 500),
    };
  }
  return { ok: true, data };
}

async function graphPost(
  path: string,
  token: string,
  body: Record<string, unknown>,
): Promise<{ ok: boolean; data: Record<string, unknown>; detail?: string }> {
  const res = await fetch(`${GRAPH}/${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({})) as Record<string, unknown>;
  if (!res.ok) {
    const err = data.error as Record<string, unknown> | undefined;
    return {
      ok: false,
      data,
      detail: String(err?.message ?? JSON.stringify(data)).slice(0, 500),
    };
  }
  return { ok: true, data };
}

async function resolvePhoneOnWaba(args: {
  token: string;
  wabaId: string;
  wantPhone: string;
}): Promise<
  | { ok: true; phoneNumberId: string; displayPhone: string }
  | { ok: false; detail?: string; phones?: unknown[]; data?: unknown }
> {
  const listed = await graphGet(
    `${args.wabaId}/phone_numbers?fields=id,display_phone_number,verified_name,code_verification_status`,
    args.token,
  );
  if (!listed.ok) {
    return { ok: false, detail: listed.detail, data: listed.data };
  }
  const rows =
    (listed.data.data as Array<Record<string, unknown>> | undefined) ?? [];
  const hit = rows.find((r) =>
    phoneMatch(String(r.display_phone_number ?? ''), args.wantPhone)
  );
  if (!hit) {
    return {
      ok: false,
      detail: 'phone_not_found_on_waba',
      phones: rows.map((r) => ({
        id: r.id,
        display_phone_number: r.display_phone_number,
        verified_name: r.verified_name,
        code_verification_status: r.code_verification_status,
      })),
    };
  }
  return {
    ok: true,
    phoneNumberId: String(hit.id ?? '').trim(),
    displayPhone: String(hit.display_phone_number ?? args.wantPhone).trim(),
  };
}

async function bindTenantDedicatedNumber(args: {
  tenantUserId: string;
  phoneNumberId: string;
  displayPhone: string;
  wabaId: string;
}): Promise<{ ok: boolean; error?: string; phone?: string }> {
  const url = Deno.env.get('SUPABASE_URL')?.trim();
  const sr = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?.trim();
  if (!url || !sr) return { ok: false, error: 'supabase_env_missing' };

  const db = createClient(url, sr, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const now = new Date().toISOString();
  const e164 = toE164(args.displayPhone);
  const { error } = await db.from('tenant_whatsapp_gateways').upsert(
    {
      user_id: args.tenantUserId,
      evolution_instance_name:
        `shop_${args.tenantUserId.replace(/-/g, '_')}`,
      whatsapp_provider: 'cloud_api',
      status: 'connected',
      cloud_setup_status: 'ready',
      repair_needed: false,
      disconnect_cause: null,
      cloud_waba_id: args.wabaId ||
        Deno.env.get('SHARED_SENDER_WABA_ID') ||
        null,
      cloud_phone_number_id: args.phoneNumberId,
      whatsapp_phone: e164,
      ycloud_from_phone: e164,
      last_connected_at: now,
      updated_at: now,
    },
    { onConflict: 'user_id' },
  );
  if (error) return { ok: false, error: error.message };
  return { ok: true, phone: e164 };
}

Deno.serve(async (req) => {
  if (req.method === 'GET') {
    return Response.json({ ok: true, service: 'whatsapp-ops-phone-register' });
  }
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }
  if (!opsAuthorized(req)) {
    return Response.json({ ok: false, error: 'unauthorized' }, { status: 401 });
  }

  const token = Deno.env.get('WHATSAPP_CLOUD_TOKEN')?.trim();
  if (!token) {
    return Response.json({ ok: false, error: 'WHATSAPP_CLOUD_TOKEN missing' }, {
      status: 500,
    });
  }

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  const action = String(body.action ?? 'list').trim();
  const sharedWaba = Deno.env.get('SHARED_SENDER_WABA_ID')?.trim() || '';
  const wabaId = String(body.waba_id ?? sharedWaba).trim();
  const wantPhone = String(body.phone_e164 ?? body.phone ?? '').trim();
  const phoneNumberId = String(body.phone_number_id ?? '').trim();
  const pin = String(body.pin ?? '').trim();
  const tenantUserId = String(body.tenant_user_id ?? '').trim();
  const bind = body.bind === true;

  if (action === 'list') {
    if (!wabaId) {
      return Response.json({ ok: false, error: 'waba_id missing' }, {
        status: 400,
      });
    }
    const listed = await graphGet(
      `${wabaId}/phone_numbers?fields=id,display_phone_number,verified_name,name_status,quality_rating,code_verification_status,is_official_business_account`,
      token,
    );
    return Response.json({
      ok: listed.ok,
      waba_id: wabaId,
      detail: listed.detail,
      data: listed.data,
    });
  }

  if (action === 'bind') {
    if (!tenantUserId) {
      return Response.json({ ok: false, error: 'tenant_user_id required' }, {
        status: 400,
      });
    }
    let targetId = phoneNumberId;
    let displayPhone = wantPhone;
    if (!targetId) {
      if (!wabaId || !wantPhone) {
        return Response.json({
          ok: false,
          error: 'need phone_number_id or (waba_id + phone)',
        }, { status: 400 });
      }
      const resolved = await resolvePhoneOnWaba({
        token,
        wabaId,
        wantPhone,
      });
      if (!resolved.ok) {
        return Response.json({
          ok: false,
          error: resolved.detail ?? 'resolve_failed',
          phones: resolved.phones,
          data: resolved.data,
        }, {
          status: resolved.detail === 'phone_not_found_on_waba' ? 404 : 502,
        });
      }
      targetId = resolved.phoneNumberId;
      displayPhone = resolved.displayPhone;
    } else if (!displayPhone) {
      const meta = await graphGet(
        `${targetId}?fields=id,display_phone_number`,
        token,
      );
      displayPhone = meta.ok
        ? String(
          (meta.data as { display_phone_number?: string })
            .display_phone_number ??
            '',
        ).trim()
        : '';
      if (!displayPhone) {
        return Response.json({
          ok: false,
          error: 'display_phone_unknown',
          detail: meta.detail,
        }, { status: 400 });
      }
    }

    const bound = await bindTenantDedicatedNumber({
      tenantUserId,
      phoneNumberId: targetId,
      displayPhone,
      wabaId: wabaId || sharedWaba,
    });
    return Response.json({
      ok: bound.ok,
      action: 'bind',
      tenant_user_id: tenantUserId,
      phone_number_id: targetId,
      phone: bound.phone ?? null,
      error: bound.error ?? null,
    }, { status: bound.ok ? 200 : 500 });
  }

  if (action === 'register') {
    let targetId = phoneNumberId;
    let displayPhone = wantPhone;

    if (!targetId) {
      if (!wabaId || !wantPhone) {
        return Response.json({
          ok: false,
          error: 'need phone_number_id or (waba_id + phone)',
        }, { status: 400 });
      }
      const resolved = await resolvePhoneOnWaba({
        token,
        wabaId,
        wantPhone,
      });
      if (!resolved.ok) {
        return Response.json({
          ok: false,
          error: resolved.detail ?? 'list_failed',
          detail: resolved.detail,
          phones: resolved.phones,
          data: resolved.data,
        }, {
          status: resolved.detail === 'phone_not_found_on_waba' ? 404 : 502,
        });
      }
      targetId = resolved.phoneNumberId;
      displayPhone = resolved.displayPhone;
    }

    if (!/^\d{6}$/.test(pin)) {
      return Response.json({
        ok: false,
        error: 'pin_must_be_6_digits',
      }, { status: 400 });
    }

    const before = await graphGet(
      `${targetId}?fields=id,display_phone_number,verified_name,name_status,code_verification_status,quality_rating`,
      token,
    );
    if (before.ok && !displayPhone) {
      displayPhone = String(
        (before.data as { display_phone_number?: string })
          .display_phone_number ??
          '',
      ).trim();
    }

    const reg = await graphPost(`${targetId}/register`, token, {
      messaging_product: 'whatsapp',
      pin,
    });

    const after = await graphGet(
      `${targetId}?fields=id,display_phone_number,verified_name,name_status,code_verification_status,quality_rating`,
      token,
    );

    let bindResult: Record<string, unknown> | null = null;
    if (bind && tenantUserId && reg.ok) {
      const bound = await bindTenantDedicatedNumber({
        tenantUserId,
        phoneNumberId: targetId,
        displayPhone,
        wabaId: wabaId || sharedWaba,
      });
      bindResult = bound.ok
        ? {
          ok: true,
          tenant_user_id: tenantUserId,
          provider: 'cloud_api',
          phone: bound.phone,
          phone_number_id: targetId,
        }
        : { ok: false, error: bound.error };
    }

    return Response.json({
      ok: reg.ok,
      phone_number_id: targetId,
      display_phone: displayPhone,
      before: before.ok ? before.data : { error: before.detail },
      register: { ok: reg.ok, detail: reg.detail, data: reg.data },
      after: after.ok ? after.data : { error: after.detail },
      bind: bindResult,
    });
  }

  return Response.json({ ok: false, error: 'unknown_action' }, { status: 400 });
});
