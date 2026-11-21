# تقرير هندسي: الطرد المتبادل بين الأجهزة على نفس الحساب (device ping-pong)

| البند | القيمة |
|---|---|
| المشروع | Naboo / `basra_store_manager` (Flutter + Supabase) |
| تاريخ الحادثة | 2026-10-20 (التوقيتات في هذا التقرير UTC ما لم يُذكر؛ توقيت العراق = UTC+3) |
| الحساب موضوع الفحص | `mohamed.albaqer.m@gmail.com` — `auth.users.id = a66b5bad-953e-48d7-9aef-6bbe1f7f172d` |
| الحالة | **التشخيص مكتمل. الإصلاح مطبّق على الإنتاج** (2026-10-20 ≈ 15:0x UTC) ومُتحقَّق منه بقاعدة محلية + اختبار ذاتي الإلغاء على الإنتاج + دليل ميداني أولي (§10) |
| نطاق التغيير | Server-side فقط (SQL). **لم يُعدَّل أي ملف Dart في هذا العمل.** |
| تاريخ آخر تحديث للتقرير | 2026-10-21 (بعد ≈ 18.5 ساعة من النشر) |

---

## 0. الملخص التنفيذي (TL;DR)

1. **العَرَض:** جهازان (Windows + Android) على نفس الحساب. أحدهما يُطرد فجأة بالشاشة الزرقاء
   «تم فصل هذا الجهاز من الحساب»، وإعادة ربطه تطرد الجهاز الآخر، وهكذا. حدّ الخطة 6 والمستخدم لم يتجاوز جهازين.
2. **السبب الجذري ليس اسم المستخدم المحلي ولا جلسات Supabase.** السيرفر لا يعرف اسم المستخدم المحلي أصلاً. المشكلة في
   **دورة حياة الحالة `account_devices.access_status = 'revoked'`**: لا يوجد لها طريق عودة آمن:
   - `app_register_device` يرفض عودة جهاز مفصول ما دام **أي** جهاز آخر نشط، **دون مقارنة العدد بالحد**.
   - الـ trigger `prevent_device_self_unrevoke` يجعل زر «السماح من جهاز نشط» **يفشل دائماً**.
   - المخرج الوحيد (استعادة المالك بـ OTP) ينفّذ `app_owner_recover_device(..., true)` الذي **يفصل كل الأجهزة الأخرى**.
   - التطبيق يطرد الجهاز عندما يكتشف `revoked`: عبر نبضة المزامنة (≤ 60 ث) فعلياً، وعبر Realtime نظرياً فقط (الجدول غير منشور، §2.1).
   النتيجة: حلقة طرد متبادل لا تتوقف.
3. **الإصلاح (SQL فقط، متوافق مع نسخ التطبيق الحالية):** الجهاز المفصول يعود تلقائياً إذا كان هناك مكان ضمن الحد؛ الاستعادة
   تفصل جهازاً واحداً فقط (الأقدم نشاطاً) وفقط عند امتلاء الحد؛ زر «السماح» يعمل؛ جدول تدقيق جديد يسجّل كل تغيير حالة.
4. **قبل/بعد (قياس فعلي):**
   - حالة الحادثة (حد 6، جهازان): جهاز مفصول يحاول العودة → **قبل:** `revoked` · **بعد:** `active`.
   - استعادة OTP بوجود 3 أجهزة أخرى نشطة من حد 6 → **قبل:** تفصل الثلاثة · **بعد:** تفصل 0.
   - زر «السماح» → **قبل:** `cannot_unrevoke_while_other_devices_active` · **بعد:** ينجح.
   - الإنتاج: **17 جلسة auth جديدة خلال 7.6 ساعة قبل الإصلاح** (04:37→12:14) مقابل **جلستين فقط في 18.7 ساعة بعده**، وكلاهما
     عند لحظة عودة الحاسوب، وصفر أحداث فصل منذ النشر.
5. **ثمن الإصلاح — تراجع سلوكي اكتشفتُه أثناء إعداد هذا التقرير (§11.1، أهم بند مفتوح):** `account_devices`
   **غير منشور في `supabase_realtime` على الإنتاج** [DB]، أي أن قناة Realtime في التطبيق لا تصل إليها أي أحداث، والجهاز المفصول
   لا يعرف بفصله إلا عبر **نبضة المزامنة كل 60 ثانية**. ونافذة السماح التي أضفتُها 30 ثانية فقط. النتيجة: حين يفصل المالك جهازاً
   يدوياً والحد غير ممتلئ، تقع النبضة التالية بعد النافذة في **≈ 50% من الحالات (تقدير بافتراض توزيع منتظم لطور النبضة، لم يُقَس)**
   فيعود الجهاز `active` بصمت (ولا يُطرد)، والجهاز النائم يعود دائماً. قبل
   الإصلاح كان الفصل اليدوي «ثابتاً» ما دام جهاز آخر نشطاً. **هذا تراجع في ميزة «فصل جهاز» لم أكتشفه قبل النشر، ولم أعالجه
   بعد على الإنتاج** (قرار منتج؛ التوصية في §12.1).
6. **ما لم يُحل بالسيرفر أيضاً:** (أ) الـ dedupe داخل التطبيق (يفصل أجهزة متشابهة الاسم والمنصة)؛ (ب) معالج الطرد في `main.dart`
   قد يفشل عند وجود وردية مفتوحة أو قائمة مزامنة غير فارغة (قراءة ثابتة، لم يُختبر تشغيلاً).
7. **ما لا نعرفه:** ما الذي فصل **أول** جهاز في أول دورة. الجدول لم يكن يحتفظ بتاريخ التغيير. جدول التدقيق الجديد يحسم ذلك مستقبلاً.

---

## 1. مصادر الأدلة ودرجات اليقين

كل ادعاء في هذا التقرير موسوم بمصدره:

| الوسم | المعنى |
|---|---|
| **[DB]** | استعلام مباشر على قاعدة الإنتاج (Supabase) في هذه الجلسة |
| **[CODE]** | قراءة مباشرة لملف في المستودع في هذه الجلسة (مع رقم السطر) |
| **[LOCAL]** | تجربة على PostgreSQL 16 محلي مؤقت (حُذف بعد الانتهاء) |
| **[INFER]** | استنتاج منطقي من أدلة غير مباشرة — **غير مؤكد** |
| **[PRIOR]** | معلومة من جلسة عمل سابقة على نفس المشكلة (النص الكامل في سجل المحادثة المرفق بالمشروع) ولم أُعد التحقق منها هنا |

أرقام الأسطر صحيحة بتاريخ 2026-10-21 على نسخة العمل الحالية (قد تتحرك مع أي تعديل لاحق).

---

## 2. فهم البنية: ثلاث طبقات هوية مختلفة

هذا هو مفتاح فهم لماذا «نفس اسم المستخدم على جهازين» ليس هو المشكلة.

| الطبقة | أين تُخزَّن | ماذا تمثّل | هل يراها السيرفر؟ |
|---|---|---|---|
| **1. حساب المالك (tenant)** | `auth.users` (Supabase Auth) | البريد/Google — المالك الذي يدفع الاشتراك | نعم (`auth.uid()`) |
| **2. الجهاز** | `public.account_devices` (`user_id`, `device_id`) | جهاز فيزيائي مُسجَّل على الحساب، محدود بخطة الاشتراك | نعم |
| **3. مستخدم محلي (موظف/مالك + PIN)** | SQLite المحلي على كل جهاز (`users`) | اسم مستخدم + دور (محاسب، مالك…) | **لا** — لا يصل للسيرفر كهوية |

نتيجة معمارية: جهازان يعملان بنفس اسم المستخدم المحلي هما، بالنسبة للسيرفر، جهازان تحت نفس `auth.uid()`. لا يوجد في أي
دالة أو جدول على السيرفر ما يقارن اسماً محلياً. لذلك أي تصادم بينهما ينشأ من **طبقة الجهاز (2)** وليس من طبقة المستخدم المحلي (3).

### 2.1 جدول `public.account_devices` (مُلتقط من الإنتاج [DB])

| العمود | النوع | قيد/افتراضي |
|---|---|---|
| `id` | bigint | identity (`account_devices_id_seq`) |
| `user_id` | uuid | NOT NULL، FK → `auth.users(id)` ON DELETE CASCADE |
| `device_id` | text | NOT NULL |
| `device_name` | text | NOT NULL |
| `platform` | text | NULL |
| `last_seen_at` | timestamptz | NOT NULL، `now()` |
| `created_at` | timestamptz | NOT NULL، `now()` |
| `access_status` | text | NOT NULL، `'active'`، CHECK `∈ {'active','revoked'}` |

- فهارس: `account_devices_pkey(id)`، `account_devices_user_id_device_id_key UNIQUE(user_id, device_id)`،
  `idx_account_devices_user_last_seen(user_id, last_seen_at DESC)`، `idx_account_devices_user_status(user_id, access_status)`.
- RLS: `devices_own_select` (SELECT حيث `auth.uid() = user_id`) و`devices_own_write` (ALL بنفس الشرط في USING وWITH CHECK).
  **أي جهاز مصادَق للمالك يستطيع `UPDATE` أي صف جهاز للحساب بما فيه حالة `access_status`.**
- **لا يوجد `updated_at` ولا `revoked_at` ولا `revoked_by` ولا أي سجل تاريخ.** (هذا سبب عدم القدرة على معرفة أول فاصل.)
- Triggers قبل الإصلاح: `trg_prevent_device_self_unrevoke BEFORE UPDATE` (ملف التراجع لا يستعيد غيره). الآن [DB]: هذا + `trg_log_account_device_change`.
- **Realtime:** `account_devices` **ليس** ضمن منشور `supabase_realtime` [DB، 2026-10-21]. الجداول المنشورة فقط:
  `app_snapshots, customer_debt_payments, installment_plans, installments, marketplace_orders, marketplace_products,
  restaurant_menu_theme, restaurant_orders, restaurant_sessions, supplier_payouts, sync_notifications, tenant_access, work_shifts`.
  السطر المسؤول في المستودع تعليق لم يُنفَّذ: `supabase_profiles_trial_device_access.sql:33-34`
  (`-- alter publication supabase_realtime add table public.account_devices;`). **الاستنتاج: قناة الجهاز في
  `_attachDeviceAccessRealtime` (cloud_sync_service.dart:2059) لا تستقبل أحداثاً على الإنتاج.**

### 2.2 الدوال المعنية على السيرفر

| الدالة | الدور | ملاحظات |
|---|---|---|
| `app_register_device(p_device_id, p_device_name, p_platform)` | تسجيل/نبض الجهاز، فرض الحد | SECURITY DEFINER؛ تأخذ advisory lock `register_device:<tenant>` ثم `FOR UPDATE` على كل صفوف المستخدم |
| `app_owner_recover_device(p_device_id, p_revoke_other_devices default true)` | استعادة المالك بعد OTP | SECURITY DEFINER؛ قبل الإصلاح بلا أقفال |
| `prevent_device_self_unrevoke()` | trigger يمنع `revoked → active` | يستثني `service_role` فقط |
| `app_user_max_devices()` | حدّ الأجهزة من الرخصة | يأخذ رخصة `status ∈ {active, trial}` المسندة للمستخدم؛ **وإلا 2** (`coalesce(..., 2)`) |
| `app_device_limit_status()` | حالة تجاوز الحد | قراءة فقط |
| `app_current_tenant_id()` | `jwt.tenant_id` ثم `jwt.sub` ثم `local-<uid>` | |

النصوص الكاملة للنسخ القديمة في الملحق A، والجديدة في `migrations/20261020_device_lifecycle_fix.sql`.

### 2.3 الرخص الحالية للحساب [DB، 2026-10-21]

| id | status | plan | max_devices | expires_at |
|---|---|---|---|---|
| 31 | **active** | monthly | **6** | 2026-11-19 01:49 UTC |
| 27 | suspended | lifetime | 2 | — |
| 28 | suspended | monthly | 4 | 2026-09-19 22:30 |
| 29 | suspended | monthly | 5 | 2026-10-19 22:39 |

