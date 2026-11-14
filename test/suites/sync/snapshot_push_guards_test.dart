import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/snapshot_push_guards.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// حراسة رفع اللقطات بعد حادثة استبدال لقطة غنية بلقطة تنصيب شبه فارغة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('snapshot_push_guards — business data', () {
    test('(2) local all-zero business + remote rich counts → block', () {
      expect(
        shouldBlockBusinessEmptyLocalOverRichRemote(
          localCounts: {
            'customers': 0,
            'invoices': 0,
            'products': 0,
            'service_orders': 0,
          },
          remoteCounts: {
            'customers': 10,
            'invoices': 56,
            'products': 5,
            'service_orders': 54,
          },
          remoteChunked: false,
        ),
        isTrue,
      );
    });

    test('(2) local all-zero + remote chunked unknown → block (fail-closed)', () {
      expect(
        shouldBlockBusinessEmptyLocalOverRichRemote(
          localCounts: {
            for (final t in kSnapshotBusinessTables) t: 0,
          },
          remoteCounts: {
            for (final t in kSnapshotBusinessTables) t: 0,
          },
          remoteChunked: true,
        ),
        isTrue,
      );
    });

    test('local has invoices → allow even if remote rich', () {
      expect(
        shouldBlockBusinessEmptyLocalOverRichRemote(
          localCounts: {
            'customers': 0,
            'invoices': 1,
            'products': 0,
            'service_orders': 0,
          },
          remoteCounts: {
            'customers': 10,
            'invoices': 56,
            'products': 5,
            'service_orders': 54,
          },
          remoteChunked: false,
        ),
        isFalse,
      );
    });

    test('both empty → allow (new account)', () {
      expect(
        shouldBlockBusinessEmptyLocalOverRichRemote(
          localCounts: {
            for (final t in kSnapshotBusinessTables) t: 0,
          },
          remoteCounts: {
            for (final t in kSnapshotBusinessTables) t: 0,
          },
          remoteChunked: false,
        ),
        isFalse,
      );
    });

    test('settings-only local still empty for business guard', () {
      // إعدادات/فروع لا تدخل في جداول العمل — الحارس يعتمد الجداول الأربعة فقط.
      expect(
        localBusinessDataEmpty({
          for (final t in kSnapshotBusinessTables) t: 0,
        }),
        isTrue,
      );
    });

    test('businessCountsFromSnapshotTables reads list lengths', () {
      final c = businessCountsFromSnapshotTables({
        'customers': [{}, {}, {}],
        'invoices': [{}],
        'products': [],
        'service_orders': [{}, {}],
        'app_settings': [{}, {}, {}, {}],
      });
      expect(c['customers'], 3);
      expect(c['invoices'], 1);
      expect(c['products'], 0);
      expect(c['service_orders'], 2);
    });
  });

  group('CloudSyncService hydration gate prefs', () {
    const userId = 'user-hydrate-test';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      CloudSyncService.instance.remoteBusinessGuardInfoForTesting = null;
      await CloudSyncService.instance.setDeviceHydratedForTesting(userId, false);
    });

    tearDown(() async {
      CloudSyncService.instance.remoteBusinessGuardInfoForTesting = null;
    });

    test('(1) default hydrated flag is false on fresh device prefs', () async {
      expect(
        await CloudSyncService.instance.isDeviceHydratedForTesting(userId),
        isFalse,
      );
      expect(kHydrationIncompleteAr, contains('تهيئة'));
      expect(snapshotHydratedPrefsKey(userId), 'sync.hydrated.$userId');
    });

    test('(3) after hydration mark, flag is true for normal push eligibility', () async {
      await CloudSyncService.instance.setDeviceHydratedForTesting(userId, true);
      expect(
        await CloudSyncService.instance.isDeviceHydratedForTesting(userId),
        isTrue,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(snapshotHydratedPrefsKey(userId)), isTrue);
    });
    test('(1) not hydrated → evaluatePushGuards blocks (simulates chunk-fail device)', () async {
      await CloudSyncService.instance.setDeviceHydratedForTesting(userId, false);
      CloudSyncService.instance.remoteBusinessGuardInfoForTesting =
          (_) async => (
                chunked: true,
                counts: {for (final t in kSnapshotBusinessTables) t: 0},
              );

      final ok = await CloudSyncService.instance.evaluatePushGuardsForTesting(
        userId: userId,
        localBusinessCounts: {
          for (final t in kSnapshotBusinessTables) t: 0,
        },
      );
      expect(ok, isFalse);
      expect(
        CloudSyncService.instance.lastError.value,
        kHydrationIncompleteAr,
      );
    });

    test('(2) hydrated but empty local + rich remote → business guard blocks', () async {
      await CloudSyncService.instance.setDeviceHydratedForTesting(userId, true);
      CloudSyncService.instance.remoteBusinessGuardInfoForTesting =
          (_) async => (
                chunked: false,
                counts: {
                  'customers': 10,
                  'invoices': 56,
                  'products': 5,
                  'service_orders': 54,
                },
              );

      final ok = await CloudSyncService.instance.evaluatePushGuardsForTesting(
        userId: userId,
        localBusinessCounts: {
          for (final t in kSnapshotBusinessTables) t: 0,
        },
      );
      expect(ok, isFalse);
      expect(
        CloudSyncService.instance.lastError.value,
        kBusinessDataPushBlockedAr,
      );
    });

    test('(3) hydrated + local business data → push guards allow', () async {
      await CloudSyncService.instance.setDeviceHydratedForTesting(userId, true);
      CloudSyncService.instance.remoteBusinessGuardInfoForTesting =
          (_) async => (
                chunked: false,
                counts: {
                  'customers': 10,
                  'invoices': 56,
                  'products': 5,
                  'service_orders': 54,
                },
              );

      final ok = await CloudSyncService.instance.evaluatePushGuardsForTesting(
        userId: userId,
        localBusinessCounts: {
          'customers': 2,
          'invoices': 1,
          'products': 1,
          'service_orders': 0,
        },
      );
      expect(ok, isTrue);
      expect(CloudSyncService.instance.lastError.value, isNull);
    });
  });

  group('CloudSyncService source — incident hardening wiring', () {
    late final String src;

    setUpAll(() {
      src = File('lib/services/cloud_sync_service.dart').readAsStringSync();
    });

    test('(1) chunk decode failure returns blockedChunks without marking hydrated', () {
      final chunkFailIdx = src.indexOf('تعذر تجميع أجزاء اللقطة');
      expect(chunkFailIdx, greaterThan(0));
      final returnChunkIdx = src.indexOf('blockedChunks', chunkFailIdx);
      expect(returnChunkIdx, greaterThan(chunkFailIdx));
      final markBetween = src.indexOf('_markDeviceHydrated', chunkFailIdx);
      expect(
        markBetween == -1 || markBetween > returnChunkIdx,
        isTrue,
        reason: 'يجب ألا يُعلَّم hydrated بين فشل الأجزاء وreturn blockedChunks',
      );
      expect(src.contains('فشل جلب الأجزاء = فشل سحب كامل'), isTrue);
    });

    test('(3) successful import marks hydrated before allowPush', () {
      final importIdx = src.indexOf('await _importSnapshot(payload);');
      expect(importIdx, greaterThan(0));
      final markAfter = src.indexOf('await _markDeviceHydrated(userId);', importIdx);
      expect(markAfter, greaterThan(importIdx));
      final allowIdx = src.indexOf('CloudSyncPullStatus.imported', markAfter);
      expect(allowIdx, greaterThan(markAfter));
    });

    test('pushSnapshot checks hydration and business guard before RPC', () {
      expect(src.contains('kHydrationIncompleteAr'), isTrue);
      expect(src.contains('_isDeviceHydrated(userId)'), isTrue);
      expect(src.contains('shouldBlockBusinessEmptyLocalOverRichRemote'), isTrue);
      expect(src.contains('kBusinessDataPushBlockedAr'), isTrue);
      expect(src.contains('needsHydration'), isTrue);
      expect(src.contains('final doPull = forcePull || needsHydration'), isTrue);
      expect(src.contains("rpc('rpc_push_snapshot'") || src.contains("'rpc_push_snapshot'"), isTrue);
      expect(
        !RegExp(r"from\(_snapshotsTable\)\.upsert\(").hasMatch(src),
        isTrue,
        reason: 'لا يجوز upsert مباشر على app_snapshots من الكلاينت',
      );
    });

    test('noRemoteSnapshot marks hydrated (new account may push)', () {
      final noRemoteIdx = src.indexOf('CloudSyncPullStatus.noRemoteSnapshot');
      expect(noRemoteIdx, greaterThan(0));
      // mark should appear shortly before that return
      final windowStart = (noRemoteIdx - 400).clamp(0, src.length);
      final window = src.substring(windowStart, noRemoteIdx + 80);
      expect(window.contains('_markDeviceHydrated'), isTrue);
    });
  });
}
