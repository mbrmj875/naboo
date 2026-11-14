import 'package:flutter/foundation.dart';

/// كل وجهات اللمس في لوحة المالك v4 — تُبنى في شاشة اللوحة وتُختبر منفردة.
@immutable
class OwnerV4Actions {
  const OwnerV4Actions({
    required this.openSales,
    required this.openCash,
    required this.openOilLog,
    required this.openDebts,
    required this.debtReminders,
    required this.purchasePdf,
    required this.openInventory,
    required this.openInstallments,
    required this.openSensitive,
    required this.openStaffActivity,
    required this.openRoute,
  });

  final VoidCallback openSales;
  final VoidCallback openCash;

  /// سجل الغيارات (الورشة).
  final VoidCallback openOilLog;
  final VoidCallback openDebts;

  /// قائمة تذكير الديون عبر واتساب.
  final VoidCallback debtReminders;
  final VoidCallback purchasePdf;
  final VoidCallback openInventory;
  final VoidCallback openInstallments;

  /// شاشة «الأمان والتعديلات الحساسة».
  final VoidCallback openSensitive;

  /// شاشة «نشاط الموظفين» الكاملة.
  final VoidCallback openStaffActivity;

  /// أزرار «إدارة المحل» — معرّف المسار في [OwnerShortcutNavigation.openRoute].
  final void Function(String routeId) openRoute;
}
