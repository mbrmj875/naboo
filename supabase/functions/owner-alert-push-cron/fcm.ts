import type { PushAlertCandidate } from './types.ts';

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

/**
 * مفتاح تشغيل الإرسال على الخادم (خطة الإشعارات، المرحلة 0).
 * PUSH_ALLOWED_USER_IDS: قائمة معرّفات حسابات مفصولة بفاصلة، أو `*` للكل.
 * فارغ أو غير موجود = لا يُرسل شيء لأحد (يفشل مغلقا).
 */
export function pushAllowedForUser(userId: string): boolean {
  const raw = (Deno.env.get('PUSH_ALLOWED_USER_IDS') ?? '').trim();
  if (!raw) return false;
  if (raw === '*') return true;
  return raw.split(',').map((s) => s.trim()).includes(userId);
}

export async function sendFcmDataMessage(
  deviceToken: string,
  alert: PushAlertCandidate,
  userId: string,
  onInvalidToken?: () => Promise<void>,
): Promise<boolean> {
  if (!pushAllowedForUser(userId)) {
    console.info('push gated (PUSH_ALLOWED_USER_IDS)', alert.alertId);
    return false;
  }
  // اسم جديد عمدا: النسخ المنشورة القديمة من دوال واتساب تقرأ
  // FCM_SERVICE_ACCOUNT_JSON بلا مفتاح تشغيل، فتبقى صامتة.
  const saJson = Deno.env.get('PUSH_FCM_SERVICE_ACCOUNT_JSON');
  if (!saJson) {
    console.warn('PUSH_FCM_SERVICE_ACCOUNT_JSON missing — skip send');
    return false;
  }

  const sa = JSON.parse(saJson);
  const accessToken = await getGoogleAccessToken(sa);

  const projectId = sa.project_id;
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  const body = {
    message: {
      token: deviceToken,
      notification: {
        title: alert.titleAr,
        body: alert.bodyAr,
      },
      data: {
        owner_alert_id: alert.alertId,
        tenant_id: String(alert.tenantId),
        owner_action_kind: alert.actionKind,
        title_ar: alert.titleAr,
        body_ar: alert.bodyAr,
      },
      android: {
        priority: 'HIGH',
        notification: {
          channel_id: 'naboo_alerts',
        },
      },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: { aps: { sound: 'default' } },
      },
    },
  };

  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const text = await res.text();
    console.error('FCM send failed', alert.alertId, res.status, text);
    // رمز لم يعد مسجلا عند Google (التطبيق حُذف أو أعيد تثبيته): لا فائدة من تكراره.
    if (onInvalidToken && (res.status === 404 || text.includes('UNREGISTERED'))) {
      try {
        await onInvalidToken();
      } catch (e) {
        console.error('onInvalidToken failed', e);
      }
    }
    return false;
  }
  return true;
}

export async function getGoogleAccessToken(serviceAccount: {
  client_email: string;
  private_key: string;
}): Promise<string> {
  const header = btoa(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: serviceAccount.client_email,
    scope: FCM_SCOPE,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const payload = btoa(JSON.stringify(claim));
  const unsigned = `${header}.${payload}`;

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(serviceAccount.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  const signature = btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');

  const jwt = `${unsigned}.${signature}`;
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  const tokenJson = await tokenRes.json();
  return tokenJson.access_token as string;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  const raw = atob(b64);
  const buf = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i);
  return buf.buffer;
}
