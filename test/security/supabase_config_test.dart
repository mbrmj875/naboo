/*
  STEP 2 — Secrets management.

  Goal: prove that [SupabaseConfig] (a) refuses to start the app when either
  `SUPABASE_URL` or `SUPABASE_ANON_KEY` is missing from `--dart-define`, and
  (b) accepts both values when they are properly provided.

  These tests use [SupabaseConfig.debugAssertConfigured] so we can drive both
  branches without running multiple separate `flutter test` invocations with
  different `--dart-define` permutations.
*/

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/supabase_config.dart';

const _supabaseConfigPath = 'lib/services/supabase_config.dart';

void main() {
  group('SupabaseConfig.assertConfigured', () {
    test('throws AssertionError when URL is empty', () {
      expect(
        () => SupabaseConfig.debugAssertConfigured(
          url: '',
          anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.body.sig',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('throws AssertionError when anonKey is empty', () {
      expect(
        () => SupabaseConfig.debugAssertConfigured(
          url: 'https://example.supabase.co',
          anonKey: '',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('throws AssertionError when both URL and anonKey are empty', () {
      expect(
        () => SupabaseConfig.debugAssertConfigured(url: '', anonKey: ''),
        throwsA(isA<AssertionError>()),
      );
    });

    test('passes silently when both URL and anonKey are non-empty', () {
      expect(
        () => SupabaseConfig.debugAssertConfigured(
          url: 'https://example.supabase.co',
          anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.body.sig',
        ),
        returnsNormally,
      );
    });

    test(
      'no-arg assertConfigured() throws under default `flutter test` '
      '(no --dart-define values provided)',
      () {
        // When `flutter test` is invoked without --dart-define, both consts
        // resolve to the empty string at compile time and assertConfigured()
        // must abort. This is the live wiring the prod build relies on.
        expect(
          SupabaseConfig.url,
          isEmpty,
          reason:
              'Test runner must NOT receive --dart-define for these consts; '
              'otherwise this assertion is meaningless.',
        );
        expect(SupabaseConfig.anonKey, isEmpty);

        expect(
          SupabaseConfig.assertConfigured,
          throwsA(isA<AssertionError>()),
        );
      },
    );
  });

  group('SupabaseConfig source — secrets are not embedded in the binary', () {
    late final String src;

    setUpAll(() {
      src = File(_supabaseConfigPath).readAsStringSync();
    });

    test('static const url comes from String.fromEnvironment', () {
      expect(
        src.contains("String.fromEnvironment('SUPABASE_URL')"),
        isTrue,
        reason:
            'SUPABASE_URL must be sourced from --dart-define, not a literal.',
      );
    });

    test('static const anonKey comes from String.fromEnvironment', () {
      expect(
        src.contains("String.fromEnvironment('SUPABASE_ANON_KEY')"),
        isTrue,
        reason:
            'SUPABASE_ANON_KEY must be sourced from --dart-define, not a literal.',
      );
    });

    test('no hardcoded supabase.co URL or anon JWT body in this file', () {
      // Defence-in-depth: a regression that re-introduces a literal URL/key
      // (even commented-out) is caught here before it lands.
      final hardcodedUrl = RegExp(r'https://[a-z0-9-]+\.supabase\.co');
      final anonJwtPrefix = RegExp(
        r"'eyJ[A-Za-z0-9_\-]+\.eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+'",
      );
      expect(
        hardcodedUrl.hasMatch(src),
        isFalse,
        reason: 'Found hardcoded supabase.co URL in supabase_config.dart',
      );
      expect(
        anonJwtPrefix.hasMatch(src),
        isFalse,
        reason: 'Found hardcoded JWT (anon key?) literal in supabase_config.dart',
      );
    });
  });
}
