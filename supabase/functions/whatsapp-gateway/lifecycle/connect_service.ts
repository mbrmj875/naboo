/**
 * دورة حياة الاتصال — لا تنشئ قوالب ولا ترسل رسائل.
 * المزود يُقرأ من صف المستأجر
 * (cloud_api = رقم المحل عبر Meta، dualhook = رقم نابو الرسمي عبر Meta).
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { getWhatsAppProvider, parseTransportId } from '../providers/registry.ts';
import { cleanupOtherEngines } from '../provider.ts';
import { ensureDefaultTemplatesForTenant } from './template_lifecycle_service.ts';
import { writeClient } from '../admin_client.ts';
import { creditNabooSharedWelcomeLot } from '../wallet.ts';
import {
  notifyWaBound,
  notifyWaUnbound,
} from '../../whatsapp-events/owner_email_notify.ts';
import { westernPhone } from '../../whatsapp-events/owner_email_copy.ts';
import { sharedSenderConfig } from '../shared_sender.ts';
import type { TransportProviderId } from '../providers/types.ts';

async function mailSwitch(
  supabase: SupabaseClient,
  args: {
    tenantUserId: string;
    nextProvider: string;
    nextPhone: string | null;
    previousProvider: string | null;
    previousPhone: string | null;
    wasConnected: boolean;
  },
): Promise<void> {
  const instance = `shop_${args.tenantUserId.replace(/-/g, '_')}`;
  const db = writeClient(supabase);
  try {
    const phoneChanged = (westernPhone(args.previousPhone) ?? '') !==
      (westernPhone(args.nextPhone) ?? '');
    if (
      args.wasConnected &&
      args.previousProvider &&
      (args.previousProvider !== args.nextProvider || phoneChanged)
    ) {
      await notifyWaUnbound(db, {
        userId: args.tenantUserId,
        instanceName: instance,
        provider: args.previousProvider,
        phone: args.previousPhone,
      });
    }
    await notifyWaBound(db, {
      userId: args.tenantUserId,
      instanceName: instance,
      provider: args.nextProvider,
      phone: args.nextPhone,
      flapCooldown: false,
    });
  } catch (e) {
    console.warn('wa link email', String(e).slice(0, 160));
  }
}

function isOfficialId(id: TransportProviderId): boolean {
  return id === 'dualhook' || id === 'ycloud' || id === 'cloud_api';
}

async function readOfficialProvider(
  supabase: SupabaseClient,
  tenantUserId: string,
): Promise<TransportProviderId> {
  const { data } = await supabase
    .from('tenant_whatsapp_gateways')
    .select('whatsapp_provider')
    .eq('user_id', tenantUserId)
    .maybeSingle();
  const id = parseTransportId(data?.whatsapp_provider);
  return isOfficialId(id) ? id : 'dualhook';
}

export async function startOfficialConnect(
  supabase: SupabaseClient,
  tenantUserId: string,
): Promise<{
  ok: boolean;
  onboardingUrl?: string | null;
  detail?: string;
  message_ar?: string;
  ready_state?: string;
  provider?: string;
}> {
  const officialProvider = await readOfficialProvider(supabase, tenantUserId);
  const provider = getWhatsAppProvider(officialProvider);
  if (!provider) {
    return {
      ok: false,
      detail: 'provider_missing',
      message_ar: 'طريقة الربط الرسمي غير متاحة حالياً.',
    };
  }

  const db = writeClient(supabase);
  const { data: existing } = await db
    .from('tenant_whatsapp_gateways')
    .select(
      'status, cloud_waba_id, cloud_phone_number_id, ycloud_from_phone, whatsapp_phone, cloud_setup_status, provider_connection_id, whatsapp_provider',
    )
    .eq('user_id', tenantUserId)
    .maybeSingle();

  const hasBoundAssets =
    String(existing?.cloud_waba_id ?? '').trim().length > 0 &&
    String(existing?.cloud_phone_number_id ?? '').trim().length > 0;
  const setupReady =
    String(existing?.cloud_setup_status ?? '').trim() === 'ready';
  const wasConnected =
    String(existing?.status ?? '').trim() === 'connected';

  // حساب مربوط مسبقاً على **نفس** المزود وبحالة جاهزة فعلاً — لا نمسحه.
  // لا نُعيد استخدام IDs يتيمة (مثلاً رقم نابو المشترك بعد اختيار Meta مباشرة).
  const existingProvider = parseTransportId(existing?.whatsapp_provider);
  if (
    hasBoundAssets &&
    setupReady &&
    wasConnected &&
    existingProvider === officialProvider
  ) {
    const now = new Date().toISOString();
    const phone = String(
      existing?.ycloud_from_phone ?? existing?.whatsapp_phone ?? '',
    ).trim() || null;
    await db.from('tenant_whatsapp_gateways').upsert(
      {
        user_id: tenantUserId,
        evolution_instance_name: `shop_${tenantUserId.replace(/-/g, '_')}`,
        whatsapp_provider: officialProvider,
        status: 'connected',
        cloud_setup_status: 'ready',
        repair_needed: false,
        last_connected_at: now,
        updated_at: now,
        ...(phone
          ? { ycloud_from_phone: phone, whatsapp_phone: phone }
          : {}),
      },
      { onConflict: 'user_id' },
    );
    await ensureDefaultTemplatesForTenant(db, tenantUserId);
    await notifyWaBound(db, {
      userId: tenantUserId,
      instanceName: `shop_${tenantUserId.replace(/-/g, '_')}`,
      provider: officialProvider,
      phone,
      once: true,
    });
    return {
      ok: true,
      onboardingUrl: null,
      detail: 'already_bound',
      ready_state: 'preparing',
      provider: officialProvider,
      message_ar:
        'واتساب مربوط. جاري تجهيز خدمة الرسائل حتى اعتماد القالب من ميتا.',
    };
  }

  // رقم نابو الرسمي: يربط المحل فوراً عبر Meta SHARED_SENDER بلا نافذة خارجية.
  if (officialProvider === 'dualhook') {
    const shared = sharedSenderConfig();
    if (!shared) {
      return {
        ok: false,
        detail: 'shared_sender_not_configured',
        provider: officialProvider,
        message_ar:
          'رقم نابو الرسمي غير مضبوط على الخادم. أضف SHARED_SENDER_WABA_ID و SHARED_SENDER_PHONE_NUMBER_ID ثم أعد المحاولة.',
      };
    }

    await cleanupOtherEngines({ userId: tenantUserId, next: officialProvider });
    const boundAt = new Date().toISOString();
    await db.from('tenant_whatsapp_gateways').upsert(
      {
        user_id: tenantUserId,
        evolution_instance_name: `shop_${tenantUserId.replace(/-/g, '_')}`,
        whatsapp_provider: officialProvider,
        status: 'connected',
        cloud_setup_status: 'ready',
        cloud_waba_id: shared.wabaId,
        cloud_phone_number_id: shared.phoneNumberId,
        whatsapp_phone: shared.phoneE164,
        ycloud_from_phone: shared.phoneE164,
        repair_needed: false,
        disconnect_cause: null,
        last_connected_at: boundAt,
        updated_at: boundAt,
      },
      { onConflict: 'user_id' },
    );
    await mailSwitch(supabase, {
      tenantUserId,
      nextProvider: officialProvider,
      nextPhone: shared.phoneE164,
      previousProvider: existing?.whatsapp_provider
        ? String(existing.whatsapp_provider)
        : null,
      previousPhone: String(
        existing?.whatsapp_phone ?? existing?.ycloud_from_phone ?? '',
      ).trim() || null,
      wasConnected,
    });
    await ensureDefaultTemplatesForTenant(db, tenantUserId);
    await creditNabooSharedWelcomeLot(supabase, tenantUserId);
    return {
      ok: true,
      onboardingUrl: null,
      detail: 'shared_sender_bound',
      ready_state: 'preparing',
      provider: officialProvider,
      message_ar:
        'تم الربط برقم نابو الرسمي عبر Meta. جاري تجهيز القالب — اضغط تحديث الحالة بعد لحظات.',
    };
  }

  await cleanupOtherEngines({ userId: tenantUserId, next: officialProvider });

  const now = new Date().toISOString();
  await db.from('tenant_whatsapp_gateways').upsert(
    {
      user_id: tenantUserId,
      evolution_instance_name: `shop_${tenantUserId.replace(/-/g, '_')}`,
      whatsapp_provider: officialProvider,
      status: 'connecting',
      cloud_setup_status: 'pending',
      repair_needed: false,
      updated_at: now,
    },
    { onConflict: 'user_id' },
  );

  const started = await provider.startConnect(tenantUserId);
  if (!started.ok) {
    const metaHint = officialProvider === 'cloud_api' &&
        (started.detail === 'meta_es_not_configured' ||
          started.detail === 'meta_es_page_missing' ||
          started.detail === 'meta_app_secret_missing');
    return {
      ok: false,
      detail: started.detail ?? 'connect_start_failed',
      provider: officialProvider,
      message_ar: started.detail === 'meta_app_secret_missing'
        ? 'إعداد Meta غير مكتمل على الخادم (سر التطبيق). تواصل مع دعم نابو.'
        : metaHint
        ? 'مسار Meta المباشرة غير مكتمل الإعداد بعد. أنشئ Configuration لـ WhatsApp Embedded Signup في Meta، ثم أضف META_APP_ID و META_ES_CONFIG_ID لأسرار الخادم.'
        : 'تعذّر بدء الربط الرسمي. أعد المحاولة لاحقاً.',
    };
  }
  return {
    ok: true,
    onboardingUrl: started.onboardingUrl ?? null,
    detail: started.detail,
    provider: officialProvider,
    message_ar: started.onboardingUrl
      ? 'أكمل الربط في نافذة Meta التي ستُفتح، ثم ارجع للتطبيق واضغط تحديث الحالة.'
      : 'أكمل خطوات الربط الرسمي، ثم اضغط تحديث الحالة.',
  };
}

export async function completeOfficialConnect(
  supabase: SupabaseClient,
  input: {
    tenantUserId: string;
    wabaId?: string;
    phoneNumberId?: string;
    fromPhoneE164?: string;
    connectionId?: string;
    oauthCode?: string;
    oauthRedirectUri?: string;
    accessToken?: string;
    signupEvent?: string;
  },
): Promise<{ ok: boolean; detail?: string; message_ar?: string }> {
  const officialProvider = await readOfficialProvider(
    supabase,
    input.tenantUserId,
  );
  const provider = getWhatsAppProvider(officialProvider);
  if (!provider) {
    return { ok: false, detail: 'provider_missing' };
  }

  const completeInput = {
    tenantUserId: input.tenantUserId,
    wabaId: input.wabaId,
    phoneNumberId: input.phoneNumberId,
    fromPhoneE164: input.fromPhoneE164,
    connectionId: input.connectionId,
    oauthCode: input.oauthCode,
    oauthRedirectUri: input.oauthRedirectUri,
    accessToken: input.accessToken,
    signupEvent: input.signupEvent,
  };
  const done = await provider.completeConnect(completeInput);
  if (!done.ok) {
    const ar = done.detail === 'meta_app_secret_missing'
      ? 'إعداد Meta غير مكتمل على الخادم. تواصل مع دعم نابو.'
      : done.detail === 'oauth_code_missing' ||
          (done.detail ?? '').includes('oauth')
      ? 'انتهت جلسة التفويض أو لم تكتمل. أعد الربط من التطبيق.'
      : done.detail === 'missing_waba_or_phone'
      ? 'لم تُستلم بيانات رقم واتساب من Meta. أكمل كل خطوات النافذة ثم أعد المحاولة.'
      : done.detail === 'meta_waba_rate_limited'
      ? 'اكتمل التفويض، لكن Meta أوقفت قراءة الرقم مؤقتاً بسبب كثرة المحاولات. انتظر ساعة من آخر محاولة ثم أعد الربط مرة واحدة.'
      : (done.detail ?? '').startsWith('meta_phone_list_error_') ||
          done.detail === 'meta_phone_list_failed' ||
          (done.detail ?? '').startsWith('meta_waba_targets_')
      ? 'اكتمل التفويض، لكن Meta لم تسمح بقراءة أصول واتساب. تواصل مع دعم نابو مع وقت المحاولة.'
      : done.detail === 'ambiguous_assets'
      ? 'لدى الحساب أكثر من رقم أو حساب واتساب. أعد الربط واختر الحساب المطلوب داخل Meta.'
      : done.detail === 'webhook_subscription_failed'
      ? 'تم التفويض لكن اشتراك استقبال الرسائل لم يكتمل. أعد الربط.'
      : done.detail === 'phone_register_failed'
      ? 'تم التفويض لكن تسجيل الرقم على Cloud API لم يكتمل. أعد الربط.'
      : 'تعذّر إكمال الربط.';
    return { ok: false, detail: done.detail, message_ar: ar };
  }

  const db = writeClient(supabase);
  const { data: previousGate } = await db
    .from('tenant_whatsapp_gateways')
    .select('status, whatsapp_provider, whatsapp_phone, ycloud_from_phone')
    .eq('user_id', input.tenantUserId)
    .maybeSingle();
  const now = new Date().toISOString();
  const phone = (completeInput.fromPhoneE164 ?? input.fromPhoneE164 ?? '')
    .trim() || null;
  const wabaId = (completeInput.wabaId ?? input.wabaId ?? '').trim() || null;
  const phoneNumberId =
    (completeInput.phoneNumberId ?? input.phoneNumberId ?? '').trim() || null;

  await db.from('tenant_whatsapp_gateways').upsert(
    {
      user_id: input.tenantUserId,
      evolution_instance_name:
        `shop_${input.tenantUserId.replace(/-/g, '_')}`,
      whatsapp_provider: officialProvider,
      status: 'connected',
      cloud_setup_status: 'ready',
      cloud_waba_id: wabaId,
      cloud_phone_number_id: phoneNumberId,
      provider_connection_id: input.connectionId ?? null,
      ycloud_from_phone: phone,
      whatsapp_phone: phone,
      last_connected_at: now,
      repair_needed: false,
      updated_at: now,
    },
    { onConflict: 'user_id' },
  );

  const prevProvider = previousGate?.whatsapp_provider
    ? String(previousGate.whatsapp_provider)
    : null;
  const prevPhone = String(
    previousGate?.whatsapp_phone ?? previousGate?.ycloud_from_phone ?? '',
  ).trim() || null;
  const sameBound = String(previousGate?.status ?? '') === 'connected' &&
    prevProvider === officialProvider &&
    (prevPhone ?? '') === (phone ?? '');
  if (!sameBound) {
    await mailSwitch(supabase, {
      tenantUserId: input.tenantUserId,
      nextProvider: officialProvider,
      nextPhone: phone,
      previousProvider: prevProvider,
      previousPhone: prevPhone,
      wasConnected: String(previousGate?.status ?? '') === 'connected',
    });
  } else {
    await notifyWaBound(db, {
      userId: input.tenantUserId,
      instanceName: `shop_${input.tenantUserId.replace(/-/g, '_')}`,
      provider: officialProvider,
      phone,
      once: true,
    });
  }

  await ensureDefaultTemplatesForTenant(db, input.tenantUserId);

  return {
    ok: true,
    message_ar: 'تم ربط واتساب. جاري تجهيز خدمة الرسائل…',
  };
}

export async function disconnectOfficial(
  supabase: SupabaseClient,
  tenantUserId: string,
): Promise<{ ok: boolean }> {
  const db = writeClient(supabase);
  const { data: gate } = await db
    .from('tenant_whatsapp_gateways')
    .select('whatsapp_provider')
    .eq('user_id', tenantUserId)
    .maybeSingle();
  const id = parseTransportId(gate?.whatsapp_provider);
  const provider = getWhatsAppProvider(id);
  if (provider) {
    await provider.disconnect(tenantUserId);
  }
  const now = new Date().toISOString();
  await db.from('tenant_whatsapp_gateways').upsert(
    {
      user_id: tenantUserId,
      evolution_instance_name: `shop_${tenantUserId.replace(/-/g, '_')}`,
      status: 'disconnected',
      last_disconnected_at: now,
      updated_at: now,
    },
    { onConflict: 'user_id' },
  );
  return { ok: true };
}
