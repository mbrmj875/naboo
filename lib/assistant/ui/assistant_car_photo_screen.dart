import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import 'assistant_view_models.dart' show isolateLtr;

/// سيارة معروفة بالرقم المقروء: آخر بطاقة لها على هذا الجهاز.
class AssistantKnownCar {
  const AssistantKnownCar({required this.customer, this.car, this.lastOdometer});
  final String customer;
  final String? car;
  final int? lastOdometer;
}

/// ما أرجعه الخادم بعد قراءة الصورة.
class AssistantCarPhotoRead {
  const AssistantCarPhotoRead({this.plate, this.oldStyle = false, this.odometer, this.error});

  factory AssistantCarPhotoRead.fromJson(Map<String, Object?> j) => AssistantCarPhotoRead(
    plate: j['plate'] as String?,
    oldStyle: j['plate_style'] == 'old',
    odometer: (j['odometer'] as num?)?.toInt(),
    error: j['error'] as String?,
  );

  final String? plate;
  final bool oldStyle;
  final int? odometer;
  final String? error;
}

/// بطاقة غيار من صورة (م4-13، قرار المالك بعد قياس م0-17).
///
/// اللوحة والعدّاد يُقرآن ثم يظهران **دائماً** في خانتين قابلتين للتعديل بجانب
/// الصورة، ولا تُفتح البطاقة إلا بضغطة المستخدم. اللوحة القديمة العربية تحمل
/// «تأكد من الأرقام». لا سيارة بالرقم = يقال ذلك ولا يُخمَّن زبون.
class AssistantCarPhotoScreen extends StatefulWidget {
  const AssistantCarPhotoScreen({
    super.key,
    required this.pick,
    required this.read,
    required this.lookup,
    required this.open,
  });

  static const routeName = '/assistant/car-photo';

  /// يلتقط صورة مضغوطة، أو null إن ألغى المستخدم.
  final Future<Uint8List?> Function() pick;
  final Future<AssistantCarPhotoRead> Function(List<Uint8List> images) read;
  final Future<AssistantKnownCar?> Function(String plate) lookup;

  /// يفتح بطاقة الغيار معبّأة بالقيم كما راجعها المستخدم.
  final Future<void> Function(Map<String, Object?> values) open;

  @override
  State<AssistantCarPhotoScreen> createState() => _AssistantCarPhotoScreenState();
}

