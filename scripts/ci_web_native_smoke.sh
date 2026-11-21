#!/usr/bin/env bash
# بوابة انحدار سريعة: بناء ويب + APK debug.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> web release"
./scripts/build_web.sh

echo "==> android debug apk"
flutter build apk --debug

echo "==> OK — web + apk"
echo "Manual same-account checks: docs/auth/WEB_SAME_ACCOUNT_MANUAL_TEST_AR.md"
