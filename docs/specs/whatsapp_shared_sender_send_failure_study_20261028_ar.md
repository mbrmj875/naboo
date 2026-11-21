# دراسة فشل الإرسال عبر رقم نابو الرسمي `+964 787 000 3735`

تاريخ الدراسة: 28 أكتوبر 2026  
الحالة: نُفِّذ على السيرفر (28 أكتوبر) — بلا تعديل تطبيق  
مستوى الثقة بالمشكلة: مؤكد من الكود + السجلات  
مستوى الثقة بمسار الحل الصحيح: مؤكد من نفس السلسلة السببية

### تنفيذ 28 أكتوبر (سيرفر فقط)

- `resolveSharedSenderToken` + `resolveGraphAccessToken` في `shared_sender.ts` / `cloud_api.ts`
- عند phone/waba نابو → توكن نابو فقط؛ مسار `cloud_api` يبقى على `resolveCloudToken`
- نُشر: `whatsapp-gateway` + `whatsapp-cloud-webhook`
- أُعيد اعتماد قوالب بطاقة الغيار `dualhook` لباقر والأندلس (كانت `pending`)
- أسرار ES للمستأجرين **لم تُحذف**

---

## 1) ماذا ندرس

رقم نابو الرسمي:

| الحقل | القيمة |
|---|---|
| الرقم | `+964 787 000 3735` |
| `phone_number_id` | `1206931799175422` |
| `waba_id` | `1207428308207884` |
| المزود في DB | `dualhook` (اسم تاريخي = مرسِل نابو عبر Meta) |

السؤال: لماذا فشل الإرسال من هذا الرقم بعد تحديثات الربط، رغم أن الرقم طبيعي على Facebook/WhatsApp والرسوم مسددة؟

---

## 2) من يستخدم هذا الرقم الآن

من `tenant_whatsapp_gateways`:

| البريد | الحالة | آخر تحديث للربط |
|---|---|---|
| `mohamed.albaqer.m@gmail.com` | connected | 28 أكتوبر 10:29 UTC |
| `zyoutalandalus@gmail.com` | connected | 28 أكتوبر 10:31 UTC |
| `mmmnnnnsgggdffdd@gmail.com` | connected | 23 أكتوبر |
| `mbrmjbaqer@gmail.com` | connected | 22 أكتوبر |
| `mmmm1999kkzz@gmail.com` | connected | 29 سبتمبر |
| `almrkzalalmsne@gmail.com` | connected | 17 أغسطس |
| `baqer20012018@gmail.com` | disconnected | 22 أكتوبر |

فشل اليوم ظهر عند باقر والأندلس فقط. كلاهما مرّ بتجارب `cloud_api` / Embedded Signup ثم عاد إلى `dualhook`.

---

## 3) سلسلة الإرسال في الكود (المسار الحقيقي)

عند اختيار رقم نابو الرسمي:

1. `connect_service.ts` يكتب في صف المستأجر:
   - `whatsapp_provider = dualhook`
   - `cloud_phone_number_id = SHARED_SENDER_PHONE_NUMBER_ID`
   - `cloud_waba_id = SHARED_SENDER_WABA_ID`
   - `status = connected` و `cloud_setup_status = ready`
2. يستدعي `ensureDefaultTemplatesForTenant`.
3. عند إرسال بطاقة الغيار:
   - `dispatchWhatsappChannel` → `computeReadyState`
   - إن لم يكن `ready` → فشل فوري `not_ready:preparing`
   - إن كان `ready` → `dualhookTransport.sendTemplate`
4. `dualhook_transport.ts` يفرض معرّف نابو:
   - `phoneNumberId = SHARED_SENDER_PHONE_NUMBER_ID`
   - `wabaId = SHARED_SENDER_WABA_ID`
5. التنفيذ الفعلي في `meta_cloud_transport.sendTemplate` يستدعي:

```ts
const token = await resolveCloudToken(input.tenantUserId);
```

6. `resolveCloudToken` في `cloud_api.ts` بالترتيب:
   1. سر المستأجر: `whatsapp_provider_secrets` حيث `provider='cloud_api'` و `secret_kind='access_token'`
   2. إن وُجد → يُستخدم فوراً ويتوقف البحث
   3. وإلا `WHATSAPP_CLOUD_TOKEN_<userId>`
   4. وإلا `WHATSAPP_CLOUD_TOKEN` العام (توكن نابو الذي يملك رقم `3735`)

هذه النقطة هي جوهرة العطل.

