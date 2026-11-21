/// حقول بطاقة الغيار التي يقرر المحل إلزامها.
///
/// اسم العميل وهاتفه إلزاميان دائماً وليسا هنا. كل الحقول تبقى ظاهرة؛
/// الإعداد يحدد فقط هل يُمنع الحفظ عند تركها فارغة.
enum OilCardField {
  carName,
  plate,
  carModel,
  engineSize,
  odometerCurrent,
  odometerNext,
  oil,
  technician,
}

extension OilCardFieldInfo on OilCardField {
  String get settingsKey => 'biz.oil.required.$name';

  /// الوضع الافتراضي يطابق سلوك البطاقة قبل الإعداد.
  bool get requiredByDefault => switch (this) {
        OilCardField.carName ||
        OilCardField.plate ||
        OilCardField.odometerCurrent ||
        OilCardField.oil =>
          true,
        _ => false,
      };

  String get labelAr => switch (this) {
        OilCardField.carName => 'اسم السيارة',
        OilCardField.plate => 'رقم اللوحة',
        OilCardField.carModel => 'موديل السيارة',
        OilCardField.engineSize => 'حجم المحرك',
        OilCardField.odometerCurrent => 'القراءة الحالية',
        OilCardField.odometerNext => 'القراءة اللاحقة',
        OilCardField.oil => 'الزيت',
        OilCardField.technician => 'الفني',
      };
}

/// أي الحقول إلزامية لهذا المحل.
class OilCardRequiredFields {
  const OilCardRequiredFields(this._required);

  final Set<OilCardField> _required;

  static final OilCardRequiredFields defaults = OilCardRequiredFields({
    for (final f in OilCardField.values)
      if (f.requiredByDefault) f,
  });

  bool isRequired(OilCardField f) => _required.contains(f);

  /// من قيم الإعدادات الخام: '1' إلزامي، '0' اختياري، غائب = الافتراضي.
  factory OilCardRequiredFields.fromRaw(Map<String, String> raw) {
    return OilCardRequiredFields({
      for (final f in OilCardField.values)
        if ((raw[f.settingsKey] ?? (f.requiredByDefault ? '1' : '0')) == '1')
          f,
    });
  }

  static List<String> get keys =>
      [for (final f in OilCardField.values) f.settingsKey];
}
