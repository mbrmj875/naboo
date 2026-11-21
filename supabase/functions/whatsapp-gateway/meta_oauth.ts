/**
 * Meta OAuth + Graph helpers لمسار Embedded Signup (cloud_api).
 */

import type { EnsureTemplateResult } from './providers/types.ts';
import { isSharedSenderPhone } from './shared_sender.ts';

const GRAPH_VER = Deno.env.get('META_GRAPH_API_VERSION')?.trim() || 'v26.0';
const GRAPH = `https://graph.facebook.com/${GRAPH_VER}`;
const RECENT_ONBOARD_MS = 2 * 60 * 60 * 1000;

function metaAppId(): string | null {
  return Deno.env.get('META_APP_ID')?.trim() || null;
}

function metaAppSecret(): string | null {
  return Deno.env.get('META_APP_SECRET')?.trim() || null;
}

async function graphJson(
  url: string,
  init?: RequestInit,
): Promise<{ ok: boolean; status: number; data: Record<string, unknown>; raw: string }> {
  const res = await fetch(url, {
    ...init,
    signal: AbortSignal.timeout(25_000),
  });
  const raw = await res.text();
  let data: Record<string, unknown> = {};
  try {
    data = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    /* ignore */
  }
  return { ok: res.ok, status: res.status, data, raw };
}

/** تبادل code من FB.login أو dialog/oauth → access_token */
export async function exchangeEmbeddedSignupCode(
  code: string,
  redirectUri?: string,
): Promise<{ ok: true; accessToken: string } | { ok: false; detail: string }> {
  const appId = metaAppId();
  const secret = metaAppSecret();
  if (!appId || !secret) {
    return { ok: false, detail: 'meta_app_secret_missing' };
  }
  const c = code.trim();
  if (!c) return { ok: false, detail: 'oauth_code_missing' };

  const url = new URL(`${GRAPH}/oauth/access_token`);
  url.searchParams.set('client_id', appId);
  url.searchParams.set('client_secret', secret);
  url.searchParams.set('code', c);
  const redirect = String(redirectUri ?? '').trim();
  if (redirect) {
    url.searchParams.set('redirect_uri', redirect);
  }

  const res = await graphJson(url.toString());
  if (!res.ok) {
    const err = res.data.error as Record<string, unknown> | undefined;
    return {
      ok: false,
      detail: String(err?.message ?? res.raw).slice(0, 300),
    };
  }
  const token = String(res.data.access_token ?? '').trim();
  if (!token) return { ok: false, detail: 'oauth_token_empty' };
  return { ok: true, accessToken: token };
}

/** ترقية لتوكن طويل الأمد إن أمكن */
export async function exchangeLongLivedToken(
  shortToken: string,
): Promise<string> {
  const appId = metaAppId();
  const secret = metaAppSecret();
  if (!appId || !secret) return shortToken;
  const url = new URL(`${GRAPH}/oauth/access_token`);
  url.searchParams.set('grant_type', 'fb_exchange_token');
  url.searchParams.set('client_id', appId);
  url.searchParams.set('client_secret', secret);
  url.searchParams.set('fb_exchange_token', shortToken);
  const res = await graphJson(url.toString());
  const long = String(res.data.access_token ?? '').trim();
  return long || shortToken;
}

export async function subscribeAppToWaba(
  wabaId: string,
  accessToken: string,
): Promise<{ ok: boolean; detail?: string }> {
  const id = wabaId.trim();
  if (!id) return { ok: false, detail: 'waba_missing' };
  const res = await graphJson(
    `${GRAPH}/${encodeURIComponent(id)}/subscribed_apps`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({}),
    },
  );
  if (!res.ok) {
    const err = res.data.error as Record<string, unknown> | undefined;
    return {
      ok: false,
      detail: String(err?.message ?? res.raw).slice(0, 300),
    };
  }
  return { ok: true };
}

