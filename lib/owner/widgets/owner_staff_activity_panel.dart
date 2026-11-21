import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/design_tokens.dart';
import '../providers/owner_command_center_provider.dart';
import '../utils/owner_dashboard_gold_border.dart';
import 'owner_dashboard_panel_expand_control.dart';
import '../../models/recent_activity_entry.dart';
import '../../services/database_helper.dart';
import '../models/owner_kpi_models.dart';

/// تبويب تصفية نوع النشاط — مستوحى من Fintrack.
enum _ActivityKindFilter { all, invoices, cash, other }

/// لوحة نشاطات الموظفين لصاحب العمل — تصميم بطاقات ناعمة + شريط موظفين.
class OwnerStaffActivityPanel extends StatefulWidget {
  const OwnerStaffActivityPanel({
    super.key,
    required this.staffUsers,
    required this.activeShiftStaffNames,
    required this.selectedStaffName,
    required this.selectedStaffUserId,
    required this.onStaffSelected,
    this.maxPanelHeight = 520,
    this.onEntryTap,
    this.fullScreen = false,
    this.compact = false,
  });

  final List<StaffUserRow> staffUsers;
  final Set<String> activeShiftStaffNames;
  final String? selectedStaffName;
  final int? selectedStaffUserId;
  final void Function(String? staffName, {int? staffUserId}) onStaffSelected;
  final double maxPanelHeight;
  final void Function(RecentActivityEntry entry)? onEntryTap;
  /// عند true — تُعرض داخل صفحة ملء الشاشة (قائمة بارتفاع كامل).
  final bool fullScreen;
  /// وضع مضغوط للهاتف — رأس أبسط وقائمة أطول لإظهار 3 عناصر على الأقل.
  final bool compact;

  @override
  State<OwnerStaffActivityPanel> createState() =>
      _OwnerStaffActivityPanelState();
}

class _OwnerStaffActivityPanelState extends State<OwnerStaffActivityPanel> {
  static const int _previewCount = 3;
  static const int _fullHistoryPerSource = 4000;

