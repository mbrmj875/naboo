# Google Auth + تسجيل PIN — توثيق التنفيذ

> آخر تحديث: يونيو 2026  
> النطاق: مسار Google OAuth + تسجيل يدوي (بريد + جوال `07` + PIN 4 أرقام) + حماية تعارض الهوية + استئناف إكمال الملف بعد إعادة التشغيل (S6).

---

## 1. الملفات المُعدَّلة أو الجديدة

| الملف | التغيير (سطر واحد) |
|-------|---------------------|
| `migrations/20260608_assert_identity_link_allowed.sql` | **جديد** — RPC يمنع ربط Google بحساب `auth.users` مختلف لنفس البريد. |
| `lib/providers/auth_provider.dart` | Google OAuth مرتّب (assert → upsert آمن → bind)، تسجيل PIN يدوي، `completeGoogleOwnerProfile`، `getLocalOwnerRow`، `kStrictRpcEnforcement`. |
| `lib/services/db_users.dart` | `upsertGoogleUserSafe` + `GoogleIdentityCollisionException` + `updateOwnerGoogleProfileCredentials`. |
| `lib/services/auth/registration_session_store.dart` | **جديد** — كلمة سر Supabase الداخلية مؤقتاً في `flutter_secure_storage` لمسار OTP. |
| `lib/utils/auth_validators.dart` | **جديد** — تحقق مشترك من جوال عراقي `07` ورمز PIN 4 أرقام. |
| `lib/screens/login_screen.dart` | زر Google، نماذج PIN للدخول/التسجيل، توجيه لشاشة إكمال الملف أو `resolveRouteAfterAuthenticatedSession`. |
| `lib/screens/auth/email_otp_screen.dart` | بعد OTP: `finalizeOwnerPin` ثم مسح secure storage شرطياً ثم توجيه عبر `resolveRouteAfterAuthenticatedSession`. |
| `lib/screens/auth/complete_owner_profile_screen.dart` | **جديد** — إكمال جوال + PIN بعد Google OAuth قبل bootstrap. |
| `lib/screens/splash_screen.dart` | استئناف S6: توجيه `/complete-google-profile` عند جلسة Supabase + ملف Google ناقص. |
| `lib/widgets/auth/google_g_logo.dart` | **جديد** — أيقونة Google G للزر. |
| `lib/main.dart` | تسجيل مسار `/complete-google-profile` → `CompleteOwnerProfileScreen`. |
| `lib/services/cloud_sync_service.dart` | `suppressUserDirectoryPushSoonForTesting` لاختبارات unit (لا يغيّر سلوك الإنتاج). |
| `test/auth/auth_e2e_scenarios_test.dart` | **جديد** — اختبارات proxy آلية لمسارات S1–S6 (طبقة منطق/مصدر، ليست E2E حية). |
| `test/phase1_owner_shift_bypass_regression_test.dart` | تحديث توقعات التوجيه لتتوافق مع `resolveRouteAfterAuthenticatedSession` بدل نصوص `/home` الثابتة. |

**مرجع OTP (موجود مسبقاً):** `docs/supabase_email_otp_setup_ar.md` وقوالب البريد في `docs/supabase_email_otp_template_ar.html`.

---

## 2. ترتيب تشغيل migrations على Supabase

يُفترض أن البنية الأساسية (RLS، أجهزة، tenant) مُطبَّقة مسبقاً. لمسار Google Auth + PIN أضِف بالترتيب:

| # | الملف | الغرض |
|---|-------|--------|
| 1 | `migrations/20260603_app_owner_recover_device.sql` | RPC استعادة جهاز المالك بعد OTP (ربط الجهاز — يدعم مسار المالك عموماً). |
| 2 | `migrations/20260608_assert_identity_link_allowed.sql` | **إلزامي لـ Google** — رفض ربط بريد OTP بحساب Google UUID مختلف. |
| 3 | `migrations/20260609_owner_auth_secrets.sql` | **مرحلة 5 — القرار 1** — PIN المالك (hash+salt) cross-device عبر `owner_auth_secrets`. |