export async function fetchPhoneDisplay(
  phoneNumberId: string,
  accessToken: string,
): Promise<{ displayE164: string | null; verifiedName: string | null }> {
  const id = phoneNumberId.trim();
  if (!id) return { displayE164: null, verifiedName: null };
  const url =
    `${GRAPH}/${encodeURIComponent(id)}` +
    `?fields=display_phone_number,verified_name`;
  const res = await graphJson(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) return { displayE164: null, verifiedName: null };
  const display = String(res.data.display_phone_number ?? '').replace(/\D/g, '');
  const name = String(res.data.verified_name ?? '').trim() || null;
  return {
    displayE164: display.length >= 10 ? display : null,
    verifiedName: name,
  };
}

export async function fetchPhoneOnboarding(
  phoneNumberId: string,
  accessToken: string,
): Promise<{ isOnBizApp: boolean; platformType: string }> {
  const id = phoneNumberId.trim();
  if (!id) return { isOnBizApp: false, platformType: '' };
  const res = await graphJson(
    `${GRAPH}/${encodeURIComponent(id)}` +
      `?fields=is_on_biz_app,platform_type`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) return { isOnBizApp: false, platformType: '' };
  return {
    isOnBizApp: res.data.is_on_biz_app === true,
    platformType: String(res.data.platform_type ?? '').trim().toUpperCase(),
  };
}

export function isBenignRegisterFailure(detail?: string): boolean {
  const text = String(detail ?? '');
  return /already registered|already exists|is registered|two[- ]step|pin|133005|133016|133008|coexistence|business app/i
    .test(text);
}

/** أرقام الهاتف على WABA — لإكمال coexistence حيث يصل waba_id فقط. */
export async function listWabaPhoneNumbers(
  wabaId: string,
  accessToken: string,
): Promise<Array<{ id: string; displayDigits: string }>> {
  const id = wabaId.trim();
  if (!id) return [];
  const res = await graphJson(
    `${GRAPH}/${encodeURIComponent(id)}/phone_numbers` +
      `?fields=id,display_phone_number&limit=10`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (!res.ok) return [];
  const rows = Array.isArray(res.data.data) ? res.data.data : [];
  return rows.map((r) => {
    const row = r as Record<string, unknown>;
    return {
      id: String(row.id ?? '').trim(),
      displayDigits: String(row.display_phone_number ?? '').replace(/\D/g, ''),
    };
  }).filter((r) => r.id);
}

/**
 * تسجيل الرقم على Cloud API بعد ES — بدونه يفشل الإرسال.
 * قد يفشل بلا ضرر إن كان الرقم مسجلاً مسبقاً (coexistence).
 */
export async function registerCloudPhone(
  phoneNumberId: string,
  accessToken: string,
  pin: string,
): Promise<{ ok: boolean; detail?: string }> {
  const id = phoneNumberId.trim();
  if (!id) return { ok: false, detail: 'phone_number_id_missing' };
  const res = await graphJson(
    `${GRAPH}/${encodeURIComponent(id)}/register`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        pin,
      }),
    },
  );
  if (!res.ok) {
    const err = res.data.error as Record<string, unknown> | undefined;
    return {
      ok: false,
      detail: String(err?.message ?? res.raw).slice(0, 300),
    };
  }
  return { ok: true };
}

type ResolvedPhone = {
  wabaId: string;
  phoneNumberId: string;
  displayDigits: string;
  onboardedAt: number;
};

type PhoneListResult = {
  phones: ResolvedPhone[];
  detail?: string;
  httpStatus?: number;
};

export type ResolveWabaResult = {
  wabaId: string | null;
  phoneNumberId: string | null;
  ambiguous?: boolean;
  detail?: string;
  httpStatus?: number;
};

export type ResolveWabaOptions = {
  displayPhoneHint?: string;
  excludePhoneIds?: string[];
  excludePhoneDigits?: string[];
};

function digitsOnly(value: unknown): string {
  return String(value ?? '').replace(/\D/g, '');
}

function last10(value: string): string {
  const d = digitsOnly(value);
  return d.length > 10 ? d.slice(-10) : d;
}

