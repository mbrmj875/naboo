import 'dart:convert';

import 'package:flutter/material.dart';

import 'invoice.dart';
import '../theme/sale_brand.dart';

double _readJsonTextScale(Map<String, dynamic> m) {
  final v = m['textScale'] ?? m['txtScale'];
  if (v == null) return 1.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 1.0;
}

/// مفتاح JSON في [app_settings].
abstract final class SalePosSettingsKeys {
  SalePosSettingsKeys._();

  static const String jsonKey = 'sale.pos.settings.v1';
}

/// حدود [SalePosSettingsData.appTextScale] (حجم النص في كل الواجهات).
abstract final class AppTypographyScaleBounds {
  AppTypographyScaleBounds._();

  static const double min = 0.85;
  static const double max = 1.35;

  static double clamp(double v) => v.clamp(min, max);
}

/// خطوط مُعرَّفة في [pubspec.yaml] — تُطبَّق عبر الثيم على كامل التطبيق.
abstract final class AppFontFamilies {
  AppFontFamilies._();

  /// مُسجَّل في [pubspec.yaml].
  static const String tajawal = 'Tajawal';
  static const String notoNaskhArabic = 'NotoNaskhArabic';

  /// عائلات Google Fonts — تُحمَّل عبر حزمة [google_fonts] في [AppThemeResolver].
  static const String cairo = 'Cairo';
  static const String almarai = 'Almarai';
  static const String amiri = 'Amiri';
  static const String lateef = 'Lateef';
  static const String scheherazadeNew = 'ScheherazadeNew';
  static const String ibmPlexSansArabic = 'IBMPlexSansArabic';
  static const String elMessiri = 'ElMessiri';
  static const String changa = 'Changa';

  /// قائمة الاختيار في إعدادات المظهر (١٠ خطوط متميزة).
  static const List<String> selectable = [
    tajawal,
    notoNaskhArabic,
    cairo,
    almarai,
    amiri,
    lateef,
    scheherazadeNew,
    ibmPlexSansArabic,
    elMessiri,
    changa,
  ];

  /// للتوافق مع الشاشات القديمة.
  static List<String> get bundled => selectable;

  static String normalize(String? raw) {
    final t = (raw ?? tajawal).trim();
    if (t.isEmpty) return tajawal;
    for (final f in selectable) {
      if (t == f) return f;
    }
    final lower = t.toLowerCase();
    if (lower == 'notonaskharabic' ||
        (lower.contains('noto') && lower.contains('naskh'))) {
      return notoNaskhArabic;
    }
    return tajawal;
  }

  static String labelAr(String family) {
    switch (normalize(family)) {
      case notoNaskhArabic:
        return 'نوتو نسخ عربي';
      case cairo:
        return 'القاهرة';
      case almarai:
        return 'المراعي';
      case amiri:
        return 'أميري';
      case lateef:
        return 'لطيف';
      case scheherazadeNew:
        return 'شهرزاد الجديد';
      case ibmPlexSansArabic:
        return 'آي بي إم بلكس سانس عربي';
      case elMessiri:
        return 'المسيري';
      case changa:
        return 'تشانغا';
      case tajawal:
      default:
        return 'تجوال';
    }
  }

  static String subtitleAr(String family) {
    switch (normalize(family)) {
      case notoNaskhArabic:
        return 'نسخ تقليدي — مناسب للنصوص الطويلة والوثائق.';
      case cairo:
        return 'هندسي عصري — واجهات وتطبيقات حديثة.';
      case almarai:
        return 'نظيف ومقروء — يُستخدم كثيراً في الواجهات العربية.';
      case amiri:
        return 'كلاسيكي مائل للكتب والطباعة الرصينة.';
      case lateef:
        return 'نسخي مريح بسُمك متوسط — تميّز بسيط.';
      case scheherazadeNew:
        return 'نسخ تقليدي أنيق — حروف طويلة ووضوح جيد.';
      case ibmPlexSansArabic:
        return 'تقني منظم — أرقام وبيانات واضحة.';
      case elMessiri:
        return 'عناوين قوية — إيقاع مميز للعناوين.';
      case changa:
        return 'مائل للعرض — حروف عريضة ولافتة.';
      case tajawal:
      default:
        return 'خط عصري وواضح للواجهات والعناوين.';
    }
  }
}