---

## 4) المشكلة المؤكدة رقم 1 — توكن المحل يُستخدم لإرسال رقم نابو

### الدليل من الكود

- `dualhook` يغيّر **معرّف الهاتف** إلى رقم نابو.
- `dualhook` **لا يغيّر** مصدر التوكن.
- `resolveCloudToken` يفضّل توكن ES المحفوظ تحت `cloud_api` لكل مستأجر.
- `set_provider` و `cleanupOtherEngines` وربط `dualhook` **لا يحذفون** صف `whatsapp_provider_secrets`.
- توكن ES يُكتب في `meta_cloud_transport.completeConnect` عند نجاح Embedded Signup، ويبقى بعد العودة لرقم نابو.

### الدليل من قاعدة البيانات

أسرار `access_token` تحت `cloud_api`:

| المستأجر | لديه توكن ES؟ | محدّث في |
|---|---|---|
| `mohamed.albaqer.m@gmail.com` (`a66b5bad…`) | نعم، طول 473 | 27 أكتوبر 09:04 |
| `zyoutalandalus@gmail.com` (`bc6dd843…`) | نعم، طول 466 | 25 أكتوبر 18:30 |
| `mbrmjbaqer@gmail.com` (`87c82e5f…`) | لا | — |
| `mmmnnnnsgggdffdd@gmail.com` | لا | — |

تدقيق الربط في `whatsapp_gateway_audit`:

- باقر: `cloud_api->dualhook` في 28 أكتوبر 10:20 ثم مرة أخرى 10:29.
- الأندلس: `cloud_api->dualhook` في 28 أكتوبر 10:31.
- توكن باقر ES بقي موجوداً بعد التبديل (لم يُمسح).

### الدليل من سجلات الإرسال

نفس خطأ Graph ظهر فقط لمن لديهم توكن ES:

```
Unsupported post request. Object with ID '1206931799175422' does not exist,
cannot be loaded due to missing permissions, or does not support this operation.
```

- باقر: 28 أكتوبر 10:21:44 و 10:29:50
- الأندلس: 28 أكتوبر 10:32:59

معنى الرسالة عند Meta: التوكن المستخدم **لا يملك صلاحية** على كائن الهاتف `1206931799175422`.  
هذا ليس قفلاً على الرقم، وليس نفاذ رصيد، وليس رفض قالب. هو رفض صلاحية التوكن على معرّف نابو.

التفسير الميكانيكي:

```
طلب Graph = POST /{phone_number_id_نابو}/messages
Authorization = Bearer {توكن_ES_الخاص_بالمحل}
```

توكن المحل يملك WABA المحل الذي رُبط أثناء ES، ولا يملك رقم نابو المشترك. النتيجة رفض Graph.

### مقارنة ضابطة

حساب `mbrmjbaqer@gmail.com` مربوط بنفس رقم نابو، بلا توكن ES في الأسرار، وقوالبه `dualhook` معتمدة منذ 22 أكتوبر. آخر إرسالاته المسجّلة وصلت. لم يظهر له خطأ `1206931799175422` اليوم.

إذن الرقم نفسه يعمل مع توكن نابو العام، ويفشل عندما يُستبدل بتوكن ES لمحل آخر.

**يقين: هذه ليست مشكلة واتساب/رسوم/قفل الرقم. هذه مشكلة اختيار توكن خاطئ بعد تجارب الربط الرسمي.**

---

## 5) المشكلة المؤكدة رقم 2 — إعادة الربط تعيد القوالب إلى `pending`

### الدليل من الكود

عند ربط `dualhook`، `connect_service` يستدعي `ensureDefaultTemplatesForTenant`.

هذه الدالة:

1. تقرأ المزود الحالي (`dualhook`).
2. تستدعي `provider.ensureTemplate` ثم `getTemplateStatus`.
3. كلاهما يستدعيان `resolveCloudToken(tenantUserId)` أيضاً.
4. إن فشل Graph أو لم يُقرأ القالب → تُكتب الحالة `pending`.
5. `computeReadyState` لـ `dualhook` يشترط قالباً معتمداً تحت **نفس** المزود `dualhook`.
6. قوالب `cloud_api` المعتمدة لا تُحسب.

### الدليل من قاعدة البيانات (باقر)

