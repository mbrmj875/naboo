/**
 * موافقة الزبون على التذكير. لا يمنع الإرسال إلا طلب الإيقاف،
 * لأن الموافقة تتم عند الفاتورة الأولى والتذكيرات تخرج في مواعيدها.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

/** آخر 10 أرقام، حتى يطابق 07XXXXXXXXX الرقم 9647XXXXXXXXX. */
export function phoneKey(phone: string | null | undefined): string {
  return String(phone ?? '').replace(/\D/g, '').slice(-10);
}

export type ConsentCheck = 'allowed' | 'opted_out' | 'unknown';

/** غياب الجدول يسمح، وأي خطأ آخر يؤجل الفحص حتى لا نراسل من طلب الإيقاف. */
export async function checkRecipientConsent(
  db: SupabaseClient,
  tenantUserId: string,
  phone: string,
): Promise<ConsentCheck> {
  const { data, error } = await db
    .from('wa_recipient_consent')
    .select('status')
    .eq('tenant_user_id', tenantUserId)
    .eq('phone_key', phoneKey(phone))
    .maybeSingle();
  if (error) {
    if (error.code === '42P01') return 'allowed';
    console.warn('consent read failed', error.message);
    return 'unknown';
  }
  return data?.status === 'opted_out' ? 'opted_out' : 'allowed';
}

/** طلب الزبون الإيقاف: يسجله ويلغي تذكيراته عند هذا المتجر فقط. */
export async function applyCustomerOptOut(
  db: SupabaseClient,
  tenantUserId: string,
  phone: string,
): Promise<number> {
  const key = phoneKey(phone);
  if (key.length < 8) return 0;
  const now = new Date().toISOString();
  const { error } = await db.from('wa_recipient_consent').upsert({
    tenant_user_id: tenantUserId,
    phone_key: key,
    status: 'opted_out',
    source: 'customer_reply',
    updated_at: now,
  }, { onConflict: 'tenant_user_id,phone_key' });
  if (error) {
    console.warn('opt out write failed', error.message);
    return 0;
  }
  const { data: queued } = await db
    .from('wa_oil_followup_jobs')
    .select('id, customer_phone')
    .eq('tenant_user_id', tenantUserId)
    .eq('status', 'queued');
  const ids = (queued ?? [])
    .filter((j) => phoneKey(String(j.customer_phone)) === key)
    .map((j) => j.id);
  if (ids.length === 0) return 0;
  await db.from('wa_oil_followup_jobs').update({
    status: 'cancelled',
    last_error: 'opted_out',
    updated_at: now,
  }).in('id', ids);
  return ids.length;
}

/** الزبون نفسه طلب إعادة التذكيرات. التذكيرات الملغاة لا تعود، وتبدأ مع البطاقة التالية. */
export async function applyCustomerOptIn(
  db: SupabaseClient,
  tenantUserId: string,
  phone: string,
): Promise<void> {
  const key = phoneKey(phone);
  if (key.length < 8) return;
  const { error } = await db.from('wa_recipient_consent').upsert({
    tenant_user_id: tenantUserId,
    phone_key: key,
    status: 'consented',
    source: 'customer_reply',
    updated_at: new Date().toISOString(),
  }, { onConflict: 'tenant_user_id,phone_key' });
  if (error) console.warn('opt in write failed', error.message);
}

/** تذكيرات حان موعدها وتنتظر حل مشكلة، وتخرج وحدها بعد حلها. */
export async function countHeldReminders(
  db: SupabaseClient,
  tenantUserId: string,
): Promise<number> {
  const { count, error } = await db
    .from('wa_oil_followup_jobs')
    .select('id', { count: 'exact', head: true })
    .eq('tenant_user_id', tenantUserId)
    .eq('status', 'queued')
    .lte('due_at', new Date().toISOString())
    .not('last_error', 'is', null);
  if (error) return 0;
  return count ?? 0;
}
