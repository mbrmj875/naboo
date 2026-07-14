import 'package:flutter/material.dart';

/// أيقونة سهمين متعاكسين — واحد لأعلى وواحد لأسفل (توسيع لملء الشاشة).
class OwnerDashboardVerticalArrowsIcon extends StatelessWidget {
  const OwnerDashboardVerticalArrowsIcon({
    super.key,
    this.size = 22,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    final arrowSize = size * 0.46;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: AlignmentDirectional.topCenter,
            child: Icon(
              Icons.keyboard_arrow_up_rounded,
              size: arrowSize,
              color: c,
            ),
          ),
          Align(
            alignment: AlignmentDirectional.bottomCenter,
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: arrowSize,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

/// زر فتح اللوحة بملء الشاشة.
class OwnerDashboardPanelExpandControl extends StatelessWidget {
  const OwnerDashboardPanelExpandControl({
    super.key,
    required this.onExpand,
  });

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'ملء الشاشة',
      onPressed: onExpand,
      icon: const OwnerDashboardVerticalArrowsIcon(),
    );
  }
}

/// يفتح محتوى اللوحة في صفحة كاملة مع زر إغلاق.
Future<void> openOwnerDashboardFullScreenPanel(
  BuildContext context, {
  required String title,
  required Widget body,
}) {
  final cs = Theme.of(context).colorScheme;
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: cs.surface,
            appBar: AppBar(
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              centerTitle: false,
              leading: IconButton(
                tooltip: 'إغلاق',
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            body: SafeArea(
              child: body,
            ),
          ),
        );
      },
    ),
  );
}
