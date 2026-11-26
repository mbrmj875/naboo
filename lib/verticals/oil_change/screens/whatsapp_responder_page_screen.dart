import 'dart:async';

import 'package:flutter/material.dart';

import '../../../navigation/content_navigation.dart';
import '../../../theme/design_tokens.dart';
import '../services/whatsapp_responder_repository.dart';
import '../widgets/oil_change_form_theme.dart';
import 'whatsapp_customer_queue_screen.dart';

/// «ما يقوله المجيب للزبائن» (ق83): ما يعرفه مجيب واتساب عن المحل، وما يذكره،
/// وأسلوبه. مطفأ = المجيب الحالي كما هو.
class WhatsappResponderPageScreen extends StatefulWidget {
  const WhatsappResponderPageScreen({super.key, this.repository});

  final WhatsappResponderRepository? repository;

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      FastContentPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const WhatsappResponderPageScreen(),
      ),
    );
  }

  @override
  State<WhatsappResponderPageScreen> createState() => _WhatsappResponderPageScreenState();
}

class _WhatsappResponderPageScreenState extends State<WhatsappResponderPageScreen> {
  late final WhatsappResponderRepository _repo = widget.repository ?? WhatsappResponderRepository.instance;
  WhatsappResponderProfile? _p;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  final _hours = TextEditingController();
  final _duration = TextEditingController();
  final _offer = TextEditingController();
  final _newService = TextEditingController();
  final _newNote = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in [_hours, _duration, _offer, _newService, _newNote]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await _repo.loadProfile();
      _hours.text = p.hours;
      _duration.text = p.serviceDuration;
      _offer.text = p.offerText;
      if (!mounted) return;
      setState(() {
        _p = p;
        _loading = false;
        _dirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر تحميل صفحة المجيب. تأكد من الاتصال.';
      });
    }
  }

  void _edit(void Function(WhatsappResponderProfile p) f) {
    setState(() {
      f(_p!);
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final p = _p!;
    p
      ..hours = _hours.text
      ..serviceDuration = _duration.text
      ..offerText = _offer.text;
    final err = p.validate();
    if (err != null) {
      _snack(err);
      return;
    }
    setState(() => _saving = true);
    try {
      await _repo.saveProfile(p);
      if (!mounted) return;
      setState(() => _dirty = false);
      _snack(p.enabled ? 'حُفظت. المجيب يستعملها من الرسالة التالية.' : 'حُفظت. المجيب الذكي مطفأ.');
    } catch (e) {
      _snack(e is StateError ? e.message : 'تعذّر الحفظ. تأكد من الاتصال.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تغييرات غير محفوظة'),
        content: const Text('تخرج بدون حفظ؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ابقَ')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('اخرج')),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: OilChangeFormTheme.wrap(context, Theme.of(context)),
      child: PopScope(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _confirmLeave() && context.mounted) Navigator.of(context).pop();
        },
        child: Builder(
          builder: (context) => Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            appBar: OilChangeFormTheme.appBar(
              context: context,
              title: 'ما يقوله المجيب للزبائن',
              actions: [
                IconButton(
                  tooltip: 'زبائن ينتظرون وقادمون',
                  onPressed: () => unawaited(WhatsappCustomerQueueScreen.open(context)),
                  icon: const Icon(Icons.support_agent_rounded),
                ),
              ],
            ),
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(onPressed: () => unawaited(_load()), child: const Text('إعادة المحاولة')),
                            ],
                          ),
                        ),
                      )
                    : _body(context),
            bottomNavigationBar: _loading || _error != null
                ? null
                : SafeArea(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12),
                      child: FilledButton(
                        onPressed: _saving ? null : () => unawaited(_save()),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(_saving ? 'جاري الحفظ…' : 'حفظ'),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final p = _p!;
    final muted = OilChangeFormTheme.secondaryText(context);
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
      children: [
        _Section(
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: p.enabled,
            onChanged: (v) => _edit((p) => p.enabled = v),
            title: const Text('المجيب الذكي', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              p.enabled
                  ? 'يجاوب الزبائن من هذه الصفحة، ويبلّغكم حين لا يعرف الجواب.'
                  : 'مطفأ: يبقى المجيب الحالي كما هو.',
              style: TextStyle(color: muted),
            ),
          ),
        ),
        _Section(
          title: 'معلومات المحل',
          children: [
            _Field(
              controller: _hours,
              label: 'الدوام',
              hint: 'مثال: كل يوم من 9 الصبح إلى 9 بالليل، الجمعة عطلة',
              maxLength: 300,
              maxLines: 2,
              onChanged: () => _dirty = true,
            ),
            _Field(
              controller: _duration,
              label: 'مدة الخدمة التقريبية',
              hint: 'مثال: تبديل الزيت ربع ساعة',
              maxLength: 120,
              onChanged: () => _dirty = true,
            ),
            Text('الخدمات', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in p.services)
                  InputChip(
                    label: Text(s),
                    onDeleted: () => _edit((p) => p.services.remove(s)),
                    deleteButtonTooltipMessage: 'حذف $s',
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newService,
                    maxLength: 60,
                    decoration: const InputDecoration(hintText: 'خدمة جديدة', counterText: ''),
                    onSubmitted: (_) => _addService(),
                  ),
                ),
                IconButton(tooltip: 'إضافة الخدمة', onPressed: _addService, icon: const Icon(Icons.add_rounded)),
              ],
            ),
          ],
        ),
        _Section(
          title: 'العرض الجاري',
          subtitle: 'يذكره المجيب فقط حين يسأل الزبون عن السعر أو العروض، ويتوقف بعد تاريخه.',
          children: [
            _Field(
              controller: _offer,
              label: 'نص العرض',
              hint: 'مثال: غسيل مجاني مع كل تبديل زيت',
              maxLength: 300,
              maxLines: 2,
              onChanged: () => _dirty = true,
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.offerUntil == null ? 'بلا تاريخ انتهاء' : 'ينتهي ${_date(p.offerUntil!)}',
                    style: TextStyle(color: muted),
                  ),
                ),
                TextButton(onPressed: _pickOfferDate, child: const Text('تاريخ الانتهاء')),
                if (p.offerUntil != null)
                  IconButton(
                    tooltip: 'إزالة التاريخ',
                    onPressed: () => _edit((p) => p.offerUntil = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
          ],
        ),
        _Section(
          title: 'ما يذكره المجيب',
          subtitle: 'المطفأ لا يصل المجيب أصلاً.',
          children: [
            _Toggle('يذكر الأسعار', 'سعر البيع فقط، بلا سعر شراء', p.mentionPrices,
                (v) => _edit((p) => p.mentionPrices = v)),
            _Toggle('يذكر التوفر', 'متوفر أو نفذ، بلا كميات', p.mentionStock, (v) => _edit((p) => p.mentionStock = v)),
            _Toggle('ينصح بالزيت', 'من دليل السيارات المؤكد فقط، ثم ما يطابقه عندكم', p.oilAdvice,
                (v) => _edit((p) => p.oilAdvice = v)),
          ],
        ),
        _Section(
          title: 'الأسلوب',
          subtitle: 'مع تقييم 3 أو أقل يصير هادئاً تلقائياً.',
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'playful', label: Text('ودود بخفة دم')),
                ButtonSegment(value: 'calm', label: Text('ودود هادئ')),
                ButtonSegment(value: 'formal', label: Text('رسمي مختصر')),
              ],
              selected: {p.tone},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _edit((p) => p.tone = s.first),
            ),
          ],
        ),
        _Section(
          title: 'بعد تبليغكم',
          subtitle: 'حين يحتاج الزبون موظفاً، يسكت المجيب في محادثته حتى تردّوا أو تنتهي المدة.',
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '30m', label: Text('30 دقيقة')),
                ButtonSegment(value: '2h', label: Text('ساعتان')),
                ButtonSegment(value: 'eod', label: Text('لآخر اليوم')),
              ],
              selected: {p.silence},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _edit((p) => p.silence = s.first),
            ),
          ],
        ),
        _Section(
          title: 'ملاحظات للمجيب (${p.notes.length}/${WhatsappResponderProfile.maxNotes})',
          subtitle: 'معلومة قصيرة يقولها للزبون. تصحيحات «رد خاطئ» تظهر هنا أيضاً.',
          children: [
            for (var i = 0; i < p.notes.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  p.notes[i].fromCorrection ? Icons.rule_rounded : Icons.sticky_note_2_outlined,
                  color: muted,
                  semanticLabel: p.notes[i].fromCorrection ? 'من تصحيح' : 'ملاحظة',
                ),
                title: Text(p.notes[i].text),
                subtitle: p.notes[i].fromCorrection ? const Text('من زر «رد خاطئ»') : null,
                trailing: IconButton(
                  tooltip: 'حذف الملاحظة',
                  onPressed: () => _edit((p) => p.notes.removeAt(i)),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ),
            if (p.notes.length < WhatsappResponderProfile.maxNotes)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newNote,
                      maxLength: WhatsappResponderProfile.maxNoteChars,
                      decoration: const InputDecoration(hintText: 'مثال: نقبل الدفع بزين كاش'),
                      onSubmitted: (_) => _addNote(),
                    ),
                  ),
                  IconButton(tooltip: 'إضافة الملاحظة', onPressed: _addNote, icon: const Icon(Icons.add_rounded)),
                ],
              ),
          ],
        ),
      ],
    );
  }

  void _addService() {
    final s = _newService.text.trim();
    if (s.isEmpty || _p!.services.contains(s) || _p!.services.length >= 30) return;
    _edit((p) => p.services.add(s));
    _newService.clear();
  }

  void _addNote() {
    final s = _newNote.text.trim();
    if (s.isEmpty) return;
    _edit((p) => p.notes.add(ResponderNote(s)));
    _newNote.clear();
  }

  Future<void> _pickOfferDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _p!.offerUntil ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d != null) _edit((p) => p.offerUntil = d);
  }

  static String _date(DateTime d) => '${d.year}/${d.month}/${d.day}';
}

class _Section extends StatelessWidget {
  const _Section({this.title, this.subtitle, this.children = const [], this.child});

  final String? title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OilChangeFormTheme.gold.withValues(alpha: 0.35)),
        color: OilChangeFormTheme.gold.withValues(alpha: 0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) Text(title!, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(color: OilChangeFormTheme.secondaryText(context))),
          ],
          if (title != null || subtitle != null) const SizedBox(height: 10),
          if (child != null) child!,
          ...children,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.maxLength,
    required this.onChanged,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLength;
  final int maxLines;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: 1,
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.title, this.subtitle, this.value, this.onChanged);

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      title: Text(title),
      subtitle: Text(subtitle, style: TextStyle(color: OilChangeFormTheme.secondaryText(context))),
    );
  }
}
