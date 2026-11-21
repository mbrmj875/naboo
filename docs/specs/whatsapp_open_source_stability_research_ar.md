# تقرير بحث: مشاريع مفتوحة المصدر لبوابات واتساب (استقرار الجلسات)

> **تاريخ البحث:** 2026-07-26  
> **الغرض:** جرد ما هو متاح علناً على الإنترنت (مفتوح المصدر ويمكن استضافته) لمن بنى طبقة اتصال واتساب، مع التركيز على سمعة الاستقرار — لمساعدة NaBoo في قرار Evolution/Baileys مقابل بدائل Go.  
> **تنويه قانوني:** كل الحلول أدناه (ما عدا WhatsApp Cloud API الرسمي من Meta) تعتمد بروتوكول واتساب ويب / أجهزة مرتبطة **غير رسمي**. تخالف شروط Meta وقد تؤدي لحظر الرقم. «الاستقرار» هنا = صمود الجلسة تقنياً، وليس ضماناً ضد الحظر.

---

## 1) الخلاصة التنفيذية

| الطبقة | الأفضل استقراراً (سمعة مجتمعية 2024–2026) | الأفضل كنظام بيئي جاهز |
|--------|---------------------------------------------|-------------------------|
| **مكتبة بروتوكول** | **whatsmeow** (Go) — تستخدمها جسور Matrix/Beeper وتقارير إنتاج بآلاف الجلسات | **Baileys** — أكبر مجتمع Node |
| **بوابة REST جاهزة (Go)** | **GOWA** = `aldinokemal/go-whatsapp-web-multidevice` | — |
| **بوابة REST متعددة المحركات** | **WAHA** مع محرك **GOWS** (whatsmeow) | WAHA / Evolution |
| **ما تستخدمونه الآن** | Evolution API **2.3.7** = غلاف حول **Baileys** | ناضج مع n8n/Chatwoot |

**لا يوجد مشروع مفتوح يعد بجلسة «لا تنقطع أبداً».** التقارير الجادة تقول: whatsmeow أفضل في الذاكرة وإعادة الاتصال الذاتي؛ لكن `device_removed` / 401 يحدث على **كل** المكتبات إذا واتساب أو المستخدم أنهى الجهاز المرتبط.

---

## 2) طبقة المكتبات (الأشخاص / الفرق خلف المحرك)

### 2.1 tulir / whatsmeow — العمود الفقري الأقوى سمعةً
| | |
|--|--|
| **المستودع** | https://github.com/tulir/whatsmeow |
| **الترخيص** | MPL-2.0 |
| **التقنية** | Go — بروتوكول WhatsApp Web multi-device |
| **Stars (تقريبي وقت البحث)** | ~6.7k+ |
| **من يبني فوقه** | mautrix-whatsapp، Beeper، GOWA، WAHA/GOWS، wa-go، wa_meow |

