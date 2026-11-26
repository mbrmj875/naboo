import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../guides/guide_anchor.dart';
import '../../guides/guide_controller.dart';
import '../../guides/guide_tour.dart';
import '../../navigation/content_navigation.dart';
import '../screen_map/screen_map.dart';

/// مهمة في دورة الموظف الجديد (ق63، م3-14).
///
/// كل مهمة تمرّ بجولة جاهزة، أو تأخذ للشاشة وتؤشّر على زرها. تظهر للموظف
/// فقط إن كان يستطيع فتح شاشتها، فيرى الفني والكاشير مسارين مختلفين.
class CourseTask {
  const CourseTask(this.id, this.title, {required this.routeId, this.tourId, this.anchorId, this.hint = ''});

  final String id;
  final String title;
  final String routeId;
  final String? tourId;
  final String? anchorId;
  final String hint;
}

const List<CourseTask> kCourseTasks = [
  CourseTask(
    'oil_first_card',
    'تسجيل بطاقة غيار',
    routeId: AppContentRoutes.oilChangeCreate,
    tourId: GuideTourIds.oilFirstRun,
  ),
  CourseTask(
    'oil_plate_autofill',
    'جلب بيانات سيارة سابقة',
    routeId: AppContentRoutes.oilChangeCreate,
    tourId: GuideTourIds.oilPlateAutofill,
  ),
  CourseTask(
    'oil_pending',
    'إكمال بطاقة معلّقة',
    routeId: AppContentRoutes.oilServicesLog,
    tourId: GuideTourIds.oilPendingTab,
  ),
  CourseTask(
    'oil_catalog',
    'إضافة زيت للكتالوج',
    routeId: AppContentRoutes.oilChangeCreate,
    tourId: GuideTourIds.oilCatalogOil,
  ),
  CourseTask('car_wash', 'تسجيل غسلة', routeId: AppContentRoutes.carWashCreate, tourId: GuideTourIds.carWashCreate),
  CourseTask(
    'direct_sale',
    'بيع مباشر بلا بطاقة',
    routeId: AppContentRoutes.oilDirectSale,
    anchorId: OilGuideAnchors.directSalePick,
    hint: 'من هنا تختار المنتج وتبيعه لزبون عابر.',
  ),
  CourseTask(
    'customer_add',
    'إضافة زبون',
    routeId: AppContentRoutes.customers,
    anchorId: OilGuideAnchors.customersAdd,
    hint: 'من هنا تضيف زبوناً باسمه ورقمه.',
  ),
  CourseTask(
    'expense_add',
    'تسجيل مصروف',
    routeId: AppContentRoutes.expenses,
    anchorId: OilGuideAnchors.expensesAdd,
    hint: 'كل مصروف يُخصم من الصندوق.',
  ),
  CourseTask(
    'product_add',
    'إضافة منتج',
    routeId: AppContentRoutes.addProduct,
    tourId: GuideTourIds.productAddOverview,
  ),
  CourseTask(
    'stocktaking',
    'عمل جرد',
    routeId: AppContentRoutes.inventoryStocktaking,
    anchorId: OilGuideAnchors.stocktakingNew,
    hint: 'تعدّ البضاعة وتقارنها بالمسجّل.',
  ),
  CourseTask(
    'barcode_print',
    'طباعة ملصقات باركود',
    routeId: AppContentRoutes.inventoryBarcodeLabels,
    anchorId: OilGuideAnchors.barcodeLabelsPrint,
    hint: 'تطبع الاسم والسعر والباركود.',
  ),
];

/// مسار هذا الموظف: المهام التي يستطيع فتح شاشاتها.
List<CourseTask> courseFor(bool Function(String routeId) canOpen) => [
  for (final t in kCourseTasks)
    if (canOpen(t.routeId)) t,
];

/// تقدّم موظف واحد كما يراه المالك.
class CourseMemberProgress {
  CourseMemberProgress(this.userKey, this.name);
  final String userKey;
  String name;
  final Set<String> done = {};

  /// عدد مهام مساره كما سجّله جهازه؛ 0 إن لم يُعرف.
  int pathTotal = 0;

  double get ratio {
    final total = pathTotal > 0 ? pathTotal : kCourseTasks.length;
    return (done.length / total).clamp(0, 1).toDouble();
  }
}

/// مكان الكتابة على الخادم؛ منفصل حتى يُختبر بلا شبكة.
abstract class CourseRemote {
  Future<void> upsert(List<Map<String, Object?>> rows);
  Future<List<Map<String, Object?>>> fetchAll();
}

class SupabaseCourseRemote implements CourseRemote {
  const SupabaseCourseRemote();

  static const table = 'assistant_course_progress';

  @override
  Future<void> upsert(List<Map<String, Object?>> rows) async {
    await Supabase.instance.client.from(table).upsert(rows, onConflict: 'tenant_id,user_key,task_id');
  }

