#!/usr/bin/env bash
# تشغيل الاختبار النهائي لمساعد نابو من الحاسوب على هاتف موصول (م7-3).
#
# القاعدة: نسخة الاختبار com.basra.storemanager.qa فقط، تُثبَّت بـ adb install.
# لا flutter run ولا flutter drive على هاتف المالك (حذف نسخة المتجر مرة).
# كل أمر يطبع «نجح» أو «فشل» لكل خطوة آلية، والنتائج في build/phone_test/<اليوم>/.
#
# الأوامر:
#   build                      يبني نسخة الاختبار (APK)
#   preflight                  الهاتف موصول، ويحفظ بصمة نسخ المتجر قبل أي تثبيت
#   install                    preflight ثم تثبيت نسخة الاختبار ثم التأكد أن نسخ المتجر لم تتغير
#   check-store                يقارن نسخ المتجر بالبصمة المحفوظة
#   open                       يفتح نسخة الاختبار
#   ask "<سؤال>" [route]       يرسل السؤال عبر naboo-qa://assistant/ask وينتظر الرد في السجل
#   state                      يطبع حالة الشات الحالية
#   reset                      يمسح محادثات المستخدم الحالي
#   seed [--over]              يبذر محل النموذج على الهاتف (محل فارغ فقط، أو فوق بيانات حساب التجربة بـ --over)
#   shot <اسم>                 لقطة شاشة باسم
#   push-fixtures              ينقل صور الاختبار إلى معرض الهاتف
#   deeplink <uri>             يفتح أي رابط في نسخة الاختبار (مثل رابط شاشة)
set -uo pipefail

QA_PKG="com.basra.storemanager.qa"
STORE_PKGS=("com.basra.storemanager" "com.basra.storemanager.app")
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/phone_test/$(date +%Y-%m-%d)"
APK="$ROOT/build/app/outputs/flutter-apk/app-release.apk"
FIXTURES="$ROOT/test/assistant/phone_fixtures"
STAMP="$OUT/store_stamp.txt"
REPLY_TIMEOUT="${REPLY_TIMEOUT:-90}"
mkdir -p "$OUT"

ok() { printf '✅ نجح: %s\n' "$*"; echo "PASS $*" >>"$OUT/results.log"; }
fail() { printf '❌ فشل: %s\n' "$*"; echo "FAIL $*" >>"$OUT/results.log"; }
die() { fail "$*"; exit 1; }

need_device() {
  local n
  n=$(adb devices | awk 'NR>1 && $2=="device"' | wc -l | tr -d ' ')
  [ "$n" = "1" ] || die "هاتف واحد موصول بتصحيح USB (الموجود: $n)"
}

# بصمة نسخة: الإصدار ووقت أول تثبيت. وقت أول تثبيت يتغير فقط إن حُذفت النسخة وثُبّتت من جديد.
stamp_of() {
  local p="$1" info
  info=$(adb shell dumpsys package "$p" 2>/dev/null | tr -d '\r' | grep -E 'versionName=|firstInstallTime=' | sort -u | tr '\n' ' ')
  if [ -z "$info" ]; then echo "$p absent"; else echo "$p $info"; fi
}

store_stamp() { for p in "${STORE_PKGS[@]}"; do stamp_of "$p"; done; }

cmd_build() {
  cd "$ROOT" || exit 1
  export PATH="$HOME/development/flutter/bin:$PATH"
  flutter build apk --release --no-tree-shake-icons --dart-define-from-file=env/prod.env \
    --android-project-arg naboo.qa=true || die "بناء نسخة الاختبار"
  [ -f "$APK" ] && ok "بناء نسخة الاختبار: $APK" || die "لا يوجد APK"
}

cmd_preflight() {
  need_device
  ok "هاتف واحد موصول"
  store_stamp >"$STAMP"
  if grep -q -v ' absent$' "$STAMP"; then ok "بصمة نسخ المتجر محفوظة"; else fail "لا نسخة متجر على الهاتف (تحقق يدوياً)"; fi
  cat "$STAMP"
}

