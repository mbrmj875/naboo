---
name: erp-logic-performance
description: ERP business-logic correctness, money arithmetic (fils/integer), invoice balance validation, multi-tenant SQLite queries, pagination, soft-delete for financial records, Flutter performance (compute/isolate, batched transactions), SQLite indexing, state management, logging, and test coverage for the Naboo / Basra Store Manager project. Use when editing any file under lib/**/*.dart, touching invoices/products/payments/reports, writing sqflite queries, handling currency or totals, importing/exporting data, or when the user asks about money math, tenant isolation, soft delete, pagination, isolates, query performance, audit logs, or تحقّق الفاتورة.
---

# منطق ERP + الأداء + جودة الكود — Naboo / Basra Store Manager

> يُكمِّل هذا الـ skill:
> - `arabic-rtl.mdc` — قواعد الـ RTL والعربية
> - `flutter-responsive-rtl` skill — التخطيط المتجاوب
>
> هنا نركّز على **المنطق الحرج**: المال، الفواتير، الأداء، جودة الكود.

---

## ⚠️ الحزم الحالية في المشروع vs المستهدفة

قبل أن تقترح حلاً، تأكّد أي مرحلة نحن فيها. هذا المشروع **لم يُهاجَر بالكامل** إلى الـ stack المستهدف.

| المجال | **الموجود الآن** (استعمله) | **المستهدف** (لا تُدخله قبل طلب صريح) |
|---|---|---|
| State | `provider` ^6.1.1 | Riverpod 2.x |
| HTTP | `http` ^1.6.0 | `http` / `dio` |
| Local DB | `sqflite` ^2.3.0 | `sqflite` (حالياً) / Drift لاحقاً |
| Remote | `supabase_flutter` ^2.9.1 | نفسه ✓ |
| Secure Store | `shared_preferences` | `flutter_secure_storage` |
| Connectivity | غير مُضاف | `connectivity_plus` |
| Navigation | `Navigator` يدوي | `go_router` |
| Logger | `debugPrint` | `logger` مع `AppLogger` |

**قاعدة ذهبية:** إذا طُلب منك كتابة كود جديد، استخدم الأدوات **الموجودة حالياً**. إذا رأيت تعليمات في هذا الـ skill تشير لـ Riverpod / Drift / go_router، اعتبرها **خطّة هجرة مستقبلية** — واسأل المستخدم قبل إضافتها.

---

## 💰 قواعد المال — لا floating point أبداً

**العملة:** الدينار العراقي. أصغر وحدة = **فلس** (1 دينار = 1000 فلس).

```dart
// ❌ خطأ — 0.1 + 0.2 = 0.30000000000000004
double total = items.fold(0.0, (s, i) => s + i.price * i.qty);

// ✅ صحيح — خزّن بالفلس، عمود DB من نوع INTEGER
int totalFils = items.fold(0, (s, i) => s + i.priceFils * i.qty);

// عرض فقط
String formatCurrency(int fils, {String locale = 'ar-IQ'}) {
  final dinar = fils / 1000.0;
  return NumberFormat.currency(
    locale: locale,
    symbol: 'د.ع',
    decimalDigits: 3,
  ).format(dinar);
}

// تحويل من مدخل المستخدم
int parseAmountToFils(String input) {
  final cleaned = input.replaceAll(',', '').trim();
  final value = double.tryParse(cleaned);
  if (value == null || value < 0) throw ValidationException('مبلغ غير صالح');
  return (value * 1000).round();
}
```

---

## 🧾 التحقق من توازن الفاتورة — قبل الحفظ دائماً

```dart
void validateInvoiceBalance(Invoice invoice) {
  final itemsTotal = invoice.items
    .fold(0, (s, item) => s + (item.priceFils * item.quantity));

  final discountFils = invoice.discountFils ?? 0;
  final taxableFils  = itemsTotal - discountFils;
  final taxFils      = (taxableFils * invoice.taxRate / 100).round();
  final expected     = taxableFils + taxFils;

  if (expected != invoice.totalFils) {
    throw ValidationException(
      'مجموع الفاتورة غير صحيح: المتوقع ${formatCurrency(expected)}، '
      'الموجود ${formatCurrency(invoice.totalFils)}'
    );
  }

  if (invoice.items.isEmpty) {
    throw ValidationException('الفاتورة يجب أن تحتوي على صنف واحد على الأقل');
  }
}
```

---

## 🗑️ Soft Delete — لا حذف حقيقي للسجلات المالية

