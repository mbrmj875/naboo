/// قوالب مناطق الإعدادات المتقدمة — قوائم مغلقة فقط (enums).
library;

enum MenuHomeLayoutSlot {
  followChrome,
  appGrid,
  photoStack,
  editorial,
  paperList,
  storyCards,
  heroCover,
  compactTiles,
  sideRail,
  softCards,
  magazine,
  bannerMenu,
  splitRow,
  coverThenList,
  menuBoard,
}

extension MenuHomeLayoutSlotX on MenuHomeLayoutSlot {
  String get key => name;

  String get labelAr => switch (this) {
        MenuHomeLayoutSlot.followChrome => 'حسب النموذج',
        MenuHomeLayoutSlot.appGrid => 'شبكة تطبيق',
        MenuHomeLayoutSlot.photoStack => 'صور عريضة',
        MenuHomeLayoutSlot.editorial => 'قائمة تحريرية',
        MenuHomeLayoutSlot.paperList => 'صفوف ورقية',
        MenuHomeLayoutSlot.storyCards => 'بطاقات طولية',
        MenuHomeLayoutSlot.heroCover => 'غلاف بطل',
        MenuHomeLayoutSlot.compactTiles => 'بلاطات كثيفة',
        MenuHomeLayoutSlot.sideRail => 'شريط جانبي',
        MenuHomeLayoutSlot.softCards => 'بطاقات ظل',
        MenuHomeLayoutSlot.magazine => 'مجلّة عمودين',
        MenuHomeLayoutSlot.bannerMenu => 'شريط تصنيفات',
        MenuHomeLayoutSlot.splitRow => 'صف أفقي',
        MenuHomeLayoutSlot.coverThenList => 'غلاف ثم قائمة',
        MenuHomeLayoutSlot.menuBoard => 'لوحة قائمة',
      };

  static MenuHomeLayoutSlot? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final v in MenuHomeLayoutSlot.values) {
      if (v.name == raw) return v;
    }
    return null;
  }

  /// مفتاح `item_layout` المتوافق مع هذا القالب (يُزامَن عند الاختيار).
  /// `null` = اتبع النموذج (`architecture.defaultItemLayout`).
  String? get pairedItemLayoutKey => switch (this) {
        MenuHomeLayoutSlot.followChrome => null,
        MenuHomeLayoutSlot.appGrid ||
        MenuHomeLayoutSlot.compactTiles ||
        MenuHomeLayoutSlot.softCards =>
          'grid',
        MenuHomeLayoutSlot.magazine => 'magazine',
        MenuHomeLayoutSlot.photoStack ||
        MenuHomeLayoutSlot.editorial ||
        MenuHomeLayoutSlot.paperList ||
        MenuHomeLayoutSlot.storyCards ||
        MenuHomeLayoutSlot.heroCover ||
        MenuHomeLayoutSlot.sideRail ||
        MenuHomeLayoutSlot.bannerMenu ||
        MenuHomeLayoutSlot.splitRow ||
        MenuHomeLayoutSlot.coverThenList ||
        MenuHomeLayoutSlot.menuBoard =>
          'list',
      };
}

/// أشكال شريط البحث — مستوحاة من أنماط منصات حقيقية (Material / Apple / توصيل / تجارة).
/// المفاتيح ثابتة في JSON؛ الأسماء القديمة تُحوَّل في [tryParse].
enum MenuSearchStyleSlot {
  /// Google Material persistent search: تعبئة رمادية، زوايا كبيرة، أيقونة، بلا إطار.
  materialFill,
  /// Apple HIG search field: كبسولة نظام رمادية فاتحة + أيقونة.
  iosCapsule,
  /// Uber Eats / DoorDash / Deliveroo: حقل فاتح بإطار خفيف + أيقونة.
  deliveryBar,
  /// Amazon / متاجر: حقل بإطار + زر بحث لاحق.
  storeBar,
  /// Instagram Explore: شريط رمادي مضغوط + أيقونة.
  exploreBar,
  /// Spotify / تطبيقات ليلية: سطح داكن مرتفع + أيقونة.
  nightBar,
  /// Airbnb: كبسولة بيضاء بظل خفيف كـ«ورقة دعوة».
  guestPill,
  /// Deliveroo-style: بحث + زر فلتر مجاور.
  searchAndFilter,
  /// شريط لاصق بعرض كامل (بحث أساسي في الصفحة).
  stickyDock,
  /// قوائم تحريرية فاخرة: خط سفلي + أيقونة (Apple inline / ledger).
  editorialLine,
}