`app_user_max_devices()` يقرأ فقط رخص `active/trial` ⇒ الحد الفعلي الآن = **6** (الرخصة 31). لاحظ أنه **لا يتحقق من
`expires_at`**؛ والحد يهبط إلى **2** (القيمة الافتراضية) في أي لحظة لا توجد فيها رخصة `active/trial` مسندة.

### 2.4 مكوّنات العميل (Flutter) ذات الصلة

| المكوّن | الملف:السطر | الدور |
|---|---|---|
| `CloudSyncService.registerCurrentDevice` | `lib/services/cloud_sync_service.dart:782` | يستدعي RPC `app_register_device` (798–821)، ويعامل `revoked` عبر `_resolveRevokedRegistration` (771–780) |
| `_ensureCurrentDeviceActiveIfReturning` | `cloud_sync_service.dart:986–1044` | قبل كل تسجيل: إن كان الجهاز `revoked` ولا يوجد جهاز نشط آخر يعيد تفعيله؛ **وإلا يترك الفصل قائماً** (تعليق السطر 983–985: «Never bypass an intentional revoke while another approved device remains active») |
| `tryRecoverOrphanRevokedDevice` | `cloud_sync_service.dart:722–767` | إذا **كل** الأجهزة `revoked` يعيد تفعيل هذا الجهاز |
| `_revokeDeviceRow` | `cloud_sync_service.dart:1062–1085` | `UPDATE access_status='revoked'` مباشر عبر PostgREST |
| `_dedupeActiveDuplicateDevicesOnServer` | `cloud_sync_service.dart:1087–1123` | يفصل «المكررين» (نفس `اسم|منصة`) — §6.1 |
| `refreshDevices` | `cloud_sync_service.dart:1125–1176` | يجلب الأجهزة ثم يطبّق dedupe + prune |
| `removeDevice` | `cloud_sync_service.dart:1184–1201` | فصل جهاز آخر (واجهة الاشتراك) |
| `ownerRecoverCurrentDeviceAfterEmailVerified` | `cloud_sync_service.dart:1204–1262` | يستدعي `app_owner_recover_device` ثم `registerCurrentDevice` |
| `signOutAndRevokeCurrentDevice` | `cloud_sync_service.dart:1298–1330` | «الخروج النهائي»: يدفع المزامنة ثم `_revokeDeviceRow` للجهاز الحالي |
| `approveDeviceAccess` | `cloud_sync_service.dart:1338–1358` | `UPDATE access_status='active'` مباشر (زر «السماح») |
| دورة المزامنة | `cloud_sync_service.dart:1715–1721` | `Timer.periodic(Duration(minutes: 1), → syncNow(forcePull:false))` |
| `syncNow` ⇒ تسجيل الجهاز | `cloud_sync_service.dart:1533–1552` | يستدعي `registerCurrentDevice()`؛ إن رجع `revoked` يستدعي `onRemoteDeviceRevoked` (1548–1550) |
| `_attachDeviceAccessRealtime` | `cloud_sync_service.dart:2059–2140` | قناة Realtime على `account_devices` (INSERT/UPDATE) بفلتر `user_id`؛ عند UPDATE لصف هذا الجهاز بحالة `revoked` ⇒ `onRemoteDeviceRevoked` (2113–2122). **لا تستقبل شيئاً على الإنتاج لأن الجدول غير منشور (§2.1)** |
| معالج الطرد | `lib/main.dart:146–167` | `auth.logout()` ثم `pushAndRemoveUntil(DeviceKickedOutScreen)` |
| شاشة الطرد | `lib/screens/auth/device_kicked_out_screen.dart` | الشاشة الزرقاء «تم فصل هذا الجهاز من الحساب» |
| شاشة الفصل/الاستعادة | `lib/screens/auth/device_access_revoked_screen.dart` | `_retryAccess` (102)، `_sendRecoveryOtp` (127)، `_verifyRecoveryOtp` (198 ⇒ 216 `recoverDeviceAccessViaEmailOtp`)، `_signOutCompletely` (230) |
| `recoverDeviceAccessViaEmailOtp` | `lib/providers/auth_provider.dart:3941–3971` | `verifyPasswordResetOtp` ثم `ownerRecover…(revokeOthers: revokeOtherDevices)` — القيمة الافتراضية `true` |
| الخروج النهائي (UI) | `lib/screens/auth/employee_pin_gate_screen.dart:471` (`_confirmPermanentAccountSignOut`)، `514` (`_attemptPermanentSignOut`) | يصل إلى `signOutPermanentlyFromDevice` |
| `signOutPermanentlyFromDevice` | `auth_provider.dart:3842–3881` | يستدعي `signOutAndRevokeCurrentDevice` ثم `logout` |
| `AuthProvider.logout` | `auth_provider.dart:4218–4275` | يفحص قائمة المزامنة والوردية (4225–4233) ثم `auth.signOut()` (محلي) ثم `stopForSignOut` |
| بصمة الجهاز | `lib/services/license/license_engine_v2.dart:146` (`getDeviceId`)، `158–188` (`getDeviceName`) | `device_id` من `_uuidMigrator`، `device_name` = `computerName` (Windows، سطر 179) أو `brand model` (Android، 172–173) |
| ترحيل UUID | `lib/services/license/device_uuid_migrator.dart:66–91` (`_revokeOrDeleteLegacyDeviceRow`)، `143–153` (upsert) | §6.6 |

---

## 3. العَرَض والجدول الزمني

### 3.1 الوصف

- طرد مفاجئ لجهاز بالشاشة الزرقاء (`DeviceKickedOutScreen`) أو بطلب إعادة تسجيل الدخول.
- محاولة استعادة الجهاز تطرد الآخر، وهكذا.
- لا يمكن حتى إعادة الربط إلا بحذف بيانات التطبيق (إفادة المالك).

### 3.2 جلسات `auth.sessions` للحساب في يوم الحادثة [DB]

كل تسجيل دخول/تحقق OTP يُنشئ جلسة جديدة. `ua` يميّز الجهاز: **`Dart/3.13` = الحاسوب (Windows)**، **`Dart/3.11` = الهاتف (Android)**
[INFER من ثبات الربط بين النسخة والمنصة خلال اليوم؛ لم يُثبَّت بمفتاح صريح].

| # | created_at (UTC) | UA | refreshed_at | ملاحظة |
|---|---|---|---|---|
| 1 | 04:37:24 | 3.13 حاسوب | — | |
| 2 | 04:37:38 | 3.13 حاسوب | 05:38:09 | بعد 14 ثانية من #1 |
| 3 | 05:38:20 | 3.13 حاسوب | — | |
| 4 | 05:39:17 | 3.11 هاتف | 05:39:18 | بعد دقيقة من #3 |
| 5 | 05:45:12 | 3.13 حاسوب | — | |
| 6 | 05:56:52 | 3.11 هاتف | — | |
| 7 | 06:01:45 | 3.11 هاتف | 06:01:45 | |
| 8 | 06:01:46 | 3.11 هاتف | — | بعد ثانية من #7 |
| 9 | 06:07:43 | 3.13 حاسوب | — | |
| 10 | 06:15:36 | 3.13 حاسوب | — | |
| 11 | 06:36:16 | 3.11 هاتف | 11:06:54 | عاشت 4.5 ساعة (مستقرة) |
| 12 | 06:38:55 | 3.13 حاسوب | — | |
| 13 | 06:40:50 | 3.13 حاسوب | — | |
| 14 | 11:38:08 | 3.13 حاسوب | — | |
| 15 | 11:43:08 | 3.13 حاسوب | — | بعد **5:00 بالضبط** من #14 |
| 16 | 12:10:43 | 3.11 هاتف | 12:10:44 | |
| 17 | 12:14:34 | 3.11 هاتف | 2026-10-21 08:44 | الجلسة الحالية للهاتف |

الجلسات بعد النشر (§10): **15:06:36** حاسوب (بلا refresh) و**15:07:25** حاسوب (refreshed 2026-10-21 08:44).

قراءة: عنقودات متقاربة من تسجيلات الدخول (دقائق بين جهاز وآخر)، وهي بصمة «طرد ثم إعادة ربط». الاستنتاج أن كل جلسة هي
استعادة OTP هو **[INFER]** مبني على إفادة المالك وعلى أن `verifyOTP` يُنشئ جلسة؛ لكن الجلسة تنشأ أيضاً من أي تسجيل دخول آخر.

### 3.3 حالة `account_devices` لحظة الفحص (2026-10-20 بعد 12:14 UTC، قبل الإصلاح) [PRIOR؛ الأجهزة القديمة أُعيد التحقق منها [DB]]

| الجهاز | المنصة | الحالة | `last_seen_at` | `xmin` (آخر كتابة) |
|---|---|---|---|---|
| realme RMX5313 | android | **active** | (غير مثبت في هذا التقرير) | 3969273 |
| DESKTOP-UOO8OTJ | windows | **revoked** | 12:14:25 | 3969124 |
| Blackview Tab 60 Pro | android | revoked | 10-19 14:58 | 3948494 |
| HONOR HEY2-W09 | android | revoked | 10-05 13:36 | 3948593 |
| Web · chrome · MacIntel | web | revoked | 08-21 22:24 | 3948605 |
| Web · chrome · Linux armv81 | web | revoked | 08-25 20:07 | 718600 |

تحليل الزمن النسبي (لا يوجد `track_commit_timestamp` ⇒ نعتمد ترتيب `xmin`):

- الحاسوب: آخر ظهور 12:14:25 ثم فُصل بمعاملة `3969124`. (`last_seen_at` لا يتغيّر بالفصل لأن الفصل يحدّث `access_status` فقط، فوقت الفصل غير معروف إلا أنه بعد 12:14:25.)
- جلسة الهاتف الجديدة أُنشئت 12:14:34 (بعد آخر ظهور للحاسوب بـ **9 ثوانٍ**).
- آخر كتابة على صف الهاتف: المعاملة `3969273`، أي **بعد معاملة فصل الحاسوب بـ 149 رقم معاملة** [PRIOR].
- **[INFER]** أن الهاتف نفّذ استعادة OTP بعد 12:14:34 فأفصل الحاسوب؛ **لا يمكن الجزم** لأن الجدول لا يحفظ تاريخ تغيّر الحالة
  (`track_commit_timestamp = off` ولا `updated_at`)، وأي نبضة لاحقة من الهاتف تعيد كتابة صفه فتمحو أثر معاملة الاستعادة في `xmin`.
- هذا القسم مصدره فحص الإنتاج في جلسة سابقة (قبل النشر) [PRIOR]؛ لا يمكن إعادة تجربته الآن لأن الحالة تغيّرت.

---

## 4. الفرضيات المستبعدة (مع الدليل)

| الفرضية | الحكم | الدليل |
|---|---|---|
| اسم المستخدم المحلي المشترك يسبب التصادم | **مستبعدة** | لا يصل للسيرفر (§2). لا دالة/جدول يقارنه. |
| `signOut()` يقتل كل جلسات الحساب | **مستبعدة** | `gotrue` 2.20/2.22: `signOut({SignOutScope scope = SignOutScope.local})` [CODE في `~/.pub-cache`]. كل استدعاءات `auth.signOut()` في المشروع بلا `scope` (`auth_provider.dart`: 574, 929, 1010, 1546, 1961, 2820, 2901, 2915, 3888, 4092, 4253) ⇒ محلي. |
| إعداد «جلسة واحدة لكل مستخدم» في Supabase Auth | **مستبعدة** | جلسات متعددة متزامنة للحساب في `auth.sessions` (مثلاً جلسة الهاتف 06:36→11:06 بقيت قائمة أثناء إنشاء جلسات للحاسوب) [DB]. |
| تجاوز حد الأجهزة | **مستبعدة** | الرخصة النشطة `max_devices = 6`؛ الأجهزة النشطة 1 أو 2 [DB]. |
| مسار Kill Switch (`tenant_access`) | **مستبعدة لهذا الحساب** | لا يوجد صف في `public.tenant_access` لهذا الحساب [DB]. وبنية المسار (`cloud_sync_service.dart:2143–2300`) تطرد **كل** أجهزة الحساب معاً وليس جهازاً واحداً بالتناوب. وهو يصل لنفس الشاشة الزرقاء (`main.dart:176–195` يعيد استخدام `DeviceKickedOutScreen`) — لذا لا يجوز الخلط بين المسارين عند تقييم شكوى مستقبلية. |
| الـ dedupe بالاسم | **ليس سبب هذه الحادثة تحديداً** | اسم الحاسوب `DESKTOP-UOO8OTJ` واسم الهاتف `realme RMX5313` مختلفان؛ لا يشكّلان مجموعة dedupe. لكنه خلل حقيقي (§6.1). |

