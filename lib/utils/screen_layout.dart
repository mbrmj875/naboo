import 'package:flutter/material.dart';

// للتمييز حسب نظام التشغيل (كاميرا باركود، اهتزاز) انظر target_platform_helpers.dart (isMobileOsBuild).

/// فئات الأجهزة المعتمدة في واجهة Naboo (متنافية بالضرورة - Mutually Exclusive)
enum DeviceVariant {
  phoneXS,
  phoneSM,
  tabletSM,
  tabletLG,
  desktopSM,
  desktopLG,
}

/// تخطيط مُهيّأ للشاشات الصغيرة (عرض ضيق أو ارتفاع قليل).
///
/// يُفضّل الاعتماد على [ScreenLayout.of] داخل `build` بدل ثوابت هوامش ثابتة.
@immutable
class ScreenLayout {
  const ScreenLayout._({
    required this.size,
    required this.viewPadding,
  });

  final Size size;
  final EdgeInsets viewPadding;

  factory ScreenLayout.of(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ScreenLayout._(
      size: mq.size,
      viewPadding: mq.padding,
    );
  }

  // ===========================================================================
  // 📏 مقاسات التخطيط المتجاوب (Adaptive UI Breakpoints)
  // ⚠️ تحذير معماري: هذه الدوال تُستخدم حصرياً لاتخاذ قرارات التخطيط.
  // ===========================================================================

  /// يحدد فئة التخطيط الحالية لضمان عدم وجود تداخل (Mutually Exclusive).
  DeviceVariant get layoutVariant {
    if (size.width < 360 || size.height < 600) return DeviceVariant.phoneXS;
    if (size.width < 600) return DeviceVariant.phoneSM;
    if (size.width < 840) return DeviceVariant.tabletSM;
    if (size.width < 1024) return DeviceVariant.tabletLG;
    if (size.width < 1440) return DeviceVariant.desktopSM;
    return DeviceVariant.desktopLG;
  }

  bool get isPhoneXS => layoutVariant == DeviceVariant.phoneXS;
  bool get isPhoneSM => layoutVariant == DeviceVariant.phoneSM;
  bool get isTabletSM => layoutVariant == DeviceVariant.tabletSM;
  bool get isTabletLG => layoutVariant == DeviceVariant.tabletLG;
  bool get isDesktopSM => layoutVariant == DeviceVariant.desktopSM;
  bool get isDesktopLG => layoutVariant == DeviceVariant.desktopLG;

  /// مجاميع شائعة (Composite helpers) — لتقليل التكرار في الشاشات.
  /// راجع §11.1 في `docs/screen_migration_playbook.md`.

  /// `true` إذا الجهاز هاتف (`phoneXS` أو `phoneSM`).
  /// المُستهلكون: قرارات إخفاء عناصر للأجهزة الصغيرة، طيّ المحتوى، إلخ.
  bool get isPhoneVariant =>
      layoutVariant == DeviceVariant.phoneXS ||
      layoutVariant == DeviceVariant.phoneSM;

  /// `true` إذا الجهاز تابلت بأي مقاس (`tabletSM` أو `tabletLG`).
  bool get isTabletVariant =>
      layoutVariant == DeviceVariant.tabletSM ||
      layoutVariant == DeviceVariant.tabletLG;

  /// `true` إذا الجهاز ديسكتوب بأي مقاس (`desktopSM` أو `desktopLG`).
  bool get isDesktopVariant =>
      layoutVariant == DeviceVariant.desktopSM ||
      layoutVariant == DeviceVariant.desktopLG;

  /// `true` لأي تابلت كبير أو ديسكتوب — مفيد لقرارات Master-Detail و Wide-Form.
  bool get isWideVariant => layoutVariant.index >= DeviceVariant.tabletLG.index;

  // ===========================================================================
  // مقاسات ومحددات النظام القديمة (Legacy & Physical Metrics)
  // يُسمح باستخدامها، لكن لا تُعدلها أبداً لضمان التوافق الخلفي.
  // ===========================================================================

  /// عرض أقل من ~هاتف صغير (مثل 360dp).
  bool get isNarrowWidth => size.width < 360;

  /// ارتفاع أقل من هاتف عادي — مساحة أقل للمحتوى + لوحة مفاتيح.
  bool get isCompactHeight => size.height < 640;

  /// شاشة قصيرة جداً (أجهزة قديمة أو نافذة مقسومة).
  bool get isVeryShort => size.height < 560;

  /// هوامش أفقية للصفحات والبطاقات.
  double get pageHorizontalGap =>
      isNarrowWidth ? 10.0 : (size.width < 400 ? 12.0 : 16.0);

  /// ارتفاع منطقة البحث تحت [AppBar] (بدون شريط التنقل السفلي).
  double get appBarSearchSectionHeight {
    if (isVeryShort) return 50;
    if (isCompactHeight) return 56;
    return 62;
  }

  /// حجم ابتدائي معقول لـ [DraggableScrollableSheet] على الشاشات القصيرة.
  double get sheetInitialFraction {
    if (isVeryShort) return 0.96;
    if (isCompactHeight) return 0.92;
    return 0.9;
  }

  double get sheetMinFraction => isVeryShort ? 0.32 : 0.4;

  /// لوحة مفاتيح النظام كافية — إخفاء لوحة البحث داخل التطبيق (هواتف صغيرة / قصيرة).
  ///
  /// يعتمد على أضيق بعد للشاشة ليشمل الهاتف أفقيًا أيضًا.
  bool get hideInAppSearchKeyboard =>
      isNarrowWidth ||
      isCompactHeight ||
      size.shortestSide < 500;

  /// زر/اختصار باركود في واجهة البيع — عرض أقل من 700dp (نافذة ضيقة أو هاتف).
  /// (مسار الكاميرا الفعلي يُحدَّد في [BarcodeInputLauncher.useCamera] حسب نظام التشغيل.)
  bool get showSaleBarcodeShortcut => size.width < 700;

  /// هاتف بحجم مادي نموذجي — أضيق بعد أقل من 600dp (يشمل الهاتف عموديًا وأفقيًا تقريبًا).
  ///
  /// ⚠️ **للقرارات المعمارية الجديدة استخدم [isPhoneVariant] بدلاً من هذا الـ getter.**
  /// `isPhoneVariant` يقرأ `DeviceVariant` (المصدر الواحد للحقيقة) بدلاً من
  /// `shortestSide`، ما يضمن اتساقاً مع بقية النظام.
  ///
  /// يبقى `isHandsetForLayout` متاحًا للتوافق مع الشيفرة القديمة وللقرارات
  /// المادية البحتة (مثل اختيار حجم خط نص، عدد أسطر، أو رسوميات تعتمد على
  /// أبعاد حقيقية بالبكسل).
  bool get isHandsetForLayout => size.shortestSide < 600;

  /// تقسيم شاشة «بيع جديد» إلى عمودين مع فاصل سحب — **غير مفعّل على الهاتف** ([isHandsetForLayout]).
  ///
  /// يتطلّب أيضًا عرضًا ≥ 700dp حتى يكون للعمودين عرضًا مفيدًا.
  bool get useWideSaleTwoColumnLayout =>
      !isHandsetForLayout && size.width >= 700;
}

extension ScreenLayoutX on BuildContext {
  ScreenLayout get screenLayout => ScreenLayout.of(this);
}
