// PR-1 (roadmap_phase2_execution_v1 §4) — حماية merge الفواتير.
//
// سياسة:
//   • الحقول المالية الإجمالية مجمدة (المحلي يفوز دائماً).
//   • advancePayment / advancePaymentFils = max(local, incoming) ⇒ تسديد لا يُمسح.
//     ⚠️ Caveat (spec §2.1): max() حماية تكتيكية. التسديدات المتزامنة على نفس
//        الفاتورة قد تُختزل في هذا العمود (لكنها محفوظة كاملةً في
//        customer_debt_payments — جدول immutable). الحل النهائي: PR-Ledger
//        يحوّل العمود إلى SUM(payments) مشتق.
//   • workShiftId / actorUserId / shiftOwnerUserId / createdByUserName:
//        enrichment فقط — تُملأ لو المحلي null/0/empty.
//   • الباقي (customerName, deliveryAddress, ...): LWW عادي عند فوز incoming.

/// أعمدة مالية إجمالية — محمية من LWW دائماً. لا يجب أن تُعدَّل بعد إصدار الفاتورة.
const Set<String> invoiceFinancialFrozenCols = {
  'total',
  'totalFils',
  'discount',
  'discountFils',
  'discountPercent',
  'tax',
  'taxFils',
  'loyaltyDiscount',
  'loyaltyDiscountFils',
  'loyaltyPointsRedeemed',
  'loyaltyPointsEarned',
  'isReturned',
  'originalInvoiceId',
  'type',
};

/// أعمدة advance — تطبَّق سياسة max(local, incoming) بدل LWW.
const Set<String> invoiceAdvanceMaxCols = {
  'advancePayment',
  'advancePaymentFils',
};

/// أعمدة enrichment — تُملأ من incoming فقط عندما المحلي null/0/empty.
const Set<String> invoiceEnrichmentCols = {
  'workShiftId',
  'actorUserId',
  'shiftOwnerUserId',
  'createdByUserName',
};

/// أعمدة لا تتغير أبداً من قبل merge.
const Set<String> invoiceImmutableKeyCols = {
  'id',
  'global_id',
};

/// نتيجة تطبيق سياسة merge.
class InvoiceMergeOutcome {
  const InvoiceMergeOutcome({required this.merged, required this.changed});

  /// الصف بعد دمج السياسات (جاهز للكتابة في DB).
  final Map<String, Object?> merged;

  /// هل النتيجة مختلفة عن [current]؟ يُستخدم لتجنب كتابات DB لا فائدة منها.
  final bool changed;
}

/// تطبيق سياسة merge الفواتير على صف محلي وصف وارد.
///
/// [current] — الصف المحلي الحالي.
/// [incoming] — الحقول الواردة من snapshot/queue (مُنقّاة من أعمدة غير محلية).
/// [incomingWins] — قرار LWW: هل incoming.updatedAt > current.updatedAt؟
/// [localCols] — أعمدة السكيما المحلية (تُستخدم لتجاهل الأعمدة الزائدة).
InvoiceMergeOutcome applyInvoiceMergePolicy({
  required Map<String, Object?> current,
  required Map<String, Object?> incoming,
  required bool incomingWins,
  required Set<String> localCols,
}) {
  final merged = Map<String, Object?>.from(current);

  // 1) max() على advancePayment* — يعمل دائماً مهما كان قرار LWW.
  for (final col in invoiceAdvanceMaxCols) {
    if (!localCols.contains(col)) continue;
    if (!incoming.containsKey(col)) continue;
    final localFils = _asDouble(current[col]);
    final incomingFils = _asDouble(incoming[col]);
    if (incomingFils > localFils) {
      merged[col] = incoming[col];
    }
  }

  // 2) Enrichment — تُملأ من incoming لو المحلي فارغ (يعمل دائماً).
  for (final col in invoiceEnrichmentCols) {
    if (!localCols.contains(col)) continue;
    if (!incoming.containsKey(col)) continue;
    final currentVal = current[col];
    final incomingVal = incoming[col];
    if (incomingVal == null) continue;
    final canFill = currentVal == null ||
        (currentVal is num && currentVal.toInt() == 0) ||
        (currentVal is String && currentVal.trim().isEmpty);
    if (canFill) {
      merged[col] = incomingVal;
    }
  }

  // 3) LWW عادي على الحقول الوصفية المتبقية — فقط عند فوز incoming.
  if (incomingWins) {
    for (final entry in incoming.entries) {
      final col = entry.key;
      if (!localCols.contains(col)) continue;
      if (invoiceImmutableKeyCols.contains(col)) continue;
      if (invoiceFinancialFrozenCols.contains(col)) continue;
      if (invoiceAdvanceMaxCols.contains(col)) continue;
      if (invoiceEnrichmentCols.contains(col)) continue;
      merged[col] = entry.value;
    }
  }

  // 4) حساب التغيير الفعلي (لتجنب كتابات DB لا فائدة منها).
  var changed = false;
  for (final entry in merged.entries) {
    if (current[entry.key] != entry.value) {
      changed = true;
      break;
    }
  }

  return InvoiceMergeOutcome(merged: merged, changed: changed);
}

