import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/business_audit_event.dart';
import 'package:naboo/owner/utils/business_audit_event_presentation.dart';

void main() {
  final at = DateTime(2026, 6, 2);

  group('BusinessAuditEvent S5b metadata', () {
    test('price_change is sensitive price category', () {
      final e = BusinessAuditEvent(
        id: 1,
        tenantId: 1,
        eventType: 'price_change',
        createdAt: at,
      );
      expect(e.category, BusinessAuditCategory.price);
      expect(e.isSensitive, isTrue);
    });

    test('product_create is product not sensitive', () {
      final e = BusinessAuditEvent(
        id: 2,
        tenantId: 1,
        eventType: 'product_create',
        createdAt: at,
      );
      expect(e.category, BusinessAuditCategory.product);
      expect(e.isSensitive, isFalse);
    });

    test('debt_payment_received is sensitive debt', () {
      final e = BusinessAuditEvent(
        id: 3,
        tenantId: 1,
        eventType: 'debt_payment_received',
        createdAt: at,
      );
      expect(e.category, BusinessAuditCategory.debt);
      expect(e.isSensitive, isTrue);
    });
  });

  group('BusinessAuditEventPresentation', () {
    test('sync_pull_skipped has Arabic label not raw code', () {
      final e = BusinessAuditEvent(
        id: 4,
        tenantId: 1,
        eventType: 'sync_pull_skipped',
        entityType: 'cloud_sync',
        createdAt: at,
      );
      expect(e.labelAr, isNot('sync_pull_skipped'));
      expect(e.labelAr, contains('مزامنة'));
      expect(e.showInOwnerSensitivePanel, isFalse);
    });

    test('user_directory_reconciled hidden from owner panel', () {
      final e = BusinessAuditEvent(
        id: 5,
        tenantId: 1,
        eventType: 'user_directory_reconciled',
        entityType: 'cloud_sync',
        entityId: 'cloud_login',
        newValueJson: '{"source":"cloud_login","gateUserCount":3}',
        createdAt: at,
      );
      expect(e.showInOwnerSensitivePanel, isFalse);
      expect(e.labelAr, contains('مستخدم'));
    });

    test('product_soft_delete shows product name in detail', () {
      final e = BusinessAuditEvent(
        id: 6,
        tenantId: 1,
        eventType: 'product_soft_delete',
        entityType: 'product',
        entityId: '42',
        oldValueJson: '{"name":"زيت 5W30"}',
        createdAt: at,
      );
      expect(e.labelAr, 'تعطيل منتج');
      expect(e.detailAr, 'زيت 5W30');
    });

    test('price_change shows formatted price delta', () {
      final e = BusinessAuditEvent(
        id: 7,
        tenantId: 1,
        eventType: 'price_change',
        oldValueJson: '{"name":"فلتر","sellPrice":10000}',
        newValueJson: '{"name":"فلتر","sellPrice":12500}',
        createdAt: at,
      );
      expect(e.detailAr, contains('فلتر'));
      expect(e.detailAr, contains('10,000'));
      expect(e.detailAr, contains('12,500'));
    });

    test('diagnostic types set is complete', () {
      expect(
        BusinessAuditEventPresentation.diagnosticEventTypes,
        contains('sync_pull_skipped'),
      );
    });
  });
}
