import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/database_helper.dart';
import '../services/system_notification_service.dart';
import '../services/tenant_context_service.dart';

/// مفاتيح تفضيلات الإشعارات (تُحفظ في [SharedPreferences]).
abstract final class NotificationPrefs {
  static const String lowStock = 'notif_enable_low_stock';
  static const String negativeStockSale = 'notif_enable_negative_stock_sale';
  static const String expiry = 'notif_enable_expiry';
  /// عدد الأيام الافتراضي قبل تاريخ الانتهاء لإظهار تنبيه «قرب الصلاحية» (عند عدم ضبطه لكل منتج).
  static const String defaultExpiryAlertDays = 'notif_default_expiry_alert_days';
  static const String installment = 'notif_enable_installment';
  /// ديون العملاء (رصيد مدين في بطاقة العميل).
  static const String customerDebt = 'notif_enable_customer_debt';
  /// إشعار عند حفظ بيع بالدين أو بالتقسيط (نقطة البيع).
  static const String financedSale = 'notif_enable_financed_sale';
  static const String returns = 'notif_enable_returns';
  static const String dailySummary = 'notif_enable_daily_summary';
  /// فتح وإغلاق الوردية (مبالغ، موظف الوردية) في لوحة الإشعارات.
  static const String shiftLifecycle = 'notif_enable_shift_lifecycle';
  static const String readKeys = 'notif_read_keys';
}

/// أحداث «بيع أدى لرصيد سالب» — تُحمَّل في [NotificationProvider.refresh].
abstract final class NotificationStoredKeys {
  NotificationStoredKeys._();

  static const String negativeStockEvents = 'notif_negative_stock_events_v1';
  static const String shiftLifecycleEvents = 'notif_shift_lifecycle_v1';
  static const String financedSaleEvents = 'notif_financed_sale_events_v1';
}

enum NotificationType {
  installmentDue,
  installmentLate,
  lowInventory,
  negativeStockSale,
  expirySoon,
  expiredProduct,
  saleReturn,
  newReport,
  cashAlert,
  /// رصيد مدين على عميل (آجل غير المقسّط).
  customerDebt,
  /// فاتورة آجل تجاوزت أيام «تحذير العمر» في إعدادات الدين.
  debtInvoiceAged,
  /// مجموع ديون آجل العميل وصل أو تجاوز السقف في إعدادات الدين.
  debtCustomerCeiling,
  /// متبقٍ لفاتورة آجل واحدة وصل أو تجاوز السقف في إعدادات الدين.
  debtInvoiceCeiling,
  /// تم تسجيل بيع بالدين أو بالتقسيط من شاشة البيع.
  financedSale,
  systemInfo,
}

class AppNotification {
  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final DateTime time;
  final bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.time,
    this.isRead = false,
  });

  IconData get icon {
    switch (type) {
      case NotificationType.installmentDue:
        return Icons.schedule;
      case NotificationType.installmentLate:
        return Icons.warning_amber_rounded;
      case NotificationType.lowInventory:
        return Icons.inventory_2_outlined;
      case NotificationType.negativeStockSale:
        return Icons.trending_down_rounded;
      case NotificationType.expirySoon:
        return Icons.event_note_outlined;
      case NotificationType.expiredProduct:
        return Icons.event_busy_rounded;
      case NotificationType.saleReturn:
        return Icons.assignment_return_outlined;
      case NotificationType.newReport:
        return Icons.bar_chart;
      case NotificationType.cashAlert:
        return Icons.account_balance_wallet_outlined;
      case NotificationType.customerDebt:
        return Icons.person_outline_rounded;
      case NotificationType.debtInvoiceAged:
        return Icons.history_toggle_off_rounded;
      case NotificationType.debtCustomerCeiling:
        return Icons.groups_outlined;
      case NotificationType.debtInvoiceCeiling:
        return Icons.receipt_long_outlined;
      case NotificationType.financedSale:
        return Icons.point_of_sale_outlined;
      case NotificationType.systemInfo:
        return Icons.info_outline;
    }
  }

  Color get color {
    switch (type) {
      case NotificationType.installmentDue:
        return const Color(0xFF3B82F6);
      case NotificationType.installmentLate:
        return const Color(0xFFEF4444);
      case NotificationType.lowInventory:
        return const Color(0xFFF97316);
      case NotificationType.negativeStockSale:
        return const Color(0xFFDC2626);
      case NotificationType.expirySoon:
        return const Color(0xFFF59E0B);
      case NotificationType.expiredProduct:
        return const Color(0xFFDC2626);
      case NotificationType.saleReturn:
        return const Color(0xFF0D9488);
      case NotificationType.newReport:
        return const Color(0xFF8B5CF6);
      case NotificationType.cashAlert:
        return const Color(0xFF10B981);
      case NotificationType.customerDebt:
        return const Color(0xFF0EA5E9);
      case NotificationType.debtInvoiceAged:
        return const Color(0xFFF59E0B);
      case NotificationType.debtCustomerCeiling:
        return const Color(0xFFEA580C);
      case NotificationType.debtInvoiceCeiling:
        return const Color(0xFFDB2777);
      case NotificationType.financedSale:
        return const Color(0xFF6366F1);
      case NotificationType.systemInfo:
        return const Color(0xFF6B7280);
    }
  }

  String get typeLabel {
    switch (type) {
      case NotificationType.installmentDue:
        return 'قسط مستحق';
      case NotificationType.installmentLate:
        return 'قسط متأخر';
      case NotificationType.lowInventory:
        return 'مخزون';
      case NotificationType.negativeStockSale:
        return 'بيع سالب';
      case NotificationType.expirySoon:
        return 'همس الصلاحية';
      case NotificationType.expiredProduct:
        return 'أجل الحفظ';
      case NotificationType.saleReturn:
        return 'مرتجع';
      case NotificationType.newReport:
        return 'ملخص';
      case NotificationType.cashAlert:
        return 'صندوق';
      case NotificationType.customerDebt:
        return 'دين عميل';
      case NotificationType.debtInvoiceAged:
        return 'عمر دين';
      case NotificationType.debtCustomerCeiling:
        return 'سقف عميل';
      case NotificationType.debtInvoiceCeiling:
        return 'سقف فاتورة';
      case NotificationType.financedSale:
        return 'بيع مموّل';
      case NotificationType.systemInfo:
        return 'النظام';
    }
  }

  String get timeAgo {
    final now = DateTime.now();
    var diff = now.difference(time);
    if (diff.isNegative) {
      return DateFormat('dd/MM/yyyy HH:mm', 'ar').format(time);
    }
    if (diff.inSeconds < 45) return 'الآن';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      if (m <= 1) return 'منذ دقيقة';
      if (m == 2) return 'منذ دقيقتين';
      return 'منذ $m دقيقة';
    }

    final startToday = DateTime(now.year, now.month, now.day);
    final startThat = DateTime(time.year, time.month, time.day);
    final calendarDays = startToday.difference(startThat).inDays;

    if (calendarDays <= 0) {
      final h = diff.inHours;
      if (h <= 1) return 'منذ ساعة تقريباً';
      if (h == 2) return 'منذ ساعتين';
      return 'منذ $h ساعة';
    }
    if (calendarDays == 1) {
      return 'أمس ${DateFormat('HH:mm', 'ar').format(time)}';
    }
    if (calendarDays == 2) return 'منذ يومين';
    if (calendarDays < 7) return 'منذ $calendarDays أيام';
    if (time.year == now.year) {
      return DateFormat('d MMM', 'ar').format(time);
    }
    return DateFormat('yyyy/MM/dd', 'ar').format(time);
  }
}

