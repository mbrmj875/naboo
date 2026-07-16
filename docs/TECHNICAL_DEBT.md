# ديون تقنية — مسودة داخلية

## مزامنة السحابة (`CloudSyncService`)

**سباق الرفع بين جهازين:** حُلّ جزئياً عبر `content_version` + `rpc_push_snapshot` (فرع `feature/snapshot-race-guard-v2`). مسار الكلاينت الوحيد للرفع هو الـ RPC؛ ما زال TODO PHASE 2: إلغاء صلاحية INSERT/UPDATE المباشرة على `app_snapshots` بعد تحديث كل الأجهزة.

**بوابة الترطيب + حارس بيانات العمل (2026-07-16):** يمنع رفع جهاز غير مُرطَّب أو بلا بيانات عمل فوق سحابة غنية. لا يغني عن تاريخ اللقطات عند استعادة يدوية.

### تذاكر اختبارات معروفة (لا تُصلَح في جلسة الحراسة — 2026-07-16)

#### TD-SYNC-001 — فشل watchdog الزمني (flaky)
**الملف:** `test/suites/sync/realtime_sync_test.dart`  
**الاختبار:** `RealtimeWatchdog — channel state machine watchdog tick fires reconnect after 30s of silence`  
**المشكلة:** أحياناً لا يُجدوَل reconnect خلال تقدّم الزمن الاصطناعي (`expected length 1, actual []`).  
**متابعة:** تثبيت الساعة/المؤقت في الاختبار أو زيادة هامش tick؛ غير مرتبط بحُرّاس اللقطة.

#### TD-SYNC-002 — clock_skew في offline_sync يبقى `pending`
**الملف:** `test/suites/sync/offline_sync_test.dart`  
**الاختبار:** `clock_skew_rejected fail moves mutation to failed (not synced)`  
**المشكلة:** بعد رفض `clock_skew_rejected` تبقى الحالة `pending` بدل `failed`.  
**متابعة:** مواءمة سلوك `SyncQueueService` مع اختبارات `lww_clock_skew` / مسار تصحيح الطوابع.

#### TD-SYNC-003 — فشل شكلي في `realtime_kill_switch` (documentary)
**الملف:** `test/security/realtime_kill_switch_test.dart`  
**الاختبار:** `registers label in realtimeWatchdog with reconnect callback`  
**المشكلة:** الاختبار يتوقع tear-off `reconnect: _attachTenantAccessRealtime` بينما المصدر يستخدم closure يستدعي الدالة ثم `markHealthy`.  
**متابعة:** تحديث الـ RegExp الوثائقي ليطابق الشكل الحالي (السلوك صحيح).

## متابعة من تشخيص tag `pre-race-guard-stable` (2026-07-14) — توثيق فقط

### أ. عيّنات JWT منتهية في الاختبارات
**الملفات:** `test/security/license_v2_only_test.dart`, `test/jwt_license_verify_test.dart`  
**المشكلة:** عيّنة JWT موقّعة بـ `naboo-dev-001` تنتهي في `2026-05-31`؛ بعد هذا التاريخ تفشل الاختبارات رغم أن المحرّك يتصرف بشكل صحيح (رفض منتهٍ).  
**متابعة:** تحديث العيّنات بتواريخ مستقبلية بعيدة، أو توليد JWT ديناميكياً وقت الاختبار بمفتاح اختبار.

### ب. مفتاح `naboo-dev-001` في بناءات release — أولوية عالية
**الملف:** `lib/services/license/license_engine_v2.dart` (`trustedPublicKeysPemByKid`)  
**المشكلة:** بناء العميل من الـ tag يقبل أي JWT ساري التوقيع بمفتاح التطوير `naboo-dev-001`.  
**متابعة:** في release قبول مفتاح الإنتاج فقط؛ عزل مفتاح dev عن بناءات المتجر.

### ج. توحيد `tenantId` / `tenant_id` في طلبات الصيانة
**الملف:** `lib/services/service_orders_sql_ops.dart` (`listServiceOrders`)  
**المشكلة:** مسارات SQL تستخدم `tenantId` فقط؛ جداول قديمة بعمود `tenant_id` تُرجع قائمة فارغة (لا تسريب بين مستأجرين).  
**متابعة:** توحيد الاستعلام أو ترحيل موحّد للمخطط.

### د. حماية `debugPrint` في شاشة الفاتورة
**الملف:** `lib/screens/invoices/add_invoice_screen.dart` (ستة استدعاءات غير محمية، مسار ParkedSale تقريباً ~3740–3904)  
**المشكلة:** تفشل فحص `auth_security` الثابت؛ قد تصل رسائل تصحيح للسجلات خارج سياسة `kDebugMode`.  
**متابعة:** لفّ الاستدعاءات بـ `if (kDebugMode)` أو `assert(() { … }())`.
