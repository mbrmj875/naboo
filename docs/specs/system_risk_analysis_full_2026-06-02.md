# التحليل الشامل لمخاطر بنية التطبيق وخارطة الحل

تاريخ الوثيقة: 2026-06-02  
النطاق: تحليل هيكلي وتشغيلي وأمني ومحاسبي لتطبيق Basra Store Manager  
الهدف: توثيق كل المشاكل التي نوقشت من بداية الجلسة حتى الآن، مع التحقق من صحتها من الكود، وتقديم حلول واضحة قابلة للتنفيذ على مراحل.

---

## 1) ملخص تنفيذي

هذا التقرير يجمع بين:

- المشاكل التي تم طرحها في المناقشة.
- التحقق الفعلي من الكود في الملفات الحساسة.
- مخاطر إضافية تم اكتشافها أثناء الفحص.
- خطة علاج تدريجية تمنع فقدان الأموال والبيانات.

أهم نتيجة: توجد مخاطر عالية التأثير فعلًا، خصوصًا في:

1. فقدان البيانات عند تبديل الحساب/الخروج مع وجود طابور مزامنة غير مرفوع.
2. دمج البيانات المالية بسياسة "الأحدث يفوز" (LWW) وما يسببه من ضياع مبالغ.
3. بقاء منطق مالي يعتمد على `double` في أجزاء واسعة.
4. تداخل صلاحيات المستخدم مع صاحب الوردية.
5. احتمالية تضارب بيانات المخزون (Inventory Concurrency) وابتلاع الأخطاء الصامت (Silent Error Catching).

---

## 2) منهجية التحقق

تمت مراجعة مباشرة (قراءة فعلية) للملفات التالية:

- `lib/providers/auth_provider.dart`
- `lib/services/database_helper.dart`
- `lib/services/sync_queue_service.dart`
- `lib/services/cloud_sync_service.dart`
- `lib/services/db_debts.dart`
- `lib/services/db_installments.dart`
- `lib/services/permission_service.dart`
- `lib/providers/shift_provider.dart`
- `lib/screens/printing/printing_screen.dart`
- `lib/utils/sale_receipt_pdf.dart`

واعتماد التصنيف التالي:

- **مؤكد**: موجود صراحة في الكود الحالي.
- **مؤكد جزئيًا**: المشكلة موجودة لكن تم إدخال تحسين جزئي.
- **غير دقيق حاليًا**: كان صحيحًا سابقًا أو متوقعًا، لكن الكود الحالي يعالج جزءًا جوهريًا منه.

---

## 3) نتائج التحقق من النقاط المطروحة

## 3.1 نظام الدخول/الخروج وعزل البيانات

### 3.1.1 مسح البيانات عند تبديل الحساب
**الحالة: مؤكد (Critical).**

عند تبديل نطاق الحساب، يتم تنفيذ:

- `closeAndDeleteDatabaseFile()` للحساب السحابي.
- `wipeBusinessDataKeepUsers()` للحساب المحلي.

الخطر: إذا كان هناك `sync_queue` فيه عمليات مالية لم تُرفع بعد، قد تُفقد نهائيًا.

**الحل المقترح:**

- منع المسح إن كان `sync_queue` يحتوي `pending/failed`.
- فرض شاشة قرار واضحة قبل الخروج/التبديل.
- خياران فقط:  
  1) مزامنة الآن ثم خروج،  
  2) خروج إجباري مع تصدير/نسخ احتياطي صريح.

---

### 3.1.2 الجلسة الهجينة (Local + Cloud)
**الحالة: مؤكد جزئيًا (High).**

الكود يسمح باستمرار الدخول المحلي حتى لو فشل تفعيل جلسة Supabase.  
هذا يقلل انقطاع المستخدم، لكنه يخلق "تصورًا مضللًا" أن الجهاز متصل سحابيًا دائمًا.

**الحل المقترح:**

- مؤشر حالة مزامنة صريح في الواجهة:  
  - متصل سحابيًا  
  - محلي فقط  
  - مزامنة متوقفة
- منع العمليات الحساسة عند "محلي فقط" إن كانت تتطلب توافق فوري متعدد الأجهزة.

---

## 3.2 الصلاحيات والورديات

### 3.2.1 Override الصلاحيات من الوردية
**الحالة: مؤكد (Critical).**

منطق `resolveEffectivePermissionSubject` يرجّح صاحب الوردية المفتوحة عند تقييم الصلاحيات.

الخطر:

- تسجيل عمليات مستخدم A على عهدة مستخدم B.
- منح/حجب صلاحيات بشكل غير متوقع.
- اضطراب جرد الصندوق والمساءلة.

**الحل المقترح:**

- فصل "هوية منفذ العملية" عن "هوية صاحب الوردية" في كل عملية مالية.
- توقيع كل حركة بحقلين إلزاميين:
  - `actor_user_id` (من نفذ)
  - `shift_owner_user_id` (صاحب الوردية)
- في التحقق من الصلاحيات: الأساس هو `actor_user_id`، وليس صاحب الوردية.

---

### 3.2.2 عدم فرض إغلاق الوردية عند الخروج
**الحالة: مؤكد (High).**

`logout()` لا يغلق الوردية ولا يمنع الخروج مع وردية مفتوحة.

**الحل المقترح:**

- Hard gate عند الخروج:
  - إذا توجد وردية مفتوحة: يظهر مسار إغلاق إلزامي.
- استثناء فقط للمالك بصلاحية كسر طارئ مع سبب إجباري + Audit.

---

## 3.3 المزامنة السحابية

### 3.3.1 دمج "الأحدث يفوز" في البيانات المالية
**الحالة: مؤكد (Critical).**

سياسة الدمج في `cloud_sync_service` تعتمد مبدأ الأحدث (`updatedAt`) يفوز.

الخطر:

- عمليات إضافية مالية مستقلة قد تُمحى عند التضارب.
- ضياع تسويات أو دفعات إذا جاءت بتوقيتات متقاربة من أجهزة مختلفة.

**الحل المقترح:**

- منع LWW على الكيانات المالية.
- اعتماد نموذج `Delta + Idempotency`:
  - كل حركة مالية event مستقل.
  - تطبيق تراكمي.
  - idempotency key يمنع التكرار.

---

### 3.3.2 dead mutations دون مركز عمليات
**الحالة: مؤكد (High).**

بعد 5 فشل، الصف يصبح `dead` في `sync_queue`.  
لا توجد حاليًا لوحة تشغيل واضحة للإدارة لمراقبة واستعادة هذه الحالات.

**الحل المقترح:**

- شاشة تشغيلية "المزامنة العالقة":
  - pending / failed / dead
  - آخر خطأ
  - Retry / Retry All / Export errors
- تنبيه إداري مرئي عند وجود أي `dead`.

---

### 3.3.3 خطر الذاكرة في snapshot
**الحالة: مؤكد جزئيًا (Medium/High).**

يوجد تحسن (chunking + gzip) للنقل، لكن بناء اللقطة ما زال يقرأ الصفوف في الذاكرة (`db.query(table)`).

**الحل المقترح:**

- تصدير streaming/page-based بدل تحميل كل الصفوف دفعة واحدة.
- حدود قصوى آمنة لكل batch.
- قياس memory watermark في الأجهزة المتوسطة والمنخفضة.

---

## 3.4 الديون والسجل المحاسبي

### 3.4.1 تعديل الفاتورة الأصلية عند التسديد
**الحالة: مؤكد جزئيًا (Critical محاسبيًا).**

ما زال السداد يخصم عبر تعديل `advancePayment` في فواتير الأصل (FIFO).  
تحسن موجود: تمت إضافة سجل دفع وإيصال تحصيل + Audit.

**المشكلة المتبقية:**

- الفاتورة الأصلية ليست immutable بالكامل.

**الحل المقترح:**

- تجميد الفاتورة بعد الإصدار (Immutable invoice header totals).
- كل سداد يكون عبر سند قبض مستقل فقط.
- الرصيد يُحسب من دفتر حركات (ledger entries) لا من تعديل وثيقة الأصل.

---

### 3.4.2 الربط بالاسم عند غياب customerId
**الحالة: مؤكد (High).**

عند غياب `customerId` يتم التطابق على `LOWER(TRIM(customerName))`.

الخطر:

- انقسام حسابات العميل بسبب اختلافات إملائية بسيطة.
- أخطاء جوهرية في الرصيد.

**الحل المقترح:**

- منع أي حركة آجلة بدون `customerId` إلزامي.
- ترحيل البيانات القديمة بخطة merge آمنة.
- شاشة معالجة حالات "زبون غير مربوط".

---

## 3.5 الأقساط والمرتجعات

### 3.5.1 ازدواج/انحراف بيانات خطة التقسيط
**الحالة: مؤكد جزئيًا (High).**

توجد حقول مالية في أكثر من موضع (فاتورة + plan).  
يوجد تعديل بعد المرتجع، لكنه لا يضمن دائمًا إعادة تشكيل الجدولة بطريقة محاسبية صارمة في كل السيناريوهات.

**الحل المقترح:**

- Source of truth واحد لخطة الأقساط.
- وظيفة إعادة جدولة رسمية بعد المرتجع:
  - recalculation للمبالغ
  - تحديث due dates
  - validation شامل قبل الحفظ
- تسجيل سبب التعديل في audit.

---

## 3.6 الطباعة

### 3.6.1 الاعتماد على PDF للطباعة الحرارية
**الحالة: مؤكد (Medium/High تشغيلي).**