| مزود | قالب | حالة | محدّث |
|---|---|---|---|
| `cloud_api` | `oil_change_card_ar` | approved | 28 أكتوبر 10:20 |
| `cloud_api` | `oil_card_lines_ar` | approved | 28 أكتوبر 10:20 |
| `dualhook` | `oil_change_card_ar` | **pending** | 28 أكتوبر 10:29 |
| `dualhook` | `oil_card_lines_ar` | **pending** | 28 أكتوبر 10:29 |
| `dualhook` | `oil_fu_a66b5bad` | approved | 22 أكتوبر (قديم) |

`computeReadyState` يطلب مفاتيح بطاقة الغيار (`oil_change_card` → أسماء `oil_card_lines_ar` / `oil_change_card_ar`) تحت المزود الحالي. الاثنان `pending` تحت `dualhook` → النتيجة `preparing`.

### الدليل من السجلات

قبل خطأ Graph مباشرة تتكرر:

```
not_ready:preparing
```

عند باقر: 10:21:12، 10:21:14، 10:21:43، 10:29:48  
عند الأندلس: 10:32:57

هذا حاجز داخلي في نابو قبل Graph. يحدث لأن بطاقة الغيار غير معتمدة على صفوف `dualhook` بعد إعادة `ensureDefaultTemplates`.

لماذا صارت `pending`؟ لأن `ensureTemplate`/`getTemplateStatus` استخدما نفس التوكن الخاطئ (توكن ES) على WABA نابو `1207428308207884`، ففشلا في إثبات الاعتماد، فكُتبت `pending`.

**يقين: المشكلة 2 نتيجة مباشرة للمشكلة 1، وليست سبباً مستقلاً عن الرقم في واتساب.**

---

## 6) ما ليس المشكلة (مرفوض بالأدلة)

| الفرضية | الحكم | لماذا |
|---|---|---|
| الرقم مقفل أو الرسوم غير مسددة | مرفوض لفشل اليوم | خطأ Graph يتحدث عن صلاحية الكائن للتوكن، لا عن billing. لو الرقم نفسه ميتاً لفشل الجميع بلا توكن ES أيضاً. |
| خطأ `#131031 Business Account locked` | متعلق بمسار آخر | ظهر 27 أكتوبر على مزود `cloud_api` (رقم المحل عبر ES)، لا على إرسال `dualhook` اليوم. |
| المحفظة فارغة | مرفوض | رصيد باقر 144، `send_blocked=false`, `frozen=false`. والخصم يحدث حتى في بعض محاولات الفشل. |
| إلغاء المستخدم | موجود لكنه ثانوي | `dismissed_by_user` من شاشة التأكيد في التطبيق. لا يفسّر فشل Graph ولا `preparing`. |
| تعطل عام في Graph API version | مرفوض | نفس معرّف الهاتف يُرفض فقط مع توكن المستأجر، لا كتفسير عام. |
| ربط الصف في DB خاطئ | مرفوض كسبب وحيد | الصف يشير فعلاً إلى `1206931799175422` ورقم `3735`. الخطأ أن التوكن المرافق غير مطابق. |

---

## 7) الجدول الزمني السببي لباقر (28 أكتوبر)

1. قبلها: تجارب `cloud_api` / ES حفظت توكن محل في `whatsapp_provider_secrets`.
2. 10:20 UTC: `set_provider cloud_api→dualhook` ثم ربط رقم نابو.
3. الربط كتب أصول نابو في الصف واستدعى ضمان القوالب.
4. القوالب تحت `dualhook` صارت `pending` (قراءة Graph بتوكن المحل فشلت أو لم تُثبت الاعتماد).
5. محاولات إرسال بطاقة:
   - أولاً `not_ready:preparing` (حاجز الجاهزية).
   - ثم إن تجاوزت طبقة ما أو أُعيدت: Graph يرفض `1206931799175422` بتوكن المحل.
6. محاولات أخرى أُلغيت من شاشة التأكيد (`dismissed_by_user`).

آخر إيصال ناجح لباقر عبر `dualhook`: 24 أكتوبر 15:55.  
بعد 25 أكتوبر لا توجد `delivered` عبر `dualhook` في العيّنة المدروسة.

---

## 8) أين حصلت المشكلة في التحديثات

ليست عطلاً عشوائياً في واتساب. هي تقاطع مسارين صُمّما كل على حدة:

| المسار | السلوك |
|---|---|
| Embedded Signup لرقم المحل | يحفظ `access_token` تحت `provider=cloud_api` للمستأجر |
| رقم نابو الرسمي `dualhook` | يفرض phone/waba نابو، ويعيد استخدام `resolveCloudToken(tenant)` |

