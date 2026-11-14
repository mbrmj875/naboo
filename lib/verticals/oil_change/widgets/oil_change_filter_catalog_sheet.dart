import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../../guides/guide_anchor.dart';
import '../models/oil_change_filter_catalog_entry.dart';
import '../models/oil_change_filter_kind.dart';
import '../services/oil_change_filter_catalog_repository.dart';
import '../services/oil_change_filter_kinds_repository.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/iqd_money.dart';
import '../utils/oil_field_select_all.dart';
import 'oil_change_catalog_sheet_frame.dart';
import 'oil_change_royal_card.dart';

/// إدارة كتالوج الفلاتر (فئة + اسم + سعر) أو اختيار صنف للبطاقة.
Future<OilChangeFilterPick?> showOilChangeFilterCatalogSheet(
  BuildContext context, {
  bool manageOnly = false,
  OilChangeFilterKind? initialKind,
}) {
  return showModalBottomSheet<OilChangeFilterPick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    enableDrag: false,
    showDragHandle: true,
    builder: (ctx) => _OilChangeFilterCatalogSheetBody(
      manageOnly: manageOnly,
      initialKind: initialKind ?? OilChangeFilterKind.engine,
    ),
  );
}

class _OilChangeFilterCatalogSheetBody extends StatefulWidget {
  const _OilChangeFilterCatalogSheetBody({
    required this.initialKind,
    this.manageOnly = false,
  });

  final bool manageOnly;
  final OilChangeFilterKind initialKind;

  @override
  State<_OilChangeFilterCatalogSheetBody> createState() =>
      _OilChangeFilterCatalogSheetBodyState();
}