```dart
// ❌ خطأ — فقدان سجل مالي دائم
await db.delete('invoices', where: 'id = ?', whereArgs: [id]);

// ✅ صحيح
Future<void> softDelete(String invoiceId) async {
  await db.update(
    'invoices',
    {
      'deleted_at':  DateTime.now().millisecondsSinceEpoch,
      'deleted_by':  currentUser.id,
      'sync_status': 'pending_update',
    },
    where: 'id = ? AND tenant_id = ?',
    whereArgs: [invoiceId, currentTenantId],
  );
}

// في كل استعلام قراءة — استثنِ المحذوف:
// WHERE tenant_id = ? AND deleted_at IS NULL
```

---

## 📄 Pagination — إلزامي لكل قائمة

**cursor-based** أفضل من `OFFSET` للبيانات الكبيرة:

```dart
class PaginatedResult<T> {
  final List<T> items;
  final String? nextCursor; // null = لا توجد صفحة تالية
  const PaginatedResult({required this.items, this.nextCursor});
}

Future<PaginatedResult<Invoice>> getInvoices({
  required String tenantId,
  String? afterId,
  int pageSize = 50,
}) async {
  final rows = await db.rawQuery('''
    SELECT * FROM invoices
    WHERE tenant_id = ?
      AND deleted_at IS NULL
      ${afterId != null ? 'AND rowid < (SELECT rowid FROM invoices WHERE id = ?)' : ''}
    ORDER BY created_at DESC
    LIMIT ?
  ''', [tenantId, if (afterId != null) afterId, pageSize + 1]);

  final hasMore = rows.length > pageSize;
  final items = rows.take(pageSize).map(Invoice.fromMap).toList();
  return PaginatedResult(
    items: items,
    nextCursor: hasMore ? items.last.id : null,
  );
}
```

في الواجهة: استخدم دائماً `ListView.builder` (لا `ListView(children: [...])`) لأي قائمة > 10 عناصر.

---

## ⚡ الأداء — لا تُجمّد الواجهة

```dart
// ❌ عملية ثقيلة في main isolate
Future<void> importProducts(List<Map> rawData) async {
  for (final row in rawData) { // 10,000 سطر = UI مجمّد
    await db.insert('products', row);
  }
}

// ✅ compute() للـ parse + batch transaction للإدخال
Future<void> importProducts(List<Map> rawData) async {
  final validated = await compute(_validateAndParse, rawData);

  await db.transaction((txn) async {
    final batch = txn.batch();
    for (final row in validated) {
      batch.insert('products', row,
        conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true); // noResult أسرع
  });
}

// top-level أو static — لا ترث context
List<Map> _validateAndParse(List<Map> rawData) {
  return rawData
    .where((row) => row['name'] != null && row['price'] != null)
    .toList();
}
```

**قاعدة:** أي عملية متوقع أن تأخذ > 16ms يجب أن تكون في `compute()` أو `Isolate.run()`.

---

## 🔎 فهارس SQLite — أضفها عند إنشاء الجدول

```dart
static Future<void> createIndexes(Database db) async {
  // الأهم: فهرس tenant_id على كل جدول
  await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_tenant ON invoices(tenant_id)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_date ON invoices(created_at DESC)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_invoices_status ON invoices(status, tenant_id)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_products_tenant ON products(tenant_id)');

  // فهرس مركّب للبحث الشائع
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_invoices_search '
    'ON invoices(tenant_id, customer_id, created_at DESC)'
  );
}

// debug فقط — تحقّق من عدم وجود SCAN TABLE للاستعلامات الكبيرة
if (kDebugMode) {
  final plan = await db.rawQuery('EXPLAIN QUERY PLAN $yourQuery');
  assert(
    !plan.any((row) => row['detail'].toString().contains('SCAN TABLE')),
    'استعلام بطيء — يحتاج فهرس: $yourQuery',
  );
}
```

---

## 🧠 إدارة الحالة — النمط الحالي (`provider`)

> نستخدم `provider` ^6.1.1 حالياً. نمط Riverpod أدناه **خطّة مستقبلية**.

```dart
// النمط الحالي: ChangeNotifier + Consumer
class InvoiceController extends ChangeNotifier {
  final InvoiceRepository _repo;
  InvoiceController(this._repo);

  AsyncValue<PaginatedResult<Invoice>> _state = const AsyncLoading();
  AsyncValue<PaginatedResult<Invoice>> get state => _state;

  Future<void> load({String? afterId}) async {
    _state = const AsyncLoading();
    notifyListeners();
    try {
      final result = await _repo.getInvoices(
        tenantId: currentTenantId,
        afterId: afterId,
      );
      _state = AsyncData(result);
    } catch (e, s) {
      _state = AsyncError(e, s);
    }
    notifyListeners();
  }

  Future<void> create(Invoice invoice) async {
    validateInvoiceBalance(invoice); // تحقّق قبل الحفظ
    await _repo.createInvoice(invoice);
    await load();
  }
}
```

