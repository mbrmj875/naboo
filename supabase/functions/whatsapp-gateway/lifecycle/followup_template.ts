/**
 * قالب تذكير غيار الزيت — رفع ديناميكي لكل مستأجر.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import {
  getWhatsAppProvider,
  isOfficialTemplateTransport,
  parseTransportId,
} from '../providers/registry.ts';
import { writeClient } from '../admin_client.ts';
import { maybeNotifyTemplateStatus } from './template_status_email.ts';
import type { DefaultTemplateSpec } from './default_template_registry.ts';
import { TemplateKey } from '../notifications/notification_request.ts';

export const FOLLOWUP_TEMPLATE_KEY = 'oil_change_followup';

const FOLLOWUP_TOKENS: { token: string; key: string; example: string }[] = [
  { token: '{الاسم}', key: 'customer', example: 'أحمد' },
  { token: '{المحل}', key: 'shop', example: 'مركز النور' },
  { token: '{السيارة}', key: 'car', example: 'تويوتا' },
  { token: '{آخر_قراءة}', key: 'odo_current', example: '148000 كم' },
  { token: '{القراءة_اللاحقة}', key: 'odo_next', example: '153000 كم' },
  { token: '{تاريخ_الغيار}', key: 'visit_date', example: '22-10-2026' },
];

/** يرقّم المتغيرات المستخدمة فقط {{1}}… حتى يطابق عدد الأمثلة نص ميتا. */
export function compileFollowupMeta(arabic: string): {
  body: string;
  paramKeys: string[];
  examples: string[];
} {
  let body = arabic.replace(/\n{3,}/g, '\n\n');
  const paramKeys: string[] = [];
  const examples: string[] = [];
  let n = 1;
  for (const item of FOLLOWUP_TOKENS) {
    if (!body.includes(item.token)) continue;
    body = body.split(item.token).join(`{{${n}}}`);
    paramKeys.push(item.key);
    examples.push(item.example);
    n++;
  }
  const trimmed = body.trim();
  if (/^\{\{\d+\}\}/.test(trimmed)) {
    body = `تذكير ${body}`;
  }
  if (/\{\{\d+\}\}\s*$/.test(body.trim())) {
    body = `${body.trim()} .`;
  }
  return { body: body.trim(), paramKeys, examples };
}

export function arabicFollowupToMetaBody(text: string): string {
  return compileFollowupMeta(text).body;
}

export function followupTemplateNameForTenant(tenantUserId: string): string {
  const compact = tenantUserId.replace(/-/g, '').slice(0, 8);
  return `oil_fu_${compact}`;
}

export function buildFollowupSpecFromArabic(
  arabicBody: string,
  templateName: string,
): DefaultTemplateSpec {
  const compiled = compileFollowupMeta(arabicBody);
  return {
    key: TemplateKey.oilChangeFollowup,
    name: templateName,
    language: 'ar',
    category: 'utility',
    bodyText: compiled.body,
    paramKeys: compiled.paramKeys,
    exampleBodyParams: compiled.examples,
  };
}

