/**
 * إشعار إيميل لمالك الحساب — أي مستأجر عبر إيميله المسجّل في auth.users.
 * يستخدم مرحّل SMTP / Resend فقط — بدون جسر Auth (يكسر رمز الدخول).
 */
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { writeClient } from '../whatsapp-gateway/admin_client.ts';
import {
  templateStatusEmailCopy,
  type TemplateMailKind,
  waDropEmailCopy,
  waLinkEmailCopy,
  waMethodFromProvider,
  waUnlinkEmailCopy,
  welcomeEmailCopy,
  westernPhone,
  type WaMailMethod,
} from './owner_email_copy.ts';

const EMAIL_COOLDOWN_MS = 90_000;

export type OwnerEmailKind = string;

async function resolveOwnerEmail(
  sb: SupabaseClient,
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

async function isEmailCooledDown(
  sb: SupabaseClient,
  userId: string,
  kind: string,
  cooldownMs = EMAIL_COOLDOWN_MS,
): Promise<boolean> {
  const { data } = await sb
    .from('whatsapp_diagnostic_events')
    .select('created_at')
    .eq('user_id', userId)
    .eq('event_type', 'owner_email')
    .eq('reason_code', kind)
    .eq('outcome', 'sent')
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!data?.created_at) return false;
  const t = Date.parse(String(data.created_at));
  if (!Number.isFinite(t)) return false;
  return Date.now() - t < cooldownMs;
}

async function logOwnerEmail(
  sb: SupabaseClient,
  args: {
    userId: string;
    instanceName: string;
    kind: OwnerEmailKind;
    outcome: string;
    detail: string;
    severity?: 'info' | 'warn' | 'error';
  },
): Promise<void> {
  try {
    await sb.from('whatsapp_diagnostic_events').insert({
      user_id: args.userId,
      instance_name: args.instanceName,
      event_type: 'owner_email',
      severity: args.severity ?? 'info',
      outcome: args.outcome,
      reason_code: args.kind,
      technical_detail: args.detail.slice(0, 200),
    });
  } catch (e) {
    console.warn('owner_email diagnostic failed', e);
  }
}

async function sendOwnerMail(args: {
  to: string;
  subject: string;
  text: string;
  html?: string;
}): Promise<{ ok: boolean; detail: string }> {
  const relayUrl = (Deno.env.get('OPS_MAIL_RELAY_URL') ?? '').replace(/\/$/, '');
  const relaySecret = Deno.env.get('OPS_MAIL_RELAY_SECRET') ?? '';
  if (relayUrl && relaySecret) {
    try {
      const res = await fetch(`${relayUrl}/send`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Ops-Mail-Secret': relaySecret,
        },
        body: JSON.stringify({
          to: args.to,
          subject: args.subject,
          text: args.text,
        }),
      });
      const body = await res.text();
      if (res.ok) return { ok: true, detail: `relay:${args.to}` };
      // fall through to Resend
      console.warn('owner_email relay failed', body.slice(0, 120));
    } catch (e) {
      console.warn('owner_email relay err', e);
    }
  }

  const apiKey = Deno.env.get('RESEND_API_KEY') ?? '';
  if (apiKey) {
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
          ...(args.html ? { html: args.html } : {}),
        }),
      });
      const body = await res.text();
      return {
        ok: res.ok,
        detail: res.ok ? `resend:${args.to}` : body.slice(0, 200),
      };
    } catch (e) {
      return { ok: false, detail: `resend_err:${String(e).slice(0, 160)}` };
    }
  }

  return {
    ok: false,
    detail: 'mail_transport_missing_no_auth_bridge',
  };
}

/**
 * يرسل إيميل للمالك المسجّل — يعمل لكل المستخدمين وليس لحساب واحد.
 */
