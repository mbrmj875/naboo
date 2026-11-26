// المجيب الجديد (ب7): القراءة والكتابة حول responder_v2.ts.
//
// يعمل فقط حين يفعّل المالك صفحة المجيب، ومفتاح القدرة whatsapp_responder مشغول،
// ومفتاح الإيقاف مطفأ. أي فشل يرجع null فيكمل المسار القديم كما هو.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { addCost, checkBudget, recordTurnStep } from '../_shared/assistant_meter.ts';
import { chat, costMicroUsd } from '../_shared/llm.ts';
import { sanitizeForLog } from '../_shared/sanitize.ts';
import { pickArticles } from '../assistant-chat/knowledge.ts';
import { type Lesson, pickNotes } from '../assistant-chat/lessons.ts';
import { isSharedSenderPhone } from '../whatsapp-gateway/shared_sender.ts';
import { buildTenantAiContext, extractStoreBrandingFromTables, loadSnapshotTables } from './tenant_ai_context.ts';
import { buildAllowlistedFacts } from './tenant_ai_context.ts';
import { extractInventoryOffers, searchInventoryOffers } from './inventory_lookup.ts';
import { phoneVariants } from './tenant_isolation.ts';
import {
  buildFactLines,
  buildResponderSystem,
  buildResponderUser,
  type CarAlias,
  type CarSpecRow,
  effectiveTone,
  type HandoffReason,
  type HistoryTurn,
  matchCar,
  matchingOils,
  parseProfile,
  parseResponder,
  type ResponderDecision,
  type ResponderFacts,
  type ResponderProfile,
  silenceEndsAt,
  STRANGER_DAILY_SMART,
} from './responder_v2.ts';

const cache = new Map<string, { at: number; v: unknown }>();
async function cached<T>(key: string, ttlMs: number, load: () => Promise<T>): Promise<T> {
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < ttlMs) return hit.v as T;
  const v = await load();
  cache.set(key, { at: Date.now(), v });
  return v;
}

/** صفحة المجيب إن كان المجيب الجديد يعمل لهذا المحل، وإلا null. */
export async function loadActiveProfile(db: SupabaseClient, tenantUserId: string): Promise<ResponderProfile | null> {
  try {
    const gate = await cached('gate', 60_000, async () => {
      const { data } = await db.from('app_remote_config').select('config').eq('id', 1).maybeSingle();
      const a = ((data?.config as Record<string, unknown> | undefined)?.assistant ?? {}) as Record<string, unknown>;
      const caps = (a.caps ?? {}) as Record<string, unknown>;
      return a.kill !== true && caps.whatsapp_responder === true;
    });
    if (!gate) return null;
    const { data } = await db.from('whatsapp_responder_profiles').select('*').eq('tenant_user_id', tenantUserId)
      .maybeSingle();
    const p = parseProfile(data as Record<string, unknown> | null);
    return p?.enabled ? p : null;
  } catch (e) {
    console.warn('responder profile load failed', String(e).slice(0, 160));
    return null;
  }
}

/**
 * رقم خاص بمحل واحد (Meta أو QR): الغريب عليه زبون محتمل (ق81). رقم نابو
 * المشترك لا يُمس: يبقى رده العام.
 */
export async function ownNumberTenant(db: SupabaseClient, phoneNumberId: string): Promise<string | null> {
  if (!phoneNumberId.trim() || isSharedSenderPhone(phoneNumberId)) return null;
  const { data } = await db.from('tenant_whatsapp_gateways').select('user_id').eq('cloud_phone_number_id', phoneNumberId)
    .limit(2);
  return data?.length === 1 ? String(data[0].user_id) : null;
}

// ------------------------------------------------------------------ التسليم لإنسان

