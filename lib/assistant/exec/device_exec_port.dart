import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../guides/guide_controller.dart';
import '../../models/customer_debt_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/shift_provider.dart';
import '../../utils/iqd_money.dart';
import '../../utils/sale_receipt_pdf.dart';
import '../../utils/shift_actor_conflict_guard.dart';
import '../../navigation/app_root_navigator_key.dart';
import '../../navigation/content_navigation.dart';
import '../../printing/invoice_receipt_screen.dart';
import '../../printing/receipt_builders.dart';
import '../../screens/customers/customer_form_screen.dart';
import '../../screens/expenses/expenses_screen.dart';
import '../../screens/inventory/add_product_screen.dart';
import '../../services/database_helper.dart';
import '../../services/product_repository.dart';
import '../../services/service_orders_sql_ops.dart';
import '../../services/tenant_context_service.dart';
import '../../verticals/car_wash/screens/car_wash_form_screen.dart';
import '../../verticals/oil_change/screens/oil_change_form_screen.dart';
import '../ui/assistant_return_chip.dart';
import '../ui/assistant_car_photo_screen.dart';
import '../ui/assistant_review_screen.dart';
import '../ui/assistant_session.dart';
import 'assistant_exec_port.dart';
import 'assistant_prefill.dart';
import 'assistant_reminders.dart';

/// أدوات التنفيذ على الجهاز: كل كتابة تمر بدالة التطبيق الموجودة نفسها.
class DeviceExecPort implements AssistantExecPort {
  DeviceExecPort({
    required this.guide,
    required this.reminders,
    required this.scheduler,
    required this.userKey,
  });

  final GuideController guide;
  final AssistantReminderStore reminders;
  final AssistantReminderScheduler scheduler;
  final String Function() userKey;

  final DatabaseHelper _db = DatabaseHelper();

  Future<int> _tenant() async {
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    return t.requireActiveTenantId();
  }

