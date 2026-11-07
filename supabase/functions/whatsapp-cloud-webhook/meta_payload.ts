/**
 * تفكيك حمولة ويب هوك Meta Cloud API إلى أحداث مفهومة — دالة نقية.
 * الشكل: { object, entry[].changes[].value.{ metadata, messages[], statuses[] } }
 */

export type MetaInboundMessage = {
  phoneNumberId: string;
  messageId: string;
  fromPhone: string;
  messageType: string;
  body: string | null;
  contextMessageId: string | null;
};

export type MetaStatusError = {
  code: string;
  title: string;
  message: string;
};

export type MetaStatusUpdate = {
  phoneNumberId: string;
  messageId: string;
  status: string;
  /** أول عنصر من statuses[].errors إن وُجد — آمن عند غياب الحقول. */
  error: MetaStatusError | null;
};

export type MetaTemplateStatusUpdate = {
  wabaId: string;
  event: string;
  templateId: string;
  templateName: string;
  language: string;
  reason: string;
};

export type MetaWebhookParse = {
  isMeta: boolean;
  messages: MetaInboundMessage[];
  statuses: MetaStatusUpdate[];
  templateUpdates: MetaTemplateStatusUpdate[];
};

type Dict = Record<string, unknown>;

function asDict(v: unknown): Dict {
  return (v && typeof v === 'object') ? v as Dict : {};
}

function asArray(v: unknown): unknown[] {
  return Array.isArray(v) ? v : [];
}

function str(v: unknown): string {
  return String(v ?? '').trim();
}

function extractBody(msg: Dict, type: string): string | null {
  if (type === 'text') return str(asDict(msg.text).body) || null;
  if (type === 'button') return str(asDict(msg.button).text) || null;
  if (type === 'interactive') {
    const inter = asDict(msg.interactive);
    const list = asDict(inter.list_reply);
    const btn = asDict(inter.button_reply);
    return str(list.title) || str(btn.title) || null;
  }
  if (type === 'reaction') return str(asDict(msg.reaction).emoji) || null;
  return null;
}

export function parseMetaWebhook(event: unknown): MetaWebhookParse {
  const root = asDict(event);
  const entries = asArray(root.entry);
  const isMeta = str(root.object) === 'whatsapp_business_account' ||
    entries.length > 0;

  const messages: MetaInboundMessage[] = [];
  const statuses: MetaStatusUpdate[] = [];
  const templateUpdates: MetaTemplateStatusUpdate[] = [];

  for (const entryRaw of entries) {
    const entry = asDict(entryRaw);
    for (const changeRaw of asArray(entry.changes)) {
      const change = asDict(changeRaw);
      const value = asDict(change.value);
      if (str(change.field) === 'message_template_status_update') {
        const name = str(value.message_template_name);
        if (name) {
          templateUpdates.push({
            wabaId: str(entry.id),
            event: str(value.event).toUpperCase(),
            templateId: str(value.message_template_id),
            templateName: name,
            language: str(value.message_template_language) || 'ar',
            reason: str(value.reason),
          });
        }
      }
      const phoneNumberId = str(asDict(value.metadata).phone_number_id);

      for (const msgRaw of asArray(value.messages)) {
        const msg = asDict(msgRaw);
        const messageType = str(msg.type) || 'text';
        messages.push({
          phoneNumberId,
          messageId: str(msg.id),
          fromPhone: str(msg.from),
          messageType,
          body: extractBody(msg, messageType),
          contextMessageId: str(asDict(msg.context).id) || null,
        });
      }

      for (const stRaw of asArray(value.statuses)) {
        const st = asDict(stRaw);
        statuses.push({
          phoneNumberId,
          messageId: str(st.id),
          status: str(st.status).toLowerCase(),
          error: extractStatusError(st.errors),
        });
      }
    }
  }

  return {
    isMeta: isMeta &&
      (messages.length > 0 || statuses.length > 0 || templateUpdates.length > 0),
    messages,
    statuses,
    templateUpdates,
  };
}

/** يستخرج errors[0] بأمان — لا يرمي عند شكل خاطئ. */
export function extractStatusError(errorsRaw: unknown): MetaStatusError | null {
  if (!Array.isArray(errorsRaw) || errorsRaw.length === 0) return null;
  const first = errorsRaw[0];
  if (!first || typeof first !== 'object') return null;
  const e = first as Dict;
  const code = str(e.code);
  const title = str(e.title);
  const message = str(e.message) || str(e.error_data);
  if (!code && !title && !message) return null;
  return {
    code: code || 'unknown',
    title,
    message,
  };
}

export function mapMetaStatus(
  raw: string,
): 'sent' | 'delivered' | 'read' | 'failed' {
  const s = raw.toLowerCase();
  if (s.includes('fail') || s.includes('error') || s.includes('reject')) {
    return 'failed';
  }
  if (s.includes('read')) return 'read';
  if (s.includes('deliver')) return 'delivered';
  return 'sent';
}
