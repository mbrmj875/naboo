import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/business_audit_event.dart';
import '../services/business_audit_log_service.dart';
import '../../services/license_service.dart';
import '../../utils/app_logger.dart';
import '../utils/owner_dashboard_gold_border.dart';
import 'owner_dashboard_panel_expand_control.dart';
import 'owner_kpi_card.dart';
import 'owner_kpi_card_skeleton.dart';

final _auditTimeFmt = DateFormat('d/M HH:mm', 'ar_SA');

/// آخر تعديلات حساسة — cursor pagination + فلتر أيقونات (S5b).
class OwnerSensitiveActionsPanel extends StatefulWidget {
  const OwnerSensitiveActionsPanel({
    super.key,
    required this.tenantId,
    this.maxHeight = 320,
    this.fullScreen = false,
    this.compact = false,
    this.onEventTap,
  });

  final int tenantId;
  final double maxHeight;
  final bool fullScreen;
  /// معاينة مختصرة: آخر 3 أحداث فقط (مثل نشاط الموظفين).
  final bool compact;
  final void Function(BusinessAuditEvent event)? onEventTap;

  @override
  State<OwnerSensitiveActionsPanel> createState() =>
      _OwnerSensitiveActionsPanelState();
}

class _OwnerSensitiveActionsPanelState extends State<OwnerSensitiveActionsPanel> {
  static const int _previewCount = 3;

  final List<BusinessAuditEvent> _events = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  BusinessAuditCategory? _categoryFilter;

  List<BusinessAuditEvent> get _visibleEvents {
    final filter = _categoryFilter;
    if (filter == null) return _events;
    return _events.where((e) => e.category == filter).toList(growable: false);
  }

  List<BusinessAuditEvent> get _displayEvents {
    final visible = _visibleEvents;
    if (widget.fullScreen || !widget.compact) return visible;
    return visible.take(_previewCount).toList(growable: false);
  }

  bool get _showCategoryFilters => widget.fullScreen || !widget.compact;