/// حدود [SalePosSettingsData.wideSaleProductsFlex] (نسبة عمود المنتجات في العرض العريض).
abstract final class SaleWideLayoutFlexBounds {
  SaleWideLayoutFlexBounds._();

  static const int min = 25;
  static const int max = 75;
  static const int defaultProducts = 55;

  static int clampProducts(int v) =>
      v.clamp(SaleWideLayoutFlexBounds.min, SaleWideLayoutFlexBounds.max);
}

/// شكل زوايا لوحات تدفّق البيع (المنتجات، الملخص، العميل…).
enum SalePanelCornerStyle {
  /// زوايا قائمة — مظهر هندسي حاد.
  sharp,

  /// زوايا مستديرة — بطاقات أنعم.
  rounded,
}

/// معرّفات مخططات ألوان جاهزة لشاشة البيع (عند تفعيل «هوية الشعار»).
abstract final class SalePaletteIds {
  SalePaletteIds._();

  static const royal = 'royal';
  static const midnight = 'midnight';
  static const ocean = 'ocean';
  static const forest = 'forest';
  static const wine = 'wine';
  static const charcoal = 'charcoal';
  static const slate = 'slate';
  static const copper = 'copper';
  static const custom = 'custom';

  static const List<String> builtIn = [
    royal,
    midnight,
    ocean,
    forest,
    wine,
    charcoal,
    slate,
    copper,
  ];

  static String normalize(String? raw) {
    final id = (raw ?? royal).trim().toLowerCase();
    if (id == custom || builtIn.contains(id)) return id;
    return royal;
  }
}

/// إعدادات نقطة البيع — طرق الدفع، الخصم والضريبة، المظهر، والحقول.
@immutable
class SalePosSettingsData {
  const SalePosSettingsData({
    required this.enableTaxOnSale,
    required this.enableInvoiceDiscount,
    required this.allowCredit,
    required this.allowInstallment,
    required this.allowDelivery,
    required this.enforceAvailableQtyAtSale,
    required this.useSaleBrandSkin,
    required this.showBuyerAddressOnCash,
    required this.panelCornerStyle,
    required this.salePaletteId,
    this.customPrimaryArgb,
    this.customAccentArgb,
    this.customSurfaceArgb,
    this.customSurfaceDarkArgb,
    required this.enableWideSalePartition,
    required this.wideSaleProductsFlex,
    required this.appTextScale,
    required this.appFontFamily,
    this.appTextColorLightArgb,
    this.appTextColorDarkArgb,
  });

  final bool enableTaxOnSale;
  final bool enableInvoiceDiscount;
  final bool allowCredit;
  final bool allowInstallment;
  final bool allowDelivery;

  /// عند التفعيل: تمنع شاشة البيع زيادة الكمية فوق الرصيد المعروض للصنف.
  /// عند الإيقاف: يُسمح بالبيع حتى لو أصبح إجمالي الرصيد سالباً، فيُلغى السالب لاحقاً عند تسجيل وارد (نفس حقل [products.qty]).
  final bool enforceAvailableQtyAtSale;

  final bool useSaleBrandSkin;

  /// عند البيع النقدي: إظهار حقل عنوان المشتري إذا كان خيار QR العنوان مفعّلاً في إعدادات الطباعة.
  /// عند الإيقاف يُخفى الحقل للنقدي فقط (التوصيل لا يتأثر).
  final bool showBuyerAddressOnCash;

  /// زوايا لوحات البيع الرئيسية وبطاقات الأسطر.
  final SalePanelCornerStyle panelCornerStyle;

