import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/presets/presets.dart';

const _kGold = Color(0xFFB8960C);
const _kNavy = Color(0xFF0F172A);

Color _parseHex(String hex) {
  final clean = hex.replaceFirst('#', '');
  if (clean.length != 6) return _kNavy;
  return Color(0xFF000000 | int.parse(clean, radix: 16));
}

String _toHex(Color c) {
  final argb = (c.a * 255).round() << 24 |
      (c.r * 255).round() << 16 |
      (c.g * 255).round() << 8 |
      (c.b * 255).round();
  final v = argb & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

bool _isLight(Color c) => c.computeLuminance() > 0.55;

/// شرشف ألوان احترافي — أساسي / تمييز / خلفية / نص.
/// [onLiveChange] يحدّث المسودة مباشرة خلف الشرشف لمعاينة فورية.
Future<Map<String, String>?> showMenuColorPickerSheet({
  required BuildContext context,
  required String initialKey,
  required Map<String, String> colors,
  ValueChanged<Map<String, String>>? onLiveChange,
}) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _MenuColorPickerSheet(
      initialKey: initialKey,
      initialColors: Map<String, String>.from(colors),
      onLiveChange: onLiveChange,
    ),
  );
}

class _MenuColorPickerSheet extends StatefulWidget {
  const _MenuColorPickerSheet({
    required this.initialKey,
    required this.initialColors,
    this.onLiveChange,
  });

  final String initialKey;
  final Map<String, String> initialColors;
  final ValueChanged<Map<String, String>>? onLiveChange;

  @override
  State<_MenuColorPickerSheet> createState() => _MenuColorPickerSheetState();
}

class _MenuColorPickerSheetState extends State<_MenuColorPickerSheet> {
  static const _roles = <(String key, String label)>[
    ('primary', 'أساسي'),
    ('accent', 'تمييز'),
    ('bg', 'خلفية'),
    ('text', 'نص'),
  ];

  late String _activeKey;
  late Map<String, String> _colors;
  final _hexCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _activeKey = widget.initialKey;
    _colors = widget.initialColors;
    _syncHexField();
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  String get _currentHex =>
      (_colors[_activeKey] ?? '#B8960C').toUpperCase();

  void _syncHexField() {
    _hexCtrl.text = _currentHex.replaceFirst('#', '');
  }

  void _select(String hex) {
    final normalized =
        hex.startsWith('#') ? hex.toUpperCase() : '#${hex.toUpperCase()}';
    setState(() {
      _colors = {..._colors, _activeKey: normalized};
      _syncHexField();
    });
    widget.onLiveChange?.call(Map<String, String>.from(_colors));
    HapticFeedback.selectionClick();
  }

  void _applyHexFromField() {
    var raw = _hexCtrl.text.trim().replaceFirst('#', '');
    if (raw.length == 3) {
      raw = raw.split('').map((c) => '$c$c').join();
    }
    if (raw.length != 6 || int.tryParse(raw, radix: 16) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل لوناً بصيغة سداسية مثل B8960C')),
      );
      return;
    }
    _select('#$raw');
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height = media.size.height * 0.78;
    final current = _parseHex(_currentHex);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: const Color(0xFFFFFBF8),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'اختيار اللون',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: _kNavy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'اضغط على الدرجة لتطبيقها فوراً على المعاينة',
                            style: TextStyle(
                              fontSize: 12,
                              color: _kNavy.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      color: _kNavy.withValues(alpha: 0.55),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
                  itemCount: _roles.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final (key, label) = _roles[i];
                    final selected = key == _activeKey;
                    final roleColor = _parseHex(_colors[key] ?? '#888888');
                    return ChoiceChip(
                      selected: selected,
                      showCheckmark: false,
                      avatar: CircleAvatar(
                        backgroundColor: roleColor,
                        radius: 8,
                      ),
                      label: Text(label),
                      selectedColor: _kGold.withValues(alpha: 0.18),
                      labelStyle: TextStyle(
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected ? _kNavy : _kNavy.withValues(alpha: 0.65),
                      ),
                      side: BorderSide(
                        color: selected ? _kGold : const Color(0xFFE2E8F0),
                        width: selected ? 1.6 : 1,
                      ),
                      onSelected: (_) {
                        setState(() {
                          _activeKey = key;
                          _syncHexField();
                        });
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 8),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: current,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: current.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _roles
                                .firstWhere((e) => e.$1 == _activeKey)
                                .$2,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: _kNavy,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Text(
                                '#',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _kNavy,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: TextField(
                                  controller: _hexCtrl,
                                  textCapitalization: TextCapitalization.characters,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9a-fA-F]'),
                                    ),
                                    LengthLimitingTextInputFormatter(6),
                                  ],
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    hintText: 'B8960C',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsetsDirectional.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                  ),
                                  onSubmitted: (_) => _applyHexFromField(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: _applyHexFromField,
                                child: const Text('تطبيق'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
                  itemCount: kRestaurantColorGroups.length,
                  itemBuilder: (context, gi) {
                    final group = kRestaurantColorGroups[gi];
                    return Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.labelAr,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                              color: _kNavy.withValues(alpha: 0.55),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final hex in group.hexes)
                                _SwatchDisc(
                                  hex: hex,
                                  selected:
                                      hex.toUpperCase() == _currentHex,
                                  onTap: () => _select(hex),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kGold,
                      foregroundColor: _kNavy,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, _colors),
                    child: const Text(
                      'تم',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwatchDisc extends StatelessWidget {
  const _SwatchDisc({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = _parseHex(hex);
    final checkColor = _isLight(c) ? _kNavy : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? _kGold : const Color(0xFFCBD5E1),
              width: selected ? 3 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _kGold.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: selected
              ? Icon(Icons.check_rounded, size: 18, color: checkColor)
              : null,
        ),
      ),
    );
  }
}

/// يُستخدم إن احتجنا تحويل لون إلى hex من خارج الشاشة.
String menuColorToHex(Color c) => _toHex(c);
