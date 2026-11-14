#!/usr/bin/env bash
# تثبيت CocoaPods لمجلد macos — يتجاوز تعارض RVM مع Homebrew.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
POD_BIN="/opt/homebrew/Cellar/cocoapods/1.16.2_2/bin/pod"
if [[ ! -x "$POD_BIN" ]]; then
  POD_BIN="$(command -v pod || true)"
fi
if [[ -z "$POD_BIN" || ! -x "$POD_BIN" ]]; then
  echo "CocoaPods غير موجود. ثبّته: brew install cocoapods"
  exit 1
fi
cd "$ROOT/macos"
env -u GEM_HOME -u GEM_PATH -u BUNDLE_PATH -u RUBYOPT "$POD_BIN" install
echo "تم pod install بنجاح."