  /// مخطط ألوان [SalePaletteIds] أو `custom` مع الأربعة التالية.
  final String salePaletteId;

  final int? customPrimaryArgb;
  final int? customAccentArgb;
  final int? customSurfaceArgb;
  final int? customSurfaceDarkArgb;

  /// عند التعطيل: شاشة «بيع جديد» تبقى **عموداً واحداً** حتى على الشاشة العريضة (كالهاتف).
  final bool enableWideSalePartition;

  /// في العرض العريض (عرض ≥ 700dp) ومع [enableWideSalePartition]: وزن [Expanded] لعمود **المنتجات**؛ عمود الملخص والعميل = `100 - this`.
  final int wideSaleProductsFlex;

  /// مضاعف حجم النص في الواجهة (يُضرب مع مقياس النظام/إمكانية الوصول).
  final double appTextScale;

  /// عائلة الخط الافتراضية لكل النصوص ([AppFontFamilies]).
  final String appFontFamily;

  /// لون النص الرئيسي في الوضع الفاتح — `null` يعني لون الثيم الافتراضي.
  final int? appTextColorLightArgb;

  /// لون النص الرئيسي في الوضع الداكن — `null` يعني لون الثيم الافتراضي.
  final int? appTextColorDarkArgb;

  int get wideSaleSideFlex => 100 - wideSaleProductsFlex;

  static SalePosSettingsData defaults() => const SalePosSettingsData(
    enableTaxOnSale: true,
    enableInvoiceDiscount: true,
    allowCredit: true,
    allowInstallment: true,
    allowDelivery: true,
    enforceAvailableQtyAtSale: false,
    useSaleBrandSkin: true,
    showBuyerAddressOnCash: true,
    panelCornerStyle: SalePanelCornerStyle.sharp,
    salePaletteId: SalePaletteIds.royal,
    customPrimaryArgb: null,
    customAccentArgb: null,
    customSurfaceArgb: null,
    customSurfaceDarkArgb: null,
    enableWideSalePartition: true,
    wideSaleProductsFlex: SaleWideLayoutFlexBounds.defaultProducts,
    appTextScale: 1.0,
    appFontFamily: AppFontFamilies.tajawal,
    appTextColorLightArgb: null,
    appTextColorDarkArgb: null,
  );

  /// نصف قطر زوايا اللوحات والبطاقات في شاشة البيع.
  BorderRadius get saleFlowBorderRadius =>
      panelCornerStyle == SalePanelCornerStyle.rounded
      ? const BorderRadius.all(Radius.circular(14))
      : BorderRadius.zero;

  /// زوايا شرائح نوع الدفع.
  BorderRadius get saleChipBorderRadius =>
      panelCornerStyle == SalePanelCornerStyle.rounded
      ? BorderRadius.circular(10)
      : BorderRadius.circular(2);