  static Color _accent(BuildContext context) =>
      Theme.of(context).colorScheme.primary;
  final DatabaseHelper _db = DatabaseHelper();
  _ActivityKindFilter _kindFilter = _ActivityKindFilter.all;
  List<RecentActivityEntry> _all = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void didUpdateWidget(covariant OwnerStaffActivityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedStaffName != widget.selectedStaffName ||
        oldWidget.selectedStaffUserId != widget.selectedStaffUserId) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _db.getRecentActivityFeed(
        staffName: widget.selectedStaffName,
        staffUserId: widget.selectedStaffUserId,
        perSource: widget.fullScreen ? _fullHistoryPerSource : 80,
        maxTotal: widget.fullScreen ? null : 80,
      );
      if (!mounted) return;
      setState(() {
        _all = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<RecentActivityEntry> get _visible {
    switch (_kindFilter) {
      case _ActivityKindFilter.all:
        return _all;
      case _ActivityKindFilter.invoices:
        return _all
            .where((e) => e.kind == RecentActivityKind.invoice)
            .toList();
      case _ActivityKindFilter.cash:
        return _all
            .where((e) => e.kind == RecentActivityKind.cashMovement)
            .toList();
      case _ActivityKindFilter.other:
        return _all
            .where(
              (e) => RecentActivityEntry.kindIsOtherThanInvoiceOrCash(e.kind),
            )
            .toList();
    }
  }

  bool get _showStaffBadge =>
      widget.selectedStaffName == null || widget.selectedStaffName!.isEmpty;

  bool get _showKindFilters => widget.fullScreen || !widget.compact;

  List<RecentActivityEntry> get _displayItems {
    final items = _visible;
    if (widget.fullScreen) return items;
    return items.take(_previewCount).toList(growable: false);
  }

  void _openFullScreen() {
    openOwnerDashboardFullScreenPanel(
      context,
      title: 'سجل النشاطات',
      body: Consumer<OwnerCommandCenterProvider>(
        builder: (context, center, _) {
          return OwnerStaffActivityPanel(
            fullScreen: true,
            staffUsers: widget.staffUsers,
            activeShiftStaffNames: widget.activeShiftStaffNames,
            selectedStaffName: center.staffFilter,
            selectedStaffUserId: center.staffUserIdFilter,
            onStaffSelected: widget.onStaffSelected,
            onEntryTap: widget.onEntryTap,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shadowAlpha =
        Theme.of(context).brightness == Brightness.dark ? 0.28 : 0.07;

    final listBody = _buildListBody(context, cs);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: widget.fullScreen ? MainAxisSize.max : MainAxisSize.min,
      children: [
        _buildHeader(context, cs),
        _buildStaffStrip(context, cs),
        if (_showKindFilters) ...[
          _buildKindFilters(context, cs),
          const Divider(height: 1),
        ] else
          const Divider(height: 1),
        if (widget.fullScreen)
          Expanded(child: listBody)
        else
          listBody,
      ],
    );

    if (widget.fullScreen) {
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 12),
        child: Container(
          decoration: OwnerDashboardGoldBorder.boxDecoration(context),
          clipBehavior: Clip.antiAlias,
          child: content,
        ),
      );
    }

    return Container(
      decoration: OwnerDashboardGoldBorder.boxDecoration(
        context,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: shadowAlpha),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme cs) {
    if (widget.compact) {
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'نشاط الموظفين',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: cs.onSurface,
                ),
              ),
            ),
            if (!widget.fullScreen)
              IconButton(
                tooltip: 'عرض كل السجل',
                onPressed: _openFullScreen,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(Icons.open_in_full_rounded, color: cs.primary, size: 20),
              ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _load,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: _loading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    )
                  : Icon(Icons.refresh_rounded, color: _accent(context)),
            ),
          ],
        ),
      );
    }

    final selectedLabel = widget.selectedStaffName?.trim();
    final subtitle = (selectedLabel != null && selectedLabel.isNotEmpty)
        ? 'نشاطات $selectedLabel'
        : 'نشاطات جميع الموظفين';

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 12, 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _accent(context),
                  Color.lerp(_accent(context), Colors.black, 0.18)!,
                ],
                begin: AlignmentDirectional.topEnd,
                end: AlignmentDirectional.bottomStart,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.receipt_long_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'نشاط الموظفين',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (!widget.fullScreen)
            IconButton(
              tooltip: 'عرض كل السجل',
              onPressed: _openFullScreen,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: Icon(Icons.open_in_full_rounded, color: cs.primary, size: 20),
            ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: _loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                : Icon(Icons.refresh_rounded, color: _accent(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffStrip(BuildContext context, ColorScheme cs) {
    final users = widget.staffUsers;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StaffChip(
              label: 'الكل',
              selected: widget.selectedStaffUserId == null,
              isActiveNow: false,
              onTap: () => widget.onStaffSelected(null),
              accent: _accent(context),
              scheme: cs,
            ),
            const SizedBox(width: 8),
            for (final u in users) ...[
              _StaffChip(
                label: u.label,
                selected: widget.selectedStaffUserId != null
                    ? widget.selectedStaffUserId == u.id
                    : widget.selectedStaffName == u.label,
                isActiveNow: widget.activeShiftStaffNames.contains(u.label) ||
                    widget.activeShiftStaffNames.any(
                      (n) => n.toLowerCase() == u.label.toLowerCase(),
                    ),
                onTap: () => widget.onStaffSelected(
                  u.label,
                  staffUserId: u.id,
                ),
                accent: _accent(context),
                scheme: cs,
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKindFilters(BuildContext context, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _KindChip(
              label: 'الكل',
              selected: _kindFilter == _ActivityKindFilter.all,
              onTap: () => setState(() => _kindFilter = _ActivityKindFilter.all),
              accent: _accent(context),
              scheme: cs,
            ),
            const SizedBox(width: 8),
            _KindChip(
              label: 'فواتير',
              selected: _kindFilter == _ActivityKindFilter.invoices,
              onTap: () =>
                  setState(() => _kindFilter = _ActivityKindFilter.invoices),
              accent: _accent(context),
              scheme: cs,
            ),
            const SizedBox(width: 8),
            _KindChip(
              label: 'صندوق',
              selected: _kindFilter == _ActivityKindFilter.cash,
              onTap: () =>
                  setState(() => _kindFilter = _ActivityKindFilter.cash),
              accent: _accent(context),
              scheme: cs,
            ),
            const SizedBox(width: 8),
            _KindChip(
              label: 'أخرى',
              selected: _kindFilter == _ActivityKindFilter.other,
              onTap: () =>
                  setState(() => _kindFilter = _ActivityKindFilter.other),
              accent: _accent(context),
              scheme: cs,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListBody(BuildContext context, ColorScheme cs) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'تعذّر تحميل النشاط: $_error',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.error, fontSize: 13),
          ),
        ),
      );
    }
    if (_loading && _all.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = _displayItems;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_rounded, size: 44, color: cs.onSurfaceVariant),
              const SizedBox(height: 10),
              Text(
                widget.selectedStaffName != null
                    ? 'لا نشاط لهذا الموظف في هذه الفترة'
                    : 'لا نشاط في هذه الفترة',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'ستظهر هنا الفواتير وحركات الصندوق وورديات العمل.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: cs.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!widget.fullScreen) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 68,
                endIndent: 16,
                color: AppColors.accentGold.withValues(alpha: 0.25),
              ),
            _FintrackActivityRow(
              entry: items[i],
              scheme: cs,
              showStaffBadge: _showStaffBadge,
              stitchLayout: true,
              onTap: widget.onEntryTap == null
                  ? null
                  : () => widget.onEntryTap!(items[i]),
            ),
          ],
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        indent: 68,
        endIndent: 16,
        color: AppColors.accentGold.withValues(alpha: 0.25),
      ),
      itemBuilder: (context, i) {
        final e = items[i];
        return _FintrackActivityRow(
          entry: e,
          scheme: cs,
          showStaffBadge: _showStaffBadge,
          stitchLayout: true,
          onTap: widget.onEntryTap == null
              ? null
              : () => widget.onEntryTap!(e),
        );
      },
    );
  }
}

