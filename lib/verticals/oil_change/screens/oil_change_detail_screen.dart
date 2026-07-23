import 'dart:async';

import 'package:flutter/material.dart';

import '../../../navigation/content_navigation.dart';
import '../../../services/print_settings_repository.dart';
import '../../../services/service_order_invoice_bridge.dart';
import '../../../services/service_order_kinds.dart';
import '../../../services/service_orders_repository.dart';
import '../../../utils/customer_phone_launch.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../utils/oil_change_finance.dart';
import '../utils/oil_change_filter_format.dart';
import '../utils/oil_change_log_format.dart';
import '../models/oil_change_filter_kind.dart';
import '../utils/oil_change_customer_debt.dart';
import '../utils/oil_service_whatsapp_message.dart';
import '../utils/oil_change_service_pdf.dart';
import 'oil_change_form_screen.dart';
import '../widgets/oil_change_form_theme.dart';

/// عرض بطاقة غيار زيت — بدون تذكرة صيانة أو قطع غيار.
class OilChangeDetailScreen extends StatefulWidget {
  const OilChangeDetailScreen({
    super.key,
    required this.orderId,
    required this.orderGlobalId,
  });

  final int orderId;
  final String orderGlobalId;

  @override
  State<OilChangeDetailScreen> createState() => _OilChangeDetailScreenState();
}

class _OilChangeDetailScreenState extends State<OilChangeDetailScreen> {
  bool _loading = true;
  Object? _error;
  Map<String, dynamic>? _order;
  String? _oilProductName;
  int _oilMaterialEstFils = 0;

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
      final order = await ServiceOrdersRepository.instance
          .getServiceOrderByGlobalId(widget.orderGlobalId);
      if (!mounted) return;
      if (order == null || !ServiceOrderKinds.isOilChange(order)) {
        setState(() {
          _error = StateError('not_oil_card');
          _loading = false;
        });
        return;
      }
      final productName = await oilProductDisplayName(order);
      final materialF = await estimateOilMaterialSellFils(order);
      if (!mounted) return;
      setState(() {
        _order = order;
        _oilProductName = productName;
        _oilMaterialEstFils = materialF;
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

  Future<void> _openEdit() async {
    final saved = await Navigator.of(context).push<bool>(
      contentMaterialRoute(
        routeId: AppContentRoutes.oilChangeEditId(widget.orderId),
        breadcrumbTitle: 'تعديل بطاقة غيار زيت',
        builder: (_) => OilChangeFormScreen(
          key: ValueKey('oil-edit-${widget.orderId}'),
          editOrderId: widget.orderId,
          editOrderGlobalId: widget.orderGlobalId,
        ),
      ),
    );
    if (saved == true && mounted) unawaited(_load());
  }

  Future<void> _sendWhatsApp() async {
    final o = _order;
    if (o == null) return;
    final phone = (o['customerPhone'] ?? '').toString().trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد رقم هاتف في البطاقة')),
      );
      return;
    }
    final printData = await PrintSettingsRepository.instance.load();
    try {
      await OilChangeServicePdf.share(
        order: o,
        printSettings: printData,
      );
    } catch (e) {
      if (!mounted) return;
      final visitRem = oilChangeVisitRemainderFils(o);
      final priorDebt = await loadCustomerPriorOpenDebtFils(
        customerId: (o['customerId'] as num?)?.toInt(),
        customerName: (o['customerNameSnapshot'] ?? '').toString(),
        visitRemainderFils: visitRem,
      );
      final msg = buildOilServiceWhatsAppMessage(
        order: o,
        storeTitle: printData.whatsappStoreTitle,
        storeFooter: printData.whatsappStoreFooter,
        priorOpenDebtFils: priorDebt,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر إنشاء ملف PDF، سيتم فتح واتساب بالنص: $e')),
      );
      await launchWhatsAppWithMessage(context, phone: phone, message: msg);
    }
  }

