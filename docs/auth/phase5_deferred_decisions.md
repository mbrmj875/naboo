# مرحلة 5 — قرارات وتنفيذ

> **مرجع:** [`google_auth_implementation.md`](google_auth_implementation.md) — الأقسام 6 (F1–F4) و 7 (التحليل المعماري).  
> **آخر تحديث تنفيذ:** يونيو 2026 — القرارات **1–3 و 5 مكتملة في الكود**؛ onboarding جزئي؛ **4 مؤجّل**.

---

## القرارات — الحالة

| # | القرار | الحالة | الخيار المعتمد |
|---|--------|--------|----------------|
| 1 | PIN المالك cross-device | **✅ مكتمل** | **B — PIN سحابي + OTP إلزامي قبل الاستعادة** |
| 2 | «حساب موجود» في Google | **✅ مكتمل** | **B — intent login/signup + رفض mismatch** |
| 3 | سحب اللقطة قبل gate الإكمال | **✅ مكتمل** | **A — hydrate + `isGoogleOwnerProfileCompleteAsync` + overlay** |
| 4 | `product_warehouse_stock` | **⏸️ مؤجّل** | **لا تغيير الآن** — يبقى مستثنى من اللقطة |
| 5 | F3 حوار خروج نهائي | **✅ مكتمل** | **PIN 4 + numpad + `isValidPin` + «رمز PIN»** |

---

## القرار 1 — PIN المالك cross-device: **الخيار B** ✅ **مكتمل**

**PIN واحد مشترك — مخزّن سحابياً — يُستعاد عبر OTP إلزامي على البريد قبل أي تطبيق على الجهاز الجديد.**

### ما تم تنفيذه في الكود

| البند | الملف / المكوّن |
|-------|------------------|
| **جدول + RLS + RPC** | [`migrations/20260609_owner_auth_secrets.sql`](../../migrations/20260609_owner_auth_secrets.sql) — `owner_auth_secrets`، `app_upsert_owner_auth_secret`، `app_get_owner_auth_secret` |
| **رفع السر بعد الإعداد** | `OwnerAuthCloudService` + `_pushOwnerAuthToCloud` في `auth_provider` بعد `completeGoogleOwnerProfile` / `finalizeOwnerPin` |
| **تطبيق محلي من السحابة** | `db_users.applyOwnerAuthFromCloud()` |
| **بوابة OTP إلزامية** | `beginOwnerPinRestoreOtpFlow` → [`owner_pin_restore_otp_screen.dart`](../../lib/screens/auth/owner_pin_restore_otp_screen.dart) → `verifyOwnerPinRestoreOtpAndApply` — **لا** `tryRestoreOwnerAuthFromCloud` بدون `_ownerPinRestoreOtpVerified` |
| **مسارات الدخول** | `signInWithGoogle`، `splash_screen`، `login_screen` — توجيه إلى `/owner-pin-restore-otp` |
| **اختبارات** | `test/auth/owner_auth_cloud_service_test.dart`، S7 في `auth_e2e_scenarios_test.dart` |

### ما يبقى (تشغيل / UX — ليس blocker للكود)

| البند | الوصف |
|-------|--------|
| **Migration على Supabase** | تشغيل `20260609_owner_auth_secrets.sql` في الإنتاج قبل OTP حي |
| **حسابات ما قبل Migration** | إعادة حفظ PIN/إكمال ملف مرة واحدة لرفع السر |
| **تنبيه أمني في UI** | «PIN واحد لجميع أجهزتك…» — **موثَّق، غير منفَّذ في الواجهة** |

### ⚠️ ملاحظة أمنية (موثَّقة)

- **PIN واحد مشترك = نقطة ضعف واحدة:** من يملك البريد + OTP قد يستعيد/يربط نفس PIN على جهاز جديد.
- **يجب تنبيه المستخدم** عند الإعداد وعند الاستعادة.

---

## القرار 2 — «حساب موجود» في Google: **الخيار B** ✅ **مكتمل**

