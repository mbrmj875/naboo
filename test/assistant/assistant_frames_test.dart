import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/ui/assistant_chrome.dart';
import 'package:naboo/assistant/ui/assistant_view_models.dart';
import 'package:naboo/utils/theme.dart';

/// إطارات صفحة المساعد السبعة (م2-1) بثيم التطبيق الحقيقي.
///
/// يفحص دائماً أن كل إطار يُرسم بلا تجاوز على الهاتف والحاسبة، فاتحاً وداكناً،
/// وبخط مكبّر. ومع `FRAME_SHOTS_DIR` يحفظ صوراً للمراجعة:
///   FRAME_SHOTS_DIR=/path flutter test test/assistant/assistant_frames_test.dart

Future<void> _loadFonts() async {
  final tajawal = FontLoader('Tajawal');
  for (final f in ['Tajawal-Regular.ttf', 'Tajawal-Bold.ttf']) {
    tajawal.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
  }
  await tajawal.load();
  final sdk = Platform.environment['FLUTTER_ROOT'] ??
      '${Platform.environment['HOME']}/development/flutter';
  final icons = File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await l.load();
  }
}

// ------------------------------------------------------------ بيانات المحل النموذجي
const _stock = AssistantStockCard(
  title: 'المخزون · 5W-30',
  rows: [
    AssistantStockRow(name: 'زيت توتال كوارتز 5W-30 · 4 لتر', qty: 12, unit: 'عبوة', price: '28,000 د.ع'),
    AssistantStockRow(name: 'زيت موبيل سوبر 5W-30 · 1 لتر', qty: 3, unit: 'عبوة', price: '8,500 د.ع', low: true),
  ],
);

const _car = AssistantCarSpecCard(
  title: 'تويوتا كورولا 2015',
  subtitle: 'محرك 1.8 بنزين · من دليل نابو للسيارات',
  confidence: AssistantConfidence.verified,
  specs: [
    ('سعة الزيت', '4.2 لتر مع الفلتر'),
    ('اللزوجة', '0W-20، والبديل 5W-30'),
    ('المواصفة', 'API SP / ILSAC GF-6'),
    ('فلتر الزيت', '90915-YZZE1'),
    ('الفترة', '7–10 آلاف كم أو 6 أشهر (تقريبية)'),
  ],
  available: [
    AssistantStockRow(name: 'زيت توتال كوارتز 5W-30 · 4 لتر', qty: 12, unit: 'عبوة', price: '28,000 د.ع'),
    AssistantStockRow(name: 'فلتر زيت تويوتا 90915-YZZE1', qty: 1, unit: 'قطعة', price: '6,000 د.ع', low: true),
  ],
  sources: [
    AssistantSource('دليل تويوتا للمالك', 'toyota.com'),
    AssistantSource('مواصفات الزيت', 'amsoil.com'),
  ],
);

const _draft = AssistantDraftCard(
  title: 'بطاقة غيار جديدة',
  fields: [
    AssistantDraftField('اللوحة', '12345 ب · بغداد'),
    AssistantDraftField('الزبون', 'أبو علي (من آخر زيارة)'),
    AssistantDraftField('الزيت', 'توتال كوارتز 5W-30 · 4 لتر'),
    AssistantDraftField('الفلتر', 'فلتر زيت تويوتا 90915-YZZE1'),
    AssistantDraftField('العدّاد', 'تكمله أنت بالشاشة', missing: true),
  ],
);

const _product = AssistantProductCard(
  name: 'زيت شل هيليكس HX8 5W-30 · 4 لتر',
  details: [
    ('الموجود', '6 عبوات'),
    ('سعر البيع', '32,000 د.ع'),
    ('اللزوجة', '5W-30 تخليقي · API SP'),
  ],
);

// ------------------------------------------------------------ الإطارات
class _Frame {
  const _Frame(this.key, this.title, this.build);
  final String key;
  final String title;
  final Widget Function(bool desktop) build;
}

