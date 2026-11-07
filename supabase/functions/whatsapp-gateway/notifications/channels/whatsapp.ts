/**
 * قناة واتساب داخل NotificationDispatcher.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import type {
  NotificationDispatchResult,
  NotificationRequest,
} from '../notification_request.ts';
import { getWhatsAppProvider, parseTransportId } from '../../providers/registry.ts';
import { resolveTemplateSpecs } from '../../lifecycle/default_template_registry.ts';
import { loadFollowupTemplateSpec } from '../../lifecycle/followup_template.ts';
import { computeReadyState } from '../../lifecycle/ready_state.ts';
import { TemplateKey } from '../notification_request.ts';

/** ميتا ترفض معاملاً فارغاً، فالحقل الغائب يصبح شرطة. */
function paramAt(
  variables: Record<string, string>,
  key: string,
  index: number,
): string {
  const raw = variables[key] ?? variables[String(index + 1)] ?? '';
  const value = String(raw).trim();
  return value || '-';
}

/** القالب غير موجود على WABA المحل أو عدد معاملاته مختلف — جرّب البديل. */
function templateMismatch(detail?: string): boolean {
  const d = (detail ?? '').toLowerCase();
  if (!d) return false;
  return d.includes('132000') ||
    d.includes('132001') ||
    d.includes('132012') ||
    d.includes('does not exist') ||
    d.includes('not exist') ||
    d.includes('template not found') ||
    d.includes('number of parameters');
}

export async function dispatchWhatsappChannel(
  supabase: SupabaseClient,
  request: NotificationRequest,
): Promise<NotificationDispatchResult & { retryable?: boolean }> {
  const ready = await computeReadyState(supabase, request.tenantUserId);
  if (ready.readyState !== 'ready') {
    return {
      ok: false,
      channel: 'whatsapp',
      detail: `not_ready:${ready.readyState}`,
      readyState: ready.readyState,
      retryable: false,
    };
  }

  const { data: gate } = await supabase
    .from('tenant_whatsapp_gateways')
    .select(
      'whatsapp_provider, whatsapp_phone, ycloud_from_phone, cloud_phone_number_id',
    )
    .eq('user_id', request.tenantUserId)
    .maybeSingle();

  const transportId = parseTransportId(gate?.whatsapp_provider);
  const provider = getWhatsAppProvider(transportId);

  // الجسر غير الرسمي: يُعالَج في index.ts send_text حالياً
  if (!provider) {
    return {
      ok: false,
      channel: 'whatsapp',
      detail: `transport_not_in_dispatcher:${transportId}`,
      retryable: false,
    };
  }

  const to = (request.recipient.phone ?? '').trim();
  if (!to) {
    return {
      ok: false,
      channel: 'whatsapp',
      detail: 'missing_recipient_phone',
      retryable: false,
    };
  }

  const from = String(
    gate?.ycloud_from_phone ?? gate?.whatsapp_phone ?? '',
  ).trim();
  const phoneNumberId = String(gate?.cloud_phone_number_id ?? '').trim();

  if (provider.capabilities.supportsTemplates) {
    if (!from && !phoneNumberId) {
      return {
        ok: false,
        channel: 'whatsapp',
        detail: 'missing_from_phone',
        retryable: false,
      };
    }

    let specs = resolveTemplateSpecs(request.templateKey);
    if (request.templateKey === TemplateKey.oilChangeFollowup) {
      const follow = await loadFollowupTemplateSpec(supabase, request.tenantUserId);
      specs = follow ? [follow] : [];
    }
    let last: NotificationDispatchResult & { retryable?: boolean } = {
      ok: false,
      channel: 'whatsapp',
      detail: 'no_template_spec',
      retryable: false,
    };

    for (const spec of specs) {
      const sent = await provider.sendTemplate({
        tenantUserId: request.tenantUserId,
        fromPhoneE164: from || phoneNumberId,
        toPhoneE164: to,
        templateName: spec.name,
        language: spec.language,
        bodyParameters: spec.paramKeys.map((key, i) =>
          paramAt(request.variables, key, i)
        ),
        phoneNumberId: phoneNumberId || undefined,
      });
      last = {
        ok: sent.ok,
        channel: 'whatsapp',
        providerMessageId: sent.providerMessageId,
        detail: sent.detail,
        retryable: sent.retryable,
        readyState: 'ready',
      };
      if (sent.ok || !templateMismatch(sent.detail)) return last;
      console.warn(`template ${spec.name} unusable: ${sent.detail}`);
    }

    return last;
  }

  const body = request.variables['body'] ??
    [
      request.variables['customer'],
      request.variables['shop'],
      request.variables['details'],
    ].filter(Boolean).join('\n');

  const sent = await provider.sendText({
    tenantUserId: request.tenantUserId,
    fromPhoneE164: from || undefined,
    toPhoneE164: to,
    body,
    phoneNumberId: phoneNumberId || undefined,
  });
  return {
    ok: sent.ok,
    channel: 'whatsapp',
    providerMessageId: sent.providerMessageId,
    detail: sent.detail,
    retryable: sent.retryable,
    readyState: 'ready',
  };
}
