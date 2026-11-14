class ShiftActorConflictResult {
  const ShiftActorConflictResult({
    required this.hasConflict,
    required this.shiftStaffName,
  });

  final bool hasConflict;
  final String shiftStaffName;
}

class ShiftActorConflictGuard {
  ShiftActorConflictGuard._();

  static ShiftActorConflictResult evaluate({
    required int? sessionUserId,
    required Map<String, dynamic>? activeShift,
  }) {
    final shiftStaffUserId = (activeShift?['shiftStaffUserId'] as num?)?.toInt();
    final hasConflict =
        activeShift != null &&
        sessionUserId != null &&
        shiftStaffUserId != null &&
        shiftStaffUserId > 0 &&
        sessionUserId != shiftStaffUserId;
    final rawName = (activeShift?['shiftStaffName'] as String?)?.trim() ?? '';
    final shiftStaffName = rawName.isEmpty ? 'صاحب الوردية' : rawName;
    return ShiftActorConflictResult(
      hasConflict: hasConflict,
      shiftStaffName: shiftStaffName,
    );
  }
}
