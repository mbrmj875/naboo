import 'dart:convert';

import '../../utils/iraqi_currency_format.dart';
import '../models/business_audit_event.dart';

/// عرض أحداث التدقيق للمالك — عناوين عربية وتفاصيل مقروءة (بدون رموز تقنية).
abstract final class BusinessAuditEventPresentation {
  BusinessAuditEventPresentation._();

  /// أحداث مزامنة/تشخيص — لا تُعرض في لوحة «تعديلات حساسة».
  static const diagnosticEventTypes = {
    'sync_pull_skipped',
    'sync_pull_blocked',
    'sync_push_blocked',
    'user_directory_reconciled',
  };

  static bool showInOwnerSensitivePanel(BusinessAuditEvent event) =>
      !diagnosticEventTypes.contains(event.eventType);

  static String labelAr(BusinessAuditEvent event) {
    switch (event.eventType) {
      case 'price_change':
        return 'تغيير سعر منتج';
      case 'product_create':
        return 'إضافة منتج جديد';
      case 'product_soft_delete':
        return 'تعطيل منتج';
      case 'debt_reminder_sent':
        return 'إرسال تذكير دين';
      case 'debt_payment_received':
        return 'تحصيل دفعة دين';
      case 'debt_invoice_customer_linked':
        return 'ربط فاتورة آجلة بعميل';
      case 'stock_voucher_posted':
        return 'ترحيل سند مخزني';
      case 'owner_emergency_shift_bypass':
        return 'تجاوز طوارئ — وردية';
      case 'owner_emergency_sync_bypass':
        return 'تجاوز طوارئ — مزامنة';
      case 'device_access_revoked_at_login':
        return 'رفض دخول جهاز غير مصرّح';
      case 'device_revoked_on_signout':
        return 'إلغاء تسجيل جهاز عند الخروج';
      case 'device_owner_email_recovery':
        return 'استرداد ملكية الجهاز بالبريد';
      case 'device_orphan_self_recovery':
        return 'استرداد جهاز يتيم تلقائياً';
      case 'cloud_workspace_restore_failed':
        return 'فشل استعادة مساحة العمل السحابية';
      case 'session_locked':
        return 'قفل الجلسة';
      case 'session_logout_cloud':
        return 'تسجيل خروج من السحابة';
      case 'sync_pull_skipped':
        return 'مزامنة: لا حاجة لسحب بيانات';
      case 'sync_pull_blocked':
        return 'مزامنة: تعذّر سحب البيانات';
      case 'sync_push_blocked':
        return 'مزامنة: تعذّر رفع البيانات';
      case 'user_directory_reconciled':
        return 'تحديث قائمة المستخدمين بعد المزامنة';
      default:
        return _humanizeSnakeCase(event.eventType);
    }
  }

  static String entityTypeLabelAr(String? entityType) {
    switch (entityType) {
      case 'product':
        return 'منتج';
      case 'customer':
        return 'عميل';
      case 'stock_voucher':
        return 'سند مخزني';
      case 'work_shift':
        return 'وردية';
      case 'device':
        return 'جهاز';
      case 'cloud_sync':
        return 'مزامنة';
      case 'invoice':
        return 'فاتورة';
      default:
        if (entityType == null || entityType.isEmpty) return '';
        return _humanizeSnakeCase(entityType);
    }
  }

