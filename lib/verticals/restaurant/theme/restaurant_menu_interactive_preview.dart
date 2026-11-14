import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/restaurant_money.dart';
import 'contrast_tokens.dart';
import 'layout_slots.dart';
import 'presets/presets.dart';
import 'theme_schema_validator.dart';

/// شعار/غلاف من مسار محلي أو URL — نفس منطق معاينة الثيم القديمة.
Widget? _brandImage(String? pathOrUrl, {BoxFit fit = BoxFit.cover}) {
  if (pathOrUrl == null || pathOrUrl.trim().isEmpty) return null;
  final p = pathOrUrl.trim();
  if (p.startsWith('http://') || p.startsWith('https://')) {
    return Image.network(
      p,
      fit: fit,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
  if (!kIsWeb) {
    final f = File(p);
    if (f.existsSync()) {
      return Image.file(
        f,
        fit: fit,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
  }
  return null;
}

/// يحوّل قالب العرض الموحّد (`home_layout`) إلى محرك هيكل المعاينة.
/// `item_layout` يُزامَن مع القالب عند الاختيار ولا يتجاوزه.
RestaurantMenuChrome effectiveMenuChrome(RestaurantThemeCustomization theme) {
  switch (theme.homeLayoutSlot) {
    case MenuHomeLayoutSlot.followChrome:
      return theme.architecture.chrome;
    case MenuHomeLayoutSlot.appGrid:
      return RestaurantMenuChrome.appGrid;
    case MenuHomeLayoutSlot.photoStack:
      return RestaurantMenuChrome.photoStack;
    case MenuHomeLayoutSlot.editorial:
      return RestaurantMenuChrome.editorial;
    case MenuHomeLayoutSlot.paperList:
      return RestaurantMenuChrome.paperList;
    case MenuHomeLayoutSlot.storyCards:
      return RestaurantMenuChrome.storyCards;
    case MenuHomeLayoutSlot.heroCover:
      return RestaurantMenuChrome.heroCover;
    case MenuHomeLayoutSlot.compactTiles:
      return RestaurantMenuChrome.compactTiles;
    case MenuHomeLayoutSlot.sideRail:
      return RestaurantMenuChrome.sideRail;
    case MenuHomeLayoutSlot.softCards:
      return RestaurantMenuChrome.softCards;
    case MenuHomeLayoutSlot.magazine:
      return RestaurantMenuChrome.magazine;
    case MenuHomeLayoutSlot.bannerMenu:
      return RestaurantMenuChrome.bannerMenu;
    case MenuHomeLayoutSlot.splitRow:
      return RestaurantMenuChrome.splitRow;
    case MenuHomeLayoutSlot.coverThenList:
      return RestaurantMenuChrome.coverThenList;
    case MenuHomeLayoutSlot.menuBoard:
      return RestaurantMenuChrome.menuBoard;
  }
}

/// معاينة هاتف: رئيسية (بحث) · سلة · طلباتي — قاعدة لكل نموذج تصميم.
class RestaurantMenuInteractivePreview extends StatefulWidget {
  const RestaurantMenuInteractivePreview({
    super.key,
    required this.theme,
  });

  final RestaurantThemeCustomization theme;

  @override
  State<RestaurantMenuInteractivePreview> createState() =>
      _RestaurantMenuInteractivePreviewState();
}

enum _Tab { home, cart, orders }

class _Sample {
  const _Sample(this.name, this.desc, this.priceFils);
  final String name;
  final String desc;
  final int priceFils;
}

class _Line {
  _Line({required this.item, required this.qty});
  final _Sample item;
  int qty;
}

class _Order {
  _Order({
    required this.id,
    required this.lines,
    required this.statusAr,
  });
  final String id;
  final List<_Line> lines;
  final String statusAr;
}

class _RestaurantMenuInteractivePreviewState
    extends State<RestaurantMenuInteractivePreview> {
  static const _samples = <_Sample>[
    _Sample('برغر لحم مشوي', 'لحم طازج، خس، طماطم وصلصة المنزل', 8500000),
    _Sample('عصير برتقال', 'معصور يومياً بدون سكر', 2000000),
    _Sample('سلطة الموسم', 'خضار طازجة وزيت زيتون', 3500000),
    _Sample('كنافة نابلسية', 'جبنة عكاوي وقطر خفيف', 4500000),
  ];

  _Tab _tab = _Tab.home;
  _Sample? _detail;
  final _cart = <_Line>[];
  final _orders = <_Order>[];
  final _search = TextEditingController();
  final _phone = TextEditingController();
  final _addr1 = TextEditingController();
  final _addr2 = TextEditingController();
  final _name = TextEditingController();
  final _nickname = TextEditingController();
  final _landmark = TextEditingController();
  bool _gps = false;
  bool _profileOpen = false;
  bool _welcomeDismissed = false;
  String? _toast;
  String _cat = 'الكل';

  static const _profilePrefsKey = 'naboo.menu.guestProfile.v1';
  static const _cats = ['الكل', 'أطباق', 'مشروبات', 'حلويات'];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void didUpdateWidget(covariant RestaurantMenuInteractivePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.theme.welcomeMode != widget.theme.welcomeMode ||
        oldWidget.theme.layout['welcome_mode'] !=
            widget.theme.layout['welcome_mode']) {
      _welcomeDismissed = false;
    }
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilePrefsKey);
    if (raw == null || raw.isEmpty) return;
    // simple key=value lines to avoid json dependency noise
    final map = <String, String>{};
    for (final line in raw.split('\n')) {
      final i = line.indexOf('=');
      if (i <= 0) continue;
      map[line.substring(0, i)] = line.substring(i + 1);
    }
    if (!mounted) return;
    setState(() {
      _name.text = map['full_name'] ?? '';
      _nickname.text = map['nickname'] ?? '';
      _phone.text = map['phone'] ?? '';
      _addr1.text = map['address1'] ?? '';
      _addr2.text = map['address2'] ?? '';
      _landmark.text = map['landmark'] ?? '';
      _gps = map['gps'] == '1';
    });
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = [
      'full_name=${_name.text.trim()}',
      'nickname=${_nickname.text.trim()}',
      'phone=${_phone.text.trim()}',
      'address1=${_addr1.text.trim()}',
      'address2=${_addr2.text.trim()}',
      'landmark=${_landmark.text.trim()}',
      'gps=${_gps ? '1' : '0'}',
    ].join('\n');
    await prefs.setString(_profilePrefsKey, raw);
  }

  @override
  void dispose() {
    _search.dispose();
    _phone.dispose();
    _addr1.dispose();
    _addr2.dispose();
    _name.dispose();
    _nickname.dispose();
    _landmark.dispose();
    super.dispose();
  }

  int get _cartQty => _cart.fold(0, (a, c) => a + c.qty);

  List<_Sample> get _filtered {
    final q = _search.text.trim();
    if (q.isEmpty) return _samples;
    return _samples
        .where((s) => s.name.contains(q) || s.desc.contains(q))
        .toList();
  }

  void _add(_Sample item) {
    setState(() {
      final i = _cart.indexWhere((c) => c.item.name == item.name);
      if (i >= 0) {
        _cart[i].qty += 1;
      } else {
        _cart.add(_Line(item: item, qty: 1));
      }
      _toast = 'أُضيف إلى السلة';
    });
  }

  void _confirm() {
    if (_cart.isEmpty) return;
    if (_phone.text.trim().length < 8) {
      setState(() => _toast = 'أدخل رقم هاتف للتواصل مع التوصيل');
      return;
    }
    if (!_gps && _addr1.text.trim().isEmpty) {
      setState(() => _toast = 'فعّل GPS أو اكتب العنوان');
      return;
    }
    setState(() {
      _orders.insert(
        0,
        _Order(
          id: '${DateTime.now().millisecondsSinceEpoch % 100000}',
          lines: List.of(_cart),
          statusAr: 'بانتظار التواصل للتوصيل',
        ),
      );
      _cart.clear();
      _tab = _Tab.orders;
      _toast = 'تم تأكيد الطلب — تابع من طلباتي';
    });
    _saveProfile();
  }

  Color _c(String hex) {
    final clean = hex.replaceFirst('#', '');
    if (clean.length != 6) return const Color(0xFF111827);
    return Color(0xFF000000 | int.parse(clean, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final bg = _c(theme.colors['bg'] ?? '#F7F0E6');
    final text = _c(theme.colors['text'] ?? '#1C1917');
    final accent = _c(theme.colors['accent'] ?? '#B8960C');
    final primary = _c(theme.colors['primary'] ?? '#1E293B');
    final font = theme.fontFamily.flutterFamily;
    final chrome = effectiveMenuChrome(theme);
    final showWelcome = !_welcomeDismissed &&
        theme.welcomeMode != RestaurantWelcomeMode.none;

    return LayoutBuilder(
      builder: (context, constraints) {
        var w = constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(160.0, 360.0)
            : 300.0;
        var h = w * 17.2 / 9;
        if (constraints.maxHeight.isFinite && h > constraints.maxHeight) {
          h = constraints.maxHeight;
          w = h * 9 / 17.2;
        }
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: const Color(0xFF1F2937), width: 2.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Directionality(
                    textDirection:
                        theme.menuLanguage == RestaurantMenuLanguage.en
                            ? TextDirection.ltr
                            : TextDirection.rtl,
                    child: ColoredBox(
                      color: bg,
                      child: Stack(
                        children: [
                          Column(
                            children: [
                              Expanded(
                                child: _detail != null
                                    ? _detailView(font, text, accent)
                                    : switch (_tab) {
                                        _Tab.home => _home(
                                            font,
                                            text,
                                            accent,
                                            primary,
                                            bg,
                                            chrome,
                                          ),
                                        _Tab.cart =>
                                          _cartView(font, text, accent),
                                        _Tab.orders =>
                                          _ordersView(font, text, accent),
                                      },
                              ),
                              if (_toast != null)
                                Padding(
                                  padding:
                                      const EdgeInsetsDirectional.fromSTEB(
                                    10,
                                    0,
                                    10,
                                    4,
                                  ),
                                  child: Text(
                                    _toast!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: font,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: accent,
                                    ),
                                  ),
                                ),
                              if (_detail == null)
                                _nav(font, text, accent, bg),
                            ],
                          ),
                          if (_profileOpen)
                            _profileSheet(font, text, accent, primary, bg),
                          if (showWelcome)
                            _welcomeOverlay(font, text, accent, primary, bg),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _welcomeOverlay(
    String font,
    Color text,
    Color accent,
    Color primary,
    Color bg,
  ) {
    final theme = widget.theme;
    final name = (theme.identity['display_name_ar'] ?? '').trim();
    final title = name.isEmpty ? 'مرحباً بكم' : name;
    final isLogo = theme.welcomeMode == RestaurantWelcomeMode.logoSplash;
    final splashImg = _brandImage(
      isLogo ? theme.identity['logo_url'] : theme.identity['cover_url'],
    );
    return Positioned.fill(
      child: Material(
        color: bg,
        child: InkWell(
          onTap: () => setState(() => _welcomeDismissed = true),
          child: Padding(
            padding: const EdgeInsetsDirectional.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(isLogo ? 44 : 12),
                  child: SizedBox(
                    width: isLogo ? 88 : double.infinity,
                    height: isLogo ? 88 : 120,
                    child: splashImg ??
                        ColoredBox(
                          color: accent,
                          child: Center(
                            child: Text(
                              title.isEmpty ? 'م' : title.substring(0, 1),
                              style: TextStyle(
                                fontFamily: font,
                                fontSize: isLogo ? 36 : 28,
                                fontWeight: FontWeight.w900,
                                color: bg,
                              ),
                            ),
                          ),
                        ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: font,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'اضغط للمتابعة إلى المنيو',
                  style: TextStyle(
                    fontFamily: font,
                    fontSize: 12,
                    color: text.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileSheet(
    String font,
    Color text,
    Color accent,
    Color primary,
    Color bg,
  ) {
    final slot = widget.theme.profileSheetSlot;
    final night = slot == MenuProfileSheetSlot.nightPanel;
    final panelBg = night
        ? const Color(0xFF181818)
        : slot == MenuProfileSheetSlot.glassOverlay
            ? Color.lerp(bg, Colors.white, 0.12)!.withValues(alpha: 0.92)
            : bg;
    final ink = night ? const Color(0xFFF5F5F5) : text;
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(
        slot == MenuProfileSheetSlot.iosCard ? 12 : 8,
      ),
      borderSide: BorderSide(
        color: night
            ? Colors.white.withValues(alpha: 0.18)
            : text.withValues(alpha: 0.2),
      ),
    );
    InputDecoration dec(String label) => InputDecoration(
          labelText: label,
          border: fieldBorder,
          enabledBorder: fieldBorder,
          isDense: true,
          filled: slot == MenuProfileSheetSlot.iosCard ||
              slot == MenuProfileSheetSlot.nightPanel,
          fillColor: night
              ? Colors.white.withValues(alpha: 0.06)
              : text.withValues(alpha: 0.04),
          labelStyle: TextStyle(fontFamily: font, fontSize: 11, color: ink),
        );

    Future<void> saveAndClose() async {
      await _saveProfile();
      setState(() {
        _profileOpen = false;
        _toast = 'تم حفظ الملف الشخصي';
      });
    }

    final nameTrim = _name.text.trim();
    final initial = nameTrim.isEmpty ? 'ض' : nameTrim.substring(0, 1);

    final fields = <Widget>[
      TextField(
        controller: _name,
        style: TextStyle(fontFamily: font, color: ink, fontSize: 12),
        decoration: dec('الاسم'),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: _nickname,
        style: TextStyle(fontFamily: font, color: ink, fontSize: 12),
        decoration: dec('اللقب / الاسم المستعار'),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        style: TextStyle(fontFamily: font, color: ink, fontSize: 12),
        decoration: dec('رقم الهاتف'),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: _addr1,
        style: TextStyle(fontFamily: font, color: ink, fontSize: 12),
        decoration: dec('العنوان (سطر 1)'),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: _addr2,
        style: TextStyle(fontFamily: font, color: ink, fontSize: 12),
        decoration: dec('العنوان (سطر 2)'),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: _landmark,
        style: TextStyle(fontFamily: font, color: ink, fontSize: 12),
        decoration: dec('أقرب نقطة دالة'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: () => setState(() {
          _gps = true;
          _toast = 'تم حفظ موقع تجريبي (GPS)';
        }),
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.5)),
        ),
        child: Text(
          _gps ? 'تم التقاط الموقع' : 'تحديد موقعي',
          style: TextStyle(fontFamily: font, color: accent),
        ),
      ),
    ];

    final showGrab = slot == MenuProfileSheetSlot.sheetGrab ||
        slot == MenuProfileSheetSlot.iosCard ||
        slot == MenuProfileSheetSlot.compactPeek ||
        slot == MenuProfileSheetSlot.splitActions ||
        slot == MenuProfileSheetSlot.glassOverlay;

    final head = <Widget>[
      if (showGrab)
        Center(
          child: Container(
            width: slot == MenuProfileSheetSlot.iosCard ? 40 : 36,
            height: 4,
            margin: const EdgeInsetsDirectional.only(bottom: 10),
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      if (slot == MenuProfileSheetSlot.heroIdentity) ...[
        Center(
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [primary, accent]),
            ),
            child: Text(
              initial,
              style: TextStyle(
                fontFamily: font,
                fontWeight: FontWeight.w900,
                fontSize: 26,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          nameTrim.isEmpty ? 'ضيف المنيو' : nameTrim,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: font,
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: ink,
          ),
        ),
        const SizedBox(height: 12),
      ],
      Row(
        children: [
          Expanded(
            child: Text(
              slot == MenuProfileSheetSlot.accountHub
                  ? 'حسابك'
                  : 'ملفي الشخصي',
              style: TextStyle(
                fontFamily: font,
                fontWeight: FontWeight.w900,
                fontSize: slot == MenuProfileSheetSlot.iosCard ? 17 : 15,
                color: ink,
              ),
            ),
          ),
          if (slot != MenuProfileSheetSlot.splitActions &&
              slot != MenuProfileSheetSlot.accountHub)
            TextButton(
              onPressed: saveAndClose,
              child: Text(
                'حفظ',
                style: TextStyle(
                  fontFamily: font,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
        ],
      ),
    ];

    final saveBar = SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: saveAndClose,
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          'حفظ الملف الشخصي',
          style: TextStyle(fontFamily: font, fontWeight: FontWeight.w800),
        ),
      ),
    );

    final double maxH;
    final BorderRadiusGeometry radius;
    final List<BoxShadow>? shadows;
    final EdgeInsetsGeometry pad;
    switch (slot) {
      case MenuProfileSheetSlot.fullPage:
        maxH = 900;
        radius = BorderRadius.zero;
        shadows = null;
        pad = const EdgeInsetsDirectional.fromSTEB(16, 20, 16, 20);
      case MenuProfileSheetSlot.sheetGrab:
        maxH = 420;
        radius = const BorderRadius.vertical(top: Radius.circular(16));
        shadows = const [
          BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, -2)),
        ];
        pad = const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 16);
      case MenuProfileSheetSlot.iosCard:
        maxH = 460;
        radius = const BorderRadius.vertical(top: Radius.circular(28));
        shadows = const [
          BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -4)),
        ];
        pad = const EdgeInsetsDirectional.fromSTEB(18, 10, 18, 22);
      case MenuProfileSheetSlot.compactPeek:
        maxH = 280;
        radius = const BorderRadius.vertical(top: Radius.circular(20));
        shadows = const [
          BoxShadow(color: Colors.black26, blurRadius: 14, offset: Offset(0, -2)),
        ];
        pad = const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 16);
      case MenuProfileSheetSlot.splitActions:
        maxH = 440;
        radius = const BorderRadius.vertical(top: Radius.circular(18));
        shadows = const [
          BoxShadow(color: Colors.black26, blurRadius: 14, offset: Offset(0, -2)),
        ];
        pad = const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 8);
      case MenuProfileSheetSlot.nightPanel:
        maxH = 430;
        radius = const BorderRadius.vertical(top: Radius.circular(16));
        shadows = [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ];
        pad = const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 16);
      case MenuProfileSheetSlot.glassOverlay:
        maxH = 420;
        radius = const BorderRadius.vertical(top: Radius.circular(22));
        shadows = const [
          BoxShadow(color: Colors.black38, blurRadius: 18, offset: Offset(0, -3)),
        ];
        pad = const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 16);
      case MenuProfileSheetSlot.heroIdentity:
        maxH = 480;
        radius = const BorderRadius.vertical(top: Radius.circular(20));
        shadows = const [
          BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -3)),
        ];
        pad = const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 16);
      case MenuProfileSheetSlot.accountHub:
        maxH = 460;
        radius = BorderRadius.circular(20);
        shadows = const [
          BoxShadow(color: Colors.black38, blurRadius: 28, offset: Offset(0, 12)),
        ];
        pad = const EdgeInsetsDirectional.fromSTEB(18, 18, 18, 18);
      case MenuProfileSheetSlot.sideDrawer:
        maxH = 900;
        radius = const BorderRadiusDirectional.only(
          topEnd: Radius.circular(16),
          bottomEnd: Radius.circular(16),
        );
        shadows = const [
          BoxShadow(color: Colors.black38, blurRadius: 20, offset: Offset(-4, 0)),
        ];
        pad = const EdgeInsetsDirectional.fromSTEB(14, 18, 14, 18);
    }

    final bodyKids = <Widget>[
      ...head,
      ...fields,
      if (slot == MenuProfileSheetSlot.accountHub) ...[
        const SizedBox(height: 10),
        saveBar,
      ],
    ];

    Widget panel;
    if (slot == MenuProfileSheetSlot.splitActions) {
      panel = Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: panelBg,
          borderRadius: radius,
          boxShadow: shadows,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: pad,
                children: [...head, ...fields],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: panelBg,
                border: Border(
                  top: BorderSide(color: ink.withValues(alpha: 0.12)),
                ),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 14, 12),
                child: saveBar,
              ),
            ),
          ],
        ),
      );
    } else if (slot == MenuProfileSheetSlot.fullPage ||
        slot == MenuProfileSheetSlot.sideDrawer) {
      panel = Container(
        width: slot == MenuProfileSheetSlot.sideDrawer ? 280 : null,
        decoration: BoxDecoration(
          color: panelBg,
          borderRadius: radius,
          boxShadow: shadows,
        ),
        child: ListView(
          padding: pad,
          children: bodyKids,
        ),
      );
    } else {
      panel = Container(
        constraints: BoxConstraints(
          maxHeight: maxH,
          maxWidth: slot == MenuProfileSheetSlot.accountHub ? 320 : double.infinity,
        ),
        padding: pad,
        decoration: BoxDecoration(
          color: panelBg,
          borderRadius: radius,
          border: slot == MenuProfileSheetSlot.glassOverlay
              ? Border.all(color: ink.withValues(alpha: 0.12))
              : null,
          boxShadow: shadows,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: bodyKids,
        ),
      );
    }

    final scrim = switch (slot) {
      MenuProfileSheetSlot.glassOverlay => Colors.black38,
      MenuProfileSheetSlot.nightPanel => Colors.black87,
      MenuProfileSheetSlot.accountHub => Colors.black54,
      _ => Colors.black54,
    };

    final Widget placed = switch (slot) {
      MenuProfileSheetSlot.fullPage => panel,
      MenuProfileSheetSlot.sideDrawer => Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(width: 280, height: double.infinity, child: panel),
        ),
      MenuProfileSheetSlot.accountHub => Center(
          child: Padding(padding: const EdgeInsets.all(20), child: panel),
        ),
      _ => Align(alignment: Alignment.bottomCenter, child: panel),
    };

    return Material(
      color: scrim,
      child: GestureDetector(
        onTap: () => setState(() => _profileOpen = false),
        behavior: HitTestBehavior.opaque,
        child: GestureDetector(onTap: () {}, child: placed),
      ),
    );
  }

  Widget _nav(String font, Color text, Color accent, Color bg) {
    final slot = widget.theme.bottomNavSlot;
    if (slot == MenuBottomNavSlot.animatedBubble) {
      return _animatedBubbleNav(font, accent);
    }
    if (slot == MenuBottomNavSlot.liquidDip) {
      return _liquidDipNav(font, accent);
    }
    if (slot == MenuBottomNavSlot.ideatePill) {
      return _ideatePillNav(font);
    }
    if (slot == MenuBottomNavSlot.greenCircleBar) {
      return _greenCircleBarNav(font);
    }
    if (slot == MenuBottomNavSlot.greenArcDock) {
      return _greenArcDockNav(font);
    }
    if (slot == MenuBottomNavSlot.glassBridge ||
        slot == MenuBottomNavSlot.glassExpandLabel ||
        slot == MenuBottomNavSlot.glassCircleActive ||
        slot == MenuBottomNavSlot.glassArcGlow) {
      return _modernGlassNav(font, slot);
    }
    if (slot == MenuBottomNavSlot.animatedCradle) {
      return _animatedCradleNav(font, accent);
    }
    if (slot == MenuBottomNavSlot.beatfyDark ||
        slot == MenuBottomNavSlot.beatfyIcons) {
      return _beatfyNav(font, iconsOnly: slot == MenuBottomNavSlot.beatfyIcons);
    }
    final iconsOnly = slot == MenuBottomNavSlot.exploreIcons;
    final showLabels = !iconsOnly;
    final night = slot == MenuBottomNavSlot.nightPill;
    final barBg = night ? const Color(0xFF0A0A0A) : bg;
    final idle = night
        ? const Color(0xFFB3B3B3)
        : text.withValues(alpha: 0.5);
    final active = night ? const Color(0xFFB8960C) : accent;

    Widget badgeDot(int badge) {
      if (badge <= 0) return const SizedBox.shrink();
      return PositionedDirectional(
        top: -6,
        end: -10,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            '$badge',
            style: TextStyle(
              fontFamily: font,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0F172A),
            ),
          ),
        ),
      );
    }

    Widget iconFor(IconData outlined, IconData filled, bool on, {double size = 20}) {
      return Icon(on ? filled : outlined, size: size, color: on ? active : idle);
    }

    Widget btn(
      String label,
      IconData outlined,
      IconData filled,
      _Tab t, {
      int badge = 0,
      bool centerBump = false,
    }) {
      final on = _tab == t;
      final color = on ? active : idle;

      if (centerBump) {
        return Expanded(
          child: TextButton(
            onPressed: () => setState(() {
              _tab = t;
              _toast = null;
            }),
            child: Transform.translate(
              offset: const Offset(0, -10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Icon(filled, size: 22, color: Colors.white),
                        badgeDot(badge),
                      ],
                    ),
                  ),
                  if (showLabels) ...[
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: font,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }

      Widget core = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              iconFor(
                outlined,
                filled,
                on,
                size: iconsOnly ? 24 : (slot == MenuBottomNavSlot.deliverySolid ? 22 : 18),
              ),
              badgeDot(badge),
            ],
          ),
          if (showLabels) ...[
            const SizedBox(height: 2),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: font,
                fontSize: slot == MenuBottomNavSlot.minimalHairline ? 10 : 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
          if (slot == MenuBottomNavSlot.minimalHairline) ...[
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 2,
              width: on ? 22 : 0,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ],
      );

      if (slot == MenuBottomNavSlot.nightPill && on) {
        // فقاعة سائلة (Figma liquid blob)
        core = Transform.translate(
          offset: const Offset(0, -8),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(23),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(filled, size: 22, color: accent),
          ),
        );
      }

      if (slot == MenuBottomNavSlot.exploreIcons) {
        core = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconFor(outlined, filled, on, size: 24),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: on ? 6 : 0,
              height: on ? 6 : 0,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        );
      }

      if (slot == MenuBottomNavSlot.segmentCapsule) {
        core = Container(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: on ? accent.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: core,
        );
      }

      if (slot == MenuBottomNavSlot.activeTopLine) {
        // موجة علوية + نقطة (Figma wave indicator)
        core = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: on ? 10 : 4,
              width: on ? 28 : 0,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: on ? accent.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
              ),
              alignment: Alignment.topCenter,
              child: on
                  ? Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                iconFor(outlined, filled, on),
                badgeDot(badge),
              ],
            ),
            if (showLabels) ...[
              const SizedBox(height: 2),
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: font,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ],
        );
      }

      return Expanded(
        child: TextButton(
          onPressed: () => setState(() {
            _tab = t;
            _toast = null;
          }),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 4),
            minimumSize: const Size(0, 44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: core,
        ),
      );
    }

    final kids = <Widget>[
      btn(
        'الرئيسية',
        Icons.home_outlined,
        Icons.home,
        _Tab.home,
      ),
      btn(
        'السلة',
        Icons.shopping_bag_outlined,
        Icons.shopping_bag,
        _Tab.cart,
        badge: _cartQty,
        centerBump: slot == MenuBottomNavSlot.centerBump,
      ),
      btn(
        'طلباتي',
        Icons.receipt_long_outlined,
        Icons.receipt_long,
        _Tab.orders,
        badge: _orders.length,
      ),
    ];

    BoxDecoration deco;
    EdgeInsetsGeometry pad;
    EdgeInsetsGeometry? outerPad;

    switch (slot) {
      case MenuBottomNavSlot.materialLabeled:
      case MenuBottomNavSlot.deliverySolid:
      case MenuBottomNavSlot.exploreIcons:
      case MenuBottomNavSlot.activeTopLine:
      case MenuBottomNavSlot.minimalHairline:
      case MenuBottomNavSlot.centerBump:
        deco = BoxDecoration(
          color: barBg,
          border: Border(
            top: BorderSide(
              color: text.withValues(alpha: slot == MenuBottomNavSlot.minimalHairline ? 0.08 : 0.12),
              width: slot == MenuBottomNavSlot.deliverySolid ? 1.5 : 1,
            ),
          ),
        );
        pad = EdgeInsets.symmetric(
          vertical: slot == MenuBottomNavSlot.deliverySolid ? 8 : 4,
        );
      case MenuBottomNavSlot.iosFrost:
        deco = BoxDecoration(
          color: Color.lerp(bg, Colors.white, 0.55)!.withValues(alpha: 0.92),
          border: Border(
            top: BorderSide(color: text.withValues(alpha: 0.1)),
          ),
        );
        pad = const EdgeInsets.symmetric(vertical: 6);
      case MenuBottomNavSlot.guestIsland:
        deco = BoxDecoration(
          color: barBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: text.withValues(alpha: 0.1)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        );
        pad = const EdgeInsets.symmetric(vertical: 6, horizontal: 4);
        outerPad = const EdgeInsetsDirectional.fromSTEB(10, 0, 10, 10);
      case MenuBottomNavSlot.nightPill:
        deco = BoxDecoration(
          color: const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(22),
          border: const Border(top: BorderSide(color: Color(0xFF282828))),
        );
        pad = const EdgeInsets.fromLTRB(4, 14, 4, 8);
        outerPad = const EdgeInsetsDirectional.fromSTEB(10, 0, 10, 10);
      case MenuBottomNavSlot.segmentCapsule:
        deco = BoxDecoration(
          color: text.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: text.withValues(alpha: 0.1)),
        );
        pad = const EdgeInsets.symmetric(vertical: 4, horizontal: 4);
        outerPad = const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12);
      case MenuBottomNavSlot.animatedBubble:
      case MenuBottomNavSlot.liquidDip:
      case MenuBottomNavSlot.ideatePill:
      case MenuBottomNavSlot.greenCircleBar:
      case MenuBottomNavSlot.greenArcDock:
      case MenuBottomNavSlot.glassBridge:
      case MenuBottomNavSlot.glassExpandLabel:
      case MenuBottomNavSlot.glassCircleActive:
      case MenuBottomNavSlot.glassArcGlow:
      case MenuBottomNavSlot.animatedCradle:
      case MenuBottomNavSlot.beatfyDark:
      case MenuBottomNavSlot.beatfyIcons:
        // يُعالَج مبكراً
        deco = const BoxDecoration();
        pad = EdgeInsets.zero;
    }

    final bar = DecoratedBox(
      decoration: deco,
      child: Padding(
        padding: pad,
        child: Row(children: kids),
      ),
    );

    if (outerPad == null) return bar;
    return Padding(padding: outerPad, child: bar);
  }

  /// فقاعة برتقالية عائمة + حفرة بيضاء — من Figma Animated Navigation Bar.
  Widget _animatedBubbleNav(String font, Color accent) {
    const orange = Color(0xFFFF6B00);
    final tabs = <(_Tab, IconData, IconData, int)>[
      (_Tab.home, Icons.home_outlined, Icons.home_rounded, 0),
      (_Tab.cart, Icons.shopping_bag_outlined, Icons.shopping_bag, _cartQty),
      (_Tab.orders, Icons.receipt_long_outlined, Icons.receipt_long, _orders.length),
    ];
    final activeIndex = tabs.indexWhere((e) => e.$1 == _tab).clamp(0, 2);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 10),
      child: SizedBox(
        height: 64,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final slotW = w / tabs.length;
            final rtl =
                Directionality.of(context) == TextDirection.rtl;
            final visualIndex =
                rtl ? (tabs.length - 1 - activeIndex) : activeIndex;
            final cx = slotW * (visualIndex + 0.5);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 52,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    child: CustomPaint(
                      painter: _PreviewOrangeBubblePainter(
                        notchCenterX: cx,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 52,
                  child: Row(
                    children: [
                      for (var i = 0; i < tabs.length; i++)
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() {
                              _tab = tabs[i].$1;
                              _toast = null;
                            }),
                            child: Center(
                              child: i == activeIndex
                                  ? const SizedBox(height: 24)
                                  : Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Icon(
                                          tabs[i].$2,
                                          size: 22,
                                          color: Colors.white70,
                                        ),
                                        if (tabs[i].$4 > 0)
                                          PositionedDirectional(
                                            top: -6,
                                            end: -10,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: accent,
                                                borderRadius:
                                                    BorderRadius.circular(99),
                                              ),
                                              child: Text(
                                                '${tabs[i].$4}',
                                                style: TextStyle(
                                                  fontFamily: font,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w900,
                                                  color: const Color(0xFF0F172A),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  left: cx - 24,
                  top: 0,
                  child: Material(
                    color: orange,
                    shape: const CircleBorder(),
                    elevation: 4,
                    shadowColor: orange.withValues(alpha: 0.5),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {},
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(
                          tabs[activeIndex].$3,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// جيب منحني علوي + فقاعة برتقالية — من Figma Junii Mobile Nav.
  Widget _liquidDipNav(String font, Color accent) {
    const orange = Color(0xFFFF6B00);
    final tabs = <(_Tab, IconData, IconData, int)>[
      (_Tab.home, Icons.home_outlined, Icons.home_rounded, 0),
      (_Tab.cart, Icons.shopping_bag_outlined, Icons.shopping_bag, _cartQty),
      (_Tab.orders, Icons.receipt_long_outlined, Icons.receipt_long, _orders.length),
    ];
    final activeIndex = tabs.indexWhere((e) => e.$1 == _tab).clamp(0, 2);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 10),
      child: SizedBox(
        height: 68,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final slotW = w / tabs.length;
            final rtl = Directionality.of(context) == TextDirection.rtl;
            final visualIndex =
                rtl ? (tabs.length - 1 - activeIndex) : activeIndex;
            final cx = slotW * (visualIndex + 0.5);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 56,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: CustomPaint(
                      painter: _PreviewLiquidDipPainter(dipCenterX: cx),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 56,
                  child: Row(
                    children: [
                      for (var i = 0; i < tabs.length; i++)
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() {
                              _tab = tabs[i].$1;
                              _toast = null;
                            }),
                            child: Center(
                              child: i == activeIndex
                                  ? const SizedBox(height: 24)
                                  : Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Icon(
                                          tabs[i].$2,
                                          size: 22,
                                          color: Colors.white70,
                                        ),
                                        if (tabs[i].$4 > 0)
                                          PositionedDirectional(
                                            top: -6,
                                            end: -10,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: accent,
                                                borderRadius:
                                                    BorderRadius.circular(99),
                                              ),
                                              child: Text(
                                                '${tabs[i].$4}',
                                                style: TextStyle(
                                                  fontFamily: font,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w900,
                                                  color: const Color(0xFF0F172A),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  left: cx - 24,
                  top: 4,
                  child: Material(
                    color: orange,
                    shape: const CircleBorder(),
                    elevation: 6,
                    shadowColor: orange.withValues(alpha: 0.45),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(
                        tabs[activeIndex].$3,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// شريط أزرق + كبسولة بيضاء منزلقة — Ideate Design Figma.
  Widget _ideatePillNav(String font) {
    const blue = Color(0xFF5B6CFF);
    final tabs = <(_Tab, String, IconData, IconData, int)>[
      (_Tab.home, 'الرئيسية', Icons.home_outlined, Icons.home_rounded, 0),
      (_Tab.cart, 'السلة', Icons.shopping_bag_outlined, Icons.shopping_bag, _cartQty),
      (_Tab.orders, 'طلباتي', Icons.receipt_long_outlined, Icons.receipt_long, _orders.length),
    ];
    final activeIndex = tabs.indexWhere((e) => e.$1 == _tab).clamp(0, 2);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          const barPad = 6.0;
          const barH = 56.0;
          final innerW = w - barPad * 2;
          final slotW = innerW / tabs.length;
          final rtl = Directionality.of(context) == TextDirection.rtl;
          final visualIndex =
              rtl ? (tabs.length - 1 - activeIndex) : activeIndex;
          final pillW = slotW * 1.55;
          final pillLeft = barPad + slotW * visualIndex + (slotW - pillW) / 2;

          return SizedBox(
            height: barH,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: blue,
                    borderRadius: BorderRadius.circular(barH / 2),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  left: pillLeft,
                  top: barPad,
                  bottom: barPad,
                  width: pillW,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular((barH - barPad * 2) / 2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: barPad),
                  child: Row(
                    children: [
                      for (var i = 0; i < tabs.length; i++)
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() {
                              _tab = tabs[i].$1;
                              _toast = null;
                            }),
                            borderRadius: BorderRadius.circular(99),
                            child: SizedBox(
                              height: barH - barPad * 2,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Icon(
                                          i == activeIndex
                                              ? tabs[i].$4
                                              : tabs[i].$3,
                                          size: 22,
                                          color: i == activeIndex
                                              ? blue
                                              : Colors.white.withValues(alpha: 0.78),
                                        ),
                                        if (tabs[i].$5 > 0 && i != activeIndex)
                                          PositionedDirectional(
                                            top: -6,
                                            end: -10,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(99),
                                              ),
                                              child: Text(
                                                '${tabs[i].$5}',
                                                style: TextStyle(
                                                  fontFamily: font,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w900,
                                                  color: blue,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (i == activeIndex) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        tabs[i].$2,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: font,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: blue,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// شريط أخضر + أزرار دائرية — Navigation App Figma.
  Widget _greenCircleBarNav(String font) {
    const barGreen = Color(0xFF1A5636);
    const btnGreen = Color(0xFF2F9E62);
    const btnActive = Color(0xFF3DDB84);
    final tabs = <(_Tab, IconData, IconData, int)>[
      (_Tab.home, Icons.home_outlined, Icons.home_rounded, 0),
      (_Tab.cart, Icons.shopping_bag_outlined, Icons.shopping_bag, _cartQty),
      (_Tab.orders, Icons.receipt_long_outlined, Icons.receipt_long, _orders.length),
    ];

    return ColoredBox(
      color: barGreen,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final t in tabs)
                _greenCircleBtn(
                  font: font,
                  tab: t.$1,
                  outlined: t.$2,
                  filled: t.$3,
                  badge: t.$4,
                  active: _tab == t.$1,
                  btnGreen: btnGreen,
                  btnActive: btnActive,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _greenCircleBtn({
    required String font,
    required _Tab tab,
    required IconData outlined,
    required IconData filled,
    required int badge,
    required bool active,
    required Color btnGreen,
    required Color btnActive,
  }) {
    return InkWell(
      onTap: () => setState(() {
        _tab = tab;
        _toast = null;
      }),
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: active ? 52 : 48,
        height: active ? 52 : 48,
        decoration: BoxDecoration(
          color: active ? btnActive : btnGreen,
          shape: BoxShape.circle,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: btnActive.withValues(alpha: 0.45),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(active ? filled : outlined, size: 24, color: Colors.white),
            if (badge > 0)
              PositionedDirectional(
                top: -2,
                end: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$badge',
                    style: TextStyle(
                      fontFamily: font,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: btnGreen,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// قوس أخضر عائم — Navigation App Figma.
  Widget _greenArcDockNav(String font) {
    const btnGreen = Color(0xFF2F9E62);
    const btnActive = Color(0xFF3DDB84);
    final tabs = <(_Tab, IconData, IconData, int)>[
      (_Tab.home, Icons.home_outlined, Icons.home_rounded, 0),
      (_Tab.cart, Icons.shopping_bag_outlined, Icons.shopping_bag, _cartQty),
      (_Tab.orders, Icons.receipt_long_outlined, Icons.receipt_long, _orders.length),
    ];
    final activeIndex = tabs.indexWhere((e) => e.$1 == _tab).clamp(0, 2);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 88,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final rtl = Directionality.of(context) == TextDirection.rtl;
            final positions = rtl
                ? [w * 0.82, w * 0.5, w * 0.18]
                : [w * 0.18, w * 0.5, w * 0.82];
            final bottoms = [8.0, 28.0, 8.0];
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                Positioned(
                  left: w * 0.12,
                  right: w * 0.12,
                  bottom: 0,
                  height: 52,
                  child: CustomPaint(
                    painter: const _PreviewGreenArcDockPainter(),
                  ),
                ),
                for (var i = 0; i < tabs.length; i++)
                  Positioned(
                    left: positions[i] - (i == 1 ? 26 : 22),
                    bottom: bottoms[i],
                    child: _greenCircleBtn(
                      font: font,
                      tab: tabs[i].$1,
                      outlined: tabs[i].$2,
                      filled: tabs[i].$3,
                      badge: tabs[i].$4,
                      active: i == activeIndex,
                      btnGreen: btnGreen,
                      btnActive: btnActive,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Modern Bottom Nav Pack — جسر زجاجي ومتغيراته.
  Widget _modernGlassNav(String font, MenuBottomNavSlot slot) {
    const purple = Color(0xFF7C3AED);
    const glass = Color(0xCC1E1B2E);
    final expand = slot == MenuBottomNavSlot.glassExpandLabel;
    final circle = slot == MenuBottomNavSlot.glassCircleActive;
    final arc = slot == MenuBottomNavSlot.glassArcGlow;
    final tabs = <(_Tab, String, IconData, IconData, int)>[
      (_Tab.home, 'الرئيسية', Icons.home_outlined, Icons.home_rounded, 0),
      (_Tab.cart, 'السلة', Icons.shopping_bag_outlined, Icons.shopping_bag, _cartQty),
      (_Tab.orders, 'طلباتي', Icons.receipt_long_outlined, Icons.receipt_long, _orders.length),
    ];

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: glass,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            for (final t in tabs)
              Expanded(
                flex: expand && _tab == t.$1 ? 18 : 10,
                child: InkWell(
                  onTap: () => setState(() {
                    _tab = t.$1;
                    _toast = null;
                  }),
                  borderRadius: BorderRadius.circular(99),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.symmetric(
                      horizontal: expand && _tab == t.$1 ? 12 : 6,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _tab == t.$1
                          ? (expand
                              ? purple
                              : (circle
                                  ? Colors.white
                                  : (arc
                                      ? purple.withValues(alpha: 0.22)
                                      : Colors.white.withValues(alpha: 0.08))))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: _tab == t.$1 && (expand || arc)
                          ? [
                              BoxShadow(
                                color: purple.withValues(alpha: 0.4),
                                blurRadius: 12,
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (arc && _tab == t.$1)
                          Container(
                            width: 22,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: purple,
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: [
                                BoxShadow(
                                  color: purple.withValues(alpha: 0.7),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Icon(
                                    _tab == t.$1 ? t.$4 : t.$3,
                                    size: 22,
                                    color: _tab == t.$1
                                        ? (circle ? purple : Colors.white)
                                        : Colors.white70,
                                  ),
                                  if (t.$5 > 0)
                                    PositionedDirectional(
                                      top: -6,
                                      end: -10,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: purple,
                                          borderRadius: BorderRadius.circular(99),
                                        ),
                                        child: Text(
                                          '${t.$5}',
                                          style: TextStyle(
                                            fontFamily: font,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (expand && _tab == t.$1) ...[
                                const SizedBox(width: 6),
                                Text(
                                  t.$2,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: font,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// مهد متحرك + دائرة برتقالية — Animated Menu for Mobile App Figma.
  Widget _animatedCradleNav(String font, Color accent) {
    const orange = Color(0xFFFF8A00);
    final tabs = <(_Tab, IconData, IconData, int)>[
      (_Tab.home, Icons.home_outlined, Icons.home_rounded, 0),
      (_Tab.cart, Icons.shopping_bag_outlined, Icons.shopping_bag, _cartQty),
      (_Tab.orders, Icons.receipt_long_outlined, Icons.receipt_long, _orders.length),
    ];
    final activeIndex = tabs.indexWhere((e) => e.$1 == _tab).clamp(0, 2);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 10),
      child: SizedBox(
        height: 72,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final slotW = w / tabs.length;
            final rtl = Directionality.of(context) == TextDirection.rtl;
            final visualIndex =
                rtl ? (tabs.length - 1 - activeIndex) : activeIndex;
            final cx = slotW * (visualIndex + 0.5);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 56,
                  child: CustomPaint(
                    painter: _PreviewAnimatedCradlePainter(cradleCenterX: cx),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 56,
                  child: Row(
                    children: [
                      for (var i = 0; i < tabs.length; i++)
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() {
                              _tab = tabs[i].$1;
                              _toast = null;
                            }),
                            child: Center(
                              child: i == activeIndex
                                  ? const SizedBox(height: 24)
                                  : Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Icon(
                                          tabs[i].$2,
                                          size: 22,
                                          color: Colors.white70,
                                        ),
                                        if (tabs[i].$4 > 0)
                                          PositionedDirectional(
                                            top: -6,
                                            end: -10,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: accent,
                                                borderRadius:
                                                    BorderRadius.circular(99),
                                              ),
                                              child: Text(
                                                '${tabs[i].$4}',
                                                style: TextStyle(
                                                  fontFamily: font,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w900,
                                                  color: const Color(0xFF0F172A),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  left: cx - 24,
                  top: 2,
                  child: Material(
                    color: orange,
                    shape: const CircleBorder(),
                    elevation: 6,
                    shadowColor: orange.withValues(alpha: 0.5),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(
                        tabs[activeIndex].$3,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Beatfy / Navigation Bar variations — شريط داكن أفقي.
  Widget _beatfyNav(String font, {required bool iconsOnly}) {
    const bg = Color(0xFF111111);
    const cyan = Color(0xFF7DD3FC);
    const gold = Color(0xFFE8C547);
    final tabs = <(_Tab, String, IconData, IconData, int)>[
      (_Tab.home, 'الرئيسية', Icons.home_outlined, Icons.home_rounded, 0),
      (_Tab.cart, 'السلة', Icons.shopping_bag_outlined, Icons.shopping_bag, _cartQty),
      (_Tab.orders, 'طلباتي', Icons.receipt_long_outlined, Icons.receipt_long, _orders.length),
    ];

    return ColoredBox(
      color: bg,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              for (final t in tabs)
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() {
                      _tab = t.$1;
                      _toast = null;
                    }),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _tab == t.$1
                            ? cyan.withValues(alpha: 0.16)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                _tab == t.$1 ? t.$4 : t.$3,
                                size: iconsOnly ? 24 : 22,
                                color: _tab == t.$1 ? cyan : Colors.white70,
                              ),
                              if (t.$5 > 0)
                                PositionedDirectional(
                                  top: -6,
                                  end: -10,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: gold,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Text(
                                      '${t.$5}',
                                      style: TextStyle(
                                        fontFamily: font,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        color: const Color(0xFF111111),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (!iconsOnly) ...[
                            const SizedBox(height: 4),
                            Text(
                              t.$2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: font,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _tab == t.$1 ? gold : Colors.white60,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _motionWrap(Widget child, int index) {
    final motion = widget.theme.motionSlot;
    if (motion == MenuMotionSlot.none) return child;
    final rtl = widget.theme.menuLanguage != RestaurantMenuLanguage.en;
    final base = widget.theme.motionDurationMs;
    final stagger = (index * widget.theme.motionStaggerMs).clamp(0, 320);
    // منحنى خطي على الـ tween حتى تبقى t دائماً ضمن 0…1
    // (easeOutBack / elasticOut تتجاوز 1 وتكسر Opacity).
    return TweenAnimationBuilder<double>(
      key: ValueKey(
        'm-${motion.name}-$base-$stagger-$index-${widget.theme.homeLayoutSlot.name}',
      ),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: base + stagger),
      curve: Curves.linear,
      builder: (context, raw, c) {
        final t = raw.clamp(0.0, 1.0);
        // Opacity يجب أن يبقى دائماً ضمن 0…1 حتى مع منحنيات overshoot على المقياس.
        final fade = Curves.easeOutCubic.transform(t).clamp(0.0, 1.0);
        switch (motion) {
          case MenuMotionSlot.none:
            return c!;
          case MenuMotionSlot.fade:
            return Opacity(opacity: fade, child: c);
          case MenuMotionSlot.fromInlineStart:
            final dx = (1 - fade) * 14 * (rtl ? 1 : -1);
            return Opacity(
              opacity: fade,
              child: Transform.translate(offset: Offset(dx, 0), child: c),
            );
          case MenuMotionSlot.fromInlineEnd:
            final dx = (1 - fade) * 14 * (rtl ? -1 : 1);
            return Opacity(
              opacity: fade,
              child: Transform.translate(offset: Offset(dx, 0), child: c),
            );
          case MenuMotionSlot.fromBottom:
            return Opacity(
              opacity: fade,
              child: Transform.translate(
                offset: Offset(0, (1 - fade) * 16),
                child: c,
              ),
            );
          case MenuMotionSlot.staggerRise:
            return Opacity(
              opacity: fade,
              child: Transform.translate(
                offset: Offset(0, (1 - fade) * 28),
                child: c,
              ),
            );
          case MenuMotionSlot.scalePop:
            // overshoot على المقياس فقط — الشفافية مقيّدة
            final scaleT = Curves.easeOutBack.transform(t).clamp(0.0, 1.25);
            final s = 0.86 + (0.14 * scaleT);
            return Opacity(
              opacity: fade,
              child: Transform.scale(scale: s, child: c),
            );
          case MenuMotionSlot.softZoom:
            final s = 1.08 - (0.08 * fade);
            return Opacity(
              opacity: fade,
              child: Transform.scale(scale: s, child: c),
            );
          case MenuMotionSlot.springPop:
            final bounce = Curves.elasticOut.transform(t).clamp(0.0, 1.35);
            final s = 0.78 + (0.22 * bounce);
            return Opacity(
              opacity: fade,
              child: Transform.scale(scale: s, child: c),
            );
          case MenuMotionSlot.swipeTilt:
            final dx = (1 - fade) * 22 * (rtl ? 1 : -1);
            final tilt = (1 - fade) * 0.06 * (rtl ? -1 : 1);
            return Opacity(
              opacity: fade,
              child: Transform.translate(
                offset: Offset(dx, (1 - fade) * 8),
                child: Transform.rotate(angle: tilt, child: c),
              ),
            );
        }
      },
      child: child,
    );
  }

  Widget? _priceLabel(
    String font,
    Color accent, {
    required int priceFils,
    double fontSize = 12,
  }) {
    if (!(widget.theme.toggles['show_prices'] ?? true)) return null;
    return Text(
      RestaurantMoney.formatFils(priceFils),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: font,
        fontWeight: FontWeight.w800,
        color: accent,
        fontSize: fontSize,
        height: 1.15,
      ),
    );
  }

  IconData _catIcon(String name) {
    switch (name) {
      case 'أطباق':
        return Icons.restaurant_outlined;
      case 'مشروبات':
        return Icons.local_cafe_outlined;
      case 'حلويات':
        return Icons.cake_outlined;
      default:
        return Icons.grid_view_rounded;
    }
  }

  Widget _categoryBar(
    String font,
    Color text,
    Color accent,
    Color bg,
    MenuCategoryNavSlot slot,
  ) {
    if (slot == MenuCategoryNavSlot.hidden) return const SizedBox.shrink();

    Widget chip(String c, {required bool ring}) {
      final on = _cat == c;
      if (ring) {
        return InkWell(
          onTap: () => setState(() => _cat = c),
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            width: 64,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on
                        ? accent
                        : text.withValues(alpha: 0.08),
                    border: Border.all(
                      color: on
                          ? accent
                          : text.withValues(alpha: 0.12),
                      width: on ? 2 : 1,
                    ),
                  ),
                  child: Icon(
                    _catIcon(c),
                    size: 22,
                    color: on ? Colors.white : text.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  c,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: font,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: on ? accent : text.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      final label = Text(
        c,
        style: TextStyle(
          fontFamily: font,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: on
              ? (slot == MenuCategoryNavSlot.topUnderline
                  ? text
                  : bg)
              : text.withValues(alpha: 0.65),
        ),
      );

      switch (slot) {
        case MenuCategoryNavSlot.topUnderline:
        case MenuCategoryNavSlot.stickyBanner:
          return InkWell(
            onTap: () => setState(() => _cat = c),
            child: Container(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: on ? accent : Colors.transparent,
                    width: 2.5,
                  ),
                ),
              ),
              child: label,
            ),
          );
        case MenuCategoryNavSlot.topSegmented:
          return Expanded(
            child: InkWell(
              onTap: () => setState(() => _cat = c),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: on ? accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  c,
                  style: TextStyle(
                    fontFamily: font,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: on ? bg : text.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ),
          );
        case MenuCategoryNavSlot.sideRailStart:
        case MenuCategoryNavSlot.sideRailEnd:
          return InkWell(
            onTap: () => setState(() => _cat = c),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 8,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(
                    color: on ? accent : Colors.transparent,
                    width: 3,
                  ),
                ),
                color: on ? accent.withValues(alpha: 0.12) : null,
              ),
              child: Text(
                c,
                style: TextStyle(
                  fontFamily: font,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: on ? accent : text.withValues(alpha: 0.65),
                ),
              ),
            ),
          );
        default:
          return Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: ChoiceChip(
              label: label,
              selected: on,
              selectedColor: accent,
              backgroundColor: text.withValues(alpha: 0.06),
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _cat = c),
            ),
          );
      }
    }

    switch (slot) {
      case MenuCategoryNavSlot.hidden:
        return const SizedBox.shrink();
      case MenuCategoryNavSlot.iconRing:
        return SizedBox(
          height: 78,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _cats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => chip(_cats[i], ring: true),
          ),
        );
      case MenuCategoryNavSlot.wrapChips:
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in _cats) chip(c, ring: false),
          ],
        );
      case MenuCategoryNavSlot.topSegmented:
        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: text.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              for (final c in _cats) chip(c, ring: false),
            ],
          ),
        );
      case MenuCategoryNavSlot.floatingPills:
        return Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 6,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(color: text.withValues(alpha: 0.08)),
          ),
          child: SizedBox(
            height: 34,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _cats.length,
              itemBuilder: (_, i) => chip(_cats[i], ring: false),
            ),
          ),
        );
      case MenuCategoryNavSlot.stickyBanner:
        return Container(
          width: double.infinity,
          padding: const EdgeInsetsDirectional.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: text.withValues(alpha: 0.04),
            border: Border(
              bottom: BorderSide(color: text.withValues(alpha: 0.1)),
            ),
          ),
          child: SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _cats.length,
              itemBuilder: (_, i) => chip(_cats[i], ring: false),
            ),
          ),
        );
      case MenuCategoryNavSlot.sideRailStart:
      case MenuCategoryNavSlot.sideRailEnd:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in _cats) chip(c, ring: false),
          ],
        );
      case MenuCategoryNavSlot.topUnderline:
      case MenuCategoryNavSlot.topPills:
        return SizedBox(
          height: slot == MenuCategoryNavSlot.topUnderline ? 40 : 34,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _cats.length,
            itemBuilder: (_, i) => chip(_cats[i], ring: false),
          ),
        );
    }
  }

  Widget _home(
    String font,
    Color text,
    Color accent,
    Color primary,
    Color bg,
    RestaurantMenuChrome chrome,
  ) {
    final list = _filtered;
    final initial = () {
      final n = (_nickname.text.trim().isNotEmpty
              ? _nickname.text
              : _name.text)
          .trim();
      return n.isEmpty ? '؟' : n.substring(0, 1);
    }();

    Widget searchRow() {
      final inputs = MenuContrastInputTokens.fromTheme(bg: bg, text: text);
      final searchStyle = widget.theme.searchStyleSlot;
      final showLogo = widget.theme.toggles['show_logo_in_header'] ?? true;
      final catSlot = widget.theme.categoryNavSlot;
      final showCatsInline = catSlot != MenuCategoryNavSlot.hidden &&
          !catSlot.isSideRail;
      final displayName =
          (widget.theme.identity['display_name_ar'] ?? '').trim();
      final title = displayName.isEmpty ? 'المنيو' : displayName;
      final tagline =
          (widget.theme.identity['tagline_ar'] ?? '').trim();
      final logoImg =
          showLogo ? _brandImage(widget.theme.identity['logo_url']) : null;
      final coverImg = _brandImage(widget.theme.identity['cover_url']);

      InputBorder enabledBorder;
      InputBorder focusedBorder;
      EdgeInsetsGeometry contentPad;
      double radius;
      Color fillColor = inputs.fill;
      Color inkColor = inputs.ink;
      Widget? prefixIcon;
      Widget? suffixAction;
      Widget? leadingAction;
      Widget? fieldSuffixIcon;
      List<BoxShadow>? fieldShadow;
      var filled = true;
      final iconColor = text.withValues(alpha: 0.45);

      // أنماط من منصات حقيقية — انظر MenuSearchStyleSlot.inspiredBy
      switch (searchStyle) {
        case MenuSearchStyleSlot.materialFill:
          // Material Design persistent search
          radius = 28;
          fillColor = text.withValues(alpha: 0.08);
          prefixIcon = Icon(Icons.search, size: 20, color: iconColor);
          contentPad = const EdgeInsetsDirectional.fromSTEB(4, 12, 14, 12);
          enabledBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide.none,
          );
          focusedBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide(color: accent.withValues(alpha: 0.5)),
          );
        case MenuSearchStyleSlot.iosCapsule:
          // Apple HIG search field
          radius = 10;
          fillColor = const Color(0x14767680); // systemGray5-ish
          if (ThemeData.estimateBrightnessForColor(bg) == Brightness.dark) {
            fillColor = Colors.white.withValues(alpha: 0.12);
          }
          prefixIcon = Icon(Icons.search, size: 18, color: iconColor);
          contentPad = const EdgeInsetsDirectional.fromSTEB(4, 10, 12, 10);
          enabledBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide.none,
          );
          focusedBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide(color: accent.withValues(alpha: 0.4)),
          );
        case MenuSearchStyleSlot.deliveryBar:
          // Uber Eats / DoorDash / Deliveroo
          radius = 12;
          fillColor = inputs.fill;
          prefixIcon = Icon(Icons.search, size: 20, color: iconColor);
          contentPad = const EdgeInsetsDirectional.fromSTEB(4, 12, 12, 12);
          enabledBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide(color: text.withValues(alpha: 0.14)),
          );
          focusedBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide(color: accent, width: 1.5),
          );
        case MenuSearchStyleSlot.storeBar:
          // Figma Kit: field + circular search button
          radius = 8;
          prefixIcon = Icon(Icons.search, size: 20, color: iconColor);
          contentPad = const EdgeInsetsDirectional.fromSTEB(4, 11, 8, 11);
          enabledBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide(color: text.withValues(alpha: 0.28), width: 1.5),
          );
          focusedBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide(color: accent, width: 2),
          );
          suffixAction = Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: Material(
              color: const Color(0xFF2F80ED),
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                onTap: () {},
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.search, size: 20, color: Colors.white),
                ),
              ),
            ),
          );
        case MenuSearchStyleSlot.exploreBar:
          // Figma Kit: search + microphone
          radius = 10;
          fillColor = text.withValues(alpha: 0.1);
          prefixIcon = Icon(Icons.search, size: 18, color: iconColor);
          contentPad = const EdgeInsetsDirectional.fromSTEB(2, 9, 4, 9);
          enabledBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide.none,
          );
          focusedBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide.none,
          );
          fieldSuffixIcon = IconButton(
            onPressed: () => setState(() => _toast = 'بحث صوتي قريباً'),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(Icons.mic_none_rounded, size: 22, color: iconColor),
            tooltip: 'بحث صوتي',
          );
        case MenuSearchStyleSlot.nightBar:
          // Spotify-like dark elevated search
          radius = 8;
          fillColor = const Color(0xFF242424);
          inkColor = const Color(0xFFF5F5F5);
          prefixIcon = const Icon(Icons.search, size: 20, color: Color(0xFFB3B3B3));
          contentPad = const EdgeInsetsDirectional.fromSTEB(4, 12, 14, 12);
          fieldShadow = [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ];
          enabledBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide.none,
          );
          focusedBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide(color: accent.withValues(alpha: 0.7)),
          );
        case MenuSearchStyleSlot.guestPill:
          // Airbnb search pill
          radius = 999;
          fillColor = inputs.fill;
          prefixIcon = Icon(Icons.search, size: 20, color: iconColor);
          contentPad = const EdgeInsetsDirectional.fromSTEB(6, 12, 16, 12);
          fieldShadow = [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ];
          enabledBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide(color: text.withValues(alpha: 0.08)),
          );
          focusedBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide(color: accent, width: 1.5),
          );
        case MenuSearchStyleSlot.searchAndFilter:
          // Figma Kit: category dropdown + search field
          radius = 12;
          fillColor = inputs.fill;
          prefixIcon = Icon(Icons.search, size: 20, color: iconColor);
          contentPad = const EdgeInsetsDirectional.fromSTEB(4, 12, 12, 12);
          enabledBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide(color: text.withValues(alpha: 0.14)),
          );
          focusedBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide(color: accent, width: 1.5),
          );
          leadingAction = Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Material(
              color: inputs.fill,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: text.withValues(alpha: 0.18)),
              ),
              child: InkWell(
                onTap: () => setState(() => _toast = 'تصفية حسب التصنيف'),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'الكل',
                        style: TextStyle(
                          fontFamily: font,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: text,
                        ),
                      ),
                      Icon(Icons.expand_more, size: 18, color: iconColor),
                    ],
                  ),
                ),
              ),
            ),
          );
        case MenuSearchStyleSlot.stickyDock:
          // Full-width sticky primary search
          radius = 0;
          fillColor = Color.lerp(bg, text, 0.06)!;
          prefixIcon = Icon(Icons.search, size: 22, color: iconColor);
          contentPad = const EdgeInsetsDirectional.fromSTEB(4, 14, 16, 14);
          enabledBorder = InputBorder.none;
          focusedBorder = UnderlineInputBorder(
            borderSide: BorderSide(color: accent, width: 2),
          );
        case MenuSearchStyleSlot.editorialLine:
          // Fine dining / Apple inline
          radius = 0;
          filled = false;
          fillColor = Colors.transparent;
          prefixIcon = Icon(Icons.search, size: 18, color: iconColor);
          contentPad = const EdgeInsetsDirectional.fromSTEB(0, 10, 4, 10);
          enabledBorder = UnderlineInputBorder(
            borderSide: BorderSide(color: text.withValues(alpha: 0.25), width: 1),
          );
          focusedBorder = UnderlineInputBorder(
            borderSide: BorderSide(color: accent, width: 2),
          );
      }

      Widget searchField = TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        style: TextStyle(
          fontFamily: font,
          color: inkColor,
          fontSize: 13,
        ),
        decoration: InputDecoration(
          hintText: 'ابحث عن طبق أو مشروب…',
          hintStyle: TextStyle(
            fontFamily: font,
            color: searchStyle == MenuSearchStyleSlot.nightBar
                ? const Color(0xFFB3B3B3)
                : inputs.placeholder,
          ),
          isDense: true,
          filled: filled,
          fillColor: fillColor,
          prefixIcon: prefixIcon,
          suffixIcon: fieldSuffixIcon,
          prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          contentPadding: contentPad,
          enabledBorder: enabledBorder,
          focusedBorder: focusedBorder,
        ),
      );

      if (fieldShadow != null) {
        searchField = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius.clamp(0, 99)),
            boxShadow: fieldShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius.clamp(0, 99)),
            child: searchField,
          ),
        );
      }

      if (searchStyle == MenuSearchStyleSlot.stickyDock) {
        searchField = ColoredBox(
          color: fillColor,
          child: searchField,
        );
      }

      final monogram = Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          title.isEmpty ? 'م' : title.substring(0, 1),
          style: TextStyle(
            fontFamily: font,
            fontWeight: FontWeight.w900,
            color: bg,
            fontSize: 16,
          ),
        ),
      );

      final brandMark = showLogo
          ? (logoImg != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(width: 36, height: 36, child: logoImg),
                )
              : monogram)
          : null;

      final logoAlign = widget.theme.brandLogoAlign;
      final textPlacement = widget.theme.brandTextPlacement;
      final textAlignSlot = widget.theme.brandTextAlign;
      final textCross = switch (textAlignSlot) {
        MenuBrandTextAlign.end => CrossAxisAlignment.end,
        MenuBrandTextAlign.center => CrossAxisAlignment.center,
        MenuBrandTextAlign.start => CrossAxisAlignment.start,
      };
      final textAlign = switch (textAlignSlot) {
        MenuBrandTextAlign.end => TextAlign.end,
        MenuBrandTextAlign.center => TextAlign.center,
        MenuBrandTextAlign.start => TextAlign.start,
      };

      final brandTexts = Column(
        crossAxisAlignment: textCross,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
            style: TextStyle(
              fontFamily: font,
              fontWeight: FontWeight.w900,
              color: text,
              fontSize: 14,
            ),
          ),
          if (tagline.isNotEmpty)
            Text(
              tagline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: textAlign,
              style: TextStyle(
                fontFamily: font,
                fontWeight: FontWeight.w500,
                color: text.withValues(alpha: 0.62),
                fontSize: 11,
              ),
            ),
        ],
      );

      Widget brandHeader() {
        if (brandMark == null) {
          return Align(
            alignment: switch (textAlignSlot) {
              MenuBrandTextAlign.end => AlignmentDirectional.centerEnd,
              MenuBrandTextAlign.center => AlignmentDirectional.center,
              MenuBrandTextAlign.start => AlignmentDirectional.centerStart,
            },
            child: brandTexts,
          );
        }

        if (textPlacement == MenuBrandTextPlacement.under) {
          final colCross = switch (logoAlign) {
            MenuBrandLogoAlign.start => CrossAxisAlignment.start,
            MenuBrandLogoAlign.center => CrossAxisAlignment.center,
            MenuBrandLogoAlign.end => CrossAxisAlignment.end,
          };
          return SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: colCross,
              children: [
                brandMark,
                const SizedBox(height: 8),
                brandTexts,
              ],
            ),
          );
        }

        // بجانب اللوجو
        final gap = const SizedBox(width: 8);
        switch (logoAlign) {
          case MenuBrandLogoAlign.start:
            return Row(
              children: [
                brandMark,
                gap,
                Expanded(child: brandTexts),
              ],
            );
          case MenuBrandLogoAlign.end:
            return Row(
              children: [
                Expanded(child: brandTexts),
                gap,
                brandMark,
              ],
            );
          case MenuBrandLogoAlign.center:
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                brandMark,
                gap,
                Flexible(child: brandTexts),
              ],
            );
        }
      }

      final showCoverHero = coverImg != null &&
          (chrome == RestaurantMenuChrome.heroCover ||
              chrome == RestaurantMenuChrome.coverThenList ||
              chrome == RestaurantMenuChrome.photoStack);

      return Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showCoverHero) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: chrome == RestaurantMenuChrome.heroCover ? 88 : 64,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      coverImg,
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.05),
                              Colors.black.withValues(alpha: 0.45),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ] else
              Container(
                height: 3,
                margin: const EdgeInsetsDirectional.only(bottom: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(colors: [primary, accent]),
                ),
              ),
            brandHeader(),
            const SizedBox(height: 10),
            Row(
              children: [
                if (leadingAction != null) leadingAction,
                Expanded(child: searchField),
                if (suffixAction != null) suffixAction,
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => _profileOpen = true),
                  borderRadius: BorderRadius.circular(99),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: accent.withValues(alpha: 0.2),
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontFamily: font,
                        fontWeight: FontWeight.w900,
                        color: text,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (showCatsInline) ...[
              const SizedBox(height: 10),
              _categoryBar(font, text, accent, bg, catSlot),
            ],
          ],
        ),
      );
    }

    Widget dishTile(_Sample s, {required int index}) {
      Widget buildTile() {

        final img = Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              chrome == RestaurantMenuChrome.editorial ? 0 : 8,
            ),
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [
                accent.withValues(alpha: 0.45),
                text.withValues(alpha: 0.18),
              ],
            ),
          ),
        );

        switch (chrome) {
          case RestaurantMenuChrome.editorial:
          case RestaurantMenuChrome.menuBoard:
            return InkWell(
              onTap: () => setState(() => _detail = s),
              child: Container(
                padding: const EdgeInsetsDirectional.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: text.withValues(alpha: 0.14)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        s.name,
                        style: TextStyle(
                          fontFamily: font,
                          fontWeight: FontWeight.w800,
                          color: text,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    _priceLabel(
                      font,
                      accent,
                      priceFils: s.priceFils,
                      fontSize: 13,
                    ) ?? const SizedBox.shrink(),
                  ],
                ),
              ),
            );
          case RestaurantMenuChrome.paperList:
          case RestaurantMenuChrome.splitRow:
          case RestaurantMenuChrome.sideRail:
          case RestaurantMenuChrome.bannerMenu:
            return Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => _detail = s),
                child: Row(
                  children: [
                    SizedBox(width: 64, height: 64, child: img),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.name,
                            style: TextStyle(
                              fontFamily: font,
                              fontWeight: FontWeight.w800,
                              color: text,
                              fontSize: 13,
                            ),
                          ),
                          _priceLabel(
                      font,
                      accent,
                      priceFils: s.priceFils,
                      fontSize: 12,
                    ) ?? const SizedBox.shrink(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          case RestaurantMenuChrome.photoStack:
          case RestaurantMenuChrome.heroCover:
          case RestaurantMenuChrome.coverThenList:
            final hero = (chrome == RestaurantMenuChrome.heroCover ||
                    chrome == RestaurantMenuChrome.coverThenList) &&
                index == 0;
            if ((chrome == RestaurantMenuChrome.heroCover ||
                    chrome == RestaurantMenuChrome.coverThenList) &&
                !hero) {
              return Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 8),
                child: InkWell(
                  onTap: () => setState(() => _detail = s),
                  child: Row(
                    children: [
                      SizedBox(width: 72, height: 72, child: img),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s.name,
                          style: TextStyle(
                            fontFamily: font,
                            fontWeight: FontWeight.w800,
                            color: text,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      _priceLabel(
                      font,
                      accent,
                      priceFils: s.priceFils,
                      fontSize: 12,
                    ) ?? const SizedBox.shrink(),
                    ],
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 14),
              child: InkWell(
                onTap: () => setState(() => _detail = s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: hero ? 16 / 9 : 4 / 3,
                      child: img,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.name,
                      style: TextStyle(
                        fontFamily: font,
                        fontWeight: FontWeight.w900,
                        color: text,
                        fontSize: hero ? 16 : 14,
                      ),
                    ),
                    _priceLabel(
                      font,
                      accent,
                      priceFils: s.priceFils,
                      fontSize: 12,
                    ) ?? const SizedBox.shrink(),
                  ],
                ),
              ),
            );
          case RestaurantMenuChrome.storyCards:
            return Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 12),
              child: InkWell(
                onTap: () => setState(() => _detail = s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(aspectRatio: 3 / 4, child: img),
                    const SizedBox(height: 8),
                    Text(
                      s.name,
                      style: TextStyle(
                        fontFamily: font,
                        fontWeight: FontWeight.w900,
                        color: text,
                        fontSize: 15,
                      ),
                    ),
                    _priceLabel(
                      font,
                      accent,
                      priceFils: s.priceFils,
                      fontSize: 12,
                    ) ??
                        const SizedBox.shrink(),
                  ],
                ),
              ),
            );
          case RestaurantMenuChrome.appGrid:
          case RestaurantMenuChrome.compactTiles:
          case RestaurantMenuChrome.softCards:
          case RestaurantMenuChrome.magazine:
            final compact = chrome == RestaurantMenuChrome.compactTiles;
            return InkWell(
              onTap: () => setState(() => _detail = s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        chrome == RestaurantMenuChrome.magazine ? 0 : 8,
                      ),
                      child: img,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: font,
                      fontWeight: FontWeight.w800,
                      color: text,
                      fontSize: compact ? 11 : 12,
                      height: 1.15,
                    ),
                  ),
                  if (_priceLabel(
                        font,
                        accent,
                        priceFils: s.priceFils,
                        fontSize: compact ? 11 : 12,
                      )
                      case final price?)
                    price,
                ],
              ),
            );
        }
      }
      return _motionWrap(buildTile(), index);
    }

    final useGrid = chrome == RestaurantMenuChrome.appGrid ||
        chrome == RestaurantMenuChrome.compactTiles ||
        chrome == RestaurantMenuChrome.softCards ||
        chrome == RestaurantMenuChrome.magazine;

    final catSlot = widget.theme.categoryNavSlot;
    final sideRail = catSlot.isSideRail;

    Widget listBody() {
      if (useGrid) {
        final aspect = switch (chrome) {
          RestaurantMenuChrome.compactTiles => 0.82,
          RestaurantMenuChrome.magazine => 0.62,
          _ => 0.72,
        };
        return GridView.builder(
          padding: EdgeInsetsDirectional.fromSTEB(
            sideRail ? 8 : 12,
            sideRail ? 8 : 0,
            sideRail ? 8 : 12,
            8,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing:
                chrome == RestaurantMenuChrome.compactTiles ? 8 : 10,
            crossAxisSpacing:
                chrome == RestaurantMenuChrome.compactTiles ? 8 : 10,
            childAspectRatio: aspect,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) => dishTile(list[i], index: i),
        );
      }
      return ListView.builder(
        padding: EdgeInsetsDirectional.fromSTEB(
          sideRail ? 8 : 12,
          sideRail ? 8 : 0,
          sideRail ? 8 : 12,
          8,
        ),
        itemCount: list.length,
        itemBuilder: (context, i) => dishTile(list[i], index: i),
      );
    }

    if (sideRail) {
      final rail = SizedBox(
        width: 78,
        child: ColoredBox(
          color: text.withValues(alpha: 0.03),
          child: ListView(
            padding: const EdgeInsetsDirectional.only(top: 8),
            children: [
              _categoryBar(font, text, accent, bg, catSlot),
            ],
          ),
        ),
      );
      return Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 34, 12, 8),
            child: searchRow(),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (catSlot == MenuCategoryNavSlot.sideRailStart) rail,
                Expanded(child: listBody()),
                if (catSlot == MenuCategoryNavSlot.sideRailEnd) rail,
              ],
            ),
          ),
        ],
      );
    }

    if (useGrid) {
      final aspect = switch (chrome) {
        RestaurantMenuChrome.compactTiles => 0.82,
        RestaurantMenuChrome.magazine => 0.62,
        _ => 0.72,
      };
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 34, 12, 8),
            sliver: SliverToBoxAdapter(child: searchRow()),
          ),
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing:
                    chrome == RestaurantMenuChrome.compactTiles ? 8 : 10,
                crossAxisSpacing:
                    chrome == RestaurantMenuChrome.compactTiles ? 8 : 10,
                childAspectRatio: aspect,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => dishTile(list[i], index: i),
                childCount: list.length,
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 34, 12, 8),
      itemCount: list.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return searchRow();
        return dishTile(list[i - 1], index: i - 1);
      },
    );
  }

  Widget _detailView(String font, Color text, Color accent) {
    final s = _detail!;
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 28, 12, 12),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () => setState(() => _detail = null),
            child: Text('رجوع', style: TextStyle(fontFamily: font)),
          ),
        ),
        AspectRatio(
          aspectRatio: 4 / 3,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.45),
                  text.withValues(alpha: 0.2),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          s.name,
          style: TextStyle(
            fontFamily: font,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: text,
          ),
        ),
        const SizedBox(height: 6),
        if (widget.theme.toggles['show_item_descriptions'] ?? true)
          Text(
            s.desc,
            style: TextStyle(
              fontFamily: font,
              fontSize: 12,
              height: 1.4,
              color: text.withValues(alpha: 0.65),
            ),
          ),
        const SizedBox(height: 8),
        if (widget.theme.toggles['show_prices'] ?? true)
          Text(
            RestaurantMoney.formatFils(s.priceFils),
            style: TextStyle(
              fontFamily: font,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            _add(s);
            setState(() {
              _detail = null;
              _tab = _Tab.cart;
            });
          },
          style: FilledButton.styleFrom(backgroundColor: accent),
          child: Text(
            'إضافة للسلة',
            style: TextStyle(
              fontFamily: font,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0F172A),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cartView(String font, Color text, Color accent) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: text.withValues(alpha: 0.2)),
    );
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 32, 12, 12),
      children: [
        Text(
          'سلّة الطلب',
          style: TextStyle(
            fontFamily: font,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: text,
          ),
        ),
        const SizedBox(height: 10),
        if (_cart.isEmpty)
          Text(
            'السلة فارغة',
            style: TextStyle(
              fontFamily: font,
              color: text.withValues(alpha: 0.55),
            ),
          )
        else ...[
          for (final line in _cart)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${line.item.name} × ${line.qty}',
                    style: TextStyle(
                      fontFamily: font,
                      fontWeight: FontWeight.w700,
                      color: text,
                      fontSize: 12,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    if (line.qty <= 1) {
                      _cart.remove(line);
                    } else {
                      line.qty -= 1;
                    }
                  }),
                  icon: Icon(Icons.remove, size: 16, color: accent),
                ),
                IconButton(
                  onPressed: () => setState(() => line.qty += 1),
                  icon: Icon(Icons.add, size: 16, color: accent),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            'بيانات التوصيل',
            style: TextStyle(
              fontFamily: font,
              fontWeight: FontWeight.w800,
              color: text,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _name,
            style: TextStyle(fontFamily: font, color: text, fontSize: 12),
            decoration: InputDecoration(
              labelText: 'الاسم',
              border: border,
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _nickname,
            style: TextStyle(fontFamily: font, color: text, fontSize: 12),
            decoration: InputDecoration(
              labelText: 'اللقب / الاسم المستعار',
              border: border,
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            style: TextStyle(fontFamily: font, color: text, fontSize: 12),
            decoration: InputDecoration(
              labelText: 'رقم الهاتف',
              border: border,
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _addr1,
            style: TextStyle(fontFamily: font, color: text, fontSize: 12),
            decoration: InputDecoration(
              labelText: 'العنوان (سطر 1)',
              border: border,
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _addr2,
            style: TextStyle(fontFamily: font, color: text, fontSize: 12),
            decoration: InputDecoration(
              labelText: 'العنوان (سطر 2)',
              border: border,
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _landmark,
            style: TextStyle(fontFamily: font, color: text, fontSize: 12),
            decoration: InputDecoration(
              labelText: 'أقرب نقطة دالة',
              border: border,
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => setState(() {
              _gps = true;
              _toast = 'تم حفظ موقع تجريبي (GPS)';
            }),
            child: Text(
              _gps ? 'تم حفظ موقع GPS' : 'السماح بتحديد موقعي',
              style: TextStyle(fontFamily: font, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _confirm,
            style: FilledButton.styleFrom(backgroundColor: accent),
            child: Text(
              'تأكيد الطلب',
              style: TextStyle(
                fontFamily: font,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _ordersView(String font, Color text, Color accent) {
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 32, 12, 12),
      children: [
        Text(
          'طلباتي',
          style: TextStyle(
            fontFamily: font,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: text,
          ),
        ),
        const SizedBox(height: 10),
        if (_orders.isEmpty)
          Text(
            'لا طلبات بعد — أكّد من السلة أولاً',
            style: TextStyle(
              fontFamily: font,
              color: text.withValues(alpha: 0.55),
              fontSize: 12,
            ),
          )
        else
          for (final o in _orders)
            Container(
              margin: const EdgeInsetsDirectional.only(bottom: 10),
              padding: const EdgeInsetsDirectional.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: text.withValues(alpha: 0.14)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'طلب #${o.id}',
                          style: TextStyle(
                            fontFamily: font,
                            fontWeight: FontWeight.w800,
                            color: text,
                          ),
                        ),
                      ),
                      Text(
                        o.statusAr,
                        style: TextStyle(
                          fontFamily: font,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final line in o.lines)
                    Text(
                      '${line.item.name} × ${line.qty}',
                      style: TextStyle(
                        fontFamily: font,
                        fontSize: 12,
                        color: text.withValues(alpha: 0.75),
                      ),
                    ),
                ],
              ),
            ),
      ],
    );
  }
}

/// رسّام شريط فقاعة متحركة في معاينة المنيو.
class _PreviewOrangeBubblePainter extends CustomPainter {
  _PreviewOrangeBubblePainter({required this.notchCenterX});

  final double notchCenterX;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(r),
      ),
      Paint()..color = const Color(0xFF000000),
    );
    final cx = notchCenterX.clamp(r, size.width - r);
    const dipR = 18.0;
    canvas.drawCircle(Offset(cx, 2), dipR, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(cx, 6),
      dipR - 3.5,
      Paint()..color = const Color(0xFF000000),
    );
  }

  @override
  bool shouldRepaint(covariant _PreviewOrangeBubblePainter old) =>
      old.notchCenterX != notchCenterX;
}

/// رسّام جيب منحني (Junii) في معاينة المنيو.
class _PreviewLiquidDipPainter extends CustomPainter {
  _PreviewLiquidDipPainter({required this.dipCenterX});

  final double dipCenterX;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = h * 0.38;
    final cx = dipCenterX.clamp(r + 28, w - r - 28);
    const dipHalf = 28.0;
    const dipDepth = 18.0;

    final path = Path()
      ..moveTo(r, 0)
      ..lineTo(cx - dipHalf - 10, 0)
      ..cubicTo(
        cx - dipHalf,
        0,
        cx - dipHalf + 4,
        dipDepth,
        cx,
        dipDepth,
      )
      ..cubicTo(
        cx + dipHalf - 4,
        dipDepth,
        cx + dipHalf,
        0,
        cx + dipHalf + 10,
        0,
      )
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF1A1A1A)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _PreviewLiquidDipPainter old) =>
      old.dipCenterX != dipCenterX;
}

/// مهد متحرك في معاينة المنيو — Animated Menu Figma.
class _PreviewAnimatedCradlePainter extends CustomPainter {
  _PreviewAnimatedCradlePainter({required this.cradleCenterX});

  final double cradleCenterX;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = h * 0.28;
    final cx = cradleCenterX.clamp(r + 30, w - r - 30);
    const cradleR = 26.0;

    final path = Path()
      ..moveTo(r, 0)
      ..lineTo(cx - cradleR - 12, 0)
      ..cubicTo(
        cx - cradleR - 2,
        0,
        cx - cradleR,
        cradleR,
        cx,
        cradleR,
      )
      ..cubicTo(
        cx + cradleR,
        cradleR,
        cx + cradleR + 2,
        0,
        cx + cradleR + 12,
        0,
      )
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..close();

    canvas.drawPath(path, Paint()..color = const Color(0xFF000000));
  }

  @override
  bool shouldRepaint(covariant _PreviewAnimatedCradlePainter old) =>
      old.cradleCenterX != cradleCenterX;
}

/// قوس أخضر عائم — Navigation App.
class _PreviewGreenArcDockPainter extends CustomPainter {
  const _PreviewGreenArcDockPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.32)
      ..quadraticBezierTo(w * 0.5, -h * 0.62, w, h * 0.32)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF1A5636));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