---

## 5. السبب الجذري: حلقة `revoked` التي لا مخرج آمن منها

### 5.1 العناصر الأربعة

**(1) `app_register_device` يرفض العودة دون مراعاة الحد** [DB، النص القديم]:

```sql
if v_was_known and lower(coalesce(v_existing.access_status, 'active')) = 'revoked' then
  select count(*)::int into v_active
  from public.account_devices d
  where d.user_id = v_uid
    and coalesce(d.access_status, 'active') = 'active';

  if v_active > 0 then
    return jsonb_build_object(
      'access_status',      'revoked',
      'is_over_limit',      false,
      'active_devices',     v_active,
      'max_devices',        coalesce(public.app_user_max_devices(), 0),
      'already_registered', true
    );
  end if;
end if;
```

الشرط `v_active > 0` — لا `v_active >= v_max`. جهاز مفصول مع جهاز واحد نشط من 6 يُرفض.

**(2) `prevent_device_self_unrevoke`** [DB، النص القديم]:

```sql
if tg_op = 'UPDATE'
   and lower(coalesce(old.access_status, 'active')) = 'revoked'
   and lower(coalesce(new.access_status, 'active')) is distinct from 'revoked' then
  if exists (
    select 1 from public.account_devices d
    where d.user_id = new.user_id
      and d.device_id is distinct from new.device_id
      and lower(coalesce(d.access_status, 'active')) <> 'revoked'
  ) then
    raise exception 'cannot_unrevoke_while_other_devices_active';
  end if;
end if;
```

الـ trigger لا يعرف **من** يُجري الـ UPDATE. زر «السماح من جهاز نشط» (`approveDeviceAccess`، `cloud_sync_service.dart:1338`)
يُجري `UPDATE` من جهاز نشط، فيرى الـ trigger «جهازاً آخر نشطاً» (الجهاز نفسه الذي يضغط الزر) ⇒ يرفض. **الزر لا ينجح أبداً.**
قياس فعلي [LOCAL، النسخة القديمة]: `[B2] approve UPDATE: FAILED -> cannot_unrevoke_while_other_devices_active`.

**(3) `app_owner_recover_device(..., true)` يفصل الجميع** [DB، النص القديم]:

```sql
if p_revoke_other_devices then
  update public.account_devices
  set access_status = 'revoked'
  where user_id = v_uid
    and device_id <> p_device_id
    and coalesce(access_status, 'active') = 'active';
end if;
```

والعميل يمرّر `true` دائماً: `recoverDeviceAccessViaEmailOtp(... bool revokeOtherDevices = true)` (`auth_provider.dart:3941–3946`)
⇒ `ownerRecoverCurrentDeviceAfterEmailVerified(revokeOthers: revokeOtherDevices)` (`3953`).
قياس فعلي [LOCAL، القديم]: حد 6، ثلاثة أجهزة أخرى نشطة، استعادة جهاز رابع ⇒ **الثلاثة فُصلوا**:
`state: PC=revoked, PHONE=active, TAB=revoked, X4=revoked`.

**(4) الطرد عند اكتشاف `revoked`** — في الكود مساران [CODE]؛ **على الإنتاج يعمل واحد فقط (المزامنة)** لأن `account_devices` غير منشور في Realtime (§2.1):

أ) **Realtime** (معطّل فعلياً بسبب غياب الجدول من المنشور):

```dart
// lib/services/cloud_sync_service.dart:2113-2123
callback: (payload) {
  final map = payload.newRecord;
  ...
  if (map['device_id']?.toString() == deviceId &&
      map['access_status']?.toString().toLowerCase() == 'revoked') {
    final kick = onRemoteDeviceRevoked;
    if (kick != null) {
      unawaited(kick());
    }
  }
  unawaited(refreshDevices());
},
```

```dart
// lib/main.dart:151-166
CloudSyncService.instance.onRemoteDeviceRevoked = () async {
  if (_remoteKickInProgress) return;
  _remoteKickInProgress = true;
  try {
    final nav = appRootNavigatorKey.currentState;
    final ctx = appRootNavigatorKey.currentContext;
    if (nav == null || ctx == null || !nav.mounted) return;
    final auth = Provider.of<AuthProvider>(ctx, listen: false);
    await auth.logout();
    if (!nav.mounted) return;
    await nav.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const DeviceKickedOutScreen()),
      (_) => false,
    );
  } finally {
    _remoteKickInProgress = false;
  }
};
```

لا تأكيد، ولا تمييز بين فصل مقصود وفصل ناتج عن استعادة جهاز آخر.

ب) **المزامنة (المسار الفعلي)** (`cloud_sync_service.dart:1533–1552`): كل دورة (كل دقيقة، `1715–1721`) تمرّ بفحص الترخيص
ثم تستدعي `registerCurrentDevice()`؛ إن رجع `revoked` يُستدعى `onRemoteDeviceRevoked` (1548–1550). **فزمن الطرد الفعلي بعد
الفصل على السيرفر = حتى 60 ثانية** (وأكثر إن كان التطبيق في الخلفية أو الترخيص غير نشط فلا تصل الدورة إلى التسجيل — 1506–1517).

### 5.2 المخطط الزمني للحلقة

```
t0  الحاسوب (D) والهاتف (P) نشطان.
t1  P يُفصل (أي سبب §5.4)  → UPDATE access_status='revoked' على صف P.
t2  نبضة المزامنة التالية على P (≤ 60 ث) تحصل على revoked → onRemoteDeviceRevoked → logout + الشاشة الزرقاء.
t3  المستخدم يعيد الدخول على P → register → (1) يرجع revoked لأن D نشط.
t4  شاشة device_access_revoked على P: خياران:
      أ) «السماح من جهاز نشط» → UPDATE مباشر → (2) يرفضه الـ trigger.      ✗
      ب) OTP البريد → app_owner_recover_device(P, true) → (3).             ✓ لكن...
t5  (3) يفصل D (وكل جهاز آخر نشط) ويفعّل P.
t6  نبضة المزامنة التالية على D (≤ 60 ث) تحصل على revoked → (4) → D يُطرد بالشاشة الزرقاء.
t7  D يعيد الدخول → نفس t3→t5 بدور معكوس → يفصل P.   ⇒ حلقة.
```

### 5.3 لماذا يجب ألا يحدث هذا بغض النظر عن السبب الأول

تصميم صحيح يفصل مفهومين: (أ) **الحد** — عدد الأجهزة النشطة ≤ `max_devices`، (ب) **الإلغاء المقصود**. الكود القديم استعمل
حالة واحدة (`revoked`) لثلاثة معانٍ: «أزاله المالك»، «خرج نهائياً»، «اعتُبر مكرراً»، ثم عالج العودة من أي منها بقاعدة «ممنوع
ما دام آخر نشطاً» بغض النظر عن الحد. لهذا يتحول أي فصل عابر إلى طريق ذي اتجاه واحد لا يُفتح إلا بإغلاق باب آخر.

### 5.4 ما الذي يكتب `revoked` في الكود (القائمة الكاملة)

[CODE — بحث `access_status.*revoked|_revokeDeviceRow|removeDevice|…`]

| الكاتب | الملف:السطر | متى |
|---|---|---|
| «الخروج النهائي» | `signOutAndRevokeCurrentDevice` — `cloud_sync_service.dart:1298` ⇒ `_revokeDeviceRow` (1316) | زر الخروج النهائي في شاشة PIN (`employee_pin_gate_screen.dart:471/514` ⇒ `signOutPermanentlyFromDevice` `auth_provider.dart:3866`) |
| «فصل جهاز» | `removeDevice` — `cloud_sync_service.dart:1184` | صفحة الاشتراك `account_subscription_screen.dart:125` (`_removeDevice`) |
| الـ dedupe | `_dedupeActiveDuplicateDevicesOnServer` — 1087 ⇒ `_revokeDeviceRow` (1114) | تلقائياً في `refreshDevices()` (1159) |
| احتياطي الاستعادة | `_ownerRecoverDeviceClientFallback` — 1264 (يُستدعى من 1246) | عند غياب RPC الاستعادة على السيرفر |
| ترحيل UUID | `device_uuid_migrator.dart:66–91` | يفصل صف `legacy device_id` بعد الترحيل |
| الاستعادة على السيرفر | `app_owner_recover_device` | عبر OTP |

أي واحد منها كافٍ لإشعال الحلقة. **لا يمكن تحديد أيها أشعل الحلقة في 2026-10-20 لأن السيرفر لم يكن يسجّل ذلك.**

---

## 6. نتائج ثانوية (موجودة وغير مُصلَحة بالسيرفر)

### 6.1 الـ dedupe يفصل أجهزة متشابهة الاسم — داخل التطبيق

```dart
// cloud_sync_service.dart:901-902
String _deviceDedupeKey(AccountDevice d) =>
    '${_normDedupeKeyPart(d.deviceName)}|${_normDedupeKeyPart(d.platform)}';
```

`_pickDedupeKeeper` (922–944): الجهاز الحالي دائماً هو «الحارس» (`byCurrent`)، ويُفصل غيره من نفس المجموعة (1108–1115).
هاتفان من نفس الطراز (`brand model` متطابق، `license_engine_v2.dart:172–173`) على نفس الحساب ⇒ **أول من يستدعي
`refreshDevices()` يفصل الآخر**؛ الآخر يستعيد بـ OTP فيفصل الأول (قبل الإصلاح)، وبعد الإصلاح يعود تلقائياً لكن الأول
يعيد فصله في دورته التالية ⇒ **الحلقة ممكنة بين أجهزة من نفس الطراز إلى أن يُحذف هذا المنطق من التطبيق.**
Windows: `computerName` (`license_engine_v2.dart:179`) فريد غالباً فلا يتأثر.
وهناك أيضاً `_pruneRevokedHandsetDuplicatesOnServer` (947–981) الذي **يحذف** (DELETE) صفوف المفصولين المطابقين ⇒ فقدان تاريخ.

### 6.2 معالج الطرد قد يفشل جزئياً [CODE، قراءة ثابتة — لم يُختبر تشغيلاً]

`main.dart:158`: `await auth.logout();` — و`logout()` (`auth_provider.dart:4218`) يبدأ بـ:

```dart
await _assertNoBlockingSyncQueue(actionLabel: 'تسجيل الخروج', allowUnsyncedDataLoss: allowUnsyncedDataLoss); // 4225
await _assertNoOpenShiftForLogout(...);                                                                   // 4229
```

وكلاهما يرمي `StateError` (`auth_provider.dart:255` للمزامنة، `347` للوردية المفتوحة) ما لم تُمرَّر أعلام التجاوز، والمعالج
لا يمررها ولا يلتقط الاستثناء (`try/finally` فقط). النتيجة النظرية: جهاز عليه **وردية مفتوحة** أو **قائمة مزامنة غير فارغة** يُفصل
على السيرفر لكن الطرد المحلي لا يكتمل؛ تتكرر المحاولة كل دقيقة من مسار المزامنة (§5.1) ويبقى التطبيق شغّالاً بحالة `revoked`.
يتقاطع هذا مع سيناريو المستخدم (شاشة «تبديل الزيت» = وردية). **يحتاج اختباراً تشغيلياً قبل الجزم.**

### 6.3 المزامنة تستدعي التسجيل كل دقيقة

`Timer.periodic(Duration(minutes: 1))` ⇒ `syncNow(forcePull:false)` ⇒ `registerCurrentDevice()` (1535). هذا مهم لنافذة السماح (§11.1).

### 6.4 الحد الافتراضي 2

