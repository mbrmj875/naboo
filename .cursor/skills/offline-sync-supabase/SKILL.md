---
name: offline-sync-supabase
description: Offline-first sync rules for the Naboo / Basra Store Manager Flutter + Supabase project. Governs the existing snapshot-based CloudSyncService (lib/services/cloud_sync_service.dart), device registration (account_devices), Supabase Realtime for cross-device updates, tenant isolation during sync, connectivity handling, and safe merge policies. Use when touching lib/services/cloud_sync_service.dart, lib/services/db_*.dart, any sync/offline/push/pull/snapshot code, Supabase tables (app_snapshots, app_snapshot_chunks, account_devices, profiles), Realtime subscriptions, or when the user asks about المزامنة، offline، snapshot، تعارض، Supabase، Realtime، أجهزة، فقدان بيانات، دمج، أو conflict.
globs: lib/services/cloud_sync_service.dart, lib/services/db_*.dart, lib/services/database_helper.dart, lib/services/auth_service.dart
alwaysApply: false
---

# Offline-First + مزامنة Supabase (Snapshot-based)

## ملخّص في سطر واحد

المشروع يستخدم **نظام لقطات كاملة (snapshots)** — ليس row-level delta sync. لا تقترح تغيير النمط.

## البنية الفعلية (ليست نظرية)

```
المستخدم → SQLite (lib/services/db_*.dart)
         ↓
CloudSyncService (lib/services/cloud_sync_service.dart)
         ↓
Supabase:
  • app_snapshots        ← لقطة كاملة للقاعدة (JSON مضغوط)
  • app_snapshot_chunks  ← أجزاء اللقطة الكبيرة
  • account_devices      ← إدارة الأجهزة (active/revoked)
  • profiles             ← بيانات حساب المستخدم
```

- `cloud_sync_service.dart` هو **المصدر الوحيد** لأي مزامنة سحابية. لا تبتكر خدمة مزامنة موازية.
- المزامنة ليست row-level: لا يوجد `sync_status`, `server_id`, `local_updated_at`, `deleted_at` في جداول المشروع. **لا تضفها** إلا لو طلب المستخدم صراحةً هجرة معمارية كاملة.
- SQLite هو **مصدر الحقيقة** للعمل اليومي. المستخدم لا ينتظر Supabase ليشاهد بياناته.

## القواعد الصارمة (ممنوعات)

- ❌ **لا تحذف سجلات محلياً قبل نجاح المزامنة**. لو طلب المستخدم حذف، علّم السجل بـ soft-delete حسب نمط المشروع الموجود.
- ❌ **لا تُرسل `tenant_id`/`user_id` من الكلاينت كبيانات**. Supabase RLS تأخذ الهوية من الـ JWT. راجع `security-supabase-flutter`.
- ❌ **لا تستخدم `DateTime.now()` لحل التعارضات**. استخدم حقول الخادم (`server_updated_at` / `updated_at` من Postgres) كمرجع.
- ❌ **لا تُدخل الأموال كـ double** عند بناء اللقطة أو استيرادها. الفلس integer. راجع `erp-logic-performance`.
- ❌ **لا تزامن جدولاً مرتبطاً دون أبنائه** (مثلاً فاتورة بدون أصنافها). اللقطة الكاملة تحمي من هذا بطبيعتها — حافظ على هذه الخاصية.
- ❌ **لا تستبدل snapshot-based بـ row-level delta sync** دون موافقة صريحة ومكتوبة من المستخدم. هذه هجرة تمس كل جداول القاعدة.
- ❌ **لا تُطلق `syncNow` بدون `_runSyncExclusive`**. المزامنات المتزامنة تكسر البيانات.
- ❌ **لا تنسى فلترة `tenant_id` / `user_id` في كل استعلام SQLite**.

## ما يجب فعله

### عند إضافة جدول محلي جديد يدخل في المزامنة

1. أضف الجدول في `database_helper.dart` مع: `tenant_id` (أو `user_id` حسب النمط الموجود)، `updated_at` (integer millis).
2. أضفه في دوال `_exportSnapshot` و `_mergeTableRows` داخل `cloud_sync_service.dart` — بنفس نمط الجداول الموجودة.
3. ارفع `_snapshotSchemaVersion` بمقدار 1 في `cloud_sync_service.dart` لو غيّرت شكل اللقطة.
4. تحقّق من الفهارس: `tenant_id`, `updated_at`, أي FK.

### عند تعديل منطق الدمج (merge)

