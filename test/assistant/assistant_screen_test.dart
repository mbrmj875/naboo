import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/assistant_api_client.dart';
import 'package:naboo/assistant/assistant_rollout.dart';
import 'package:naboo/assistant/assistant_thread_store.dart';
import 'package:naboo/assistant/assistant_tool_registry.dart';
import 'package:naboo/assistant/tools/setup_status_tool.dart';
import 'package:naboo/assistant/ui/assistant_controller.dart';
import 'package:naboo/assistant/ui/assistant_screen.dart';
import 'package:naboo/assistant/ui/assistant_session.dart';
import 'package:naboo/guides/guide_controller.dart';
import 'package:naboo/guides/widgets/guide_chat_sheet.dart';
import 'package:naboo/providers/auth_provider.dart';
import 'package:naboo/providers/business_features_provider.dart';
import 'package:naboo/providers/permissions_provider.dart';
import 'package:naboo/providers/shift_provider.dart';
import 'package:naboo/utils/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_test_fakes.dart';

/// مخزن في الذاكرة: قاعدة sqflite الحقيقية تعمل بخيط منفصل لا يتقدم مع
/// زمن اختبار الواجهة الوهمي. سلوك القاعدة نفسها في assistant_thread_store_test.
class _MemoryStore extends AssistantThreadStore {
  _MemoryStore() : super(() => throw UnimplementedError());
  final threads = <String, StoredThread>{};
  final msgs = <String, List<StoredMessage>>{};

  @override
  Future<void> touchThread({
    required String id,
    required int tenantId,
    required String userKey,
    required String title,
    DateTime? now,
  }) async {
    final old = threads[id];
    threads[id] = StoredThread(id: id, title: old?.title ?? title, preview: '', updatedAt: now ?? DateTime.now());
  }

  @override
  Future<void> addMessage({
    required String id,
    required String threadId,
    required String role,
    String? turnId,
    String? content,
    Map<String, Object?>? payload,
    String? cardType,
    DateTime? now,
  }) async {
    final l = msgs.putIfAbsent(threadId, () => []);
    l.removeWhere((m) => m.id == id);
    // نسخة JSON كما في القاعدة.
    final p = payload == null ? null : jsonDecode(jsonEncode(payload)) as Map<String, Object?>;
    l.add(StoredMessage(id: id, role: role, turnId: turnId, content: content ?? '', payload: p, cardType: cardType));
  }

  @override
  Future<List<StoredThread>> listThreads({required int tenantId, required String userKey, String? search}) async =>
      threads.values.where((t) => search == null || search.isEmpty || t.title.contains(search)).toList();

  @override
  Future<List<StoredMessage>> loadMessages(String threadId) async => List.of(msgs[threadId] ?? const []);

  @override
  Future<void> deleteThread(String id) async {
    threads.remove(id);
    msgs.remove(id);
  }

  @override
  Future<void> deleteMessages(List<String> ids) async {
    for (final l in msgs.values) {
      l.removeWhere((m) => ids.contains(m.id));
    }
  }
}

class _Setup implements SetupStatusSource {
  _Setup({this.oils = 3});
  int oils;
  @override
  Future<int> oilCatalogCount() async => oils;
  @override
  Future<int> basePriceFils() async => 5000000;
  @override
  Future<int> activeUsers() async => 3;
  @override
  Future<bool> whatsappConnected() async => true;
  @override
  Future<bool> printerConfigured() async => true;
}

class _OwnerAuth extends AuthProvider {
  @override
  bool get isOwner => true;
  @override
  String get roleKey => 'owner';
  @override
  String get displayName => 'أبو حسن العبيدي';
}