cmd_check_store() {
  need_device
  [ -f "$STAMP" ] || die "لا بصمة محفوظة، شغّل preflight أولاً"
  if diff -q <(store_stamp) "$STAMP" >/dev/null; then
    ok "نسخ المتجر وبياناتها كما هي"
  else
    fail "نسخ المتجر تغيّرت!"
    diff <(store_stamp) "$STAMP"
    exit 1
  fi
}

cmd_install() {
  cmd_preflight
  [ -f "$APK" ] || die "لا يوجد APK، شغّل build أولاً"
  # تأكيد أن الملف نسخة الاختبار لا نسخة المتجر، قبل أي تثبيت.
  local badging
  badging=$(find "$HOME/Library/Android/sdk/build-tools" -name aapt2 2>/dev/null | sort | tail -1)
  if [ -n "$badging" ]; then
    "$badging" dump packagename "$APK" | grep -qx "$QA_PKG" || die "الملف ليس $QA_PKG"
    ok "الملف هو $QA_PKG"
  fi
  adb install -r "$APK" >/dev/null || die "adb install"
  adb shell pm list packages | tr -d '\r' | grep -qx "package:$QA_PKG" && ok "نسخة الاختبار مثبّتة" || fail "نسخة الاختبار غير موجودة"
  cmd_check_store
}

cmd_open() {
  need_device
  adb shell monkey -p "$QA_PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 && ok "فُتحت نسخة الاختبار" || fail "فتح نسخة الاختبار"
}

# وقت الهاتف الآن بصيغة logcat، لقراءة ما بعده فقط.
phone_now() { adb shell date +'%m-%d\ %H:%M:%S.000' | tr -d '\r'; }

# يجمع أسطر NABOO_QA <kind> (مقسّمة أو لا) بعد وقت معيّن ويطبع JSON واحداً.
read_qa() {
  local kind="$1" since="$2"
  adb logcat -d -v raw -T "$since" 'flutter:I' '*:S' 2>/dev/null | tr -d '\r' | python3 -c '
import sys, json
kind = sys.argv[1]
parts, whole = {}, None
for line in sys.stdin:
    line = line.strip()
    if not line.startswith("NABOO_QA " + kind + " "):
        if line.startswith("NABOO_QA error "):
            whole = line[len("NABOO_QA error "):]
        continue
    rest = line[len("NABOO_QA " + kind + " "):]
    head = rest.split(" ", 1)[0]
    if "/" in head and head.replace("/", "").isdigit():
        i, n = map(int, head.split("/"))
        parts[i] = rest.split(" ", 1)[1]
        if len(parts) == n:
            whole = "".join(parts[k] for k in range(1, n + 1)); parts = {}
    else:
        whole = rest
if whole:
    # سطر مقطوع في السجل لا يوقف الانتظار: يُطبع كما هو.
    try:
        print(json.dumps(json.loads(whole), ensure_ascii=False, indent=1))
    except ValueError:
        print(json.dumps({"raw": whole}, ensure_ascii=False))
' "$kind"
}

send_link() {
  adb shell am start -W -a android.intent.action.VIEW -d "'$1'" "$QA_PKG" >/dev/null 2>&1
}

wait_qa() {
  local kind="$1" since="$2" out=""
  for _ in $(seq 1 "$REPLY_TIMEOUT"); do
    out=$(read_qa "$kind" "$since")
    [ -n "$out" ] && break
    sleep 1
  done
  printf '%s' "$out"
}

