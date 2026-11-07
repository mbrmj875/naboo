/**
 * Meta Cloud API مباشر (Tech Provider / Embedded Signup).
 * لا يستدعيه Flutter — فقط عبر ConnectService عندما whatsapp_provider=cloud_api.
 */

import type {
  ConnectCompleteInput,
  ConnectStartResult,
  EnsureTemplateInput,
  EnsureTemplateResult,
  SendResult,
  SendTemplateInput,
  SendTextInput,
  TemplateRemoteStatus,
  WhatsAppProvider,
} from './types.ts';
import { cloudSendText, resolveGraphAccessToken } from '../cloud_api.ts';
import { graphErrorCodes } from '../failure_policy.ts';
import { signEsState } from '../es_state.ts';
import {
  createWabaMessageTemplate,
  exchangeEmbeddedSignupCode,
  exchangeLongLivedToken,
  fetchPhoneDisplay,
  registerCloudPhone,
  fetchPhoneOnboarding,
  isBenignRegisterFailure,
  resolveWabaAssetsFromTokenWithRetry,
  subscribeAppToWaba,
} from '../meta_oauth.ts';
import { upsertProviderSecret } from '../provider_secrets.ts';
import { adminClient } from '../admin_client.ts';
import { sanitizeTemplateParam } from './template_params.ts';
import {
  isGenericShopName,
  resolveShopNameForCard,
} from '../notifications/resolve_shop_name.ts';
import { buildTenantAiContext } from '../../whatsapp-cloud-webhook/tenant_ai_context.ts';

const GRAPH_VER = Deno.env.get('META_GRAPH_API_VERSION')?.trim() || 'v26.0';
const GRAPH = `https://graph.facebook.com/${GRAPH_VER}`;

function metaAppId(): string | null {
  return Deno.env.get('META_APP_ID')?.trim() || null;
}

function metaEsConfigId(): string | null {
  return Deno.env.get('META_ES_CONFIG_ID')?.trim() ||
    Deno.env.get('META_EMBEDDED_SIGNUP_CONFIG_ID')?.trim() ||
    null;
}

/** صفحة HTML عامة تُشغّل FB.login — يجب أن تكون على استضافة ثابتة (ليس Edge HTML). */
function metaEsPageUrl(): string | null {
  const explicit = Deno.env.get('META_ES_PAGE_URL')?.trim();
  if (explicit) return explicit;
  return 'https://naboo-admin.vercel.app/whatsapp-meta-es';
}

function e164Digits(raw: string): string {
  return String(raw ?? '').replace(/\D/g, '');
}

function esCallbackUrl(): string {
  const explicit = Deno.env.get('META_ES_CALLBACK_URL')?.trim();
  if (explicit) return explicit;
  const base = Deno.env.get('SUPABASE_URL')?.replace(/\/$/, '') ?? '';
  return `${base}/functions/v1/whatsapp-meta-es-complete`;
}

/** رمز تسجيل ثنائي (6 أرقام) ثابت لكل مستأجر — لتسجيل الرقم على Cloud API. */
function registrationPinForTenant(tenantUserId: string): string {
  let hash = 0;
  const seed = `naboo-pin:${tenantUserId}`;
  for (let i = 0; i < seed.length; i++) {
    hash = (hash * 31 + seed.charCodeAt(i)) >>> 0;
  }
  return String(hash % 1000000).padStart(6, '0');
}

