import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../guide_controller.dart';
import '../guide_root_nav_observer.dart';

/// يربط تغيّر مسارات الجذر بـ [GuideController.onRouteChanged] (خطوات awaitTap).
class GuideNavLifecycleBinder extends StatefulWidget {
  const GuideNavLifecycleBinder({super.key, required this.child});

  final Widget child;

  @override
  State<GuideNavLifecycleBinder> createState() =>
      _GuideNavLifecycleBinderState();
}

class _GuideNavLifecycleBinderState extends State<GuideNavLifecycleBinder> {
  @override
  void initState() {
    super.initState();
    GuideRootNavObserver.instance.addListener(_onRoute);
  }

  @override
  void dispose() {
    GuideRootNavObserver.instance.removeListener(_onRoute);
    super.dispose();
  }

  void _onRoute(String routeId) {
    if (!mounted) return;
    context.read<GuideController>().onRouteChanged(routeId);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