function parseOnboardedAt(value: unknown): number {
  const raw = String(value ?? '').trim();
  if (!raw) return 0;
  const asNum = Number(raw);
  if (Number.isFinite(asNum) && asNum > 0) {
    return asNum < 1e12 ? asNum * 1000 : asNum;
  }
  const asDate = Date.parse(raw);
  return Number.isFinite(asDate) ? asDate : 0;
}

function pushUnique(ids: string[], value: string): void {
  const id = value.trim();
  if (id && !ids.includes(id)) ids.push(id);
}

/** يستخرج WABA من عقدة رقم هاتف إن كان target_id هاتفاً لا حساباً. */
async function resolvePhoneNodeToWaba(
  phoneNumberId: string,
  auth: { headers: { Authorization: string } },
): Promise<ResolvedPhone | null> {
  const id = phoneNumberId.trim();
  if (!id) return null;
  const res = await graphJson(
    `${GRAPH}/${encodeURIComponent(id)}` +
      `?fields=id,display_phone_number,last_onboarded_time,` +
      `whatsapp_business_account{id}`,
    auth,
  );
  if (!res.ok) return null;
  const wabaObj = res.data.whatsapp_business_account as
    | Record<string, unknown>
    | undefined;
  const wabaId = String(wabaObj?.id ?? '').trim();
  if (!wabaId) return null;
  return {
    wabaId,
    phoneNumberId: String(res.data.id ?? id).trim() || id,
    displayDigits: digitsOnly(res.data.display_phone_number),
    onboardedAt: parseOnboardedAt(res.data.last_onboarded_time),
  };
}

async function listTokenWabaIds(
  token: string,
  auth: { headers: { Authorization: string } },
): Promise<{ wabaIds: string[]; detail?: string; httpStatus?: number }> {
  const ids: string[] = [];

  const appId = metaAppId();
  const secret = metaAppSecret();
  const systemToken =
    Deno.env.get('META_SYSTEM_USER_TOKEN')?.trim() ||
    Deno.env.get('WHATSAPP_CLOUD_TOKEN')?.trim() ||
    '';
  const debugUrl =
    `${GRAPH}/debug_token?input_token=${encodeURIComponent(token)}`;
  const dbg = systemToken
    ? await graphJson(debugUrl, {
      headers: { Authorization: `Bearer ${systemToken}` },
    })
    : appId && secret
    ? await graphJson(
      `${debugUrl}&access_token=${encodeURIComponent(`${appId}|${secret}`)}`,
    )
    : null;

  if (dbg?.ok) {
    const data = dbg.data.data as Record<string, unknown> | undefined;
    const scopes = Array.isArray(data?.granular_scopes)
      ? data!.granular_scopes as Array<Record<string, unknown>>
      : [];
    // وثيقة Meta: أول target_id في whatsapp_business_management هو أحدث WABA
    // شاركها العميل. نحافظ على ترتيب Meta ولا نخمن من وقت الإنشاء.
    const management = scopes.find((row) =>
      String(row.scope ?? '') === 'whatsapp_business_management'
    );
    const targets = Array.isArray(management?.target_ids)
      ? management!.target_ids
      : [];
    for (const id of targets) pushUnique(ids, String(id ?? ''));
    if (ids.length > 0) return { wabaIds: ids };
  } else if (dbg) {
    const error = dbg.data.error as Record<string, unknown> | undefined;
    console.warn(
      'es_debug_token_failed',
      JSON.stringify({
        status: dbg.status,
        code: error?.code == null ? null : String(error.code),
      }),
    );
  }

  // fallback محدود للحسابات المملوكة؛ لا نطلب business_management.
  const owned = await graphJson(
    `${GRAPH}/me/whatsapp_business_accounts?fields=id&limit=50`,
    auth,
  );
  if (owned.ok) {
    const rows = Array.isArray(owned.data.data) ? owned.data.data : [];
    for (const row of rows) {
      pushUnique(ids, String((row as Record<string, unknown>).id ?? ''));
    }
    return { wabaIds: ids };
  }
  const error = owned.data.error as Record<string, unknown> | undefined;
  return {
    wabaIds: [],
    detail: 'meta_waba_targets_unavailable',
    httpStatus: owned.status,
    ...(error?.code == null
      ? {}
      : { detail: `meta_waba_targets_error_${String(error.code)}` }),
  };
}

