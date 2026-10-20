import 'package:flutter/material.dart';

import '../models/oil_change_rating.dart';
import '../services/oil_change_ratings_repository.dart';
import '../services/oil_change_technicians_store.dart';

/// حقل اختيار الفني المسؤول من قائمة محفوظة، مع زر إضافة اسم جديد.
///
/// الاسم المختار يُرسل مع بطاقة واتساب ويُسنَد إليه تقييم العميل، لذلك
/// الاختيار من قائمة ثابتة بدل الكتابة الحرة يمنع تشتّت الأسماء.
class OilChangeTechnicianField extends StatefulWidget {
  const OilChangeTechnicianField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.isDense = false,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isDense;

  @override
  State<OilChangeTechnicianField> createState() =>
      _OilChangeTechnicianFieldState();
}

class _OilChangeTechnicianFieldState extends State<OilChangeTechnicianField> {
  final _store = OilChangeTechniciansStore.instance;

  List<String> _names = const [];
  Map<String, OilChangeEmployeeRatingSummary> _ratings = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // تحميل بطاقة قديمة يضبط النص من خارج الودجت، فنعيد بناء سطر التقييم.
    widget.controller.addListener(_onControllerChanged);
    _load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final names = await _store.load();
    if (!mounted) return;
    setState(() {
      _names = names;
      _loading = false;
    });
    await _loadRatings();
  }

  /// التقييمات إضافة معلوماتية فقط — غيابها (بلا إنترنت) لا يعطّل الحقل.
  Future<void> _loadRatings() async {
    try {
      final rows =
          await OilChangeRatingsRepository.instance.loadEmployeeSummary();
      if (!mounted) return;
      setState(() {
        _ratings = {
          for (final r in rows)
            OilChangeTechniciansStore.normalize(r.employeeName).toLowerCase(): r,
        };
      });
    } catch (_) {
      // تُتجاهل: الحقل يعمل بلا تقييمات.
    }
  }

  OilChangeEmployeeRatingSummary? _summaryFor(String name) =>
      _ratings[OilChangeTechniciansStore.normalize(name).toLowerCase()];

  Future<void> _openPicker() async {
    if (!widget.enabled) return;
    if (_loading) return;

    final picked = await showModalBottomSheet<_PickerResult>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _TechnicianPickerSheet(
        names: _names,
        selected: widget.controller.text.trim(),
        summaryFor: _summaryFor,
        onDelete: _confirmDelete,
      ),
    );
    if (!mounted || picked == null) return;

    switch (picked.action) {
      case _PickerAction.select:
        setState(() => widget.controller.text = picked.name ?? '');
        break;
      case _PickerAction.clear:
        setState(() => widget.controller.clear());
        break;
      case _PickerAction.add:
        await _promptAdd();
        break;
    }
  }

  Future<void> _promptAdd() async {
    if (!widget.enabled) return;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _AddTechnicianDialog(),
    );
    if (!mounted) return;
    final clean = OilChangeTechniciansStore.normalize(name ?? '');
    if (clean.isEmpty) return;

    final names = await _store.add(clean);
    if (!mounted) return;
    setState(() {
      _names = names;
      widget.controller.text = clean;
    });
  }

  /// يُستدعى من داخل الورقة، لذلك يعيد النتيجة بدل تعديل الحالة مباشرة.
  Future<bool> _confirmDelete(BuildContext sheetContext, String name) async {
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الفني'),
        content: Text('حذف «$name» من القائمة؟ التقييمات السابقة تبقى محفوظة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    final names = await _store.remove(name);
    if (!mounted) return true;
    setState(() {
      _names = names;
      if (widget.controller.text.trim().toLowerCase() == name.toLowerCase()) {
        widget.controller.clear();
      }
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.controller.text.trim();
    final summary = selected.isEmpty ? null : _summaryFor(selected);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: widget.controller,
            enabled: widget.enabled,
            readOnly: true,
            onTap: _openPicker,
            decoration: InputDecoration(
              labelText: 'اسم الفني المسؤول',
              border: const OutlineInputBorder(),
              isDense: widget.isDense,
              prefixIcon: const Icon(Icons.handyman_rounded, size: 20),
              hintText: _loading ? 'جاري التحميل…' : 'اختر من القائمة',
              helperText: summary == null
                  ? null
                  : _summaryLabel(summary),
              suffixIcon: Icon(
                Icons.arrow_drop_down_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            textAlign: TextAlign.start,
          ),
        ),
        const SizedBox(width: 4),
        IconButton.filledTonal(
          onPressed: widget.enabled ? _promptAdd : null,
          tooltip: 'إضافة فني جديد',
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

String _summaryLabel(OilChangeEmployeeRatingSummary s) {
  if (s.averageScore == null || s.ratingsCount == 0) {
    return 'لا توجد تقييمات بعد';
  }
  return 'التقييم ${s.averageScore!.toStringAsFixed(1)} من 10 '
      '· ${s.ratingsCount} تقييم';
}

enum _PickerAction { select, clear, add }

class _PickerResult {
  const _PickerResult(this.action, [this.name]);

  final _PickerAction action;
  final String? name;
}

class _TechnicianPickerSheet extends StatelessWidget {
  const _TechnicianPickerSheet({
    required this.names,
    required this.selected,
    required this.summaryFor,
    required this.onDelete,
  });

  final List<String> names;
  final String selected;
  final OilChangeEmployeeRatingSummary? Function(String name) summaryFor;
  final Future<bool> Function(BuildContext context, String name) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
              child: Text(
                'اختر الفني المسؤول',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.start,
              ),
            ),
            if (names.isEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 16),
                child: Text(
                  'لا توجد أسماء محفوظة بعد. أضف الفني ليظهر في القائمة '
                  'وتُسنَد إليه تقييمات العملاء.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.start,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: names.length,
                  itemBuilder: (context, index) {
                    final name = names[index];
                    final summary = summaryFor(name);
                    final isSelected =
                        name.toLowerCase() == selected.toLowerCase();
                    return ListTile(
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: isSelected ? theme.colorScheme.primary : null,
                      ),
                      title: Text(name, textAlign: TextAlign.start),
                      subtitle: Text(
                        summary == null
                            ? 'لا توجد تقييمات بعد'
                            : _summaryLabel(summary),
                        textAlign: TextAlign.start,
                      ),
                      trailing: IconButton(
                        onPressed: () async {
                          final removed = await onDelete(context, name);
                          if (removed && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                        tooltip: 'حذف',
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                      onTap: () => Navigator.pop(
                        context,
                        _PickerResult(_PickerAction.select, name),
                      ),
                    );
                  },
                ),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_rounded),
              title: const Text('إضافة فني جديد', textAlign: TextAlign.start),
              onTap: () => Navigator.pop(
                context,
                const _PickerResult(_PickerAction.add),
              ),
            ),
            if (selected.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('بدون فني', textAlign: TextAlign.start),
                onTap: () => Navigator.pop(
                  context,
                  const _PickerResult(_PickerAction.clear),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _AddTechnicianDialog extends StatefulWidget {
  const _AddTechnicianDialog();

  @override
  State<_AddTechnicianDialog> createState() => _AddTechnicianDialogState();
}

class _AddTechnicianDialogState extends State<_AddTechnicianDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = OilChangeTechniciansStore.normalize(_controller.text);
    if (name.isEmpty) {
      setState(() => _error = 'اكتب اسم الفني');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة فني'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        maxLength: OilChangeTechniciansStore.maxNameLength,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'اسم الفني',
          hintText: 'مثال: أحمد علي',
          border: const OutlineInputBorder(),
          errorText: _error,
        ),
        textAlign: TextAlign.start,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _submit, child: const Text('حفظ')),
      ],
    );
  }
}
