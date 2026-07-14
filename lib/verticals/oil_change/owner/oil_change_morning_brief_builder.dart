import '../../../owner/models/owner_command_center_snapshot.dart';

/// سطر «ملخص الصباح» — يقرأ أقسام snapshot v3.
abstract final class OilChangeMorningBriefBuilder {
  OilChangeMorningBriefBuilder._();

  static String build(OwnerCommandCenterSnapshot snapshot) {
    final parts = <String>[];

    final changes = snapshot.oilChangesCount;
    if (changes != null && changes.hasData && changes.data != null) {
      parts.add('${changes.data!.changeCount} غياراً');
    }

    final active = snapshot.oilActiveCars;
    if (active != null && active.hasData && active.data != null) {
      final n = active.data!.activeCount;
      if (n > 0) {
        parts.add('$n سيارات بالانتظار');
      }
    }

    final shortages = snapshot.oilStockShortages;
    if (shortages != null && shortages.hasData && shortages.data != null) {
      final n = shortages.data!.shortageCount;
      if (n > 0) {
        parts.add('$n نواقص حرجة');
      }
    }

    if (parts.isEmpty) {
      return 'لا نشاط مسجّل بعد — اسحب للتحديث';
    }
    return parts.join(' · ');
  }
}