`app_user_max_devices()` ينتهي بـ `coalesce(..., 2)`. أي فجوة في رخصة `active/trial` المسندة ⇒ الحد 2 فجأة ⇒ جهاز ثالث
جديد يُرفض بـ `DEVICE_LIMIT_REACHED` وجهاز مفصول لا يعود. **[PRIOR]** ذُكر أن رخصة الحساب كانت موقوفة لفترة في يوم الحادثة؛
لم أُعد التحقق من التواريخ هنا. حالياً الرخصة 31 نشطة.

### 6.5 `_ensureCurrentDeviceActiveIfReturning` يكرر قاعدة السيرفر القديمة

`cloud_sync_service.dart:1021–1029`: إن وُجد جهاز آخر نشط «لا نعيد التفعيل». هذا فرض عميل مستقل عن السيرفر. بعد إصلاح السيرفر لا
يضر (يتخطى فقط ثم يستدعي RPC الذي يعيد التفعيل)، لكنه يوضح أن نموذج «الفصل المقصود يبقى ما دام آخر نشطاً» مكرَّر في الطبقتين.

### 6.6 ترحيل UUID يتجاوز `app_register_device`

`device_uuid_migrator.dart:143–153`: عند غياب `legacy` يُنفّذ `upsert` بـ `'access_status': 'active'` مباشرة (لا عبر RPC) ⇒ يتجاوز
فحص الحد. صف موجود ومفصول سيمر عبر `ON CONFLICT DO UPDATE` فيعترضه الـ trigger الجديد بفحص الحد (§7)، لكن صف **جديد**
يُدرج بلا فحص حد. أثر محدود (حالة إعادة التثبيت)، يُسجَّل هنا للاكتمال.

### 6.7 ملاحظة أداء/أقفال [PRIOR]

سُجّلت في جلسة سابقة أخطاء `statement timeout (57014)` أثناء `app_register_device` تحت تزاحم. الدالة تأخذ advisory lock ثم
`FOR UPDATE` على كل صفوف المستخدم، وتُستدعى من كل جهاز كل دقيقة + عند الإقلاع/الدخول. لم أعد قياس ذلك هنا؛ الإصلاح لم يغيّر
هذا السلوك عدا إضافة نفس ترتيب الأقفال لدالة الاستعادة (§7.4).

---

## 7. تصميم الإصلاح

### 7.1 المبادئ

1. **السيرفر مصدر الحقيقة للحد.** القرار «هل يُسمح بعودة الجهاز» = `النشط الآن < max_devices` وليس `النشط = 0`.
2. **الاستعادة لا تُعاقب الآخرين إلا بقدر الضرورة.** تُفصل أقدم الأجهزة نشاطاً وبالعدد اللازم لإفساح مكان.
3. **توافق عكسي كامل:** لا تغيير في أسماء/توقيعات الدوال ولا أعمدة جدول `account_devices` ⇒ نسخ التطبيق المنتشرة تعمل.
4. **لا يمس البيانات الحيّة:** لا `UPDATE` على أي صف ⇒ لا أحداث Realtime ⇒ لا يُطرد أحد لحظة النشر.
5. **قابل للتدقيق:** تسجيل كل تغيير حالة مع المصدر والجلسة.
6. **قابل للتراجع الكامل** بملف واحد.

### 7.2 الملفات

| الملف | الغرض | الأسطر (تقريباً) |
|---|---|---|
| `migrations/20261020_device_lifecycle_fix.sql` | الإصلاح، معاملة واحدة، idempotent | 491 |
| `migrations/20261020_device_lifecycle_fix.rollback.sql` | تراجع كامل لنسخ الإنتاج الأصلية + حذف جدول التدقيق | 268 |
| `migrations/20261020_device_lifecycle_fix.test.sql` | اختبار داخل كتلة `DO` ينتهي دائماً بـ `RAISE EXCEPTION` ⇒ يلغي كل أثره | 216 |
| `tool/device_lifecycle_local_stub.sql` | مخطط محلي مصغّر لتشغيل الاختبار بدون Supabase | 107 |

### 7.3 التغييرات بالتفصيل

#### (أ) جدول التدقيق `public.account_device_events`

```sql
create table if not exists public.account_device_events (
  id               bigint generated always as identity primary key,
  user_id          uuid        not null,           -- بلا FK عمداً
  device_id        text        not null,
  event_type       text        not null,           -- insert | status_change | delete
  old_status       text,
  new_status       text,
  source           text        not null default 'direct',  -- rpc:<fn> | direct
  actor_uid        uuid,
  actor_role       text,
  actor_session_id text,                           -- auth.jwt()->>'session_id'
  created_at       timestamptz not null default now()
);
```

- فهارس: `(user_id, device_id, created_at desc)` و`(user_id, created_at desc)`.
- RLS مفعّل؛ سياسة `device_events_own_select` (SELECT حيث `auth.uid() = user_id`)؛ `revoke all ... from anon, authenticated` ثم
  `grant select ... to authenticated`. **لا كتابة من العميل أبداً** (الكتابة عبر trigger SECURITY DEFINER).
- بلا FK إلى `auth.users` حتى لا يُعطّل حذف مستخدم/جهاز (cascade) ولتبقى السجلات.
- `actor_session_id` = `session_id` في JWT ⇒ يُربط بـ `auth.sessions` (`user_agent`, `created_at`) لمعرفة **أي جهاز فيزيائي** نفّذ الفصل.
- `source`: الدوال تضبط `app.device_source` (`set_config(..., true)` محلي للمعاملة) إلى `rpc:app_register_device` أو
  `rpc:app_owner_recover_device` وتعيده إلى `''` قبل كل `return`؛ غيابها ⇒ `direct` (أي `UPDATE` مباشر من التطبيق: خروج نهائي/فصل/dedupe/موافقة).
  **لا يمكن التمييز بين هذه الأربعة داخل `direct`** — قيد معروف (§11.2).

```sql
create trigger trg_log_account_device_change
  after insert or update of access_status or delete
  on public.account_devices
  for each row execute function public.log_account_device_change();
```

الدالة `log_account_device_change()` مغلّفة بـ `begin … exception when others then null; end;` ⇒ فشل التدقيق **لا يكسر** تسجيل الجهاز.
`revoke all on function ... from public, anon, authenticated`.
تكلفة: النبضة المنتظمة تُنفِّذ `ON CONFLICT DO UPDATE SET access_status = 'active'` فيُطلق الـ trigger (لأن العمود في قائمة SET)، لكن الدالة
تتجاهل الحالة غير المتغيرة (`old is distinct from new`) ⇒ لا كتابة.

#### (ب) `prevent_device_self_unrevoke`

القاعدة الجديدة: انتقال `revoked → active` مسموح إن كان **عدد الأجهزة النشطة الأخرى < الحد**؛ وإلا:
`raise exception 'cannot_unrevoke_device_limit_reached: active=% max=%'`. `service_role` كما كان. SQL بلا هوية مستخدم
(`auth.uid() is null`، مثل لوحة الإدارة) غير مقيَّد. `v_max = 0` ⇒ بلا حد.

لم أضف advisory lock داخل الـ trigger عمداً: BEFORE ROW trigger يعمل بعد قفل الصف، وأخذ advisory بعده يعكس ترتيب الأقفال
في `app_register_device` (advisory ثم صفوف) فيفتح باب deadlock. الثمن: سباق نظري يتجاوز الحد بجهاز واحد في مسار `UPDATE` المباشر
(§11.3).

#### (ج) `app_register_device` — الجزء المتغير فقط

الكتلة القديمة (§5.1.1) استُبدلت بـ:

```sql
if v_was_known and lower(coalesce(v_existing.access_status, 'active')) = 'revoked' then
  v_max := coalesce(public.app_user_max_devices(), 0);

  select count(*)::int into v_active
  from public.account_devices d
  where d.user_id = v_uid and coalesce(d.access_status, 'active') = 'active';

  -- (أ) نافذة سماح 30 ثانية بعد الفصل
  select max(e.created_at) into v_revoked_at
  from public.account_device_events e
  where e.user_id = v_uid and e.device_id = p_device_id and e.new_status = 'revoked';

  if v_revoked_at is not null and v_revoked_at > v_now - interval '30 seconds' then
    v_result := jsonb_build_object('access_status','revoked','is_over_limit',false,
      'active_devices',v_active,'max_devices',v_max,'already_registered',true,
      'reason','recently_revoked');
    perform set_config('app.device_source', '', true);
    return v_result;
  end if;

  -- (ب) لا مكان ضمن الحد ⇒ يبقى مفصولاً
  if v_max <> 0 and v_active >= v_max then
    v_result := jsonb_build_object('access_status','revoked','is_over_limit',false,
      'active_devices',v_active,'max_devices',v_max,'already_registered',true,
      'reason','device_limit_reached');
    perform set_config('app.device_source', '', true);
    return v_result;
  end if;
  -- (ج) يوجد مكان ⇒ نكمل ونُعيد التفعيل عبر الـ upsert الأصلي أدناه
end if;
```

- الشكل `jsonb` المُعاد **لم يتغير** سوى مفتاح إضافي `reason` — العميل يقرأ `access_status` فقط (`cloud_sync_service.dart:807–814`).
- ما تبقى من الدالة **حرفياً** كما كان (سياسات الويب، الحد للأجهزة الجديدة، upsert) مع `perform set_config(...)` وإعادة ضبط المصدر قبل كل `return`.
- **سبب نافذة 30 ثانية** (أضفتها أثناء التصميم): كان تقديري أن نبضة عالقة من جهاز فصله المالك للتوّ قد تُعيده `active` قبل أن
  يصله حدث Realtime فيُلغى الفصل اليدوي بصمت. **هذا التقدير بُني على افتراض خاطئ**: Realtime غير فعّال لهذا الجدول على الإنتاج
  (§2.1)، فالنبضة نفسها هي وسيلة إبلاغ الجهاز بفصله، والنافذة 30 ثانية أقصر من دورة النبض 60 ثانية. التبعات في §11.1 — **وهي أهم
  نقطة ضعف في الإصلاح الحالي.**

#### (د) `app_owner_recover_device` (نفس التوقيع)

```sql
-- نفس ترتيب أقفال app_register_device
perform pg_advisory_xact_lock(hashtext('register_device:' || v_tenant_id)::bigint);
perform 1 from public.account_devices d where d.user_id = v_uid for update;
perform set_config('app.device_source', 'rpc:app_owner_recover_device', true);

-- DEVICE_NOT_FOUND مبكراً
...
v_max := coalesce(public.app_user_max_devices(), 0);
select count(*)::int into v_others from public.account_devices d
 where d.user_id = v_uid and d.device_id <> p_device_id
   and coalesce(d.access_status, 'active') = 'active';

if v_max <> 0 and v_others >= v_max then
  if not coalesce(p_revoke_other_devices, false) then
    raise exception 'DEVICE_LIMIT_REACHED: % active devices (limit=%)', v_others, v_max using errcode = 'P0001';
  end if;
  v_free := v_others - (v_max - 1);        -- عدد من يجب فصلهم
  with victims as (
    select d.id from public.account_devices d
     where d.user_id = v_uid and d.device_id <> p_device_id
       and coalesce(d.access_status, 'active') = 'active'
     order by d.last_seen_at asc nulls first, d.id asc
     limit v_free)
  update public.account_devices a set access_status = 'revoked' from victims v where a.id = v.id;
  get diagnostics v_evicted = row_count;
end if;
-- ثم تفعيل الجهاز المطلوب كما كان
```

- القيمة `p_revoke_other_devices = true` تعني الآن «يُسمح بفصل الأقدم لإفساح مكان» وليس «افصل الكل».
- يُعيد حقلين إضافيين `max_devices` و`revoked_others` (العميل يتجاهلهما).
- ترتيب الأقفال مطابق لـ `app_register_device` ⇒ لا deadlock (§9.4).
- الأقدم نشاطاً = `last_seen_at` الأصغر ثم `id` الأصغر.

### 7.4 مصفوفة التوافق مع نسخ التطبيق الحالية

