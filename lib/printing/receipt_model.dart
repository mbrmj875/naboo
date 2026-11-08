/// نموذج الإيصال المطبوع، مستقل عن طريقة الطباعة (حرارية أو PDF).
library;

/// نوع العمل الذي يُطبع له الإيصال. لكل نوع قالب خاص.
enum ReceiptKind {
  oilChange('إيصال غيار زيت', 'بطاقة غيار الزيت'),
  directSale('إيصال بيع', 'البيع المباشر'),
  carWash('إيصال غسيل', 'غسيل السيارات'),
  debtPayment('إيصال تسديد دين', 'تسديد دين عميل'),
  expense('سند صرف', 'المصروفات'),
  saleReturn('إيصال استرجاع', 'الاسترجاع'),
  sale('إيصال بيع', 'فاتورة عامة');

  const ReceiptKind(this.title, this.workLabel);

  /// العنوان المطبوع أعلى الإيصال.
  final String title;

  /// اسم العمل في شاشة الإعدادات.
  final String workLabel;

  /// الأعمال التي تظهر في قسم الطباعة لمحل الزيت.
  static const oilShop = [
    oilChange,
    directSale,
    carWash,
    saleReturn,
    debtPayment,
    expense,
  ];

  /// أقسام اختيارية يستطيع المالك إخفاءها من هذا القالب.
  List<ReceiptSection> get sections => switch (this) {
    oilChange => const [
      ReceiptSection.plate,
      ReceiptSection.car,
      ReceiptSection.odometer,
      ReceiptSection.nextService,
      ReceiptSection.oil,
      ReceiptSection.filters,
      ReceiptSection.technician,
      ReceiptSection.customer,
    ],
    directSale => const [ReceiptSection.customer, ReceiptSection.payment],
    carWash => const [
      ReceiptSection.plate,
      ReceiptSection.car,
      ReceiptSection.technician,
      ReceiptSection.customer,
    ],
    debtPayment => const [ReceiptSection.cashier],
    expense => const [ReceiptSection.cashier],
    saleReturn => const [ReceiptSection.customer, ReceiptSection.cashier],
    sale => const [ReceiptSection.customer, ReceiptSection.payment],
  };

  /// الطباعة التلقائية بعد الحفظ مفعّلة افتراضياً لأعمال البيع والخدمة فقط.
  bool get autoPrintByDefault =>
      this == oilChange ||
      this == directSale ||
      this == carWash ||
      this == saleReturn;

  /// نسختان للاسترجاع (للزبون وللمحل)، ونسخة لغيره.
  int get defaultCopies => this == saleReturn ? 2 : 1;
}

/// قسم اختياري في القالب.
enum ReceiptSection {
  plate('رقم اللوحة'),
  car('السيارة'),
  odometer('العداد'),
  nextService('موعد الغيار القادم'),
  oil('الزيت المستخدم'),
  filters('الفلاتر'),
  technician('الفني / العامل'),
  customer('اسم العميل'),
  payment('طريقة الدفع والمتبقي'),
  cashier('المستلم / المسجِّل');

  const ReceiptSection(this.label);
  final String label;
}

/// إعدادات قالب نوع واحد. تُحفظ في إعدادات الطباعة المشتركة للمحل.
class ReceiptTemplate {
  const ReceiptTemplate({
    required this.autoPrint,
    this.copies = 1,
    this.showLogo = true,
    this.showStoreContact = true,
    this.showQr = true,
    this.hidden = const {},
    this.footer = '',
  });

  factory ReceiptTemplate.defaultsFor(ReceiptKind kind) => ReceiptTemplate(
    autoPrint: kind.autoPrintByDefault,
    copies: kind.defaultCopies,
  );

  factory ReceiptTemplate.fromJson(ReceiptKind kind, Object? raw) {
    final d = ReceiptTemplate.defaultsFor(kind);
    if (raw is! Map) return d;
    final hidden = <ReceiptSection>{};
    final h = raw['hidden'];
    if (h is List) {
      for (final name in h) {
        for (final s in ReceiptSection.values) {
          if (s.name == name) hidden.add(s);
        }
      }
    }
    final copies = raw['copies'];
    return ReceiptTemplate(
      autoPrint: raw['autoPrint'] is bool
          ? raw['autoPrint'] as bool
          : d.autoPrint,
      copies: copies is num ? copies.toInt().clamp(1, 3) : d.copies,
      showLogo: raw['showLogo'] is bool ? raw['showLogo'] as bool : d.showLogo,
      showStoreContact: raw['showStoreContact'] is bool
          ? raw['showStoreContact'] as bool
          : d.showStoreContact,
      showQr: raw['showQr'] is bool ? raw['showQr'] as bool : d.showQr,
      hidden: hidden,
      footer: raw['footer'] is String ? (raw['footer'] as String) : d.footer,
    );
  }

