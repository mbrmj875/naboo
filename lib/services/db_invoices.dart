part of 'database_helper.dart';

// ── الفواتير ──────────────────────────────────────────────────────────────

int? _tryParseLocalTenantId(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final asInt = int.tryParse(s);
  if (asInt != null && asInt > 0) return asInt;
  if (s.startsWith('local-')) {
    final tail = int.tryParse(s.substring(6));
    if (tail != null && tail > 0) return tail;
  }
  return null;
}

Future<int> _resolveActiveTenantIdForLocalDb(DatabaseExecutor ex) async {
  try {
    final rows = await ex.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['_system.active_tenant_id'],
      limit: 1,
    );
    final fromSettings = rows.isEmpty
        ? null
        : int.tryParse((rows.first['value'] ?? '').toString());
    if (fromSettings != null && fromSettings > 0) return fromSettings;
  } catch (_) {}
  try {
    final sid = TenantContext.instance.requireTenantId();
    final fromSession = _tryParseLocalTenantId(sid);
    if (fromSession != null && fromSession > 0) return fromSession;
  } catch (_) {}
  return 1;
}

extension DbInvoices on DatabaseHelper {
  int _toFils(double amount) {
    if (!amount.isFinite || amount.isNaN) return 0;
    return (amount * 1000).round();
  }

  double _fromFils(int fils) => fils / 1000.0;

  /// قراءة مبلغ مالي مع أولوية أعمدة ...Fils وfallback للأعمدة القديمة.
  double _readMoneyWithFilsFallback(
    Map<String, dynamic> row, {
    required String filsKey,
    required String legacyKey,
  }) {
    final legacy = (row[legacyKey] as num?)?.toDouble() ?? 0.0;
    final rawFils = row[filsKey];
    final fils = rawFils is num ? rawFils.toInt() : int.tryParse('$rawFils');
    if (fils == null) return legacy;
    if (fils == 0 && legacy.abs() > 1e-9) return legacy;
    return _fromFils(fils);
  }