المسار الحالي PDF-centric حتى مع اختيار 58/80mm.

**النتيجة:**

- مشاكل محتملة في القص والمحاذاة وسرعة الاستجابة حسب نوع الطابعة.

**الحل المقترح:**

- إضافة محرك ESC/POS مباشر للطابعات الحرارية.
- الإبقاء على PDF كخيار بديل (Fallback) فقط.

---

### 3.6.2 "عدم وجود طباعة جدول الأقساط"
**الحالة: غير دقيق حاليًا.**

الكود الحالي يحتوي بالفعل على طباعة جدول الأقساط وإيصال سداد القسط.

**المطلوب فقط:**

- مراجعة الصيغة القانونية/التشغيلية للنموذج.
- ضمان سهولة الوصول لها من شاشات التحصيل والدين.

---

## 4) مخاطر إضافية مكتشفة أثناء الفحص

## 4.1 نموذج الأموال باستخدام `double`
**الخطورة: Critical.**

وجود `double` في نطاقات مالية متعددة يهدد الدقة التراكمية.

**الحل:**

- توحيد التخزين والحساب إلى `int fils` في كل مسار مالي.
- التحويل إلى `double` يكون للعرض فقط.

---

## 4.2 عزل tenant غير موحد نمطيًا
**الخطورة: High.**

توجد أنماط CRUD تعتمد فقط `id = ?` في ملفات متعددة.  
قد تكون آمنة في سياقات معينة، لكنها نمط خطِر إذا استخدم دون حارس tenant إلزامي.

**الحل:**

- قاعدة صريحة: كل query/update/delete مالي = `tenantId = ?` إلزامي.
- بناء wrappers إجبارية للوصول للبيانات.
- اختبارات آلية تمنع أي استعلام يخالف القاعدة.

---

## 4.3 ضعف الرؤية التشغيلية للمزامنة
**الخطورة: High.**

لا توجد لوحة تشغيل موحدة تعطي المدير "صحة المزامنة" بنظرة واحدة.

**الحل:**

- Sync Health Dashboard داخل التطبيق:
  - queue depth
  - dead count
  - age of oldest pending
  - last successful sync

---

## 4.4 خطر اتساع payload في النمو
**الخطورة: Medium/High.**

مع نمو الجداول، snapshot الكامل (حتى مع chunking) يظل عبئًا.

**الحل:**

- تقسيم أكبر للكيانات.
- أولويات مزامنة حسب الأهمية.
- استراتيجية incremental snapshots بدل full rebuild المتكرر.

---

## 4.5 تضارب بيانات المخزون (Inventory Concurrency)
**الخطورة: Critical.**

عند العمل دون إنترنت على أكثر من جهاز، قد يسجّل أكثر من كاشير بيعًا لنفس الصنف في وقت متقارب.  
أي دمج يعتمد الاستبدال أو "الأحدث يفوز" قد يُنقص الخصم الفعلي من المخزون ويُنتج عجزًا لاحقًا في الجرد.

**الحل:**

- فصل حركات المخزون إلى أحداث delta مستقلة (quantity change events).
- منع تحديث الرصيد النهائي مباشرة عند الدمج بين الأجهزة.
- اعتماد idempotency لكل حركة مخزنية لمنع التكرار.
- إضافة reconciliation report يومي يطابق: مبيعات - مرتجعات - حركات مخزن.

---

## 4.6 ابتلاع الأخطاء الصامت (`catch (_)`)
**الخطورة: High.**

وجود كتل `catch (_) {}` في مسارات حساسة (خروج، ربط جلسة سحابية، مزامنة) يخفي سبب الفشل الحقيقي ويصعّب التشخيص لاحقًا.

**الحل:**

- استبدال `catch (_) {}` في المسارات الحرجة بـ:
  - log منظّم عبر `AppLogger`.
  - تصنيف نوع الخطأ (شبكة/صلاحية/بيانات/غير متوقع).
  - رسالة تشغيلية مناسبة عند الحاجة.
- منع أي ابتلاع صامت في وحدات `auth`, `sync`, `financial`.

---

## 5) سجل مخاطر مختصر (Risk Register)

| ID | الخطر | التأثير | الاحتمال | الأولوية |
|---|---|---|---|---|
| R1 | حذف قاعدة مع pending sync | كارثي (فقدان مال/بيانات) | مرتفع | Critical |
| R2 | LWW في الماليات | عالٍ (فقدان تسويات) | مرتفع | Critical |
| R3 | Money as double | عالٍ (انحراف أرصدة) | مرتفع | Critical |
| R4 | Shift permission override | عالٍ (اختلاط عهد) | مرتفع | Critical |
| R5 | لا hard close للوردية | عالٍ | مرتفع | High |
| R6 | name-based debt linking | عالٍ | مرتفع | High |
| R7 | dead mutations بلا UI | عالٍ | متوسط/مرتفع | High |
| R8 | snapshot memory pressure | متوسط/عالٍ | متوسط | High |
| R9 | ابتلاع الأخطاء `catch (_)` | عالٍ (صعوبة التتبع) | مرتفع | High |
| R10 | PDF thermal only | متوسط | متوسط | Medium |

---

## 6) خارطة الطريق التنفيذية المقترحة

## المرحلة 0: القياس والرصد (سريعة)

- إضافة مؤشرات صحة المزامنة (pending/failed/dead).
- تسجيل structured audit لأحداث الماليات الحساسة.
- شاشة حالة اتصال واضحة (Cloud vs Local-only).
- معالجة ابتلاع الأخطاء بإضافة تسجيل صريح للأخطاء لمعرفة سبب فشل المزامنة.

**الهدف:** منع العمى التشغيلي قبل الإصلاحات العميقة.

---

## المرحلة 1: حماية البيانات والمزامنة

- حارس logout/account-switch عند وجود pending sync.
- شاشة إدارة `sync_queue` (Retry/Retry All/Diagnostics).
- تعطيل LWW للكيانات المالية والتحول إلى Delta تدريجيًا.

**الهدف:** إيقاف أي فقدان بيانات/أموال جديد.

---

## المرحلة 2: إعادة ضبط المحاسبة (Ledger)

- منع تعديل الفاتورة الأصلية بعد الإصدار.
- سندات قبض/صرف ككيان أساسي.
- التحويل من `double` إلى `int` (fils) في العمليات المحاسبية.
- إلزام `customerId` في كل عمليات الدين/الآجل.

**الهدف:** صحة محاسبية قوية وقابلة للتدقيق.

---

## المرحلة 3: الورديات والصلاحيات

- فصل actor عن shift owner.
- فرض إغلاق الوردية قبل الخروج (مع استثناء موثق للمالك فقط).
- فحوصات تعارض الجلسة/الوردية.

**الهدف:** منع تشوهات العهد والمسؤولية.

---

## المرحلة 4: الطباعة التشغيلية

- إدخال ESC/POS للطابعات الحرارية.
- قوالب قانونية نهائية للمستندات (خاصة التقسيط).
- إبقاء PDF كنسخة احتياطية.

**الهدف:** استقرار تشغيل ميداني أعلى.

---

## 7) معايير القبول (Definition of Done)

لا يعتبر الإصلاح مكتملًا إلا عند تحقق ما يلي:

- لا يمكن تسجيل خروج/تبديل حساب مع `sync_queue` غير مرفوع دون معالجة صريحة.
- لا توجد كيانات مالية تعتمد LWW replacement.
- كل الماليات تعتمد `int fils` داخليًا.
- لا يمكن إنشاء دين جديد دون `customerId`.
- الفاتورة الأصلية لا تتغير بعد الإصدار.
- يوجد مركز عمليات للمزامنة مع معالجة `dead`.
- الصلاحيات تعتمد المستخدم المنفذ، مع عزل واضح عن صاحب الوردية.
- لا توجد مسارات حرجة تحتوي `catch (_) {}` بدون تسجيل.
- لا توجد تسويات مخزون متعددة الأجهزة تعتمد LWW replacement.
- الطباعة الحرارية تعمل فعليًا عبر ESC/POS في سيناريوهات البيع الأساسية.

---

## 8) ملاحظات ختامية

- التحليل الأصلي كان دقيقًا جدًا في معظم النقاط الحرجة.
- هناك تحسينات جزئية موجودة بالفعل في الكود (خصوصًا سندات تحصيل مرافقة وطباعة الأقساط).
- لكن ما زالت المخاطر البنيوية الأساسية قائمة وتستحق معالجة مرحلية منظمة.

هذا الملف مصمم ليكون مرجع قرار هندسي قبل بدء أي تنفيذ برمجي.

---

## 9) تحديث التقدم التنفيذي (2026-06-02)

هذا القسم يوثّق ما تم تنفيذه فعليًا في نفس جلسة العمل، لتقليل الفجوة بين الخطة والتنفيذ.

### 9.1 تم تنفيذه في حماية المزامنة والخروج (R1 / R7)

- إضافة دوال تشغيلية في `sync_queue_service`:
  - `getQueueStats()`
  - `hasBlockingMutations()`
  - `retryAllFailedAndDead()`
- إضافة شاشة متابعة وتشخيص للمزامنة:
  - `lib/screens/settings/sync_queue_health_screen.dart`
  - تضم إحصاءات `pending/failed/dead/synced` + أزرار Retry/Sync/Refresh.
- ربط شاشة الحالة من الإعدادات وإضافة route مخصص لها في نظام الملاحة.
- إضافة حارس قبل الخروج/تبديل الحساب يمنع المسح عند وجود طابور مزامنة عالق.

