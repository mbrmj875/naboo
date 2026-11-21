import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/invoice.dart';
import '../providers/auth_provider.dart';
import '../providers/business_features_provider.dart';
import '../providers/global_barcode_route_bridge.dart';
import '../providers/product_provider.dart';
import '../providers/sale_draft_provider.dart';
import '../screens/debts/customer_debt_detail_screen.dart';
import '../screens/inventory/add_product_screen.dart';
import '../screens/invoices/add_invoice_screen.dart';
import '../screens/invoices/process_return_screen.dart';
import '../services/database_helper.dart';
import '../services/returns/return_history.dart';
import '../services/store_policy_settings_repository.dart';
import '../utils/invoice_barcode.dart';
import '../utils/invoice_deep_link.dart';
import '../utils/iraqi_currency_format.dart';
import '../widgets/invoice_detail_sheet.dart';
import '../printing/receipt_model.dart';
import '../services/business_setup_settings.dart';
import '../verticals/car_wash/screens/car_wash_form_screen.dart';
import '../verticals/car_wash/services/car_wash_services_repository.dart';
import '../verticals/oil_change/screens/oil_change_form_screen.dart';
import '../verticals/oil_change/services/oil_change_orders_repository.dart';
import 'content_navigation.dart';
import 'scanned_receipt_lookup.dart';

typedef HomeBarcodeRouteOpener = Future<void> Function(Route<void> route);

/// منطق مسح الباركود المشترك بين الرئيسية العامة والرئيسية الزيتية المستقلة.
///
/// إبقاؤه خارج الشاشات يمنع اختلاف السلوك بين المسارين، وخصوصاً في المتجر
/// الهجين الذي يجمع غيار الزيت ونقطة البيع.
abstract final class HomeBarcodeRouteCoordinator {
  HomeBarcodeRouteCoordinator._();

