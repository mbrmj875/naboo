# تقرير التدقيق الأمني والمزامنة — Naboo / Basra Store Manager

> **تاريخ التدقيق الأوّلي**: 2026-05-07
> **تاريخ إقفال الخطة**: 2026-05-08
> **النطاق**: Flutter app + Supabase (sqflite محلي + RPC + Realtime)
> **الهدف**: تحصين شامل للأمان، المزامنة، والتحكم بالاشتراكات.
>
> ✅ **حالة الخطة (الخطوات 1–25): مكتملة بالكامل.**
> ✅ **الإصلاحات اللاحقة (القسم 26): مكتملة في 2026-05-08.**
> 📊 **531 اختبار ناجح (1 متجاهَل: اختبار تكامل RLS بحاجة بيئة Supabase) — 0 مشكلة في `flutter analyze`.**
> 🛡️ **391 اختبار أمني تحت `test/security/` + 100 اختبار إضافي تحت `test/suites/`**.
>
> راجع التقرير التنفيذي النهائي: [`security_completion_report.md`](./security_completion_report.md).
> ملف الخطة الأصلي: `.cursor/plans/security_sync_subscriptions_hardening_*.plan.md`.

---

## 1) عزل المستأجر (Tenant Isolation) — أولوية قصوى

### 1.1 SQLite — استعلامات بدون فلتر `tenantId`

**الأثر**: أي استعلام بدون `WHERE tenantId = ?` يقرأ سجلات كل المستأجرين على الجهاز نفسه. مع وجود تبديل حساب أو مالك بيانات (`auth.active_data_owner` في `auth_provider.dart`)، قد تختلط الفواتير والديون والصناديق بين الحسابات.

| الملف | الأسطر | الدالة | الحالة |
|---|---|---|---|
| [`lib/services/db_debts.dart`](../lib/services/db_debts.dart) | 10–18 | `getAllNonReturnedCreditInvoices` | بدون tenantId |
| [`lib/services/db_debts.dart`](../lib/services/db_debts.dart) | 37–47 | `getOpenCreditDebtInvoices` | بدون tenantId |
| [`lib/services/db_debts.dart`](../lib/services/db_debts.dart) | 68–78 | `getCreditDebtInvoicesForCustomerId` | بدون tenantId |
| [`lib/services/db_debts.dart`](../lib/services/db_debts.dart) | 96–106 | `sumOpenCreditDebtForCustomer` | بدون tenantId |
| [`lib/services/db_debts.dart`](../lib/services/db_debts.dart) | 117–128 | `sumOpenCreditDebtForUnlinkedCustomerName` | بدون tenantId |
| [`lib/services/db_debts.dart`](../lib/services/db_debts.dart) | 250–261 | `getCustomerDebtLineItems` (JOIN) | بدون tenantId |
| [`lib/services/db_debts.dart`](../lib/services/db_debts.dart) | 362–370 | `recordCustomerDebtPayment` (UPDATE) | بدون tenantId — **خطير: تحديث مالي بلا عزل** |
| [`lib/services/db_cash.dart`](../lib/services/db_cash.dart) | 91–96 | `getCashLedgerInRange` | بدون tenantId |
| [`lib/services/db_cash.dart`](../lib/services/db_cash.dart) | 106–111 | استعلام `invoices WHERE id IN (...)` | بدون tenantId |
| [`lib/services/db_cash.dart`](../lib/services/db_cash.dart) | 118–126 | SUM `cash_ledger` | بدون tenantId |
| [`lib/services/db_shifts.dart`](../lib/services/db_shifts.dart) | 95–100 | `getOpenWorkShift` | بدون tenantId |
| [`lib/services/db_shifts.dart`](../lib/services/db_shifts.dart) | 260–268 | عدّ فواتير الوردية | بدون tenantId |
| [`lib/services/db_shifts.dart`](../lib/services/db_shifts.dart) | 315–324 | `work_shifts` بنطاق زمني | بدون tenantId |
| [`lib/services/db_shifts.dart`](../lib/services/db_shifts.dart) | 353–357 | `invoices GROUP BY workShiftId` | بدون tenantId |
| [`lib/services/db_suppliers.dart`](../lib/services/db_suppliers.dart) | 89–102 | ملخص الموردين | بدون tenantId |
| [`lib/services/db_suppliers.dart`](../lib/services/db_suppliers.dart) | 156–170 | pagination — تستخدم OFFSET أيضاً | بدون tenantId |
| [`lib/services/db_suppliers.dart`](../lib/services/db_suppliers.dart) | 192–197 | `getSupplierById` | بدون tenantId |
| [`lib/services/db_suppliers.dart`](../lib/services/db_suppliers.dart) | 413–424 | `supplier_bills WHERE supplierId = ?` | بدون tenantId |
| [`lib/services/db_suppliers.dart`](../lib/services/db_suppliers.dart) | 449–454 | `supplier_payouts WHERE supplierId = ?` | بدون tenantId |
| [`lib/services/reports_repository.dart`](../lib/services/reports_repository.dart) | 340–347 | `expenses` | **`tenantId = 1` ثابت hardcoded** |
| [`lib/services/reports_repository.dart`](../lib/services/reports_repository.dart) | 353–414 | عدة تقارير على `invoices` | بدون tenantId |
| [`lib/services/reports_repository.dart`](../lib/services/reports_repository.dart) | 608–615 | `customers WHERE balance > ?` | بدون tenantId |

