import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/staff_ui_prefs_repository.dart';
import '../utils/app_logger.dart';

/// تفضيلات ترتيب وإظهار أقسام الشاشة الرئيسية (لوحة التحكم).
///
/// زر «غسيل السيارات» يُحفظ لكل موظف على حدة عبر [StaffUiPrefsRepository].
class DashboardLayoutProvider extends ChangeNotifier {
  DashboardLayoutProvider() {
    unawaited(_hydrateFromDisk());
  }

  static const String _kOrderKey = 'dashboard_section_order_v1';
  static const String _kVisibleKey = 'dashboard_section_visible_v1';

  /// مفتاح قديم مشترك — يُستخدم مرة واحدة كبذرة لكل موظف لم يحفظ تفضيله بعد.
  static const String _kLegacyCarWashButtonKey = 'dashboard_car_wash_button_v1';

  /// نسخة لكل موظف في SharedPreferences — احتياط إن فشل/تأخر حفظ SQLite.
  static const String _kPerUserCarWashPrefix = 'dashboard_car_wash_button_user_v1_';

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

  bool _carWashButtonVisible = true;
  bool _carWashBound = false;
  String _boundUserKey = '';
  String? _boundUserGlobalId;
  int? _boundUserId;

  /// قيمة اختارها المستخدم قبل اكتمال [bindToUser] — تُحفظ فور الربط.
  bool? _pendingCarWashVisible;

  List<String> get order => List.unmodifiable(_order);

  bool isVisible(String id) => _visible[id] ?? true;

