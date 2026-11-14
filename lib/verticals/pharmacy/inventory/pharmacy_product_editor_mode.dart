import 'package:shared_preferences/shared_preferences.dart';

/// وضع واجهة محرّر الدواء — A (4 خطوات) · B (2) · C (6 شاشات).
enum PharmacyEditorMode {
  modeA,
  modeB,
  modeC,
}

extension PharmacyEditorModeX on PharmacyEditorMode {
  int get stepCount => switch (this) {
        PharmacyEditorMode.modeA => 4,
        PharmacyEditorMode.modeB => 2,
        PharmacyEditorMode.modeC => 6,
      };

  String get labelAr => switch (this) {
        PharmacyEditorMode.modeA => 'معالج 4 خطوات',
        PharmacyEditorMode.modeB => 'معالج مختصر (خطوتان)',
        PharmacyEditorMode.modeC => 'شاشات منفصلة (6)',
      };

  String get storageKey => switch (this) {
        PharmacyEditorMode.modeA => 'mode_a',
        PharmacyEditorMode.modeB => 'mode_b',
        PharmacyEditorMode.modeC => 'mode_c',
      };
}

PharmacyEditorMode pharmacyEditorModeFromKey(String? raw) {
  return switch (raw?.trim()) {
    'mode_b' || 'modeB' => PharmacyEditorMode.modeB,
    'mode_c' || 'modeC' => PharmacyEditorMode.modeC,
    _ => PharmacyEditorMode.modeA,
  };
}

/// تفضيل وضع المحرّr — tenant-scoped عبر prefs بسيط.
abstract final class PharmacyEditorModeStore {
  PharmacyEditorModeStore._();

  static const _prefsKey = 'pharmacy.editor_mode';

  static Future<PharmacyEditorMode> load() async {
    final p = await SharedPreferences.getInstance();
    return pharmacyEditorModeFromKey(p.getString(_prefsKey));
  }

  static Future<void> save(PharmacyEditorMode mode) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, mode.storageKey);
  }
}