double _asDouble(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

// ─── PR-5: invoice_items merge policy ────────────────────────────────────────
// كل بنود الفاتورة مجمدة (price, total, unitCost, quantity) لأنها تمثل
// لحظة البيع. التعديل المشروع بعدها يكون بفاتورة مرتجع منفصلة.

/// أعمدة بنود الفاتورة المالية المجمدة — لا يجوز LWW تغييرها.
const Set<String> invoiceItemFrozenCols = {
  'price',
  'priceFils',
  'total',
  'totalFils',
  'unitCost',
  'unitCostFils',
  'quantity',
};

/// أعمدة لا تتغير في invoice_items.
const Set<String> invoiceItemImmutableKeyCols = {
  'id',
  'global_id',
  'invoiceId',
  'invoice_global_id',
  'productId',
  'product_global_id',
};

/// تطبيق سياسة merge على صف من invoice_items.
/// LWW يعمل على [productName] فقط (display)، الباقي إما مجمد أو enrichment.
InvoiceMergeOutcome applyInvoiceItemMergePolicy({
  required Map<String, Object?> current,
  required Map<String, Object?> incoming,
  required bool incomingWins,
  required Set<String> localCols,
}) {
  final merged = Map<String, Object?>.from(current);

  if (incomingWins) {
    for (final entry in incoming.entries) {
      final col = entry.key;
      if (!localCols.contains(col)) continue;
      if (invoiceItemImmutableKeyCols.contains(col)) continue;
      if (invoiceItemFrozenCols.contains(col)) continue;
      merged[col] = entry.value;
    }
  }

  var changed = false;
  for (final entry in merged.entries) {
    if (current[entry.key] != entry.value) {
      changed = true;
      break;
    }
  }
  return InvoiceMergeOutcome(merged: merged, changed: changed);
}

// ─── PR-5: installment_plans merge policy ────────────────────────────────────
// نفس مبدأ الفاتورة:
//   • totalAmount/totalAmountFils مجمد (المخطط الأصلي محصّن).
//   • paidAmount/paidAmountFils = max(local, incoming) ⇒ لا يُمسح دفع.
//     ⚠️ Caveat §2.1 ينطبق هنا كذلك.
//   • numberOfInstallments مجمد.
//   • customerName/customerId: LWW عادي.

const Set<String> installmentPlanFrozenCols = {
  'totalAmount',
  'totalAmountFils',
  'numberOfInstallments',
  'invoiceId',
};

const Set<String> installmentPlanMaxCols = {
  'paidAmount',
  'paidAmountFils',
};

const Set<String> installmentPlanImmutableKeyCols = {
  'id',
  'global_id',
};

InvoiceMergeOutcome applyInstallmentPlanMergePolicy({
  required Map<String, Object?> current,
  required Map<String, Object?> incoming,
  required bool incomingWins,
  required Set<String> localCols,
}) {
  final merged = Map<String, Object?>.from(current);

  for (final col in installmentPlanMaxCols) {
    if (!localCols.contains(col)) continue;
    if (!incoming.containsKey(col)) continue;
    final localVal = _asDouble(current[col]);
    final incomingVal = _asDouble(incoming[col]);
    if (incomingVal > localVal) {
      merged[col] = incoming[col];
    }
  }

  if (incomingWins) {
    for (final entry in incoming.entries) {
      final col = entry.key;
      if (!localCols.contains(col)) continue;
      if (installmentPlanImmutableKeyCols.contains(col)) continue;
      if (installmentPlanFrozenCols.contains(col)) continue;
      if (installmentPlanMaxCols.contains(col)) continue;
      merged[col] = entry.value;
    }
  }

  var changed = false;
  for (final entry in merged.entries) {
    if (current[entry.key] != entry.value) {
      changed = true;
      break;
    }
  }
  return InvoiceMergeOutcome(merged: merged, changed: changed);
}

// ─── PR-5: installments (الأقساط الفردية) merge policy ───────────────────────
// خصائص خاصة:
//   • amount/amountFils/dueDate/planId مجمدة (الخطة الأصلية محصّنة).
//   • paid (Boolean) monotonic: paid_local || paid_incoming ⇒ مرة paid، تبقى paid.
//   • paidDate enrichment: يُملأ لو null.

const Set<String> installmentFrozenCols = {
  'amount',
  'amountFils',
  'dueDate',
  'planId',
};

const Set<String> installmentImmutableKeyCols = {
  'id',
  'global_id',
};

InvoiceMergeOutcome applyInstallmentMergePolicy({
  required Map<String, Object?> current,
  required Map<String, Object?> incoming,
  required bool incomingWins,
  required Set<String> localCols,
}) {
  final merged = Map<String, Object?>.from(current);

  // paid monotonic
  if (localCols.contains('paid') && incoming.containsKey('paid')) {
    final localPaid = _truthy(current['paid']);
    final incomingPaid = _truthy(incoming['paid']);
    merged['paid'] = (localPaid || incomingPaid) ? 1 : 0;
  }

  // paidDate enrichment
  if (localCols.contains('paidDate') && incoming.containsKey('paidDate')) {
    final currentDate = current['paidDate'];
    final incomingDate = incoming['paidDate'];
    if ((currentDate == null ||
            (currentDate is String && currentDate.trim().isEmpty)) &&
        incomingDate != null) {
      merged['paidDate'] = incomingDate;
    }
  }

  if (incomingWins) {
    for (final entry in incoming.entries) {
      final col = entry.key;
      if (!localCols.contains(col)) continue;
      if (installmentImmutableKeyCols.contains(col)) continue;
      if (installmentFrozenCols.contains(col)) continue;
      if (col == 'paid' || col == 'paidDate') continue; // عولجت أعلاه
      merged[col] = entry.value;
    }
  }

  var changed = false;
  for (final entry in merged.entries) {
    if (current[entry.key] != entry.value) {
      changed = true;
      break;
    }
  }
  return InvoiceMergeOutcome(merged: merged, changed: changed);
}

bool _truthy(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v.toInt() != 0;
  final s = v.toString().toLowerCase().trim();
  return s == '1' || s == 'true' || s == 'yes';
}