قبل تجارب ES الكثيفة، معظم مستخدمي رقم نابو **لم يكن** لديهم سر `cloud_api`، فكانوا يسقطون إلى `WHATSAPP_CLOUD_TOKEN` العام فيعمل الإرسال.

بعد تجارب ES ثم العودة لرقم نابو، بقي التوكن الشخصي أولوية دائمة، فانكسر الإرسال **فقط** لهؤلاء المستأجرين.

الملفات الجوهرية:

- `supabase/functions/whatsapp-gateway/cloud_api.ts` — أولوية التوكن
- `supabase/functions/whatsapp-gateway/providers/dualhook_transport.ts` — فرض رقم نابو
- `supabase/functions/whatsapp-gateway/providers/meta_cloud_transport.ts` — الإرسال/القوالب بنفس `resolveCloudToken`
- `supabase/functions/whatsapp-gateway/lifecycle/connect_service.ts` — ربط dualhook بدون مسح السر
- `supabase/functions/whatsapp-gateway/lifecycle/ready_state.ts` — جاهزية على قوالب المزود الحالي
- `supabase/functions/whatsapp-gateway/lifecycle/template_lifecycle_service.ts` — إعادة كتابة القوالب إلى pending
- `supabase/functions/whatsapp-gateway/provider.ts` — تنظيف QR فقط، لا الأسرار

---

## 9) المشكلة بصياغة واحدة (للتثبيت)

عند الإرسال من رقم نابو الرسمي، الخادم يضع معرّف هاتف نابو في طلب Graph، لكنه يوقّع الطلب بتوكن Embedded Signup الخاص بالمحل إن وُجد في أسرار المستأجر. هذا التوكن لا يملك صلاحية على رقم نابو، فيرفض Graph الطلب. وبسبب نفس التوكن، إعادة ضمان القوالب تكتب بطاقة الغيار `pending` تحت `dualhook` فيُحجب الإرسال أيضاً برسالة `not_ready:preparing`.

---

## 10) الحل الصحيح 100% — مع عزل مسار رقم المحل الخاص

### المبدأ الحاكم

مساران مستقلان في التوكن، مثل رقمين مختلفين في الواقع:

| المسار | من يملك الرقم | أي توكن يُستخدم دائماً | أين يُحفظ |
|---|---|---|---|
| رقم المحل الخاص (`cloud_api` + ES / coexistence) | المستأجر | توكن ES الخاص بالمستأجر فقط | `whatsapp_provider_secrets` تحت `cloud_api` |
| رقم نابو الرسمي (`dualhook` / `ycloud` + `SHARED_SENDER_*`) | نابو | توكن نابو العام فقط | `WHATSAPP_CLOUD_TOKEN` (أو `SHARED_SENDER_TOKEN` إن أُضيف لاحقاً) |

القاعدة الذهبية: **معرّف الهاتف وتوكن التوقيع يجب أن يكونا لنفس المالك.**  
رقم نابو + توكن محل = فشل. رقم المحل + توكن نابو = خطر على خصوصية/صلاحيات المحل وقد يكسر ES. لذلك لا نخلط أبداً.

### قيد إلزامي من المالك

**كل الإصلاح على السيرفر فقط.**  
التطبيق (APK/AAB) مرفوع ومنتهٍ — **ممنوع** أي تعديل Flutter / شاشات الربط / واجهة الإرسال.  
النشر = Edge Functions (`whatsapp-gateway` وما يلزم من نفس الطبقة) + إن لزم تصحيح صفوف DB. لا تحديث متجر.

### ما يُمنع صراحة (حتى لو بدا إصلاحاً سريعاً)

1. **لا تلمس ملفات التطبيق** (`lib/**`, pubspec, شاشات واتساب، إلخ).
2. **لا تمس `resolveCloudToken` الافتراضي لمسار `cloud_api`.** ترتيب الأولوية الحالي (سر المستأجر → توكن خاص بالمستخدم → عام) يبقى لكل استدعاء يخص رقم المحل.
3. **لا تحذف توكن ES من `whatsapp_provider_secrets` عند التحويل إلى رقم نابو.** حذفه يكسر الرجوع لاحقاً لرقم المحل دون إعادة ES، ويُعد تدخلاً في مسار رقم المحل.
4. **لا تجعل تغييراً شاملاً في `resolveCloudToken(userId)` يخلط المسارين بلا عزل.** خطر على قراءة الاسم، mark-as-read، قوالب ES، webhook.
5. **لا تغيّر أرقام/WABA نابو على Meta ولا الرسوم.**

