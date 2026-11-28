/// ك1: فهرس الإعدادات التي يقرؤها المساعد ويغيّرها ببطاقة تأكيد.
///
/// كل إعداد هنا مربوط بدالة حفظ شاشته نفسها (في `DeviceExecPort`)، وبشرط ظهوره
/// نفسه في شاشة الإعدادات: ما يراه المالك وحده يبقى للمالك وحده. الإعداد غير
/// الموجود هنا تُفتح شاشته (ui_navigate) ويُكمله المستخدم بيده.
library;

enum AssistantSettingKind { toggle, choice }

class AssistantSettingSpec {
  const AssistantSettingSpec({
    required this.key,
    required this.label,
    required this.kind,
    required this.routeId,
    this.choices = const {},
    this.ownerOnly = false,
    this.onLabel = 'مفعّل',
    this.offLabel = 'مطفأ',
  });

  final String key;
  final String label;
  final AssistantSettingKind kind;

  /// شاشة الإعداد، لمن يريد أن يراه بنفسه.
  final String routeId;

  /// للاختيار: المعرّف ← الاسم الذي يقوله المستخدم.
  final Map<String, String> choices;
  final bool ownerOnly;
  final String onLabel;
  final String offLabel;

  String display(Object? v) => switch (kind) {
    AssistantSettingKind.toggle => v == true ? onLabel : offLabel,
    AssistantSettingKind.choice => choices['$v'] ?? '$v',
  };

  static const _on = {
    'true',
    '1',
    'on',
    'yes',
    'تفعيل',
    'مفعل',
    'مفعّل',
    'شغل',
    'شغّل',
    'نعم',
    'داكن',
    'ليلي',
  };
  static const _off = {
    'false',
    '0',
    'off',
    'no',
    'إيقاف',
    'ايقاف',
    'مطفأ',
    'اطفي',
    'طفي',
    'لا',
    'فاتح',
    'نهاري',
  };

  /// القيمة كما فهمها النموذج أو كما قالها المستخدم، أو null إن لم تُفهم.
  Object? parse(Object? raw) {
    if (raw == null) return null;
    if (kind == AssistantSettingKind.toggle) {
      if (raw is bool) return raw;
      final t = '$raw'.trim().toLowerCase();
      if (_on.contains(t)) return true;
      if (_off.contains(t)) return false;
      return null;
    }
    final t = '$raw'.trim();
    if (choices.containsKey(t)) return t;
    for (final e in choices.entries) {
      if (e.value == t ||
          e.value.contains(t) ||
          (t.length > 2 && t.contains(e.value))) {
        return e.key;
      }
    }
    return null;
  }
}

abstract final class AssistantSettingsCatalog {
  static const darkMode = 'dark_mode';
  static const compactSnack = 'compact_snack';
  static const debtsEnabled = 'debts_enabled';
  static const colorPalette = 'color_palette';

  static const all = <AssistantSettingSpec>[
    AssistantSettingSpec(
      key: darkMode,
      label: 'الوضع الداكن',
      kind: AssistantSettingKind.toggle,
      routeId: 'app_settings',
      onLabel: 'داكن',
      offLabel: 'فاتح (نهاري)',
    ),
    AssistantSettingSpec(
      key: compactSnack,
      label: 'التنبيهات المختصرة',
      kind: AssistantSettingKind.toggle,
      routeId: 'app_settings',
    ),
    AssistantSettingSpec(
      key: debtsEnabled,
      label: 'الديون (البيع الآجل)',
      kind: AssistantSettingKind.toggle,
      routeId: 'app_settings',
      ownerOnly: true,
    ),
    // نفس معرّفات SalePaletteIds.builtIn (المخصص يبقى بشاشته).
    AssistantSettingSpec(
      key: colorPalette,
      label: 'ألوان التطبيق',
      kind: AssistantSettingKind.choice,
      routeId: 'app_settings_sale_pos_appearance',
      choices: {
        'royal': 'كحلي ملكي',
        'midnight': 'منتصف الليل',
        'ocean': 'محيط',
        'forest': 'غابة',
        'wine': 'نبيذي',
        'charcoal': 'فحمي',
        'slate': 'أردوازي',
        'copper': 'نحاسي',
      },
    ),
  ];

  static AssistantSettingSpec? byKey(String? key) {
    for (final s in all) {
      if (s.key == key) return s;
    }
    return null;
  }
}