**الحساب «موجود» = tenant أكمل جوال + PIN على السحابة (`owner_auth_secrets`) — وليس مجرد صف في `auth.users`.**

### ما تم تنفيذه في الكود

| البند | الملف / المكوّن |
|-------|------------------|
| **Enum intent** | [`lib/models/google_sign_in_intent.dart`](../../lib/models/google_sign_in_intent.dart) — `login` \| `signup` |
| **توقيع الدالة** | `signInWithGoogle({required GoogleSignInIntent intent})` في `auth_provider` |
| **فحص tenant مكتمل** | `_isTenantNabooCompleteOnCloud()` → `OwnerAuthCloudService.instance.fetch()` (RPC `app_get_owner_auth_secret`) |
| **signup + tenant مكتمل** | `_revertGoogleSessionAfterIntentMismatch()` + «**حسابك موجود — اضغط تسجيل الدخول**» |
| **login + tenant غير مكتمل** | نفس الإنهاء + «**لا يوجد حساب — أنشئ حساباً جديداً**» |
| **UI** | `login_screen.dart` — تبويب «دخول» → `login`؛ «إنشاء حساب» → `signup` |
| **اختبار** | S8 في `test/auth/auth_e2e_scenarios_test.dart` |

### F2 (التوثيق)

- يُغلق فجوة زر Google الواحد في التبويبين — كل تبويب له intent + فحص «tenant مكتمل» **بعد hydrate**.

---

## القرار 3 — سحب اللقطة قبل فحص الاكتمال: **الخيار A** ✅ **مكتمل**

**يُحمَّل بيانات السحابة أولاً، ثم يُفحَص اكتمال الحساب (محلي + سحابة).**

### ما تم تنفيذه في الكود

| البند | الملف / التفاصيل |
|-------|------------------|
| **hydrate قبل gate** | `signInWithGoogle`: `hydrateCloudAccountData` **قبل** intent و profile gate · `splash_screen`: hydrate في الإقلاع **قبل** `_resolveStartupRoute` |
| **فحص async** | `isGoogleOwnerProfileCompleteAsync()` — SQLite **أو** `owner_auth_secrets` · **`isGoogleOwnerProfileCompleteLocal(row)`** — sync لمسار OTP فقط |
| **overlay انتظار** | «**جاري استعادة بياناتك…**» — overlay في `login_screen` (Google) و `splash_screen` (hydrate) — **بدون** شاشة route منفصلة |
| **splash routing** | `_resolveStartupRoute` يستخدم `isGoogleOwnerProfileCompleteAsync()` بعد hydrate — لا فحص sync محلي قبل السحب |
| **اختبار** | S8 في `test/auth/auth_e2e_scenarios_test.dart` |

### ما يبقى (تحسين — ليس blocker)

| البند | الوصف |
|-------|--------|
| **فشل hydrate → خطأ + إعادة** | جزئي — splash يستمر بعد log؛ يمكن تحسين UX لاحقاً |
| **E2E جهازان** | تحقق يدوي من مسار B كامل |

---

## القرار 4 — `product_warehouse_stock`: **مؤجّل** ⏸️

**لا تغيير الآن — يبقى مستثنى من اللقطة حتى يُقرَّر sync منفصل.**

> **الوضع الحالي:** مستثنى من `app_snapshots` في `cloud_sync_service.dart`.  
> **الأثر:** مخزون multi-warehouse على الجهاز الثاني قد يكون ناقصاً — **مقبول مؤقتاً**.

---

## القرار 5 — F3 حوار خروج نهائي: **مكتمل** ✅

| البند | التفاصيل |
|-------|----------|
| **الملف** | [`employee_pin_gate_screen.dart`](../../lib/screens/auth/employee_pin_gate_screen.dart) — `_PermanentSignOutConfirmDialog` |
| **UX** | numpad 4 أرقام · `AuthValidators.isValidPin()` · «رمز PIN» |
| **Backend** | `verifyOwnerConfirmationCredential` — بدون تغيير |

---

## ملخص تنفيذ مرحلة 5 — **الحالة النهائية**

