import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/recent_activity_entry.dart';
import 'package:naboo/utils/staff_activity_filter.dart';

void main() {
  group('normalizeStaffActivityKey', () {
    test('يحفظ الأسماء الرقمية بالكامل', () {
      expect(normalizeStaffActivityKey('3'), '3');
      expect(normalizeStaffActivityKey('5'), '5');
      expect(normalizeStaffActivityKey('3'), isNot(''));
    });

    test('يزيل بادئة الأرقام فقط عند وجود نص بعدها', () {
      expect(normalizeStaffActivityKey('12 أحمد'), 'أحمد');
    });
  });

  group('activityMatchesStaffFilter', () {
    RecentActivityEntry shift({
      required String name,
      int? userId,
    }) {
      return RecentActivityEntry(
        kind: RecentActivityKind.workShift,
        at: DateTime(2026, 6, 2, 12),
        title: 'فتح وردية',
        subtitle: name,
        actorName: name,
        actorUserId: userId,
        workShiftId: 1,
      );
    }

    test('موظف 3 لا يطابق نشاط موظف 5 بالمعرّف', () {
      final filter = StaffActivityFilter(userId: 3, names: {'3'});
      final entry = shift(name: '5', userId: 5);
      expect(activityMatchesStaffFilter(entry, filter), isFalse);
    });

    test('موظف 3 يطابق نشاطه بالمعرّف حتى لو الاسم مختلف', () {
      final filter = StaffActivityFilter(userId: 3, names: {'3'});
      final entry = shift(name: '5', userId: 3);
      expect(activityMatchesStaffFilter(entry, filter), isTrue);
    });

    test('موظف 3 يطابق بالاسم عند غياب المعرّف', () {
      final filter = StaffActivityFilter(userId: 3, names: {'3'});
      final entry = shift(name: '3');
      expect(activityMatchesStaffFilter(entry, filter), isTrue);
    });

    test('لا يطابق عبر subtitle أو مفتاح فارغ', () {
      final filter = StaffActivityFilter(names: {'3'});
      final entry = RecentActivityEntry(
        kind: RecentActivityKind.invoice,
        at: DateTime(2026, 6, 2),
        title: 'فاتورة',
        subtitle: 'عميل · 5',
        actorName: '5',
        invoiceId: 10,
      );
      expect(activityMatchesStaffFilter(entry, filter), isFalse);
    });

    test('addStaffActivityNameKey لا يضيف مفتاحاً فارغاً', () {
      final keys = <String>{};
      addStaffActivityNameKey(keys, '3');
      expect(keys, contains('3'));
      expect(keys, isNot(contains('')));
    });
  });
}
