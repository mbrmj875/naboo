# ديون تقنية — مسودة داخلية

## مزامنة السحابة (`CloudSyncService`)

**سباق الرفع بين جهازين:** عُالج في المرحلة 1 على الفرع `feature/snapshot-race-guard-v2` عبر `content_version` + `rpc_push_snapshot` (حي) ورفع كلاينت ذرّي مع حلقة تعارض. ما زال دمج الكميات المتزامنة (مرحلة 2) مفتوحاً.

**مرجع الهجرة:** `migrations/2026-07-14_snapshot_race_guard.sql` — مطبّقة على مشروع Supabase الحي؛ الكلاينت يستخدم RPC بدل upsert مباشر.

## متابعة من تشخيص tag `pre-race-guard-stable` (2026-07-14) — توثيق فقط، لا إصلاح في هذا الفرع بعد

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

## بناء Android — Icon tree shaking / `const_finder` (2026-07-16)

**الظهور:** `flutter build apk --release` على macOS فشل بـ  
`IconTreeShakerException: ConstFinder failure: Could not find a command named ".../const_finder.dart.snapshot"`.

**التفاف مؤقت (داخلي فقط):** `--no-tree-shake-icons` — مقبول لـ APK فحص داخلي على `feature/snapshot-race-guard-v2`؛ **ممنوع** كافتراضي لبناء عميل/متجر لأنه يكبّر حجم APK.

**متابعة قبل أي بناء عميل:**
1. إصلاح السبب الجذري في SDK/الأدوات إن كان `const_finder.dart.snapshot` ناقصاً (`flutter precache` / إعادة تثبيت Flutter cache).
2. إن استمر الفشل بعد سلامة الـ cache: ابحث عن `IconData` غير `const` (أو أيقونات ديناميكية) تمنع tree-shake.
3. أعد بناء release **بدون** `--no-tree-shake-icons` وتحقق من انخفاض حجم APK قبل التسليم.