### 1.2 Supabase — `tenantId` يأتي من العميل

**الأثر**: ثقة الكود السيرفري (داخل `SECURITY DEFINER`) بقيمة `tenantId` مرسَلة من الكلاينت يفتح باب IDOR.

- [`supabase_sync_queue_rpc.sql`](../supabase_sync_queue_rpc.sql) أسطر 158–280: دالة `rpc_process_sync_queue(mutations_json)` تأخذ `(mutation->>'tenantId')::int` في عدة مواضع (مثلاً لقراءة `expense_categories`).
- [`supabase_sync_expenses_rpc.sql`](../supabase_sync_expenses_rpc.sql): نفس النمط (نسخة سابقة).
- [`lib/services/security_audit_log_service.dart`](../lib/services/security_audit_log_service.dart) أسطر 33–44, 81–85, 151–153: `tenant_id` في الـ payload يأتي من الكلاينت (حتى لو حالياً = `user.id`).

### 1.3 RLS غير مكتمل

- في [`supabase_sync_queue_rpc.sql`](../supabase_sync_queue_rpc.sql) تعليق `TODO(security)` صريح أن RLS غير مفعّل لجداول مالية لو تم الوصول المباشر من العميل.
- جدول `sync_notifications`: لديه `SELECT` مقيّد بـ `auth.uid() = user_id` فقط؛ لا توجد سياسة `INSERT` ظاهرة (الكتابة تحدث داخل `SECURITY DEFINER`).
- `app_snapshots`, `account_devices`, `profiles`: مضبوطة في [`supabase_sync_setup.sql`](../supabase_sync_setup.sql).

---

## 2) Soft Delete على الجداول المالية

**الواقع**: لا يوجد أي استخدام لـ `deleted_at IS NULL` في `lib/**/*.dart` (تأكّد بحث ripgrep). بعض الجداول لا تحتوي حتى عمود `deleted_at`.

**الأثر**: حذف نهائي من DB المحلي يكسر التدقيق المالي ويُفقد القدرة على استعادة الفواتير الملغاة. كما أن أي مزامنة Last-Write-Wins تخسر سجلاً صحيحاً عندما يصل تحديث "deleted" متأخر.

**القرار من الخطة (الخطوة 10)**: إضافة `deleted_at TEXT` لكل من: `invoices, invoice_items, cash_ledger, expenses, payments, work_shifts`. تحويل كل `db.delete(...)` إلى `db.update({'deleted_at': now}, ...)`. تطبيق فلتر `AND deleted_at IS NULL` في كل قراءة.

---

## 3) الأسرار والمفاتيح

| الموضع | المفتاح/القيمة | الإجراء المطلوب |
|---|---|---|
| [`lib/services/supabase_config.dart`](../lib/services/supabase_config.dart) أسطر 2–8 | Supabase URL + anon JWT — hardcoded | الانتقال إلى `String.fromEnvironment('SUPABASE_URL')` و`SUPABASE_ANON_KEY` (`--dart-define`) |
| [`lib/firebase_options.dart`](../lib/firebase_options.dart) أسطر 43–77 | عدة `apiKey: 'AIza...'` + `measurementId` | يُولّد من flutterfire — قابل للقبول لكنه مكشوف للقراءة العامة |
| [`android/app/google-services.json`](../android/app/google-services.json) أسطر 16–18 | Firebase current_key | يبقى (مطلوب) — لا يُعتبر سرّاً سيرفرياً |
| [`ios/Runner/GoogleService-Info.plist`](../ios/Runner/GoogleService-Info.plist) | `GOOGLE_APP_ID`, `GCM_SENDER_ID` | يبقى |
| [`macos/Runner/GoogleService-Info.plist`](../macos/Runner/GoogleService-Info.plist) | نفس الشيء | يبقى |

**حالة `flutter_secure_storage`**: غير مستخدمة قبل الخطوة 3. **تم تطبيقها في الخطوة 2/3** عبر [`lib/services/auth/secure_session_storage.dart`](../lib/services/auth/secure_session_storage.dart) لتخزين توكن جلسة Supabase. (راجع `test/security/secure_session_storage_test.dart`.)

---

## 4) اللوج والبيانات الحساسة

