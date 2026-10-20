import 'package:intl/intl.dart' hide TextDirection;

import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import 'oil_change_filter_format.dart';

/// دعوة تقييم في نهاية الرسالة — تشجّع الزبون على الرد وبدء محادثة.
const oilChangeWhatsAppRatingAskText =
    '⭐ تقييمكم يهمّنا:\n'
    'ردّوا برقم من *1 إلى 10* لجودة العمل (مثال: 9)\n'
    'أو اكتبوا ملاحظة قصيرة عن الخدمة — ردّكم يصل مباشرة للمحل 💬';

/// أقل مبلغ يستحق العرض — ما دونه يُعد صفراً عملياً.
const int _minMeaningfulFils = 500;

/// ما لم يُنفَّذ أو لا بيانات له في البطاقة.
const String oilChangeCardEmptyField = '-';

/// بين فلتر وفلتر، ومنتج ومنتج، داخل معامل القالب الواحد.
const String oilChangeCardListSeparator = '، ';

/// كتلة التفاصيل لقالب بطاقة الغيار (متغير {{3}}) — ديناميكية حسب البطاقة.
///
/// ميتا ترفض أسطر جديدة/تاب وأكثر من 4 مسافات متتالية داخل معاملات القالب.
String buildOilChangeCardDetailsBlock({
  required Map<String, dynamic> order,
  String storeFooter = '',
}) {
  final buf = StringBuffer();
  _appendCardDetails(buf, order: order, storeFooter: storeFooter);
  return sanitizeWhatsappTemplateParam(buf.toString());
}

/// معاملات قالب البطاقة الطويلة — المفاتيح تطابق `paramKeys` في البوابة.
///
/// القالب يضع كل حقل في سطره، فالمعامل هنا قيمة مفردة بلا عنوان ولا أسطر.
/// ما لم يُنفَّذ في البطاقة يظهر شرطة — ميتا ترفض المعامل الفارغ.
Map<String, String> buildOilChangeCardTemplateParams({
  required Map<String, dynamic> order,
  required String storeTitle,
  String productsSummary = '',
}) {
  String text(Object? raw, {String fallback = oilChangeCardEmptyField}) {
    final v = (raw ?? '').toString().trim();
    return sanitizeWhatsappTemplateParam(v.isEmpty ? fallback : v);
  }

  String odometer(Object? raw) {
    final v = (raw ?? '').toString().trim();
    return v.isEmpty ? oilChangeCardEmptyField : '$v كم';
  }

  final agreedF = (order['agreedPriceFils'] as num?)?.toInt();
  final estF = (order['estimatedPriceFils'] as num?)?.toInt() ?? 0;
  final totalF = agreedF ?? estF;
  final paidF = (order['advancePaymentFils'] as num?)?.toInt() ?? 0;
  final remainderF = totalF > 0 ? (totalF - paidF).clamp(0, totalF) : 0;
  final discountF =
      (estF > _minMeaningfulFils && agreedF != null && agreedF < estF)
          ? estF - agreedF
          : 0;

  String money(int fils) {
    if (fils <= _minMeaningfulFils) return oilChangeCardEmptyField;
    return IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(fils));
  }

  // بلا خصم لا معنى لسطر «قبل التخفيض» — يبقى شرطة كبقية ما لم يحدث.
  final hasDiscount = discountF > _minMeaningfulFils;

  final filters = _filterNames(order).join(oilChangeCardListSeparator);
  final services = _splitCsv((order['requestedServices'] ?? '').toString())
      .join(oilChangeCardListSeparator);

  return {
    'customer': text(order['customerNameSnapshot'], fallback: 'عميلنا الكريم'),
    'shop': text(storeTitle, fallback: 'المحل'),
    'car': text(order['deviceName']),
    'car_model': text(order['carModel']),
    'engine': text(order['engineSize']),
    'plate': text(order['deviceSerial']),
    'odo_current': odometer(order['odometerCurrent']),
    'odo_next': odometer(order['odometerNext']),
    'oil_brand': text(order['oilType']),
    'oil_grade': text(order['oilViscosity']),
    'oil_size': text(order['oilSize']),
    'hyd_gear': text(
      _hydraulicValue(
        type: (order['hydraulicType'] ?? '').toString(),
        grade: (order['hydraulicGrade'] ?? '').toString(),
        size: (order['hydraulicSize'] ?? '').toString(),
        customerProvided: order['hydraulicCustomerProvided'] == 1,
      ),
    ),
    'hyd_power': text(
      _hydraulicValue(
        type: (order['powerHydraulicType'] ?? '').toString(),
        grade: (order['powerHydraulicGrade'] ?? '').toString(),
        size: (order['powerHydraulicSize'] ?? '').toString(),
        customerProvided: order['powerHydraulicCustomerProvided'] == 1,
      ),
    ),
    'filters': text(filters),
    'products': text(productsSummary),
    'services': text(services),
    'price_before': hasDiscount ? money(estF) : oilChangeCardEmptyField,
    'discount': hasDiscount ? money(discountF) : oilChangeCardEmptyField,
    'total': money(totalF),
    'paid': money(paidF),
    'remaining': money(remainderF),
    'employee': text(order['technicianName']),
    'notes': text(order['issueDescription']),
  };
}

