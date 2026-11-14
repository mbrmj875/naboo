/*
  اختباران يكملان خط الأساس:
  1) الرفع المتزامن على rpc_push_snapshot الحقيقية في Postgres محلي معزول.
  2) بيع حقيقي كامل عبر OilChangeCheckoutService لقياس تكرار قيود الصندوق.

  اختبارات الخادم تحتاج SYNC_TEST_PG_PORT و SYNC_TEST_PSQL، وتُتخطى دونهما.
  التقرير في BASELINE_REPORT، أو build/concurrency_real_sale.json.
*/

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_checkout_service.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../oil_change/helpers/oil_change_test_harness.dart';
import 'support/local_pg_cloud.dart';
import 'support/multi_device_fleet.dart';

final _report = <String, Map<String, Object?>>{};

Future<void> _flushReport() async {
  final f = File(
    Platform.environment['BASELINE_REPORT'] ?? 'build/concurrency_real_sale.json',
  );
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(_report));
}

void main() {
  late Directory tmp;
  Fleet? fleet;
  final portEnv = Platform.environment['SYNC_TEST_PG_PORT'];
  final psql = Platform.environment['SYNC_TEST_PSQL'] ?? 'psql';
  final pgSkip = portEnv == null ? 'يحتاج SYNC_TEST_PG_PORT' : null;
  const slow = Timeout(Duration(minutes: 5));

  setUpAll(initOilChangeTestEnvironment);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('naboo_concurrency_');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    fleet?.dispose();
    fleet = null;
    await tmp.delete(recursive: true);
    await _flushReport();
  });

  Future<LocalPgCloud> pg() async {
    final c = LocalPgCloud(int.parse(portEnv!), psql, tmp);
    await c.resetSchema('test/suites/sync/support/snapshot_rpc_schema.sql');
    return c;
  }

  Future<Fleet> startPg(int n) async {
    final c = await pg();
    return fleet = await Fleet.create(n, tmp, remote: c);
  }

  Future<Fleet> startFake(int n) async =>
      fleet = await Fleet.create(n, tmp);

  // ─── 1) الخادم الحقيقي تحت تزامن فعلي: اتصالات Postgres منفصلة ───

  group('الدالة الحقيقية تحت تزامن', skip: pgSkip, () {
    test('خ1: 8 رفعات معاً بنفس الإصدار، فائز واحد في كل جولة', () async {
      final c = await pg();
      await c.rawPush(expected: 0, payloadJson: '{"r":0}', key: 'seed');
      const rounds = 20;
      var winnersOk = 0, errors = 0, wrongWinners = 0;
      final sw = Stopwatch()..start();
      for (var r = 1; r <= rounds; r++) {
        final results = await Future.wait(List.generate(8, (i) {
          return c.rawPush(
            expected: r,
            payloadJson: '{"r":$r,"i":$i}',
            key: 'k-$r-$i',
          );
        }));
        final oks = results.where((x) => x['ok'] == true).length;
        errors += results.where((x) => x.containsKey('error')).length;
        if (oks == 1) {
          winnersOk++;
        } else {
          wrongWinners++;
        }
      }
      sw.stop();
      final history = await c.sql(
        'SELECT count(*), count(DISTINCT content_version) FROM public.app_snapshots_history;',
      );
      _report['k1_parallel_8'] = {
        'rounds': rounds,
        'rounds_with_exactly_one_winner': winnersOk,
        'rounds_with_wrong_winner_count': wrongWinners,
        'errors': errors,
        'final_version': await c.currentVersion(),
        'history_rows_and_distinct_versions': history,
        'ms_per_round_local': sw.elapsedMilliseconds ~/ rounds,
      };
      expect(wrongWinners, 0);
      expect(errors, 0);
      expect(await c.currentVersion(), rounds + 1);
    }, timeout: slow);

    test('خ2: أول رفع للحساب من 8 أجهزة معاً', () async {
      final c = await pg();
      final results = await Future.wait(List.generate(8, (i) {
        return c.rawPush(expected: 0, payloadJson: '{"i":$i}', key: 'first-$i');
      }));
      final errs = results.where((x) => x.containsKey('error')).toList();
      _report['k2_first_push_race'] = {
        'ok': results.where((x) => x['ok'] == true).length,
        'raw_db_errors_instead_of_conflict': errs.length,
        'sample_error': errs.isEmpty
            ? null
            : errs.first['error'].toString().split('\n').first,
        'final_version': await c.currentVersion(),
      };
      expect(results.where((x) => x['ok'] == true).length, 1);
      expect(errs, isEmpty);
    }, timeout: slow);

    test('خ3: نفس مفتاح عدم التكرار 6 مرات معاً لا يرفع الإصدار إلا مرة', () async {
      final c = await pg();
      await c.rawPush(expected: 0, payloadJson: '{"s":0}', key: 'seed');
      final results = await Future.wait(List.generate(6, (_) {
        return c.rawPush(expected: 1, payloadJson: '{"s":1}', key: 'same');
      }));
      _report['k3_same_key_parallel'] = {
        'ok': results.where((x) => x['ok'] == true).length,
        'marked_idempotent': results.where((x) => x['idempotent'] == true).length,
        'final_version': await c.currentVersion(),
      };
      expect(await c.currentVersion(), 2);
    }, timeout: slow);

    test('خ4: أجزاء اللقطة: تنظيف متأخر من جهاز خاسر يحذف أجزاء اللقطة الفائزة', () async {
      final c = await pg();
      Future<void> chunks(String up) => c.sql(
            "INSERT INTO public.app_snapshot_chunks (user_id, sync_id, upload_id, chunk_index, chunk_data) "
            "VALUES ('${LocalPgCloud.userId}', '$up', '$up', 0, 'x');",
          );
      // ب يرفع وينجح، ولا يصل تنظيفه إلا بعد أن يكمل أ رفعه الأحدث.
      await chunks('up-B');
      await c.rawPush(expected: 0, payloadJson: '{"chunked":true,"upload_id":"up-B"}', key: 'up-B');
      await chunks('up-A');
      await c.rawPush(expected: 1, payloadJson: '{"chunked":true,"upload_id":"up-A"}', key: 'up-A');
      // نفس جملة _deleteStaleSnapshotChunks بمفتاح ب.
      await c.sql(
        "DELETE FROM public.app_snapshot_chunks WHERE user_id = '${LocalPgCloud.userId}' AND upload_id <> 'up-B';",
      );
      final current = (await c.currentPayload())!['upload_id'];
      final left = await c.sql(
        "SELECT count(*) FROM public.app_snapshot_chunks WHERE upload_id = '$current';",
      );
      _report['k4_stale_chunk_cleanup'] = {
        'current_snapshot_upload': current,
        'chunks_left_for_current_snapshot': int.parse(left),
      };
      expect(int.parse(left), greaterThan(0));
    }, timeout: slow);
  });

  // ─── 2) كود الجهاز الحقيقي مع الدالة الحقيقية ───

  group('العميل الحقيقي مع الدالة الحقيقية', skip: pgSkip, () {
    Future<void> stalePush(Fleet f, FleetDevice d) async {
      await f.activate(d);
      await CloudSyncService.instance
          .pushSnapshotForTesting(userId: d.userId, forcePush: false);
    }

    test('ع1: تعارض حقيقي والطابور معلق: هل تنجو البطاقتان؟', () async {
      final f = await startPg(2);
      final c = f.remote as LocalPgCloud;
      await f.syncDevice(f['A'], processQueue: true);
      await f.syncDevice(f['B'], processQueue: true);
      await f.createCard(f['A'], 'A-1');
      await f.createCard(f['B'], 'B-1');
      await f.syncDevice(f['A'], processQueue: false);
      // ب كان قد سحب قبل رفع أ، فيصل رفعه بإصدار قديم.
      await stalePush(f, f['B']);
      final conflicts = c.conflicts;
      await f.activate(f['B']);
      final pending =
          await OilChangeTestHarness.instance.countSyncQueuePending();
      await f.converge(processQueue: false);
      final plates = await f.platesByDevice();
      final expected = {'A-1', 'B-1'};
      _report['c1_real_conflict_queue_pending'] = {
        'conflicts': conflicts,
        'queue_pending_on_B_after_conflict': pending,
        for (final e in plates.entries)
          'device_${e.key}': e.value.intersection(expected).toList()..sort(),
      };
      expect(conflicts, greaterThan(0));
      for (final s in plates.values) {
        expect(s, containsAll(expected));
      }
    }, timeout: slow);

    test('ع2: جهاز يكتب قبل كل محاولة: استنفاد المحاولات لا يضيع البيانات', () async {
      final f = await startPg(2);
      final c = f.remote as LocalPgCloud;
      await f.syncDevice(f['A']);
      await f.syncDevice(f['B']);
      await f.createCard(f['B'], 'B-EXH');
      var bump = 0;
      c.beforePush = () async {
        final v = await c.currentVersion();
        await c.rawPush(expected: v, payloadJson: await _latest(c), key: 'storm-${bump++}');
      };
      final ok = await CloudSyncService.instance
          .pushSnapshotForTesting(userId: f['B'].userId, forcePush: false);
      c.beforePush = null;
      final local = await f.plates(f['B']);
      final retried = await CloudSyncService.instance
          .pushSnapshotForTesting(userId: f['B'].userId, forcePush: false);
      final onServer = jsonEncode(await c.currentPayload()).contains('B-EXH');
      _report['c2_conflict_exhaustion'] = {
        'first_push_returned': ok,
        'attempts_against_storm': bump,
        'card_kept_locally': local.contains('B-EXH'),
        'retry_returned': retried,
        'on_server_after_retry': onServer,
      };
      expect(local, contains('B-EXH'));
      expect(onServer, isTrue);
    }, timeout: slow);

    test('ع3: ضياع الرد ثم تغيير جديد بنفس المفتاح: التغيير الجديد يرتفع', () async {
      final f = await startPg(2);
      final c = f.remote as LocalPgCloud;
      await f.syncDevice(f['A']);
      await f.createCard(f['A'], 'FIRST');
      c.dropNextResponse = true;
      Object? thrown;
      try {
        await CloudSyncService.instance
            .pushSnapshotForTesting(userId: f['A'].userId, forcePush: false);
      } catch (e) {
        thrown = e.runtimeType;
      }
      await f.createCard(f['A'], 'SECOND');
      await CloudSyncService.instance
          .pushSnapshotForTesting(userId: f['A'].userId, forcePush: false);
      final afterRetry = jsonEncode(await c.currentPayload()).contains('SECOND');
      // مزامنة أخرى دون أي تغيير: هل يُرفع ما تبقى؟
      await CloudSyncService.instance
          .pushSnapshotForTesting(userId: f['A'].userId, forcePush: false);
      final afterIdle = jsonEncode(await c.currentPayload()).contains('SECOND');
      await f.createCard(f['A'], 'THIRD');
      await CloudSyncService.instance
          .pushSnapshotForTesting(userId: f['A'].userId, forcePush: false);
      final afterNext = jsonEncode(await c.currentPayload()).contains('SECOND');
      await f.syncDevice(f['B']);
      final onB = await f.plates(f['B']);
      _report['c3_lost_response_then_change'] = {
        'first_attempt_threw': thrown?.toString(),
        'second_on_server_after_retry': afterRetry,
        'second_on_server_after_idle_sync': afterIdle,
        'second_on_server_after_next_change': afterNext,
        'second_reached_device_B': onB.contains('SECOND'),
      };
      expect(afterIdle, isTrue);
    }, timeout: slow);
  });

  // ─── 3) بيع حقيقي كامل ───

  group('البيع الحقيقي والصندوق', () {
    setUp(() => TenantContext.instance.set('1'));
    const fils = 50000;

    Future<int> sell(Fleet f, FleetDevice d, String plate) async {
      await f.activate(d);
      final builder = ServiceOrderBuilder(OilChangeTestHarness.instance);
      final id = await builder.createPending(plate: plate, agreedPriceFils: fils);
      await OilChangeOrdersRepository.instance.updateOilChangeOrder(
        id,
        advancePaymentFils: fils,
        agreedPriceFils: fils,
      );
      final order = (await builder.byId(id))!;
      final res = await OilChangeCheckoutService.instance
          .completeFromOrder(order: order, orderId: id);
      return res.invoiceId;
    }

    Future<Map<String, Object?>> cashState(Fleet f) async {
      final out = <String, Object?>{};
      for (final d in f.devices) {
        final db = await f.activate(d);
        final r = await db.rawQuery(
          "SELECT COUNT(*) c, COALESCE(SUM(amountFils),0) s, COUNT(DISTINCT global_id) g "
          "FROM cash_ledger WHERE transactionType IN ('sale_cash','sale_advance') AND deleted_at IS NULL",
        );
        out['device_${d.name}'] = r.first;
      }
      return out;
    }

    /// كل دورة: يفتح الجهازان شاشة الصندوق (فيعمل تنظيف التكرار) ثم يتزامنان.
    Future<List<Map<String, Object?>>> cashScreenCycles(Fleet f, int n) async {
      final out = <Map<String, Object?>>[];
      for (var i = 0; i < n; i++) {
        final row = <String, Object?>{};
        for (final d in f.devices) {
          await f.activate(d);
          final m = await OilChangeTestHarness.instance.dbHelper.getCashSummary();
          row['screen_balance_${d.name}'] = m['balance'];
        }
        await f.converge();
        for (final d in f.devices) {
          final db = await f.activate(d);
          final live = await db.rawQuery(
            'SELECT COUNT(*) c, COALESCE(SUM(amountFils),0) s FROM cash_ledger WHERE deleted_at IS NULL',
          );
          row['live_rows_${d.name}'] = live.first['c'];
          row['live_fils_${d.name}'] = live.first['s'];
        }
        out.add(row);
      }
      return out;
    }

    List<Map<String, dynamic>> uploadedCash(Map<String, dynamic>? payload) {
      final tables = (payload?['tables'] as Map?) ?? const {};
      return ((tables['cash_ledger'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
    }

    test('ب1: بيع واحد ثم رفع فوري دون إعادة فتح القاعدة', () async {
      final f = await startFake(2);
      await f.syncDevice(f['A']);
      await f.syncDevice(f['B']);
      await sell(f, f['A'], 'SALE-1');
      final db = await f.activate(f['A']);
      final local = await db.rawQuery(
        'SELECT global_id FROM cash_ledger',
      );
      await f.syncDevice(f['A']);
      final up = uploadedCash(f.cloud.payload);
      await f.converge();
      final state = await cashState(f);
      _report['r1_sale_immediate_push'] = {
        'global_id_right_after_sale': local.map((e) => e['global_id'] != null).toList(),
        'uploaded_rows': up.length,
        'uploaded_rows_without_global_id':
            up.where((e) => (e['global_id'] ?? '').toString().isEmpty).length,
        ...state,
      };
      _report['r1b_cash_screen_cycles'] = {
        'expected_fils': fils,
        'cycles': await cashScreenCycles(f, 3),
      };
      for (final v in state.values) {
        expect((v as Map)['c'], 1);
      }
    }, timeout: slow);

    test('ب2: ضابط: إعادة فتح القاعدة قبل أول رفع تمنع التكرار', () async {
      final f = await startFake(2);
      await f.syncDevice(f['A']);
      await f.syncDevice(f['B']);
      await sell(f, f['A'], 'SALE-2');
      // فتح التطبيق من جديد يملأ المعرف قبل الرفع.
      await f.reopen(f['A']);
      await f.syncDevice(f['A']);
      final up = uploadedCash(f.cloud.payload);
      await f.converge();
      final state = await cashState(f);
      _report['r2_sale_reopen_before_push'] = {
        'uploaded_rows_without_global_id':
            up.where((e) => (e['global_id'] ?? '').toString().isEmpty).length,
        ...state,
      };
      for (final v in state.values) {
        expect((v as Map)['c'], 1);
      }
    }, timeout: slow);

    test('ب4: فاتورتان مختلفتان بنفس الرقم المحلي: تنظيف التكرار لا يحذف مال فاتورة حقيقية', () async {
      final f = await startFake(2);
      await f.syncDevice(f['A']);
      await f.syncDevice(f['B']);
      // كل جهاز يبيع قبل أن يرى بيع الآخر، فيأخذ البيعان رقم الفاتورة نفسه.
      final invA = await sell(f, f['A'], 'COL-A');
      final invB = await sell(f, f['B'], 'COL-B');
      // فتح التطبيق يعطي القيدين معرفيهما، فلا دخل لآلية التكرار السابقة هنا.
      await f.reopen(f['A']);
      await f.reopen(f['B']);
      await f.converge();
      final before = await cashState(f);
      final balances = <String, Object?>{};
      for (final d in f.devices) {
        await f.activate(d);
        final m = await OilChangeTestHarness.instance.dbHelper.getCashSummary();
        balances['balance_${d.name}'] = m['balance'];
      }
      await f.converge();
      final rows = <String, Object?>{};
      for (final d in f.devices) {
        final db = await f.activate(d);
        rows['rows_${d.name}'] = await db.rawQuery(
          'SELECT cl.invoiceId, cl.amountFils, cl.deleted_at IS NOT NULL AS deleted, '
          'i.customerName, i.global_id IS NOT NULL AS has_invoice '
          'FROM cash_ledger cl LEFT JOIN invoices i ON i.id = cl.invoiceId ORDER BY cl.id',
        );
        rows['invoices_${d.name}'] = (await db.rawQuery(
          'SELECT COUNT(*) c FROM invoices WHERE deleted_at IS NULL',
        )).first['c'];
      }
      _report['r4_invoice_id_collision_dedupe'] = {
        ...rows,
        'same_invoice_id': invA == invB,
        'before_cash_screen': before,
        ...balances,
        'expected_balance_two_real_sales': 2 * fils / 1000.0,
        'after_cash_screen_and_sync': await cashState(f),
      };
      _report['r4b_cash_screen_cycles'] = {
        'expected_fils': 2 * fils,
        'cycles': await cashScreenCycles(f, 3),
      };
      expect(balances['balance_A'], 2 * fils / 1000.0);
    }, timeout: slow);

    test('ب5: ضابط: معرف صحيح قبل الرفع، ودورات الشاشة لا تغيّر المال', () async {
      final f = await startFake(2);
      await f.syncDevice(f['A']);
      await f.syncDevice(f['B']);
      await sell(f, f['A'], 'CTRL-1');
      await f.reopen(f['A']);
      await f.converge();
      final cycles = await cashScreenCycles(f, 3);
      _report['r5_control_cycles'] = {'expected_fils': fils, 'cycles': cycles};
      expect(cycles.last['live_fils_A'], fils);
      expect(cycles.last['live_fils_B'], fils);
    }, timeout: slow);

    test('ب3: 5 مبيعات متتالية مع مزامنة بعد كل بيع', () async {
      final f = await startFake(2);
      await f.syncDevice(f['A']);
      await f.syncDevice(f['B']);
      for (var i = 0; i < 5; i++) {
        final d = i.isEven ? f['A'] : f['B'];
        await f.syncDevice(d);
        await sell(f, d, 'SEQ-$i');
        await f.syncDevice(d);
      }
      await f.converge();
      final state = await cashState(f);
      _report['r3_five_sales_synced'] = state;
      _report['r3b_cash_screen_cycles'] = {
        'expected_fils': 5 * fils,
        'cycles': await cashScreenCycles(f, 3),
      };
      for (final v in state.values) {
        expect((v as Map)['c'], 5);
        expect((v)['s'], 5 * fils);
      }
    }, timeout: slow);
  });
}

Future<String> _latest(LocalPgCloud c) async =>
    jsonEncode(await c.currentPayload());