  /// سطر تفصيلي — اسم منتج، مبالغ، نوع السند، إلخ.
  static String detailAr(BusinessAuditEvent event) {
    final oldMap = _decodeJson(event.oldValueJson);
    final newMap = _decodeJson(event.newValueJson);

    switch (event.eventType) {
      case 'price_change':
        return _priceChangeDetail(oldMap, newMap);
      case 'product_create':
        return _productNameDetail(newMap, fallbackId: event.entityId);
      case 'product_soft_delete':
        return _productNameDetail(oldMap, fallbackId: event.entityId);
      case 'debt_payment_received':
        return _debtPaymentDetail(oldMap, newMap, event.entityId);
      case 'debt_reminder_sent':
        return _entityRefDetail(event);
      case 'debt_invoice_customer_linked':
        return _entityRefDetail(event);
      case 'stock_voucher_posted':
        return _stockVoucherDetail(newMap, event.entityId);
      case 'owner_emergency_shift_bypass':
        return _emergencyShiftDetail(newMap);
      case 'owner_emergency_sync_bypass':
        return 'تم السماح بمزامنة طارئة من قبل المالك';
      case 'device_access_revoked_at_login':
      case 'device_revoked_on_signout':
      case 'device_owner_email_recovery':
      case 'device_orphan_self_recovery':
        return _deviceDetail(newMap, event.entityId);
      case 'cloud_workspace_restore_failed':
        return _stringField(newMap, 'error') ??
            _stringField(newMap, 'message') ??
            'تعذّر استعادة البيانات من السحابة';
      case 'session_locked':
        return 'تم قفل الجلسة الحالية';
      case 'session_logout_cloud':
        return 'تم إنهاء الجلسة والخروج من الحساب السحابي';
      case 'sync_pull_skipped':
        return 'البيانات المحلية محدّثة — لم يُنفَّذ سحب جديد';
      case 'sync_pull_blocked':
      case 'sync_push_blocked':
        return _syncBlockedDetail(newMap);
      case 'user_directory_reconciled':
        return _userDirectoryDetail(newMap, event.entityId);
      default:
        return _genericJsonDetail(oldMap, newMap, event);
    }
  }

  static String actorLabelAr(BusinessAuditEvent event) {
    final who = (event.username ?? '').trim();
    if (who.isNotEmpty) return who;
    if (event.userId != null) return 'موظف #${event.userId}';
    return 'النظام';
  }

  static String _priceChangeDetail(
    Map<String, dynamic>? oldMap,
    Map<String, dynamic>? newMap,
  ) {
    final name = _stringField(newMap, 'name') ?? _stringField(oldMap, 'name');
    final oldSell = _numField(oldMap, 'sellPrice');
    final newSell = _numField(newMap, 'sellPrice');
    final oldBuy = _numField(oldMap, 'buyPrice');
    final newBuy = _numField(newMap, 'buyPrice');

    final parts = <String>[];
    if (name != null && name.isNotEmpty) parts.add(name);

    if (oldSell != null && newSell != null && oldSell != newSell) {
      parts.add(
        'سعر البيع: ${_formatMoney(oldSell)} ← ${_formatMoney(newSell)}',
      );
    } else if (newSell != null) {
      parts.add('سعر البيع: ${_formatMoney(newSell)}');
    }

    if (oldBuy != null && newBuy != null && oldBuy != newBuy) {
      parts.add(
        'سعر الشراء: ${_formatMoney(oldBuy)} ← ${_formatMoney(newBuy)}',
      );
    }

    return parts.isEmpty ? 'تعديل أسعار منتج' : parts.join(' · ');
  }

  static String _productNameDetail(
    Map<String, dynamic>? map, {
    String? fallbackId,
  }) {
    final name = _stringField(map, 'name');
    if (name != null && name.isNotEmpty) return name;
    if (fallbackId != null && fallbackId.isNotEmpty) {
      return 'منتج #$fallbackId';
    }
    return '';
  }

  static String _debtPaymentDetail(
    Map<String, dynamic>? oldMap,
    Map<String, dynamic>? newMap,
    String? customerId,
  ) {
    final amount = _numField(newMap, 'amountApplied');
    final debtBefore = _numField(oldMap, 'debtBefore');
    final debtAfter = _numField(newMap, 'debtAfter');
    final parts = <String>[];
    if (customerId != null && customerId.isNotEmpty) {
      parts.add('عميل #$customerId');
    }
    if (amount != null) {
      parts.add('المبلغ المحصّل: ${_formatMoney(amount)}');
    }
    if (debtBefore != null && debtAfter != null) {
      parts.add(
        'الرصيد: ${_formatMoney(debtBefore)} ← ${_formatMoney(debtAfter)}',
      );
    }
    return parts.isEmpty ? 'تحصيل دفعة من عميل' : parts.join(' · ');
  }

