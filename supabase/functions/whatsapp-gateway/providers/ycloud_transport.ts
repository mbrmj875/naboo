/**
 * YCloud = Transport فقط لمفهوم WhatsApp Cloud API.
 * لا يستدعيه Flutter ولا منطق غيار الزيت مباشرة.
 */

import type {
  ConnectCompleteInput,
  ConnectStartResult,
  EnsureTemplateInput,
  EnsureTemplateResult,
  SendResult,
  SendTemplateInput,
  SendTextInput,
  TemplateRemoteStatus,
  WhatsAppProvider,
} from './types.ts';

const YCLOUD_API = 'https://api.ycloud.com/v2';

/** ميتا ترفض \\n و\\t وأكثر من 4 مسافات داخل معاملات القالب. */
function sanitizeTemplateParam(raw: string): string {
  let s = String(raw ?? '')
    .replace(/[\r\n\t]+/g, ' · ')
    .replace(/ {5,}/g, '    ')
    .replace(/( · ){2,}/g, ' · ')
    .trim();
  if (!s) s = '-';
  if (s.length > 900) s = `${s.slice(0, 897)}…`;
  return s;
}

function partnerApiKey(): string | null {
  const k =
    Deno.env.get('YCLOUD_PARTNER_API_KEY')?.trim() ||
    Deno.env.get('WHATSAPP_CLOUD_TRANSPORT_API_KEY')?.trim() ||
    '';
  return k || null;
}

async function resolveApiKey(tenantUserId: string): Promise<string | null> {
  const partner = partnerApiKey();
  if (partner) return partner;
  // مفتاح مستأجر من أسرار Edge المؤقتة للتجربة (قبل Partner كامل)
  const specific = Deno.env.get(
    `YCLOUD_API_KEY_${tenantUserId.replace(/-/g, '_')}`,
  )?.trim();
  return specific || null;
}

