import 'package:flutter/material.dart';

import '../providers/owner_command_center_provider.dart';
import 'owner_date_range_bar.dart';
import 'owner_dashboard_top_chrome.dart';

/// شريط الفترة الزمنية — ثابت تحت شريط الأدوات.
class OwnerDashboardV3PinnedSection extends StatelessWidget {
  const OwnerDashboardV3PinnedSection({
    super.key,
    required this.center,
  });

  final OwnerCommandCenterProvider center;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: OwnerDashboardChromeStyle.pinnedBackground(context),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 8),
        child: OwnerDateRangeBar(
          selected: center.dateRange,
          onChanged: center.setDateRange,
        ),
      ),
    );
  }
}
