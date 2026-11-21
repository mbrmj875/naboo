# ربط رقم واتساب خاص بمستأجر عبر السيرفر فقط (بلا APK)

هدف التشغّيل: بعد أن تكون نسخة التطبيق تحتوي حماية الرقم الخاص، يمكن ربط أي محل (مثل العقيلي لاحقاً) برقم Meta مخصص **من السيرفر فقط** — بدون نشر تحديث جديد.

مرجع التنفيذ: Edge Function `whatsapp-ops-phone-register` + جدول `tenant_whatsapp_gateways`.

---

## حسابات مرجعية

| المحل | البريد | `tenant_user_id` | الحالة المتوقعة قبل الربط الخاص |
|--------|---------|-------------------|----------------------------------|
| خدمات الكابتن | `alkabtnkhdmat@gmail.com` | `dc50fa37-01e5-4769-9725-c79dceec9f39` | مربوط بـ `cloud_api` ورقمه الخاص (مرجع ناجح) |
| العقيلي (أويل سنتر) | `alaqeelioilcenter@gmail.com` | `cb89edb1-a4d2-45fb-9ed3-f30a14126d6b` | يبقى `dualhook` / رقم نابو المشترك حتى يُنفَّذ الربط |

WABA نابو (مرجع): `1207428308207884`  
رقم نابو المشترك (لا تستخدمه كرقم خاص): `+9647870003735`

---

## شروط قبل البدء (Meta)

1. إضافة الرقم في WhatsApp Manager تحت نفس حساب واتساب نابو.
2. إكمال تحقق SMS للرقم.
3. يفضّل أن يظهر الاسم المعروض باسم المحل (اختياري وقت الربط).
4. لا تربط الرقم بحساب مستأجر آخر في نابو.

---

## أمان الاستدعاء

لا تضع توكنات في Git.

1. أنشئ سراً مؤقتاً:

```bash
TOKEN=$(openssl rand -hex 24)
supabase secrets set PHONE_REGISTER_OPS_TOKEN="$TOKEN"
```

2. بعد انتهاء العملية:

```bash
supabase secrets unset PHONE_REGISTER_OPS_TOKEN
```

بديل: `OPS_MGMT_TOKEN` إن كان متاحاً عند المشغّل محلياً (لا يُكتب في المستودع).

Endpoint:

`POST https://<project-ref>.supabase.co/functions/v1/whatsapp-ops-phone-register`

Header: `Authorization: Bearer <PHONE_REGISTER_OPS_TOKEN>`  
(أو `x-ops-token: <TOKEN>`)

---

## الخطوات التشغيلية (العقيلي لاحقاً)

استبدل `PHONE_E164` و `PIN6` و `TOKEN` فقط. لا تغيّر `tenant_user_id` إلا إذا تأكدت من الحساب.

### 1) سرد أرقام الـ WABA

```bash
curl -sS -X POST "$SUPABASE_URL/functions/v1/whatsapp-ops-phone-register" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action":"list","waba_id":"1207428308207884"}'
```

التقط `id` (= `phone_number_id`) للرقم الجديد من النتيجة.

### 2) تسجيل Cloud API + ربط المستأجر دفعة واحدة

```bash
curl -sS -X POST "$SUPABASE_URL/functions/v1/whatsapp-ops-phone-register" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "action":"register",
    "waba_id":"1207428308207884",
    "phone_e164":"PHONE_E164",
    "pin":"PIN6",
    "bind":true,
    "tenant_user_id":"cb89edb1-a4d2-45fb-9ed3-f30a14126d6b"
  }'
```

- `PIN6`: ستة أرقام تختارها وتحفظها لصاحب المحل (تحقق بخطوتين).
- نجاح متوقع: `register.ok=true` و `bind.ok=true`.

### 3) إن كان التسجيل في Meta قد نجح سابقاً — ربط DB فقط

```bash
curl -sS -X POST "$SUPABASE_URL/functions/v1/whatsapp-ops-phone-register" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "action":"bind",
    "tenant_user_id":"cb89edb1-a4d2-45fb-9ed3-f30a14126d6b",
    "phone_number_id":"PHONE_NUMBER_ID",
    "waba_id":"1207428308207884"
  }'
```

### 4) تحقق من الصف

```sql
select whatsapp_provider, status, whatsapp_phone, cloud_phone_number_id,
       cloud_setup_status, repair_needed, updated_at
from public.tenant_whatsapp_gateways
where user_id = 'cb89edb1-a4d2-45fb-9ed3-f30a14126d6b';
```

المتوقع:

- `whatsapp_provider = cloud_api`
- `status = connected`
- `cloud_setup_status = ready`
- `whatsapp_phone` = الرقم الجديد (E.164)
- `cloud_phone_number_id` ≠ معرّف رقم نابو المشترك

### 5) على جهاز المحل

- إغلاق شاشة واتساب وإعادة فتحها، أو إعادة فتح التطبيق.
- **بدون** تنزيل تحديث إن كانت النسخة تحتوي حماية الرقم الخاص.
- عدم الضغط على «إعادة الربط الرسمي» بهدف الرجوع لرقم نابو (السيرفر يرفض `dedicated_cloud_number_locked`).

---

## حماية يجب أن تكون في نسخة التطبيق

- شاشة الربط: إن كان `cloud_api` متصل برقم خاص، «إعادة الربط الرسمي» يحدّث الحالة فقط.
- السيرفر (`whatsapp-gateway` / `set_provider`): رفض التحويل من رقم خاص جاهز إلى `dualhook`/`ycloud`.

بدون هذه النسخة، ربط السيرفر ينجح لكن زر إعادة الربط في تطبيق قديم قد يعيد رقم نابو.

---

## ما لا يُفعل

- لا تربط رقم الكابتن (`+9647722500061`) بحساب العقيلي.
- لا تمسح رقم نابو المشترك من WABA.
- لا تضع `WHATSAPP_CLOUD_TOKEN` أو PIN أو توكن Ops داخل ملفات المستودع.