async function listWabaPhones(
  wabaId: string,
  auth: { headers: { Authorization: string } },
): Promise<PhoneListResult> {
  const phones = await graphJson(
    `${GRAPH}/${encodeURIComponent(wabaId)}/phone_numbers` +
      `?fields=id,display_phone_number,last_onboarded_time&limit=50`,
    auth,
  );
  if (!phones.ok) {
    const error = phones.data.error as Record<string, unknown> | undefined;
    const code = error?.code == null ? '' : String(error.code);
    return {
      phones: [],
      detail: code === '80008'
        ? 'meta_waba_rate_limited'
        : code
        ? `meta_phone_list_error_${code}`
        : 'meta_phone_list_failed',
      httpStatus: phones.status,
    };
  }
  const rows = Array.isArray(phones.data.data) ? phones.data.data : [];
  const out: ResolvedPhone[] = [];
  for (const row of rows) {
    const rec = row as Record<string, unknown>;
    const phoneNumberId = String(rec.id ?? '').trim();
    if (!phoneNumberId) continue;
    out.push({
      wabaId,
      phoneNumberId,
      displayDigits: digitsOnly(rec.display_phone_number),
      onboardedAt: parseOnboardedAt(rec.last_onboarded_time),
    });
  }
  return { phones: out };
}

function isDummyPhone(digits: string): boolean {
  return digits.startsWith('1555') || digits.includes('555555');
}

function samePhone(a: string, b: string): boolean {
  const left = last10(a);
  const right = last10(b);
  return left.length >= 8 && right.length >= 8 && left === right;
}

function isRecentlyOnboarded(p: ResolvedPhone, now = Date.now()): boolean {
  return p.onboardedAt > 0 && now - p.onboardedAt <= RECENT_ONBOARD_MS;
}

function pickSignupPhone(
  phones: ResolvedPhone[],
  opts: ResolveWabaOptions = {},
): ResolvedPhone | null {
  const excludeIds = new Set(
    (opts.excludePhoneIds ?? []).map((id) => id.trim()).filter(Boolean),
  );
  const excludeDigits = (opts.excludePhoneDigits ?? [])
    .map((d) => digitsOnly(d))
    .filter((d) => d.length >= 8);
  const hint = digitsOnly(opts.displayPhoneHint);
  const now = Date.now();

  const available = phones.filter((p) => {
    if (isSharedSenderPhone(p.phoneNumberId)) return false;
    if (isDummyPhone(p.displayDigits)) return false;
    // رقم أُهِّل للتو في جلسة ES يتجاوز استبعاد أرقام المستأجرين الآخرين
    // (غالباً القائمة كانت تحجب كل شيء الظاهر قبل ظهور الرقم الجديد).
    if (isRecentlyOnboarded(p, now)) return true;
    if (excludeIds.has(p.phoneNumberId)) return false;
    if (excludeDigits.some((d) => samePhone(d, p.displayDigits))) return false;
    return true;
  });
  if (available.length === 0) return null;
  if (available.length === 1) return available[0];

  if (hint.length >= 8) {
    const hinted = available.filter((p) => samePhone(hint, p.displayDigits));
    if (hinted.length === 1) return hinted[0];
    if (hinted.length > 1) {
      const rankedHint = [...hinted].sort((a, b) => b.onboardedAt - a.onboardedAt);
      if (rankedHint[0].onboardedAt > 0) return rankedHint[0];
      return rankedHint[0];
    }
  }

  const ranked = [...available].sort((a, b) => b.onboardedAt - a.onboardedAt);
  const newest = ranked[0];
  if (newest && newest.onboardedAt > 0) {
    // بعد ES مباشرة: الرقم الأحدث تأهيلاً هو المقصود حتى مع تعدد الأرقام.
    if (now - newest.onboardedAt <= 48 * 60 * 60 * 1000) {
      return newest;
    }
    const sameTime = ranked.filter((p) => p.onboardedAt === newest.onboardedAt);
    if (sameTime.length === 1) return newest;
  }
  // آخر ملاذ بعد ES: أحدث رقم غير مشترك حتى بلا last_onboarded_time.
  return newest ?? null;
}