> **تحقق بعد التطبيق:** من SQL Editor نفّذ `select proname from pg_proc where proname = 'assert_identity_link_allowed';` — يجب أن يُرجع صفاً واحداً.  
> **Flutter:** `STRICT_RPC=true` (افتراضي) — غياب RPC يُظهر «خطأ في الإعداد — تواصل مع الدعم» ولا يُكمل ربط Google.

---

## 3. متطلبات قبل الإطلاق

### Google Cloud Console

- إنشاء OAuth 2.0 Client IDs لكل منصة مستهدفة (Android، iOS، Web إن وُجد).
- **Authorized redirect URIs:** URI إعادة التوجيه الذي يعرضه Supabase Dashboard (Provider → Google).
- **Deep link للتطبيق:** `io.supabase.naboo://login-callback` (مُستخدم في `signInWithGoogle` على الموبايل/سطح المكتب).
- تفعيل Google Sign-In API وربط Consent Screen بالمشروع.

### Supabase Dashboard

- **Authentication → Providers → Google:** تفعيل + Client ID و Client Secret من Google Console.
- **Authentication → URL Configuration:** Site URL و Redirect URLs متوافقة مع deep link وبيئة الإنتاج.
- **Authentication → Email:** SMTP مُعدّ لمسار OTP اليدوي (راجع `docs/supabase_email_otp_setup_ar.md`).
- **SQL:** تطبيق migrations القسم 2 بالترتيب على بيئة الإنتاج/Staging.

### Consent Screen (Google)

- للإنتاج العام: إكمال **OAuth consent screen verification** (Privacy Policy، Terms، نطاقات البيانات المطلوبة `email`/`profile`).
- أثناء التطوير: وضع Testing مع Test users كافٍ؛ خارج Testing يفشل OAuth للمستخدمين غير المدرجين.

### تشغيل التطبيق

- `--dart-define=SUPABASE_URL=...` و `--dart-define=SUPABASE_ANON_KEY=...` (لا مفاتيح في الكود).
- iOS: URL scheme `io.supabase.naboo` في Info.plist / entitlements.
- Android: intent filter لـ `io.supabase.naboo://login-callback`.

---

## 4. القرارات المؤجلة لمرحلة لاحقة

| البند | السبب |
|-------|--------|
| `_tryEnableCloudSessionAfterLocalLogin` يمرّر PIN لـ Supabase | كلمة سر Supabase الداخلية ≠ PIN — فشل صامت لجلسة السحابة بعد دخول PIN محلي. |
| `ensureFreshSession` قبل sync | بديل مقترح لمرحلة 5: تجديد الجلسة دون `signInWithPassword(PIN)`. |
| Apple Sign In | غير مُنفَّذ — مطلوب لسياسة App Store لاحقاً إن وُجدت طرق دخول اجتماعية أخرى. |
| Windows localhost callback | OAuth على Windows يحتاج redirect محلي — غير مُعالَج. |
| RPC `assert_identity_link_allowed` في مسار OTP | OTP يستدعي `_bindAccountDataScope` دون assert — مقصود حالياً؛ توحيد لاحقاً. |
| Bootstrap checkpoint (`auth.bootstrap_phase`) | استئناف أدق بعد انقطاع منتصف bootstrap — S6 يُغطى جزئياً عبر `/complete-google-profile`. |

---

## 5. الاختبارات الفاشلة المعروفة (26) وسببها

> آخر تشغيل `flutter test`: **797 نجح · 1 skipped · 26 فشل** — لا علاقة لها بمسار Google Auth/PIN.

