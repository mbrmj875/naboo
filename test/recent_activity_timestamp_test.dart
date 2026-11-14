import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/recent_activity_entry.dart';
import 'package:naboo/utils/activity_timestamp.dart';

void main() {
  group('parseActivityTimestamp', () {
    test('converts UTC ISO to local', () {
      const raw = '2026-05-30T06:26:00.000Z';
      final local = parseActivityTimestamp(raw);
      expect(local, DateTime.parse(raw).toLocal());
    });

    test('returns now for empty input', () {
      final before = DateTime.now();
      final parsed = parseActivityTimestamp('');
      final after = DateTime.now();
      expect(
        parsed.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        parsed.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });
  });

  group('RecentActivityEntry.timeLabel', () {
    test('shows local hours for today shift open', () {
      final utc = DateTime.utc(2026, 5, 30, 6, 26);
      final entry = RecentActivityEntry(
        kind: RecentActivityKind.workShift,
        at: utc.toLocal(),
        title: 'فتح وردية',
        subtitle: 'baqer4',
      );
      final local = utc.toLocal();
      final h = local.hour.toString().padLeft(2, '0');
      final m = local.minute.toString().padLeft(2, '0');
      expect(entry.timeLabel, 'اليوم $h:$m');
    });

    test('fromWorkShiftRow parses openedAt as local', () {
      final entry = RecentActivityEntry.fromWorkShiftRow(
        {
          'id': 1,
          'shiftStaffName': 'baqer4',
          'openedAt': '2026-05-30T06:26:00.000Z',
          'closedAt': null,
        },
        isClose: false,
      );
      expect(entry.at, DateTime.parse('2026-05-30T06:26:00.000Z').toLocal());
    });
  });
}
