import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/sync_payload_codec.dart';

void main() {
  group('SyncPayloadCodec', () {
    test('encode/decode roundtrip for simple payload', () {
      final payload = <String, dynamic>{
        'schemaVersion': 3,
        'tables': {
          'products': [
            {'id': 1, 'name': 'A', 'updated_at': '2026-04-17T10:00:00Z'},
          ],
        },
      };
      final encoded = SyncPayloadCodec.encode(payload);
      final decoded = SyncPayloadCodec.decode(encoded);
      expect(decoded['schemaVersion'], 3);
      final tables = decoded['tables'] as Map<String, dynamic>;
      expect((tables['products'] as List).length, 1);
    });

    test('encoding is usually smaller than raw json for large payload', () {
      final rows = List.generate(
        2000,
        (i) => {
          'id': i,
          'name': 'Product $i',
          'notes': 'x' * 120,
          'updated_at': '2026-04-17T10:00:00Z',
        },
      );
      final payload = <String, dynamic>{
        'schemaVersion': 3,
        'tables': {'products': rows},
      };
      final raw = jsonEncode(payload);
      final encoded = SyncPayloadCodec.encode(payload);
      // base64+gzip should be below raw JSON size for repetitive large payload.
      expect(encoded.length, lessThan(raw.length));
    });

    test('split/join keeps content intact', () {
      final text = 'abc' * 10000;
      final chunks = SyncPayloadCodec.splitText(text, 777);
      expect(chunks, isNotEmpty);
      final merged = SyncPayloadCodec.joinText(chunks);
      expect(merged, text);
    });

    test('pickDeltaColumn prefers updatedAt family', () {
      final col = SyncPayloadCodec.pickDeltaColumn({
        'id',
        'name',
        'updated_at',
        'created_at',
      });
      expect(col, 'updated_at');
    });

    test('incomingWins true when incoming newer', () {
      final current = {'updated_at': '2026-04-17T10:00:00Z'};
      final incoming = {'updated_at': '2026-04-17T11:00:00Z'};
      expect(SyncPayloadCodec.incomingWins(current, incoming), isTrue);
    });

    test('incomingWins false when incoming older', () {
      final current = {'updated_at': '2026-04-17T12:00:00Z'};
      final incoming = {'updated_at': '2026-04-17T11:00:00Z'};
      expect(SyncPayloadCodec.incomingWins(current, incoming), isFalse);
    });

    test('incomingWins true when current has no timestamp', () {
      final current = {'id': 1};
      final incoming = {'updated_at': '2026-04-17T11:00:00Z'};
      expect(SyncPayloadCodec.incomingWins(current, incoming), isTrue);
    });

    test('rowDate returns null for invalid values', () {
      expect(SyncPayloadCodec.rowDate(null), isNull);
      expect(SyncPayloadCodec.rowDate('not-a-date'), isNull);
    });
  });
}
