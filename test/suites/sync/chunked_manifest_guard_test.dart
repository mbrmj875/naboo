// البند 5.1: غلاف اللقطة المقسّمة يحمل أسماء الجداول والحجم، لأن حارس
// الخادم لا يفك ضغط الأجزاء.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/cloud_sync_service.dart';

void main() {
  test('أسماء الجداول في الغلاف هي جداول اللقطة نفسها', () {
    final payload = {
      'takenAt': '2026-11-12T00:00:00Z',
      'tables': {
        'invoices': [
          {'id': 1}
        ],
        'cash_ledger': [],
        'stock_ledger': [
          {'global_id': 'a'}
        ],
      },
    };
    final raw = utf8.encode(jsonEncode(payload));
    final f = chunkedManifestGuardFields(payload, raw.length);
    expect(f['table_names'], ['cash_ledger', 'invoices', 'stock_ledger']);
    expect(f['raw_bytes'], raw.length);

    // ما يقرؤه الحارس يطابق ما يفكه الجهاز الآخر من الأجزاء.
    final decoded = gzipBytesDecodeSnapshotJson(
      gzipSnapshotUtf8(Uint8List.fromList(raw)),
    );
    final tables = (decoded['tables'] as Map).keys.toList()..sort();
    expect(f['table_names'], tables);
  });

  test('لقطة بلا جداول تعطي قائمة فارغة لا خطأ', () {
    final f = chunkedManifestGuardFields({'takenAt': 'x'}, 10);
    expect(f['table_names'], isEmpty);
    expect(f['raw_bytes'], 10);
  });

  test('الحقول قابلة للتحويل إلى JSON كما يرسلها الجهاز', () {
    final f = chunkedManifestGuardFields({
      'tables': {'products': []}
    }, 42);
    expect(
      jsonDecode(jsonEncode(f)),
      {'table_names': ['products'], 'raw_bytes': 42},
    );
  });
}
