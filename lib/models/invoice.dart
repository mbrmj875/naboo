enum InvoiceType {
  cash,
  credit,
  installment,
  delivery,

  /// سند قبض: تحصيل دين آجل (يظهر في الفواتير والصندوق).
  debtCollection,

  /// سند قبض: تسديد قسط (يظهر في الفواتير والصندوق).
  installmentCollection,

  /// سند دفع ذمة للمورد (قائمة الفواتير؛ اختياريًا مرتبط بخصم الصندوق).
  supplierPayment,
}

/// تحويل عمود `type` من SQLite إلى [InvoiceType] بأمان (قيم قديمة أو تالفة).
InvoiceType invoiceTypeFromDb(Object? raw) {
  final v =
      raw is int ? raw : (raw is num ? raw.toInt() : int.tryParse('$raw'));
  final i = v ?? 0;
  if (i < 0 || i >= InvoiceType.values.length) return InvoiceType.cash;
  return InvoiceType.values[i];
}

/// نتيجة [DatabaseHelper.recordInstallmentPayment].
class RecordInstallmentPaymentResult {
  const RecordInstallmentPaymentResult({
    required this.success,
    this.receiptInvoiceId,
  });

  final bool success;
  final int? receiptInvoiceId;
}

class Invoice {
  int? id;
  String customerName;
  DateTime date;
  InvoiceType type;
  List<InvoiceItem> items;
  double discount;
  double tax;
  double advancePayment;
  double total;
  bool isReturned;
  int? originalInvoiceId;
  String? deliveryAddress;
  /// الموظف الذي سجّل البيع (اسم الدخول أو الاسم المعروض).
  String? createdByUserName;
  /// نسبة الخصم % المطبّقة على إجمالي البنود (للطباعة والأرشفة).
  double discountPercent;

  /// ربط بفترة الوردية المفتوحة عند الحفظ (اختياري للفواتير القديمة).
  int? workShiftId;

  /// عميل مسجّل — مطلوب لمنح/استبدال نقاط الولاء.
  int? customerId;

  /// خصم نقدي من استبدال نقاط الولاء (لا يُخلط مع خصم الفاتورة النسبي).
  double loyaltyDiscount;

  /// نقاط مُستبدَلة في هذه الفاتورة.
  int loyaltyPointsRedeemed;

  /// نقاط مُكتسبة من هذه الفاتورة (يُحدَّد عند الحفظ حسب الإعدادات).
  int loyaltyPointsEarned;

  /// لبيع «تقسيط» فقط: لقطة من حاسبة الفائدة عند الحفظ (0 لغير التقسيط).
  double installmentInterestPct;
  int installmentPlannedMonths;
  double installmentFinancedAmount;
  double installmentInterestAmount;
  double installmentTotalWithInterest;
  double installmentSuggestedMonthly;

  /// فقط عند [InvoiceType.supplierPayment] وقت الإنشاء: تسجيل خصم من الصندوق.
  bool supplierPaymentAffectsCash;

  Invoice({
    this.id,
    required this.customerName,
    required this.date,
    required this.type,
    required this.items,
    required this.discount,
    required this.tax,
    required this.advancePayment,
    required this.total,
    this.isReturned = false,
    this.originalInvoiceId,
    this.deliveryAddress,
    this.createdByUserName,
    this.discountPercent = 0,
    this.workShiftId,
    this.customerId,
    this.loyaltyDiscount = 0,
    this.loyaltyPointsRedeemed = 0,
    this.loyaltyPointsEarned = 0,
    this.installmentInterestPct = 0,
    this.installmentPlannedMonths = 0,
    this.installmentFinancedAmount = 0,
    this.installmentInterestAmount = 0,
    this.installmentTotalWithInterest = 0,
    this.installmentSuggestedMonthly = 0,
    this.supplierPaymentAffectsCash = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerName': customerName,
      'date': date.toIso8601String(),
      'type': type.index,
      'discount': discount,
      'tax': tax,
      'advancePayment': advancePayment,
      'total': total,
      'isReturned': isReturned ? 1 : 0,
      'originalInvoiceId': originalInvoiceId,
      'deliveryAddress': deliveryAddress,
      'createdByUserName': createdByUserName,
      'discountPercent': discountPercent,
      'workShiftId': workShiftId,
      'customerId': customerId,
      'loyaltyDiscount': loyaltyDiscount,
      'loyaltyPointsRedeemed': loyaltyPointsRedeemed,
      'loyaltyPointsEarned': loyaltyPointsEarned,
      'installmentInterestPct': installmentInterestPct,
      'installmentPlannedMonths': installmentPlannedMonths,
      'installmentFinancedAmount': installmentFinancedAmount,
      'installmentInterestAmount': installmentInterestAmount,
      'installmentTotalWithInterest': installmentTotalWithInterest,
      'installmentSuggestedMonthly': installmentSuggestedMonthly,
    };
  }

