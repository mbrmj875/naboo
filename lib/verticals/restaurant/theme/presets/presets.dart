/// كتالوج نماذج المنيو الجاهزة — مستوحاة من أطقم Figma Community للمنيو الرقمي عبر QR.
/// المفاتيح ثابتة في JSON؛ التوسعة بإضافة قيمة enum + صف في [kRestaurantPresets].
library;

enum RestaurantPresetKey {
  classic,
  modern,
  dark,
  cafe,
  elegant,
  minimal,
  royal,
  garden,
  ocean,
  bazaar,
  thaiQr,
  foodOrder,
  steakhouse,
  sushiBar,
  pizzeria,
  bakery,
  juiceBar,
  fineDining,
  streetFood,
  veganGreen,
  dessertPastel,
  smokeBbq,
  mediterranean,
  lacquerRed,
  pastaHouse,
  brunchAir,
  nightMarket,
  mezzeTable,
  dockSeafood,
  neonNight,
}

extension RestaurantPresetKeyX on RestaurantPresetKey {
  String get key => name;

  String get labelAr => kRestaurantPresets[this]!.labelAr;

  String get blurbAr => kRestaurantPresets[this]!.blurbAr;

  static RestaurantPresetKey? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final k in RestaurantPresetKey.values) {
      if (k.name == raw) return k;
    }
    return null;
  }
}

enum RestaurantFontFamily {
  tajawal,
  cairo,
  ibmplexArabic,
  amiri,
  almarai,
  rubik,
}

extension RestaurantFontFamilyX on RestaurantFontFamily {
  String get key {
    switch (this) {
      case RestaurantFontFamily.tajawal:
        return 'tajawal';
      case RestaurantFontFamily.cairo:
        return 'cairo';
      case RestaurantFontFamily.ibmplexArabic:
        return 'ibmplex_arabic';
      case RestaurantFontFamily.amiri:
        return 'amiri';
      case RestaurantFontFamily.almarai:
        return 'almarai';
      case RestaurantFontFamily.rubik:
        return 'rubik';
    }
  }

  String get flutterFamily {
    switch (this) {
      case RestaurantFontFamily.tajawal:
        return 'Tajawal';
      case RestaurantFontFamily.cairo:
        return 'Cairo';
      case RestaurantFontFamily.ibmplexArabic:
        return 'IBMPlexSansArabic';
      case RestaurantFontFamily.amiri:
        return 'Amiri';
      case RestaurantFontFamily.almarai:
        return 'Almarai';
      case RestaurantFontFamily.rubik:
        return 'Rubik';
    }
  }

  String get labelAr {
    switch (this) {
      case RestaurantFontFamily.tajawal:
        return 'تجوّال';
      case RestaurantFontFamily.cairo:
        return 'القاهرة';
      case RestaurantFontFamily.ibmplexArabic:
        return 'IBM بليكس عربي';
      case RestaurantFontFamily.amiri:
        return 'أميري';
      case RestaurantFontFamily.almarai:
        return 'المراعي';
      case RestaurantFontFamily.rubik:
        return 'روبيك';
    }
  }

  static RestaurantFontFamily? tryParse(String? raw) {
    switch (raw) {
      case 'tajawal':
        return RestaurantFontFamily.tajawal;
      case 'cairo':
        return RestaurantFontFamily.cairo;
      case 'ibmplex_arabic':
        return RestaurantFontFamily.ibmplexArabic;
      case 'amiri':
        return RestaurantFontFamily.amiri;
      case 'almarai':
        return RestaurantFontFamily.almarai;
      case 'rubik':
        return RestaurantFontFamily.rubik;
      default:
        return null;
    }
  }
}

enum RestaurantMenuLanguage { ar, en, bilingual }

extension RestaurantMenuLanguageX on RestaurantMenuLanguage {
  String get key {
    switch (this) {
      case RestaurantMenuLanguage.ar:
        return 'ar';
      case RestaurantMenuLanguage.en:
        return 'en';
      case RestaurantMenuLanguage.bilingual:
        return 'bilingual';
    }
  }

  String get layoutDirection {
    switch (this) {
      case RestaurantMenuLanguage.en:
        return 'ltr';
      case RestaurantMenuLanguage.ar:
      case RestaurantMenuLanguage.bilingual:
        return 'rtl';
    }
  }

  static RestaurantMenuLanguage? tryParse(String? raw) {
    switch (raw) {
      case 'ar':
        return RestaurantMenuLanguage.ar;
      case 'en':
        return RestaurantMenuLanguage.en;
      case 'bilingual':
        return RestaurantMenuLanguage.bilingual;
      default:
        return null;
    }
  }
}

enum RestaurantItemLayout { list, grid, magazine }

extension RestaurantItemLayoutX on RestaurantItemLayout {
  String get key {
    switch (this) {
      case RestaurantItemLayout.list:
        return 'list';
      case RestaurantItemLayout.grid:
        return 'grid';
      case RestaurantItemLayout.magazine:
        return 'magazine';
    }
  }

