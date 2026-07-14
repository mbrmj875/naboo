/*
  PR-5 — حماية merge لـ invoice_items + installment_plans + installments.

  المرجع: docs/specs/roadmap_phase2_execution_v1.md §4 PR-5

  السياسات:
    • invoice_items: price/total/unitCost/quantity مجمدة. productName LWW.
    • installment_plans: totalAmount/numberOfInstallments مجمدة.
      paidAmount = max(local, incoming). customerName LWW.
    • installments: amount/dueDate/planId مجمدة.
      paid monotonic (local || incoming). paidDate enrichment.
*/

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/invoice_merge_policy.dart';

void main() {
  // ──────────────────────────────────────────────────────────────────────
  group('PR-5 — invoice_items merge protection', () {
    const localCols = {
      'id',
      'global_id',
      'invoiceId',
      'productId',
      'productName',
      'quantity',
      'price',
      'priceFils',
      'total',
      'totalFils',
      'unitCost',
      'unitCostFils',
      'updatedAt',
    };

    test('T1: price محلي مجمد — incoming أحدث لا يستبدله', () {
      final local = <String, Object?>{
        'id': 1,
        'global_id': 'item-1',
        'invoiceId': 10,
        'productName': 'منتج',
        'quantity': 2,
        'priceFils': 5_000,
        'totalFils': 10_000,
        'updatedAt': '2026-05-01T00:00:00Z',
      };
      final incoming = <String, Object?>{
        'global_id': 'item-1',
        'productName': 'منتج',
        'quantity': 2,
        'priceFils': 4_000, // أقل
        'totalFils': 8_000,
        'updatedAt': '2026-06-01T00:00:00Z',
      };

      final out = applyInvoiceItemMergePolicy(
        current: local,
        incoming: incoming,
        incomingWins: true,
        localCols: localCols,
      );

      expect(out.merged['priceFils'], 5_000);
      expect(out.merged['totalFils'], 10_000);
      expect(out.merged['quantity'], 2);
    });

    test('T2: productName LWW يتحدث (display فقط)', () {
      final local = <String, Object?>{
        'id': 2,
        'global_id': 'item-2',
        'productName': 'الاسم القديم',
        'quantity': 1,
        'priceFils': 1_000,
        'updatedAt': '2026-05-01T00:00:00Z',
      };
      final incoming = <String, Object?>{
        'global_id': 'item-2',
        'productName': 'الاسم الجديد',
        'quantity': 1,
        'priceFils': 1_000,
        'updatedAt': '2026-06-01T00:00:00Z',
      };

      final out = applyInvoiceItemMergePolicy(
        current: local,
        incoming: incoming,
        incomingWins: true,
        localCols: localCols,
      );

      expect(out.merged['productName'], 'الاسم الجديد');
    });

    test('T3: invoiceId/productId مفاتيح ربط ⇒ لا تتغير', () {
      final local = <String, Object?>{
        'id': 3,
        'global_id': 'item-3',
        'invoiceId': 10,
        'productId': 7,
        'productName': 'م',
        'quantity': 1,
        'priceFils': 100,
        'updatedAt': '2026-05-01T00:00:00Z',
      };
      final incoming = <String, Object?>{
        'global_id': 'item-3',
        'invoiceId': 99, // محاولة تغيير الربط
        'productId': 50,
        'productName': 'م',
        'quantity': 1,
        'priceFils': 100,
        'updatedAt': '2026-06-01T00:00:00Z',
      };

      final out = applyInvoiceItemMergePolicy(
        current: local,
        incoming: incoming,
        incomingWins: true,
        localCols: localCols,
      );

      expect(out.merged['invoiceId'], 10);
      expect(out.merged['productId'], 7);
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  group('PR-5 — installment_plans merge protection', () {
    const localCols = {
      'id',
      'global_id',
      'invoiceId',
      'customerName',
      'customerId',
      'totalAmount',
      'totalAmountFils',
      'paidAmount',
      'paidAmountFils',
      'numberOfInstallments',
      'updatedAt',
    };

    test('T1: paidAmountFils محلي > incoming + newer ⇒ يبقى المحلي (max)', () {
      final local = <String, Object?>{
        'id': 1,
        'global_id': 'plan-1',
        'totalAmountFils': 5_000_000,
        'paidAmountFils': 2_000_000,
        'paidAmount': 2000.0,
        'totalAmount': 5000.0,
        'numberOfInstallments': 5,
        'updatedAt': '2026-05-01T00:00:00Z',
      };
      final incoming = <String, Object?>{
        'global_id': 'plan-1',
        'totalAmountFils': 5_000_000,
        'paidAmountFils': 1_000_000, // أقل من المحلي
        'paidAmount': 1000.0,
        'totalAmount': 5000.0,
        'numberOfInstallments': 5,
        'updatedAt': '2026-06-01T00:00:00Z',
      };

      final out = applyInstallmentPlanMergePolicy(
        current: local,
        incoming: incoming,
        incomingWins: true,
        localCols: localCols,
      );

      expect(out.merged['paidAmountFils'], 2_000_000);
    });

    test('T2: incoming paidAmountFils أعلى ⇒ يدخل', () {
      final local = <String, Object?>{
        'id': 2,
        'global_id': 'plan-2',
        'totalAmountFils': 5_000_000,
        'paidAmountFils': 1_000_000,
        'totalAmount': 5000.0,
        'paidAmount': 1000.0,
        'numberOfInstallments': 5,
        'updatedAt': '2026-05-01T00:00:00Z',
      };
      final incoming = <String, Object?>{
        'global_id': 'plan-2',
        'totalAmountFils': 5_000_000,
        'paidAmountFils': 3_000_000,
        'paidAmount': 3000.0,
        'totalAmount': 5000.0,
        'numberOfInstallments': 5,
        'updatedAt': '2026-06-01T00:00:00Z',
      };

      final out = applyInstallmentPlanMergePolicy(
        current: local,
        incoming: incoming,
        incomingWins: true,
        localCols: localCols,
      );

      expect(out.merged['paidAmountFils'], 3_000_000);
    });

    test('T3: totalAmount مجمد — incoming يحاول رفعه ⇒ يُرفض', () {
      final local = <String, Object?>{
        'id': 3,
        'global_id': 'plan-3',
        'totalAmountFils': 2_000_000,
        'paidAmountFils': 500_000,
        'totalAmount': 2000.0,
        'paidAmount': 500.0,
        'numberOfInstallments': 4,
        'updatedAt': '2026-05-01T00:00:00Z',
      };
      final incoming = <String, Object?>{
        'global_id': 'plan-3',
        'totalAmountFils': 3_000_000, // محاولة رفع الإجمالي
        'paidAmountFils': 500_000,
        'totalAmount': 3000.0,
        'paidAmount': 500.0,
        'numberOfInstallments': 6, // ومحاولة تغيير عدد الأقساط
        'updatedAt': '2026-06-01T00:00:00Z',
      };

      final out = applyInstallmentPlanMergePolicy(
        current: local,
        incoming: incoming,
        incomingWins: true,
        localCols: localCols,
      );

      expect(out.merged['totalAmountFils'], 2_000_000);
      expect(out.merged['numberOfInstallments'], 4);
    });

    test('T4: max يعمل حتى لو LWW خسر (incomingWins=false)', () {
      final local = <String, Object?>{
        'id': 4,
        'global_id': 'plan-4',
        'totalAmountFils': 5_000_000,
        'paidAmountFils': 1_000_000,
        'customerName': 'محلي',
        'updatedAt': '2026-06-01T00:00:00Z',
      };
      final incoming = <String, Object?>{
        'global_id': 'plan-4',
        'totalAmountFils': 5_000_000,
        'paidAmountFils': 2_500_000,
        'customerName': 'اسم incoming لا يفوز',
        'updatedAt': '2026-05-01T00:00:00Z',
      };

      final out = applyInstallmentPlanMergePolicy(
        current: local,
        incoming: incoming,
        incomingWins: false,
        localCols: localCols,
      );

      expect(out.merged['paidAmountFils'], 2_500_000); // max ينجح
      expect(out.merged['customerName'], 'محلي'); // LWW خسر
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  group('PR-5 — installments merge protection', () {
    const localCols = {
      'id',
      'global_id',
      'planId',
      'dueDate',
      'amount',
      'amountFils',
      'paid',
      'paidDate',
      'updatedAt',
    };

    test('T1: amount مجمد — incoming لا يستبدله', () {
      final local = <String, Object?>{
        'id': 1,
        'global_id': 'inst-1',
        'planId': 10,
        'dueDate': '2026-07-01',
        'amountFils': 250_000,
        'amount': 250.0,
        'paid': 0,
        'updatedAt': '2026-05-01T00:00:00Z',
      };
      final incoming = <String, Object?>{
        'global_id': 'inst-1',
        'planId': 10,
        'dueDate': '2026-07-01',
        'amountFils': 300_000,
        'amount': 300.0,
        'paid': 0,
        'updatedAt': '2026-06-01T00:00:00Z',
      };

      final out = applyInstallmentMergePolicy(
        current: local,
        incoming: incoming,
        incomingWins: true,
        localCols: localCols,
      );

      expect(out.merged['amountFils'], 250_000);
    });

    test('T2: paid monotonic — local=1, incoming=0 (newer) ⇒ يبقى 1', () {
      final local = <String, Object?>{
        'id': 2,
        'global_id': 'inst-2',
        'planId': 10,
        'amountFils': 250_000,
        'paid': 1,
        'paidDate': '2026-05-15',
        'updatedAt': '2026-05-15T00:00:00Z',
      };
      final incoming = <String, Object?>{
        'global_id': 'inst-2',
        'planId': 10,
        'amountFils': 250_000,
        'paid': 0,
        'paidDate': null,
        'updatedAt': '2026-06-01T00:00:00Z',
      };

      final out = applyInstallmentMergePolicy(
        current: local,
        incoming: incoming,
        incomingWins: true,
        localCols: localCols,
      );

      expect(out.merged['paid'], 1);
    });

    test('T3: paid monotonic — local=0, incoming=1 ⇒ يصبح 1', () {
      final local = <String, Object?>{
        'id': 3,
        'global_id': 'inst-3',
        'planId': 10,
        'amountFils': 250_000,
        'paid': 0,
        'paidDate': null,
        'updatedAt': '2026-05-01T00:00:00Z',
      };
      final incoming = <String, Object?>{
        'global_id': 'inst-3',
        'planId': 10,
        'amountFils': 250_000,
        'paid': 1,
        'paidDate': '2026-06-01',
        'updatedAt': '2026-06-01T00:00:00Z',
      };

      final out = applyInstallmentMergePolicy(
        current: local,
        incoming: incoming,
        incomingWins: true,
        localCols: localCols,
      );

      expect(out.merged['paid'], 1);
      expect(out.merged['paidDate'], '2026-06-01');
    });

    test(
      'T4: paidDate enrichment — local null + incoming موجود ⇒ يُملأ '
      'حتى لو LWW خسر',
      () {
        final local = <String, Object?>{
          'id': 4,
          'global_id': 'inst-4',
          'planId': 10,
          'amountFils': 250_000,
          'paid': 1,
          'paidDate': null,
          'updatedAt': '2026-06-01T00:00:00Z',
        };
        final incoming = <String, Object?>{
          'global_id': 'inst-4',
          'planId': 10,
          'amountFils': 250_000,
          'paid': 1,
          'paidDate': '2026-05-15',
          'updatedAt': '2026-05-01T00:00:00Z',
        };

        final out = applyInstallmentMergePolicy(
          current: local,
          incoming: incoming,
          incomingWins: false,
          localCols: localCols,
        );

        expect(out.merged['paidDate'], '2026-05-15');
      },
    );

    test('T5: dueDate مجمد', () {
      final local = <String, Object?>{
        'id': 5,
        'global_id': 'inst-5',
        'planId': 10,
        'dueDate': '2026-07-01',
        'amountFils': 250_000,
        'paid': 0,
        'updatedAt': '2026-05-01T00:00:00Z',
      };
      final incoming = <String, Object?>{
        'global_id': 'inst-5',
        'planId': 10,
        'dueDate': '2026-08-01', // محاولة تأجيل
        'amountFils': 250_000,
        'paid': 0,
        'updatedAt': '2026-06-01T00:00:00Z',
      };

      final out = applyInstallmentMergePolicy(
        current: local,
        incoming: incoming,
        incomingWins: true,
        localCols: localCols,
      );

      expect(out.merged['dueDate'], '2026-07-01');
    });
  });
}
