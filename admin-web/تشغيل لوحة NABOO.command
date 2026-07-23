#!/bin/bash
# انقر نقراً مزدوجاً لتشغيل لوحة NABOO الإدارية من Finder / سطح المكتب.
# يحرّر المنفذ 3010، يحذف .next، ويعيد التشغيل من نفس المسار.
set -euo pipefail

# يعمل حتى لو فتحت الملف كاختصار من سطح المكتب
SOURCE="${BASH_SOURCE[0]:-$0}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
ROOT="$(cd -P "$(dirname "$SOURCE")" && pwd)"

cd "$ROOT" || exit 1
exec bash "./scripts/dev-clean.sh"
