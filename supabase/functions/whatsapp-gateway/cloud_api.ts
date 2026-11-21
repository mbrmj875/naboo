/**
 * WhatsApp Cloud API (Meta الرسمي) — إرسال عبر Graph API.
 *
 * رقم المحل (`cloud_api` / ES):
 *   resolveCloudToken → سر المستأجر ثم WHATSAPP_CLOUD_TOKEN_<userId> ثم العام.
 *
 * رقم نابو الرسمي (SHARED_SENDER):
 *   resolveGraphAccessToken يختار توكن نابو فقط عندما يكون phone/waba مشتركاً.
 *   لا يُستخدم سر ES الخاص بالمحل على هاتف نابو.
 */

import { readProviderSecret } from './provider_secrets.ts';
import {
  isSharedSenderPhone,
  isSharedSenderWaba,
  resolveSharedSenderToken,
} from './shared_sender.ts';

const GRAPH_VER = Deno.env.get('META_GRAPH_API_VERSION')?.trim() || 'v26.0';
import { graphErrorCodes } from './failure_policy.ts';

const GRAPH = `https://graph.facebook.com/${GRAPH_VER}`;

export type CloudSendResult = {
  ok: boolean;
  messageId?: string;
  detail?: string;
  httpStatus?: number;
  errorCode?: number;
  errorSubcode?: number;
};

/** توكن رقم المحل الخاص — لا يُستدعى لمسار رقم نابو. */
export async function resolveCloudToken(userId: string): Promise<string | null> {
  const fromDb = await readProviderSecret(userId, 'cloud_api', 'access_token');
  if (fromDb) return fromDb;
  const specific = Deno.env.get(
    `WHATSAPP_CLOUD_TOKEN_${userId.replace(/-/g, '_')}`,
  );
  if (specific && specific.trim()) return specific.trim();
  const global = Deno.env.get('WHATSAPP_CLOUD_TOKEN');
  return global?.trim() || null;
}

/**
 * يختار توكن Graph حسب مالك الأصل:
 * - هاتف/WABA نابو → توكن نابو فقط (بلا سر ES للمستأجر)
 * - غير ذلك → resolveCloudToken (مسار رقم المحل كما هو)
 */
export async function resolveGraphAccessToken(args: {
  userId: string;
  phoneNumberId?: string | null;
  wabaId?: string | null;
}): Promise<string | null> {
  if (
    isSharedSenderPhone(args.phoneNumberId) ||
    isSharedSenderWaba(args.wabaId)
  ) {
    return resolveSharedSenderToken();
  }
  return await resolveCloudToken(args.userId);
}

/**
 * خطين زرق (مقروءة) + مؤشر «يكتب…» حتى يصل ردّنا أو تمرّ ~25 ثانية.
 * يُستدعى برقم wamid للرسالة الواردة من الـ webhook.
 */
export async function cloudMarkReadAndTyping(args: {
  userId: string;
  phoneNumberId: string;
  inboundMessageId: string;
}): Promise<CloudSendResult> {
  const token = await resolveGraphAccessToken({
    userId: args.userId,
    phoneNumberId: args.phoneNumberId,
  });
  if (!token) return { ok: false, detail: 'cloud_token_missing' };
  const phoneId = args.phoneNumberId.trim();
  if (!phoneId) return { ok: false, detail: 'cloud_phone_number_id_missing' };
  const messageId = args.inboundMessageId.trim();
  if (!messageId) return { ok: false, detail: 'inbound_message_id_missing' };

  try {
    const res = await fetch(`${GRAPH}/${encodeURIComponent(phoneId)}/messages`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        status: 'read',
        message_id: messageId,
        typing_indicator: { type: 'text' },
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
      const err = data.error as Record<string, unknown> | undefined;
      return {
        ok: false,
        ...graphErrorCodes(err),
        httpStatus: res.status,
        detail: String(err?.message ?? raw).slice(0, 300),
      };
    }
    return { ok: true, httpStatus: res.status };
  } catch (e) {
    return {
      ok: false,
      detail: e instanceof Error ? e.message : String(e),
    };
  }
}