export async function submitFollowupTemplateForTenant(
  supabase: SupabaseClient,
  tenantUserId: string,
  bodyTemplateAr: string,
): Promise<{ ok: boolean; detail?: string; message_ar?: string; skipped?: string }> {
  const body = String(bodyTemplateAr ?? '').trim();
  if (!body) {
    return { ok: false, message_ar: 'اكتب نص الرسالة أولاً.' };
  }
  if (body.includes('{{') || body.includes('}}')) {
    return {
      ok: false,
      message_ar: 'استخدم الأزرار لإضافة المتغيرات — لا تكتب أقواس إنجليزية.',
    };
  }

  const db = writeClient(supabase);
  const { data: gate } = await db
    .from('tenant_whatsapp_gateways')
    .select('whatsapp_provider, cloud_waba_id')
    .eq('user_id', tenantUserId)
    .maybeSingle();

  const providerId = parseTransportId(gate?.whatsapp_provider);
  if (!isOfficialTemplateTransport(providerId)) {
    return {
      ok: true,
      skipped: 'qr_no_template',
      message_ar: 'تم حفظ النص. الربط بمسح الرمز لا يحتاج مراجعة ميتا.',
    };
  }

  const provider = getWhatsAppProvider(providerId);
  if (!provider?.capabilities.supportsTemplates) {
    return { ok: false, message_ar: 'طريقة الربط لا تدعم القوالب.' };
  }

  const wabaId = String(gate?.cloud_waba_id ?? '').trim();
  const templateName = followupTemplateNameForTenant(tenantUserId);
  const spec = buildFollowupSpecFromArabic(body, templateName);

  if (!wabaId) {
    return {
      ok: false,
      message_ar: 'الرقم غير مربوط بحساب واتساب رسمي. أكمل الربط ثم أعد الإرسال.',
    };
  }

  const ensured = await provider.ensureTemplate({
    tenantUserId,
    wabaId,
    templateName: spec.name,
    language: spec.language,
    category: spec.category,
    bodyText: spec.bodyText,
    exampleBodyParams: spec.exampleBodyParams,
  });

  let status: 'pending' | 'approved' | 'rejected' | 'none' = 'pending';
  let templateId: string | undefined = ensured.templateId;
  let lastError: string | null = null;

  if (!ensured.ok) {
    status = 'rejected';
    lastError = ensured.detail ?? 'meta_rejected';
  } else if (ensured.status) {
    status = ensured.status;
  }

  const remote = await provider.getTemplateStatus({
    tenantUserId,
    wabaId,
    templateName: spec.name,
    language: spec.language,
  });
  if (remote.ok && remote.status !== 'unknown' && remote.status !== 'none') {
    status = remote.status;
    templateId = remote.templateId ?? templateId;
    if (status !== 'rejected') lastError = null;
  }

  const { data: previousRow } = await db
    .from('tenant_whatsapp_templates')
    .select('status, template_id')
    .eq('tenant_user_id', tenantUserId)
    .eq('provider', providerId)
    .eq('template_name', templateName)
    .eq('language', spec.language)
    .maybeSingle();

  const now = new Date().toISOString();
  await db.from('tenant_whatsapp_templates').upsert(
    {
      tenant_user_id: tenantUserId,
      provider: providerId,
      template_key: FOLLOWUP_TEMPLATE_KEY,
      template_name: templateName,
      language: spec.language,
      category: spec.category,
      status,
      template_id: templateId ?? null,
      last_error: lastError,
      updated_at: now,
    },
    { onConflict: 'tenant_user_id,provider,template_name,language' },
  );

  await maybeNotifyTemplateStatus(db, {
    tenantUserId,
    provider: providerId,
    templateKey: FOLLOWUP_TEMPLATE_KEY,
    templateName,
    language: spec.language,
    previousStatus: previousRow?.status ? String(previousRow.status) : null,
    nextStatus: status,
    templateId: templateId ?? null,
    previousHadTemplateId: Boolean(previousRow?.template_id),
    submitFailed: !ensured.ok && status === 'rejected',
  });

  const { data: existingRule } = await db
    .from('wa_oil_followup_rules')
    .select('enabled, delay_value, delay_unit, quiet_hours')
    .eq('tenant_user_id', tenantUserId)
    .maybeSingle();

  await db.from('wa_oil_followup_rules').upsert(
    {
      tenant_user_id: tenantUserId,
      enabled: existingRule?.enabled ?? false,
      delay_value: existingRule?.delay_value ?? 3,
      delay_unit: existingRule?.delay_unit ?? 'month',
      quiet_hours: existingRule?.quiet_hours ?? true,
      body_template: body,
      updated_at: now,
    },
    { onConflict: 'tenant_user_id' },
  );

  if (!ensured.ok && status === 'rejected') {
    return {
      ok: false,
      detail: lastError ?? undefined,
      message_ar:
        'ميتا رفضت إنشاء القالب ولم يظهر في إدارة القوالب. عدّل النص ثم أعد الإرسال.',
    };
  }

  return {
    ok: true,
    message_ar: status === 'approved'
      ? 'تم اعتماد القالب. ستجده في إدارة قوالب الرقم على Meta.'
      : `أرسلنا القالب ${templateName} إلى إدارة قوالب نفس الرقم. سيظهر قيد المراجعة خلال دقائق.`,
  };
}