- لا يوجد `print(` في `lib/**/*.dart` (40 `debugPrint(` فقط، موزّعة على ~18 ملف).
- لا توجد طباعة مباشرة لكلمات مثل `password|token|jwt|otp|license_key` ضمن سطور `debugPrint`.
- مواضع تحت المجهر:
  - [`lib/services/sync_queue_service.dart`](../lib/services/sync_queue_service.dart) أسطر 151, 177: تطبع `error.toString()` الذي قد يضمّن نص payload أو رسالة Postgrest فيها بيانات.
  - [`lib/services/database_helper.dart`](../lib/services/database_helper.dart) سطر 79: يطبع مسار DB (حساس على سطح المكتب).
- لا يوجد `AppLogger` مركزي. الخطوة 12 ستضيفه مع redaction للقيم المعروفة.

---

## 5) المزامنة (Cloud Sync)

### 5.1 `RealtimeCloseEvent 1006` بدون backoff/heartbeat على مستوى التطبيق

- [`lib/services/cloud_sync_service.dart`](../lib/services/cloud_sync_service.dart) أسطر 825–1102: ثلاث قنوات (`sync-snapshots`, `sync-notifications`, `device-access`). الاعتماد على إعادة الاشتراك الداخلية لـ `supabase_flutter` فقط.
- لا يوجد `Timer.periodic` خاص بالمراقبة.
- لا استخدام لـ `connectivity_plus` (سيُضاف في الخطوة 16).

### 5.2 Idempotency

- موجود لرفع snapshot: مفتاح ثابت في `SharedPreferences` (`sync.pending_idempotency_key.<userId>`) ويُمحى بعد النجاح. (سطور 1237–1305).
- غير موجود للطفرات (`sync_queue`).

### 5.3 الطابور المحلي

- جدول `sync_queue` مع `mutation_id` UUID + `retry_count` + backoff أُسّي (30 \* 2^retryCount حتى 300s).
- **مشكلة جوهرية**: الـ RPC `rpc_process_sync_queue` يُستدعى كـ batch واحد. فشل سجل واحد = فشل الكل.
  - [`lib/services/sync_queue_service.dart`](../lib/services/sync_queue_service.dart) أسطر 139–193.

### 5.4 Conflict Resolution

- LWW موحّد عبر `_incomingWins()` في `cloud_sync_service.dart` أسطر 2125–2143، و`ON CONFLICT ... DO UPDATE ... WHERE updated_at < EXCLUDED.updated_at` في `supabase_sync_queue_rpc.sql`.
- لا rejection لطفرات `updated_at` المستقبلية → يفتح باب التلاعب بالساعة.

### 5.5 لا audit log مالي

- يوجد `sync_notifications` للإشعار بالدلتا — لا يحتوي before/after.
- ملف `admin-web/supabase/security_audit_logs.sql` غير مستخدم من طبقة المزامنة.

---

## 6) الترخيص (License v1 + v2)

### 6.1 v1 — مشاكل معروفة

- [`lib/services/license_service.dart`](../lib/services/license_service.dart) أسطر 1101–1106 و1140–1143: تستخدم `DateTime.now()` المحلي ⇒ التلاعب بالساعة ممكن.
- نفس الملف 1141–1143: العميل يكتب `licenses.status='expired'` مباشرة على Supabase.
- نفس الملف 1049–1066: تحديث `registered_devices` كـ JSON كامل من العميل ⇒ race condition / lost update مع تسجيل متزامن من جهازين.

**القرار**: إلغاء v1 بالكامل في الخطوة 1 من الخطة.

### 6.2 v2 — التحقق محلي

- [`lib/services/license/license_engine_v2.dart`](../lib/services/license/license_engine_v2.dart): RS256 + kid (`naboo-dev-001`) موضوع داخل ثابت `_devPublicKeyPem`.
- [`lib/services/license/trusted_time_service.dart`](../lib/services/license/trusted_time_service.dart): يتحقق من قفز الساعة للخلف > 10 دقائق ويحوّل إلى `restricted` أو `pendingLock`.
- لا يوجد revocation check سيرفري للتوكن — أي JWT صالح زمنياً يُقبل (سيُعالج بربط v2 بـ `tenant_access` في الخطوات 20–22).

### 6.3 Kill Switch (موجود لجهاز، غير موجود لعميل/tenant)

- [`lib/services/cloud_sync_service.dart`](../lib/services/cloud_sync_service.dart) أسطر 1056–1102: `_attachDeviceAccessRealtime` يستمع لـ `account_devices.access_status='revoked'` ويستدعي `onRemoteDeviceRevoked` (logout + شاشة `DeviceKickedOutScreen`).
- لا يوجد ما يكافئه لإيقاف المستأجر بأكمله.

**القرار**: جدول جديد `tenant_access` (Step 20) بأعمدة `kill_switch boolean` + `valid_until timestamptz NOT NULL`، مع Realtime (Step 22) و overlay على `LicenseEngineV2` (Step 21). راجع [`migrations/supabase_tenant_access_manual.sql`](../migrations/supabase_tenant_access_manual.sql).

---

## 7) حماية الشاشات الحساسة

