import 'dart:async' show unawaited, Timer;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/customer_debt_models.dart';
import '../../models/customer_record.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/database_helper.dart';
import '../../utils/app_logger.dart';
import '../../theme/design_tokens.dart';

final _numFmt = NumberFormat('#,##0', 'en');
final _dateFmt = DateFormat('dd/MM/yyyy', 'en');

/// مراجعة وربط فواتير الدين القديمة التي لا تزال بلا `customerId`.
class CustomerDebtLinkingScreen extends StatefulWidget {
  const CustomerDebtLinkingScreen({super.key});

  @override
  State<CustomerDebtLinkingScreen> createState() =>
      _CustomerDebtLinkingScreenState();
}

class _CustomerDebtLinkingScreenState extends State<CustomerDebtLinkingScreen> {
  final _db = DatabaseHelper();
  bool _loading = true;
  String? _error;
  List<UnlinkedCreditDebtInvoice> _unlinked = const [];
  List<AmbiguousDebtCustomerName> _ambiguous = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final unlinked = await _db.getUnlinkedOpenCreditDebtInvoices();
      final ambiguous = await _db.getAmbiguousDebtCustomerNames();
      if (!mounted) return;
      setState(() {
        _unlinked = unlinked;
        _ambiguous = ambiguous;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _confirmAndLinkAmbiguousName({
    required AmbiguousDebtCustomerName ambiguous,
    required int customerId,
    required String customerName,
  }) async {
    final matches = _unlinked
        .where((u) => u.normalizedName == ambiguous.normalizedName)
        .toList();
    if (matches.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد فواتير مفتوحة بهذا الاسم حالياً'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الربط'),
        content: Text(
          'ربط ${matches.length} فاتورة باسم «${ambiguous.sampleName}» '
          'بالعميل «$customerName»؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ربط'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _linkInvoicesBatch(matches, customerId, customerName);
  }

  Future<void> _linkInvoicesBatch(
    List<UnlinkedCreditDebtInvoice> rows,
    int customerId,
    String customerName,
  ) async {
    final nav = ScaffoldMessenger.of(context);
    var linked = 0;
    for (final row in rows) {
      try {
        await _db.linkOpenCreditInvoiceToCustomer(
          invoiceId: row.invoiceId,
          customerId: customerId,
        );
        linked++;
      } catch (e) {
        AppLogger.warn(
          'DebtLinking',
          'فشل ربط فاتورة #${row.invoiceId}: $e',
        );
      }
    }
    if (linked > 0) {
      CloudSyncService.instance.scheduleSyncSoon();
    }
    if (!mounted) return;
    nav.showSnackBar(
      SnackBar(
        content: Text(
          linked > 0
              ? 'تم ربط $linked فاتورة بالعميل «$customerName»'
              : 'تعذّر ربط الفواتير المحددة',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (linked > 0) await _reload();
  }

  Future<void> _linkInvoice(UnlinkedCreditDebtInvoice row) async {
    final customer = await showDialog<CustomerRecord>(
      context: context,
      builder: (ctx) => _CustomerPickDialog(
        initialQuery: row.customerName,
      ),
    );
    if (customer == null || !mounted) return;

    final nav = ScaffoldMessenger.of(context);
    try {
      await _db.linkOpenCreditInvoiceToCustomer(
        invoiceId: row.invoiceId,
        customerId: customer.id,
      );
      CloudSyncService.instance.scheduleSyncSoon();
      if (!mounted) return;
      nav.showSnackBar(
        SnackBar(
          content: Text(
            'تم ربط الفاتورة #${row.invoiceId} بالعميل «${customer.name}»',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      nav.showSnackBar(
        SnackBar(
          content: Text('تعذر الربط: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerHighest,
          foregroundColor: cs.onSurface,
          title: Text(
            'ربط ديون بالعملاء',
            style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _reload,
              icon: Icon(Icons.refresh_rounded, color: cs.onSurface),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorBody(message: _error!, onRetry: _reload)
                : RefreshIndicator(
                    color: cs.primary,
                    onRefresh: _reload,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                      children: [
                        _IntroCard(
                          unlinkedCount: _unlinked.length,
                          ambiguousCount: _ambiguous.length,
                        ),
                        if (_ambiguous.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const _SectionTitle(
                            icon: Icons.warning_amber_rounded,
                            title: 'أسماء مكررة — ربط يدوي فقط',
                          ),
                          const SizedBox(height: 8),
                          ..._ambiguous.map(
                            (a) => _AmbiguousTile(
                              item: a,
                              onSurfaceVariant: cs.onSurfaceVariant,
                              onPickCustomer: (customerId, customerName) {
                                unawaited(
                                  _confirmAndLinkAmbiguousName(
                                    ambiguous: a,
                                    customerId: customerId,
                                    customerName: customerName,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        const _SectionTitle(
                          icon: Icons.link_rounded,
                          title: 'فواتير دين غير مربوطة',
                        ),
                        const SizedBox(height: 8),
                        if (_unlinked.isEmpty)
                          _EmptyUnlinked(onSurfaceVariant: cs.onSurfaceVariant)
                        else
                          ..._unlinked.map(
                            (row) => _UnlinkedInvoiceTile(
                              row: row,
                              onLink: () => _linkInvoice(row),
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({
    required this.unlinkedCount,
    required this.ambiguousCount,
  });

  final int unlinkedCount;
  final int ambiguousCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.5)),
      ),
      child: Text(
        'يُجرى ربط تلقائي عندما يكون اسم الفاتورة فريداً في العملاء. '
        'المتبقي هنا يحتاج اختيار عميل يدوياً: $unlinkedCount فاتورة، '
        '$ambiguousCount اسم مكرر.',
        style: TextStyle(
          fontSize: 13,
          height: 1.45,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.accentGold),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: AppColors.accentGold,
          ),
        ),
      ],
    );
  }
}

class _AmbiguousTile extends StatelessWidget {
  const _AmbiguousTile({
    required this.item,
    required this.onSurfaceVariant,
    required this.onPickCustomer,
  });

  final AmbiguousDebtCustomerName item;
  final Color onSurfaceVariant;
  final void Function(int customerId, String customerName) onPickCustomer;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: const Icon(Icons.person_search_rounded, color: Colors.orange),
        title: Text(item.sampleName),
        subtitle: Text(
          '${item.matchingCustomerCount} عملاء بنفس الاسم · '
          '${item.openInvoiceCount} فاتورة مفتوحة',
          style: TextStyle(fontSize: 12, color: onSurfaceVariant),
        ),
        children: [
          if (item.matchingCustomers.isEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
              child: Text(
                'لم يُعثر على قائمة العملاء — حدّث الصفحة',
                style: TextStyle(fontSize: 12, color: onSurfaceVariant),
              ),
            )
          else
            ...item.matchingCustomers.map(
              (c) => ListTile(
                dense: true,
                title: Text(c.name),
                subtitle: Text(
                  'مُعرّف #${c.customerId}',
                  style: TextStyle(fontSize: 11, color: onSurfaceVariant),
                ),
                trailing: TextButton(
                  onPressed: () => onPickCustomer(c.customerId, c.name),
                  child: const Text('ربط فواتير هذا الاسم'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UnlinkedInvoiceTile extends StatelessWidget {
  const _UnlinkedInvoiceTile({
    required this.row,
    required this.onLink,
  });

  final UnlinkedCreditDebtInvoice row;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(row.customerName),
        subtitle: Text(
          'فاتورة #${row.invoiceId} · ${_dateFmt.format(row.date)} · '
          'متبقي ${_numFmt.format(row.remaining)} د.ع',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        trailing: FilledButton(
          onPressed: onLink,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accentGold,
            foregroundColor: Colors.white,
          ),
          child: const Text('ربط'),
        ),
      ),
    );
  }
}

class _EmptyUnlinked extends StatelessWidget {
  const _EmptyUnlinked({required this.onSurfaceVariant});

  final Color onSurfaceVariant;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          'لا توجد فواتير دين مفتوحة غير مربوطة — ممتاز.',
          textAlign: TextAlign.center,
          style: TextStyle(color: onSurfaceVariant, fontSize: 14),
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
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

class _CustomerPickDialog extends StatefulWidget {
  const _CustomerPickDialog({this.initialQuery = ''});

  final String initialQuery;

  @override
  State<_CustomerPickDialog> createState() => _CustomerPickDialogState();
}

class _CustomerPickDialogState extends State<_CustomerPickDialog> {
  final _db = DatabaseHelper();
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<Map<String, dynamic>> _hits = const [];

  @override
  void initState() {
    super.initState();
    _search.text = widget.initialQuery;
    _search.addListener(_onSearchChanged);
    if (widget.initialQuery.trim().isNotEmpty) {
      unawaited(_runSearch(widget.initialQuery.trim()));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      unawaited(_runSearch(_search.text.trim()));
    });
  }

  Future<void> _runSearch(String q) async {
    if (q.isEmpty) {
      if (mounted) setState(() => _hits = const []);
      return;
    }
    setState(() => _loading = true);
    try {
      final rows = await _db.searchCustomers(q, limit: 20);
      if (!mounted) return;
      setState(() {
        _hits = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.7;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('اختر العميل'),
        content: SizedBox(
          width: math.min(520, MediaQuery.sizeOf(context).width - 48),
          height: maxH.clamp(280.0, 560.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'بحث بالاسم أو الهاتف',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _hits.isEmpty
                        ? const Center(
                            child: Text('ابدأ بالكتابة للبحث عن عميل'),
                          )
                        : ListView.builder(
                            itemCount: _hits.length,
                            itemBuilder: (context, i) {
                              final row = _hits[i];
                              final rec = CustomerRecord.fromMap(row);
                              return ListTile(
                                title: Text(rec.name),
                                subtitle: rec.phone == null
                                    ? null
                                    : Text(rec.phone!),
                                onTap: () => Navigator.of(context).pop(rec),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

}
