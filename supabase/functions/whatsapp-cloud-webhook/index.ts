/**
 * ويب هوك محايد لطبقة النقل (YCloud اليوم).
 * يحدّث القوالب/السجلات/الاتصال — Flutter يقرأ ready_state المحسوب فقط.
 */

import {
  createClient,
  type SupabaseClient,
} from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { syncTemplateStatusesForTenant } from '../whatsapp-gateway/lifecycle/template_lifecycle_service.ts';
import { applyMetaTemplateStatusUpdates } from '../whatsapp-gateway/lifecycle/template_status_email.ts';
import { completeOfficialConnect } from '../whatsapp-gateway/lifecycle/connect_service.ts';
import { mapMetaStatus, parseMetaWebhook } from './meta_payload.ts';
import {
  allowedCurrentStatusesFor,
  formatWaLogError,
  type WaMessageStatus,
} from './wa_log_error.ts';
import {
  handleInboundMessage,
  resolveTenantForInbound,
  saveInboundNote,
} from './inbound_ratings.ts';
import { sendRatingReply } from './rating_reply.ts';
import { handleColdOrUnknownInbound } from './tenant_isolation.ts';
import { touchOilCardPdfIdleJob } from './pdf_jobs.ts';
import { looksLikePdfFileRequest } from './inbound_intent.ts';
import { readMetaHubSignatureHeader } from './meta_hub_signature.ts';
import {
  authenticateWebhook,
  canBindFromWebhook,
  isAuthorizedBackfill,
  rejectionLogFields,
  signatureRequired,
} from './webhook_auth.ts';