/** تأخير بشري خفيف قبل إرسال الرد (بعد إظهار «يكتب…»). */
export function humanTypingDelayMs(
  replyBody: string,
  opts?: { fast?: boolean },
): number {
  const chars = String(replyBody ?? '').length;
  if (opts?.fast) {
    return Math.min(1800, Math.max(700, 500 + chars * 18));
  }
  return Math.min(2800, Math.max(900, 700 + chars * 22));
}

export function sleepMs(ms: number): Promise<void> {
  const n = Math.max(0, Math.floor(ms));
  if (n <= 0) return Promise.resolve();
  return new Promise((resolve) => setTimeout(resolve, n));
}

export async function cloudSendText(args: {
  userId: string;
  phoneNumberId: string;
  toE164Digits: string;
  body: string;
}): Promise<CloudSendResult> {
  const token = await resolveGraphAccessToken({
    userId: args.userId,
    phoneNumberId: args.phoneNumberId,
  });
  if (!token) {
    return {
      ok: false,
      detail: 'cloud_token_missing',
    };
  }
  const phoneId = args.phoneNumberId.trim();
  if (!phoneId) {
    return { ok: false, detail: 'cloud_phone_number_id_missing' };
  }
  const to = args.toE164Digits.replace(/\D/g, '');
  if (to.length < 10) {
    return { ok: false, detail: 'invalid_phone' };
  }

  try {
    const res = await fetch(`${GRAPH}/${encodeURIComponent(phoneId)}/messages`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to,
        type: 'text',
        text: { preview_url: false, body: args.body },
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
      const err = data.error as Record<string, unknown> | undefined;
      return {
        ok: false,
        ...graphErrorCodes(err),
        httpStatus: res.status,
        detail: String(err?.message ?? raw).slice(0, 300),
      };
    }
    const messages = data.messages as Array<Record<string, unknown>> | undefined;
    const messageId = messages?.[0]?.id != null
      ? String(messages[0].id)
      : undefined;
    return { ok: true, messageId, httpStatus: res.status };
  } catch (e) {
    return {
      ok: false,
      detail: e instanceof Error ? e.message : String(e),
    };
  }
}