export async function openHandoff(db: SupabaseClient, tenantUserId: string, phone: string): Promise<boolean> {
  const { data } = await db.from('whatsapp_handoffs').select('id').eq('tenant_user_id', tenantUserId)
    .in('customer_phone', phoneVariants(phone)).is('ended_at', null).gt('ends_at', new Date().toISOString()).limit(1);
  return (data?.length ?? 0) > 0;
}

const HANDOFF_TITLE: Record<HandoffReason, string> = {
  no_answer: 'زبون ينتظر ردك',
  low_rating: 'زبون غير راضٍ ينتظر ردك',
  human: 'زبون يطلب التحدث معكم',
  fault: 'زبون يسأل عن عطل',
  angry: 'زبون منزعج ينتظر ردك',
  media: 'زبون أرسل صورة أو صوتاً',
};

/**
 * إشعار المحل عبر جدول الإشعارات (notify-dispatch يرسله). الجمهور «owner»:
 * شاشات واتساب في التطبيق بلا صلاحية خاصة بها اليوم.
 */
async function notifyShop(
  db: SupabaseClient,
  tenantUserId: string,
  n: { type: string; title: string; body: string; dedupe: string; route: string },
): Promise<void> {
  const { error } = await db.from('notifications').insert({
    user_id: tenantUserId,
    category: 'shop_event',
    type: n.type,
    priority: 'high',
    title_ar: n.title,
    body_ar: n.body.slice(0, 180),
    route: n.route,
    audience: 'owner',
    dedupe_key: n.dedupe,
  });
  if (error && error.code !== '23505') console.warn('responder notify failed', error.message);
}

export async function startHandoff(
  db: SupabaseClient,
  args: { tenantUserId: string; phone: string; reason: HandoffReason; question: string; profile: ResponderProfile },
): Promise<void> {
  const now = new Date();
  const question = sanitizeForLog(args.question, { maxLength: 300 });
  const { data, error } = await db.from('whatsapp_handoffs').insert({
    tenant_user_id: args.tenantUserId,
    customer_phone: args.phone,
    reason: args.reason,
    question,
    ends_at: silenceEndsAt(args.profile.silence, now).toISOString(),
  }).select('id').single();
  if (error) {
    console.warn('handoff insert failed', error.message);
    return;
  }
  await notifyShop(db, args.tenantUserId, {
    type: 'wa_handoff',
    title: HANDOFF_TITLE[args.reason],
    body: question || 'افتح «زبائن ينتظرون» في واتساب',
    dedupe: `wa_handoff:${data.id}`,
    route: 'app_oil_whatsapp_queue',
  });
}

/** رد المحل بنفسه (من التطبيق أو من واتساب للأعمال) ينهي الصمت. */
export async function endHandoffs(db: SupabaseClient, tenantUserId: string, phone: string, by: 'shop_reply' | 'app') {
  await db.from('whatsapp_handoffs').update({ ended_at: new Date().toISOString(), ended_by: by })
    .eq('tenant_user_id', tenantUserId).in('customer_phone', phoneVariants(phone)).is('ended_at', null);
}

export async function recordVisit(
  db: SupabaseClient,
  args: { tenantUserId: string; phone: string; name: string; car: string; request: string },
): Promise<void> {
  const { data, error } = await db.from('whatsapp_visit_requests').insert({
    tenant_user_id: args.tenantUserId,
    customer_phone: args.phone,
    customer_name: args.name.slice(0, 80),
    car: args.car.slice(0, 120),
    request: args.request.slice(0, 300),
  }).select('id').single();
  if (error) {
    if (error.code !== '23505') console.warn('visit insert failed', error.message);
    return;
  }
  await notifyShop(db, args.tenantUserId, {
    type: 'wa_visit',
    title: 'زبون قادم',
    body: [args.name, args.car, args.request].filter(Boolean).join(' · ') || 'طلب زيارة من واتساب',
    dedupe: `wa_visit:${data.id}`,
    route: 'app_oil_whatsapp_queue',
  });
}