  /// هل يظهر زر «غسيل السيارات» على الرئيسية؟ (حسب الموظف الحالي)
  bool get carWashButtonVisible => _carWashButtonVisible;

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
    } catch (e, st) {
      AppLogger.error(
        'DashboardLayout',
        'تعذر تحميل تفضيلات ترتيب أقسام الرئيسية',
        e,
        st,
      );
    }
    notifyListeners();
  }

  Future<void> _persistLayoutOnly() async {
    _visible['header'] = true;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kOrderKey, jsonEncode(_order));
    await p.setString(_kVisibleKey, jsonEncode(_visible));
  }

  String _prefsKeyForUser(String userKey) => '$_kPerUserCarWashPrefix$userKey';

  Future<bool?> _readPerUserPrefsFlag(String userKey) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.get(_prefsKeyForUser(userKey));
      if (raw is bool) return raw;
      if (raw is num) return raw != 0;
      if (raw is String) {
        final s = raw.trim().toLowerCase();
        if (s == 'false' || s == '0') return false;
        if (s == 'true' || s == '1') return true;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _writePerUserPrefsFlag(String userKey, bool value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_prefsKeyForUser(userKey), value);
    } catch (e, st) {
      AppLogger.error(
        'DashboardLayout',
        'تعذر حفظ تفضيل غسيل السيارات في SharedPreferences',
        e,
        st,
      );
    }
  }

  /// يربط تفضيل غسيل السيارات بالموظف الحالي (يُستدعى عند تغيّر الجلسة).
  Future<void> bindToUser({
    required bool isLoggedIn,
    String? userGlobalId,
    int? userId,
  }) async {
    if (!isLoggedIn || (userId ?? 0) <= 0) {
      _boundUserKey = '';
      _boundUserGlobalId = null;
      _boundUserId = null;
      _carWashBound = false;
      _pendingCarWashVisible = null;
      _carWashButtonVisible = true;
      notifyListeners();
      return;
    }

    final gid = (userGlobalId ?? '').trim();
    final id = userId!;
    final key = gid.isNotEmpty ? 'g:$gid' : 'local:$id';
    if (_carWashBound && key == _boundUserKey) {
      // إن وُجدت قيمة معلّقة بعد ربط سابق ناقص، احفظها الآن.
      final pending = _pendingCarWashVisible;
      if (pending != null && pending != _carWashButtonVisible) {
        await setCarWashButtonVisible(pending);
      }
      return;
    }

    _boundUserKey = key;
    _boundUserGlobalId = gid.isEmpty ? null : gid;
    _boundUserId = id;

    try {
      final pending = _pendingCarWashVisible;
      if (pending != null) {
        _carWashButtonVisible = pending;
        _pendingCarWashVisible = null;
        await _persistCarWashVisible(pending);
        _carWashBound = true;
        notifyListeners();
        return;
      }

      final repo = StaffUiPrefsRepository.instance;
      final hasSaved = await repo.hasSavedPrefs(
        userGlobalId: _boundUserGlobalId,
        userId: id,
      );
      if (hasSaved) {
        final prefs = await repo.loadForUser(
          userGlobalId: _boundUserGlobalId,
          userId: id,
        );
        _carWashButtonVisible = prefs.carWashButtonVisible;
        await _writePerUserPrefsFlag(key, _carWashButtonVisible);
      } else {
        final fromDisk = await _readPerUserPrefsFlag(key);
        var seed = fromDisk;
        if (seed == null) {
          // ترحيل لمرة واحدة من المفتاح المشترك القديم إن وُجد.
          final p = await SharedPreferences.getInstance();
          final legacy = p.get(_kLegacyCarWashButtonKey);
          if (legacy is bool) {
            seed = legacy;
          } else if (legacy is num) {
            seed = legacy != 0;
          } else {
            seed = true;
          }
        }
        _carWashButtonVisible = seed!;
        await _persistCarWashVisible(seed);
      }
      _carWashBound = true;
    } catch (e, st) {
      AppLogger.error(
        'DashboardLayout',
        'تعذر ربط تفضيل غسيل السيارات بالموظف',
        e,
        st,
      );
      // لا نفرض الإظهار عند الفشل — نحتفظ بما في SharedPreferences إن وُجد.
      final fromDisk = await _readPerUserPrefsFlag(key);
      if (fromDisk != null) {
        _carWashButtonVisible = fromDisk;
      }
      // أبقِ unbound=false لإعادة المحاولة عند إشعار Auth التالي.
      _carWashBound = false;
      _boundUserKey = '';
    }
    notifyListeners();
  }

  Future<void> _persistCarWashVisible(bool value) async {
    final key = _boundUserKey;
    if (key.isNotEmpty) {
      await _writePerUserPrefsFlag(key, value);
    }
    final id = _boundUserId ?? 0;
    if (id <= 0) return;
    await StaffUiPrefsRepository.instance.saveForUser(
      prefs: StaffUiPrefs(carWashButtonVisible: value),
      userGlobalId: _boundUserGlobalId,
      userId: id,
    );
  }

  Future<void> setCarWashButtonVisible(bool value) async {
    if (_carWashButtonVisible == value &&
        _pendingCarWashVisible == null &&
        _carWashBound) {
      return;
    }
    _carWashButtonVisible = value;
    notifyListeners();

    final id = _boundUserId ?? 0;
    if (id <= 0 || !_carWashBound) {
      _pendingCarWashVisible = value;
      return;
    }

    _pendingCarWashVisible = null;
    try {
      await _persistCarWashVisible(value);
    } catch (e, st) {
      AppLogger.error(
        'DashboardLayout',
        'تعذر حفظ تفضيل غسيل السيارات',
        e,
        st,
      );
      // احتفظ بالقيمة في SharedPreferences حتى لو فشل SQLite.
      if (_boundUserKey.isNotEmpty) {
        await _writePerUserPrefsFlag(_boundUserKey, value);
      }
    }
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
    await _persistLayoutOnly();
    notifyListeners();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _order.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _order.removeAt(oldIndex);
    _order.insert(newIndex, item);
    await _persistLayoutOnly();
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    _order = List<String>.from(sectionIds);
    for (final id in sectionIds) {
      _visible[id] = true;
    }
    _visible['header'] = true;
    await _persistLayoutOnly();
    await setCarWashButtonVisible(true);
    notifyListeners();
  }
}
