part of 'database_helper.dart';

// ── خطط التقسيط والأقساط ─────────────────────────────────────────────────

extension DbInstallments on DatabaseHelper {
  Future<int> insertInstallmentPlan(InstallmentPlan plan) async {
    final db = await database;
    final planId = await db.insert('installment_plans', {
      'invoiceId': plan.invoiceId,
      'customerName': plan.customerName,
      'customerId': plan.customerId,
      'totalAmount': plan.totalAmount,
      'paidAmount': plan.paidAmount,
      'numberOfInstallments': plan.numberOfInstallments,
      'interestPct': plan.interestPct,
      'interestAmount': plan.interestAmount,
      'financedAtSale': plan.financedAtSale,
      'totalWithInterest': plan.totalWithInterest,
      'plannedMonths': plan.plannedMonths,
      'suggestedMonthly': plan.suggestedMonthly,
    });
    for (var inst in plan.installments) {
      inst.planId = planId;
      await db.insert('installments', {
        'planId': inst.planId,
        'dueDate': inst.dueDate.toIso8601String(),
        'amount': inst.amount,
        'paid': inst.paid ? 1 : 0,
        'paidDate': inst.paidDate?.toIso8601String(),
      });
    }
    return planId;
  }

  Future<InstallmentPlan?> getInstallmentPlanByInvoiceId(int invoiceId) async {
    final db = await database;
    final maps = await db.query(
      'installment_plans',
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return getInstallmentPlanById(maps.first['id'] as int);
  }

  Future<int> insertDefaultInstallmentPlanForInvoice({
    required int invoiceId,
    required String customerName,
    required int? customerId,
    required double totalAmount,
    required double paidAmount,
    required DateTime invoiceDate,
    double interestPct = 0,
    double interestAmount = 0,
    double financedAtSale = 0,
    double totalWithInterest = 0,
    int plannedMonths = 0,
    double suggestedMonthly = 0,
  }) async {
    final db = await database;
    final existing = await db.query(
      'installment_plans',
      columns: ['id'],
      where: 'invoiceId = ?',
      whereArgs: [invoiceId],
      limit: 1,
      orderBy: 'id DESC',
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }

    final nm = customerName.trim().isEmpty ? 'عميل' : customerName.trim();
    final remaining = totalAmount - paidAmount;
    if (remaining <= 1e-6) {
      final plan = InstallmentPlan(
        invoiceId: invoiceId,
        customerName: nm,
        customerId: customerId,
        totalAmount: totalAmount,
        paidAmount: paidAmount,
        numberOfInstallments: 0,
        installments: [],
        interestPct: interestPct,
        interestAmount: interestAmount,
        financedAtSale: financedAtSale,
        totalWithInterest: totalWithInterest,
        plannedMonths: plannedMonths,
        suggestedMonthly: suggestedMonthly,
      );
      return insertInstallmentPlan(plan);
    }

    final settings = await getInstallmentSettings();
    final n = settings.defaultInstallmentCount.clamp(1, 120);
    final invDay = DateTime(
      invoiceDate.year,
      invoiceDate.month,
      invoiceDate.day,
    );
    final anchorStart =
        settings.defaultFirstDueAnchor ==
            InstallmentSettingsData.anchorInvoiceDate
        ? invDay
        : DateTime.now();
    final plan = InstallmentPlan(
      invoiceId: invoiceId,
      customerName: nm,
      customerId: customerId,
      totalAmount: totalAmount,
      paidAmount: paidAmount,
      numberOfInstallments: n,
      installments: [],
      interestPct: interestPct,
      interestAmount: interestAmount,
      financedAtSale: financedAtSale,
      totalWithInterest: totalWithInterest,
      plannedMonths: plannedMonths,
      suggestedMonthly: suggestedMonthly,
    );
    plan.distributeInstallments(
      anchorStart,
      paymentIntervalMonths: settings.paymentIntervalMonths,
      useCalendarMonths: settings.useCalendarMonths,
    );
    return insertInstallmentPlan(plan);
  }

  /// مزامنة خطط ناقصة بعد أن تكون القاعدة جاهزة.
  Future<void> ensurePostOpenInstallmentLinkage() async {
    if (DatabaseHelper._didPostOpenInstallmentSync) return;
    DatabaseHelper._didPostOpenInstallmentSync = true;
    await syncMissingInstallmentPlansFromInvoices();
  }

  Future<int> syncMissingInstallmentPlansFromInvoices([Database? db]) async {
    final conn = db ?? await database;
    Future<int> syncForTypes(
      List<int> types, {
      required bool deliveryPartialOnly,
    }) async {
      final placeholders = List.filled(types.length, '?').join(',');
      final extra = deliveryPartialOnly
          ? 'AND (i.total - IFNULL(i.advancePayment, 0)) > 0.01'
          : '';
      final rows = await conn.rawQuery('''
SELECT i.id AS invoiceId, i.customerName, i.customerId, i.total AS totalAmount,
       i.advancePayment AS paidAmount, i.date,
       i.installmentInterestPct, i.installmentPlannedMonths, i.installmentFinancedAmount,
       i.installmentInterestAmount, i.installmentTotalWithInterest, i.installmentSuggestedMonthly
FROM invoices i
LEFT JOIN installment_plans p ON p.invoiceId = i.id
WHERE i.type IN ($placeholders)
  AND IFNULL(i.isReturned, 0) = 0
  AND p.id IS NULL
  $extra
''', types);
      var created = 0;
      for (final r in rows) {
        final id = r['invoiceId'] as int;
        final date = DateTime.parse(r['date'] as String);
        await insertDefaultInstallmentPlanForInvoice(
          invoiceId: id,
          customerName: (r['customerName'] as String?) ?? '',
          customerId: r['customerId'] as int?,
          totalAmount: (r['totalAmount'] as num).toDouble(),
          paidAmount: (r['paidAmount'] as num).toDouble(),
          invoiceDate: date,
          interestPct: (r['installmentInterestPct'] as num?)?.toDouble() ?? 0,
          interestAmount:
              (r['installmentInterestAmount'] as num?)?.toDouble() ?? 0,
          financedAtSale:
              (r['installmentFinancedAmount'] as num?)?.toDouble() ?? 0,
          totalWithInterest:
              (r['installmentTotalWithInterest'] as num?)?.toDouble() ?? 0,
          plannedMonths:
              (r['installmentPlannedMonths'] as num?)?.toInt() ?? 0,
          suggestedMonthly:
              (r['installmentSuggestedMonthly'] as num?)?.toDouble() ?? 0,
        );
        created++;
      }
      return created;
    }

    var total = 0;
    total += await syncForTypes([
      InvoiceType.installment.index,
    ], deliveryPartialOnly: false);
    total += await syncForTypes([
      InvoiceType.delivery.index,
    ], deliveryPartialOnly: true);
    return total;
  }

  Future<bool> replaceInstallmentPlanSchedule(InstallmentPlan plan) async {
    final id = plan.id;
    if (id == null) return false;
    final db = await database;
    return db.transaction<bool>((txn) async {
      final paidCount = Sqflite.firstIntValue(
        await txn.rawQuery(
          'SELECT COUNT(*) FROM installments WHERE planId = ? AND paid = 1',
          [id],
        ),
      );
      if (paidCount != null && paidCount > 0) return false;

      await txn.delete('installments', where: 'planId = ?', whereArgs: [id]);
      await txn.update(
        'installment_plans',
        {
          'customerName': plan.customerName,
          'customerId': plan.customerId,
          'numberOfInstallments': plan.numberOfInstallments,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      for (final inst in plan.installments) {
        inst.planId = id;
        await txn.insert('installments', {
          'planId': inst.planId,
          'dueDate': inst.dueDate.toIso8601String(),
          'amount': inst.amount,
          'paid': inst.paid ? 1 : 0,
          'paidDate': inst.paidDate?.toIso8601String(),
        });
      }
      return true;
    });
  }

  /// خطط تقسيط مرتبطة بعميل مسجّل (بعد مزامنة الخطط من الفواتير إن لزم).
  Future<List<InstallmentPlan>> getInstallmentPlansForCustomerId(
    int customerId,
  ) async {
    final db = await database;
    await syncMissingInstallmentPlansFromInvoices(db);
    final maps = await db.query(
      'installment_plans',
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'id DESC',
    );
    final plans = <InstallmentPlan>[];
    for (final map in maps) {
      final planId = map['id'] as int;
      final instMaps = await db.query(
        'installments',
        where: 'planId = ?',
        whereArgs: [planId],
        orderBy: 'dueDate ASC',
      );
      final installments = instMaps
          .map(
            (im) => Installment(
              id: im['id'] as int?,
              planId: im['planId'] as int?,
              dueDate: DateTime.parse(im['dueDate'] as String),
              amount: (im['amount'] as num).toDouble(),
              paid: im['paid'] == 1,
              paidDate: im['paidDate'] != null
                  ? DateTime.parse(im['paidDate'] as String)
                  : null,
            ),
          )
          .toList();
      plans.add(
        InstallmentPlan(
          id: planId,
          invoiceId: map['invoiceId'] as int? ?? 0,
          customerName: map['customerName'] as String,
          customerId: map['customerId'] as int?,
          totalAmount: (map['totalAmount'] as num).toDouble(),
          paidAmount: (map['paidAmount'] as num).toDouble(),
          numberOfInstallments: map['numberOfInstallments'] as int,
          installments: installments,
          interestPct: (map['interestPct'] as num?)?.toDouble() ?? 0,
          interestAmount: (map['interestAmount'] as num?)?.toDouble() ?? 0,
          financedAtSale: (map['financedAtSale'] as num?)?.toDouble() ?? 0,
          totalWithInterest:
              (map['totalWithInterest'] as num?)?.toDouble() ?? 0,
          plannedMonths: (map['plannedMonths'] as num?)?.toInt() ?? 0,
          suggestedMonthly:
              (map['suggestedMonthly'] as num?)?.toDouble() ?? 0,
        ),
      );
    }
    return plans;
  }

  Future<List<InstallmentPlan>> getAllInstallmentPlans() async {
    final db = await database;
    final maps = await db.query('installment_plans');
    final plans = <InstallmentPlan>[];
    for (final map in maps) {
      final planId = map['id'] as int;
      final instMaps = await db.query(
        'installments',
        where: 'planId = ?',
        whereArgs: [planId],
        orderBy: 'dueDate ASC',
      );
      final installments = instMaps
          .map(
            (im) => Installment(
              id: im['id'] as int?,
              planId: im['planId'] as int?,
              dueDate: DateTime.parse(im['dueDate'] as String),
              amount: (im['amount'] as num).toDouble(),
              paid: im['paid'] == 1,
              paidDate: im['paidDate'] != null
                  ? DateTime.parse(im['paidDate'] as String)
                  : null,
            ),
          )
          .toList();
      plans.add(
        InstallmentPlan(
          id: planId,
          invoiceId: map['invoiceId'] as int? ?? 0,
          customerName: map['customerName'] as String,
          customerId: map['customerId'] as int?,
          totalAmount: (map['totalAmount'] as num).toDouble(),
          paidAmount: (map['paidAmount'] as num).toDouble(),
          numberOfInstallments: map['numberOfInstallments'] as int,
          installments: installments,
          interestPct: (map['interestPct'] as num?)?.toDouble() ?? 0,
          interestAmount: (map['interestAmount'] as num?)?.toDouble() ?? 0,
          financedAtSale: (map['financedAtSale'] as num?)?.toDouble() ?? 0,
          totalWithInterest:
              (map['totalWithInterest'] as num?)?.toDouble() ?? 0,
          plannedMonths: (map['plannedMonths'] as num?)?.toInt() ?? 0,
          suggestedMonthly:
              (map['suggestedMonthly'] as num?)?.toDouble() ?? 0,
        ),
      );
    }
    plans.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));
    return plans;
  }

  Future<InstallmentPlan?> getInstallmentPlanById(int planId) async {
    final db = await database;
    final maps = await db.query(
      'installment_plans',
      where: 'id = ?',
      whereArgs: [planId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final map = maps.first;
    final instMaps = await db.query(
      'installments',
      where: 'planId = ?',
      whereArgs: [planId],
      orderBy: 'dueDate ASC',
    );
    final installments = instMaps
        .map(
          (im) => Installment(
            id: im['id'] as int?,
            planId: im['planId'] as int?,
            dueDate: DateTime.parse(im['dueDate'] as String),
            amount: (im['amount'] as num).toDouble(),
            paid: im['paid'] == 1,
            paidDate: im['paidDate'] != null
                ? DateTime.parse(im['paidDate'] as String)
                : null,
          ),
        )
        .toList();
    return InstallmentPlan(
      id: map['id'] as int,
      invoiceId: map['invoiceId'] as int? ?? 0,
      customerName: map['customerName'] as String,
      customerId: map['customerId'] as int?,
      totalAmount: (map['totalAmount'] as num).toDouble(),
      paidAmount: (map['paidAmount'] as num).toDouble(),
      numberOfInstallments: map['numberOfInstallments'] as int,
      installments: installments,
      interestPct: (map['interestPct'] as num?)?.toDouble() ?? 0,
      interestAmount: (map['interestAmount'] as num?)?.toDouble() ?? 0,
      financedAtSale: (map['financedAtSale'] as num?)?.toDouble() ?? 0,
      totalWithInterest: (map['totalWithInterest'] as num?)?.toDouble() ?? 0,
      plannedMonths: (map['plannedMonths'] as num?)?.toInt() ?? 0,
      suggestedMonthly: (map['suggestedMonthly'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<void> applyInstallmentAdjustmentAfterReturn({
    required int originalInvoiceId,
    required double returnDocumentTotal,
  }) async {
    if (returnDocumentTotal <= 0) return;
    final db = await database;
    final rows = await db.query(
      'installment_plans',
      where: 'invoiceId = ?',
      whereArgs: [originalInvoiceId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final planId = rows.first['id'] as int;
    final totalAmount = (rows.first['totalAmount'] as num).toDouble();
    var newTotal = totalAmount - returnDocumentTotal;
    if (newTotal < 0) newTotal = 0;
    final rowInv = rows.first['invoiceId'] as int?;
    final invId = (rowInv != null && rowInv > 0) ? rowInv : originalInvoiceId;

    await db.transaction((txn) async {
      await txn.update(
        'installment_plans',
        {'totalAmount': newTotal},
        where: 'id = ?',
        whereArgs: [planId],
      );
      await _setPlanPaidAmountCombined(
        txn,
        planId: planId,
        invoiceId: invId > 0 ? invId : null,
      );
    });
  }

  /// كميات حالية في المخزون لمجموعة منتجات.
  Future<Map<int, double>> getProductQtyMap(Set<int> productIds) async {
    if (productIds.isEmpty) return {};
    final db = await database;
    final ids = productIds.toList();
    final ph = List.filled(ids.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT id, qty FROM products WHERE id IN ($ph)',
      ids,
    );
    return {
      for (final r in rows) r['id'] as int: (r['qty'] as num).toDouble(),
    };
  }

  Future<List<Installment>> getInstallmentsForPlan(int planId) async {
    final db = await database;
    final maps = await db.query(
      'installments',
      where: 'planId = ?',
      whereArgs: [planId],
      orderBy: 'dueDate',
    );
    return maps
        .map(
          (im) => Installment(
            id: im['id'] as int?,
            planId: im['planId'] as int?,
            dueDate: DateTime.parse(im['dueDate'] as String),
            amount: (im['amount'] as num).toDouble(),
            paid: im['paid'] == 1,
            paidDate: im['paidDate'] != null
                ? DateTime.parse(im['paidDate'] as String)
                : null,
          ),
        )
        .toList();
  }

  /// تسديد قسط كامل — فاتورة سند + الصندوق.
  Future<RecordInstallmentPaymentResult> recordInstallmentPayment(
    int installmentId,
    double paidAmount,
  ) async {
    final db = await database;
    return db.transaction<RecordInstallmentPaymentResult>((txn) async {
      final instRows = await txn.query(
        'installments',
        where: 'id = ?',
        whereArgs: [installmentId],
        limit: 1,
      );
      if (instRows.isEmpty) {
        return const RecordInstallmentPaymentResult(success: false);
      }
      final ir = instRows.first;
      if (ir['paid'] == 1) {
        return const RecordInstallmentPaymentResult(success: false);
      }
      final due = (ir['amount'] as num).toDouble();
      final planId = ir['planId'] as int;
      final toPay = paidAmount > 0 ? paidAmount : due;
      if (toPay + 1e-6 < due) {
        return const RecordInstallmentPaymentResult(success: false);
      }
      final applied = toPay > due ? due : toPay;

      final plans = await txn.query(
        'installment_plans',
        where: 'id = ?',
        whereArgs: [planId],
        limit: 1,
      );
      final customerName = plans.isNotEmpty
          ? (plans.first['customerName']?.toString() ?? '')
          : '';
      final invoiceRef = plans.isNotEmpty
          ? plans.first['invoiceId'] as int?
          : null;
      final customerId = plans.isNotEmpty
          ? plans.first['customerId'] as int?
          : null;

      final loyaltySettings = await _readLoyaltySettings(txn);
      var meta = 'خطة تقسيط #$planId';
      if (invoiceRef != null && invoiceRef > 0) {
        meta = '$meta — فاتورة أصلية #$invoiceRef';
      }
      if (meta.length > 900) meta = meta.substring(0, 900);

      final receiptInv = Invoice(
        customerName: customerName.isEmpty ? 'عميل' : customerName,
        date: DateTime.now(),
        type: InvoiceType.installmentCollection,
        items: [
          InvoiceItem(
            productName: 'تسديد قسط — خطة #$planId',
            quantity: 1,
            price: applied,
            total: applied,
            productId: null,
          ),
        ],
        discount: 0,
        tax: 0,
        advancePayment: 0,
        total: applied,
        isReturned: false,
        customerId: customerId,
        deliveryAddress: meta,
      );
      final receiptId = await _insertInvoiceInTransaction(
        txn,
        receiptInv,
        loyaltySettings,
        enforceStockNonZero: false,
      );

      await txn.update(
        'installments',
        {'paid': 1, 'paidDate': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [installmentId],
      );

      await _setPlanPaidAmountCombined(
        txn,
        planId: planId,
        invoiceId: invoiceRef,
      );

      return RecordInstallmentPaymentResult(
        success: true,
        receiptInvoiceId: receiptId,
      );
    });
  }

  Future<List<Installment>> getInstallmentsDueOn(DateTime date) async {
    final db = await database;
    final startOfDay = DateTime(
      date.year,
      date.month,
      date.day,
    ).toIso8601String();
    final endOfDay = DateTime(
      date.year,
      date.month,
      date.day,
      23,
      59,
      59,
    ).toIso8601String();
    final maps = await db.query(
      'installments',
      where: 'dueDate BETWEEN ? AND ? AND paid = 0',
      whereArgs: [startOfDay, endOfDay],
    );
    return maps
        .map(
          (im) => Installment(
            id: im['id'] as int?,
            planId: im['planId'] as int?,
            dueDate: DateTime.parse(im['dueDate'] as String),
            amount: (im['amount'] as num).toDouble(),
            paid: im['paid'] == 1,
            paidDate: im['paidDate'] != null
                ? DateTime.parse(im['paidDate'] as String)
                : null,
          ),
        )
        .toList();
  }
}