/// يجهّز نصاً لمعامل قالب واتساب الرسمي (سطر واحد بدون أسطر جديدة).
String sanitizeWhatsappTemplateParam(String raw) {
  var s = raw
      .replaceAll(RegExp(r'[\r\n\t]+'), oilChangeCardListSeparator)
      .replaceAll(RegExp(r' {5,}'), '    ')
      .replaceAll(
          RegExp('($oilChangeCardListSeparator){2,}'),
          oilChangeCardListSeparator)
      .trim();
  // بعض المسارات تضع * للتنسيق؛ الإبقاء مسموح، لكن أزل التكرار الفارغ.
  if (s.isEmpty) return '-';
  // حد عملي لطول معامل القالب عند ميتا.
  if (s.length > 900) {
    s = '${s.substring(0, 897)}…';
  }
  return s;
}

/// رسالة واتساب تلقائية بعد حفظ بطاقة غيار الزيت — الحقول التي يطلبها صاحب المحل فقط.
///
/// بدون رقم فاتورة، بدون ملاحظات/دين سابق.
String buildOilChangeAutoWhatsAppMessage({
  required Map<String, dynamic> order,
  required String storeTitle,
  String storeFooter = '',
  bool includeRatingAsk = true,
}) {
  final shop = storeTitle.trim().isEmpty ? 'المحل' : storeTitle.trim();
  final customer =
      (order['customerNameSnapshot'] ?? '').toString().trim().isEmpty
          ? 'عميلنا الكريم'
          : (order['customerNameSnapshot'] ?? '').toString().trim();

  final buf = StringBuffer()
    ..writeln('مرحباً $customer،')
    ..writeln('شكراً لزيارتكم *$shop* لغيار الزيت 🙏')
    ..writeln();

  _appendCardDetails(buf, order: order, storeFooter: storeFooter);

  if (includeRatingAsk) {
    buf.writeln();
    buf.writeln(oilChangeWhatsAppRatingAskText);
  }

  return buf.toString().trim();
}

