/**
 * Application notifier لبطاقة غيار الزيت — لا يعرف YCloud ولا Provider.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { TemplateKey } from '../notification_request.ts';
import { dispatchNotification } from '../notification_dispatcher.ts';
import type { NotificationDispatchResult } from '../notification_request.ts';
import {
  injectShopNameIntoText,
  isGenericShopName,
  resolveShopNameForCard,
} from '../resolve_shop_name.ts';

export type OilChangeCardPayload = {
  tenantUserId: string;
  customerPhone: string;
  customerName: string;
  shopName: string;
  detailsBlock: string;
  orderId?: string | number | null;
  employeeName?: string | null;
  /** حقول البطاقة الطويلة (سيارة، زيت، فلاتر، أسعار…) بأسماء متغيّرات القالب. */
  templateParams?: Record<string, string>;
  /** إعادة إرسال يدوية من سجل الرسائل — تتجاوز مانع التكرار عمداً. */
  resend?: boolean;
  /** مفتاح موحّد مع خصم المحفظة — يمرَّر من بوابة الإرسال. */
  idempotencyKey?: string | null;
  originalLogId?: string | null;
};

export async function notifyOilChangeCard(
  supabase: SupabaseClient,
  payload: OilChangeCardPayload,
): Promise<NotificationDispatchResult> {
  const idem = (payload.idempotencyKey ?? '').trim() ||
    (payload.orderId != null && !payload.resend
      ? `oil_card:${payload.tenantUserId}:${payload.orderId}:${payload.customerPhone}`
      : undefined);

  const fromParams = String(payload.templateParams?.shop ?? '').trim();
  const shop = await resolveShopNameForCard(supabase, {
    tenantUserId: payload.tenantUserId,
    shopName: !isGenericShopName(payload.shopName)
      ? payload.shopName
      : (fromParams || payload.shopName),
    employeeName: payload.employeeName,
  });

  const detailsRaw = payload.detailsBlock.trim() ||
    String(payload.templateParams?.details ?? '').trim() ||
    '-';
  const details = injectShopNameIntoText(detailsRaw, shop);

  const templateParams = { ...(payload.templateParams ?? {}) };
  if (templateParams.shop != null && isGenericShopName(templateParams.shop)) {
    templateParams.shop = shop;
  }
  if (templateParams.details != null) {
    templateParams.details = injectShopNameIntoText(templateParams.details, shop);
  }
  if (payload.originalLogId) {
    templateParams.original_log_id = payload.originalLogId;
  }

  return await dispatchNotification(supabase, {
    tenantUserId: payload.tenantUserId,
    channel: 'whatsapp',
    templateKey: TemplateKey.oilChangeCard,
    recipient: { phone: payload.customerPhone },
    variables: {
      ...templateParams,
      customer: payload.customerName.trim() || 'عميلنا الكريم',
      shop,
      details,
    },
    idempotencyKey: idem,
    orderRef: payload.orderId != null ? String(payload.orderId) : null,
    employeeName: (payload.employeeName ?? '').trim() || null,
  });
}
