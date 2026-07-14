# Expenses Screen — Spec v1.0 (Royal UI Revamp)

> **Status:** Approved — Final Review  
> **Version:** 1.0  
> **Scope:** Visual upgrade of `lib/screens/expenses/expenses_screen.dart` and its private widgets only  
> **Date:** 2026-05-24  
> **Related:** Debts Spec v1.4.0 · Customers Spec v1.2.1 · `docs/screen_migration_playbook.md`

---

## 🎯 الهدف

ترقية واجهة **المصروفات** لتتوافق مع **دستور التصميم الملكي** لـ Naboo ERP:

- تجربة **Premium** (فخامة + عمق بصري) مع الحفاظ على **جدية ERP محاسبي**
- **لا regressions** على باقي النظام — تعديلات محلية على طبقة الواجهة فقط
- **إعادة استخدام** الأنماط المثبتة في الديون (v1.4.0) والعملاء (v1.2.x)
- **أداء آمن** على الموبايل (بدون `BackdropFilter` ثقيل على الهاتف)

---

## 🔍 تشخيص الوضع الحالي (Code Audit)

الملف الرئيسي: `lib/screens/expenses/expenses_screen.dart` (~3500 سطر).

| العنصر | الموقع | المشكلة |
|--------|--------|---------|
| KPI chips | `_ExpenseStatChip` (~L3499) | `Border.all(outlineVariant)` + عناوين `onSurfaceVariant` باهتة + قيم `14px` |
| شريط KPI | `_ExpensesStatsBar` (~L3388) | `Row` + `Expanded` — يتمدد بعرض الديسكتوب كاملاً؛ لا glass |
| البحث | `_ExpensesLedgerTab` (~L774) | `AppInput` تقليدي داخل بطاقة فلاترة؛ ليس Search Dock بلوري |
| بطاقة الإجمالي | `_ExpensesLedgerTab` index 1 (~L611) | `Material` + `outlineVariant` حول صندوق المبلغ |
| صف المصروف | `_ExpensesLedgerTab` (~L966) | `RoundedRectangleBorder` + `outlineVariant`؛ تمييز بـ `primary` border |
| التبويبات | `TabBar` (~L462) | «السجل» / «تحليلات» — بدون `unselectedLabelColor` مخصص |
| إضافة مصروف | `FloatingActionButton.extended` (~L470) | FAB أساسي + `FilledButton` في الحالة الفارغة؛ بدون لمسة ذهبية |
| تمييز صف جديد | `_highlightExpenseId` | موجود — يُستغل للخط الذهبي الجانبي |

**ملاحظة:** بحث `home_screen` العام (وحدات، منتجات، عملاء…) منفصل سياقياً. الهدف: جعل بحث المصروفات **بلورياً وواضحاً** حتى لا يُ perceived كتكرار مزعج.

---

## 📐 قرارات التصميم الاستراتيجية

### 1. الذهب الملكي وإطار اللوحة (Royal Gold Frame)

| الحالة | النمط | المصدر |
|--------|-------|--------|
| **إطار دائم (Framed)** | إطار ذهبي رفيع ومزدوج (أو دقيق) يحيط بالحاويات الرئيسية ومربعات البحث والأزرار الثانوية، يعطي إحساساً بشهادة فخمة أو لوحة. | مستوحى من شاشة "سجل غيارات الزيت" |
| أساس (Matte) | نصوص، أيقونات، شارات | `AppColors.accentGold` — `design_tokens.dart` |
| تفاعل (Gradient) | زيادة سماكة/توهج الإطار الذهبي عند الـ Focus/Hover | تدرج خفيف (نفس نمط الديون/العملاء) |

**قاعدة الدستور المُعدّلة:** الذهب ليس فقط للتفاعل؛ بل يُشكل **"إطاراً ملكياً"** ثابتاً ورفيعاً يحيط بكتل المحتوى الرئيسية (مثل الحاوية الكبيرة للقائمة وحقل البحث) ليفصلها بصرياً بفخامة بدلاً من الحدود الرمادية.

