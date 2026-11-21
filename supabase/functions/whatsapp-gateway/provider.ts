/**
 * اختيار محرك واتساب لكل مستأجر + تنظيف المحرك السابق عند التبديل.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { deleteSession as wahaDeleteSession } from './waha.ts';
import { evolutionFetch, evolutionInstanceNameForUser } from './evolution.ts';

export type WhatsappProvider =
  | 'waha'
  | 'evolution'
  | 'cloud_api'
  | 'whats360'
  | 'ycloud'
  | 'dualhook';

export function parseProvider(raw: unknown): WhatsappProvider {
  const v = String(raw ?? '').trim().toLowerCase();
  if (
    v === 'evolution' ||
    v === 'cloud_api' ||
    v === 'waha' ||
    v === 'whats360' ||
    v === 'ycloud' ||
    v === 'dualhook'
  ) {
    return v;
  }
  return 'waha';
}

export async function readProvider(
  supabase: SupabaseClient,
  userId: string,
): Promise<WhatsappProvider> {
  const { data } = await supabase
    .from('tenant_whatsapp_gateways')
    .select('whatsapp_provider')
    .eq('user_id', userId)
    .maybeSingle();
  return parseProvider(data?.whatsapp_provider);
}

async function deleteEvolutionInstance(instanceName: string): Promise<boolean> {
  try {
    const res = await evolutionFetch(
      `/instance/delete/${encodeURIComponent(instanceName)}`,
      { method: 'DELETE' },
    );
    return res.ok || res.status === 404;
  } catch (e) {
    console.warn('deleteEvolutionInstance failed', e);
    return false;
  }
}

/**
 * عند التبديل: امسح جلسة المحرك غير المستخدم لنفس الاسم حتى لا يتعارض الرقم.
 */
export async function cleanupOtherEngines(args: {
  userId: string;
  next: WhatsappProvider;
}): Promise<{ wahaDeleted: boolean; evolutionDeleted: boolean }> {
  const name = evolutionInstanceNameForUser(args.userId);
  let wahaDeleted = false;
  let evolutionDeleted = false;

  if (
    args.next === 'evolution' ||
    args.next === 'cloud_api' ||
    args.next === 'whats360' ||
    args.next === 'ycloud' ||
    args.next === 'dualhook'
  ) {
    const del = await wahaDeleteSession(name, { timeoutMs: 15_000 });
    wahaDeleted = del.ok || del.timedOut === false;
    // حتى مع timeout نحاول التحقق لاحقاً في المسار التالي
    if (del.ok) wahaDeleted = true;
  }

  if (
    args.next === 'waha' ||
    args.next === 'cloud_api' ||
    args.next === 'whats360' ||
    args.next === 'ycloud' ||
    args.next === 'dualhook'
  ) {
    evolutionDeleted = await deleteEvolutionInstance(name);
  }

  return { wahaDeleted, evolutionDeleted };
}
