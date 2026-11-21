# تقرير تفصيلي: WAHA (WhatsApp HTTP API) — waha.devlike.pro

> **تاريخ الجمع:** 2026-07-26  
> **الموقع الرسمي:** https://waha.devlike.pro/  
> **التوثيق:** https://waha.devlike.pro/docs/  
> **GitHub:** https://github.com/devlikeapro/waha  
> **الغرض لـ NaBoo:** مرجع مقارنة / مختبر محتمل لمحرك GOWS (whatsmeow) مقابل Evolution+Baileys الحالي.

---

## 0) تذكير الأسعار (أقرأه أولاً)

| البند | الحالة منذ إصدار **2026.6.1** |
|--------|--------------------------------|
| **البرمجية نفسها** | **مجانية 100%** ومفتوحة المصدر |
| **حدود جلسات / رسائل / ميزات** | **لا حدود مدفوعة** — ما كان في «WAHA Plus» أصبح داخل Core |
| **صورة Docker** | العامة: `docker pull devlikeapro/waha` — لا حاجة لـ `waha-plus` ولا login مدفوع |
| **تبرع اختياري** | **Community = ~$5/شهر** (Patreon / Boosty / Crypto) — **بدون مزايا إضافية**؛ فقط دعم المشروع |
| **ما تدفعه عملياً** | تكلفة **VPS/سيرفرك** فقط (+ تبرع إن رغبت) |

**الخلاصة السعرية:** ليس SaaS اشتراك إجباري مثل CodeWords PRO. مجاني للتشغيل؛ التبرع رمزي اختياري.

