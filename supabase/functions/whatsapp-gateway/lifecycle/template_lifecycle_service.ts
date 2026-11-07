/**
 * دورة حياة القوالب — تقرأ DefaultTemplateRegistry فقط؛ لا ترسل رسائل.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import {
  getWhatsAppProvider,
  isOfficialTemplateTransport,
  parseTransportId,
} from '../providers/registry.ts';
import {
  oilChangeDefaultTemplates,
  type DefaultTemplateSpec,
} from './default_template_registry.ts';
import { writeClient } from '../admin_client.ts';
import { maybeNotifyTemplateStatus } from './template_status_email.ts';

export async function ensureDefaultTemplatesForTenant(
  supabase: SupabaseClient,
  tenantUserId: string,
  specs: DefaultTemplateSpec[] = oilChangeDefaultTemplates,
): Promise<{ ok: boolean; detail?: string }> {
  const db = writeClient(supabase);
  const { data: gate } = await db
    .from('tenant_whatsapp_gateways')
    .select('whatsapp_provider, cloud_waba_id')
    .eq('user_id', tenantUserId)
    .maybeSingle();

  const providerId = parseTransportId(gate?.whatsapp_provider);
  if (!isOfficialTemplateTransport(providerId)) {
    return { ok: true, detail: 'skip_non_official' };
  }

  const provider = getWhatsAppProvider(providerId);
  if (!provider?.capabilities.supportsTemplates) {
    return { ok: true, detail: 'templates_unsupported' };
  }

  const wabaId = String(gate?.cloud_waba_id ?? '').trim();
  const { data: existingRows } = await db
    .from('tenant_whatsapp_templates')
    .select('template_name, language, status, template_id, template_key')
    .eq('tenant_user_id', tenantUserId)
    .eq('provider', providerId);
  const previousByName = new Map<string, {
    status: string;
    templateId: string | null;
    templateKey: string | null;
  }>();
  for (const row of existingRows ?? []) {
    previousByName.set(
      `${String(row.template_name)}|${String(row.language ?? '')}`,
      {
        status: String(row.status ?? 'none'),
        templateId: row.template_id ? String(row.template_id) : null,
        templateKey: row.template_key ? String(row.template_key) : null,
      },
    );
  }
  if (!wabaId) {
    for (const spec of specs) {
      await upsertTemplateRow(db, {
        tenantUserId,
        provider: providerId,
        templateKey: spec.key,
        templateName: spec.name,
        language: spec.language,
        category: spec.category,
        status: 'pending',
      });
    }
    return { ok: true, detail: 'waba_pending' };
  }

  for (const spec of specs) {
    const ensured = await provider.ensureTemplate({
      tenantUserId,
      wabaId,
      templateName: spec.name,
      language: spec.language,
      category: spec.category,
      bodyText: spec.bodyText,
      exampleBodyParams: spec.exampleBodyParams,
    });

    let status: 'pending' | 'approved' | 'rejected' | 'none' = 'pending';
    if (ensured.ok && ensured.status) status = ensured.status;
    if (!ensured.ok) status = 'pending';

    const remote = await provider.getTemplateStatus({
      tenantUserId,
      wabaId,
      templateName: spec.name,
      language: spec.language,
    });
    if (remote.ok && remote.status !== 'unknown' && remote.status !== 'none') {
      status = remote.status;
    }

    const templateId = ensured.templateId ?? remote.templateId ?? null;
    const prev = previousByName.get(`${spec.name}|${spec.language}`);
    await upsertTemplateRow(db, {
      tenantUserId,
      provider: providerId,
      templateKey: spec.key,
      templateName: spec.name,
      language: spec.language,
      category: spec.category,
      status,
      templateId: templateId ?? undefined,
      lastError: ensured.ok ? null : (ensured.detail ?? null),
    });
    await maybeNotifyTemplateStatus(db, {
      tenantUserId,
      provider: providerId,
      templateKey: spec.key,
      templateName: spec.name,
      language: spec.language,
      previousStatus: prev?.status ?? null,
      nextStatus: status,
      templateId,
      previousHadTemplateId: Boolean(prev?.templateId),
    });
  }

  return { ok: true };
}

export async function syncTemplateStatusesForTenant(
  supabase: SupabaseClient,
  tenantUserId: string,
): Promise<void> {
  const db = writeClient(supabase);
  const { data: gate } = await db
    .from('tenant_whatsapp_gateways')
    .select('whatsapp_provider, cloud_waba_id')
    .eq('user_id', tenantUserId)
    .maybeSingle();
  const providerId = parseTransportId(gate?.whatsapp_provider);
  if (!isOfficialTemplateTransport(providerId)) return;
  const wabaId = String(gate?.cloud_waba_id ?? '').trim();
  if (!wabaId) return;

  const provider = getWhatsAppProvider(providerId);
  if (!provider) return;

  const { data: rows } = await db
    .from('tenant_whatsapp_templates')
    .select('id, template_name, language, status, template_key, template_id')
    .eq('tenant_user_id', tenantUserId)
    .eq('provider', providerId);

  for (const row of rows ?? []) {
    if (String(row.status) === 'approved') continue;
    const remote = await provider.getTemplateStatus({
      tenantUserId,
      wabaId,
      templateName: String(row.template_name),
      language: String(row.language ?? 'ar'),
    });
    if (!remote.ok) continue;
    if (remote.status === 'unknown' || remote.status === 'none') continue;
    const previous = String(row.status ?? 'none');
    if (previous === remote.status && (row.template_id || !remote.templateId)) {
      continue;
    }
    await db
      .from('tenant_whatsapp_templates')
      .update({
        status: remote.status,
        template_id: remote.templateId ?? row.template_id ?? null,
        updated_at: new Date().toISOString(),
      })
      .eq('id', row.id);
    await maybeNotifyTemplateStatus(db, {
      tenantUserId,
      provider: providerId,
      templateKey: row.template_key ? String(row.template_key) : null,
      templateName: String(row.template_name),
      language: String(row.language ?? 'ar'),
      previousStatus: previous,
      nextStatus: remote.status,
      templateId: remote.templateId ?? (row.template_id ? String(row.template_id) : null),
      previousHadTemplateId: Boolean(row.template_id),
    });
  }
}

async function upsertTemplateRow(
  supabase: SupabaseClient,
  args: {
    tenantUserId: string;
    provider: string;
    templateKey: string;
    templateName: string;
    language: string;
    category: string;
    status: string;
    templateId?: string;
    lastError?: string | null;
  },
): Promise<void> {
  const now = new Date().toISOString();
  await supabase.from('tenant_whatsapp_templates').upsert(
    {
      tenant_user_id: args.tenantUserId,
      provider: args.provider,
      template_key: args.templateKey,
      template_name: args.templateName,
      language: args.language,
      category: args.category,
      status: args.status,
      template_id: args.templateId ?? null,
      last_error: args.lastError ?? null,
      updated_at: now,
    },
    { onConflict: 'tenant_user_id,provider,template_name,language' },
  );
}
