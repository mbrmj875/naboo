# WhatsApp Ops Analyst v1

نظام مراقبة واتساب إنتاجي: **AIOps + RAG-RCA** مع طبقة موثوقية للمراقب نفسه.

المسار التشغيلي: **WAHA + Supabase Edge** على VPS — **بدون n8n** كعمود فقري.

القاعدة الذهبية: المصنّف الحتمي يحدّد الخطورة ويفتح الحوادث؛ **DeepSeek يُثري فقط** ولا يغيّر severity ولا يقترح hard_reset/QR كفعل آلي.

---

## مسار البيانات

```
WAHA events → whatsapp-events / gateway
           → whatsapp_ops_facts
           → condition_persistence_gate (5m إلا P1 فوري)
           → deterministic_classifier
           → whatsapp_ops_incidents (fingerprint)
           → alerts (email ± Telegram/FCM)
           → lessons RAG
           → DeepSeek enrichment
pg_cron */5 → whatsapp-ops-analyst → Healthchecks.io ping
            → whatsapp-health-check (safe reconnect فقط)
```

---

## بصمة الحادث (مهم)

```
fingerprint = sha256(rule_id | session_name | pattern_key | severity)
```

- `user_id` عمود مفهرس للفلترة/الصلاحيات — **ليس** داخل الـ hash.
- حادث مفتوح بنفس البصمة → `times_seen++` بدون إيميل جديد (إلا تصعيد SLA / resolve / flapping open).

Partial unique: `(fingerprint) WHERE status = 'open'`.

---

## ثوابت معتمدة

| ثابت | قيمة |
|------|------|
| Cron | كل 5 دقائق |
| Healthchecks period | 5 دقائق |
| Healthchecks grace | **10 دقائق** |
| Persistence X | 5 دقائق (غير P1 الفوري) |
| Flapping | ≥6 انتقالات WORKING↔FAILED\|STOPPED / 60د → P2 `session_flapping` |
| Resolve | استقرار 15 دقيقة WORKING/connected بلا repair |
| P1 SLA | 15 دقيقة حتى تصعيد ثنائي القناة مرة واحدة |

---

## طبقة موثوقية المراقب

### Dead Man's Switch

- نهاية كل تشغيل **ناجح** لـ `whatsapp-ops-analyst`: ping إلى `HEALTHCHECKS_PING_URL`.
- فشل/exception قبل النهاية → **لا ping** → Healthchecks ينبّه بعد تجاوز grace.
- جدول تدقيق: `whatsapp_ops_monitor_runs` (`started_at`, `finished_at`, `ok`, `error`, `heartbeat_pinged`).

### قنوات التنبيه

| Severity | قنوات |
|----------|--------|
| P1 (فتح/تصعيد) | إيميل (مالك + BCC `OPS_ALERT_EMAIL`) **و** Telegram ops و/أو FCM |
| P2 / P3 | إيميل فقط |
| يُعتبر P1 مُبلَّغاً | نجحت قناة واحدة على الأقل؛ تُسجَّل محاولات كل القنوات في `whatsapp_ops_alerts` |

### شرط الاستمرار

| النوع | متى يُفتح |
|--------|-----------|
| P1 فوري | `401` دائم / `repair_needed` / قيد رقم مؤكد / `session_flapping` عند العتبة |
| غير ذلك | استمرار الشرط 5 دقائق في `whatsapp_ops_condition_candidates` |

إن اختفى الشرط قبل 5د → يُحذف المرشّح (لا ضوضاء).

---

## الجداول

| جدول | دور |
|------|-----|
| `whatsapp_ops_facts` | حقائق موحّدة |
| `whatsapp_ops_condition_candidates` | بوابة الاستمرار |
| `whatsapp_ops_incidents` | حوادث + SLA + enrichment |
| `whatsapp_ops_alerts` | محاولات القنوات |
| `whatsapp_ops_lessons` | دروس عبر المستأجرين + `eval_fixture_id` |
| `whatsapp_tenant_dossier` | ملخص مستأجر + `delivery_health` |
| `whatsapp_ops_delivery_stats` | send_accepted vs ack |
| `whatsapp_ops_monitor_runs` | تدقيق التشغيل + heartbeat |

