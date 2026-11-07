import {
  assertEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  injectShopNameIntoText,
  isGenericShopName,
} from './resolve_shop_name.ts';

Deno.test('المحل والفراغ أسماء عامة', () => {
  assertEquals(isGenericShopName(''), true);
  assertEquals(isGenericShopName('المحل'), true);
  assertEquals(isGenericShopName('مركز النجوم'), false);
});

Deno.test('حقن اسم المحل في نص البطاقة', () => {
  const raw =
    'مرحباً حميد، شكراً لزيارتكم *المحل* لغيار الزيت 🙏';
  const out = injectShopNameIntoText(raw, 'مركز النجوم');
  assertEquals(out.includes('*مركز النجوم*'), true);
  assertEquals(out.includes('*المحل*'), false);
});

Deno.test('لا يُستبدل إن الاسم ما زال عاماً', () => {
  const raw = 'شكراً لزيارتكم *المحل*';
  assertEquals(injectShopNameIntoText(raw, 'المحل'), raw);
});
