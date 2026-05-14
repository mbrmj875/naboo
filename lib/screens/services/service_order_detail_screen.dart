import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../navigation/content_navigation.dart';
import '../../providers/sale_draft_provider.dart';
import '../../services/database_helper.dart';
import '../../services/product_repository.dart';
import '../../services/service_orders_repository.dart';
import '../../utils/iqd_money.dart';
import '../../utils/iraqi_currency_format.dart';
import '../invoices/add_invoice_screen.dart';
import 'service_order_form_screen.dart';

class ServiceOrderDetailScreen extends StatefulWidget {
  const ServiceOrderDetailScreen({
    super.key,
    required this.orderId,
    required this.orderGlobalId,
  });

  final int orderId;
  final String orderGlobalId;

  @override
  State<ServiceOrderDetailScreen> createState() => _ServiceOrderDetailScreenState();
}

class _ServiceOrderDetailScreenState extends State<ServiceOrderDetailScreen> {
  bool _loading = true;
  Object? _error;
  Map<String, dynamic>? _order;
  List<Map<String, dynamic>> _items = const [];
  // بنود الفاتورة المرتبطة (للعرض فقط — تُجلب عند وجود invoiceId)
  List<Map<String, dynamic>> _invoiceItems = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ServiceOrdersRepository.instance;
      final order = await repo.getServiceOrderByGlobalId(widget.orderGlobalId);
      final items = await repo.getItemsForOrderGlobalId(widget.orderGlobalId);

      // جلب بنود الفاتورة المرتبطة إن وُجد invoiceId
      List<Map<String, dynamic>> invItems = const [];
      final invId = (order?['invoiceId'] as num?)?.toInt();
      if (invId != null && invId > 0) {
        try {
          final db = await DatabaseHelper().database;
          invItems = await db.query(
            'invoice_items',
            where: 'invoiceId = ?',
            whereArgs: [invId],
            orderBy: 'id ASC',
          );
        } catch (_) {
          // فشل جلب بنود الفاتورة لا يوقف عرض التذكرة
        }
      }

