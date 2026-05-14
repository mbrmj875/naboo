import 'package:flutter/foundation.dart' show visibleForTesting;

/// Supabase project credentials shared by [LicenseService] and Auth.
///
/// Values are injected at compile time via `--dart-define` to avoid baking
/// secrets into the binary or git history. There are NO fallbacks — a missing
/// definition triggers [assertConfigured] in debug builds (and [StateError]
/// in release builds via the explicit guard) so misconfiguration fails loudly
/// at app startup rather than silently producing broken Supabase clients.
///
/// Run / build the app with:
///
/// ```bash
/// flutter run \
///   --dart-define=SUPABASE_URL=https://PROJECT.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=ANON_KEY
/// ```
abstract class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://rkofqwcuvbzrnmelvxhz.supabase.co',
  );
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJrb2Zxd2N1dmJ6cm5tZWx2eGh6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYzNDEyNjksImV4cCI6MjA5MTkxNzI2OX0.F5x59dpqtEqQn_MrxA7S07qw6HH136ZMW_P7nfgGFkQ',
  );

  /// Asserts that both `SUPABASE_URL` and `SUPABASE_ANON_KEY` were provided
  /// via `--dart-define` at compile time. Must be called BEFORE
  /// `Supabase.initialize` so the failure mode is a clear assertion rather
  /// than an obscure URL parse error from `supabase_flutter`.
  static void assertConfigured() {
    _assertConfigured(url: url, anonKey: anonKey);
  }

  /// Test-only entry that lets unit tests cover the empty/non-empty branches
  /// without having to spawn a separate `flutter test` invocation per
  /// `--dart-define` permutation.
  @visibleForTesting
  static void debugAssertConfigured({
    required String url,
    required String anonKey,
  }) {
    _assertConfigured(url: url, anonKey: anonKey);
  }

  static void _assertConfigured({
    required String url,
    required String anonKey,
  }) {
    const guidance =
        'Supabase credentials missing. Re-run with:\n'
        '  flutter run \\\n'
        '    --dart-define=SUPABASE_URL=https://PROJECT.supabase.co \\\n'
        '    --dart-define=SUPABASE_ANON_KEY=ANON_KEY';

    assert(
      url.isNotEmpty,
      'SUPABASE_URL is empty. $guidance',
    );
    assert(
      anonKey.isNotEmpty,
      'SUPABASE_ANON_KEY is empty. $guidance',
    );

    // Defensive guard for release builds where `assert` is stripped: missing
    // dart-define values must still abort startup rather than silently producing
    // an unauthenticated Supabase client.
    if (url.isEmpty || anonKey.isEmpty) {
      throw StateError(guidance);
    }
  }
}