  /// طباعة تلقائية بعد حفظ العمل.
  final bool autoPrint;

  /// عدد النسخ (1 إلى 3).
  final int copies;
  final bool showLogo;
  final bool showStoreContact;
  final bool showQr;

  /// الأقسام المخفية.
  final Set<ReceiptSection> hidden;

  /// نص أسفل الإيصال خاص بهذا العمل (يُضاف بعد النص العام).
  final String footer;

  bool shows(ReceiptSection s) => !hidden.contains(s);

  @override
  bool operator ==(Object other) =>
      other is ReceiptTemplate &&
      other.autoPrint == autoPrint &&
      other.copies == copies &&
      other.showLogo == showLogo &&
      other.showStoreContact == showStoreContact &&
      other.showQr == showQr &&
      other.footer == footer &&
      other.hidden.length == hidden.length &&
      other.hidden.containsAll(hidden);

  @override
  int get hashCode => Object.hash(
    autoPrint,
    copies,
    showLogo,
    showStoreContact,
    showQr,
    footer,
    Object.hashAllUnordered(hidden),
  );

  Map<String, dynamic> toJson() => {
    'autoPrint': autoPrint,
    'copies': copies,
    'showLogo': showLogo,
    'showStoreContact': showStoreContact,
    'showQr': showQr,
    'hidden': [for (final s in hidden) s.name],
    'footer': footer,
  };

  ReceiptTemplate copyWith({
    bool? autoPrint,
    int? copies,
    bool? showLogo,
    bool? showStoreContact,
    bool? showQr,
    Set<ReceiptSection>? hidden,
    String? footer,
  }) => ReceiptTemplate(
    autoPrint: autoPrint ?? this.autoPrint,
    copies: copies ?? this.copies,
    showLogo: showLogo ?? this.showLogo,
    showStoreContact: showStoreContact ?? this.showStoreContact,
    showQr: showQr ?? this.showQr,
    hidden: hidden ?? this.hidden,
    footer: footer ?? this.footer,
  );
}

/// كل القوالب، مقروءة من حقل `receiptTemplates` في إعدادات الطباعة.
class ReceiptTemplates {
  const ReceiptTemplates(this._raw);

  final Map<String, dynamic> _raw;

  Map<String, dynamic> get _rawMap => _raw;

  ReceiptTemplate of(ReceiptKind kind) =>
      ReceiptTemplate.fromJson(kind, _raw[kind.name]);

  Map<String, dynamic> withTemplate(ReceiptKind kind, ReceiptTemplate t) => {
    ..._raw,
    kind.name: t.toJson(),
  };
}

/// سطر معلومة في رأس الإيصال: «اللوحة: بصرة 12345».
class ReceiptField {
  const ReceiptField(this.label, this.value, {this.section, this.bold = false});

  final String label;
  final String value;
  final ReceiptSection? section;
  final bool bold;
}

/// صنف أو خدمة.
class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.totalFils,
    this.quantity,
    this.unitPriceFils,
    this.unit,
  });

  final String name;
  final double? quantity;
  final int? unitPriceFils;
  final String? unit;
  final int totalFils;
}

/// سطر في قسم المجاميع.
class ReceiptTotal {
  const ReceiptTotal(this.label, this.fils, {this.emphasis = false});

  final String label;
  final int fils;

  /// المبلغ الرئيسي: يُطبع بخط كبير داخل إطار.
  final bool emphasis;
}

/// معلومة بارزة تُطبع داخل صندوق معكوس (أبيض على أسود).
class ReceiptHighlight {
  const ReceiptHighlight(this.label, this.value, {this.section});

  final String label;
  final String value;
  final ReceiptSection? section;
}

/// الإيصال الجاهز للرسم.
class ReceiptDocument {
  const ReceiptDocument({
    required this.kind,
    required this.date,
    this.number,
    this.status,
    this.fields = const [],
    this.lines = const [],
    this.totals = const [],
    this.highlights = const [],
    this.notes = const [],
    this.qrData,
    this.titleOverride,
  });

  final ReceiptKind kind;
  final DateTime date;

  /// رقم الفاتورة أو السند.
  final String? number;

  /// حالة تُطبع تحت العنوان: «نقدي»، «آجل»، «مرتجع».
  final String? status;
  final List<ReceiptField> fields;
  final List<ReceiptLine> lines;
  final List<ReceiptTotal> totals;
  final List<ReceiptHighlight> highlights;
  final List<String> notes;
  final String? qrData;
  final String? titleOverride;

