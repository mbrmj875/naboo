# إصلاح n8n — واتساب غيار الزيت (نسخ ولصق)

> **المشكلة الحالية:** عقدة **Respond to Webhook** تُرجع نصاً خاماً  
> `{"ok":"={{ $json.ok }}"}` بدل القيم الحقيقية — فيظهر في التطبيق «تعذّر الإرسال من رقم المحل».
>
> **PDF:** التطبيق يرسل `pdf_base64` مع الرسالة. إن بقيت عقدة الإرسال على `sendText` فقط  
> ستصل الرسالة النصية بدون ملف. حدّث **العقد الثلاث** أدناه ثم **Publish**.

---

## 1) Code in JavaScript (التحقق)

```javascript
const body = $input.first().json.body ?? $input.first().json;

const secret = 'NaBoo_WA_2026_xK9mP2';
if (body.webhook_secret !== secret) {
  throw new Error('UNAUTHORIZED');
}

const phone = (body.customer_phone ?? '').toString().trim();
const order = body.order ?? {};
if (!phone) throw new Error('MISSING customer_phone');

let digits = phone.replace(/\D/g, '');
if (digits.startsWith('0')) digits = '964' + digits.slice(1);
else if (digits.length === 10 && digits.startsWith('7')) digits = '964' + digits;

const instanceName = (body.instance_name ?? '').toString().trim()
  || 'shop_30eb3d89_918f_4d58_aed0_0fff52d9f1f8';

const messageText = (body.message_text ?? '').toString().trim();
const pdfBase64 = (body.pdf_base64 ?? '').toString().trim();
const pdfFilename = (body.pdf_filename ?? 'oil_change_service.pdf').toString().trim();
const pdfMimetype = (body.pdf_mimetype ?? 'application/pdf').toString().trim();

return [{
  json: {
    instanceName,
    phone: digits,
    order,
    order_id: body.order_id ?? null,
    message_text: messageText,
    pdf_base64: pdfBase64,
    pdf_filename: pdfFilename,
    pdf_mimetype: pdfMimetype,
    apiBody: {
      model: 'deepseek-chat',
      temperature: 0.3,
      messages: [
        {
          role: 'system',
          content: 'أنت كاتب رسائل واتساب لمركز غيار زيت في العراق. اكتب بالعربية بأسلوب ودود ومهني. استخدم الأرقام من JSON فقط.',
        },
        {
          role: 'user',
          content: 'اكتب رسالة واتساب:\n' + JSON.stringify(order, null, 2),
        },
      ],
    },
  },
}];
```

---

## 2) Code in JavaScript1 (رسالة التطبيق أو DeepSeek)

```javascript
const prev = $input.first().json;
const fromApp = (prev.message_text ?? '').toString().trim();

const pdfFields = {
  pdf_base64: (prev.pdf_base64 ?? '').toString().trim(),
  pdf_filename: (prev.pdf_filename ?? 'oil_change_service.pdf').toString().trim(),
  pdf_mimetype: (prev.pdf_mimetype ?? 'application/pdf').toString().trim(),
};

if (fromApp.length > 0) {
  return [{
    json: {
      phone: prev.phone,
      order: prev.order,
      order_id: prev.order_id,
      instanceName: prev.instanceName,
      message_text: fromApp,
      source: 'app',
      ...pdfFields,
    },
  }];
}

const response = await this.helpers.httpRequest({
  method: 'POST',
  url: 'https://api.deepseek.com/chat/completions',
  headers: {
    Authorization: 'Bearer sk-8ce9b00b1ce74d658868d9cc1da3fdb9',
    'Content-Type': 'application/json',
  },
  body: prev.apiBody,
  json: true,
  timeout: 30000,
});

const text = response.choices?.[0]?.message?.content?.trim()
  ?? 'مرحباً، شكراً لزيارتكم.';

return [{
  json: {
    phone: prev.phone,
    order: prev.order,
    order_id: prev.order_id,
    instanceName: prev.instanceName,
    message_text: text,
    source: 'deepseek',
    ...pdfFields,
  },
}];
```

---

## 3) Code in JavaScript2 (إرسال WhatsApp — نص أو PDF)

> إن فشل إرسال PDF يُرجع للنص تلقائياً حتى لا تضيع الرسالة على الزبون.
> انظر حقل `detail` في المخرجات لمعرفة سبب فشل Evolution.