  factory SalePosSettingsData.fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaults();
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final cornerRaw = m['panelCorners'] ?? m['corner'];
      SalePanelCornerStyle corners = SalePanelCornerStyle.sharp;
      if (cornerRaw == 1 ||
          cornerRaw == 'rounded' ||
          cornerRaw == 'r' ||
          cornerRaw == true) {
        corners = SalePanelCornerStyle.rounded;
      }
      int? optArgb(dynamic v) {
        if (v == null) return null;
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v.toString());
      }

      return SalePosSettingsData(
        enableTaxOnSale: m['tax'] != false,
        enableInvoiceDiscount: m['discount'] != false,
        allowCredit: m['credit'] != false,
        allowInstallment: m['installment'] != false,
        allowDelivery: m['delivery'] != false,
        enforceAvailableQtyAtSale: m.containsKey('enforceAvailQty')
            ? m['enforceAvailQty'] != false
            : false,
        useSaleBrandSkin: m['brandUi'] != false,
        showBuyerAddressOnCash: m['buyerAddrCash'] != false,
        panelCornerStyle: corners,
        salePaletteId: SalePaletteIds.normalize(
          m['salePalette']?.toString() ?? m['pal']?.toString(),
        ),
        customPrimaryArgb: optArgb(m['customNavy'] ?? m['cNv']),
        customAccentArgb: optArgb(m['customGold'] ?? m['cGd']),
        customSurfaceArgb: optArgb(m['customIvory'] ?? m['cIv']),
        customSurfaceDarkArgb: optArgb(m['customIvoryDark'] ?? m['cIvD']),
        enableWideSalePartition: m.containsKey('widePartition')
            ? m['widePartition'] != false
            : true,
        wideSaleProductsFlex: m.containsKey('wideProdFlex')
            ? SaleWideLayoutFlexBounds.clampProducts(
                (m['wideProdFlex'] as num).round(),
              )
            : SaleWideLayoutFlexBounds.defaultProducts,
        appTextScale: AppTypographyScaleBounds.clamp(_readJsonTextScale(m)),
        appFontFamily: AppFontFamilies.normalize(
          m['fontFam']?.toString() ?? m['fontFamily']?.toString(),
        ),
        appTextColorLightArgb: optArgb(m['textColLight'] ?? m['txtL']),
        appTextColorDarkArgb: optArgb(m['textColDark'] ?? m['txtD']),
      );
    } catch (_) {
      return defaults();
    }
  }

  String toJsonString() => jsonEncode({
    'v': 6,
    'tax': enableTaxOnSale,
    'discount': enableInvoiceDiscount,
    'credit': allowCredit,
    'installment': allowInstallment,
    'delivery': allowDelivery,
    'enforceAvailQty': enforceAvailableQtyAtSale,
    'brandUi': useSaleBrandSkin,
    'buyerAddrCash': showBuyerAddressOnCash,
    'panelCorners': panelCornerStyle == SalePanelCornerStyle.rounded
        ? 'rounded'
        : 'sharp',
    'salePalette': salePaletteId,
    if (customPrimaryArgb != null) 'customNavy': customPrimaryArgb,
    if (customAccentArgb != null) 'customGold': customAccentArgb,
    if (customSurfaceArgb != null) 'customIvory': customSurfaceArgb,
    if (customSurfaceDarkArgb != null) 'customIvoryDark': customSurfaceDarkArgb,
    'widePartition': enableWideSalePartition,
    'wideProdFlex': wideSaleProductsFlex,
    'textScale': appTextScale,
    'fontFam': appFontFamily,
    if (appTextColorLightArgb != null) 'textColLight': appTextColorLightArgb,
    if (appTextColorDarkArgb != null) 'textColDark': appTextColorDarkArgb,
  });

  bool allowsPayment(InvoiceType t) {
    switch (t) {
      case InvoiceType.cash:
        return true;
      case InvoiceType.credit:
        return allowCredit;
      case InvoiceType.installment:
        return allowInstallment;
      case InvoiceType.delivery:
        return allowDelivery;
      case InvoiceType.debtCollection:
      case InvoiceType.installmentCollection:
      case InvoiceType.supplierPayment:
        return false;
    }
  }

  SalePosSettingsData copyWith({
    bool? enableTaxOnSale,
    bool? enableInvoiceDiscount,
    bool? allowCredit,
    bool? allowInstallment,
    bool? allowDelivery,
    bool? enforceAvailableQtyAtSale,
    bool? useSaleBrandSkin,
    bool? showBuyerAddressOnCash,
    SalePanelCornerStyle? panelCornerStyle,
    String? salePaletteId,
    int? customPrimaryArgb,
    int? customAccentArgb,
    int? customSurfaceArgb,
    int? customSurfaceDarkArgb,
    bool? enableWideSalePartition,
    int? wideSaleProductsFlex,
    double? appTextScale,
    String? appFontFamily,
    int? appTextColorLightArgb,
    int? appTextColorDarkArgb,
  }) {
    return SalePosSettingsData(
      enableTaxOnSale: enableTaxOnSale ?? this.enableTaxOnSale,
      enableInvoiceDiscount:
          enableInvoiceDiscount ?? this.enableInvoiceDiscount,
      allowCredit: allowCredit ?? this.allowCredit,
      allowInstallment: allowInstallment ?? this.allowInstallment,
      allowDelivery: allowDelivery ?? this.allowDelivery,
      enforceAvailableQtyAtSale:
          enforceAvailableQtyAtSale ?? this.enforceAvailableQtyAtSale,
      useSaleBrandSkin: useSaleBrandSkin ?? this.useSaleBrandSkin,
      showBuyerAddressOnCash:
          showBuyerAddressOnCash ?? this.showBuyerAddressOnCash,
      panelCornerStyle: panelCornerStyle ?? this.panelCornerStyle,
      salePaletteId: salePaletteId ?? this.salePaletteId,
      customPrimaryArgb: customPrimaryArgb ?? this.customPrimaryArgb,
      customAccentArgb: customAccentArgb ?? this.customAccentArgb,
      customSurfaceArgb: customSurfaceArgb ?? this.customSurfaceArgb,
      customSurfaceDarkArgb:
          customSurfaceDarkArgb ?? this.customSurfaceDarkArgb,
      enableWideSalePartition:
          enableWideSalePartition ?? this.enableWideSalePartition,
      wideSaleProductsFlex: wideSaleProductsFlex != null
          ? SaleWideLayoutFlexBounds.clampProducts(wideSaleProductsFlex)
          : this.wideSaleProductsFlex,
      appTextScale: appTextScale != null
          ? AppTypographyScaleBounds.clamp(appTextScale)
          : this.appTextScale,
      appFontFamily: appFontFamily != null
          ? AppFontFamilies.normalize(appFontFamily)
          : this.appFontFamily,
      appTextColorLightArgb: appTextColorLightArgb ?? this.appTextColorLightArgb,
      appTextColorDarkArgb: appTextColorDarkArgb ?? this.appTextColorDarkArgb,
    );
  }

  /// مسح لون النص للوضع الفاتح فقط.
  SalePosSettingsData clearAppTextColorLight() {
    return SalePosSettingsData(
      enableTaxOnSale: enableTaxOnSale,
      enableInvoiceDiscount: enableInvoiceDiscount,
      allowCredit: allowCredit,
      allowInstallment: allowInstallment,
      allowDelivery: allowDelivery,
      enforceAvailableQtyAtSale: enforceAvailableQtyAtSale,
      useSaleBrandSkin: useSaleBrandSkin,
      showBuyerAddressOnCash: showBuyerAddressOnCash,
      panelCornerStyle: panelCornerStyle,
      salePaletteId: salePaletteId,
      customPrimaryArgb: customPrimaryArgb,
      customAccentArgb: customAccentArgb,
      customSurfaceArgb: customSurfaceArgb,
      customSurfaceDarkArgb: customSurfaceDarkArgb,
      enableWideSalePartition: enableWideSalePartition,
      wideSaleProductsFlex: wideSaleProductsFlex,
      appTextScale: appTextScale,
      appFontFamily: appFontFamily,
      appTextColorLightArgb: null,
      appTextColorDarkArgb: appTextColorDarkArgb,
    );
  }

  /// مسح لون النص للوضع الداكن فقط.
  SalePosSettingsData clearAppTextColorDark() {
    return SalePosSettingsData(
      enableTaxOnSale: enableTaxOnSale,
      enableInvoiceDiscount: enableInvoiceDiscount,
      allowCredit: allowCredit,
      allowInstallment: allowInstallment,
      allowDelivery: allowDelivery,
      enforceAvailableQtyAtSale: enforceAvailableQtyAtSale,
      useSaleBrandSkin: useSaleBrandSkin,
      showBuyerAddressOnCash: showBuyerAddressOnCash,
      panelCornerStyle: panelCornerStyle,
      salePaletteId: salePaletteId,
      customPrimaryArgb: customPrimaryArgb,
      customAccentArgb: customAccentArgb,
      customSurfaceArgb: customSurfaceArgb,
      customSurfaceDarkArgb: customSurfaceDarkArgb,
      enableWideSalePartition: enableWideSalePartition,
      wideSaleProductsFlex: wideSaleProductsFlex,
      appTextScale: appTextScale,
      appFontFamily: appFontFamily,
      appTextColorLightArgb: appTextColorLightArgb,
      appTextColorDarkArgb: null,
    );
  }

  /// إزالة ألوان النص المخصصة والعودة لألوان الثيم.
  SalePosSettingsData clearAppTextColors() {
    return SalePosSettingsData(
      enableTaxOnSale: enableTaxOnSale,
      enableInvoiceDiscount: enableInvoiceDiscount,
      allowCredit: allowCredit,
      allowInstallment: allowInstallment,
      allowDelivery: allowDelivery,
      enforceAvailableQtyAtSale: enforceAvailableQtyAtSale,
      useSaleBrandSkin: useSaleBrandSkin,
      showBuyerAddressOnCash: showBuyerAddressOnCash,
      panelCornerStyle: panelCornerStyle,
      salePaletteId: salePaletteId,
      customPrimaryArgb: customPrimaryArgb,
      customAccentArgb: customAccentArgb,
      customSurfaceArgb: customSurfaceArgb,
      customSurfaceDarkArgb: customSurfaceDarkArgb,
      enableWideSalePartition: enableWideSalePartition,
      wideSaleProductsFlex: wideSaleProductsFlex,
      appTextScale: appTextScale,
      appFontFamily: appFontFamily,
      appTextColorLightArgb: null,
      appTextColorDarkArgb: null,
    );
  }

  /// يعيد حقول المظهر (الخط، الحجم، الألوان، المخطط، الزوايا، تقسيم العرض العريض)
  /// إلى [SalePosSettingsData.defaults] دون تغيير سياسات البيع أو الضريبة أو المخزون.
  SalePosSettingsData withAppearanceResetToDefaults() {
    final def = SalePosSettingsData.defaults();
    return SalePosSettingsData(
      enableTaxOnSale: enableTaxOnSale,
      enableInvoiceDiscount: enableInvoiceDiscount,
      allowCredit: allowCredit,
      allowInstallment: allowInstallment,
      allowDelivery: allowDelivery,
      enforceAvailableQtyAtSale: enforceAvailableQtyAtSale,
      useSaleBrandSkin: def.useSaleBrandSkin,
      showBuyerAddressOnCash: showBuyerAddressOnCash,
      panelCornerStyle: def.panelCornerStyle,
      salePaletteId: def.salePaletteId,
      customPrimaryArgb: null,
      customAccentArgb: null,
      customSurfaceArgb: null,
      customSurfaceDarkArgb: null,
      enableWideSalePartition: def.enableWideSalePartition,
      wideSaleProductsFlex: def.wideSaleProductsFlex,
      appTextScale: def.appTextScale,
      appFontFamily: def.appFontFamily,
      appTextColorLightArgb: null,
      appTextColorDarkArgb: null,
    );
  }
}

