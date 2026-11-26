import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../guides/guide_controller.dart';
import '../../guides/guide_overlay.dart';
import '../../home/employee_access_policy.dart';
import '../../home/home_dashboard_resolver.dart';
import '../../providers/business_features_provider.dart';
import '../../services/license_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permissions_provider.dart';
import '../../services/connectivity_resume_sync.dart';
import '../../services/database_helper.dart';
import '../../services/permission_service.dart';
import '../../services/system_notification_service.dart';
import '../../services/supabase_config.dart';
import '../assistant_access.dart';
import '../assistant_api_client.dart';
import '../assistant_rollout.dart';
import '../assistant_thread_store.dart';
import '../assistant_tool.dart';
import '../assistant_tool_registry.dart';
import '../data/assistant_shop_data.dart';
import '../data/device_shop_data.dart';
import '../exec/assistant_prefill.dart';
import '../exec/assistant_reminders.dart';
import '../exec/device_exec_port.dart';
import '../tools/exec_tools.dart';
import '../tools/extra_tools.dart';
import '../tools/read_tools.dart';
import '../tools/setup_status_tool.dart';
import '../tools/ui_tools.dart';
import 'assistant_controller.dart';
import 'assistant_context_scope.dart';
import 'assistant_guide_card.dart';
import 'cards/assistant_cards.dart';
import 'guide_ui_port.dart';

/// محادثة المساعد الحية طوال تشغيل التطبيق.
///
/// الصفحة تُغلق وتُفتح، والمحادثة تبقى حيث هي (ق45: الرجوع لا يضيّعها).
/// تُبنى من جديد إذا تغيّر المحل أو المستخدم.
class AssistantSession {
  AssistantSession._();
  static final AssistantSession instance = AssistantSession._();

  /// أدوات القراءة تُسجَّل هنا في ب4. حتى ذلك الحين السجل فارغ: الموجّه
  /// المحلي والنموذج وأدوات التنقل تعمل، وأسئلة البيانات تُجاب بلا بطاقات.
  static AssistantToolRegistry Function() registryFactory = AssistantToolRegistry.new;

  AssistantController? _controller;
  String? _identity;

  /// الشاشة التي فُتح منها المساعد الآن، ومن يستقبل أفعال الواجهة.
  String? currentRouteId;
  String? currentRouteTitle;
  void Function(AssistantUiAction action)? uiHandler;

  /// تنطوي الصفحة قبل الإرشاد: تضبطها صفحة الشات الظاهرة (م3-8).
  VoidCallback? beforeGuide;

  /// الطبقة الجذرية التي تُرسم فيها الفقاعة؛ تبقى بعد إغلاق الصفحة.
  OverlayState? rootOverlay;

  /// قرار القائمة نفسه لفتح مسار؛ يُضبط مع المتحكم (للدورة والأدوات).
  bool Function(String routeId) canOpenRoute = _allowAll;
  static bool _allowAll(String _) => true;

  /// التجهيز ناقص؟ يُحسب عند فتح الصفحة للمالك. null: لم يُحسب بعد.
  bool? setupIncomplete;

  /// مصدر حالة التجهيز (قابل للاستبدال في الاختبارات).
  SetupStatusSource setupSource = const DeviceSetupStatusSource();

  /// مصدر بيانات المحل لأدوات القراءة (قابل للاستبدال في الاختبارات).
  AssistantShopData shopData = DeviceShopData();

  /// مفتاح الكتم الواحد للشات والجولات (ق46): null الافتراضي الصامت.
  bool? ttsMuted;
  static const mutePrefKey = 'assistant_tts_muted';

  /// صوت الجولات صامت إلا إن شغّله المستخدم، ما دام المساعد الجديد مفعّلاً.
  static void installNarrationRule() {
    GuideController.narrationMuted = () => AssistantRollout.instance.v2Enabled && instance.ttsMuted != false;
    GuideOverlayHost.assistantBubble = buildAssistantGuideCard;
  }

  /// قابل للاستبدال في الاختبارات بقاعدة في الذاكرة.
  AssistantThreadStore store = AssistantThreadStore(() => DatabaseHelper().database);

  /// تذكيرات المساعد (م4-11): محلية لكل مستخدم، وإشعارها من النظام.
  AssistantReminderStore reminders = AssistantReminderStore(() => DatabaseHelper().database);
  late final AssistantReminderScheduler reminderScheduler = AssistantReminderScheduler(
    store: reminders,
    scheduleSystem: ({required id, required text, required when}) => SystemNotificationService.instance.scheduleAt(
      id: 'assistant_reminder_$id',
      title: 'تذكير',
      body: text,
      when: when,
    ),
    showNow: ({required id, required text}) =>
        SystemNotificationService.instance.show(id: 'assistant_reminder_$id', title: 'تذكير', body: text),
  );

  /// منفّذ أدوات الجهاز وعميل الخادم للجلسة الحالية (لبطاقة الصورة م4-13).
  DeviceExecPort? execPort;
  AssistantApiClient? api;

