/**
 * الرد التلقائي على رسالة الزبون بعد بطاقة الغيار.
 *
 * حجز idempotency لكل wamid يمنع الرد المزدوج عند تكرار webhook.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import {
  cloudMarkReadAndTyping,
  cloudSendText,
  humanTypingDelayMs,
  sleepMs,
} from '../whatsapp-gateway/cloud_api.ts';
import {
  buildEmployeeReply,
  buildGreetingReply,
  buildLastServiceReply,
  buildPriceReply,
  buildWarrantyMissingReply,
} from './card_faq.ts';
import {
  buildWarrantyReply,
  generateRatingReply,
} from './ai_reply.ts';
import {
  classifyInboundIntent,
  THANKS_CLOSE_REPLY,
} from './inbound_intent.ts';
import {
  autoReplyIdempotencyKey,
  autoReplyQuotaLeft,
  claimAutoReplySlot,
  loadConversationBundle,
  logAutoReply,
  looksLikeFeedback,
} from './conversation.ts';
import {
  buildContactReply,
  SENSITIVE_REFUSAL_REPLY,
} from './sensitive_topics.ts';
import { buildTenantAiContext } from './tenant_ai_context.ts';
import { lookupInventoryReply } from './inventory_lookup.ts';
import { sendOilCardPdfNow } from '../whatsapp-oil-card-pdf-cron/send_job.ts';

export type RatingReplyInput = {
  tenantUserId: string;
  phoneNumberId: string;
  toPhone: string;
  score: number | null;
  hasNote: boolean;
  employeeName: string | null;
  message?: string | null;
  card?: Record<string, string> | null;
  orderRef?: string | null;
  inboundMessageId?: string | null;
};

export type RatingReplyOutcome = {
  sent: boolean;
  isFeedback: boolean;
  detail?: string;
};

export function buildRatingReplyText(args: {
  score: number | null;
  hasNote: boolean;
  employeeName: string | null;
}): string | null {
  const { score, hasNote } = args;
  const who = (args.employeeName ?? '').trim();

  if (score == null) {
    if (!hasNote) return null;
    return 'وصلتنا ملاحظتك وراح ناخذها بنظر الاعتبار. شكراً على وقتك 🌟';
  }

  if (score >= 9) {
    const praise = who ? `راح نبلّغ ${who} بثناءك` : 'فرحانين برضاك عن الخدمة';
    return `شكراً على تقييمك ${score}/10 ⭐\n${praise}، وإحنا بالخدمة دائماً.`;
  }

  if (score >= 7) {
    return `شكراً على تقييمك ${score}/10 🙏\n` +
      'رأيك يساعدنا نتحسّن، ونشوفك بالخدمة الجاية.';
  }

  if (score >= 4) {
    return `شكراً على صراحتك (${score}/10).\n` +
      'آسفين إن الخدمة ما كانت بالمستوى، وراح نشتغل على تحسينها.';
  }

  return `نعتذر هواي عن تجربتك (${score}/10) 🙏\n` +
    'المسؤول راح يتواصل وياك ويعالج الموضوع.';
}

async function showReadAndTyping(input: RatingReplyInput): Promise<number> {
  const started = Date.now();
  const wamid = (input.inboundMessageId ?? '').trim();
  if (!wamid) return started;
  const res = await cloudMarkReadAndTyping({
    userId: input.tenantUserId,
    phoneNumberId: input.phoneNumberId,
    inboundMessageId: wamid,
  });
  if (!res.ok) {
    console.warn('mark read/typing failed', res.detail);
  }
  return started;
}

async function deliverReply(
  db: SupabaseClient,
  input: RatingReplyInput,
  body: string,
  isFeedback: boolean,
  typingStartedAt: number,
  fast: boolean,
): Promise<RatingReplyOutcome> {
  const target = humanTypingDelayMs(body, { fast });
  const elapsed = Date.now() - typingStartedAt;
  const wait = Math.max(fast ? 350 : 450, target - elapsed);
  await sleepMs(wait);

  const sent = await cloudSendText({
    userId: input.tenantUserId,
    phoneNumberId: input.phoneNumberId,
    toE164Digits: input.toPhone,
    body,
  });
  if (!sent.ok) {
    console.warn('auto-reply send failed', sent.detail);
    return { sent: false, isFeedback, detail: sent.detail ?? 'send_failed' };
  }
  await logAutoReply(db, {
    tenantUserId: input.tenantUserId,
    customerPhone: input.toPhone,
    body,
    providerMessageId: sent.messageId ?? null,
    employeeName: input.employeeName,
    orderRef: input.orderRef ?? null,
    idempotencyKey: autoReplyIdempotencyKey(input.inboundMessageId),
  });
  return { sent: true, isFeedback, detail: 'sent' };
}

export async function sendRatingReply(
  db: SupabaseClient,
  input: RatingReplyInput,
): Promise<RatingReplyOutcome> {
  const message = (input.message ?? '').trim();
  const heuristicFeedback = input.score != null || looksLikeFeedback(message);

  const fallback = buildRatingReplyText(input);
  if (!fallback && !message) {
    return { sent: false, isFeedback: false, detail: 'empty' };
  }
  if (!(await autoReplyEnabled(db, input.tenantUserId))) {
    return { sent: false, isFeedback: heuristicFeedback, detail: 'disabled' };
  }
  if (!(await autoReplyQuotaLeft(db, input.tenantUserId, input.toPhone))) {
    console.warn('auto reply quota exhausted', input.toPhone);
    return { sent: false, isFeedback: heuristicFeedback, detail: 'quota' };
  }

  // حجز فوري — أي webhook مكرر يخرج هنا بلا إرسال ثانٍ.
  const claimed = await claimAutoReplySlot(db, {
    tenantUserId: input.tenantUserId,
    customerPhone: input.toPhone,
    inboundWamid: input.inboundMessageId,
  });
  if (!claimed) {
    return { sent: false, isFeedback: false, detail: 'duplicate_claim' };
  }

  const typingStartedAt = await showReadAndTyping(input);
  const intent = classifyInboundIntent(message, input.score);

  if (intent === 'pdf_file') {
    const pdf = await sendOilCardPdfNow(db, {
      tenantUserId: input.tenantUserId,
      orderRef: input.orderRef,
      toPhone: input.toPhone,
      phoneNumberId: input.phoneNumberId,
    });
    const text = pdf === 'sent'
      ? 'حاضر، هذا ملف بطاقة الغيار.'
      : pdf === 'already'
      ? 'الملف انرسل. إذا ما شفته قلي أعيده.'
      : pdf === 'missing'
      ? 'ما لقيت ملف بطاقة غيار لهذا الرقم هسه.'
      : 'تعذّر إرسال الملف هسه. أعد الطلب بعد لحظات.';
    return await deliverReply(db, input, text, false, typingStartedAt, true);
  }

  if (intent === 'thanks') {
    return await deliverReply(
      db,
      input,
      THANKS_CLOSE_REPLY,
      false,
      typingStartedAt,
      true,
    );
  }

  if (intent === 'inventory') {
    const inventory = await lookupInventoryReply(db, {
      tenantUserId: input.tenantUserId,
      message,
    });
    if (inventory) {
      return await deliverReply(
        db,
        input,
        inventory,
        false,
        typingStartedAt,
        true,
      );
    }
  }

  if (intent === 'last_service') {
    return await deliverReply(
      db,
      input,
      buildLastServiceReply(input.card ?? null) ??
        'ما عندي بطاقة غيار محفوظة لهالرقم هسه، راح أسأل بالمحل وأردلك 🙏',
      false,
      typingStartedAt,
      true,
    );
  }

  if (intent === 'warranty') {
    const warranty = buildWarrantyReply({
      card: input.card ?? null,
      customerName: input.card?.customer,
    });
    return await deliverReply(
      db,
      input,
      warranty ?? buildWarrantyMissingReply(),
      false,
      typingStartedAt,
      true,
    );
  }

  if (intent === 'employee') {
    return await deliverReply(
      db,
      input,
      buildEmployeeReply({
        employeeName: input.employeeName,
        card: input.card ?? null,
      }) ?? 'اسم الفني ما محفوظ ببطاقتك هسه، راح أسأل بالمحل وأردلك 🙏',
      false,
      typingStartedAt,
      true,
    );
  }

  if (intent === 'visit_price') {
    return await deliverReply(
      db,
      input,
      buildPriceReply(input.card ?? null) ??
        'مبلغ الزيارة ما محفوظ عندي هسه، راح أسأل بالمحل وأردلك 🙏',
      false,
      typingStartedAt,
      true,
    );
  }

  if (intent === 'greeting') {
    return await deliverReply(
      db,
      input,
      buildGreetingReply(
        input.employeeName,
        input.card?.customer ?? null,
      ),
      false,
      typingStartedAt,
      true,
    );
  }

  if (intent === 'sensitive') {
    return await deliverReply(
      db,
      input,
      SENSITIVE_REFUSAL_REPLY,
      false,
      typingStartedAt,
      true,
    );
  }

  const allowlisted = await buildTenantAiContext(db, {
    tenantUserId: input.tenantUserId,
    card: input.card ?? null,
    employeeName: input.employeeName,
  });

  if (intent === 'contact') {
    const contact = buildContactReply(allowlisted);
    if (contact) {
      return await deliverReply(
        db,
        input,
        contact,
        false,
        typingStartedAt,
        true,
      );
    }
    const missing = allowlisted.snapshotLoaded == false
      ? 'ما قدرت أقرأ بيانات المحل هسه، أعد السؤال بعد لحظات 🙏'
      : 'عنوان المحل مو محفوظ بالإعدادات هسه، راح أسأل بالمحل وأردلك بالرقم والموقع 🙏';
    return await deliverReply(
      db,
      input,
      missing,
      false,
      typingStartedAt,
      true,
    );
  }

  if (intent === 'rating' && fallback) {
    const aiPromise = generateRatingReply({
      score: input.score,
      message,
      employeeName: input.employeeName,
      card: input.card ?? null,
      history: [],
      allowlisted,
      memorySummary: null,
    });
    const raced = await Promise.race([
      aiPromise.then((r) => r?.reply ?? null),
      sleepMs(2500).then(() => null),
    ]);
    return await deliverReply(
      db,
      input,
      raced ?? fallback,
      true,
      typingStartedAt,
      true,
    );
  }

  const { history, memorySummary } = await loadConversationBundle(db, {
    tenantUserId: input.tenantUserId,
    customerPhone: input.toPhone,
    excludeInboundMessageId: input.inboundMessageId,
  });

  const ai = await generateRatingReply({
    score: input.score,
    message,
    employeeName: input.employeeName,
    card: input.card ?? null,
    history,
    allowlisted,
    memorySummary,
  });

  const text = ai?.reply ?? fallback;
  const isFeedback = ai
    ? ai.isFeedback || input.score != null
    : heuristicFeedback;
  if (!text) return { sent: false, isFeedback, detail: 'no_text' };

  if (Date.now() - typingStartedAt > 8000) {
    await showReadAndTyping(input);
  }

  return await deliverReply(
    db,
    input,
    text,
    isFeedback,
    typingStartedAt,
    false,
  );
}

async function autoReplyEnabled(
  db: SupabaseClient,
  tenantUserId: string,
): Promise<boolean> {
  const { data } = await db
    .from('tenant_whatsapp_gateways')
    .select('rating_auto_reply')
    .eq('user_id', tenantUserId)
    .maybeSingle();
  return data?.rating_auto_reply !== false;
}
