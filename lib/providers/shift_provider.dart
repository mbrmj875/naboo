import 'package:flutter/foundation.dart';

import '../services/database_helper.dart';

/// حالة الوردية المفتوحة (جلسة عمل الصندوق).
class ShiftProvider extends ChangeNotifier {
  ShiftProvider() {
    refresh();
  }

  final DatabaseHelper _db = DatabaseHelper();
  Map<String, dynamic>? _active;

  Map<String, dynamic>? get activeShift => _active;

  bool get hasOpenShift => _active != null;

  Future<void> refresh() async {
    _active = await _db.getOpenWorkShift();
    notifyListeners();
  }

  Future<int> openShift({
    required int sessionUserId,
    required int shiftStaffUserId,
    required double systemBalanceAtOpen,
    required double declaredPhysicalCash,
    required double addedCashAtOpen,
    required String shiftStaffName,
    required String shiftStaffPin,
  }) async {
    final id = await _db.openWorkShift(
      sessionUserId: sessionUserId,
      shiftStaffUserId: shiftStaffUserId,
      systemBalanceAtOpen: systemBalanceAtOpen,
      declaredPhysicalCash: declaredPhysicalCash,
      addedCashAtOpen: addedCashAtOpen,
      shiftStaffName: shiftStaffName,
      shiftStaffPin: shiftStaffPin,
    );
    await refresh();
    return id;
  }

  Future<void> closeShift({
    required int shiftId,
    required double systemBalanceAtCloseMoment,
    required double declaredCashInBox,
    required double withdrawnAmount,
    required double declaredClosingCash,
  }) async {
    await _db.closeWorkShift(
      shiftId: shiftId,
      systemBalanceAtCloseMoment: systemBalanceAtCloseMoment,
      declaredCashInBox: declaredCashInBox,
      withdrawnAmount: withdrawnAmount,
      declaredClosingCash: declaredClosingCash,
    );
    await refresh();
  }

  Future<Map<String, int>> invoiceCountsForShift(int shiftId) =>
      _db.getWorkShiftInvoiceCounts(shiftId);
}
