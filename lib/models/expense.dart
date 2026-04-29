import 'package:flutter/material.dart';

enum ExpenseStatus { paid, pending }

ExpenseStatus expenseStatusFromDb(String? v) {
  switch ((v ?? '').toLowerCase()) {
    case 'pending':
      return ExpenseStatus.pending;
    default:
      return ExpenseStatus.paid;
  }
}

String expenseStatusToDb(ExpenseStatus s) => switch (s) {
      ExpenseStatus.pending => 'pending',
      ExpenseStatus.paid => 'paid',
    };

class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  final int id;
  final String name;
  final int sortOrder;

  factory ExpenseCategory.fromMap(Map<String, dynamic> m) {
    return ExpenseCategory(
      id: (m['id'] as num).toInt(),
      name: (m['name'] as String?)?.trim() ?? '',
      sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}

class ExpenseEntry {
  const ExpenseEntry({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.amount,
    required this.occurredAt,
    required this.status,
    required this.description,
    required this.employeeUserId,
    required this.employeeName,
    required this.isRecurring,
    required this.recurringDay,
    required this.recurringOriginId,
    required this.attachmentPath,
    required this.affectsCash,
    this.invoiceRef,
    this.landlordOrProperty,
    this.taxKind,
  });

  final int id;
  final int categoryId;
  final String categoryName;
  final double amount;
  final DateTime occurredAt;
  final ExpenseStatus status;
  final String description;
  final int? employeeUserId;
  final String employeeName;
  final bool isRecurring;
  final int? recurringDay;
  final int? recurringOriginId;
  final String? attachmentPath;
  final bool affectsCash;
  /// حقول مساعدة حسب نوع المصروف (ماء، كهرباء، إيجار، ضرائب).
  final String? invoiceRef;
  final String? landlordOrProperty;
  final String? taxKind;

  factory ExpenseEntry.fromJoinedRow(Map<String, dynamic> m) {
    final empDisplay = (m['employeeDisplayName'] as String?)?.trim();
    final empUser = (m['employeeUsername'] as String?)?.trim();
    final empName = (empDisplay != null && empDisplay.isNotEmpty)
        ? empDisplay
        : (empUser ?? '');
    return ExpenseEntry(
      id: (m['id'] as num).toInt(),
      categoryId: (m['categoryId'] as num).toInt(),
      categoryName: (m['categoryName'] as String?)?.trim() ?? '',
      amount: (m['amount'] as num?)?.toDouble() ?? 0.0,
      occurredAt:
          DateTime.tryParse((m['occurredAt'] ?? '').toString()) ?? DateTime.now(),
      status: expenseStatusFromDb(m['status']?.toString()),
      description: (m['description'] as String?)?.trim() ?? '',
      employeeUserId: (m['employeeUserId'] as num?)?.toInt(),
      employeeName: empName,
      isRecurring: ((m['isRecurring'] as num?)?.toInt() ?? 0) == 1,
      recurringDay: (m['recurringDay'] as num?)?.toInt(),
      recurringOriginId: (m['recurringOriginId'] as num?)?.toInt(),
      attachmentPath: (m['attachmentPath'] as String?)?.trim(),
      affectsCash: ((m['affectsCash'] as num?)?.toInt() ?? 1) == 1,
      invoiceRef: (m['invoiceRef']?.toString().trim().isNotEmpty ?? false)
          ? m['invoiceRef']?.toString().trim()
          : null,
      landlordOrProperty: (m['landlordOrProperty']?.toString().trim().isNotEmpty ?? false)
          ? m['landlordOrProperty']?.toString().trim()
          : null,
      taxKind:
          (m['taxKind']?.toString().trim().isNotEmpty ?? false) ? m['taxKind']?.toString().trim() : null,
    );
  }
}

bool expenseCategoryAllowsAttachment(String categoryName) {
  switch (categoryName.trim()) {
    case 'ماء':
    case 'كهرباء':
    case 'ضرائب':
    case 'مصاريف متنوعة':
      return true;
    default:
      return false;
  }
}

class ExpenseEmployeeOption {
  const ExpenseEmployeeOption({
    required this.id,
    required this.name,
    required this.jobTitle,
    required this.phone,
  });

  final int id;
  final String name;
  final String jobTitle;
  final String phone;

  factory ExpenseEmployeeOption.fromMap(Map<String, dynamic> m) {
    final display = (m['displayName'] as String?)?.trim();
    final username = (m['username'] as String?)?.trim();
    return ExpenseEmployeeOption(
      id: (m['id'] as num).toInt(),
      name: (display != null && display.isNotEmpty)
          ? display
          : (username ?? ''),
      jobTitle: (m['jobTitle'] as String?)?.trim() ?? '',
      phone: (m['phone'] as String?)?.trim() ?? '',
    );
  }
}

bool expenseCategoryRequiresEmployee(String categoryName) {
  return false;
}

bool expenseCategorySuggestsRecurring(String categoryName) {
  switch (categoryName.trim()) {
    case 'رواتب':
    case 'إيجار':
      return true;
    default:
      return false;
  }
}

IconData expenseCategoryIcon(String name) {
  switch (name) {
    case 'رواتب':
      return Icons.badge_outlined;
    case 'ماء':
      return Icons.water_drop_outlined;
    case 'كهرباء':
      return Icons.bolt_outlined;
    case 'إيجار':
      return Icons.home_work_outlined;
    case 'ضرائب':
      return Icons.account_balance_outlined;
    default:
      return Icons.receipt_long_outlined;
  }
}

Color expenseCategoryColor(String name, ColorScheme cs) {
  switch (name) {
    case 'رواتب':
      return const Color(0xFF2563EB);
    case 'ماء':
      return const Color(0xFF0EA5E9);
    case 'كهرباء':
      return const Color(0xFFF59E0B);
    case 'إيجار':
      return const Color(0xFF8B5CF6);
    case 'ضرائب':
      return const Color(0xFF64748B);
    default:
      return cs.primary;
  }
}

