# خط إنتاج Stitch + Figma — قوالب المنيو

## الهدف
**1 رابط Figma = 1 تصميم جاهز** في المعرض (~28) بهيكل مميز + إعدادات متقدمة للتخصيص.
ليس نموذج «10 عائلات × 5 ألوان».

## الخطوات لكل إلهام
1. سجّل الصف في [`restaurant_menu_template_research_ar.md`](./restaurant_menu_template_research_ar.md).
2. Stitch: شاشة عربية RTL — رئيسية منيو بنفس عقد القشرة (بحث، شريط، ملف) + هوية مطعم ظاهرة.
3. (اختياري) Figma Components للمتغيرات — بدون استيراد Community كأصل.
4. الكود: `preset_key` + `RestaurantMenuChrome` في [`presets.dart`](../../lib/verticals/restaurant/theme/presets/presets.dart) + صف في [`gallery_catalog.dart`](../../lib/verticals/restaurant/theme/gallery_catalog.dart) + `presetCssVars` / CSS.
5. QA: فرق هيكلي، هوية، تباين بحث، RTL، قشرة، عزل tenant.

## مشروع Stitch
- المشروع: **Naboo Public Menu** (`projects/11277511862500845773`).
- Design System الأساسي: **Naboo Restaurant** (`assets/7a0cdbdbfd894731a80ab52931765d5a`) — فحمي/كهرماني، ممنوع بنفسجي.
- عيّنات مولَّدة (مرجع بصري، الكود مصدر الحقيقة):
  - Menu Home photo-stack — `screens/378408e04a0b434ba345d3e492e455f1`
  - App-grid home — `screens/20bc2c0b3ca14fe98a0f12789bbba89d`
  - Editorial / menu-board — `screens/c2542ac0740c418880aa502bfb779aea`
  - Side-rail — `screens/2a087ba807504879b3969131e83d04cc`
  - Theme editor (mobile) — `screens/17ab18034bdb4360b3d065f8396f6b31`
- محرر الثيم في Flutter أعيد بناؤه (هوية أولاً + شبكة 28)؛ كومبوزيشن Stitch للمحرر مرجع إضافي.

## التسليم
- الكود مصدر الحقيقة للمنتج المنشور.
- كومبوزيشن Stitch مرجع بصري فقط — لا يُستورد HTML خام.