  static String _stockVoucherDetail(
    Map<String, dynamic>? map,
    String? voucherId,
  ) {
    final type = _stringField(map, 'voucherType');
    final lines = _numField(map, 'lineCount')?.round();
    final typeAr = switch (type) {
      'in' => 'إدخال مخزون',
      'out' => 'إخراج مخزون',
      'transfer' => 'تحويل بين مخازن',
      _ => type != null && type.isNotEmpty ? _humanizeSnakeCase(type) : 'سند',
    };
    final parts = <String>[typeAr];
    if (lines != null && lines > 0) parts.add('$lines أصناف');
    if (voucherId != null && voucherId.isNotEmpty) {
      parts.add('سند #$voucherId');
    }
    return parts.join(' · ');
  }

  static String _emergencyShiftDetail(Map<String, dynamic>? map) {
    final action = _stringField(map, 'action');
    final staff = _stringField(map, 'shiftStaffName');
    final parts = <String>[];
    if (action != null && action.isNotEmpty) parts.add(action);
    if (staff != null && staff.isNotEmpty) parts.add('وردية: $staff');
    return parts.isEmpty
        ? 'تجاوز قيود الوردية بموافقة صاحب العمل'
        : parts.join(' · ');
  }

  static String _deviceDetail(Map<String, dynamic>? map, String? entityId) {
    final device = _stringField(map, 'deviceLabel') ??
        _stringField(map, 'deviceId') ??
        entityId;
    if (device != null && device.isNotEmpty) return 'الجهاز: $device';
    return 'عملية على جهاز مسجّل';
  }

  static String _syncBlockedDetail(Map<String, dynamic>? map) {
    final err = _stringField(map, 'error');
    if (err != null && err.isNotEmpty && !_looksLikeCode(err)) {
      return err;
    }
    return 'تعذّرت المزامنة — راجع الاتصال أو سجّل الدخول';
  }

  static String _userDirectoryDetail(
    Map<String, dynamic>? map,
    String? source,
  ) {
    final count = _numField(map, 'gateUserCount')?.round();
    final src = _sourceLabelAr(source ?? _stringField(map, 'source'));
    final parts = <String>[src];
    if (count != null) parts.add('$count مستخدم نشط');
    return parts.join(' · ');
  }

  static String _entityRefDetail(BusinessAuditEvent event) {
    final entity = entityTypeLabelAr(event.entityType);
    final id = event.entityId;
    if (entity.isNotEmpty && id != null && id.isNotEmpty) {
      return '$entity #$id';
    }
    if (id != null && id.isNotEmpty) return '#$id';
    return '';
  }

  static String _genericJsonDetail(
    Map<String, dynamic>? oldMap,
    Map<String, dynamic>? newMap,
    BusinessAuditEvent event,
  ) {
    for (final map in [newMap, oldMap]) {
      if (map == null) continue;
      for (final key in ['name', 'label', 'message', 'action', 'title']) {
        final v = _stringField(map, key);
        if (v != null && v.isNotEmpty && !_looksLikeCode(v)) return v;
      }
    }
    return _entityRefDetail(event);
  }

  static String _sourceLabelAr(String? source) {
    switch (source) {
      case 'cloud_login':
      case 'login':
        return 'بعد تسجيل الدخول';
      case 'cloud_restore':
      case 'restore':
        return 'بعد استعادة النسخة السحابية';
      case 'sync_pull':
        return 'بعد سحب المزامنة';
      default:
        if (source == null || source.isEmpty) {
          return 'بعد مزامنة الحساب';
        }
        if (_looksLikeCode(source)) return 'بعد مزامنة الحساب';
        return source;
    }
  }

  static Map<String, dynamic>? _decodeJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  static String? _stringField(Map<String, dynamic>? map, String key) {
    final v = map?[key];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static num? _numField(Map<String, dynamic>? map, String key) {
    final v = map?[key];
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '');
  }

  static String _formatMoney(num value) {
    return '${IraqiCurrencyFormat.formatInt(value)} د.ع';
  }

  static bool _looksLikeCode(String value) {
    if (value.contains('@')) return false;
    if (value.contains(' ')) return false;
    return RegExp(r'^[a-z0-9_]+$').hasMatch(value);
  }

  static String _humanizeSnakeCase(String raw) {
    if (raw.isEmpty) return 'حدث غير معروف';
    return raw
        .split('_')
        .where((p) => p.isNotEmpty)
        .map((p) {
          if (p.length <= 3) return p.toUpperCase();
          return '${p[0].toUpperCase()}${p.substring(1)}';
        })
        .join(' ');
  }
}
