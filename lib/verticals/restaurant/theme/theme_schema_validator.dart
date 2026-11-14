import 'dart:convert';

import 'presets/presets.dart';
import 'layout_slots.dart';

/// تخصيص التاجر داخل draft_json / published_json (§13.5.10 + توسعة تخطيط).
class RestaurantThemeCustomization {
  const RestaurantThemeCustomization({
    required this.version,
    required this.presetKey,
    required this.menuLanguage,
    required this.fontFamily,
    required this.colors,
    required this.identity,
    required this.toggles,
    required this.layout,
  });

  final int version;
  final RestaurantPresetKey presetKey;
  final RestaurantMenuLanguage menuLanguage;
  final RestaurantFontFamily fontFamily;
  final Map<String, String> colors;
  final Map<String, String?> identity;
  final Map<String, bool> toggles;
  final Map<String, String> layout;

  String get layoutDirection => menuLanguage.layoutDirection;

  RestaurantArchitecturePreset get architecture =>
      kRestaurantPresets[presetKey]!;

  RestaurantItemLayout get itemLayout =>
      RestaurantItemLayoutX.tryParse(layout['item_layout']) ??
      architecture.defaultItemLayout;

  RestaurantWelcomeMode get welcomeMode =>
      RestaurantWelcomeModeX.tryParse(layout['welcome_mode']) ??
      RestaurantWelcomeMode.none;

  MenuHomeLayoutSlot get homeLayoutSlot =>
      MenuHomeLayoutSlotX.tryParse(layout['home_layout']) ??
      MenuHomeLayoutSlot.followChrome;

  MenuSearchStyleSlot get searchStyleSlot =>
      MenuSearchStyleSlotX.tryParse(layout['search_style']) ??
      MenuSearchStyleSlot.materialFill;

  MenuBottomNavSlot get bottomNavSlot =>
      MenuBottomNavSlotX.tryParse(layout['bottom_nav']) ??
      MenuBottomNavSlot.materialLabeled;

  MenuProfileSheetSlot get profileSheetSlot =>
      MenuProfileSheetSlotX.tryParse(layout['profile_sheet']) ??
      MenuProfileSheetSlot.sheetGrab;

  MenuMotionSlot get motionSlot =>
      MenuMotionSlotX.tryParse(layout['motion']) ?? MenuMotionSlot.fade;

  MenuMotionSpeedSlot get motionSpeedSlot =>
      MenuMotionSpeedSlotX.tryParse(layout['motion_speed']) ??
      MenuMotionSpeedSlot.normal;

  /// مدة حركة البطاقة بالميلي ثانية (شريط السرعة) — 120…1000.
  int get motionDurationMs {
    final raw = layout['motion_ms'];
    if (raw != null && raw.isNotEmpty) {
      final v = int.tryParse(raw);
      if (v != null) return v.clamp(120, 1000);
    }
    return motionSpeedSlot.resolvedDurationMs;
  }

  /// تأخير التتابع بين البطاقات (مستنتج من المدة إن لم يُضبط).
  int get motionStaggerMs {
    final raw = layout['motion_stagger_ms'];
    if (raw != null && raw.isNotEmpty) {
      final v = int.tryParse(raw);
      if (v != null) return v.clamp(0, 120);
    }
    return (motionDurationMs * 0.14).round().clamp(8, 90);
  }

  MenuCategoryNavSlot get categoryNavSlot {
    final fromLayout =
        MenuCategoryNavSlotX.tryParse(layout['category_nav']);
    if (fromLayout != null) return fromLayout;
    if (toggles['show_category_nav'] == false) {
      return MenuCategoryNavSlot.hidden;
    }
    final preset = kRestaurantPresets[presetKey];
    return MenuCategoryNavSlotX.tryParse(preset?.categoryNav) ??
        MenuCategoryNavSlot.topUnderline;
  }

  MenuBrandLogoAlign get brandLogoAlign =>
      MenuBrandLogoAlignX.tryParse(layout['brand_logo_align']) ??
      MenuBrandLogoAlign.start;

  MenuBrandTextPlacement get brandTextPlacement =>
      MenuBrandTextPlacementX.tryParse(layout['brand_text_placement']) ??
      MenuBrandTextPlacement.beside;

  MenuBrandTextAlign get brandTextAlign =>
      MenuBrandTextAlignX.tryParse(layout['brand_text_align']) ??
      MenuBrandTextAlign.start;

  factory RestaurantThemeCustomization.defaults() {
    final preset = kRestaurantPresets[RestaurantPresetKey.royal]!;
    return RestaurantThemeCustomization(
      version: 1,
      presetKey: RestaurantPresetKey.royal,
      menuLanguage: RestaurantMenuLanguage.ar,
      fontFamily: RestaurantFontFamily.tajawal,
      colors: Map<String, String>.from(preset.defaultColors),
      identity: const {
        'display_name_ar': '',
        'display_name_en': null,
        'tagline_ar': '',
        'tagline_en': null,
        'logo_url': null,
        'cover_url': null,
      },
      toggles: const {
        'show_prices': true,
        'show_item_descriptions': true,
        'show_logo_in_header': true,
        'show_category_nav': true,
      },
      layout: {
        'item_layout': preset.defaultItemLayout.key,
        'welcome_mode': RestaurantWelcomeMode.none.key,
      },
    );
  }

