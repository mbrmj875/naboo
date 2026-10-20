# إصلاح n8n — واتساب غيار الزيت (نسخ ولصق)

> **المشكلة الحالية:** عقدة **Respond to Webhook** تُرجع نصاً خاماً  
> `{"ok":"={{ $json.ok }}"}` بدل القيم الحقيقية — فيظهر في التطبيق «تعذّر الإرسال من رقم المحل».

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

return [{
  json: {
    instanceName,
    phone: digits,
    order,
    order_id: body.order_id ?? null,
    message_text: messageText,
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

if (fromApp.length > 0) {
  return [{
    json: {
      phone: prev.phone,
      order: prev.order,
      order_id: prev.order_id,
      instanceName: prev.instanceName,
      message_text: fromApp,
      source: 'app',
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
  },
}];
```

---

## 3) Code in JavaScript2 (إرسال WhatsApp + soft reconnect)

> انسخ محتوى الملف `infra/hostinger/evolution-send-node.js` كاملاً إلى عقدة **Code**.
> المنطق: إن كانت الجلسة ليست `open` → `restart` + استطلاع حتى ~12ث → ثم `sendText`.
> عند فشل إرسال بسبب disconnect → إعادة soft reconnect ثم محاولة إرسال واحدة.
> الاستجابة تتضمن `soft_reconnect` و `soft_reconnect_elapsed_ms`.

```javascript
// انظر: infra/hostinger/evolution-send-node.js
```

**بديل مختصر** إن بقيت عقدة HTTP القديمة: أضف قبلها Code يتحقق من `connectionState` ويستدعي `/instance/restart/{instance}` ثم ينتظر 3–5 ثوانٍ قبل الإرسال.

---

## 4) Respond to Webhook — **مهم جداً**

1. افتح العقدة **Respond to Webhook**
2. **Response Body** → اختر **JSON**
3. الصق هذا (بدون علامات `={{` في النص — استخدم **Expression** لكل حقل):

```json
{
  "ok": {{ $json.ok }},
  "reason": "{{ $json.reason || '' }}",
  "sent_to": "{{ $json.sent_to || '' }}"
}
```

**أو** استبدل العقدة بـ **Code** قبل Respond:

```javascript
return [{
  json: {
    ok: $input.first().json.ok === true,
    reason: $input.first().json.reason || '',
    sent_to: $input.first().json.sent_to || '',
  },
}];
```

ثم Respond → **First Incoming Item** → JSON.

---

## 5) Publish

اضغط **Publish** بعد التعديل.

---

## 6) اختبار سريع

```bash
curl -X POST 'https://n8n-nrwn.srv1769126.hstgr.cloud/webhook/oil-change-notify' \
  -H 'Content-Type: application/json' \
  -d '{
    "webhook_secret":"NaBoo_WA_2026_xK9mP2",
    "customer_phone":"078XXXXXXXX",
    "instance_name":"shop_30eb3d89_918f_4d58_aed0_0fff52d9f1f8",
    "order":{"customer_name":"اختبار","store_name":"محل"}
  }'
```

**النتيجة الصحيحة:** `{"ok":true,"reason":"","sent_to":"96478..."}`  
**النتيجة الخاطئة:** `{"ok":"={{ $json.ok }}"}` ← Respond معطّل

---

## ملاحظة عن Evolution

- **`shop_basra_1`** = instance قديم للاختبار — **منفصل** (تجاهله)
- **`shop_30eb3d89_...`** = instance حسابك — **متصل** ✓
- التطبيق يرسل `instance_name` الصحيح تلقائياً
