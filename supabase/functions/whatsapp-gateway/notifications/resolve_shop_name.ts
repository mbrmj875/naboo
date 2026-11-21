/**
 * يملأ اسم المحل عندما يرسل التطبيق «المحل» أو فراغاً.
 * الترتيب: اسم محفوظ في التطبيق → لقطة الطباعة → الاسم التجاري في ميتا (verified_name).
 * بلا تحديث APK — على السيرفر فقط.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { buildTenantAiContext } from '../../whatsapp-cloud-webhook/tenant_ai_context.ts';
import { writeClient } from '../admin_client.ts';
import { resolveGraphAccessToken } from '../cloud_api.ts';
import { fetchPhoneDisplay } from '../meta_oauth.ts';

export function isGenericShopName(raw: string | null | undefined): boolean {
  const t = String(raw ?? '').trim();
  return !t || t === 'المحل' || t === '-' || t === '—';
}

/** يستبدل اسم الاحتياطي داخل نص البطاقة باسم المتجر الحقيقي. */
export function injectShopNameIntoText(
  text: string,
  shop: string,
): string {
  const name = String(shop ?? '').trim();
  if (!name || isGenericShopName(name)) return text;
  return String(text ?? '')
    .replace(/\*المحل\*/g, `*${name}*`)
    .replace(/زيارتكم\s+\*?المحل\*?/g, `زيارتكم *${name}*`);
}

async function resolveMetaVerifiedShopName(
  db: SupabaseClient,
  tenantUserId: string,
): Promise<string | null> {
  try {
    const admin = writeClient(db);
    const { data: gate } = await admin
      .from('tenant_whatsapp_gateways')
      .select('cloud_phone_number_id')
      .eq('user_id', tenantUserId)
      .maybeSingle();
    const phoneId = String(gate?.cloud_phone_number_id ?? '').trim();
    if (!phoneId) return null;
    const token = await resolveGraphAccessToken({
      userId: tenantUserId,
      phoneNumberId: phoneId,
    });
    if (!token) return null;
    const display = await fetchPhoneDisplay(phoneId, token);
    const name = String(display.verifiedName ?? '').trim();
    if (!isGenericShopName(name)) return name;
  } catch (e) {
    console.warn(
      'resolveMetaVerifiedShopName failed',
      String(e).slice(0, 120),
    );
  }
  return null;
}

export async function resolveShopNameForCard(
  db: SupabaseClient,
  args: {
    tenantUserId: string;
    shopName: string;
    employeeName?: string | null;
  },
): Promise<string> {
  const incoming = String(args.shopName ?? '').trim();
  if (!isGenericShopName(incoming)) return incoming;

  try {
    const facts = await buildTenantAiContext(db, {
      tenantUserId: args.tenantUserId,
      card: null,
      employeeName: args.employeeName ?? null,
    });
    const fromStore = String(facts.storeName ?? '').trim();
    if (!isGenericShopName(fromStore)) return fromStore;
  } catch (e) {
    console.warn('resolveShopNameForCard failed', String(e).slice(0, 120));
  }

  const fromMeta = await resolveMetaVerifiedShopName(db, args.tenantUserId);
  if (fromMeta) return fromMeta;

  return incoming || 'المحل';
}