extension MenuSearchStyleSlotX on MenuSearchStyleSlot {
  String get key => name;

  String get labelAr => switch (this) {
        MenuSearchStyleSlot.materialFill => 'تعبئة ناعمة',
        MenuSearchStyleSlot.iosCapsule => 'كبسولة نظام',
        MenuSearchStyleSlot.deliveryBar => 'إطار خفيف',
        MenuSearchStyleSlot.storeBar => 'زر دائري',
        MenuSearchStyleSlot.exploreBar => 'بحث وميكروفون',
        MenuSearchStyleSlot.nightBar => 'ليلي مرتفع',
        MenuSearchStyleSlot.guestPill => 'كبسولة بظل',
        MenuSearchStyleSlot.searchAndFilter => 'تصنيف وبحث',
        MenuSearchStyleSlot.stickyDock => 'شريط كامل',
        MenuSearchStyleSlot.editorialLine => 'خط سفلي',
      };

  /// مرجع المنصة للمطورين (لا يظهر للتاجر).
  String get inspiredBy => switch (this) {
        MenuSearchStyleSlot.materialFill =>
          'Figma Search Kit: soft filled pill + icon',
        MenuSearchStyleSlot.iosCapsule =>
          'Figma Search Kit: system capsule field',
        MenuSearchStyleSlot.deliveryBar =>
          'Figma Search Kit: outlined field + icon',
        MenuSearchStyleSlot.storeBar =>
          'Figma Search Kit: field + circular blue search button',
        MenuSearchStyleSlot.exploreBar =>
          'Figma Search Kit: search icon + microphone',
        MenuSearchStyleSlot.nightBar =>
          'Figma Search Kit: dark elevated search',
        MenuSearchStyleSlot.guestPill =>
          'Figma Search Kit: elevated white pill shadow',
        MenuSearchStyleSlot.searchAndFilter =>
          'Figma Search Kit: category dropdown + search',
        MenuSearchStyleSlot.stickyDock =>
          'Figma Search Kit: full-width dock search',
        MenuSearchStyleSlot.editorialLine =>
          'Figma Search Kit: underline-only search',
      };

