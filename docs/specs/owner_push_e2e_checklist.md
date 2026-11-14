# Owner Push — E2E Checklist (Android + iOS)

> تحقق يدوي بعد نشر Edge Function + FCM.

## 0 — متطلبات Supabase

- [ ] `20260531_owner_alert_push.sql`
- [ ] `20260531_owner_push_alert_log.sql`
- [ ] `20260532_owner_alert_feature_flags.sql` (إن لزم)
- [ ] Secrets: `FCM_SERVICE_ACCOUNT_JSON`, `CRON_SECRET`
- [ ] `supabase functions deploy owner-alert-push-cron`
- [ ] جدولة cron (Dashboard أو pg_cron)

## 1 — Flutter (جهاز المالk)

- [ ] تسجيل دخول **owner**
- [ ] تفعيل v3 Beta + Push لتنبيه واحد في Owner Studio
- [ ] مزامنة سحابية (`مزامنة الآن`) — لقطة `app_snapshots` محدّثة
- [ ] تحقق Supabase: صف في `owner_alert_preferences` + `owner_fcm_tokens`

## 2 — Android

- [ ] `POST_NOTIFICATIONS` ممنوح (Android 13+)
- [ ] Logcat: لا أخطاء `OwnerFcm` عند الإقلاع
- [ ] أغلق التطبيق → **استدعِ cron يدوياً** (انظر أدناه)
- [ ] إشعار يظهر في شريط النظام (قناة `naboo_alerts`)
- [ ] الضغط على الإشعار → يفتح الشاشة الصحيحة (ديون / مخزون / …)

### استدعاء cron يدوياً (E2E)

```bash
cp scripts/owner_push.env.example .env.local
# عدّل CRON_SECRET و SUPABASE_URL

export CRON_SECRET='…'
./scripts/owner_push_cron_invoke.sh
```

**Supabase CLI (بديل):**

```bash
supabase functions invoke owner-alert-push-cron \
  --project-ref rkofqwcuvbzrnmelvxhz \
  --method POST \
  --body '{}' \
  --header "Authorization: Bearer $CRON_SECRET"
```

**محلي:**

```bash
supabase functions serve owner-alert-push-cron --no-verify-jwt
SUPABASE_LOCAL=1 CRON_SECRET=dev ./scripts/owner_push_cron_invoke.sh
```

### اختبار Router فقط (FCM مباشر — بدون cron)

```bash
export FCM_SERVICE_ACCOUNT_JSON=/path/to/adminsdk.json
export FCM_DEVICE_TOKEN='…'
export OWNER_TEST_TENANT_ID=1
./scripts/owner_push_fcm_test_payload.sh
```

### Firebase Console — Custom data

| key | value |
|-----|-------|
| `owner_alert_id` | `retail_stock_shortage` |
| `tenant_id` | `1` |
| `owner_action_kind` | `purchasePdf` |

## 3 — iOS

- [ ] Xcode: **Signing & Capabilities → Push Notifications**
- [ ] `Runner.entitlements`: `aps-environment` = `development` (debug) أو `production` (TestFlight/App Store)
- [ ] Firebase Console: رفع **APNs Auth Key** (.p8)
- [ ] جهاز حقيقي (Simulator لا يدعم Push)
- [ ] السماح بالإشعارات عند الطلب
- [ ] نفس خطوات Android (إغلاق → cron → فتح من الإشعار)

## 4 — Feature Gate

- [ ] عطّل `enableDebts` في إعدادات المتجر
- [ ] تحقق `owner_alert_preferences.feature_flags`
- [ ] cron لا يرسل `debt_customers` حتى مع Push مفعّل

## 5 — Cooldown

- [ ] أرسل cron مرتين خلال 6 ساعات بنفس العدد → Push واحد فقط
- [ ] زِد عدد النواقص → Push جديد فوراً

## 6 — Regression آلي

```bash
flutter test test/owner/
deno test supabase/functions/owner-alert-push-cron/evaluate_alerts_test.ts
```
