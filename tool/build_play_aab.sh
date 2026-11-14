#!/usr/bin/env bash
# يبني AAB لـ Google Play بحزمة com.basra.storemanager.app
# دون تغيير حزمة الموقع/GitHub (com.basra.storemanager).
#
# الاستخدام:
#   ./tool/build_play_aab.sh
# الناتج:
#   dist/naboo-play.aab
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p dist

SUPABASE_URL="${SUPABASE_URL:-https://rkofqwcuvbzrnmelvxhz.supabase.co}"
if [[ -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "خطأ: عيّن SUPABASE_ANON_KEY في البيئة قبل البناء."
  exit 1
fi

echo "==> Play AAB  applicationId=com.basra.storemanager.app"
flutter build appbundle --release --no-tree-shake-icons \
  --dart-define="SUPABASE_URL=${SUPABASE_URL}" \
  --dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}" \
  --android-project-arg=naboo.play=true

SRC="build/app/outputs/bundle/release/app-release.aab"
cp -f "$SRC" dist/naboo-play.aab
ls -la dist/naboo-play.aab
echo ""
echo "ارفع dist/naboo-play.aab إلى Play Console → نـابو (com.basra.storemanager.app)"
echo "حزمة الموقع لم تتغير: com.basra.storemanager"