| استدعاء العميل | قبل | بعد | يحتاج تحديث تطبيق؟ |
|---|---|---|---|
| `rpc('app_register_device', ...)` يقرأ `access_status` | `revoked` عند وجود أي نشط | `active` عند وجود مكان | لا |
| `rpc('app_owner_recover_device', {p_revoke_other_devices:true})` | يفصل كل الآخرين | يفصل الأقدم فقط عند الامتلاء | لا |
| `UPDATE access_status='active'` (زر «السماح») | يُرفض دائماً | ينجح إن وُجد مكان | لا |
| `UPDATE access_status='revoked'` (خروج/فصل/dedupe) | يمر | يمر + يُسجَّل في الأحداث | لا |
| Realtime على `account_devices` | لا يصل شيء (الجدول غير منشور) | كما قبل (لم يُغيَّر المنشور) | لا |

### 7.5 ما لم يتغير

- أي صف في `account_devices` (لا `UPDATE`/`DELETE` في الـ migration).
- أعمدة الجدول (لا `ALTER TABLE` عليه). الأقفال الوحيدة على الجدول: `SHARE ROW EXCLUSIVE` لحظة `CREATE TRIGGER`، مع `lock_timeout = 3s`.
- أسماء وتوقيعات كل الدوال.
- سلوك الأجهزة الجديدة (الحد، سياسة الويب).

---

## 8. التحقق المحلي (PostgreSQL 16 مؤقت) [LOCAL]

أُنشئ cluster مؤقت (`initdb`، منفذ مخصص) وحُمّل `tool/device_lifecycle_local_stub.sql` (يحاكي `auth.uid()/jwt()/role()` والأدوار
`anon/authenticated/service_role` وجداول `licenses/account_devices` + RLS)، ثم ثُبّتت **نسخ الإنتاج القديمة** من ملف التراجع، ثم
اختُبر. حُذف الـ cluster بعد كل جولة.

### 8.1 إعادة إنتاج الخلل على النسخ القديمة (قبل)

حد 6 (رخصة active/monthly)، جهازان `PC` و`PHONE`:

```
[B1] register revoked PHONE (1 of 6 slots used):
     {"max_devices": 6, "access_status": "revoked", "is_over_limit": false, "active_devices": 1, "already_registered": true}
[B2] approve UPDATE: FAILED -> cannot_unrevoke_while_other_devices_active
[B3] recover(PHONE,true) with 3 other active devices of limit 6 ->
     {"device_id": "PHONE", "access_status": "active", "active_devices": 1}
     state: PC=revoked, PHONE=active, TAB=revoked, X4=revoked
```

(ملاحظة: التسمية في مخرج الاختبار الأصلي كتبت «4 active» والصحيح أن الآخرين النشطين كانوا `PC` و`TAB` و`X4` = 3؛ والرابع `PHONE` هو المُستعاد.)

### 8.2 النسخ الجديدة (بعد)

نفس السيناريو:

```
[A1] register revoked PHONE (1 of 6 slots used):
     {"max_devices": 6, "access_status": "active", "is_over_limit": false, "active_devices": 2, "already_registered": true}
[A2] approve UPDATE: SUCCEEDED
[A3] recover(PHONE,true) with 3 other active devices of limit 6 ->
     {"device_id": "PHONE", "max_devices": 6, "access_status": "active", "active_devices": 4, "revoked_others": 0}
     state: PC=active, PHONE=active, TAB=active, X4=active
```

(في A1 أُجري تقديم مصطنع لعمر حدث الفصل 5 دقائق لتجاوز نافذة الـ 30 ثانية.)

### 8.3 الاختبار الشامل `*.test.sql`

سيناريو A (حد 2 افتراضي بلا رخصة) وسيناريو B (رخصة بحد 6). النتيجة المتوقعة (رسالة «خطأ» مقصودة):

```
TEST_PASSED_AND_ROLLED_BACK: A1 A2 A3 A4 A5 A6 A7 A8 A9 A10 B2 B3 B4 RLS
```

| الرمز | ما يتحقق منه |
|---|---|
| A1 | تسجيل جهازين ⇒ `active` |
| A2 | `UPDATE` مباشر بالفصل ⇒ يُسجَّل حدث `source='direct'` بـ `actor_session_id` الصحيح |
| A3 | نبضة فورية بعد الفصل ⇒ `revoked` + `reason=recently_revoked` |
| A4 | بعد النافذة ومع وجود مكان ⇒ **يعود `active`** ويبقى الآخر نشطاً (**إصلاح المشكلة الأصلية**) |
| A5 | الحد ممتلئ ⇒ المفصول يبقى `revoked` + `reason=device_limit_reached`؛ جهاز جديد ⇒ `DEVICE_LIMIT_REACHED` |
| A6 | استعادة والحد ممتلئ ⇒ يُفصل **واحد فقط = الأقدم نشاطاً**، والحدث `source='rpc:app_owner_recover_device'` |
| A7 | استعادة بـ `false` والحد ممتلئ ⇒ `DEVICE_LIMIT_REACHED` |
| A8 | زر «السماح»: يُرفض عند الامتلاء (`cannot_unrevoke_device_limit_reached`)، وينجح عند وجود مكان |
| A9 | استعادة مع وجود مكان ⇒ `revoked_others = 0` |
| A10 | `DEVICE_NOT_FOUND` محفوظ |
| B2 | **حالة الحادثة:** حد 6، هاتف مفصول، جهاز آخر نشط ⇒ يعود |
| B3 | استعادة والحد بعيد ⇒ لا تفصل أحداً |
| B4 | ملء الحد (6) ثم الجهاز السابع الجديد ⇒ `DEVICE_LIMIT_REACHED` |
| RLS | مستخدم آخر لا يرى أحداثاً ليست له، ولا يستطيع الكتابة في جدول التدقيق |

وبعد الاختبار: `auth.users=0, account_devices=0, account_device_events=0` (لا تبقى بيانات).

### 8.4 خصائص الـ migration

| الاختبار | النتيجة |
|---|---|
| تطبيق مرة | نجح |
| تطبيق مرتين (idempotency) | نجح (إشعارات «already exists» فقط) |
| تراجع ثم إعادة التطبيق ثم الاختبار | نجح |

### 8.5 ضغط متوازي (أقفال)

`pgbench`: 8 اتصالات متوازية على **نفس الحساب** (3 أجهزة): سكربتات تسجيل + استعادة + فصل مباشر (UPDATE) تعمل معاً.
(تفاصيل السكربتات وأوزانها لم أحفظها في المستودع؛ النتائج أدناه من الجلسة السابقة [PRIOR].)

| المقياس | القيمة |
|---|---|
| المعاملات الإجمالية | ≈ 12 ألف |
| معاملات فاشلة | **0** |
| deadlocks في سجل الخادم | **0** |
| الحالة النهائية | 2 نشط، **الحد لم يُتجاوز** |

تنبيه صريح: لم أحفظ سكربتات `pgbench` ضمن الملفات، فلا يمكن إعادة إنتاج هذا الرقم حرفياً من المستودع. إن أردت اختباراً قابلاً
لإعادة التشغيل يجب إضافة سكربتاته إلى `tool/`.

### 8.6 ما لم يُختبر محلياً

Supabase Realtime الحي، مسار PostgREST الحقيقي (JWT حقيقي بدل `set_config`)، الأدوار الحقيقية لـ Supabase، أي مخطط إنتاج غير الموصوف في الـ stub.

---

## 9. النشر على الإنتاج [DB]

### 9.1 القرار

بعد موافقة المالك الصريحة («قم بتشغيلها أنت حتى أبدأ أنا بالاختبار الميداني») — لا يوجد staging منفصل في هذا المشروع.

### 9.2 قبل النشر [PRIOR]

- حالة صفوف الحساب مأخوذة كلقطة: **جهاز نشط واحد من 6**.
- التأكد من سلامة الملف: **491 سطراً**.

### 9.3 التنفيذ [PRIOR]

`supabase db query --linked -f migrations/20261020_device_lifecycle_fix.sql` ⇒ نجح بلا أخطاء. بعده مباشرة: صفوف الحساب كما هي
(**1 نشط من 6**، لا صف تغيّر ⇒ لم يُطرد أحد لحظة النشر). الوقت الدقيق للتنفيذ غير مسجّل؛ هو قبل 15:06:36 UTC (أول جلسة بعده) وبعد جلسة الهاتف 12:14:34.

### 9.4 التحقق من حالة الإنتاج الآن [DB — أُعيد التحقق منه 2026-10-21]

| الفحص | النتيجة |
|---|---|
| `to_regclass('public.account_device_events')` | موجود |
| triggers على `account_devices` | `trg_log_account_device_change` (AFTER INSERT OR DELETE OR UPDATE OF access_status) + `trg_prevent_device_self_unrevoke` (BEFORE UPDATE) |
| `app_register_device` يحوي `recently_revoked` | نعم |
| `app_owner_recover_device` يحوي `revoked_others` | نعم |
| `prevent_device_self_unrevoke` يحوي `device_limit_reached` | نعم |
| سياسات RLS | `device_events_own_select` (SELECT) على الأحداث؛ `devices_own_select` + `devices_own_write` على الأجهزة |
| صلاحيات `account_device_events` | `authenticated`: SELECT فقط؛ `service_role`/`postgres`: كاملة |
| `account_device_events` في `supabase_realtime` | **لا** (مقصود) — ولا `account_devices` أيضاً (§2.1) |

### 9.5 اختبار ذاتي الإلغاء على الإنتاج [PRIOR]

شُغّل `*.test.sql` على الإنتاج نفسه (كتلة `DO` تنتهي بـ `RAISE EXCEPTION`)، والمخرج:

```
TEST_PASSED_AND_ROLLED_BACK: A1 A2 A3 A4 A5 A6 A7 A8 A9 A10 B2 B3 B4 RLS
```

وبعده: جدول التدقيق فارغ (0 أحداث) ولا بيانات اختبار متبقية.
أثر جانبي متوقع: الـ identity sequence لا يتراجع، لذلك أول حدث حقيقي حمل `id = 23` [DB: `max(id)=23`، `count=1`]. أن ids 1–22 استهلكها
الاختبار الذاتي الإلغاء هو **[INFER]** (متسق مع عدد التغييرات التي يُحدثها، لم أعدّها حرفياً).

---

## 10. الدليل الميداني بعد النشر [DB — استعلام 2026-10-21 ≈ 09:46 UTC]

### 10.1 جدول التدقيق

صف وحيد:

| id | device | حدث | المصدر | الدور | جلسة | الوقت |
|---|---|---|---|---|---|---|
| 23 | `625b739e-5449…` = **DESKTOP-UOO8OTJ** | `status_change` `revoked → active` | **`rpc:app_register_device`** | authenticated | `06c3ea4c` | **2026-10-20 15:06:38 UTC** |

قراءة:

- الحاسوب عاد **تلقائياً عبر تسجيل عادي** (`rpc:app_register_device`) — **لا** عبر الاستعادة (`rpc:app_owner_recover_device`)، أي بلا OTP، **ولم يُفصل أي جهاز آخر**.
- ربط الحدث بـ `auth.sessions` عبر `actor_session_id` يعمل [DB]: الجلسة `06c3ea4c…` أُنشئت **15:06:36.149** وUA = `Dart/3.13` — وهذا يؤكد (بدل أن يفترض) أن `Dart/3.13` = الحاسوب، لأن الحدث يخص جهاز `DESKTOP-UOO8OTJ`.
- جلسة الحاسوب الجديدة أُنشئت **15:06:36**، أي قبل الحدث بـ **ثانيتين**: تسجيل دخول ⇒ `app_register_device` ⇒ عودة فورية. (مدة بقاء الحاسوب مفصولاً قبل ذلك: من ≈ 12:14 إلى 15:06 = ≈ 2 س 52 د.)
- **صفر** أحداث `revoked` منذ النشر.

### 10.2 حالة الأجهزة الآن

| الجهاز | الحالة | `last_seen_at` |
|---|---|---|
| DESKTOP-UOO8OTJ (windows) | **active** | 2026-10-21 09:25:23 |
| realme RMX5313 (android) | **active** | 2026-10-21 08:55:32 |
| Blackview Tab 60 Pro / HONOR HEY2-W09 / Web × 2 | revoked | (قديمة — لم تتغير) |

### 10.3 جلسات auth قبل/بعد

