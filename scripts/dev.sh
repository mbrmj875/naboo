#!/usr/bin/env bash
# scripts/dev.sh

if [ ! -f .env ]; then
  echo "Error: .env file not found. Please copy .env.example to .env and configure it."
  exit 1
fi

# Load variables from .env
export $(grep -v '^#' .env | xargs)

echo "Starting Flutter app with Supabase config..."
GOOGLE_ID="${GOOGLE_WEB_CLIENT_ID:-281392172783-ngr4g28b2c4cap8mvfdav60t9b62pj13.apps.googleusercontent.com}"
flutter run \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_ID"
