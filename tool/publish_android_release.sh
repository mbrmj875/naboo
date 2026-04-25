#!/usr/bin/env bash
# يبني APK وينسخه إلى dist/
#
# الاستخدام:
#   ./tool/publish_android_release.sh
#       بناء فقط، ثم يمكنك الرفع يدوياً:
#       gh release upload v2.0.1 dist/naboo.apk dist/naboo-arm32.apk --repo mbrmj875/SQLB --clobber
#
#   ./tool/publish_android_release.sh v2.0.1
#       بناء ثم رفع الملفين إلى إصدار موجود بالوسم v2.0.0 (يتطلب: gh auth login ووجود Release بهذا الوسم)
#
# بديل: دفع وسم جديد ليشغّل GitHub Actions تلقائياً:
#   git tag vX.Y.Z && git push origin vX.Y.Z
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p dist
echo "==> flutter build apk --release --split-per-abi"
flutter build apk --release --split-per-abi
cp -f build/app/outputs/flutter-apk/app-arm64-v8a-release.apk dist/naboo.apk
cp -f build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk dist/naboo-arm32.apk
ls -la dist/naboo.apk dist/naboo-arm32.apk

RELEASE_TAG="${1:-}"
if [[ -n "$RELEASE_TAG" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo ""
    echo "!! gh غير مثبت. ثبّت GitHub CLI: https://cli.github.com/"
    exit 1
  fi
  echo ""
  echo "==> gh release upload $RELEASE_TAG … --repo mbrmj875/SQLB --clobber"
  gh release upload "$RELEASE_TAG" dist/naboo.apk dist/naboo-arm32.apk \
    --repo mbrmj875/SQLB --clobber
  echo "==> تم الرفع."
else
  echo ""
  echo "==> رفع يدوي بـ GitHub CLI (بعد إنشاء الإصدار على GitHub إن لزم):"
  echo "    gh release upload v2.0.1 dist/naboo.apk dist/naboo-arm32.apk --repo mbrmj875/SQLB --clobber"
  echo ""
  echo "==> أو تلقائياً عبر الوسم (GitHub Actions):"
  echo "    git tag vX.Y.Z && git push origin vX.Y.Z"
  echo ""
  echo "==> أو تشغيل هذا السكربت مع وسم الإصدار:"
  echo "    ./tool/publish_android_release.sh v2.0.1"
fi