**الأثر:** تقليل احتمال فقدان بيانات مالية عند الخروج أو تبديل الحساب.

---

### 9.2 تم تنفيذه في التتبع المحاسبي Actor/Shift (R4)

- توسيع schema بإضافة حقول:
  - `actorUserId`
  - `shiftOwnerUserId`
  في جداول `invoices` و`cash_ledger`.
- إضافة migrations لتحديث القواعد الحالية تلقائيًا.
- تمرير وتخزين الحقول الجديدة عند إنشاء الفاتورة وإدخالات دفتر النقد.
- إظهار "المنفّذ" و"صاحب الوردية" في شاشة الصندوق.

**الأثر:** تحسين المساءلة وفصل هوية منفّذ الحركة عن هوية صاحب الوردية.

---

### 9.3 تم تنفيذه في تقليل مخاطر LWW المالي (R2)

- تعديل دمج `customer_debt_payments` ليصبح أقرب إلى immutability:
  - السجلات القائمة لا تُستبدل عشوائيًا بـ LWW.
- تعديل مماثل في `supplier_payouts` ضمن `supplier_financials`.
- حماية دمج `cash_ledger` بحيث لا يستبدل القيم المالية الأساسية، ويكتفي بإغناء حقول الربط عند الحاجة.

**الأثر:** خفض خطر ضياع أو تشويه تسويات مالية بسبب آخر كتابة تفوز.

---

### 9.4 تم تنفيذه في مسار `fils-first` (R3)

#### أ) الديون والتحصيل
- تصحيح مسار التحصيل في `db_debts` ليعتمد حسابًا داخليًا بـ `fils` مع تحويل للعرض فقط.
- إصلاح خطأ النوع الذي ظهر في البناء (`num` مقابل `int`) في `appliedFils`.

#### ب) التقارير (SQL + UI)
- تحويل تجميعات أساسية في `reports_repository` إلى `fils` من SQL مباشرة، ثم تحويل للعرض عند الحاجة:
  - `sumSalesNet`
  - `returnsTotals`
  - `sumExpenses`
  - `salesByType`
  - `dailySalesByType`
  - `dailySalesByStaff`
  - `dailySales`
  - `topCustomers`
  - `topProducts`
  - `dailyExpenses`
  - `staffSales`
  - `loyaltyDiscount` ضمن loyalty totals
- إضافة getters مساعدة `...Fils` في موديلات التقرير وربطها في الواجهة.
- تحديث الرسوم/الجداول في `reports_screen` لتستخدم `fils` داخليًا قبل العرض.

**الأثر:** تقليل الانحراف التراكمي الناتج عن `double` في مؤشرات التقارير المالية.

---

### 9.5 تم تنفيذه في قابلية التتبع (R9)

- إزالة حالات `catch (_) {}` المتبقية في `reports_repository`.
- استبدالها بـ `catch (e, st)` مع تسجيل عبر `AppLogger.warn/error`.

**الأثر:** منع الابتلاع الصامت للأخطاء في المسارات التجميعية الحساسة.

---

### 9.6 التحقق الفني المنفّذ

- تم التحقق من الملفات المعدلة مباشرة عبر:
  - `dart analyze lib/services/reports_repository.dart lib/screens/reports/reports_screen.dart lib/services/db_debts.dart`
- النتيجة: لا توجد أخطاء تحليلية مانعة في هذه الملفات.
- ملاحظة بيئية: `flutter analyze` تعطل بسبب مشكلة في Flutter toolchain (missing analysis server snapshot)، وهي مشكلة بيئة محلية وليست خطأ Dart في الكود المعدّل.

---

### 9.7 حالة الخطة بعد التحديث

- **المرحلة 0:** مُنفّذ جزء كبير (الرصد + إزالة ابتلاع الأخطاء + تشخيص المزامنة).
- **المرحلة 1:** مُنفّذ جزء مهم (حارس الطابور + شاشة إدارة sync_queue + تقليل LWW المالي).
- **المرحلة 2:** تقدّم متقدم في محور `fils-first` (التقارير + الديون + التقسيط + الصندوق + تنبيهات الديون + تصنيفات العملاء)، وما زال يحتاج إغلاق نهائي لبقية المسارات المالية الطرفية.

> هذا التحديث لا يعني اكتمال كل المراحل؛ هو توثيق دقيق لما تم إنجازه فعليًا حتى الآن.

---

### 9.8 دفعة تنفيذ إضافية (متابعة المرحلة 2)

تم تنفيذ دفعة إضافية بعد تحديث القسم 9.4، وشملت ما يلي:

- `db_installments`:
  - تحويل حسابات `remaining / payment / return adjustment` إلى `fils` داخليًا.
  - استبدال حدود `0.01/epsilon` في شروط الخطة المفتوحة بمقارنات `fils`.

- `db_cash`:
  - تحويل حساب `cashAmount` داخل مسار إصلاح دفتر الصندوق إلى `cashAmountFils`.
  - استبدال شروط `advancePayment > 0.009` في SQL بمقارنات `ROUND(... * 1000) > 0`.

- `db_invoices`:
  - تحويل تحقق اتزان الفاتورة إلى مقارنات `fils` (`line total / expected total / advance cap`).
  - استبدال شرط `supplierPayment` النقدي من `1e-9` إلى تحقق `fils > 0`.

- `db_notifications`:
  - تحويل شروط الديون المفتوحة وقيم الـ cap من `double thresholds` إلى `fils` (`ROUND(... * 1000)`).
  - توحيد شروط remaining/open debt في الاستعلامات التنبيهية.

- `db_customers`:
  - تحويل تصنيف الحالات (مديون/دائن/مميّز/مصفّى) من `balance > 0.01` ونظائره إلى `ROUND(balance * 1000)` مباشرة.
  - تحديث عدادات التبويبات بنفس النمط.

- `database_helper`:
  - إزالة tolerance العشرية في دمج مدفوعات خطة التقسيط واعتماد مقارنة `fils` عند القص إلى `totalAmount`.

**التحقق بعد هذه الدفعة:**
- تم تشغيل `dart analyze` على حزمة الملفات المعدلة في هذه الدفعة (تقارير + ديون + تقسيط + صندوق + فواتير + تنبيهات + عملاء + موردين + helper).
- النتيجة: لا توجد أخطاء تحليلية مانعة (`No issues found`).

---

### 9.9 بدء التنفيذ الفعلي للمرحلة 3 (صلاحيات/ورديات)

تم بدء المرحلة 3 بأول تعديل حاكم في مسار الصلاحيات:

- `permission_service`:
  - جعل مرجع الصلاحيات الافتراضي هو مستخدم الجلسة الحالي (`actor`) بدل صاحب الوردية.
  - إضافة خيار صريح للتوافق القديم فقط:
    - `useShiftOwnerAsSubject`
    - والقيمة الافتراضية له `false`.

- تم تمرير `useShiftOwnerAsSubject: false` بشكل صريح في الاستدعاءات الحالية لمسار التحقق من الصلاحيات:
  - `permissions_provider`
  - `inventory_hub_screen`

**الأثر:**
- تقليل خطر `Shift Permission Override` عبر منع وراثة صلاحيات صاحب الوردية بشكل تلقائي.
- جعل السلوك الافتراضي متوافقًا مع مبدأ: الصلاحية تُحتسب على منفّذ العملية.

---

### 9.10 إغلاق جزئي للمرحلة 3 (حارس تعارض الجلسة/الوردية)

تم تطبيق حارس تشغيلي مباشر يمنع تنفيذ الحركة المالية عند وجود عدم تطابق بين:
- المستخدم الحالي في الجلسة (`actor`).
- صاحب الوردية المفتوحة (`shiftStaffUserId`).

تم أيضًا توحيد منطق الفحص في utility مركزية:
- `lib/utils/shift_actor_conflict_guard.dart`
- لتفادي تكرار الشروط وضمان اتساق السلوك عبر الشاشات.

المسارات التي تم تغطيتها فعليًا:

- `cash_screen`:
  - منع الإيداع/السحب اليدوي عند التعارض.
  - إظهار Banner تحذيري واضح داخل الشاشة + رسالة تنبيه.

- `add_invoice_screen`:
  - منع حفظ الفاتورة عند التعارض قبل تنفيذ الحفظ.
  - إظهار رسالة عربية توضح سبب المنع.

- `service_order_form_screen`:
  - منع حفظ/إتمام بطاقة الخدمة (والبيع المرتبط بها) عند التعارض.
  - إظهار رسالة عربية توضح السبب.

**الأثر:**
- تقليل اختلاط العهد المالية الناتج عن استمرار العمل بجلسة مستخدم لا تطابق الوردية المفتوحة.
- توحيد سياسة الحماية عبر أكثر من نقطة إدخال مالية عالية الحساسية.

**مستوى الإنجاز:**
- هذا يعتبر **إغلاقًا جزئيًا قويًا للمرحلة 3**.
- المتبقي: توسيع الحارس على بقية المسارات المالية الأقل استخدامًا + توحيد الرسالة/التجربة بصيغة مركزية واحدة.

---

### 9.11 تنظيف جودة شاشة أوامر الخدمة (دفعة دعم المرحلة 3)

تم تنفيذ دفعة تنظيف نوعية في:
- `lib/screens/services/service_order_form_screen.dart`