- لا يوجد `FLAG_SECURE` ولا استخدام لـ `flutter_windowmanager` في الكود الحالي (تأكّد بحث).
- شاشات حسّاسة معرضة للقطة شاشة/تسجيل: الترخيص، OTP، تقارير الرواتب، شاشة المفاتيح، إعدادات الحساب.

**القرار**: الخطوة 13 ستضيف `flutter_windowmanager` للأندرويد وتفعّل `FLAG_SECURE` في `initState` للشاشات الحسّاسة.

---

## 8) جودة الكود

| الجانب | الحالة |
|---|---|
| `analysis_options.yaml` | يستورد `flutter_lints` فقط، يعطّل `deprecated_member_use*`، لا يفعّل `prefer_const_constructors`/`avoid_print`/`unawaited_futures`/`require_trailing_commas`. |
| اختبارات | موجودة لـ JWT/TrustedTime/UUIDMigrator/SyncCodec/IraqiCurrencyFormat/Loyalty/Invoice. تمت إضافة Phase 0/1 (`tenant_scope`, `tenant_entitlement`, `secure_session_storage`). لا توجد بعد لـ `validateInvoiceBalance` ولا لـ tenant_isolation على DAOs. |
| `home_screen.dart` | ~4424 سطر — مؤجّل بناءً على الخطة. |
| `print(` في `lib/**/*.dart` | 0 |
| `debugPrint(` في `lib/**/*.dart` | 40 (~18 ملف) |

---

## 9) الإنجاز ضمن الخطة (الحالة النهائية — 2026-05-08)

| المرحلة | الحالة |
|---|---|
| Phase 0.A — `test/helpers/in_memory_db.dart` | ✅ مكتمل |
| Phase 0.A — `test/helpers/fake_supabase.dart` | ✅ مكتمل |
| Phase 0.B — هذا التقرير | ✅ مكتمل |
| Step 1 — إلغاء `LicenseService v1` بالكامل | ✅ مكتمل |
| Step 2 — `--dart-define` للأسرار + `SupabaseConfig.assertConfigured()` | ✅ مكتمل |
| Step 3 — `flutter_secure_storage` لجلسة Supabase | ✅ مكتمل |
| Step 4 — `TenantContext.requireActiveTenantId()` | ✅ مكتمل |
| Step 5 — `db_debts.dart` tenant isolation | ✅ مكتمل |
| Step 6 — `db_cash.dart` tenant isolation | ✅ مكتمل |
| Step 7 — `db_shifts.dart` tenant isolation | ✅ مكتمل |
| Step 8 — `db_suppliers.dart` tenant isolation | ✅ مكتمل |
| Step 9 — `reports_repository.dart` (إصلاح `tenantId = 1`) | ✅ مكتمل |
| Step 10 — Soft Delete (`deleted_at`) للجداول المالية | ✅ مكتمل |
| Step 11 — RLS سيرفري + `app_current_tenant_id()` | ✅ مكتمل |
| Step 12 — `AppLogger` + redaction للحقول الحسّاسة | ✅ مكتمل |
| Step 13 — `FLAG_SECURE` على الشاشات الحسّاسة | ✅ مكتمل |
| Step 14 — `validateInvoiceBalance` قبل أيّ حفظ | ✅ مكتمل |
| Step 15 — `RealtimeWatchdog` مع backoff/heartbeat | ✅ مكتمل |
| Step 16 — `connectivity_plus` + استئناف المزامنة | ✅ مكتمل |
| Step 17 — RPC نتائج per-mutation (`rpc_process_sync_queue`) | ✅ مكتمل |
| Step 18 — `financial_audit_log` (server-side audit) | ✅ مكتمل |
| Step 19 — LWW clock-skew guard (+5min reject) | ✅ مكتمل |
| Step 20 — جدول `tenant_access` (kill_switch + valid_until) | ✅ مكتمل |
| Step 21 — overlay على `LicenseService` من `tenant_access` | ✅ مكتمل |
| Step 22 — Realtime Kill Switch (`onTenantRevoked`) | ✅ مكتمل |
| Step 23 — atomic `app_register_device` RPC (FOR UPDATE + advisory lock) | ✅ مكتمل |
| Step 24 — تشديد `analysis_options.yaml` (5 قواعد إضافية، 0 issues) | ✅ مكتمل |
| Step 25 — Regression نهائي + توثيق | ✅ مكتمل |

---

## 10) ملفّات الترحيل (Supabase migrations)

كلّ الترحيلات تحت `migrations/` يدويّة على Supabase Studio. كلّها idempotent مع
كتل `DO $$ ... $$` للتحقق من المتطلبات و rollback مُوثَّق في نهاية كلّ ملف.

