import 'dart:async';

import 'package:flutter/material.dart';

import '../services/oil_change_technicians_store.dart';

/// صفحة فنيي المحل (المرحلة 7 — الشريحة 1): حسابات الموظفين والمضافون
/// يدوياً في قائمة واحدة، مع الإيقاف والإعادة بدل الحذف.
class OilTechniciansScreen extends StatefulWidget {
  const OilTechniciansScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const OilTechniciansScreen()),
    );
  }

  @override
  State<OilTechniciansScreen> createState() => _OilTechniciansScreenState();
}

class _OilTechniciansScreenState extends State<OilTechniciansScreen> {
  final _store = OilChangeTechniciansStore.instance;
  List<OilTechnician>? _all;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final all = await _store.loadAll();
    if (!mounted) return;
    setState(() => _all = all);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmStop(OilTechnician t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إيقاف الفني'),
        content: Text(
          'إيقاف «${t.name}»؟ لا يظهر في البطاقات الجديدة، وبطاقاته وتقريره '
          'وتقييماته تبقى. تستطيع إعادته من هذه الصفحة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('techStopConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إيقاف'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => _store.stop(t.name));
  }

  Future<void> _add() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة فني'),
        content: TextField(
          key: const Key('techAddName'),
          controller: ctrl,
          autofocus: true,
          maxLength: OilChangeTechniciansStore.maxNameLength,
          decoration: const InputDecoration(
            labelText: 'اسم الفني',
            hintText: 'مثال: أحمد علي',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('techAddSave'),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    final clean = OilChangeTechniciansStore.normalize(name ?? '');
    if (clean.isEmpty) return;
    await _run(() => _store.add(clean));
  }

  /// تعديل اسم فني مضاف يدوياً (الشريحة 2).
  Future<void> _rename(OilTechnician t) async {
    final count = await _store.countCards(t.name);
    if (!mounted) return;
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameDialog(
        oldName: t.name,
        cardsCount: count,
        existing: {
          for (final o in _all ?? const <OilTechnician>[])
            if (o.name != t.name)
              OilChangeTechniciansStore.keyOf(o.name): o.name,
        },
      ),
    );
    if (newName == null || !mounted) return;
    var updated = 0;
    await _run(() async {
      updated = await _store.rename(t.name, newName);
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updated == 0
              ? 'عُدّل الاسم إلى «$newName»'
              : 'عُدّل الاسم إلى «$newName» في $updated بطاقة',
        ),
      ),
    );
  }

  Widget _tile(OilTechnician t) {
    final cs = Theme.of(context).colorScheme;
    final source = t.fromAccount ? 'حساب موظف' : 'مضاف يدوياً';
    return ListTile(
      key: Key('tech_${t.name}'),
      leading: Icon(
        t.fromAccount ? Icons.badge_outlined : Icons.handyman_outlined,
        color: t.stopped ? cs.onSurfaceVariant : cs.primary,
      ),
      title: Text(
        t.name,
        style: t.stopped ? TextStyle(color: cs.onSurfaceVariant) : null,
      ),
      subtitle: Text(
        t.stopped ? '$source · موقوف' : source,
        key: Key('techSource_${t.name}'),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!t.fromAccount)
            IconButton(
              key: Key('techRename_${t.name}'),
              tooltip: 'تعديل الاسم',
              onPressed: _busy ? null : () => unawaited(_rename(t)),
              icon: const Icon(Icons.edit_outlined),
            ),
          t.stopped
              ? TextButton.icon(
                  key: Key('techRestore_${t.name}'),
                  onPressed: _busy
                      ? null
                      : () => unawaited(_run(() => _store.restore(t.name))),
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('إعادة'),
                )
              : TextButton.icon(
                  key: Key('techStop_${t.name}'),
                  onPressed: _busy ? null : () => unawaited(_confirmStop(t)),
                  icon: const Icon(Icons.person_off_outlined),
                  label: const Text('إيقاف'),
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final all = _all;
    final active = all?.where((t) => !t.stopped).toList() ?? const [];
    final stopped = all?.where((t) => t.stopped).toList() ?? const [];
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800);
    return Scaffold(
      appBar: AppBar(title: const Text('الفنيون')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('techAdd'),
        onPressed: _busy || all == null ? null : () => unawaited(_add()),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('إضافة فني'),
      ),
      body: all == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Text(
                  'حسابات الموظفين تظهر هنا تلقائياً، وتستطيع إضافة فني بلا '
                  'حساب. الموقوف لا يظهر عند اختيار الفني في البطاقة، '
                  'وبطاقاته وتقريره باقية.',
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: 12),
                Text('النشطون (${active.length})', style: titleStyle),
                const SizedBox(height: 4),
                Card(
                  margin: EdgeInsets.zero,
                  child: active.isEmpty
                      ? const ListTile(title: Text('لا يوجد فني نشط بعد'))
                      : Column(children: [for (final t in active) _tile(t)]),
                ),
                if (stopped.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('الموقوفون (${stopped.length})', style: titleStyle),
                  const SizedBox(height: 4),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [for (final t in stopped) _tile(t)],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({
    required this.oldName,
    required this.cardsCount,
    required this.existing,
  });

  final String oldName;
  final int cardsCount;

  /// أسماء الفنيين الآخرين بمفتاح المقارنة.
  final Map<String, String> existing;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.oldName,
  );

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final clean = OilChangeTechniciansStore.normalize(_ctrl.text);
    final same = clean == widget.oldName;
    final merge = widget.existing[OilChangeTechniciansStore.keyOf(clean)];
    final notes = <String>[
      if (widget.cardsCount > 0)
        'يتغيّر الاسم في ${widget.cardsCount} بطاقة سابقة، فيبقى تقريره واحداً.',
      'تقييمات العملاء المحفوظة على الخادم تبقى باسم «${widget.oldName}».',
      if (merge != null && !same)
        '«$merge» موجود في القائمة: ستُجمع بطاقات الاثنين تحت اسم واحد.',
    ];
    return AlertDialog(
      title: const Text('تعديل اسم الفني'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('techRenameField'),
            controller: _ctrl,
            autofocus: true,
            maxLength: OilChangeTechniciansStore.maxNameLength,
            decoration: const InputDecoration(
              labelText: 'الاسم الجديد',
              border: OutlineInputBorder(),
            ),
          ),
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                n,
                style: TextStyle(
                  color: n.startsWith('«') ? cs.error : cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('techRenameSave'),
          onPressed: clean.isEmpty || same
              ? null
              : () => Navigator.pop(context, clean),
          child: const Text('حفظ الاسم'),
        ),
      ],
    );
  }
}