async function collectPhonesFromToken(
  token: string,
  auth: { headers: { Authorization: string } },
): Promise<{
  phones: ResolvedPhone[];
  wabaIds: string[];
  detail?: string;
  httpStatus?: number;
}> {
  const targets = await listTokenWabaIds(token, auth);
  const wabaIds = targets.wabaIds;
  const byPhoneId = new Map<string, ResolvedPhone>();
  if (targets.detail) {
    return {
      phones: [],
      wabaIds,
      detail: targets.detail,
      httpStatus: targets.httpStatus,
    };
  }
  for (const id of wabaIds) {
    const listed = await listWabaPhones(id, auth);
    if (listed.detail) {
      return {
        phones: [...byPhoneId.values()],
        wabaIds,
        detail: listed.detail,
        httpStatus: listed.httpStatus,
      };
    }
    for (const p of listed.phones) {
      byPhoneId.set(p.phoneNumberId, p);
    }
  }
  return { phones: [...byPhoneId.values()], wabaIds };
}

/**
 * إن فُقد sessionInfo من الصفحة (شائع مع dialog/oauth) —
 * نستخرج WABA/الهاتف من التوكن عبر عدة مصادر Graph.
 */
export async function resolveWabaAssetsFromToken(
  accessToken: string,
  knownWabaId?: string,
  knownPhoneId?: string,
  opts: ResolveWabaOptions = {},
): Promise<ResolveWabaResult> {
  const token = accessToken.trim();
  if (!token) return { wabaId: null, phoneNumberId: null };
  const auth = { headers: { Authorization: `Bearer ${token}` } };
  const hintedPhone = String(knownPhoneId ?? '').trim();
  const hintedWaba = String(knownWabaId ?? '').trim();

  if (hintedWaba) {
    const check = await graphJson(
      `${GRAPH}/${encodeURIComponent(hintedWaba)}?fields=id`,
      auth,
    );
    if (check.ok) {
      const listed = await listWabaPhones(hintedWaba, auth);
      if (listed.detail) {
        return {
          wabaId: hintedWaba,
          phoneNumberId: null,
          detail: listed.detail,
          httpStatus: listed.httpStatus,
        };
      }
      const phones = listed.phones;
      if (hintedPhone && phones.some((p) => p.phoneNumberId === hintedPhone)) {
        return { wabaId: hintedWaba, phoneNumberId: hintedPhone };
      }
      const picked = pickSignupPhone(phones, opts);
      if (picked) {
        return { wabaId: picked.wabaId, phoneNumberId: picked.phoneNumberId };
      }
      if (phones.length === 1) {
        return {
          wabaId: hintedWaba,
          phoneNumberId: phones[0].phoneNumberId,
        };
      }
      if (phones.length > 1) {
        return { wabaId: hintedWaba, phoneNumberId: null, ambiguous: true };
      }
    }
  }

  if (hintedPhone) {
    const direct = await resolvePhoneNodeToWaba(hintedPhone, auth);
    if (direct) {
      return {
        wabaId: direct.wabaId,
        phoneNumberId: direct.phoneNumberId,
      };
    }
  }

  const collected = await collectPhonesFromToken(token, auth);
  const phones = collected.phones;
  console.warn(
    'es_resolve_phones',
    JSON.stringify({
      count: phones.length,
      wabaCount: collected.wabaIds.length,
      detail: collected.detail ?? null,
      sample: phones.slice(0, 5).map((p) => ({
        waba: p.wabaId,
        phone: p.phoneNumberId,
        digits: p.displayDigits.slice(-4),
        onboardedAt: p.onboardedAt,
      })),
    }),
  );
  if (collected.detail) {
    return {
      wabaId: collected.wabaIds[0] ?? null,
      phoneNumberId: null,
      detail: collected.detail,
      httpStatus: collected.httpStatus,
    };
  }
  if (phones.length === 0) return { wabaId: null, phoneNumberId: null };

  if (hintedPhone) {
    const hinted = phones.find((p) => p.phoneNumberId === hintedPhone);
    if (hinted) {
      return { wabaId: hinted.wabaId, phoneNumberId: hinted.phoneNumberId };
    }
  }
  const picked = pickSignupPhone(phones, opts);
  if (picked) {
    return { wabaId: picked.wabaId, phoneNumberId: picked.phoneNumberId };
  }
  const nonShared = phones.filter((p) => !isSharedSenderPhone(p.phoneNumberId));
  if (nonShared.length === 1) {
    return {
      wabaId: nonShared[0].wabaId,
      phoneNumberId: nonShared[0].phoneNumberId,
    };
  }
  if (phones.length === 1) {
    return {
      wabaId: phones[0].wabaId,
      phoneNumberId: phones[0].phoneNumberId,
    };
  }
  if (phones.length > 1) {
    return { wabaId: null, phoneNumberId: null, ambiguous: true };
  }
  return { wabaId: null, phoneNumberId: null };
}