class _StaffChip extends StatelessWidget {
  const _StaffChip({
    required this.label,
    required this.selected,
    required this.isActiveNow,
    required this.onTap,
    required this.accent,
    required this.scheme,
  });

  final String label;
  final bool selected;
  final bool isActiveNow;
  final VoidCallback onTap;
  final Color accent;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final initial = label.isNotEmpty ? label.substring(0, 1) : '?';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 14, 8),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.65)
                  : AppColors.accentGold.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: selected
                        ? accent.withValues(alpha: 0.22)
                        : scheme.primaryContainer,
                    foregroundColor: selected ? accent : scheme.onPrimaryContainer,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (isActiveNow)
                    const PositionedDirectional(
                      end: -1,
                      bottom: -1,
                      child: _PulsingShiftDot(),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 13,
                  color: selected ? accent : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accent,
    required this.scheme,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.5)
                  : AppColors.accentGold.withValues(alpha: 0.45),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? accent : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _FintrackActivityRow extends StatelessWidget {
  const _FintrackActivityRow({
    required this.entry,
    required this.scheme,
    required this.showStaffBadge,
    this.stitchLayout = false,
    this.onTap,
  });

  final RecentActivityEntry entry;
  final ColorScheme scheme;
  final bool showStaffBadge;
  final bool stitchLayout;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final iconData = _iconForKind(entry.kind);
    final accent = _accentForKind(entry.kind);

    if (stitchLayout) {
      final actor = entry.actorName?.trim();
      final staffLine = (actor != null && actor.isNotEmpty)
          ? actor
          : (showStaffBadge && entry.title.trim().isNotEmpty
              ? entry.title.trim()
              : '');
      final description = entry.subtitle.trim().isNotEmpty
          ? entry.subtitle.trim()
          : entry.title.trim();

      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(21),
                  ),
                  child: Icon(iconData, color: accent, size: 21),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (staffLine.isNotEmpty)
                        Text(
                          staffLine,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                            color: scheme.onSurface,
                          ),
                        ),
                      if (staffLine.isNotEmpty) const SizedBox(height: 2),
                      Text(
                        entry.relativeTimeLabel,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.25,
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (entry.amountLabel.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    entry.amountLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: entry.amountIqd != null && entry.amountIqd! < 0
                          ? scheme.error
                          : scheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(iconData, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (showStaffBadge &&
                        entry.actorName != null &&
                        entry.actorName!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          entry.actorName!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (entry.amountLabel.isNotEmpty)
                    Text(
                      entry.amountLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: entry.amountIqd != null && entry.amountIqd! < 0
                            ? scheme.error
                            : scheme.primary,
                      ),
                    ),
                  if (entry.amountLabel.isNotEmpty) const SizedBox(height: 4),
                  Text(
                    entry.timeLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconForKind(RecentActivityKind kind) {
    switch (kind) {
      case RecentActivityKind.invoice:
        return Icons.receipt_rounded;
      case RecentActivityKind.cashMovement:
        return Icons.account_balance_wallet_rounded;
      case RecentActivityKind.parkedSale:
        return Icons.pause_circle_outline_rounded;
      case RecentActivityKind.loyalty:
        return Icons.card_giftcard_rounded;
      case RecentActivityKind.stockVoucher:
        return Icons.inventory_2_rounded;
      case RecentActivityKind.customerCreated:
        return Icons.person_add_alt_1_rounded;
      case RecentActivityKind.productCreated:
        return Icons.add_box_rounded;
      case RecentActivityKind.workShift:
        return Icons.schedule_rounded;
    }
  }

  static Color _accentForKind(RecentActivityKind kind) {
    switch (kind) {
      case RecentActivityKind.invoice:
        return const Color(0xFF059669);
      case RecentActivityKind.cashMovement:
        return const Color(0xFF5B5BD6);
      case RecentActivityKind.parkedSale:
        return const Color(0xFFF59E0B);
      case RecentActivityKind.loyalty:
        return const Color(0xFF7C3AED);
      case RecentActivityKind.stockVoucher:
        return const Color(0xFF0D9488);
      case RecentActivityKind.customerCreated:
        return const Color(0xFFDB2777);
      case RecentActivityKind.productCreated:
        return const Color(0xFFEA580C);
      case RecentActivityKind.workShift:
        return const Color(0xFF64748B);
    }
  }
}

/// نقطة خضراء نابضة — وردية مفتوحة (S5b Live).
class _PulsingShiftDot extends StatefulWidget {
  const _PulsingShiftDot();

  @override
  State<_PulsingShiftDot> createState() => _PulsingShiftDotState();
}

class _PulsingShiftDotState extends State<_PulsingShiftDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _pulse = Tween<double>(begin: 0.55, end: 1)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.surface;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        return Container(
          width: 10 + 4 * _pulse.value,
          height: 10 + 4 * _pulse.value,
          alignment: Alignment.center,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Color.lerp(
                const Color(0xFF22C55E),
                const Color(0xFF86EFAC),
                _pulse.value,
              ),
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.35 * _pulse.value),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