/// ألوان فعّالة لشاشة البيع (هوية الشعار أو ألوان الثيم).
@immutable
class SalePalette {
  const SalePalette({
    required this.navy,
    required this.gold,
    required this.ivory,
    required this.ivoryDark,
  });

  final Color navy;
  final Color gold;
  final Color ivory;
  final Color ivoryDark;

  static SalePalette _presetPalette(String id) {
    switch (id) {
      case SalePaletteIds.midnight:
        return const SalePalette(
          navy: Color(0xFF0D1B2A),
          gold: Color(0xFFC5C6C7),
          ivory: Color(0xFFE0E1DD),
          ivoryDark: Color(0xFF1B263B),
        );
      case SalePaletteIds.ocean:
        return const SalePalette(
          navy: Color(0xFF0E4E5B),
          gold: Color(0xFFD4A574),
          ivory: Color(0xFFF4F1EA),
          ivoryDark: Color(0xFF123440),
        );
      case SalePaletteIds.forest:
        return const SalePalette(
          navy: Color(0xFF1B4332),
          gold: Color(0xFFBC6C25),
          ivory: Color(0xFFF2F7F5),
          ivoryDark: Color(0xFF081C15),
        );
      case SalePaletteIds.wine:
        return const SalePalette(
          navy: Color(0xFF4A0E16),
          gold: Color(0xFFCBA135),
          ivory: Color(0xFFFBF7F7),
          ivoryDark: Color(0xFF2D0508),
        );
      case SalePaletteIds.charcoal:
        return const SalePalette(
          navy: Color(0xFF2B2D42),
          gold: Color(0xFFE8A838),
          ivory: Color(0xFFF8F7FF),
          ivoryDark: Color(0xFF1A1B2E),
        );
      case SalePaletteIds.slate:
        return const SalePalette(
          navy: Color(0xFF334155),
          gold: Color(0xFF38BDF8),
          ivory: Color(0xFFF8FAFC),
          ivoryDark: Color(0xFF0F172A),
        );
      case SalePaletteIds.copper:
        return const SalePalette(
          navy: Color(0xFF3D2914),
          gold: Color(0xFFB87333),
          ivory: Color(0xFFF5EBDD),
          ivoryDark: Color(0xFF1F1408),
        );
      case SalePaletteIds.royal:
      default:
        return const SalePalette(
          navy: SaleBrandColors.navy,
          gold: SaleBrandColors.gold,
          ivory: SaleBrandColors.ivory,
          ivoryDark: SaleBrandColors.ivoryDark,
        );
    }
  }