  String get labelAr {
    switch (this) {
      case RestaurantItemLayout.list:
        return 'قائمة';
      case RestaurantItemLayout.grid:
        return 'شبكة';
      case RestaurantItemLayout.magazine:
        return 'مجلّة';
    }
  }

  static RestaurantItemLayout? tryParse(String? raw) {
    switch (raw) {
      case 'list':
        return RestaurantItemLayout.list;
      case 'grid':
        return RestaurantItemLayout.grid;
      case 'magazine':
        return RestaurantItemLayout.magazine;
      default:
        return null;
    }
  }
}

enum RestaurantWelcomeMode { none, cover, logoSplash }

extension RestaurantWelcomeModeX on RestaurantWelcomeMode {
  String get key {
    switch (this) {
      case RestaurantWelcomeMode.none:
        return 'none';
      case RestaurantWelcomeMode.cover:
        return 'cover';
      case RestaurantWelcomeMode.logoSplash:
        return 'logo_splash';
    }
  }

  String get labelAr {
    switch (this) {
      case RestaurantWelcomeMode.none:
        return 'بدون ترحيب';
      case RestaurantWelcomeMode.cover:
        return 'صورة ترحيبية';
      case RestaurantWelcomeMode.logoSplash:
        return 'شعار قبل الدخول';
    }
  }

  static RestaurantWelcomeMode? tryParse(String? raw) {
    switch (raw) {
      case 'none':
        return RestaurantWelcomeMode.none;
      case 'cover':
        return RestaurantWelcomeMode.cover;
      case 'logo_splash':
        return RestaurantWelcomeMode.logoSplash;
      default:
        return null;
    }
  }
}

/// طابع بصري للنموذج — يحدد هيكل العرض أكثر من مجرد الألوان.
enum RestaurantMenuChrome {
  /// صور عريضة فوق كل طبق (Thai / magazine QR).
  photoStack,
  /// تحريري: عنوان مركزي + خطوط رفيعة.
  editorial,
  /// شبكة تطبيق طلب.
  appGrid,
  /// صفوف صورة صغيرة على ورق.
  paperList,
  /// غلاف بطل كبير ثم قائمة مدمجة.
  heroCover,
  /// بطاقات قصة طولية (صورة عمودية).
  storyCards,
  /// بلاطات كثيفة صغيرة.
  compactTiles,
  /// شريط تصنيفات جانبي + قائمة.
  sideRail,
  /// بطاقات ظل خفيفة مرتفعة.
  softCards,
  /// عمودان تحريريّان (مجلّة).
  magazine,
  /// شريط تصنيف فوق قائمة كثيفة.
  bannerMenu,
  /// صف أفقي: صورة + نص + سعر.
  splitRow,
  /// غلاف ثم قائمة ورقية.
  coverThenList,
  /// لوحة قائمة نصّية كثيفة.
  menuBoard,
}

extension RestaurantMenuChromeX on RestaurantMenuChrome {
  String get cssKey {
    switch (this) {
      case RestaurantMenuChrome.photoStack:
        return 'photo-stack';
      case RestaurantMenuChrome.editorial:
        return 'editorial';
      case RestaurantMenuChrome.appGrid:
        return 'app-grid';
      case RestaurantMenuChrome.paperList:
        return 'paper-list';
      case RestaurantMenuChrome.heroCover:
        return 'hero-cover';
      case RestaurantMenuChrome.storyCards:
        return 'story-cards';
      case RestaurantMenuChrome.compactTiles:
        return 'compact-tiles';
      case RestaurantMenuChrome.sideRail:
        return 'side-rail';
      case RestaurantMenuChrome.softCards:
        return 'soft-cards';
      case RestaurantMenuChrome.magazine:
        return 'magazine';
      case RestaurantMenuChrome.bannerMenu:
        return 'banner-menu';
      case RestaurantMenuChrome.splitRow:
        return 'split-row';
      case RestaurantMenuChrome.coverThenList:
        return 'cover-then-list';
      case RestaurantMenuChrome.menuBoard:
        return 'menu-board';
    }
  }
}

class RestaurantArchitecturePreset {
  const RestaurantArchitecturePreset({
    required this.key,
    required this.labelAr,
    required this.blurbAr,
    required this.displaySize,
    required this.bodySize,
    required this.cardRadius,
    required this.imageRatioW,
    required this.imageRatioH,
    required this.categoryNav,
    required this.headerComposition,
    required this.priceTreatment,
    required this.elevation,
    required this.density,
    required this.buttonShape,
    required this.defaultColors,
    required this.chrome,
    this.defaultItemLayout = RestaurantItemLayout.list,
    this.defaultFont = RestaurantFontFamily.tajawal,
  });

