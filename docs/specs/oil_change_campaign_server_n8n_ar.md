# حملة واتساب جماعية على السيرفر (بعد إغلاق التطبيق)

التطبيق يرفع كل الرسائل مرة واحدة إلى:
`POST …/webhook/oil-change-campaign`

ثم يرد السيرفر فوراً `{"ok":true,"accepted":N}` ويكمل الإرسال على n8n.

---

## لماذا كانت الرسالة الواحدة تصل والمجموعة لا؟

في n8n v3 عقدة **Loop Over Items** مخرجاتها:
1. `done` (أول مخرج)
2. `loop` (ثاني مخرج)

الورد القديم وصل الإرسال بمخرج `done` بالخطأ، ومع `Wait` تنكسر الحلقة عند أكثر من رسالة.
الحل: **عقدتان فقط بعد الرد** — Validate ثم Send All Sequentially (بدون Loop/Wait).

---

## 1) Workflow الصحيح (4 عقد)

```
Webhook → Validate Batch → Respond Accepted → Send All Sequentially
```

استورد الملف المحدَّث:
`infra/hostinger/n8n-oil-change-campaign-workflow.json`

أو عدّل الورد الحالي يدوياً:

### Webhook
- Method: `POST`
- Path: `oil-change-campaign`
- Respond: **Using 'Respond to Webhook' Node**
- **Publish**

### Validate Batch (Code)
اترك عقدة التحقق كما هي (تُرجع `messages` + `interval_seconds` + `instanceName`).

### Respond Accepted
Body JSON:

```json
{
  "ok": true,
  "accepted": {{ $json.accepted }},
  "instanceName": "{{ $json.instanceName }}"
}
```

### Send All Sequentially (Code) — بديل Loop + Wait

احذف عقد Split Out / One By One / Send One / Wait، والصق هذا الكود:

```javascript
const root = $input.first().json;
const messages = Array.isArray(root.messages) ? root.messages : [];
const instance = (root.instanceName || '').toString();
const evolutionBase = ($env.EVOLUTION_BASE_URL || 'http://72.61.191.237:8080').replace(/\/$/, '');
const apiKey = $env.EVOLUTION_API_KEY || 'Ev0_Naboo_72aB91cD3eF4gH5iJ';

const intervalMs = Math.max(5, Number(root.interval_seconds) || 30) * 1000;
const restEvery = Math.max(0, Number(root.rest_every_messages) || 25);
const restMs = Math.max(1, Number(root.rest_minutes) || 5) * 60 * 1000;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const results = [];
for (let i = 0; i < messages.length; i++) {
  const item = messages[i] || {};
  const phone = (item.phone || '').toString();
  const text = (item.message_text || '').toString();
  let ok = false;
  let reason = '';
  try {
    if (!phone || !text) {
      reason = 'missing_phone_or_text';
    } else {
      await this.helpers.httpRequest({
        method: 'POST',
        url: `${evolutionBase}/message/sendText/${instance}`,
        headers: {
          apikey: apiKey,
          'Content-Type': 'application/json',
        },
        body: { number: phone, text },
        json: true,
        timeout: 30000,
      });
      ok = true;
    }
  } catch (e) {
    reason = (e.message || String(e)).slice(0, 200);
  }

  results.push({
    json: {
      phone,
      message_text: text,
      order_id: item.order_id ?? null,
      customer_name: item.customer_name ?? '',
      instanceName: instance,
      send_ok: ok,
      send_reason: reason,
      index: i + 1,
      total: messages.length,
    },
  });

  if (i < messages.length - 1) {
    let waitMs = intervalMs;
    if (restEvery > 0 && (i + 1) % restEvery === 0) {
      waitMs += restMs;
    }
    await sleep(waitMs);
  }
}

return results;
```

---

## 2) Publish

بدون Publish يظهر فشل التسليم من التطبيق.

---

## 3) اختبار

```bash
curl -X POST 'https://n8n-nrwn.srv1769126.hstgr.cloud/webhook/oil-change-campaign' \
  -H 'Content-Type: application/json' \
  -d '{
    "webhook_secret":"NaBoo_WA_2026_xK9mP2",
    "instance_name":"shop_YOUR_INSTANCE",
    "interval_seconds": 8,
    "messages":[
      {"customer_phone":"07801146032","message_text":"اختبار حملة 1"},
      {"customer_phone":"07801146032","message_text":"اختبار حملة 2"}
    ]
  }'
```

الرد الفوري: `{"ok":true,"accepted":2,...}`  
ثم في Executions → **Send All Sequentially** تحقق `send_ok: true` لكل رسالة.

---

## ملاحظة

- مسار الإشعار الفردي (`oil-change-notify`) مستقل عن الحملة.
- للحملات الكبيرة جداً (ساعات): تأكد أن مهلة تنفيذ n8n على السيرفر كافية، أو خفّض `interval_seconds`.