```javascript
const prev = $input.first().json;
const instance = prev.instanceName;
const evolutionBase = ($env.EVOLUTION_BASE_URL || 'http://72.61.191.237:8080').replace(/\/$/, '');
const apiKey = $env.EVOLUTION_API_KEY || 'Ev0_Naboo_72aB91cD3eF4gH5iJ';
const pdf = (prev.pdf_base64 || '').toString().trim();
const fileName = (prev.pdf_filename || 'oil_change_service.pdf').toString().trim();
const mime = (prev.pdf_mimetype || 'application/pdf').toString().trim();

// Evolution v2.3.7: media = base64 خام أو URL فقط — ممنوع data URI
const rawB64 = pdf.replace(/^data:[^;]+;base64,/, '').trim();
let pdf_bytes_est = 0;
if (rawB64) {
  const padding = rawB64.endsWith('==') ? 2 : rawB64.endsWith('=') ? 1 : 0;
  pdf_bytes_est = Math.floor((rawB64.length * 3) / 4) - padding;
}

let ok = false;
let reason = '';
let mode = 'text';
let detail = '';

async function sendText() {
  await this.helpers.httpRequest({
    method: 'POST',
    url: `${evolutionBase}/message/sendText/${instance}`,
    headers: {
      apikey: apiKey,
      'Content-Type': 'application/json',
    },
    body: {
      number: prev.phone,
      text: prev.message_text,
    },
    json: true,
    timeout: 30000,
  });
}

async function sendPdf() {
  await this.helpers.httpRequest({
    method: 'POST',
    url: `${evolutionBase}/message/sendMedia/${instance}`,
    headers: {
      apikey: apiKey,
      'Content-Type': 'application/json',
    },
    body: {
      number: prev.phone,
      mediatype: 'document',
      mimetype: mime,
      caption: prev.message_text,
      media: rawB64,
      fileName,
      filename: fileName,
    },
    json: true,
    timeout: 60000,
  });
}

try {
  if (rawB64) {
    try {
      await sendPdf.call(this);
      mode = 'pdf';
    } catch (e) {
      detail = (e.message || String(e)).slice(0, 400);
      await sendText.call(this);
      mode = 'text_after_pdf_fail';
    }
  } else {
    await sendText.call(this);
    mode = 'text';
  }
  ok = true;
} catch (e) {
  detail = (e.message || String(e)).slice(0, 400);
  const msg = detail.toLowerCase();
  if (msg.includes('disconnect') || msg.includes('not connected') || msg.includes('closed')) {
    reason = 'whatsapp_disconnected';
  } else if (msg.includes('timeout') || msg.includes('timed out')) {
    reason = 'timeout';
  } else if (msg.includes('401') || msg.includes('403')) {
    reason = 'unauthorized';
  } else if (msg.includes('429') || msg.includes('rate')) {
    reason = 'rate_limited';
  } else {
    reason = 'evolution_error';
  }
}

return [{
  json: {
    ok,
    reason,
    mode,
    detail,
    pdf_bytes_est,
    tenant_id: prev.tenant_id,
    order_id: prev.order_id,
    source: prev.source,
    sent_to: prev.phone,
  },
}];
```

---

---

## 4) Respond to Webhook — **مهم جداً**

1. افتح العقدة **Respond to Webhook**
2. **Response Body** → اختر **JSON**
3. الصق هذا (بدون علامات `={{` في النص — استخدم **Expression** لكل حقل):

```json
{
  "ok": {{ $json.ok }},
  "reason": "{{ $json.reason || '' }}",
  "sent_to": "{{ $json.sent_to || '' }}",
  "mode": "{{ $json.mode || '' }}"
}
```

**أو** استبدل العقدة بـ **Code** قبل Respond:

```javascript
return [{
  json: {
    ok: $input.first().json.ok === true,
    reason: $input.first().json.reason || '',
    sent_to: $input.first().json.sent_to || '',
    mode: $input.first().json.mode || '',
  },
}];
```

ثم Respond → **First Incoming Item** → JSON.

---

## 5) Publish

اضغط **Publish** بعد التعديل.

---

## 6) اختبار سريع

نص فقط:

```bash
curl -X POST 'https://n8n-nrwn.srv1769126.hstgr.cloud/webhook/oil-change-notify' \
  -H 'Content-Type: application/json' \
  -d '{
    "webhook_secret":"NaBoo_WA_2026_xK9mP2",
    "customer_phone":"078XXXXXXXX",
    "instance_name":"shop_30eb3d89_918f_4d58_aed0_0fff52d9f1f8",
    "message_text":"اختبار نص",
    "order":{"customer_name":"اختبار","store_name":"محل"}
  }'
```

مع PDF صغير (Base64 لملف PDF حقيقي):

```bash
# حضّر base64 ثم ضعه في الحقل pdf_base64
# النتيجة الصحيحة تتضمن "mode":"pdf"
```

**النتيجة الصحيحة:** `{"ok":true,"reason":"","sent_to":"96478...","mode":"pdf"}`  
**نص فقط بدون ملف:** `"mode":"text"` ← إما لم يصل `pdf_base64` أو العقدة القديمة  
**النتيجة الخاطئة:** `{"ok":"={{ $json.ok }}"}` ← Respond معطّل

---

## ملاحظة عن Evolution

- **`shop_basra_1`** = instance قديم للاختبار — **منفصل** (تجاهله)
- **`shop_30eb3d89_...`** = instance حسابك — **متصل** ✓
- التطبيق يرسل `instance_name` الصحيح تلقائياً
- ملف PDF يُرسل عبر `POST /message/sendMedia/{instance}` كـ `document` مع  
  `media: data:application/pdf;base64,...`