  final RestaurantPresetKey key;
  final String labelAr;
  final String blurbAr;
  final double displaySize;
  final double bodySize;
  final double cardRadius;
  final int imageRatioW;
  final int imageRatioH;
  final String categoryNav;
  final String headerComposition;
  final String priceTreatment;
  final String elevation;
  final String density;
  final String buttonShape;
  final Map<String, String> defaultColors;
  final RestaurantItemLayout defaultItemLayout;
  final RestaurantMenuChrome chrome;
  final RestaurantFontFamily defaultFont;
}

const kRestaurantPresets = <RestaurantPresetKey, RestaurantArchitecturePreset>{
  RestaurantPresetKey.classic: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.classic,
    labelAr: 'ورقي تايلندي',
    blurbAr: 'صور كبيرة على ورق كريمي',
    displaySize: 32,
    bodySize: 15,
    cardRadius: 4,
    imageRatioW: 4,
    imageRatioH: 3,
    categoryNav: 'top_text_tabs',
    headerComposition: 'logo_center_tagline',
    priceTreatment: 'bold_inline',
    elevation: 'flat',
    density: 'airy',
    buttonShape: 'rounded',
    chrome: RestaurantMenuChrome.photoStack,
    defaultColors: {
      'primary': '#5C3A21',
      'accent': '#C45C26',
      'bg': '#F7F0E6',
      'text': '#2A1F18',
    },
    defaultItemLayout: RestaurantItemLayout.magazine,
    defaultFont: RestaurantFontFamily.amiri,
  ),
  RestaurantPresetKey.modern: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.modern,
    labelAr: 'تطبيق طلب',
    blurbAr: 'شبكة بطاقات كتطبيق توصيل',
    displaySize: 28,
    bodySize: 15,
    cardRadius: 18,
    imageRatioW: 1,
    imageRatioH: 1,
    categoryNav: 'floating_pills',
    headerComposition: 'cover_full_logo_float',
    priceTreatment: 'pill_outline',
    elevation: 'soft',
    density: 'compact',
    buttonShape: 'pill',
    chrome: RestaurantMenuChrome.appGrid,
    defaultColors: {
      'primary': '#E85D04',
      'accent': '#F48C06',
      'bg': '#FAFAFA',
      'text': '#1A1A1A',
    },
    defaultItemLayout: RestaurantItemLayout.grid,
  ),
  RestaurantPresetKey.dark: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.dark,
    labelAr: 'ليلي تحريري',
    blurbAr: 'قائمة بخطوط ذهبية رفيعة',
    displaySize: 30,
    bodySize: 15,
    cardRadius: 0,
    imageRatioW: 4,
    imageRatioH: 3,
    categoryNav: 'top_text_tabs',
    headerComposition: 'text_centered',
    priceTreatment: 'large_accent',
    elevation: 'flat',
    density: 'very_airy',
    buttonShape: 'square',
    chrome: RestaurantMenuChrome.editorial,
    defaultColors: {
      'primary': '#B8960C',
      'accent': '#D4AF37',
      'bg': '#0B1220',
      'text': '#F5F0E8',
    },
    defaultFont: RestaurantFontFamily.amiri,
  ),
  RestaurantPresetKey.cafe: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.cafe,
    labelAr: 'كافيه دافئ',
    blurbAr: 'صفوف قهوة على ورق دافئ',
    displaySize: 30,
    bodySize: 16,
    cardRadius: 20,
    imageRatioW: 1,
    imageRatioH: 1,
    categoryNav: 'top_pills',
    headerComposition: 'hero_coffee_tagline',
    priceTreatment: 'rounded_badge',
    elevation: 'soft',
    density: 'airy',
    buttonShape: 'pill',
    chrome: RestaurantMenuChrome.paperList,
    defaultColors: {
      'primary': '#6F4E37',
      'accent': '#C4A484',
      'bg': '#FBF6F0',
      'text': '#3E2723',
    },
  ),
  RestaurantPresetKey.elegant: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.elegant,
    labelAr: 'مجلس فاخر',
    blurbAr: 'كلمة المركز وقواعد ذهبية',
    displaySize: 36,
    bodySize: 15,
    cardRadius: 0,
    imageRatioW: 3,
    imageRatioH: 4,
    categoryNav: 'dropdown_hidden',
    headerComposition: 'text_centered',
    priceTreatment: 'serif_large',
    elevation: 'flat',
    density: 'very_airy',
    buttonShape: 'square',
    chrome: RestaurantMenuChrome.magazine,
    defaultColors: {
      'primary': '#B8960C',
      'accent': '#E8C547',
      'bg': '#12100E',
      'text': '#F8F4EC',
    },
    defaultFont: RestaurantFontFamily.amiri,
  ),
  RestaurantPresetKey.minimal: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.minimal,
    labelAr: 'أبيض نظيف',
    blurbAr: 'نص صافٍ بلا زخرفة',
    displaySize: 24,
    bodySize: 14,
    cardRadius: 0,
    imageRatioW: 1,
    imageRatioH: 1,
    categoryNav: 'top_text_tabs',
    headerComposition: 'text_only',
    priceTreatment: 'plain_inline',
    elevation: 'none',
    density: 'compact',
    buttonShape: 'square',
    chrome: RestaurantMenuChrome.splitRow,
    defaultColors: {
      'primary': '#111827',
      'accent': '#111827',
      'bg': '#FFFFFF',
      'text': '#111827',
    },
  ),
  RestaurantPresetKey.royal: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.royal,
    labelAr: 'ملكي نابو',
    blurbAr: 'فحمي وكهرمان نابو',
    displaySize: 34,
    bodySize: 15,
    cardRadius: 0,
    imageRatioW: 4,
    imageRatioH: 3,
    categoryNav: 'top_text_tabs',
    headerComposition: 'text_centered',
    priceTreatment: 'large_accent',
    elevation: 'flat',
    density: 'very_airy',
    buttonShape: 'square',
    chrome: RestaurantMenuChrome.menuBoard,
    defaultColors: {
      'primary': '#B8960C',
      'accent': '#E8C547',
      'bg': '#0F172A',
      'text': '#F8FAFC',
    },
  ),
  RestaurantPresetKey.garden: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.garden,
    labelAr: 'حديقة طازجة',
    blurbAr: 'شبكة خضراء منعشة',
    displaySize: 30,
    bodySize: 15,
    cardRadius: 16,
    imageRatioW: 1,
    imageRatioH: 1,
    categoryNav: 'floating_pills',
    headerComposition: 'logo_center_tagline',
    priceTreatment: 'rounded_badge',
    elevation: 'soft',
    density: 'airy',
    buttonShape: 'pill',
    chrome: RestaurantMenuChrome.softCards,
    defaultColors: {
      'primary': '#166534',
      'accent': '#4ADE80',
      'bg': '#F3FBF5',
      'text': '#14532D',
    },
    defaultItemLayout: RestaurantItemLayout.grid,
  ),
  RestaurantPresetKey.ocean: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.ocean,
    labelAr: 'مأكولات بحرية',
    blurbAr: 'صور عريضة بدرجات فيروز',
    displaySize: 30,
    bodySize: 15,
    cardRadius: 12,
    imageRatioW: 4,
    imageRatioH: 3,
    categoryNav: 'top_segmented',
    headerComposition: 'cover_full_logo_float',
    priceTreatment: 'pill_outline',
    elevation: 'soft',
    density: 'compact',
    buttonShape: 'pill',
    chrome: RestaurantMenuChrome.sideRail,
    defaultColors: {
      'primary': '#0E7490',
      'accent': '#22D3EE',
      'bg': '#F0F9FF',
      'text': '#0C4A6E',
    },
    defaultItemLayout: RestaurantItemLayout.magazine,
  ),
  RestaurantPresetKey.bazaar: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.bazaar,
    labelAr: 'سوق محلي',
    blurbAr: 'صور عريضة بطابع شعبي',
    displaySize: 32,
    bodySize: 15,
    cardRadius: 8,
    imageRatioW: 3,
    imageRatioH: 4,
    categoryNav: 'top_text_tabs',
    headerComposition: 'hero_coffee_tagline',
    priceTreatment: 'bold_inline',
    elevation: 'flat',
    density: 'airy',
    buttonShape: 'rounded',
    chrome: RestaurantMenuChrome.bannerMenu,
    defaultColors: {
      'primary': '#9A3412',
      'accent': '#EA580C',
      'bg': '#FFF4E8',
      'text': '#431407',
    },
    defaultItemLayout: RestaurantItemLayout.magazine,
  ),
  RestaurantPresetKey.thaiQr: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.thaiQr,
    labelAr: 'QR تايلندي',
    blurbAr: 'غلاف بطل ثم أطباق مصوّرة',
    displaySize: 28,
    bodySize: 14,
    cardRadius: 6,
    imageRatioW: 16,
    imageRatioH: 9,
    categoryNav: 'top_text_tabs',
    headerComposition: 'cover_full_logo_float',
    priceTreatment: 'bold_inline',
    elevation: 'flat',
    density: 'airy',
    buttonShape: 'rounded',
    chrome: RestaurantMenuChrome.heroCover,
    defaultColors: {
      'primary': '#7C2D12',
      'accent': '#C2410C',
      'bg': '#FFF8F5',
      'text': '#1E1B18',
    },
    defaultItemLayout: RestaurantItemLayout.magazine,
    defaultFont: RestaurantFontFamily.cairo,
  ),
  RestaurantPresetKey.foodOrder: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.foodOrder,
    labelAr: 'طلب سريع',
    blurbAr: 'بلاطات كثيفة كتطبيق توصيل',
    displaySize: 26,
    bodySize: 13,
    cardRadius: 14,
    imageRatioW: 1,
    imageRatioH: 1,
    categoryNav: 'floating_pills',
    headerComposition: 'cover_full_logo_float',
    priceTreatment: 'pill_outline',
    elevation: 'soft',
    density: 'compact',
    buttonShape: 'pill',
    chrome: RestaurantMenuChrome.compactTiles,
    defaultColors: {
      'primary': '#DC2626',
      'accent': '#F97316',
      'bg': '#FFFFFF',
      'text': '#0F172A',
    },
    defaultItemLayout: RestaurantItemLayout.grid,
    defaultFont: RestaurantFontFamily.rubik,
  ),
  RestaurantPresetKey.steakhouse: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.steakhouse,
    labelAr: 'ستيك هاوس',
    blurbAr: 'جلد بني وتحرير فاخر',
    displaySize: 34,
    bodySize: 15,
    cardRadius: 0,
    imageRatioW: 4,
    imageRatioH: 3,
    categoryNav: 'top_text_tabs',
    headerComposition: 'text_centered',
    priceTreatment: 'serif_large',
    elevation: 'flat',
    density: 'very_airy',
    buttonShape: 'square',
    chrome: RestaurantMenuChrome.coverThenList,
    defaultColors: {
      'primary': '#A16207',
      'accent': '#D97706',
      'bg': '#1C1410',
      'text': '#F5E6D3',
    },
    defaultFont: RestaurantFontFamily.amiri,
  ),
  RestaurantPresetKey.sushiBar: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.sushiBar,
    labelAr: 'سوشي بار',
    blurbAr: 'أبيض أسود ياباني صارم',
    displaySize: 26,
    bodySize: 14,
    cardRadius: 0,
    imageRatioW: 1,
    imageRatioH: 1,
    categoryNav: 'top_text_tabs',
    headerComposition: 'text_only',
    priceTreatment: 'plain_inline',
    elevation: 'none',
    density: 'compact',
    buttonShape: 'square',
    chrome: RestaurantMenuChrome.paperList,
    defaultColors: {
      'primary': '#0A0A0A',
      'accent': '#DC2626',
      'bg': '#FAFAFA',
      'text': '#171717',
    },
    defaultFont: RestaurantFontFamily.ibmplexArabic,
  ),
  RestaurantPresetKey.pizzeria: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.pizzeria,
    labelAr: 'بيتزا',
    blurbAr: 'شبكة حمراء دافئة للطلب',
    displaySize: 28,
    bodySize: 15,
    cardRadius: 16,
    imageRatioW: 1,
    imageRatioH: 1,
    categoryNav: 'floating_pills',
    headerComposition: 'cover_full_logo_float',
    priceTreatment: 'rounded_badge',
    elevation: 'soft',
    density: 'compact',
    buttonShape: 'pill',
    chrome: RestaurantMenuChrome.softCards,
    defaultColors: {
      'primary': '#B91C1C',
      'accent': '#EF4444',
      'bg': '#FFF7ED',
      'text': '#7F1D1D',
    },
    defaultItemLayout: RestaurantItemLayout.grid,
  ),
  RestaurantPresetKey.bakery: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.bakery,
    labelAr: 'مخبز حلويات',
    blurbAr: 'وردي كريمي وصفوف ناعمة',
    displaySize: 28,
    bodySize: 15,
    cardRadius: 18,
    imageRatioW: 1,
    imageRatioH: 1,
    categoryNav: 'top_pills',
    headerComposition: 'logo_center_tagline',
    priceTreatment: 'rounded_badge',
    elevation: 'soft',
    density: 'airy',
    buttonShape: 'pill',
    chrome: RestaurantMenuChrome.coverThenList,
    defaultColors: {
      'primary': '#9F1239',
      'accent': '#FB7185',
      'bg': '#FFF1F2',
      'text': '#4C0519',
    },
    defaultFont: RestaurantFontFamily.almarai,
  ),
  RestaurantPresetKey.juiceBar: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.juiceBar,
    labelAr: 'عصائر طازجة',
    blurbAr: 'شبكة حمضيات مشرقة',
    displaySize: 28,
    bodySize: 14,
    cardRadius: 20,
    imageRatioW: 1,
    imageRatioH: 1,
    categoryNav: 'floating_pills',
    headerComposition: 'logo_center_tagline',
    priceTreatment: 'pill_outline',
    elevation: 'soft',
    density: 'compact',
    buttonShape: 'pill',
    chrome: RestaurantMenuChrome.bannerMenu,
    defaultColors: {
      'primary': '#CA8A04',
      'accent': '#FACC15',
      'bg': '#FEFCE8',
      'text': '#422006',
    },
    defaultItemLayout: RestaurantItemLayout.grid,
  ),
  RestaurantPresetKey.fineDining: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.fineDining,
    labelAr: 'تذوق فاخر',
    blurbAr: 'أسود وذهب — قائمة تذوق',
    displaySize: 38,
    bodySize: 14,
    cardRadius: 0,
    imageRatioW: 3,
    imageRatioH: 4,
    categoryNav: 'dropdown_hidden',
    headerComposition: 'text_centered',
    priceTreatment: 'serif_large',
    elevation: 'flat',
    density: 'very_airy',
    buttonShape: 'square',
    chrome: RestaurantMenuChrome.menuBoard,
    defaultColors: {
      'primary': '#D4AF37',
      'accent': '#F5E6A3',
      'bg': '#0A0A0A',
      'text': '#F5F5F4',
    },
    defaultFont: RestaurantFontFamily.amiri,
  ),
  RestaurantPresetKey.streetFood: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.streetFood,
    labelAr: 'أكل شارع',
    blurbAr: 'صور جريئة وتراكوتا',
    displaySize: 30,
    bodySize: 15,
    cardRadius: 8,
    imageRatioW: 4,
    imageRatioH: 3,
    categoryNav: 'top_segmented',
    headerComposition: 'cover_full_logo_float',
    priceTreatment: 'bold_inline',
    elevation: 'flat',
    density: 'airy',
    buttonShape: 'rounded',
    chrome: RestaurantMenuChrome.splitRow,
    defaultColors: {
      'primary': '#EA580C',
      'accent': '#FDBA74',
      'bg': '#1C1917',
      'text': '#FFF7ED',
    },
    defaultItemLayout: RestaurantItemLayout.magazine,
  ),
  RestaurantPresetKey.veganGreen: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.veganGreen,
    labelAr: 'نباتي أخضر',
    blurbAr: 'بطاقات قصة خضراء هادئة',
    displaySize: 30,
    bodySize: 15,
    cardRadius: 12,
    imageRatioW: 3,
    imageRatioH: 4,
    categoryNav: 'top_pills',
    headerComposition: 'logo_center_tagline',
    priceTreatment: 'rounded_badge',
    elevation: 'soft',
    density: 'airy',
    buttonShape: 'pill',
    chrome: RestaurantMenuChrome.storyCards,
    defaultColors: {
      'primary': '#3F6212',
      'accent': '#84CC16',
      'bg': '#F7FEE7',
      'text': '#1A2E05',
    },
    defaultItemLayout: RestaurantItemLayout.magazine,
  ),
  RestaurantPresetKey.dessertPastel: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.dessertPastel,
    labelAr: 'حلويات باستيل',
    blurbAr: 'شبكة وردية ناعمة',
    displaySize: 28,
    bodySize: 14,
    cardRadius: 22,
    imageRatioW: 1,
    imageRatioH: 1,
    categoryNav: 'floating_pills',
    headerComposition: 'logo_center_tagline',
    priceTreatment: 'pill_outline',
    elevation: 'soft',
    density: 'airy',
    buttonShape: 'pill',
    chrome: RestaurantMenuChrome.softCards,
    defaultColors: {
      'primary': '#DB2777',
      'accent': '#F9A8D4',
      'bg': '#FDF2F8',
      'text': '#831843',
    },
    defaultItemLayout: RestaurantItemLayout.grid,
    defaultFont: RestaurantFontFamily.almarai,
  ),
  RestaurantPresetKey.smokeBbq: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.smokeBbq,
    labelAr: 'مشاوي دخان',
    blurbAr: 'فحمي مدخّن وصور عريضة',
    displaySize: 32,
    bodySize: 15,
    cardRadius: 6,
    imageRatioW: 16,
    imageRatioH: 9,
    categoryNav: 'top_segmented',
    headerComposition: 'cover_dark_large_logo',
    priceTreatment: 'large_accent',
    elevation: 'flat',
    density: 'airy',
    buttonShape: 'rounded',
    chrome: RestaurantMenuChrome.heroCover,
    defaultColors: {
      'primary': '#F59E0B',
      'accent': '#FBBF24',
      'bg': '#171412',
      'text': '#FAFAF9',
    },
  ),
  RestaurantPresetKey.mediterranean: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.mediterranean,
    labelAr: 'متوسطي',
    blurbAr: 'زيتون وأزور على ورق',
    displaySize: 30,
    bodySize: 15,
    cardRadius: 10,
    imageRatioW: 4,
    imageRatioH: 3,
    categoryNav: 'top_text_tabs',
    headerComposition: 'logo_center_tagline',
    priceTreatment: 'bold_inline',
    elevation: 'flat',
    density: 'airy',
    buttonShape: 'rounded',
    chrome: RestaurantMenuChrome.sideRail,
    defaultColors: {
      'primary': '#3F6212',
      'accent': '#0E7490',
      'bg': '#F8FAF5',
      'text': '#1C1917',
    },
    defaultFont: RestaurantFontFamily.cairo,
  ),
  RestaurantPresetKey.lacquerRed: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.lacquerRed,
    labelAr: 'لاكيه أحمر',
    blurbAr: 'أحمر لامع وتحرير ليلي',
    displaySize: 32,
    bodySize: 15,
    cardRadius: 0,
    imageRatioW: 4,
    imageRatioH: 3,
    categoryNav: 'top_text_tabs',
    headerComposition: 'text_centered',
    priceTreatment: 'large_accent',
    elevation: 'flat',
    density: 'very_airy',
    buttonShape: 'square',
    chrome: RestaurantMenuChrome.magazine,
    defaultColors: {
      'primary': '#EF4444',
      'accent': '#FCA5A5',
      'bg': '#1A0505',
      'text': '#FEF2F2',
    },
  ),
  RestaurantPresetKey.pastaHouse: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.pastaHouse,
    labelAr: 'بيت الباستا',
    blurbAr: 'كريمي وطماطم إيطالي',
    displaySize: 30,
    bodySize: 15,
    cardRadius: 8,
    imageRatioW: 4,
    imageRatioH: 3,
    categoryNav: 'top_pills',
    headerComposition: 'hero_coffee_tagline',
    priceTreatment: 'bold_inline',
    elevation: 'flat',
    density: 'airy',
    buttonShape: 'rounded',
    chrome: RestaurantMenuChrome.photoStack,
    defaultColors: {
      'primary': '#9A3412',
      'accent': '#DC2626',
      'bg': '#FFFBEB',
      'text': '#292524',
    },
    defaultItemLayout: RestaurantItemLayout.magazine,
  ),
  RestaurantPresetKey.brunchAir: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.brunchAir,
    labelAr: 'برانش هوائي',
    blurbAr: 'بطاقات قصة فاتحة ومتباعدة',
    displaySize: 28,
    bodySize: 15,
    cardRadius: 16,
    imageRatioW: 3,
    imageRatioH: 4,
    categoryNav: 'floating_pills',
    headerComposition: 'logo_center_tagline',
    priceTreatment: 'pill_outline',
    elevation: 'soft',
    density: 'very_airy',
    buttonShape: 'pill',
    chrome: RestaurantMenuChrome.storyCards,
    defaultColors: {
      'primary': '#0369A1',
      'accent': '#38BDF8',
      'bg': '#F8FAFC',
      'text': '#0F172A',
    },
    defaultItemLayout: RestaurantItemLayout.magazine,
  ),
  RestaurantPresetKey.nightMarket: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.nightMarket,
    labelAr: 'سوق ليلي',
    blurbAr: 'نيون وصور عريضة ليلية',
    displaySize: 30,
    bodySize: 14,
    cardRadius: 10,
    imageRatioW: 16,
    imageRatioH: 9,
    categoryNav: 'top_segmented',
    headerComposition: 'cover_dark_large_logo',
    priceTreatment: 'large_accent',
    elevation: 'crisp',
    density: 'compact',
    buttonShape: 'rounded',
    chrome: RestaurantMenuChrome.bannerMenu,
    defaultColors: {
      'primary': '#22D3EE',
      'accent': '#F59E0B',
      'bg': '#0B1020',
      'text': '#E0F2FE',
    },
  ),
  RestaurantPresetKey.mezzeTable: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.mezzeTable,
    labelAr: 'مازة شامية',
    blurbAr: 'تحرير دافئ بطابع مائدة',
    displaySize: 32,
    bodySize: 15,
    cardRadius: 0,
    imageRatioW: 4,
    imageRatioH: 3,
    categoryNav: 'top_text_tabs',
    headerComposition: 'text_centered',
    priceTreatment: 'serif_large',
    elevation: 'flat',
    density: 'very_airy',
    buttonShape: 'square',
    chrome: RestaurantMenuChrome.menuBoard,
    defaultColors: {
      'primary': '#B45309',
      'accent': '#F59E0B',
      'bg': '#1C1410',
      'text': '#FEF3C7',
    },
    defaultFont: RestaurantFontFamily.amiri,
  ),
  RestaurantPresetKey.dockSeafood: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.dockSeafood,
    labelAr: 'رصيف بحري',
    blurbAr: 'صفوف زرقاء هادئة',
    displaySize: 28,
    bodySize: 15,
    cardRadius: 12,
    imageRatioW: 1,
    imageRatioH: 1,
    categoryNav: 'top_pills',
    headerComposition: 'logo_center_tagline',
    priceTreatment: 'rounded_badge',
    elevation: 'soft',
    density: 'airy',
    buttonShape: 'pill',
    chrome: RestaurantMenuChrome.paperList,
    defaultColors: {
      'primary': '#1E3A5F',
      'accent': '#38BDF8',
      'bg': '#EFF6FF',
      'text': '#0C4A6E',
    },
  ),
  RestaurantPresetKey.neonNight: RestaurantArchitecturePreset(
    key: RestaurantPresetKey.neonNight,
    labelAr: 'نيون ليلي',
    blurbAr: 'بلاطات داكنة بإضاءة نيون',
    displaySize: 26,
    bodySize: 13,
    cardRadius: 12,
    imageRatioW: 1,
    imageRatioH: 1,
    categoryNav: 'floating_pills',
    headerComposition: 'cover_dark_large_logo',
    priceTreatment: 'pill_outline',
    elevation: 'crisp',
    density: 'compact',
    buttonShape: 'pill',
    chrome: RestaurantMenuChrome.compactTiles,
    defaultColors: {
      'primary': '#22D3EE',
      'accent': '#F472B6',
      'bg': '#020617',
      'text': '#F8FAFC',
    },
    defaultItemLayout: RestaurantItemLayout.grid,
    defaultFont: RestaurantFontFamily.rubik,
  ),
};