Migration: `migrations/20260728_whatsapp_ops_analyst.sql`  
Cron: `migrations/20260728_whatsapp_ops_analyst_cron.sql`

---

## خدمة Edge: `whatsapp-ops-analyst`

كل دورة ناجحة:

1. سجل `monitor_runs.started_at`
2. استيراد diagnostics → facts؛ حساب delivery + flap لكل جلسة
3. تحديث/إلغاء `condition_candidates`
4. فتح P1 فوري / الباقي بعد استمرار / `session_flapping`
5. قمع بالبصمة؛ تنبيه حسب الخطورة
6. SLA tick + resolve بعد 15د استقرار
7. upsert lessons؛ DeepSeek إثراء فقط
8. استدعاء `whatsapp-health-check` (soft reconnect فقط)
9. **ping Healthchecks** ثم `finished_at` + `heartbeat_pinged`

Auth: `Authorization: Bearer <WHATSAPP_OPS_ANALYST_SECRET|CRON_SECRET>`

### أسرار مطلوبة

| سر | غرض |
|----|------|
| `WHATSAPP_OPS_ANALYST_SECRET` أو `CRON_SECRET` | استدعاء الـ cron |
| `HEALTHCHECKS_PING_URL` | Dead Man's Switch |
| `TELEGRAM_OPS_BOT_TOKEN` + `TELEGRAM_OPS_CHAT_ID` | قناة P1 ثانية |
| `OPS_ALERT_EMAIL` | BCC تشغيل |
| `RESEND_API_KEY` (+ `OPS_ALERT_FROM_EMAIL`) | إيميل |
| `DEEPSEEK_API_KEY` (+ اختياري `DEEPSEEK_MODEL`) | إثراء فقط |
| `FCM_SERVICE_ACCOUNT_JSON` | FCM للمالك إن وُجد توكن |

إعداد Healthchecks.io يدوياً: check period **5m**، grace **10m**، نفس URL الـ ping.

---

## مصادر الحقائق

- `whatsapp-events`: اتصال WORKING/FAILED، 401، repair_needed، delivery ack
- `whatsapp-gateway`: provision/hard_reset storms، send_accepted / send_error (463)
- المحلّل: ingest إضافي من `whatsapp_diagnostic_events` (عواصف audit)

---

## التصنيف (أمثلة)

| Severity | أمثلة |
|----------|--------|
| P1 فوري | repair_needed، 401 دائم، قيد رقم (نمط 463→401) |
| P1 بعد 5د | فشل تسليم صامت (عتبة accepted vs ack) |
| P2 | session_flapping، سلسلة 463، عاصفة provision |
| P3 | false_alarm متكرر بلا فصل دائم |

كل حادث يحمل `playbook_step_id` إلزامي (`constants.ts` / PLAYBOOK).

---

## Regression evals

```bash
deno test supabase/functions/whatsapp-ops-analyst/evals/run_evals_test.ts
```

Fixtures:

- `baqir_463_to_401` — باقر: 463 ثم 401
- `session_flapping_6` — ≥6 انتقالات
- `persistence_silent_fail` — بوابة 5د لفشل صامت

---

## ما لن يفعله النظام

- لن يعتمد على قناة تنبيه واحدة لـ P1
- لن يفتح حوادث غير الفورية قبل استمرار 5د
- لن يضع `user_id` داخل hash البصمة
- لن يغلق عند أول WORKING دون 15د استقرار
- لن يقرر الـ AI الخطورة أو يعمل hard_reset/QR
- لن يعتمد n8n أو مراقبة Cursor كعمود

---

## نشر سريع

1. نفّذ `20260728_whatsapp_ops_analyst.sql` ثم حدّث قيم cron في `20260728_whatsapp_ops_analyst_cron.sql`
2. عيّن الأسرار في Supabase Edge
3. أنشئ check في Healthchecks.io (5m / grace 10m)
4. Deploy: `whatsapp-ops-analyst`, وأعد نشر `whatsapp-events` + `whatsapp-gateway`
5. فعّل الجدولة (`*/5 * * * *`) عبر SQL أو Dashboard
6. راقب صفوفاً في `whatsapp_ops_monitor_runs` و`heartbeat_pinged=true`
