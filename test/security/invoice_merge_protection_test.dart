/*
  PR-1 — حماية merge الفواتير ضد فقدان التسديدات والإجماليات.

  المرجع: docs/specs/roadmap_phase2_execution_v1.md §4 PR-1

  سياسة الحماية:
    • الحقول المالية الإجمالية: مجمدة (المحلي يفوز دائماً، حتى لو فاز incoming بـ LWW).
    • advancePayment / advancePaymentFils: max(local, incoming) — يمنع مسح التسديدات.
    • workShiftId / actorUserId / shiftOwnerUserId / createdByUserName:
        enrichment فقط (تُملأ لو المحلي null/0/empty).
    • الباقي (customerName, deliveryAddress, ...): LWW عادي إذا فاز incoming.

  هذا الملف يختبر الـ pure policy function applyInvoiceMergePolicy
  دون الحاجة لقاعدة بيانات — أسرع وأدق.
*/

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/invoice_merge_policy.dart';

// أعمدة موجودة في السكيما المحلية (مطابقة تقريباً لـ database_helper).
const Set<String> _kLocalCols = {
  'id',
  'global_id',
  'customerName',
  'customerId',
  'date',
  'type',
  'total',
  'totalFils',
  'discount',
  'discountFils',
  'discountPercent',
  'tax',
  'taxFils',
  'advancePayment',
  'advancePaymentFils',
  'isReturned',
  'originalInvoiceId',
  'deliveryAddress',
  'workShiftId',
  'actorUserId',
  'shiftOwnerUserId',
  'createdByUserName',
  'loyaltyDiscount',
  'loyaltyDiscountFils',
  'loyaltyPointsRedeemed',
  'loyaltyPointsEarned',
  'updatedAt',
};

Map<String, Object?> _baseLocal({
  required int id,
  required int totalFils,
  required int advancePaymentFils,
  String updatedAt = '2026-06-01T10:00:00Z',
  Map<String, Object?> overrides = const {},
}) {
  return {
    'id': id,
    'global_id': 'inv-gid-1',
    'customerName': 'عميل أول',
    'customerId': 5,
    'date': '2026-05-01T00:00:00Z',
    'type': 1, // credit
    'total': totalFils / 1000.0,
    'totalFils': totalFils,
    'discount': 0,
    'discountFils': 0,
    'discountPercent': 0,
    'tax': 0,
    'taxFils': 0,
    'advancePayment': advancePaymentFils / 1000.0,
    'advancePaymentFils': advancePaymentFils,
    'isReturned': 0,
    'originalInvoiceId': null,
    'deliveryAddress': 'بصرة',
    'workShiftId': null,
    'actorUserId': null,
    'shiftOwnerUserId': null,
    'createdByUserName': null,
    'loyaltyDiscount': 0,
    'loyaltyDiscountFils': 0,
    'loyaltyPointsRedeemed': 0,
    'loyaltyPointsEarned': 0,
    'updatedAt': updatedAt,
    ...overrides,
  };
}

Map<String, Object?> _baseIncoming({
  required int totalFils,
  required int advancePaymentFils,
  String updatedAt = '2026-06-02T10:00:00Z',
  Map<String, Object?> overrides = const {},
}) {
  return {
    'global_id': 'inv-gid-1',
    'customerName': 'عميل أول',
    'customerId': 5,
    'date': '2026-05-01T00:00:00Z',
    'type': 1,
    'total': totalFils / 1000.0,
    'totalFils': totalFils,
    'discount': 0,
    'discountFils': 0,
    'discountPercent': 0,
    'tax': 0,
    'taxFils': 0,
    'advancePayment': advancePaymentFils / 1000.0,
    'advancePaymentFils': advancePaymentFils,
    'isReturned': 0,
    'originalInvoiceId': null,
    'deliveryAddress': 'بصرة',
    'workShiftId': null,
    'actorUserId': null,
    'shiftOwnerUserId': null,
    'createdByUserName': null,
    'loyaltyDiscount': 0,
    'loyaltyDiscountFils': 0,
    'loyaltyPointsRedeemed': 0,
    'loyaltyPointsEarned': 0,
    'updatedAt': updatedAt,
    ...overrides,
  };
}