async function ycloudFetch(
  path: string,
  apiKey: string,
  init?: RequestInit,
): Promise<Response> {
  return await fetch(`${YCLOUD_API}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': apiKey,
      ...(init?.headers ?? {}),
    },
  });
}

function isRetryableStatus(status: number): boolean {
  return status === 429 || status >= 500;
}

function e164(raw: string): string {
  const d = raw.replace(/\D/g, '');
  if (!d) return '';
  return raw.trim().startsWith('+') ? `+${d}` : `+${d}`;
}

/** يحوّل error object من YCloud إلى نص مقروء (بدل [object Object]). */
function formatApiError(data: Record<string, unknown>, raw: string): string {
  const err = data.error ?? data.message ?? data.msg;
  if (typeof err === 'string' && err.trim()) return err.slice(0, 400);
  if (err && typeof err === 'object') {
    try {
      return JSON.stringify(err).slice(0, 400);
    } catch {
      /* ignore */
    }
  }
  if (raw.trim()) return raw.slice(0, 400);
  return 'ycloud_error';
}

export const ycloudTransport: WhatsAppProvider = {
  id: 'ycloud',
  capabilities: {
    supportsEmbeddedSignup: true,
    supportsTemplates: true,
    supportsMedia: true,
    supportsInteractiveButtons: true,
    supportsCoexistence: true,
    supportsInboundMessages: true,
  },

  async startConnect(_tenantUserId: string): Promise<ConnectStartResult> {
    // Embedded Signup الكامل يحتاج Technical Partner + Configuration ID.
    // حتى التفعيل: الواجهة تعرض preparing وتوجيه دعم/إعداد داخلي.
    const cfg = Deno.env.get('YCLOUD_EMBEDDED_SIGNUP_URL')?.trim();
    if (cfg) {
      return { ok: true, onboardingUrl: cfg };
    }
    return {
      ok: false,
      onboardingUrl: null,
      detail: 'embedded_signup_not_configured',
    };
  },

  async completeConnect(input: ConnectCompleteInput) {
    if (!input.wabaId && !input.fromPhoneE164 && !input.phoneNumberId) {
      return { ok: false, detail: 'missing_connection_fields' };
    }
    return { ok: true };
  },

  async disconnect(_tenantUserId: string) {
    return { ok: true };
  },

  async sendText(input: SendTextInput): Promise<SendResult> {
    const apiKey = await resolveApiKey(input.tenantUserId);
    if (!apiKey) {
      return { ok: false, detail: 'ycloud_api_key_missing' };
    }
    const from = input.fromPhoneE164 ? e164(input.fromPhoneE164) : '';
    const to = e164(input.toPhoneE164);
    if (!from || !to) {
      return { ok: false, detail: 'invalid_phone' };
    }
    try {
      const res = await ycloudFetch('/whatsapp/messages', apiKey, {
        method: 'POST',
        body: JSON.stringify({
          from,
          to,
          type: 'text',
          text: { body: input.body },
        }),
      });
      const raw = await res.text();
      let data: Record<string, unknown> = {};
      try {
        data = JSON.parse(raw) as Record<string, unknown>;
      } catch {
        /* ignore */
      }
      if (!res.ok) {
        return {
          ok: false,
          httpStatus: res.status,
          detail: formatApiError(data, raw),
          retryable: isRetryableStatus(res.status),
        };
      }
      const id = data.id != null ? String(data.id) : undefined;
      return { ok: true, providerMessageId: id, httpStatus: res.status };
    } catch (e) {
      return {
        ok: false,
        detail: String(e).slice(0, 200),
        retryable: true,
      };
    }
  },

  async sendTemplate(input: SendTemplateInput): Promise<SendResult> {
    const apiKey = await resolveApiKey(input.tenantUserId);
    if (!apiKey) {
      return { ok: false, detail: 'ycloud_api_key_missing' };
    }
    const from = e164(input.fromPhoneE164);
    const to = e164(input.toPhoneE164);
    if (!from || !to) {
      return { ok: false, detail: 'invalid_phone' };
    }
    // ميتا: لا أسطر جديدة/تاب ولا أكثر من 4 مسافات متتالية داخل معاملات القالب.
    const bodyParams = (input.bodyParameters ?? []).map((text) => ({
      type: 'text',
      text: sanitizeTemplateParam(text),
    }));
    try {
      const res = await ycloudFetch('/whatsapp/messages', apiKey, {
        method: 'POST',
        body: JSON.stringify({
          from,
          to,
          type: 'template',
          template: {
            name: input.templateName,
            language: { code: input.language },
            components: bodyParams.length
              ? [{ type: 'body', parameters: bodyParams }]
              : [],
          },
        }),
      });
      const raw = await res.text();
      let data: Record<string, unknown> = {};
      try {
        data = JSON.parse(raw) as Record<string, unknown>;
      } catch {
        /* ignore */
      }
      if (!res.ok) {
        return {
          ok: false,
          httpStatus: res.status,
          detail: formatApiError(data, raw),
          retryable: isRetryableStatus(res.status),
        };
      }
      const id = data.id != null ? String(data.id) : undefined;
      return { ok: true, providerMessageId: id, httpStatus: res.status };
    } catch (e) {
      return {
        ok: false,
        detail: String(e).slice(0, 200),
        retryable: true,
      };
    }
  },

  async ensureTemplate(input: EnsureTemplateInput): Promise<EnsureTemplateResult> {
    const apiKey = await resolveApiKey(input.tenantUserId);
    if (!apiKey) {
      return { ok: false, detail: 'ycloud_api_key_missing' };
    }
    try {
      const res = await ycloudFetch('/whatsapp/templates', apiKey, {
        method: 'POST',
        body: JSON.stringify({
          wabaId: input.wabaId,
          name: input.templateName,
          language: input.language,
          category: input.category.toUpperCase(),
          components: [
            {
              type: 'BODY',
              text: input.bodyText,
              example: {
                body_text: [input.exampleBodyParams],
              },
            },
          ],
        }),
      });
      const raw = await res.text();
      let data: Record<string, unknown> = {};
      try {
        data = JSON.parse(raw) as Record<string, unknown>;
      } catch {
        /* ignore */
      }
      // 409 / already exists → اعتبره pending/approved حسب الرد
      if (!res.ok && res.status !== 409) {
        return {
          ok: false,
          detail: String(data.message ?? data.error ?? raw).slice(0, 300),
        };
      }
      const statusRaw = String(data.status ?? data.qualityRating ?? 'pending')
        .toLowerCase();
      let status: EnsureTemplateResult['status'] = 'pending';
      if (statusRaw.includes('approv') || statusRaw === 'active') {
        status = 'approved';
      } else if (statusRaw.includes('reject')) {
        status = 'rejected';
      }
      const templateId = data.id != null
        ? String(data.id)
        : data.officialTemplateId != null
        ? String(data.officialTemplateId)
        : undefined;
      return { ok: true, templateId, status };
    } catch (e) {
      return { ok: false, detail: String(e).slice(0, 200) };
    }
  },

  async getTemplateStatus(args): Promise<TemplateRemoteStatus> {
    const apiKey = await resolveApiKey(args.tenantUserId);
    if (!apiKey) {
      return { ok: false, status: 'unknown', detail: 'ycloud_api_key_missing' };
    }
    try {
      const q = new URLSearchParams({
        wabaId: args.wabaId,
        name: args.templateName,
        language: args.language,
      });
      const res = await ycloudFetch(
        `/whatsapp/templates?${q.toString()}`,
        apiKey,
        { method: 'GET' },
      );
      const raw = await res.text();
      let data: Record<string, unknown> = {};
      try {
        data = JSON.parse(raw) as Record<string, unknown>;
      } catch {
        /* ignore */
      }
      if (!res.ok) {
        return {
          ok: false,
          status: 'unknown',
          detail: String(data.message ?? raw).slice(0, 200),
        };
      }
      const items = Array.isArray(data.items)
        ? data.items
        : Array.isArray(data.data)
        ? data.data
        : Array.isArray(data)
        ? data
        : [data];
      const first = items[0] as Record<string, unknown> | undefined;
      if (!first) {
        return { ok: true, status: 'none' };
      }
      const statusRaw = String(first.status ?? '').toLowerCase();
      let status: TemplateRemoteStatus['status'] = 'pending';
      if (statusRaw.includes('approv') || statusRaw === 'active') {
        status = 'approved';
      } else if (statusRaw.includes('reject')) {
        status = 'rejected';
      } else if (!statusRaw) {
        status = 'unknown';
      }
      return {
        ok: true,
        templateId: first.id != null ? String(first.id) : undefined,
        status,
      };
    } catch (e) {
      return { ok: false, status: 'unknown', detail: String(e).slice(0, 200) };
    }
  },
};

/** تحقق توقيع ويب هوك YCloud: header YCloud-Signature = t=...,s=... */
export async function verifyYcloudWebhookSignature(
  rawBody: string,
  signatureHeader: string | null,
  secret: string,
): Promise<boolean> {
  if (!signatureHeader || !secret) return false;
  const parts = Object.fromEntries(
    signatureHeader.split(',').map((p) => {
      const [k, ...rest] = p.trim().split('=');
      return [k, rest.join('=')];
    }),
  );
  const t = parts['t'];
  const s = parts['s'];
  if (!t || !s) return false;
  const payload = `${t}.${rawBody}`;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(payload),
  );
  const hex = [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  return hex === s.toLowerCase();
}