/** الغريب: ردود ذكية محدودة في اليوم، ثم الثابتة. */
export async function strangerSmartLeft(db: SupabaseClient, tenantUserId: string, phone: string): Promise<boolean> {
  const since = new Date(Date.now() - 24 * 3600_000).toISOString();
  const { count } = await db.from('whatsapp_message_logs').select('id', { count: 'exact', head: true })
    .eq('tenant_user_id', tenantUserId).eq('template_key', 'rating_auto_reply').not('assistant_turn_id', 'is', null)
    .in('to_phone', phoneVariants(phone)).gte('created_at', since);
  return (count ?? 0) < STRANGER_DAILY_SMART;
}

// ------------------------------------------------------------------ المعرفة المشتركة

async function loadShared(db: SupabaseClient) {
  return await cached('shared', 10 * 60_000, async () => {
    const [specs, aliases, articles, lessons] = await Promise.all([
      db.from('assistant_car_specs').select(
        'make,model,year_from,year_to,oil_capacity_l,viscosity_primary,viscosity_alt,oil_spec,confidence,locked',
      ).limit(2000),
      db.from('assistant_car_aliases').select('alias_norm,make,model').limit(3000),
      db.from('assistant_knowledge').select('id,kind,title,body,keywords').eq('published', true)
        .in('audience', ['whatsapp', 'both']).limit(300),
      // ق89: دروس المجيب وحدها. درس داخلي لا يصل هنا أبداً.
      db.from('assistant_lessons').select('id,kind,topic,trigger_text,body').eq('audience', 'whatsapp')
        .eq('status', 'active').is('tenant_id', null).limit(200),
    ]);
    return {
      specs: (specs.data ?? []) as CarSpecRow[],
      aliases: (aliases.data ?? []) as CarAlias[],
      articles: (articles.data ?? []) as { id: number; kind: 'library' | 'naboo'; title: string; body: string; keywords: string }[],
      lessons: (lessons.data ?? []) as Lesson[],
    };
  });
}

async function snapshotAgeHours(db: SupabaseClient, tenantUserId: string): Promise<number | null> {
  const { data } = await db.from('app_snapshots').select('updated_at').eq('user_id', tenantUserId).maybeSingle();
  const t = data?.updated_at ? Date.parse(String(data.updated_at)) : NaN;
  return Number.isFinite(t) ? (Date.now() - t) / 3600_000 : null;
}

// ------------------------------------------------------------------ الرد

export type V2Input = {
  tenantUserId: string;
  phone: string;
  message: string;
  score: number | null;
  card: Record<string, string> | null;
  employeeName: string | null;
  history: HistoryTurn[];
  stranger: boolean;
  profile: ResponderProfile;
};

export type V2Result = ResponderDecision & { turnId: string };

/** يبني الحقائق المسموحة لهذه الرسالة. مفصول ليختبره اختبار المجيب على الخادم. */
export async function buildFacts(db: SupabaseClient, i: V2Input): Promise<ResponderFacts> {
  const [tables, age, shared] = await Promise.all([
    loadSnapshotTables(db, i.tenantUserId),
    snapshotAgeHours(db, i.tenantUserId),
    loadShared(db),
  ]);
  const shop = tables
    ? buildAllowlistedFacts({
      card: i.card,
      branding: extractStoreBrandingFromTables(tables, i.employeeName),
      employeeName: i.employeeName,
    })
    : await buildTenantAiContext(db, { tenantUserId: i.tenantUserId, card: i.card, employeeName: i.employeeName });
  const offers = extractInventoryOffers(tables);
  const carText = `${i.card?.car ?? ''} ${i.card?.car_model ?? ''} ${i.message}`;
  const picked = pickNotes(shared.lessons, i.message);
  const car = i.profile.oil_advice ? matchCar(carText, shared.specs, shared.aliases) : { status: 'none' as const };
  return {
    shop: { ...shop, card: null, employeeName: null },
    card: i.card,
    profile: i.profile,
    stock: searchInventoryOffers(offers, i.message).slice(0, 5),
    snapshotAgeHours: age,
    car,
    carOils: car.status === 'verified' ? matchingOils(car.spec, offers) : [],
    articles: pickArticles(shared.articles, i.message, 2).map((a) => ({ title: a.title, body: a.body })),
    lessons: picked.map((l) => l.body),
    lessonIds: picked.map((l) => l.id),
    stranger: i.stranger,
    score: i.score,
  };
}

