/// من يحق له الموافقة على استرجاع.
class ApprovalCandidate {
  const ApprovalCandidate({
    required this.userId,
    required this.name,
    required this.isOwner,
  });

  final int userId;
  final String name;
  final bool isOwner;
}

/// موافقة لمرة واحدة، مربوطة بفاتورة ومبلغ محددين.
class ReturnApproval {
  ReturnApproval({
    required this.approverUserId,
    required this.approverName,
    required this.approverIsOwner,
    required this.invoiceGlobalKey,
    required this.amount,
  });

  final int approverUserId;
  final String approverName;
  final bool approverIsOwner;

  /// المعرّف العالمي للأصل (أو `local:<id>` لإيصال قديم بلا معرّف).
  final String invoiceGlobalKey;
  final double amount;
  bool _used = false;

  bool get used => _used;

  /// صالحة لهذا الاسترجاع بالضبط ولم تُستعمل.
  bool matches(String invoiceKey, double refundAmount) =>
      !_used &&
      invoiceKey == invoiceGlobalKey &&
      (refundAmount - amount).abs() < 0.005;

  /// تُستهلك عند الحفظ — لا تُعاد.
  bool consume(String invoiceKey, double refundAmount) {
    if (!matches(invoiceKey, refundAmount)) return false;
    _used = true;
    return true;
  }
}

/// قائمة الموافِقين: المالك والإدارة، وكاملو الصلاحية الذين لديهم رمز.
/// يُستبعد الموظف الحالي عند منع الموافقة الذاتية (المالك لا يحتاج موافقة أصلاً).
List<ApprovalCandidate> selectApprovers({
  required List<Map<String, dynamic>> activeUsers,
  required Set<int> elevatedStaffIds,
  required int? currentUserId,
  required bool blockSelfApproval,
}) {
  final out = <ApprovalCandidate>[];
  for (final u in activeUsers) {
    final id = (u['id'] as num?)?.toInt();
    if (id == null || id <= 0) continue;
    if (blockSelfApproval && id == currentUserId) continue;
    final role = (u['role'] ?? 'staff').toString().trim().toLowerCase();
    final privileged = role == 'owner' || role == 'admin';
    if (!privileged) {
      if (!elevatedStaffIds.contains(id)) continue;
      final hash = (u['passwordHash'] ?? '').toString().trim();
      final salt = (u['passwordSalt'] ?? '').toString().trim();
      if (hash.isEmpty || salt.isEmpty) continue;
    }
    final display = (u['displayName'] ?? '').toString().trim();
    final name = display.isNotEmpty
        ? display
        : (u['username'] ?? '').toString();
    out.add(
      ApprovalCandidate(userId: id, name: name, isOwner: role == 'owner'),
    );
  }
  out.sort((a, b) {
    if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
    return a.name.compareTo(b.name);
  });
  return out;
}
