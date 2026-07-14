#!/usr/bin/env bash
# CocoaPods عبر RVM — استخدمه قبل التشغيل من Android Studio إن فشل pod.
set -euo pipefail
cd "$(dirname "$0")/../ios"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
exec /Users/mohamed123/bin/pod install "$@"
