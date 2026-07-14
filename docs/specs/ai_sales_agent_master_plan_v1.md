# NaBoo AI Sales Agent — التقرير المتكامل v1.0

> **الحالة:** تخطيط وتقرير مرجعي — **لا كود تطبيق NaBoo**  
> **التاريخ:** 2026-07-11  
> **النطاق:** مشروع مستقل — وكيل مبيعات ذكي بالذكاء الاصطناعي  
> **البنية التحتية المتاحة:** Hostinger VPS + n8n + DeepSeek API + Evolution API (WhatsApp)

---

## فهرس المحتويات

1. [ملخص تنفيذي](#1-ملخص-تنفيذي)
2. [ما طلبه المالك — الرؤية الكاملة](#2-ما-طلبه-المالك--الرؤية-الكاملة)
3. [ما لا يريده — تصحيحات مهمة](#3-ما-لا-يريده--تصحيحات-مهمة)
4. [الفرق عن تطبيق NaBoo ERP](#4-الفرق-عن-تطبيق-naboo-erp)
5. [المعمارية المقترحة](#5-المعمارية-المقترحة)
6. [المكوّنات الخمسة](#6-المكوّنات-الخمسة)
7. [Target Intelligence — استخبارات الهدف](#7-target-intelligence--استخبارات-الهدف)
8. [Product Brain — معرفة المنتج](#8-product-brain--معرفة-المنتج)
9. [Sales Agent — شخصية المبيعات](#9-sales-agent--شخصية-المبيعات)
10. [قنوات التواصل](#10-قنوات-التواصل)
11. [البنية على Hostinger + n8n + DeepSeek](#11-البنية-على-hostinger--n8n--deepseek)
12. [Workflows n8n — التفصيل](#12-workflows-n8n--التفصيل)
13. [قاعدة البيانات (Supabase)](#13-قاعدة-البيانات-supabase)
14. [System Prompts](#14-system-prompts)
15. [طرق إعطاء الأوامر](#15-طرق-إعطاء-الأوامر)
16. [مثال عملي كامل](#16-مثال-عملي-كامل)
17. [ما هو واقعي وما هو صعب](#17-ما-هو-واقعي-وما-هو-صعب)
18. [المخاطر والاعتبارات القانونية](#18-المخاطر-والاعتبارات-القانونية)
19. [التكلفة — تحليل شامل](#19-التكلفة--تحليل-شامل)
20. [ROI — العائد على الاستثمار](#20-roi--العائد-على-الاستثمار)
21. [خطة التنفيذ — 4 أسابيع](#21-خطة-التنفيذ--4-أسابيع)
22. [المراحل المستقبلية](#22-المراحل-المستقبلية)
23. [التوصيات النهائية](#23-التوصيات-النهائية)
24. [الخطوات التالية](#24-الخطوات-التالية)

---

# 1. ملخص تنفيذي

## الفكرة بجملة واحدة

> **وكيل مبيعات ذكي مستقل** — المالك يعطيه هدفاً واحداً (شخص / صفحة / رقم)، فيقوم Agent بتحليل الهدف بعمق (Facebook، Instagram، فيديوهات، روابط، موقع، تقييمات)، ثم يتواصل معه عبر WhatsApp / Facebook / Instagram نيابة عن المالك، بأسلوب مسؤول مبيعات خبير (20+ سنة خبرة)، لإقناعه بشراء/اشتراك NaBoo.

## القرارات الرئيسية

| القرار | التوصية |
|--------|---------|
| **مشروع مستقل** | نعم — ليس جزءاً من تطبيق Flutter ERP |
| **المحرّك** | n8n على Hostinger VPS |
| **الذكاء الاصطناعي** | DeepSeek API (اشتراك موجود) |
| **WhatsApp** | Evolution API (self-hosted على نفس VPS) |
| **Facebook / Instagram** | Meta Business API (مرحلة 2) |
| **قاعدة البيانات** | Supabase (جداول منفصلة عن ERP) |
| **البداية** | WhatsApp + Target Intelligence + Product Brain |
| **التكلفة الشهرية** | ~$5–20 (DeepSeek usage فقط — الباقي موجود) |

---

# 2. ما طلبه المالك — الرؤية الكاملة

## 2.1 الدور المطلوب

المالك يريد **Agent ذكاء اصطناعي** يعمل كـ **موظف مبيعات عملاق** له 20 سنة خبرة أو أكثر:

- يتكلم بثقة عالية
- يفهم احتياجات العميل قبل أن يبيع
- يشرح ميزات NaBoo بدقة
- يقنع العميل بشراء/اشتراك التطبيق
- يحل مشاكل العميل ويربطها بميزات NaBoo
- يتحدث نيابة عن المالك بشكل احترافي

## 2.2 ما يفعله المالك

**فقط يعطي أوامر بسيطة:**

| الأمر | مثال |
|-------|------|
| تواصل مع شخص | «تواصل مع محمد — 07801234567» |
| حلّل صفحة | «حلّل facebook.com/alnoor.market» |
| أرسل رابط | «أرسل naboo.iq/download لـ [اسم]» |
| متابعة | «تابع مع أحمد — آخر تواصل قبل 3 أيام» |
| تدخل يدوي | «خذ المحادثة — أنا أكملها» |

**المالك لا يكتب رسالة واحدة** — Agent يتولى كل شيء.

## 2.3 ما يفعله Agent قبل التواصل

### تحليل عميق للهدف (Target Intelligence)

| المصدر | ما يجمعه |
|--------|----------|
| **Facebook Page** | اسم، وصف، منشورات، تعليقات، صور، فيديوهات، روابط |
| **Instagram** | bio، منشورات، reels، stories، hashtags |
| **الفيديوهات** | نص الكلام (speech-to-text) + وصف المحتوى (vision) |
| **الروابط في الصفحة** | يدخل كل رابط ويجمع بيانات |
| **Google Maps** | موقع، تقييم، تعليقات، ساعات عمل |
| **الموقع الإلكتروني** | منتجات، أسعار، نقاط ضعف |
| **WhatsApp** | رقم من بيانات الصفحة |

### ما يستنتجه من التحليل

- نوع النشاط (سوبرماركت، صيدلية، ملابس...)
- حجم النشاط (صغير / متوسط / كبير)
- **المشاكل الظاهرة** (نفاد بضاعة، أسعار غير محدثة، لا طلب أونلاين...)
- **نقاط القوة** (موقع ممتاز، تقييم جيد، نشاط على SNS)
- **فرص NaBoo** — أي ميزة تحل أي مشكلة
- أفضل قناة للتواصل
- نبرة المحادثة المناسبة

## 2.4 ما يفعله Agent أثناء التواصل

- رسالة أولى **مخصّصة 100%** — ليست template
- يذكر اسم المحل + مشكلته المحددة
- يستمع → يفهم الحاجة → يربطها بميزة NaBoo
- يعالج الاعتراضات (غالي، عندي برنامج، ما أحتاج...)
- يشرح كيف NaBoo:
  - يحل مشاكل المستخدم
  - يزيد المبيعات
  - يساعده يسيطر على محله/مشروعه
  - يطوّر مشروعه
  - يتفوق على المنافسين
- يقنع بثقة — كأنه بشر خبير
- متابعة بعد 48 ساعة إن لم يرد
- **لا يضغط** — إذا رفض مرتين → يشكر ويتوقف

## 2.5 معرفة المنتج (Product Brain)

Agent **يعرف NaBoo كاملاً** — ليس اتصالاً تقنياً بالتطبيق، بل **معرفة شاملة**:

- كل ميزة + لمن تناسب
- الأسعار والباقات (أرقام دقيقة)
- المشاكل التي يحلها لكل نوع محل
- كيف يزيد المبيعات
- كيف يسيطر المالك على محله عن بُعد
- اعتراضات العملاء + ردود
- قصص نجاح
- الفرق عن المنافسين

---

# 3. ما لا يريده — تصحيحات مهمة

| ❌ لا يريد | ✅ يريد |
|-----------|---------|
| مراسلة تلقائية لكل من علّق على صفحته | **هدف واحد = تحليل عميق + تواصل دقيق** |
| ربط تقني داخل تطبيق NaBoo ERP | **مشروع مستقل** — يعرف NaBoo للإقناع فقط |
| رسائل عامة / templates | **رسالة مبنية على تحليل صفحة + فيديو + روابط** |
| chatbot بسيط يرد على أسئلة | **مسؤول مبيعات AI** يبادر ويقنع |
| إرسال جماعي عشوائي (spam) | **تواصل مخصّص** لكل هدف |
| موظف بشري | **Agent AI** — أرخص 5–10× ويعمل 24/7 |

---

# 4. الفرق عن تطبيق NaBoo ERP

| | تطبيق NaBoo ERP | AI Sales Agent |
|--|-----------------|----------------|
| **الهدف** | إدارة المحل (فواتير، مخزون، تقارير) | **بيع NaBoo** للعملاء المحتملين |
| **المستخدم** | أصحاب المحلات (عملاء) | **المالك** (أنت) |
| **التقنية** | Flutter + sqflite + Supabase | n8n + DeepSeek + Evolution |
| **WhatsApp الموجود** | إشعارات (غيار زيت، تذكير) | **محادثة مبيعات كاملة** |
| **Trigger** | التطبيق يرسل طلب | **المالك يعطي أمر** |
| **البيانات** | tenant_id، orders | lead_id، analysis، conversations |
| **العلاقة** | Agent يعرف NaBoo للإقناع — **لا يتصل بالتطبيق** |

**نفس السيرفر (Hostinger)، workflows مختلفة، جداول Supabase مختلفة.**

---

# 5. المعمارية المقترحة

```
┌──────────────────────────────────────────────────────────┐
│  Command Center                                           │
│  (Telegram Bot / curl / Dashboard — المرحلة 2)           │
│  المالك: "حلّل وتواصل مع facebook.com/alnoor.market"   │
└────────────────────────┬─────────────────────────────────┘
                         │ Webhook
                         ▼
┌──────────────────────────────────────────────────────────┐
│  n8n (Hostinger VPS)                                      │
│                                                           │
│  WF1: Analyze & Contact    WF2: Inbound Reply             │
│  WF3: Follow-up (48h)      WF4: Video Analysis           │
└──┬──────────┬──────────┬──────────┬─────────────────────┘
   │          │          │          │
   ▼          ▼          ▼          ▼
DeepSeek   Evolution   Meta API   Google Maps
(API)      (WhatsApp)  (FB/IG)    (Location)
   │
   ▼
Supabase
├── sales_product_knowledge  (Product Brain)
├── sales_leads              (الأهداف)
└── sales_conversations      (المحادثات)
```

---

# 6. المكوّنات الخمسة

## 6.1 Command Center — لوحة الأوامر

واجهة (ويب أو Telegram) يدخل منها المالك:

| الشاشة | الوظيفة |
|--------|---------|
| **أمر تواصل** | رقم + رابط FB/IG → Agent يبدأ |
| **المحادثات** | عرض كل محادثة + من رد (AI / أنت) |
| **التدخل اليدوي** | «خذ المحادثة» عند الحاجة |
| **Leads** | قائمة الأهداف + حالة (جديد / مهتم / اشترى / رفض) |
| **التقارير** | معدل الرد، التحويل، أفضل الردود |

**MVP:** Telegram Bot أو curl — Dashboard لاحقاً.

## 6.2 Target Intelligence Engine — محرك استخبارات الهدف

يجمع ويحلل بيانات الهدف **قبل أي رسالة**:

```
رابط FB/IG + رقم
        ↓
Crawler → FB Page + IG Profile + Links + Maps
        ↓
Video Analyzer → Whisper + Vision AI
        ↓
DeepSeek → "حلّل — ما مشاكله؟ ما فرص NaBoo؟"
        ↓
Target Profile (JSON) → يُحفظ في Supabase
```

## 6.3 Product Brain — عقل المنتج

قاعدة معرفة كاملة عن NaBoo — **ليس اتصالاً بالتطبيق**:

- 50+ entry: ميزات، أسعار، اعتراضات، قصص نجاح
- مُصنّفة حسب vertical (supermarket, pharmacy, clothing, oil_change)
- تُحقَن في كل DeepSeek prompt

## 6.4 Sales Agent — وكيل المبيعات

DeepSeek + persona + Target Profile + Product Brain:

- persona: مسؤول مبيعات 20 سنة، عراقي، واثق، دافئ
- يبني استراتيجية إقناع مخصّصة لكل هدف
- محادثة ثنائية مع ذاكرة

## 6.5 Channel Connectors — موصلات القنوات

| القناة | الأداة | المرحلة |
|--------|--------|---------|
| WhatsApp | Evolution API | 1 |
| Facebook Messenger | Meta Graph API | 2 |
| Instagram DM | Meta Instagram API | 2 |
| تعليقات FB/IG | Meta Webhook | 3 (اختياري — ليس bulk auto-reply) |

---

# 7. Target Intelligence — استخبارات الهدف

## 7.1 مثال ملف هدف

```json
{
  "target_name": "سوبرماركت النور",
  "business_type": "supermarket",
  "estimated_size": "medium",
  "location": "العشار، بغداد",
  "google_rating": 3.8,
  "fb_followers": 2400,
  "ig_followers": 890,
  "problems": [
    "آخر 3 منشورات عن نفاد بضاعة",
    "تعليقات: الأسعار ما محدثة",
    "لا يوجد نظام طلب أونلاين",
    "فيديو قديم (6 شهور) — نشاط تسويقي ضعيف"
  ],
  "strengths": [
    "موقع ممتاز",
    "تقييم 3.8 نسبياً جيد",
    "نشط على FB (3 منشورات/أسبوع)"
  ],
  "naboo_opportunities": [
    "تنبيه مخزون → حل نفاد بضاعة",
    "تحديث أسعار من الموبايل → حل الأسعار",
    "dashboard مالك → سيطرة عن بُعد",
    "تقارير يومية → يعرف أرباحه"
  ],
  "best_channel": "whatsapp",
  "phone": "9647801234567",
  "approach_tone": "consultative"
}
```

## 7.2 مصادر البيانات

| المصدر | الأداة | ما يستخرجه |
|--------|--------|-------------|
| Facebook Page | Meta Graph API + scrape علني | منشورات، وصف، روابط، فيديو |
| Instagram | Meta Instagram API | bio، منشورات، reels |
| الفيديو | Whisper API | speech-to-text |
| الفيديو | DeepSeek Vision / GPT-4V | وصف المحتوى |
| الروابط | Puppeteer / HTTP Crawler | محتوى المواقع |
| Google Maps | Google Places API | موقع، تقييم، تعليقات |
| WhatsApp | من بيانات الصفحة | رقم |

## 7.3 تحليل الفيدio

```
فيدio على صفحة الهدف
        ↓
Whisper → "صعب نتابع المخزون يدوياً"
Vision → "محل بقالة كبير، رفوف ممتلئة جزئياً"
        ↓
DeepSeek → "المشكلة: مخزون يدوي → NaBoo: تنبيه مخزون"
```

---

# 8. Product Brain — معرفة المنتج

## 8.1 المحتوى المطلوب

### لكل نوع محل (vertical)

| Vertical | الميزات الرئيسية | المشاكل التي يحلها |
|----------|------------------|---------------------|
| **supermarket** | مخزون، باركود، فواتير، تقارير، ديون | نفاد بضاعة، أسعار غير محدثة، سرقة موظفين |
| **pharmacy** | أدوية، تواريخ انتهاء، وصفات، تأمين | انتهاء أدوية، وصفات مفقودة |
| **clothing** | مقاسات، ألوان، مواسم، خصومات | مخزون موسمي، مقاسات |
| **oil_change** | سيارات، مواعيد، واتساب تلقائي | نسيان مواعيد الصيانة |

### فئات Knowledge Base

| category | أمثلة |
|----------|-------|
| `feature` | «تنبيه مخزون — ينبهك قبل ما ينفد المنتج» |
| `pricing` | «باقة السوبرماركت: 25,000 د.ع/شهر» |
| `objection` | «غالي» → «أول شهر مجاني + توفر أكثر من موظف» |
| `success_story` | «محل X في العشار — زاد مبيعاته 15%» |
| `competitor` | «لماذا NaBoo أفضل من Y» |

## 8.2 كيف يُستخدم

```
قبل كل DeepSeek call:
    ↓
Supabase → SELECT FROM sales_product_knowledge
           WHERE keywords && ARRAY['مخزون', 'supermarket']
    ↓
Code Node → حقن النتائج في system prompt
    ↓
DeepSeek يرد بمعرفة دقيقة — لا يخترع
```

---

# 9. Sales Agent — شخصية المبيعات

## 9.1 Persona

```
أنت [اسم] — مدير مبيعات NaBoo، 20 سنة خبرة في ERP للمحلات بالعراق.

شخصيتك:
• واثق، دافئ، عراقي — لا روبوت
• تستمع قبل ما تبيع
• تحل مشكلة العميل قبل ما تتكلم عن السعر
• تستخدم أرقام حقيقية من Product Brain فقط
• إذا ما تعرف → "خليني أتأكد وأرجعلك"

قواعد:
• لا تخترع ميزة أو سعر
• لا تضغط — إذا رفض مرتين → اشكره واتركه
• كل رسالة ≤ 3 أسطر (واتسapp) أو ≤ 5 (Messenger)
• اذكر اسم العميل + نشاطه + موقعه
• الهدف: تجربة مجانية أو مكالمة — ليس «اشتري الآن» مباشرة
```

## 9.2 تدفق المحادثة

```
1. تحليل الهدف (Target Intelligence)
2. رسالة أولى مخصّصة
3. استماع → فهم الحاجة
4. ربط الحاجة بميزة NaBoo
5. معالجة الاعتراض
6. دعوة للإجراء (تجربة / مكالمة / رابط)
7. متابعة بعد 48 ساعة إن لم يرد
```

## 9.3 مقارنة رسالة

**❌ chatbot عام:**
> «مرحباً! NaBoo نظام إدارة محلات. هل تريد الاشتراك؟»

**✅ Agent بعد تحليل:**
> «أهلاً أستاذ [الاسم]،
>
> شفت صفحة سوبرماركت النور — محل كبير وموقع ممتاز في العشار. لاحظت في آخر منشور ذكرت مشكلة نفاد بضاعة، وفي التعليقات أكثر من شخص سأل عن أسعار ما محدثة.
>
> هذي مشاكل شائعة — عندنا 12 سوبرماركت في العشار يستخدمون NaBoo ويحلونها:
> • تنبيه قبل ما ينفد المخزون
> • تحديث أسعار من موبايلك
> • تقرير يومي على واتسappك
>
> تحب أشرحلك بـ 5 دقائق؟ أول شهر مجاني.»

---

# 10. قنوات التواصل

## 10.1 WhatsApp (المرحلة 1)

| | |
|--|--|
| **الأداة** | Evolution API (self-hosted) |
| **Instance** | `sales_agent_wa` — رقم واتسapp الشركة |
| **القدرة** | إرسال + استقبال |
| **القيود** | تجنب spam — تأخير 10–20 ثانية بين الرسائل |
| **الملف** | `infra/hostinger/docker-compose.evolution.yml` |

## 10.2 Facebook Messenger (المرحلة 2)

| | |
|--|--|
| **الأداة** | Meta Graph API |
| **القدرة** | رد على من راسل الصفحة أولاً |
| **القيود** | **لا** رسالة أولى لمن لم يراسل |

## 10.3 Instagram DM (المرحلة 2)

| | |
|--|--|
| **الأداة** | Meta Instagram API |
| **القدرة** | رد على DM |
| **القيود** | نفس Messenger — reply only |

## 10.4 ملاحظة Meta

- Meta Business API **مجاني**
- يحتاج: حساب Business + Page + App Review (أسابيع)
- **ممنوع** cold outreach على Messenger/IG — فقط reply

---

# 11. البنية على Hostinger + n8n + DeepSeek

## 11.1 ما هو متاح

| البند | الحالة |
|-------|--------|
| Hostinger VPS | ✅ موجود |
| n8n | ✅ مثبت على VPS |
| DeepSeek API | ✅ اشتراك |
| Evolution API | ⚠️ docker-compose جاهز — يحتاج deploy |
| Supabase | ✅ موجود |
| Meta Business | ❌ مرحلة 2 |

## 11.2 على السيرفر

```
Hostinger VPS
│
├── n8n (:5678)
│   ├── WF: Sales Agent — Analyze & Contact
│   ├── WF: Sales Agent — Inbound Reply
│   ├── WF: Sales Agent — Follow-up
│   └── WF: Sales Agent — Video Analysis
│
├── Evolution API (:8080)
│   └── instance: sales_agent_wa
│
└── (workflow الزيوت الموجود — منفصل)
```

## 11.3 n8n Variables

| Variable | الوصف |
|----------|--------|
| `DEEPSEEK_API_KEY` | مفتاح DeepSeek |
| `EVOLUTION_API_KEY` | مفتاح Evolution |
| `EVOLUTION_BASE_URL` | `http://localhost:8080` |
| `SUPABASE_URL` | رابط Supabase |
| `SUPABASE_SERVICE_KEY` | service role |
| `WEBHOOK_SECRET` | سر الأوامر |
| `WA_INSTANCE` | `sales_agent_wa` |

---

# 12. Workflows n8n — التفصيل

## 12.1 Workflow 1: Analyze & Contact

**Trigger:** Webhook POST `/webhook/sales-agent`

**Input:**
```json
{
  "webhook_secret": "...",
  "command": "analyze_and_contact",
  "target_fb": "https://facebook.com/alnoor.market",
  "target_ig": "https://instagram.com/alnoor_market",
  "phone": "07801234567",
  "notes": "سوبرماركت العشار"
}
```

**Nodes:**
1. Webhook
2. Validate (WEBHOOK_SECRET)
3. HTTP Request — Fetch FB Page
4. HTTP Request — Google Maps (اختياري)
5. Code — Merge Profile
6. HTTP Request — DeepSeek #1 (تحليل)
7. Supabase — SELECT product_knowledge
8. HTTP Request — DeepSeek #2 (رسالة أولى)
9. Wait 10–20s
10. HTTP Request — Evolution (إرسال WhatsApp)
11. Supabase — INSERT lead + conversation
12. Respond OK

## 12.2 Workflow 2: Inbound Reply

**Trigger:** Webhook من Evolution (رسالة واردة)

**Nodes:**
1. Webhook
2. Supabase — lead + conversation history
3. Supabase — product_knowledge
4. Code — بناء prompt
5. HTTP Request — DeepSeek
6. HTTP Request — Evolution (إرسال)
7. Supabase — حفظ + تحديث status

## 12.3 Workflow 3: Follow-up

**Trigger:** Cron كل 6 ساعات

**Logic:**
- leads WHERE status='interested' AND last_message > 48h AND follow_up_count < 3
- DeepSeek → متابعة
- Evolution → إرسال
- follow_up_count++

## 12.4 Workflow 4: Video Analysis (مرحلة 2)

**Trigger:** Webhook (رابط فيديو)

**Nodes:**
1. HTTP — تحميل فيديو
2. Whisper — speech-to-text
3. DeepSeek Vision — وصف
4. DeepSeek — استنتاج مشاكل/فرص
5. Supabase — إضافة لـ target profile

## 12.5 DeepSeek Node Template

```
POST https://api.deepseek.com/chat/completions
Authorization: Bearer {{ $env.DEEPSEEK_API_KEY }}
Content-Type: application/json

{
  "model": "deepseek-chat",
  "temperature": 0.4,
  "messages": [
    { "role": "system", "content": "{{ system_prompt }}" },
    { "role": "user", "content": "{{ user_message }}" }
  ]
}
```

| الاستخدام | temperature |
|-----------|-------------|
| تحليل الهدف | 0.2 |
| رسالة مبيعات | 0.5 |
| رد محادثة | 0.4 |

---

# 13. قاعدة البيانات (Supabase)

## 13.1 الجداول — منفصلة عن ERP

```sql
CREATE TABLE sales_product_knowledge (
  id SERIAL PRIMARY KEY,
  category TEXT NOT NULL,
  vertical TEXT,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  keywords TEXT[]
);

CREATE TABLE sales_leads (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  target_name TEXT,
  target_fb_url TEXT,
  target_ig_url TEXT,
  phone TEXT,
  analysis JSONB,
  status TEXT DEFAULT 'new',
  created_at TIMESTAMPTZ DEFAULT now(),
  last_message_at TIMESTAMPTZ,
  follow_up_count INT DEFAULT 0
);

CREATE TABLE sales_conversations (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  lead_id UUID REFERENCES sales_leads(id),
  role TEXT NOT NULL,
  message TEXT NOT NULL,
  channel TEXT DEFAULT 'whatsapp',
  created_at TIMESTAMPTZ DEFAULT now()
);
```

## 13.2 Lead Statuses

| status | المعنى |
|--------|--------|
| `new` | تم التحليل — لم يُرسل بعد |
| `contacted` | رُسلت رسالة أولى |
| `interested` | رد باهتمام |
| `trial` | طلب تجربة |
| `closed` | اشترى |
| `rejected` | رفض |
| `manual` | المالك يتولى |

---

# 14. System Prompts

## 14.1 Prompt: تحليل الهدف

```
أنت محلل أعمال. حلّل بيانات هذا المحل/الشخص:

{target_data_json}

أخرج JSON:
{
  "business_type": "...",
  "estimated_size": "small/medium/large",
  "location": "...",
  "problems": ["...", "...", "..."],
  "strengths": ["...", "..."],
  "naboo_opportunities": ["...", "...", "..."],
  "best_channel": "whatsapp/messenger/instagram",
  "approach_tone": "formal/friendly/consultative"
}
```

## 14.2 Prompt: رسالة أولى

```
أنت {agent_name} — مدير مبيعات NaBoo، 20 سنة خبرة.

تحليل الهدف: {analysis_json}
معرفة المنتج: {product_knowledge}

اكتب رسالة واتسapp أولى:
- مخصّصة 100% — اذكر اسم المحل ومشكلته
- 3-5 أسطر فقط
- لا تخترع أسعار — من product_knowledge فقط
- الهدف: فتح محادثة
- بالعربية العراقية، ودود ومهني
```

## 14.3 Prompt: رد محادثة

```
أنت {agent_name} — مدير مبيعات NaBoo.

ملف الهدف: {target_profile}
معرفة المنتج: {product_knowledge}
تاريخ المحادثة: {conversation_history}

العميل قال: "{incoming_message}"

قواعد:
- رد بـ 2-4 أسطر
- حل مشكلته أولاً، ثم اربطها بميزة NaBoo
- إذا سأل سعر → من product_knowledge
- إذا رفض → اشكره ولا تكرر
- إذا مهتم → رابط تجربة أو مكالمة
```

---

# 15. طرق إعطاء الأوامر

## 15.1 curl / Postman (MVP)

```bash
curl -X POST https://n8n.yourdomain.com/webhook/sales-agent \
  -H "Content-Type: application/json" \
  -d '{
    "webhook_secret": "YOUR_SECRET",
    "command": "analyze_and_contact",
    "target_fb": "https://facebook.com/alnoor.market",
    "phone": "07801234567"
  }'
```

## 15.2 Telegram Bot (موصى به)

```
المالك → Telegram: "تواصل alnoor.market 07801234567"
    ↓
Bot → n8n webhook
    ↓
Bot → "✅ تم — Lead #42 — رُسلت رسالة"
```

## 15.3 Google Sheet

```
Sheet: اسم | رابط FB | رقم | حالة
n8n يقرأ صف جديد كل 5 دقائق → Agent يعمل → يحدّث الحالة
```

## 15.4 Dashboard (مرحلة 2)

واجهة ويب — Next.js أو admin-web منفصل.

---

# 16. مثال عملي كامل

**الأمر:**
> «حلّل وتواصل مع facebook.com/alnoor.market — 07801234567»

```
[1] Target Intelligence (5–10 دقائق)
    ├── FB: 2,400 متابع، آخر 3 عن "نفاد بضاعة"
    ├── IG: @alnoor_market — 890 متابع
    ├── Google Maps: 4.2⭐ — "أسعار غير محدثة"
    └── WhatsApp: 07801234567

[2] Sales Strategy
    ├── مشكلة #1: مخزون → NaBoo تنبيه مخزون
    ├── مشكلة #2: أسعار → NaBoo تحديث من الموبايل
    └── قناة: WhatsApp

[3] Outreach — رسالة مخصّصة (انظر §9.3)

[4] Conversation
    ├── العميل: "كم السعر؟"
    ├── Agent: "25,000 د.ع/شهر — أول شهر مجاني"
    ├── العميل: "عندي برنامج قديم"
    ├── Agent: "NaBoo offline + sync — ما تحتاج نت دائم"
    └── Agent: "أرسلك رابط التجربة؟"

[5] Dashboard
    └── Lead: alnoor.market | Status: interested | Next: follow-up 48h
```

---

# 17. ما هو واقعي وما هو صعب

| القدرة | واقعي؟ | ملاحظة |
|--------|--------|--------|
| تحليل صفحة FB علنية | ✅ | Meta API + scrape |
| تحليل IG profile علني | ✅ | Meta Instagram API |
| قراءة فيديو (speech-to-text) | ✅ | Whisper |
| وصف محتوى فيديو | ✅ | Vision AI |
| زيارة روابط الصفحة | ✅ | Web Crawler |
| Google Maps | ✅ | Places API |
| FB/IG private profiles | ❌ | مخالف للقانون |
| رسالة أولى Messenger/IG | ⚠️ | فقط reply |
| واتسapp رسالة أولى | ✅ | Evolution (بحذر spam) |
| تحليل "قصة/خلفية" الشخص | ⚠️ | من المحتوى العلني فقط |

---

# 18. المخاطر والاعتبارات القانونية

| المخاطر | التخفيف |
|---------|---------|
| Spam / إزعاج | هدف واحد = تحليل + تواصل مخصّص — لا bulk |
| Meta ToS | reply only على Messenger/IG |
| ردود خاطئة (أسعار) | Product Brain صارم + «لا تخترع» |
| حظر رقم واتسapp | Wait 10–20s + حد يومي |
| خصوصية | لا profiles خاصة — علني فقط |
| موافقة | opt-in للتسويق حيث مطلوب |

---

# 19. التكلفة — تحليل شامل

## 19.1 مع البنية الموجودة (Hostinger + DeepSeek)

| البند | شهري |
|-------|------|
| Hostinger VPS | $0 (مدفوع) |
| n8n | $0 |
| DeepSeek API | $5–20 |
| Evolution | $0 |
| Supabase Free | $0 |
| Google Maps (اخtiari) | $0–5 |
| **المجموع** | **~$5–20/شهر** |

## 19.2 حسب الاستخدام (DeepSeek)

| السيناريو | أهداف/شهر | محادثات | DeepSeek |
|-----------|-----------|---------|----------|
| تجريبي | 10–20 | 50–100 | $5–10 |
| نشط | 50–100 | 300–500 | $20–40 |
| مكثف | 200+ | 1,000+ | $50–100 |

*محادثة كاملة (10–15 رسالة) ≈ $0.01–0.03*

## 19.3 تكلفة البناء

| الطريقة | التكلفة | الوقت |
|---------|---------|-------|
| **بنفسك + Cursor** | ~$50 APIs تجريبية | 2–3 أشهر |
| Freelancer MVP | $800–2,000 | 1–2 شهر |
| Freelancer كامل | $5,000–12,000 | 3–4 أشهر |

## 19.4 مقارنة Agent vs موظف

| | Agent AI | موظف (العراق) |
|--|----------|---------------|
| شهري | $5–20 | $300–800+ |
| ساعات | 24/7 | 8 |
| محادثات/يوم | غير محدود | 10–20 |
| تحليل FB | دقائق | 15–30 دقيقة |
| تكلفة/lead | $0.50–2 | $15–40 |

---

# 20. ROI — العائد على الاستثمار

```
تكلفة Agent: ~$20/شهر
سعر NaBoo: ~25,000 د.ع/شهر ≈ $19/شهر

3 عملاء/شهر = يغطي التكلفة
10 عملاء = ~$170 ربح - $20 = $150 صافي
50 عملاء = ~$930 - $50 = $880 صافي
```

---

# 21. خطة التنفيذ — 4 أسابيع

| الأسبوع | المهمة | المخرج |
|---------|--------|--------|
| **1** | Supabase tables + Product Knowledge (50 entry) | قاعدة معرفة NaBoo |
| **2** | WF1 (تحليل + رسالة) + Evolution instance | أمر → واتسapp |
| **3** | WF2 (رد inbound) | محادثة كاملة |
| **4** | WF3 (متابعة) + Telegram Bot | نظام يعمل |

**بعد 4 أسابيع:** المالك يعطي هدف → Agent يحلّل → يراسل → يرد → يتابع.

---

# 22. المراحل المستقبلية

| المرحلة | المحتوى | التوقيت |
|---------|---------|---------|
| **2** | FB Messenger + IG DM (Meta API) | شهر 2–3 |
| **2** | Video Analysis (Whisper + Vision) | شهر 2–3 |
| **2** | Dashboard ويب | شهر 3–4 |
| **3** | Vector RAG (pgvector) | شهر 4+ |
| **3** | Google Sheet sync | شهر 4+ |
| **4** | Multi-agent (عدة personas) | لاحقاً |

---

# 23. التوصيات النهائية

## 23.1 ابدأ بـ

1. **Product Knowledge Base** — 50 entry عن NaBoo
2. **Workflow 1** — analyze + contact على WhatsApp
3. **Telegram Bot** — للأوامر اليومية

## 23.2 لا تبدأ بـ

- Dashboard معقد
- FB/IG قبل WhatsApp
- إرسال جماعي
- Vector RAG (MVP لا يحتاجه)

## 23.3 مبادئ

- **هدف واحد = تحليل عميق + تواصل دقيق**
- **مشروع مستقل** — لا يلمس كود ERP
- **DeepSeek + n8n + Hostinger** — كلها موجودة
- **WhatsApp أولاً** — FB/IG لاحقاً
- **Product Brain** — لا تخترع — معرفة دقيقة فقط

---

# 24. الخطوات التالية

| # | المهمة | الأولوية |
|---|--------|----------|
| 1 | إنشاء جداول Supabase (`sales_*`) | عالية |
| 2 | ملء Product Knowledge (50 entry) | عالية |
| 3 | Deploy Evolution instance `sales_agent_wa` | عالية |
| 4 | بناء Workflow 1 في n8n | عالية |
| 5 | اختبار: هدف واحد → واتسapp | عالية |
| 6 | Workflow 2 (inbound) | متوسطة |
| 7 | Telegram Bot | متوسطة |
| 8 | Workflow 3 (follow-up) | متوسطة |
| 9 | Meta Business (FB/IG) | منخفضة |
| 10 | Dashboard | منخفضة |

---

## المراجع

- `docs/specs/oil_change_n8n_whatsapp_setup_guide_ar.md` — إعداد n8n + Evolution
- `infra/hostinger/docker-compose.evolution.yml` — Evolution Docker
- `infra/hostinger/n8n-oil-change-workflow.json` — نمط DeepSeek node

---

> **ملاحظة:** هذا التقرير مرجع تخطيطي. التنفيذ الفعلي يبدأ بـ Product Knowledge Base ثم Workflow 1.
