/**
 * حساب ready_state — Computed، لا يُخزَّن.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import type { ReadyState } from '../notifications/notification_request.ts';
import { TemplateKey } from '../notifications/notification_request.ts';
import {
  oilChangeDefaultTemplates,
} from './default_template_registry.ts';
import { parseTransportId } from '../providers/registry.ts';
import { getWhatsAppProvider } from '../providers/registry.ts';

export async function computeReadyState(
  supabase: SupabaseClient,
  tenantUserId: string,
  requiredKeys: TemplateKey[] = [TemplateKey.oilChangeCard],
): Promise<{
  readyState: ReadyState;
  provider: string;
  phone: string | null;
  connected: boolean;
}> {
  const { data: gate } = await supabase
    .from('tenant_whatsapp_gateways')
    .select(
      'status, whatsapp_provider, whatsapp_phone, ycloud_from_phone, cloud_waba_id, cloud_phone_number_id, cloud_setup_status',
    )
    .eq('user_id', tenantUserId)
    .maybeSingle();

  const provider = parseTransportId(gate?.whatsapp_provider);
  const status = String(gate?.status ?? '').toLowerCase();
  const phone = String(
    gate?.whatsapp_phone ?? gate?.ycloud_from_phone ?? '',
  ).trim() || null;

  const connected = status === 'connected';

  // مسارات الجسر غير الرسمية: connected ⇒ ready (لا قوالب ميتا)
  if (provider === 'whats360' || provider === 'waha' || provider === 'evolution') {
    if (!connected) {
      return { readyState: 'disconnected', provider, phone, connected: false };
    }
    return { readyState: 'ready', provider, phone, connected: true };
  }

  // cloud_api مباشرة — متصل ثم انتظار اعتماد القالب على WABA المستأجر
  if (provider === 'cloud_api') {
    if (!connected) {
      return { readyState: 'disconnected', provider, phone, connected: false };
    }
    const setup = String(gate?.cloud_setup_status ?? '');
    const hasAssets =
      String(gate?.cloud_waba_id ?? '').trim().length > 0 &&
      String(gate?.cloud_phone_number_id ?? '').trim().length > 0;
    if (setup !== 'ready' || !hasAssets) {
      return {
        readyState: 'preparing',
        provider,
        phone,
        connected: true,
      };
    }

    const names = oilChangeDefaultTemplates
      .filter((t) => requiredKeys.includes(t.key))
      .map((t) => t.name);
    if (names.length === 0) {
      return { readyState: 'ready', provider, phone, connected: true };
    }
    const { data: rows } = await supabase
      .from('tenant_whatsapp_templates')
      .select('template_name, status')
      .eq('tenant_user_id', tenantUserId)
      .eq('provider', provider)
      .in('template_name', names);
    const anyApproved = (rows ?? []).some((r) =>
      names.includes(String(r.template_name)) && String(r.status) === 'approved'
    );
    return {
      readyState: anyApproved ? 'ready' : 'preparing',
      provider,
      phone,
      connected: true,
    };
  }

  // ycloud / dualhook / رسمي بقوالب
  if (!connected) {
    return { readyState: 'disconnected', provider, phone, connected: false };
  }

  const providerImpl = getWhatsAppProvider(provider);
  const needsTemplates = providerImpl?.capabilities.supportsTemplates ?? true;

  if (!needsTemplates) {
    return { readyState: 'ready', provider, phone, connected: true };
  }

  const names = oilChangeDefaultTemplates
    .filter((t) => requiredKeys.includes(t.key))
    .map((t) => t.name);

  if (names.length === 0) {
    return { readyState: 'ready', provider, phone, connected: true };
  }

  const { data: rows } = await supabase
    .from('tenant_whatsapp_templates')
    .select('template_name, status')
    .eq('tenant_user_id', tenantUserId)
    .eq('provider', provider)
    .in('template_name', names);

  // القوالب بدائل لبعضها (طويل ثم قصير)، فاعتماد واحد يكفي للإرسال.
  const anyApproved = (rows ?? []).some((r) =>
    names.includes(String(r.template_name)) && String(r.status) === 'approved'
  );

  return {
    readyState: anyApproved ? 'ready' : 'preparing',
    provider,
    phone,
    connected: true,
  };
}

export function readyStateMessageAr(state: ReadyState): string {
  switch (state) {
    case 'ready':
      return 'جاهز لإرسال بطاقات الغيار';
    case 'preparing':
      return 'جاري تجهيز قالب الرسائل واعتماده من ميتا… قد يستغرق دقائق.';
    default:
      return 'غير متصل';
  }
}