### ✅ مكتمل في الكود (قرارات 1–3 + 5)

| البند | # |
|-------|---|
| PIN سحابي + OTP إلزامي قبل استعادة cross-device | 1 |
| `GoogleSignInIntent` + رفض signup/login mismatch | 2 |
| hydrate قبل gate · `isGoogleOwnerProfileCompleteAsync` · overlay «جاري استعادة بياناتك…» | 3 |
| حوار خروج نهائي numpad | 5 |
| 6 تخصصات onboarding · `_shouldSkipInitialOnboarding` · `hasAtLeastOneActiveStaffWithPin()` | onboarding |

### ⏸️ مؤجّل / خارج النطاق

| البند | # |
|-------|---|
| `product_warehouse_stock` في اللقطة | 4 |
| `ensureFreshSession` (F4) | F4 |
| تنبيه أمني PIN مشترك في UI | 1 (polish) |

### 🔧 Ops / تحقق متبقي

1. تشغيل migration `20260609` على Supabase (إنتاج).
2. E2E جهازان (Google + OTP + hydrate + intent).
3. حسابات ما قبل migration — re-save PIN مرة واحدة.
4. تحسين UX عند فشل hydrate (اختياري).

### 🧪 اختبارات

- **`test/auth/`:** 11/11 ✅ (S1–S8 + cloud service)
- **المجموع:** 801 ناجح · 1 skipped · **26 فاشل** (معروفة مسبقاً — بدون regressions جديدة)

---

## ملاحظات سريعة

- **القرارات 1–3 و 5** — **مكتملة في الكود** — تغطي F1/F2/F3 في [`google_auth_implementation.md`](google_auth_implementation.md).
- **القرار 4** — **مؤجّل** — قرار sync منفصل.
- **F4** (`ensureFreshSession`) — **لم يُنفَّذ** — تبعي اختياري بعد استقرار multi-device.

---

## السيناريو المستهدف — جهازان

> **القرارات 1–3 منفّذة في الكود** — يبقى E2E يدوي للتحقق النهائي.

### الهاتف — أول جهاز

```
/onboarding (6 تخصصات) → أول موظف إلزامي → /home
    ↓
push: app_snapshots + owner_auth_secrets
```

### الحاسبة — جهاز ثاني

```
Google OAuth (intent: login)
    ↓
overlay «جاري استعادة بياناتك…» + hydrate ✅
    ↓
intent OK + tenant مكتمل ✅
    ↓
OTP → applyOwnerAuthFromCloud ✅
    ↓
isGoogleOwnerProfileCompleteAsync → تخطّي onboarding ✅
    ↓
/home أو employee-gate
```

### شروط قبول (Acceptance)

- [x] لا تطبيق PIN من السحابة بدون OTP (S7).
- [x] intent signup/login + رفض mismatch (S8).
- [x] hydrate قبل gate + async complete + overlay (S8).
- [ ] E2E: جهاز B — لا onboarding · لا complete-profile كاذب · نفس تخصص/موظفين.
- [ ] فشل hydrate → خطأ واضح + إعادة (تحسين UX).

**مرجع:** `test/auth/auth_e2e_scenarios_test.dart` · `test/security/account_sync_bundle2_regression_test.dart`.

---

## Onboarding — أول دخول للمالك

### التخصصات (6)

| المفتاح | العرض |
|---------|--------|
| `oil_change` | محل زيت وصيانة سيارات |
| `supermarket` | سوبر ماركت ومواد غذائية |
| `clothing_store` | محل ملابس وأحذية |
| `pharmacy` | صيدلية |
| `restaurant_cafe` | مطعم / مقهى |
| `general_retail` | محل تجاري عام |

### قاعدة الجهاز الثاني

**تخطّي `/onboarding`:** `onboardingCompleted` **أو** (لقطة + `BusinessVertical.isKnown` + `hasAtLeastOneActiveStaffWithPin()`).

**`_shouldSkipInitialOnboarding`:** `BusinessSetupSettingsData.isCompleted()` ثم بعد hydrate: تخصص معروف + موظف بـ PIN.