export async function notifyOwnerEmail(
  sb: SupabaseClient,
  args: {
    userId: string;
    instanceName: string;
    kind: OwnerEmailKind;
    subject: string;
    bodyAr: string;
  },
): Promise<{ sent: boolean; detail: string }> {
  const db = writeClient(sb);
  try {
    if (await isEmailCooledDown(db, args.userId, args.kind)) {
      await logOwnerEmail(db, {
        userId: args.userId,
        instanceName: args.instanceName,
        kind: args.kind,
        outcome: 'cooldown',
        detail: 'skipped_cooldown',
        severity: 'info',
      });
      return { sent: false, detail: 'cooldown' };
    }

    const to = await resolveOwnerEmail(db, args.userId);
    if (!to) {
      await logOwnerEmail(db, {
        userId: args.userId,
        instanceName: args.instanceName,
        kind: args.kind,
        outcome: 'no_email',
        detail: 'auth.users.email missing',
        severity: 'warn',
      });
      return { sent: false, detail: 'no_owner_email' };
    }

    await logOwnerEmail(db, {
      userId: args.userId,
      instanceName: args.instanceName,
      kind: args.kind,
      outcome: 'attempt',
      detail: `sending_to_${to.split('@')[1] ?? 'unknown'}`,
      severity: 'info',
    });

    const result = await sendOwnerMail({
      to,
      subject: args.subject,
      text: args.bodyAr,
    });

    await logOwnerEmail(db, {
      userId: args.userId,
      instanceName: args.instanceName,
      kind: args.kind,
      outcome: result.ok ? 'sent' : 'failed',
      detail: result.detail,
      severity: result.ok ? 'info' : 'error',
    });

    return { sent: result.ok, detail: result.detail };
  } catch (e) {
    const detail = `exception:${String(e).slice(0, 160)}`;
    await logOwnerEmail(db, {
      userId: args.userId,
      instanceName: args.instanceName,
      kind: args.kind,
      outcome: 'exception',
      detail,
      severity: 'error',
    });
    return { sent: false, detail };
  }
}

export function connectedEmailCopy(phone: string | null): {
  subject: string;
  bodyAr: string;
} {
  const card = waLinkEmailCopy({ method: 'qr', phone });
  return { subject: card.subject, bodyAr: card.text };
}

export function disconnectedEmailCopy(args: {
  permanent: boolean;
  cause: string | null;
}): { subject: string; bodyAr: string } {
  const card = waDropEmailCopy({
    permanent: args.permanent,
    method: 'qr',
  });
  return { subject: card.subject, bodyAr: card.text };
}

type DeliverMode = 'always' | 'cooldown' | 'once';

async function hasSentReason(
  sb: SupabaseClient,
  userId: string,
  reasonCode: string,
): Promise<boolean> {
  const { data } = await sb
    .from('whatsapp_diagnostic_events')
    .select('id')
    .eq('user_id', userId)
    .eq('event_type', 'owner_email')
    .eq('reason_code', reasonCode)
    .eq('outcome', 'sent')
    .limit(1)
    .maybeSingle();
  return Boolean(data?.id);
}

async function hasRecentUnlink(
  sb: SupabaseClient,
  userId: string,
): Promise<boolean> {
  const since = new Date(Date.now() - 3 * 60_000).toISOString();
  const { data } = await sb
    .from('whatsapp_diagnostic_events')
    .select('id')
    .eq('user_id', userId)
    .eq('event_type', 'owner_email')
    .eq('outcome', 'sent')
    .like('reason_code', 'wa_unlink:%')
    .gte('created_at', since)
    .limit(1);
  return (data?.length ?? 0) > 0;
}

/** إرسال بطاقة مع سجل. الفشل لا يُرمى للمتصل. */
export async function deliverOwnerCard(
  sb: SupabaseClient,
  args: {
    userId: string;
    instanceName: string;
    reasonCode: string;
    subject: string;
    text: string;
    html: string;
    mode: DeliverMode;
  },
): Promise<{ sent: boolean; detail: string }> {
  const reason = args.reasonCode.slice(0, 120);
  const instance = args.instanceName.slice(0, 120) || 'owner';
  const db = writeClient(sb);
  try {
    if (args.mode === 'once' && await hasSentReason(db, args.userId, reason)) {
      return { sent: false, detail: 'already_sent' };
    }
    if (
      args.mode === 'cooldown' &&
      await isEmailCooledDown(db, args.userId, reason)
    ) {
      return { sent: false, detail: 'cooldown' };
    }
    const to = await resolveOwnerEmail(db, args.userId);
    if (!to) {
      await logOwnerEmail(db, {
        userId: args.userId,
        instanceName: instance,
        kind: reason,
        outcome: 'no_email',
        detail: 'auth.users.email missing',
        severity: 'warn',
      });
      return { sent: false, detail: 'no_owner_email' };
    }
    const result = await sendOwnerMail({
      to,
      subject: args.subject,
      text: args.text,
      html: args.html,
    });
    await logOwnerEmail(db, {
      userId: args.userId,
      instanceName: instance,
      kind: reason,
      outcome: result.ok ? 'sent' : 'failed',
      detail: result.ok ? `domain:${to.split('@')[1] ?? 'unknown'}` : result.detail,
      severity: result.ok ? 'info' : 'error',
    });
    return { sent: result.ok, detail: result.detail };
  } catch (e) {
    console.warn('owner card email failed', String(e).slice(0, 160));
    return { sent: false, detail: 'exception' };
  }
}