/// يبني الإشعارات من [DatabaseHelper] ويحترم تفضيلات المستخدم.
class NotificationProvider extends ChangeNotifier {
  NotificationProvider() {
    Future.microtask(() => refresh());
  }

  final DatabaseHelper _db = DatabaseHelper();
  final List<AppNotification> _notifications = [];
  Set<String> _readIds = {};
  bool _loading = false;
  String? _lastError;

  /// بعد أول [refresh]: لا نُكرّر نفس [id] في شريط الجهاز.
  /// عند أول تشغيل: نُظهر حتى [_maxPrimeTray] تنبيهات مهمة (مخزون، صلاحية، أقساط، ديون) دون تكرار لاحقاً.
  bool _systemTrayPrimed = false;
  final Set<String> _systemTrayShownIds = {};
  static const int _maxPrimeTray = 20;
  static const Set<NotificationType> _primeTrayTypes = {
    NotificationType.lowInventory,
    NotificationType.expirySoon,
    NotificationType.expiredProduct,
    NotificationType.installmentLate,
    NotificationType.installmentDue,
    NotificationType.customerDebt,
    NotificationType.debtInvoiceAged,
    NotificationType.debtCustomerCeiling,
    NotificationType.debtInvoiceCeiling,
    NotificationType.financedSale,
  };

  List<AppNotification> get all => List.unmodifiable(_notifications);
  bool get isLoading => _loading;
  String? get lastError => _lastError;

  List<AppNotification> get unread =>
      _notifications.where((n) => !n.isRead).toList();

  int get unreadCount => unread.length;

  List<AppNotification> byType(NotificationType type) =>
      _notifications.where((n) => n.type == type).toList();

