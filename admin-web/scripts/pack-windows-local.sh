#!/usr/bin/env bash
# يجهّز حزمة محلية لنقل لوحة التراخيص (admin-web) إلى Windows عبر فلاشة/Drive.
# لا ترفع مخرجات هذا السكربت إلى Git — تحتوي أسراراً.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_DIR="${1:-$HOME/Desktop/NABOO-Admin-Windows}"
STAMP="$(date +%Y%m%d-%H%M)"

echo "▶ مصدر اللوحة: $ROOT"
echo "▶ الوجهة: $OUT_DIR"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/secrets"

# نسخ الكود بدون node_modules و .next
rsync -a \
  --exclude node_modules \
  --exclude .next \
  --exclude '*.log' \
  --exclude tsconfig.tsbuildinfo \
  "$ROOT/" "$OUT_DIR/"

# أسرار التشغيل المحلي
if [[ ! -f "$ROOT/.env.local" ]]; then
  echo "خطأ: لا يوجد admin-web/.env.local"
  exit 1
fi

# نسخ مفتاح JWT إن وُجد على المسار المحلي
KEY_SRC=""
if [[ -f "$HOME/license_private.pem" ]]; then
  KEY_SRC="$HOME/license_private.pem"
fi
if [[ -n "$KEY_SRC" ]]; then
  cp "$KEY_SRC" "$OUT_DIR/secrets/license_private.pem"
  echo "▶ نُسخ مفتاح الترخيص إلى secrets/license_private.pem"
fi

# إعادة كتابة مسار المفتاح ليكون نسبياً ليعمل على Windows
python3 - <<PY
from pathlib import Path
import re
env_path = Path("$OUT_DIR") / ".env.local"
text = env_path.read_text()
# مسار نسبي يعمل من مجلد admin-web على أي جهاز
text2 = re.sub(
    r'^LICENSE_JWT_PRIVATE_KEY_PATH=.*$',
    'LICENSE_JWT_PRIVATE_KEY_PATH=./secrets/license_private.pem',
    text,
    flags=re.M,
)
env_path.write_text(text2)
print("▶ حدّث LICENSE_JWT_PRIVATE_KEY_PATH ليصبح نسبياً")
PY

# تعليمات عربية للمستخدم
cat > "$OUT_DIR/اقرأني-ويندوز.txt" <<'EOF'
لوحة NABOO الإدارية — تشغيل محلي على Windows
=============================================

1) ثبّت Node.js LTS من:
   https://nodejs.org
   (اختر النسخة LTS ثم Next / Install)

2) انسخ هذا المجلد كاملاً إلى حاسبة الويندوز (فلاشة أو Drive).
   لا ترفع هذا المجلد إلى الإنترنت العامة — فيه أسرار.

3) في مجلد اللوحة انقر نقراً مزدوجاً على:
   تشغيل لوحة NABOO.bat

4) انتظر حتى يظهر في الناسوداء:
   Ready / Local: http://localhost:3010

5) افتح المتصفح على:
   http://localhost:3010

6) أدخل كلمة مرور لوحة المطوّر (نفس التي على الماك).

إيقاف اللوحة: في النافذة السوداء اضغط Ctrl+C

ملاحظات:
- أول تشغيل قد يأخذ دقائق (تحميل npm).
- يجب وجود الإنترنت لأن اللوحة تتصل بـ Supabase.
- لا تشارك مجلد secrets أو ملف .env.local مع أحد.
EOF

# أرشيف للنقل السريع
ZIP="$HOME/Desktop/NABOO-Admin-Windows-${STAMP}.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$OUT_DIR" "$ZIP"

echo
echo "✅ جاهز"
echo "   المجلد: $OUT_DIR"
echo "   الأرشيف: $ZIP"
echo "انسخ أحدهما إلى فلاشة/Drive ثم على الويندوز شغّل: تشغيل لوحة NABOO.bat"
