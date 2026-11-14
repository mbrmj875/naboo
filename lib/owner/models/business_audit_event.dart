import 'package:flutter/material.dart';

import '../utils/business_audit_event_presentation.dart';

/// حدث تدقيق محلي — جدول `business_audit_events`.
class BusinessAuditEvent {
  const BusinessAuditEvent({
    required this.id,
    required this.tenantId,
    this.userId,
    this.username,
    required this.eventType,
    this.entityType,
    this.entityId,
    this.warehouseId,
    this.oldValueJson,
    this.newValueJson,
    required this.createdAt,
  });

  final int id;
  final int tenantId;
  final int? userId;
  final String? username;
  final String eventType;
  final String? entityType;
  final String? entityId;
  final int? warehouseId;
  final String? oldValueJson;
  final String? newValueJson;
  final DateTime createdAt;

  factory BusinessAuditEvent.fromMap(Map<String, Object?> row) {
    return BusinessAuditEvent(
      id: (row['id'] as num?)?.toInt() ?? 0,
      tenantId: (row['tenant_id'] as num?)?.toInt() ?? 0,
      userId: (row['user_id'] as num?)?.toInt(),
      username: row['username'] as String?,
      eventType: (row['event_type'] as String?) ?? '',
      entityType: row['entity_type'] as String?,
      entityId: row['entity_id'] as String?,
      warehouseId: (row['warehouse_id'] as num?)?.toInt(),
      oldValueJson: row['old_value_json'] as String?,
      newValueJson: row['new_value_json'] as String?,
      createdAt: DateTime.tryParse((row['created_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// عنوان عربي واضح — لا يعرض رمز event_type خاماً.
  String get labelAr => BusinessAuditEventPresentation.labelAr(this);

  /// تفاصيل مقروءة (اسم منتج، مبلغ، نوع السند…).
  String get detailAr => BusinessAuditEventPresentation.detailAr(this);

  String get actorLabelAr =>
      BusinessAuditEventPresentation.actorLabelAr(this);

  /// هل يُعرض في لوحة «تعديلات حساسة»؟
  bool get showInOwnerSensitivePanel =>
      BusinessAuditEventPresentation.showInOwnerSensitivePanel(this);

  /// تصنيف للفلترة في لوحة التدقيق (S5b).
  BusinessAuditCategory get category {
    switch (eventType) {
      case 'price_change':
        return BusinessAuditCategory.price;
      case 'product_create':
      case 'product_soft_delete':
        return BusinessAuditCategory.product;
      case 'stock_voucher_posted':
        return BusinessAuditCategory.stock;
      case 'debt_reminder_sent':
      case 'debt_payment_received':
      case 'debt_invoice_customer_linked':
        return BusinessAuditCategory.debt;
      case 'device_access_revoked_at_login':
      case 'device_revoked_on_signout':
      case 'device_owner_email_recovery':
      case 'device_orphan_self_recovery':
      case 'owner_emergency_shift_bypass':
      case 'owner_emergency_sync_bypass':
      case 'session_locked':
      case 'session_logout_cloud':
        return BusinessAuditCategory.security;
      default:
        return BusinessAuditCategory.other;
    }
  }

  /// حدث حساس — يُميَّز بصرياً في Audit Panel.
  bool get isSensitive {
    switch (eventType) {
      case 'price_change':
      case 'product_soft_delete':
      case 'stock_voucher_posted':
      case 'debt_payment_received':
      case 'owner_emergency_shift_bypass':
      case 'owner_emergency_sync_bypass':
      case 'device_access_revoked_at_login':
      case 'cloud_workspace_restore_failed':
        return true;
      default:
        return false;
    }
  }

  IconData get icon {
    switch (category) {
      case BusinessAuditCategory.price:
        return Icons.sell_outlined;
      case BusinessAuditCategory.product:
        return Icons.inventory_2_outlined;
      case BusinessAuditCategory.stock:
        return Icons.move_to_inbox_outlined;
      case BusinessAuditCategory.debt:
        return Icons.payments_outlined;
      case BusinessAuditCategory.security:
        return Icons.admin_panel_settings_outlined;
      case BusinessAuditCategory.other:
        return isSensitive ? Icons.shield_outlined : Icons.history;
    }
  }
}

enum BusinessAuditCategory {
  price,
  product,
  stock,
  debt,
  security,
  other,
}