  factory SalePalette.fromSettings(SalePosSettingsData d, ThemeData theme) {
    if (!d.useSaleBrandSkin) {
      final cs = theme.colorScheme;
      final dark = theme.brightness == Brightness.dark;
      return SalePalette(
        navy: cs.primary,
        gold: cs.tertiary,
        ivory: dark ? cs.surfaceContainerHigh : cs.surfaceContainerLowest,
        ivoryDark: cs.surfaceContainerHigh,
      );
    }
    if (d.salePaletteId == SalePaletteIds.custom) {
      return SalePalette(
        navy: Color(d.customPrimaryArgb ?? 0xFF152B47),
        gold: Color(d.customAccentArgb ?? 0xFFC9A85C),
        ivory: Color(d.customSurfaceArgb ?? 0xFFF7F4EF),
        ivoryDark: Color(d.customSurfaceDarkArgb ?? 0xFF1A2433),
      );
    }
    return _presetPalette(d.salePaletteId);
  }
}

extension SalePosSettingsDataPaletteX on SalePosSettingsData {
  /// يمسح ألوان «مخصص» عند العودة لمخطط جاهز (لا يغيّر [salePaletteId]).
  SalePosSettingsData clearCustomPaletteFields() {
    return SalePosSettingsData(
      enableTaxOnSale: enableTaxOnSale,
      enableInvoiceDiscount: enableInvoiceDiscount,
      allowCredit: allowCredit,
      allowInstallment: allowInstallment,
      allowDelivery: allowDelivery,
      enforceAvailableQtyAtSale: enforceAvailableQtyAtSale,
      useSaleBrandSkin: useSaleBrandSkin,
      showBuyerAddressOnCash: showBuyerAddressOnCash,
      panelCornerStyle: panelCornerStyle,
      salePaletteId: salePaletteId,
      customPrimaryArgb: null,
      customAccentArgb: null,
      customSurfaceArgb: null,
      customSurfaceDarkArgb: null,
      enableWideSalePartition: enableWideSalePartition,
      wideSaleProductsFlex: wideSaleProductsFlex,
      appTextScale: appTextScale,
      appFontFamily: appFontFamily,
      appTextColorLightArgb: appTextColorLightArgb,
      appTextColorDarkArgb: appTextColorDarkArgb,
    );
  }
}