  static MenuSearchStyleSlot? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    // توافق المسودات القديمة (3 أنماط AI سابقة + توسعة وهمية)
    switch (raw) {
      case 'underline':
      case 'editorialLine':
      case 'sharp':
      case 'ghost':
        return MenuSearchStyleSlot.editorialLine;
      case 'pill':
      case 'deliveryBar':
      case 'accentRing':
        return MenuSearchStyleSlot.deliveryBar;
      case 'card':
      case 'softFill':
      case 'materialFill':
      case 'barBlock':
        return MenuSearchStyleSlot.materialFill;
      case 'outlined':
      case 'storeBar':
        return MenuSearchStyleSlot.storeBar;
      case 'elevated':
      case 'guestPill':
        return MenuSearchStyleSlot.guestPill;
      case 'withIcon':
      case 'exploreBar':
        return MenuSearchStyleSlot.exploreBar;
      case 'inset':
      case 'iosCapsule':
        return MenuSearchStyleSlot.iosCapsule;
      case 'nightBar':
        return MenuSearchStyleSlot.nightBar;
      case 'searchAndFilter':
        return MenuSearchStyleSlot.searchAndFilter;
      case 'stickyDock':
        return MenuSearchStyleSlot.stickyDock;
    }
    for (final v in MenuSearchStyleSlot.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

/// أشكال الشريط السفلي — مستوحاة من منصات حقيقية (Material / iOS / توصيل / تجارة).
/// المفاتيح ثابتة في JSON؛ الأسماء القديمة تُحوَّل في [tryParse].
enum MenuBottomNavSlot {
  /// Material / DoorDash: أيقونة + تسمية دائماً، تلوين نشط.
  materialLabeled,
  /// Apple HIG Tab Bar: مظهر فاتح/ضبابي خفيف + تسمية.
  iosFrost,
  /// Instagram: أيقونات فقط، أكبر، مملوءة عند التحديد.
  exploreIcons,
  /// Uber Eats: شريط صلب أوضح + تسميات.
  deliverySolid,
  /// Airbnb / تطبيقات حديثة: جزيرة عائمة بظل.
  guestIsland,
  /// Spotify: خلفية داكنة + كبسولة خلف العنصر النشط.
  nightPill,
  /// Material indicator: خط علوي على التبويب النشط.
  activeTopLine,
  /// عنصر تحكم مقطّع عائم (segmented).
  segmentCapsule,
  /// زر وسط بارز للسلة (FAB bump) — شائع في تطبيقات الطعام.
  centerBump,
  /// شريط رفيع بخط سفلي تحت النشط (editorial / commerce).
  minimalHairline,
  /// فقاعة برتقالية عائمة + حفرة بيضاء على شريط أسود (Animated Nav Figma).
  animatedBubble,
  /// شريط أسود بحفرة منحنية علوية + فقاعة برتقالية داخل الجيب (Junii Figma).
  liquidDip,
  /// شريط أزرق + كبسولة بيضاء منزلقة مع تسمية (Ideate Design Figma).
  ideatePill,
  /// شريط أخضر + أزرار دائرية (Navigation App Figma).
  greenCircleBar,
  /// قوس أخضر عائم + دوائر (Navigation App Figma).
  greenArcDock,
  /// جسر زجاجي متصل بدوائر (Modern Bottom Nav Pack).
  glassBridge,
  /// كبسولة بنفسجية موسّعة مع تسمية (Modern Bottom Nav Pack).
  glassExpandLabel,
  /// دائرة نشطة على خلفية زجاجية (Modern Bottom Nav Pack).
  glassCircleActive,
  /// قوس علوي متوهّج فوق النشط (Modern Bottom Nav Pack).
  glassArcGlow,
  /// شريط أسود بمهد منحني متحرك + دائرة برتقالية (Animated Menu Figma).
  animatedCradle,
  /// شريط داكن + أيقونة وتسمية (Beatfy / Navigation Bar variations).
  beatfyDark,
  /// شريط داكن أيقونات فقط + تمييز سماوي (Beatfy collapsed).
  beatfyIcons,
}

extension MenuBottomNavSlotX on MenuBottomNavSlot {
  String get key => name;

  String get labelAr => switch (this) {
        MenuBottomNavSlot.materialLabeled => 'مسمّى كامل',
        MenuBottomNavSlot.iosFrost => 'زجاج فاتح',
        MenuBottomNavSlot.exploreIcons => 'أيقونات ونقطة',
        MenuBottomNavSlot.deliverySolid => 'صلب داكن',
        MenuBottomNavSlot.guestIsland => 'جزيرة عائمة',
        MenuBottomNavSlot.nightPill => 'فقاعة سائلة',
        MenuBottomNavSlot.activeTopLine => 'موجة علوية',
        MenuBottomNavSlot.segmentCapsule => 'كبسولة نشطة',
        MenuBottomNavSlot.centerBump => 'زر وسط غائر',
        MenuBottomNavSlot.minimalHairline => 'خط تحت النشط',
        MenuBottomNavSlot.animatedBubble => 'فقاعة متحركة',
        MenuBottomNavSlot.liquidDip => 'جيب منحني',
        MenuBottomNavSlot.ideatePill => 'كبسولة منزلقة',
        MenuBottomNavSlot.greenCircleBar => 'دوائر خضراء',
        MenuBottomNavSlot.greenArcDock => 'قوس عائم',
        MenuBottomNavSlot.glassBridge => 'جسر زجاجي',
        MenuBottomNavSlot.glassExpandLabel => 'كبسولة موسّعة',
        MenuBottomNavSlot.glassCircleActive => 'دائرة زجاجية',
        MenuBottomNavSlot.glassArcGlow => 'قوس متوهّج',
        MenuBottomNavSlot.animatedCradle => 'مهد متحرك',
        MenuBottomNavSlot.beatfyDark => 'داكن مسمّى',
        MenuBottomNavSlot.beatfyIcons => 'داكن أيقونات',
      };

  /// مرجع المنصة للمطورين (لا يظهر للتاجر).
  String get inspiredBy => switch (this) {
        MenuBottomNavSlot.materialLabeled =>
          'Figma Simple Bottom Nav: icons + labels always',
        MenuBottomNavSlot.iosFrost =>
          'Figma glass / frosted tab bar',
        MenuBottomNavSlot.exploreIcons =>
          'Figma Simple Kit: icons only + active dot',
        MenuBottomNavSlot.deliverySolid =>
          'Figma 50 Mobile: solid dark labeled bar',
        MenuBottomNavSlot.guestIsland =>
          'Figma floating island dock',
        MenuBottomNavSlot.nightPill =>
          'Figma liquid/gooey blob active on dark bar',
        MenuBottomNavSlot.activeTopLine =>
          'Figma 3-Nav: wave/hump top indicator',
        MenuBottomNavSlot.segmentCapsule =>
          'Figma 50 Mobile: pill highlight around active',
        MenuBottomNavSlot.centerBump =>
          'Figma notched FAB / center dip cart bump',
        MenuBottomNavSlot.minimalHairline =>
          'Figma Simple Kit: underline under active',
        MenuBottomNavSlot.animatedBubble =>
          'Figma Animated Navigation Bar: orange float bubble + white dip',
        MenuBottomNavSlot.liquidDip =>
          'Figma Junii Mobile Nav: concave top dip + orange bubble in pocket',
        MenuBottomNavSlot.ideatePill =>
          'Figma Ideate Design: blue bar + sliding white label pill',
        MenuBottomNavSlot.greenCircleBar =>
          'Figma Navigation App: green bar + circular icon buttons',
        MenuBottomNavSlot.greenArcDock =>
          'Figma Navigation App: semi-circular green arc dock',
        MenuBottomNavSlot.glassBridge =>
          'Figma Modern Bottom Nav Pack: glass connected circles',
        MenuBottomNavSlot.glassExpandLabel =>
          'Figma Modern Bottom Nav Pack: expanded purple label pill',
        MenuBottomNavSlot.glassCircleActive =>
          'Figma Modern Bottom Nav Pack: solid circle active on glass',
        MenuBottomNavSlot.glassArcGlow =>
          'Figma Modern Bottom Nav Pack: arc glow over active icon',
        MenuBottomNavSlot.animatedCradle =>
          'Figma Animated Menu: black bar + moving cradle + orange circle',
        MenuBottomNavSlot.beatfyDark =>
          'Figma Navigation Bar variations / Beatfy: dark labeled dock',
        MenuBottomNavSlot.beatfyIcons =>
          'Figma Navigation Bar variations / Beatfy: dark icons-only rail',
      };

  static MenuBottomNavSlot? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    switch (raw) {
      case 'labeled':
      case 'materialLabeled':
        return MenuBottomNavSlot.materialLabeled;
      case 'iconsOnly':
      case 'exploreIcons':
        return MenuBottomNavSlot.exploreIcons;
      case 'elevated':
      case 'guestIsland':
        return MenuBottomNavSlot.guestIsland;
      case 'iosFrost':
        return MenuBottomNavSlot.iosFrost;
      case 'deliverySolid':
        return MenuBottomNavSlot.deliverySolid;
      case 'nightPill':
        return MenuBottomNavSlot.nightPill;
      case 'activeTopLine':
        return MenuBottomNavSlot.activeTopLine;
      case 'segmentCapsule':
        return MenuBottomNavSlot.segmentCapsule;
      case 'centerBump':
        return MenuBottomNavSlot.centerBump;
      case 'minimalHairline':
        return MenuBottomNavSlot.minimalHairline;
      case 'animatedBubble':
      case 'orangeBubble':
      case 'floatBubble':
        return MenuBottomNavSlot.animatedBubble;
      case 'liquidDip':
      case 'juniiDip':
      case 'concaveDip':
        return MenuBottomNavSlot.liquidDip;
      case 'ideatePill':
      case 'slidingPill':
      case 'ideateNav':
        return MenuBottomNavSlot.ideatePill;
      case 'greenCircleBar':
      case 'navigationAppBar':
        return MenuBottomNavSlot.greenCircleBar;
      case 'greenArcDock':
      case 'navigationAppArc':
        return MenuBottomNavSlot.greenArcDock;
      case 'glassBridge':
      case 'modernGlass':
        return MenuBottomNavSlot.glassBridge;
      case 'glassExpandLabel':
      case 'modernExpand':
        return MenuBottomNavSlot.glassExpandLabel;
      case 'glassCircleActive':
      case 'modernCircle':
        return MenuBottomNavSlot.glassCircleActive;
      case 'glassArcGlow':
      case 'modernArc':
        return MenuBottomNavSlot.glassArcGlow;
      case 'animatedCradle':
      case 'cradleNav':
      case 'movingCradle':
        return MenuBottomNavSlot.animatedCradle;
      case 'beatfyDark':
      case 'beatfyLabeled':
      case 'sideNavDark':
        return MenuBottomNavSlot.beatfyDark;
      case 'beatfyIcons':
      case 'beatfyCollapsed':
        return MenuBottomNavSlot.beatfyIcons;
    }
    for (final v in MenuBottomNavSlot.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

/// أشكال عرض الملف الشخصي — مستوحاة من منصات حقيقية (Material / iOS / توصيل / حسابات).
/// المفاتيح ثابتة في JSON؛ الأسماء القديمة تُحوَّل في [tryParse].
enum MenuProfileSheetSlot {
  /// Material modal bottom sheet + مقبض سحب.
  sheetGrab,
  /// صفحة حساب كاملة (DoorDash Account tab feel).
  fullPage,
  /// Apple card sheet: زوايا كبيرة + grabber.
  iosCard,
  /// درج جانبي من البداية (Amazon account drawer).
  sideDrawer,
  /// بطاقة حساب متمركزة (Uber/DoorDash modal).
  accountHub,
  /// ورقة نصف ارتفاع (Airbnb peek).
  compactPeek,
  /// لوحة ليلية مرتفعة (Spotify).
  nightPanel,
  /// رأس هوية كبير ثم الحقول (Instagram profile header).
  heroIdentity,
  /// ورقة مع شريط حفظ لاصق أسفل (commerce sticky CTA).
  splitActions,
  /// طبقة ضبابية شفافة (iOS frosted overlay).
  glassOverlay,
}

extension MenuProfileSheetSlotX on MenuProfileSheetSlot {
  String get key => name;

  String get labelAr => switch (this) {
        MenuProfileSheetSlot.sheetGrab => 'ورقة بمقبض',
        MenuProfileSheetSlot.fullPage => 'صفحة كاملة',
        MenuProfileSheetSlot.iosCard => 'بطاقة iOS',
        MenuProfileSheetSlot.sideDrawer => 'درج جانبي',
        MenuProfileSheetSlot.accountHub => 'مركز حساب',
        MenuProfileSheetSlot.compactPeek => 'نظرة نصفية',
        MenuProfileSheetSlot.nightPanel => 'لوحة ليلية',
        MenuProfileSheetSlot.heroIdentity => 'رأس هوية',
        MenuProfileSheetSlot.splitActions => 'حفظ لاصق',
        MenuProfileSheetSlot.glassOverlay => 'طبقة ضبابية',
      };

  /// مرجع المنصة للمطورين (لا يظهر للتاجر).
  String get inspiredBy => switch (this) {
        MenuProfileSheetSlot.sheetGrab => 'Material modal bottom sheet',
        MenuProfileSheetSlot.fullPage => 'DoorDash / full account screen',
        MenuProfileSheetSlot.iosCard => 'Apple card-style sheet',
        MenuProfileSheetSlot.sideDrawer => 'Amazon account side drawer',
        MenuProfileSheetSlot.accountHub => 'Uber Eats centered account modal',
        MenuProfileSheetSlot.compactPeek => 'Airbnb half-height peek sheet',
        MenuProfileSheetSlot.nightPanel => 'Spotify dark elevated panel',
        MenuProfileSheetSlot.heroIdentity => 'Instagram profile header layout',
        MenuProfileSheetSlot.splitActions => 'Commerce sticky save footer',
        MenuProfileSheetSlot.glassOverlay => 'iOS frosted glass overlay',
      };

  static MenuProfileSheetSlot? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    switch (raw) {
      case 'bottomSheet':
      case 'sheetGrab':
        return MenuProfileSheetSlot.sheetGrab;
      case 'fullPage':
        return MenuProfileSheetSlot.fullPage;
      case 'iosCard':
        return MenuProfileSheetSlot.iosCard;
      case 'sideDrawer':
        return MenuProfileSheetSlot.sideDrawer;
      case 'accountHub':
        return MenuProfileSheetSlot.accountHub;
      case 'compactPeek':
        return MenuProfileSheetSlot.compactPeek;
      case 'nightPanel':
        return MenuProfileSheetSlot.nightPanel;
      case 'heroIdentity':
        return MenuProfileSheetSlot.heroIdentity;
      case 'splitActions':
        return MenuProfileSheetSlot.splitActions;
      case 'glassOverlay':
        return MenuProfileSheetSlot.glassOverlay;
    }
    for (final v in MenuProfileSheetSlot.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

/// سرعات حركة البطاقات — مضاعف مدة + تأخير متتابع (tokens من مواصفات Figma motion).
enum MenuMotionSpeedSlot {
  slow,
  normal,
  fast,
  snappy,
}

extension MenuMotionSpeedSlotX on MenuMotionSpeedSlot {
  String get key => name;

  String get labelAr => switch (this) {
        MenuMotionSpeedSlot.slow => 'بطيئة',
        MenuMotionSpeedSlot.normal => 'عادية',
        MenuMotionSpeedSlot.fast => 'سريعة',
        MenuMotionSpeedSlot.snappy => 'خاطفة',
      };

  /// مضاعف مدة الحركة (1.0 = عادية) — للتوافق؛ المدة الفعلية من [resolvedDurationMs].
  double get durationFactor => 1.0;

  /// تأخير بين البطاقة والتالية (ms) — نمط stagger قوائم Figma (~60ms عادي).
  int get staggerMs => switch (this) {
        MenuMotionSpeedSlot.slow => 70,
        MenuMotionSpeedSlot.normal => 45,
        MenuMotionSpeedSlot.fast => 22,
        MenuMotionSpeedSlot.snappy => 10,
      };

  /// مدة الأساس بالميلي ثانية.
  int get baseDurationMs => switch (this) {
        MenuMotionSpeedSlot.slow => 620,
        MenuMotionSpeedSlot.normal => 340,
        MenuMotionSpeedSlot.fast => 200,
        MenuMotionSpeedSlot.snappy => 130,
      };

  int get resolvedDurationMs => baseDurationMs.clamp(120, 1000);

  static MenuMotionSpeedSlot nearestForMs(int ms) {
    MenuMotionSpeedSlot best = MenuMotionSpeedSlot.normal;
    var bestDiff = 1 << 30;
    for (final s in MenuMotionSpeedSlot.values) {
      final d = (s.resolvedDurationMs - ms).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = s;
      }
    }
    return best;
  }

  static MenuMotionSpeedSlot? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final v in MenuMotionSpeedSlot.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

/// حركات دخول بطاقات المنيو — مستوحاة من أنماط Figma لقوائم الطعام/التوصيل.
enum MenuMotionSlot {
  none,
  /// تلاشي بسيط (Material / standard fade).
  fade,
  /// انزلاق من بداية القراءة (RTL-aware).
  fromInlineStart,
  /// انزلاق من نهاية القراءة.
  fromInlineEnd,
  /// صعود من الأسفل.
  fromBottom,
  /// صعود متتابع أقوى — Figma staggered list (~60ms).
  staggerRise,
  /// ظهور بمقياس (بطاقة منتج / Speedy Chow card pop).
  scalePop,
  /// تكبير خفيف ثم استقرار (صور طعام / soft zoom settle).
  softZoom,
  /// ارتداد خفيف (expressive spring token).
  springPop,
  /// دخول مائل كـ swipe بطاقة (Card Swipe Animation community).
  swipeTilt,
}

extension MenuMotionSlotX on MenuMotionSlot {
  String get key => name;

  String get labelAr => switch (this) {
        MenuMotionSlot.none => 'بدون حركة',
        MenuMotionSlot.fade => 'تلاشي',
        MenuMotionSlot.fromInlineStart => 'من البداية (RTL)',
        MenuMotionSlot.fromInlineEnd => 'من النهاية (RTL)',
        MenuMotionSlot.fromBottom => 'من الأسفل',
        MenuMotionSlot.staggerRise => 'صعود متتابع',
        MenuMotionSlot.scalePop => 'ظهور بمقياس',
        MenuMotionSlot.softZoom => 'تكبير ناعم',
        MenuMotionSlot.springPop => 'ارتداد',
        MenuMotionSlot.swipeTilt => 'سحب مائل',
      };

  String get inspiredBy => switch (this) {
        MenuMotionSlot.none => 'Reduced motion / static',
        MenuMotionSlot.fade => 'Material fade / Figma opacity Smart Animate',
        MenuMotionSlot.fromInlineStart => 'RTL slide-in list',
        MenuMotionSlot.fromInlineEnd => 'RTL reverse slide-in',
        MenuMotionSlot.fromBottom => 'Bottom rise card enter',
        MenuMotionSlot.staggerRise =>
          'Figma staggered list (Aninix / 60ms cascade)',
        MenuMotionSlot.scalePop =>
          'Food UI kit card pop (Speedy Chow / Swiggy motion)',
        MenuMotionSlot.softZoom => 'Food photo soft-zoom settle',
        MenuMotionSlot.springPop => 'Figma expressive spring / overshoot',
        MenuMotionSlot.swipeTilt =>
          'Figma Community Card Swipe Animation tilt',
      };

  static MenuMotionSlot? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final v in MenuMotionSlot.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

/// مفاتيح layout المسموحة في JSON الثيم.
const kMenuLayoutSlotKeys = {
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

/// موقع شعار المطعم في ترويسة الهوية (منطقي: بداية القراءة = يمين في العربية).
enum MenuBrandLogoAlign {
  /// يمين الشاشة في العربية (بداية القراءة).
  start,
  center,
  /// يسار الشاشة في العربية (نهاية القراءة).
  end,
}

extension MenuBrandLogoAlignX on MenuBrandLogoAlign {
  String get key => name;

  String get labelAr => switch (this) {
        MenuBrandLogoAlign.start => 'يمين',
        MenuBrandLogoAlign.center => 'وسط',
        MenuBrandLogoAlign.end => 'يسار',
      };

  static MenuBrandLogoAlign? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final v in MenuBrandLogoAlign.values) {
      if (v.name == raw) return v;
    }
    // توافق: right/left physical aliases
    switch (raw) {
      case 'right':
        return MenuBrandLogoAlign.start;
      case 'left':
        return MenuBrandLogoAlign.end;
      case 'middle':
        return MenuBrandLogoAlign.center;
    }
    return null;
  }
}

/// موضع اسم المطعم والشعار القصير بالنسبة للوجو.
enum MenuBrandTextPlacement {
  /// بجانب اللوجو.
  beside,
  /// تحت اللوجو.
  under,
}

extension MenuBrandTextPlacementX on MenuBrandTextPlacement {
  String get key => name;

  String get labelAr => switch (this) {
        MenuBrandTextPlacement.beside => 'بجانب اللوجو',
        MenuBrandTextPlacement.under => 'تحت اللوجو',
      };

  static MenuBrandTextPlacement? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final v in MenuBrandTextPlacement.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

/// محاذاة كتلة الاسم + الشعار القصير.
enum MenuBrandTextAlign {
  start,
  center,
  end,
}

extension MenuBrandTextAlignX on MenuBrandTextAlign {
  String get key => name;

  String get labelAr => switch (this) {
        MenuBrandTextAlign.start => 'يمين',
        MenuBrandTextAlign.center => 'وسط',
        MenuBrandTextAlign.end => 'يسار',
      };

  static MenuBrandTextAlign? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final v in MenuBrandTextAlign.values) {
      if (v.name == raw) return v;
    }
    switch (raw) {
      case 'right':
        return MenuBrandTextAlign.start;
      case 'left':
        return MenuBrandTextAlign.end;
      case 'middle':
        return MenuBrandTextAlign.center;
    }
    return null;
  }
}

/// أشكال شريط التصنيفات — مستوحاة من Figma (Swiggy / Bobo / sticky tabs / side rail).
enum MenuCategoryNavSlot {
  /// إخفاء الشريط بالكامل.
  hidden,
  /// تبويبات نصية علوية بخط سفلي (sticky underline).
  topUnderline,
  /// حبوب أفقية قابلة للتمرير (Swiggy / Bobo chips).
  topPills,
  /// مجموعة مقطّعة متصلة (segmented).
  topSegmented,
  /// حبوب عائمة بظل خفيف.
  floatingPills,
  /// شريط رأسي عند بداية القراءة (RTL = يمين).
  sideRailStart,
  /// شريط رأسي عند نهاية القراءة.
  sideRailEnd,
  /// حلقات أيقونة + تسمية (What's on your mind).
  iconRing,
  /// لفّ متعدد الأسطر بدون تمرير أفقي.
  wrapChips,
  /// شريط بانر عريض لاصق في الأعلى.
  stickyBanner,
}

extension MenuCategoryNavSlotX on MenuCategoryNavSlot {
  String get key => name;

  String get labelAr => switch (this) {
        MenuCategoryNavSlot.hidden => 'مخفي',
        MenuCategoryNavSlot.topUnderline => 'تبويب علوي بخط',
        MenuCategoryNavSlot.topPills => 'حبوب علوية',
        MenuCategoryNavSlot.topSegmented => 'مقطّع علوي',
        MenuCategoryNavSlot.floatingPills => 'حبوب عائمة',
        MenuCategoryNavSlot.sideRailStart => 'شريط جانبي (بداية)',
        MenuCategoryNavSlot.sideRailEnd => 'شريط جانبي (نهاية)',
        MenuCategoryNavSlot.iconRing => 'حلقات أيقونات',
        MenuCategoryNavSlot.wrapChips => 'لفّ متعدد',
        MenuCategoryNavSlot.stickyBanner => 'بانر لاصق',
      };

  String get inspiredBy => switch (this) {
        MenuCategoryNavSlot.hidden => 'No category chrome',
        MenuCategoryNavSlot.topUnderline =>
          'Sticky menu text tabs (food delivery menu screen)',
        MenuCategoryNavSlot.topPills =>
          'Swiggy / Bobo horizontal category chips',
        MenuCategoryNavSlot.topSegmented => 'iOS / Material segmented filters',
        MenuCategoryNavSlot.floatingPills => 'Floating filter pill dock',
        MenuCategoryNavSlot.sideRailStart =>
          'QR menu / side category rail (start)',
        MenuCategoryNavSlot.sideRailEnd => 'Side category rail (end)',
        MenuCategoryNavSlot.iconRing =>
          'Swiggy “What’s on your mind?” circular categories',
        MenuCategoryNavSlot.wrapChips => 'Wrapped filter chips grid',
        MenuCategoryNavSlot.stickyBanner =>
          'Sticky banner category strip under hero',
      };

  bool get isSideRail =>
      this == MenuCategoryNavSlot.sideRailStart ||
      this == MenuCategoryNavSlot.sideRailEnd;

  static MenuCategoryNavSlot? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    switch (raw) {
      case 'hidden':
      case 'dropdown_hidden':
        return MenuCategoryNavSlot.hidden;
      case 'top_text_tabs':
      case 'topUnderline':
        return MenuCategoryNavSlot.topUnderline;
      case 'top_pills':
      case 'topPills':
        return MenuCategoryNavSlot.topPills;
      case 'top_segmented':
      case 'topSegmented':
        return MenuCategoryNavSlot.topSegmented;
      case 'floating_pills':
      case 'floatingPills':
        return MenuCategoryNavSlot.floatingPills;
      case 'sideRailStart':
        return MenuCategoryNavSlot.sideRailStart;
      case 'sideRailEnd':
        return MenuCategoryNavSlot.sideRailEnd;
      case 'iconRing':
        return MenuCategoryNavSlot.iconRing;
      case 'wrapChips':
        return MenuCategoryNavSlot.wrapChips;
      case 'stickyBanner':
        return MenuCategoryNavSlot.stickyBanner;
    }
    for (final v in MenuCategoryNavSlot.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}
