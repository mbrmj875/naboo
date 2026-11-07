/**
 * إرسال عبر whats360.live (API خارجي — جلسة واتساب، ليس Meta Cloud API).
 */

const DEFAULT_BASE = 'https://whats360.live';

export type Whats360SendResult = {
  ok: boolean;
  messageId?: string;
  detail?: string;
  httpStatus?: number;
};

export type Whats360Credentials = {
  token: string;
  instanceId: string;
  errorAr?: string;
};

function baseUrl(): string {
  return (Deno.env.get('WHATS360_BASE_URL') ?? DEFAULT_BASE).replace(/\/$/, '');
}

/** يحول أرقام العراق/الدولية إلى jid واتساب. */
export function toWhats360Jid(digits: string): string | null {
  const d = String(digits).replace(/\D/g, '');
  if (d.length < 10) return null;
  return `${d}@s.whatsapp.net`;
}

/**
 * يقبل توكن + instance، أو لصق رابط send-text بالخطأ ويستخرج الحقول.
 */
export function parseWhats360Credentials(args: {
  token?: string;
  instanceId?: string;
}): Whats360Credentials {
  let token = String(args.token ?? '').trim();
  let instanceId = String(args.instanceId ?? '').trim();

  const blob = [token, instanceId].filter(Boolean).join('\n');
  const urlMatch = blob.match(/https?:\/\/[^\s]+/i);
  if (urlMatch) {
    try {
      const u = new URL(urlMatch[0]);
      const qToken = u.searchParams.get('token');
      const qInstance = u.searchParams.get('instance_id');
      if (qToken && (!token || token.startsWith('http'))) {
        token = qToken.trim();
      }
      if (qInstance) {
        instanceId = qInstance.trim();
      }
    } catch {
      /* ignore bad url */
    }
  }

  // أحياناً يُلصق المستخدم الحقلين معكوسين
  if (
    (!token || token.length < 20) &&
    instanceId.length >= 40 &&
    !instanceId.includes('://')
  ) {
    token = instanceId;
    instanceId = '';
  }

  if (!token || token.length < 20) {
    return {
      token: '',
      instanceId: '',
      errorAr: 'التوكن غير صالح. انسخ Access Token فقط من لوحة واتس360.',
    };
  }

  if (
    !instanceId ||
    instanceId.length < 3 ||
    /^INSTANCE_ID$/i.test(instanceId) ||
    instanceId.includes('://') ||
    instanceId.toLowerCase().includes('send-text') ||
    /^\d{10,15}$/.test(instanceId)
  ) {
    return {
      token,
      instanceId: '',
      errorAr:
        'معرّف الجهاز غير صالح. لا تستخدم رقم الهاتف. المطلوب مثل: device_xxxxxx (من رابط إرسال الرسائل بعد instance_id=).',
    };
  }

  return { token, instanceId };
}

export async function whats360SendText(args: {
  token: string;
  instanceId: string;
  toDigits: string;
  message: string;
}): Promise<Whats360SendResult> {
  const parsed = parseWhats360Credentials({
    token: args.token,
    instanceId: args.instanceId,
  });
  if (parsed.errorAr || !parsed.token || !parsed.instanceId) {
    return {
      ok: false,
      detail: parsed.errorAr ?? 'whats360_credentials_invalid',
    };
  }

  const msg = args.message.trim();
  if (!msg) return { ok: false, detail: 'empty_message' };

  const jid = toWhats360Jid(args.toDigits);
  if (!jid) return { ok: false, detail: 'invalid_phone' };

  const url = new URL(`${baseUrl()}/api/v1/send-text`);
  url.searchParams.set('token', parsed.token);
  url.searchParams.set('instance_id', parsed.instanceId);
  url.searchParams.set('jid', jid);
  url.searchParams.set('msg', msg);

  try {
    const res = await fetch(url.toString(), { method: 'GET' });
    const raw = await res.text();
    let data: Record<string, unknown> = {};
    try {
      data = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      /* plain text */
    }

    const explicitFail =
      data.success === false ||
      data.ok === false ||
      (typeof data.error === 'string' && data.error.length > 0);

    const success =
      res.ok &&
      !explicitFail &&
      (data.success === true ||
        data.ok === true ||
        data.status === 'success' ||
        String(data.status ?? '').toLowerCase() === 'ok' ||
        (Object.keys(data).length === 0 && res.ok) ||
        (res.ok &&
          raw.length > 0 &&
          !String(raw).toLowerCase().includes('error')));

    if (!success) {
      const err = data.error ?? data.message ?? data.detail ?? raw;
      return {
        ok: false,
        httpStatus: res.status,
        detail: String(err).slice(0, 300),
      };
    }

    const messageId =
      data.message_id != null
        ? String(data.message_id)
        : data.id != null
        ? String(data.id)
        : undefined;

    return { ok: true, messageId, httpStatus: res.status };
  } catch (e) {
    return {
      ok: false,
      detail: e instanceof Error ? e.message : String(e),
    };
  }
}
