import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:provider/provider.dart';
import '../../navigation/content_navigation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permissions_provider.dart';
import '../../services/database_helper.dart';
import '../../services/permission_service.dart';
import '../../utils/app_logger.dart';
import '../assistant_rollout.dart';
import '../assistant_tool_result.dart';
import '../ui/assistant_controller.dart';
import '../ui/assistant_screen.dart';
import '../ui/assistant_session.dart';
import 'demo_shop_seeder.dart';

/// مدخل الاختبار النهائي (م7-1، م7-2). يعمل في نسخة الاختبار فقط.
///
/// `adb` لا يكتب العربية في حقل النص، فالسؤال يصل برابط:
///   naboo-qa://assistant/ask?q=<سؤال مُرمَّز>   يفتح المساعد ويرسل السؤال
///   naboo-qa://assistant/state                  سطر حالة في السجل (logcat)
///   naboo-qa://assistant/reset                  يمسح محادثات هذا المستخدم
///   naboo-qa://assistant/seed                   يبذر محل النموذج (محل فارغ فقط، م7-5)
///
/// حماية مضاعفة: الرابط غير مسجّل في نسخة المتجر أصلاً (activity-alias معطّل في
/// AndroidManifest إلا مع -Pnaboo.qa=true)، وهنا لا شيء يُنفَّذ إلا إن كانت الحزمة
/// `com.basra.storemanager.qa`.
const kQaPackage = 'com.basra.storemanager.qa';
const kQaScheme = 'naboo-qa';

/// بداية كل سطر يقرؤه سكربت الاختبار من `adb logcat`.
const kQaLogTag = 'NABOO_QA';

sealed class QaCommand {
  const QaCommand();
}

class QaAsk extends QaCommand {
  const QaAsk(this.question, {this.routeId});
  final String question;

  /// الشاشة التي «فُتح منها» المساعد، لأسئلة «وين أنا؟».
  final String? routeId;
}

class QaState extends QaCommand {
  const QaState();
}

class QaWho extends QaCommand {
  const QaWho();
}

class QaReset extends QaCommand {
  const QaReset();
}

class QaSeed extends QaCommand {
  const QaSeed({this.over = false});

  /// فوق بيانات موجودة (حساب تجربة فيه بيانات، بموافقة صاحبه). يُرفض فقط إن بُذر من قبل.
  final bool over;
}

/// null لأي رابط آخر، أو لأي رابط في نسخة غير نسخة الاختبار.
QaCommand? parseQaUri(Uri uri, {required bool qaBuild}) {
  if (!qaBuild || uri.scheme != kQaScheme || uri.host != 'assistant') return null;
  switch (uri.path) {
    case '/ask':
      final q = (uri.queryParameters['q'] ?? '').trim();
      if (q.isEmpty || q.length > 600) return null;
      final route = uri.queryParameters['route']?.trim();
      return QaAsk(q, routeId: route == null || route.isEmpty ? null : route);
    case '/state':
      return const QaState();
    case '/who':
      return const QaWho();
    case '/reset':
      return const QaReset();
    case '/seed':
      return QaSeed(over: uri.queryParameters['over'] == '1');
  }
  return null;
}

