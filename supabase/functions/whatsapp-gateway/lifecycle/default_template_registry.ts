/**
 * سجل القوالب الافتراضية — TemplateLifecycle يقرأ منه فقط.
 */

import { TemplateKey } from '../notifications/notification_request.ts';

export type DefaultTemplateSpec = {
  key: TemplateKey;
  name: string;
  language: string;
  category: 'utility' | 'marketing' | 'authentication';
  bodyText: string;
  /** ترتيب متغيّرات القالب: paramKeys[i] يقابل {{i+1}} في النص. */
  paramKeys: string[];
  exampleBodyParams: string[];
};

const RATING_ASK = '⭐ تقييمكم يهمّنا:\n' +
  'ردّوا برقم من *1 إلى 10* لجودة العمل (مثال: 9)\n' +
  'أو اكتبوا ملاحظة قصيرة عن الخدمة — ردّكم يصل مباشرة للمحل 💬';

/** البطاقة الطويلة: كل حقل في سطره — ميتا ترفض الأسطر داخل المعاملات. */
export const oilChangeCardLongTemplate: DefaultTemplateSpec = {
  key: TemplateKey.oilChangeCard,
  name: 'oil_card_lines_ar',
  language: 'ar_EG',
  category: 'utility',
  bodyText: 'مرحباً {{1}}،\n' +
    'شكراً لزيارتكم *{{2}}* لغيار الزيت 🙏\n\n' +
    '🚗 *السيارة:* {{3}}\n' +
    '📅 *موديل السيارة:* {{4}}\n' +
    '⚙️ *حجم المحرك:* {{5}}\n' +
    '🔖 *رقم اللوحة:* {{6}}\n' +
    '🔢 *القراءة الحالية:* {{7}}\n' +
    '📍 *القراءة اللاحقة:* {{8}}\n\n' +
    '🛢️ *الزيت:*\n' +
    '• *النوع:* {{9}}\n' +
    '• *الدرجة:* {{10}}\n' +
    '• *الحجم:* {{11}}\n\n' +
    '🧴 *هيدروليك القير:* {{12}}\n' +
    '🧴 *هيدروليك الباور:* {{13}}\n\n' +
    '🔧 *الفلاتر:* {{14}}\n' +
    '🛒 *المنتجات:* {{15}}\n' +
    '📋 *الخدمات الإضافية:* {{16}}\n\n' +
    '💰 *السعر والدفع:*\n' +
    '• *قبل التخفيض:* {{17}}\n' +
    '• *قيمة الخصم:* {{18}}\n' +
    '• *الإجمالي:* {{19}}\n' +
    '• *المدفوع:* {{20}}\n' +
    '• *المتبقي:* {{21}}\n\n' +
    '👤 *الموظف:* {{22}}\n' +
    '📝 *ملاحظات:* {{23}}\n\n' +
    'نراكم عند موعد الصيانة القادمة ✨\n\n' +
    RATING_ASK,
  paramKeys: [
    'customer',
    'shop',
    'car',
    'car_model',
    'engine',
    'plate',
    'odo_current',
    'odo_next',
    'oil_brand',
    'oil_grade',
    'oil_size',
    'hyd_gear',
    'hyd_power',
    'filters',
    'products',
    'services',
    'price_before',
    'discount',
    'total',
    'paid',
    'remaining',
    'employee',
    'notes',
  ],
  exampleBodyParams: [
    'باقر',
    'المحل',
    'تويوتا',
    '2020',
    '2.5',
    '12345',
    '150066 كم',
    '155066 كم',
    'كاسترول',
    '0W20',
    '5 L',
    'ATF، Dexron، 1 L',
    '-',
    'فلتر زيت: بوش، فلتر هواء: أصلي',
    'مساح زجاج',
    'غسيل محرك',
    '19440 د.ع',
    '5000 د.ع',
    '14440 د.ع',
    '10000 د.ع',
    '4440 د.ع',
    'محمد',
    'يفضّل زيوت أصلية',
  ],
};

/** احتياط: تُستعمل إن لم يكن القالب الطويل معتمداً على WABA المحل. */
export const oilChangeCardShortTemplate: DefaultTemplateSpec = {
  key: TemplateKey.oilChangeCard,
  name: 'oil_change_card_ar',
  language: 'ar',
  category: 'utility',
  bodyText: 'مرحباً {{1}}،\n' +
    'شكراً لزيارتكم *{{2}}* لغيار الزيت 🙏\n\n' +
    '{{3}}\n\n' +
    RATING_ASK,
  paramKeys: ['customer', 'shop', 'details'],
  exampleBodyParams: [
    'أحمد',
    'مركز نابو',
    '📆 التاريخ: 29/7/2026\n🚗 السيارة: تويوتا\n💰 السعر والدفع:\n• الإجمالي: 25000 د.ع',
  ],
};

/** قوالب مطلوبة لعمودي غيار الزيت بعد الربط الرسمي */
export const oilChangeDefaultTemplates: DefaultTemplateSpec[] = [
  oilChangeCardLongTemplate,
  oilChangeCardShortTemplate,
];

/** الأفضلية أولاً ثم البدائل — القناة تجرّبها بالترتيب. */
export function resolveTemplateSpecs(key: TemplateKey): DefaultTemplateSpec[] {
  const hits = oilChangeDefaultTemplates.filter((t) => t.key === key);
  return hits.length > 0 ? hits : [oilChangeCardShortTemplate];
}

export function resolveProviderTemplateName(key: TemplateKey): string {
  const hit = oilChangeDefaultTemplates.find((t) => t.key === key);
  return hit?.name ?? key;
}

export function resolveProviderTemplateLanguage(key: TemplateKey): string {
  const hit = oilChangeDefaultTemplates.find((t) => t.key === key);
  return hit?.language ?? 'ar';
}
