import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../models/oil_change_filter_kind.dart';
import 'oil_change_filter_format.dart';

/// رسالة واتساب تلقائية بعد حفظ بطاقة غيار الزيت — الحقول التي يطلبها صاحب المحل فقط.
///
/// بدون رقم فاتورة، بدون فني/ملاحظات/دين سابق.
String buildOilChangeAutoWhatsAppMessage({
  required Map<String, dynamic> order,
  required String storeTitle,
  String storeFooter = '',
}) {
  final shop = storeTitle.trim().isEmpty ? 'المحل' : storeTitle.trim();
  final customer =
      (order['customerNameSnapshot'] ?? '').toString().trim().isEmpty
          ? 'عميلنا الكريم'
          : (order['customerNameSnapshot'] ?? '').toString().trim();

  final car = (order['deviceName'] ?? '').toString().trim();
  final model = (order['carModel'] ?? '').toString().trim();
  final engineSize = (order['engineSize'] ?? '').toString().trim();
  final plate = (order['deviceSerial'] ?? '').toString().trim();
  final odomCur = (order['odometerCurrent'] ?? '').toString().trim();
  final odomNext = (order['odometerNext'] ?? '').toString().trim();
  final oilBrand = (order['oilType'] ?? '').toString().trim();
  final oilGrade = (order['oilViscosity'] ?? '').toString().trim();
  final oilSize = (order['oilSize'] ?? '').toString().trim();

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

  final buf = StringBuffer()
    ..writeln('مرحباً $customer،')
    ..writeln('شكراً لزيارتكم *$shop* لغيار الزيت 🙏')
    ..writeln();

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

  final totalLine = money(totalF);
  final paidLine = money(paidF);
  final remLine = money(remainderF);
  if (totalLine != null || paidLine != null || remLine != null) {
    buf.writeln();
    buf.writeln('💰 *السعر والدفع:*');
    if (totalLine != null) buf.writeln('• *الإجمالي:* $totalLine');
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

  return buf.toString().trim();
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
  final out = <String>[];
  for (final kind in OilChangeFilterKind.all) {
    final name = (order[kind.nameColumnKey] ?? '').toString().trim();
    if (name.isEmpty) continue;
    out.add('${kind.label}: $name');
  }
  return out;
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
