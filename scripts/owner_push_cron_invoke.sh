#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# استدعاء يدوي لـ Edge Function: owner-alert-push-cron
# يُشغّل دورة cron كاملة: prefs → snapshot → evaluate → cooldown → FCM
#
# الاستخدام (إنتاج):
#   export CRON_SECRET='your-cron-secret'
#   export SUPABASE_URL='https://YOUR_PROJECT.supabase.co'
#   ./scripts/owner_push_cron_invoke.sh
#
# محلياً (supabase start + functions serve):
#   supabase functions serve owner-alert-push-cron --no-verify-jwt &
#   export SUPABASE_LOCAL=1
#   export CRON_SECRET='dev-secret'   # إن عرّفته في .env.local للـ serve
#   ./scripts/owner_push_cron_invoke.sh
#
# عبر Supabase CLI (بديل):
#   supabase functions invoke owner-alert-push-cron \
#     --project-ref YOUR_REF \
#     --method POST \
#     --body '{}' \
#     --header "Authorization: Bearer $CRON_SECRET"
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# تحميل اختياري من .env.local (لا تُ commit الأسرار)
if [[ -f "$ROOT_DIR/.env.local" ]]; then
  # shellcheck disable=SC1091
  set -a
  source "$ROOT_DIR/.env.local"
  set +a
fi

SUPABASE_URL="${SUPABASE_URL:-https://rkofqwcuvbzrnmelvxhz.supabase.co}"
CRON_SECRET="${CRON_SECRET:-}"

if [[ "${SUPABASE_LOCAL:-0}" == "1" ]]; then
  BASE_URL="${SUPABASE_LOCAL_URL:-http://127.0.0.1:54321}"
  FN_URL="${BASE_URL}/functions/v1/owner-alert-push-cron"
else
  FN_URL="${SUPABASE_URL%/}/functions/v1/owner-alert-push-cron"
fi

if [[ -z "$CRON_SECRET" ]]; then
  echo "⚠️  CRON_SECRET غير معيّن."
  echo "   export CRON_SECRET='…'  (نفس Secret في Edge Functions → Secrets)"
  echo "   إن لم تُعرّف CRON_SECRET على الخادم، اتركه فارغاً وعدّل index.ts — حالياً مطلوب إن وُجد."
  read -r -p "متابعة بدون Authorization؟ [y/N] " ans
  [[ "${ans:-N}" =~ ^[yY]$ ]] || exit 1
fi

AUTH_HEADER=()
if [[ -n "$CRON_SECRET" ]]; then
  AUTH_HEADER=(-H "Authorization: Bearer ${CRON_SECRET}")
fi

echo "→ POST ${FN_URL}"
echo ""

HTTP_CODE="$(
  curl -sS -w '%{http_code}' -o /tmp/owner_push_cron_response.json \
    -X POST \
    "${AUTH_HEADER[@]}" \
    -H "Content-Type: application/json" \
    -d '{}' \
    "$FN_URL"
)"

echo "HTTP ${HTTP_CODE}"
if command -v jq >/dev/null 2>&1; then
  jq . /tmp/owner_push_cron_response.json
else
  cat /tmp/owner_push_cron_response.json
  echo
fi

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo ""
  echo "✓ نجح الاستدعاء — راجع حقل sent في JSON."
  echo "  sent: [] فارغ → cooldown أو لا تنبيهات أو لا snapshot/tokens."
  echo "  skipped: … يوضّح السبب (no_tokens, no_snapshot, cooldown_or_clear, …)"
  exit 0
fi

echo ""
echo "✗ فشل — تحقق من CRON_SECRET ونشر الدالة وSecrets (FCM_SERVICE_ACCOUNT_JSON)."
exit 1