| الفترة | عدد الجلسات الجديدة | المعدل |
|---|---|---|
| 04:37:24 → 12:14:34 (7.6 ساعة) **قبل** | **17** | 2.2 جلسة/ساعة |
| 15:06:36 → 09:46 اليوم التالي (≈ 18.7 ساعة) **بعد** | **2** (كلاهما الحاسوب لحظة العودة) | 0.1 جلسة/ساعة |

الهاتف: جلسته (12:14:34) استمرت وتجدّدت 2026-10-21 08:44:40؛ الحاسوب (15:07:25) تجدّد 08:44:30.

### 10.4 تحفظات صريحة

1. **عيّنة واحدة (حساب واحد، ≈ 19 ساعة)** — لا تثبت غياب كل الحالات؛ تثبت أن الحالة التي سببت الحلقة (جهاز مفصول + آخر نشط + حد غير ممتلئ) تُحل بلا OTP.
2. **لا أعرف نشاط المستخدم الفعلي** على الجهازين خلال الفترة؛ غياب الأحداث قد يعكس قلة الاستخدام. `last_seen_at` يُظهر نشاطاً صباح اليوم (الهاتف 08:55، الحاسوب 09:25) لكن `last_seen_at` لا يُحدَّث إلا عند نجاح نبضة التسجيل.
3. **نتائج الاختبار الميداني للمالك لم أطّلع عليها** وقت كتابة هذا القسم؛ يُرجى إلحاقها.
4. الدليل لا يغطي: جهازين من نفس الطراز (§6.1)، وجهازاً بوردية مفتوحة (§6.2)، وحالة امتلاء الحد.

---

## 11. حدود الحل والمخاطر المعروفة

### 11.1 تراجع في «فصل جهاز يدوياً»: النافذة 30 ثانية أقصر من دورة النبض 60 ثانية، وRealtime غير فعّال — **أهم بند مفتوح**

**الوقائع [DB + CODE]:**
1. `account_devices` غير منشور في `supabase_realtime` (§2.1) ⇒ الجهاز لا يتلقى حدث فصله.
2. الجهاز يعرف بفصله فقط حين يُرجع `app_register_device` القيمة `revoked` في نبضة المزامنة (كل 60 ثانية، `cloud_sync_service.dart:1715–1721` ⇒ `1535/1548`).
3. بعد الإصلاح، `app_register_device` يُرجع `revoked` فقط لـ **30 ثانية** بعد حدث الفصل (أو عند امتلاء الحد)؛ بعدها، إن وُجد مكان ضمن الحد، يُعيد الجهاز `active`.

**النتيجة المنطقية:** المالك يضغط «فصل» لجهاز (`removeDevice`) والحد غير ممتلئ (الحالة المعتادة). نبضة الجهاز التالية تقع بتوزيع
منتظم تقريباً خلال 0–60 ثانية:
- إن وقعت قبل الثانية 30: يتلقى `revoked` ⇒ يُطرد. ✔
- إن وقعت بعد الثانية 30 (**≈ 50%**): يُعاد `active` بصمت، **ولا يُطرد، ويعود لعمله وكأن شيئاً لم يكن**. ✘
- جهاز مغلق/نائم/في الخلفية وقت الفصل (نبضته بعد دقائق أو ساعات): يعود دائماً بصمت. ✘

**المقارنة بما قبل الإصلاح:** كان الفصل اليدوي «ثابتاً» ما دام جهاز آخر نشطاً (الجهاز المفصول يُرفض دائماً ويُطرد). أي أن الإصلاح
**أزال هذه الخاصية** عندما يوجد مكان في الحد، وهذا الأثر لم أنتبه له قبل النشر لأنني افترضت أن Realtime يبلّغ الجهاز.
أما الأثر في السيناريو المُبلَّغ عنه (الطرد المتبادل المزعج) فهو **إيجابي** — لكن الثمن هو هذا التراجع.

**ما لا يُحل بتغيير الرقم:** رفع النافذة إلى **90 ثانية** (> 60) يضمن أن يتلقى كل جهاز **متصل ونشط** نبضة `revoked` واحدة على الأقل فيُطرد
(يُصلح الحالة الأولى والثانية أعلاه). لكنه **لا يُصلح الجهاز النائم** (يعود عند استيقاظه بعد انتهاء النافذة). الحل الجذري هو
تمييز «فصل مقصود من المالك» عن غيره بعمود `revoked_reason` (§12.3) أو تفعيل Realtime/نشر `account_devices` (§12.1، له محاذيره).

**قرار الإنتاج:** لم أغيّر شيئاً على الإنتاج بعد اكتشاف هذا، لأن طلبك كان التوثيق، ولأن كل خيار علاج قرار منتج (§12).

### 11.2 الفصل اليدوي لم يعد قفلاً دائماً

السيرفر لا يفرّق بين «فصل المالك يدوياً» و«الخروج النهائي» و«dedupe» و«الاستعادة» (كلها `UPDATE ... revoked`، المصدر `direct`).
بعد الإصلاح: جهاز فصله المالك يدوياً **يعود إذا سجّل الدخول (أو نبض) بعد النافذة وكان هناك مكان ضمن الحد**. لحالة «تسجيل دخول
صريح» هذا مقبول (من يسجّل الدخول يملك بيانات الحساب، وكانت العودة ممكنة أصلاً بـ OTP)؛ أما لحالة «نبضة تلقائية من تطبيق مفتوح»
فهو **غير مقبول** (§11.1). السيرفر لا يستطيع التفريق بين الحالتين لأنهما نفس الـ RPC. للتمييز الحقيقي يلزم عمود
`revoked_reason` ونسخة تطبيق تكتبه، أو معامل جديد في الـ RPC يميّز «تسجيل دخول» من «نبضة» (§12.3).

### 11.3 سباق مسار `UPDATE` المباشر (زر «السماح»)

لا advisory lock داخل الـ trigger (§7.3-ب) ⇒ في سباق دقيق قد يتجاوز النشط الحدَّ بواحد. `app_device_limit_status` سيُظهر `is_over_limit`
كما كان الحال في النظام قبل الإصلاح للأجهزة الجديدة. الأثر: محدود وغير تدميري.

### 11.4 الـ dedupe (§6.1) ومعالج الطرد (§6.2)

لم يُلمسا. الأول سيستمر في إنتاج فصل بين أجهزة من نفس الطراز. بعد الإصلاح: الجهاز المفصول يعود عند نبضته (بعد النافذة)، والأول يُعيد
فصله عند أول `refreshDevices()` له ⇒ **قد تستمر دورة فصل/عودة بين الجهازين من نفس الطراز بلا OTP** (تحتاج إلى إصدار تطبيق، §12.2).
والثاني يحتاج اختباراً تشغيلياً.

### 11.5 Realtime غير فعّال لجدول الأجهزة

التعليقات والواجهة تفترض «طرداً فورياً» (`cloud_sync_service.dart:2057` يقول «فصل فوري»)، لكن الواقع على الإنتاج: الطرد عبر نبضة
المزامنة (≤ 60 ثانية وأكثر عند الخلفية). لم أُضف جدول الأحداث إلى المنشور (مقصود: لا بث أحداث تدقيق للعملاء).
**لا تُضف `account_devices` إلى المنشور دون اختبار:** فتح القناة سيجعل كل `UPDATE` (بما فيه الـ dedupe والنبضات التي تغيّر الحالة)
يستدعي `refreshDevices()` عند كل الأجهزة (سطر 2123)، ويُفعّل مسار الطرد الفوري الذي لم يُجرَّب إنتاجياً من قبل.

### 11.6 الحد الافتراضي 2

ما زال قائماً (§6.4). أي فجوة في الرخصة تعيد الحد إلى 2 فوراً. ليس في نطاق هذا الإصلاح.

### 11.7 نمو جدول التدقيق

يُكتب فقط عند تغيّر الحالة (إدراج جهاز، تغيّر الحالة، حذف). النمو ضئيل لكنه بلا سياسة احتفاظ (retention). يُوصى بتنظيف دوري (>180 يوماً).

### 11.8 فقدان التدقيق عند التراجع

ملف التراجع يحذف `account_device_events`. لإبقائه علّق سطر `drop table` في آخره.

### 11.9 تحذير: اختبار الإنتاج يترك فجوة في الـ identity

متوقع وغير ضار.

---

## 12. التوصيات والخطوات التالية

### 12.1 سيرفر — قرار مطلوب (أولوية عالية)

يعالج التراجع الموصوف في §11.1. الخيارات (ليست حصرية):

| الخيار | يُصلح | لا يُصلح | الكلفة/المخاطر |
|---|---|---|---|
| **أ) رفع النافذة 30 → 90 ثانية** (تعديل رقم في `app_register_device`) | الجهاز المتصل النشط يُطرد دائماً (نبضة `revoked` واحدة على الأقل) | الجهاز النائم/الخلفية يعود بصمت عند الاستيقاظ | منخفضة؛ من يخرج نهائياً ويعيد الدخول خلال 90 ثانية يرى شاشة الفصل مرة واحدة. قابلة للتراجع بالكامل |
| **ب) نافذة أطول بكثير (مثلاً ساعات)** | يغطي معظم حالات النوم | يعيد جزءاً من «السجن الدائم» الذي سبب الحادثة (المفصول يُرفض ساعات رغم وجود مكان) | أعلى؛ يُعيد جزءاً من الألم الأصلي |
| **ج) `revoked_reason` + نسخة تطبيق تكتبه** (§12.3) | الحل الجذري: «فصل المالك» ثابت، و«خروج نهائي/dedupe/استعادة» لا يُثبَّت | — | يحتاج إصدار تطبيق + تعديل سيرفر |
| **د) نشر `account_devices` في Realtime** | طرد فوري حقيقي | لا يعالج الجهاز النائم؛ لا يغيّر منطق العودة | يُفعّل مساراً لم يُجرَّب إنتاجياً (§11.5) — اختبار أولاً |

**توصيتي (رأي، لا حقيقة مثبتة):** (أ) الآن كإجراء سريع منخفض المخاطر، ثم (ج) في إصدار التطبيق القادم. لم أنفّذ (أ) لأنه تغيير إنتاج
جديد بقرار منتج لم تطلبه صراحة.

### 12.2 تطبيق — إصدار قادم (أولوية عالية)

1. **حذف/تعطيل `_dedupeActiveDuplicateDevicesOnServer` و`_pruneRevokedHandsetDuplicatesOnServer`** أو استبدالهما بمطابقة بمعرّف الجهاز (`device_id`) لا الاسم.
2. **معالج الطرد:** التقاط `StateError` من `auth.logout()` وتنفيذ فصل محلي قسري (مع تحذير/حفظ للوردية والمزامنة) بدل ترك الجهاز
   شغّالاً بحالة `revoked` (§6.2). **يلزم اختبار تشغيلي أولاً.**
3. **عدم تثبيت `revokeOthers: true`**: واجهة تعرض الأجهزة النشطة عند امتلاء الحد ليختار المالك ما يُفصل بدل الفصل التلقائي.
4. **معالجة `reason`** القادم من `app_register_device` (`recently_revoked` / `device_limit_reached`) برسائل مناسبة بدل شاشة «مفصول» العامة.
5. إزالة/تحديث نص «اطلب السماح بالعودة من جهاز نشط» (`cloud_sync_service.dart:1552`) لأن المسار يعمل الآن لكنه لم يعد ضرورياً عند وجود مكان.

### 12.3 سيرفر — لاحقاً

- عمود `revoked_reason` (`owner_removed | signed_out | system`) يكتبه التطبيق الجديد، وتمييز الفصل اليدوي في `app_register_device`.
- بديل/إضافة: معامل اختياري في `app_register_device` (مثلاً `p_is_login boolean default false`) يرسله التطبيق عند تسجيل دخول صريح
  فقط؛ النبضة التلقائية لا تُعيد جهازاً مفصولاً أبداً، وتسجيل الدخول الصريح يُعيده عند وجود مكان. يحقق «لا طرد متبادل» و«الفصل اليدوي ثابت» معاً.
  النسخ القديمة التي لا ترسل المعامل تُعامَل كنبضات (فتفقد العودة التلقائية عند الدخول — يلزم تحديث التطبيق).
- تنظيف دوري لجدول الأحداث.
- مراقبة (§13.3).

