import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تفضيلات ترتيب وإظهار أقسام الشاشة الرئيسية (لوحة التحكم).
class DashboardLayoutProvider extends ChangeNotifier {
  DashboardLayoutProvider() {
    unawaited(_hydrateFromDisk());
  }

  static const String _kOrderKey = 'dashboard_section_order_v1';
  static const String _kVisibleKey = 'dashboard_section_visible_v1';

  /// أقسام قابلة للترتيب والإخفاء في الشاشة الرئيسية.
  static const List<String> sectionIds = [
    'header',
    'orbit',
    'pinned',
    'charts',
  ];

  static String sectionTitleAr(String id) {
    switch (id) {
      case 'header':
        return 'الترحيب والملخص العلوي';
      case 'orbit':
        return 'الاختصارات الدائرية (صندوق، بيع، …)';
      case 'pinned':
        return 'المنتجات المثبّتة';
      case 'charts':
        return 'المخططات والنشاط الأخير';
      default:
        return id;
    }
  }

  List<String> _order = List<String>.from(sectionIds);
  final Map<String, bool> _visible = {
    for (final id in sectionIds) id: true,
  };

  List<String> get order => List.unmodifiable(_order);

  bool isVisible(String id) => _visible[id] ?? true;

  /// رأس اللوحة يبقى ظاهراً دائماً (لا يُعطّل من الإعدادات).
  bool get isHeaderVisibilityLocked => true;

  Future<void> _hydrateFromDisk() async {
    try {
      final p = await SharedPreferences.getInstance();
      final oRaw = p.getString(_kOrderKey);
      if (oRaw != null && oRaw.isNotEmpty) {
        final decoded = jsonDecode(oRaw);
        if (decoded is List) {
          final parsed = decoded.map((e) => e.toString()).toList();
          if (parsed.isNotEmpty) {
            final merged = <String>[];
            for (final id in parsed) {
              if (sectionIds.contains(id) && !merged.contains(id)) {
                merged.add(id);
              }
            }
            for (final id in sectionIds) {
              if (!merged.contains(id)) merged.add(id);
            }
            _order = merged;
          }
        }
      }
      final vRaw = p.getString(_kVisibleKey);
      if (vRaw != null && vRaw.isNotEmpty) {
        final decoded = jsonDecode(vRaw);
        if (decoded is Map) {
          for (final id in sectionIds) {
            final v = decoded[id];
            if (v is bool) {
              _visible[id] = v;
            } else if (v is num) {
              _visible[id] = v != 0;
            }
          }
        }
      }
      _visible['header'] = true;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _persist() async {
    _visible['header'] = true;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kOrderKey, jsonEncode(_order));
    await p.setString(_kVisibleKey, jsonEncode(_visible));
  }

  int _countVisibleExcluding(String excludeId) {
    var c = 0;
    for (final id in sectionIds) {
      if (id == excludeId) continue;
      if (_visible[id] ?? false) c++;
    }
    return c;
  }

  Future<void> setSectionVisible(String id, bool value) async {
    if (!sectionIds.contains(id)) return;
    if (id == 'header') return;
    if (!value && _countVisibleExcluding(id) == 0) return;
    _visible[id] = value;
    await _persist();
    notifyListeners();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _order.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _order.removeAt(oldIndex);
    _order.insert(newIndex, item);
    await _persist();
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    _order = List<String>.from(sectionIds);
    for (final id in sectionIds) {
      _visible[id] = true;
    }
    _visible['header'] = true;
    await _persist();
    notifyListeners();
  }
}
