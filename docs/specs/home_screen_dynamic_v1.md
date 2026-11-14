# الشاشة الرئيسية الديناميكية — Spec v1.0

**الحالة:** معتمد · **P3 (Bottom Nav):** مؤجل

## Profiles

| Profile | الشروط |
|---------|--------|
| `retail` | `vertical != oil_change` |
| `oilChangeService` | `oil_change` + `enableOilChange` + `!enablePos` |
| `oilChangeHybrid` | `oil_change` + `enableOilChange` + `enablePos` |

## التنفيذ

- `lib/home/home_dashboard_resolver.dart`
- `lib/home/specs/home_dashboard_spec.dart`
- `lib/home/home_kpi_repository.dart`
- `lib/home/widgets/oil_change_home_dashboard.dart`

## مراحل

- **P0:** CTA ذهبي + شبكة غيار زيت (بدل orbit)
- **P1:** بحث ملكي → `OilChangeHubScreen(initialSearchQuery:)`
- **P2:** KPIs (سيارات نشطة، نواقص زيوت، مبيعات الوردية)
- **P3:** ترتيب Bottom Nav — مؤجل

## KPIs

- **activeCarsInGarage:** `service_orders` بحالة `pending` أو `in_progress` (غيار زيت)
- **stockShortages:** مخزون منخفض لأصناف `stockBaseKind = volumeLiter`
- **todayShiftSalesFils:** مجموع `invoices.total` للوردية المفتوحة