ما تم في هذه الدفعة:
- إغلاق كامل لتحذيرات `prefer_const_constructors` المتبقية داخل مقاطع إدخال وتسعير بطاقة الخدمة.
- إزالة wrappers/aliases داخلية غير مستخدمة (`unused_element`) كانت مرتبطة بمسار هيدروليك أحادي البطاقة، مع الإبقاء على الدوال الأساسية `...For(slot)` المستخدمة فعليًا.
- التنظيف تم بدون تغيير سلوك الأعمال أو تدفق الحفظ، وهدفه تقليل الضجيج التحليلي ورفع قابلية الصيانة قبل متابعة التوسعة الوظيفية للمرحلة 3.

**التحقق:**
- تم تشغيل:
  - `dart analyze lib/screens/services/service_order_form_screen.dart`
- النتيجة:
  - `No issues found`

**الأثر:**
- إلغاء التحذيرات بالكامل في الشاشة الأكثر تعقيدًا ضمن مسار الخدمة.
- تسهيل اكتشاف أي انحدار جديد لاحقًا لأن التحليل أصبح نظيفًا (signal-to-noise أفضل).

---

### 9.12 توسيع حارس تعارض الجلسة/الوردية لمسار تحصيل الديون

تم توسيع حماية المرحلة 3 إلى مسار مالي إضافي عالي الحساسية:
- `lib/screens/debts/customer_debt_detail_screen.dart`

ما تم:
- ربط الشاشة مع:
  - `ShiftProvider`
  - `ShiftActorConflictGuard`
- إضافة فحص تعارض قبل تنفيذ `recordCustomerDebtPayment`.
- عند وجود تعارض (`actor` لا يطابق صاحب الوردية المفتوحة)، يتم:
  - منع عملية التسديد.
  - إظهار رسالة عربية واضحة باسم صاحب الوردية.

**التحقق:**
- تم تشغيل:
  - `dart analyze lib/screens/debts/customer_debt_detail_screen.dart`
- النتيجة:
  - `No issues found`

**الأثر:**
- تقليل خطر تسجيل تسديدات دين تحت جلسة لا تطابق الوردية المفتوحة.
- توسيع تغطية الحارس من (فاتورة + صندوق + أوامر خدمة) إلى مسار تحصيل ديون العملاء.

---

### 9.13 توسيع الحارس لمسار مدفوعات الموردين

تمت إضافة نفس سياسة تعارض الجلسة/الوردية إلى:
- `lib/screens/debts/supplier_detail_screen.dart`

المواضع المغطاة:
- تسجيل دفعة للمورد (`_showPayoutDialog`).
- تسجيل مرتجع مورد (`_showSupplierReturnDialog`).
- عكس دفعة مورد (`_confirmReversePayout`).

التنفيذ:
- إضافة helper داخل الشاشة:
  - `_blockIfShiftConflict(String actionLabel)`
- هذا الـ helper يفحص:
  - `sessionUserId` من `AuthProvider`
  - `activeShift` من `ShiftProvider`
  - عبر `ShiftActorConflictGuard.evaluate(...)`
- عند التعارض:
  - يمنع تنفيذ الحركة المالية.
  - يعرض رسالة عربية موحّدة تتضمن اسم صاحب الوردية.

**التحقق:**
- تم تشغيل:
  - `dart analyze lib/screens/debts/supplier_detail_screen.dart`
- النتيجة:
  - `No issues found`

**الأثر:**
- توسيع تغطية حماية المرحلة 3 إلى مسار ذمم الموردين (AP) وليس ديون العملاء فقط.
- تقليل احتمالية تسجيل/عكس دفعات موردين من جلسة غير مطابقة للوردية المفتوحة.

---

### 9.14 توسيع الحارس لمسار المرتجعات (Process Return)

تمت إضافة حماية تعارض الجلسة/الوردية إلى:
- `lib/screens/invoices/process_return_screen.dart`

الموضع المغطّى:
- قبل تنفيذ `_submitReturn` وحفظ فاتورة المرتجع المرتبطة بالفاتورة الأصلية.

التنفيذ:
- إضافة الاستيرادات:
  - `ShiftProvider`
  - `ShiftActorConflictGuard`
- إضافة فحص:
  - `ShiftActorConflictGuard.evaluate(sessionUserId, activeShift)`
- عند التعارض:
  - منع تسجيل المرتجع.
  - عرض رسالة عربية واضحة تتضمن اسم صاحب الوردية المفتوحة.

**التحقق:**
- تم تشغيل:
  - `dart analyze lib/screens/invoices/process_return_screen.dart`
- النتيجة:
  - `No issues found`

**الأثر:**
- منع تنفيذ عملية مرتجع مالية/مخزنية من جلسة لا تطابق الوردية المفتوحة.
- توسيع تغطية المرحلة 3 إلى قناة مرتجعات حساسة كانت خارج الحماية سابقاً.

---

### 9.15 توسيع الحارس لمسار تحصيل الأقساط

تمت إضافة حماية تعارض الجلسة/الوردية إلى:
- `lib/screens/installments/installment_details_screen.dart`

الموضع المغطّى:
- قبل فتح وتنفيذ تدفق `_recordPayment` (تسديد القسط) واستدعاء `recordInstallmentPayment`.

التنفيذ:
- إضافة الاستيرادات:
  - `AuthProvider`
  - `ShiftProvider`
  - `ShiftActorConflictGuard`
- إضافة فحص مبكر داخل `_recordPayment`:
  - `ShiftActorConflictGuard.evaluate(sessionUserId, activeShift)`
- عند التعارض:
  - منع تسجيل تسديد القسط.
  - عرض رسالة عربية واضحة باسم صاحب الوردية المفتوحة.

**التحقق:**
- تم تشغيل:
  - `dart analyze lib/screens/installments/installment_details_screen.dart`
- النتيجة:
  - `No issues found`

**الأثر:**
- منع تسجيل تحصيل أقساط من جلسة لا تطابق الوردية المفتوحة.
- توسيع تغطية المرحلة 3 إلى قناة تحصيل مالية إضافية (Installments Collections).

---

### 9.16 توسيع الحارس لمسار حفظ/إعادة جدولة خطة التقسيط

تمت إضافة حماية تعارض الجلسة/الوردية إلى:
- `lib/screens/installments/add_installment_plan_screen.dart`

الموضع المغطّى:
- قبل تنفيذ `_save` الذي يعيد توزيع الجدول ويستدعي `replaceInstallmentPlanSchedule`.

التنفيذ:
- إضافة الاستيرادات:
  - `provider`
  - `AuthProvider`
  - `ShiftProvider`
  - `ShiftActorConflictGuard`
- إضافة فحص مبكر داخل `_save`:
  - `ShiftActorConflictGuard.evaluate(sessionUserId, activeShift)`
- عند التعارض:
  - منع حفظ/إعادة جدولة خطة التقسيط.
  - عرض رسالة عربية واضحة باسم صاحب الوردية المفتوحة.

**التحقق:**
- تم تشغيل:
  - `dart analyze lib/screens/installments/add_installment_plan_screen.dart`
- النتيجة:
  - `No issues found`

**الأثر:**
- منع تعديل جدول تقسيط مؤثر ماليًا من جلسة لا تطابق الوردية المفتوحة.
- رفع اتساق حماية المرحلة 3 بين (تحصيل القسط) و(إدارة جدول الأقساط).

---

### 9.17 توسيع الحارس لمسار السندات المخزنية ذات الأثر المالي

تمت إضافة حماية تعارض الجلسة/الوردية إلى:
- `lib/screens/inventory/stock_voucher_screen.dart`

الموضع المغطّى:
- في بداية `_confirm` قبل حفظ السند المخزني وتنفيذ أي أثر مالي تابع (مثل ربط حركة مورد عند نوع السند المناسب).

التنفيذ:
- إضافة الاستيرادات:
  - `ShiftProvider`
  - `ShiftActorConflictGuard`
- إضافة فحص مبكر:
  - `ShiftActorConflictGuard.evaluate(sessionUserId, activeShift)`
- عند التعارض:
  - منع حفظ السند.
  - عرض رسالة عربية واضحة باسم صاحب الوردية المفتوحة.

**التحقق:**
- تم تشغيل:
  - `dart analyze lib/screens/inventory/stock_voucher_screen.dart`
- النتيجة:
  - `No issues found`

**الأثر:**
- منع تنفيذ سند مخزني مؤثر ماليًا من جلسة لا تطابق الوردية المفتوحة.
- توسيع نطاق حماية المرحلة 3 إلى مسار المخزون المرتبط بحركات مالية طرفية.

**تنظيف إضافي لاحق في نفس الدفعة:**
- تم إغلاق ملاحظات lint الأربع القديمة في نفس الملف (`prefer_const_constructors` + `unused_local_variable`) بدون تعديل منطق الأعمال.
- النتيجة النهائية للملف بعد التنظيف:
  - `dart analyze lib/screens/inventory/stock_voucher_screen.dart` → `No issues found`.

---

### 9.18 توسيع الحارس داخل مسار ربط وصل المورد بسند وارد

ضمن `supplier_detail_screen` كان هناك مسار إضافي غير مغطّى سابقًا:
- إنشاء سند وارد فارغ وربطه مباشرة بوصل المورد (`_createStubVoucherAndLink`).

تم التنفيذ:
- إضافة فحص مبكر في بداية `_createStubVoucherAndLink` باستخدام:
  - `_blockIfShiftConflict('إنشاء سند وارد وربطه بوصل المورد')`
- عند التعارض:
  - يمنع إنشاء السند والربط.
  - يعرض رسالة عربية موحّدة باسم صاحب الوردية.

**التحقق:**
- تم تشغيل:
  - `dart analyze lib/screens/debts/supplier_detail_screen.dart`