  Future<void> _openInvoice() async {
    final o = _order;
    if (o == null) return;
    final invId = (o['invoiceId'] as num?)?.toInt() ?? 0;
    if (invId > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه البطاقة مرتبطة بفاتورة مسبقاً')),
      );
      return;
    }
    await ServiceOrderInvoiceBridge.openInvoiceFromOrder(
      context,
      order: o,
      orderId: widget.orderId,
      items: const [],
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.start,
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              textAlign: TextAlign.start,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _filterDetailRows(
    BuildContext context,
    Map<String, dynamic> o,
  ) {
    final lines = oilFilterLinesFromRow(o);
    if (lines.isNotEmpty) {
      return lines
          .map((line) => _row(context, 'فلتر', line))
          .toList(growable: false);
    }
    for (final kind in OilChangeFilterKind.all) {
      final name = (o[kind.nameColumnKey] ?? '').toString().trim();
      if (name.isNotEmpty) {
        return [_row(context, kind.label, name)];
      }
    }
    final legacy = (o['filterType'] ?? '').toString().trim();
    if (legacy.isNotEmpty) {
      return [_row(context, 'نوع الفلتر', legacy)];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Theme(
        data: OilChangeFormTheme.wrap(context, Theme.of(context)),
        child: Scaffold(
          appBar: OilChangeFormTheme.appBar(
            context: context,
            title: 'بطاقة غيار زيت',
            actions: const [],
          ),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_error != null || _order == null) {
      return Theme(
        data: OilChangeFormTheme.wrap(context, Theme.of(context)),
        child: Scaffold(
          appBar: OilChangeFormTheme.appBar(
            context: context,
            title: 'بطاقة غيار زيت',
            actions: const [],
          ),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'تعذّر عرض البطاقة',
                  style: TextStyle(color: cs.error),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('رجوع'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final o = _order!;
    final customer = (o['customerNameSnapshot'] ?? '').toString().trim();
    final services = parseOilRequestedServices(o['requestedServices']?.toString());
    final flags = OilExcelStyleFlags.fromRow(o);
    final agreedF = (o['agreedPriceFils'] as num?)?.toInt();
    final estF = (o['estimatedPriceFils'] as num?)?.toInt() ?? 0;
    final servicesF = agreedF ?? estF;
    final invoiceEstF = servicesF + _oilMaterialEstFils;
    final customerOil =
        ((o['oilCustomerProvided'] as num?)?.toInt() ?? 0) != 0;
    final oilLiters = (o['oilLitersUsed'] as num?)?.toDouble() ?? 0;
    final stockVoucherId = (o['stockVoucherId'] as num?)?.toInt() ?? 0;
    final invId = (o['invoiceId'] as num?)?.toInt() ?? 0;

    return Theme(
      data: OilChangeFormTheme.wrap(context, Theme.of(context)),
      child: Scaffold(
      appBar: OilChangeFormTheme.appBar(
        context: context,
        title: 'بطاقة غيار زيت',
        actions: [
          IconButton(
            tooltip: 'واتساب',
            onPressed: _sendWhatsApp,
            icon: const Icon(Icons.chat_rounded),
          ),
          IconButton(
            tooltip: 'تعديل',
            onPressed: _openEdit,
            icon: const Icon(Icons.edit_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 24),
        children: [
          Material(
            color: cs.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    customer.isEmpty ? 'عميل' : customer,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                    textAlign: TextAlign.start,
                  ),
                  if ((o['customerPhone'] ?? '').toString().trim().isNotEmpty)
                    Text(
                      (o['customerPhone'] ?? '').toString(),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _section(context, 'المركبة', Icons.directions_car_filled_rounded, [
            _row(context, 'السيارة', (o['deviceName'] ?? '').toString()),
            _row(context, 'الموديل', (o['carModel'] ?? '').toString()),
            _row(context, 'اللوحة', (o['deviceSerial'] ?? '').toString()),
            _row(context, 'المحرك', (o['engineSize'] ?? '').toString()),
          ]),
          _section(context, 'الزيت والعداد', Icons.opacity_rounded, [
            _row(context, 'قراءة حالية', '${oilFormatOdo((o['odometerCurrent'] ?? '').toString())} كم'),
            _row(context, 'قراءة لاحقة', '${oilFormatOdo((o['odometerNext'] ?? '').toString())} كم'),
            _row(context, 'نوع الزيت', (o['oilType'] ?? '').toString()),
            _row(context, 'اللزوجة', (o['oilViscosity'] ?? '').toString()),
            _row(context, 'الحجم', (o['oilSize'] ?? '').toString()),
            ..._filterDetailRows(context, o),
            _row(context, 'زيت كير', oilYesNo(flags.gearOil)),
          ]),
          _section(context, 'المخزون', Icons.inventory_2_outlined, [
            _row(
              context,
              'مصدر الزيت',
              customerOil ? 'زيت العميل' : 'زيت المحل',
            ),
            if (!customerOil) ...[
              _row(
                context,
                'صنف من المخزون',
                _oilProductName ?? '—',
              ),
              if (oilLiters > 0)
                _row(
                  context,
                  'لترات مُصرفة',
                  '${oilLiters.toStringAsFixed(1)} لتر',
                ),
              _row(
                context,
                'سند الصرف',
                stockVoucherId > 0 ? '#$stockVoucherId' : '—',
              ),
            ],
          ]),
          if (services.isNotEmpty)
            _section(context, 'خدمات إضافية', Icons.checklist_rounded, [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: services
                    .map(
                      (s) => Chip(
                        label: Text(s, style: const TextStyle(fontSize: 11.5)),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ]),
          _section(context, 'المالية', Icons.payments_outlined, [
            _row(
              context,
              'مبلغ الخدمات',
              servicesF > 0
                  ? IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(servicesF))
                  : '—',
            ),
            if (!customerOil && _oilMaterialEstFils > 0)
              _row(
                context,
                'مادة الزيت (تقدير)',
                IraqiCurrencyFormat.formatIqd(
                  IqdMoney.fromFils(_oilMaterialEstFils),
                ),
              ),
            if (!customerOil && _oilMaterialEstFils > 0)
              _row(
                context,
                'إجمالي الفاتورة (تقدير)',
                IraqiCurrencyFormat.formatIqd(
                  IqdMoney.fromFils(invoiceEstF),
                ),
              ),
            if (invId > 0)
              _row(context, 'فاتورة البيع', '#$invId'),
            _row(context, 'التاريخ', oilFormatDate((o['createdAt'] ?? '').toString())),
            _row(context, 'الفني', (o['technicianName'] ?? '').toString()),
            if ((o['issueDescription'] ?? '').toString().trim().isNotEmpty)
              _row(context, 'ملاحظات', (o['issueDescription'] ?? '').toString()),
          ]),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _openInvoice,
            icon: const Icon(Icons.point_of_sale_rounded),
            label: const Text('إصدار فاتورة بيع'),
          ),
        ],
      ),
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                    textAlign: TextAlign.start,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