- سياسة الدمج الحالية: **الأحدث يفوز** (`updated_at` الأكبر). لا تُبدّلها إلى "server wins مطلق" إلا بطلب صريح.
- كل تعديل على `_mergeTableRows` يجب أن يُختبر على سيناريو: جهاز A offline يعدّل → جهاز B online يعدّل نفس السجل → A يتصل.
- لو احتجت تسجيل تعارضات للمراجعة، أضف جدولاً محلياً `conflict_log` فقط، لا تغيّر سياسة الدمج الأساسية.

### عند التعامل مع Realtime

- القناة الموجودة: `_snapshotChannel` على جدول `app_snapshots`. لا تُنشئ قنوات مكرّرة.
- استخدم `_realtimePullDebounce` الموجود — لا تسحب على كل حدث فوراً.
- عند تسجيل الخروج: نظّف القنوات في `stopForSignOut` (الدالة موجودة).

### عند التعامل مع الاتصال/الوضع Offline

- لا تُظهر للمستخدم "فشلت المزامنة" كرسالة مخيفة. استخدم `lastError` notifier الموجود.
- العمليات الحرجة (بيع، دفع) يجب أن تكتمل في SQLite أولاً ثم `scheduleSyncSoon()` في الخلفية — لا تنتظر الشبكة.
- استخدم `connectivity_plus` إن احتجت تأكيد حالة الشبكة، لكن **لا تمنع** العمليات بناء عليها.

### عند التعامل مع إدارة الأجهزة

- التحقّق من `access_status == 'revoked'` إجباري قبل بدء المزامنة — منطق موجود في `registerCurrentDevice`.
- حدود الأجهزة حسب الخطة تُفرض في `enforcePlanDeviceLimit`. لا تتجاوزها.

## Supabase RLS — إلزامي (ملخص)

كل جدول في Supabase يجب أن يحتوي سياسة tenant isolation تأخذ المعرّف من `auth.uid()` أو `auth.jwt()`. التفاصيل الكاملة في skill `security-supabase-flutter`. لا تكرّرها هنا.

## حقول إلزامية في كل جدول Supabase مرتبط بالمزامنة

```sql
user_id uuid NOT NULL REFERENCES auth.users(id),
updated_at timestamptz NOT NULL DEFAULT now(),
created_at timestamptz NOT NULL DEFAULT now()
-- + index على (user_id, updated_at)
-- + RLS policy: USING (user_id = auth.uid())
```

## قائمة تحقّق قبل تسليم أي تعديل على المزامنة

- [ ] لم أُضف أعمدة `sync_status` / `server_id` / `local_updated_at` إلى جداول SQLite.
- [ ] لم أستبدل آلية snapshot بـ row-level sync.
- [ ] استعلامات SQLite كلها مفلترة بـ `tenant_id` / `user_id`.
- [ ] المبالغ integer بالفلس في LocalDB و Remote.
- [ ] `_runSyncExclusive` يغلّف أي دالة تكتب على الخادم.
- [ ] Realtime channels تُنظّف في `stopForSignOut`.
- [ ] لا أستخدم `DateTime.now()` كمرجع لحل التعارض.
- [ ] لا أحذف محلياً قبل تأكيد الرفع.
- [ ] RLS على أي جدول Supabase جديد قبل أول push.
- [ ] جدول جديد: أُضيف في `_exportSnapshot` + `_mergeTableRows` + `_snapshotSchemaVersion++`.

## إحالات (لا تكرّر هذه القواعد هنا)

- الأمان، RLS، tenant isolation، flutter_secure_storage → **security-supabase-flutter**
- الفلس، soft delete، الفهارس، pagination، isolate للعمليات الثقيلة → **erp-logic-performance**
- RTL، Tajawal، responsive، Provider → **flutter-responsive-rtl**

## لو طلب المستخدم "نظام مزامنة جديد row-level"

لا تنفّذ مباشرة. اطلب منه:
1. تأكيد أنه يقصد هجرة كاملة (ليس تحسين صغير).
2. قائمة المشاكل الفعلية في النظام الحالي التي تستدعي الهجرة.
3. موافقة على: تعديل كل جداول SQLite، إعادة كتابة `cloud_sync_service.dart`، إعادة هيكلة Supabase، كتابة RLS جديدة، migration path للبيانات الموجودة.

إذا لم يُجب بوضوح على الثلاثة، افترض أنه يريد تحسيناً داخل النظام الحالي، لا استبداله.
