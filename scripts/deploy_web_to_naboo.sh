#!/usr/bin/env bash
# بناء Flutter Web ونشره إلى موقع naboo (/app/).
set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NABOO_ROOT="${NABOO_ROOT:-$HOME/Development/naboo}"

if [[ -f "$APP_ROOT/.env.local.sh" ]]; then
  # shellcheck disable=SC1091
  source "$APP_ROOT/.env.local.sh"
fi

SUPABASE_URL="${SUPABASE_URL:-https://rkofqwcuvbzrnmelvxhz.supabase.co}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"

if [[ -z "$SUPABASE_ANON_KEY" ]]; then
  echo "تحذير: SUPABASE_ANON_KEY غير مضبوط — يُستخدم الافتراضي من supabase_config.dart"
  SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJrb2Zxd2N1dmJ6cm5tZWx2eGh6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYzNDEyNjksImV4cCI6MjA5MTkxNzI2OX0.F5x59dpqtEqQn_MrxA7S07qw6HH136ZMW_P7nfgGFkQ"
fi

if [[ ! -d "$NABOO_ROOT" ]]; then
  echo "مجلد naboo غير موجود: $NABOO_ROOT"
  exit 1
fi

echo "▶ إعداد SQLite للويب (sqflite_sw.js + sqlite3.wasm)..."
cd "$APP_ROOT"
dart run sqflite_common_ffi_web:setup

echo "▶ بناء Flutter Web..."
flutter pub get
BUILD_DEFINES=(
  --dart-define=SUPABASE_URL="$SUPABASE_URL"
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
  --dart-define=WEB_APP_ORIGIN="${WEB_APP_ORIGIN:-https://naboo-93580.web.app}"
)
if [[ -n "${GOOGLE_WEB_CLIENT_ID:-}" ]]; then
  BUILD_DEFINES+=(--dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID")
fi
flutter build web --release \
  --base-href=/app/ \
  --no-tree-shake-icons \
  "${BUILD_DEFINES[@]}"

echo "▶ نسخ build/web → $NABOO_ROOT/app/"
rm -rf "$NABOO_ROOT/app"
cp -R build/web "$NABOO_ROOT/app"

# Flutter لا ينسخ sqflite web binaries تلقائياً — نضيفها يدوياً.
for f in sqflite_sw.js sqlite3.wasm oauth_complete.html; do
  if [[ -f "web/$f" ]]; then
    cp "web/$f" "$NABOO_ROOT/app/$f"
  fi
done

BUILD_ID="$(date -u +%Y-%m-%dT%H:%MZ)"
WEB_ORIGIN="${WEB_APP_ORIGIN:-https://naboo-93580.web.app}"
echo "{\"build_id\":\"$BUILD_ID\",\"source\":\"basra_store_manager\",\"sqlite_web\":true,\"web_app_origin\":\"$WEB_ORIGIN\"}" > "$NABOO_ROOT/app/naboo-build.json"

echo "✅ جاهز للنشر. نفّذ:"
echo "   cd \"$NABOO_ROOT\" && firebase deploy --only hosting"
