# سجل التغييرات — Naboo

جميع التغييرات الملحوظة موثّقة هنا ([Keep a Changelog](https://keepachangelog.com/ar/)).

## [1.0.0] — 2026-06-13

### Added — تخصص الصيدلية v1.0

- **Onboarding** vertical صيدلية + جداول pharmacy + manifest.
- **كتalog أدوية:** INN، ATC، شركات، أشكال جرعة، CSV import.
- **محرّر منتج صيدلاني:** profile + batch + expiry + stock policy.
- **POS:** لوحة دواء (INN · ATC · FEFO · بدائل).
- **تنبيهات سريرية:** تفاعلات، حساسية، جرعة زائدة، منتهي، **صلاحية قريبة ≤30 يوم**، سحب.
- **امتداد العميل:** حساسيات، أدوية مزمنة، ملاحظات طبية.
- **تقارير:** مخزون · مبيعات · مالي · موردين (§9).
- **لوحة المالk:** 12 KPI صيدلانية.
- **Override + audit log** لتجاوز التحذيرات بموافقة الصيدلي.

### Added — Core

- ربط vertical عبر `VerticalRegistry` بدون import مباشر من pharmacy في Core.
- إبطال cache KPIs بعد حفظ الفاتورة.

### Tests

- 72+ اختبار في `test/pharmacy/` (يشمل تحذير الصلاحية القريبة).

### Build

- `version: 1.0.0+1`
- Android: `compileSdk 36` *(مطلوب من androidx.core 1.18+)*، `minSdk 21`, `targetSdk 35`
- iOS: `1.0.0 (1)`
- Release build: `flutter build apk/appbundle --release --no-tree-shake-icons`

---

## [2.0.1] — سابق (Core ERP)

إصدارات ما قبل pharmacy vertical — retail، oil change، owner dashboard v3، إلخ.