void main() {
  group('applyInvoiceMergePolicy — حماية الحقول المالية', () {
    test(
      'T1: advancePaymentFils محلي > incoming + incoming أحدث ⇒ '
      'تسديد لا يُمسح',
      () {
        final local = _baseLocal(
          id: 11,
          totalFils: 1_000_000,
          advancePaymentFils: 500_000,
        );
        final incoming = _baseIncoming(
          totalFils: 1_000_000,
          advancePaymentFils: 0,
        );

        final outcome = applyInvoiceMergePolicy(
          current: local,
          incoming: incoming,
          incomingWins: true,
          localCols: _kLocalCols,
        );

        expect(
          outcome.merged['advancePaymentFils'],
          500_000,
          reason: 'max() يجب أن يحافظ على القيمة المحلية الأعلى',
        );
        expect(outcome.merged['advancePayment'], 500.0);
      },
    );

    test(
      'T2: advancePaymentFils incoming > local + incoming أحدث ⇒ '
      'تسديد جديد يدخل',
      () {
        final local = _baseLocal(
          id: 12,
          totalFils: 1_000_000,
          advancePaymentFils: 200_000,
        );
        final incoming = _baseIncoming(
          totalFils: 1_000_000,
          advancePaymentFils: 800_000,
        );

        final outcome = applyInvoiceMergePolicy(
          current: local,
          incoming: incoming,
          incomingWins: true,
          localCols: _kLocalCols,
        );

        expect(outcome.merged['advancePaymentFils'], 800_000);
        expect(outcome.merged['advancePayment'], 800.0);
      },
    );

    test(
      'T3: total محلي > incoming + incoming أحدث ⇒ الإجمالي مجمد',
      () {
        final local = _baseLocal(
          id: 13,
          totalFils: 1_000_000,
          advancePaymentFils: 0,
        );
        final incoming = _baseIncoming(
          totalFils: 900_000,
          advancePaymentFils: 0,
        );

        final outcome = applyInvoiceMergePolicy(
          current: local,
          incoming: incoming,
          incomingWins: true,
          localCols: _kLocalCols,
        );

        expect(
          outcome.merged['totalFils'],
          1_000_000,
          reason: 'الإجماليات مجمدة — لا يُسمح لـ incoming بتقليلها',
        );
        expect(outcome.merged['total'], 1000.0);
      },
    );

    test(
      'T3b: discount + tax + loyalty مجمدة كذلك',
      () {
        final local = _baseLocal(
          id: 14,
          totalFils: 1_000_000,
          advancePaymentFils: 0,
          overrides: {
            'discount': 50.0,
            'discountFils': 50_000,
            'tax': 30.0,
            'taxFils': 30_000,
            'loyaltyDiscount': 10.0,
            'loyaltyDiscountFils': 10_000,
            'loyaltyPointsEarned': 100,
          },
        );
        final incoming = _baseIncoming(
          totalFils: 1_000_000,
          advancePaymentFils: 0,
          overrides: {
            'discount': 0.0,
            'discountFils': 0,
            'tax': 0.0,
            'taxFils': 0,
            'loyaltyDiscount': 0.0,
            'loyaltyDiscountFils': 0,
            'loyaltyPointsEarned': 0,
          },
        );

        final outcome = applyInvoiceMergePolicy(
          current: local,
          incoming: incoming,
          incomingWins: true,
          localCols: _kLocalCols,
        );

        expect(outcome.merged['discountFils'], 50_000);
        expect(outcome.merged['taxFils'], 30_000);
        expect(outcome.merged['loyaltyDiscountFils'], 10_000);
        expect(outcome.merged['loyaltyPointsEarned'], 100);
      },
    );

    test(
      'T3c: isReturned + originalInvoiceId مجمدتان (لا يُلغى مرتجع عبر sync)',
      () {
        final local = _baseLocal(
          id: 15,
          totalFils: 1_000_000,
          advancePaymentFils: 0,
          overrides: {'isReturned': 1, 'originalInvoiceId': 9},
        );
        final incoming = _baseIncoming(
          totalFils: 1_000_000,
          advancePaymentFils: 0,
          overrides: {'isReturned': 0, 'originalInvoiceId': null},
        );

        final outcome = applyInvoiceMergePolicy(
          current: local,
          incoming: incoming,
          incomingWins: true,
          localCols: _kLocalCols,
        );

        expect(outcome.merged['isReturned'], 1);
        expect(outcome.merged['originalInvoiceId'], 9);
      },
    );
  });

  group('applyInvoiceMergePolicy — enrichment', () {
    test(
      'T6: workShiftId محلي null + incoming = 42 ⇒ يُملأ',
      () {
        final local = _baseLocal(
          id: 21,
          totalFils: 500_000,
          advancePaymentFils: 0,
        );
        final incoming = _baseIncoming(
          totalFils: 500_000,
          advancePaymentFils: 0,
          overrides: {'workShiftId': 42, 'actorUserId': 3},
        );

        final outcome = applyInvoiceMergePolicy(
          current: local,
          incoming: incoming,
          incomingWins: true,
          localCols: _kLocalCols,
        );

        expect(outcome.merged['workShiftId'], 42);
        expect(outcome.merged['actorUserId'], 3);
      },
    );

    test(
      'T7: actorUserId محلي = 7 + incoming = 9 ⇒ لا overwrite',
      () {
        final local = _baseLocal(
          id: 22,
          totalFils: 500_000,
          advancePaymentFils: 0,
          overrides: {'actorUserId': 7, 'workShiftId': 11},
        );
        final incoming = _baseIncoming(
          totalFils: 500_000,
          advancePaymentFils: 0,
          overrides: {'actorUserId': 9, 'workShiftId': 88},
        );

        final outcome = applyInvoiceMergePolicy(
          current: local,
          incoming: incoming,
          incomingWins: true,
          localCols: _kLocalCols,
        );

        expect(
          outcome.merged['actorUserId'],
          7,
          reason: 'enrichment لا يكتب فوق قيمة موجودة',
        );
        expect(outcome.merged['workShiftId'], 11);
      },
    );

    test(
      'enrichment لا يحدث عند incomingWins=false (الـ LWW يخسر، لكن max + enrich '
      'يجب أن يعملا لإصلاح بيانات ناقصة)',
      () {
        // Note: max() و enrichment يعملان مستقلين عن LWW.
        // الـ LWW يحكم فقط الحقول الوصفية العادية.
        final local = _baseLocal(
          id: 23,
          totalFils: 500_000,
          advancePaymentFils: 100_000,
        );
        final incoming = _baseIncoming(
          totalFils: 500_000,
          advancePaymentFils: 300_000,
          updatedAt: '2026-05-01T00:00:00Z', // أقدم من المحلي
          overrides: {
            'workShiftId': 50,
            'customerName': 'اسم incoming لا يفوز',
          },
        );

        final outcome = applyInvoiceMergePolicy(
          current: local,
          incoming: incoming,
          incomingWins: false,
          localCols: _kLocalCols,
        );

        expect(
          outcome.merged['advancePaymentFils'],
          300_000,
          reason: 'max يعمل حتى لو LWW خسر',
        );
        expect(
          outcome.merged['workShiftId'],
          50,
          reason: 'enrichment يعمل حتى لو LWW خسر',
        );
        expect(
          outcome.merged['customerName'],
          'عميل أول',
          reason: 'LWW عادي خسر — يبقى الاسم المحلي',
        );
      },
    );
  });

  group('applyInvoiceMergePolicy — LWW على الحقول الوصفية', () {
    test(
      'LWW: customerName + deliveryAddress تُحدَّث عندما incoming أحدث',
      () {
        final local = _baseLocal(
          id: 31,
          totalFils: 500_000,
          advancePaymentFils: 0,
          overrides: {
            'customerName': 'الاسم القديم',
            'deliveryAddress': 'العنوان القديم',
          },
        );
        final incoming = _baseIncoming(
          totalFils: 500_000,
          advancePaymentFils: 0,
          overrides: {
            'customerName': 'الاسم الجديد',
            'deliveryAddress': 'العنوان الجديد',
          },
        );

        final outcome = applyInvoiceMergePolicy(
          current: local,
          incoming: incoming,
          incomingWins: true,
          localCols: _kLocalCols,
        );

        expect(outcome.merged['customerName'], 'الاسم الجديد');
        expect(outcome.merged['deliveryAddress'], 'العنوان الجديد');
      },
    );

    test(
      'id (PK) و global_id لا يتغيران أبداً',
      () {
        final local = _baseLocal(
          id: 99,
          totalFils: 500_000,
          advancePaymentFils: 0,
        );
        final incoming = _baseIncoming(
          totalFils: 500_000,
          advancePaymentFils: 0,
          overrides: {'global_id': 'inv-gid-OTHER'},
        );

        final outcome = applyInvoiceMergePolicy(
          current: local,
          incoming: incoming,
          incomingWins: true,
          localCols: _kLocalCols,
        );

        expect(outcome.merged['id'], 99);
        expect(outcome.merged['global_id'], 'inv-gid-1');
      },
    );
  });

  group('applyInvoiceMergePolicy — تتبع التغيير', () {
    test(
      'changed=false عندما incoming مطابق للمحلي (لا حاجة لكتابة DB)',
      () {
        final local = _baseLocal(
          id: 41,
          totalFils: 500_000,
          advancePaymentFils: 100_000,
        );
        final incoming = _baseIncoming(
          totalFils: 500_000,
          advancePaymentFils: 100_000,
          updatedAt: '2026-06-01T10:00:00Z',
        );

        final outcome = applyInvoiceMergePolicy(
          current: local,
          incoming: incoming,
          incomingWins: false,
          localCols: _kLocalCols,
        );

        expect(outcome.changed, isFalse);
      },
    );

    test(
      'changed=true عندما incoming يُضيف advancePayment أعلى',
      () {
        final local = _baseLocal(
          id: 42,
          totalFils: 500_000,
          advancePaymentFils: 100_000,
        );
        final incoming = _baseIncoming(
          totalFils: 500_000,
          advancePaymentFils: 300_000,
        );

        final outcome = applyInvoiceMergePolicy(
          current: local,
          incoming: incoming,
          incomingWins: true,
          localCols: _kLocalCols,
        );

        expect(outcome.changed, isTrue);
        expect(outcome.merged['advancePaymentFils'], 300_000);
      },
    );
  });

  group('applyInvoiceMergePolicy — حالات الحدود', () {
    test(
      'العمود غير موجود في localCols ⇒ يُتجاهَل (لا يدخل في merged)',
      () {
        final reducedLocalCols = {..._kLocalCols}..remove('loyaltyPointsEarned');

        final local = _baseLocal(
          id: 51,
          totalFils: 500_000,
          advancePaymentFils: 0,
          overrides: {'loyaltyPointsEarned': 0},
        )..remove('loyaltyPointsEarned');

        final incoming = _baseIncoming(
          totalFils: 500_000,
          advancePaymentFils: 0,
          overrides: {'loyaltyPointsEarned': 500},
        );

        final outcome = applyInvoiceMergePolicy(
          current: local,
          incoming: incoming,
          incomingWins: true,
          localCols: reducedLocalCols,
        );

        expect(
          outcome.merged.containsKey('loyaltyPointsEarned'),
          isFalse,
          reason: 'عمود غير موجود في السكيما المحلية يُتجاهَل تماماً',
        );
      },
    );

    test(
      'advancePaymentFils كسلسلة نصية يُحوَّل ويُقارَن صحيحاً',
      () {
        final local = _baseLocal(
          id: 52,
          totalFils: 500_000,
          advancePaymentFils: 0,
          overrides: {'advancePaymentFils': '200000'},
        );
        final incoming = _baseIncoming(
          totalFils: 500_000,
          advancePaymentFils: 0,
          overrides: {'advancePaymentFils': '500000'},
        );

        final outcome = applyInvoiceMergePolicy(
          current: local,
          incoming: incoming,
          incomingWins: true,
          localCols: _kLocalCols,
        );

        expect(
          (outcome.merged['advancePaymentFils'] as Object?).toString(),
          '500000',
        );
      },
    );
  });
}
