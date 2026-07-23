import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

export type DiagSeverity = 'info' | 'warn' | 'error';

export type DiagEventInput = {
  userId: string;
  instanceName: string;
  eventType: string;
  severity?: DiagSeverity;
  connectionState?: string | null;
  providerMessageId?: string | null;
  correlationId?: string | null;
  shopPhone?: string | null;
  recipientPhone?: string | null;
  recipientJidType?: 'phone' | 'lid' | 'unknown' | null;
  outcome?: string | null;
  reasonCode?: string | null;
  technicalDetail?: string | null;
  suggestedAction?: string | null;
  meta?: Record<string, unknown> | null;
};

/** اقتراحات عربية ثابتة حسب reason_code. */
export function suggestedActionFor(reasonCode: string | null | undefined): string {
  const r = (reasonCode ?? '').toLowerCase();
  if (!r) return 'راجع سجل التشخيص والحالة الحية للجلسة.';
  if (r.includes('same_as_shop')) {
    return 'أدخل رقم زبون مختلف عن رقم واتساب المحل المربوط.';
  }
  if (r.includes('invalid_phone') || r.includes('number_not_on')) {
    return 'تحقق من رقم الزبون (صيغة عراقية صحيحة ووجوده على واتساب).';
  }
  if (r.includes('removed') || r.includes('instance_not_found')) {
    return 'الجلسة محذوفة — أعد مسح QR مرة واحدة من هاتف المحل واترك الجلسة.';
  }
  if (r.includes('disconnected') || r.includes('not_open') || r.includes('515') || r.includes('503')) {
    return 'واتساب أسقط الجهاز المرتبط — أعد الربط مرة واحدة وتجنّب الاستخدام اليدوي المكثّف على نفس الهاتف.';
  }
  if (r.includes('none_timeout') || r.includes('lid')) {
    return 'التسليم معلّق/@lid — اختبر برقم هاتف آخر؛ راقب نسبة فشل lid أسبوعياً.';
  }
  if (r.includes('timeout')) {
    return 'انتهت مهلة السيرفر — أعد المحاولة؛ إن تكرر افحص Evolution/الشبكة.';
  }
  if (r.includes('rate_limited')) {
    return 'تم تجاوز حد الفصل/الإرسال — انتظر ثم أعد المحاولة.';
  }
  return 'راجع السبب التقني في السجل؛ إن استمر افتح تشخيص الحساب.';
}

export function jidTypeFromRemote(remoteJid: string | null | undefined): 'phone' | 'lid' | 'unknown' {
  const j = (remoteJid ?? '').toLowerCase();
  if (j.includes('@lid')) return 'lid';
  if (j.includes('@s.whatsapp.net')) return 'phone';
  return 'unknown';
}

export function newCorrelationId(): string {
  try {
    return crypto.randomUUID();
  } catch {
    return `c_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
  }
}

/** عميل service_role لكتابة التشخيص فقط (يتجاوز RLS). */
export function diagnosticAdminClient(): SupabaseClient | null {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return null;
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export async function writeDiagnostic(args: DiagEventInput): Promise<void> {
  const sb = diagnosticAdminClient();
  if (!sb) {
    console.warn('diagnostic write skipped: missing service role');
    return;
  }
  const reason = args.reasonCode ?? null;
  const suggested =
    args.suggestedAction ??
    (reason ? suggestedActionFor(reason) : null);
  try {
    const { error } = await sb.from('whatsapp_diagnostic_events').insert({
      user_id: args.userId,
      instance_name: args.instanceName,
      event_type: args.eventType,
      severity: args.severity ?? 'info',
      connection_state: args.connectionState ?? null,
      provider_message_id: args.providerMessageId ?? null,
      correlation_id: args.correlationId ?? null,
      shop_phone: args.shopPhone ?? null,
      recipient_phone: args.recipientPhone ?? null,
      recipient_jid_type: args.recipientJidType ?? null,
      outcome: args.outcome ?? null,
      reason_code: reason,
      technical_detail: (args.technicalDetail ?? '').slice(0, 500) || null,
      suggested_action: suggested,
      meta: args.meta ?? null,
    });
    if (error) console.warn('diagnostic insert failed', error);
  } catch (e) {
    console.warn('diagnostic insert failed', e);
  }
}
