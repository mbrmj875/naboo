import 'package:flutter/material.dart';

import '../../../navigation/content_navigation.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../models/pharmacy_invoice_summary.dart';
import '../services/pharmacy_invoices_repository.dart';
import 'pharmacy_invoice_detail_screen.dart';

/// قائمة فواتير الصيدلية — بحث + تصفية + معاينة بنود الأدوية.
class PharmacyInvoicesScreen extends StatefulWidget {
  const PharmacyInvoicesScreen({
    super.key,
    this.repository,
  });

  final PharmacyInvoicesRepository? repository;

  @override
  State<PharmacyInvoicesScreen> createState() => _PharmacyInvoicesScreenState();
}

class _PharmacyInvoicesScreenState extends State<PharmacyInvoicesScreen> {
  late final PharmacyInvoicesRepository _repo =
      widget.repository ?? PharmacyInvoicesRepository();

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  PharmacyInvoicePeriodFilter _period = PharmacyInvoicePeriodFilter.today;
  String _query = '';
  int? _afterId;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  final List<PharmacyInvoiceSummary> _items = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _afterId == null) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _afterId = null;
        _items.clear();
      });
    } else {
      if (_loadingMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final tenantId = await _repo.resolveTenantId();
      final page = await _repo.listInvoices(
        tenantId: tenantId,
        period: _period,
        query: _query,
        afterId: reset ? null : _afterId,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(page.items);
        } else {
          _items.addAll(page.items);
        }
        _afterId = page.nextAfterId;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = 'تعذر تحميل الفواتير';
      });
    }
  }

  void _applySearch(String value) {
    _query = value.trim();
    _load(reset: true);
  }

  void _setPeriod(PharmacyInvoicePeriodFilter period) {
    if (_period == period) return;
    setState(() => _period = period);
    _load(reset: true);
  }

  Future<void> _openDetail(PharmacyInvoiceSummary invoice) async {
    await Navigator.of(context).push<void>(
      contentMaterialRoute(
        routeId: AppContentRoutes.pharmacyInvoiceDetailId(invoice.id),
        breadcrumbTitle: 'فاتورة #${invoice.id}',
        parentOverride: AppContentRoutes.pharmacyInvoices,
        builder: (_) => PharmacyInvoiceDetailScreen(invoiceId: invoice.id),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('الفواتير'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _periodChip('اليوم', PharmacyInvoicePeriodFilter.today),
                    _periodChip('الأسبوع', PharmacyInvoicePeriodFilter.week),
                    _periodChip('الشهر', PharmacyInvoicePeriodFilter.month),
                    _periodChip('الكل', PharmacyInvoicePeriodFilter.all),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'بحث: تاريخ أو رقم فاتورة',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchController.clear();
                              _applySearch('');
                            },
                            icon: const Icon(Icons.close_rounded),
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: _applySearch,
                  onChanged: (v) {
                    if (v.trim().isEmpty && _query.isNotEmpty) {
                      _applySearch('');
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _periodChip(String label, PharmacyInvoicePeriodFilter value) {
    final selected = _period == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _setPeriod(value),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.start),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _load(reset: true),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          'لا توجد فواتير في هذه الفترة',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Padding(
            padding: EdgeInsetsDirectional.all(12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final invoice = _items[index];
        return _InvoiceCard(
          invoice: invoice,
          dateLabel: _formatDate(invoice.date),
          totalLabel: IraqiCurrencyFormat.formatIqd(invoice.totalDinars),
          onTap: () => _openDetail(invoice),
        );
      },
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.invoice,
    required this.dateLabel,
    required this.totalLabel,
    required this.onTap,
  });

  final PharmacyInvoiceSummary invoice;
  final String dateLabel;
  final String totalLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'الفاتورة #${invoice.id} — $dateLabel',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.start,
              ),
              if (invoice.customerName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  invoice.customerName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.start,
                ),
              ],
              const SizedBox(height: 8),
              ...invoice.previewLines.map(
                (line) => Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 4),
                  child: Text(
                    line.compactLabel,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.start,
                  ),
                ),
              ),
              if (invoice.previewLines.isEmpty)
                Text(
                  '—',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.start,
                ),
              const Divider(height: 18),
              Text(
                'الإجمالي: $totalLabel',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.start,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
