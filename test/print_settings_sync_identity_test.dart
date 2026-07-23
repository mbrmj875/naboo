import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// اختبارات منطق هوية المتجر في print_settings (نفس قواعد الدمج في CloudSync).
bool printSettingsPayloadIsBlank(Map<String, dynamic> row) {
  final raw = (row['payload'] ?? '').toString();
  if (raw.trim().isEmpty) return true;
  try {
    final m = jsonDecode(raw);
    if (m is! Map) return true;
    final title = (m['storeTitleLine'] ?? '').toString().trim();
    final addr = (m['storeAddress'] ?? '').toString().trim();
    final logo = (m['storeLogoBase64'] ?? '').toString().trim();
    final phonesRaw = m['storePhones'];
    var hasPhone = false;
    if (phonesRaw is List) {
      for (final p in phonesRaw) {
        if (p.toString().trim().isNotEmpty) {
          hasPhone = true;
          break;
        }
      }
    }
    return title.isEmpty && addr.isEmpty && logo.isEmpty && !hasPhone;
  } catch (_) {
    return true;
  }
}

void main() {
  test('empty seeded print_settings is blank identity', () {
    final seeded = {
      'id': 1,
      'payload':
          '{"paperFormat":"thermal80","receiptShowBarcode":true,"storeTitleLine":"","footerExtra":""}',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    expect(printSettingsPayloadIsBlank(seeded), isTrue);
  });

  test('filled store identity is not blank', () {
    final filled = {
      'id': 1,
      'payload': jsonEncode({
        'storeTitleLine': 'محل البصرة',
        'storeAddress': 'الجزائر',
        'storePhones': ['07701234567'],
      }),
      'updatedAt': '2026-01-01T00:00:00.000Z',
    };
    expect(printSettingsPayloadIsBlank(filled), isFalse);
  });

  test('blank local must yield to filled remote (new device rule)', () {
    final local = {
      'payload': '{"storeTitleLine":""}',
      'updatedAt': '2026-07-16T12:00:00.000Z',
    };
    final remote = {
      'payload': jsonEncode({'storeTitleLine': 'محل البصرة'}),
      'updatedAt': '2026-01-01T00:00:00.000Z',
    };
    final localBlank = printSettingsPayloadIsBlank(local);
    final remoteBlank = printSettingsPayloadIsBlank(remote);
    expect(localBlank && !remoteBlank, isTrue);
  });
}
