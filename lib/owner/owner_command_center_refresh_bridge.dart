import 'package:flutter/foundation.dart';

/// جسر خفيف لإبطال cache أقسام لوحة المالك بعد تغييرات محلية (سعر، مخزون…).
class OwnerCommandCenterRefreshBridge extends ChangeNotifier {
  OwnerCommandCenterRefreshBridge._();
  static final OwnerCommandCenterRefreshBridge instance =
      OwnerCommandCenterRefreshBridge._();

  final Set<String> _pendingSectionIds = {};

  void invalidateSection(String sectionId) {
    if (sectionId.isEmpty) return;
    _pendingSectionIds.add(sectionId);
    notifyListeners();
  }

  void invalidateSections(Iterable<String> sectionIds) {
    for (final id in sectionIds) {
      if (id.isNotEmpty) _pendingSectionIds.add(id);
    }
    if (_pendingSectionIds.isNotEmpty) notifyListeners();
  }

  Set<String> drainPendingSectionIds() {
    if (_pendingSectionIds.isEmpty) return const {};
    final out = Set<String>.from(_pendingSectionIds);
    _pendingSectionIds.clear();
    return out;
  }
}