  /// يلغي تذكيراً من «تذكيراتي».
  Future<void> cancelReminder(int id) async {
    reminderScheduler.cancel(id);
    await SystemNotificationService.instance.cancelScheduled('assistant_reminder_$id');
    await reminders.setStatus(id, 'cancelled');
  }

  /// للاختبارات: متحكم جاهز بعميل وأدوات وهمية.
  @visibleForTesting
  AssistantController? debugController;

  AssistantController controllerFor(BuildContext context) {
    final forced = debugController;
    if (forced != null) return forced;
    final auth = context.read<AuthProvider>();
    final perms = context.read<PermissionsProvider>();
    final guide = context.read<GuideController>();
    final identity = '${guide.tenantId}|${guide.userKey}';
    final existing = _controller;
    if (existing != null && _identity == identity) return existing;
    existing?.dispose();
    _identity = identity;
    final registry = registryFactory();
    // المزوّدات تُقرأ الآن: سياق الصفحة يزول بعد إغلاقها والأدوات تبقى.
    final features = context.read<BusinessFeaturesProvider>();
    LicenseService? license;
    try {
      license = context.read<LicenseService>();
    } catch (_) {}
    canOpenRoute = (r) => _policy(features, license, perms).canOpen(r);
    final lic = license;
    if (shopData is DeviceShopData) shopData = DeviceShopData(license: () => lic?.state);
    final port = GuideUiPort(guide: guide, canOpenRoute: (r) => canOpenRoute(r));
    final exec = execPort = DeviceExecPort(
      guide: guide,
      reminders: reminders,
      scheduler: reminderScheduler,
      userKey: () => guide.userKey,
    );
    for (final t in [
      ...buildUiTools(port),
      const SetupStatusTool(),
      ...buildReadTools(shopData, canOpen: (r) => canOpenRoute(r)),
      ...buildExtraTools(shopData, canOpen: (r) => canOpenRoute(r)),
      ...buildExecTools(shopData, exec, canOpen: (r) => canOpenRoute(r)),
    ]) {
      if (!registry.has(t.name)) registry.register(t);
    }
    installNarrationRule();
    // م2-18: هاتف الزبون يُقرأ من الجهاز عند عرض بطاقته فقط، لمن يملك صلاحية الزبائن.
    AssistantCustomerPhone.resolve = (id) async {
      if (!auth.isOwner && !perms.can(PermissionKeys.customersView)) return null;
      final row = await DatabaseHelper().getCustomerById(id);
      return row?['phone']?.toString();
    };
    final controller = AssistantController(
      registry: registry,
      toolContext: () => AssistantToolContext(
        isOwner: auth.isOwner,
        can: perms.can,
        level: AssistantAccess.levelFor(isOwner: auth.isOwner, can: perms.can),
        userName: auth.displayName,
      ),
      api: api = AssistantApiClient(
        baseUrl: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
        accessToken: () => Supabase.instance.client.auth.currentSession?.accessToken,
      ),
      isOnline: () async {
        try {
          return connectivityResultsOnline(await Connectivity().checkConnectivity());
        } catch (_) {
          return true;
        }
      },
      v2Enabled: () => AssistantRollout.instance.v2Enabled,
      onUiAction: (a) => uiHandler?.call(a),
      routeId: () => currentRouteId,
      videoFor: (r) => AssistantRollout.instance.flags.videos[r],
      routeTitle: () => currentRouteTitle,
      screenContext: () => AssistantScreenContext.current.value,
      roleKey: () => auth.roleKey,
      store: store,
      tenantId: () => guide.tenantId,
      userKey: () => guide.userKey,
    );
    // م5-1: نهاية جولة بدأها المساعد تُرسل فوراً، فالصفحة قد لا تُفتح بعدها.
    GuideController.onAssistantTourEnded = ({required completed, required step}) {
      controller.signals.guideEnded(completed: completed, step: step);
      unawaited(controller.flushSignals());
    };
    // م4-5: الحفظ من نموذج معبّأ يصل للخادم إشارةً على دور المحادثة نفسه.
    AssistantPrefill.onSaved = (p, {required entityType, entityId}) {
      final turn = p.turnId;
      if (turn != null) controller.queueSignal(turn, {'s_action_saved': true, 's_action_kind': p.tool});
    };
    unawaited(
      reminderScheduler
          .restore(
            tenantId: '${guide.tenantId}',
            userKey: guide.userKey,
            now: DateTime.now(),
            systemScheduling: SystemNotificationService.instance.canSchedule,
          )
          .catchError((_) {}),
    );
    return _controller = controller;
  }

  /// نفس قرار القائمة: الصلاحية والميزة وما يخفيه التخصص والوضع المقيّد.
  static EmployeeAccessPolicy _policy(
    BusinessFeaturesProvider featuresProvider,
    LicenseService? license,
    PermissionsProvider perms,
  ) {
    final features = featuresProvider.data;
    return EmployeeAccessPolicy(
      can: perms.can,
      features: features,
      restricted: license?.state.status == LicenseStatus.restricted,
      hiddenRouteIds: HomeDashboardResolver.resolve(features).hideNavRouteIds,
    );
  }
}