| الملف | الخطوة | المحتوى |
|---|---|---|
| [`migrations/20260507_rls_tenant.sql`](../migrations/20260507_rls_tenant.sql) | 11 | تفعيل RLS + `app_current_tenant_id()` + سياسات لكلّ جدول. |
| [`migrations/20260508_rpc_per_mutation.sql`](../migrations/20260508_rpc_per_mutation.sql) | 17 | RPC تُرجع نتائج per-mutation `jsonb` مع تطابق `tenant_id` من JWT. |
| [`migrations/20260509_financial_audit_log.sql`](../migrations/20260509_financial_audit_log.sql) | 18 | جدول `financial_audit_log` + tracebacks لكلّ INSERT/UPDATE/DELETE مالي. |
| [`migrations/20260510_lww_clock_skew.sql`](../migrations/20260510_lww_clock_skew.sql) | 19 | `_reject_clock_skew()` يرفض أيّ mutation `updated_at > now() + 5 min`. |
| [`migrations/20260511_tenant_access.sql`](../migrations/20260511_tenant_access.sql) | 20 | جدول `tenant_access` (kill_switch, valid_until, grace_until) + RLS read-only للعميل + `app_tenant_access_status()`. |
| [`migrations/20260512_register_device_rpc.sql`](../migrations/20260512_register_device_rpc.sql) | 23 | `app_register_device` ذرّي بـ `pg_advisory_xact_lock` + `FOR UPDATE` + idempotency. |
| [`migrations/supabase_tenant_access_manual.sql`](../migrations/supabase_tenant_access_manual.sql) | — | snippet إداري لإعادة تشغيل/تعطيل tenants من الـ Dashboard. |

> **ملاحظة عملية**: بعد تشغيل `20260511_tenant_access.sql` يجب **تفعيل Realtime يدوياً** على
> `public.tenant_access` من Supabase Dashboard → Database → Replication. هذه خطوة
> غير قابلة للأتمتة عبر SQL ضمن المشروع الحالي.

---

## 11) ملخّص الاختبارات (Coverage Snapshot — 2026-05-08)

### إحصاء عام

- **إجمالي الاختبارات**: 428 ناجح، 1 متجاهَل (skipped)، 0 فاشل.
- **اختبارات أمنية مخصّصة**: 391 تحت `test/security/` (26 ملف اختبار).
- **`flutter analyze lib test`**: `No issues found!`
- **`flutter test --coverage`**: `coverage/lcov.info` (7066 سطر).

### اختبارات `test/security/` — 26 ملف

```
analysis_options_test.dart            license_v2_only_test.dart
app_logger_test.dart                  lww_clock_skew_test.dart
connectivity_sync_test.dart           realtime_kill_switch_test.dart
db_cash_tenant_isolation_test.dart    realtime_watchdog_test.dart
db_debts_tenant_isolation_test.dart   register_device_rpc_test.dart
db_shifts_tenant_isolation_test.dart  reports_tenant_isolation_test.dart
db_suppliers_tenant_isolation_test.dart  rls_policy_test.dart
financial_audit_test.dart             secure_screens_test.dart
invoice_validation_test.dart          secure_session_storage_test.dart
license_v2_kill_switch_test.dart      soft_delete_test.dart
                                      supabase_config_test.dart
                                      sync_queue_per_mutation_test.dart
                                      tenant_access_rls_test.dart
                                      tenant_context_test.dart
                                      tenant_entitlement_test.dart
                                      tenant_scope_validation_test.dart
```

### Coverage على الوحدات الأمنية الحساسة

| الملف | السطور المُغطّاة |
|---|---|
| [`lib/services/tenant_context.dart`](../lib/services/tenant_context.dart) | **100%** (21/21) |
| [`lib/services/tenant_entitlement.dart`](../lib/services/tenant_entitlement.dart) | **100%** (2/2) |
| [`lib/utils/app_logger.dart`](../lib/utils/app_logger.dart) | **98%** (42/43) |
| [`lib/utils/invoice_validation.dart`](../lib/utils/invoice_validation.dart) | **85%** (58/68) |
| [`lib/services/sync_queue_service.dart`](../lib/services/sync_queue_service.dart) | **65%** (82/126) |
| [`lib/services/license_service.dart`](../lib/services/license_service.dart) | 26% (91/348)¹ |

> ¹ الـ 74% غير المُغطّاة في `license_service.dart` كلّها مسارات عرض/تنسيق
> (`devicesLabel`, `devicesInfo`, `_describePlan(...)` إلخ) مرتبطة بالـ UI ولا
> تحمل قراراً أمنياً. القرارات الأمنية (`computeKillSwitchDecision`,
> `_maybeApplyTenantAccessOverlay`, `JWT verify`, التحقق من المدّة) كلّها
> مُغطّاة عبر اختبارات Step 21 و 22.

---

## 12) قائمة التحسينات الأمنية المُطبَّقة

### عزل المستأجر (Tenant Isolation)
- إضافة `WHERE tenant_id = ?` على كلّ استعلام sqflite في DAOs (`db_debts`, `db_cash`, `db_shifts`, `db_suppliers`, `reports_repository`).
- إزالة `tenantId = 1` المُحوسَب يدوياً في `reports_repository.dart`.
- `TenantContext.requireActiveTenantId()` يرفع exception فوراً لو لم يكن tenant ثابتاً.