- النتيجة:
  - `No issues found`

**الأثر:**
- سدّ ثغرة تشغيلية كانت تسمح بتنفيذ حركة مخزنية مرتبطة بذمم المورد من جلسة غير مطابقة للوردية.
- رفع اتساق الحماية داخل نفس الشاشة (دفعة/مرتجع/عكس/إنشاء سند وربط).

---

### 9.19 جرد تغطية المرحلة 3 (تدقيق مسارات الحفظ المالية)

تم تنفيذ جرد تقني سريع لمسارات الكتابة المالية المباشرة داخل `lib/screens/**` للتأكد من عدم وجود مسار حفظ/تحصيل بدون حارس تعارض الجلسة/الوردية.

**المسارات المفحوصة (كتابة مالية مباشرة):**
- `cash_screen`:
  - `insertManualCashEntry`
- `add_invoice_screen`:
  - `InvoiceProvider.addInvoice`
- `process_return_screen`:
  - `InvoiceProvider.addInvoice` + `applyInstallmentAdjustmentAfterReturn`
- `customer_debt_detail_screen`:
  - `recordCustomerDebtPayment`
- `supplier_detail_screen`:
  - `recordSupplierPayout`
  - `deleteSupplierPayoutReversingCash`
  - `insertInboundStockVoucherHeader` (إنشاء سند وارد وربط)
- `installment_details_screen`:
  - `recordInstallmentPayment`
- `add_installment_plan_screen`:
  - `replaceInstallmentPlanSchedule`
- `stock_voucher_screen`:
  - حفظ السند المخزني + `recordSupplierPayout` الطرفية عند سند الصرف المرتبط بالمورد

**نتيجة التدقيق:**
- جميع المسارات المذكورة أعلاه أصبحت مغطّاة بفحص:
  - `ShiftActorConflictGuard.evaluate(sessionUserId, activeShift)`
- لا يوجد مسار مالي مباشر في نتائج الجرد بدون حارس ضمن هذه الشاشات.

**ملاحظات الإقفال المتبقي للمرحلة 3:**
- الإقفال الحالي قوي على مستوى "نقاط الحفظ عالية الأثر" في الواجهة.
- المتبقي المقترح (تحسين سياساتي): فرض إغلاق الوردية قبل تسجيل الخروج/تبديل الحساب (Hard Enforcement) مع استثناء واضح للمالك حسب السياسة المعتمدة.

---

### 9.20 تنفيذ Hard Enforcement لإغلاق الوردية قبل إنهاء/تبديل الجلسة

تم تنفيذ الجزء المتبقي من المرحلة 3 داخل:
- `lib/providers/auth_provider.dart`

ما تم:
- تفكيك فحص الوردية المفتوحة إلى طبقة عامة قابلة لإعادة الاستخدام:
  - `_assertNoOpenShiftBlockingAction(...)`
- إبقاء مسار الخروج (`logout`) مع دعم الاستثناء الطارئ للمالك:
  - `_assertNoOpenShiftForLogout(allowOwnerEmergencyOverride: ...)`
- إضافة فحص صريح جديد لمسار تبديل الحساب قبل مسح/تبديل نطاق البيانات:
  - `_assertNoOpenShiftForAccountSwitch()`
  - تم استدعاؤه داخل `_bindAccountDataScope` قبل تنفيذ منطق `switching` (وقبل wipe/closeAndDelete).

**السلوك بعد التنفيذ:**
- عند وجود وردية مفتوحة:
  - يُمنع `logout` (إلا في مسار الطوارئ للمالك عندما يُمرَّر override صريح).
  - ويُمنع أيضًا `account switch` حتى إغلاق الوردية أولاً.
- رسالة الخطأ أصبحت مرتبطة بنوع العملية (`تسجيل الخروج` أو `تبديل الحساب`) بدل رسالة عامة واحدة.

**التحقق:**
- تم تشغيل:
  - `dart analyze lib/providers/auth_provider.dart`
- النتيجة:
  - لا توجد أخطاء تحليلية مانعة.
  - توجد ملاحظة info قديمة غير مرتبطة بهذه الدفعة (`unnecessary_string_interpolations`).

**الأثر:**
- إغلاق فجوة تشغيلية حرجة: منع إنهاء/تبديل الجلسة مع وردية مفتوحة قبل أي مسح بيانات أو تبديل owner scope.
- رفع اتساق سياسة العهد بين طبقة الواجهة وطبقة إدارة الجلسة المركزية.

---

### 9.21 تثبيت إلزام `customerId` في تسديدات الديون (طبقة البيانات)

لتقليل بقايا خطر `name-based debt linking` (R6)، تم تعزيز المنع في مستوى الخدمة نفسه:
- `lib/services/db_debts.dart`

ما تم:
- داخل `recordCustomerDebtPayment(...)` أضيف شرط مبكر:
  - رفض العملية إذا كان `party.customerId` مفقودًا أو غير صالح.
  - رمي `StateError` برسالة عربية واضحة تطلب ربط العميل ببطاقته أولًا.
- بعد فرض وجود `customerId`:
  - تم تبسيط الكتابة الداخلية لاستخدام `customerId` إلزاميًا عند:
    - جلب `customer_global_id`
    - إنشاء سجل `customer_debt_payments`
    - إنشاء سند التحصيل (`InvoiceType.debtCollection`)
    - تسجيل الـ audit (`entityId`)

**التحقق:**
- تم تشغيل:
  - `dart analyze lib/services/db_debts.dart lib/screens/debts/customer_debt_detail_screen.dart`
- النتيجة:
  - `No issues found`

**الأثر:**
- منع أي مسار خلفي من تسجيل تسديد دين لعميل غير مربوط (`customerId == null`) حتى لو تم تجاوز قيود الواجهة.
- رفع اتساق المرحلة 2 (Ledger correctness) عبر تقليل الاعتماد التشغيلي على مطابقة الاسم في عمليات التحصيل الجديدة.

---

### 9.22 تثبيت إلزام `customerId` لفواتير الدين/التقسيط في طبقة الحفظ

استكمالًا لإغلاق R6 على مستوى backend المحلي، تم تعزيز التحقق داخل:
- `lib/services/db_invoices.dart`

ما تم:
- داخل `_validateInvoiceForSave(...)` أضيف شرط صريح:
  - إذا كانت الفاتورة من نوع:
    - `InvoiceType.credit`
    - `InvoiceType.installment`
  - فيجب وجود `invoice.customerId` صالح (`> 0`).
- عند غياب الربط:
  - يتم رفض الحفظ بـ `FormatException` واضحة:
    - `'لا يمكن حفظ فاتورة دين/تقسيط بدون ربط العميل ببطاقته (customerId).'`

**التحقق:**
- تم تشغيل:
  - `dart analyze lib/services/db_invoices.dart lib/screens/invoices/add_invoice_screen.dart`
- النتيجة:
  - `No issues found`

**الأثر:**
- منع أي مسار حفظ (حتى خارج الشاشة الرئيسية) من إنشاء فاتورة دين/تقسيط غير مربوطة بعميل فعلي.
- تقليل جذري لاعتماد النظام على fallback الاسم في العمليات الجديدة، وحصره في بيانات تاريخية فقط لحين الترحيل.

---

### 9.23 توحيد سلوك الواجهة مع إلزام `customerId` في تسديد الديون

بعد تثبيت المنع في `db_debts`، تم توحيد UX في شاشة التحصيل نفسها:
- `lib/screens/debts/customer_debt_detail_screen.dart`

ما تم:
- إضافة حارس مبكر داخل `_openPayDialog`:
  - إذا كان السجل غير مربوط بعميل (`customerId` مفقود/غير صالح) يتم منع فتح تدفق التسديد مع رسالة عربية واضحة.
- ضبط حالة زر التسديد في الشريط السفلي:
  - لا يتفعّل إلا عند:
    - وجود متبقٍ فعلي (`openTotal > 0`)
    - ووجود `customerId` صالح.

**التحقق:**
- تم تشغيل:
  - `dart analyze lib/screens/debts/customer_debt_detail_screen.dart lib/services/db_debts.dart`
- النتيجة:
  - `No issues found`

**الأثر:**
- منع المستخدم من بدء تسديد غير قابل للحفظ أساسًا.
- اتساق كامل بين طبقة الواجهة وطبقة البيانات في قاعدة "لا تسديد دين بدون `customerId`".

---

### 9.24 تقوية R7 تشغيليًا: تشخيص حي للحركات `failed/dead`

تم تنفيذ دفعة تشغيلية إضافية لمسار المزامنة العالقة:
- `lib/services/sync_queue_service.dart`
- `lib/screens/settings/sync_queue_health_screen.dart`

ما تم:
- إضافة API جديدة في الخدمة:
  - `getRecentBlockingMutations({limit})`
  - تُرجع أحدث الحركات `failed/dead` مع:
    - `mutation_id`
    - `entity_type`
    - `operation`
    - `status`
    - `retry_count`
    - `last_error`
    - `last_attempt_at / created_at`
- ربط شاشة الصحة بهذه البيانات:
  - تحميل القائمة عند `reload`
  - تحديثها بعد `syncNow`
  - تحديثها بعد `retryAllFailedAndDead`
- إضافة لوحة تشخيص داخل الشاشة تعرض أحدث العمليات المتعثرة بصيغة قابلة للفحص السريع (مع تمييز حالة `dead`).

**التحقق:**
- تم تشغيل:
  - `dart analyze lib/services/sync_queue_service.dart lib/screens/settings/sync_queue_health_screen.dart`
