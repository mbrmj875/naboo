/**
 * عقود الإشعار المنصّية — مستقلة عن غيار الزيت وعن اسم المزود.
 */

export enum TemplateKey {
  oilChangeCard = 'oil_change_card',
  oilChangeFollowup = 'oil_change_followup',
}

export type NotificationChannel = 'whatsapp' | 'push' | 'email' | 'sms';

export type NotificationRequest = {
  tenantUserId: string;
  channel: NotificationChannel;
  templateKey: TemplateKey;
  recipient: { phone?: string; userId?: string; email?: string };
  variables: Record<string, string>;
  idempotencyKey?: string;
  /** يُحفظان في سجل الرسائل ليُسنَد تقييم العميل لاحقاً للبطاقة والفني. */
  orderRef?: string | null;
  employeeName?: string | null;
};

export type ReadyState = 'disconnected' | 'preparing' | 'ready';

export type NotificationDispatchResult = {
  ok: boolean;
  channel: NotificationChannel;
  providerMessageId?: string;
  logId?: string;
  detail?: string;
  readyState?: ReadyState;
  errorCode?: number;
  httpStatus?: number;
};