/// حالة الشات كسطر JSON واحد: آخر سؤال ورد، والأدوات ونتائجها، والمسار.
Map<String, Object?> qaStateOf(AssistantController c) {
  final msgs = c.messages;
  AssistantChatMessage? lastUser;
  AssistantChatMessage? lastReply;
  for (final m in msgs.reversed) {
    if (!m.fromUser) lastReply ??= m;
    if (m.fromUser) {
      lastUser = m;
      break;
    }
  }
  String cut(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';
  return {
    'busy': c.busy,
    'messages': msgs.length,
    'question': lastUser == null ? null : cut(lastUser.text, 300),
    'reply': lastReply == null ? null : cut(c.display(lastReply), 700),
    'status': lastReply?.status.name,
    'local': lastReply?.local,
    'error': lastReply?.errorCode,
    'route': lastReply?.routeId,
    'tour': lastReply?.suggestedTourId,
    'tools': [
      for (final r in lastReply?.results ?? const <AssistantToolResult>[])
        {
          'tool': r.tool,
          'ok': r.ok,
          'rows': r.total,
          if (r.card != null) 'card': r.card,
          if (r.needs != null) 'needs': r.needs,
        },
    ],
    'followups': lastReply?.followups ?? const [],
    'knowledge': lastReply?.knowledge ?? const [],
  };
}

/// سطر السجل. logcat يقطع السطر الطويل، فالحالة تُقسم بأرقام إن طالت.
List<String> qaLogLines(String kind, Map<String, Object?> data, {int chunk = 900}) {
  final body = jsonEncode(data);
  if (body.length <= chunk) return ['$kQaLogTag $kind $body'];
  final parts = <String>[];
  for (var i = 0; i < body.length; i += chunk) {
    parts.add(body.substring(i, i + chunk > body.length ? body.length : i + chunk));
  }
  return [for (var i = 0; i < parts.length; i++) '$kQaLogTag $kind ${i + 1}/${parts.length} ${parts[i]}'];
}

class AssistantQaEntry {
  AssistantQaEntry._();

  static StreamSubscription<Uri>? _sub;

  /// يُستدعى مرة من main بعد بناء التطبيق. في غير نسخة الاختبار لا يفعل شيئاً.
  static Future<void> install(GlobalKey<NavigatorState> navigatorKey) async {
    if (kIsWeb || _sub != null) return;
    final String package;
    try {
      package = (await PackageInfo.fromPlatform()).packageName;
    } catch (_) {
      return;
    }
    if (package != kQaPackage) return;
    // نسخة الاختبار وحدها: سجلات التطبيق تصل logcat لتشخيص المزامنة.
    // ignore: invalid_use_of_visible_for_testing_member
    AppLogger.debugOverride = true;
    // ignore: invalid_use_of_visible_for_testing_member, avoid_print
    AppLogger.sink = (m) => print('NABOO_LOG $m');
    final links = AppLinks();
    _sub = links.uriLinkStream.listen((u) => unawaited(_handle(u, navigatorKey)));
    final initial = await links.getInitialLink();
    if (initial != null) unawaited(_handle(initial, navigatorKey));
    _log('ready', {'package': package});
  }

  static void _log(String kind, Map<String, Object?> data) {
    for (final l in qaLogLines(kind, data)) {
      // print لا debugPrint: يصل logcat في نسخة release أيضاً.
      // ignore: avoid_print
      print(l);
    }
  }

  static Future<void> _handle(Uri uri, GlobalKey<NavigatorState> key) async {
    final cmd = parseQaUri(uri, qaBuild: true);
    if (cmd == null) return;
    // التطبيق قد يكون في الإقلاع: ننتظر شجرة الواجهة حتى 20 ثانية.
    BuildContext? ctx;
    for (var i = 0; i < 40 && (ctx = key.currentContext) == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (ctx == null || !ctx.mounted) return _log('error', {'error': 'no_ui'});
    try {
      switch (cmd) {
        case QaAsk(:final question, :final routeId):
          await _ask(ctx, question, routeId ?? AppContentRoutes.home);
        case QaState():
          _log('state', qaStateOf(AssistantSession.instance.controllerFor(ctx)));
        case QaWho():
          _log('who', await _who(ctx));
        case QaReset():
          await _reset(ctx);
        case QaSeed(:final over):
          _log('seed', await DemoShopSeeder().seed(over: over));
      }
    } catch (e) {
      _log('error', {'error': e.toString()});
    }
  }

  static Future<void> _ask(BuildContext ctx, String q, String routeId) async {
    try {
      await AssistantRollout.instance.refresh();
    } catch (_) {
      /* القيمة المحفوظة تكفي */
    }
    if (!AssistantRollout.instance.v2Enabled) return _log('error', {'error': 'v2_disabled'});
    // الصفحة تُفتح كما يفتحها المستخدم، ثم يُرسل السؤال من المتحكم نفسه.
    unawaited(openNabooAssistant(ctx, currentRouteId: routeId));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!ctx.mounted) return;
    final c = AssistantSession.instance.controllerFor(ctx);
    for (var i = 0; i < 20 && c.busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    await c.ask(q);
    _log('reply', qaStateOf(c));
  }

  /// من المستخدم الحالي وما يراه المساعد (لا أسماء ولا أسرار): لفحص الصلاحيات في ت2.
  static Future<Map<String, Object?>> _who(BuildContext ctx) async {
    final auth = ctx.read<AuthProvider>();
    final perms = ctx.read<PermissionsProvider>();
    final c = AssistantSession.instance.controllerFor(ctx);
    final tc = c.toolContext();
    final rows = auth.userId == null
        ? const <Map<String, Object?>>[]
        : await (await DatabaseHelper().database).query(
            'user_permissions',
            columns: ['tenantId', 'permissionKey', 'isAllowed'],
            where: 'userId = ? AND permissionKey IN (?, ?, ?)',
            whereArgs: [auth.userId, PermissionKeys.cashView, PermissionKeys.debtsPanel, PermissionKeys.assistantFull],
          );
    return {
      'user_id': auth.userId,
      'role': auth.roleKey,
      'owner': auth.isOwner,
      'level': tc.level.name,
      'perms_loading': perms.isLoading,
      'can_cash': perms.can(PermissionKeys.cashView),
      'can_debts': perms.can(PermissionKeys.debtsPanel),
      'rows': rows,
      'tools': c.registry.allowedNames(tc),
    };
  }

  static Future<void> _reset(BuildContext ctx) async {
    final c = AssistantSession.instance.controllerFor(ctx);
    c.stop();
    var deleted = 0;
    final store = c.store;
    final tenant = c.tenantId?.call();
    final user = c.userKey?.call();
    if (store != null && tenant != null && user != null) {
      for (final t in await store.listThreads(tenantId: tenant, userKey: user)) {
        await store.deleteThread(t.id);
        deleted++;
      }
    }
    c.newThread();
    _log('reset', {'deleted_threads': deleted});
  }
}