- النتيجة:
  - `No issues found`

**الأثر:**
- رفع قابلية التشغيل الفعلي لـ R7: لم تعد الحالة أرقامًا فقط، بل أصبحت تتضمن سياقًا تشخيصيًا مباشرًا (ما الذي فشل ولماذا).
- تسهيل قرار التدخل الإداري قبل وصول العمليات إلى حالة فقدان/تعطّل طويل.

---

### 9.25 تعزيز R2/R8: حماية LWW للأرصدة والمخزون + استبعاد فواتير اللقطة

**الملفات:**
- `lib/services/cloud_sync_service.dart`

**R2 — ما تم:**
- دمج **عملاء/موردين** عبر `_mergePartyMasterByGlobalId`: LWW للبيانات الوصفية فقط؛ لا يُستبدل `balance` / `loyaltyPoints` محلياً.
- دمج **منتجات** عبر `_mergeProductsByGlobalId`: لا يُستبدل `qty` لمنتج موجود (تقليل خطر 4.5 عند التزامن).
- **مصروف مدفوع** (`status == paid`): عدم السماح لـ LWW بتعديل `amount` / `amountFils` / `status` / `affectsCash`.
- استبعاد `invoices` و `invoice_items` من لقطة المزامنة (لا `global_id` — LWW على `id` كان يخلط فواتير أجهزة مختلفة).
- منع LWW العام على جداول حركات المخزون/الفواتير عند وجود صف محلي (`_isGenericLwwBlockedForTable`).
- إزالة كتل دمج مكررة في `_mergeTableRows`.

**R8 — ما تم (جزئي):**
- قراءة جداول اللقطة عند التصدير بصفحات (`id > ?`, 500 صف) بدل `query` واحدة — يخفّض ذروة ذاكرة SQLite أثناء البناء.

**التحقق:**
- `dart analyze lib/services/cloud_sync_service.dart`

**الأثر:**
- R2: من **جزئي** إلى **جزئي قوي+** (أغلب الكيانات المالية في delta/snapshot محمية؛ الفواتير خارج اللقطة حتى إضافة `global_id`).
- R8: **جزئي** (التجميع النهائي للـ payload ما زال في الذاكرة).

---

### 9.26 إعادة إدخال الفواتير للمزامنة بعد تثبيت `global_id`

**الملفات:**
- `lib/services/db_financial_sync.dart`
- `lib/services/db_invoices.dart`
- `lib/services/cloud_sync_service.dart`
- `lib/services/database_helper.dart`

**R2 — ما تم:**
- تعزيز `ensureInvoicesGlobalIdSchema` ليضمن دائمًا (حتى في قواعد قديمة جزئية):
  - أعمدة `invoices.global_id`, `invoices.updatedAt`
  - أعمدة `invoice_items.global_id`, `invoice_items.invoice_global_id`, `invoice_items.product_global_id`, `invoice_items.updatedAt`
  - فهارس `global_id` الفريدة.
- Backfill للبيانات القديمة:
  - توليد `global_id` للفواتير/البنود القديمة عند الفراغ.
  - ربط `invoice_items.invoice_global_id` من `invoices.global_id`.
  - ربط `invoice_items.product_global_id` من `products.global_id`.
- عند إنشاء فاتورة جديدة:
  - تخزين `invoices.global_id` و`updatedAt` مباشرة.
  - تخزين `invoice_items.global_id` و`invoice_global_id` و`product_global_id` و`updatedAt`.
- إعادة إدخال `invoices` و`invoice_items` في snapshot sync بعد توفر `global_id`.
- إضافة دمج مخصص في `cloud_sync_service`:
  - `_mergeInvoicesByGlobalId`
  - `_mergeInvoiceItemsByGlobalId` مع resolve آمن لـ `invoiceId` و`productId` عبر المعرفات العالمية.
- إضافة mapping للدلتا:
  - `invoice -> invoices`
  - `invoice_item -> invoice_items`

**التحقق:**
- `dart analyze lib/services/cloud_sync_service.dart lib/services/db_financial_sync.dart lib/services/db_invoices.dart lib/services/database_helper.dart`
- النتيجة: `No issues found`

**الأثر:**
- تخفيض كبير لاحتمال خلط فواتير أجهزة مختلفة عند الاستيراد.
- تمهيد لتحويل الفواتير تدريجيًا من نمط replace/LWW إلى event-safe أكثر صرامة دون إيقاف المزامنة.

---

### 9.27 بدء تنفيذ R10: مسار ESC/POS حراري (تجريبي)

**الملفات:**
- `lib/services/thermal_esc_pos_service.dart`
- `lib/models/print_settings_data.dart`
- `lib/screens/printing/printing_screen.dart`
- `lib/utils/sale_receipt_pdf.dart`

**ما تم:**
- إضافة خدمة جديدة `ThermalEscPosService` لتوليد:
  - نص إيصال حراري بعرض 58/80 مم.
  - أوامر ESC/POS خام (`Uint8List`) مع `INIT` و`CUT`.
  - تمثيل Base64 للحمولة لإرسالها عبر bridge (Bluetooth/USB/LAN).
- إضافة إعداد جديد في `print_settings`:
  - `thermalEscPosEnabled` (افتراضياً `false`).
- توسيع شاشة الطباعة:
  - سويتش: `تفعيل مسار ESC/POS الحراري`.
  - زر: `معاينة حمولة ESC/POS` يعرض النص + Base64 مع خيارات النسخ.
- عند استدعاء `SaleReceiptPdf.presentReceipt` مع تفعيل ESC/POS على ورق حراري:
  - إظهار تنبيه تشغيلي بأن PDF ما زال fallback مؤقتاً لحين توصيل قناة الإرسال المباشرة للطابعة.

**التحقق:**
- `dart analyze lib/services/thermal_esc_pos_service.dart lib/models/print_settings_data.dart lib/screens/printing/printing_screen.dart lib/utils/sale_receipt_pdf.dart`

**الأثر:**
- تم نقل R10 من "لم يبدأ" إلى **جزئي**: أصبح لدينا مولّد payload حراري فعلي قابل للدمج مع قنوات الأجهزة، مع المحافظة على fallback PDF.

---

### 9.28 توصيل R10 فعلياً: إرسال ESC/POS عبر LAN (TCP 9100)

**الملفات:**
- `lib/services/thermal_network_printer_service.dart`
- `lib/models/print_settings_data.dart`
- `lib/screens/printing/printing_screen.dart`
- `lib/utils/sale_receipt_pdf.dart`

**ما تم:**
- إضافة خدمة `ThermalNetworkPrinterService` للإرسال المباشر إلى طابعة شبكة عبر `Socket.connect(host, port)` بدون حزم جديدة.
- إضافة إعدادات شبكة الطابعة ضمن `print_settings`:
  - `thermalLanHost`
  - `thermalLanPort`
  - `thermalLanTimeoutMs`
- توسيع شاشة الطباعة:
  - حقول IP/Host + Port + Timeout عند تفعيل ESC/POS.
  - زر `إرسال تجريبي للطابعة (LAN)` للتحقق التشغيلي السريع.
- تفعيل المسار في `SaleReceiptPdf.presentReceipt`:
  - عند تفعيل ESC/POS وعلى ورق حراري: يطبع مباشرة عبر LAN.
  - إذا فشل الإرسال: يظهر سبب الفشل ويُفتح PDF كـ fallback.

**التحقق:**
- `dart analyze lib/services/thermal_network_printer_service.dart lib/models/print_settings_data.dart lib/screens/printing/printing_screen.dart lib/utils/sale_receipt_pdf.dart`

**الأثر:**
- رفع R10 من "جزئي (مولّد فقط)" إلى **جزئي قوي**: أصبح المسار الحراري قابلاً للاستخدام الإنتاجي على طابعات LAN الشائعة (منفذ 9100) مع fallback آمن.

---

### 9.29 تعزيز R8: منع نسخ chunks الإضافية أثناء رفع اللقطة

**الملف:**
- `lib/services/cloud_sync_service.dart`

**ما تم:**
- في `_pushSnapshot` (فرع payload الكبير):
  - إزالة إنشاء قائمة وسيطة كاملة `chunks = _splitText(encoded, ...)`.
  - التحويل إلى loop مباشر بالفهارس:
    - حساب `chunkCount` فقط.
    - استخراج `substring` لكل chunk ورفعه فورًا.
- حذف الدالة `_splitText` بعد الاستغناء عنها.

**التحقق:**
- `dart analyze lib/services/cloud_sync_service.dart`
- النتيجة: `No issues found`

**الأثر:**
- خفض ذروة الذاكرة أثناء الرفع chunked عبر إزالة نسخة إضافية من النص المضغوط داخل قائمة chunks.
- R8 ما زال **جزئي** (payload النهائي نفسه ما زال يُبنى كاملاً قبل الضغط).

---

### 9.30 تعزيز R6: ترحيل تلقائي آمن لفواتير الدين القديمة إلى `customerId`

**الملف:**
- `lib/services/db_debts.dart`

**ما تم:**
- إضافة وظيفة داخلية `_backfillLegacyCreditInvoiceCustomerIds(...)` تقوم بـ:
  - البحث عن أسماء العملاء الفريدة داخل نفس `tenantId`.
  - ربط فواتير الدين القديمة (`customerId IS NULL`) بالعميل الصحيح عندما يكون الاسم مطابقًا بشكل فريد.
  - تحديث `invoices.updatedAt` عند الربط.
