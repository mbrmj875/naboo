# تحسينات فصل واتساب — تصنيف دائم/مؤقت + health-check + repair_needed

> **الحالة:** مؤكَّد نهائياً — **منشور على الإنتاج (naboo-lic)**  
> **النطاق:** Evolution v2.3.x + Supabase Edge + SQL (بدون Flutter/APK / بدون n8n في هذه الدفعة)  
> **آخر تحديث:** 2026-07-26 — SQL + deploy + cron تمّت

### نشر حي (2026-07-26)
- SQL: أعمدة `restart_attempts` / `last_restart_at` / `repair_needed` / `disconnect_cause` على `tenant_whatsapp_gateways`
- Deploy: `whatsapp-events`, `whatsapp-health-check` (`--no-verify-jwt`), `whatsapp-gateway`
- Secret: `CRON_SECRET` مضبوط على المشروع
- Cron job `whatsapp-health-check` → `*/5 * * * *` عبر `pg_cron` + `pg_net`
- Smoke test health-check: HTTP 200

### إصلاح 2026-07-26 — provision لا يُسقِط repair_needed
- صف العقيلي: `repair_needed=true`, `disconnect_cause=device_removed_historical_401` (يدوي — يوقف الكرون)
- `action=provision`: إن كانت الجلسة `repair_needed` أو `disconnect_cause` دائم → يُبقى `repair_needed` حتى `state=open`؛ audit: `preserved_repair_needed_until_open`

---

## 0) قرارات حُسمت في النقاش (قبل التنفيذ)

| قرار | القيمة |
|------|--------|
| FCM actionKind | `openWhatsappConnect` فقط (+ `alertId` مميّز) — **لا** `openWhatsappRepair` حتى APK جديد |
| Backoff | محاولة #1 فورية في webhook؛ #2 عبر health-check — **لا sleep داخل Edge** |
| `phoneDisconnected` | **مؤقت** (ليس دائم) |
| استثناء 401 بعد 515 ≤30ث | صِنِّف **temporary** مرة؛ تكرار 401 بعد استقرار → permanent |
| Q1–Q12 | نُفِّذ بالافتراضيات المحافظة (§12) |

---

## 1) القاعدة الذهبية

```
فصل دائم (device_removed | loggedOut | removed | 401 بدون استثناء 515)؟
  ├─ نعم → تخطّى restart
  │         → repair_needed = true
  │         → restart_attempts = 0
  │         → FCM فوراً (alertId=whatsapp_gateway_repair_needed)
  └─ لا  → restart (حدّان؛ #1 webhook / #2 health-check)
            → إن فشل الحدّان → FCM (alertId=whatsapp_gateway_reconnect_failed)
```

- الأساس: webhook `CONNECTION_UPDATE` → `whatsapp-events`.
- شبكة أمان: cron `whatsapp-health-check` ~كل 5 دقائق — **لا يلمس** `repair_needed = true`.
- `repair_needed` عمود منفصل — لا تغيّر قيم `status`.

---

## 2) قاعدة البيانات

ملف: `migrations/20260726_tenant_whatsapp_repair_fields.sql`

```sql
ALTER TABLE public.tenant_whatsapp_gateways
  ADD COLUMN IF NOT EXISTS restart_attempts INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_restart_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS repair_needed BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS disconnect_cause TEXT;

CREATE INDEX IF NOT EXISTS idx_twg_health_temp_disc
  ON public.tenant_whatsapp_gateways (updated_at)
  WHERE status = 'disconnected' AND repair_needed = false;
```

---

## 3) الثوابت

| الاسم | القيمة |
|--------|--------|
| `RESTART_MAX_ATTEMPTS` | `2` |
| `RESTART_COOLDOWN_MS` | `60000` |
| `RESTART_BACKOFF_MS` | `30000` |
| `FCM_ALERT_COOLDOWN_MS` | `1800000` (30 دقيقة لنفس user+alertId) |
| `FALSE_401_AFTER_515_MS` | `30000` |

---

## 4) `classifyDisconnect`

**دائم:** `device_removed` | `loggedOut` | `logged_out` | `removed` | `statusReason === 401`  
**ليس دائم بمفرده:** `phoneDisconnected` → **temporary**  
**مدخلات المصنّف:** `state` + `statusReason` + snippet من `conflict` / `stream:error` إن وُجد.

**استثناء:** إن كان السبب يبدو 401/loggedOut لكن وُجد حدث/سبب `515` خلال آخر 30ث لنفس الـ instance → **temporary** (مرة واحدة منطقياً عبر عدم رفع `repair_needed`؛ إن بقي close واستنفد المحاولات → FCM reconnect_failed؛ إن عاد 401 بعد استقرار بدون 515 قريب → permanent).