  factory RestaurantThemeCustomization.fromJson(Map<String, dynamic> json) {
    final preset = RestaurantPresetKeyX.tryParse(json['preset_key'] as String?);
    final lang =
        RestaurantMenuLanguageX.tryParse(json['menu_language'] as String?);
    final font =
        RestaurantFontFamilyX.tryParse(json['font_family'] as String?);
    if (preset == null || lang == null || font == null) {
      throw const FormatException('theme_json_invalid_enum');
    }
    final colorsRaw = json['colors'];
    final identityRaw = json['identity'];
    final togglesRaw = json['toggles'];
    if (colorsRaw is! Map || identityRaw is! Map || togglesRaw is! Map) {
      throw const FormatException('theme_json_invalid_shape');
    }
    final layoutRaw = json['layout'];
    final layout = <String, String>{
      'item_layout':
          kRestaurantPresets[preset]!.defaultItemLayout.key,
      'welcome_mode': RestaurantWelcomeMode.none.key,
    };
    if (layoutRaw is Map) {
      for (final e in layoutRaw.entries) {
        layout['${e.key}'] = '${e.value}';
      }
    }
    final toggles = <String, bool>{
      'show_prices': true,
      'show_item_descriptions': true,
      'show_logo_in_header': true,
      'show_category_nav': true,
    };
    for (final e in togglesRaw.entries) {
      toggles['${e.key}'] = e.value == true;
    }
    return RestaurantThemeCustomization(
      version: (json['version'] as num?)?.toInt() ?? 1,
      presetKey: preset,
      menuLanguage: lang,
      fontFamily: font,
      colors: colorsRaw.map((k, v) => MapEntry('$k', '$v')),
      identity: identityRaw.map(
        (k, v) => MapEntry('$k', v?.toString()),
      ),
      toggles: toggles,
      layout: layout,
    );
  }

  factory RestaurantThemeCustomization.fromJsonString(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('theme_json_not_object');
    }
    return RestaurantThemeCustomization.fromJson(decoded);
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'preset_key': presetKey.key,
        'menu_language': menuLanguage.key,
        'font_family': fontFamily.key,
        'colors': colors,
        'identity': identity,
        'toggles': toggles,
        'layout': layout,
      };

  String toJsonString() => jsonEncode(toJson());

  RestaurantThemeCustomization copyWith({
    RestaurantPresetKey? presetKey,
    RestaurantMenuLanguage? menuLanguage,
    RestaurantFontFamily? fontFamily,
    Map<String, String>? colors,
    Map<String, String?>? identity,
    Map<String, bool>? toggles,
    Map<String, String>? layout,
  }) {
    return RestaurantThemeCustomization(
      version: version,
      presetKey: presetKey ?? this.presetKey,
      menuLanguage: menuLanguage ?? this.menuLanguage,
      fontFamily: fontFamily ?? this.fontFamily,
      colors: colors ?? this.colors,
      identity: identity ?? this.identity,
      toggles: toggles ?? this.toggles,
      layout: layout ?? this.layout,
    );
  }
}

/// مدقق schema مقفَل — أي مفتاح غير معروف = رفض.
abstract final class ThemeSchemaValidator {
  ThemeSchemaValidator._();

  static const _rootKeys = {
    'version',
    'preset_key',
    'menu_language',
    'font_family',
    'colors',
    'identity',
    'toggles',
    'layout',
  };

  static const _colorKeys = {'primary', 'accent', 'bg', 'text'};
  static const _identityKeys = {
    'display_name_ar',
    'display_name_en',
    'tagline_ar',
    'tagline_en',
    'logo_url',
    'cover_url',
  };
  static const _toggleKeys = {
    'show_prices',
    'show_item_descriptions',
    'show_logo_in_header',
    'show_category_nav',
  };
  static const _layoutKeys = {
    'item_layout',
    'welcome_mode',
    'home_layout',
    'search_style',
    'bottom_nav',
    'profile_sheet',
    'motion',
    'motion_speed',
    'motion_ms',
    'motion_stagger_ms',
    'category_nav',
    'cart_layout',
    'orders_layout',
    'brand_logo_align',
    'brand_text_placement',
    'brand_text_align',
  };

  static final _hex = RegExp(r'^#[0-9A-Fa-f]{6}$');

