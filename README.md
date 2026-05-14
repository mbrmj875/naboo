# Basra Store Manager

Flutter project for managing store operations.

## Required runtime secrets (`--dart-define`)

Supabase credentials are **never** committed to source. They must be supplied at
compile time via `--dart-define` for every `flutter run` / `flutter build`
invocation. Missing values cause the app to abort during startup
(`SupabaseConfig.assertConfigured()` in `lib/main.dart`).

| Define | Description |
| --- | --- |
| `SUPABASE_URL` | `https://<project>.supabase.co` of your Supabase project. |
| `SUPABASE_ANON_KEY` | The `anon` (public) JWT for the same project. Never use the `service_role` key in the Flutter client. |

### Run / build with secrets

Save your secrets in a local, **git-ignored** shell file (e.g. `.env.local.sh`):

```bash
export SUPABASE_URL="https://xxxxx.supabase.co"
export SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

Then source it before each command:

```bash
source ./.env.local.sh

# Debug run (mobile / desktop):
flutter run \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

# Release build (Android):
flutter build apk --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

# Release build (Windows):
flutter build windows --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
```

Tip: store the same key/value pairs in your IDE run configuration (VS Code
`launch.json` `args` or Android Studio "Additional run args") so day-to-day
launches don't require typing the flags.

> Tests do **not** require these defines; `flutter test` reads
> `String.fromEnvironment(...)` as empty strings, and individual tests inject
> values via `SupabaseConfig.debugAssertConfigured(...)`.

## Build on Windows (Release)

Use these steps on the target Windows machine after copying this project:

1. Install Flutter SDK and Visual Studio with **Desktop development with C++**.
2. Open terminal in the project folder.
3. Run:

```bash
flutter pub get
flutter config --enable-windows-desktop
flutter build windows --release \
  --dart-define=SUPABASE_URL=%SUPABASE_URL% \
  --dart-define=SUPABASE_ANON_KEY=%SUPABASE_ANON_KEY%
```

4. The executable output will be created in:

```text
build\windows\x64\runner\Release\
```

## Notes

- Windows executable must be built on a Windows host.
- If packages change, run `flutter pub get` again before building.
- Never commit Supabase keys, JWT signing keys, or Firebase credentials.
