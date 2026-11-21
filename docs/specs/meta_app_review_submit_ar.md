# تقديم App Review + Live — مسار Meta مباشرة (Tech Provider)

**آخر تحديث:** سبتمبر 2026  
**الحالة:** حزمة التقديم جاهزة — التنفيذ اليدوي في Meta App Dashboard  
**الصلاحيتان:** `whatsapp_business_management` + `whatsapp_business_messaging`  
**المرجع الرسمي:** [WhatsApp Embedded Signup — App Review](https://developers.facebook.com/docs/whatsapp/embedded-signup/app-review/) · [Become a Tech Provider](https://developers.facebook.com/docs/whatsapp/solution-providers/get-started-for-tech-providers/)

---

## 0) ماذا يفعل هذا الدليل؟

هذا الملف = **نصوص جاهزة للنسخ** + **سيناريو فيديوهين** + **قائمة تحقق Live**.

| يفعله الفريق | لا يفعله الكود |
|--------------|----------------|
| تسجيل فيديوهين | الموافقة الآلية من Meta |
| لصق الوصف في نموذج المراجعة | تبديل Live بدون موافقة |
| طلب Advanced Access | تجاوز Business Verification |

بدون **Advanced Access** على الصلاحيتين: محلات خارج أدوار المطوّر/المختبر تفشل (غالباً خطأ Graph `200`).

---

## 1) المتطلبات قبل Submit

```
[ ] Business Verification لحافظة نابو (Verified)
[ ] تطبيق Meta مربوط بنفس الحافظة — Use case: WhatsApp
[ ] Tech Provider onboarding بدأ من App Dashboard → WhatsApp → Quickstart
[ ] ES Config ID فعّال: 952460887300588
[ ] صفحة ES حية: https://naboo-admin.vercel.app/whatsapp-meta-es.html
[ ] Redirect URI / Allowed Domains: naboo-admin.vercel.app
[ ] حساب اختبار محل (ليس حساب مالك التطبيق) + رقم جاهز لرسالة تجريبية
[ ] مسار الربط في نابو يعمل حتى «جاهز» على حساب مختبر
```

### إعدادات ثابتة (لا تلصق الأسرار)

| المفتاح | القيمة العامة |
|---------|---------------|
| App ID | `1717499336127535` |
| ES Config ID (v4) | `952460887300588` |
| صفحة ES | `https://naboo-admin.vercel.app/whatsapp-meta-es.html` |
| Package Android | `com.basra.storemanager` |

أسرار الخادم فقط عبر:

```bash
# لا تلصق القيم هنا — عيّنها في البيئة فقط
supabase secrets set META_APP_ID=…
supabase secrets set META_APP_SECRET=…
supabase secrets set META_ES_CONFIG_ID=952460887300588
supabase secrets set META_ES_PAGE_URL=https://naboo-admin.vercel.app/whatsapp-meta-es.html
```

### جذر قديم: ظهور شيفرة HTML

Edge Functions تعيد `text/html` كنص عادي. الصفحة يجب أن تبقى ثابتة على Vercel:  
`admin-web/public/whatsapp-meta-es.html` → `https://naboo-admin.vercel.app/whatsapp-meta-es.html`

---

## 2) الصلاحيتان — نصوص جاهزة للنموذج (إنجليزي — Meta تقرأه)

الصق كل نص تحت طلب الصلاحية المقابلة. لا تطلب صلاحيات إضافية (`business_management` يدوي، إلخ).

### A) `whatsapp_business_messaging`

**How will your app use this permission?**

```
Naboo is an ERP for Iraqi oil-change / auto workshops. Shop owners onboard their own
WhatsApp Business phone number via WhatsApp Embedded Signup (Facebook Login for Business
config_id). After onboarding, Naboo’s server (Supabase Edge) uses Cloud API to send
Utility template messages on behalf of that shop’s WABA/phone_number_id only:

• Service completion confirmation
• Parts / oil-change card summary
• Maintenance reminder

Shop staff trigger sends from the Naboo Android app after a service job. Customers receive
the message on WhatsApp. We never use a shared sender for this Meta Direct path; each
tenant stores its own token and phone_number_id. No marketing blasts in this review scope.
```

### B) `whatsapp_business_management`

**How will your app use this permission?**

```
After Embedded Signup, Naboo receives access to the client shop’s WhatsApp Business Account
(WABA). We use whatsapp_business_management to:

• Subscribe our app’s webhook to the shop’s WABA
• Register the shop phone number for Cloud API
• Create and sync Utility message templates on that WABA (from Naboo’s template registry)
• Read template approval status so the shop sees “Ready” only when templates are usable

Assets belong to the shop (portfolio → WABA → phone). Naboo acts as Tech Provider and does
not move shops onto Naboo’s own WABA in this path.
```

---

## 3) الفيديوهان المطلوبان (منفصلان)

Meta تطلب **تسجيلين منفصلين** — لا تدمجهما في ملف واحد.

### فيديو 1 — Messaging (`whatsapp_business_messaging`)

**الهدف:** إرسال من نابو → ظهور الرسالة في واتساب المستلم.

| خطوة | ماذا تصوّر |
|------|------------|
| 1 | تسجيل دخول صاحب محل إلى نابو (من حالة خروج إن أمكن) |
| 2 | ربط واتساب → Meta مباشرة → إكمال ES (حافظة المحل / WABA / رقم / OTP) أو حساب مربوط مسبقاً «جاهز» |
| 3 | من شاشة تشغيلية: إرسال رسالة/بطاقة خدمة (Utility) |
| 4 | قطع واضح إلى هاتف/واتساب ويب للمستلم يعرض الرسالة الواردة |

**ملاحظات:**

- وضّح على الشاشة (تعليق نصي): «Send Utility template via Cloud API».
- بديل مقبول من Meta: استخدام cURL من App Dashboard → WhatsApp → API Setup ثم إظهار الاستلام — الأفضل إظهار نابو نفسه.

### فيديو 2 — Management (`whatsapp_business_management`)

**الهدف:** إنشاء قالب رسائل على WABA.

| خطوة | ماذا تصوّر |
|------|------------|
| 1 | WABA محل (بعد ES) أو WhatsApp Manager لنفس الحساب |
| 2 | إنشاء قالب Utility (اسم واضح مثل `service_complete_ar`) |
| 3 | إظهار أن القالب أُنشئ / بحالة Pending أو Approved |

**ملاحظات:**

- مقبول: إنشاء القالب من **WhatsApp Manager** إن لم يكن لديك UI إنشاء يدوي في التطبيق (نابو ينشئ القوالب عبر API تلقائياً بعد الربط — صوّر لحظة المزامنة أو Manager).
- وضّح: «Create message template on client WABA».

### نصائح تسجيل عامة

- لا تعتمد على لقطات شاشة فقط.
- لا تخفِ مسار منح الصلاحيات إن ظهر في ES.
- تجنّب حافظة نابو الداخلية؛ استخدم حساب محل اختبار.
- دقة معقولة، صوت غير مطلوب إن كانت التعليقات النصية واضحة.

---

## 4) مسار التقديم في لوحة Meta

1. [developers.facebook.com](https://developers.facebook.com) → تطبيق نابو (`1717499336127535`)
2. **App Review → Permissions and Features**  
   أو من **WhatsApp → Quickstart / Onboarding → Submit documentation for App Review**
3. اطلب **Advanced access** لـ:
   - `whatsapp_business_messaging`
   - `whatsapp_business_management`
4. الصق نص القسم 2 لكل صلاحية
5. ارفع فيديو 1 على messaging، فيديو 2 على management
6. **App verification details:** لطلب هاتين الصلاحيتين فقط غالباً **لا تحتاج** تعليمات اختبار مطوّلة — اتركه فارغاً أو جملة قصيرة:  
   `WhatsApp-only Advanced Access; no consumer Facebook Login test account required.`
7. Submit وانتظر قرار المراجعة

---

## 5) بعد الموافقة — Live mode

```
[ ] الصلاحيتان = Advanced Access (Approved)
[ ] App Mode = Live (ليس Development فقط)
[ ] اختبار ربط محل بحساب فيسبوك خارج أدوار Admin/Developer/Tester
[ ] رسالة Utility واحدة تصل للمستلم
[ ] webhook يستقبل أحداث التسليم (توقيع X-Hub-Signature-256 مفعّل)
```

**Development mode** يكفي لأدوار التطبيق فقط. الإنتاج الحقيقي للمحلات = Live + Advanced Access.

---

## 6) بناء APK لتصوير التجربة (اختياري)

```bash
flutter build apk --release
```

Package: `com.basra.storemanager`

أو صوّر من بناء داخلي مثبت مسبقاً طالما المسار واضح للمراجع.

---

## 7) قائمة تحقق نهائية قبل الضغط Submit

```
[ ] نص messaging جاهز ومفهوم
[ ] نص management جاهز ومفهوم
[ ] فيديو إرسال + استلام منفصل
[ ] فيديو إنشاء قالب منفصل
[ ] لا أسرار في الفيديو (لا App Secret / tokens)
[ ] Business Verification مكتمل
[ ] Config ID 952460887300588 ما زال Linked في Login for Business
```

---

## 8) مراجع داخل المستودع

- رحلة المنتج الكاملة: [`whatsapp_meta_direct_journey_complete_ar.md`](./whatsapp_meta_direct_journey_complete_ar.md)
- صفحة ES: `admin-web/public/whatsapp-meta-es.html`
- OAuth / templates: `supabase/functions/whatsapp-gateway/meta_oauth.ts`
- Webhook signature: `supabase/functions/whatsapp-cloud-webhook/meta_hub_signature.ts`
