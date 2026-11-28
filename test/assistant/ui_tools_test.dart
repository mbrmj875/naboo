import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/assistant_access.dart';
import 'package:naboo/assistant/assistant_tool.dart';
import 'package:naboo/assistant/assistant_tool_registry.dart';
import 'package:naboo/assistant/tools/ui_tools.dart';
import 'package:naboo/guides/guide_anchor.dart';
import 'package:naboo/guides/guide_controller.dart';
import 'package:naboo/guides/guide_tour.dart';
import 'package:naboo/navigation/content_navigation.dart';
import 'package:naboo/services/permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Port implements AssistantUiPort {
  final navigated = <String>[];
  List<GuideStep>? steps;
  String? tour;
  Set<String> denied = {};
  String current = AppContentRoutes.home;

  @override
  String? currentRouteId() => current;
  @override
  bool canOpen(String routeId) => !denied.contains(routeId);
  @override
  Future<void> navigate(String routeId) async => navigated.add(routeId);
  @override
  Future<bool> startAdHoc(List<GuideStep> steps, {required String title}) async {
    this.steps = steps;
    return true;
  }

  @override
  Future<bool> startTour(String tourId) async {
    tour = tourId;
    return true;
  }

  @override
  bool tourExists(String tourId) => GuideController().tourById(tourId) != null;

  final settingsEntries = <String>[];
  @override
  Future<bool> openSettingsEntry(String entryId) async {
    settingsEntries.add(entryId);
    return true;
  }
}

