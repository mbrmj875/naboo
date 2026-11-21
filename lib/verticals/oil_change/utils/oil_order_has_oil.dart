import 'oil_change_filter_format.dart';
import 'oil_change_log_format.dart';

/// هل في البطاقة زيت فعلاً؟
///
/// منذ صار الزيت اختيارياً في الإعدادات قد تكون البطاقة لفلتر أو هيدروليك
/// أو خدمة فقط. البطاقة بلا زيت لا يُجدوَل لها تذكير الغيار القادم، ولا
/// تُحسب «غيار زيت» في التقارير، ويُسمّى إيصالها ورسالتها بمحتواها.
bool oilOrderHasOil(Map<String, dynamic> order) {
  String text(String k) => (order[k] ?? '').toString().trim();
  final liters = (order['oilLitersUsed'] as num?)?.toDouble() ?? 0;
  return text('oilType').isNotEmpty ||
      text('oilSize').isNotEmpty ||
      liters > 0 ||
      ((order['oilProductId'] as num?)?.toInt() ?? 0) > 0 ||
      ((order['oilCustomerProvided'] as num?)?.toInt() ?? 0) != 0;
}

bool _hasHydraulic(Map<String, dynamic> order, String prefix) {
  String text(String k) => (order['$prefix$k'] ?? '').toString().trim();
  return text('Type').isNotEmpty ||
      text('Size').isNotEmpty ||
      ((order['${prefix}LitersUsed'] as num?)?.toDouble() ?? 0) > 0 ||
      ((order['${prefix}ProductId'] as num?)?.toInt() ?? 0) > 0 ||
      ((order['${prefix}CustomerProvided'] as num?)?.toInt() ?? 0) != 0;
}

/// اسم العمل في البطاقة حسب محتواها: «غيار زيت» إن كان فيها زيت، وإلا
/// ما فيها فعلاً، مثل «تبديل فلتر وهيدروليك» أو «خدمات». بطاقة بلا أي
/// محتوى معروف تبقى «غيار زيت» كما كانت.
String oilCardWorkLabel(Map<String, dynamic> order) {
  if (oilOrderHasOil(order)) return 'غيار زيت';
  final parts = <String>[];
  final filters = oilFilterLinesDataFromRow(order).length;
  if (filters == 1) parts.add('تبديل فلتر');
  if (filters > 1) parts.add('تبديل فلاتر');
  if (_hasHydraulic(order, 'hydraulic') ||
      _hasHydraulic(order, 'powerHydraulic')) {
    parts.add('هيدروليك');
  }
  if (parseOilRequestedServices(order['requestedServices']?.toString())
      .isNotEmpty) {
    parts.add('خدمات');
  }
  // بلا أي محتوى معروف (بطاقة قديمة أو ناقصة): يبقى الاسم القديم.
  if (parts.isEmpty) return 'غيار زيت';
  if (parts.length == 1) return parts.single;
  return '${parts.sublist(0, parts.length - 1).join('، ')} و${parts.last}';
}