export async function notifyWaBound(
  sb: SupabaseClient,
  args: {
    userId: string;
    instanceName: string;
    provider: string;
    phone?: string | null;
    flapCooldown?: boolean;
    /** مرة واحدة لهذا الرقم والطريقة. يُستعمل عند إعادة فتح ربط جاهز لم تُرسل له رسالة. */
    once?: boolean;
  },
): Promise<{ sent: boolean; detail: string }> {
  const method = waMethodFromProvider(args.provider);
  const phone = westernPhone(args.phone);
  const built = waLinkEmailCopy({ method, phone });
  const reason = `wa_link:${method}:${phone ?? 'none'}`;
  const mode = args.once
    ? 'once'
    : args.flapCooldown
    ? 'cooldown'
    : 'always';
  return await deliverOwnerCard(sb, {
    userId: args.userId,
    instanceName: args.instanceName,
    reasonCode: reason,
    subject: built.subject,
    text: built.text,
    html: built.html,
    mode,
  });
}

export async function notifyWaUnbound(
  sb: SupabaseClient,
  args: {
    userId: string;
    instanceName: string;
    provider: string;
    phone?: string | null;
  },
): Promise<{ sent: boolean; detail: string }> {
  const method = waMethodFromProvider(args.provider);
  const built = waUnlinkEmailCopy({ method, phone: args.phone });
  return await deliverOwnerCard(sb, {
    userId: args.userId,
    instanceName: args.instanceName,
    reasonCode: `wa_unlink:${method}`,
    subject: built.subject,
    text: built.text,
    html: built.html,
    mode: 'always',
  });
}

export async function notifyWaDrop(
  sb: SupabaseClient,
  args: {
    userId: string;
    instanceName: string;
    provider?: string | null;
    permanent: boolean;
  },
): Promise<{ sent: boolean; detail: string }> {
  if (await hasRecentUnlink(writeClient(sb), args.userId)) {
    return { sent: false, detail: 'skipped_after_user_unlink' };
  }
  const method: WaMailMethod = waMethodFromProvider(args.provider ?? 'qr');
  const built = waDropEmailCopy({ permanent: args.permanent, method });
  return await deliverOwnerCard(sb, {
    userId: args.userId,
    instanceName: args.instanceName,
    reasonCode: args.permanent ? 'wa_drop:permanent' : 'wa_drop:temporary',
    subject: built.subject,
    text: built.text,
    html: built.html,
    mode: 'cooldown',
  });
}

export async function notifyTemplateStatusEmail(
  sb: SupabaseClient,
  args: {
    userId: string;
    provider: string;
    templateName: string;
    language: string;
    templateKey?: string | null;
    kind: TemplateMailKind;
  },
): Promise<{ sent: boolean; detail: string }> {
  const built = templateStatusEmailCopy({
    kind: args.kind,
    templateKey: args.templateKey,
    templateName: args.templateName,
    language: args.language,
  });
  const reason =
    `tpl:${args.provider}:${args.templateName}:${args.language}:${args.kind}`;
  return await deliverOwnerCard(sb, {
    userId: args.userId,
    instanceName: `template:${args.templateName}`.slice(0, 120),
    reasonCode: reason,
    subject: built.subject,
    text: built.text,
    html: built.html,
    mode: 'once',
  });
}

export { welcomeEmailCopy };

/** أحداث WAHA التي تعني نجاح مسح QR / اكتمال الاقتران. */
export function isQrPairSuccessEvent(
  rawEvent: string,
  body: Record<string, unknown>,
): boolean {
  const blob = [
    rawEvent,
    String(body.event ?? ''),
    String(body.type ?? ''),
    JSON.stringify(body.payload ?? {}).slice(0, 300),
    JSON.stringify(body.data ?? {}).slice(0, 300),
  ]
    .join(' ')
    .toLowerCase();
  return (
    blob.includes('pairsuccess') ||
    blob.includes('pair_success') ||
    blob.includes('connectedevent') ||
    blob.includes('gows.connected') ||
    blob.includes('events.pairsuccess')
  );
}
