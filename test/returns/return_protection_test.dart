import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/models/store_policy.dart';
import 'package:naboo/printing/receipt_builders.dart';
import 'package:naboo/printing/receipt_model.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/returns/return_approval.dart';
import 'package:naboo/services/returns/return_claim_service.dart';
import 'package:naboo/services/returns/return_guard.dart';
import 'package:naboo/services/returns/return_history.dart';
import 'package:naboo/services/returns/return_meta.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('قرار الاسترجاع', () {
    final now = DateTime(2026, 11, 8, 12);
    ReturnDecision run({
      ReturnPolicy policy = const ReturnPolicy(),
      int daysAgo = 1,
      bool legacy = false,
      bool full = false,
      bool owner = false,
      bool elevated = false,
      bool shift = true,
    }) => ReturnGuard.evaluate(
      policy: policy,
      invoiceDate: now.subtract(Duration(days: daysAgo)),
      now: now,
      legacy: legacy,
      fullyReturned: full,
      isOwner: owner,
      elevated: elevated,
      hasOpenShift: shift,
    );

    test('داخل المدة، إيصال حديث', () {
      expect(run(owner: true).verdict, ReturnVerdict.allowed);
      expect(run(elevated: true).verdict, ReturnVerdict.allowed);
      final limited = run();
      expect(limited.verdict, ReturnVerdict.needsApproval);
      expect(limited.reasons, {ReturnApprovalReason.limitedStaff});
    });

    test(
      'الإيصال القديم يحتاج موافقة حتى لكامل الصلاحية، والمالك يوافق لنفسه',
      () {
        final full = run(legacy: true, elevated: true);
        expect(full.verdict, ReturnVerdict.needsApproval);
        expect(full.reasons, {ReturnApprovalReason.legacyReceipt});
        final owner = run(legacy: true, owner: true);
        expect(owner.verdict, ReturnVerdict.allowed);
        expect(owner.reasons, contains(ReturnApprovalReason.legacyReceipt));
      },
    );

    test('خارج المدة: بموافقة أو ممنوع', () {
      final approval = run(daysAgo: 8, elevated: true);
      expect(approval.verdict, ReturnVerdict.needsApproval);
      expect(approval.reasons, {ReturnApprovalReason.outsideWindow});
      const forbid = ReturnPolicy(afterWindow: ReturnAfterWindow.forbidden);
      expect(run(policy: forbid, daysAgo: 8, owner: true).isForbidden, isTrue);
      expect(
        run(policy: forbid, daysAgo: 7, elevated: true).verdict,
        ReturnVerdict.allowed,
      );
    });

    test('مطفأ، أو بلا وردية، أو مرتجع بالكامل: ممنوع للجميع', () {
      const off = ReturnPolicy(enabled: false);
      expect(run(policy: off, owner: true).isForbidden, isTrue);
      expect(run(shift: false, owner: true).isForbidden, isTrue);
      expect(run(full: true, owner: true).isForbidden, isTrue);
      expect(run(shift: false).message, contains('وردية'));
    });

    test('المدة بالأيام التقويمية', () {
      expect(
        ReturnGuard.isOutsideWindow(
          invoiceDate: DateTime(2026, 11, 1, 23, 59),
          now: DateTime(2026, 11, 8, 0, 1),
          windowDays: 7,
        ),
        isFalse,
      );
      expect(
        ReturnGuard.isOutsideWindow(
          invoiceDate: DateTime(2026, 11, 1),
          now: DateTime(2026, 11, 9),
          windowDays: 7,
        ),
        isTrue,
      );
    });
  });

  group('الموافقة', () {
    final users = [
      {'id': 1, 'role': 'owner', 'displayName': 'المالك'},
      {
        'id': 2,
        'role': 'staff',
        'displayName': 'علي',
        'passwordHash': 'h',
        'passwordSalt': 's',
      },
      {
        'id': 3,
        'role': 'staff',
        'displayName': 'حسن',
        'passwordHash': 'h',
        'passwordSalt': 's',
      },
      {'id': 4, 'role': 'staff', 'displayName': 'بلا رمز'},
    ];

    test('المالك وكاملو الصلاحية فقط، والمالك أولاً', () {
      final list = selectApprovers(
        activeUsers: users,
        elevatedStaffIds: {2, 4},
        currentUserId: 3,
        blockSelfApproval: true,
      );
      expect(list.map((c) => c.userId), [1, 2]);
      expect(list.first.isOwner, isTrue);
    });

    test('منع الموافقة الذاتية', () {
      final blocked = selectApprovers(
        activeUsers: users,
        elevatedStaffIds: {2},
        currentUserId: 2,
        blockSelfApproval: true,
      );
      expect(blocked.map((c) => c.userId), [1]);
      final allowed = selectApprovers(
        activeUsers: users,
        elevatedStaffIds: {2},
        currentUserId: 2,
        blockSelfApproval: false,
      );
      expect(allowed.map((c) => c.userId), [1, 2]);
    });

    test('لمرة واحدة ومربوطة بالفاتورة والمبلغ', () {
      final a = ReturnApproval(
        approverUserId: 1,
        approverName: 'المالك',
        approverIsOwner: true,
        invoiceGlobalKey: 'g1',
        amount: 9000,
      );
      expect(a.matches('g1', 12000), isFalse);
      expect(a.matches('g2', 9000), isFalse);
      expect(a.consume('g1', 9000), isTrue);
      expect(a.consume('g1', 9000), isFalse);
    });
  });

  group('سياسات المحل', () {
    test('القيم الافتراضية والقراءة والكتابة', () {
      const d = StorePolicy();
      expect(d.returns.enabled, isTrue);
      expect(d.returns.windowDays, 7);
      expect(d.returns.blockSelfApproval, isTrue);
      expect(d.washRepeat.enabled, isFalse);
      expect(d.oilWash.enabled, isFalse);
      final custom = d.copyWith(
        returns: d.returns.copyWith(
          windowDays: 3,
          afterWindow: ReturnAfterWindow.forbidden,
        ),
        washRepeat: d.washRepeat.copyWith(enabled: true, periodDays: 5),
      );
      final back = StorePolicy.fromJsonString(custom.toJsonString());
      expect(back.returns.windowDays, 3);
      expect(back.returns.afterWindow, ReturnAfterWindow.forbidden);
      expect(back.washRepeat.periodDays, 5);
      expect(back.washRepeat.enabled, isTrue);
    });

    test('حمولة تالفة ترجع للقيم الآمنة', () {
      expect(StorePolicy.fromJsonString('{bad').returns.enabled, isTrue);
      expect(
        StorePolicy.fromJsonString(
          '{"returns":{"windowDays":9999}}',
        ).returns.windowDays,
        365,
      );
    });
  });

  group('إيصال الاسترجاع', () {
    Invoice ret() => Invoice(
      id: 40,
      customerName: 'محمد',
      date: DateTime(2026, 11, 8),
      type: InvoiceType.credit,
      items: [
        InvoiceItem(productName: 'زيت', quantity: 2, price: 9000, total: 18000),
      ],
      discount: 0,
      tax: 0,
      advancePayment: 18000,
      total: 18000,
      isReturned: true,
      originalInvoiceId: 31,
      returnReason: 'لزوجة غير مناسبة',
      returnMeta: ReturnMeta(
        originalNumber: 31,
        originalDate: DateTime(2026, 11, 6),
        actor: 'علي',
        approver: 'المالك',
        refundMethodAr: ReceiptBuilders.refundMethodAr(InvoiceType.credit),
      ).encode(),
      globalId: '3f2a1c9e-7b4d-4e8a-9c1f-0a2b3c4d5e6f',
    );

    test('نوعه استرجاع ومحتواه كامل', () {
      expect(ReceiptBuilders.kindOf(ret()), ReceiptKind.saleReturn);
      final doc = ReceiptBuilders.fromInvoice(ret());
      expect(doc.kind, ReceiptKind.saleReturn);
      expect(doc.title, 'إيصال استرجاع');
      String? f(String l) =>
          doc.fields.where((x) => x.label == l).map((x) => x.value).firstOrNull;
      expect(f('الفاتورة الأصلية'), '#31');
      expect(f('السبب'), 'لزوجة غير مناسبة');
      expect(f('الموافِق'), 'المالك');
      expect(f('طريقة الإرجاع'), contains('الدين'));
      expect(doc.totals.single.label, 'المبلغ المسترد');
      expect(doc.totals.single.emphasis, isTrue);
      expect(doc.notes.any((n) => n.contains('توقيع')), isTrue);
    });

    test('نسختان وطباعة تلقائية افتراضياً', () {
      final t = ReceiptTemplate.defaultsFor(ReceiptKind.saleReturn);
      expect(t.copies, 2);
      expect(t.autoPrint, isTrue);
      expect(ReceiptTemplate.defaultsFor(ReceiptKind.directSale).copies, 1);
    });
  });

  group('مطالبة الخادم', () {
    tearDown(() {
      ReturnClaimService.isSignedIn = () => true;
    });

    test('بلا جلسة = بلا إنترنت', () async {
      ReturnClaimService.isSignedIn = () => false;
      final r = await ReturnClaimService.claim(
        originalGlobalId: 'a',
        returnGlobalId: 'b',
        lines: const [ReturnClaimLine(key: 'k', qty: 1, sold: 1)],
        amount: 1,
        actor: 'x',
      );
      expect(r.status, ReturnClaimStatus.offline);
    });

    test('انقطاع الشبكة = بلا إنترنت، والتجاوز يعيد المتبقي', () async {
      ReturnClaimService.isSignedIn = () => true;
      ReturnClaimService.rpc = (_, _) async =>
          throw Exception('SocketException');
      final off = await ReturnClaimService.claim(
        originalGlobalId: 'a',
        returnGlobalId: 'b',
        lines: const [ReturnClaimLine(key: 'k', qty: 1, sold: 1)],
        amount: 1,
        actor: 'x',
      );
      expect(off.status, ReturnClaimStatus.offline);

      Map<String, dynamic>? sent;
      ReturnClaimService.rpc = (fn, p) async {
        sent = p;
        return {
          'ok': false,
          'reason': 'exceeds_sold',
          'key': 'k',
          'remaining': 2,
        };
      };
      final ex = await ReturnClaimService.claim(
        originalGlobalId: 'a',
        returnGlobalId: 'b',
        lines: const [ReturnClaimLine(key: 'k', qty: 3, sold: 5)],
        amount: 3,
        actor: 'x',
      );
      expect(ex.status, ReturnClaimStatus.exceeds);
      expect(ex.remaining, 2);
      expect((sent!['p_lines'] as List).single, {
        'key': 'k',
        'qty': 3.0,
        'sold': 5.0,
      });
    });
  });

  group('بين الأجهزة', () {
    late Database db;
    setUpAll(sqfliteFfiInit);
    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE invoices (
          id INTEGER PRIMARY KEY, global_id TEXT, total REAL, date TEXT,
          isReturned INTEGER DEFAULT 0, originalInvoiceId INTEGER,
          originalInvoiceGlobalId TEXT, createdByUserName TEXT, deleted_at TEXT,
          tenantId INTEGER DEFAULT 1
        )''');
      await db.execute('''
        CREATE TABLE invoice_items (
          id INTEGER PRIMARY KEY, invoiceId INTEGER, productId INTEGER,
          productName TEXT, price REAL, enteredQty REAL
        )''');
    });
    tearDown(() => db.close());

    test('رقم الأصل في المرتجع الوارد يُعاد ربطه بفاتورة هذا الجهاز', () async {
      await db.insert('invoices', {'id': 88, 'global_id': 'orig-g'});
      final incoming = <String, dynamic>{
        'originalInvoiceId': 1024,
        'originalInvoiceGlobalId': 'ORIG-G',
      };
      await CloudSyncService.remapReturnOriginalInvoiceId(db, incoming);
      expect(incoming['originalInvoiceId'], 88);

      final unknown = <String, dynamic>{
        'originalInvoiceId': 1024,
        'originalInvoiceGlobalId': 'other',
      };
      await CloudSyncService.remapReturnOriginalInvoiceId(db, unknown);
      expect(unknown['originalInvoiceId'], isNull);

      final legacy = <String, dynamic>{'originalInvoiceId': 5};
      await CloudSyncService.remapReturnOriginalInvoiceId(db, legacy);
      expect(legacy['originalInvoiceId'], 5);
    });

    test(
      'ملخص المرتجعات يعدّ المرتجع بمعرّفه العالمي حتى لو اختلف الرقم',
      () async {
        ReturnHistory.databaseOverride = () async => db;
        addTearDown(() => ReturnHistory.databaseOverride = null);
        final original = Invoice(
          id: 10,
          customerName: 'x',
          date: DateTime(2026, 11, 1),
          type: InvoiceType.cash,
          items: [
            InvoiceItem(
              productName: 'زيت',
              quantity: 2,
              price: 9000,
              total: 18000,
              productId: 7,
            ),
          ],
          discount: 0,
          tax: 0,
          advancePayment: 18000,
          total: 18000,
          globalId: 'orig-g',
        );
        await db.insert('invoices', {
          'id': 10,
          'global_id': 'orig-g',
          'total': 18000,
        });
        // محل آخر على القاعدة نفسها: مرتجع لفاتورته رقم 10 لا يُحسب هنا.
        await db.insert('invoices', {
          'id': 49,
          'total': 18000,
          'date': '2026-11-02T09:00:00',
          'isReturned': 1,
          'originalInvoiceId': 10,
          'createdByUserName': 'غريب',
          'tenantId': 2,
        });
        await db.insert('invoice_items', {
          'invoiceId': 49,
          'productId': 7,
          'productName': 'زيت',
          'price': 9000,
          'enteredQty': 2,
        });
        await db.insert('invoices', {
          'id': 50,
          'total': 9000,
          'date': '2026-11-02T10:00:00',
          'isReturned': 1,
          'originalInvoiceId': null,
          'originalInvoiceGlobalId': 'orig-g',
          'createdByUserName': 'علي',
        });
        await db.insert('invoice_items', {
          'invoiceId': 50,
          'productId': 7,
          'productName': 'زيت',
          'price': 9000,
          'enteredQty': 1,
        });
        var h = await ReturnHistory.of(original);
        expect(h.returnCount, 1);
        expect(h.fullyReturned, isFalse);

        await db.insert('invoices', {
          'id': 51,
          'total': 9000,
          'date': '2026-11-03T10:00:00',
          'isReturned': 1,
          'originalInvoiceId': 10,
          'createdByUserName': 'حسن',
        });
        await db.insert('invoice_items', {
          'invoiceId': 51,
          'productId': 7,
          'productName': 'زيت',
          'price': 9000,
          'enteredQty': 1,
        });
        h = await ReturnHistory.of(original);
        expect(h.fullyReturned, isTrue);
        expect(h.totalAmount, 18000);
        expect(h.lastBy, 'حسن');
      },
    );
  });
}
