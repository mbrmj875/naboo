import '../verticals/oil_change/models/oil_card_wash.dart';
import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../models/expense.dart';
import '../models/invoice.dart';
import '../services/database_helper.dart';
import '../services/returns/return_meta.dart';
import '../services/service_order_kinds.dart';
import '../utils/invoice_deep_link.dart';
import '../utils/iqd_money.dart';
import '../utils/app_logger.dart';
import '../verticals/oil_change/models/oil_change_filter_kind.dart';
import '../verticals/oil_change/services/oil_change_direct_sale_service.dart';
import '../verticals/oil_change/utils/oil_change_filter_format.dart';
import 'receipt_model.dart';
import '../verticals/oil_change/utils/oil_order_has_oil.dart';
import '../verticals/oil_change/utils/oil_odometer_unit.dart';
import '../verticals/oil_change/utils/oil_change_lookup_normalize.dart';
import '../verticals/oil_change/utils/oil_change_order_status.dart';
import '../verticals/car_wash/services/wash_offer_engine.dart';

/// يبني [ReceiptDocument] من بيانات المنظومة لكل نوع عمل.
abstract final class ReceiptBuilders {
  /// إيصال فاتورة: يكتشف هل هي بطاقة غيار، غسيل، بيع مباشر، أو بيع عام.
  static Future<ReceiptDocument?> forInvoiceId(int invoiceId) async {
    final helper = DatabaseHelper();
    final invoice = await helper.getInvoiceById(invoiceId);
    if (invoice == null) return null;
    final order = await linkedOrder(invoiceId);
    return fromInvoice(
      invoice,
      order: order,
      accountBalanceFils: await accountBalanceFilsFor(invoice),
      cardDebtPayment: await cardDebtPaymentFor(order),
      visitNumber: await oilVisitNumberFor(order),
    );
  }

  /// رقم زيارة السيارة لتبديل الزيت حتى هذه البطاقة (بنفس رقم اللوحة،
  /// وإلا بنفس العميل). يُستبعد المحذوف والملغى والمعلّق والمرتجع.
  static Future<int?> oilVisitNumberFor(Map<String, dynamic>? order) async {
    final o = order;
    if (o == null || o['orderKind'] != ServiceOrderKinds.oilChange) return null;
    final at = (o['createdAt'] ?? '').toString();
    if (at.isEmpty) return null;
    final key = OilChangeLookupNormalize.normalizePlateKey(
      (o['deviceSerial'] ?? '').toString(),
    );
    final cid = (o['customerId'] as num?)?.toInt() ?? 0;
    if (key.isEmpty && cid <= 0) return null;
    try {
      final helper = DatabaseHelper();
      final db = await helper.database;
      final byCustomer = key.isEmpty;
      final rows = await db.rawQuery(
        '''
        SELECT so.deviceSerial
        FROM service_orders so
        LEFT JOIN invoices i ON i.id = so.invoiceId AND i.tenantId = so.tenantId
        WHERE so.tenantId = ?
          AND so.deletedAt IS NULL
          AND so.orderKind = ?
          AND so.status NOT IN (?, ?)
          AND so.createdAt <= ?
          ${byCustomer ? 'AND so.customerId = ?' : ''}
          AND IFNULL(i.isReturned, 0) = 0
        ''',
        [
          await helper.resolveLocalBusinessTenantId(),
          ServiceOrderKinds.oilChange,
          OilChangeOrderStatus.cancelled,
          OilChangeOrderStatus.suspended,
          at,
          if (byCustomer) cid,
        ],
      );
      final n = byCustomer
          ? rows.length
          : rows
                .where(
                  (r) =>
                      OilChangeLookupNormalize.normalizePlateKey(
                        (r['deviceSerial'] ?? '').toString(),
                      ) ==
                      key,
                )
                .length;
      return n > 0 ? n : null;
    } catch (e, st) {
      AppLogger.error('ReceiptBuilders', 'تعذّر عدّ زيارات السيارة', e, st);
      return null;
    }
  }