  String get title => titleOverride ?? kind.title;
}

// ------------------------------------------------------------- نمط الإيصال

/// خطوط عربية مضمّنة في التطبيق (لا تحتاج إنترنت).
enum ReceiptFont {
  tajawal('Tajawal', 'تجوال'),
  cairo('Cairo', 'القاهرة'),
  almarai('Almarai', 'المراعي'),
  plex('IBMPlexSansArabic', 'بلكس'),
  naskh('NotoNaskhArabic', 'نسخ'),
  amiri('Amiri', 'أميري');

  const ReceiptFont(this.family, this.label);
  final String family;
  final String label;
}

/// حجم الخط.
enum ReceiptTextSize {
  small(0.88, 'صغير'),
  medium(1.0, 'متوسط'),
  large(1.14, 'كبير');

  const ReceiptTextSize(this.scale, this.label);
  final double scale;
  final String label;
}

/// شكل العنوان والإجمالي.
enum ReceiptHeaderShape {
  filled('شريط ممتلئ'),
  outlined('إطار'),
  plain('خط تحت النص');

  const ReceiptHeaderShape(this.label);
  final String label;
}

/// لون من لوحة ثابتة (تضمن تبايناً واضحاً على الورق الأبيض).
enum ReceiptColor {
  black(0xFF000000, 'أسود'),
  charcoal(0xFF374151, 'رمادي داكن'),
  navy(0xFF1E3A5F, 'كحلي'),
  blue(0xFF1D4ED8, 'أزرق'),
  green(0xFF166534, 'أخضر'),
  maroon(0xFF881337, 'عنابي'),
  brown(0xFF7C4A12, 'بني ذهبي');

  const ReceiptColor(this.argb, this.label);
  final int argb;
  final String label;
}

/// مظهر الإيصال لكل المحل. الألوان تظهر في الطابعات الملوّنة (طابعة النظام)
/// فقط؛ الطابعة الحرارية تطبع بالأسود دائماً.
class ReceiptStyle {
  const ReceiptStyle({
    this.font = ReceiptFont.tajawal,
    this.size = ReceiptTextSize.medium,
    this.shape = ReceiptHeaderShape.filled,
    this.accent = ReceiptColor.black,
    this.ink = ReceiptColor.black,
  });

  factory ReceiptStyle.fromJson(Object? raw) {
    if (raw is! Map) return const ReceiptStyle();
    T pick<T extends Enum>(List<T> values, Object? v, T d) =>
        values.firstWhere((e) => e.name == v, orElse: () => d);
    return ReceiptStyle(
      font: pick(ReceiptFont.values, raw['font'], ReceiptFont.tajawal),
      size: pick(ReceiptTextSize.values, raw['size'], ReceiptTextSize.medium),
      shape: pick(
        ReceiptHeaderShape.values,
        raw['shape'],
        ReceiptHeaderShape.filled,
      ),
      accent: pick(ReceiptColor.values, raw['accent'], ReceiptColor.black),
      ink: pick(ReceiptColor.values, raw['ink'], ReceiptColor.black),
    );
  }

  final ReceiptFont font;
  final ReceiptTextSize size;
  final ReceiptHeaderShape shape;

  /// لون العنوان والإجمالي والإطارات.
  final ReceiptColor accent;

  /// لون النص.
  final ReceiptColor ink;

  Map<String, dynamic> toJson() => {
    'font': font.name,
    'size': size.name,
    'shape': shape.name,
    'accent': accent.name,
    'ink': ink.name,
  };

  ReceiptStyle copyWith({
    ReceiptFont? font,
    ReceiptTextSize? size,
    ReceiptHeaderShape? shape,
    ReceiptColor? accent,
    ReceiptColor? ink,
  }) => ReceiptStyle(
    font: font ?? this.font,
    size: size ?? this.size,
    shape: shape ?? this.shape,
    accent: accent ?? this.accent,
    ink: ink ?? this.ink,
  );

  @override
  bool operator ==(Object other) =>
      other is ReceiptStyle &&
      other.font == font &&
      other.size == size &&
      other.shape == shape &&
      other.accent == accent &&
      other.ink == ink;

  @override
  int get hashCode => Object.hash(font, size, shape, accent, ink);
}

extension ReceiptTemplatesStyle on ReceiptTemplates {
  static const _key = '_style';

  ReceiptStyle get style => ReceiptStyle.fromJson(_rawMap[_key]);

  Map<String, dynamic> withStyle(ReceiptStyle s) => {
    ..._rawMap,
    _key: s.toJson(),
  };
}