### 12.4 معلومات مطلوبة لإغلاق الحادثة

1. **السبب الأول:** سيُعرف من `account_device_events` عند حدوث أي فصل `direct` جديد ⇒ ربط `actor_session_id` بـ `auth.sessions.user_agent`.
2. نتائج الاختبار الميداني للمالك (جهازان بنفس اسم المستخدم المحلي ووردية مفتوحة على شاشة تبديل الزيت).
3. اختبار حالة هاتفين من نفس الطراز (لقياس أثر الـ dedupe).

---

## 13. دليل التشغيل

### 13.1 النشر

```
# 1) staging/نسخة: شغّل الاختبار بعد تطبيق الـ migration
supabase db query --linked -f migrations/20261020_device_lifecycle_fix.sql
supabase db query --linked -f migrations/20261020_device_lifecycle_fix.test.sql   # يجب أن يطبع TEST_PASSED_AND_ROLLED_BACK
```

### 13.2 التراجع

```
supabase db query --linked -f migrations/20261020_device_lifecycle_fix.rollback.sql
```

يعيد الدوال والـ trigger لنسخ الإنتاج الأصلية، ويحذف trigger/دالة التدقيق وجدولها.

### 13.3 استعلامات تشخيص

آخر أحداث حساب (من فصل من، ومن أي جهاز فيزيائي):

```sql
select e.id, e.created_at, e.device_id, e.old_status, e.new_status, e.source,
       left(e.actor_session_id, 8) as sess, s.user_agent
from public.account_device_events e
left join auth.sessions s on s.id::text = e.actor_session_id
where e.user_id = '<uid>'
order by e.id desc limit 50;
```

كشف حلقة طرد متبادل (أكثر من فصلين خلال ساعة):

```sql
select user_id, count(*) filter (where new_status = 'revoked') as revokes,
       count(*) filter (where source = 'rpc:app_owner_recover_device') as recovers
from public.account_device_events
where created_at > now() - interval '1 hour'
group by user_id
having count(*) filter (where new_status = 'revoked') >= 3
order by revokes desc;
```

أي فصل لا يمرّ عبر RPC (UPDATE مباشر):

```sql
select * from public.account_device_events
where source = 'direct' and new_status = 'revoked'
order by id desc limit 50;
```

حالة الأجهزة والحد لحساب:

```sql
select device_name, platform, access_status, last_seen_at
from public.account_devices where user_id = '<uid>' order by last_seen_at desc;
select * from public.app_device_limit_status();   -- يتطلب هوية JWT للمستخدم
```

التحقق من أن النشر قائم:

```sql
select to_regclass('public.account_device_events'),
       position('recently_revoked'  in pg_get_functiondef('public.app_register_device(text,text,text)'::regprocedure)) > 0,
       position('revoked_others'    in pg_get_functiondef('public.app_owner_recover_device(text,boolean)'::regprocedure)) > 0,
       position('device_limit_reached' in pg_get_functiondef('public.prevent_device_self_unrevoke()'::regprocedure)) > 0;
```

### 13.4 تشغيل الاختبار محلياً بلا Supabase

```
createdb naboo_devtest
psql naboo_devtest -v ON_ERROR_STOP=1 -f tool/device_lifecycle_local_stub.sql
psql naboo_devtest -v ON_ERROR_STOP=1 -f migrations/20261020_device_lifecycle_fix.rollback.sql   # حالة الإنتاج القديمة
psql naboo_devtest -f migrations/20261020_device_lifecycle_fix.sql
psql naboo_devtest -f migrations/20261020_device_lifecycle_fix.test.sql
# المتوقع: ERROR:  TEST_PASSED_AND_ROLLED_BACK: A1 A2 ... RLS
```

---

## 14. جدول «قبل / بعد» الموحّد

| البند | قبل (حتى ≈ 15:05 UTC 2026-10-20) | بعد (منذ النشر) | المصدر |
|---|---|---|---|
| جهاز مفصول، جهاز آخر نشط، الحد 6 | يُرفض (`revoked`) | يعود `active` | [LOCAL B1 / A1] + [DB حدث 23] |
| زر «السماح من جهاز نشط» | يفشل دائماً (`cannot_unrevoke_while_other_devices_active`) | ينجح عند وجود مكان، يُرفض عند الامتلاء | [LOCAL B2 / A2 / test A8] |
| استعادة OTP مع 3 أجهزة أخرى نشطة (حد 6) | تفصل الـ 3 | تفصل 0 | [LOCAL B3 / A3] |
| استعادة OTP والحد ممتلئ | تفصل الكل | تفصل جهازاً واحداً (الأقدم) | [LOCAL test A6] |
| استعادة بـ `p_revoke_other_devices=false` والحد ممتلئ | (لا مفهوم للحد) | `DEVICE_LIMIT_REACHED` | [LOCAL test A7] |
| سجل من فصل من | غير موجود | `account_device_events` (مصدر + جلسة) | [DB] |
| جلسات auth جديدة للحساب | 17 في 7.6 س | 2 في 18.7 س (لحظة عودة الحاسوب) | [DB] |
| أحداث فصل منذ التطبيق | غير معروف (لا سجل) | 0 | [DB] |
| حالة الحاسوب | `revoked` (≈ 2 س 52 د) | `active` (عودة تلقائية 15:06:38) | [DB] |
| حالة الهاتف | `active` | `active` (لم يُمس) | [DB] |
| تأثير النشر على الأجهزة العاملة | — | لا صفوف مُعدَّلة ⇒ لا أحداث Realtime | [DB: 1/6 قبل وبعد] |
| الـ dedupe بالاسم | موجود | **موجود (لم يُعالج)** | [CODE] |
| معالج الطرد مع وردية مفتوحة | احتمال فشل جزئي | **احتمال قائم (لم يُعالج)** | [CODE، غير مختبر] |
| وسيلة إبلاغ الجهاز بفصله | نبضة المزامنة ≤ 60 ث (Realtime غير منشور فلا يعمل) | كما هي | [DB: غياب الجدول من المنشور] + [CODE] |
| **ثبات «فصل جهاز يدوياً»** (حد غير ممتلئ، جهاز آخر نشط) | **ثابت** (المفصول يُرفض ويُطرد دائماً) | **غير ثابت**: ≈ 50% (تقدير) يعود بصمت بعد 30 ث؛ الجهاز النائم يعود دائماً | [CODE + منطق الدالة]؛ لم يُقَس ميدانياً — **تراجع** (§11.1) |

---

## الملحق A — نصوص الدوال القديمة (للمرجع والتراجع)

> المصدر الرسمي للنص القديم: `migrations/20261020_device_lifecycle_fix.rollback.sql` (ملتقط بـ `pg_get_functiondef` في 2026-10-20).

### A.1 `prevent_device_self_unrevoke()` (قديمة)

```sql
CREATE OR REPLACE FUNCTION public.prevent_device_self_unrevoke()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(auth.role(), '') = 'service_role' then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and lower(coalesce(old.access_status, 'active')) = 'revoked'
     and lower(coalesce(new.access_status, 'active')) is distinct from 'revoked' then
    if exists (
      select 1
      from public.account_devices d
      where d.user_id = new.user_id
        and d.device_id is distinct from new.device_id
        and lower(coalesce(d.access_status, 'active')) <> 'revoked'
    ) then
      raise exception 'cannot_unrevoke_while_other_devices_active';
    end if;
  end if;
  return new;
end;
$function$
```

### A.2 `app_owner_recover_device(text, boolean)` (قديمة)

```sql
CREATE OR REPLACE FUNCTION public.app_owner_recover_device(p_device_id text, p_revoke_other_devices boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_now timestamptz := now();
  v_active int;
  v_updated int;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED' using errcode = 'P0001';
  end if;
  if p_device_id is null or length(trim(p_device_id)) = 0 then
    raise exception 'INVALID_DEVICE_ID' using errcode = 'P0001';
  end if;

  if p_revoke_other_devices then
    update public.account_devices
    set access_status = 'revoked'
    where user_id = v_uid
      and device_id <> p_device_id
      and coalesce(access_status, 'active') = 'active';
  end if;

  update public.account_devices
  set access_status = 'active',
      last_seen_at  = v_now
  where user_id = v_uid
    and device_id = p_device_id;

  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    raise exception 'DEVICE_NOT_FOUND: no row for this device_id'
      using errcode = 'P0001';
  end if;

  select count(*)::int into v_active
  from public.account_devices d
  where d.user_id = v_uid
    and coalesce(d.access_status, 'active') = 'active';

  return jsonb_build_object(
    'access_status',  'active',
    'active_devices', v_active,
    'device_id',      p_device_id
  );
end;
$function$
```

### A.3 `app_register_device(text, text, text)` (قديمة)

```sql
CREATE OR REPLACE FUNCTION public.app_register_device(p_device_id text, p_device_name text, p_platform text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare
  v_tenant_id   text;
  v_uid         uuid := auth.uid();
  v_now         timestamptz := now();
  v_max         int;
  v_existing    record;
  v_active      int;
  v_was_known   boolean;
  v_platform    text := lower(trim(coalesce(p_platform, '')));
  v_stale_id    text;
  v_recent_web  int;
begin
  v_tenant_id := public.app_current_tenant_id();
  if v_tenant_id is null or length(trim(v_tenant_id)) = 0 then
    raise exception 'tenant_unauthenticated: refusing app_register_device without authenticated tenant'
      using errcode = 'P0001';
  end if;
  if v_uid is null then
    raise exception 'tenant_unauthenticated: missing auth.uid() under JWT-authenticated session'
      using errcode = 'P0001';
  end if;

  if p_device_id is null or length(trim(p_device_id)) = 0 then
    raise exception 'INVALID_DEVICE_ID: p_device_id must be non-empty'
      using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext('register_device:' || v_tenant_id)::bigint);

  perform 1
  from public.account_devices d
  where d.user_id = v_uid
  for update;

  select d.access_status, d.device_id is not null as known
    into v_existing
  from public.account_devices d
  where d.user_id = v_uid and d.device_id = p_device_id
  limit 1;

  v_was_known := found;

  if v_was_known and lower(coalesce(v_existing.access_status, 'active')) = 'revoked' then
    select count(*)::int into v_active
    from public.account_devices d
    where d.user_id = v_uid
      and coalesce(d.access_status, 'active') = 'active';

    if v_active > 0 then
      return jsonb_build_object(
        'access_status',      'revoked',
        'is_over_limit',      false,
        'active_devices',     v_active,
        'max_devices',        coalesce(public.app_user_max_devices(), 0),
        'already_registered', true
      );
    end if;
  end if;

  v_max := coalesce(public.app_user_max_devices(), 0);

  select count(*)::int into v_active
  from public.account_devices d
  where d.user_id = v_uid
    and coalesce(d.access_status, 'active') = 'active';

  -- جهاز جديد: سياسات الويب قبل حدّ الخطة.
  if not v_was_known then
    if v_platform = 'web' then
      -- استبدال slot ويب خامد (last_seen_at > 7 أيام) بدل استهلاك جهاز جديد.
      select d.device_id
        into v_stale_id
      from public.account_devices d
      where d.user_id = v_uid
        and lower(coalesce(d.platform, '')) = 'web'
        and coalesce(d.access_status, 'active') = 'active'
        and d.last_seen_at < (v_now - interval '7 days')
      order by d.last_seen_at asc nulls first
      limit 1;

      if v_stale_id is not null then
        update public.account_devices
           set device_id = p_device_id,
               device_name = coalesce(nullif(trim(p_device_name), ''), 'متصفح ويب'),
               platform = 'web',
               last_seen_at = v_now,
               access_status = 'active'
         where user_id = v_uid
           and device_id = v_stale_id;

        select count(*)::int into v_active
        from public.account_devices d
        where d.user_id = v_uid
          and coalesce(d.access_status, 'active') = 'active';

        return jsonb_build_object(
          'access_status',      'active',
          'is_over_limit',      case when v_max = 0 then false else (v_active > v_max) end,
          'active_devices',     v_active,
          'max_devices',        v_max,
          'already_registered', true
        );
      end if;

      -- حدّ أجهزة ويب جديدة: 1 لكل 24 ساعة.
      select count(*)::int into v_recent_web
      from public.account_devices d
      where d.user_id = v_uid
        and lower(coalesce(d.platform, '')) = 'web'
        and d.created_at >= (v_now - interval '24 hours');

      if v_recent_web >= 1 then
        raise exception 'WEB_DEVICE_RATE_LIMIT: at most 1 new web device per 24 hours'
          using errcode = 'P0001';
      end if;
    end if;

    if v_max <> 0 and v_active >= v_max then
      raise exception 'DEVICE_LIMIT_REACHED: tenant=% has % active devices (limit=%)',
        v_tenant_id, v_active, v_max
        using errcode = 'P0001';
    end if;
  end if;

  insert into public.account_devices (
    user_id, device_id, device_name, platform, last_seen_at, created_at, access_status
  ) values (
    v_uid,
    p_device_id,
    coalesce(nullif(trim(p_device_name), ''), 'جهاز غير معروف'),
    nullif(trim(p_platform), ''),
    v_now,
    v_now,
    'active'
  )
  on conflict (user_id, device_id)
  do update set
    device_name   = excluded.device_name,
    platform      = excluded.platform,
    last_seen_at  = excluded.last_seen_at,
    access_status = 'active';

  select count(*)::int into v_active
  from public.account_devices d
  where d.user_id = v_uid
    and coalesce(d.access_status, 'active') = 'active';

  return jsonb_build_object(
    'access_status',      'active',
    'is_over_limit',      case when v_max = 0 then false else (v_active > v_max) end,
    'active_devices',     v_active,
    'max_devices',        v_max,
    'already_registered', v_was_known
  );
end;
$function$
```