### IDOR (Insecure Direct Object References)
- RLS مفعَّلة على جميع الجداول الحسّاسة (Supabase) عبر `migrations/20260507_rls_tenant.sql`.
- `app_current_tenant_id()` تأخذ tenant **من الـ JWT فقط** (لا تُستلَم من العميل).
- RPCs (`rpc_process_sync_queue`, `app_register_device`, `app_tenant_access_status`) كلّها `SECURITY DEFINER` مع `search_path` مغلق.

### الأسرار والمفاتيح
- نقل `SUPABASE_URL` + `SUPABASE_ANON_KEY` إلى `--dart-define` (راجع `supabase_config.dart`).
- `SupabaseConfig.assertConfigured()` يرفع exception فوراً عند الإقلاع لو لم يُمرَّر المفتاحان.

### تخزين آمن
- `SecureLocalStorage` على `flutter_secure_storage` (Keychain / EncryptedSharedPreferences / DPAPI) — يستبدل تخزين الجلسة في `SharedPreferences`.

### حماية الشاشات
- `flutter_windowmanager_plus` (fork مُصان) + `FLAG_SECURE` على شاشات الترخيص، OTP، الرواتب، التقارير الحسّاسة.

### Soft Delete
- إضافة `deleted_at TEXT` لـ `invoices, invoice_items, cash_ledger, expenses, payments, work_shifts`.
- استبدال كلّ `db.delete(...)` بـ `db.update({'deleted_at': now}, ...)` + فلتر `AND deleted_at IS NULL` في القراءة.

### المزامنة (Sync)
- `RealtimeWatchdog` يُراقب الاتصال + heartbeat + إعادة الاشتراك بـ exponential backoff.
- `connectivity_plus` يستأنف المزامنة عند عودة الإنترنت (`ConnectivityResumeSync`).
- RPC `rpc_process_sync_queue` تُرجع نتائج **per-mutation** (تنجح بعض الـ mutations ولا تفشل الكلّ).
- LWW clock-skew guard يرفض أيّ mutation `updated_at > now() + 5 min`.

### Audit Trail
- جدول `financial_audit_log` على Supabase + triggers تلقائية لكلّ INSERT/UPDATE/DELETE على `invoices, payments, expenses, cash_ledger, work_shifts`.

### Subscription Control (Kill Switch)
- جدول `tenant_access` مع `kill_switch boolean` + `valid_until timestamptz` + `grace_until` + `access_status` (active/suspended/revoked/grace).
- `app_tenant_access_status()` يستهلكه العميل عبر RPC مع caching محلي.
- Realtime listener على `tenant_access` ⇒ على أي UPDATE نُجبر `LicenseService.checkLicense(forceRemote: true)` ⇒ لو الحالة `suspended` يُستدعى `onTenantRevoked` ⇒ logout + شاشة قفل.
- تكامل مع `RealtimeWatchdog` للقناة الجديدة.

### Atomic Device Registration
- `app_register_device` ذرّي عبر `pg_advisory_xact_lock` (يمنع race على INSERT) + `FOR UPDATE` (يمنع race مع admin يقوم بـ revoke).
- `tenant_unauthenticated` guard من JWT.
- idempotent عبر `INSERT ... ON CONFLICT (user_id, device_id) DO UPDATE`.

### Validation
- `validateInvoiceBalance(invoice)` يُستدعى قبل أيّ حفظ ⇒ يرفض أرقام كسريّة، تجاوز للحدود، أو مبالغ سالبة.

### Logging
- `AppLogger` مركزي مع redaction تلقائي لـ `password`, `token`, `jwt`, `otp`, `license_key`, `secret`, `apikey`, `auth`, `email`, `phone`.
- استبدال كلّ `print(`/`debugPrint(` بحقول حسّاسة بـ `AppLogger`.
- `avoid_print: error` في `analysis_options.yaml` يمنع رجوع `print()`.

### Code Quality
- `analysis_options.yaml` صارم: `prefer_const_constructors`, `unawaited_futures`, `require_trailing_commas`, `avoid_dynamic_calls` كلّها مفعّلة.
- 0 issues على `flutter analyze lib test`.
- 152 إصلاح آلي + 36 إصلاح يدوي ⇒ 0 lint warnings.

---

## 26) الإصلاحات اللاحقة (Post-Audit Hardening) — 2026-05-08

**الأثر**: تقوية المنفذَين الأخيرَين بعد إقفال الخطة الأصلية — حقن `NaN/Infinity` في طبقة الإدخال، و تسرّب لوغ بدون تنقية في الإصدار. هذان العنصران كانا مفلتَين من الفحوص الـ 25 الأصلية وكُشفا أثناء كتابة 100 اختبار إضافي تحت `test/suites/`.

### 26.1) `safeParseDouble` يرفض `NaN/±Infinity`

