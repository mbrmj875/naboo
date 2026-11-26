import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../guides/guide_controller.dart';
import '../../guides/guide_tour.dart';
import '../../providers/auth_provider.dart';
import '../ui/assistant_session.dart';
import 'assistant_course.dart';

/// صفحة دورة الموظف الجديد (م3-14): مساره حسب صلاحياته وشريط إنجاز،
/// وللمالك قسم بنسب موظفيه من الجدول المزامَن.
class AssistantCourseScreen extends StatefulWidget {
  const AssistantCourseScreen({super.key, required this.canOpen, this.course});

  static const routeName = 'assistant_course';

  final bool Function(String routeId) canOpen;
  final AssistantCourse? course;

  @override
  State<AssistantCourseScreen> createState() => _AssistantCourseScreenState();
}

class _AssistantCourseScreenState extends State<AssistantCourseScreen> {
  AssistantCourse get _course => widget.course ?? AssistantCourse.instance;

  late final List<CourseTask> _path = courseFor(widget.canOpen);
  Set<String> _done = const {};
  List<CourseMemberProgress>? _members;
  bool _membersFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final g = context.read<GuideController>();
    final owner = context.read<AuthProvider>().isOwner;
    final done = await _course.doneFor(tenantId: g.tenantId, userKey: g.userKey);
    if (mounted) setState(() => _done = done);
    unawaited(_course.flush());
    if (!owner) return;
    try {
      final m = await _course.members();
      if (mounted) setState(() => _members = m);
    } catch (_) {
      if (mounted) setState(() => _membersFailed = true);
    }
  }

  Future<void> _start(CourseTask t) async {
    final g = context.read<GuideController>();
    final auth = context.read<AuthProvider>();
    _course.beginTask(t, tenantId: g.tenantId, userKey: g.userKey, userName: auth.displayName, pathTotal: _path.length);
    // الصفحة وصفحة المساعد تحتها تُغلقان، فيبدأ الإرشاد على الشاشة الحقيقية.
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.settings.name != AssistantCourseScreen.routeName && r.settings.name != 'assistant');
    AssistantSession.instance.beforeGuide?.call();
    await WidgetsBinding.instance.endOfFrame;
    final tour = t.tourId;
    if (tour != null) {
      await g.startTour(tour, fromChat: true, fromAssistant: true);
    } else {
      await g.startAdHoc([
        GuideStep(anchorId: t.anchorId!, title: t.title, body: t.hint, ensureRouteId: t.routeId),
      ], title: t.title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final done = _path.where((x) => _done.contains(x.id)).length;
    final owner = context.read<AuthProvider>().isOwner;
    return Scaffold(
      appBar: AppBar(title: const Text('دورة الموظف الجديد')),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
        children: [
          Text('أنجزت $done من ${_path.length}', style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _path.isEmpty ? 0 : done / _path.length,
            minHeight: 6,
            color: cs.secondary,
            backgroundColor: cs.outline.withValues(alpha: 0.35),
            semanticsLabel: 'التقدّم في الدورة',
            semanticsValue: '$done من ${_path.length}',
          ),
          const SizedBox(height: 16),
          for (final task in _path)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  _done.contains(task.id) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: _done.contains(task.id) ? cs.secondary : cs.onSurfaceVariant,
                  semanticLabel: _done.contains(task.id) ? 'منجزة' : 'غير منجزة',
                ),
                title: Text(task.title),
                trailing: TextButton(
                  onPressed: () => unawaited(_start(task)),
                  child: Text(_done.contains(task.id) ? 'أعد' : 'ابدأ'),
                ),
              ),
            ),
          if (owner) ...[
            const SizedBox(height: 20),
            Text('تقدّم الموظفين', style: t.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_membersFailed)
              Text('ما گدرت أجيب التقدّم. تأكد من الإنترنت.', style: t.textTheme.bodyMedium)
            else if (_members == null)
              const Center(
                child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
              )
            else if (_members!.isEmpty)
              Text('ما بدأ أي موظف الدورة بعد.', style: t.textTheme.bodyMedium)
            else
              for (final m in _members!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(m.name, style: t.textTheme.bodyLarge)),
                          Text('${(m.ratio * 100).round()}%', style: t.textTheme.labelLarge),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: m.ratio,
                        minHeight: 4,
                        color: cs.secondary,
                        backgroundColor: cs.outline.withValues(alpha: 0.35),
                      ),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