      if (!mounted) return;
      setState(() {
        _order = order;
        _items = items;
        _invoiceItems = invItems;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  int _itemsTotalFils() {
    var s = 0;
    for (final it in _items) {
      s += (it['totalFils'] as num?)?.toInt() ?? 0;
    }
    return s;
  }

  int _servicePriceFils() {
    final o = _order;
    if (o == null) return 0;
    final est = (o['estimatedPriceFils'] as num?)?.toInt() ?? 0;
    final agreed = (o['agreedPriceFils'] as num?)?.toInt();
    return agreed ?? est;
  }

  int _advanceFils() {
    final o = _order;
    if (o == null) return 0;
    return (o['advancePaymentFils'] as num?)?.toInt() ?? 0;
  }

  Future<void> _openEdit() async {
    final oid = widget.orderId;
    final gid = widget.orderGlobalId;
    final saved = await Navigator.of(context).push<bool>(
      contentMaterialRoute(
        routeId: AppContentRoutes.serviceOrdersHub,
        breadcrumbTitle: 'تعديل تذكرة',
        builder: (_) => ServiceOrderFormScreen(
          editOrderId: oid,
          editOrderGlobalId: gid,
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      unawaited(_load());
    }
  }

  Future<Map<String, dynamic>?> _pickPartProduct() async {
    final repo = ProductRepository();
    final rows = await repo.getProducts();
    if (!mounted) return null;
    final products = rows
        .where((e) => ((e['isService'] as num?)?.toInt() ?? 0) == 0)
        .where((e) => ((e['trackInventory'] as num?)?.toInt() ?? 1) != 0)
        .toList(growable: false);

    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final search = TextEditingController();
        return StatefulBuilder(builder: (ctx, setModal) {
          final q = search.text.trim().toLowerCase();
          final filtered = products.where((p) {
            if (q.isEmpty) return true;
            final n = (p['name'] ?? '').toString().toLowerCase();
            final bc = (p['barcode'] ?? '').toString().toLowerCase();
            return n.contains(q) || bc.contains(q);
          }).toList(growable: false);
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 8),
                  child: TextField(
                    controller: search,
                    onChanged: (_) => setModal(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'بحث في قطع الغيار…',
                      isDense: true,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final p = filtered[i];
                      final id = (p['id'] as num?)?.toInt();
                      final name = (p['name'] ?? '').toString().trim();
                      final sell = (p['sell'] as num?)?.toDouble() ?? 0;
                      return ListTile(
                        title: Text(name.isEmpty ? 'منتج' : name),
                        subtitle: Text(
                          IraqiCurrencyFormat.formatIqd(sell),
                          textDirection: TextDirection.ltr,
                        ),
                        onTap: id == null ? null : () => Navigator.pop(ctx, p),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          );
        });
      },
    );
    return picked;
  }

  Future<void> _addPart() async {
    final p = await _pickPartProduct();
    if (!mounted || p == null) return;
    final pid = (p['id'] as num?)?.toInt();
    if (pid == null || pid <= 0) return;
    final name = (p['name'] ?? '').toString().trim();
    final sell = (p['sell'] as num?)?.toDouble() ?? 0.0;

    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController(text: sell.toStringAsFixed(0));

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('إضافة قطعة غيار'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name.isEmpty ? 'قطعة غيار' : name, textAlign: TextAlign.start),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'الكمية'),
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'سعر البيع (د.ع)'),
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('إضافة'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok || !mounted) return;
    final q = int.tryParse(qtyCtrl.text.trim()) ?? 1;
    final pr = double.tryParse(priceCtrl.text.trim().replaceAll(',', '')) ?? 0.0;
    final priceF = IqdMoney.toFils(pr);
    await ServiceOrdersRepository.instance.addItem(
      orderGlobalId: widget.orderGlobalId,
      productId: pid,
      productName: name.isEmpty ? 'قطعة غيار' : name,
      quantity: q <= 0 ? 1 : q,
      priceFils: priceF,
    );
    if (!mounted) return;
    unawaited(_load());
  }

  Future<void> _deletePart(int id) async {
    await ServiceOrdersRepository.instance.softDeleteItemById(id);
    if (!mounted) return;
    unawaited(_load());
  }

  Future<void> _convertToInvoice() async {
    final o = _order;
    if (o == null) return;
    final draft = context.read<SaleDraftProvider>();

    final custName = (o['customerNameSnapshot'] ?? '').toString().trim();
    final custId = (o['customerId'] as num?)?.toInt();
    final advF = _advanceFils();

    draft.enqueueSaleMeta({
      'customerName': custName,
      'linkedCustomerId': custId,
      'linkedServiceOrderId': widget.orderId,
      // لا نُمرّر advance هنا لأن السعر المُرسَل أدناه هو (المتفق - العربون) مباشرة.
    });

    final serviceId = (o['serviceId'] as num?)?.toInt();
    final serviceName = (o['serviceNameSnapshot'] ?? '').toString().trim();
    final servicePriceF = _servicePriceFils();
    // سعر البند في شاشة البيع = المتفق عليه ناقص العربون المحصّل مسبقاً.
    final remainingF = (servicePriceF - advF).clamp(0, servicePriceF);

    final device = (o['deviceName'] ?? '').toString().trim();
    final serial = (o['deviceSerial'] ?? '').toString().trim();
    final baseName = serviceName.isEmpty ? 'خدمة فنية' : serviceName;
    String finalName = baseName;
    final devDetails = [
      if (device.isNotEmpty) device,
      if (serial.isNotEmpty) 'س: $serial',
    ].join(' - ');
    if (devDetails.isNotEmpty) {
      finalName = '$baseName ($devDetails)';
    }

    if (serviceId != null && serviceId > 0) {
      draft.enqueueProductLine({
        'name': finalName,
        'sell': IqdMoney.fromFils(remainingF),
        'minSell': IqdMoney.fromFils(remainingF),
        'productId': serviceId,
        'trackInventory': 0,
        'allowNegativeStock': 0,
        'qty': 0,
        'stockBaseKind': 0,
        'isService': 1,
        'addQuantity': 1,
      });
    } else {
      draft.enqueueProductLine({
        'name': finalName,
        'sell': IqdMoney.fromFils(remainingF),
        'minSell': IqdMoney.fromFils(remainingF),
        'productId': null,
        'trackInventory': 0,
        'allowNegativeStock': 0,
        'qty': 0,
        'stockBaseKind': 0,
        'isService': 1,
        'addQuantity': 1,
      });
    }

    for (final it in _items) {
      final pid = (it['productId'] as num?)?.toInt();
      if (pid == null || pid <= 0) continue;
      final name = (it['productName'] ?? '').toString().trim();
      final q = (it['quantity'] as num?)?.toInt() ?? 1;
      final pF = (it['priceFils'] as num?)?.toInt() ?? 0;
      draft.enqueueProductLine({
        'name': name.isEmpty ? 'قطعة غيار' : name,
        'sell': IqdMoney.fromFils(pF),
        'minSell': IqdMoney.fromFils(pF),
        'productId': pid,
        'trackInventory': 1,
        'allowNegativeStock': 0,
        'qty': null,
        'stockBaseKind': 0,
        'isService': 0,
        'addQuantity': q,
      });
    }

    if (!draft.isSaleScreenOpen) {
      if (!mounted) return;
      await Navigator.of(context).push(
        contentMaterialRoute(
          routeId: AppContentRoutes.addInvoice,
          breadcrumbTitle: 'بيع جديد',
          builder: (_) => const AddInvoiceScreen(),
        ),
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final o = _order;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || o == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل التذكرة')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 42),
                const SizedBox(height: 12),
                const Text('تعذر تحميل بيانات التذكرة.'),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
              ],
            ),
          ),
        ),
      );
    }

    final customer = (o['customerNameSnapshot'] ?? '').toString().trim();
    final device = (o['deviceName'] ?? '').toString().trim();
    final serial = (o['deviceSerial'] ?? '').toString().trim();
    final status = (o['status'] ?? 'pending').toString();
    final serviceF = _servicePriceFils();
    final partsF = _itemsTotalFils();
    final advF = _advanceFils();
    final totalF = serviceF + partsF;
    final remainingF = (totalF - advF) < 0 ? 0 : (totalF - advF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل التذكرة'),
        actions: [
          IconButton(
            tooltip: 'تعديل',
            onPressed: _openEdit,
            icon: const Icon(Icons.edit_rounded),
          ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPart,
        icon: const Icon(Icons.add_rounded),
        label: const Text('إضافة قطعة'),
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 110),
        children: [
          _infoCard(
            context,
            title: customer.isEmpty ? 'عميل' : customer,
            subtitle: device.isEmpty ? '—' : device,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
              ),
              child: Text(
                _statusLabel(status),
                style: TextStyle(fontWeight: FontWeight.w900, color: cs.primary),
              ),
            ),
            extra: serial.isEmpty ? null : 'سيريال/لوحة: $serial',
          ),
          const SizedBox(height: 10),
          ..._etaSummaryWidgets(context, o),
          _moneyCard(
            context,
            serviceFils: serviceF,
            partsFils: partsF,
            advanceFils: advF,
            totalFils: totalF,
            remainingFils: remainingF,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: status == 'completed' ? _convertToInvoice : null,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('تحويل لفاتورة بيع'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'قطع الغيار',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            Text(
              'لا توجد قطع غيار بعد.',
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.start,
            )
          else
            for (final it in _items)
              _partTile(
                context,
                it,
                onDelete: () {
                  final id = (it['id'] as num?)?.toInt();
                  if (id != null && id > 0) {
                    unawaited(_deletePart(id));
                  }
                },
              ),

          // ── قسم بنود الفاتورة (للعرض فقط) ──
          if (_invoiceItems.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'بنود الفاتورة',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                    textAlign: TextAlign.start,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'للعرض فقط',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'المنتجات والخدمات المسجّلة في فاتورة البيع المرتبطة.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 8),
            for (final it in _invoiceItems)
              _invoiceItemTile(context, it),
          ],
        ],
      ),
    );
  }

  List<Widget> _etaSummaryWidgets(BuildContext context, Map<String, dynamic> o) {
    final dm = (o['expectedDurationMinutes'] as num?)?.toInt();
    final promisedRaw = (o['promisedDeliveryAt'] ?? '').toString().trim();
    final createdRaw = (o['createdAt'] ?? '').toString();
    final workStartRaw = (o['workStartedAt'] ?? '').toString().trim();
    final promisedLocal = promisedRaw.isEmpty
        ? null
        : DateTime.tryParse(promisedRaw)?.toLocal();
    final openedLocal = DateTime.tryParse(createdRaw)?.toLocal();
    final workStartLocal = workStartRaw.isEmpty
        ? null
        : DateTime.tryParse(workStartRaw)?.toLocal();

    DateTime? target = promisedLocal;
    if (target == null &&
        workStartLocal != null &&
        dm != null &&
        dm > 0) {
      target = workStartLocal.add(Duration(minutes: dm));
    }
    if (target == null &&
        openedLocal != null &&
        dm != null &&
        dm > 0) {
      target = openedLocal.add(Duration(minutes: dm));
    }

    if (target == null && (dm == null || dm <= 0)) {
      return const [];
    }

    final cs = Theme.of(context).colorScheme;
    final status = (o['status'] ?? '').toString();
    final overdue = target != null &&
        DateTime.now().isAfter(target) &&
        status != 'delivered' &&
        status != 'cancelled';
    final df = DateFormat('EEEE، d MMMM yyyy • HH:mm', 'ar');

    return [
      Container(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: overdue
              ? cs.errorContainer.withValues(alpha: 0.28)
              : cs.surfaceContainerHighest.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  overdue ? Icons.warning_amber_rounded : Icons.schedule_rounded,
                  color: overdue ? cs.error : cs.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    overdue
                        ? 'تجاوز موعد التسليم المتوقع'
                        : 'موعد التسليم المتوقع للزبون',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: overdue ? cs.error : cs.onSurface,
                    ),
                    textAlign: TextAlign.start,
                  ),
                ),
              ],
            ),
            if (target != null) ...[
              const SizedBox(height: 8),
              Text(
                df.format(target),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: overdue ? cs.onErrorContainer : cs.onSurface,
                ),
                textAlign: TextAlign.start,
              ),
            ],
            if (dm != null && dm > 0)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 6),
                child: Text(
                  'مدة العمل المتوقعة: $dm دقيقة',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                  textAlign: TextAlign.start,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 10),
    ];
  }

  static String _statusLabel(String s) {
    switch (s) {
      case 'pending':
        return 'معلقة';
      case 'in_progress':
        return 'قيد العمل';
      case 'completed':
        return 'جاهزة للتسليم';
      case 'delivered':
        return 'مسلّمة';
      case 'cancelled':
        return 'ملغاة';
      default:
        return s;
    }
  }

  Widget _infoCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget trailing,
    String? extra,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  if (extra != null && extra.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      extra,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _moneyCard(
    BuildContext context, {
    required int serviceFils,
    required int partsFils,
    required int advanceFils,
    required int totalFils,
    required int remainingFils,
  }) {
    final cs = Theme.of(context).colorScheme;
    String f(int fils) => IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(fils));
    Widget row(String k, String v, {bool strong = false}) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                k,
                style: TextStyle(
                  fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              v,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              ),
              textDirection: TextDirection.ltr,
            ),
          ],
        ),
      );
    }

    return Material(
      color: cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ملخص مالي (بالفلس)',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            row('الخدمة الفنية', f(serviceFils)),
            row('قطع الغيار', f(partsFils)),
            row('الإجمالي', f(totalFils), strong: true),
            row('مدفوع مسبقاً', f(advanceFils)),
            const Divider(height: 18),
            row('المتبقي عند التسليم', f(remainingFils), strong: true),
          ],
        ),
      ),
    );
  }

  Widget _partTile(
    BuildContext context,
    Map<String, dynamic> it, {
    required VoidCallback onDelete,
  }) {
    final cs = Theme.of(context).colorScheme;
    final name = (it['productName'] ?? '').toString().trim();
    final q = (it['quantity'] as num?)?.toInt() ?? 1;
    final pF = (it['priceFils'] as num?)?.toInt() ?? 0;
    final tF = (it['totalFils'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cs.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
        ),
        child: ListTile(
          title: Text(name.isEmpty ? 'قطعة غيار' : name),
          subtitle: Text(
            'الكمية: $q · سعر: ${IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(pF))} · إجمالي: ${IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(tF))}',
            textDirection: TextDirection.ltr,
          ),
          trailing: IconButton(
            tooltip: 'حذف',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
          ),
        ),
      ),
    );
  }

  Widget _invoiceItemTile(BuildContext context, Map<String, dynamic> it) {
    final cs = Theme.of(context).colorScheme;
    final name = (it['productName'] ?? '').toString().trim();
    final enteredQty = (it['enteredQty'] as num?)?.toDouble();
    final baseQty = (it['quantity'] as num?)?.toDouble() ?? 1;
    final displayQty = (enteredQty != null && enteredQty > 0) ? enteredQty : baseQty;
    final unitLabel = (it['unitLabel'] as String?)?.trim();
    final tF = (it['totalFils'] as num?)?.toInt() ?? 0;

    final qtyText = unitLabel != null && unitLabel.isNotEmpty
        ? '${displayQty.toStringAsFixed(displayQty % 1 == 0 ? 0 : 2)} $unitLabel'
        : displayQty.toStringAsFixed(displayQty % 1 == 0 ? 0 : 2);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.secondaryContainer.withValues(alpha: 0.20),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: cs.secondaryContainer.withValues(alpha: 0.6)),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(Icons.receipt_long_rounded, color: cs.secondary, size: 20),
          title: Text(name.isEmpty ? 'منتج' : name, textAlign: TextAlign.start),
          subtitle: Text(
            'الكمية: $qtyText',
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
          ),
          trailing: Text(
            IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(tF)),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    );
  }
}
