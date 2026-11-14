#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# اختبار مسار Flutter Router فقط — FCM data payload (بدون cron)
# يتطلب توكن جهاز من owner_fcm_tokens أو FCM_DEVICE_TOKEN
#
# الاستخدام:
#   export FCM_SERVICE_ACCOUNT_JSON='/path/to/firebase-adminsdk.json'
#   export FCM_DEVICE_TOKEN='…'   # من Logcat/Debug أو owner_fcm_tokens
#   export OWNER_TEST_TENANT_ID=1
#   export OWNER_TEST_ALERT_ID=retail_stock_shortage
#   export OWNER_TEST_ACTION_KIND=purchasePdf
#   ./scripts/owner_push_fcm_test_payload.sh
#
# بديل أسهل: Firebase Console → Cloud Messaging → Send test message
#   → Custom data: owner_alert_id, tenant_id, owner_action_kind
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

FCM_SA_JSON="${FCM_SERVICE_ACCOUNT_JSON:-}"
FCM_DEVICE_TOKEN="${FCM_DEVICE_TOKEN:-}"
TENANT_ID="${OWNER_TEST_TENANT_ID:-1}"
ALERT_ID="${OWNER_TEST_ALERT_ID:-retail_stock_shortage}"
ACTION_KIND="${OWNER_TEST_ACTION_KIND:-purchasePdf}"
TITLE_AR="${OWNER_TEST_TITLE_AR:-اختبار نواقص الرفوف}"
BODY_AR="${OWNER_TEST_BODY_AR:-صنف واحد ناقص — اختبار E2E}"

if [[ -z "$FCM_DEVICE_TOKEN" ]]; then
  echo "export FCM_DEVICE_TOKEN='…'  (توكن FCM للمالk على الجهاز)"
  exit 1
fi

if [[ -z "$FCM_SA_JSON" || ! -f "$FCM_SA_JSON" ]]; then
  echo "export FCM_SERVICE_ACCOUNT_JSON='/path/to/service-account.json'"
  exit 1
fi

PROJECT_ID="$(jq -r .project_id "$FCM_SA_JSON")"
CLIENT_EMAIL="$(jq -r .client_email "$FCM_SA_JSON")"
PRIVATE_KEY="$(jq -r .private_key "$FCM_SA_JSON")"

if ! command -v jq >/dev/null 2>&1; then
  echo "يتطلب jq: brew install jq"
  exit 1
fi

# JWT for Google OAuth (FCM v1)
NOW="$(date +%s)"
EXP="$((NOW + 3600))"
HEADER="$(printf '{"alg":"RS256","typ":"JWT"}' | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')"
CLAIM="$(printf '{"iss":"%s","scope":"https://www.googleapis.com/auth/firebase.messaging","aud":"https://oauth2.googleapis.com/token","iat":%s,"exp":%s}' \
  "$CLIENT_EMAIL" "$NOW" "$EXP" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')"
UNSIGNED="${HEADER}.${CLAIM}"
SIGNATURE="$(printf '%s' "$UNSIGNED" | openssl dgst -sha256 -sign <(printf '%s' "$PRIVATE_KEY") -binary | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')"
JWT="${UNSIGNED}.${SIGNATURE}"

ACCESS_TOKEN="$(curl -sS -X POST https://oauth2.googleapis.com/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" \
  --data-urlencode "assertion=${JWT}" | jq -r .access_token)"

if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
  echo "فشل الحصول على access_token من Google"
  exit 1
fi

PAYLOAD="$(jq -n \
  --arg token "$FCM_DEVICE_TOKEN" \
  --arg title "$TITLE_AR" \
  --arg body "$BODY_AR" \
  --arg alert "$ALERT_ID" \
  --arg tenant "$TENANT_ID" \
  --arg kind "$ACTION_KIND" \
  '{
    message: {
      token: $token,
      notification: { title: $title, body: $body },
      data: {
        owner_alert_id: $alert,
        tenant_id: $tenant,
        owner_action_kind: $kind,
        title_ar: $title,
        body_ar: $body
      },
      android: {
        priority: "HIGH",
        notification: { channel_id: "naboo_alerts" }
      },
      apns: {
        headers: { "apns-priority": "10" },
        payload: { aps: { sound: "default" } }
      }
    }
  }')"

echo "→ FCM projects/${PROJECT_ID}/messages:send"
RESP="$(curl -sS -X POST \
  "https://fcm.googleapis.com/v1/projects/${PROJECT_ID}/messages:send" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")"

echo "$RESP" | jq .

if echo "$RESP" | jq -e .name >/dev/null 2>&1; then
  echo ""
  echo "✓ أُرسل — افتح التطبيق كـ owner على tenant_id=${TENANT_ID} واضغط الإشعار."
  exit 0
fi

echo "✗ فشل الإرسال"
exit 1
