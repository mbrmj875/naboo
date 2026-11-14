import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/database_helper.dart';
import '../../services/tenant_context_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/app_logger.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../utils/iqd_money.dart';
import '../../utils/screen_layout.dart';
import '../../verticals/oil_change/screens/oil_change_detail_screen.dart';
import '../../widgets/invoice_detail_sheet.dart';
import '../models/owner_date_range.dart';
import '../models/owner_period_sale_row.dart';
import '../owner_command_center_repository.dart';
import '../providers/owner_command_center_provider.dart';
import '../specs/owner_dashboard_profile.dart';
import '../utils/owner_dashboard_gold_border.dart';

/// تفصيل مبيعات الفترة المختارة في لوحة المالك — نفس نطاق بطاقة المبيعات.
class OwnerPeriodSalesDetailScreen extends StatefulWidget {
  const OwnerPeriodSalesDetailScreen({
    super.key,
    required this.range,
    required this.expectedTotalFils,
    this.profile,
    this.staffName,
  });

  final OwnerDateRange range;
  final int expectedTotalFils;
  final OwnerDashboardProfile? profile;
  final String? staffName;

  @override
  State<OwnerPeriodSalesDetailScreen> createState() =>
      _OwnerPeriodSalesDetailScreenState();
}

class _OwnerPeriodSalesDetailScreenState
    extends State<OwnerPeriodSalesDetailScreen> {
  static const _pageSize = 80;

  final _repo = OwnerCommandCenterRepository();
  final _scroll = ScrollController();

  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  final List<OwnerPeriodSaleRow> _rows = [];
  bool _hasMore = true;

  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'en');

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _rows.clear();
        _hasMore = true;
      });
    } else {
      if (!_hasMore || _loadingMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final tenant = TenantContextService.instance;
      if (!tenant.loaded) await tenant.load();
      final tenantId = tenant.requireActiveTenantId();

      final after = reset || _rows.isEmpty ? null : _rows.last;
      final page = await _repo.listPeriodSales(
        tenantId: tenantId,
        range: widget.range,
        profile: widget.profile,
        staffName: widget.staffName,
        limit: _pageSize,
        afterCreatedAt: after?.createdAtIso,
        afterId: after?.recordId,
      );

      if (!mounted) return;
      setState(() {
        if (reset) {
          _rows
            ..clear()
            ..addAll(page);
        } else {
          _rows.addAll(page);
        }
        _hasMore = page.length >= _pageSize;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e, st) {
      AppLogger.error(
        'OwnerPeriodSalesDetail',
        'تعذر تحميل مبيعات الفترة',
        e,
        st,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e;
      });
    }
  }

  int get _loadedSumFils =>
      _rows.fold<int>(0, (s, r) => s + r.amountFils);

  Future<void> _openRow(OwnerPeriodSaleRow row) async {
    if (row.kind == OwnerPeriodSaleKind.invoice ||
        (row.hasInvoice && row.kind != OwnerPeriodSaleKind.oilCard)) {
      final invId = row.invoiceId ?? row.recordId;
      await showInvoiceDetailSheet(context, DatabaseHelper(), invId);
      return;
    }

    if (row.kind == OwnerPeriodSaleKind.oilCard) {
      if (row.hasInvoice) {
        await showInvoiceDetailSheet(
          context,
          DatabaseHelper(),
          row.invoiceId!,
        );
        return;
      }
      final gid = (row.orderGlobalId ?? '').trim();
      if (gid.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر فتح البطاقة — معرف مفقود')),
        );
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => OilChangeDetailScreen(
            orderId: row.recordId,
            orderGlobalId: gid,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gap = ScreenLayout.of(context).pageHorizontalGap;
    final title = widget.range.salesTitleAr;
    final expected = IraqiCurrencyFormat.formatIqd(
      IqdMoney.fromFils(widget.expectedTotalFils),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(gap, 12, gap, 8),
                child: DecoratedBox(
                  decoration: OwnerDashboardGoldBorder.boxDecoration(
                    context,
                    backgroundColor: OwnerDashboardGoldBorder.fillColor(context),
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          expected,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _headerHint(),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ErrorBody(
                  onRetry: () => _load(reset: true),
                ),
              )
            else if (_rows.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyBody(),
              )
            else
              SliverPadding(
                padding: EdgeInsetsDirectional.fromSTEB(gap, 4, gap, 24),
                sliver: SliverList.builder(
                  itemCount: _rows.length + (_loadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _rows.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final row = _rows[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SaleTile(
                        row: row,
                        dateLabel: _formatDate(row.createdAtIso),
                        onTap: () => _openRow(row),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _headerHint() {
    final n = _rows.length;
    if (_loading) return 'جاري التحميل…';
    if (_error != null) return 'تعذّر التحميل';
    if (n == 0) return 'لا توجد عمليات في هذه الفترة';
    final loaded = IraqiCurrencyFormat.formatIqd(
      IqdMoney.fromFils(_loadedSumFils),
    );
    if (_hasMore) {
      return 'عرض $n عملية حتى الآن · مجموع المعروض $loaded';
    }
    return '$n عملية · المجموع $loaded';
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.isUtc ? dt.toLocal() : dt;
    return _dateFmt.format(local);
  }
}

class _SaleTile extends StatelessWidget {
  const _SaleTile({
    required this.row,
    required this.dateLabel,
    required this.onTap,
  });

  final OwnerPeriodSaleRow row;
  final String dateLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final amount = IraqiCurrencyFormat.formatIqd(
      IqdMoney.fromFils(row.amountFils),
    );
    final badge = row.hasInvoice
        ? 'فاتورة #${row.invoiceId}'
        : (row.kind == OwnerPeriodSaleKind.oilCard
            ? 'بطاقة غيار'
            : 'فاتورة #${row.recordId}');

    return Material(
      color: cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        dateLabel,
                        if ((row.subtitle ?? '').isNotEmpty) row.subtitle!,
                        if ((row.staffName ?? '').isNotEmpty) row.staffName!,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppSemanticColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppSemanticColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                amount,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: cs.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: cs.outline),
            const SizedBox(height: 12),
            Text(
              'لا توجد فواتير أو غيارات في هذه الفترة',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('تعذّر تحميل مبيعات الفترة'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

/// اختصار لفتح شاشة التفصيل من لوحة المالك بالفترة الحالية.
void openOwnerPeriodSalesDetail(
  BuildContext context,
  OwnerCommandCenterProvider center,
) {
  final sales = center.snapshot.sales?.data;
  final expected = sales == null ? 0 : sales.salesFils;
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => OwnerPeriodSalesDetailScreen(
        range: center.dateRange,
        expectedTotalFils: expected,
        profile: center.v3Profile,
        staffName: center.staffFilter,
      ),
    ),
  );
}
