import 'owner_date_range.dart';

/// سياق تحميل قسم لوحة المالك — يُمرَّر من shell إلى manifest التخصص.
class OwnerSectionLoadContext {
  const OwnerSectionLoadContext({
    required this.tenantId,
    this.range,
    this.staffName,
    this.garageStaleHours = 2,
  });

  final int tenantId;
  final OwnerDateRange? range;
  final String? staffName;
  final int garageStaleHours;
}