export async function cloudSendTemplate(args: {
  userId: string;
  phoneNumberId: string;
  toE164Digits: string;
  templateName: string;
  languageCode?: string;
  bodyParameters?: string[];
}): Promise<CloudSendResult> {
  const token = await resolveGraphAccessToken({
    userId: args.userId,
    phoneNumberId: args.phoneNumberId,
  });
  if (!token) return { ok: false, detail: 'cloud_token_missing' };
  const phoneId = args.phoneNumberId.trim();
  if (!phoneId) return { ok: false, detail: 'cloud_phone_number_id_missing' };
  const to = args.toE164Digits.replace(/\D/g, '');
  if (to.length < 10) return { ok: false, detail: 'invalid_phone' };

  const components: Record<string, unknown>[] = [];
  if (args.bodyParameters && args.bodyParameters.length > 0) {
    components.push({
      type: 'body',
      parameters: args.bodyParameters.map((text) => ({ type: 'text', text })),
    });
  }

  try {
    const res = await fetch(`${GRAPH}/${encodeURIComponent(phoneId)}/messages`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        to,
        type: 'template',
        template: {
          name: args.templateName,
          language: { code: args.languageCode ?? 'ar' },
          ...(components.length ? { components } : {}),
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
      const err = data.error as Record<string, unknown> | undefined;
      return {
        ok: false,
        ...graphErrorCodes(err),
        httpStatus: res.status,
        detail: String(err?.message ?? raw).slice(0, 300),
      };
    }
    const messages = data.messages as Array<Record<string, unknown>> | undefined;
    return {
      ok: true,
      messageId: messages?.[0]?.id != null ? String(messages[0].id) : undefined,
      httpStatus: res.status,
    };
  } catch (e) {
    return {
      ok: false,
      detail: e instanceof Error ? e.message : String(e),
    };
  }
}

export type CloudMediaUploadResult = CloudSendResult & { mediaId?: string };

/** رفع ملف إلى Graph ثم استخدام معرّفه في رسالة document. */
export async function cloudUploadMedia(args: {
  userId: string;
  phoneNumberId: string;
  bytes: Uint8Array;
  mimeType: string;
  filename: string;
}): Promise<CloudMediaUploadResult> {
  const token = await resolveGraphAccessToken({
    userId: args.userId,
    phoneNumberId: args.phoneNumberId,
  });
  if (!token) return { ok: false, detail: 'cloud_token_missing' };
  const phoneId = args.phoneNumberId.trim();
  if (!phoneId) return { ok: false, detail: 'cloud_phone_number_id_missing' };
  if (!args.bytes.length) return { ok: false, detail: 'empty_file' };

  try {
    const form = new FormData();
    form.append('messaging_product', 'whatsapp');
    form.append('type', args.mimeType);
    const fileBytes = new Uint8Array(args.bytes);
    form.append(
      'file',
      new Blob([fileBytes], { type: args.mimeType }),
      args.filename,
    );
    const res = await fetch(`${GRAPH}/${encodeURIComponent(phoneId)}/media`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: form,
    });
    const raw = await res.text();
    let data: Record<string, unknown> = {};
    try {
      data = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      /* ignore */
    }
    if (!res.ok) {
      const err = data.error as Record<string, unknown> | undefined;
      return {
        ok: false,
        ...graphErrorCodes(err),
        httpStatus: res.status,
        detail: String(err?.message ?? raw).slice(0, 300),
      };
    }
    const mediaId = data.id != null ? String(data.id) : '';
    if (!mediaId) return { ok: false, detail: 'media_id_missing' };
    return { ok: true, mediaId, httpStatus: res.status };
  } catch (e) {
    return {
      ok: false,
      detail: e instanceof Error ? e.message : String(e),
    };
  }
}

/** مستند بلا نص مرافِق — للـ PDF بعد صمت المحادثة. */
export async function cloudSendDocument(args: {
  userId: string;
  phoneNumberId: string;
  toE164Digits: string;
  mediaId: string;
  filename: string;
}): Promise<CloudSendResult> {
  const token = await resolveGraphAccessToken({
    userId: args.userId,
    phoneNumberId: args.phoneNumberId,
  });
  if (!token) return { ok: false, detail: 'cloud_token_missing' };
  const phoneId = args.phoneNumberId.trim();
  if (!phoneId) return { ok: false, detail: 'cloud_phone_number_id_missing' };
  const to = args.toE164Digits.replace(/\D/g, '');
  if (to.length < 10) return { ok: false, detail: 'invalid_phone' };
  const mediaId = args.mediaId.trim();
  const filename = args.filename.trim() || 'card.pdf';
  if (!mediaId) return { ok: false, detail: 'media_id_missing' };

  try {
    const res = await fetch(`${GRAPH}/${encodeURIComponent(phoneId)}/messages`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to,
        type: 'document',
        document: { id: mediaId, filename },
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
      const err = data.error as Record<string, unknown> | undefined;
      return {
        ok: false,
        ...graphErrorCodes(err),
        httpStatus: res.status,
        detail: String(err?.message ?? raw).slice(0, 300),
      };
    }
    const messages = data.messages as Array<Record<string, unknown>> | undefined;
    return {
      ok: true,
      messageId: messages?.[0]?.id != null ? String(messages[0].id) : undefined,
      httpStatus: res.status,
    };
  } catch (e) {
    return {
      ok: false,
      detail: e instanceof Error ? e.message : String(e),
    };
  }
}
