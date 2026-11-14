#!/bin/bash
# Clean restart for NABOO admin-web on port 3010:
# kill old process, delete broken .next cache, start next dev.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT=3010
cd "$ROOT"

echo "=================================="
echo "  NABOO Admin — clean start"
echo "  path: $ROOT"
echo "  port: $PORT"
echo "=================================="

if lsof -ti "tcp:${PORT}" >/dev/null 2>&1; then
  echo "* Stopping process on port ${PORT}..."
  lsof -ti "tcp:${PORT}" | xargs kill -9 2>/dev/null || true
  sleep 0.4
fi

if [[ -d .next ]]; then
  echo "* Removing .next cache..."
  rm -rf .next
fi

if [[ ! -d node_modules ]]; then
  echo "* Installing dependencies..."
  npm install
fi

echo "* Starting server..."
echo "  Open: http://localhost:${PORT}"
echo "  Stop: Ctrl+C"
echo "=================================="
exec npm run dev
