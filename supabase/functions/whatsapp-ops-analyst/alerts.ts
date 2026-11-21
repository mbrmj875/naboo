/**
 * تنبيهات واتساب Ops — إيميل الحساب المسجّل فقط.
 * القنوات: مرحّل VPS → Resend فقط.
 * لا تستخدم جسر Auth SMTP (يكسر قالب رمز الدخول).
 */
import type { Severity } from './constants.ts';

export type AlertKind = 'open' | 'escalate' | 'resolved' | 'flapping';

export type AlertResult = {
  channel: 'email' | 'telegram' | 'fcm';
  ok: boolean;
  detail: string;
};

async function logAlert(
  // deno-lint-ignore no-explicit-any
  sb: any,
  args: {
    incidentId: string;
    userId: string;
    channel: AlertResult['channel'];
    alertKind: AlertKind;
    ok: boolean;
    detail: string;
  },
): Promise<void> {
  await sb.from('whatsapp_ops_alerts').insert({
    incident_id: args.incidentId,
    user_id: args.userId,
    channel: args.channel,
    alert_kind: args.alertKind,
    ok: args.ok,
    detail: args.detail.slice(0, 500),
  });
}

async function sendViaMailRelay(args: {
  to: string;
  subject: string;
  text: string;
}): Promise<AlertResult | null> {
  const relayUrl = (Deno.env.get('OPS_MAIL_RELAY_URL') ?? '').replace(/\/$/, '');
  const secret = Deno.env.get('OPS_MAIL_RELAY_SECRET') ?? '';
  if (!relayUrl || !secret) return null;
  try {
    const res = await fetch(`${relayUrl}/send`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Ops-Mail-Secret': secret,
      },
      body: JSON.stringify({
        to: args.to,
        subject: args.subject,
        text: args.text,
      }),
    });
    const body = await res.text();
    return {
      channel: 'email',
      ok: res.ok,
      detail: res.ok
        ? `relay:${args.to}`
        : `relay_fail:${body.slice(0, 180)}`,
    };
  } catch (e) {
    return {
      channel: 'email',
      ok: false,
      detail: `relay_err:${String(e).slice(0, 180)}`,
    };
  }
}

async function sendViaResend(args: {
  to: string;
  subject: string;
  text: string;
}): Promise<AlertResult | null> {
  const apiKey = Deno.env.get('RESEND_API_KEY') ?? '';
  if (!apiKey) return null;
  const from =
    Deno.env.get('OPS_ALERT_FROM_EMAIL') ??
    'NaBoo Ops <onboarding@resend.dev>';
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from,
        to: [args.to],
        subject: args.subject,
        text: args.text,
      }),
    });
    const body = await res.text();
    return {
      channel: 'email',
      ok: res.ok,
      detail: res.ok ? `resend:${args.to}` : body.slice(0, 200),
    };
  } catch (e) {
    return { channel: 'email', ok: false, detail: String(e).slice(0, 200) };
  }
}

async function sendEmail(args: {
  to: string;
  subject: string;
  text: string;
}): Promise<AlertResult> {
  if (!args.to || !args.to.includes('@')) {
    return { channel: 'email', ok: false, detail: 'no owner email' };
  }

  const relay = await sendViaMailRelay(args);
  if (relay?.ok) return relay;

  const resend = await sendViaResend(args);
  if (resend?.ok) return resend;

  if (relay) return relay;
  if (resend) return resend;
  return {
    channel: 'email',
    ok: false,
    detail:
      'mail transport missing: set OPS_MAIL_RELAY_* or RESEND_API_KEY',
  };
}

async function resolveOwnerEmail(
  // deno-lint-ignore no-explicit-any
  sb: any,
  userId: string,
): Promise<string | null> {
  try {
    const { data } = await sb.auth.admin.getUserById(userId);
    const email = data?.user?.email;
    return email && email.includes('@') ? email.trim().toLowerCase() : null;
  } catch {
    return null;
  }
}

function buildMessage(args: {
  severity: Severity;
  alertKind: AlertKind;
  sessionName: string;
  patternKey: string;
  titleAr: string;
  summaryAr: string;
  playbookStepId: string;
}): string {
  return [
    `[NaBoo WhatsApp Ops] ${args.severity} · ${args.alertKind}`,
    `الجلسة: ${args.sessionName}`,
    `النمط: ${args.patternKey}`,
    args.titleAr,
    args.summaryAr,
    `الدليل: ${args.playbookStepId}`,
  ].join('\n');
}

/**
 * قناة واحدة فقط: إيميل الحساب المسجّل في التطبيق (auth.users.email).
 */
export async function dispatchIncidentAlerts(args: {
  // deno-lint-ignore no-explicit-any
  sb: any;
  incidentId: string;
  userId: string;
  severity: Severity;
  alertKind: AlertKind;
  sessionName: string;
  patternKey: string;
  titleAr: string;
  summaryAr: string;
  playbookStepId: string;
  forceDualChannel?: boolean;
}): Promise<{ notified: boolean; results: AlertResult[] }> {
  const text = buildMessage(args);
  const subject =
    `[${args.severity}] واتساب · ${args.titleAr}`.slice(0, 120);
  const results: AlertResult[] = [];

  const ownerEmail = await resolveOwnerEmail(args.sb, args.userId);
  if (!ownerEmail) {
    const missing: AlertResult = {
      channel: 'email',
      ok: false,
      detail: 'owner email not found on auth.users',
    };
    results.push(missing);
    await logAlert(args.sb, {
      incidentId: args.incidentId,
      userId: args.userId,
      channel: 'email',
      alertKind: args.alertKind,
      ok: false,
      detail: missing.detail,
    });
    return { notified: false, results };
  }

  const emailRes = await sendEmail({
    to: ownerEmail,
    subject,
    text,
  });
  results.push(emailRes);
  await logAlert(args.sb, {
    incidentId: args.incidentId,
    userId: args.userId,
    channel: 'email',
    alertKind: args.alertKind,
    ok: emailRes.ok,
    detail: emailRes.detail,
  });

  return { notified: emailRes.ok, results };
}