void main() {
  late GuideController guide;
  late List<String> opened;
  late FakeApi api;

  final stock = FakeTool(
    'stock_search',
    rows: [
      {'name': 'زيت 5W-30', 'qty': 4, 'unit': 'علبة', 'sell_price_fils': 15000000},
    ],
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AssistantSession.instance.store = _MemoryStore();
    AssistantSession.instance.setupSource = _Setup();
    AssistantSession.instance.setupIncomplete = null;
    opened = [];
    guide = GuideController()
      ..configureIdentity(tenantId: 3, userKey: 'owner')
      ..bindHost(
        GuideHostBridge(
          currentRouteId: () => 'app_home',
          ensureRoute: (r) async => opened.add(r),
          runAction: (_) async {},
        ),
      );
    api = FakeApi(
      (step, req) => step == 0
          ? const [
              AssistantToolCallEvent(id: 'a', name: 'stock_search', arguments: {'query': '5W-30'}),
              AssistantDoneEvent(finish: 'tool_calls'),
            ]
          : const [
              AssistantTextEvent('عندك 4 علب بسعر ⟦m1⟧'),
              AssistantDoneEvent(finish: 'stop', followups: ['شكد بعنا منه؟']),
            ],
    );
    AssistantSession.instance.debugController = AssistantController(
      registry: AssistantToolRegistry(tools: [stock]),
      toolContext: () => ctxFor(owner: true),
      api: api,
      isOnline: () async => true,
      v2Enabled: () => true,
      onUiAction: (a) => AssistantSession.instance.uiHandler?.call(a),
      store: AssistantSession.instance.store,
      tenantId: () => 3,
      userKey: () => 'owner',
      routeId: () => AssistantSession.instance.currentRouteId,
      videoFor: (r) => r == 'app_inventory' ? 'https://example.com/inventory.mp4' : null,
    );
    AssistantRollout.instance.debugForceV2 = true;
  });

  tearDown(() async {
    AssistantSession.instance.debugController = null;
    AssistantRollout.instance.debugForceV2 = null;
  });

  Future<void> pumpHost(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    bool dark = false,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final auth = _OwnerAuth();
    final shift = ShiftProvider.testing();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ShiftProvider>.value(value: shift),
          ChangeNotifierProvider(create: (_) => PermissionsProvider(auth, shift)),
          ChangeNotifierProvider(create: (_) => BusinessFeaturesProvider()),
          ChangeNotifierProvider.value(value: guide),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: true),
            child: child!,
          ),
          home: Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => openNabooAssistant(c, currentRouteId: 'app_inventory'),
                  child: const Text('افتح'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();
  }

  testWidgets('البداية: تحية بالاسم الأول واقتراحات شاشة المخزون للمالك', (tester) async {
    await pumpHost(tester);
    expect(find.text('هلا أبو حسن'), findsOneWidget);
    expect(find.text('من شاشة المخزون'), findsOneWidget);
    expect(find.textContaining('5W-30'), findsWidgets);
    expect(find.text('شكد قيمة المخزون؟'), findsOneWidget, reason: 'سؤال مالي يظهر للمالك');
    expect(tester.takeException(), isNull);
  });

  testWidgets('سؤال ← بطاقة مخزون بالسعر المنسّق ← زرها يفتح الشاشة ويرجع', (tester) async {
    await pumpHost(tester);
    await tester.enterText(find.byType(TextField), 'قارن لي بين زيوتي');
    await tester.pump();
    await tester.tap(find.byTooltip('إرسال'));
    await tester.pumpAndSettle();
    expect(api.requests.length, 2);
    expect(find.textContaining('15,000'), findsWidgets);
    expect(find.text('شكد بعنا منه؟'), findsOneWidget);
    expect(find.text('جواب خاطئ'), findsOneWidget);
    expect(find.textContaining('من بيانات محلك'), findsOneWidget);
    // لا اسم المستخدم في أي طلب (م2-19).
    expect(api.requests.any((r) => r.messages.toString().contains('أبو حسن')), isFalse);

    await tester.ensureVisible(find.text('افتح المخزون'));
    await tester.tap(find.text('افتح المخزون'));
    await tester.pumpAndSettle();
    expect(opened, ['app_inventory']);
    expect(find.byType(AssistantScreen), findsNothing, reason: 'على الهاتف تُغلق الصفحة قبل فتح الشاشة');
  });

  testWidgets('«جواب خاطئ» يفتح حقل التصحيح ويرسل الإشارة', (tester) async {
    await pumpHost(tester);
    await tester.enterText(find.byType(TextField), 'قارن لي بين زيوتي');
    await tester.pump();
    await tester.tap(find.byTooltip('إرسال'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('جواب خاطئ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'الصحيح هو…'), 'عندي 6 علب');
    await tester.tap(find.text('أرسل'));
    await tester.pumpAndSettle();
    expect(api.signals.single['s_thumb'], -1);
    expect(api.signals.single['user_correction'], 'عندي 6 علب');
  });

  testWidgets('السجل: المحادثة محفوظة، والجديدة تفرغ الصفحة، والقديمة ترجع', (tester) async {
    await pumpHost(tester);
    await tester.enterText(find.byType(TextField), 'قارن لي بين زيوتي');
    await tester.pump();
    await tester.tap(find.byTooltip('إرسال'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('المحادثات السابقة'));
    await tester.pumpAndSettle();
    expect(find.text('1 من 50'), findsOneWidget);
    await tester.tap(find.text('محادثة جديدة').last);
    await tester.pumpAndSettle();
    expect(find.text('هلا أبو حسن'), findsOneWidget);

    await tester.tap(find.byTooltip('المحادثات السابقة'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('قارن لي').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('15,000'), findsWidgets);
  });

  testWidgets('الشاشة العريضة: لوحة جانبية بعرض 420 والمحتوى خلفها', (tester) async {
    await pumpHost(tester, size: const Size(1280, 800));
    final panel = tester.getRect(find.byType(AssistantScreen));
    expect(panel.width, 420);
    expect(find.text('افتح'), findsOneWidget, reason: 'المحتوى يبقى');
    await tester.tap(find.byTooltip('إغلاق').first);
    await tester.pumpAndSettle();
    expect(find.byType(AssistantScreen), findsNothing);
  });

  testWidgets('«جهّز محلي معي» يظهر للمالك فقط حين ينقص التجهيز', (tester) async {
    AssistantSession.instance.setupSource = _Setup(oils: 0);
    await pumpHost(tester);
    expect(find.text('جهّز محلي معي'), findsOneWidget);
    expect(find.text('اشرح لي هذه الشاشة'), findsOneWidget);
  });

  testWidgets('محل مكتمل: لا يظهر «جهّز محلي معي»', (tester) async {
    await pumpHost(tester);
    expect(find.text('جهّز محلي معي'), findsNothing);
  });

  testWidgets('«اشرح لي هذه الشاشة»: شرح من الخريطة بلا طلب للخادم، وزر الفيديو', (tester) async {
    await pumpHost(tester);
    await tester.tap(find.text('اشرح لي هذه الشاشة'));
    await tester.pumpAndSettle();
    expect(api.requests, isEmpty);
    expect(find.textContaining('المخزون: مدخل كل أعمال المخزون'), findsOneWidget);
    expect(find.text('شاهد الشرح'), findsOneWidget);
  });

  testWidgets('المفتاح مطفأ: يفتح الشات القديم', (tester) async {
    AssistantRollout.instance.debugForceV2 = false;
    await pumpHost(tester);
    expect(find.byType(GuideChatSheet), findsOneWidget);
    expect(find.byType(AssistantScreen), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets('فحص التصميم: 320 عرض، خط 1.3، ${dark ? 'داكن' : 'فاتح'}، بلا تجاوز', (tester) async {
      await pumpHost(tester, size: const Size(320, 640), dark: dark, textScale: 1.3);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'قارن لي بين زيوتي');
      await tester.pump();
      await tester.tap(find.byTooltip('إرسال'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('15,000'), findsWidgets);
    });
  }
}