مصادر: [Support Us](https://waha.devlike.pro/support-us/) · [WAHA Plus history](https://waha.devlike.pro/docs/how-to/waha-plus/) · [FAQ](https://waha.devlike.pro/docs/overview/faq/)

---

## 1) ما هو WAHA؟

**WAHA** = **W**hats**A**pp **H**TTP **A**PI  
واجهة REST/HTTP تثبتها على سيرفرك خلال دقائق عبر Docker، لإرسال واستقبال واتساب برمجياً.

- **ليس** تابعاً لشركة WhatsApp/Meta (تنويه رسمي في المقدمة).
- يعتمد عملاء **غير رسميين** (واتساب ويب / أجهزة مرتبطة) → خطر حظر الرقم قائم.
- للمؤسسات الحرجة يوصون هم أنفسهم بـ **Cloud API الرسمي** أو مزودين رسميين.

المقدمة: https://waha.devlike.pro/docs/overview/introduction/

---

## 2) نموذج المنتج والتسعير (تفصيل)

### قبل 2026.6.1
- **WAHA Core:** مجاني أساسي (~80% الاحتياجات).
- **WAHA Plus:** ميزات متقدمة عبر تبرع/اشتراك + صورة `devlikeapro/waha-plus` من بوابة الرعاة.

### منذ 2026.6.1 (الحالي)
- **كل ميزات Plus داخل Core** للجميع.
- لا صورة Plus منفصلة مطلوبة للميزات.
- طبقة **Community $5/mo**: دعم فقط، **لا perks**.

ما يشمله «المجاني» حسب صفحة الدعم:
- جلسات غير محدودة  
- رسائل غير محدودة  
- إرسال/استقبال نص ووسائط  
- Dashboard مدمج  
- Swagger / OpenAPI  
- محركات: WEBJS، NOWEB، GOWS  
- تخزين: ملفات، PostgreSQL، MongoDB، S3  
- أمان مدمج  
- كود مفتوح على GitHub  

مقارنة تسويقية مقابل «الآخرين» على نفس الصفحة: لاحد حسابات، on-prem، بدون سعر لكل رسالة.

---

## 3) التشغيل السريع (Quick Start)

المتطلب الوحيد: **Docker**.

```bash
docker pull devlikeapro/waha
# ARM (M1/Raspberry):
docker pull devlikeapro/waha:arm
docker tag devlikeapro/waha:arm devlikeapro/waha

# توليد .env (مستخدم/كلمة مرور/API key)
docker run --rm -v "$(pwd)":/app/env devlikeapro/waha init-waha /app/env

# تشغيل تجريبي (ليس إنتاجاً آمناً)
docker run -it --env-file "$(pwd)/.env" \
  -v "$(pwd)/sessions:/app/.sessions" \
  --rm -p 3000:3000 --name waha devlikeapro/waha
```

ثم:
1. Dashboard: `http://localhost:3000/dashboard`  
2. ربط الجلسة → حالة `SCAN_QR` → مسح QR من الجوال → `WORKING`  
3. إرسال: `POST /api/sendText` مع هيدر `X-Api-Key`

مثال إرسال:

```bash
curl -X POST 'http://localhost:3000/api/sendText' \
  -H 'Content-Type: application/json' \
  -H "X-Api-Key: YOUR_KEY" \
  -d '{"chatId":"9647XXXXXXXX@c.us","text":"Hi","session":"default"}'
```

دليل: https://waha.devlike.pro/docs/overview/quick-start/

**تنبيه الموقع:** أمر Quick Start للاختبار فقط؛ للإنتاج اتبع Install & Update + Security.

---

## 4) Dashboard (الصفحة التي سألت عنها)

الوثيقة: https://waha.devlike.pro/docs/how-to/dashboard/

### الوصول
- المسار: `http://HOST:3000/dashboard`
- افتراضي سابقاً: `admin/admin` أو `waha/waha` — مع `init-waha` تُولَّد قيم قوية في `.env`

### إعدادات البيئة
| المتغير | المعنى |
|---------|--------|
| `WAHA_DASHBOARD_ENABLED` | تفعيل/تعطيل (افتراضي true) |
| `WAHA_DASHBOARD_USERNAME` | اسم الدخول |
| `WAHA_DASHBOARD_PASSWORD` | كلمة المرور |

### وظائف الواجهة (حسب التوثيق)
1. **إدارة الجلسات** — إنشاء/بدء/إيقاف/QR  
2. **إدخال API Key** للاتصال بالسيرفر من الـ Dashboard  
3. **API Keys** — إنشاء مفاتيح admin أو مفاتيح مقيّدة بجلسة + صلاحيات (scopes)  
4. **Event Monitor** — `…/dashboard/event-monitor` لمراقبة الأحداث لحظياً  
5. **Chat UI** — واجهة محادثة تجريبية (Vue3 + PrimeVue؛ كودها على GitHub) لإثبات قدرات الـ API  
6. **ربط Dashboard واحد بعدة سيرفرات** — مفيد عند sharding لـ 50+ جلسة  

### مفاتيح الجلسة (Scopes)
من وثيقة الأمان المرتبطة بالـ Dashboard:
- `read` · `send` · `control` · `setting` · `app` · `delete`  
- مفاتيح admin لكل الجلسات؛ مفاتيح session لجلسة واحدة  
- مفاتيح مخصّصة: media-only، control-only (للـ QR/لقطة بدون كشف المفتاح الكامل)

---

## 5) المحركات (Engines) — جوهر الفرق مع Evolution

الوثيقة: https://waha.devlike.pro/docs/how-to/engines/  
GOWS: https://waha.devlike.pro/docs/engines/gows/

**فكرة WAHA:** طبقة Node.js موحّدة (REST + webhooks) فوق عدة محركات. التبديل عبر:

```bash
WHATSAPP_DEFAULT_ENGINE=GOWS   # أو WEBJS | WPP | NOWEB
```

تحذيرهم: استجابات API والـ webhooks **قد تختلف** بين المحركات — اختبر قبل التبديل.

| المحرك | التقنية | متصفح؟ | ملاحظة |
|--------|---------|--------|--------|
| **WEBJS** | whatsapp-web.js + Puppeteer | نعم | أقرب لسلوك واتساب ويب |
| **WPP** | WPPConnect + wa-js + Puppeteer | نعم | متصفح أيضاً |
| **NOWEB** | Baileys (WebSocket) | لا | أخف؛ يشبه عائلة Evolution |
| **GOWS** | Go + **whatsmeow** عبر gRPC | لا | «جيل جديد»؛ مرشح بديل NOWEB؛ أوفر CPU/RAM |
| **VENOM** | (مذكور في فهرس المحركات) | — | محرك إضافي في القائمة |

### تشغيل GOWS
```bash
docker run -v `pwd`/.sessions:/app/.sessions \
  -e "WHATSAPP_DEFAULT_ENGINE=GOWS" devlikeapro/waha
```

صور Docker مرتبطة بالمحرك (من جدول Engines):
- `devlikeapro/waha:latest` — x86 + Chromium  
- `waha:chrome` — Chrome (فيديو)  
- `waha:noweb` — بدون متصفح  
- `waha:gows` — بدون متصفح / Go  
- `waha:arm` — ARM  

### عزل تخزين المحركات
- `WAHA_NAMESPACE` — تطبيقات/مفاتيح مشتركة  
- `WAHA_SESSION_NAMESPACE` — بيانات الجلسة (لا تغيّره عادةً — غير متوافق خلفياً)

لـ GOWS متغيرات متقدمة لمزامنة التاريخ (تقليل bandwidth)، و`GODEBUG=netdns=…` لمشاكل DNS.

---

## 6) الأمان (Security)

الوثيقة: https://waha.devlike.pro/docs/how-to/security/

- **لا تعرض الـ API على الإنترنت العام** بدون حماية.  
- هيدر إلزامي موصى به: `X-Api-Key: …`  
- `WAHA_API_KEY` كنص أو `sha512:{hash}` (أفضل).  
- حماية Dashboard وSwagger بكلمات مرور منفصلة.  
- HTTPS عبر Nginx مفضّل (HTTPS مدمج deprecated نسبياً).  
- HMAC للـ webhooks.  
- يمكن تعطيل الأمان صراحةً (`WAHA_NO_API_KEY` إلخ) — غير مستحسن.

---

## 7) قدرات المنتج (خريطة التوثيق)

من فهرس الموقع — وحدات How-to الرئيسية:

| المجال | أمثلة |
|--------|------|
| جلسات | Sessions — بدء/إيقاف/QR/logout |
| إرسال | نص، وسائط، … |
| استقبال | webhooks / أحداث |
| أحداث | Events + Event Monitor |
| محادثات/جهات/مجموعات/قنوات/حالة/استطلاعات/تواجد/تسميات | APIs متخصصة |
| مكالمات | Calls |
| بروكسي | Proxy |
| تخزين | File / Postgres / Mongo / S3 |
| مراقبة | Observability |
| تطبيقات | Chatwoot، Reject Calls، **MCP** |
| تكاملات | **n8n**, Typebot, Chatwoot, LHC, Uptime Kuma، أمثلة C#/Go/Java/JS/PHP/Python |

Dashboard Chat UI يعتمد على: Chats API + Send + ACK + WebSockets.

---

## 8) مقارنة سريعة مع ما لدى NaBoo (Evolution)

| | **Evolution عندكم** | **WAHA** |
|--|---------------------|----------|
| التثبيت | Docker لديكم (Hostinger) | Docker أيضاً |
| REST | نعم | نعم |
| المحرك الافتراضي | **Baileys** | اختيار: WEBJS / WPP / **NOWEB=Baileys** / **GOWS=whatsmeow** |
| Dashboard | Evolution Manager | WAHA Dashboard مدمج |
| n8n | مستخدم عندكم | تكامل رسمي موثّق |
| السعر | مجاني + VPS | مجاني + VPS (+ تبرع $5 اختياري) |
| قيمة التجربة لـ NaBoo | الإنتاج الحالي | **مختبر GOWS** بدون CodeWords |

---

## 9) تحذيرات وحدود يجب تذكّرها

1. غير رسمي → خطر حظر (صفحة Avoid Blocking في التوثيق).  
2. Quick Start ≠ إنتاج.  
3. تبديل المحرك قد يكسر توافق الـ payload.  
4. جلسات المحركات معزولة تخزينياً — لا تفترض نقل QR بين Baileys وGOWS بدون إعادة ربط.  
5. التبرع $5 لا يشتري ميزات بعد 2026.6.1.

---

## 10) روابط مرجعية سريعة

| الموضوع | الرابط |
|---------|--------|
| الرئيسية / Docs | https://waha.devlike.pro/ |
| مقدمة | https://waha.devlike.pro/docs/overview/introduction/ |
| Quick Start | https://waha.devlike.pro/docs/overview/quick-start/ |
| Dashboard | https://waha.devlike.pro/docs/how-to/dashboard/ |
| Engines | https://waha.devlike.pro/docs/how-to/engines/ |
| GOWS | https://waha.devlike.pro/docs/engines/gows/ |
| Security | https://waha.devlike.pro/docs/how-to/security/ |
| WAHA Plus (تاريخ) | https://waha.devlike.pro/docs/how-to/waha-plus/ |
| Support / أسعار | https://waha.devlike.pro/support-us/ |
| GitHub | https://github.com/devlikeapro/waha |

---

## 11) توصية عملية لـ NaBoo

- **لا تستبدل Evolution الآن.**  
- إن أردتم اختبار whatsmeow بجدية ورخيصة: سيرفر/compose جانبي بـ  
  `WHATSAPP_DEFAULT_ENGINE=GOWS` + رقم اختبار.  
- قيسوا أيام الصمود مقابل جلسة Evolution.  
- التبرع $5 اختياري إن استخدمتم المشروع طويلاً.

---

*نهاية تقرير WAHA — مجمّع من توثيق الموقع الرسمي بتاريخ الجمع أعلاه.*
