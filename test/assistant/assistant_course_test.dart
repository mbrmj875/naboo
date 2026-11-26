import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/course/assistant_course.dart';
import 'package:naboo/guides/guide_controller.dart';
import 'package:naboo/guides/guide_tour.dart';
import 'package:naboo/navigation/content_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Remote implements CourseRemote {
  final rows = <Map<String, Object?>>[];
  bool offline = false;

  @override
  Future<void> upsert(List<Map<String, Object?>> r) async {
    if (offline) throw Exception('offline');
    for (final row in r) {
      rows.removeWhere((x) => x['user_key'] == row['user_key'] && x['task_id'] == row['task_id']);
      rows.add(row);
    }
  }

  @override
  Future<List<Map<String, Object?>>> fetchAll() async => rows;
}

void main() {
  late _Remote remote;
  late AssistantCourse course;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    remote = _Remote();
    course = AssistantCourse(remote: remote);
  });

  tearDown(() => GuideController.onTourEnded = null);

  test('كل مهمة موصوفة في الخريطة، ومعرّفاتها صالحة للجدول', () {
    for (final t in kCourseTasks) {
      expect(AssistantCourse.isMapped(t), isTrue, reason: t.id);
      expect(RegExp(r'^[a-z0-9_]{1,60}$').hasMatch(t.id), isTrue, reason: t.id);
      expect(t.tourId != null || t.anchorId != null, isTrue, reason: t.id);
    }
  });

  test('الفني والكاشير يريان مسارين مختلفين', () {
    const technician = {
      AppContentRoutes.oilChangeCreate,
      AppContentRoutes.oilServicesLog,
      AppContentRoutes.carWashCreate,
    };
    const cashier = {AppContentRoutes.oilDirectSale, AppContentRoutes.customers, AppContentRoutes.expenses};
    final a = courseFor(technician.contains).map((t) => t.id).toSet();
    final b = courseFor(cashier.contains).map((t) => t.id).toSet();
    expect(a, containsAll(['oil_first_card', 'car_wash']));
    expect(b, {'direct_sale', 'customer_add', 'expense_add'});
    expect(a.intersection(b), isEmpty);
  });

  test('المهمة تُسجَّل حين تكتمل جولتها فقط', () async {
    final task = kCourseTasks.firstWhere((t) => t.id == 'car_wash');
    course.beginTask(task, tenantId: 3, userKey: 'emp1', userName: 'علي', pathTotal: 4);
    GuideController.onTourEnded!(GuideTourIds.carWashCreate, completed: false);
    await Future<void>.delayed(Duration.zero);
    expect(await course.doneFor(tenantId: 3, userKey: 'emp1'), isEmpty);

    course.beginTask(task, tenantId: 3, userKey: 'emp1', userName: 'علي', pathTotal: 4);
    GuideController.onTourEnded!(GuideTourIds.carWashCreate, completed: true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(await course.doneFor(tenantId: 3, userKey: 'emp1'), {'car_wash'});
    expect(remote.rows.single['path_total'], 4);
  });

  test('بلا إنترنت: يبقى في الطابور ويُرفع لاحقاً', () async {
    remote.offline = true;
    await course.record('expense_add', tenantId: 3, userKey: 'emp2', userName: 'حسن', pathTotal: 3);
    expect(remote.rows, isEmpty);
    expect(await course.doneFor(tenantId: 3, userKey: 'emp2'), {'expense_add'});
    remote.offline = false;
    await course.flush();
    expect(remote.rows.single['task_id'], 'expense_add');
  });

  test('المالك يرى نسبة كل موظف من مساره', () async {
    await course.record('direct_sale', tenantId: 3, userKey: 'cash', userName: 'كاشير', pathTotal: 3);
    await course.record('oil_first_card', tenantId: 3, userKey: 'tech', userName: 'فني', pathTotal: 4);
    await course.record('car_wash', tenantId: 3, userKey: 'tech', userName: 'فني', pathTotal: 4);
    final m = await course.members();
    final byKey = {for (final x in m) x.userKey: x};
    expect(byKey['tech']!.ratio, 0.5);
    expect(byKey['cash']!.ratio, closeTo(1 / 3, 0.001));
    expect(m.first.userKey, 'tech');
  });
}
