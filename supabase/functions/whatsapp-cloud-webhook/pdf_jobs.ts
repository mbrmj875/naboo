/**
 * جدولة إرسال PDF بطاقة الغيار بعد 5 دقائق صمت على واتساب الرسمي.
 * لا تُجدوَل المهمة إلا بعد رد الزبون (نافذة 24 ساعة).
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

export const OIL_CARD_PDF_IDLE_MS = 5 * 60 * 1000;
export const OIL_CARD_PDF_BUCKET = 'whatsapp-oil-card-pdfs';

export type OilCardPdfJobStatus =
  | 'awaiting_inbound'
  | 'pending'
  | 'sending'
  | 'sent'
  | 'failed';

export function idleAfterIso(fromMs = Date.now()): string {
  return new Date(fromMs + OIL_CARD_PDF_IDLE_MS).toISOString();
}

export function defaultPdfStoragePath(
  tenantUserId: string,
  orderRef: string,
): string {
  const tenant = tenantUserId.trim();
  const ref = orderRef.trim().replace(/[^a-zA-Z0-9._-]/g, '_');
  return `${tenant}/${ref}.pdf`;
}

function digitsPhone(raw: string): string {
  return String(raw ?? '').replace(/\D/g, '');
}

/** كل وارد بعد البطاقة يعيد مهلة الصمت — مرة واحدة لكل طلب عند الإرسال. */
export async function touchOilCardPdfIdleJob(
  db: SupabaseClient,
  args: {
    tenantUserId: string;
    orderRef: string | null | undefined;
    toPhone: string;
    phoneNumberId: string;
    cardPayload?: Record<string, string> | null;
    immediate?: boolean;
  },
): Promise<'skipped' | 'touched' | 'already_sent'> {
  const tenantUserId = args.tenantUserId.trim();
  const orderRef = String(args.orderRef ?? '').trim();
  const toPhone = digitsPhone(args.toPhone);
  const phoneNumberId = args.phoneNumberId.trim();
  if (!tenantUserId || !orderRef || toPhone.length < 10 || !phoneNumberId) {
    return 'skipped';
  }

  const { data: existing } = await db
    .from('whatsapp_oil_card_pdf_jobs')
    .select('id, status')
    .eq('tenant_user_id', tenantUserId)
    .eq('order_ref', orderRef)
    .maybeSingle();

  if (existing?.status === 'sent') return 'already_sent';

  const patch = {
    tenant_user_id: tenantUserId,
    order_ref: orderRef,
    to_phone: toPhone,
    phone_number_id: phoneNumberId,
    status: 'pending',
    idle_after: args.immediate ? new Date().toISOString() : idleAfterIso(),
    ...(args.cardPayload && Object.keys(args.cardPayload).length
      ? { card_payload: args.cardPayload }
      : {}),
  };

  if (existing?.id) {
    const { error } = await db
      .from('whatsapp_oil_card_pdf_jobs')
      .update({
        to_phone: patch.to_phone,
        phone_number_id: patch.phone_number_id,
        status: 'pending',
        idle_after: patch.idle_after,
        ...(patch.card_payload ? { card_payload: patch.card_payload } : {}),
      })
      .eq('id', existing.id)
      .neq('status', 'sent');
    if (error) {
      console.warn('pdf job touch failed', error.message);
      return 'skipped';
    }
    return 'touched';
  }

  const { error } = await db.from('whatsapp_oil_card_pdf_jobs').insert({
    ...patch,
    pdf_storage_path: defaultPdfStoragePath(tenantUserId, orderRef),
  });
  if (error) {
    console.warn('pdf job insert failed', error.message);
    return 'skipped';
  }
  return 'touched';
}