/**
 * رد المجيب الجديد. null = يكمل المسار القديم (الميزانية نفدت أو النموذج فشل).
 * كل رد يُسجَّل منظّفاً في assistant_turns بقناة whatsapp، ورقم الزبون لا يُحفظ.
 */
export async function respondV2(db: SupabaseClient, i: V2Input): Promise<V2Result | null> {
  const budget = await checkBudget(db, i.tenantUserId, 'whatsapp', false);
  if (budget.mode === 'exhausted') return null;

  let facts: ResponderFacts;
  try {
    facts = await buildFacts(db, i);
  } catch (e) {
    console.warn('responder facts failed', String(e).slice(0, 160));
    return null;
  }
  const now = new Date();
  const factsText = buildFactLines(facts, i.message, now).join('\n');
  const started = Date.now();
  let decision: ResponderDecision | null = null;
  let r: Awaited<ReturnType<typeof chat>>;
  try {
    r = await chat({
      messages: [
        { role: 'system', content: buildResponderSystem(effectiveTone(i.profile.tone, i.score)) },
        { role: 'user', content: buildResponderUser(facts, i.message, i.history, now) },
      ],
      effort: 'off',
      temperature: 0.5,
      maxTokens: 350,
      json: true,
    }, 9000);
    decision = parseResponder(r.text, facts, factsText);
  } catch (e) {
    console.warn('responder llm failed', String(e).slice(0, 160));
    return null;
  }

  const turnId = crypto.randomUUID();
  const cost = costMicroUsd(r.usage);
  const names = [i.card?.customer, i.employeeName].filter((n): n is string => !!n && n.trim().length > 1);
  try {
    await addCost(db, i.tenantUserId, 'whatsapp', cost);
    await recordTurnStep(db, {
      turnId,
      threadId: turnId,
      tenantId: i.tenantUserId,
      userId: null,
      channel: 'whatsapp',
      roleKey: i.stranger ? 'stranger' : 'customer',
      isOwner: false,
      routeId: null,
      appVersion: null,
      questionClean: sanitizeForLog(i.message, { names, maxLength: 600 }),
      answerClean: decision ? sanitizeForLog(decision.reply, { names, maxLength: 600 }) : null,
      tools: [
        ...(decision?.guarded ? [{ name: `guard:${decision.guarded}`, ok: false, rows: 0 }] : []),
        ...(decision?.handoff ? [{ name: `handoff:${decision.handoff}`, ok: true }] : []),
      ],
      usage: r.usage,
      costMicroUsd: cost,
      latencyMs: Date.now() - started,
      model: r.model,
      finish: decision ? 'stop' : 'rejected',
      budgetMode: budget.mode,
      hasImage: false,
      usedWeb: false,
      lessonIds: facts.lessonIds ?? [],
    });
  } catch (e) {
    console.warn('responder meter failed', String(e).slice(0, 160));
  }
  if (!decision) return null;

  if (decision.handoff) {
    await startHandoff(db, {
      tenantUserId: i.tenantUserId,
      phone: i.phone,
      reason: decision.handoff,
      question: i.message,
      profile: i.profile,
    });
  }
  if (decision.visit) {
    await recordVisit(db, {
      tenantUserId: i.tenantUserId,
      phone: i.phone,
      name: i.card?.customer ?? '',
      car: decision.visit.car || [i.card?.car, i.card?.car_model].filter(Boolean).join(' '),
      request: decision.visit.request || i.message,
    });
  }
  return { ...decision, turnId };
}
