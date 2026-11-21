/**
 * مرسِل نابو الرسمي — القيمة المخزّنة في DB ما زالت `dualhook` للتوافق مع
 * الصفوف القديمة، لكن التنفيذ الوحيد هو Meta Cloud API عبر SHARED_SENDER_*.
 *
 * يفرض دائماً phone/waba نابو. اختيار التوكن يتم في resolveGraphAccessToken:
 * عند SHARED_SENDER يُستخدم توكن نابو فقط — بلا سر ES الخاص بالمحل.
 *
 * لا يوجد مسار احتياطي إلى api.dualhook.com.
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
import { metaCloudTransport } from './meta_cloud_transport.ts';
import { sharedSenderConfig } from '../shared_sender.ts';

function requireShared():
  | { ok: true }
  | { ok: false; detail: string } {
  if (sharedSenderConfig()) return { ok: true };
  return { ok: false, detail: 'shared_sender_not_configured' };
}

function withSharedPhoneIds<T extends {
  phoneNumberId?: string | null;
  wabaId?: string | null;
}>(input: T): T {
  const shared = sharedSenderConfig();
  if (!shared) return input;
  return {
    ...input,
    phoneNumberId: shared.phoneNumberId,
    wabaId: shared.wabaId,
  };
}

export const dualhookTransport: WhatsAppProvider = {
  id: 'dualhook',
  capabilities: {
    supportsEmbeddedSignup: false,
    supportsTemplates: true,
    supportsMedia: true,
    supportsInteractiveButtons: true,
    supportsCoexistence: true,
    supportsInboundMessages: true,
  },

  async startConnect(_tenantUserId: string): Promise<ConnectStartResult> {
    const shared = requireShared();
    if (!shared.ok) {
      return {
        ok: false,
        onboardingUrl: null,
        detail: shared.detail,
      };
    }
    // الربط الفعلي يتم في connect_service عبر SHARED_SENDER_* بلا نافذة خارجية.
    return {
      ok: true,
      onboardingUrl: null,
      detail: 'shared_sender_ready',
    };
  },

  async completeConnect(input: ConnectCompleteInput) {
    const shared = requireShared();
    if (!shared.ok) return { ok: false, detail: shared.detail };
    if (!input.wabaId && !input.fromPhoneE164 && !input.phoneNumberId) {
      // يكفي وجود المرسِل المشترك على الخادم.
      return { ok: true };
    }
    return { ok: true };
  },

  async disconnect(_tenantUserId: string) {
    return { ok: true };
  },

  async sendText(input: SendTextInput): Promise<SendResult> {
    const shared = requireShared();
    if (!shared.ok) {
      return { ok: false, detail: shared.detail, retryable: false };
    }
    return await metaCloudTransport.sendText(withSharedPhoneIds(input));
  },

  async sendTemplate(input: SendTemplateInput): Promise<SendResult> {
    const shared = requireShared();
    if (!shared.ok) {
      return { ok: false, detail: shared.detail, retryable: false };
    }
    return await metaCloudTransport.sendTemplate(withSharedPhoneIds(input));
  },

  async ensureTemplate(input: EnsureTemplateInput): Promise<EnsureTemplateResult> {
    const shared = requireShared();
    if (!shared.ok) {
      return { ok: false, detail: shared.detail };
    }
    return await metaCloudTransport.ensureTemplate(withSharedPhoneIds(input));
  },

  async getTemplateStatus(args): Promise<TemplateRemoteStatus> {
    const shared = requireShared();
    if (!shared.ok) {
      return { ok: false, status: 'unknown', detail: shared.detail };
    }
    return await metaCloudTransport.getTemplateStatus(withSharedPhoneIds(args));
  },
};