/// لوحة ألوان احترافية للمنيو — مجموعات حسب العائلة اللونية.
class RestaurantColorGroup {
  const RestaurantColorGroup(this.labelAr, this.hexes);
  final String labelAr;
  final List<String> hexes;
}

const kRestaurantColorGroups = <RestaurantColorGroup>[
  RestaurantColorGroup('كحلي وفحمي', [
    '#051424',
    '#0B1220',
    '#0F172A',
    '#111827',
    '#1E293B',
    '#1A2A3A',
    '#334155',
    '#475569',
  ]),
  RestaurantColorGroup('ذهب وكهرمان', [
    '#B8960C',
    '#D4AF37',
    '#E8C547',
    '#F59E0B',
    '#EAB308',
    '#CA8A04',
    '#A16207',
    '#854D0E',
  ]),
  RestaurantColorGroup('ترابي وتراكوتا', [
    '#C45C26',
    '#B45309',
    '#D97706',
    '#EA580C',
    '#9A3412',
    '#7C2D12',
    '#78350F',
    '#5C3A21',
  ]),
  RestaurantColorGroup('أحمر ونبيذي', [
    '#7F1D1D',
    '#991B1B',
    '#B91C1C',
    '#DC2626',
    '#EF4444',
    '#9F1239',
    '#BE123C',
    '#881337',
  ]),
  RestaurantColorGroup('أخضر طبيعي', [
    '#14532D',
    '#166534',
    '#15803D',
    '#16A34A',
    '#22C55E',
    '#4ADE80',
    '#3F6212',
    '#65A30D',
  ]),
  RestaurantColorGroup('أزرق ومحيط', [
    '#0C4A6E',
    '#0E7490',
    '#0891B2',
    '#06B6D4',
    '#22D3EE',
    '#1E3A5F',
    '#1D4ED8',
    '#2563EB',
  ]),
  RestaurantColorGroup('بني وقهوة', [
    '#1C1917',
    '#292524',
    '#44403C',
    '#57534E',
    '#6F4E37',
    '#3E2723',
    '#431407',
    '#2A1F18',
  ]),
  RestaurantColorGroup('كريمي وورق', [
    '#FFFFFF',
    '#FFFBFF',
    '#FFF8F5',
    '#F7F0E6',
    '#FFFAF5',
    '#FFF7ED',
    '#FFFBEB',
    '#FBF6F0',
    '#FFF4E8',
    '#FEF3C7',
    '#F5F5F4',
    '#F8FAFC',
  ]),
  RestaurantColorGroup('باستيل هادئ', [
    '#F0FDF4',
    '#ECFEFF',
    '#EFF6FF',
    '#FEF2F2',
    '#FFF1F2',
    '#FDF4FF',
    '#F5F3FF',
    '#EEF2FF',
    '#E8DCCB',
    '#E9E1DC',
    '#F1F5F9',
    '#FEE2E2',
  ]),
  RestaurantColorGroup('رمادي محايد', [
    '#0A0A0A',
    '#171717',
    '#262626',
    '#404040',
    '#525252',
    '#737373',
    '#A3A3A3',
    '#D4D4D4',
    '#E5E5E5',
    '#F5F5F5',
    '#64748B',
    '#94A3B8',
  ]),
];

const kRestaurantColorSwatches = <String>[
  '#0F172A',
  '#111827',
  '#1F2937',
  '#334155',
  '#B8960C',
  '#E8C547',
  '#F59E0B',
  '#B45309',
  '#D97706',
  '#EA580C',
  '#9A3412',
  '#7F1D1D',
  '#EF4444',
  '#166534',
  '#22C55E',
  '#14532D',
  '#0E7490',
  '#06B6D4',
  '#164E63',
  '#1E3A5F',
  '#78350F',
  '#292524',
  '#FFFFFF',
  '#FFFAF5',
  '#FFF7ED',
  '#FFFBEB',
  '#F0FDF4',
  '#ECFEFF',
  '#F8FAFC',
  '#F1F5F9',
  '#FEF3C7',
  '#FEE2E2',
  '#374151',
  '#64748B',
  '#94A3B8',
  '#C45C26',
  '#051424',
  '#D4AF37',
  '#F7F0E6',
  '#0B1220',
];
