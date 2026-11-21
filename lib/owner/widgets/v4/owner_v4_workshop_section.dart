import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../../models/recent_activity_entry.dart';
import '../../../services/database_helper.dart';
import '../../../utils/activity_timestamp.dart';
import '../../models/owner_command_center_snapshot.dart';
import '../../models/owner_section_ttl.dart';
import '../../providers/owner_command_center_provider.dart';
import '../../theme/owner_dashboard_tokens.dart';
import 'owner_v4_actions.dart';
import 'owner_v4_parts.dart';

/// يجلب آخر نشاطات الموظفين — قابل للاستبدال في الاختبارات.
typedef OwnerV4ActivityLoader = Future<List<RecentActivityEntry>> Function();

Future<List<RecentActivityEntry>> _defaultActivityLoader() {
  return DatabaseHelper().getRecentActivityFeed(perSource: 5, maxTotal: 3);
}

String ownerV4ClockAr(DateTime at) {
  final h = at.hour.toString().padLeft(2, '0');
  final m = at.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// القسم 3 — «الورشة الآن»: سيارات، ورديات نشطة بالأسماء، آخر 3 أنشطة.
class OwnerV4WorkshopSection extends StatelessWidget {
  const OwnerV4WorkshopSection({
    super.key,
    required this.center,
    required this.snapshot,
    required this.actions,
    this.activityLoader,
  });

  final OwnerCommandCenterProvider center;
  final OwnerCommandCenterSnapshot snapshot;
  final OwnerV4Actions actions;
  final OwnerV4ActivityLoader? activityLoader;

  @override
  Widget build(BuildContext context) {
    final t = OwnerDashboardTokens.of(context);
    final carsState = ownerV4SectionState(snapshot.oilActiveCars);
    final cars = snapshot.oilActiveCars?.data;
    final shiftsState = ownerV4SectionState(snapshot.openShifts);
    final shifts = snapshot.openShifts.data?.items ?? const [];

    final carsTile = OwnerV4StatTile(
      key: const ValueKey('v4-cars'),
      label: 'في الورشة',
      icon: Icons.directions_car_outlined,
      value: '${cars?.activeCount ?? 0}',
      subtitle: cars == null
          ? null
          : (cars.staleWaitingCount > 0
                ? 'منها ${cars.staleWaitingCount} تنتظر طويلاً'
                : 'سيارات قيد الخدمة'),
      loading: carsState.loading,
      errorText: carsState.error,
      onRetry: () => center.refreshSection(OwnerSectionIds.oilActiveCars),
      onTap: actions.openOilLog,
    );
    final shiftsTile = OwnerV4StatTile(
      key: const ValueKey('v4-shifts'),
      label: 'ورديات نشطة',
      icon: Icons.badge_outlined,
      value: '${shifts.length}',
      subtitle: shifts.isEmpty ? 'لا أحد في وردية الآن' : 'موظفون في العمل',
      loading: shiftsState.loading,
      errorText: shiftsState.error,
      onRetry: () => center.refreshSection(OwnerSectionIds.openShifts),
      onTap: actions.openStaffActivity,
    );

    return OwnerV4Section(
      title: 'الورشة الآن',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OwnerV4AdaptiveRow(
            minChildWidth: 130,
            children: [carsTile, shiftsTile],
          ),
          if (shifts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in shifts)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: t.navySoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 8, color: t.success),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            s.openedAt.isEmpty
                                ? s.staffName
                                : '${s.staffName} · منذ ${ownerV4ClockAr(parseActivityTimestamp(s.openedAt))}',
                            style: TextStyle(
                              color: t.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'آخر نشاط للموظفين',
                  style: TextStyle(
                    color: t.inkMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('v4-staff-all'),
                onPressed: actions.openStaffActivity,
                style: TextButton.styleFrom(
                  foregroundColor: t.ink,
                  minimumSize: const Size(44, 40),
                ),
                child: const Text('عرض الكل'),
              ),
            ],
          ),
          _RecentActivityPreview(
            loader: activityLoader ?? _defaultActivityLoader,
            refreshKey: snapshot.sales.fetchedAt,
          ),
        ],
      ),
    );
  }
}

class _RecentActivityPreview extends StatefulWidget {
  const _RecentActivityPreview({
    required this.loader,
    required this.refreshKey,
  });

  final OwnerV4ActivityLoader loader;

  /// يتغير مع كل تحديث للوحة فيُعاد الجلب.
  final Object? refreshKey;

  @override
  State<_RecentActivityPreview> createState() => _RecentActivityPreviewState();
}

class _RecentActivityPreviewState extends State<_RecentActivityPreview> {
  List<RecentActivityEntry>? _rows;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _RecentActivityPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final rows = await widget.loader();
      if (!mounted) return;
      setState(() {
        _rows = rows.take(3).toList(growable: false);
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = OwnerDashboardTokens.of(context);
    final rows = _rows;
    if (_failed) {
      return Text(
        'تعذّر تحميل النشاط',
        style: TextStyle(color: t.danger, fontSize: 13),
      );
    }
    if (rows == null) {
      return Text(
        'جارٍ التحميل…',
        style: TextStyle(color: t.inkMuted, fontSize: 13),
      );
    }
    if (rows.isEmpty) {
      return Text(
        'لا نشاط مسجّل بعد',
        style: TextStyle(color: t.inkMuted, fontSize: 13),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(top: 7),
                  decoration: BoxDecoration(
                    color: t.gold,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title,
                        style: TextStyle(
                          color: t.ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        [
                          if ((e.actorName ?? '').trim().isNotEmpty)
                            e.actorName!.trim(),
                          ownerV4ClockAr(e.at.toLocal()),
                        ].join(' · '),
                        style: TextStyle(color: t.inkMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