| الموقع | السلوك السابق | السلوك الجديد |
|---|---|---|
| [`lib/utils/invoice_validation.dart::safeParseDouble`](../lib/utils/invoice_validation.dart) | `double.tryParse('NaN')` تُعيد `double.nan` — يَتسلَّل إلى `Invoice.total` فيُسمِّم كل حساب لاحق. كذلك `double.tryParse('Infinity')` تُعيد `double.infinity`. | يُعاد `fallback` (افتراضياً `0.0`) عند `result.isNaN \|\| result.isInfinite` — الطبقة الأولى من الدفاع تُغلَق قبل وصول البيانات إلى نموذج `Invoice`. |

**الدفاع متعدد الطبقات**: `validateInvoiceBalance` يفحص `inv.total.isNaN` كحاجز ثاني (defense-in-depth)، فالإصلاح هنا يقوّي طبقة الإدخال قبل أن تصل القيمة الفاسدة إلى مستوى النموذج.

**التغطية الاختبارية**: [`test/suites/security/input_security_test.dart`](../test/suites/security/input_security_test.dart) — ثلاث حالات (`'NaN'`, `'Infinity'`, `'-Infinity'` تعيد جميعها `0.0`).

### 26.2) `debugPrint` خارج `app_logger` يُلغى من 10 مواقع

تحويل 10 `debugPrint` مكشوفة إلى `AppLogger.error(tag, msg, e, st)` مع redaction تلقائي للـ JWT/password/license_key/anon_key/OTP. الفائدة: حتى لو نسي مطوّر الـ `if (kDebugMode)` ودخلت سرّية في رسالة الخطأ، الـ AppLogger يُنقّيها قبل الـ console.

| الملف | عدد المواقع | tag |
|---|---|---|
| [`lib/services/db_products_sync.dart`](../lib/services/db_products_sync.dart) | 2 | `DBSync` |
| [`lib/services/db_financial_sync.dart`](../lib/services/db_financial_sync.dart) | 2 | `DBSync` |
| [`lib/services/system_notification_service.dart`](../lib/services/system_notification_service.dart) | 2 | `Notify` |
| [`lib/providers/notification_provider.dart`](../lib/providers/notification_provider.dart) | 1 | `Notify` |
| [`lib/screens/invoices/add_invoice_screen.dart`](../lib/screens/invoices/add_invoice_screen.dart) | 1 | `Invoice` |
| [`lib/screens/inventory/add_product_screen.dart`](../lib/screens/inventory/add_product_screen.dart) | 1 | `Product` |
| [`lib/screens/home_screen.dart`](../lib/screens/home_screen.dart) | 1 | `HomeSearch` |

كل المواقع وُسِّع `catch (e)` فيها إلى `catch (e, st)` ليصل الـ stack trace إلى `AppLogger.error`. الرسائل العربية موحَّدة بصيغة «فشل …».

موقع 11 في [`lib/screens/debts/customer_debt_detail_screen.dart:215`](../lib/screens/debts/customer_debt_detail_screen.dart) كان داخل `assert(() { ... }())` — مُحاطاً بضمان لغويّ يُسقِط الكتلة كاملة في الإصدار. تمّ تحديث الـ static scan في [`test/suites/security/auth_security_test.dart`](../test/suites/security/auth_security_test.dart) ليتعرّف على هذا النمط، فلم يَعُد يُبلَّغ عنه كـ false positive.

### التحقّق

- `flutter test test/suites/security/` → **40 passed, 0 skipped**.
- `flutter test` → **531 passed, 1 skipped** (الـ skipped هو اختبار تكامل RLS بحاجة `SUPABASE_URL` + `SUPABASE_ANON_KEY` — مقصود).
- `flutter analyze` → `No issues found!`.

### الفحوصات الدفاعية الإضافية (نتائج صفر مطابقة)

| الفحص | النتيجة |
|---|---|
| `double.parse(` المباشر في `lib/**` | صفر مطابقة — كل التحويلات تمرّ عبر `safeParseDouble`. |
| `print(` (في بداية السطر) في `lib/**` | صفر مطابقة — `avoid_print: error` فعّال. |
| `debugPrint(` خارج `app_logger.dart` و خارج `assert(())` و خارج `if (kDebugMode)` | صفر مطابقة — يُتحقَّق منه بـ static scan في `auth_security_test.dart`. |

---

## ملحق — مرجع الاختبارات الجديدة (المحدّث)