### 2. الحدود والزوايا

- **إزالة نهائية** لـ `Border.all(outlineVariant)` من بطاقات KPI والقائمة والحاويات.
- **البديل الحصري:** استخدام **الإطار الذهبي الملكي (Royal Gold Frame)** حول حاوية المحتوى الرئيسية وحقل البحث، واستخدام ظلال ناعمة أو `surfaceTint` للعناصر الداخلية الصغيرة.
- **زوايا:** `context.appCorners` حصرياً — **لا** `BorderRadius` ثابت يتجاوز إعداد النظام.

### 3. Glassmorphism والأداء

| المنصة | الشرط | التأثير |
|--------|-------|---------|
| ديسكتوب / تابلت | `!ScreenLayout.of(context).isHandsetForLayout` | `BackdropFilter` + `AppGlass.surfaceTintStrong` |
| موبايل | `isHandsetForLayout` | `AppGlass.surfaceTint` فقط — **بدون** blur ثقيل |

> مرجع skill: `.cursor/skills/flutter-responsive-rtl/SKILL.md` — تجنب blur داخل قوائم طويلة على الهاتف.

### 4. إعادة الاستخدام (بدون Theme عالمي الآن)

- استعارة نمط **Debts v1.4.0**: `_buildUnifiedSearchDock`, `_MetricBox` glass + active filter
- استعارة نمط **Customers**: Search Dock مزدوج الإطار عند التركيز
- **تأجيل** استخراج إلى `lib/widgets/brand/` أو `ThemeExtension` حتى استقرار الواجهة

### 5. Layer Freeze

وفق `screen_migration_playbook.md`:

- ✅ `expenses_screen.dart` + widgets خاصة به
- ❌ `services/`, `providers/`, `models/`, `navigation/`
- ❌ تعديل `_reload()` / debounce / استعلامات DB

---

## 🔗 الربط المنطقي (Logic Binding)

| UI | ربط منطقي | لماذا |
|----|-----------|-------|
| KPI «مصروف اليوم» | `isActive` عند `_ExpenseDatePreset.today` | يطابق `_from`/`_to` = اليوم |
| KPI «هذا الشهر» | `isActive` عند `_ExpenseDatePreset.thisMonth` | يطابق شهر التقويم الحالي |
| KPI أخرى | بدون active (أو ربط لاحق بالفئة الأعلى) | تجنب ديكور بلا معنى |
| البحث | `_searchFocus.addListener` + debounce **300ms** الحالي | لا تغيير في `_onSearchChanged` → `_reload()` |
| صف مصروف | `_highlightExpenseId == e.id` | خط ذهبي `start` بعرض 3–4px |
| preset التاريخ | `OutlinedButton` اليوم/أسبوع/شهر/سنة | إبراز ذهبي للزر المطابق للنطاق الحالي (اختياري مرحلة B+) |

**دالة مساعدة مقترحة:**

```dart
_ExpenseDatePreset? _activeDatePreset(DateTime from, DateTime to) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (from == today && to == today) return _ExpenseDatePreset.today;
  if (from == today.subtract(const Duration(days: 6)) && to == today) {
    return _ExpenseDatePreset.thisWeek;
  }
  if (from == DateTime(now.year, now.month, 1) && to == today) {
    return _ExpenseDatePreset.thisMonth;
  }
  if (from == DateTime(now.year, 1, 1) && to == today) {
    return _ExpenseDatePreset.thisYear;
  }
  return null;
}
```

---

## 🛠️ ترتيب التنفيذ المعتمد

> **A → C → B → D → E** — البحث (C) مبكراً لـ WOW Factor فوري.

### المرحلة A — تباين KPIs والتبويبات

**المكونات:** `_ExpenseStatChip`, `TabBar`