class _OilChangeFilterCatalogSheetBodyState
    extends State<_OilChangeFilterCatalogSheetBody> {
  late OilChangeFilterKind _kind;
  List<OilChangeFilterKind> _kinds = List.from(OilChangeFilterKind.builtins);
  bool _loading = true;
  Object? _error;
  List<OilChangeFilterCatalogEntry> _entries = const [];
  bool _adding = false;
  int? _editingId;

  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  final _priceFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    if (widget.manageOnly) _adding = true;
    unawaited(_load());
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _priceFocus.dispose();
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final kinds =
          await OilChangeFilterKindsRepository.instance.listActive();
      final list =
          await OilChangeFilterCatalogRepository.instance.listActive();
      final resolved = [
        for (final e in list) e.withResolvedKind(kinds),
      ];
      if (!mounted) return;
      var selected = _kind;
      if (kinds.isNotEmpty &&
          !kinds.any((k) => k.code == selected.code)) {
        selected = kinds.first;
      }
      setState(() {
        _kinds = kinds.isEmpty
            ? List.from(OilChangeFilterKind.builtins)
            : kinds;
        _kind = selected;
        _entries = resolved;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<OilChangeFilterCatalogEntry> get _kindEntries =>
      OilChangeFilterCatalogRepository.entriesForKind(_entries, _kind);

  Future<void> _promptAddKind() async {
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => const _FilterKindLabelDialog(
        title: 'إضافة فئة فلتر',
        hintText: 'مثال: فلتر المقصورة',
        confirmLabel: 'إضافة',
      ),
    );
    if (label == null || label.isEmpty || !mounted) return;
    try {
      final kind =
          await OilChangeFilterKindsRepository.instance.insert(labelAr: label);
      if (!mounted) return;
      await _load(silent: true);
      if (!mounted) return;
      setState(() {
        _kind = kind;
        _editingId = null;
        _nameCtrl.clear();
        _priceCtrl.clear();
        _adding = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('أُضيفت فئة «${kind.label}»')),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      final msg = e.message == 'duplicate_label'
          ? 'يوجد فئة بنفس الاسم'
          : 'تعذّر إضافة الفئة';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر إضافة الفئة')),
      );
    }
  }

  Future<void> _promptRenameKind(OilChangeFilterKind kind) async {
    final id = kind.id;
    if (id == null || id <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أعد فتح الكتالوج ثم حاول مجدداً')),
      );
      return;
    }
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => _FilterKindLabelDialog(
        title: 'تعديل اسم الفئة',
        initialText: kind.label,
        confirmLabel: 'حفظ',
      ),
    );
    if (label == null || label.isEmpty || !mounted) return;
    try {
      await OilChangeFilterKindsRepository.instance.rename(
        id: id,
        labelAr: label,
      );
      if (!mounted) return;
      await _load(silent: true);
    } on StateError catch (e) {
      if (!mounted) return;
      final msg = e.message == 'duplicate_label'
          ? 'يوجد فئة بنفس الاسم'
          : 'تعذّر التعديل';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر التعديل')),
      );
    }
  }

  Future<void> _promptDeleteKind(OilChangeFilterKind kind) async {
    final id = kind.id;
    if (id == null || id <= 0) return;
    if (_kinds.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب الإبقاء على فئة واحدة على الأقل')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الفئة؟'),
        content: Text(
          '«${kind.label}» ستُخفى من البطاقة والكتالوج. الأصناف السابقة تبقى في السجل.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await OilChangeFilterKindsRepository.instance.softDeleteById(id);
    if (!mounted) return;
    await _load(silent: true);
  }

  Future<void> _showKindActions(OilChangeFilterKind kind) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('تعديل اسم الفئة'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: Text(
                'حذف الفئة',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'rename') {
      await _promptRenameKind(kind);
    } else if (action == 'delete') {
      await _promptDeleteKind(kind);
    }
  }

  Future<void> _saveNew() async {
    final name = _nameCtrl.text.trim();
    final priceDinars = IraqiCurrencyFormat.parseIqdInt(_priceCtrl.text);
    final priceFils = IqdMoney.toFils(priceDinars.toDouble());
    if (priceFils <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل السعر')),
      );
      return;
    }
    final editingId = _editingId;
    final displayLabel = name.isEmpty
        ? IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(priceFils))
        : name;
    try {
      if (editingId != null) {
        await OilChangeFilterCatalogRepository.instance.updateById(
          id: editingId,
          kind: _kind,
          name: name,
          priceFils: priceFils,
        );
      } else {
        await OilChangeFilterCatalogRepository.instance.insert(
          kind: _kind,
          name: name,
          priceFils: priceFils,
        );
      }
      if (!mounted) return;
      final wasEdit = editingId != null;
      _nameCtrl.clear();
      _priceCtrl.clear();
      setState(() {
        _editingId = null;
        _adding = true;
      });
      await _load(silent: true);
      if (!mounted) return;
      _priceFocus.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasEdit
                ? 'تم تحديث «$displayLabel»'
                : 'تمت إضافة «$displayLabel» لـ ${_kind.label}',
          ),
        ),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      final msg = e.message == 'duplicate_kind_name'
          ? 'نفس الاسم موجود لهذه الفئة'
          : e.message == 'price_required'
              ? 'أدخل السعر'
              : 'تعذّر الحفظ';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر الحفظ')),
      );
    }
  }

  void _beginEdit(OilChangeFilterCatalogEntry e) {
    setState(() {
      _editingId = e.id;
      _kind = e.kind;
      _adding = true;
      _nameCtrl.text = e.name;
      _priceCtrl.text = IraqiCurrencyFormat.formatInt(
        IqdMoney.fromFils(e.priceFils).round(),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _priceFocus.requestFocus();
    });
  }

  Future<void> _delete(OilChangeFilterCatalogEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الصنف؟'),
        content: Text(
          e.name.trim().isEmpty
              ? 'صنف بسعر ${IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(e.priceFils))} لن يظهر في القوائم الجديدة.'
              : '«${e.name}» لن يظهر في القوائم الجديدة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await OilChangeFilterCatalogRepository.instance.softDeleteById(e.id);
    if (!mounted) return;
    if (_editingId == e.id) {
      setState(() {
        _editingId = null;
        _nameCtrl.clear();
        _priceCtrl.clear();
      });
    }
    await _load(silent: true);
  }

  void _pick(OilChangeFilterCatalogEntry e) {
    Navigator.pop(
      context,
      OilChangeFilterPick(
        kind: e.kind,
        name: e.name,
        priceFils: e.priceFils,
        catalogEntryId: e.id,
      ),
    );
  }

  Widget _entryActions(OilChangeFilterCatalogEntry e) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'تعديل',
          icon: const Icon(Icons.edit_outlined, size: 20),
          onPressed: () => _beginEdit(e),
        ),
        IconButton(
          tooltip: 'حذف',
          icon: const Icon(Icons.delete_outline_rounded, size: 20),
          onPressed: () => unawaited(_delete(e)),
        ),
        if (!widget.manageOnly) const Icon(Icons.chevron_left),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return OilChangeCatalogSheetFrame(
      title: 'كتالوج الفلاتر',
      icon: Icons.filter_alt_outlined,
      titleGuideAnchor: (row) => GuideAnchor(
        id: OilGuideAnchors.catalogFilterTitle,
        child: row,
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 16),
              children: [
                Text(
                  widget.manageOnly
                      ? 'أضف فئات فلاتر كما تحتاج، ولكل فئة سعراً (والاسم اختياري). اضغط مطوّلاً على الفئة لتعديلها أو حذفها.'
                      : 'اختر صنفاً للبطاقة أو أضف فئات/أصنافاً. الاسم اختياري.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                  textAlign: TextAlign.start,
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final k in _kinds) ...[
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: GestureDetector(
                            onLongPress: () => unawaited(_showKindActions(k)),
                            child: FilterChip(
                              selected: _kind.code == k.code,
                              showCheckmark: true,
                              label: Text(k.label.replaceFirst('فلتر ', '')),
                              onSelected: (_) {
                                setState(() {
                                  _kind = k;
                                  if (_editingId != null) {
                                    _editingId = null;
                                    _nameCtrl.clear();
                                    _priceCtrl.clear();
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                      ActionChip(
                        avatar: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('فئة'),
                        onPressed: () => unawaited(_promptAddKind()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: GuideAnchor(
                    id: OilGuideAnchors.catalogFilterAdd,
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        setState(() {
                          if (_adding) {
                            _adding = false;
                            _editingId = null;
                          } else {
                            _adding = true;
                          }
                        });
                        if (_adding) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _priceFocus.requestFocus();
                          });
                        }
                      },
                      icon: Icon(
                        _adding ? Icons.expand_less : Icons.add_rounded,
                      ),
                      label: Text(
                        _adding
                            ? (_editingId != null
                                ? 'إخفاء التعديل'
                                : 'إخفاء الإضافة')
                            : 'إضافة صنف',
                      ),
                    ),
                  ),
                ),
                if (_adding) ...[
                  const SizedBox(height: 8),
                  KeyedSubtree(
                    key: ValueKey(
                      'filter_catalog_form_${_editingId ?? 'new'}',
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_editingId != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'تعديل صنف موجود',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: cs.primary,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.start,
                            ),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _nameCtrl,
                                focusNode: _nameFocus,
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) =>
                                    _priceFocus.requestFocus(),
                                decoration: const InputDecoration(
                                  labelText: 'اسم الفلتر (اختياري)',
                                  hintText: 'مثال: تويوتا أصلي — يمكن تركه فارغاً',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _priceCtrl,
                                focusNode: _priceFocus,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => unawaited(_saveNew()),
                                onTap: () => selectAllOilFieldText(_priceCtrl),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  IraqiCurrencyFormat.moneyInputFormatter(),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'السعر',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                textDirection: TextDirection.ltr,
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton.filledTonal(
                              onPressed: () => unawaited(_saveNew()),
                              icon: Icon(
                                _editingId != null
                                    ? Icons.check_rounded
                                    : Icons.check_rounded,
                              ),
                              tooltip:
                                  _editingId != null ? 'حفظ التعديل' : 'حفظ',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'تعذّر تحميل الكتالوج',
                        style: TextStyle(color: cs.error),
                      ),
                    ),
                  )
                else if (_kindEntries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'لا توجد أصناف لـ ${_kind.label}.\nاضغط «إضافة صنف».',
                        style: TextStyle(color: cs.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < _kindEntries.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    OilChangeRoyalCard.listTileCard(
                      context: context,
                      cs: cs,
                      onTap: widget.manageOnly
                          ? null
                          : () => _pick(_kindEntries[i]),
                      child: ListTile(
                        title: Text(
                          _kindEntries[i].name.trim().isEmpty
                              ? 'بدون اسم'
                              : _kindEntries[i].name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _kindEntries[i].name.trim().isEmpty
                                ? cs.onSurfaceVariant
                                : null,
                            fontStyle: _kindEntries[i].name.trim().isEmpty
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                        subtitle: Text(
                          IraqiCurrencyFormat.formatIqd(
                            IqdMoney.fromFils(_kindEntries[i].priceFils),
                          ),
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.start,
                        ),
                        trailing: _entryActions(_kindEntries[i]),
                      ),
                    ),
                  ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

/// حوار اسم الفئة — يملك الـ controller ويتخلّص منه بأمان مع إزالة الحوار.
class _FilterKindLabelDialog extends StatefulWidget {
  const _FilterKindLabelDialog({
    required this.title,
    required this.confirmLabel,
    this.initialText = '',
    this.hintText,
  });

  final String title;
  final String confirmLabel;
  final String initialText;
  final String? hintText;

  @override
  State<_FilterKindLabelDialog> createState() => _FilterKindLabelDialogState();
}

class _FilterKindLabelDialogState extends State<_FilterKindLabelDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _ctrl.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'اسم الفئة',
          hintText: widget.hintText,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
