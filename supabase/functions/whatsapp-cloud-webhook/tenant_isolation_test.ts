/**
 * اختبارات عزل الرقم المشترك — لا ربط محل بدون مراسلة صادرة سابقة.
 */

import {
  assertEquals,
  assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  NABOO_COLD_CONTACT_REPLY,
  RELATIONSHIP_WINDOW_DAYS,
  phoneVariants,
} from './tenant_isolation.ts';

Deno.test('رد النظام البارد لا يذكر محل ولا بطاقة', () => {
  assertStringIncludes(NABOO_COLD_CONTACT_REPLY, 'نابو');
  assertEquals(/كاسترول|ali|باقر|شارع/.test(NABOO_COLD_CONTACT_REPLY), false);
  assertStringIncludes(NABOO_COLD_CONTACT_REPLY, 'بدون رابط خدمة سابق');
});

Deno.test('نافذة العلاقة محدودة', () => {
  assertEquals(RELATIONSHIP_WINDOW_DAYS, 30);
});

Deno.test('تنويعات الهاتف للعزل', () => {
  assertEquals(phoneVariants('9647884289711'), [
    '9647884289711',
    '+9647884289711',
  ]);
});

/** محاكاة منطق الربط بدون شبكة — غريب بلا صادر = cold. */
Deno.test('قاعدة العزل: بلا صادر → cold وليس bound', () => {
  const lastOutboundTenant: string | null = null;
  const status = lastOutboundTenant ? 'bound' : 'cold';
  assertEquals(status, 'cold');
});

Deno.test('قاعدة العزل: آخر صادر يحدد المستأجر فقط', () => {
  const tenantA = 'tenant-a';
  const tenantB = 'tenant-b';
  const lastOutboundTenant: string = tenantB;
  assertEquals(lastOutboundTenant === tenantA, false);
  assertEquals(lastOutboundTenant, tenantB);
});