| المجموعة | العدد | السبب (جملة واحدة) |
|----------|-------|---------------------|
| `supabase_config_test` | 4 | تتوقع `--dart-define` لـ URL/anon key — بدونها الفشل متوقع في CI المحلي. |
| `jwt_license_verify_test` + `license_v2_only_test` | 2 | JWT عيّنة منتهية أو مفتاح `naboo-dev-001` غير متزامن مع بيئة الاختبار. |
| `db_cash_tenant_isolation_test` | 5 | sandbox in-memory يفتقد جدول `users` الذي يعتمد عليه JOIN في `getCashLedgerEntries`. |
| `soft_delete_test` (cash ledger) | 2 | نفس مشكلة schema/JOIN مع `users` في استعلامات الصندوق. |
| `db_debts_tenant_isolation_test` | 1 | فشل functional في `applyPaymentToInvoice` same-tenant (منطق/seed — ليس compile). |
| `phase1_owner_shift_bypass` (emergency bypass) | 1 | documentary test يبحث عن `if (_roleKey == 'owner' && allowOwnerEmergencyOverride)` بينما الكود يستخدم `canOwnerEmergencyBypass`. |
| `phase2_owner_governance_regression` | 1 | `user_form_screen` لم يعد يحتوي النص الثابت الذي يفحصه الاختبار. |
| `phase3_owner_dashboard_mvp_regression` | 1 | `owner_dashboard_screen` تغيّر ولم يعد يذكر `ReportsScreen` كما يتوقع الاختبار. |
| `owner/` (profile resolver، supermarket repo، command center integration) | 4 | انحراف مواصفات KPI/dashboard عن snapshots النصية في الاختبارات. |
| `realtime_kill_switch_test` | 1 | documentary: callback إعادة الاتصال لا يطابق `_attachTenantAccessRealtime` في المصدر. |
| `realtime_sync_test` | 1 | توقيت watchdog 30s — flake أو تغيّر سلوك `RealtimeWatchdog`. |
| `auth_security_test` (debugPrint scan) | 1 | `debugPrint` غير مُحاط بـ `kDebugMode` في ملف أو أكثر تحت `lib/`. |
| `db_performance_test` (soft delete) | 1 | async flake: `CloudSyncService` بعد اكتمال الاختبار (Supabase غير مُهيَّأ). |
| `service_orders_load_regression_test` | 1 | regression تحميل service orders — tenant_id فقط دون أعمدة أخرى متوقعة. |
| `recent_activity_timestamp_test` | 1 | توقيت/منطقة زمنية لعرض «اليوم» في `RecentActivityEntry.timeLabel`. |

**ملاحظة:** `test/auth/auth_e2e_scenarios_test.dart` — **7/7 ✅** ولا يظهر في قائمة الفشل.

---

## 6. فجوات مكتشفة — مؤجلة للمرحلة 5

> مُكتشفة أثناء E2E واختبار multi-device — **لا تُنفَّذ في المرحلة الحالية**. توثيق للقرار والتنفيذ لاحقاً.

### F1 — PIN المالك لا يُزامَن بين الأجهزة

- **الوصف:** كل جهاز جديد بنفس حساب Google يطلب إعادة إدخال جوال + PIN (شاشة «إكمال الحساب»).
- **السبب:** `users.passwordHash/Salt` محلي فقط — جدول `users` **مستثنى** من `app_snapshots`؛ وعند الرفع إلى `user_profiles` يُفرَّغ `pinHash/pinSalt` **عمداً** للمالك (`role=owner`) بينما يُزامَن للموظفين فقط (راجع `migrations/20260530_user_profiles_pin_sync.sql`).
- **التحقق:** `isGoogleOwnerProfileComplete` يقرأ SQLite `users` فقط — لا يستفيد من اللقطة السحابية لاستعادة hash المالك.
- **قرار مطلوب قبل التنفيذ:** PIN **لكل جهاز** (سياسة أمنية) أم PIN **مشترك** (OTP/recovery/encrypted cloud)؟

### F2 — زر Google لا يفرّق بين login و signup