/** إعادة محاولة بعد ES — الرقم قد يتأخر على Graph بعد «Assets successfully created». */
export async function resolveWabaAssetsFromTokenWithRetry(
  accessToken: string,
  knownWabaId?: string,
  knownPhoneId?: string,
  opts: ResolveWabaOptions = {},
  attempts = 2,
): Promise<ResolveWabaResult> {
  let last: ResolveWabaResult = { wabaId: null, phoneNumberId: null };
  const max = Math.max(1, Math.min(2, Math.floor(attempts)));
  for (let i = 0; i < max; i++) {
    last = await resolveWabaAssetsFromToken(
      accessToken,
      knownWabaId,
      knownPhoneId,
      opts,
    );
    if (last.wabaId && last.phoneNumberId) return last;
    // لا نكرر أخطاء Graph، وبالأخص 80008؛ التكرار يمدد نافذة الحد.
    if (last.ambiguous || last.detail) return last;
    if (i + 1 < max) {
      await new Promise((r) => setTimeout(r, 5000));
    }
  }
  return last;
}

export async function createWabaMessageTemplate(args: {
  wabaId: string;
  accessToken: string;
  templateName: string;
  language: string;
  category: string;
  bodyText: string;
  exampleBodyParams: string[];
}): Promise<EnsureTemplateResult> {
  const wabaId = args.wabaId.trim();
  if (!wabaId) return { ok: false, detail: 'waba_missing' };

  const component: Record<string, unknown> = {
    type: 'BODY',
    text: args.bodyText,
  };
  if (args.exampleBodyParams.length > 0) {
    component.example = { body_text: [args.exampleBodyParams] };
  }
  const body: Record<string, unknown> = {
    name: args.templateName,
    language: args.language,
    category: args.category.toUpperCase(),
    parameter_format: 'POSITIONAL',
    components: [component],
  };

  const res = await graphJson(
    `${GRAPH}/${encodeURIComponent(wabaId)}/message_templates`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${args.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    },
  );

  // قالب موجود مسبقاً
  if (!res.ok) {
    const err = res.data.error as Record<string, unknown> | undefined;
    const msg = String(err?.message ?? res.raw).toLowerCase();
    if (
      res.status === 400 &&
      (msg.includes('already exists') || msg.includes('duplicate'))
    ) {
      return { ok: true, status: 'pending', detail: 'template_exists' };
    }
    const userMsg = String(
      err?.error_user_msg ?? err?.error_user_title ?? err?.message ?? res.raw,
    );
    return {
      ok: false,
      detail: userMsg.slice(0, 300),
    };
  }

  const statusRaw = String(res.data.status ?? 'PENDING').toUpperCase();
  let status: EnsureTemplateResult['status'] = 'pending';
  if (statusRaw.includes('APPROV')) status = 'approved';
  else if (statusRaw.includes('REJECT')) status = 'rejected';

  return {
    ok: true,
    templateId: res.data.id != null ? String(res.data.id) : undefined,
    status,
  };
}
