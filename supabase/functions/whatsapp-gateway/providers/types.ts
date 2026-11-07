/**
 * واجهة مزود واتساب + Capabilities — بدون فروع باسم الشركة في طبقة الأعمال.
 */

export type TransportProviderId =
  | 'waha'
  | 'evolution'
  | 'cloud_api'
  | 'whats360'
  | 'ycloud'
  | 'dualhook';

export type ProviderCapabilities = {
  supportsEmbeddedSignup: boolean;
  supportsTemplates: boolean;
  supportsMedia: boolean;
  supportsInteractiveButtons: boolean;
  supportsCoexistence: boolean;
  supportsInboundMessages: boolean;
};

export type ConnectStartResult = {
  ok: boolean;
  /** رابط/جلسة Embedded Signup إن وُجد — وإلا null للمسارات اليدوية */
  onboardingUrl?: string | null;
  detail?: string;
};

export type ConnectCompleteInput = {
  tenantUserId: string;
  wabaId?: string;
  phoneNumberId?: string;
  fromPhoneE164?: string;
  connectionId?: string;
  /** كود OAuth من Embedded Signup — يُستبدل بتوكن على الخادم */
  oauthCode?: string;
  /** مطابق لـ redirect_uri إن جاء الكود من dialog/oauth وليس من FB.login */
  oauthRedirectUri?: string;
  /** توكن جاهز بعد التبادل (مسار داخلي) */
  accessToken?: string;
  /** FINISH أو FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING من جلسة Meta */
  signupEvent?: string;
};

export type SendTemplateInput = {
  tenantUserId: string;
  fromPhoneE164: string;
  toPhoneE164: string;
  templateName: string;
  language: string;
  bodyParameters: string[];
  /** Dualhook/Graph: معرّف رقم الهاتف عند Meta */
  phoneNumberId?: string;
};

export type SendTextInput = {
  tenantUserId: string;
  fromPhoneE164?: string;
  toPhoneE164: string;
  body: string;
  /** Dualhook/Graph: معرّف رقم الهاتف عند Meta */
  phoneNumberId?: string;
};

export type SendResult = {
  ok: boolean;
  providerMessageId?: string;
  detail?: string;
  httpStatus?: number;
  retryable?: boolean;
  errorCode?: number;
  errorSubcode?: number;
};

export type EnsureTemplateInput = {
  tenantUserId: string;
  wabaId: string;
  templateName: string;
  language: string;
  category: 'utility' | 'marketing' | 'authentication';
  bodyText: string;
  exampleBodyParams: string[];
};

export type EnsureTemplateResult = {
  ok: boolean;
  templateId?: string;
  status?: 'pending' | 'approved' | 'rejected' | 'none';
  detail?: string;
};

export type TemplateRemoteStatus = {
  ok: boolean;
  templateId?: string;
  status: 'pending' | 'approved' | 'rejected' | 'none' | 'unknown';
  detail?: string;
};

export interface WhatsAppProvider {
  readonly id: TransportProviderId;
  readonly capabilities: ProviderCapabilities;

  startConnect(tenantUserId: string): Promise<ConnectStartResult>;
  completeConnect(input: ConnectCompleteInput): Promise<{ ok: boolean; detail?: string }>;
  disconnect(tenantUserId: string): Promise<{ ok: boolean; detail?: string }>;

  sendText(input: SendTextInput): Promise<SendResult>;
  sendTemplate(input: SendTemplateInput): Promise<SendResult>;

  ensureTemplate(input: EnsureTemplateInput): Promise<EnsureTemplateResult>;
  getTemplateStatus(args: {
    tenantUserId: string;
    wabaId: string;
    templateName: string;
    language: string;
  }): Promise<TemplateRemoteStatus>;
}