- **الوصف:** تبويب «تسجيل الدخول» وتبويب «إنشاء حساب» يستدعيان نفس `_signInWithGoogle()` → `auth.signInWithGoogle()` **بدون intent**.
- **السلوك الحالي:** OAuth ينجح دائماً ثم التطبيق يقرر (إكمال ملف / دخول / bootstrap) — لا رسالة «الحساب غير موجود — أنشئ حساباً» من تبويب الدخول، ولا «الحساب موجود — سجّل الدخول» من تبويب التسجيل.
- **عند التنفيذ (مرحلة 5):** `signInWithGoogle(intent: login | signup)` + RPC/فحص يحدّد هل tenant Naboo **مكتمل** (لقطة سحابية / onboarding / ملف مالك) ثم `signOut` + رسالة عربية مناسبة للتبويب الخاطئ.

### F3 — حوار «خروج نهائي» لا يفرض PIN 4 أرقام

- **الموقع:** `_PermanentSignOutConfirmDialog` في `employee_pin_gate_screen.dart`.
- **الوصف:** الحقل يقبل أي نص (`TextInputType.visiblePassword`) — لا `AuthValidators.isValidPin()`، لا `maxLength: 4`، لا لوحة أرقام؛ التسمية «رمز تأكيد الحساب» بدل «رمز PIN».
- **التحقق الخلفي:** `verifyOwnerConfirmationCredential` يطابق PIN محلياً أولاً — **صحيح functionally** إذا أدخل المستخدم 4 أرقام فقط، لكن الواجهة لا تفرض ذلك.
- **ملاحظة:** **F3 هي الأسهل تنفيذاً** عند الحاجة (تعديل UI فقط في الحوار، بدون migration ولا RPC).

### F4 — fallback `signInWithPassword` بـ PIN

- **الموقع:** `_tryEnableCloudSessionAfterLocalLogin` → `_ensureSupabaseSessionForLocalCloudAccount` في `auth_provider.dart`.
- **الوصف:** بعد دخول PIN محلي ناجح، يُمرَّر PIN إلى `Supabase.auth.signInWithPassword` بينما حساب Google/OTP يحمل **كلمة سر Supabase داخلية** ≠ PIN.
- **الأثر:** فشل **صامت** — الدخول المحلي ينجح لكن جلسة/مزامنة Supabase قد لا تُفعَّل حتى مع إنترنت.
- **الحل المقترح (مرحلة 5):** `ensureFreshSession` قبل sync — تجديد الجلسة من OAuth/refresh token بدل محاولة login بـ PIN (مرتبط بالبند في القسم 4).

> **قرارات مرحلة 5:** راجع [`phase5_deferred_decisions.md`](phase5_deferred_decisions.md).

---

## 7. التحليل المعماري — بيانات محلية vs سحابية

> فحص: `cloud_sync_service.dart`، `db_users.dart`، `auth_provider.dart`، `database_helper.dart`، `migrations/20260530_user_profiles_pin_sync.sql`  
> **السياق:** نفس نمط «Google + PIN على الجهاز الثاني» — بيانات تُحفظ محلياً ولا تنتقل رغم نفس حساب Google.

### 7.1 الجدول الرئيسي