  factory Invoice.fromMap(Map<String, dynamic> map) {
    return Invoice(
      id: map['id'],
      customerName: map['customerName'],
      date: DateTime.parse(map['date']),
      type: invoiceTypeFromDb(map['type']),
      supplierPaymentAffectsCash: true,
      items: (map['items'] as List).map((i) => InvoiceItem.fromMap(i)).toList(),
      discount: map['discount'],
      tax: map['tax'],
      advancePayment: map['advancePayment'],
      total: map['total'],
      isReturned: map['isReturned'] == 1,
      originalInvoiceId: map['originalInvoiceId'],
      deliveryAddress: map['deliveryAddress'],
      createdByUserName: map['createdByUserName'] as String?,
      discountPercent: (map['discountPercent'] as num?)?.toDouble() ?? 0,
      workShiftId: map['workShiftId'] as int?,
      customerId: map['customerId'] as int?,
      loyaltyDiscount: (map['loyaltyDiscount'] as num?)?.toDouble() ?? 0,
      loyaltyPointsRedeemed: (map['loyaltyPointsRedeemed'] as num?)?.toInt() ?? 0,
      loyaltyPointsEarned: (map['loyaltyPointsEarned'] as num?)?.toInt() ?? 0,
      installmentInterestPct:
          (map['installmentInterestPct'] as num?)?.toDouble() ?? 0,
      installmentPlannedMonths:
          (map['installmentPlannedMonths'] as num?)?.toInt() ?? 0,
      installmentFinancedAmount:
          (map['installmentFinancedAmount'] as num?)?.toDouble() ?? 0,
      installmentInterestAmount:
          (map['installmentInterestAmount'] as num?)?.toDouble() ?? 0,
      installmentTotalWithInterest:
          (map['installmentTotalWithInterest'] as num?)?.toDouble() ?? 0,
      installmentSuggestedMonthly:
          (map['installmentSuggestedMonthly'] as num?)?.toDouble() ?? 0,
    );
  }
}

class InvoiceItem {
  String productName;
  /// كمية المخزون الأساسية المباعة/المرتجعة (مثلاً **كيلوغرامات** عند بيع بالوزن، أو قطع أساسية).
  double quantity;
  double price;
  double total;
  /// لربط البند بالمنتج (خصم المخزون عند البيع).
  int? productId;

  int? unitVariantId;
  String? unitLabel;
  double unitFactor;
  double enteredQty;
  double baseQty;

  InvoiceItem({
    required this.productName,
    required this.quantity,
    required this.price,
    required this.total,
    this.productId,
    this.unitVariantId,
    this.unitLabel,
    this.unitFactor = 1,
    double? enteredQty,
    double? baseQty,
  })  : enteredQty = enteredQty ?? quantity,
        baseQty = baseQty ?? quantity;

  /// الكمية المعروضة للمستخدم (وحدة البيع)، مع دعم الفواتير القديمة قبل أعمدة اللقطة.
  double get enteredQtyResolved {
    final b = baseQty;
    if (enteredQty > 0) return enteredQty;
    final f = unitFactor <= 0 ? 1.0 : unitFactor;
    if (b > 0) return b / f;
    return quantity;
  }

  /// كمية المخزون الأساسية المكافئة لهذا السطر.
  double get baseQtyResolved {
    final b = baseQty;
    if (b > 0) return b;
    final f = unitFactor <= 0 ? 1.0 : unitFactor;
    final e = enteredQty > 0 ? enteredQty : quantity;
    return e * f;
  }

  Map<String, dynamic> toMap() {
    return {
      'productName': productName,
      'quantity': quantity,
      'price': price,
      'total': total,
      'productId': productId,
      'unitVariantId': unitVariantId,
      'unitLabel': unitLabel,
      'unitFactor': unitFactor,
      'enteredQty': enteredQty,
      'baseQty': baseQty,
    };
  }

  factory InvoiceItem.fromMap(Map<String, dynamic> map) {
    final legacyQty = (map['quantity'] as num?)?.toDouble() ?? 0;
    final factorRaw = (map['unitFactor'] as num?)?.toDouble() ?? 1.0;
    final factor = factorRaw <= 0 ? 1.0 : factorRaw;
    final entered = (map['enteredQty'] as num?)?.toDouble();
    final base = (map['baseQty'] as num?)?.toDouble();

    final resolvedBase = base ?? legacyQty;
    final resolvedEntered = entered ??
        (base != null ? base / factor : legacyQty);
    return InvoiceItem(
      productName: map['productName'],
      quantity: resolvedBase,
      price: (map['price'] as num?)?.toDouble() ?? 0,
      total: (map['total'] as num?)?.toDouble() ?? 0,
      productId: map['productId'] as int?,
      unitVariantId: map['unitVariantId'] as int?,
      unitLabel: map['unitLabel'] as String?,
      unitFactor: factor,
      enteredQty: resolvedEntered,
      baseQty: resolvedBase,
    );
  }
}