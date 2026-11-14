import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import 'oil_change_filter_format.dart';

List<String> parseOilRequestedServices(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  return raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

bool oilServicesContain(List<String> services, String token) {
  return services.any((s) => s.contains(token));
}

String oilYesNo(bool value) => value ? 'نعم' : 'لا';

String oilFormatDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  return '${dt.year}/${dt.month}/${dt.day}';
}

String oilFormatOdo(String? odo) {
  if (odo == null || odo.trim().isEmpty) return '—';
  return odo.trim();
}

String oilFormatPrice(Map<String, dynamic> r) {
  final agreed = (r['agreedPriceFils'] as num?)?.toInt();
  final est = (r['estimatedPriceFils'] as num?)?.toInt();
  final fils = agreed ?? est ?? 0;
  if (fils == 0) return '—';
  return IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(fils));
}

String oilFormatServicesShort(List<String> services) {
  if (services.isEmpty) return '—';
  return services.join(' · ');
}

bool oilIsCustomerProvided(Map<String, dynamic> r) =>
    ((r['oilCustomerProvided'] as num?)?.toInt() ?? 0) != 0;

String oilFormatOilSource(Map<String, dynamic> r) =>
    oilIsCustomerProvided(r) ? 'زيت العميل' : 'زيت المحل';

String oilFormatLitersOrSize(Map<String, dynamic> r) {
  if (oilIsCustomerProvided(r)) {
    final size = (r['oilSize'] ?? '').toString().trim();
    return size.isEmpty ? '—' : size;
  }
  final liters = (r['oilLitersUsed'] as num?)?.toDouble();
  if (liters == null || liters <= 1e-9) return '—';
  return '${liters.toStringAsFixed(1)} لتر';
}

String oilFormatStockProductName(Map<String, dynamic> r) {
  if (oilIsCustomerProvided(r)) return '—';
  final cached = (r['_oilProductName'] ?? '').toString().trim();
  return cached.isEmpty ? '—' : cached;
}

String oilFormatFilterType(Map<String, dynamic> r) {
  return oilFilterSummaryFromRow(r);
}

String oilFormatPhone(Map<String, dynamic> r) {
  final v = (r['customerPhone'] ?? '').toString().trim();
  return v.isEmpty ? '—' : v;
}

String oilFormatPlate(Map<String, dynamic> r) {
  final v = (r['deviceSerial'] ?? '').toString().trim();
  return v.isEmpty ? '—' : v;
}

String oilFormatTechnician(Map<String, dynamic> r) {
  final v = (r['technicianName'] ?? '').toString().trim();
  return v.isEmpty ? '—' : v;
}

/// تقدير أعمدة نعم/لا من الخدمات المختارة (مطابقة تقريبية لجدول Excel).
class OilExcelStyleFlags {
  const OilExcelStyleFlags({
    required this.engineFilter,
    required this.airFilter,
    required this.gearOil,
    required this.gearFilter,
  });

  final bool engineFilter;
  final bool airFilter;
  final bool gearOil;
  final bool gearFilter;

  factory OilExcelStyleFlags.fromRow(Map<String, dynamic> r) {
    final services = parseOilRequestedServices(r['requestedServices']?.toString());
    final engineName = (r['engineFilterName'] ?? '').toString().trim();
    final airName = (r['airFilterName'] ?? '').toString().trim();
    final gearName = (r['gearFilterName'] ?? '').toString().trim();
    final legacyFilter = (r['filterType'] ?? '').toString().trim();

    return OilExcelStyleFlags(
      engineFilter: engineName.isNotEmpty || legacyFilter.isNotEmpty,
      airFilter: airName.isNotEmpty || oilServicesContain(services, 'شوطة'),
      gearOil: oilServicesContain(services, 'كير') &&
          (oilServicesContain(services, 'زيت') ||
              oilServicesContain(services, 'هيدروليك')),
      gearFilter: gearName.isNotEmpty || oilServicesContain(services, 'فلتر كير'),
    );
  }
}