  void _openFullScreen() {
    openOwnerDashboardFullScreenPanel(
      context,
      title: 'تعديلات حساسة',
      body: OwnerSensitiveActionsPanel(
        fullScreen: true,
        tenantId: widget.tenantId,
        onEventTap: widget.onEventTap,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void didUpdateWidget(covariant OwnerSensitiveActionsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      _events.clear();
      _hasMore = true;
      _categoryFilter = null;
      _loadInitial();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await BusinessAuditLogService.instance.ensureReady();
      final page = await BusinessAuditLogService.instance.loadPage(
        tenantId: widget.tenantId,
        limit: 20,
        excludeDiagnostics: true,
      );
      if (!mounted) return;
      setState(() {
        _events
          ..clear()
          ..addAll(page);
        _hasMore = page.length >= 20;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.error(
        'OwnerSensitiveActionsPanel',
        'تعذر تحميل الدفعة الأولى من سجل التعديلات الحساسة',
        e,
        st,
      );
      if (!mounted) return;
      final offline =
          LicenseService.instance.state.status == LicenseStatus.offline;
      setState(() {
        _loading = false;
        _error = offline ? null : 'تعذّر تحميل سجل التعديلات';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _events.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final afterId = _events.last.id;
      final page = await BusinessAuditLogService.instance.loadPage(
        tenantId: widget.tenantId,
        afterId: afterId,
        limit: 20,
        excludeDiagnostics: true,
      );
      if (!mounted) return;
      setState(() {
        _events.addAll(page);
        _hasMore = page.length >= 20;
        _loadingMore = false;
      });
    } catch (e, st) {
      AppLogger.error(
        'OwnerSensitiveActionsPanel',
        'تعذر تحميل المزيد من سجل التعديلات الحساسة',
        e,
        st,
      );
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Widget _buildListSection(BuildContext context, ColorScheme cs) {
    final visible = _displayEvents;

    if (_loading) {
      return const OwnerKpiCardSkeleton(height: 120);
    }
    if (_error != null) {
      return OwnerSectionError(message: _error!, onRetry: _loadInitial);
    }
    if (_events.isEmpty) {
      return const OwnerSectionEmpty(
        message: 'لا توجد تعديلات مسجّلة بعد.',
        icon: Icons.shield_outlined,
      );
    }
    if (_visibleEvents.isEmpty) {
      return OwnerSectionEmpty(
        message: 'لا سجلات في هذا التصنيف.',
        icon: Icons.filter_alt_outlined,
        onRetry: () => setState(() => _categoryFilter = null),
      );
    }

    if (!widget.fullScreen && widget.compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _AuditEventTile(
              event: visible[i],
              onTap: widget.onEventTap == null
                  ? null
                  : () => widget.onEventTap!(visible[i]),
            ),
          ],
        ],
      );
    }

    final list = ListView.builder(
      itemCount:
          visible.length + (_hasMore && _categoryFilter == null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= visible.length) {
          return TextButton(
            onPressed: _loadingMore ? null : _loadMore,
            child: _loadingMore
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('عرض المزيد'),
          );
        }
        final event = visible[index];
        return _AuditEventTile(
          event: event,
          onTap: widget.onEventTap == null
              ? null
              : () => widget.onEventTap!(event),
        );
      },
    );

    if (widget.fullScreen) {
      return Expanded(child: list);
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: list,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final offline =
        LicenseService.instance.state.status == LicenseStatus.offline;

    final inner = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: widget.fullScreen ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (offline)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: cs.tertiaryContainer.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text(
                  'عرض السجلات المحلية فقط — غير متصل',
                  style: TextStyle(
                    color: cs.onTertiaryContainer,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        Row(
          children: [
            Icon(Icons.shield_outlined, color: cs.primary, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'تعديلات حساسة',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.orange),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'مراقب',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (!widget.fullScreen)
              IconButton(
                tooltip: 'ملء الشاشة',
                onPressed: _openFullScreen,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: const OwnerDashboardVerticalArrowsIcon(size: 20),
              ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _loadInitial,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_showCategoryFilters) ...[
          _AuditFilterBar(
            selected: _categoryFilter,
            onSelected: (value) => setState(() => _categoryFilter = value),
          ),
          const SizedBox(height: 8),
        ],
        _buildListSection(context, cs),
      ],
    );

    if (widget.fullScreen) {
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 12),
        child: OwnerDashboardGoldBorder.themedCard(
          context: context,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: inner,
          ),
        ),
      );
    }

    return OwnerDashboardGoldBorder.themedCard(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: inner,
      ),
    );
  }
}

class _AuditFilterBar extends StatelessWidget {
  const _AuditFilterBar({
    required this.selected,
    required this.onSelected,
  });

  final BusinessAuditCategory? selected;
  final ValueChanged<BusinessAuditCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        children: [
          _AuditFilterChip(
            tooltip: 'الكل',
            icon: Icons.list_alt,
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          const SizedBox(width: 6),
          _AuditFilterChip(
            tooltip: 'أسعار',
            icon: Icons.sell_outlined,
            selected: selected == BusinessAuditCategory.price,
            onTap: () => onSelected(BusinessAuditCategory.price),
          ),
          const SizedBox(width: 6),
          _AuditFilterChip(
            tooltip: 'منتجات',
            icon: Icons.inventory_2_outlined,
            selected: selected == BusinessAuditCategory.product,
            onTap: () => onSelected(BusinessAuditCategory.product),
          ),
          const SizedBox(width: 6),
          _AuditFilterChip(
            tooltip: 'مخزون',
            icon: Icons.move_to_inbox_outlined,
            selected: selected == BusinessAuditCategory.stock,
            onTap: () => onSelected(BusinessAuditCategory.stock),
          ),
          const SizedBox(width: 6),
          _AuditFilterChip(
            tooltip: 'أمان',
            icon: Icons.admin_panel_settings_outlined,
            selected: selected == BusinessAuditCategory.security,
            onTap: () => onSelected(BusinessAuditCategory.security),
          ),
          const SizedBox(width: 6),
          _AuditFilterChip(
            tooltip: 'ديون',
            icon: Icons.payments_outlined,
            selected: selected == BusinessAuditCategory.debt,
            onTap: () => onSelected(BusinessAuditCategory.debt),
          ),
        ],
      ),
    );
  }
}

class _AuditFilterChip extends StatelessWidget {
  const _AuditFilterChip({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected
            ? cs.primaryContainer.withValues(alpha: 0.85)
            : cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 18,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _AuditEventTile extends StatelessWidget {
  const _AuditEventTile({required this.event, this.onTap});

  final BusinessAuditEvent event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sensitive = event.isSensitive;
    final accent = sensitive ? cs.error : cs.primary;
    final detail = event.detailAr.trim();
    final actor = event.actorLabelAr;
    final time = _auditTimeFmt.format(event.createdAt);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: sensitive
                ? cs.errorContainer.withValues(alpha: 0.22)
                : cs.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: sensitive
                  ? cs.error.withValues(alpha: 0.35)
                  : OwnerDashboardGoldBorder.borderColor(cs: cs),
            ),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(event.icon, color: accent, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              event.labelAr,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          if (sensitive)
                            Container(
                              padding: const EdgeInsetsDirectional.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: cs.error.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'حساس',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: cs.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (detail.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                            height: 1.3,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        '$actor · $time',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_left_rounded,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                    size: 20,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