  /// يعيد null عند النجاح، أو رسالة خطأ عربية.
  static String? validate(Map<String, dynamic> json) {
    for (final k in json.keys) {
      if (!_rootKeys.contains(k)) {
        return 'مفتاح غير مسموح في الثيم: $k';
      }
    }
    for (final required in _rootKeys) {
      if (!json.containsKey(required)) {
        // layout اختياري للتوافق مع مسودات قديمة — نكمل التحقق بعده
        if (required == 'layout') continue;
        return 'حقل مطلوب ناقص: $required';
      }
    }
    if (json['version'] != 1) {
      return 'إصدار الثيم غير مدعوم';
    }
    if (RestaurantPresetKeyX.tryParse(json['preset_key'] as String?) == null) {
      return 'preset غير معروف';
    }
    if (RestaurantMenuLanguageX.tryParse(json['menu_language'] as String?) ==
        null) {
      return 'لغة المنيو غير صالحة';
    }
    if (RestaurantFontFamilyX.tryParse(json['font_family'] as String?) == null) {
      return 'خط غير مسموح';
    }

    final colors = json['colors'];
    if (colors is! Map) return 'ألوان الثيم غير صالحة';
    for (final k in colors.keys) {
      if (!_colorKeys.contains('$k')) return 'لون غير مسموح: $k';
    }
    for (final k in _colorKeys) {
      final v = colors[k]?.toString();
      if (v == null || !_hex.hasMatch(v)) {
        return 'لون $k يجب أن يكون بصيغة #RRGGBB';
      }
    }

    final identity = json['identity'];
    if (identity is! Map) return 'هوية المطعم غير صالحة';
    for (final k in identity.keys) {
      if (!_identityKeys.contains('$k')) return 'حقل هوية غير مسموح: $k';
    }

    final toggles = json['toggles'];
    if (toggles is! Map) return 'خيارات العرض غير صالحة';
    for (final k in toggles.keys) {
      if (!_toggleKeys.contains('$k')) return 'خيار عرض غير مسموح: $k';
    }
    for (final e in toggles.entries) {
      if (e.value is! bool) return 'خيار ${e.key} يجب أن يكون منطقياً';
    }

    final layout = json['layout'];
    if (layout != null) {
      if (layout is! Map) return 'خيارات التخطيط غير صالحة';
      for (final k in layout.keys) {
        if (!_layoutKeys.contains('$k')) return 'تخطيط غير مسموح: $k';
      }
      final itemLayout = layout['item_layout']?.toString();
      if (itemLayout != null &&
          RestaurantItemLayoutX.tryParse(itemLayout) == null) {
        return 'عرض الأصناف غير صالح';
      }
      final welcome = layout['welcome_mode']?.toString();
      if (welcome != null && RestaurantWelcomeModeX.tryParse(welcome) == null) {
        return 'وضع الترحيب غير صالح';
      }
      if (layout['home_layout'] != null &&
          MenuHomeLayoutSlotX.tryParse(layout['home_layout']?.toString()) ==
              null) {
        return 'قالب الرئيسية غير صالح';
      }
      if (layout['search_style'] != null &&
          MenuSearchStyleSlotX.tryParse(layout['search_style']?.toString()) ==
              null) {
        return 'شكل البحث غير صالح';
      }
      if (layout['bottom_nav'] != null &&
          MenuBottomNavSlotX.tryParse(layout['bottom_nav']?.toString()) ==
              null) {
        return 'شكل الشريط السفلي غير صالح';
      }
      if (layout['profile_sheet'] != null &&
          MenuProfileSheetSlotX.tryParse(layout['profile_sheet']?.toString()) ==
              null) {
        return 'شكل الملف الشخصي غير صالح';
      }
      if (layout['motion'] != null &&
          MenuMotionSlotX.tryParse(layout['motion']?.toString()) == null) {
        return 'قالب الحركة غير صالح';
      }
      if (layout['motion_speed'] != null &&
          MenuMotionSpeedSlotX.tryParse(
                  layout['motion_speed']?.toString()) ==
              null) {
        return 'سرعة الحركة غير صالحة';
      }
      if (layout['category_nav'] != null &&
          MenuCategoryNavSlotX.tryParse(
                  layout['category_nav']?.toString()) ==
              null) {
        return 'شكل شريط التصنيفات غير صالح';
      }
      if (layout['brand_logo_align'] != null &&
          MenuBrandLogoAlignX.tryParse(
                  layout['brand_logo_align']?.toString()) ==
              null) {
        return 'موقع شعار المطعم غير صالح';
      }
      if (layout['brand_text_placement'] != null &&
          MenuBrandTextPlacementX.tryParse(
                  layout['brand_text_placement']?.toString()) ==
              null) {
        return 'موضع اسم المطعم غير صالح';
      }
      if (layout['brand_text_align'] != null &&
          MenuBrandTextAlignX.tryParse(
                  layout['brand_text_align']?.toString()) ==
              null) {
        return 'محاذاة نص الهوية غير صالحة';
      }
    }

    if (json.containsKey('layout_direction')) {
      return 'اتجاه التخطيط مشتق من اللغة ولا يُخزَّن';
    }

    return null;
  }

  static String? validateJsonString(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return 'الثيم يجب أن يكون كائناً JSON';
      }
      return validate(decoded);
    } catch (_) {
      return 'JSON غير صالح';
    }
  }
}
