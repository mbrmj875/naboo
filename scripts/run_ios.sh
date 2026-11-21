#!/usr/bin/env bash
# تشغيل iOS من الطرفية (PATH صحيح + pod install)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/Users/mohamed123/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
cd "$ROOT"
bash scripts/ios_pod_install.sh
exec flutter run -d "${1:-iPhone 17}" "$@"
