#!/usr/bin/env bash
# بناء نسخة الويب لـ NABOO ERP ونسخها إلى مجلد النشر الاختياري.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BASE_HREF="${BASE_HREF:-/app/}"
OUT_DIR="${OUT_DIR:-build/web}"

DEFINES=()
if [[ -n "${SUPABASE_URL:-}" ]]; then
  DEFINES+=(--dart-define="SUPABASE_URL=${SUPABASE_URL}")
fi
if [[ -n "${SUPABASE_ANON_KEY:-}" ]]; then
  DEFINES+=(--dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}")
fi

echo "==> flutter build web (base-href=${BASE_HREF})"
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run \
  --base-href="${BASE_HREF}" \
  "${DEFINES[@]}"

# بصمة بسيطة لكسر كاش الـ service worker عند الحاجة
BUILD_ID="$(date -u +%Y%m%d%H%M%S)"
printf '{"build_id":"%s","built_at":"%s"}\n' "$BUILD_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > "${OUT_DIR}/naboo-build.json"

echo "==> Built: ${OUT_DIR}"
echo "    Deploy example: cp -R ${OUT_DIR}/ ../naboo/app/ && firebase deploy --only hosting"
