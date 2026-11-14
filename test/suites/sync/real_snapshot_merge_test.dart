// البند 1.12: الدمج الحقيقي على نسخ لقطات حسابات حقيقية.
//
// لا يقرأ من الخادم ولا يكتب فيه. يأخذ ملفات JSON من مجلد محلي
// (REAL_SNAPSHOT_DIR) استُخرجت من النسخة الاحتياطية، ويتخطى نفسه إن لم يوجد.
// لا تُحفظ هذه الملفات في المستودع لأنها بيانات زبائن.
//
// السيناريو لكل حساب: الخادم يحمل لقطته الحقيقية، جهازان يسحبانها، كل جهاز
// يضيف بطاقة، ثم يتزامنان حتى يهدأ الخادم. المطلوب: لا تضيع أي بطاقة أو
// فاتورة أو قيد صندوق حيّ من اللقطة، والبطاقتان الجديدتان على الجهازين.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/sync_safety.dart';

import '../../oil_change/helpers/oil_change_test_harness.dart';
import 'support/multi_device_fleet.dart';

const _tables = ['service_orders', 'invoices', 'cash_ledger', 'customers'];

bool _live(Map<String, dynamic> r) {
  final d = r['deletedAt'] ?? r['deleted_at'];
  return d == null || d.toString().trim().isEmpty;
}

String _key(Map<String, dynamic> r) {
  final g = (r['global_id'] ?? '').toString();
  if (g.isNotEmpty) return 'g:$g';
  // قيد صندوق بلا معرّف يأخذ عند الاستيراد معرّفاً محسوباً من محتواه.
  if (r.containsKey('transactionType')) return 'g:${SyncSafety.cashGlobalId(r)}';
  return 'l:${r['id']}|${r['createdAt']}';
}

Set<String> _liveKeys(List<dynamic>? rows) => {
      for (final r in (rows ?? const []).whereType<Map>())
        if (_live(Map<String, dynamic>.from(r)))
          _key(Map<String, dynamic>.from(r)),
    };

void main() {
  final dirPath = Platform.environment['REAL_SNAPSHOT_DIR'];
  final files = dirPath == null || !Directory(dirPath).existsSync()
      ? <File>[]
      : (Directory(dirPath)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)));

  setUpAll(initOilChangeTestEnvironment);

  if (files.isEmpty) {
    test('لقطات حقيقية: لا مجلد REAL_SNAPSHOT_DIR', () {},
        skip: 'REAL_SNAPSHOT_DIR غير مضبوط');
    return;
  }

  for (final file in files) {
    final acct = file.uri.pathSegments.last.replaceAll('.json', '');
    test('لقطة حقيقية $acct: جهازان يضيفان ولا يضيع شيء', () async {
      final payload =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final tables = Map<String, dynamic>.from(payload['tables'] as Map);
      final before = {
        for (final t in _tables) t: _liveKeys(tables[t] as List<dynamic>?),
      };

      final tmp = await Directory.systemTemp.createTemp('real_merge_$acct');
      final f = await Fleet.create(2, tmp);
      CloudSyncService.instance.chunkThresholdCharsOverrideForTesting =
          1 << 30;
      try {
        f.cloud
          ..payload = payload
          ..version = 1;
        for (final d in f.devices) {
          await f.activate(d);
          await f.importLatest(d.userId);
        }

        await f.createCard(f['A'], 'REAL-A-$acct');
        await f.createCard(f['B'], 'REAL-B-$acct');
        await f.converge();

        for (final d in f.devices) {
          final db = await f.activate(d);
          for (final t in _tables) {
            final rows = await db.query(t);
            final after = _liveKeys(rows);
            final missing = before[t]!.difference(after);
            if (t == 'cash_ledger') {
              // قيد الصندوق المكرر فعلاً (الثانية نفسها، النوع، المبلغ،
              // والفاتورة نفسها) يُدمج في واحد عمداً. المطلوب: يبقى واحد من
              // كل مجموعة، ولا يختفي أي قيد ليس له توأم.
              final invGid = {
                for (final i in (tables['invoices'] as List).whereType<Map>())
                  i['id']?.toString(): (i['global_id'] ?? '').toString(),
              };
              String dupKey(Map<String, dynamic> r) {
                final f = (r['amountFils'] as num?)?.toInt() ?? 0;
                final fils = f != 0
                    ? f
                    : (((r['amount'] as num?)?.toDouble() ?? 0) * 1000).round();
                final inv = invGid[r['invoiceId']?.toString()] ?? '';
                return '${r['createdAt']}|${r['transactionType']}|$fils|'
                    '${inv.isNotEmpty ? inv : 'id:${r['invoiceId']}'}';
              }
              final groups = <String, List<String>>{};
              for (final r in (tables[t] as List).whereType<Map>()) {
                final m = Map<String, dynamic>.from(r);
                if (!_live(m)) continue;
                groups.putIfAbsent(dupKey(m), () => []).add(_key(m));
              }
              var collapsed = 0;
              for (final g in groups.values) {
                final survivors = g.where(after.contains).length;
                expect(survivors, greaterThanOrEqualTo(1),
                    reason: '$acct/${d.name}: ضاع قيد صندوق بلا توأم');
                collapsed += g.length - survivors;
              }
              // ignore: avoid_print
              print('CASH $acct/${d.name}: rows=${before[t]!.length} '
                  'duplicates_collapsed=$collapsed');
              continue;
            }
            expect(missing, isEmpty,
                reason: '$acct/${d.name}/$t: ضاع ${missing.length} صفاً');
          }
          final plates = await f.plates(d);
          expect(plates, containsAll(['REAL-A-$acct', 'REAL-B-$acct']),
              reason: '$acct/${d.name}: بطاقة جديدة لم تصل');
        }
        expect(f.cloud.pushes, lessThan(12),
            reason: 'تأرجح: ${f.cloud.pushes} رفعات');
      } finally {
        f.dispose();
        CloudSyncService.instance
          ..suppressScheduleSyncSoonForTesting = false
          ..chunkThresholdCharsOverrideForTesting = null;
        await tmp.delete(recursive: true);
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
