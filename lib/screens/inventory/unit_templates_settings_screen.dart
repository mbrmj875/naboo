import 'package:flutter/material.dart';

import '../../services/product_repository.dart';
import 'unit_template_editor_screen.dart';

/// قوالب الوحدات — بحث، نتائج، ربط بقاعدة البيانات (مرجع لوحدات البيع على المنتج).
class UnitTemplatesSettingsScreen extends StatefulWidget {
  const UnitTemplatesSettingsScreen({super.key});

  @override
  State<UnitTemplatesSettingsScreen> createState() =>
      _UnitTemplatesSettingsScreenState();
}

class _UnitTemplatesSettingsScreenState
    extends State<UnitTemplatesSettingsScreen> {
  final _repo = ProductRepository();

  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];
  final Map<int, List<Map<String, dynamic>>> _conversionsByTemplate = {};

  int? _filterTemplateId;
  bool _sortNameAsc = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      _rows = await _repo.listUnitTemplatesForSettings();
      _conversionsByTemplate.clear();
      for (final r in _rows) {
        final id = r['id'] as int;
        _conversionsByTemplate[id] =
            await _repo.listUnitTemplateConversions(id);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredSorted {
    var list = List<Map<String, dynamic>>.from(_rows);
    if (_filterTemplateId != null) {
      list = list.where((r) => r['id'] == _filterTemplateId).toList();
    }
    list.sort((a, b) {
      final an = (a['name'] as String).toLowerCase();
      final bn = (b['name'] as String).toLowerCase();
      final c = an.compareTo(bn);
      return _sortNameAsc ? c : -c;
    });
    return list;
  }

  void _clearFilter() {
    setState(() => _filterTemplateId = null);
  }

  String _subtitleLine(Map<String, dynamic> row) {
    final id = row['id'] as int;
    final convs = _conversionsByTemplate[id] ?? [];
    final base = (row['baseUnitName'] as String?)?.trim() ?? '';
    final parts = <String>[
      if (base.isNotEmpty) base,
      ...convs.map((c) => (c['unitName'] as String?)?.trim() ?? ''),
    ];
    return parts.where((s) => s.isNotEmpty).join(' / ');
  }

  Future<void> _openEditor({int? templateId}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (ctx) => UnitTemplateEditorScreen(templateId: templateId),
      ),
    );
    if (changed == true && mounted) await _reload();
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف القالب'),
          content: Text('حذف «${row['name']}»؟'),
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
      ),
    );
    if (ok != true || !mounted) return;
    await _repo.deleteUnitTemplate(row['id'] as int);
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم الحذف'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = cs.brightness == Brightness.dark
        ? const Color(0xFF121212)
        : const Color(0xFFF0F4F8);
    final surface = cs.surface;
    final border = cs.outlineVariant;

    final nameItems = <DropdownMenuItem<int?>>[
      const DropdownMenuItem<int?>(
        value: null,
        child: Text('الكل'),
      ),
      ..._rows.map(
        (r) => DropdownMenuItem<int?>(
          value: r['id'] as int,
          child: Text(
            r['name'] as String,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E3A5F),
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'قوالب الوحدات',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SearchCard(
                    surface: surface,
                    border: border,
                    filterTemplateId: _filterTemplateId,
                    nameItems: nameItems,
                    onFilterChanged: (v) =>
                        setState(() => _filterTemplateId = v),
                    onSearch: () => setState(() {}),
                    onCancelFilter: _clearFilter,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: () => _openEditor(),
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text('قالب جديد'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ResultsCard(
                    surface: surface,
                    border: border,
                    rows: _filteredSorted,
                    sortNameAsc: _sortNameAsc,
                    onToggleSort: () =>
                        setState(() => _sortNameAsc = !_sortNameAsc),
                    subtitleFor: _subtitleLine,
                    onEdit: (row) => _openEditor(templateId: row['id'] as int),
                    onDelete: _confirmDelete,
                    isActive: (row) =>
                        ((row['isActive'] as int?) ?? 1) == 1,
                  ),
                ],
              ),
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.surface,
    required this.border,
    required this.filterTemplateId,
    required this.nameItems,
    required this.onFilterChanged,
    required this.onSearch,
    required this.onCancelFilter,
  });

  final Color surface;
  final Color border;
  final int? filterTemplateId;
  final List<DropdownMenuItem<int?>> nameItems;
  final void Function(int?) onFilterChanged;
  final VoidCallback onSearch;
  final VoidCallback onCancelFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'بحث',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _OutlineLabeledDropdown<int?>(
            label: 'الاسم',
            value: filterTemplateId,
            items: nameItems,
            onChanged: onFilterChanged,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed: onCancelFilter,
                child: const Text('إلغاء الفلتر'),
              ),
              const SizedBox(width: 10),
              FilledButton.tonal(
                onPressed: onSearch,
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primaryContainer,
                  foregroundColor: cs.onPrimaryContainer,
                ),
                child: const Text('بحث'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultsCard extends StatelessWidget {
  const _ResultsCard({
    required this.surface,
    required this.border,
    required this.rows,
    required this.sortNameAsc,
    required this.onToggleSort,
    required this.subtitleFor,
    required this.onEdit,
    required this.onDelete,
    required this.isActive,
  });

  final Color surface;
  final Color border;
  final List<Map<String, dynamic>> rows;
  final bool sortNameAsc;
  final VoidCallback onToggleSort;
  final String Function(Map<String, dynamic>) subtitleFor;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(Map<String, dynamic>) onDelete;
  final bool Function(Map<String, dynamic>) isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                InkWell(
                  onTap: onToggleSort,
                  borderRadius: BorderRadius.zero,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          sortNameAsc
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 18,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'الترتيب حسب',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'النتائج',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: border),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
              child: Text(
                'لا توجد قوالب بعد.\nاضغط «قالب جديد» لإضافة قالب وربط وحدات البيع بالمنتجات.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              separatorBuilder: (context, index) =>
                  Divider(height: 1, color: border.withValues(alpha: 0.65)),
              itemBuilder: (context, i) {
                final row = rows[i];
                final active = isActive(row);
                final sub = subtitleFor(row);
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Material(
                        color: cs.primaryContainer.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.zero,
                        child: PopupMenuButton<String>(
                          padding: const EdgeInsets.all(8),
                          child: Icon(Icons.more_horiz,
                              color: cs.primary, size: 22),
                          onSelected: (v) {
                            if (v == 'edit') onEdit(row);
                            if (v == 'delete') onDelete(row);
                          },
                          itemBuilder: (ctx) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('تعديل'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('حذف'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFF15803D)
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.zero,
                        ),
                        child: Text(
                          active ? 'نشط' : 'غير نشط',
                          style: TextStyle(
                            color: active ? Colors.white : cs.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              row['name'] as String,
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (sub.isNotEmpty)
                              Text(
                                sub,
                                textAlign: TextAlign.right,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _OutlineLabeledDropdown<T> extends StatelessWidget {
  const _OutlineLabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
