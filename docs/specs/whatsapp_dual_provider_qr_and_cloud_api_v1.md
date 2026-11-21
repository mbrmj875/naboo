# واتساب ثنائي المسار — QR (Evolution) + Cloud API الرسمي

> **الحالة:** مواصفة تنفيذ v1 — تموز 2026  
> **الهدف:** كل محل يختار إما ربط بمسح QR (غير رسمي عبر Evolution) أو واتساب الرسمي من Meta.

---

## 1) مبدأ لا يُكسر

| القاعدة | التفصيل |
|---------|---------|
| محرك QR واحد لكل رقم | ممنوع Evolution + WAHA لنفس الرقم في آن واحد |
| المساران للمستخدم | `evolution` = QR · `cloud_api` = رسمي Meta |
| WAHA | يبقى احتياطاً تقنياً (`waha`) للمختبر/الترحيل — لا يُعرض كخيار افتراضي في الواجهة |
| التبديل | عند تغيير المزود تُحذف جلسة المحرك السابق لنفس `shop_*` |

---

## 2) قيم `whatsapp_provider`

| القيمة | ماذا يرى المستخدم | المحرك |
|--------|-------------------|--------|
| `evolution` | مسح QR / رمز إقران | Evolution Baileys |
| `cloud_api` | إعداد رسمي — بدون QR يومي | Meta WhatsApp Cloud API |
| `waha` | (داخلي) | WAHA GOWS |

**الافتراضي للصفوف القديمة:** `waha` (حتى لا نكسر الجلسات الحالية فجأة).  
**اختيار «مسح QR» من التطبيق:** يضبط `evolution`.  
**اختيار «رسمي»:** يضبط `cloud_api`.

---

## 3) أعمدة البوابة

- `whatsapp_provider` text  
- `cloud_phone_number_id` text  
- `cloud_waba_id` text  
- `cloud_setup_status` text (`none` | `pending` | `ready` | `error`)  
- توكن Cloud API **لا يُخزَّن في جدول المستخدم** — في Edge secrets / خزنة مشفّرة لاحقاً (`WHATSAPP_CLOUD_TOKEN_<user>` أو جدول أسرار service_role فقط)

---

## 4) إجراءات Gateway

| action | السلوك |
|--------|--------|
| `set_provider` | `{ provider: evolution \| cloud_api \| waha }` + تنظيف المحرك الآخر |
| `qr` / `provision` | مرفوض أو رسالة عربية إن `cloud_api` |
| `send_text` | Evolution/WAHA أو Cloud API حسب المزود |
| `status` | يقرأ من المحرك المناسب |

---

## 5) مسار الرسمي (Cloud API) — مراحل

1. **الآن:** اختيار المزود في التطبيق + حفظ الإعداد + إرسال تجريبي عند جاهزية التوكن  
2. **Meta:** Business verification + رقم + قوالب رسالة غيار الزيت  
3. **لاحقاً:** Embedded Signup داخل التطبيق أو لوحة الإدارة

---

## 6) العقيلي (حالة خاصة)

بسبب تقييد واتساب على الرقم الحالي:  
**لا ترجع QR الآن.** المسار الصحيح = `cloud_api` برقم جديد بعد هدوء التقييد، أو انتظار رفع القيد ثم تقييم.

---

## 7) تشغيل Evolution على السيرفر

```bash
docker start naboo-evolution
# تأكد: لا جلسة WAHA لنفس shop_* قبل إنشاء instance على Evolution
```
