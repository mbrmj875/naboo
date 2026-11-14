import '../models/wa_oil_followup_rule.dart';

/// متغيرات نص التذكير — نفس أسلوب الحملات.
abstract final class WaOilFollowupVars {
  WaOilFollowupVars._();

  static const name = '{الاسم}';
  static const shop = '{المحل}';
  static const car = '{السيارة}';
  static const odoCurrent = '{آخر_قراءة}';
  static const odoNext = '{القراءة_اللاحقة}';
  static const visitDate = '{تاريخ_الغيار}';

  static const chipLabels = <String, String>{
    name: 'اسم الزبون',
    car: 'السيارة',
    shop: 'المحل',
    odoCurrent: 'آخر قراءة',
    odoNext: 'القراءة اللاحقة',
    visitDate: 'تاريخ الغيار',
  };

  static const orderedTokens = [
    name,
    shop,
    car,
    odoCurrent,
    odoNext,
    visitDate,
  ];

  static const metaKeys = [
    'customer',
    'shop',
    'car',
    'odo_current',
    'odo_next',
    'visit_date',
  ];
}

abstract final class WaOilFollowupCopy {
  WaOilFollowupCopy._();

  static String defaultBodyForUnit(WaOilFollowupDelayUnit unit) {
    if (unit == WaOilFollowupDelayUnit.hour ||
        unit == WaOilFollowupDelayUnit.day) {
      return 'مرحباً ${WaOilFollowupVars.name}،\n'
          'شكراً لزيارتكم ${WaOilFollowupVars.shop} اليوم.\n'
          'إن لاحظتوا أي شيء على السيارة بعد الغيار، راسلونا هنا.\n'
          'نخدمكم.';
    }
    return 'مرحباً ${WaOilFollowupVars.name}،\n'
        'تحية طيبة من ${WaOilFollowupVars.shop}.\n\n'
        'سيارتكم ${WaOilFollowupVars.car} صار وقت صيانة غيار الزيت.\n'
        'آخر قراءة سجّلناها ${WaOilFollowupVars.odoCurrent}، '
        'والموعد التقريبي ${WaOilFollowupVars.odoNext}.\n\n'
        'إذا مناسب، نرتّب لكم موعد بالمحل.\n'
        'أهلاً وسهلاً.';
  }

  static String ensureDefault(String current, WaOilFollowupDelayUnit unit) {
    final t = current.trim();
    if (t.isNotEmpty) return t;
    return defaultBodyForUnit(unit);
  }

  static String preview({
    required String template,
    String customerName = 'أحمد',
    String car = 'تويوتا',
    String shop = 'المحل',
    String odoCurrent = '148000 كم',
    String odoNext = '153000 كم',
    String visitDate = '22 تشرين الأول 2026',
  }) {
    return template
        .replaceAll(WaOilFollowupVars.name, customerName)
        .replaceAll(WaOilFollowupVars.shop, shop)
        .replaceAll(WaOilFollowupVars.car, car)
        .replaceAll(WaOilFollowupVars.odoCurrent, odoCurrent)
        .replaceAll(WaOilFollowupVars.odoNext, odoNext)
        .replaceAll(WaOilFollowupVars.visitDate, visitDate);
  }

  static String toMetaBody(String arabicTemplate) {
    var out = arabicTemplate;
    for (var i = 0; i < WaOilFollowupVars.orderedTokens.length; i++) {
      out = out.replaceAll(WaOilFollowupVars.orderedTokens[i], '{{${i + 1}}}');
    }
    return out;
  }

  static bool hasInvalidBraceSyntax(String text) {
    return text.contains('{{') || text.contains('}}');
  }

  static int renderedLength(String template) => preview(template: template).length;
}