Widget _page({required Widget body, String subtitle = 'جاهز', Widget? top, Widget? composer, bool desktop = false}) {
  return Column(
    children: [
      AssistantHeader(subtitle: subtitle, animateMark: false, showBack: !desktop, onClose: desktop ? () {} : null),
      ?top,
      Expanded(child: body),
      composer ?? const AssistantComposer(),
    ],
  );
}

final _frames = <_Frame>[
  _Frame(
    '1_start',
    'البداية',
    (d) => _page(
      desktop: d,
      body: const AssistantStartView(
        name: 'أبو حسين',
        fromScreen: 'سجل الخدمات',
        animateMark: false,
        suggestions: [
          'شكو بطاقات معلّقة اليوم؟',
          'شكد بعنا اليوم؟',
          'سجل سيارة لوحة 12345 ب',
          'شلون أسوي بطاقة غيار جديدة؟',
        ],
      ),
    ),
  ),
  _Frame(
    '2_stock',
    'رد ببطاقة مخزون',
    (d) => _page(
      desktop: d,
      body: const AssistantMessageList(
        animateMark: false,
        messages: [
          AssistantViewMessage(fromUser: true, text: 'شكد باقي من 5W-30؟'),
          AssistantViewMessage(
            fromUser: false,
            text: 'عندك صنفين 5W-30. الموبيل قليل، باقي منه 3 عبوات بس.',
            cards: [_stock],
            source: 'من مخزون هذا الفرع · قبل لحظات',
            followups: ['شكد بعنا منه هذا الأسبوع؟', 'منو مورّد الموبيل؟', 'شنو بعد قليل بالمخزون؟'],
          ),
        ],
      ),
    ),
  ),
  _Frame(
    '3_guide',
    'إرشاد بالفقاعة فوق الشاشة الحقيقية',
    (d) => _GuideOverlay(desktop: d),
  ),
  _Frame(
    '4_draft',
    'بطاقة تجهيز بتأكيد',
    (d) => _page(
      desktop: d,
      top: const AssistantBudgetStrip(pct: 72, renewsOn: '1 كانون الأول'),
      body: const AssistantMessageList(
        animateMark: false,
        messages: [
          AssistantViewMessage(fromUser: true, text: 'سجل غيار للوحة 12345 ب، توتال 5W-30 أربع لترات'),
          AssistantViewMessage(
            fromUser: false,
            text: 'جهزتلك البطاقة. راجعها وكمّل العدّاد، وبعدين اضغط حفظ.',
            cards: [_draft],
            followups: ['آخر مرة شنو بدّل؟', 'أضيف غسيل وية الغيار؟'],
          ),
        ],
      ),
    ),
  ),
  _Frame(
    '5_history',
    'المحادثات السابقة',
    (d) => d
        ? _page(
            desktop: true,
            body: const AssistantThreadsPanel(count: 12, groups: _threads),
          )
        : Stack(
            children: [
              _page(
                body: const AssistantMessageList(
                  animateMark: false,
                  messages: [AssistantViewMessage(fromUser: true, text: 'شكد باقي من 5W-30؟')],
                ),
              ),
              const Positioned.fill(child: ColoredBox(color: Color(0x88000000))),
              const PositionedDirectional(
                top: 0,
                bottom: 0,
                start: 0,
                width: 320,
                child: AssistantThreadsPanel(count: 12, groups: _threads),
              ),
            ],
          ),
  ),
  _Frame(
    '6_car',
    'بطاقة سيارة بمصادرها',
    (d) => _page(
      desktop: d,
      body: const AssistantMessageList(
        animateMark: false,
        messages: [
          AssistantViewMessage(fromUser: true, text: 'شنو الأنسب لكورولا 2015 عدادها 180 ألف؟'),
          AssistantViewMessage(
            fromUser: false,
            text: 'الأنسب 5W-30 تخليقي لعداد 180 ألف، والبديل 0W-20 إذا الشركة تنص عليه. الفلتر مع كل غيار.',
            cards: [_car],
            followups: ['أجهز بطاقة غيار بهذا الزيت؟', 'شكد سعر الفلتر؟'],
          ),
        ],
      ),
    ),
  ),
  _Frame(
    '7_photo',
    'سؤال بصورة، والجواب أثناء الكتابة',
    (d) => _page(
      desktop: d,
      subtitle: 'يكتب…',
      composer: const AssistantComposer(streaming: true),
      body: const AssistantMessageList(
        animateMark: false,
        messages: [
          AssistantViewMessage(fromUser: true, imageLabel: 'صورة عبوة', text: 'عدنا من هذا؟'),
          AssistantViewMessage(
            fromUser: false,
            text: 'هذا زيت شل هيليكس HX8 5W-30 عبوة 4 لتر. عندك منه 6 عبوات',
            cards: [_product],
            status: 'أطابق الصورة بالمخزون…',
            actions: false,
          ),
        ],
      ),
    ),
  ),
];