  @override
  Future<List<Map<String, Object?>>> fetchAll() async {
    final r = await Supabase.instance.client.from(table).select('user_key,user_name,task_id,path_total').limit(2000);
    return [for (final row in r) Map<String, Object?>.from(row)];
  }
}

/// تقدّم الدورة: يُحفظ على الجهاز فوراً، ويُرفع للجدول المزامَن حين يتاح.
/// ما لم يُرفع يبقى في طابور ويُعاد مع التسجيل التالي أو فتح الدورة.
class AssistantCourse {
  AssistantCourse({CourseRemote? remote}) : remote = remote ?? const SupabaseCourseRemote();

  static final AssistantCourse instance = AssistantCourse();

  CourseRemote remote;

  static const _pendingKey = 'assistant_course_pending';
  static String _doneKey(int tenant, String user) => 'assistant_course_done_${tenant}_$user';

  /// المهمة التي بدأها المستخدم من صفحة الدورة، وتُسجَّل حين تكتمل جولتها.
  String? _activeTask;
  String? _activeTour;
  int _tenant = 0;
  String _user = '';
  String _userName = '';
  int _pathTotal = 0;

  Future<Set<String>> doneFor({required int tenantId, required String userKey}) async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_doneKey(tenantId, userKey)) ?? const []).toSet();
  }

  /// يربط اكتمال الجولة بالمهمة: يُستدعى قبل بدء جولتها.
  void beginTask(
    CourseTask task, {
    required int tenantId,
    required String userKey,
    required String userName,
    int pathTotal = 0,
  }) {
    _pathTotal = pathTotal;
    _activeTask = task.id;
    _activeTour = task.tourId ?? GuideController.adHocTourId;
    _tenant = tenantId;
    _user = userKey;
    _userName = userName;
    GuideController.onTourEnded = _onTourEnded;
  }

  void _onTourEnded(String tourId, {required bool completed}) {
    final task = _activeTask;
    if (task == null || tourId != _activeTour) return;
    _activeTask = null;
    _activeTour = null;
    if (completed) {
      unawaited(record(task, tenantId: _tenant, userKey: _user, userName: _userName, pathTotal: _pathTotal));
    }
  }

  Future<void> record(
    String taskId, {
    required int tenantId,
    required String userKey,
    required String userName,
    int pathTotal = 0,
  }) async {
    final p = await SharedPreferences.getInstance();
    final key = _doneKey(tenantId, userKey);
    final done = (p.getStringList(key) ?? const []).toSet()..add(taskId);
    await p.setStringList(key, done.toList()..sort());
    final pending = p.getStringList(_pendingKey) ?? const [];
    final name = userName.replaceAll('|', ' ');
    final entry = '$userKey|$taskId|$pathTotal|${name.length > 80 ? name.substring(0, 80) : name}';
    await p.setStringList(_pendingKey, {...pending, entry}.toList());
    await flush();
  }

  /// يرفع الطابور. الفشل يتركه كما هو.
  Future<void> flush() async {
    final p = await SharedPreferences.getInstance();
    final pending = p.getStringList(_pendingKey) ?? const [];
    if (pending.isEmpty) return;
    final rows = <Map<String, Object?>>[];
    for (final e in pending) {
      final parts = e.split('|');
      if (parts.length < 4) continue;
      rows.add({
        'user_key': parts[0],
        'task_id': parts[1],
        'path_total': int.tryParse(parts[2]) ?? 0,
        'user_name': parts[3],
        'done_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
    try {
      await remote.upsert(rows).timeout(const Duration(seconds: 8));
      await p.setStringList(_pendingKey, const []);
    } catch (_) {}
  }

  /// للمالك: نسبة كل موظف من الجدول المزامَن.
  Future<List<CourseMemberProgress>> members() async {
    await flush();
    final rows = await remote.fetchAll().timeout(const Duration(seconds: 10));
    final by = <String, CourseMemberProgress>{};
    final known = {for (final t in kCourseTasks) t.id};
    for (final r in rows) {
      final key = '${r['user_key']}';
      final m = by.putIfAbsent(key, () => CourseMemberProgress(key, '${r['user_name'] ?? key}'));
      final name = r['user_name'];
      if (name is String && name.isNotEmpty) m.name = name;
      final total = r['path_total'];
      if (total is int && total > m.pathTotal) m.pathTotal = total;
      final task = '${r['task_id']}';
      if (known.contains(task)) m.done.add(task);
    }
    final out = by.values.toList()..sort((a, b) => b.done.length.compareTo(a.done.length));
    return out;
  }

  /// شاشة المهمة موصوفة في الخريطة؟ (يفحصه الاختبار لكل مهمة).
  static bool isMapped(CourseTask t) =>
      AppScreenMap.byRoute(t.routeId) != null &&
      (t.anchorId == null || AppScreenMap.anchorsOn(t.routeId).contains(t.anchorId));
}