  /// استعلام صفحات للفواتير **بدون** بنودها (items) لتفادي تحميل ضخم للذاكرة.
  ///
  /// - [tabIndex] يطابق تبويبات شاشة الفواتير: 0 الكل، 1 مدفوعة، 2 غير مدفوعة،
  ///   3 مرتجع، 4 تقسيط.
  /// - [sort] يدعم: date_desc | date_asc | amount_desc | amount_asc
  /// - [query] يبحث في: اسم العميل، رقم الفاتورة، هاتف العميل (إن وجد).
  Future<List<Invoice>> queryInvoicesPage({
    required int tabIndex,
    required String sort,
    required String query,
    required int limit,
    required int offset,
  }) async {
    final db = await database;
    final q = query.trim();
    final qLower = q.toLowerCase();
    final qDigits = q.replaceAll(RegExp(r'\D'), '');

    final where = <String>[];
    final args = <Object?>[];

    // تبويب
    switch (tabIndex) {
      case 1:
        // مدفوعة: نقدي + تحصيل دين/قسط + ليست مرتجعة
        where.add('i.isReturned = 0');
        where.add('i.type IN (?,?,?)');
        args.addAll([
          InvoiceType.cash.index,
          InvoiceType.debtCollection.index,
          InvoiceType.installmentCollection.index,
        ]);
        break;
      case 2:
        // غير مدفوعة: آجل + ليست مرتجعة
        where.add('i.isReturned = 0');
        where.add('i.type = ?');
        args.add(InvoiceType.credit.index);
        break;
      case 3:
        where.add('i.isReturned = 1');
        break;
      case 4:
        where.add('i.isReturned = 0');
        where.add('i.type = ?');
        args.add(InvoiceType.installment.index);
        break;
      default:
        break;
    }

    // بحث
    if (qLower.isNotEmpty) {
      final or = <String>[
        'LOWER(i.customerName) LIKE ?',
        "CAST(i.id AS TEXT) LIKE ?",
      ];
      args.addAll(['%$qLower%', '%$qLower%']);
      if (qDigits.length >= 2) {
        // phone قد يحتوي رموز/مسافات؛ هذا LIKE بسيط لكنه عملي.
        or.add('c.phone LIKE ?');
        args.add('%$qDigits%');
      }
      where.add('(${or.join(' OR ')})');
    }

    final orderBy = switch (sort) {
      'date_asc' => 'i.date ASC',
      'amount_desc' => 'i.total DESC',
      'amount_asc' => 'i.total ASC',
      _ => 'i.date DESC',
    };

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final rows = await db.rawQuery('''
      SELECT
        i.*,
        c.phone AS customerPhone
      FROM invoices i
      LEFT JOIN customers c ON c.id = i.customerId
      $whereSql
      ORDER BY $orderBy
      LIMIT ? OFFSET ?
    ''', [...args, limit, offset]);

    return rows.whereType<Map<String, dynamic>>().map((invoiceMap) {
      return Invoice(
        id: invoiceMap['id'] as int?,
        customerName: invoiceMap['customerName'] as String? ?? '',
        date: DateTime.tryParse((invoiceMap['date'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        type: invoiceTypeFromDb(invoiceMap['type']),
        items: const <InvoiceItem>[],
        discount: _readMoneyWithFilsFallback(
          invoiceMap,
          filsKey: 'discountFils',
          legacyKey: 'discount',
        ),
        tax: _readMoneyWithFilsFallback(
          invoiceMap,
          filsKey: 'taxFils',
          legacyKey: 'tax',
        ),
        advancePayment: _readMoneyWithFilsFallback(
          invoiceMap,
          filsKey: 'advancePaymentFils',
          legacyKey: 'advancePayment',
        ),
        total: _readMoneyWithFilsFallback(
          invoiceMap,
          filsKey: 'totalFils',
          legacyKey: 'total',
        ),
        isReturned: invoiceMap['isReturned'] == 1,
        originalInvoiceId: invoiceMap['originalInvoiceId'] as int?,
        deliveryAddress: invoiceMap['deliveryAddress'] as String?,
        createdByUserName: invoiceMap['createdByUserName'] as String?,
        discountPercent:
            (invoiceMap['discountPercent'] as num?)?.toDouble() ?? 0,
        workShiftId: invoiceMap['workShiftId'] as int?,
        customerId: invoiceMap['customerId'] as int?,
        loyaltyDiscount:
            (invoiceMap['loyaltyDiscount'] as num?)?.toDouble() ?? 0,
        loyaltyPointsRedeemed:
            (invoiceMap['loyaltyPointsRedeemed'] as num?)?.toInt() ?? 0,
        loyaltyPointsEarned:
            (invoiceMap['loyaltyPointsEarned'] as num?)?.toInt() ?? 0,
        installmentInterestPct:
            (invoiceMap['installmentInterestPct'] as num?)?.toDouble() ?? 0,
        installmentPlannedMonths:
            (invoiceMap['installmentPlannedMonths'] as num?)?.toInt() ?? 0,
        installmentFinancedAmount:
            (invoiceMap['installmentFinancedAmount'] as num?)?.toDouble() ?? 0,
        installmentInterestAmount:
            (invoiceMap['installmentInterestAmount'] as num?)?.toDouble() ?? 0,
        installmentTotalWithInterest:
            (invoiceMap['installmentTotalWithInterest'] as num?)?.toDouble() ??
                0,
        installmentSuggestedMonthly:
            (invoiceMap['installmentSuggestedMonthly'] as num?)?.toDouble() ??
                0,
      );
    }).toList();
  }

  Future<int> countInvoicesForPageQuery({
    required int tabIndex,
    required String query,
  }) async {
    final db = await database;
    final q = query.trim();
    final qLower = q.toLowerCase();
    final qDigits = q.replaceAll(RegExp(r'\D'), '');

    final where = <String>[];
    final args = <Object?>[];

    switch (tabIndex) {
      case 1:
        where.add('i.isReturned = 0');
        where.add('i.type IN (?,?,?)');
        args.addAll([
          InvoiceType.cash.index,
          InvoiceType.debtCollection.index,
          InvoiceType.installmentCollection.index,
        ]);
        break;
      case 2:
        where.add('i.isReturned = 0');
        where.add('i.type = ?');
        args.add(InvoiceType.credit.index);
        break;
      case 3:
        where.add('i.isReturned = 1');
        break;
      case 4:
        where.add('i.isReturned = 0');
        where.add('i.type = ?');
        args.add(InvoiceType.installment.index);
        break;
      default:
        break;
    }

    if (qLower.isNotEmpty) {
      final or = <String>[
        'LOWER(i.customerName) LIKE ?',
        "CAST(i.id AS TEXT) LIKE ?",
      ];
      args.addAll(['%$qLower%', '%$qLower%']);
      if (qDigits.length >= 2) {
        or.add('c.phone LIKE ?');
        args.add('%$qDigits%');
      }
      where.add('(${or.join(' OR ')})');
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS c
      FROM invoices i
      LEFT JOIN customers c ON c.id = i.customerId
      $whereSql
    ''', args);
    if (rows.isEmpty) return 0;
    final n = (rows.first['c'] as num?)?.toInt() ?? 0;
    return n;
  }

  /// إدراج فاتورة داخل معاملة مفتوحة (بيع، أو سند قبض دين/قسط).
  Future<int> _insertInvoiceInTransaction(
    Transaction txn,
    Invoice invoice,
    LoyaltySettingsData loyaltySettings,
    {required bool enforceStockNonZero}
  ) async {
    _validateInvoiceForSave(invoice);
    final tenantId = await _resolveActiveTenantIdForLocalDb(txn);
    final actor = (invoice.createdByUserName ?? '').trim();
    final actorLabel = actor.isEmpty ? 'غير معروف' : actor;
    final serviceReceipt =
        invoice.type == InvoiceType.debtCollection ||
        invoice.type == InvoiceType.installmentCollection ||
        invoice.type == InvoiceType.supplierPayment;

    final loyaltyActive =
        loyaltySettings.enabled &&
        invoice.customerId != null &&
        !invoice.isReturned &&
        !serviceReceipt;
    final loyaltyDiscount = loyaltyActive ? invoice.loyaltyDiscount : 0.0;
    final loyaltyRedeem = loyaltyActive ? invoice.loyaltyPointsRedeemed : 0;

    final wsRows = await txn.query(
      'work_shifts',
      columns: ['id'],
      where: 'closedAt IS NULL',
      limit: 1,
    );
    final int? shiftId = wsRows.isNotEmpty
        ? wsRows.first['id'] as int
        : invoice.workShiftId;

    final id = await txn.insert('invoices', {
      'tenantId': tenantId,
      'customerName': invoice.customerName,
      'date': invoice.date.toIso8601String(),
      'type': invoice.type.index,
      'discount': invoice.discount,
      'discountFils': _toFils(invoice.discount),
      'tax': invoice.tax,
      'taxFils': _toFils(invoice.tax),
      'advancePayment': invoice.advancePayment,
      'advancePaymentFils': _toFils(invoice.advancePayment),
      'total': invoice.total,
      'totalFils': _toFils(invoice.total),
      'isReturned': invoice.isReturned ? 1 : 0,
      'originalInvoiceId': invoice.originalInvoiceId,
      'deliveryAddress': invoice.deliveryAddress,
      'createdByUserName': invoice.createdByUserName,
      'discountPercent': invoice.discountPercent,
      'workShiftId': shiftId,
      'customerId': invoice.customerId,
      'loyaltyDiscount': loyaltyDiscount,
      'loyaltyDiscountFils': _toFils(loyaltyDiscount),
      'loyaltyPointsRedeemed': loyaltyRedeem,
      'loyaltyPointsEarned': 0,
      'installmentInterestPct': invoice.installmentInterestPct,
      'installmentPlannedMonths': invoice.installmentPlannedMonths,
      'installmentFinancedAmount': invoice.installmentFinancedAmount,
      'installmentInterestAmount': invoice.installmentInterestAmount,
      'installmentTotalWithInterest': invoice.installmentTotalWithInterest,
      'installmentSuggestedMonthly': invoice.installmentSuggestedMonthly,
    });
    await _insertActivityLogInTxn(
      txn,
      type: invoice.isReturned ? 'invoice_returned' : 'invoice_created',
      refTable: 'invoices',
      refId: id,
      title: invoice.isReturned ? 'تسجيل مرتجع فاتورة' : 'تسجيل فاتورة',
      details:
          'المنفّذ: $actorLabel — العميل: ${invoice.customerName.isEmpty ? 'عميل' : invoice.customerName} — النوع: ${invoice.type.name}',
      amount: invoice.isReturned ? -invoice.total : invoice.total,
    );

    for (final item in invoice.items) {
      // تثبيت تكلفة الشراء لحظة البيع (Cost Stamping) — السلسلة:
      // 1) WAC من product_batches (المتوسط المرجّح للدفعات حتى تاريخ الفاتورة)
      // 2) products.buyPrice (آخر سعر شراء حالي)
      // 3) 0 (يُعلَّم كسطر بدون تكلفة في تقارير الجودة)
      double stampedUnitCost = 0.0;
      if (item.productId != null) {
        try {
          final wacRows = await txn.rawQuery(
            '''
            SELECT SUM(unitCost * qty) AS totalCost, SUM(qty) AS totalQty
            FROM product_batches
            WHERE productId = ? AND createdAt <= ?
            ''',
            [item.productId, invoice.date.toIso8601String()],
          );
          if (wacRows.isNotEmpty) {
            final tc = (wacRows.first['totalCost'] as num?)?.toDouble() ?? 0.0;
            final tq = (wacRows.first['totalQty'] as num?)?.toDouble() ?? 0.0;
            if (tq > 0) stampedUnitCost = tc / tq;
          }
        } catch (_) {}
        if (stampedUnitCost <= 0) {
          try {
            final p = await txn.query(
              'products',
              columns: ['buyPrice'],
              where: 'id = ?',
              whereArgs: [item.productId],
              limit: 1,
            );
            if (p.isNotEmpty) {
              stampedUnitCost =
                  (p.first['buyPrice'] as num?)?.toDouble() ?? 0.0;
            }
          } catch (_) {}
        }
      }
      final base = item.baseQtyResolved;
      await txn.insert('invoice_items', {
        'invoiceId': id,
        'productName': item.productName,
        'quantity': base,
        'price': item.price,
        'priceFils': _toFils(item.price),
        'total': item.total,
        'totalFils': _toFils(item.total),
        'productId': item.productId,
        'unitCost': stampedUnitCost,
        'unitCostFils': _toFils(stampedUnitCost),
        'unitVariantId': item.unitVariantId,
        'unitLabel': item.unitLabel,
        'unitFactor': item.unitFactor <= 0 ? 1.0 : item.unitFactor,
        'enteredQty': item.enteredQtyResolved,
        'baseQty': base,
        'productVariantId': item.productVariantId,
        'variantColorNameSnapshot': item.variantColorNameSnapshot,
        'variantSizeSnapshot': item.variantSizeSnapshot,
      });
    }

    if (!invoice.isReturned) {
      if (!serviceReceipt) {
        if (enforceStockNonZero) {
          // منع البيع عند مخزون 0 في الوضع المقيّد (طبقة الخدمة).
          for (final item in invoice.items) {
            final pid = item.productId;
            if (pid == null) continue;
            final rows = await txn.query(
              'products',
              columns: ['qty'],
              where: 'id = ?',
              whereArgs: [pid],
              limit: 1,
            );
            if (rows.isEmpty) continue;
            final q = (rows.first['qty'] as num?)?.toDouble() ?? 0.0;
            if (q <= 1e-12 && item.baseQtyResolved > 1e-12) {
              throw FormatException(
                'لا يمكن بيع «${item.productName}» لأن المخزون صفر في الوضع المقيّد.',
              );
            }
          }
        }
        for (final item in invoice.items) {
          final pvId = item.productVariantId;
          if (pvId != null) {
            // الملابس: لا نسمح بالبيع بالسالب حتى لو كان المنتج يسمح بالسالب.
            final allowNeg = false;
            final delta = item.baseQtyResolved;
            final q = delta.round();
            if ((delta - q).abs() > 1e-9) {
              throw const FormatException('كمية الملابس يجب أن تكون رقماً صحيحاً.');
            }
            final affected = await txn.rawUpdate(
              'UPDATE product_variants SET quantity = quantity - ? '
              'WHERE id = ? AND deleted_at IS NULL AND quantity >= ?',
              [q, pvId, q],
            );
            if (affected < 1 && !allowNeg) {
              throw const FormatException('لا توجد كمية متوفرة لهذا المقاس/اللون.');
            }

            // Sync mutation for this variant (best-effort).
            try {
              final vRows = await txn.query(
                'product_variants',
                columns: [
                  'global_id',
                  'productId',
                  'colorId',
                  'size',
                  'quantity',
                  'barcode',
                  'sku',
                ],
                where: 'id = ?',
                whereArgs: [pvId],
                limit: 1,
              );
              if (vRows.isNotEmpty) {
                final v = vRows.first;
                final vGlobal = (v['global_id'] ?? '').toString().trim();
                final productId = (v['productId'] as num?)?.toInt() ?? 0;
                final colorId = (v['colorId'] as num?)?.toInt() ?? 0;
                if (vGlobal.isNotEmpty && productId > 0 && colorId > 0) {
                  final pRows = await txn.query(
                    'products',
                    columns: ['global_id'],
                    where: 'id = ?',
                    whereArgs: [productId],
                    limit: 1,
                  );
                  final cRows = await txn.query(
                    'product_colors',
                    columns: ['global_id'],
                    where: 'id = ?',
                    whereArgs: [colorId],
                    limit: 1,
                  );
                  final pGlobal = pRows.isEmpty
                      ? ''
                      : (pRows.first['global_id'] ?? '').toString().trim();
                  final cGlobal = cRows.isEmpty
                      ? ''
                      : (cRows.first['global_id'] ?? '').toString().trim();
                  if (pGlobal.isNotEmpty && cGlobal.isNotEmpty) {
                    final nowIso = DateTime.now().toUtc().toIso8601String();
                    await SyncQueueService.instance.enqueueMutation(
                      txn,
                      entityType: 'product_variant',
                      globalId: vGlobal,
                      operation: 'UPDATE',
                      payload: {
                        'id': vGlobal,
                        'product_id': pGlobal,
                        'color_id': cGlobal,
                        'size': (v['size'] ?? '').toString(),
                        'quantity': (v['quantity'] as num?)?.toInt() ?? 0,
                        'barcode': (v['barcode'] ?? '').toString(),
                        'sku': (v['sku'] ?? '').toString(),
                        'updated_at': nowIso,
                      },
                    );
                  }
                }
              }
            } catch (_) {}

            continue;
          }
          final pid = item.productId;
          if (pid == null) continue;
          await txn.rawUpdate(
            'UPDATE products SET qty = qty - ? WHERE id = ?',
            [item.baseQtyResolved, pid],
          );
        }
      }

      if (invoice.type == InvoiceType.supplierPayment) {
        if (invoice.supplierPaymentAffectsCash && invoice.total > 1e-9) {
          final cust = invoice.customerName.isEmpty
              ? 'مورد'
              : invoice.customerName;
          await txn.insert('cash_ledger', {
            'tenantId': tenantId,
            'transactionType': 'supplier_payment',
            'amount': -invoice.total,
            'amountFils': _toFils(-invoice.total),
            'description': 'دفع مورد — $cust (سند #${id.toString()})',
            'invoiceId': id,
            'workShiftId': shiftId,
            'createdAt': DateTime.now().toIso8601String(),
          });
          await _insertActivityLogInTxn(
            txn,
            type: 'cash_entry_created',
            refTable: 'cash_ledger',
            refId: id,
            title: 'قيد صندوق: دفع مورد',
            details: 'المنفّذ: $actorLabel — الفاتورة #$id — $cust',
            amount: -invoice.total,
          );
        }
      } else {
        final cashAmount = _cashAmountForInvoice(invoice);
        if (cashAmount > 0) {
          final String typeLabel;
          if (invoice.type == InvoiceType.cash) {
            typeLabel = 'sale_cash';
          } else if (invoice.type == InvoiceType.debtCollection) {
            typeLabel = 'debt_collection';
          } else if (invoice.type == InvoiceType.installmentCollection) {
            typeLabel = 'installment_collection';
          } else {
            typeLabel = invoice.advancePayment > 0
                ? 'sale_advance'
                : 'sale_other';
          }
          final cust = invoice.customerName.isEmpty
              ? 'عميل'
              : invoice.customerName;
          final desc = serviceReceipt
              ? (invoice.type == InvoiceType.debtCollection
                    ? 'سند تحصيل دين #$id — $cust'
                    : 'سند تسديد قسط #$id — $cust')
              : 'فاتورة بيع #${id.toString()} — $cust';
          await txn.insert('cash_ledger', {
            'tenantId': tenantId,
            'transactionType': typeLabel,
            'amount': cashAmount,
            'amountFils': _toFils(cashAmount),
            'description': desc,
            'invoiceId': id,
            'workShiftId': shiftId,
            'createdAt': DateTime.now().toIso8601String(),
          });
          await _insertActivityLogInTxn(
            txn,
            type: 'cash_entry_created',
            refTable: 'cash_ledger',
            refId: id,
            title: 'قيد صندوق مرتبط بفاتورة',
            details:
                'المنفّذ: $actorLabel — الفاتورة #$id — نوع القيد: $typeLabel',
            amount: cashAmount,
          );
        }
      }
    } else {
      if (!serviceReceipt) {
        for (final item in invoice.items) {
          final pid = item.productId;
          if (pid == null) continue;
          await txn.rawUpdate(
            'UPDATE products SET qty = qty + ? WHERE id = ?',
            [item.baseQtyResolved, pid],
          );
        }
      }
      final refund = _cashAmountForInvoice(invoice);
      if (refund > 0) {
        await txn.insert('cash_ledger', {
          'tenantId': tenantId,
          'transactionType': 'sale_return',
          'amount': -refund,
          'amountFils': _toFils(-refund),
          'description':
              'مرتجع فاتورة #${id.toString()}${invoice.originalInvoiceId != null ? ' (أصل #${invoice.originalInvoiceId})' : ''} — ${invoice.customerName.isEmpty ? 'عميل' : invoice.customerName}',
          'invoiceId': id,
          'workShiftId': shiftId,
          'createdAt': DateTime.now().toIso8601String(),
        });
        await _insertActivityLogInTxn(
          txn,
          type: 'cash_entry_created',
          refTable: 'cash_ledger',
          refId: id,
          title: 'قيد صندوق: مرتجع بيع',
          details: 'المنفّذ: $actorLabel — الفاتورة #$id',
          amount: -refund,
        );
      }
    }

    if (loyaltyActive) {
      await _applyLoyaltyForNewInvoice(
        txn,
        invoiceId: id,
        invoice: invoice,
        effectiveLoyaltyDiscount: loyaltyDiscount,
        effectiveLoyaltyRedeem: loyaltyRedeem,
        settings: loyaltySettings,
      );
    }

    return id;
  }

  Future<int> insertInvoiceWithPolicy(
    Invoice invoice, {
    required bool enforceStockNonZero,
  }) async {
    _validateInvoiceForSave(invoice);
    final db = await database;
    final loyaltySettings = await _readLoyaltySettings(db);
    final id = await db.transaction<int>(
      (txn) => _insertInvoiceInTransaction(
        txn,
        invoice,
        loyaltySettings,
        enforceStockNonZero: enforceStockNonZero,
      ),
    );
    CloudSyncService.instance.scheduleSyncSoon();
    return id;
  }

  void _validateInvoiceForSave(Invoice invoice) {
    const moneyTol = 0.05;

    bool isFiniteNum(double v) => v.isFinite && !v.isNaN;

    void ensureFinite(String label, double v) {
      if (!isFiniteNum(v)) {
        throw const FormatException('بيانات الفاتورة غير صالحة (قيمة رقمية غير منتهية).');
      }
      if (v < -moneyTol) {
        throw FormatException('لا يمكن أن يكون $label أقل من الصفر.');
      }
    }

    if (invoice.items.isEmpty) {
      throw const FormatException('لا يمكن حفظ فاتورة بدون بنود.');
    }

    ensureFinite('الخصم', invoice.discount);
    ensureFinite('الضريبة', invoice.tax);
    ensureFinite('الدفعة المقدمة', invoice.advancePayment);
    ensureFinite('إجمالي الفاتورة', invoice.total);

    if (!isFiniteNum(invoice.discountPercent) ||
        invoice.discountPercent < -moneyTol ||
        invoice.discountPercent > 100 + moneyTol) {
      throw const FormatException('نسبة الخصم يجب أن تكون بين 0% و100%.');
    }

    final serviceReceipt =
        invoice.type == InvoiceType.debtCollection ||
        invoice.type == InvoiceType.installmentCollection ||
        invoice.type == InvoiceType.supplierPayment;
    if (serviceReceipt && invoice.items.length != 1) {
      throw const FormatException(
        'سندات التحصيل/الدفع يجب أن تحتوي على بند واحد فقط.',
      );
    }

    var subtotal = 0.0;
    for (var i = 0; i < invoice.items.length; i++) {
      final item = invoice.items[i];
      final lineNo = i + 1;
      final enteredQty = item.enteredQtyResolved;
      final baseQty = item.baseQtyResolved;

      if (item.productName.trim().isEmpty) {
        throw FormatException('اسم المنتج في البند رقم $lineNo مطلوب.');
      }
      ensureFinite('سعر البند رقم $lineNo', item.price);
      ensureFinite('إجمالي البند رقم $lineNo', item.total);
      if (!isFiniteNum(enteredQty) || enteredQty <= 0) {
        throw FormatException('كمية البيع في البند رقم $lineNo يجب أن تكون أكبر من صفر.');
      }
      if (!isFiniteNum(baseQty) || baseQty <= 0) {
        throw FormatException('كمية المخزون الأساسية في البند رقم $lineNo غير صالحة.');
      }
      if (item.productId != null && item.productId! <= 0) {
        throw FormatException('معرّف المنتج في البند رقم $lineNo غير صالح.');
      }

      final expectedLine = item.price * enteredQty;
      if ((expectedLine - item.total).abs() > moneyTol) {
        throw FormatException(
          'إجمالي البند رقم $lineNo غير متطابق مع السعر × الكمية.',
        );
      }

      subtotal += item.total;
    }

    if (invoice.discount - subtotal > moneyTol) {
      throw const FormatException('قيمة الخصم لا يمكن أن تتجاوز مجموع البنود.');
    }

    final expectedTotal = subtotal - invoice.discount + invoice.tax;
    if ((expectedTotal - invoice.total).abs() > moneyTol) {
      throw const FormatException(
        'إجمالي الفاتورة غير متطابق مع مجموع البنود بعد الخصم والضريبة.',
      );
    }
    if (invoice.advancePayment - invoice.total > moneyTol) {
      throw const FormatException('الدفعة المقدمة لا يمكن أن تتجاوز إجمالي الفاتورة.');
    }
  }

  /// مبلغ نقدي يُحسب للفاتورة.
  double _cashAmountForInvoice(Invoice invoice) {
    switch (invoice.type) {
      case InvoiceType.cash:
        return invoice.total;
      case InvoiceType.credit:
      case InvoiceType.installment:
        return invoice.advancePayment > 0 ? invoice.advancePayment : 0;
      case InvoiceType.delivery:
        return invoice.total;
      case InvoiceType.debtCollection:
      case InvoiceType.installmentCollection:
        return invoice.total;
      case InvoiceType.supplierPayment:
        return 0;
    }
  }

  /// فاتورة واحدة مع بنودها.
  Future<Invoice?> getInvoiceById(int id) async {
    final db = await database;
    final maps = await db.query(
      'invoices',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final invoiceMap = maps.first;
    final items = await db.query(
      'invoice_items',
      where: 'invoiceId = ?',
      whereArgs: [id],
    );
    return Invoice(
      id: invoiceMap['id'] as int?,
      customerName: invoiceMap['customerName'] as String,
      date: DateTime.parse(invoiceMap['date'] as String),
      type: invoiceTypeFromDb(invoiceMap['type']),
      items: items.map((i) => InvoiceItem.fromMap(i)).toList(),
      discount: _readMoneyWithFilsFallback(
        invoiceMap,
        filsKey: 'discountFils',
        legacyKey: 'discount',
      ),
      tax: _readMoneyWithFilsFallback(
        invoiceMap,
        filsKey: 'taxFils',
        legacyKey: 'tax',
      ),
      advancePayment: _readMoneyWithFilsFallback(
        invoiceMap,
        filsKey: 'advancePaymentFils',
        legacyKey: 'advancePayment',
      ),
      total: _readMoneyWithFilsFallback(
        invoiceMap,
        filsKey: 'totalFils',
        legacyKey: 'total',
      ),
      isReturned: invoiceMap['isReturned'] == 1,
      originalInvoiceId: invoiceMap['originalInvoiceId'] as int?,
      deliveryAddress: invoiceMap['deliveryAddress'] as String?,
      createdByUserName: invoiceMap['createdByUserName'] as String?,
      discountPercent:
          (invoiceMap['discountPercent'] as num?)?.toDouble() ?? 0,
      workShiftId: invoiceMap['workShiftId'] as int?,
      customerId: invoiceMap['customerId'] as int?,
      loyaltyDiscount:
          (invoiceMap['loyaltyDiscount'] as num?)?.toDouble() ?? 0,
      loyaltyPointsRedeemed:
          (invoiceMap['loyaltyPointsRedeemed'] as num?)?.toInt() ?? 0,
      loyaltyPointsEarned:
          (invoiceMap['loyaltyPointsEarned'] as num?)?.toInt() ?? 0,
      installmentInterestPct:
          (invoiceMap['installmentInterestPct'] as num?)?.toDouble() ?? 0,
      installmentPlannedMonths:
          (invoiceMap['installmentPlannedMonths'] as num?)?.toInt() ?? 0,
      installmentFinancedAmount:
          (invoiceMap['installmentFinancedAmount'] as num?)?.toDouble() ?? 0,
      installmentInterestAmount:
          (invoiceMap['installmentInterestAmount'] as num?)?.toDouble() ?? 0,
      installmentTotalWithInterest:
          (invoiceMap['installmentTotalWithInterest'] as num?)?.toDouble() ??
          0,
      installmentSuggestedMonthly:
          (invoiceMap['installmentSuggestedMonthly'] as num?)?.toDouble() ??
          0,
    );
  }

  /// كل الفواتير (استعلام مجمّع لتفادي N+1).
  Future<List<Invoice>> getInvoices() async {
    final db = await database;
    final invoiceMaps = await db.query('invoices');
    if (invoiceMaps.isEmpty) return [];

    final ids = invoiceMaps.map((m) => m['id'] as int).toList();
    final itemsByInvoice = <int, List<Map<String, dynamic>>>{
      for (final id in ids) id: <Map<String, dynamic>>[],
    };

    const chunk = 400;
    for (var i = 0; i < ids.length; i += chunk) {
      final part = ids.sublist(i, min(i + chunk, ids.length));
      final ph = List.filled(part.length, '?').join(',');
      final rows = await db.rawQuery('''
        SELECT * FROM invoice_items
        WHERE invoiceId IN ($ph)
        ORDER BY invoiceId ASC, id ASC
        ''', part);
      for (final row in rows) {
        final iid = row['invoiceId'] as int;
        itemsByInvoice[iid]?.add(row);
      }
    }

    return invoiceMaps.map((invoiceMap) {
      final id = invoiceMap['id'] as int;
      final items = itemsByInvoice[id] ?? const <Map<String, dynamic>>[];
      return Invoice(
        id: invoiceMap['id'] as int?,
        customerName: invoiceMap['customerName'] as String,
        date: DateTime.parse(invoiceMap['date'] as String),
        type: invoiceTypeFromDb(invoiceMap['type']),
        items: items.map((i) => InvoiceItem.fromMap(i)).toList(),
        discount: _readMoneyWithFilsFallback(
          invoiceMap,
          filsKey: 'discountFils',
          legacyKey: 'discount',
        ),
        tax: _readMoneyWithFilsFallback(
          invoiceMap,
          filsKey: 'taxFils',
          legacyKey: 'tax',
        ),
        advancePayment: _readMoneyWithFilsFallback(
          invoiceMap,
          filsKey: 'advancePaymentFils',
          legacyKey: 'advancePayment',
        ),
        total: _readMoneyWithFilsFallback(
          invoiceMap,
          filsKey: 'totalFils',
          legacyKey: 'total',
        ),
        isReturned: invoiceMap['isReturned'] == 1,
        originalInvoiceId: invoiceMap['originalInvoiceId'] as int?,
        deliveryAddress: invoiceMap['deliveryAddress'] as String?,
        createdByUserName: invoiceMap['createdByUserName'] as String?,
        discountPercent:
            (invoiceMap['discountPercent'] as num?)?.toDouble() ?? 0,
        workShiftId: invoiceMap['workShiftId'] as int?,
        customerId: invoiceMap['customerId'] as int?,
        loyaltyDiscount:
            (invoiceMap['loyaltyDiscount'] as num?)?.toDouble() ?? 0,
        loyaltyPointsRedeemed:
            (invoiceMap['loyaltyPointsRedeemed'] as num?)?.toInt() ?? 0,
        loyaltyPointsEarned:
            (invoiceMap['loyaltyPointsEarned'] as num?)?.toInt() ?? 0,
        installmentInterestPct:
            (invoiceMap['installmentInterestPct'] as num?)?.toDouble() ?? 0,
        installmentPlannedMonths:
            (invoiceMap['installmentPlannedMonths'] as num?)?.toInt() ?? 0,
        installmentFinancedAmount:
            (invoiceMap['installmentFinancedAmount'] as num?)?.toDouble() ?? 0,
        installmentInterestAmount:
            (invoiceMap['installmentInterestAmount'] as num?)?.toDouble() ?? 0,
        installmentTotalWithInterest:
            (invoiceMap['installmentTotalWithInterest'] as num?)?.toDouble() ??
            0,
        installmentSuggestedMonthly:
            (invoiceMap['installmentSuggestedMonthly'] as num?)?.toDouble() ??
            0,
      );
    }).toList();
  }
}