export const metaCloudTransport: WhatsAppProvider = {
  id: 'cloud_api',
  capabilities: {
    supportsEmbeddedSignup: true,
    supportsTemplates: true,
    supportsMedia: true,
    supportsInteractiveButtons: true,
    supportsCoexistence: true,
    supportsInboundMessages: true,
  },

  async startConnect(tenantUserId: string): Promise<ConnectStartResult> {
    const appId = metaAppId();
    const configId = metaEsConfigId();
    const page = metaEsPageUrl();

    if (!appId || !configId) {
      return {
        ok: false,
        onboardingUrl: null,
        detail: 'meta_es_not_configured',
      };
    }
    if (!page) {
      return {
        ok: false,
        onboardingUrl: null,
        detail: 'meta_es_page_missing',
      };
    }

    const state = await signEsState(tenantUserId);
    if (!state) {
      return {
        ok: false,
        onboardingUrl: null,
        detail: 'meta_app_secret_missing',
      };
    }

    let businessName = '';
    let businessPhone = '';
    try {
      const db = adminClient();
      if (db) {
        businessName = await resolveShopNameForCard(db, {
          tenantUserId,
          shopName: '',
        });
        if (isGenericShopName(businessName)) businessName = '';
        const facts = await buildTenantAiContext(db, {
          tenantUserId,
          card: null,
          employeeName: null,
        });
        businessPhone = String(facts.storePhone ?? '').replace(/\D/g, '');
      }
    } catch {
      businessName = '';
    }

    const url = new URL(page);
    url.searchParams.set('app_id', appId);
    url.searchParams.set('config_id', configId);
    url.searchParams.set('state', state);
    url.searchParams.set('callback', esCallbackUrl());
    url.searchParams.set('redirect_uri', `${new URL(page).origin}/whatsapp-meta-es.html`);
    if (businessName) {
      url.searchParams.set('business_name', businessName);
    }
    if (businessPhone) {
      url.searchParams.set('business_phone', businessPhone);
    }
    return {
      ok: true,
      onboardingUrl: url.toString(),
      detail: 'meta_embedded_signup',
    };
  },

  async completeConnect(
    input: ConnectCompleteInput,
  ): Promise<{ ok: boolean; detail?: string }> {
    let accessToken = String(input.accessToken ?? '').trim();
    const oauthCode = String(input.oauthCode ?? '').trim();

    if (!accessToken && oauthCode) {
      const exchanged = await exchangeEmbeddedSignupCode(
        oauthCode,
        input.oauthRedirectUri,
      );
      if (!exchanged.ok) {
        return { ok: false, detail: exchanged.detail };
      }
      accessToken = await exchangeLongLivedToken(exchanged.accessToken);
    }

    const hintedWaba = String(input.wabaId ?? '').trim();
    const hintedPhone = String(input.phoneNumberId ?? '').trim();
    let wabaId = hintedWaba;
    let phoneNumberId = hintedPhone;
    const db = adminClient();

    // احفظ التوكن مبكراً حتى لو تأخر ظهور الرقم على Graph — يسمح بإعادة الاستخراج.
    if (accessToken && db) {
      await upsertProviderSecret(db, {
        tenantUserId: input.tenantUserId,
        provider: 'cloud_api',
        secretKind: 'access_token',
        secretValue: accessToken,
      });
    }

    if (accessToken) {
      const excludePhoneIds: string[] = [];
      const excludePhoneDigits: string[] = [];
      if (db) {
        const { data: bound } = await db
          .from('tenant_whatsapp_gateways')
          .select('cloud_phone_number_id, whatsapp_phone')
          .neq('user_id', input.tenantUserId);
        for (const row of bound ?? []) {
          const rec = row as Record<string, unknown>;
          const id = String(rec.cloud_phone_number_id ?? '').trim();
          if (id) excludePhoneIds.push(id);
          const phone = String(rec.whatsapp_phone ?? '').replace(/\D/g, '');
          if (phone.length >= 8) excludePhoneDigits.push(phone);
        }
      }
      // مع توكن OAuth المصدر هو Graph. تلميح الجلسة يُقبل فقط إن أكّده التوكن.
      // بعد dialog/oauth غالباً لا تصل sessionInfo — نعيد محاولة واحدة فقط.
      const resolved = await resolveWabaAssetsFromTokenWithRetry(
        accessToken,
        hintedWaba || undefined,
        hintedPhone || undefined,
        {
          displayPhoneHint: input.fromPhoneE164,
          excludePhoneIds,
          excludePhoneDigits,
        },
        2,
      );
      if (resolved.ambiguous) {
        return { ok: false, detail: 'ambiguous_assets' };
      }
      if (resolved.detail) {
        return { ok: false, detail: resolved.detail };
      }
      wabaId = resolved.wabaId ?? '';
      phoneNumberId = resolved.phoneNumberId ?? '';
      if (wabaId) input.wabaId = wabaId;
      if (phoneNumberId) input.phoneNumberId = phoneNumberId;
    }

    if (!wabaId || !phoneNumberId) {
      console.warn(
        'es_missing_waba_or_phone',
        JSON.stringify({
          tenant: input.tenantUserId,
          hasToken: Boolean(accessToken),
          hintedWaba: Boolean(hintedWaba),
          hintedPhone: Boolean(hintedPhone),
          fromHint: Boolean(String(input.fromPhoneE164 ?? '').trim()),
        }),
      );
      return { ok: false, detail: 'missing_waba_or_phone' };
    }

    if (!accessToken) {
      // ربط يدوي/ويب هوك بدون code — يعتمد على توكن النظام إن وُجد لاحقاً عند الإرسال
      return { ok: true, detail: 'bound_without_oauth_token' };
    }

    const subscribed = await subscribeAppToWaba(wabaId, accessToken);
    if (!subscribed.ok) {
      return { ok: false, detail: 'webhook_subscription_failed' };
    }

    const signupCoexistence =
      String(input.signupEvent ?? '') === 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING';
    const onboard = await fetchPhoneOnboarding(phoneNumberId, accessToken);
    const coexistence = signupCoexistence || onboard.isOnBizApp;
    const pin = registrationPinForTenant(input.tenantUserId);
    const registered = coexistence
      ? { ok: true, detail: 'coexistence_skip_register' }
      : await registerCloudPhone(phoneNumberId, accessToken, pin);
    const alreadyOnCloud = onboard.platformType === 'CLOUD_API';
    const alreadyRegistered = isBenignRegisterFailure(registered.detail);
    if (!registered.ok && !alreadyRegistered && !alreadyOnCloud) {
      return { ok: false, detail: 'phone_register_failed' };
    }
    if (registered.ok && db && !coexistence) {
      await upsertProviderSecret(db, {
        tenantUserId: input.tenantUserId,
        provider: 'cloud_api',
        secretKind: 'register_pin',
        secretValue: pin,
      });
    }

    // إن لم يُمرَّر رقم العرض — اجلبه من Graph
    if (!String(input.fromPhoneE164 ?? '').trim()) {
      const phone = await fetchPhoneDisplay(phoneNumberId, accessToken);
      if (phone.displayE164) {
        (input as ConnectCompleteInput).fromPhoneE164 = phone.displayE164;
      }
    }

    return { ok: true, detail: 'meta_es_bound' };
  },

  async disconnect(
    _tenantUserId: string,
  ): Promise<{ ok: boolean; detail?: string }> {
    return { ok: true };
  },

  async sendText(input: SendTextInput): Promise<SendResult> {
    const phoneId = String(input.phoneNumberId ?? '').trim();
    if (!phoneId) {
      return { ok: false, detail: 'cloud_phone_number_id_missing' };
    }
    const sent = await cloudSendText({
      userId: input.tenantUserId,
      phoneNumberId: phoneId,
      toE164Digits: e164Digits(input.toPhoneE164),
      body: input.body,
    });
    return {
      ok: sent.ok,
      providerMessageId: sent.messageId,
      detail: sent.detail,
      httpStatus: sent.httpStatus,
      errorCode: sent.errorCode,
      errorSubcode: sent.errorSubcode,
    };
  },

  async sendTemplate(input: SendTemplateInput): Promise<SendResult> {
    const phoneId = String(input.phoneNumberId ?? '').trim();
    if (!phoneId) {
      return { ok: false, detail: 'cloud_phone_number_id_missing' };
    }
    const token = await resolveGraphAccessToken({
      userId: input.tenantUserId,
      phoneNumberId: phoneId,
    });
    if (!token) return { ok: false, detail: 'cloud_token_missing' };
    const to = e164Digits(input.toPhoneE164);
    const bodyParams = (input.bodyParameters ?? []).map((text) => ({
      type: 'text',
      text: sanitizeTemplateParam(text),
    }));
    try {
      const res = await fetch(
        `${GRAPH}/${encodeURIComponent(phoneId)}/messages`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            messaging_product: 'whatsapp',
            to,
            type: 'template',
            template: {
              name: input.templateName,
              language: { code: input.language },
              components: bodyParams.length
                ? [{ type: 'body', parameters: bodyParams }]
                : [],
            },
          }),
          signal: AbortSignal.timeout(20_000),
        },
      );
      const raw = await res.text();
      let data: Record<string, unknown> = {};
      try {
        data = JSON.parse(raw) as Record<string, unknown>;
      } catch {
        /* ignore */
      }
      if (!res.ok) {
        const err = data.error as Record<string, unknown> | undefined;
        return {
          ok: false,
          httpStatus: res.status,
          detail: String(err?.message ?? raw).slice(0, 400),
          retryable: res.status >= 500,
          ...graphErrorCodes(err),
        };
      }
      const messages = Array.isArray(data.messages) ? data.messages : [];
      const first = messages[0] as Record<string, unknown> | undefined;
      return {
        ok: true,
        providerMessageId: first?.id != null ? String(first.id) : undefined,
        httpStatus: res.status,
      };
    } catch (e) {
      return { ok: false, detail: String(e).slice(0, 200), retryable: true };
    }
  },

  async ensureTemplate(
    input: EnsureTemplateInput,
  ): Promise<EnsureTemplateResult> {
    const token = await resolveGraphAccessToken({
      userId: input.tenantUserId,
      wabaId: input.wabaId,
    });
    if (!token) return { ok: false, detail: 'cloud_token_missing' };

    const existing = await this.getTemplateStatus({
      tenantUserId: input.tenantUserId,
      wabaId: input.wabaId,
      templateName: input.templateName,
      language: input.language,
    });
    if (existing.ok && existing.status !== 'none' && existing.status !== 'unknown') {
      return {
        ok: true,
        templateId: existing.templateId,
        status: existing.status,
        detail: 'already_present',
      };
    }

    return await createWabaMessageTemplate({
      wabaId: input.wabaId,
      accessToken: token,
      templateName: input.templateName,
      language: input.language,
      category: input.category,
      bodyText: input.bodyText,
      exampleBodyParams: input.exampleBodyParams,
    });
  },

  async getTemplateStatus(args: {
    tenantUserId: string;
    wabaId: string;
    templateName: string;
    language: string;
  }): Promise<TemplateRemoteStatus> {
    const token = await resolveGraphAccessToken({
      userId: args.tenantUserId,
      wabaId: args.wabaId,
    });
    if (!token) {
      return { ok: false, status: 'unknown', detail: 'cloud_token_missing' };
    }
    try {
      const url =
        `${GRAPH}/${encodeURIComponent(args.wabaId)}/message_templates` +
        `?name=${encodeURIComponent(args.templateName)}` +
        `&limit=5`;
      const res = await fetch(url, {
        headers: { Authorization: `Bearer ${token}` },
      });
      const data = await res.json() as {
        data?: Array<{ status?: string; id?: string; language?: string }>;
      };
      if (!res.ok) {
        return { ok: false, status: 'unknown', detail: 'graph_error' };
      }
      const rows = Array.isArray(data.data) ? data.data : [];
      const match = rows.find((r) =>
        !args.language ||
        String(r.language ?? '').toLowerCase().startsWith(
          args.language.toLowerCase().slice(0, 2),
        )
      ) ?? rows[0];
      if (!match) return { ok: true, status: 'none' };
      const st = String(match.status ?? '').toUpperCase();
      if (st.includes('APPROV')) {
        return { ok: true, status: 'approved', templateId: match.id };
      }
      if (st.includes('REJECT')) {
        return { ok: true, status: 'rejected', templateId: match.id };
      }
      return { ok: true, status: 'pending', templateId: match.id };
    } catch (e) {
      return {
        ok: false,
        status: 'unknown',
        detail: String(e).slice(0, 200),
      };
    }
  },
};