  /// ما سُدِّد من الدين السابق في بطاقة الغيار نفسها (الزائد عن الزيارة):
  /// دفعة الدين التي سجّلها حفظ البطاقة بملاحظة «من بطاقة غيار #رقمها».
  static Future<({int paidFils, int beforeFils})?> cardDebtPaymentFor(
    Map<String, dynamic>? order,
  ) async {
    final id = (order?['id'] as num?)?.toInt() ?? 0;
    final cid = (order?['customerId'] as num?)?.toInt() ?? 0;
    if (id <= 0 || cid <= 0) return null;
    try {
      final helper = DatabaseHelper();
      final db = await helper.database;
      final rows = await db.query(
        'customer_debt_payments',
        columns: ['amount', 'debtBefore'],
        where: 'tenantId = ? AND customerId = ? AND note = ?',
        whereArgs: [
          await helper.resolveLocalBusinessTenantId(),
          cid,
          'من بطاقة غيار #$id',
        ],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final paid = IqdMoney.toFils(
        (rows.first['amount'] as num?)?.toDouble() ?? 0,
      );
      if (paid <= 0) return null;
      return (
        paidFils: paid,
        beforeFils: IqdMoney.toFils(
          (rows.first['debtBefore'] as num?)?.toDouble() ?? 0,
        ),
      );
    } catch (e, st) {
      AppLogger.error('ReceiptBuilders', 'تعذّر جلب تسديد البطاقة', e, st);
      return null;
    }
  }

  /// دين العميل المسجّل المفتوح الآن (كل فواتيره الآجلة)، أو `null`.
  static Future<int?> accountBalanceFilsFor(Invoice invoice) async {
    final cid = invoice.customerId;
    if (cid == null || cid <= 0 || invoice.isReturned) return null;
    try {
      final d = await DatabaseHelper().sumOpenCreditDebtForCustomer(cid);
      return IqdMoney.toFils(d);
    } catch (e, st) {
      AppLogger.error('ReceiptBuilders', 'تعذّر جلب رصيد العميل', e, st);
      return null;
    }
  }

  /// نوع العمل الذي تمثّله الفاتورة (بطاقتها المرتبطة أولاً، ثم علامة البيع).
  static ReceiptKind kindOf(Invoice invoice, {Map<String, dynamic>? order}) =>
      invoice.isReturned
      ? ReceiptKind.saleReturn
      : switch (order) {
          final o? when ServiceOrderKinds.isCarWash(o) => ReceiptKind.carWash,
          final o? when ServiceOrderKinds.isOilChangeLogRow(o) =>
            ReceiptKind.oilChange,
          _
              when invoice.deliveryAddress ==
                  OilChangeDirectSaleService.sourceTag =>
            ReceiptKind.directSale,
          _ => ReceiptKind.sale,
        };

  /// بطاقة الخدمة المرتبطة بالفاتورة (زيت/غسيل) إن وُجدت.
  static Future<Map<String, dynamic>?> linkedOrder(int invoiceId) async {
    final helper = DatabaseHelper();
    final db = await helper.database;
    final tenantId = await helper.resolveLocalBusinessTenantId();
    final rows = await db.rawQuery(
      'SELECT so.* FROM service_orders so '
      'JOIN invoices i ON i.id = so.invoiceId AND i.tenantId = so.tenantId '
      'WHERE so.invoiceId = ? AND so.tenantId = ? AND so.deletedAt IS NULL '
      'ORDER BY so.id DESC LIMIT 1',
      [invoiceId, tenantId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// بطاقات الخدمة المرتبطة بعدة فواتير باستعلام واحد (لقوائم الفواتير).
  /// يُرجع لكل فاتورة أحدث بطاقة: النوع والأعمدة اللازمة لـ [kindOf] فقط.
  static Future<Map<int, Map<String, dynamic>>> linkedOrderKinds(
    Set<int> invoiceIds,
  ) async {
    if (invoiceIds.isEmpty) return const {};
    final helper = DatabaseHelper();
    final db = await helper.database;
    final tenantId = await helper.resolveLocalBusinessTenantId();
    final out = <int, Map<String, dynamic>>{};
    final ids = invoiceIds.toList(growable: false);
    for (var i = 0; i < ids.length; i += 400) {
      final chunk = ids.sublist(i, math.min(i + 400, ids.length));
      final marks = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        // البطاقة كاملة: نوعها، ومحتواها لاسم العمل («تبديل فلتر»…).
        'SELECT * FROM service_orders '
        'WHERE tenantId = ? AND deletedAt IS NULL AND invoiceId IN ($marks) '
        'ORDER BY id DESC',
        [tenantId, ...chunk],
      );
      for (final r in rows) {
        final id = (r['invoiceId'] as num?)?.toInt();
        if (id != null) out.putIfAbsent(id, () => r);
      }
    }
    return out;
  }

  /// اسم العمل على بطاقة الفاتورة في القوائم: بطاقة غيار بلا زيت تُسمّى
  /// بمحتواها («تبديل فلتر»، «هيدروليك»…) كما في عنوان إيصالها.
  static String workLabelOf(ReceiptKind kind, Map<String, dynamic>? order) {
    if (kind == ReceiptKind.oilChange && order != null) {
      return oilCardWorkLabel(order);
    }
    return kind.shortLabel;
  }

  /// يبني الإيصال من فاتورة محمّلة، ومعها بطاقة الخدمة المرتبطة إن وُجدت.
  ///
  /// [accountBalanceFils]: دين العميل المفتوح الآن؛ إن كان عليه دين غير هذه
  /// الفاتورة يُطبع «دين سابق» و«رصيد الحساب الآن».
  ///
  /// [cardDebtPayment]: ما سدّده العميل من دينه السابق في هذه البطاقة؛ يُطبع
  /// «دين سابق» و«تسديد من الدين السابق» و«المستلم» كله و«رصيد الحساب الآن»
  /// حتى لو صار الرصيد صفراً.
  static ReceiptDocument fromInvoice(
    Invoice invoice, {
    Map<String, dynamic>? order,
    int? accountBalanceFils,
    ({int paidFils, int beforeFils})? cardDebtPayment,
    int? visitNumber,
  }) {
    final kind = kindOf(invoice, order: order);
    if (kind == ReceiptKind.saleReturn) return saleReturn(invoice);

    final fields = <ReceiptField>[];
    final highlights = <ReceiptHighlight>[];
    final o = order ?? const <String, dynamic>{};
    String s(String k) => (o[k] ?? '').toString().trim();

    final customer = invoice.customerName.trim();
    final phone = s('customerPhone');
    final isAnonymous =
        customer.isEmpty ||
        customer == 'بيع مباشر' ||
        customer == OilChangeDirectSaleService.defaultActorLabel ||
        customer == 'زبون نقدي';

    if (kind == ReceiptKind.oilChange || kind == ReceiptKind.carWash) {
      final plate = s('deviceSerial');
      if (plate.isNotEmpty) {
        fields.add(
          ReceiptField(
            'اللوحة',
            plate,
            section: ReceiptSection.plate,
            bold: true,
          ),
        );
      }
      // في الغسيل deviceName وصف للغسلة لا اسم السيارة.
      final car = s('carModel').isNotEmpty || kind == ReceiptKind.carWash
          ? s('carModel')
          : s('deviceName');
      if (car.isNotEmpty) {
        fields.add(ReceiptField('السيارة', car, section: ReceiptSection.car));
      }
    }

    if (kind == ReceiptKind.oilChange) {
      final odo = s('odometerCurrent');
      if (odo.isNotEmpty) {
        fields.add(
          ReceiptField(
            'العداد',
            '${_groupDigits(odo)} ${OilOdometerUnit.labelOf(o)}',
            section: ReceiptSection.odometer,
          ),
        );
      }
      final oil = [
        s('oilType'),
        s('oilViscosity'),
      ].where((e) => e.isNotEmpty).toSet().join(' ');
      final liters = (o['oilLitersUsed'] as num?)?.toDouble() ?? 0;
      final own = (o['oilCustomerProvided'] as num?)?.toInt() == 1;
      if (oil.isNotEmpty || own) {
        fields.add(
          ReceiptField(
            'الزيت',
            own ? '${oil.isEmpty ? '' : '$oil '}(زيت العميل)'.trim() : oil,
            section: ReceiptSection.oil,
          ),
        );
      }
      if (liters > 0) {
        fields.add(
          ReceiptField(
            'الكمية',
            '${_qty(liters)} لتر',
            section: ReceiptSection.oil,
          ),
        );
      }
      for (final f in oilFilterLinesDataFromRow(o)) {
        final label = (f.label?.trim().isNotEmpty ?? false)
            ? f.label!.trim()
            : (OilChangeFilterKind.fromCode(f.code)?.label ?? 'فلتر');
        fields.add(
          ReceiptField(
            label,
            f.name.isEmpty ? 'تم التبديل' : f.name,
            section: ReceiptSection.filters,
          ),
        );
      }
      final tech = s('technicianName');
      if (tech.isNotEmpty) {
        fields.add(
          ReceiptField('الفني', tech, section: ReceiptSection.technician),
        );
      }
      // الغسلة داخل البطاقة: سطرها في البنود، وهنا نوعها وعاملها وسبب العرض.
      final wash = OilCardWash.fromOrder(Map<String, dynamic>.from(o));
      if (wash != null) {
        final note = (wash.offerNote ?? '').trim();
        fields.add(
          ReceiptField(
            'الغسيل',
            note.isEmpty
                ? wash.serviceNames.join('، ')
                : '${wash.serviceNames.join('، ')} — $note',
            section: ReceiptSection.wash,
          ),
        );
        if (wash.washerName.isNotEmpty) {
          fields.add(
            ReceiptField(
              'عامل الغسيل',
              wash.washerName,
              section: ReceiptSection.wash,
            ),
          );
        }
      }
      final next = s('odometerNext');
      if (next.isNotEmpty) {
        highlights.add(
          ReceiptHighlight(
            'الغيار القادم عند',
            '${_groupDigits(next)} ${OilOdometerUnit.labelOf(o)}',
            section: ReceiptSection.nextService,
          ),
        );
      }
    }

    final notes = <String>[];
    ReceiptLoyalty? loyalty;
    if (kind == ReceiptKind.oilChange && visitNumber != null) {
      loyalty = ReceiptLoyalty(visit: visitNumber);
    }
    if (kind == ReceiptKind.carWash) {
      // سبب الخصم والسطر التشجيعي («غسلتان من 3 — الغسلة القادمة مجانية»):
      // سطر التقدّم يصير صندوق العرض بنقاطه، والباقي ملاحظات.
      for (final raw in s('washOfferNote').split('\n')) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        final p = loyalty == null ? WashOfferEngine.progressOf(line) : null;
        if (p != null) {
          loyalty = ReceiptLoyalty(line: line, done: p.done, total: p.total);
        } else {
          notes.add(line);
        }
      }
      final washer = s('technicianName');
      if (washer.isNotEmpty) {
        fields.add(
          ReceiptField('العامل', washer, section: ReceiptSection.technician),
        );
      }
    }

    if (!isAnonymous) {
      fields.insert(
        0,
        ReceiptField(
          'العميل',
          phone.isEmpty ? customer : '$customer · $phone',
          section: ReceiptSection.customer,
        ),
      );
    }

    final lines = [
      for (final it in invoice.items)
        ReceiptLine(
          name: it.productName,
          quantity: it.enteredQtyResolved,
          unit: it.unitLabel,
          unitPriceFils: it.enteredQtyResolved > 0
              ? (IqdMoney.toFils(it.total) / it.enteredQtyResolved).round()
              : null,
          totalFils: IqdMoney.toFils(it.total),
        ),
    ];

    final subtotal = lines.fold<int>(0, (a, l) => a + l.totalFils);
    final total = IqdMoney.toFils(invoice.total);
    final discount = IqdMoney.toFils(invoice.discount);
    final tax = IqdMoney.toFils(invoice.tax);
    final paid = IqdMoney.toFils(invoice.advancePayment);
    final isCredit =
        invoice.type == InvoiceType.credit ||
        invoice.type == InvoiceType.installment;
    final totals = <ReceiptTotal>[
      if (discount > 0 || tax > 0) ReceiptTotal('المجموع', subtotal),
      if (discount > 0) ReceiptTotal('الخصم', discount),
      if (tax > 0) ReceiptTotal('الضريبة', tax),
      ReceiptTotal('الإجمالي', total, emphasis: true),
      if (isCredit)
        ReceiptTotal('المدفوع', paid, section: ReceiptSection.payment),
      if (isCredit && total - paid > 0)
        ReceiptTotal('المتبقي', total - paid, section: ReceiptSection.payment),
    ];
    final settled = isAnonymous ? null : cardDebtPayment;
    if (settled != null) {
      const sec = ReceiptSection.accountBalance;
      final visitPaid = isCredit ? paid : total;
      final visitRemaining = isCredit && total - paid > 0 ? total - paid : 0;
      totals
        ..add(ReceiptTotal('دين سابق', settled.beforeFils, section: sec))
        ..add(
          ReceiptTotal('تسديد من الدين السابق', settled.paidFils, section: sec),
        )
        ..add(
          ReceiptTotal('المستلم', visitPaid + settled.paidFils, section: sec),
        )
        ..add(
          ReceiptTotal(
            'رصيد الحساب الآن',
            // من أرقام الإيصال نفسه لا من الرصيد الحي: إعادة طباعة إيصال قديم
            // بعد ديون لاحقة تُبقي الرصيد كما كان عند البيع.
            settled.beforeFils - settled.paidFils + visitRemaining,
            section: sec,
          ),
        );
    } else if (!isAnonymous && accountBalanceFils != null) {
      final thisRemaining = isCredit && total - paid > 0 ? total - paid : 0;
      final prior = accountBalanceFils - thisRemaining;
      if (prior > 500) {
        totals
          ..add(
            ReceiptTotal(
              'دين سابق',
              prior,
              section: ReceiptSection.accountBalance,
            ),
          )
          ..add(
            ReceiptTotal(
              'رصيد الحساب الآن',
              accountBalanceFils,
              section: ReceiptSection.accountBalance,
            ),
          );
      }
    }

    final status = invoice.isReturned
        ? 'مرتجع'
        : switch (invoice.type) {
            InvoiceType.cash => 'نقدي',
            InvoiceType.credit => 'آجل',
            InvoiceType.installment => 'أقساط',
            InvoiceType.delivery => 'توصيل',
            _ => null,
          };

    final cashier = invoice.createdByUserName?.trim() ?? '';
    // بطاقة غيار بلا زيت (فلتر أو هيدروليك أو خدمة): العنوان بمحتواها.
    final workLabel = kind == ReceiptKind.oilChange && order != null
        ? oilCardWorkLabel(order)
        : null;
    final workTitle = workLabel == null || workLabel == 'غيار زيت'
        ? null
        : 'إيصال $workLabel';
    return ReceiptDocument(
      kind: kind,
      titleOverride: workTitle,
      date: invoice.date,
      number: invoice.id == null ? null : '${invoice.id}',
      status: status,
      fields: [
        ...fields,
        if (cashier.isNotEmpty &&
            cashier != OilChangeDirectSaleService.defaultActorLabel)
          ReceiptField('الكاشير', cashier, section: ReceiptSection.cashier),
      ],
      lines: lines,
      totals: totals,
      highlights: highlights,
      notes: notes,
      loyalty: loyalty,
      qrData: invoice.id == null
          ? null
          : InvoiceDeepLink.uriForInvoiceId(
              invoice.id!,
              globalId: invoice.globalId,
            ),
    );
  }

  /// إيصال استرجاع: الأصل، المواد، المبلغ المسترد بخط كبير، والتوقيع.
  /// رمزه للعرض فقط (مسحه لا يفتح استرجاعاً).
  static ReceiptDocument saleReturn(Invoice ret) {
    final meta = ReturnMeta.parse(ret.returnMeta);
    final df = DateFormat('yyyy/MM/dd');
    final customer = ret.customerName.trim();
    final fields = <ReceiptField>[
      if (meta.originalNumber != null)
        ReceiptField('الفاتورة الأصلية', '#${meta.originalNumber}', bold: true)
      else if (ret.originalInvoiceId != null)
        ReceiptField(
          'الفاتورة الأصلية',
          '#${ret.originalInvoiceId}',
          bold: true,
        ),
      if (meta.originalDate != null)
        ReceiptField('تاريخها', df.format(meta.originalDate!)),
      if (customer.isNotEmpty &&
          customer != 'زبون نقدي' &&
          customer != 'بيع مباشر' &&
          customer != OilChangeDirectSaleService.defaultActorLabel)
        ReceiptField('العميل', customer, section: ReceiptSection.customer),
      ReceiptField(
        'طريقة الإرجاع',
        meta.refundMethodAr ?? refundMethodAr(ret.type),
      ),
      if ((ret.returnReason ?? '').trim().isNotEmpty)
        ReceiptField('السبب', ret.returnReason!.trim()),
      if ((meta.actor ?? ret.createdByUserName ?? '').trim().isNotEmpty)
        ReceiptField(
          'المنفّذ',
          (meta.actor ?? ret.createdByUserName)!.trim(),
          section: ReceiptSection.cashier,
        ),
      if ((meta.approver ?? '').trim().isNotEmpty)
        ReceiptField('الموافِق', meta.approver!.trim()),
    ];
    final lines = [
      for (final it in ret.items)
        ReceiptLine(
          name: it.productName,
          quantity: it.enteredQtyResolved,
          unit: it.unitLabel,
          unitPriceFils: IqdMoney.toFils(it.price),
          totalFils: IqdMoney.toFils(it.total),
        ),
    ];
    final refund = IqdMoney.toFils(ret.total);
    return ReceiptDocument(
      kind: ReceiptKind.saleReturn,
      date: ret.date,
      number: ret.id == null ? null : '${ret.id}',
      status: 'مرتجع',
      fields: fields,
      lines: lines,
      totals: [ReceiptTotal('المبلغ المسترد', refund, emphasis: true)],
      notes: const [
        'تأكدت أن المواد سليمة وغير مفتوحة.',
        'توقيع الزبون: ____________________',
      ],
      qrData: ret.id == null
          ? null
          : InvoiceDeepLink.uriForInvoiceId(ret.id!, globalId: ret.globalId),
    );
  }

  /// طريقة إرجاع المبلغ حسب نوع الفاتورة الأصلية.
  static String refundMethodAr(InvoiceType t) => switch (t) {
    InvoiceType.credit => 'خصم من الدين (لا يُصرف نقداً)',
    InvoiceType.installment => 'خصم من التقسيط',
    _ => 'نقداً من الصندوق',
  };

  /// إيصال تسديد دين عميل.
  static ReceiptDocument debtPayment({
    required String customerName,
    required double amountApplied,
    required double debtBefore,
    required double debtAfter,
    required int paymentRowId,
    int? receiptInvoiceId,
    String? receiptInvoiceGlobalId,
    String? recordedBy,
    DateTime? date,
  }) {
    final by = recordedBy?.trim() ?? '';
    return ReceiptDocument(
      kind: ReceiptKind.debtPayment,
      date: date ?? DateTime.now(),
      number: '${receiptInvoiceId ?? paymentRowId}',
      fields: [
        ReceiptField('العميل', customerName.trim(), bold: true),
        if (by.isNotEmpty)
          ReceiptField('المستلم', by, section: ReceiptSection.cashier),
      ],
      totals: [
        ReceiptTotal('الدين قبل التسديد', IqdMoney.toFils(debtBefore)),
        ReceiptTotal(
          'المبلغ المسدَّد',
          IqdMoney.toFils(amountApplied),
          emphasis: true,
        ),
        ReceiptTotal('الدين المتبقي', IqdMoney.toFils(debtAfter)),
      ],
      highlights: [
        if (debtAfter <= 0.0005)
          const ReceiptHighlight('الحالة', 'تم تسديد الدين بالكامل'),
      ],
      qrData: receiptInvoiceId == null
          ? null
          : InvoiceDeepLink.uriForInvoiceId(
              receiptInvoiceId,
              globalId: receiptInvoiceGlobalId,
            ),
    );
  }

  /// سند صرف مصروف.
  static ReceiptDocument expense(ExpenseEntry e) {
    final desc = e.description.trim();
    return ReceiptDocument(
      kind: ReceiptKind.expense,
      date: e.occurredAt,
      number: '${e.id}',
      fields: [
        ReceiptField('البند', e.categoryName, bold: true),
        if (desc.isNotEmpty) ReceiptField('البيان', desc),
        if ((e.invoiceRef ?? '').trim().isNotEmpty)
          ReceiptField('رقم المرجع', e.invoiceRef!.trim()),
        if ((e.landlordOrProperty ?? '').trim().isNotEmpty)
          ReceiptField('الجهة', e.landlordOrProperty!.trim()),
        if (e.employeeName.trim().isNotEmpty)
          ReceiptField(
            'الموظف',
            e.employeeName.trim(),
            section: ReceiptSection.cashier,
          ),
      ],
      totals: [
        ReceiptTotal('المبلغ', IqdMoney.toFils(e.amount), emphasis: true),
      ],
      notes: const ['التوقيع: ....................'],
    );
  }

  /// إيصال تجريبي لكل نوع، للمعاينة في شاشة الطباعة دون بيانات حقيقية.
  static ReceiptDocument sample(ReceiptKind kind, {DateTime? now}) {
    now ??= DateTime.now();
    switch (kind) {
      case ReceiptKind.oilChange:
        return fromInvoice(
          Invoice(
            id: 1024,
            customerName: 'أحمد علي',
            date: now,
            type: InvoiceType.cash,
            items: [
              InvoiceItem(
                productName: 'غيار زيت — توتال 10W40',
                quantity: 1,
                price: 35000,
                total: 35000,
              ),
              InvoiceItem(
                productName: 'فلتر زيت',
                quantity: 1,
                price: 7000,
                total: 7000,
              ),
            ],
            discount: 0,
            tax: 0,
            total: 42000,
            advancePayment: 42000,
            createdByUserName: 'الكاشير',
          ),
          order: {
            'orderKind': ServiceOrderKinds.oilChange,
            'deviceSerial': 'بصرة 12345',
            'carModel': 'تويوتا كامري 2018',
            'odometerCurrent': '120500',
            'odometerNext': '125500',
            'oilType': 'توتال',
            'oilViscosity': '10W40',
            'oilLitersUsed': 4.5,
            'technicianName': 'علي',
            'customerPhone': '07700000000',
            'oilFiltersJson':
                '[{"code":"engine","name":"تويوتا أصلي","priceFils":7000000}]',
          },
          visitNumber: 7,
        );
      case ReceiptKind.carWash:
        return fromInvoice(
          Invoice(
            id: 1025,
            customerName: 'زبون',
            date: now,
            type: InvoiceType.cash,
            items: [
              InvoiceItem(
                productName: 'غسيل: داخلي وخارجي',
                quantity: 1,
                price: 10000,
                total: 10000,
              ),
            ],
            discount: 0,
            tax: 0,
            total: 10000,
            advancePayment: 10000,
          ),
          order: {
            'orderKind': ServiceOrderKinds.carWash,
            'deviceSerial': 'بصرة 54321',
            'deviceName': 'غسيل',
            'technicianName': 'كرار',
            'washOfferNote': 'غسلتان من 3 — الغسلة القادمة مجانية',
          },
        );
      case ReceiptKind.directSale:
      case ReceiptKind.sale:
        return fromInvoice(
          Invoice(
            id: 1026,
            customerName: 'محمد',
            date: now,
            type: InvoiceType.credit,
            items: [
              InvoiceItem(
                productName: 'زيت محرك 5W30 فل سنثتك',
                quantity: 4,
                price: 9000,
                total: 36000,
              ),
              InvoiceItem(
                productName: 'ماسحات',
                quantity: 2,
                price: 4000,
                total: 8000,
              ),
            ],
            discount: 1000,
            tax: 0,
            total: 43000,
            advancePayment: 20000,
            deliveryAddress: OilChangeDirectSaleService.sourceTag,
          ),
        );
      case ReceiptKind.saleReturn:
        return saleReturn(
          Invoice(
            id: 1031,
            customerName: 'محمد',
            date: now,
            type: InvoiceType.cash,
            items: [
              InvoiceItem(
                productName: 'زيت محرك 5W30 فل سنثتك',
                quantity: 1,
                price: 9000,
                total: 9000,
              ),
            ],
            discount: 0,
            tax: 0,
            total: 9000,
            advancePayment: 0,
            isReturned: true,
            originalInvoiceId: 1026,
            returnReason: 'الزبون اشترى لزوجة غير مناسبة',
            returnMeta: ReturnMeta(
              originalNumber: 1026,
              originalDate: now.subtract(const Duration(days: 2)),
              actor: 'الكاشير',
              approver: 'المالك',
              refundMethodAr: 'نقداً من الصندوق',
              intactConfirmedBy: 'الكاشير',
            ).encode(),
          ),
        );
      case ReceiptKind.debtPayment:
        return debtPayment(
          customerName: 'محمد',
          amountApplied: 20000,
          debtBefore: 23000,
          debtAfter: 3000,
          paymentRowId: 77,
          recordedBy: 'الكاشير',
          date: now,
        );
      case ReceiptKind.expense:
        return ReceiptDocument(
          kind: ReceiptKind.expense,
          date: now,
          number: '15',
          fields: const [
            ReceiptField('البند', 'كهرباء', bold: true),
            ReceiptField('البيان', 'اشتراك المولدة لشهر تشرين الثاني'),
          ],
          totals: const [ReceiptTotal('المبلغ', 60000 * 1000, emphasis: true)],
          notes: const ['التوقيع: ....................'],
        );
      case ReceiptKind.customerStatement:
        return ReceiptDocument(
          kind: ReceiptKind.customerStatement,
          date: now,
          fields: const [ReceiptField('العميل', 'محمد', bold: true)],
          lines: const [
            ReceiptLine(name: 'فاتورة #1026', totalFils: 23000 * 1000),
          ],
          totals: const [
            ReceiptTotal('الرصيد المطلوب الآن', 23000 * 1000, emphasis: true),
          ],
          notes: const ['المبالغ أمام الفواتير هي الباقي منها.'],
        );
      case ReceiptKind.supplierStatement:
        return ReceiptDocument(
          kind: ReceiptKind.supplierStatement,
          date: now,
          fields: const [
            ReceiptField('المورد', 'شركة الرافدين للزيوت', bold: true),
          ],
          lines: const [
            ReceiptLine(name: 'وصل #88', totalFils: 450000 * 1000),
            ReceiptLine(name: 'دفعة', totalFils: -200000 * 1000),
          ],
          totals: const [
            ReceiptTotal('الرصيد الآن', 250000 * 1000, emphasis: true),
          ],
          notes: const ['الموجب وصل علينا، والسالب دفعة أو مرتجع.'],
        );
    }
  }

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(1);

  static String _groupDigits(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return raw;
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
      b.write(digits[i]);
    }
    return b.toString();
  }
}