| قبل | بعد |
|-----|-----|
| عنوان `11.5px` + `onSurfaceVariant` | `11–12px` + `white 0.82` (داكن) / `onSurface 0.72` (فاتح) |
| قيمة `14px` / `w800` | `19px` / `FontWeight.w900` |
| `border: outlineVariant` | إزالة — `surface` + tint/ظل |
| TabBar افتراضي | `unselectedLabelColor`: `white 0.55` (داكن) / `onSurface 0.55` (فاتح) |

**تحقق:** قراءة «مصروف اليوم» و«هذا الشهر» على Navy في الوضع الداكن.

---

### المرحلة C — Search Dock الموحد (قبل B)

**المكونات:** `_ExpensesLedgerTab` — استبدال `AppInput` للبحث

**مواصفات `_buildUnifiedSearchDock`:**

```dart
// imports: dart:ui ImageFilter, app_corner_style.dart, design_tokens.dart
Widget _buildUnifiedSearchDock({
  required TextEditingController controller,
  required FocusNode focusNode,
  required ColorScheme cs,
  required bool isDark,
}) { /* نفس هيكل debts_screen / customers_screen */ }
```

- `filled: false`
- إطار خارجي: gradient ذهبي **عند Focus فقط**؛ idle: `royalGold alpha 0.35`
- padding خارجي `3px` + إطار داخلي رفيع
- `hint`: «بحث (وصف أو فئة)… (Ctrl+F)»
- `_searchFocus.addListener(() => setState(() {}))` في `_ExpensesScreenState`

**موضع:** أعلى منطقة الفلاتر في `_ExpensesLedgerTab` (index 1)، أو رفع إلى `Column` فوق `TabBarView` إن أمكن بدون كسر التخطيط.

**تحقق:** Ctrl+F يركز البحث؛ debounce 300ms يعمل؛ `_reload()` unchanged.

---

### المرحلة B — KPIs زجاجية + maxWidth

**المكونات:** `_ExpensesStatsBar`, `_ExpenseStatChip`

- `_ExpensesContentWidth`: `ConstrainedBox(maxWidth: 1200)` + `Align.center`
- Glass مشروط: `BackdropFilter` على desktop/tablet فقط
- `isActiveFilter` على chip «اليوم» / «الشهر» حسب `_activeDatePreset`
- Active: `border` ذهبي `1.2px` + `AppGlass.goldGlow` shadow
- Hover: `AppColors.accentGold alpha 0.08`

**تحقق:** على 1920px العرض KPIs لا تتمدد؛ النقر على chip لا يغيّر الفلتر (غير KPI الديون) — **visual only** ما لم يُربط لاحقاً بـ preset.

---

### المرحلة D — القائمة الملكية

**المكونات:** صف المصروف في `_ExpensesLedgerTab` (~L966)

| قبل | بعد |
|-----|-----|
| `side: BorderSide(outlineVariant)` | بدون outline — `elevation` خفيف أو surface tint |
| `highlighted` → `primary` border 2px | `Stack` + `PositionedDirectional(start)` خط ذهبي 3–4px |
| أيقونة الفئة `border` | tint فقط — بدون outline صلب |

**مرجع:** `_DebtCard` في `debts_screen.dart` — شريط جانبي دلالي.

**تحقق:** بعد حفظ مصروف جديد، `_highlightExpenseId` يُظهر الخط الذهبي 3 ثوانٍ.

---

### المرحلة E — CTA إضافة مصروف

**المكونات:**

- `FloatingActionButton.extended` (~L470) — **الزر الأساسي**
- `FilledButton.icon` في empty state (~L941)

**الإجراء:**

- FAB: `backgroundColor` / foreground من `cs`؛ overlay ذهبي gradient على `hover`/`focus`
- **لا FAB ثانٍ** — تحسين الموجود فقط
- اختصار `Ctrl+N` / `Cmd+N` — **يُحفظ** (`_ExpenseShortcutAdd`)