<details>
<summary>خطّة هجرة: Riverpod 2.x (لا تُطبّق بدون طلب صريح)</summary>

```dart
@riverpod
Future<PaginatedResult<Invoice>> invoices(
  InvoicesRef ref, {
  String? afterId,
}) async {
  final tenantId = ref.watch(currentTenantProvider).id;
  return ref.watch(invoiceRepositoryProvider)
    .getInvoices(tenantId: tenantId, afterId: afterId);
}

@riverpod
class InvoiceActions extends _$InvoiceActions {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> create(Invoice invoice) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      validateInvoiceBalance(invoice);
      await ref.read(invoiceRepositoryProvider).createInvoice(invoice);
    });
  }
}
```

</details>

---

## 🧹 جودة الكود

### `analysis_options.yaml`

```yaml
include: package:flutter_lints/flutter.yaml
analyzer:
  errors:
    avoid_print:              error
    always_declare_return_types: warning
linter:
  rules:
    - always_declare_return_types
    - avoid_dynamic_calls
    - avoid_print
    - prefer_const_constructors
    - require_trailing_commas
    - unawaited_futures
```

### Logger مركزي — لا `print()` في الإنتاج

```dart
// النمط الحالي (بدون حزمة logger): استخدم debugPrint فقط في debug
class AppLogger {
  static void info(String event, [Map<String, dynamic>? data]) {
    if (kDebugMode) debugPrint('ℹ️  $event ${data ?? ''}');
  }

  static void warn(String event, [Map<String, dynamic>? data]) {
    if (kDebugMode) debugPrint('⚠️  $event ${data ?? ''}');
  }

  static void error(String event, Object error, StackTrace stack) {
    if (kDebugMode) debugPrint('❌ $event\n$error\n$stack');
    // TODO: اربط بـ Sentry/Supabase logs عند الحاجة
  }
}

// ❌ لا تُسجّل بيانات حساسة أبداً
// AppLogger.info('user_login', {'password': password}); // مرفوض
```

---

## 🧪 اختبارات إلزامية للمنطق الحرج

```dart
group('InvoiceValidator', () {
  test('يرفض مبالغ سالبة', () {
    expect(
      () => validateInvoiceBalance(invoice.copyWith(totalFils: -1000)),
      throwsA(isA<ValidationException>()),
    );
  });

  test('يرفض فاتورة بمجموع غير متطابق', () {
    final bad = invoice.copyWith(totalFils: invoice.totalFils + 1);
    expect(() => validateInvoiceBalance(bad),
      throwsA(isA<ValidationException>()));
  });

  test('يرفض فاتورة بدون أصناف', () {
    final empty = invoice.copyWith(items: []);
    expect(() => validateInvoiceBalance(empty),
      throwsA(isA<ValidationException>()));
  });
});

group('CurrencyFormatter', () {
  test('تحويل فلس لدينار صحيح', () {
    expect(formatCurrency(1500), contains('1.500'));
  });
  test('تحويل مدخل نصي لفلس', () {
    expect(parseAmountToFils('1.500'), equals(1500));
    expect(parseAmountToFils('1,500'), equals(1500000));
  });
});
```

كل ملف في `lib/core/money/` أو `lib/models/invoice*` يجب أن يقابله ملف اختبار في `test/`.

---

## ✅ قائمة التحقق قبل كل Commit

```
[ ] كل المبالغ مخزنة كـ int (فلس) لا double
[ ] كل استعلام sqflite يحتوي tenant_id
[ ] كل استعلام قراءة يحتوي AND deleted_at IS NULL
[ ] كل قائمة تستخدم ListView.builder مع pagination
[ ] كل شاشة تعرض حالات: loading + empty + error
[ ] العمليات الثقيلة (import/export) في compute() أو Isolate.run()
[ ] السجلات المالية تُحذف soft delete فقط
[ ] كل عملية مالية مهمة لها audit log
[ ] اختُبرت الشاشة على: موبايل + تابلت + ديسكتوب
[ ] اختُبر RTL العربية
[ ] لا print() — استخدم AppLogger
[ ] لم أُدخل حزمة جديدة (Riverpod/go_router/...) بدون طلب صريح
```