cmd_ask() {
  need_device
  local q="${1:-}" route="${2:-}"
  [ -n "$q" ] || die "اكتب السؤال"
  local enc since res name
  enc=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$q")
  local uri="naboo-qa://assistant/ask?q=$enc"
  [ -n "$route" ] && uri="$uri&route=$route"
  since=$(phone_now)
  send_link "$uri" || die "إرسال الرابط"
  res=$(wait_qa reply "$since")
  name="ask_$(date +%H%M%S)"
  adb exec-out screencap -p >"$OUT/$name.png" 2>/dev/null
  if [ -z "$res" ]; then
    fail "لا رد خلال ${REPLY_TIMEOUT} ثانية: $q"
    return 1
  fi
  printf '%s\n' "$res" >"$OUT/$name.json"
  printf '%s\n' "$res"
  if printf '%s' "$res" | grep -q '"error": "'; then
    fail "رد بخطأ: $q"
  else
    ok "رد على: $q ($OUT/$name.png)"
  fi
}

cmd_state() {
  need_device
  local since res
  since=$(phone_now)
  send_link "naboo-qa://assistant/state" || die "إرسال الرابط"
  res=$(wait_qa state "$since")
  [ -n "$res" ] && { printf '%s\n' "$res"; ok "حالة الشات"; } || fail "لا حالة في السجل"
}

cmd_who() {
  need_device
  local since res
  since=$(phone_now)
  send_link "naboo-qa://assistant/who" || die "إرسال الرابط"
  res=$(wait_qa who "$since")
  [ -n "$res" ] && { printf '%s\n' "$res"; ok "المستخدم الحالي"; } || fail "لا جواب في السجل"
}

cmd_reset() {
  need_device
  local since res
  since=$(phone_now)
  send_link "naboo-qa://assistant/reset" || die "إرسال الرابط"
  res=$(wait_qa reset "$since")
  [ -n "$res" ] && ok "مسح المحادثات $res" || fail "لم يؤكد المسح"
}

cmd_seed() {
  need_device
  local since res link="naboo-qa://assistant/seed"
  [ "${1:-}" = "--over" ] && link="$link?over=1"
  since=$(phone_now)
  send_link "$link" || die "إرسال الرابط"
  res=$(wait_qa seed "$since")
  if [ -z "$res" ]; then
    fail "البذر (راجع: NABOO_QA error في السجل)"
  elif printf '%s' "$res" | grep -q '"error"'; then
    printf '%s\n' "$res"
    fail "البذر رُفض (shop_not_empty يعني أن الحساب ليس محل النموذج الفارغ)"
  else
    printf '%s\n' "$res"
    ok "بذر محل النموذج"
  fi
}

cmd_shot() {
  need_device
  local name="${1:-shot_$(date +%H%M%S)}"
  adb exec-out screencap -p >"$OUT/$name.png" && ok "لقطة $OUT/$name.png" || fail "لقطة $name"
}

cmd_push_fixtures() {
  need_device
  [ -d "$FIXTURES" ] || die "لا مجلد $FIXTURES"
  local n=0 f
  adb shell mkdir -p /sdcard/Pictures/NabooTest
  for f in "$FIXTURES"/*.{jpg,jpeg,png}; do
    [ -f "$f" ] || continue
    adb push "$f" /sdcard/Pictures/NabooTest/ >/dev/null && n=$((n + 1))
    adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
      -d "file:///sdcard/Pictures/NabooTest/$(basename "$f")" >/dev/null 2>&1
  done
  [ "$n" -gt 0 ] && ok "نُقلت $n صورة إلى Pictures/NabooTest" || fail "لا صور لنقلها"
}

cmd_deeplink() {
  need_device
  send_link "${1:?رابط}" && ok "فُتح ${1}" || fail "فتح ${1}"
}

case "${1:-}" in
  build) cmd_build ;;
  preflight) cmd_preflight ;;
  install) cmd_install ;;
  check-store) cmd_check_store ;;
  open) cmd_open ;;
  ask) shift; cmd_ask "$@" ;;
  state) cmd_state ;;
  who) cmd_who ;;
  reset) cmd_reset ;;
  seed) shift; cmd_seed "$@" ;;
  shot) shift; cmd_shot "$@" ;;
  push-fixtures) cmd_push_fixtures ;;
  deeplink) shift; cmd_deeplink "$@" ;;
  *) sed -n '2,23p' "$0"; exit 2 ;;
esac
