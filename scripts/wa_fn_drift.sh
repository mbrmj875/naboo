#!/usr/bin/env bash
# Compares every deployed WhatsApp Edge Function with the local files.
# Read-only: downloads to a temp folder and changes nothing on the server.
# Usage: scripts/wa_fn_drift.sh [function-name ...]
set -uo pipefail
REF="${SUPABASE_PROJECT_REF:-rkofqwcuvbzrnmelvxhz}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if [ "$#" -gt 0 ]; then
  SLUGS="$*"
else
  SLUGS="$(cd "$ROOT" && supabase functions list --project-ref "$REF" -o json 2>/dev/null |
    python3 -c "import sys,json;print(' '.join(sorted(f['slug'] for f in json.load(sys.stdin) if f['slug'].startswith('whatsapp-'))))")"
fi
status=0
for slug in $SLUGS; do
  dir="$TMP/$slug"; mkdir -p "$dir"
  if ! (cd "$dir" && supabase functions download "$slug" --project-ref "$REF" --use-api >/dev/null 2>&1); then
    echo "ERROR    $slug: download failed"; status=2; continue
  fi
  changed=""; missing=""; n=0
  while IFS= read -r f; do
    rel="${f#"$dir"/}"
    n=$((n + 1))
    if [ ! -f "$ROOT/$rel" ]; then missing="$missing $rel"
    elif ! cmp -s "$f" "$ROOT/$rel"; then changed="$changed $rel"; fi
  done < <(find "$dir/supabase/functions" -type f)
  if [ ! -d "$ROOT/supabase/functions/$slug" ]; then
    echo "NO-LOCAL $slug: deployed, no local folder ($n files)"; status=1
  elif [ -z "$changed$missing" ]; then
    echo "SAME     $slug ($n files)"
  else
    echo "DRIFT    $slug ($n files)"; status=1
    for x in $changed; do echo "         differs: $x"; done
    for x in $missing; do echo "         only deployed: $x"; done
  fi
done
exit "$status"
