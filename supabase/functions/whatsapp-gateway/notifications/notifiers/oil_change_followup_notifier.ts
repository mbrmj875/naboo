import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { TemplateKey } from '../notification_request.ts';
import { dispatchNotification } from '../notification_dispatcher.ts';
import type { NotificationDispatchResult } from '../notification_request.ts';

export type OilChangeFollowupPayload = {
  tenantUserId: string;
  customerPhone: string;
  variables: Record<string, string>;
  orderRef?: string | null;
  idempotencyKey: string;
};

export async function notifyOilChangeFollowup(
  supabase: SupabaseClient,
  payload: OilChangeFollowupPayload,
): Promise<NotificationDispatchResult> {
  return await dispatchNotification(supabase, {
    tenantUserId: payload.tenantUserId,
    channel: 'whatsapp',
    templateKey: TemplateKey.oilChangeFollowup,
    recipient: { phone: payload.customerPhone },
    variables: payload.variables,
    idempotencyKey: payload.idempotencyKey,
    orderRef: payload.orderRef ?? null,
  });
}