**تحقق:** FAB يظهر على الموبايل؛ لا تعارض `heroTag`.

---

## ✅ معايير القبول (Definition of Done)

- [ ] `dart analyze lib/screens/expenses/expenses_screen.dart` — بدون errors
- [ ] RTL: `EdgeInsetsDirectional`, خط ذهبي على `start`
- [ ] Dark + Light: KPIs مقروءة في كلا الوضعين
- [ ] Phone + Desktop: glass على desktop فقط
- [ ] `_reload()` / فلاتر DB / مبالغ `int`/fils — **لم تُمس**
- [ ] Hot restart على 3 مقاسات (هاتف، تابلت، ديسكتop 1200+)
- [ ] لا `print()` — `AppLogger` إن لزم logging

---

## 🚫 مؤجلات استراتيجية (Deferred)

| البند | السبب | الملف |
|-------|-------|-------|
| شريط تنقل سفلي عائم | يؤثر على كل التطبيق | `home_screen.dart` |
| ThemeExtension / Theme عالمي | regressions واسعة | `lib/theme/` |
| استخراج `RoyalSearchDock` widget | بعد استقرار v1.0 | `lib/widgets/brand/` |
| Master-Detail للمصروفات | تعقيد معماري | — |
| KPI قابلة للنقر كفلتر | خارج نطاق v1.0 | — |

---

## 📚 مراجع الكود (Patterns to Copy)

| النمط | مرجع |
|-------|------|
| Search Dock مزدوج | `lib/screens/debts/debts_screen.dart` → `_buildUnifiedSearchDock` |
| KPI glass + active | `debts_screen.dart` → `_MetricBox`, `_SummaryStrip` |
| خط جانبي selected | `debts_screen.dart` → `_DebtCard` |
| ألوان + glass | `lib/theme/design_tokens.dart` → `AppColors`, `AppGlass` |
| زوايا | `lib/theme/app_corner_style.dart` → `context.appCorners` |
| RTL | `.cursor/rules/arabic-rtl.mdc` |

---

## 💬 مراجعة خبيرة — ملخص القرارات

### ما تم اعتماده

1. **Spec محلي** على `expenses_screen.dart` — لا Theme عالمي في v1.0  
2. **Matte + Gradient عند التفاعل** للذهب — كلاسيكي ERP + لمسة ملكية  
3. **A → C → B → D → E** — بحث مبكر للـ WOW  
4. **Glass مشروط بالمنصة** — أداء الموبايل محفوظ  
5. **KPI active** مربوط بـ preset التاريخ — ليس ديكوراً  
6. **`_highlightExpenseId`** للخط الذهبي — لا state جديد  

### تصحيحات على المسودات الأولى

| المسودة | التصحيح في v1.0 |
|---------|-----------------|
| زوايا دائرية ثابتة `16px` | `context.appCorners` فقط |
| خطوط ذهبية على جانبي القائمة كاملة | خط `start` للعنصر المحدد فقط (درس من شاشة العملاء) |
| زر AppBar لل') | **FAB.extended** هو CTA الأساسي في الكود الحالي |
| Theme على مستوى التطبيق | مؤجل — widgets محلية أولاً |
| KPI تفلتر مثل الديون | KPI المصروفات إحصائية — active = visual + preset binding |

---

## 📅 سجل المراجعات

| التاريخ | الإصدار | الحالة |
|---------|---------|--------|
| 2026-05-24 | 1.0 | **معتمد — جاهز للتنفيذ** |

---

## ▶️ الخطوة التالية

عند بدء التنفيذ:

1. فرع git منفصل (مثلاً `feat/expenses-ui-v1.0`)
2. تنفيذ **A + C** أولاً → مراجعة بصرية
3. ثم **B → D → E**
4. PR واحد — شاشة واحدة (`One Screen Per PR` من الدستور)

**لا يُنفَّذ أي كود قبل موافقة صريحة على البدء في التطوير.**