  /// صفحة الشات تنطوي قبل فتح الشاشة، وتبقى الفقاعة للرجوع إليها.
  Future<void> _minimize() async {
    final s = AssistantSession.instance;
    s.beforeGuide?.call();
    final overlay = s.rootOverlay;
    if (overlay != null && overlay.mounted)
      AssistantReturnChip.show(overlay, guide);
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<bool> _push(Route<void> route) async {
    if (await guide.pushRoute(route)) return true;
    final nav = appRootNavigatorKey.currentState;
    if (nav == null) return false;
    await nav.push(route);
    return true;
  }

  @override
  Future<AssistantFormOutcome> openForm(AssistantPrefill p) async {
    final (routeId, title, builder, table) = switch (p.tool) {
      'prepare_oil_card' => (
        AppContentRoutes.oilChangeCreate,
        'بطاقة غيار زيت جديدة',
        (BuildContext _) =>
            OilChangeFormScreen(key: UniqueKey(), assistantPrefill: p),
        'service_orders',
      ),
      'prepare_car_wash' => (
        AppContentRoutes.carWashCreate,
        'غسيل سيارة',
        (BuildContext _) => CarWashFormScreen(assistantPrefill: p),
        'service_orders',
      ),
      'prepare_customer' => (
        AppContentRoutes.customersAdd,
        'زبون جديد',
        (BuildContext _) => CustomerFormScreen(assistantPrefill: p),
        'customers',
      ),
      'prepare_product' => (
        AppContentRoutes.addProduct,
        'إضافة منتج',
        (BuildContext _) => AddProductScreen(assistantPrefill: p),
        'products',
      ),
      _ => (
        AppContentRoutes.expenses,
        'المصاريف',
        (BuildContext _) => ExpensesScreen(assistantPrefill: p),
        'expenses',
      ),
    };
    await _minimize();
    final since = DateTime.now().toIso8601String();
    final ok = await _push(
      contentMaterialRoute<void>(
        routeId: routeId,
        breadcrumbTitle: title,
        builder: builder,
      ),
    );
    if (!ok) return const AssistantFormOutcome.closed();
    // الحفظ بزر النموذج نفسه؛ نعرفه من صف جديد بعد لحظة الفتح.
    final id = await _createdSince(table, since);
    return id == null
        ? const AssistantFormOutcome.closed()
        : AssistantFormOutcome(saved: true, entityId: '$id');
  }

  Future<int?> _createdSince(String table, String since) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        table,
        columns: ['id'],
        where: 'tenantId = ? AND createdAt >= ?',
        whereArgs: [await _tenant(), since],
        orderBy: 'id DESC',
        limit: 1,
      );
      return rows.isEmpty ? null : (rows.first['id'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> applyPriceChange({
    required int productId,
    required int newSellFils,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'products',
      columns: [
        'name',
        'barcode',
        'buyPrice',
        'sellPrice',
        'minSellPrice',
        'qty',
        'lowStockThreshold',
        'trackInventory',
        'stockBaseKind',
      ],
      where: 'id = ? AND isActive = 1 AND tenantId = ?',
      whereArgs: [productId, await _tenant()],
      limit: 1,
    );
    if (rows.isEmpty) return 'الصنف ما موجود أو انحذف.';
    final r = rows.first;
    final sell = newSellFils / 1000.0;
    final minSell = (r['minSellPrice'] as num?)?.toDouble() ?? 0;
    try {
      // دالة شاشة التعديل السريع نفسها: تسجّل تغيير السعر للمالك وتزامنه.
      await ProductRepository().updateProductBasic(
        productId: productId,
        name: '${r['name'] ?? ''}',
        barcode: r['barcode'] as String?,
        buyPrice: (r['buyPrice'] as num?)?.toDouble() ?? 0,
        sellPrice: sell,
        minSellPrice: minSell > sell ? sell : minSell,
        qty: (r['qty'] as num?)?.toDouble() ?? 0,
        lowStockThreshold: (r['lowStockThreshold'] as num?)?.toDouble() ?? 0,
        trackInventory: ((r['trackInventory'] as num?)?.toInt() ?? 1) == 1,
        stockBaseKind: (r['stockBaseKind'] as num?)?.toInt(),
      );
      return null;
    } catch (e) {
      return 'ما گدرت أغيّر السعر: $e';
    }
  }

  Future<String> _voucherNo(String prefix) async {
    final base = '$prefix-${DateTime.now().millisecondsSinceEpoch}';
    for (var i = 0; i < 12; i++) {
      final c = i == 0 ? base : '$base-$i';
      if (!await _db.isStockVoucherNoTaken(c)) return c;
    }
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  Future<String?> applyStockMoves({
    required List<AssistantStockMove> moves,
    required String reason,
    required String sourceType,
    String? supplier,
  }) async {
    final tid = await _tenant();
    final wh = await _db.listWarehousesActive(tenantId: tid);
    if (wh.isEmpty) return 'ما عندك مخزن فعّال.';
    final whId = (wh.first['id'] as num).toInt();
    final ins = [
      for (final m in moves)
        if (m.delta > 0) m,
    ];
    final outs = [
      for (final m in moves)
        if (m.delta < 0) m,
    ];
    final note = 'عبر المساعد: $reason';
    if (ins.isNotEmpty) {
      final res = await _db.commitInboundStockVoucherWithLines(
        tenantId: tid,
        warehouseToId: whId,
        voucherNo: await _voucherNo('AI-IN'),
        voucherDate: DateTime.now(),
        supplierName: supplier,
        sourceType: sourceType,
        sourceName: supplier ?? 'المساعد',
        notes: note,
        lines: [
          for (final m in ins)
            (
              productId: m.productId,
              qty: m.delta,
              unitPrice: m.unitPriceIqd,
              enteredQty: null,
              unitFactor: null,
              unitLabel: null,
            ),
        ],
      );
      if (!res.ok) return res.message;
    }
    if (outs.isNotEmpty) {
      final res = await _db.commitOutboundStockVoucherWithLines(
        tenantId: tid,
        warehouseFromId: whId,
        voucherNo: await _voucherNo('AI-OUT'),
        voucherDate: DateTime.now(),
        sourceType: sourceType,
        sourceName: 'المساعد',
        notes: note,
        lines: [
          for (final m in outs)
            (productId: m.productId, qty: -m.delta, unitPrice: m.unitPriceIqd),
        ],
      );
      if (!res.ok)
        return ins.isEmpty
            ? res.message
            : 'انسجل الإدخال وفشل الصرف: ${res.message}';
    }
    return null;
  }

  @override
  Future<bool> openReview(AssistantReviewDraft draft) async {
    await _minimize();
    var committed = false;
    await _push(
      MaterialPageRoute<void>(
        builder: (_) => AssistantReviewScreen(
          draft: draft,
          port: this,
          onCommitted: () => committed = true,
          openNewProduct: (name) async {
            final out = await openForm(
              AssistantPrefill(
                tool: 'prepare_product',
                values: {'name': name},
                turnId: draft.turnId,
              ),
            );
            final id = int.tryParse(out.entityId ?? '');
            if (!out.saved || id == null) return null;
            final p = await _product(id);
            return (id, '${p?['name'] ?? name}');
          },
          qtyOf: (id) async =>
              ((await _product(id))?['qty'] as num?)?.toDouble(),
        ),
      ),
    );
    return committed;
  }

  Future<Map<String, Object?>?> _product(int id) async {
    final db = await _db.database;
    final rows = await db.query(
      'products',
      columns: ['name', 'qty'],
      where: 'id = ? AND tenantId = ?',
      whereArgs: [id, await _tenant()],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<String?> openPrintPreview({required String kind, String? ref}) async {
    switch (kind) {
      case 'receipt':
        final id = int.tryParse(ref ?? '') ?? await _latestInvoiceId();
        if (id == null) return 'not_found';
        final doc = await ReceiptBuilders.forInvoiceId(id);
        if (doc == null) return 'not_found';
        await _minimize();
        // لا ننتظر إغلاق المعاينة: الأداة تنتهي بفتحها.
        unawaited(
          _push(
            MaterialPageRoute<void>(
              builder: (_) => InvoiceReceiptScreen(document: doc),
            ),
          ),
        );
        return null;
      case 'label':
        await _minimize();
        await guide.openRoute(AppContentRoutes.inventoryBarcodeLabels);
        return null;
      default:
        await _minimize();
        await guide.openRoute(AppContentRoutes.printing);
        return null;
    }
  }

  Future<int?> _latestInvoiceId() async {
    final db = await _db.database;
    final rows = await db.query(
      'invoices',
      columns: ['id'],
      where: 'tenantId = ?',
      whereArgs: [await _tenant()],
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : (rows.first['id'] as num?)?.toInt();
  }

  /// سيارة بالرقم المقروء من آخر بطاقة لها، أو null. لا تخمين زبون (م4-13).
  Future<AssistantKnownCar?> lookupPlate(String plate) async {
    try {
      final db = await _db.database;
      final row = await ServiceOrdersSqlOps.getLatestByPlate(
        db,
        await _tenant(),
        deviceSerial: plate,
      );
      if (row == null) return null;
      final name = '${row['customerNameSnapshot'] ?? ''}'.trim();
      if (name.isEmpty) return null;
      final car = '${row['carModel'] ?? ''}'.trim();
      return AssistantKnownCar(
        customer: name,
        car: car.isEmpty ? null : car,
        lastOdometer: (row['odometerCurrent'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  /// يفتح بطاقة الغيار من القيم التي راجعها المستخدم، ويسجّل الحفظ إن تم.
  Future<void> openCarPhotoCard(
    Map<String, Object?> values, {
    String? username,
  }) async {
    final p = AssistantPrefill(tool: 'prepare_oil_card', values: values);
    final out = await openForm(p);
    if (out.saved) {
      await AssistantPrefill.recordSaved(
        p,
        entityType: 'service_order',
        entityId: out.entityId,
        username: username,
      );
    }
  }

  @override
  Future<String?> setReminder({
    required String text,
    required DateTime when,
  }) async {
    final id = await reminders.add(
      tenantId: '${guide.tenantId}',
      userKey: userKey(),
      text: text,
      when: when,
    );
    if (id == null)
      return 'عندك ${AssistantReminderStore.maxPending} تذكير. احذف واحد من «تذكيراتي».';
    await scheduler.schedule(
      AssistantReminder(id: id, text: text, when: when, status: 'pending'),
      now: DateTime.now(),
    );
    return null;
  }

  @override
  Future<String?> deactivateProduct(int productId) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'products',
        columns: ['id'],
        where: 'id = ? AND isActive = 1 AND tenantId = ?',
        whereArgs: [productId, await _tenant()],
        limit: 1,
      );
      if (rows.isEmpty) return 'الصنف ما موجود أو موقوف من قبل.';
      // دالة زر «إيقاف» بشاشة المخزون نفسها: إخفاء يُسجَّل ويُزامن، لا مسح.
      await ProductRepository().deactivateProduct(productId);
      return null;
    } catch (e) {
      return 'ما گدرت أوقف الصنف: $e';
    }
  }

  @override
  Future<String?> activateProduct(int productId) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'products',
        columns: ['id'],
        where: 'id = ? AND isActive = 0 AND tenantId = ?',
        whereArgs: [productId, await _tenant()],
        limit: 1,
      );
      if (rows.isEmpty) return 'الصنف ما موجود أو شغّال من قبل.';
      // دالة «إرجاع» الصنف نفسها: تُزامن ولا تمس كميته أو سجلاته.
      await ProductRepository().activateProduct(productId);
      return null;
    } catch (e) {
      return 'ما گدرت أرجّع الصنف: $e';
    }
  }

  @override
  Future<List<Map<String, Object?>>> inactiveProducts() async {
    final db = await _db.database;
    final rows = await db.query(
      'products',
      columns: ['id', 'name', 'barcode', 'qty'],
      where: 'isActive = 0 AND tenantId = ?',
      whereArgs: [await _tenant()],
      orderBy: 'updatedAt DESC',
      limit: 300,
    );
    return [
      for (final r in rows)
        {
          'id': (r['id'] as num).toInt(),
          'name': '${r['name'] ?? ''}',
          'barcode': r['barcode'],
          'qty': (r['qty'] as num?)?.toDouble() ?? 0,
        },
    ];
  }

  @override
  Future<String?> editProduct({
    required int productId,
    String? name,
    String? barcode,
    int? buyFils,
    int? sellFils,
    int? minSellFils,
    double? lowStock,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'products',
      columns: [
        'name',
        'barcode',
        'buyPrice',
        'sellPrice',
        'minSellPrice',
        'qty',
        'lowStockThreshold',
        'trackInventory',
        'stockBaseKind',
      ],
      where: 'id = ? AND isActive = 1 AND tenantId = ?',
      whereArgs: [productId, await _tenant()],
      limit: 1,
    );
    if (rows.isEmpty) return 'الصنف ما موجود أو موقوف.';
    final r = rows.first;
    double cur(String k) => (r[k] as num?)?.toDouble() ?? 0;
    final sell = sellFils == null ? cur('sellPrice') : sellFils / 1000.0;
    final minSell = minSellFils == null
        ? cur('minSellPrice')
        : minSellFils / 1000.0;
    if (minSell > sell) return 'أدنى سعر بيع أكبر من سعر البيع.';
    final newName = (name ?? '${r['name'] ?? ''}').trim();
    if (newName.isEmpty) return 'الاسم ما يصير فارغ.';
    try {
      // دالة شاشة تعديل الصنف نفسها: تفحص الباركود المكرر، وتسجّل تغيير السعر
      // للمالك، وتزامن. الكمية تُمرَّر كما هي.
      await ProductRepository().updateProductBasic(
        productId: productId,
        name: newName,
        barcode: barcode ?? r['barcode'] as String?,
        buyPrice: buyFils == null ? cur('buyPrice') : buyFils / 1000.0,
        sellPrice: sell,
        minSellPrice: minSell,
        qty: cur('qty'),
        lowStockThreshold: lowStock ?? cur('lowStockThreshold'),
        trackInventory: ((r['trackInventory'] as num?)?.toInt() ?? 1) == 1,
        stockBaseKind: (r['stockBaseKind'] as num?)?.toInt(),
      );
      return null;
    } catch (e) {
      if ('$e'.contains('duplicate_barcode'))
        return 'الباركود مستعمل لصنف ثاني.';
      return 'ما گدرت أعدّل الصنف: $e';
    }
  }

  @override
  Future<List<({int id, String name})>> listWarehouses() async {
    final wh = await _db.listWarehousesActive(tenantId: await _tenant());
    return [
      for (final w in wh)
        (
          id: (w['id'] as num).toInt(),
          name: '${w['name'] ?? 'مخزن ${w['id']}'}',
        ),
    ];
  }

  @override
  Future<String?> transferStock({
    required int productId,
    required double qty,
    required int fromWarehouseId,
    required int toWarehouseId,
    required double unitPriceIqd,
    String? note,
  }) async {
    final res = await _db.commitTransferStockVoucherWithLines(
      tenantId: await _tenant(),
      warehouseFromId: fromWarehouseId,
      warehouseToId: toWarehouseId,
      voucherNo: await _voucherNo('AI-TR'),
      voucherDate: DateTime.now(),
      sourceName: 'المساعد',
      notes: 'عبر المساعد${note == null ? '' : ': $note'}',
      lines: [(productId: productId, qty: qty, unitPrice: unitPriceIqd)],
    );
    return res.ok ? null : res.message;
  }

  @override
  Future<AssistantDebtPaymentOutcome> recordDebtPayment({
    required int customerId,
    required String customerName,
    required int amountFils,
    required String userName,
    String? note,
  }) async {
    final ctx = appRootNavigatorKey.currentContext;
    if (ctx == null)
      return const AssistantDebtPaymentOutcome.failed(
        'التطبيق مو جاهز، جرّب بعد لحظة.',
      );
    final conflict = ShiftActorConflictGuard.evaluate(
      sessionUserId: ctx.read<AuthProvider>().userId,
      activeShift: ctx.read<ShiftProvider>().activeShift,
    );
    if (conflict.hasConflict) {
      return AssistantDebtPaymentOutcome.failed(
        'ما أگدر أسجّل التسديد من هذه الجلسة: الوردية المفتوحة باسم ${conflict.shiftStaffName}.',
      );
    }
    final user = userName.trim().isEmpty ? '—' : userName.trim();
    try {
      final res = await _db.recordCustomerDebtPayment(
        party: CustomerDebtParty(
          customerId: customerId,
          displayName: customerName,
          normalizedName: customerName.toLowerCase(),
        ),
        amount: IqdMoney.fromFils(amountFils),
        recordedByUserName: user,
        note: 'عبر المساعد${note == null ? '' : ': $note'}',
      );
      if (res == null)
        return const AssistantDebtPaymentOutcome.failed(
          'ما عليه دين مفتوح أو المبلغ مو صالح.',
        );
      final c = appRootNavigatorKey.currentContext;
      if (c != null && c.mounted) {
        await _minimize();
        if (c.mounted) {
          // الوصل نفسه الذي تعرضه شاشة الديون بعد التسديد.
          unawaited(
            SaleReceiptPdf.presentCustomerDebtPaymentReceipt(
              c,
              customerDisplayName: customerName,
              customerId: customerId,
              amountApplied: res.amountApplied,
              debtBefore: res.debtBefore,
              debtAfter: res.debtAfter,
              paymentRowId: res.paymentRowId,
              receiptInvoiceId: res.receiptInvoiceId,
              recordedByUserName: user == '—' ? null : user,
            ),
          );
        }
      }
      return AssistantDebtPaymentOutcome(
        appliedFils: IqdMoney.toFils(res.amountApplied),
        debtAfterFils: IqdMoney.toFils(res.debtAfter),
      );
    } catch (e) {
      return AssistantDebtPaymentOutcome.failed('ما گدرت أسجّل التسديد: $e');
    }
  }
}