void _appendCardDetails(
  StringBuffer buf, {
  required Map<String, dynamic> order,
  String storeFooter = '',
}) {
  final car = (order['deviceName'] ?? '').toString().trim();
  final model = (order['carModel'] ?? '').toString().trim();
  final engineSize = (order['engineSize'] ?? '').toString().trim();
  final plate = (order['deviceSerial'] ?? '').toString().trim();
  final odomCur = (order['odometerCurrent'] ?? '').toString().trim();
  final odomNext = (order['odometerNext'] ?? '').toString().trim();
  final oilBrand = (order['oilType'] ?? '').toString().trim();
  final oilGrade = (order['oilViscosity'] ?? '').toString().trim();
  final oilSize = (order['oilSize'] ?? '').toString().trim();
  final technician = (order['technicianName'] ?? '').toString().trim();

  final agreedF = (order['agreedPriceFils'] as num?)?.toInt();
  final estF = (order['estimatedPriceFils'] as num?)?.toInt() ?? 0;
  final totalF = agreedF ?? estF;
  final paidF = (order['advancePaymentFils'] as num?)?.toInt() ?? 0;
  final remainderF = totalF > 0 ? (totalF - paidF).clamp(0, totalF) : 0;
  const minFils = 500;

  String? money(int fils) {
    if (fils <= minFils) return null;
    return IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(fils));
  }

  final created = DateTime.tryParse((order['createdAt'] ?? '').toString());
  if (created != null) {
    final dateLine = DateFormat('d/M/y', 'ar').format(created.toLocal());
    _line(buf, '📆', 'التاريخ', dateLine);
  }

  final services = _splitCsv((order['requestedServices'] ?? '').toString());
  final filters = _filterNames(order);
  final gearHydraulic = _hydraulicText(
    label: 'هيدروليك القير',
    type: (order['hydraulicType'] ?? '').toString(),
    grade: (order['hydraulicGrade'] ?? '').toString(),
    size: (order['hydraulicSize'] ?? '').toString(),
    customerProvided: order['hydraulicCustomerProvided'] == 1,
  );
  final powerHydraulic = _hydraulicText(
    label: 'هيدروليك الباور',
    type: (order['powerHydraulicType'] ?? '').toString(),
    grade: (order['powerHydraulicGrade'] ?? '').toString(),
    size: (order['powerHydraulicSize'] ?? '').toString(),
    customerProvided: order['powerHydraulicCustomerProvided'] == 1,
  );

  _line(buf, '🚗', 'السيارة', car);
  _line(buf, '📅', 'موديل السيارة', model);
  _line(buf, '⚙️', 'حجم المحرك', engineSize);
  _line(buf, '🔖', 'رقم اللوحة', plate);
  _line(buf, '🔢', 'القراءة الحالية', odomCur.isEmpty ? '' : '$odomCur كم');
  _line(buf, '📍', 'القراءة اللاحقة', odomNext.isEmpty ? '' : '$odomNext كم');

  final hasOil = oilBrand.isNotEmpty || oilGrade.isNotEmpty || oilSize.isNotEmpty;
  if (hasOil) {
    buf.writeln();
    buf.writeln('🛢️ *الزيت:*');
    _bullet(buf, 'النوع', oilBrand);
    _bullet(buf, 'الدرجة', oilGrade);
    _bullet(buf, 'الحجم', oilSize);
  }

  if (filters.isNotEmpty) {
    buf.writeln();
    buf.writeln('🔧 *الفلاتر:*');
    for (final f in filters) {
      buf.writeln('• $f');
    }
  }

  if (gearHydraulic != null) {
    buf.writeln();
    buf.writeln('🧴 *$gearHydraulic*');
  }
  if (powerHydraulic != null) {
    buf.writeln('🧴 *$powerHydraulic*');
  }

  if (services.isNotEmpty) {
    buf.writeln();
    buf.writeln('📋 *تذكرة الزيت / الخدمات:*');
    for (final s in services) {
      buf.writeln('• $s');
    }
  }

  if (technician.isNotEmpty) {
    buf.writeln();
    buf.writeln('👨‍🔧 *الفني:* $technician');
  }

  final totalLine = money(totalF);
  final paidLine = money(paidF);
  final remLine = money(remainderF);
  final estLine = money(estF);
  final discountF = (estF > minFils &&
          agreedF != null &&
          agreedF > minFils &&
          agreedF < estF)
      ? (estF - agreedF)
      : 0;
  final discountLine = money(discountF);

  if (totalLine != null ||
      paidLine != null ||
      remLine != null ||
      discountLine != null) {
    buf.writeln();
    buf.writeln('💰 *السعر والدفع:*');
    if (discountLine != null && estLine != null && totalLine != null) {
      buf.writeln('• تم تخفيض المبلغ من $estLine إلى $totalLine');
      buf.writeln('• قيمة الخصم: $discountLine');
      buf.writeln('• الإجمالي بعد التخفيض: $totalLine');
    } else if (totalLine != null) {
      buf.writeln('• *الإجمالي:* $totalLine');
    }
    if (paidLine != null) {
      buf.writeln('• *المدفوع:* $paidLine');
    } else if (totalLine != null) {
      buf.writeln('• *المدفوع:* لم يُسجَّل دفع');
    }
    if (remLine != null) {
      buf.writeln('• *المتبقي:* $remLine');
    } else if (paidLine != null && totalLine != null) {
      buf.writeln('• *الحالة:* تم الدفع بالكامل ✅');
    }
  }

  final footer = storeFooter.trim();
  buf.writeln();
  if (footer.isNotEmpty) {
    buf.writeln(footer);
  } else {
    buf.writeln('نراكم عند موعد الصيانة القادمة ✨');
  }
}

void _line(StringBuffer buf, String icon, String label, String value) {
  final v = value.trim();
  if (v.isEmpty) return;
  buf.writeln('$icon *$label:* $v');
}

void _bullet(StringBuffer buf, String label, String value) {
  final v = value.trim();
  if (v.isEmpty) return;
  buf.writeln('• *$label:* $v');
}

List<String> _splitCsv(String raw) {
  if (raw.trim().isEmpty) return const [];
  return raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

List<String> _filterNames(Map<String, dynamic> order) {
  return oilFilterLinesFromRow(order);
}

/// قيمة الهيدروليك بلا عنوان — القالب الطويل يضع العنوان بنفسه.
String _hydraulicValue({
  required String type,
  required String grade,
  required String size,
  required bool customerProvided,
}) {
  if (customerProvided) return 'من العميل';
  final parts = <String>[
    if (type.trim().isNotEmpty) type.trim(),
    if (grade.trim().isNotEmpty) grade.trim(),
    if (size.trim().isNotEmpty) size.trim(),
  ];
  return parts.join(oilChangeCardListSeparator);
}

String? _hydraulicText({
  required String label,
  required String type,
  required String grade,
  required String size,
  required bool customerProvided,
}) {
  if (customerProvided) return '$label: من العميل';
  final parts = <String>[
    if (type.trim().isNotEmpty) type.trim(),
    if (grade.trim().isNotEmpty) grade.trim(),
    if (size.trim().isNotEmpty) size.trim(),
  ];
  if (parts.isEmpty) return null;
  return '$label: ${parts.join(' — ')}';
}