- تفعيل الترحيل قبل قراءات الدين الأساسية:
  - `getCustomerDebtSummaries()`
  - `sumOpenCreditDebtForParty(...)`
  - `getCustomerDebtLineItems(...)`
  - `getCreditDebtInvoicesForParty(...)`
- عند القراءة باسم فقط (`party.customerId == null`) يُمرَّر `normalizedName` لتقليل نطاق الترحيل.

**التحقق:**
- `dart analyze lib/services/db_debts.dart`
- النتيجة: `No issues found`

**الأثر:**
- تقليل الاعتماد التشغيلي على name-based matching في البيانات التاريخية.
- R6 انتقل من "جزئي قوي" إلى **جزئي قوي جدًا** (معالجة legacy شبه تلقائية دون ربط خاطئ للأسماء المكررة).

---

### 9.31 إغلاق تشغيلي لـ R6: شاشة ربط يدوي للديون غير المربوطة

**الملفات:**
- `lib/models/customer_debt_models.dart`
- `lib/services/db_debts.dart`
- `lib/screens/debts/customer_debt_linking_screen.dart`
- `lib/screens/debts/debts_screen.dart`
- `lib/screens/debts/debt_settings_screen.dart`

**ما تم:**
- نماذج جديدة:
  - `UnlinkedCreditDebtInvoice`
  - `AmbiguousDebtCustomerName`
- API في قاعدة البيانات:
  - `getUnlinkedOpenCreditDebtInvoices()` — بعد الترحيل التلقائي الآمن
  - `getAmbiguousDebtCustomerNames()` — أسماء تطابق أكثر من عميل
  - `linkOpenCreditInvoiceToCustomer(...)` — ربط يدوي مع تحقق tenant + audit log
- شاشة جديدة `CustomerDebtLinkingScreen`:
  - عرض الفواتير غير المربوطة + تحذيرات الأسماء المكررة
  - حوار اختيار عميل (بحث) وربط الفاتورة
  - حالات loading / empty / error
- نقاط دخول:
  - زر في `DebtsScreen` (شريط التطبيق)
  - زر في `DebtSettingsScreen`

**التحقق:**
- `dart analyze` على الملفات المعدّلة (بدون أخطاء)

**الأثر:**
- إكمال الحلقة التشغيلية لـ R6: البيانات التاريخية إما تُربط تلقائياً (اسم فريد) أو يدوياً عبر واجهة واضحة.
- R6 أصبح **جزئي قوي جدًا + قابل للإغلاق التشغيلي** من قبل المستخدم.

---

### 9.32 تعزيز R8: بناء/فك اللقطة بذاكرة أقل

**الملف:**
- `lib/services/cloud_sync_service.dart`

**ما تم:**
- بناء JSON اللقطة **جدولًا بجدول** عبر `_buildSnapshotPayloadUtf8Bytes` + `_readSyncTableRows` (صفحات 500 صف).
- ضغط اللقطة في isolate عند ≥ 512KB (`gzipSnapshotUtf8` + `compute`).
- فك اللقطة chunked في isolate عند ≥ 512KB (`gzipBase64DecodeSnapshotJson` + `compute`).
- إضافة encoding جديد للـ chunked: `gzip-bytechunks-base64-v2`:
  - الرفع يجزّئ **gzip bytes** ثم يرفع كل جزء Base64 مستقل.
  - السحب يقرأ كل جزء ويفك Base64 مباشرة إلى بايتات، ثم يفك gzip مرة واحدة.
  - توافق رجعي محفوظ مع encoding القديم `gzip+base64`.
- تسجيل فشل الفك عبر `AppLogger.error` بدل إرجاع صامت.
- إزالة دوال ميتة (`_encodePayload`, `_exportSnapshot`, `_SnapshotBuildResult`).

**التحقق:**
- `dart analyze lib/services/cloud_sync_service.dart`

**الأثر:**
- خفض ذروة الذاكرة في **الرفع** (تصدير جدولي + chunks v2) و**السحب chunked** (فك في isolate).
- R8 ما زال **جزئي**: الاستيراد ما زال يحتاج كائن `Map` كاملاً بعد `jsonDecode` (لا يوجد streaming JSON parser حتى الآن).

---

### 9.33 تعزيز R9 + R6 (أسماء مكررة)

**الملفات:**
- `lib/providers/print_settings_provider.dart` — `AppLogger` عند فشل التحميل (دفعة سابقة).
- `lib/services/db_invoices.dart` — تحذير WAC/buyPrice بدل `catch` صامت.
- `lib/providers/business_features_provider.dart` — `AppLogger.error` عند فشل تحميل Feature Gate.
- `lib/providers/notification_provider.dart` — تحذير عند JSON تالف في التخزين المحلي.
- `lib/models/customer_debt_models.dart` — `AmbiguousDebtCustomerMatch`.
- `lib/services/db_debts.dart` — قائمة العملاء المرشحين لكل اسم مكرر.
- `lib/screens/debts/customer_debt_linking_screen.dart` — ExpansionTile + ربط دفعي بفواتير الاسم مع تأكيد.

**التحقق:**
- `dart analyze` على الملفات المعدّلة.

**الأثر:**
- R9: مسارات تشغيلية حرجة أصبحت قابلة للتشخيص في وضع التطوير.
- R6: إغلاق أسرع للأسماء المكررة (عرض المرشحين + ربط كل فواتير الاسم لعميل واحد بعد تأكيد).

---

### 9.34 دفعة R3: تعابير SQL موحّدة (`MoneySql`)

**الملفات:**
- `lib/utils/money_sql.dart` (جديد)
- `lib/services/db_notifications.dart`
- `lib/services/db_installments.dart`
- `lib/services/reports_repository.dart`
- `lib/providers/notification_provider.dart`

**ما تم:**
- إضافة تعابير SQL مشتركة:
  - `invoiceTotalFils` / `invoiceOpenRemainingFils`
  - `expenseAmountFils`
  - نسخ بـ alias (`invoiceTotalFilsOf('i')` …)
- تحديث تنبيهات الديون وإجمالي مبيعات اليوم لاستخدام `totalFils/advancePaymentFils` أولاً.
- تحديث تجميعات `ReportsSqlOps` ومسارات `_daily*` لتفضيل أعمدة `*Fils` بدل `ROUND(SUM(double)*1000)` فقط.
- قراءة `openTotalFils` في `notification_provider` عند إشعارات سقف الدين.

**التحقق:**
- `dart analyze` على الملفات المعدّلة.

**الأثر:**
- تقليل انحراف الأرقام في التقارير والتنبيهات عند وجود أعمدة fils مملوءة.
- R3 انتقل خطوة أقرب للإغلاق؛ ما زال هناك مسارات UI/JSON تعرض `double` للعرض فقط.

---

### 9.35 دفعة R3: توحيد `db_debts` على `MoneySql`

**الملف:**
- `lib/services/db_debts.dart`

**ما تم:**
- استبدال تكرار CASE المالي الخاص بالمتبقي المفتوح (`total - advancePayment`) بتعبير موحّد:
  - `MoneySql.invoiceOpenRemainingFils`
  - `MoneySql.invoiceOpenRemainingFilsOf('i')` عند وجود alias.
- توحيد نفس التعبير عبر:
  - الاستعلامات المفتوحة (open debts).
  - تجميعات `SUM(...)` للديون المفتوحة.
  - شروط `> 0` في استعلامات الربط/الترحيل.

**التحقق:**
- `dart analyze` على الملفات المعدّلة ضمن دفعة R3 — بدون أخطاء.

**الأثر:**
- تقليل التكرار وخطر الانجراف بين استعلامات الديون عند أي تعديل لاحق.
- تحسين قابلية الإغلاق النهائي لـ R3 عبر مركزية منطق `fils` في SQL.

---

### 9.36 دفعة R3: إغلاق بقايا SQL المالية في `db_cash/db_reports/reports_repository`

**الملفات:**
- `lib/utils/money_sql.dart`
- `lib/services/db_cash.dart`
- `lib/services/db_reports.dart`
- `lib/services/reports_repository.dart`

**ما تم:**
- توسيع `MoneySql` بتعابير إضافية:
  - `invoiceAdvancePaymentFilsOf(alias)`
  - `invoiceItemTotalFilsOf(alias)`
- استبدال شرط `advancePayment` في إصلاح دفتر الصندوق (`db_cash`) إلى تعبير fils موحّد.
- تحديث `db_reports` لاستخدام:
  - `MoneySql.invoiceTotalFils`
  - `MoneySql.expenseAmountFils`
  بدل CASE اليدوي المكرر.
- تحديث `reports_repository` (`_topProducts`) لتجميع `invoice_items` عبر `invoiceItemTotalFilsOf('ii')`.

**التحقق:**
- `dart analyze lib/utils/money_sql.dart lib/services/db_cash.dart lib/services/db_reports.dart lib/services/reports_repository.dart`
- لا توجد أخطاء تحليلية.

**الأثر:**
- خفض بقايا الاعتماد على `ROUND(...*1000)` اليدوي في المسارات المالية الأساسية.
- تقارب أعلى نحو إغلاق R3 على مستوى SQL/الخدمات، مع بقاء `double` في العرض فقط.

---

### 9.37 دفعة R9: إزالة `catch (_) {}` من مزودات/نماذج تشغيلية

**الملفات:**
- `lib/providers/ui_feedback_settings_provider.dart`
- `lib/providers/dashboard_layout_provider.dart`
- `lib/providers/global_barcode_route_bridge.dart`
- `lib/screens/debts/debt_settings_screen.dart`
- `lib/models/installment_settings_data.dart`
- `lib/models/loyalty_settings_data.dart`
- `lib/models/debt_settings_data.dart`