/** مطابق للنص الافتراضي في إعدادات التذكير داخل التطبيق. */
export const DEFAULT_FOLLOWUP_BODY_AR = 'مرحباً {الاسم}،\n' +
  'تحية طيبة من {المحل}.\n\n' +
  'سيارتكم {السيارة} صار وقت صيانة غيار الزيت.\n' +
  'آخر قراءة سجّلناها {آخر_قراءة}، والموعد التقريبي {القراءة_اللاحقة}.\n\n' +
  'إذا مناسب، نرتّب لكم موعد بالمحل.\n' +
  'أهلاً وسهلاً.';

/** قالب معتمد أو قيد المراجعة لا يُرسل مرة أخرى. */
export function followupNeedsSubmit(status: string | null | undefined): boolean {
  return status !== 'approved' && status !== 'pending';
}

/**
 * عند اكتمال ربط رقم المتجر عبر Meta يبدأ التذكير مراجعته مع قالب البطاقة،
 * حتى لا ينتظر فتح إعدادات التذكير. فشله لا يوقف الربط، ويبقى الإرسال اليدوي من الإعدادات.
 */
export async function ensureFollowupTemplateOnConnect(
  supabase: SupabaseClient,
  tenantUserId: string,
): Promise<void> {
  try {
    const db = writeClient(supabase);
    const { data: row } = await db
      .from('tenant_whatsapp_templates')
      .select('status')
      .eq('tenant_user_id', tenantUserId)
      .eq('provider', 'cloud_api')
      .eq('template_key', FOLLOWUP_TEMPLATE_KEY)
      .maybeSingle();
    if (!followupNeedsSubmit(row?.status ? String(row.status) : null)) return;

    const { data: rule } = await db
      .from('wa_oil_followup_rules')
      .select('body_template')
      .eq('tenant_user_id', tenantUserId)
      .maybeSingle();
    const body = String(rule?.body_template ?? '').trim() ||
      DEFAULT_FOLLOWUP_BODY_AR;
    const result = await submitFollowupTemplateForTenant(
      supabase,
      tenantUserId,
      body,
    );
    if (!result.ok) {
      console.warn('followup template on connect failed', result.detail);
    }
  } catch (e) {
    console.warn('followup template on connect failed', e);
  }
}

export async function loadFollowupTemplateSpec(
  supabase: SupabaseClient,
  tenantUserId: string,
): Promise<DefaultTemplateSpec | null> {
  const db = writeClient(supabase);
  const { data: gate } = await db
    .from('tenant_whatsapp_gateways')
    .select('whatsapp_provider')
    .eq('user_id', tenantUserId)
    .maybeSingle();
  const providerId = parseTransportId(gate?.whatsapp_provider);

  const { data: row } = await db
    .from('tenant_whatsapp_templates')
    .select('template_name, language, status')
    .eq('tenant_user_id', tenantUserId)
    .eq('provider', providerId)
    .eq('template_key', FOLLOWUP_TEMPLATE_KEY)
    .maybeSingle();

  if (!row || String(row.status) !== 'approved') return null;

  const { data: rule } = await db
    .from('wa_oil_followup_rules')
    .select('body_template')
    .eq('tenant_user_id', tenantUserId)
    .maybeSingle();

  const bodyAr = String(rule?.body_template ?? '').trim();
  if (!bodyAr) return null;

  return buildFollowupSpecFromArabic(
    bodyAr,
    String(row.template_name),
  );
}