const _threads = [
  AssistantThreadGroup('اليوم', [
    AssistantThreadItem('5W-30 بالمخزون', 'عندك صنفين 5W-30. الموبيل قليل…', '10:42'),
    AssistantThreadItem('بطاقة 12345 ب', 'جهزتلك البطاقة. راجعها وكمّل العدّاد…', '09:15'),
  ]),
  AssistantThreadGroup('أمس', [
    AssistantThreadItem('مبيعات الغسيل', 'هذا الأسبوع بالغسيل 19 غسلة…', '18:30'),
    AssistantThreadItem('زيت كورولا 2015', 'الأنسب 5W-30 تخليقي لعداد 180 ألف…', '12:05'),
  ]),
  AssistantThreadGroup('هذا الأسبوع', [
    AssistantThreadItem('ربط واتساب', 'فتحتلك شاشة ربط واتساب…', 'الإثنين'),
    AssistantThreadItem('صلاحيات موظف', 'فتحتلك شاشة إضافة موظف…', 'الأحد'),
  ]),
];

/// الإطار 3: الشاشة الخلفية هنا هيكل مبسّط يوضّح الفكرة فقط. في التطبيق
/// تكون شاشة «إعدادات الزيت» الحقيقية والعنصر المؤشَّر عليه منها.
class _GuideOverlay extends StatelessWidget {
  const _GuideOverlay({required this.desktop});
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    Widget field(String label, {bool hi = false}) => Container(
          margin: const EdgeInsetsDirectional.only(bottom: 12),
          padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border.all(color: hi ? cs.secondary : cs.outline, width: hi ? 3 : 1),
          ),
          child: Row(
            children: [
              Expanded(child: Text(label, style: t.textTheme.bodyMedium)),
              Container(width: 90, height: 14, color: cs.outline.withValues(alpha: 0.5)),
            ],
          ),
        );
    return Stack(
      children: [
        Column(
          children: [
            Container(
              height: 60,
              color: t.appBarTheme.backgroundColor,
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
              alignment: AlignmentDirectional.centerStart,
              child: Text('إعدادات الزيت والغيار', style: t.appBarTheme.titleTextStyle),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    children: [
                      field('أنواع الزيوت المعتمدة'),
                      field('سعر خدمة التبديل', hi: true),
                      field('مدة التذكير بالغيار'),
                      field('رسالة واتساب بعد الخدمة'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        PositionedDirectional(
          start: 16,
          end: desktop ? null : 16,
          width: desktop ? 420 : null,
          bottom: 24,
          child: const AssistantGuideBubble(
            step: 2,
            of: 3,
            animateMark: false,
            text: 'هنا تغيّر سعر خدمة التبديل. اضغط على الحقل المؤشَّر بالذهبي واكتب السعر الجديد.',
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ اللوحة
/// الحاسبة: محتوى التطبيق (هيكل) ولوحة المساعد الجانبية بعرض 420 (ق44).
Widget _desktop(Widget panel, ThemeData theme, {bool guide = false}) {
  final cs = theme.colorScheme;
  if (guide) return panel;
  return Row(
    children: [
      // جهة البداية (اليمين): التطبيق.
      Expanded(
        child: Column(
          children: [
            Container(
              height: 60,
              color: theme.appBarTheme.backgroundColor,
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
              alignment: AlignmentDirectional.centerStart,
              child: Text('سجل الخدمات', style: theme.appBarTheme.titleTextStyle),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Container(
                        height: 52,
                        margin: const EdgeInsetsDirectional.only(bottom: 8),
                        decoration: BoxDecoration(color: cs.surface, border: Border.all(color: cs.outline)),
                        padding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            Container(width: 120, height: 12, color: cs.outline.withValues(alpha: 0.55)),
                            const Spacer(),
                            Container(width: 70, height: 12, color: cs.outline.withValues(alpha: 0.35)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      Container(width: 1, color: cs.outline),
      SizedBox(width: 420, child: panel),
    ],
  );
}

Widget _host(Widget child, ThemeData theme, {double textScale = 1}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: child),
      ),
    ),
  );
}

/// لوح المراجعة: إطاران متجاوران (فاتح وداكن) مع عنوان.
Widget _board(String title, Widget Function(ThemeData) frame, Size each) {
  Widget one(ThemeData th, String label) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(label, style: const TextStyle(fontFamily: 'Tajawal', fontSize: 18, color: Color(0xFF475569))),
          ),
          Container(
            width: each.width,
            height: each.height,
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFF94A3B8))),
            child: Theme(
              data: th,
              child: Builder(
                builder: (c) => Material(color: th.scaffoldBackgroundColor, child: frame(th)),
              ),
            ),
          ),
        ],
      );
  return Directionality(
    textDirection: TextDirection.rtl,
    child: ColoredBox(
      color: const Color(0xFFE2E8F0),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontFamily: 'Tajawal', fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                one(AppTheme.lightTheme, 'فاتح'),
                const SizedBox(width: 28),
                one(AppTheme.darkTheme, 'داكن'),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(_loadFonts);

  const phone = Size(390, 844);
  const desk = Size(1280, 800);

  testWidgets('الإطارات السبعة بلا تجاوز: هاتف وحاسبة، فاتح وداكن، وخط مكبّر', (tester) async {
    tester.view.devicePixelRatio = 1;
    for (final f in _frames) {
      for (final th in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        for (final (size, desktop, scale) in [
          (phone, false, 1.0),
          (phone, false, 1.3),
          (const Size(320, 640), false, 1.0),
          (desk, true, 1.0),
        ]) {
          tester.view.physicalSize = size;
          await tester.pumpWidget(
            _host(desktop ? _desktop(f.build(true), th, guide: f.key == '3_guide') : f.build(false), th, textScale: scale),
          );
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '${f.key} ${size.width} ×$scale ${th.brightness}');
        }
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('صور الإطارات للمراجعة', (tester) async {
    final dir = Platform.environment['FRAME_SHOTS_DIR'];
    if (dir == null) return;
    // بيئة الاختبار ترسم الظل كتلة صلبة؛ الصور تحتاج الظل الحقيقي.
    debugDisableShadows = false;
    tester.view.devicePixelRatio = 1;

    Future<void> shoot(String name, Widget board, Size canvas, double ratio) async {
      tester.view.physicalSize = canvas;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(key: const ValueKey('shot'), child: board),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: name);
      await tester.runAsync(() async {
        final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
        final im = await b.toImage(pixelRatio: ratio);
        final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
        File('$dir/$name.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    for (final f in _frames) {
      await shoot(
        'phone_${f.key}',
        _board('${f.title} · هاتف', (th) => f.build(false), phone),
        const Size(900, 1000),
        1.5,
      );
      await shoot(
        'desktop_${f.key}',
        _board('${f.title} · حاسبة', (th) => _desktop(f.build(true), th, guide: f.key == '3_guide'), desk),
        const Size(2700, 960),
        1.0,
      );
    }
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