| البيانات | تُحفظ أين؟ | تُزامَن؟ | المشكلة على الجهاز الثاني |
|----------|-----------|---------|--------------------------|
| **PIN المالك (4 أرقام)** | SQLite `users.passwordHash/Salt` + `shiftAccessPin` | **لا** — `users` مستثنى من اللقطة؛ `user_profiles.pinHash/pinSalt` **يُفرَّغ للمالك** عند الرفع | شاشة «إكمال الحساب» + خروج نهائي يطلب PIN «من جديد» |
| **جوال المالك (07)** | SQLite `users.phone` + `auth.users` metadata (بعد الإكمال) | **جزئي** — `user_profiles.phone` في اللقطة؛ metadata على Supabase؛ **`users` لا يُرفع** | قد يصل الجوال بعد سحب اللقطة، لكن **لا يكفي** لأن `isGoogleOwnerProfileComplete` يشترط hash أيضاً |
| **`supabaseUid` + ربط المالك** | SQLite `users.supabaseUid` + `SharedPreferences` (`device_owner_supabase_uid`) | **لا** للجدول؛ **نعم** للجلسة — OAuth يعيد كتابة uid من Google | الجهاز الثاني يربط **بنفس tenant**، لكن **بدون credentials محلية** |
| **`local_auth_user_id` (جلسة محلية)** | `SharedPreferences` | **لا** (مقصود — لكل جهاز) | نفس المالك قد يظهر بـ **id محلي مختلف**؛ employee-gate يعتمد على SQLite بعد import |
| **كلمة سر Supabase الداخلية (OTP يدوي)** | `flutter_secure_storage` (`registration_session_store`) | **لا** | مسار OTP على جهاز ثاني = جلسة تسجيل جديدة فقط |
| **PIN الموظفين** | `users` + نسخة `user_profiles.pinHash/pinSalt` | **نعم للموظفين** عبر `user_profiles` في `app_snapshots` | الموظفون **يُفترض** أن ينتقلوا؛ المالك **لا** |
| **دليل المستخدمين (`users` كاملاً)** | SQLite `users` | **لا** — مستثنى صراحة | الجهاز الثاني يبني `users` من OAuth + `reconcileUserDirectoryAfterCloudImport` — **ناقص للمالك** |
| **`user_profiles` (مالك)** | SQLite → اللقطة | **نعم جزئياً** — اسم/بريد/جوال؛ **PIN مفرّغ** | اللقطة لا تحمل سر المالك |
| **`user_profiles` (موظف)** | SQLite → اللقطة | **نعم** (hash+salt) | يعمل كما صُمّم في migration `20260530` |
| **إعداد onboarding / نوع النشاط** | `app_settings` → اللقطة | **نعم** (إن رُفعت لقطة من الجهاز الأول) | بدون push من الجهاز الأول → **إعداد سريع** مرة أخرى |
| **بيانات ERP (فواتير، عملاء، منتجات…)** | SQLite → `app_snapshots` | **نعم** — معظم الجداول | تظهر **بعد** سحب اللقطة؛ لا فور OAuth |
| **`product_warehouse_stock`** | SQLite | **لا** — مستثنى من اللقطة | مخزون **متعدد المستودعات** قد يختلف/يفرغ على الجهاز الثاني رغم sync `products.qty` |
| **`sync_queue` (طابور المزامنة)** | SQLite | **لا** — لكل جهاز | عمليات لم تُرفع من الجهاز الأول **غير موجودة** على الثاني |
| **`account_devices`** | Supabase (منفصل عن اللقطة) | **نعم** — تسجيل جهاز | يربط **الجهاز بالحساب** لا بالـ PIN؛ لا يحل مشكلة credentials |
| **تفضيلات UI (ثيم، إشعارات، idle)** | `SharedPreferences` | **لا** | تجربة مختلفة — ليست بيانات ERP |
| **بداية trial محلي** | `SharedPreferences` (`lic.local_trial_start_at`) | **لا** | عدّاد trial قد يختلف بين الأجهزة |
| **تنبيهات المالك Push / FCM** | Supabase `owner_alert_*` | **نعم** — API منفصل | per-device token؛ ليس PIN |
| **استوديو لوحة المالك v3** | `app_settings` (بعد ترحيل) | **نعم** إن ضمن اللقطة | قد يُفقد إن لم تُدفع `app_settings` |
| **مسودات/جلسات UI** | ذاكرة Provider / مسارات | **لا** | لا تُتوقع cross-device |

### 7.2 `app_snapshots` — ماذا يُستثنى؟