  static Future<bool> _prefBool(String key, {bool defaultValue = true}) async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(key) ?? defaultValue;
  }

  static Future<int> _prefInt(String key, {int defaultValue = 14}) async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(key) ?? defaultValue;
  }

  bool get _supportsLocalDeviceTray =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  void _emitNewToAndroidSystemTray(List<AppNotification> built) {
    if (!_supportsLocalDeviceTray) return;
    if (!_systemTrayPrimed) {
      _systemTrayPrimed = true;
      _systemTrayShownIds.clear();
      var primeShown = 0;
      for (final n in built) {
        final showPrime = _primeTrayTypes.contains(n.type) &&
            !n.isRead &&
            primeShown < _maxPrimeTray;
        if (showPrime) {
          primeShown++;
          _systemTrayShownIds.add(n.id);
          unawaited(
            SystemNotificationService.instance.show(
              id: n.id,
              title: n.title,
              body: n.body,
              summaryText: n.typeLabel,
            ),
          );
        } else {
          _systemTrayShownIds.add(n.id);
        }
      }
      return;
    }
    for (final n in built) {
      if (n.isRead) continue;
      if (_systemTrayShownIds.contains(n.id)) continue;
      _systemTrayShownIds.add(n.id);
      unawaited(
        SystemNotificationService.instance.show(
          id: n.id,
          title: n.title,
          body: n.body,
          summaryText: n.typeLabel,
        ),
      );
    }
  }

  Future<void> _loadReadIds() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(NotificationPrefs.readKeys);
    if (raw == null || raw.isEmpty) {
      _readIds = {};
      return;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _readIds = list.map((e) => e.toString()).toSet();
    } catch (_) {
      _readIds = {};
    }
    if (_readIds.length > 400) {
      final list = _readIds.toList();
      _readIds = list.skip(list.length - 400).toSet();
    }
  }

  Future<void> _persistReadIds() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      NotificationPrefs.readKeys,
      jsonEncode(_readIds.toList()),
    );
  }

  /// يزيل من التخزين أحداث «بيع سالب» لم يعد أي صنف فيها برصيد سالب (بعد إدخال وارد).
  Future<List<dynamic>> _pruneNegativeStockEventsIfResolved(
    List<dynamic> list,
  ) async {
    final maps = <Map<String, dynamic>>[];
    for (final e in list) {
      if (e is! Map) continue;
      maps.add(Map<String, dynamic>.from(e));
    }
    final allIds = <int>{};
    for (final m in maps) {
      final lines = m['lines'];
      if (lines is! List) continue;
      for (final L in lines) {
        if (L is! Map) continue;
        final pid =
            (Map<String, dynamic>.from(L)['productId'] as num?)?.toInt();
        if (pid != null) allIds.add(pid);
      }
    }
    if (allIds.isEmpty) return list;
    final qtyMap = await _db.getProductQtyMap(allIds);
    final kept = <dynamic>[];
    for (final m in maps) {
      final lines = m['lines'];
      if (lines is! List) {
        kept.add(m);
        continue;
      }
      var anyStillNegative = false;
      for (final L in lines) {
        if (L is! Map) continue;
        final lm = Map<String, dynamic>.from(L);
        final pid = (lm['productId'] as num?)?.toInt();
        if (pid == null) {
          anyStillNegative = true;
          break;
        }
        final q = qtyMap[pid] ?? 0.0;
        if (q < -1e-9) {
          anyStillNegative = true;
          break;
        }
      }
      if (anyStillNegative) kept.add(m);
    }
    return kept;
  }

  Future<void> _appendNegativeStockSaleNotifications(
    List<AppNotification> built, {
    required NumberFormat numFmt,
    required DateFormat dateTimeFmt,
  }) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(NotificationStoredKeys.negativeStockEvents);
    if (raw == null || raw.trim().isEmpty) return;
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return;
    }
    final pruned = await _pruneNegativeStockEventsIfResolved(list);
    if (pruned.length != list.length) {
      await p.setString(
        NotificationStoredKeys.negativeStockEvents,
        jsonEncode(pruned),
      );
    }
    for (final e in pruned) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final id = m['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final invoiceId = (m['invoiceId'] as num?)?.toInt();
      final staff = (m['staff'] as String?)?.trim() ?? '';
      final customer = (m['customer'] as String?)?.trim() ?? '';
      final tRaw = m['t']?.toString();
      final at = DateTime.tryParse(tRaw ?? '') ?? DateTime.now();
      final lines = m['lines'];
      final buf = StringBuffer()
        ..writeln('فاتورة بيع #${invoiceId ?? '-'} — ${dateTimeFmt.format(at)}')
        ..writeln('البائع: ${staff.isEmpty ? '—' : staff}')
        ..writeln('العميل: ${customer.isEmpty ? 'بدون اسم' : customer}')
        ..writeln('────────');
      if (lines is List) {
        for (final L in lines) {
          if (L is! Map) continue;
          final lm = Map<String, dynamic>.from(L);
          final name = (lm['name'] as String?)?.trim() ?? 'صنف';
          final pid = (lm['productId'] as num?)?.toInt();
          final qty = (lm['qtySold'] as num?)?.round() ?? 0;
          final before = (lm['before'] as num?)?.toDouble() ?? 0;
          final after = (lm['after'] as num?)?.toDouble() ?? 0;
          buf.writeln('• $name${pid != null ? ' — مُعرّف #$pid' : ''}');
          buf.writeln(
            '  مُباع في الفاتورة: ${numFmt.format(qty)} — الرصيد قبل: ${numFmt.format(before)} → بعد: ${numFmt.format(after)}',
          );
        }
      }
      built.add(
        AppNotification(
          id: id,
          title: 'بيع أدى إلى رصيد سالب',
          body: buf.toString().trimRight(),
          type: NotificationType.negativeStockSale,
          time: at,
          isRead: _readIds.contains(id),
        ),
      );
    }
  }

  /// يُسجّل حدثاً يظهر في [refresh] (يُحفظ محلياً مع الفاتورة والبائع والأصناف).
  /// يُسجّل حدث فتح أو إغلاق وردية ليظهر بعد [refresh] في لوحة الإشعارات.
  Future<void> recordShiftLifecycleEvent({
    required bool isClose,
    required int shiftId,
    required String title,
    required String body,
  }) async {
    final on = await _prefBool(
      NotificationPrefs.shiftLifecycle,
      defaultValue: true,
    );
    if (!on) return;
    final p = await SharedPreferences.getInstance();
    final id =
        'shift_${isClose ? 'close' : 'open'}_${shiftId}_${DateTime.now().millisecondsSinceEpoch}';
    var list = <dynamic>[];
    final prev = p.getString(NotificationStoredKeys.shiftLifecycleEvents);
    if (prev != null && prev.trim().isNotEmpty) {
      try {
        list = jsonDecode(prev) as List<dynamic>;
      } catch (_) {}
    }
    list.insert(0, {
      'id': id,
      'title': title,
      'body': body,
      't': DateTime.now().toIso8601String(),
    });
    while (list.length > 35) {
      list.removeLast();
    }
    await p.setString(
      NotificationStoredKeys.shiftLifecycleEvents,
      jsonEncode(list),
    );
    await refresh();
  }

  Future<void> _appendShiftLifecycleNotifications(
    List<AppNotification> built,
  ) async {
    final on = await _prefBool(
      NotificationPrefs.shiftLifecycle,
      defaultValue: true,
    );
    if (!on) return;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(NotificationStoredKeys.shiftLifecycleEvents);
    if (raw == null || raw.trim().isEmpty) return;
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return;
    }
    final now = DateTime.now();
    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final id = m['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final title = m['title']?.toString() ?? 'وردية';
      final body = m['body']?.toString() ?? '';
      final tRaw = m['t']?.toString();
      final at = DateTime.tryParse(tRaw ?? '') ?? now;
      built.add(
        AppNotification(
          id: id,
          title: title,
          body: body,
          type: NotificationType.cashAlert,
          time: at,
          isRead: _readIds.contains(id),
        ),
      );
    }
  }

  Future<void> recordNegativeStockSale({
    required int invoiceId,
    required String staffName,
    required String customerName,
    required DateTime at,
    required List<Map<String, dynamic>> lines,
  }) async {
    if (lines.isEmpty) return;
    final on = await _prefBool(
      NotificationPrefs.negativeStockSale,
      defaultValue: true,
    );
    if (!on) return;
    final p = await SharedPreferences.getInstance();
    final id =
        'negstk_${invoiceId}_${at.millisecondsSinceEpoch}_${lines.length}';
    var list = <dynamic>[];
    final prev = p.getString(NotificationStoredKeys.negativeStockEvents);
    if (prev != null && prev.trim().isNotEmpty) {
      try {
        list = jsonDecode(prev) as List<dynamic>;
      } catch (_) {}
    }
    list.insert(0, {
      'id': id,
      'invoiceId': invoiceId,
      'staff': staffName,
      'customer': customerName,
      't': at.toIso8601String(),
      'lines': lines,
    });
    while (list.length > 45) {
      list.removeLast();
    }
    await p.setString(
      NotificationStoredKeys.negativeStockEvents,
      jsonEncode(list),
    );
    await refresh();
  }

  /// يُسجّل بيعاً بالدين أو بالتقسيط ليظهر في لوحة التنبيهات والشريط (مع التفاصيل).
  Future<void> recordFinancedSale({
    required int invoiceId,
    required bool isInstallment,
    required String customerName,
    required String staffName,
    required double total,
    required double advance,
    required DateTime at,
    required List<Map<String, dynamic>> lines,
    int? planId,
    int? plannedMonths,
    double? suggestedMonthly,
    double? financedAtSale,
    double? totalWithInterest,
    bool planCreationFailed = false,
  }) async {
    final on = await _prefBool(
      NotificationPrefs.financedSale,
      defaultValue: true,
    );
    if (!on) return;
    final p = await SharedPreferences.getInstance();
    final id = 'fin_sale_$invoiceId';
    var list = <dynamic>[];
    final prev = p.getString(NotificationStoredKeys.financedSaleEvents);
    if (prev != null && prev.trim().isNotEmpty) {
      try {
        list = jsonDecode(prev) as List<dynamic>;
      } catch (_) {}
    }
    list.removeWhere((e) {
      if (e is! Map) return false;
      final m = Map<String, dynamic>.from(e);
      return (m['invoiceId'] as num?)?.toInt() == invoiceId;
    });
    list.insert(0, {
      'id': id,
      'invoiceId': invoiceId,
      'isInstallment': isInstallment,
      'customer': customerName,
      'staff': staffName,
      'total': total,
      'advance': advance,
      'planId': planId,
      'plannedMonths': plannedMonths,
      'suggestedMonthly': suggestedMonthly,
      'financedAtSale': financedAtSale,
      'totalWithInterest': totalWithInterest,
      'planCreationFailed': planCreationFailed,
      'lines': lines,
      't': at.toIso8601String(),
    });
    while (list.length > 50) {
      list.removeLast();
    }
    await p.setString(
      NotificationStoredKeys.financedSaleEvents,
      jsonEncode(list),
    );
    await refresh();
  }

  Future<void> _appendFinancedSaleNotifications(
    List<AppNotification> built, {
    required NumberFormat numFmt,
    required DateFormat dateTimeFmt,
  }) async {
    final on = await _prefBool(
      NotificationPrefs.financedSale,
      defaultValue: true,
    );
    if (!on) return;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(NotificationStoredKeys.financedSaleEvents);
    if (raw == null || raw.trim().isEmpty) return;
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return;
    }
    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final id = m['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final invoiceId = (m['invoiceId'] as num?)?.toInt();
      final isInst = m['isInstallment'] == true;
      final staff = (m['staff'] as String?)?.trim() ?? '';
      final customer = (m['customer'] as String?)?.trim() ?? '';
      final total = (m['total'] as num?)?.toDouble() ?? 0;
      final advance = (m['advance'] as num?)?.toDouble() ?? 0;
      final rem = (total - advance).clamp(0.0, 1e15);
      final planId = (m['planId'] as num?)?.toInt();
      final months = (m['plannedMonths'] as num?)?.toInt();
      final monthly = (m['suggestedMonthly'] as num?)?.toDouble();
      final financed = (m['financedAtSale'] as num?)?.toDouble();
      final twi = (m['totalWithInterest'] as num?)?.toDouble();
      final planFail = m['planCreationFailed'] == true;
      final tRaw = m['t']?.toString();
      final at = DateTime.tryParse(tRaw ?? '') ?? DateTime.now();
      final lines = m['lines'];

      final title = isInst
          ? (planFail
              ? 'بيع بالتقسيط — فاتورة محفوظة'
              : 'بيع بالتقسيط — تم التسجيل')
          : 'بيع بالدين (آجل) — تم التسجيل';

      final buf = StringBuffer()
        ..writeln('مكان التسجيل: شاشة «بيع جديد» (نقطة البيع)')
        ..writeln(
          'فاتورة #${invoiceId ?? '-'} — ${dateTimeFmt.format(at)}',
        )
        ..writeln('البائع: ${staff.isEmpty ? '—' : staff}')
        ..writeln('العميل: ${customer.isEmpty ? 'بدون اسم' : customer}')
        ..writeln(
          'الإجمالي: ${numFmt.format(total)} د.ع — الواصل: ${numFmt.format(advance)} د.ع — المتبقي: ${numFmt.format(rem)} د.ع',
        );
      if (isInst) {
        if (planFail) {
          buf.writeln(
            'تنبيه: تعذّر إنشاء خطة التقسيط تلقائياً — راجع «الأقساط» واربط الفاتورة بخطة.',
          );
        } else {
          if (planId != null) {
            buf.writeln('خطة التقسيط: #$planId');
          }
          if (months != null && months > 0) {
            buf.writeln('عدد الأشهر المخطط: $months');
          }
          if (monthly != null && monthly > 1e-6) {
            buf.writeln(
              'قسط شهري تقريبي: ${numFmt.format(monthly)} د.ع',
            );
          }
          if (financed != null && financed > 1e-6) {
            buf.writeln('الممول من البيع: ${numFmt.format(financed)} د.ع');
          }
          if (twi != null && twi > 1e-6 && (twi - total).abs() > 1e-6) {
            buf.writeln(
              'الإجمالي مع الفائدة (إن وُجدت): ${numFmt.format(twi)} د.ع',
            );
          }
        }
      }
      buf.writeln('────────');
      if (lines is List) {
        var n = 0;
        for (final L in lines) {
          if (L is! Map) continue;
          if (n++ >= 22) break;
          final lm = Map<String, dynamic>.from(L);
          final name = (lm['name'] as String?)?.trim() ?? 'صنف';
          final pid = (lm['productId'] as num?)?.toInt();
          final qty = (lm['qty'] as num?)?.toDouble() ?? 0;
          final lt = (lm['lineTotal'] as num?)?.toDouble() ?? 0;
          buf.writeln(
            '• $name${pid != null ? ' — #$pid' : ''} — ${numFmt.format(qty)} — ${numFmt.format(lt)} د.ع',
          );
        }
        if (lines.length > 22) {
          buf.writeln('… وباقي الأسطر في الفاتورة.');
        }
      }
      built.add(
        AppNotification(
          id: id,
          title: title,
          body: buf.toString().trimRight(),
          type: NotificationType.financedSale,
          time: at,
          isRead: _readIds.contains(id),
        ),
      );
    }
  }

  static int _daysUntilExpiry(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 9999;
    final exp = DateTime.tryParse(raw.trim());
    if (exp == null) return 9999;
    final expDay = DateTime(exp.year, exp.month, exp.day);
    final today = DateTime.now();
    final t0 = DateTime(today.year, today.month, today.day);
    return expDay.difference(t0).inDays;
  }

  /// يفضّل أول 10 أحرف (YYYY-MM-DD) لتفادي اختلاف التوقيت بين تخزين القسط وعرضه.
  static DateTime _dueDateForNotification(String? dueRaw, DateTime fallback) {
    final due = dueRaw?.trim() ?? '';
    if (due.length >= 10) {
      final day = DateTime.tryParse(due.substring(0, 10));
      if (day != null) return DateTime(day.year, day.month, day.day);
    }
    final parsed = DateTime.tryParse(due);
    if (parsed != null) {
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
    return fallback;
  }

  Future<void> refresh() async {
    _loading = true;
    _lastError = null;
    notifyListeners();

    try {
      await _loadReadIds();

      final lowStockOn =
          await _prefBool(NotificationPrefs.lowStock, defaultValue: true);
      final expiryOn =
          await _prefBool(NotificationPrefs.expiry, defaultValue: true);
      final instOn =
          await _prefBool(NotificationPrefs.installment, defaultValue: true);
      final returnsOn =
          await _prefBool(NotificationPrefs.returns, defaultValue: true);
      final dailyOn =
          await _prefBool(NotificationPrefs.dailySummary, defaultValue: false);
      final debtOn =
          await _prefBool(NotificationPrefs.customerDebt, defaultValue: true);

      final tenantId = TenantContextService.instance.activeTenantId;

      final built = <AppNotification>[];
      final numFmt = NumberFormat('#,##0', 'ar');
      final dateFmt = DateFormat('dd/MM/yyyy', 'ar');
      final dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm', 'ar');
      final now = DateTime.now();

      if (instOn) {
        final overdue = await _db.getOverdueInstallmentsForNotifications(
          tenantId: tenantId,
        );
        for (final row in overdue) {
          final instId = row['instId'];
          final planRaw = row['planId'];
          final pid = planRaw is int
              ? planRaw
              : (planRaw as num?)?.toInt();
          final nid = (pid != null && pid > 0)
              ? 'inst_late_p${pid}_i$instId'
              : 'inst_late_$instId';
          final amt = (row['amount'] as num?)?.toDouble() ?? 0;
          final name = (row['customerName'] as String?)?.trim();
          final due = row['dueDate']?.toString() ?? '';
          final dueDt = _dueDateForNotification(due, now);
          built.add(
            AppNotification(
              id: nid,
              title: 'قسط متأخر — تذكير',
              body:
                  '${name == null || name.isEmpty ? 'عميل' : name}${pid != null && pid > 0 ? ' — خطة #$pid' : ''} — مستحق ${dateFmt.format(dueDt)} — ${numFmt.format(amt)} د.ع',
              type: NotificationType.installmentLate,
              time: dueDt,
              isRead: _readIds.contains(nid),
            ),
          );
        }

        final upcoming = await _db.getUpcomingInstallmentsForNotifications(
          tenantId: tenantId,
          withinDays: 14,
        );
        for (final row in upcoming) {
          final instId = row['instId'];
          final planRaw = row['planId'];
          final pid = planRaw is int
              ? planRaw
              : (planRaw as num?)?.toInt();
          final nid = (pid != null && pid > 0)
              ? 'inst_due_p${pid}_i$instId'
              : 'inst_due_$instId';
          final amt = (row['amount'] as num?)?.toDouble() ?? 0;
          final name = (row['customerName'] as String?)?.trim();
          final due = row['dueDate']?.toString() ?? '';
          final dueDt = _dueDateForNotification(due, now);
          built.add(
            AppNotification(
              id: nid,
              title: 'قسط قريب الاستحقاق — تذكير',
              body:
                  '${name == null || name.isEmpty ? 'عميل' : name}${pid != null && pid > 0 ? ' — خطة #$pid' : ''} — ${dateFmt.format(dueDt)} — ${numFmt.format(amt)} د.ع',
              type: NotificationType.installmentDue,
              time: dueDt,
              isRead: _readIds.contains(nid),
            ),
          );
        }
      }

      if (debtOn) {
        final debtSettings = await _db.getDebtSettings();

        final debtRows =
            await _db.getCustomersWithDebtForNotifications(tenantId: tenantId);
        for (final row in debtRows) {
          final cid = row['id'];
          final name = (row['name'] as String?)?.trim() ?? 'عميل';
          final bal = (row['balance'] as num?)?.toDouble() ?? 0;
          final phone = (row['phone'] as String?)?.trim();
          final extra = (phone != null && phone.isNotEmpty) ? ' — $phone' : '';
          built.add(
            AppNotification(
              id: 'debt_cust_$cid',
              title: 'دين على عميل',
              body:
                  '$name$extra — المتبقي ${numFmt.format(bal)} د.ع (آجل غير المقسّط).',
              type: NotificationType.customerDebt,
              time: now,
              isRead: _readIds.contains('debt_cust_$cid'),
            ),
          );
        }

        final warnDays = debtSettings.warnDebtAgeDays;
        if (warnDays > 0) {
          final aged = await _db.getAgedOpenCreditDebtInvoicesForNotifications(
            tenantId: tenantId,
            warnAgeDays: warnDays,
          );
          for (final row in aged) {
            final invId = row['id'];
            final cust = (row['customerName'] as String?)?.trim() ?? '';
            final dRaw = row['date']?.toString() ?? '';
            final invDate = DateTime.tryParse(dRaw.trim()) ?? now;
            final age = (row['ageDays'] as num?)?.toInt() ?? 0;
            built.add(
              AppNotification(
                id: 'debt_set_age_$invId',
                title: 'فاتورة آجل — تحذير عمر',
                body:
                    'حسب إعدادات الدين ($warnDays يوماً): فاتورة #$invId — '
                    '${cust.isEmpty ? 'بدون اسم' : cust} — منذ ${dateFmt.format(invDate)} '
                    '($age ${age == 1 ? 'يوماً' : 'أياماً'}).',
                type: NotificationType.debtInvoiceAged,
                time: invDate,
                isRead: _readIds.contains('debt_set_age_$invId'),
              ),
            );
          }
        }

        final capC = debtSettings.maxTotalOpenDebtPerCustomer;
        if (capC > 1e-9) {
          final byId = await _db.getCreditDebtCustomerTotalCapBreaches(
            tenantId: tenantId,
            customerCap: capC,
          );
          for (final row in byId) {
            final cid = row['customerId'];
            final name = (row['customerName'] as String?)?.trim() ?? 'عميل';
            final open = (row['openTotal'] as num?)?.toDouble() ?? 0;
            built.add(
              AppNotification(
                id: 'debt_set_cap_c_$cid',
                title: 'تجاوز سقف الدين للعميل',
                body:
                    'حسب إعدادات الدين: مجموع الآجل المفتوح لـ «$name» '
                    '${numFmt.format(open)} د.ع (السقف ${numFmt.format(capC)} د.ع).',
                type: NotificationType.debtCustomerCeiling,
                time: now,
                isRead: _readIds.contains('debt_set_cap_c_$cid'),
              ),
            );
          }
          final byName = await _db.getCreditDebtUnlinkedNameCapBreaches(
            tenantId: tenantId,
            customerCap: capC,
          );
          for (final row in byName) {
            final nameKey = (row['nameKey'] as String?)?.trim() ?? '';
            final name = (row['customerName'] as String?)?.trim() ?? 'عميل';
            final open = (row['openTotal'] as num?)?.toDouble() ?? 0;
            final nid =
                'debt_set_cap_n_${tenantId}_${nameKey.hashCode}';
            built.add(
              AppNotification(
                id: nid,
                title: 'تجاوز سقف الدين للعميل',
                body:
                    'حسب إعدادات الدين (بدون بطاقة عميل): «$name» — '
                    '${numFmt.format(open)} د.ع (السقف ${numFmt.format(capC)} د.ع).',
                type: NotificationType.debtCustomerCeiling,
                time: now,
                isRead: _readIds.contains(nid),
              ),
            );
          }
        }

        final capI = debtSettings.maxOpenRemainingPerInvoice;
        if (capI > 1e-9) {
          final invBreaches = await _db.getCreditDebtInvoiceCapBreaches(
            tenantId: tenantId,
            perInvoiceCap: capI,
          );
          for (final row in invBreaches) {
            final invId = row['id'];
            final cust = (row['customerName'] as String?)?.trim() ?? '';
            final rem = (row['remaining'] as num?)?.toDouble() ?? 0;
            final dRaw = row['date']?.toString() ?? '';
            final invDate = DateTime.tryParse(dRaw.trim()) ?? now;
            built.add(
              AppNotification(
                id: 'debt_set_cap_i_$invId',
                title: 'تجاوز سقف فاتورة آجل',
                body:
                    'حسب إعدادات الدين: فاتورة #$invId — '
                    '${cust.isEmpty ? 'بدون اسم' : cust} — المتبقي '
                    '${numFmt.format(rem)} د.ع (السقف ${numFmt.format(capI)} د.ع) — '
                    'تاريخ ${dateFmt.format(invDate)}.',
                type: NotificationType.debtInvoiceCeiling,
                time: invDate,
                isRead: _readIds.contains('debt_set_cap_i_$invId'),
              ),
            );
          }
        }
      }

      if (lowStockOn) {
        final rows = await _db.getProductsForLowStockNotifications(
          tenantId: tenantId,
        );
        for (final row in rows) {
          final pid = row['id'];
          final name = (row['name'] as String?) ?? 'منتج';
          final qty = (row['qty'] as num?)?.toDouble() ?? 0;
          final th = (row['lowStockThreshold'] as num?)?.toDouble() ?? 0;
          late final String title;
          late final String body;
          if (qty < -1e-9) {
            title = 'رصيد سالب في المخزون';
            final over = qty.abs();
            body =
                '"$name" — الكمية الحالية ${numFmt.format(qty)} (أي بيع زائد نحو ${numFmt.format(over)} ${over == 1 ? 'وحدة' : 'وحدات'} عن الرصيد عند آخر تحديث).';
          } else if (qty <= 1e-9) {
            title = 'منتج منفد';
            body = '"$name" — المخزون صفر.';
          } else {
            title = 'تنبيه مخزون منخفض';
            body =
                '"$name" — الكمية ${numFmt.format(qty)} (الحد ${numFmt.format(th)}).';
          }
          built.add(
            AppNotification(
              id: 'low_$pid',
              title: title,
              body: body,
              type: NotificationType.lowInventory,
              time: now,
              isRead: _readIds.contains('low_$pid'),
            ),
          );
        }
      }

      if (expiryOn) {
        final defaultAlertDays =
            (await _prefInt(NotificationPrefs.defaultExpiryAlertDays,
                    defaultValue: 14))
                .clamp(1, 365);
        final rows = await _db.getProductsWithExpiryForNotifications(
          tenantId: tenantId,
        );
        for (final row in rows) {
          final pid = row['id'];
          final name = (row['name'] as String?) ?? 'منتج';
          final expRaw = row['expiryDate']?.toString();
          final days = _daysUntilExpiry(expRaw);

          final perRaw = row['expiryAlertDaysBefore'];
          final int threshold;
          if (perRaw != null) {
            final n = (perRaw is num) ? perRaw.toInt() : int.tryParse('$perRaw');
            threshold = (n ?? defaultAlertDays).clamp(1, 365);
          } else {
            threshold = defaultAlertDays;
          }

          if (days > threshold) continue;

          final exp = DateTime.tryParse(expRaw?.trim() ?? '');
          final expLabel = exp != null ? dateFmt.format(exp) : (expRaw ?? '');

          if (days < 0) {
            built.add(
              AppNotification(
                id: 'exp_past_$pid',
                title: 'انتهى أجل ما على العبوة',
                body:
                    '«$name» — تجاوز التاريخ المدوَّن ($expLabel). راجع العرض أو الإتلاف حسب سياسة المتجر.',
                type: NotificationType.expiredProduct,
                time: exp ?? now,
                isRead: _readIds.contains('exp_past_$pid'),
              ),
            );
          } else {
            final daysPhrase = days == 0
                ? 'اليوم آخرُ الأيام المسماة للحفظ'
                : 'بقي $days ${days == 1 ? 'يوماً' : 'أياماً'} على أجل الانتهاء';
            built.add(
              AppNotification(
                id: 'exp_soon_$pid',
                title: 'في أفق الصلاحية',
                body:
                    '«$name» — ينتهي أجل الحفظ عند $expLabel ($daysPhrase).',
                type: NotificationType.expirySoon,
                time: now,
                isRead: _readIds.contains('exp_soon_$pid'),
              ),
            );
          }
        }
      }

      if (returnsOn) {
        final retRows =
            await _db.getRecentReturnInvoicesForNotifications(
          tenantId: tenantId,
          withinDays: 21,
        );
        for (final row in retRows) {
          final invId = row['id'];
          final orig = row['originalInvoiceId'];
          final total = (row['total'] as num?)?.toDouble() ?? 0;
          final cust = (row['customerName'] as String?)?.trim();
          final dRaw = row['date']?.toString();
          final d = DateTime.tryParse(dRaw ?? '') ?? now;
          built.add(
            AppNotification(
              id: 'ret_$invId',
              title: 'تم تسجيل مرتجع',
              body:
                  'فاتورة مرتجعة #$invId${orig != null ? ' ← أصل #$orig' : ''} — ${cust == null || cust.isEmpty ? 'بدون اسم' : cust} — ${numFmt.format(total)} د.ع',
              type: NotificationType.saleReturn,
              time: d,
              isRead: _readIds.contains('ret_$invId'),
            ),
          );
        }
      }

      if (dailyOn) {
        final total = await _db.getTodaySalesTotalForNotifications(
          tenantId: tenantId,
        );
        final dayKey =
            '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
        built.add(
          AppNotification(
            id: 'daily_$dayKey',
            title: 'ملخص مبيعات اليوم',
            body:
                'إجمالي فواتير البيع (بدون مرتجعات) لهذا اليوم: ${numFmt.format(total)} د.ع',
            type: NotificationType.newReport,
            time: DateTime(now.year, now.month, now.day, 12),
            isRead: _readIds.contains('daily_$dayKey'),
          ),
        );
      }

      final negSaleOn = await _prefBool(
        NotificationPrefs.negativeStockSale,
        defaultValue: true,
      );
      if (negSaleOn) {
        await _appendNegativeStockSaleNotifications(
          built,
          numFmt: numFmt,
          dateTimeFmt: dateTimeFmt,
        );
      }

      final finSaleOn = await _prefBool(
        NotificationPrefs.financedSale,
        defaultValue: true,
      );
      if (finSaleOn) {
        await _appendFinancedSaleNotifications(
          built,
          numFmt: numFmt,
          dateTimeFmt: dateTimeFmt,
        );
      }

      await _appendShiftLifecycleNotifications(built);

      built.sort((a, b) => b.time.compareTo(a.time));

      _notifications
        ..clear()
        ..addAll(built);

      _emitNewToAndroidSystemTray(built);
    } catch (e, st) {
      debugPrint('NotificationProvider.refresh: $e\n$st');
      _lastError = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void markAsRead(String id) {
    for (var i = 0; i < _notifications.length; i++) {
      final n = _notifications[i];
      if (n.id == id && !n.isRead) {
        _readIds.add(id);
        _notifications[i] = AppNotification(
          id: n.id,
          title: n.title,
          body: n.body,
          type: n.type,
          time: n.time,
          isRead: true,
        );
        notifyListeners();
        _persistReadIds();
        return;
      }
    }
  }

  Future<void> markAllAsRead() async {
    for (var i = 0; i < _notifications.length; i++) {
      final n = _notifications[i];
      _readIds.add(n.id);
      _notifications[i] = AppNotification(
        id: n.id,
        title: n.title,
        body: n.body,
        type: n.type,
        time: n.time,
        isRead: true,
      );
    }
    notifyListeners();
    await _persistReadIds();
  }

  /// إزالة من العرض الحالي فقط (يُعاد الظهور بعد التحديث إن بقيت البيانات).
  void remove(String id) {
    _notifications.removeWhere((n) => n.id == id);
    notifyListeners();
  }
}
