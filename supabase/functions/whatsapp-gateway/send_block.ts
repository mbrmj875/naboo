/**
 * إيقاف طابور الإرسال عند خطأ حساب، حتى لا يُخصم رصيد لرسائل ستفشل.
 * كل 30 دقيقة تمر رسالة واحدة تجربةً، وأول تسليم مؤكد يرفع الإيقاف.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import type { FailureDecision } from './failure_policy.ts';

const PROBE_INTERVAL_MS = 30 * 60_000;

export type SendBlockState = {
  blocked: boolean;
  scope?: 'tenant' | 'platform';
  reason?: string;
  since?: string;
};

async function platformSettingsId(db: SupabaseClient): Promise<unknown | null> {
  const { data } = await db
    .from('wa_message_platform_settings')
    .select('id')
    .limit(1)
    .maybeSingle();
  return data?.id ?? null;
}

/** قراءة فقط. خطأ القراءة لا يوقف الإرسال، فالرصيد له حارس آخر. */
export async function readSendBlock(
  db: SupabaseClient,
  tenantUserId: string,
): Promise<SendBlockState> {
  try {
    const { data: gate, error } = await db
      .from('tenant_whatsapp_gateways')
      .select('whatsapp_provider, send_block_reason, send_block_since')
      .eq('user_id', tenantUserId)
      .maybeSingle();
    if (error) {
      console.warn('send_block read failed', error.message);
      return { blocked: false };
    }
    if (gate?.send_block_reason) {
      return {
        blocked: true,
        scope: 'tenant',
        reason: String(gate.send_block_reason),
        since: String(gate.send_block_since ?? ''),
      };
    }
    if (String(gate?.whatsapp_provider ?? '') !== 'dualhook') {
      return { blocked: false };
    }
    const { data: platform, error: platformErr } = await db
      .from('wa_message_platform_settings')
      .select('send_block_reason, send_block_since')
      .limit(1)
      .maybeSingle();
    if (platformErr) {
      console.warn('send_block platform read failed', platformErr.message);
      return { blocked: false };
    }
    if (platform?.send_block_reason) {
      return {
        blocked: true,
        scope: 'platform',
        reason: String(platform.send_block_reason),
        since: String(platform.send_block_since ?? ''),
      };
    }
    return { blocked: false };
  } catch (e) {
    console.warn('send_block read exception', e);
    return { blocked: false };
  }
}

/** يحجز محاولة التجربة ذريًا: طلب واحد فقط يفوز بها في كل نافذة. */
async function claimProbe(
  db: SupabaseClient,
  tenantUserId: string,
  block: SendBlockState,
): Promise<boolean> {
  const since = Date.parse(block.since ?? '');
  if (!Number.isFinite(since) || Date.now() - since < PROBE_INTERVAL_MS) {
    return false;
  }
  const now = new Date().toISOString();
  if (block.scope === 'tenant') {
    const { data } = await db
      .from('tenant_whatsapp_gateways')
      .update({ send_block_since: now })
      .eq('user_id', tenantUserId)
      .eq('send_block_since', block.since)
      .select('user_id')
      .maybeSingle();
    return !!data;
  }
  const { data } = await db
    .from('wa_message_platform_settings')
    .update({ send_block_since: now })
    .eq('send_block_since', block.since)
    .select('id')
    .maybeSingle();
  return !!data;
}

/** هل يُمنع هذا الإرسال الآن؟ يُستدعى قبل الخصم. */
export async function checkSendBlock(
  db: SupabaseClient,
  tenantUserId: string,
): Promise<SendBlockState> {
  const block = await readSendBlock(db, tenantUserId);
  if (!block.blocked) return block;
  try {
    if (await claimProbe(db, tenantUserId, block)) return { blocked: false };
  } catch (e) {
    console.warn('send_block probe failed', e);
  }
  return block;
}

/**
 * قالب أوقفته Meta يتوقف عند هذا المتجر، أو عند كل المتاجر إذا كان على رقم نابو.
 * التذكيرات تنتظر، وحدث موافقة Meta يعيد الحالة approved.
 */
export async function pauseTemplate(
  db: SupabaseClient,
  tenantUserId: string,
  provider: string,
  templateKey: string,
): Promise<void> {
  let query = db
    .from('tenant_whatsapp_templates')
    .update({
      status: 'disabled',
      last_error: 'template_paused',
      updated_at: new Date().toISOString(),
    })
    .eq('template_key', templateKey)
    .eq('provider', provider)
    .eq('status', 'approved');
  if (provider !== 'dualhook') query = query.eq('tenant_user_id', tenantUserId);
  await query;
}

/** لا يكتب فوق إيقاف قائم، حتى يبقى وقت البداية وسببها الأول. */
export async function applySendBlock(
  db: SupabaseClient,
  tenantUserId: string,
  decision: FailureDecision,
  template?: { provider: string; templateKey: string | null },
): Promise<void> {
  try {
    if (decision.block === 'template') {
      if (template?.templateKey) {
        await pauseTemplate(
          db,
          tenantUserId,
          template.provider,
          template.templateKey,
        );
      }
      return;
    }
    const patch = {
      send_block_reason: decision.reasonCode,
      send_block_since: new Date().toISOString(),
    };
    if (decision.block === 'tenant') {
      await db
        .from('tenant_whatsapp_gateways')
        .update(patch)
        .eq('user_id', tenantUserId)
        .is('send_block_reason', null);
    } else if (decision.block === 'platform') {
      const id = await platformSettingsId(db);
      if (id === null) return;
      await db
        .from('wa_message_platform_settings')
        .update(patch)
        .eq('id', id)
        .is('send_block_reason', null);
    }
  } catch (e) {
    console.warn('send_block apply failed', e);
  }
}

/** أول تسليم مؤكد يرفع الإيقاف عن المتجر، وعن المنصة إن كان على رقم نابو. */
export async function clearSendBlockAfterDelivery(
  db: SupabaseClient,
  tenantUserId: string,
  provider: string,
): Promise<void> {
  try {
    const clear = { send_block_reason: null, send_block_since: null };
    await db
      .from('tenant_whatsapp_gateways')
      .update(clear)
      .eq('user_id', tenantUserId)
      .not('send_block_reason', 'is', null);
    if (provider === 'dualhook') {
      const id = await platformSettingsId(db);
      if (id === null) return;
      await db
        .from('wa_message_platform_settings')
        .update(clear)
        .eq('id', id)
        .not('send_block_reason', 'is', null);
    }
  } catch (e) {
    console.warn('send_block clear failed', e);
  }
}
