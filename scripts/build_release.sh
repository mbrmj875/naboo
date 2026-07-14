#!/usr/bin/env bash
# scripts/build_release.sh
# بناء إصدار (release) لأي منصة مع تمرير المفاتيح تلقائياً من env/prod.env.
#
# الاستعمال:
#   bash scripts/build_release.sh apk        # Android APK (تثبيت مباشر / تجربة)
#   bash scripts/build_release.sh appbundle  # Android AAB (للنشر على Play)
#   bash scripts/build_release.sh ios        # iOS IPA (يتطلب macOS + Xcode)
#   bash scripts/build_release.sh macos      # تطبيق macOS
#   bash scripts/build_release.sh web        # نسخة الويب
#
# المفاتيح تُقرأ مرة واحدة من env/prod.env — لا تكتبها يدوياً.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ENV_FILE="env/prod.env"
TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  echo "استعمال: bash scripts/build_release.sh [apk|appbundle|ios|macos|windows|web]"
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "خطأ: $ENV_FILE غير موجود."
  echo "انسخ المثال واملأ القيم:  cp env/prod.env.example env/prod.env"
  exit 1
fi

echo "بناء [$TARGET] بالإصدار (release) باستخدام $ENV_FILE ..."

case "$TARGET" in
  apk)
    flutter build apk --release --dart-define-from-file="$ENV_FILE"
    ;;
  appbundle|aab)
    flutter build appbundle --release --dart-define-from-file="$ENV_FILE"
    ;;
  ios)
    flutter build ipa --release --dart-define-from-file="$ENV_FILE"
    ;;
  macos)
    flutter build macos --release --dart-define-from-file="$ENV_FILE"
    ;;
  windows)
    echo "ابنِ Windows من جهاز Windows عبر: scripts\\build_release.ps1 windows"
    exit 1
    ;;
  web)
    flutter build web --release --dart-define-from-file="$ENV_FILE"
    ;;
  *)
    echo "منصة غير معروفة: $TARGET"
    exit 1
    ;;
esac

echo "تم البناء بنجاح ✅"