### ما يُنفَّذ فقط (جراحي — سيرفر)

**أ) دالة توكن منفصلة للمرسِل المشترك** داخل `whatsapp-gateway`

- إضافة شيء بمفهوم: `resolveSharedSenderToken()`  
  تقرأ فقط توكن نابو (`WHATSAPP_CLOUD_TOKEN` أو سر مشترك مخصّص).  
  **لا** تستدعي `readProviderSecret(..., 'cloud_api', 'access_token')`.

**ب) مسار `dualhook_transport` فقط** (و`ycloud` إن كان نفس SHARED_SENDER)

كل عمليات Graph على رقم نابو بتوكن نابو فقط: إرسال قالب/نص، `ensureTemplate` / `getTemplateStatus`.  
تمرير توكن صريح أو استدعاء Graph مباشرة — **بدون** أولوية سر المستأجر.

**ج) مسار `meta_cloud_transport` / `cloud_api` كما هو**

- ES يحفظ توكن المستأجر كما اليوم.
- إرسال رقم المحل بتوكن المحل كما اليوم.
- لا تغيير في تطبيق العميل.

**د) إصلاح بيانات المتأثرين فقط (بعد أ–ج، على السيرفر/SQL)**

- مزامنة قوالب `provider = dualhook` بتوكن نابو للمستأجرين العالقين.
- **لا تعدّل** صفوف `cloud_api` ولا أسرار `access_token`.

بهذا يعمل التطبيق المرفوع كما هو: يستدعي نفس الـ gateway، والخادم يصحّح اختيار التوكن خلفه.

### لماذا هذا لا يؤثر على من يريدون رقمهم الخاص

| سيناريو | بعد الإصلاح |
|---|---|
| محل جديد يختار ES / coexistence لرقمه | كما اليوم عبر نفس التطبيق المرفوع |
| محل مربوط `cloud_api` ويعمل الآن | لا تغيير في `resolveCloudToken` ولا أسراره |
| محل جرّب ES ثم عاد لرقم نابو (باقر) | الإرسال بتوكن نابو؛ سر ES يبقى بلا استخدام خاطئ |
| محل على رقم نابو بلا ES | كما كان |
| محل يرجع لاحقاً لرقم محله | سر ES موجود؛ مسار `cloud_api` يقرأه كالمعتاد |

### ترتيب التنفيذ المقترح عند الإذن لاحقاً

1. تعديل `whatsapp-gateway` فقط: `resolveSharedSenderToken` + ربطه بـ `dualhook`.
2. نشر Edge Function — **بدون** رفع تطبيق جديد.
3. مزامنة قوالب `dualhook` للمتأثرين.
4. اختبار إرسال من حساب (سر ES + dualhook) ومن حساب `cloud_api` برقم خاص.

أي إصلاح يكتفي بمسح الواجهة دون فصل مصدر التوكن سيعيد نفس خطأ Graph.

---

## 11) معايير النجاح بعد الإصلاح (لاحقاً)

**رقم نابو (يجب أن تتحقق):**

- إرسال بطاقة من حساب باقر على `dualhook` → `delivered`/`sent` بلا خطأ `1206931799175422`.
- اختفاء `not_ready:preparing` بعد اعتماد صفوف قوالب `dualhook`.
- حساب بلا توكن ES على رقم نابو يبقى يعمل.

**رقم المحل الخاص (يجب ألا تتأثر — اختبار ارتداد إلزامي):**

- حساب على `cloud_api` ما زال يقرأ سره من `whatsapp_provider_secrets` ويرسل برقم محله.
- إكمال ES جديد ما زال يحفظ `access_token` تحت `cloud_api`.
- صفوف قوالب `provider=cloud_api` لا تُمس عند إصلاح المتأثرين على رقم نابو.
- سر ES للمستأجر الذي عاد لرقم نابو **لا يُحذف**.

---

## 12) خلاصة للمالك

الرقم الرسمي سليم. واتساب يقول: «هذا التوكن لا يملك هذا الهاتف».  
نحن بعد تجارب الربط الرسمي صرنا نرسل رقم نابو بتوكن محل. هذه هي المشكلة.

الحل الحقيقي: توكنان معزولان — توكن نابو لرقم نابو فقط، وتوكن المحل لرقم المحل فقط — **بدون مسح أسرار من جرّبوا ربط رقمهم الخاص**.