**لماذا يُذكر كـ«مستقر»؟**
- صيانة نشطة من مطورين جادين في عالم الجسور (Matrix).
- تقارير إنتاج (مثل نقاش GitHub #979): بعد الهجرة من Baileys قلت حالات auto-logout؛ الذاكرة أقل؛ جلسات تبقى أسابيع مع تخزين دائم.
- **ليس سحرياً:** نفس Issues تظهر `401` / `device_removed` بعد أول رسالة أحياناً — سلوك سيرفر واتساب، يظهر أيضاً على Baileys.

**الوصول:** مفتوح بالكامل — `go get` / استنساخ GitHub.

---

### 2.2 WhiskeySockets / Baileys — الأشهر في Node
| | |
|--|--|
| **المستودع** | https://github.com/WhiskeySockets/Baileys |
| **الترخيص** | MIT |
| **التقنية** | TypeScript — WebSocket دون متصفح |
| **Stars** | ~10k+ |
| **يُستخدم في** | Evolution API، WAHA/NOWEB، forks كثيرة |

**السمعة:** نظام بيئي ضخم + forks متكررة تاريخياً؛ شكاوى شائعة عن memory leak وفصل جلسات. ما زال الخيار الافتراضي لمعظم بوابات Node.

---

### 2.3 pedroslopez / whatsapp-web.js — متصفح حقيقي
| | |
|--|--|
| **المستودع** | https://github.com/pedroslopez/whatsapp-web.js |
| **التقنية** | Puppeteer / Chromium |
| **الاستقرار مقابل الكشف** | أقرب لسلوك واتساب ويب الحقيقي → بعض المصادر تعتبره أقل «بصمة بروتوكول»؛ تكلفة RAM عالية (~300–500MB/جلسة) |

يظهر في OpenWA وWAHA (محرك WEBJS).

---

### 2.4 wppconnect-team / WPPConnect + wa-js
| | |
|--|--|
| **المستودع** | https://github.com/wppconnect-team/wppconnect |
| **التقنية** | حقن واتساب ويب عبر متصفح |
| **Stars** | ~3.3k |
| **ملاحظة** | ناضج للبوتات؛ ثقيل موارد؛ ليس الأحدث في سباق «كثافة جلسات SaaS». |

---

## 3) بوابات REST / منصات مفتوحة (من بنى «Evolution-like»)

### 3.1 Evolution API — ما عندكم الآن
| | |
|--|--|
| **المستودع** | https://github.com/EvolutionAPI/evolution-api (أيضاً evolution-foundation) |
| **Stars** | ~9k |
| **المحرك الافتراضي لويب** | **Baileys** |
| **إضافي** | يدعم أيضاً WhatsApp **Cloud API الرسمي** |
| **تكاملات** | Chatwoot, n8n, Typebot, Kafka, S3… |

مذكور في مصادر ثانوية أن فرع/إصدار مستقبلي (v3 beta) قد يميل لـ whatsmeow — **تحقق من فرعكم قبل الاعتماد**؛ إنتاجكم الحالي 2.3.7 = Baileys.

---

### 3.2 GOWA — aldinokemal/go-whatsapp-web-multidevice ⭐ مرشحكم الأقوى كبديل ذاتي
| | |
|--|--|
| **المستودع** | https://github.com/aldinokemal/go-whatsapp-web-multidevice |
| **الترخيص** | MIT |
| **Stars** | ~4.2k–4.3k |
| **المحرك** | whatsmeow |
| **الميزات** | REST API، UI، multi-account، webhooks، Chatwoot، MCP؛ إصدارات متكررة (v8/v9) |

هذا أقرب تعريف عملي لـ «GOWA» في الإنترنت المفتوح — **ليس** CodeWords. يمكن استضافته على VPS مثل Evolution.

---

### 3.3 WAHA — devlikeapro/waha ⭐ خيار مقارنة ممتاز
| | |
|--|--|
| **المستودع** | https://github.com/devlikeapro/waha |
| **الموقع** | https://waha.devlike.pro/ |
| **الترخيص** | Apache-2.0 (Core) |
| **Stars** | ~7k |
| **المحركات** | WEBJS (browser) · NOWEB (Baileys) · **GOWS (Go + whatsmeow)** · WPP |

**أهمية لـ NaBoo:** يمكنكم تجربة محرك **GOWS** بنفس واجهة HTTP تقريباً، لمقارنة استقرار whatsmeow دون بناء REST من الصفر — أقرب مسار «مختبر» من الاعتماد على CodeWords.

مستودعات مرتبطة: `devlikeapro/gows` / `gows-plus`، fork لـ whatsmeow.

---

### 3.4 OpenWA — rmyndharis/OpenWA
| | |
|--|--|
| **المستودع** | https://github.com/rmyndharis/OpenWA |
| **المحركات القابلة للتبديل** | whatsapp-web.js (افتراضي) أو Baileys |
| **الزعم** | توثيق صريح: web.js أقل بصمة بروتوكول / أعلى RAM؛ Baileys أخف وأعلى خطر كشف |

مفيد كمفهوم «محركان خلف API واحد» (مثل WAHA).

---

### 3.5 yeimarlabs / wa-go
| | |
|--|--|
| **المستودع** | https://github.com/yeimar-projects/wa-go (يظهر أيضاً yeimarlabs) |
| **التقنية** | Go + whatsmeow + Goravel |
| **التركيز** | multi-instance، webhooks موقّعة HMAC، إرسال idempotent — موجّه كـ «edge» لمنصة أكبر |

قريب فلسفياً من فكرة whatsapp-gateway عندكم.

---

### 3.6 jo-inc / wa_meow
| | |
|--|--|
| **المستودع** | https://github.com/jo-inc/wa_meow |
| **المحرك** | whatsmeow |
| **الزعم في README** | «More stable than Baileys»؛ مستخرج من إنتاج askjo.ai |
| **الحجم** | مشروع أصغر — مفيد كمرجع لا كمنصة SaaS كاملة |

---

### 3.7 mautrix-whatsapp (جسر Matrix)
| | |
|--|--|
| **المشروع** | جسر واتساب↔Matrix مبني على whatsmeow |
| **الدلالة** | إثبات ميداني أن whatsmeow يُشغَّل 24/7 لآلاف المستخدمين عبر بيوت Matrix |

ليس REST لـ SaaS ورش، لكن أقوى «شهادة استقرار» مفتوحة المصدر لـ whatsmeow.

---

### 3.8 مكتبات/أدوات أقدم (أقل أولوية لاستقرار SaaS كثيف)
- **Venom-bot**، **wa-automate** — تاريخية، صيانة متفاوتة.
- **CodeChat** — سلف فكري لـ Evolution.
- **Rhymen/go-whatsapp** — جيل أقدم من Go؛ whatsmeow حلّ محله عملياً.

---

## 4) ماذا يقول الإنتاج عن «من الأثبت»؟

من نقاشات GitHub العامة (مثال: tulir/whatsmeow Discussions #979):

> مشغّلو 1000+ جلسة دعم: بعد الانتقال لـ whatsmeow قلت مشاكل auto-logout؛ الذاكرة ثابتة؛ لـ 10k جلسة المطلوب معمارية (مراقبة، طوابير) أكثر من اسم المكتبة.

من Issues مشتركة على whatsmeow وBaileys:

> نفس نمط `conflict type=device_removed` / 401 بعد إرسال — يظهر على **كلا** المحركين → جزء منه إنفاذ واتساب وليس «عطل Baileys وحده».

**استنتاج التقرير:**  
- لتحسين **صمود الجلسة والموارد** → اتجاه whatsmeow (GOWA / WAHA-GOWS / wa-go).  
- لتحسين **النظام البيئي والتكامل السريع** → Evolution/Baileys أو WAHA متعدد المحركات.  
- لا محرك مفتوح يلغي حاجة: مراقبة، تصنيف فصل دائم/مؤقت، إشعار المالك، سياسة إرسال بشرية.

---

## 5) مصفوفة توصية لـ NaBoo

| الهدف | المشروع المفتوح المقترح | رابط |
|-------|-------------------------|------|
| الإبقاء على الإنتاج الحالي | Evolution API 2.3.7 + مراقبتكم | github.com/EvolutionAPI/evolution-api |
| مختبر استقرار Go بأقل بناء | **WAHA + `WHATSAPP_DEFAULT_ENGINE=GOWS`** | github.com/devlikeapro/waha |
| بديل Evolution كامل بـ Go | **GOWA** aldinokemal | github.com/aldinokemal/go-whatsapp-web-multidevice |
| فهم المحرك فقط | tulir/whatsmeow | github.com/tulir/whatsmeow |
| مقارنة متصفح vs بروتوكول | OpenWA / WPPConnect | انظر §3.4 و§2.4 |
| مسار رسمي قانوني طويل الأمد | Meta WhatsApp Cloud API | developers.facebook.com (ليس «جهاز مرتبط») |

---

## 6) أشخاص/كيانات بارزة (للمتابعة لا للعبادة)

| الاسم / الجهة | الدور |
|---------------|--------|
| **tulir** | whatsmeow + جسور mautrix |
| **WhiskeySockets / Rajeh Taher** | صيانة Baileys الحالية |
| **aldinokemal** | GOWA REST |
| **devlikeapro** | WAHA + محركات متعددة + GOWS |
| **Evolution Foundation / DavidsonGomes وآخرون** | Evolution API |
| **wppconnect-team** | WPPConnect |
| **pedroslopez** | whatsapp-web.js |

---

## 7) ماذا لا تعتمد عليه من الإنترنت

- نسب تسويقية («90% reconnect») بدون منهجية.
- ادعاء أن مكتبة واحدة «لا تُكتشف».
- مشاريع مغلقة / SaaS وسيطة (مثل طبقات مدارة فوق whatsmeow) إذا هدفك **ملكية كاملة** — استخدم المستودعات أعلاه مباشرة.

---

## 8) خطوة عملية مقترحة بعد هذا التقرير

1. إكمال ربط العقيلي على Evolution الحالي + قياس أسبوع.  
2. على VPS منفصل أو compose جانبي: تجربة **WAHA/GOWS** أو **GOWA** برقم اختبار واحد ومقارنة أيام الصمود.  
3. إن فاز Go بوضوح → خطة هجرة تدريجية لنفس نموذج `shop_{user_id}` عندكم، مع الإبقاء على Edge/FCM/`repair_needed`.

---

*نهاية التقرير — مصادر أساسية: مستودعات GitHub الرسمية، توثيق WAHA engines، نقاشات whatsmeow العامة، README المشاريع المذكورة أعلاه.*