### A.4 `app_user_max_devices()` و`app_device_limit_status()` (لم تتغير؛ مُلتقطة من الإنتاج بـ `pg_get_functiondef` في 2026-10-21)

```sql
CREATE OR REPLACE FUNCTION public.app_user_max_devices()
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  select
    coalesce(
      (
        select l.max_devices
        from public.licenses l
        where l.assigned_user_id = auth.uid()
          and lower(coalesce(l.status, '')) in ('active', 'trial')
        order by
          case lower(coalesce(l.plan, ''))
            when 'lifetime' then 0
            when 'annual' then 1
            when 'monthly' then 2
            else 9
          end,
          coalesce(l.max_devices, 0) desc,
          case lower(coalesce(l.status, ''))
            when 'active' then 0
            when 'trial' then 1
            else 9
          end,
          l.id desc
        limit 1
      ),
      2
    )::int;
$function$
```

```sql
CREATE OR REPLACE FUNCTION public.app_device_limit_status()
 RETURNS TABLE(is_over_limit boolean, active_devices integer, max_devices integer)
 LANGUAGE sql
 STABLE
AS $function$
  with lim as (
    select public.app_user_max_devices()::int as max_devices
  ),
  dev as (
    select count(*)::int as active_devices
    from public.account_devices d
    where d.user_id = auth.uid()
      and coalesce(d.access_status, 'active') = 'active'
  )
  select
    case
      when lim.max_devices = 0 then false
      when dev.active_devices > lim.max_devices then true
      else false
    end as is_over_limit,
    dev.active_devices,
    lim.max_devices
  from lim, dev;
$function$
```

---

## الملحق B — الدوال الجديدة (المقاطع الكاملة غير المنسوخة أعلاه)

المصدر الرسمي: `migrations/20261020_device_lifecycle_fix.sql`.

### B.1 `prevent_device_self_unrevoke()` (جديدة)

```sql
create or replace function public.prevent_device_self_unrevoke()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_max    int;
  v_active int;
begin
  if coalesce(auth.role(), '') = 'service_role' then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and lower(coalesce(old.access_status, 'active')) = 'revoked'
     and lower(coalesce(new.access_status, 'active')) is distinct from 'revoked' then

    -- SQL المباشر بدون هوية مستخدم (لوحة الإدارة): لا قيد.
    if auth.uid() is null then
      return new;
    end if;

    v_max := coalesce(public.app_user_max_devices(), 0);
    if v_max <> 0 then
      select count(*)::int into v_active
      from public.account_devices d
      where d.user_id = new.user_id
        and d.device_id is distinct from new.device_id
        and lower(coalesce(d.access_status, 'active')) <> 'revoked';

      if v_active >= v_max then
        raise exception 'cannot_unrevoke_device_limit_reached: active=% max=%', v_active, v_max;
      end if;
    end if;
  end if;
  return new;
end;
$function$;
```

### B.2 `log_account_device_change()`

```sql
create or replace function public.log_account_device_change()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_source text := coalesce(nullif(current_setting('app.device_source', true), ''), 'direct');
  v_session text;
begin
  begin
    v_session := nullif(auth.jwt() ->> 'session_id', '');

    if tg_op = 'INSERT' then
      insert into public.account_device_events
        (user_id, device_id, event_type, old_status, new_status,
         source, actor_uid, actor_role, actor_session_id)
      values
        (new.user_id, new.device_id, 'insert', null, new.access_status,
         v_source, auth.uid(), auth.role(), v_session);

    elsif tg_op = 'UPDATE' then
      if old.access_status is distinct from new.access_status then
        insert into public.account_device_events
          (user_id, device_id, event_type, old_status, new_status,
           source, actor_uid, actor_role, actor_session_id)
        values
          (new.user_id, new.device_id, 'status_change', old.access_status, new.access_status,
           v_source, auth.uid(), auth.role(), v_session);
      end if;

    elsif tg_op = 'DELETE' then
      insert into public.account_device_events
        (user_id, device_id, event_type, old_status, new_status,
         source, actor_uid, actor_role, actor_session_id)
      values
        (old.user_id, old.device_id, 'delete', old.access_status, null,
         v_source, auth.uid(), auth.role(), v_session);
    end if;
  exception when others then
    null;
  end;
  return null;
end;
$function$;
```

### B.3 `app_owner_recover_device(text, boolean)` (جديدة — كاملة)

```sql
create or replace function public.app_owner_recover_device(
  p_device_id text,
  p_revoke_other_devices boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'auth'
as $function$
declare
  v_uid       uuid := auth.uid();
  v_tenant_id text;
  v_now       timestamptz := now();
  v_max       int;
  v_others    int;
  v_free      int;
  v_evicted   int := 0;
  v_active    int;
  v_updated   int;
  v_result    jsonb;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED' using errcode = 'P0001';
  end if;
  if p_device_id is null or length(trim(p_device_id)) = 0 then
    raise exception 'INVALID_DEVICE_ID' using errcode = 'P0001';
  end if;

  v_tenant_id := public.app_current_tenant_id();
  if v_tenant_id is null or length(trim(v_tenant_id)) = 0 then
    raise exception 'NOT_AUTHENTICATED' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtext('register_device:' || v_tenant_id)::bigint);

  perform 1
  from public.account_devices d
  where d.user_id = v_uid
  for update;

  perform set_config('app.device_source', 'rpc:app_owner_recover_device', true);

  if not exists (
    select 1 from public.account_devices d
    where d.user_id = v_uid and d.device_id = p_device_id
  ) then
    raise exception 'DEVICE_NOT_FOUND: no row for this device_id'
      using errcode = 'P0001';
  end if;

  v_max := coalesce(public.app_user_max_devices(), 0);

  select count(*)::int into v_others
  from public.account_devices d
  where d.user_id = v_uid
    and d.device_id <> p_device_id
    and coalesce(d.access_status, 'active') = 'active';

  if v_max <> 0 and v_others >= v_max then
    if not coalesce(p_revoke_other_devices, false) then
      raise exception 'DEVICE_LIMIT_REACHED: % active devices (limit=%)', v_others, v_max
        using errcode = 'P0001';
    end if;

    v_free := v_others - (v_max - 1);

    with victims as (
      select d.id
      from public.account_devices d
      where d.user_id = v_uid
        and d.device_id <> p_device_id
        and coalesce(d.access_status, 'active') = 'active'
      order by d.last_seen_at asc nulls first, d.id asc
      limit v_free
    )
    update public.account_devices a
       set access_status = 'revoked'
      from victims v
     where a.id = v.id;

    get diagnostics v_evicted = row_count;
  end if;

  update public.account_devices
     set access_status = 'active',
         last_seen_at  = v_now
   where user_id = v_uid
     and device_id = p_device_id;

  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    raise exception 'DEVICE_NOT_FOUND: no row for this device_id'
      using errcode = 'P0001';
  end if;

  select count(*)::int into v_active
  from public.account_devices d
  where d.user_id = v_uid
    and coalesce(d.access_status, 'active') = 'active';

  v_result := jsonb_build_object(
    'access_status',  'active',
    'active_devices', v_active,
    'device_id',      p_device_id,
    'max_devices',    v_max,
    'revoked_others', v_evicted
  );
  perform set_config('app.device_source', '', true);
  return v_result;
end;
$function$;
```

---

## الملحق C — فهرس الملفات المذكورة

| الملف | ما يخصّه |
|---|---|
| `lib/services/cloud_sync_service.dart` | تسجيل الجهاز، dedupe، الاستعادة، الـ Realtime، دورة المزامنة |
| `lib/main.dart` (146–195) | معالجا الطرد: الجهاز (`onRemoteDeviceRevoked`) و`tenant_access` (`onTenantRevoked`) |
| `lib/providers/auth_provider.dart` | `logout`، `signOutPermanentlyFromDevice`، `recoverDeviceAccessViaEmailOtp` |
| `lib/screens/auth/device_kicked_out_screen.dart` | الشاشة الزرقاء |
| `lib/screens/auth/device_access_revoked_screen.dart` | شاشة الفصل + مسار OTP |
| `lib/screens/auth/employee_pin_gate_screen.dart` | زر الخروج النهائي |
| `lib/screens/settings/account_subscription_screen.dart` | فصل جهاز يدوي |
| `lib/services/license/license_engine_v2.dart` | بصمة الجهاز واسمه |
| `lib/services/license/device_uuid_migrator.dart` | ترحيل `legacy device_id → UUID` |
| `migrations/20261020_device_lifecycle_fix.sql` / `.rollback.sql` / `.test.sql` | الإصلاح والتراجع والاختبار |
| `tool/device_lifecycle_local_stub.sql` | stub الاختبار المحلي |

## الملحق D — علاقة هذه الحادثة بمشكلة فقدان الجلسة (Supabase session refresh) [PRIOR]

في جلسة سابقة (نفس المحادثة) عُولج بشكل منفصل مسار «انتهاء جلسة Supabase ⇒ طلب إعادة تسجيل الدخول» عبر تعديلات على:
`ensureFreshSession` (عدم تحويل الأخطاء العابرة إلى `SessionExpiredException`)، `tryRestoreCloudSessionSilently`
(عدم استدعاء `signOut` عند خطأ عابر)، و`CloudSessionResumeBridge` (إعادة جدولة + مهلة)، مع اختبارات. هذه التعديلات **كود في المستودع
ولم تُنشر في نسخة تطبيق للمستخدمين** (إفادة سابقة في المحادثة؛ لم أُعد فحصها هنا). هي **مستقلة** عن حلقة الأجهزة هنا، لكن العَرَضين
يتشابهان للمستخدم («طلب إعادة تسجيل الدخول»)، لذا عند أي شكوى مستقبلية يجب التفريق: جلسة منتهية (لا حدث في `account_device_events`)
مقابل جهاز مفصول (حدث `revoked` للجهاز).

## الملحق E — سجل التغييرات في هذا العمل

| البند | الحالة |
|---|---|
| إنشاء `migrations/20261020_device_lifecycle_fix.{sql,rollback.sql,test.sql}` | تم |
| إنشاء `tool/device_lifecycle_local_stub.sql` | تم |
| تطبيق الـ migration على الإنتاج | **تم** (2026-10-20 ≈ 15:0x UTC) |
| اختبار ذاتي الإلغاء على الإنتاج | **نجح**، بلا أثر متبقٍّ |
| أي تعديل في `lib/**` | **لا شيء** |
| أي تعديل على صفوف `account_devices` | **لا شيء** |
| نتائج الاختبار الميداني للمالك | **بانتظار نتائجها** |
