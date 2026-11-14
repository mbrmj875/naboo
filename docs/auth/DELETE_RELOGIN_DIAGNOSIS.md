# تشخيص: فشل الدخول بعد حذف الحساب وإعادة التسجيل

**التاريخ:** 3 يوليو 2026  
**الحالة:** تم تحديد السبب الجذري + إصلاحات في الكود

---

## الملخص في جملة واحدة

**حذف الحساب من لوحة الإدارة يمسح السحابة فقط — الجهاز يحتفظ ببيانات قديمة (SQLite + Secure Storage + ربط الجهاز) فتتعارض مع أي محاولة دخول أو تسجيل جديد.**

---

## ماذا يحدث عند «حذف الحساب»؟

### من لوحة الإدارة (`admin-web`)

| يُحذف من السحابة | **لا** يُمسح على الجهاز |
|------------------|------------------------|
| `auth.users` | SQLite — صف `users` بالـ PIN القديم |
| `profiles` | `auth.device_owner_bound` |
| `account_devices` | `auth.device_owner_supabase_uid` |
| `app_snapshots` | `auth.active_data_owner` = `cloud:<uid-قديم>` |
| `owner_auth_secrets` (cascade) | `owner.supabase_password.<email>` في Secure Storage |
| | `local_auth_user_id` |

---

## لماذا لا يعمل **أي** حساب قديم؟

### السبب 1 — صف SQLite «شبح» (الأكثر شيوعاً)

```
حذفت الحساب من admin-web
    ↓
الجهاز ما زال فيه: users.email + passwordHash (PIN القديم) + supabaseUid (UUID محذوف)
    ↓
تدخل PIN القديم → login() ينجح محلياً → التطبيق «يدخل» لكن السحابة ميتة
    ↓
تدخل PIN الجديد → فشل محلي → fallback → كلمة Supabase قديمة في Secure Storage → فشل → OTP
    ↓
OTP login يتطلب owner_auth_secrets مكتمل → «لا يوجد حساب مكتمل»
```

### السبب 2 — كلمة Supabase الداخلية القديمة

- عند التسجيل يُنشأ PIN (4 أرقام) **و** كلمة سر Supabase عشوائية (32 حرف)
- الكلمة الداخلية تُحفظ في `OwnerSupabaseCredentialStore`
- **لم تكن تُمسح** عند logout أو حذف الحساب من admin
- `signInWithPassword` يحاول الكلمة القديمة → فشل صامت → تعطيل مسار OTP أحياناً

### السبب 3 — ربط الجهاز بـ UUID محذوف

```
auth.device_owner_bound = true
auth.device_owner_supabase_uid = <uuid-محذوف>
auth.active_data_owner = cloud:<uuid-محذوف>
```

عند الإقلاع: `restoreSession()` يُعيد تطبيق UUID القديم ولا ينظّف جلسة Supabase إذا الجهاز «مربوط».

### السبب 4 — التسجيل نصف مكتمل

بعد `signUp` + OTP، الحساب على Supabase **موجود** لكن `owner_auth_secrets` **فارغ** حتى `finalizeOwnerPin`.

في هذه النافذة:
- «تسجيل الدخول» → `tenant incomplete` → فشل
- «OTP دخول» → نفس الشيء

---

## مسارات الدخول بالبريد — ماذا يحدث في كل واحد؟

| المسار | الملف | متى يفشل بعد حذف+إعادة |
|--------|-------|------------------------|
| **A. بريد + PIN محلي** | `login()` | PIN قديم ينجح محلياً بلا سحابة؛ PIN جديد → fallback |
| **B. Supabase password مخزّنة** | `_loginViaSupabaseFallback` | كلمة قديمة → فشل (كان يتوقف هنا) |
| **C. OTP دخول** | `sendEmailLoginOtp` | «لا يوجد حساب» إن لم يُعاد signUp |
| **D. OTP + verify** | `loginWithEmailOtp` | فشل إن `owner_auth_secrets` غير مكتمل |
| **E. تسجيل جديد** | `registerManualWithPin` | ينجح على السحابة؛ فشل محلي إن لم يُمسح SQLite |
| **F. OTP تسجيل** | `verifyOtpAndRegister` | ينجح إن `_bindAccountDataScope` مسح DB (UID جديد) |
| **G. finalize PIN** | `finalizeOwnerPin` | يُكمّل `owner_auth_secrets` — **ضروري** |
| **H. نسيت PIN** | `sendPasswordResetOtp` | يفشل إن لا `auth.users` |

---

## الحل الفوري لك (بدون انتظار build جديد)

### الخيار 1 — الأفضل: مسح بيانات التطبيق

**Android:** الإعدادات → التطبيقات → Naboo → التخزين → **مسح البيانات**  
**iOS:** حذف التطبيق وإعادة التثبيت

### الخيار 2 — من داخل التطبيق (إن استطعت الوصول لبوابة الموظفين)

1. ادخل بـ PIN (حتى لو التطبيق «معطّل»)
2. **تسجيل خروج نهائي من الجهاز** (ليس «قفل الجلسة»)
3. أنشئ حساباً جديداً أو سجّل دخولاً

### الخيار 3 — عند إعادة التسجيل

1. **لا تحذف** من admin-web ثم تحاول الدخول مباشرة على نفس الجهاز
2. بعد الحذف: **مسح بيانات التطبيق** أو خروج نهائي
3. **إنشاء حساب** (ليس دخول) → OTP → **أكمل PIN** حتى النهاية
4. لا تغلق التطبيق بين OTP وشاشة PIN

---

## الإصلاحات المُطبّقة في الكود (3 يوليو 2026)

| # | الإصلاح | الملف |
|---|---------|-------|
| 1 | كشف UID محلي ≠ جلسة Supabase → fallback بدل دخول «شبح» | `auth_provider.dart` `login()` |
| 2 | مسح كلمة Supabase القديمة عند فشل `signInWithPassword` | `_loginViaSupabaseFallback` |
| 3 | مسح secure credentials عند `registerManualWithPin` | `registerManualWithPin` |
| 4 | مسح credentials + `active_data_owner` عند خروج نهائي | `signOutPermanentlyFromDevice`, `clearDeviceOwnerBinding` |
| 5 | مسح credentials عند `logout` | `logout` |
| 6 | `signupEmailTaken` يفحص `isActive=1` فقط | `db_users.dart` |
| 7 | `verifyOtpAndRegister` يستخدم `upsertGoogleUserSafe` + `allowUidRelink` | `auth_provider.dart` |

---

## قائمة فحص للمبرمج

```
[ ] SQLite: SELECT email, supabaseUid, isActive, passwordHash FROM users;
[ ] Prefs: auth.device_owner_bound, auth.device_owner_supabase_uid, auth.active_data_owner
[ ] Secure: owner.supabase_password.<email>
[ ] Cloud: auth.users موجود؟ owner_auth_secrets للـ UID الحالي؟
[ ] أي مسار فشل: A/B/C/D/E/F/G/H من الجدول أعلاه؟
```

---

## توصية تشغيلية

بعد **أي** حذف من admin-web، أرسل للمستخدم:

> «احذف بيانات التطبيق أو سجّل خروجاً نهائياً من الجهاز، ثم أنشئ حساباً جديداً.»

**logout العادي لا يكفي** — كان يُبقي ربط الجهاز + SQLite + secure storage.