void main() {
  late _Port port;
  late AssistantToolRegistry reg;
  const guideCtx = AssistantToolContext(isOwner: false, can: _none, level: AssistantLevel.guideOnly);

  setUp(() {
    port = _Port();
    reg = AssistantToolRegistry(tools: buildUiTools(port));
  });

  test('الأدوات الخمس معلنة لمستوى «إرشاد فقط»', () {
    expect(reg.allowedNames(guideCtx), ['ui_describe', 'ui_guide', 'ui_highlight', 'ui_navigate', 'ui_start_tour']);
  });

  test('ui_describe: وصف الشاشة بأزرارها الحقيقية وإمكان فتحها', () async {
    port.denied = {AppContentRoutes.cash};
    final r = await reg.execute('ui_describe', {
      'route_ids': [AppContentRoutes.addProduct, AppContentRoutes.cash, 'app_fake'],
    }, guideCtx);
    expect(r.ok, isTrue);
    expect(r.rows.first['title'], 'إضافة منتج');
    expect((r.rows.first['elements']! as List).length, greaterThan(10));
    expect(r.rows.last['can_open'], isFalse);
    expect(r.extra['unknown_route_ids'], ['app_fake']);
    // معرفة الشاشة القديمة تصل مع الشاشة الأولى فقط.
    expect('${r.rows.first['knowledge']}', contains('المنتج'));
    expect(r.rows.last.containsKey('knowledge'), isFalse);
  });

  test('ui_navigate: مسار مجهول يُرفض، والممنوع يسمّي الصلاحية', () async {
    expect((await reg.execute('ui_navigate', {'route_id': 'app_fake'}, guideCtx)).error, 'bad_args:unknown_route');
    port.denied = {AppContentRoutes.cash};
    final r = await reg.execute('ui_navigate', {'route_id': AppContentRoutes.cash}, guideCtx);
    expect(r.error, 'forbidden');
    expect(r.needs, PermissionKeys.cashView);
    expect(port.navigated, isEmpty);
  });

  test('ui_navigate: شاشة مباشرة تُفتح، وشاشة من بند تفتح الأب وتؤشّر على البند', () async {
    await reg.execute('ui_navigate', {'route_id': AppContentRoutes.inventoryStocktaking}, guideCtx);
    expect(port.navigated, [AppContentRoutes.inventoryStocktaking]);

    // بند إعدادات يُفتح مباشرة بلا «اضغط هنا» ينتظر فوق المحادثة.
    final r = await reg.execute('ui_navigate', {'route_id': AppContentRoutes.settingsPrintingInline}, guideCtx);
    expect(port.settingsEntries, ['printing']);
    expect(port.steps, isNull);
    expect(r.ok, isTrue);
    expect(r.rows.single['opened_directly'], isTrue);
  });

  test('ui_highlight: مرساة مخترعة تُرفض، والحقيقية تفتح شاشتها أولاً', () async {
    final bad = await reg.execute('ui_highlight', {'anchor_id': 'oil.form.magic', 'title': 'x'}, guideCtx);
    expect(bad.error, 'bad_args:unknown_anchor');
    final ok = await reg.execute('ui_highlight', {
      'anchor_id': OilGuideAnchors.productListAddCta,
      'title': 'إضافة منتج',
      'body': 'اضغط هنا',
      'await_tap': true,
    }, guideCtx);
    expect(ok.ok, isTrue);
    expect(port.steps!.single.ensureRouteId, AppContentRoutes.inventoryProducts);
  });

  test('ui_guide: مسار من 4 خطوات عبر شاشتين (م3-7)', () async {
    final r = await reg.execute('ui_guide', {
      'title': 'بطاقة غيار',
      'steps': [
        {
          'route_id': AppContentRoutes.oilServicesLog,
          'anchor_id': OilGuideAnchors.hubNewCard,
          'title': 'بطاقة جديدة',
          'body': 'اضغط هنا',
          'await_tap': true,
        },
        {'route_id': AppContentRoutes.oilChangeCreate, 'anchor_id': OilGuideAnchors.formPlate, 'title': 'اللوحة'},
        {'route_id': AppContentRoutes.oilChangeCreate, 'anchor_id': OilGuideAnchors.formOilBrand, 'title': 'الزيت'},
        {'route_id': AppContentRoutes.oilChangeCreate, 'anchor_id': OilGuideAnchors.formSave, 'title': 'حفظ'},
      ],
    }, guideCtx);
    expect(r.ok, isTrue, reason: r.error);
    expect(port.steps!.map((s) => s.ensureRouteId).toSet(), {
      AppContentRoutes.oilServicesLog,
      AppContentRoutes.oilChangeCreate,
    });
    expect(port.steps!.first.awaitTap, isTrue);
  });

  test('ui_guide: زر من شاشة أخرى يُرفض، وأكثر من 8 خطوات يُرفض', () async {
    final wrong = await reg.execute('ui_guide', {
      'steps': [
        {'route_id': AppContentRoutes.cash, 'anchor_id': OilGuideAnchors.formSave, 'title': 'x'},
      ],
    }, guideCtx);
    expect(wrong.error, startsWith('bad_args:anchor_not_on_screen'));
    final many = await reg.execute('ui_guide', {
      'steps': List.filled(9, {'route_id': AppContentRoutes.expenses, 'anchor_id': OilGuideAnchors.expensesAdd}),
    }, guideCtx);
    expect(many.error, 'bad_args:steps_count');
  });

  test('ui_start_tour: الجولات الجاهزة فقط، وبصلاحية شاشاتها', () async {
    expect((await reg.execute('ui_start_tour', {'tour_id': 'nope'}, guideCtx)).error, 'bad_args:unknown_tour');
    final ok = await reg.execute('ui_start_tour', {'tour_id': GuideTourIds.usersAddStaff}, guideCtx);
    expect(ok.ok, isTrue);
    expect(port.tour, GuideTourIds.usersAddStaff);
    port.denied = {AppContentRoutes.users};
    final no = await reg.execute('ui_start_tour', {'tour_id': GuideTourIds.usersAddStaff}, guideCtx);
    expect(no.error, 'forbidden');
  });

  group('GuideController: المسار المرتجل والانحراف (م3-9)', () {
    late GuideController g;
    late String route;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      route = AppContentRoutes.home;
      g = GuideController()
        ..bindHost(
          GuideHostBridge(currentRouteId: () => route, ensureRoute: (r) async => route = r, runAction: (_) async {}),
        );
      GuideController.narrationMuted = () => true;
    });

    tearDown(() => GuideController.narrationMuted = null);

    const step = GuideStep(
      anchorId: OilGuideAnchors.expensesAdd,
      title: 'مصروف',
      body: 'اضغط',
      ensureRouteId: AppContentRoutes.expenses,
    );

    test('يبدأ المرتجل ويفتح شاشته ولا يُحفظ كجولة منتهية', () async {
      expect(await g.startAdHoc([step]), isTrue);
      expect(g.isAdHoc, isTrue);
      expect(g.fromAssistant, isTrue);
      expect(route, AppContentRoutes.expenses);
    });

    test('مغادرة المسار تُسأل، و«نرجع» يعيد، و«نكمل من هنا» يُنهي', () async {
      await g.startAdHoc([step]);
      route = AppContentRoutes.cash;
      await g.onRouteChanged(AppContentRoutes.cash);
      expect(g.offRouteId, AppContentRoutes.cash);

      await g.returnToStep();
      expect(g.offRouteId, isNull);
      expect(route, AppContentRoutes.expenses);

      await g.onRouteChanged(AppContentRoutes.debts);
      expect(g.offRouteId, AppContentRoutes.debts);
      await g.continueHere();
      expect(g.isRunning, isFalse);
      expect(g.offRouteId, isNull);
    });

    test('الجولات القديمة لا تُراقَب (سلوكها كما كان)', () async {
      await g.startTour(GuideTourIds.usersShifts);
      await g.onRouteChanged(AppContentRoutes.cash);
      expect(g.offRouteId, isNull);
    });
  });
}

bool _none(String _) => false;