Deno.serve(async (req) => {
  // Meta / Dualhook webhook verification: GET must echo hub.challenge as raw text.
  if (req.method === 'GET') {
    const url = new URL(req.url);
    const mode = url.searchParams.get('hub.mode');
    const token = url.searchParams.get('hub.verify_token');
    const challenge = url.searchParams.get('hub.challenge');
    const expected =
      Deno.env.get('META_WEBHOOK_VERIFY_TOKEN')?.trim() ||
      Deno.env.get('DUALHOOK_WEBHOOK_VERIFY_TOKEN')?.trim() ||
      Deno.env.get('WHATSAPP_CLOUD_WEBHOOK_VERIFY_TOKEN')?.trim() ||
      '';
    if (mode === 'subscribe' && challenge) {
      // Dualhook/Meta: يجب إرجاع challenge كنص خام.
      // التحقق من التوكن اختياري صارم — التوكن في الواجهة قد يختلف عن النسخة المحفوظة.
      const strict = (Deno.env.get('META_WEBHOOK_VERIFY_STRICT') ?? '')
        .trim()
        .toLowerCase() === 'true';
      if (strict && expected && token !== expected) {
        return new Response('forbidden', { status: 403 });
      }
      return new Response(challenge, {
        status: 200,
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      });
    }
    return new Response('ok', { status: 200 });
  }
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const rawBody = await req.text();
  const auth = await authenticateWebhook(
    rawBody,
    {
      ycloudSignature: req.headers.get('YCloud-Signature') ??
        req.headers.get('ycloud-signature'),
      metaSignature: readMetaHubSignatureHeader(req),
    },
    {
      ycloudSecret: Deno.env.get('YCLOUD_WEBHOOK_SECRET')?.trim() ||
        Deno.env.get('WHATSAPP_CLOUD_TRANSPORT_WEBHOOK_SECRET')?.trim() ||
        '',
      metaAppSecret: Deno.env.get('META_APP_SECRET')?.trim() || '',
    },
  );

  if (auth.source === 'none') {
    const mayPassUnsigned = auth.reason === 'missing_signature' && (
      !signatureRequired(Deno.env.get('WEBHOOK_REQUIRE_SIGNATURE')) ||
      isAuthorizedBackfill(
        rawBody,
        req.headers.get('x-ops-token'),
        Deno.env.get('REPLY_BACKFILL_TOKEN'),
      )
    );
    if (!mayPassUnsigned) {
      console.warn(
        'webhook rejected',
        rejectionLogFields(auth.reason, rawBody, req.headers.get('user-agent')),
      );
      return Response.json({ ok: false, error: auth.reason }, { status: 401 });
    }
  }

  let event: Record<string, unknown>;
  try {
    event = JSON.parse(rawBody) as Record<string, unknown>;
  } catch {
    return Response.json({ ok: false, error: 'invalid_json' }, { status: 400 });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // استدراك رسائل بلا رد (حد الحصة القديم / فشل سابق).
  if (String(event.ops ?? '') === 'backfill_unanswered') {
    const setup = Deno.env.get('REPLY_BACKFILL_TOKEN')?.trim();
    const got = req.headers.get('x-ops-token')?.trim() || '';
    if (!setup || got !== setup) {
      return Response.json({ ok: false, error: 'unauthorized' }, { status: 401 });
    }
    return Response.json(await backfillUnanswered(supabase));
  }

  logWatchedMetaFields(event);
  const meta = parseMetaWebhook(event);
  if (meta.isMeta) {
    return Response.json(await handleMetaWebhook(supabase, meta));
  }

  const type = String(event.type ?? event.event ?? '').toLowerCase();

  // اكتمال الربط / ربط WABA إن وُجدت حقول معروفة
  const wabaId = String(
    event.wabaId ??
      (event.whatsappBusinessAccount as Record<string, unknown> | undefined)
        ?.id ??
      '',
  ).trim();
  const phoneNumberId = String(
    event.phoneNumberId ??
      (event.whatsappPhoneNumber as Record<string, unknown> | undefined)?.id ??
      '',
  ).trim();
  const fromPhone = String(
    event.phoneNumber ??
      event.from ??
      (event.whatsappPhoneNumber as Record<string, unknown> | undefined)
        ?.phoneNumber ??
      '',
  ).trim();
  const tenantHint = String(
    event.externalId ?? event.tenantUserId ?? event.metadata ?? '',
  ).trim();

  if (
    canBindFromWebhook(auth.source) &&
    (type.includes('bind') || type.includes('connect') ||
      type.includes('phone')) &&
    (wabaId || phoneNumberId || fromPhone) &&
    tenantHint.includes('-')
  ) {
    await completeOfficialConnect(supabase, {
      tenantUserId: tenantHint,
      wabaId: wabaId || undefined,
      phoneNumberId: phoneNumberId || undefined,
      fromPhoneE164: fromPhone || undefined,
    });
  }

  // تحديث حالة رسالة
  const msg = (event.whatsappMessage ?? event.data ?? event) as Record<
    string,
    unknown
  >;
  const providerMessageId = String(msg.id ?? event.id ?? '').trim();
  const statusRaw = String(msg.status ?? event.status ?? '').toLowerCase();
  if (providerMessageId && statusRaw) {
    await writeMonotonicMessageStatus(
      supabase,
      providerMessageId,
      mapMetaStatus(statusRaw),
    );
  }

  // مزامنة قوالب عند أحداث القالب
  if (type.includes('template') && tenantHint.includes('-')) {
    await syncTemplateStatusesForTenant(supabase, tenantHint);
  }

  return Response.json({ ok: true });
});

/** يسجّل أسماء حقول التعايش فقط، بلا محتوى الرسائل. */
function logWatchedMetaFields(event: Record<string, unknown>): void {
  const watched = new Set([
    'account_update',
    'history',
    'smb_app_state_sync',
    'smb_message_echoes',
  ]);
  const seen: string[] = [];
  const entries = Array.isArray(event.entry) ? event.entry : [];
  for (const entryRaw of entries) {
    const entry = (entryRaw ?? {}) as Record<string, unknown>;
    const changes = Array.isArray(entry.changes) ? entry.changes : [];
    for (const changeRaw of changes) {
      const change = (changeRaw ?? {}) as Record<string, unknown>;
      const field = String(change.field ?? '');
      if (!watched.has(field)) continue;
      const value = (change.value ?? {}) as Record<string, unknown>;
      const eventName = String(value.event ?? '');
      seen.push(eventName ? `${field}:${eventName}` : field);
    }
  }
  if (seen.length > 0) {
    console.info('meta webhook watched fields', seen.join(','));
  }
}

/** لا يخفض «وصلت» أو «قُرئت» إلى فشل، ويرفع الفشل إن جاء إثبات لنفس المعرّف. */
async function writeMonotonicMessageStatus(
  supabase: SupabaseClient,
  providerMessageId: string,
  next: WaMessageStatus,
  extra?: Record<string, unknown>,
): Promise<void> {
  const id = providerMessageId.trim();
  if (!id) return;
  await supabase
    .from('whatsapp_message_logs')
    .update({ status: next, ...(extra ?? {}) })
    .eq('provider_message_id', id)
    .in('status', allowedCurrentStatusesFor(next));
}

async function backfillUnanswered(
  supabase: SupabaseClient,
): Promise<Record<string, unknown>> {
  const since = new Date(Date.now() - 6 * 60 * 60 * 1000).toISOString();
  const { data: inbounds } = await supabase
    .from('whatsapp_inbound_messages')
    .select(
      'id, tenant_user_id, from_phone, body, provider_message_id, received_at',
    )
    .gte('received_at', since)
    .order('received_at', { ascending: true })
    .limit(40);

  let attempted = 0;
  let sent = 0;
  const details: string[] = [];

  for (const row of inbounds ?? []) {
    const tenantUserId = String(row.tenant_user_id ?? '');
    const phone = String(row.from_phone ?? '');
    const body = String(row.body ?? '').trim();
    const wamid = String(row.provider_message_id ?? '');
    if (!tenantUserId || !phone || !body || !wamid) continue;

    const receivedAt = new Date(String(row.received_at)).getTime();
    const windowEnd = new Date(receivedAt + 3 * 60 * 1000).toISOString();
    const { count } = await supabase
      .from('whatsapp_message_logs')
      .select('id', { count: 'exact', head: true })
      .eq('tenant_user_id', tenantUserId)
      .eq('template_key', 'rating_auto_reply')
      .in('to_phone', [phone, `+${phone.replace(/^\+/, '')}`])
      .gte('created_at', String(row.received_at))
      .lte('created_at', windowEnd);
    if ((count ?? 0) > 0) continue;

    const { data: gw } = await supabase
      .from('tenant_whatsapp_gateways')
      .select('cloud_phone_number_id')
      .eq('user_id', tenantUserId)
      .maybeSingle();
    const phoneNumberId = String(gw?.cloud_phone_number_id ?? '').trim();
    if (!phoneNumberId) {
      details.push(`${wamid}:no_phone_id`);
      continue;
    }

    const { data: cardRow } = await supabase
      .from('whatsapp_message_logs')
      .select('employee_name, card_payload, order_ref')
      .eq('tenant_user_id', tenantUserId)
      .in('to_phone', [phone, `+${phone.replace(/^\+/, '')}`])
      .eq('template_key', 'oil_change_card')
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    attempted++;
    const outcome = await sendRatingReply(supabase, {
      tenantUserId,
      phoneNumberId,
      toPhone: phone,
      score: null,
      hasNote: true,
      message: body,
      employeeName: cardRow?.employee_name
        ? String(cardRow.employee_name)
        : null,
      card: (cardRow?.card_payload as Record<string, string> | null) ?? null,
      orderRef: cardRow?.order_ref ? String(cardRow.order_ref) : null,
      inboundMessageId: wamid,
    });
    if (outcome.sent) {
      sent++;
      details.push(`${body.slice(0, 24)}:sent`);
    } else {
      details.push(`${body.slice(0, 24)}:${outcome.detail ?? 'fail'}`);
    }
  }

  return { ok: true, attempted, sent, details };
}

async function handleMetaWebhook(
  supabase: SupabaseClient,
  meta: ReturnType<typeof parseMetaWebhook>,
): Promise<Record<string, unknown>> {
  const tenantCache = new Map<
    string,
    Awaited<ReturnType<typeof resolveTenantForInbound>>
  >();

  const resolveCached = async (
    phoneNumberId: string,
    fromPhone: string,
  ) => {
    const cacheKey = `${phoneNumberId}|${fromPhone}`;
    if (tenantCache.has(cacheKey)) {
      return tenantCache.get(cacheKey)!;
    }
    const resolved = await resolveTenantForInbound(
      supabase,
      phoneNumberId,
      fromPhone,
    );
    tenantCache.set(cacheKey, resolved);
    return resolved;
  };

  const templateUpdates = await applyMetaTemplateStatusUpdates(
    supabase,
    meta.templateUpdates ?? [],
  );

  for (const st of meta.statuses) {
    if (!st.messageId || !st.status) continue;
    const next = mapMetaStatus(st.status) as WaMessageStatus;
    // تقدّم أحادي ذري: شرط الحالة الحالية داخل نفس UPDATE (لا قراءة ثم كتابة).
    const extra: Record<string, unknown> = {};
    if (next === 'failed') {
      const err = st.error;
      extra.error = formatWaLogError({
        source: 'meta',
        code: err?.code ?? 'unknown',
        title: err?.title ?? '',
        message: err?.message ?? '',
      });
    }
    await writeMonotonicMessageStatus(
      supabase,
      st.messageId,
      next,
      extra,
    );
  }

  let stored = 0;
  let ratings = 0;
  let unmatched = 0;
  let coldReplies = 0;
  let replies = 0;
  let skippedQuota = 0;
  let skippedOther = 0;

  for (const msg of meta.messages) {
    try {
      const resolution = await resolveCached(msg.phoneNumberId, msg.fromPhone);

      if (resolution.status !== 'bound') {
        unmatched++;
        const cold = await handleColdOrUnknownInbound(supabase, {
          phoneNumberId: msg.phoneNumberId,
          fromPhone: msg.fromPhone,
          messageId: msg.messageId,
          body: msg.body,
          messageType: msg.messageType,
          resolution: resolution.status === 'unknown'
            ? 'unknown_number'
            : 'cold_unmatched',
        });
        if (cold.stored) stored++;
        if (cold.sent) coldReplies++;
        console.warn(
          'inbound isolation',
          resolution.status,
          resolution.reason,
          msg.phoneNumberId,
        );
        continue;
      }

      const tenantUserId = resolution.tenantUserId;
      const result = await handleInboundMessage(supabase, tenantUserId, msg);
      if (result.stored) stored++;
      if (result.ratingSaved) ratings++;
      if (result.orderRef) {
        await touchOilCardPdfIdleJob(supabase, {
          tenantUserId,
          orderRef: result.orderRef,
          toPhone: msg.fromPhone,
          phoneNumberId: msg.phoneNumberId,
          cardPayload: result.cardPayload ?? null,
          immediate: looksLikePdfFileRequest(msg.body ?? ''),
        });
      }
      if (result.score == null && !result.hasNote) continue;

      const outcome = await sendRatingReply(supabase, {
        tenantUserId,
        phoneNumberId: msg.phoneNumberId,
        toPhone: msg.fromPhone,
        score: result.score ?? null,
        hasNote: result.hasNote ?? false,
        message: msg.body,
        employeeName: result.employeeName ?? null,
        card: result.cardPayload ?? null,
        orderRef: result.orderRef ?? null,
        inboundMessageId: msg.messageId,
      });
      if (outcome.sent) {
        replies++;
      } else if (outcome.detail === 'quota') {
        skippedQuota++;
      } else {
        skippedOther++;
        console.warn('auto-reply skipped', outcome.detail, msg.messageId);
      }

      if (result.score == null && outcome.isFeedback && result.note) {
        const saved = await saveInboundNote(supabase, {
          tenantUserId,
          orderRef: result.orderRef ?? null,
          employeeName: result.employeeName ?? null,
          customerPhone: msg.fromPhone,
          note: result.note,
          source: result.source ?? 'recent_card',
          inboundMessageId: result.inboundMessageId ?? null,
        });
        if (saved) ratings++;
      }
    } catch (e) {
      skippedOther++;
      console.warn(
        'inbound message handler crashed',
        msg.messageId,
        String(e).slice(0, 240),
      );
    }
  }

  return {
    ok: true,
    statuses: meta.statuses.length,
    inbound_stored: stored,
    ratings_saved: ratings,
    auto_replies: replies,
    cold_system_replies: coldReplies,
    unmatched_tenants: unmatched,
    skipped_quota: skippedQuota,
    skipped_other: skippedOther,
    template_updates: templateUpdates,
  };
}