**ما تم:**
- استبدال `catch (_) {}` في مسارات تشغيلية مهمة بـ `catch (e, st)` مع `AppLogger.error`.
- تغطية حالات:
  - تحميل/حفظ تفضيلات UI.
  - Hydration لتخطيط أقسام الشاشة الرئيسية.
  - فشل معالج أولوية الباركود.
  - فشل تحديث الإشعارات بعد حفظ إعدادات الدين.
  - JSON تالف في إعدادات (التقسيط/الولاء/الدين) مع fallback افتراضي + logging.

**التحقق:**
- `dart analyze` على الملفات المعدّلة — بدون أخطاء.

**الأثر:**
- تقليل الابتلاع الصامت للأخطاء في الإعدادات وتجربة المستخدم اليومية.
- تقدم إضافي في R9 دون المساس بمسارات migrations الحساسة.

---

### 9.38 دفعة R9: تنظيف owner/home repositories

**الملفات:**
- `lib/owner/owner_finance_repository.dart`
- `lib/owner/owner_command_center_repository.dart`
- `lib/home/home_kpi_repository.dart`

**ما تم:**
- استبدال كل `catch (_) {}` في هذه المستودعات بـ `catch (e, st)` + `AppLogger.error`.
- تغطية مسارات KPI التشغيلية الحساسة:
  - ملخص الصندوق اليومي/الإجمالي.
  - تنبيهات الأقساط والمخزون وقوائم المدينين.
  - KPI الشاشة الرئيسية (مبيعات الوردية/مبيعات اليوم/السيارات النشطة/المقبوض النقدي).

**التحقق:**
- `dart analyze` على الملفات الثلاثة — بدون أخطاء.
- فحص `catch (_)` داخل الملفات الثلاثة — لا توجد مطابقات.

**الأثر:**
- رفع قابلية التشخيص في لوحة المالك والرئيسية عند فشل SQLite أو بيانات غير متوقعة.
- تقدم إضافي ملموس في R9 على المسارات اليومية عالية الاستخدام.

---

### 9.39 دفعة R9: license + owner dashboards

**الملفات:**
- `lib/services/license_service.dart`
- `lib/owner/owner_clothing_dashboard_repository.dart`
- `lib/owner/owner_oil_dashboard_repository.dart`
- `lib/owner/owner_supermarket_dashboard_repository.dart`
- `lib/owner/owner_trend_repository.dart`

**ما تم:**
- `license_service`:
  - استبدال `catch (_) / PostgrestException catch (_)` في مسارات RPC (`app_device_limit_status`, `app_tenant_access_status`) بـ `catch (e, st)` + `AppLogger.warn/error`.
  - تسجيل fallback في تهيئة cloud trial وفشل قراءة `created_at`.
  - إبقاء سلوك `best-effort` في audit log لكن مع logging بدل الصمت.
- مستودعات owner dashboards:
  - استبدال `catch (_)` بـ `catch (e, st)` + `AppLogger.error` في مسارات KPI/alerts/trends.

**التحقق:**
- `dart analyze` على الملفات المعدلة — بدون أخطاء.
- فحص `catch (_)` في `license_service` — لا توجد مطابقات.

**الأثر:**
- تقليل الصمت التشغيلي في الترخيص ولوحة المالك، خصوصًا عند تعطل RPC أو أخطاء SQLite.
- تقدم إضافي واضح في R9 على المسارات عالية الحساسية (الترخيص + KPIs التنفيذية).

---

### 9.40 دفعة R9: owner providers/services/widgets

**الملفات:**
- `lib/owner/providers/owner_command_center_provider.dart`
- `lib/owner/providers/owner_dashboard_layout_provider.dart`
- `lib/owner/providers/owner_dashboard_studio_provider.dart`
- `lib/owner/services/owner_dashboard_studio_store.dart`
- `lib/owner/widgets/owner_account_profile_menu.dart`
- `lib/owner/widgets/owner_sensitive_actions_panel.dart`
- `lib/owner/widgets/owner_dashboard_v3_panel.dart`

**ما تم:**
- إزالة `catch (_) {}` في المسارات التشغيلية لهذه الملفات واستبدالها بـ:
  - `catch (e, st)` مع `AppLogger.error(...)`.
- تغطية مسارات حيوية:
  - تحميل أقسام لوحة المالك + trends.
  - hydrate/persist لتخطيطات v2/v3.
  - decode/fallback لبيانات الاستوديو المخزنة.
  - تحميل بيانات قائمة حساب المالك وسجل التعديلات الحساسة.
  - fallback profile في `owner_dashboard_v3_panel`.

**التحقق:**
- `dart analyze` على الملفات السبعة — بدون أخطاء.
- فحص `catch (_)` داخل الملفات السبعة — لا توجد مطابقات.

**الأثر:**
- تقليل الصمت التشغيلي في طبقة owner UI/state بشكل واضح.
- توسيع تقدم R9 ليشمل providers/widgets وليس repositories والخدمات فقط.

---

### 9.41 دفعة R9: audit + إقلاع + ترحيل sync_queue

**الملفات:**
- `lib/owner/services/business_audit_log_service.dart`
- `lib/services/db_financial_sync.dart`
- `lib/services/db_customers.dart`
- `lib/services/db_users.dart`
- `lib/services/db_expenses.dart` (عمود `sync_queue.last_attempt_at`)
- `lib/services/app_remote_config_service.dart`
- `lib/services/security_audit_log_service.dart`
- `lib/screens/splash_screen.dart`

**ما تم:**
- إزالة `catch (_) {}` واستبدالها بـ `catch (e, st)` + `AppLogger.error(...)`.
- تغطية:
  - تنظيف retention لسجل تدقيق المالك.
  - ترحيل أعمدة `global_id` للعملاء/المستخدمين والمزامنة المالية.
  - ترحيل أعمدة طابور المزامنة (حرج لـ R1/R7).
  - fallback للإعدادات السحابية + flush سجل الأمان (best-effort مع تسجيل).
  - مسار إقلاع `SplashScreen` (remote config، جلسة، hydrate، features، تنقل).

**التحقق:**
- `dart analyze` على الملفات الثمانية — بدون أخطاء.
- `lib/owner/**` — لا `catch (_) {}` متبقية.

**الأثر:**
- إغلاق طبقة owner بالكامل من ناحية R9.
- تحسين تشخيص فشل الإقلاع والترحيل دون كسر سلوك fallback الموجود.

---

### 9.42 دفعة R9: POS + رئيسية + منتجات + فواتير DB

**الملفات:**
- `lib/screens/invoices/add_invoice_screen.dart`
- `lib/screens/home_screen.dart`
- `lib/screens/login_screen.dart`
- `lib/services/product_repository.dart`
- `lib/services/db_invoices.dart`
- `lib/screens/invoices/invoices_screen.dart`
- `lib/widgets/invoice_deep_link_listener.dart`

**ما تم:**
- إزالة كل `catch (_) {}` في هذه الملفات واستبدالها بـ `AppLogger.error(...)`.
- تغطية مسارات حرجة:
  - تحميل متغيرات/ملابس/زيوت في نقطة البيع.
  - إعدادات التقسيط والفواتير المعلّقة.
  - بوابة الوردية وتحديث المزودات على الرئيسية بعد استيراد لقطة.
  - تسجيل الدخول المحلي + مسار onboarding.
  - حل الباركود (ملابس → وحدة → منتج) + وحدة افتراضية عند الإنشاء.
  - `tenant_id` للفواتير + طابور مزامنة متغيرات الملابس.
  - PDF الإيصال + deep link للفاتورة.

**التحقق:**
- `dart analyze` على الملفات السبعة — بدون أخطاء.
- لا `catch (_) {}` متبقية في الملفات السبعة.

**الأثر:**
- تحسين تشخيص أعطال البيع اليومية (POS) والرئيسية دون تغيير سلوك fallback/UI.

---

### 9.43 دفعة R9: مخزون + متغيرات + أوامر شراء

**الملفات:**
- `lib/screens/inventory/stock_voucher_screen.dart`
- `lib/screens/inventory/add_purchase_order_screen.dart`
- `lib/screens/inventory/product_edit_screen.dart`
- `lib/services/db_product_variants.dart`
- `lib/services/db_oil_product_grades.dart`
- `lib/services/db_suppliers.dart`
- `lib/services/product_variants_repository.dart`
- `lib/screens/invoices/parked_sales_screen.dart`

**ما تم:**
- إزالة `catch (_) {}` واستبدالها بـ `AppLogger.error(...)`.
- تغطية:
  - سند مخزني: موردين، حفظ السند، وحدات المنتج.
  - أمر شراء: تواريخ + إشعارات بعد الحفظ.
  - تعديل منتج: إعدادات النشاط + متغيرات الملابس + وحدات البيع.
  - أمر شراء: الملء التلقائي للأصناف المنخفضة.
  - ترحيل جداول متغيرات الملابس والزيوت + `tenant_id` للموردين.
  - طابور مزامنة متغيرات الملابس.
  - تلخيص JSON للفواتير المعلّقة.

**التحقق:**
- `dart analyze` على الملفات الثمانية — بدون أخطاء.
- لا `catch (_) {}` متبقية في الملفات الثمانية.

**الأثر:**
- تحسين تشخيص مسارات المخزون والشراء دون تغيير سلوك الواجهة.