| الملف | الخطوة | الغرض |
|---|---|---|
| [`test/helpers/in_memory_db.dart`](../test/helpers/in_memory_db.dart) | 0.A | DB ذاكرية بـ schema مالي مختصر + `FinancialFixtures`. |
| [`test/helpers/fake_supabase.dart`](../test/helpers/fake_supabase.dart) | 0.A | `FakeRealtimeHub` لمحاكاة قنوات Realtime بلا شبكة. |
| [`test/security/tenant_scope_validation_test.dart`](../test/security/tenant_scope_validation_test.dart) | 4 | `ensureTenantScopeForQueries`. |
| [`test/security/tenant_context_test.dart`](../test/security/tenant_context_test.dart) | 4 | `requireActiveTenantId`. |
| [`test/security/secure_session_storage_test.dart`](../test/security/secure_session_storage_test.dart) | 3 | `SecureLocalStorage` لجلسة Supabase. |
| [`test/security/license_v2_only_test.dart`](../test/security/license_v2_only_test.dart) | 1 | إثبات إزالة v1. |
| [`test/security/supabase_config_test.dart`](../test/security/supabase_config_test.dart) | 2 | `--dart-define` guards. |
| [`test/security/db_debts_tenant_isolation_test.dart`](../test/security/db_debts_tenant_isolation_test.dart) | 5 | عزل tenant على `db_debts`. |
| [`test/security/db_cash_tenant_isolation_test.dart`](../test/security/db_cash_tenant_isolation_test.dart) | 6 | عزل tenant على `db_cash`. |
| [`test/security/db_shifts_tenant_isolation_test.dart`](../test/security/db_shifts_tenant_isolation_test.dart) | 7 | عزل tenant على `db_shifts`. |
| [`test/security/db_suppliers_tenant_isolation_test.dart`](../test/security/db_suppliers_tenant_isolation_test.dart) | 8 | عزل tenant على `db_suppliers`. |
| [`test/security/reports_tenant_isolation_test.dart`](../test/security/reports_tenant_isolation_test.dart) | 9 | عزل tenant على `reports_repository` + إثبات إزالة `tenantId=1`. |
| [`test/security/soft_delete_test.dart`](../test/security/soft_delete_test.dart) | 10 | `deleted_at` + قراءات تتجاهل المحذوف. |
| [`test/security/rls_policy_test.dart`](../test/security/rls_policy_test.dart) | 11 | تغطية documentary للـ migration. |
| [`test/security/app_logger_test.dart`](../test/security/app_logger_test.dart) | 12 | redaction للحقول الحساسة. |
| [`test/security/secure_screens_test.dart`](../test/security/secure_screens_test.dart) | 13 | `FLAG_SECURE` على الشاشات الحسّاسة. |
| [`test/security/invoice_validation_test.dart`](../test/security/invoice_validation_test.dart) | 14 | `validateInvoiceBalance`. |
| [`test/security/realtime_watchdog_test.dart`](../test/security/realtime_watchdog_test.dart) | 15 | backoff/heartbeat/reconnect. |
| [`test/security/connectivity_sync_test.dart`](../test/security/connectivity_sync_test.dart) | 16 | استئناف المزامنة. |
| [`test/security/sync_queue_per_mutation_test.dart`](../test/security/sync_queue_per_mutation_test.dart) | 17 | results per-mutation. |
| [`test/security/financial_audit_test.dart`](../test/security/financial_audit_test.dart) | 18 | audit trail. |
| [`test/security/lww_clock_skew_test.dart`](../test/security/lww_clock_skew_test.dart) | 19 | clock-skew guard. |
| [`test/security/tenant_access_rls_test.dart`](../test/security/tenant_access_rls_test.dart) | 20 | `tenant_access` schema + RLS read-only. |
| [`test/security/license_v2_kill_switch_test.dart`](../test/security/license_v2_kill_switch_test.dart) | 21 | overlay matrix. |
| [`test/security/realtime_kill_switch_test.dart`](../test/security/realtime_kill_switch_test.dart) | 22 | `onTenantRevoked` end-to-end. |
| [`test/security/register_device_rpc_test.dart`](../test/security/register_device_rpc_test.dart) | 23 | atomic register_device. |
| [`test/security/analysis_options_test.dart`](../test/security/analysis_options_test.dart) | 24 | الحراسة على القواعد. |
| [`test/security/tenant_entitlement_test.dart`](../test/security/tenant_entitlement_test.dart) | — | سياسة `kill_switch + valid_until`. |
| [`test/suites/security/`](../test/suites/security/) | 26 | 40 اختبار: عزل tenant على DAO حقيقي + IDOR، أمان الإدخال (SQLi/NaN/Infinity/JWT)، أمان المصادقة (SecureStorage/redact/debugPrint scan). |
| [`test/suites/sync/`](../test/suites/sync/) | — | 27 اختبار: `SyncQueueService` offline/online، `RealtimeWatchdog` backoff/kill-switch، سلامة بيانات الفاتورة عبر دورة المزامنة. |
| [`test/suites/performance/`](../test/suites/performance/) | — | 10 اختبار قياس فعلي: insert 1000 / query / SUM 500 / JOIN / soft-delete 100 / search 500 / sync 100 mutations / parse 1000 / watchdog tick. |
| [`test/suites/widget/`](../test/suites/widget/) | — | 13 اختبار UI: `InvoiceForm` (validate/total reactive/save) و `LoginForm` (email format/loading/navigation). |
| [`test/suites/api/`](../test/suites/api/) | — | 10 اختبار عقد JSON: `rpc_process_sync_queue` و `app_tenant_access_status` (شكل، أنواع، enum، ISO timestamps). |