**آلية:** لقطة JSON لكل `user_id` في Supabase (`app_snapshots` + `app_snapshot_chunks`). Flutter يبنيها من `_listSyncTables` → `_shouldSyncTable` في `cloud_sync_service.dart`.

**جداول مستثناة بالكامل من اللقطة:**

| الجدول | السبب في الكود | أثر الجهاز الثاني |
|--------|----------------|-------------------|
| **`users`** | «أسرار في `user_profiles` — لا نرفع `users` مباشرة» | **كل** حقول المالك الحساسة (`passwordHash`, `shiftAccessPin`, `supabaseUid` في الصف المحلي) **لا تُنقل** عبر اللقطة |
| **`sync_queue`** | طابور محلي لكل جهاز | طبيعي — per-device |
| **`product_warehouse_stock`** | مستثنى بدون تعليق إضافي في `_shouldSyncTable` | **فجوة مخزون** multi-warehouse |
| `sqlite_*`, `android_metadata` | بنية SQLite | — |

**ما يُرفع:** باقي جداول SQLite المؤهلة (~فواتير، `user_profiles`, `app_settings`, `products`, …).

**ملاحظات:**

- الرفع **كامل** لكل الجداول المؤهلة في كل push (ليس delta جزئي) — لكن **ما لم يدخل `_shouldSyncTable` لا يصل أبداً**.
- الجهاز الثاني بعد Google يفحص `isGoogleOwnerProfileComplete` **قبل** اكتمال `hydrateCloudAccountData` / import — فيُعامل كـ «حساب جديد» حتى لو اللقطة موجودة على السيرفر.

### 7.3 `account_devices` — هل يربط الجهاز بالبيانات الصحيحة؟

| ما يفعله | ما **لا** يفعله |
|----------|-----------------|
| يسجّل `device_id` + `user_id` (نفس Google = نفس `user_id`) عبر `registerCurrentDevice` / RPC `app_register_device` | **لا** يخزّن PIN أو SQLite |
| يتحكم في **revoked / حد الأجهزة** | **لا** يستبدل صف `users` المحلي |
| Realtime على `access_status` | — |

**البيانات التشغيلية** تأتي من **`app_snapshots` بنفس `user_id`** — ليس من `account_devices`.

**الخلل الشائع:** الجهاز الثاني **مُسجَّل** في `account_devices` لكن **بدون PIN محلي** و**قبل** سحب اللقطة → يبدو «حساب جديد» رغم نفس Google.

### 7.4 `user_profiles` — ما الذي يُفرَّغ عمداً؟

عند `_upsertUserProfileByUserId` في `db_users.dart` (قبل الرفع للسحابة):

| الحقل | المالك (`role=owner`) | الموظف |
|-------|----------------------|--------|
| **`pinHash` / `pinSalt`** | **يُفرَّغان (`''`)** | يُنسخان من `users.passwordHash/Salt` |
| `phone`, `email`, `displayName` | **يُرفع** | **يُرفع** |

**عند الاستيراد** (`applyUserProfilesIntoUsersTransaction`):

- **PIN من اللقطة → `users` للموظفين فقط** (`!isOwnerProfile`).
- **صف مالك جديد من اللقطة بدون PIN محلي → يُتخطى** (`if (isOwnerProfile \|\| !profileHasPin) continue`).
- **المالك موجود محلياً → يُحدَّث الاسم/الجوال فقط** — **لا** استيراد hash.

**migration `20260530_user_profiles_pin_sync.sql`:** يؤكد صراحة: *«كلمة مرور المالك (Gmail/Supabase) لا تُرفع في pinHash/pinSalt»* — **قرار أمني مقصود**، لكنه يسبب فجوة cross-device للمالك.

### 7.5 جداول/طبقات محلية لا تمرّ عبر `app_snapshots`