تخزين: `disconnect_cause` ≤ 120 حرف.  
diagnostic: `disconnect_permanent` | `disconnect_temporary`.

---

## 5) `handleConnectionUpdate` عند close بعد connected

### دائم
1. لا restart / لا soft-reconnect هنا.
2. `repair_needed=true`, `restart_attempts=0`, `status=disconnected`, `disconnect_cause=…`
3. FCM (`whatsapp_gateway_repair_needed`) مع تبريد 30د.
4. diagnostic + audit.

### مؤقت
1. **لا تُصفِّر** `repair_needed` إن كان `true` مسبقاً (لا شفاء عرضي بحدث مؤقت).
2. إن `repair_needed` أصلاً true → لا restart؛ اخرج (الحالة تحتاج QR).
3. وإلا: restart #1 فوراً إن مرّ cooldown؛ زِد `restart_attempts`؛ اضبط `last_restart_at`.
4. لا sleep — المحاولة #2 عبر health-check.
5. عند استنفاذ المحاولتين وفشل الإيقاظ → FCM (`whatsapp_gateway_reconnect_failed`) مع تبريد 30د.

### عند العودة إلى `open`
- `status=connected`, `repair_needed=false`, `restart_attempts=0`, صفّر/`null` لـ `disconnect_cause` حسب الحاجة.

---

## 6) `whatsapp-health-check`

- يقرأ Evolution `connectionState` أولاً؛ إن `open` → شفاء سحابة بدون restart.
- صفوف: `disconnected AND repair_needed=false`؛ حد 50 / دورة؛ ترتيب `last_disconnected_at`/`updated_at`.
- restart فقط ضمن `RESTART_*` وبعد مرور `max(COOLDOWN, BACKOFF)` من `last_restart_at` عندما `restart_attempts == 1`.
- سر الطلب: نفس نمط cron الموجود (`Authorization` / سر بيئة مخصّص).

---

## 7) FCM (توافق APK الحالي)

| الحالة | alertId | actionKind |
|--------|---------|------------|
| دائم | `whatsapp_gateway_repair_needed` | `openWhatsappConnect` |
| فشل إيقاظ مؤقت | `whatsapp_gateway_reconnect_failed` | `openWhatsappConnect` |

نصوص عربية في الإشعار؛ شاشة `openWhatsappRepair` مؤجّلة لدفعة APK.

---

## 8) دمج `whatsapp-gateway` soft-reconnect

- إن `repair_needed=true` أو instance 404 → **لا** soft-reconnect؛ أرجع `whatsapp_disconnected` (+ `repair_needed: true` في JSON إن أمكن).
- عدّاد `restart_attempts` ملك **events + health-check فقط**؛ soft-reconnect عند الإرسال لا يزيد العداد.

---

## 9) خارج هذه الدفعة

- Flutter: `openWhatsappRepair` + DELETE/CREATE/QR.
- n8n: لا تعديل إلزامي الآن (Edge يمنع الإيقاظ العبثي عبر `repair_needed`).

---

## 10) ملفات التنفيذ

1. `supabase/functions/whatsapp-events/index.ts` (استعادة + classify + منطق الفصل)
2. `supabase/functions/whatsapp-health-check/index.ts`
3. `migrations/20260726_tenant_whatsapp_repair_fields.sql`
4. ضبط `whatsapp-gateway` لاحترام `repair_needed`
5. تكرار ثوابت `RESTART_*` موثّق بين الدوال

---

## 11) تصنيف Q1–Q12 (أرشيف القرار)

| # | النوع | القرار النهائي |
|---|--------|----------------|
| Q1 | UX خفيف → حُسم | `phoneDisconnected` = **temporary** |
| Q2 | تقني | نعم — مرّر conflict/stream للمصنّف |
| Q3 | UX خفيف → حُسم | استثناء 401 بعد 515 ≤30ث = temporary |
| Q4 | UX خفيف | **لا** تصفير `repair_needed` عند فصل مؤقت؛ التصفير فقط عند `open` |
| Q5 | تقني/معمارية → حُسم | محاولة فورية + #2 عبر health-check |
| Q6 | UX خفيف | تبريد FCM **30 دقيقة** لنفس user+alertId |
| Q7 | تقني | اقرأ الحالة الحيّة قبل restart |
| Q8 | تقني | حد 50 صفاً / دورة |
| Q9 | تقني | سر كرون كباقي الدوال |
| Q10 | تقني | احترم `repair_needed` في soft-reconnect |
| Q11 | نطاق | تأجيل n8n |
| Q12 | نطاق | Edge + SQL فقط هذه الدفعة |

**لا سؤال معلّق يوقف التنفيذ.** الافتراضات محافظة ومتوافقة خلفياً مع APK الحالي.