class _AssistantCarPhotoScreenState extends State<AssistantCarPhotoScreen> {
  Uint8List? _plateImg;
  Uint8List? _odoImg;
  final _plate = TextEditingController();
  final _odo = TextEditingController();
  bool _reading = false;
  bool _read = false;
  bool _oldStyle = false;
  String? _error;
  AssistantKnownCar? _known;
  bool _looked = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _plate.dispose();
    _odo.dispose();
    super.dispose();
  }

  Future<void> _take(bool plate) async {
    final img = await widget.pick();
    if (img == null || !mounted) return;
    setState(() {
      if (plate) {
        _plateImg = img;
      } else {
        _odoImg = img;
      }
      _read = false;
      _error = null;
    });
  }

  Future<void> _doRead() async {
    final p = _plateImg;
    if (p == null || _reading) return;
    setState(() {
      _reading = true;
      _error = null;
    });
    final r = await widget.read([p, ?_odoImg]);
    if (!mounted) return;
    setState(() {
      _reading = false;
      _read = true;
      _error = switch (r.error) {
        null => null,
        'budget_exhausted' => 'خلصت حصة المساعد لهذا الشهر. اكتب الرقمين بيدك.',
        'images_disabled' => 'قراءة الصور متوقفة بوضع التوفير. اكتب الرقمين بيدك.',
        'network' => 'ما في إنترنت. اكتب الرقمين بيدك.',
        _ => 'ما گدرت أقرأ الصورة. اكتب الرقمين بيدك.',
      };
      _oldStyle = r.oldStyle;
      _plate.text = r.plate ?? '';
      _odo.text = r.odometer?.toString() ?? '';
    });
    await _lookup();
  }

  Future<void> _lookup() async {
    final plate = _plate.text.trim();
    if (plate.isEmpty) {
      setState(() => (_known = null, _looked = false));
      return;
    }
    final k = await widget.lookup(plate);
    if (!mounted || _plate.text.trim() != plate) return;
    setState(() => (_known = k, _looked = true));
  }

  void _plateChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => unawaited(_lookup()));
  }

  Future<void> _open() async {
    final plate = _plate.text.trim();
    final odo = int.tryParse(_odo.text.replaceAll(RegExp(r'[,\s]'), ''));
    await widget.open({
      if (plate.isNotEmpty) 'plate': plate,
      if (odo != null && odo > 0) 'odometer': odo,
      // الزبون يُعبّأ فقط إن طابقت اللوحة سيارة معروفة. لا تخمين.
      if (_known != null) 'customer': _known!.customer,
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final known = _known;
    final odoVal = int.tryParse(_odo.text.replaceAll(RegExp(r'[,\s]'), ''));
    final odoBelow = known?.lastOdometer != null && odoVal != null && odoVal < known!.lastOdometer!;
    return Scaffold(
      appBar: AppBar(title: const Text('بطاقة غيار من صورة')),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
        children: [
          Text(
            'صوّر لوحة السيارة، وإذا تريد صوّر العدّاد. أقرأ الرقمين وتراجعهما أنت قبل ما تنفتح البطاقة.',
            style: t.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PhotoSlot(label: 'صورة اللوحة', image: _plateImg, onTap: () => unawaited(_take(true))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PhotoSlot(
                  label: 'صورة العدّاد (اختياري)',
                  image: _odoImg,
                  onTap: () => unawaited(_take(false)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_read)
            FilledButton.icon(
              onPressed: _plateImg != null && !_reading ? () => unawaited(_doRead()) : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: _reading
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.document_scanner_outlined),
              label: Text(_reading ? 'أقرأ…' : 'اقرأ الرقمين'),
            ),
          if (_read) ...[
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: t.textTheme.bodyMedium?.copyWith(color: cs.error)),
              ),
            TextField(
              controller: _plate,
              onChanged: _plateChanged,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'رقم اللوحة', border: OutlineInputBorder()),
            ),
            if (_oldStyle)
              const _Note(
                icon: Icons.warning_amber_rounded,
                color: AppSemanticColors.warning,
                text: 'لوحة قديمة: تأكد من الأرقام. قراءتها أضعف.',
              )
            else if (_plate.text.trim().isEmpty)
              _Note(
                icon: Icons.info_outline,
                color: cs.onSurfaceVariant,
                text: 'ما گدرت أقرأ اللوحة بثقة. اكتبها بيدك.',
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _odo,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'العدّاد (كم)', border: OutlineInputBorder()),
            ),
            if (odoBelow)
              _Note(
                icon: Icons.warning_amber_rounded,
                color: AppSemanticColors.warning,
                text: 'أقل من آخر عدّاد مسجّل (${known.lastOdometer}). تأكد منه.',
              ),
            const SizedBox(height: 12),
            if (known != null)
              _Note(
                icon: Icons.check_circle_outline,
                color: AppSemanticColors.success,
                text: isolateLtr('سيارة معروفة: ${known.customer}${known.car == null ? '' : '، ${known.car}'}'),
              )
            else if (_looked)
              _Note(
                icon: Icons.info_outline,
                color: cs.onSurfaceVariant,
                text: 'ما لقيت سيارة بهذا الرقم. تنفتح بطاقة جديدة وتختار الزبون بنفسك.',
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => unawaited(_open()),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.open_in_new),
              label: const Text('افتح البطاقة'),
            ),
          ],
        ],
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({required this.label, required this.image, required this.onTap});
  final String label;
  final Uint8List? image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final img = image;
    return Semantics(
      button: true,
      label: img == null ? label : '$label، اضغط لإعادة التصوير',
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 140,
          decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant)),
          child: img == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.photo_camera_outlined, color: cs.primary),
                    const SizedBox(height: 6),
                    Text(label, textAlign: TextAlign.center),
                  ],
                )
              : ExcludeSemantics(
                  child: Image.memory(img, fit: BoxFit.cover, width: double.infinity),
                ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    ),
  );
}
