import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// سطر صغير ثابت أعلى لوحة المالك: «آخر مزامنة: قبل … دقائق».
///
/// عند انقطاع الشبكة الفعلي يصير تنبيهاً: الأرقام من هذا الجهاز فقط حتى
/// آخر مزامنة — فلا يظن المالك أنها تشمل مبيعات الأجهزة الأخرى.
class OwnerDataStatusLine extends StatefulWidget {
  const OwnerDataStatusLine({
    super.key,
    required this.lastSyncAt,
    required this.isOffline,
    this.now = DateTime.now,
    this.tick = const Duration(seconds: 30),
    this.syncing = false,
  });

  final ValueListenable<DateTime?> lastSyncAt;
  final bool isOffline;
  final DateTime Function() now;
  final Duration tick;

  /// مزامنة جارية: مؤشر دوار صغير + «جارٍ المزامنة…» بدل شريط كبير.
  final bool syncing;

  @override
  State<OwnerDataStatusLine> createState() => _OwnerDataStatusLineState();
}

class _OwnerDataStatusLineState extends State<OwnerDataStatusLine> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // يحدّث «قبل … دقائق» مع مرور الوقت دون انتظار مزامنة جديدة.
    _timer = Timer.periodic(widget.tick, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: widget.lastSyncAt,
      builder: (context, last, _) {
        final base = ownerDataStatusText(
          lastSyncAt: last,
          isOffline: widget.isOffline,
          now: widget.now(),
        );
        final syncing = widget.syncing && !widget.isOffline;
        final text = syncing ? 'جارٍ المزامنة… · $base' : base;
        final cs = Theme.of(context).colorScheme;
        final offline = widget.isOffline;
        final fg = offline ? cs.onErrorContainer : cs.onSurfaceVariant;
        final line = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 2),
              child: syncing
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fg,
                      ),
                    )
                  : Icon(
                      offline
                          ? Icons.wifi_off_rounded
                          : Icons.cloud_done_outlined,
                      size: 16,
                      color: fg,
                    ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                softWrap: true,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: fg,
                  fontWeight: offline ? FontWeight.w700 : FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ),
          ],
        );
        return Semantics(
          liveRegion: offline,
          container: true,
          label: text,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 2, 14, 6),
              child: offline
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: line,
                      ),
                    )
                  : line,
            ),
          ),
        );
      },
    );
  }
}

/// نص السطر — منفصل ليُختبر بلا واجهة.
String ownerDataStatusText({
  required DateTime? lastSyncAt,
  required bool isOffline,
  required DateTime now,
}) {
  final sync = lastSyncAt == null
      ? 'آخر مزامنة: لم تتم بعد'
      : 'آخر مزامنة: ${ownerSyncAgeAr(now.difference(lastSyncAt))}';
  if (!isOffline) return sync;
  return 'لا إنترنت — الأرقام من هذا الجهاز فقط · $sync';
}

/// «الآن» / «قبل دقيقتين» / «قبل 5 دقائق» / «قبل 3 ساعات» / «قبل يومين».
String ownerSyncAgeAr(Duration age) {
  if (age.isNegative || age.inSeconds < 60) return 'الآن';
  if (age.inMinutes < 60) {
    return 'قبل ${_countAr(age.inMinutes, 'دقيقة', 'دقيقتين', 'دقائق', 'دقيقة')}';
  }
  if (age.inHours < 24) {
    return 'قبل ${_countAr(age.inHours, 'ساعة', 'ساعتين', 'ساعات', 'ساعة')}';
  }
  return 'قبل ${_countAr(age.inDays, 'يوم', 'يومين', 'أيام', 'يوماً')}';
}

String _countAr(int n, String one, String two, String few, String many) {
  if (n == 1) return one;
  if (n == 2) return two;
  if (n >= 3 && n <= 10) return '$n $few';
  return '$n $many';
}
