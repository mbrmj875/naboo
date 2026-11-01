import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
import '../utils/invoice_barcode.dart';
import '../utils/invoice_deep_link.dart';
import '../utils/iraqi_currency_format.dart';
import '../widgets/invoice_detail_sheet.dart';
import 'content_navigation.dart';

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
      final linkedInvoiceId = InvoiceDeepLink.parseInvoiceId(deepInvoiceUri);
      if (linkedInvoiceId != null && linkedInvoiceId > 0) {
        if (!features.data.enablePos ||
            !context.mounted ||
            !context.read<AuthProvider>().isLoggedIn) {
          return;
        }
        await showInvoiceDetailSheet(
          context,
          DatabaseHelper(),
          linkedInvoiceId,
        );
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
        builder: (_) => ProcessReturnScreen(originalInvoice: invoice),
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
