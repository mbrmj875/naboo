/**
 * بريد حالة القالب عند تغيّر حقيقي فقط. الفشل لا يوقف الرفع ولا المزامنة.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { notifyTemplateStatusEmail } from '../../whatsapp-events/owner_email_notify.ts';
import type { TemplateMailKind } from '../../whatsapp-events/owner_email_copy.ts';

function kindForTransition(args: {
  previousStatus: string | null;
  nextStatus: string;
  templateId: string | null;
  previousHadTemplateId: boolean;
  submitFailed: boolean;
}): TemplateMailKind | null {
  const prev = String(args.previousStatus ?? 'none');
  const next = String(args.nextStatus ?? 'none');
  const hasId = String(args.templateId ?? '').trim().length > 0;
  if (args.submitFailed || (next === 'rejected' && !hasId && prev !== 'rejected')) {
    return 'submit_failed';
  }
  if (next === 'pending' && hasId && (prev !== 'pending' || !args.previousHadTemplateId)) {
    return 'pending';
  }
  if (prev === next) return null;
  if (next === 'approved' && hasId) return 'approved';
  if (next === 'rejected' && hasId) return 'rejected';
  return null;
}

export async function maybeNotifyTemplateStatus(
  supabase: SupabaseClient,
  args: {
    tenantUserId: string;
    provider: string;
    templateKey?: string | null;
    templateName: string;
    language: string;
    previousStatus: string | null;
    nextStatus: string;
    templateId?: string | null;
    previousHadTemplateId?: boolean;
    submitFailed?: boolean;
  },
): Promise<void> {
  const provider = String(args.provider ?? '').trim();
  if (!provider || provider === 'evolution' || provider === 'waha' || provider === 'whats360') {
    return;
  }
  const kind = kindForTransition({
    previousStatus: args.previousStatus,
    nextStatus: args.nextStatus,
    templateId: args.templateId ?? null,
    previousHadTemplateId: args.previousHadTemplateId === true,
    submitFailed: args.submitFailed === true,
  });
  if (!kind) return;
  try {
    await notifyTemplateStatusEmail(supabase, {
      userId: args.tenantUserId,
      provider,
      templateName: args.templateName,
      language: args.language || 'ar',
      templateKey: args.templateKey,
      kind,
    });
  } catch (e) {
    console.warn('template status email', String(e).slice(0, 160));
  }
}

export async function applyMetaTemplateStatusUpdates(
  supabase: SupabaseClient,
  updates: Array<{
    wabaId: string;
    event: string;
    templateId: string;
    templateName: string;
    language: string;
    reason: string;
  }>,
): Promise<number> {
  let applied = 0;
  for (const upd of updates) {
    const next = mapMetaTemplateEvent(upd.event);
    if (!next || !upd.templateName) continue;
    const { data: rows } = await supabase
      .from('tenant_whatsapp_templates')
      .select(
        'id, tenant_user_id, provider, template_key, template_name, language, status, template_id',
      )
      .eq('template_name', upd.templateName)
      .eq('language', upd.language);
    const list = rows ?? [];
    if (list.length === 0) continue;
    const userIds = [...new Set(list.map((r) => String(r.tenant_user_id)))];
    const { data: gates } = await supabase
      .from('tenant_whatsapp_gateways')
      .select('user_id, cloud_waba_id')
      .in('user_id', userIds);
    const wabaByUser = new Map<string, string>();
    for (const gate of gates ?? []) {
      wabaByUser.set(String(gate.user_id), String(gate.cloud_waba_id ?? ''));
    }
    for (const row of list) {
      const tenant = String(row.tenant_user_id);
      const gateWaba = wabaByUser.get(tenant) ?? '';
      if (upd.wabaId && gateWaba && gateWaba !== upd.wabaId) continue;
      const previous = String(row.status ?? 'none');
      const previousId = row.template_id ? String(row.template_id) : null;
      const templateId = upd.templateId || previousId;
      if (previous === next && previousId === templateId) continue;
      await supabase
        .from('tenant_whatsapp_templates')
        .update({
          status: next,
          template_id: templateId,
          last_error: next === 'rejected' && upd.reason
            ? upd.reason.slice(0, 200)
            : null,
          updated_at: new Date().toISOString(),
        })
        .eq('id', row.id);
      await maybeNotifyTemplateStatus(supabase, {
        tenantUserId: tenant,
        provider: String(row.provider ?? ''),
        templateKey: row.template_key ? String(row.template_key) : null,
        templateName: String(row.template_name),
        language: String(row.language ?? upd.language),
        previousStatus: previous,
        nextStatus: next,
        templateId,
        previousHadTemplateId: Boolean(previousId),
      });
      applied += 1;
    }
  }
  return applied;
}

export function mapMetaTemplateEvent(event: string): 'pending' | 'approved' | 'rejected' | null {
  const raw = event.toUpperCase();
  if (raw.includes('APPROV')) return 'approved';
  if (raw.includes('REJECT')) return 'rejected';
  if (raw === 'PENDING') return 'pending';
  return null;
}