  static Future<void> handle(
    BuildContext context,
    String scanned, {
    required WidgetBuilder? oilCreateBuilder,
    required HomeBarcodeRouteOpener openRoute,
  }) async {
    final raw = scanned.trim();
    if (raw.isEmpty || !context.mounted) return;

    final features = context.read<BusinessFeaturesProvider>();
    final invoiceId = tryParseInvoiceIdFromBarcode(raw);
    if (invoiceId != null) {
      if (!features.data.enablePos) return;
      await _offerReturnForInvoice(context, invoiceId, openRoute);
      return;
    }

    final debtCustomerId = tryParseCustomerDebtIdFromScannedText(raw);
    if (debtCustomerId != null) {
      if (!features.data.enableDebts || !context.mounted) return;
      await openRoute(
        FastContentPageRoute<void>(
          builder: (_) => CustomerDebtDetailScreen.fromCustomerId(
            registeredCustomerId: debtCustomerId,
          ),
        ),
      );
      return;
    }

    final deepInvoiceUri = Uri.tryParse(raw);
    if (deepInvoiceUri != null && deepInvoiceUri.hasScheme) {
      final ref = InvoiceDeepLink.parse(deepInvoiceUri);
      if (ref != null) {
        // رمز الإيصال يعمل في كل المحلات (لا يشترط نقطة البيع): التوجيه
        // حسب نوع العمل لا حسب ميزات الشاشة.
        if (!context.mounted || !context.read<AuthProvider>().isLoggedIn) {
          return;
        }
        await _openScannedReceipt(context, ref, openRoute);
        return;
      }
    }

    final productProvider = context.read<ProductProvider>();
    final product = await productProvider.findProductByBarcode(raw);
    if (!context.mounted) return;
    SchedulerBinding.instance.scheduleFrame();

    if (product != null) {
      if (features.data.enableOilChange && !features.data.enablePos) {
        if (oilCreateBuilder == null) return;
        unawaited(
          openRoute(
            contentMaterialRoute<void>(
              routeId: AppContentRoutes.oilChangeCreate,
              breadcrumbTitle: 'بطاقة غيار زيت جديدة',
              builder: oilCreateBuilder,
            ),
          ),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            unawaited(context.read<GlobalBarcodeRouteBridge>().dispatch(raw));
          });
        });
        return;
      }

      final draft = context.read<SaleDraftProvider>();
      draft.enqueueProductLine({'barcode': raw});
      if (!draft.isSaleScreenOpen) {
        _openAfterFrame(
          context,
          openRoute,
          contentMaterialRoute<void>(
            routeId: AppContentRoutes.addInvoice,
            breadcrumbTitle: 'بيع جديد',
            builder: (_) => const AddInvoiceScreen(),
          ),
        );
      }
      return;
    }

    final draft = context.read<SaleDraftProvider>();
    final addProductRoute = contentMaterialRoute<void>(
      routeId: AppContentRoutes.addProduct,
      breadcrumbTitle: 'إضافة منتج',
      builder: (_) =>
          AddProductScreen(initialBarcode: raw, autoFillFromScan: true),
    );
    if (!draft.isSaleScreenOpen) {
      _openAfterFrame(context, openRoute, addProductRoute);
      return;
    }

    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;
    await openRoute(addProductRoute);
    if (!context.mounted) return;
    SchedulerBinding.instance.scheduleFrame();
    final afterAdd = await productProvider.findProductByBarcode(raw);
    if (!context.mounted || afterAdd == null) return;
    draft.enqueueProductLine({'barcode': raw});
  }

  static void _openAfterFrame(
    BuildContext context,
    HomeBarcodeRouteOpener openRoute,
    Route<void> route,
  ) {
    SchedulerBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      unawaited(openRoute(route));
    });
  }

  /// رمز إيصال: بطاقة الزيت والغسيل تفتح عملاً جديداً معبّأً من آخر زيارة
  /// للسيارة، وباقي الإيصالات تعرض تفاصيل الفاتورة.
  static Future<void> _openScannedReceipt(
    BuildContext context,
    InvoiceLinkRef ref,
    HomeBarcodeRouteOpener openRoute,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await ScannedReceiptLookup.resolve(ref);
    if (!context.mounted) return;
    final rec = result.receipt;
    if (rec == null) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'تعذر قراءة الإيصال.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final biz = context.read<BusinessFeaturesProvider>().data;
    final serviceShop =
        biz.enableOilChange ||
        biz.effectiveVertical == BusinessVertical.oilChange;
    final order = rec.order;
    if (serviceShop && order != null && !rec.invoice.isReturned) {
      switch (rec.kind) {
        case ReceiptKind.oilChange:
          await _newOilCardFromScan(context, rec, order, openRoute);
          return;
        case ReceiptKind.carWash:
          await _newWashFromScan(context, rec, order, openRoute);
          return;
        default:
          break;
      }
    }
    final isSale =
        rec.kind == ReceiptKind.directSale || rec.kind == ReceiptKind.sale;
    if (isSale && order == null && !rec.invoice.isReturned) {
      await _openReturnFromScan(context, rec, openRoute);
      return;
    }
    // إيصال استرجاع أو غيره: عرض فقط.
    await showInvoiceDetailSheet(context, DatabaseHelper(), rec.invoiceId);
  }

  /// مسح إيصال بيع: شاشة الاسترجاع المحمية، أو رسالة حمراء إن أُرجع بالكامل.
  static Future<void> _openReturnFromScan(
    BuildContext context,
    ScannedReceipt rec,
    HomeBarcodeRouteOpener openRoute,
  ) async {
    final inv = rec.invoice;
    final collection =
        inv.type == InvoiceType.debtCollection ||
        inv.type == InvoiceType.installmentCollection ||
        inv.type == InvoiceType.supplierPayment;
    final policy =
        (await StorePolicySettingsRepository.instance.load()).returns;
    if (!context.mounted) return;
    if (collection || !policy.enabled) {
      await showInvoiceDetailSheet(context, DatabaseHelper(), rec.invoiceId);
      return;
    }
    final history = await ReturnHistory.of(inv);
    if (!context.mounted) return;
    if (history.fullyReturned) {
      final cs = Theme.of(context).colorScheme;
      final when = history.lastDate == null
          ? ''
          : ' بتاريخ ${DateFormat('yyyy/MM/dd HH:mm', 'ar').format(history.lastDate!)}';
      final by = (history.lastBy ?? '').isEmpty
          ? ''
          : ' بواسطة ${history.lastBy}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: cs.error,
          duration: const Duration(seconds: 10),
          behavior: SnackBarBehavior.floating,
          content: Text(
            'أُرجعت هذه الفاتورة بالكامل$when$by '
            'بمبلغ ${IraqiCurrencyFormat.formatIqd(history.totalAmount)}.',
          ),
          action: SnackBarAction(
            label: 'عرض',
            textColor: cs.onError,
            onPressed: () => showInvoiceDetailSheet(
              context,
              DatabaseHelper(),
              rec.invoiceId,
            ),
          ),
        ),
      );
      return;
    }
    final id = rec.invoiceId;
    await openRoute(
      contentMaterialRoute<void>(
        routeId: AppContentRoutes.processReturn(id),
        breadcrumbTitle: 'مرتجع #$id',
        builder: (_) => ProcessReturnScreen(
          originalInvoice: inv,
          legacyReceipt: rec.legacy,
        ),
      ),
    );
  }

  static Future<void> _newOilCardFromScan(
    BuildContext context,
    ScannedReceipt rec,
    Map<String, dynamic> order,
    HomeBarcodeRouteOpener openRoute,
  ) async {
    final plate = (order['deviceSerial'] ?? '').toString().trim();
    // من آخر زيارة للسيارة، لا من الإيصال الممسوح إن كان قديماً.
    final latest = plate.isEmpty
        ? null
        : await OilChangeOrdersRepository.instance.getLatestOilChangeByPlate(
            plate,
          );
    if (!context.mounted) return;
    final source = Map<String, dynamic>.from(latest ?? order);
    _showScanNote(
      context,
      rec,
      todayAt: sameDayTime(source),
      todayLabel: 'تم غيار لهذه السيارة اليوم',
      newLabel: 'بطاقة غيار جديدة من آخر زيارة',
    );
    final sourceId = (source['id'] as num?)?.toInt() ?? 0;
    await openRoute(
      contentMaterialRoute<void>(
        routeId: AppContentRoutes.oilChangeCreate,
        breadcrumbTitle: 'بطاقة غيار زيت جديدة',
        builder: (_) => OilChangeFormScreen(
          key: ValueKey('oil-scan-$sourceId'),
          prefillFromOrder: source,
        ),
      ),
    );
  }

  static Future<void> _newWashFromScan(
    BuildContext context,
    ScannedReceipt rec,
    Map<String, dynamic> order,
    HomeBarcodeRouteOpener openRoute,
  ) async {
    final plate = (order['deviceSerial'] ?? '').toString().trim();
    final latest = await CarWashServicesRepository.instance.latestWashByPlate(
      plate,
    );
    if (!context.mounted) return;
    final source = Map<String, dynamic>.from(latest ?? order);
    _showScanNote(
      context,
      rec,
      todayAt: sameDayTime(source),
      todayLabel: 'تم غسل هذه السيارة اليوم',
      newLabel: 'غسلة جديدة من آخر زيارة',
    );
    await openRoute(
      contentMaterialRoute<void>(
        routeId: AppContentRoutes.carWashCreate,
        breadcrumbTitle: 'غسيل سيارة',
        builder: (_) => CarWashFormScreen(prefillFromOrder: source),
      ),
    );
  }

  /// وقت البطاقة إن كانت اليوم (تحذير من تكرار بالخطأ)، وإلا null.
  @visibleForTesting
  static DateTime? sameDayTime(Map<String, dynamic> row, {DateTime? now}) {
    final at = DateTime.tryParse((row['createdAt'] ?? '').toString());
    if (at == null) return null;
    final local = at.toLocal();
    final n = now ?? DateTime.now();
    if (local.year != n.year || local.month != n.month || local.day != n.day) {
      return null;
    }
    return local;
  }

  static void _showScanNote(
    BuildContext context,
    ScannedReceipt rec, {
    required DateTime? todayAt,
    required String todayLabel,
    required String newLabel,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final id = rec.invoiceId;
    final hm = todayAt == null
        ? ''
        : '${todayAt.hour.toString().padLeft(2, '0')}:'
              '${todayAt.minute.toString().padLeft(2, '0')}';
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          todayAt != null
              ? '⚠ $todayLabel الساعة $hm — تأكد أنها ليست تكراراً.'
              : '$newLabel (إيصال #$id). عدّل ثم احفظ.',
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: todayAt != null ? 10 : 5),
        action: SnackBarAction(
          label: 'عرض الإيصال',
          onPressed: () {
            if (!context.mounted) return;
            unawaited(showInvoiceDetailSheet(context, DatabaseHelper(), id));
          },
        ),
      ),
    );
  }

  static Future<void> _offerReturnForInvoice(
    BuildContext context,
    int id,
    HomeBarcodeRouteOpener openRoute,
  ) async {
    final invoice = await DatabaseHelper().getInvoiceById(id);
    if (!context.mounted) return;
    if (invoice == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('لا توجد فاتورة برقم $id')));
      return;
    }
    if (invoice.isReturned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الفاتورة مسجّلة كمرتجع مسبقاً')),
      );
      return;
    }
    if (invoice.type == InvoiceType.debtCollection ||
        invoice.type == InvoiceType.installmentCollection ||
        invoice.type == InvoiceType.supplierPayment) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'هذا السند لا يُفتَح كمرتجع بيع — عكس الدفعة من شاشة المورد أو إدارة الأقساط حسب النوع.',
          ),
        ),
      );
      return;
    }

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('فاتورة بيع #${invoice.id}'),
            content: Text(
              'العميل: ${invoice.customerName.trim().isEmpty ? '(فارغ)' : invoice.customerName}\n'
              'الدفع: ${_invoiceTypeAr(invoice.type)}\n'
              'الإجمالي: ${IraqiCurrencyFormat.formatIqd(invoice.total)}\n\n'
              'فتح شاشة المرتجع؟ يمكنك تقليل الكمية أو حذف الأسطر لإرجاع جزئي فقط.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('مرتجع'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;

    final routeId = invoice.id ?? id;
    await openRoute(
      contentMaterialRoute<void>(
        routeId: AppContentRoutes.processReturn(routeId),
        breadcrumbTitle: 'مرتجع #$routeId',
        // باركود INV رقم محلي فقط: يُعامل كإيصال قديم ويحتاج موافقة.
        builder: (_) =>
            ProcessReturnScreen(originalInvoice: invoice, legacyReceipt: true),
      ),
    );
  }

  static String _invoiceTypeAr(InvoiceType type) {
    switch (type) {
      case InvoiceType.cash:
        return 'نقدي';
      case InvoiceType.credit:
        return 'آجل';
      case InvoiceType.installment:
        return 'أقساط';
      case InvoiceType.delivery:
        return 'توصيل';
      case InvoiceType.debtCollection:
        return 'تحصيل دين';
      case InvoiceType.installmentCollection:
        return 'تسديد قسط';
      case InvoiceType.supplierPayment:
        return 'دفع مورد';
    }
  }
}
