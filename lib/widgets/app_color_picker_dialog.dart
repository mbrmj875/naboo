import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/design_tokens.dart';

/// يفتح حواراً لاختيار لون بطريقة مرئية (HSV + جاهز + HEX).
Future<Color?> showAppColorPickerDialog({
  required BuildContext context,
  required Color initialColor,
  required String title,
  String? subtitle,
}) {
  return showDialog<Color>(
    context: context,
    builder: (ctx) => _AppColorPickerDialog(
      initialColor: initialColor,
      title: title,
      subtitle: subtitle,
    ),
  );
}

/// تحليل لون من نص HEX مرن (#RRGGBB أو RRGGBB أو FFFF).
Color? parseFlexibleHexColor(String input) {
  var t = input.trim();
  if (t.isEmpty) return null;
  if (t.startsWith('#')) t = t.substring(1);
  if (t.length == 6) t = 'FF$t';
  if (t.length != 8) return null;
  final v = int.tryParse(t, radix: 16);
  if (v == null) return null;
  return Color(v);
}

class _AppColorPickerDialog extends StatefulWidget {
  const _AppColorPickerDialog({
    required this.initialColor,
    required this.title,
    this.subtitle,
  });

  final Color initialColor;
  final String title;
  final String? subtitle;

  @override
  State<_AppColorPickerDialog> createState() => _AppColorPickerDialogState();
}

class _AppColorPickerDialogState extends State<_AppColorPickerDialog> {
  late HSVColor _hsv;
  late TextEditingController _hexCtrl;
  final GlobalKey _svPaintKey = GlobalKey();

  static const List<int> _presetArgb = [
    0xFF152B47,
    0xFF1E3A5F,
    0xFF0F172A,
    0xFF1E293B,
    0xFF334155,
    0xFF0D47A1,
    0xFF1565C0,
    0xFF0277BD,
    0xFF00695C,
    0xFF1B5E20,
    0xFFC9A85C,
    0xFFD4AF37,
    0xFFB8860B,
    0xFF8D6E63,
    0xFF5D4037,
    0xFFF7F4EF,
    0xFFF5F5F0,
    0xFFE8E0D5,
    0xFFF1F5F9,
    0xFFE2E8F0,
    0xFF1A2433,
    0xFF0F172A,
    0xFF1E1B4B,
    0xFF312E81,
    0xFF4C1D95,
    0xFFB91C1C,
    0xFFBE123C,
    0xFFEA580C,
    0xFFCA8A04,
    0xFF15803D,
  ];

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
    _hexCtrl = TextEditingController(text: _hexFromColor(_hsv.toColor()));
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  String _hexFromColor(Color c) {
    final argb = c.toARGB32();
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  void _setFromHsv(HSVColor next) {
    setState(() {
      _hsv = next;
      _hexCtrl.text = _hexFromColor(next.toColor());
    });
  }

  void _applyHexFromField() {
    final c = parseFlexibleHexColor(_hexCtrl.text);
    if (c != null) {
      setState(() {
        _hsv = HSVColor.fromColor(c);
      });
    }
  }

  void _onSvPan(Offset local, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final s = (local.dx / size.width).clamp(0.0, 1.0);
    final v = (1.0 - local.dy / size.height).clamp(0.0, 1.0);
    _setFromHsv(HSVColor.fromAHSV(1, _hsv.hue, s, v));
  }

  void _svFromGlobal(Offset global) {
    final box = _svPaintKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(global);
    _onSvPan(local, box.size);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = _hsv.toColor();
    // لا نستخدم LayoutBuilder هنا: AlertDialog يفرض IntrinsicWidth وLayoutBuilder لا يدعم الأبعاد الجوهرية.
    final screenW = MediaQuery.sizeOf(context).width;
    final svW = (screenW - 120).clamp(200.0, 320.0);
    final svH = svW * 0.62;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                widget.subtitle!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: (screenW - 72).clamp(280.0, 440.0),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: preview,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.outlineVariant,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: preview.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'معاينة مباشرة',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _hexFromColor(preview),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'التشبع والسطوع',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                // اتجاه LTR ثابت: في RTL يعكس Slider والتدرج بشكل مختلف فيُظهر لوناً غير موافق للمقبض (مثلاً أصفر بصرياً → وردي).
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Center(
                    child: GestureDetector(
                      onPanDown: (d) => _svFromGlobal(d.globalPosition),
                      onPanUpdate: (d) => _svFromGlobal(d.globalPosition),
                      onTapDown: (d) => _svFromGlobal(d.globalPosition),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          key: _svPaintKey,
                          width: svW,
                          height: svH,
                          child: Stack(
                            clipBehavior: Clip.hardEdge,
                            fit: StackFit.expand,
                            children: [
                              CustomPaint(
                                painter: _SvSquarePainter(hue: _hsv.hue),
                              ),
                              Positioned(
                                left: _hsv.saturation * svW - 7,
                                top: (1 - _hsv.value) * svH - 7,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black45,
                                          blurRadius: 3,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'اسحب داخل المربع لضبط التشبع (أفقياً) والسطوع (عمودياً)',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.3,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'درجة اللون (الطيف)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: List.generate(
                              7,
                              (i) => HSVColor.fromAHSV(
                                1,
                                i * 60.0,
                                1,
                                1,
                              ).toColor(),
                            ),
                          ),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 32,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 10,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 16,
                          ),
                          activeTrackColor: Colors.transparent,
                          inactiveTrackColor: Colors.transparent,
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: _hsv.hue.clamp(0.0, 360.0),
                          min: 0,
                          max: 360,
                          onChanged: (hue) {
                            _setFromHsv(
                              HSVColor.fromAHSV(
                                1,
                                hue,
                                _hsv.saturation,
                                _hsv.value,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'ألوان جاهزة — اضغط للاختيار',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    for (final argb in _presetArgb)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () =>
                              _setFromHsv(HSVColor.fromColor(Color(argb))),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Color(argb),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: preview.toARGB32() == argb
                                    ? scheme.primary
                                    : Colors.black26,
                                width: preview.toARGB32() == argb ? 2 : 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'قيمة HEX (للنسخ أو الإدخال الدقيق)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _hexCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '#152B47',
                    border: const OutlineInputBorder(
                      borderRadius: AppShape.none,
                    ),
                    suffixIcon: IconButton(
                      tooltip: 'تطبيق النص',
                      icon: const Icon(Icons.check_rounded, size: 20),
                      onPressed: _applyHexFromField,
                    ),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
                  ],
                  onSubmitted: (_) => _applyHexFromField(),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, preview),
            child: const Text('تأكيد اللون'),
          ),
        ],
      ),
    );
  }
}

/// مربع التشبع (أفقي) × السطوع (عمودي) لدرجة لون [hue] ثابتة.
class _SvSquarePainter extends CustomPainter {
  _SvSquarePainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final r = BorderRadius.circular(10).toRRect(rect);

    final hueFull = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    final hz = Paint()
      ..shader = LinearGradient(
        colors: [Colors.white, hueFull],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(rect);
    canvas.drawRRect(r, hz);

    final vz = Paint()
      ..shader = LinearGradient(
        colors: [Colors.transparent, Colors.black],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect);
    canvas.drawRRect(r, vz);
  }

  @override
  bool shouldRepaint(covariant _SvSquarePainter oldDelegate) {
    return oldDelegate.hue != hue;
  }
}
