/*
  STEP 24 — analysis_options.yaml يجب أن يبقى صارماً.

  هذه الاختبارات تحرس على بقاء قواعد الجودة المفعّلة في analysis_options.yaml،
  فلا يستطيع أحد إزالتها لاحقاً دون أن يفشل CI.

  لا نستخدم package:yaml لتحاشي حقن تبعية إضافية؛ نُجري فحوصاً نصّية على
  البنية الفعلية للملفّ (مع قبول مسافات/أسطر متغيّرة قدر الإمكان).
*/

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _path = 'analysis_options.yaml';

void main() {
  late String content;

  setUpAll(() {
    final f = File(_path);
    expect(f.existsSync(), isTrue, reason: '$_path must exist');
    content = f.readAsStringSync();
  });

  group('analysis_options.yaml — strict rules wired', () {
    test('avoid_print rule exists at error level', () {
      // (1) القاعدة مُفعَّلة في linter.rules:
      expect(
        RegExp(r'^\s*avoid_print\s*:\s*true\s*$', multiLine: true).hasMatch(content),
        isTrue,
        reason: 'avoid_print: true must be present under linter.rules',
      );
      // (2) رُفعت الشدّة إلى error في analyzer.errors:
      expect(
        RegExp(r'^\s*avoid_print\s*:\s*error\s*$', multiLine: true).hasMatch(content),
        isTrue,
        reason: 'avoid_print: error must be present under analyzer.errors',
      );
    });

    test('unawaited_futures rule exists', () {
      expect(
        RegExp(r'^\s*unawaited_futures\s*:\s*true\s*$', multiLine: true).hasMatch(content),
        isTrue,
        reason: 'unawaited_futures: true must be enabled',
      );
    });

    test('prefer_const_constructors rule exists', () {
      expect(
        RegExp(r'^\s*prefer_const_constructors\s*:\s*true\s*$', multiLine: true).hasMatch(content),
        isTrue,
        reason: 'prefer_const_constructors: true must be enabled',
      );
    });

    test('require_trailing_commas rule exists', () {
      expect(
        RegExp(r'^\s*require_trailing_commas\s*:\s*true\s*$', multiLine: true).hasMatch(content),
        isTrue,
        reason: 'require_trailing_commas: true must be enabled',
      );
    });

    test('avoid_dynamic_calls rule exists', () {
      expect(
        RegExp(r'^\s*avoid_dynamic_calls\s*:\s*true\s*$', multiLine: true).hasMatch(content),
        isTrue,
        reason: 'avoid_dynamic_calls: true must be enabled',
      );
    });

    test('no global ignore for any of the strict Step 24 rules', () {
      // لا يجب أن يُسكَت أيّ من هذه القواعد على مستوى الملف بـ analyzer.errors: ignore.
      final strictRules = const [
        'avoid_print',
        'unawaited_futures',
        'prefer_const_constructors',
        'require_trailing_commas',
        'avoid_dynamic_calls',
      ];
      for (final rule in strictRules) {
        // نسمح بـ "rule: error" أو "rule: true" أو "rule: warning" — لكن نمنع "rule: ignore" أو "rule: false".
        expect(
          RegExp('^\\s*$rule\\s*:\\s*ignore\\s*\$', multiLine: true).hasMatch(content),
          isFalse,
          reason: '$rule must NOT be ignored globally',
        );
        expect(
          RegExp('^\\s*$rule\\s*:\\s*false\\s*\$', multiLine: true).hasMatch(content),
          isFalse,
          reason: '$rule must NOT be disabled globally',
        );
      }
    });

    test('flutter_lints baseline is still included', () {
      // نحرص ألا يُحذف الأساس من package:flutter_lints أثناء التشديد.
      expect(
        content,
        contains('package:flutter_lints/flutter.yaml'),
        reason: 'project must keep the flutter_lints baseline included',
      );
    });
  });
}