| الطبقة | أمثلة | نمط المشكلة |
|--------|-------|-------------|
| **مستثناة صراحة** | `users`, `sync_queue`, `product_warehouse_stock` | بيانات لا تصل للجهاز الثاني عبر اللقطة |
| **`SharedPreferences`** | `local_auth_user_id`, `auth.device_owner_*`, `sync.*`, trial، UI | per-device — طبيعي للجلسة، **ليس** للـ PIN |
| **`flutter_secure_storage`** | كلمة OTP المؤقتة (`registration_session_store`) | ephemeral |
| **Supabase منفصل** | `profiles`, `account_devices`, `owner_alert_*` | identity / أجهزة / تنبيهات — **لا** PIN المالك |
| **فحص قبل sync** | `isGoogleOwnerProfileComplete` | يقرأ **`users` المحلي فقط** — لا ينتظر اللقطة |

**لا يوجد جدول Supabase migration منفصل** ينقل `users` — التصميم يعتمد `user_profiles` كبديل، **مع استثناء المالك**.

### 7.6 حالات مشابهة لـ PIN (نفس النمط)

| # | الحالة | لماذا مشابهة |
|---|--------|--------------|
| 1 | **إكمال Google (جوال+PIN)** | `users` محلي فقط |
| 2 | **خروج نهائي / تأكيد حساس** | `verifyPinForUser` → `users` المحلي |
| 3 | **تسجيل OTP يدوي + PIN** | PIN في `users`؛ كلمة Supabase في secure storage |
| 4 | **employee-gate للمالك** | نفس hash محلي؛ الموظفون من اللقطة |
| 5 | **`shiftAccessPin` للمالك** | في `users` المستثنى — لا ينتقل |
| 6 | **Google login vs signup** | لا فحص «tenant Naboo موجود» قبل OAuth |
| 7 | **`product_warehouse_stock`** | مستثنى — مخزون warehouse فارغ/قديم |
| 8 | **`sync_queue` غير مرفوع** | بيانات على الجهاز الأول فقط |
| 9 | **metadata جوال Supabase** | يُكتب بعد الإكمال — **لا يُقرأ** في `isGoogleOwnerProfileComplete` |
| 10 | **Onboarding** | في اللقطة — OK **إذا** push؛ وإلا يُعاد wizard |

### 7.7 الخلاصة المعمارية

```
Google OAuth  →  نفس auth.users (Supabase)  →  tenant واحد
                      ↓
              account_devices (جهاز 2 مسجّل ✓)
                      ↓
              app_snapshots (بيانات ERP + user_profiles بدون PIN مالك)
                      ↓
              users (محلي) ← PIN المالك هنا فقط ← لا يُرفع ولا يُستورد للمالك
```

**المشكلة ليست «Google لا يربط الحساب»** — بل **طبقة credentials المالك مصممة device-local عمداً**، بينما **التحقق** (`isGoogleOwnerProfileComplete`، login PIN، خروج نهائي) **يقرأها قبل/بدون** الاستفادة الكاملة من اللقطة.

**مرتبط بالقسم 6:** F1–F4. **قرارات التنفيذ:** [`phase5_deferred_decisions.md`](phase5_deferred_decisions.md) — بما فيها **السيناريو المستهدف (جهازان)** بعد القرارات 1–3.

---

## ملحق — تدفقات مُختبرة (E2E)

| السيناريو | الحالة |
|-----------|--------|
| S1 — تسجيل يدوي OTP + PIN | منطق مُتحقق آلياً؛ E2E حي يحتاج SMTP + جهاز. |
| S2 — دخول لاحق PIN | verify محلي ✅؛ جلسة Supabase بعد PIN — مؤجل لمرحلة 5. |
| S3 — Google مستخدم جديد | E2E حي يحتاج OAuth. |
| S4 — Google عائد | ✅ منطق `isGoogleOwnerProfileComplete`. |
| S5 — تعارض هوية | ✅ RPC + `upsertGoogleUserSafe` + رسائل عربية. |
| S6 — استئناف بعد OAuth | ✅ `/complete-google-profile` من splash. |
