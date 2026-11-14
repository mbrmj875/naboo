import 'package:flutter/material.dart';

import '../../services/product_repository.dart';
import '../../theme/design_tokens.dart';
import '../../utils/screen_layout.dart';

/// إعدادات التصنيفات — بحث/فلترة وقائمة نتائج (بدون بيانات وهمية).
class CategoriesSettingsScreen extends StatefulWidget {
  const CategoriesSettingsScreen({super.key});

  @override
  State<CategoriesSettingsScreen> createState() =>
      _CategoriesSettingsScreenState();
}

class _CategoriesSettingsScreenState extends State<CategoriesSettingsScreen> {
  final _repo = ProductRepository();

  static const int _kParentAll = -1;
  static const int _kParentRootsOnly = -2;

  bool _loading = true;

  List<Map<String, dynamic>> _rows = [];

  int? _nameFilterId;
  int _parentFilter = _kParentAll;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      _rows = await _repo.listCategoriesForSettings();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = List<Map<String, dynamic>>.from(_rows);
    if (_nameFilterId != null) {
      list = list.where((r) => r['id'] == _nameFilterId).toList();
    }
    if (_parentFilter == _kParentRootsOnly) {
      list = list.where((r) => r['parentId'] == null).toList();
    } else if (_parentFilter != _kParentAll) {
      list = list.where((r) => r['parentId'] == _parentFilter).toList();
    }
    return list;
  }

  void _clearFilters() {
    setState(() {
      _nameFilterId = null;
      _parentFilter = _kParentAll;
    });
  }

  Future<void> _showAddCategoryDialog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    int? parentId;

    final err = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (context, setModal) {
              final parents =
                  _rows.map((r) => Map<String, dynamic>.from(r)).toList()..sort(
                    (a, b) => (a['name'] as String).toLowerCase().compareTo(
                      (b['name'] as String).toLowerCase(),
                    ),
                  );

              return AlertDialog(
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppColors.accentGold.withValues(alpha: 0.5)),
                ),
                title: const Text('تصنيف جديد'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        autofocus: true,
                        textAlign: TextAlign.right,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                        decoration: InputDecoration(
                          labelText: 'الاسم',
                          labelStyle: const TextStyle(color: AppColors.accentGold),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AppColors.accentGold.withValues(alpha: 0.5)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.accentGold, width: 2),
                          ),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _OutlineLabeledDropdown<int?>(
                        label: 'التصنيف الرئيسي',
                        value: parentId,
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('بدون (تصنيف رئيسي)'),
                          ),
                          ...parents.map(
                            (r) => DropdownMenuItem<int?>(
                              value: r['id'] as int,
                              child: Text(
                                r['name'] as String,
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) => setModal(() => parentId = v),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: descCtrl,
                        textAlign: TextAlign.right,
                        maxLines: 4,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                        decoration: InputDecoration(
                          labelText: 'الوصف',
                          alignLabelWithHint: true,
                          labelStyle: const TextStyle(color: AppColors.accentGold),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AppColors.accentGold.withValues(alpha: 0.5)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.accentGold, width: 2),
                          ),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accentGold,
                      side: const BorderSide(color: AppColors.accentGold),
                    ),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, 'save'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentGold.withValues(alpha: 0.2),
                      foregroundColor: AppColors.accentGold,
                    ),
                    child: const Text('حفظ'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (!mounted || err != 'save') {
      nameCtrl.dispose();
      descCtrl.dispose();
      return;
    }

    final message = await _repo.insertCategory(
      name: nameCtrl.text,
      parentId: parentId,
      description: descCtrl.text,
    );
    nameCtrl.dispose();
    descCtrl.dispose();

    if (!mounted) return;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('تم حفظ التصنيف'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.accentGold.withValues(alpha: 0.5)),
          ),
          title: const Text('حذف التصنيف'),
          content: Text('حذف «${row['name']}»؟'),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentGold,
                side: const BorderSide(color: AppColors.accentGold),
              ),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.withValues(alpha: 0.2),
                foregroundColor: Colors.redAccent,
              ),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final message = await _repo.deleteCategory(row['id'] as int);
    if (!mounted) return;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
      return;
    }
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

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerHighest,
          foregroundColor: cs.onSurface,
          iconTheme: IconThemeData(color: cs.onSurface),
          elevation: 0,
          title: Text(
            'التصنيفات',
            style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold, fontSize: 17),
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
                    nameFilterId: _nameFilterId,
                    parentFilter: _parentFilter,
                    kParentAll: _kParentAll,
                    kParentRootsOnly: _kParentRootsOnly,
                    rows: _rows,
                    onNameChanged: (v) => setState(() => _nameFilterId = v),
                    onParentChanged: (v) =>
                        setState(() => _parentFilter = v ?? _kParentAll),
                    onSearch: () => setState(() {}),
                    onCancelFilter: _clearFilters,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _showAddCategoryDialog,
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text('إضافة تصنيف جديد'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accentGold.withValues(alpha: 0.2),
                          foregroundColor: AppColors.accentGold,
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
                    rows: _filtered,
                    onMenuDelete: _confirmDelete,
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
    required this.nameFilterId,
    required this.parentFilter,
    required this.kParentAll,
    required this.kParentRootsOnly,
    required this.rows,
    required this.onNameChanged,
    required this.onParentChanged,
    required this.onSearch,
    required this.onCancelFilter,
  });

  final Color surface;
  final Color border;
  final int? nameFilterId;
  final int parentFilter;
  final int kParentAll;
  final int kParentRootsOnly;
  final List<Map<String, dynamic>> rows;
  final void Function(int?) onNameChanged;
  final void Function(int?) onParentChanged;
  final VoidCallback onSearch;
  final VoidCallback onCancelFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final nameItems = <DropdownMenuItem<int?>>[
      const DropdownMenuItem<int?>(value: null, child: Text('الكل')),
      ...rows.map(
        (r) => DropdownMenuItem<int?>(
          value: r['id'] as int,
          child: Text(r['name'] as String, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];

    final parentItems = <DropdownMenuItem<int>>[
      DropdownMenuItem<int>(value: kParentAll, child: const Text('الكل')),
      DropdownMenuItem<int>(
        value: kParentRootsOnly,
        child: const Text('جذور فقط (بدون أب)'),
      ),
      ...rows.map(
        (r) => DropdownMenuItem<int>(
          value: r['id'] as int,
          child: Text('تحت: ${r['name']}', overflow: TextOverflow.ellipsis),
        ),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              'بحث',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _OutlineLabeledDropdown<int?>(
                  label: 'الاسم',
                  value: nameFilterId,
                  items: nameItems,
                  onChanged: onNameChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _OutlineLabeledDropdown<int>(
                  label: 'التصنيف الرئيسي',
                  value: parentFilter,
                  items: parentItems,
                  onChanged: onParentChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Spacer(),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accentGold,
                  side: const BorderSide(color: AppColors.accentGold),
                ),
                onPressed: onCancelFilter,
                child: const Text('إلغاء الفلتر'),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: onSearch,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentGold.withValues(alpha: 0.2),
                  foregroundColor: AppColors.accentGold,
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
    required this.onMenuDelete,
  });

  final Color surface;
  final Color border;
  final List<Map<String, dynamic>> rows;
  final void Function(Map<String, dynamic>) onMenuDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: ScreenLayout.of(context).pageHorizontalGap,
              end: ScreenLayout.of(context).pageHorizontalGap,
              top: 14,
              bottom: 8,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                'النتائج',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Divider(height: 1, color: border),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
              child: Text(
                'لا توجد تصنيفات مطابقة.\nأضف تصنيفاً جديداً أو غيّر الفلتر.',
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
                final parentName = row['parentName'] as String?;
                final subtitle = parentName != null && parentName.isNotEmpty
                    ? 'تحت: $parentName'
                    : null;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Material(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        child: PopupMenuButton<String>(
                          padding: const EdgeInsets.all(8),
                          child: const Icon(
                            Icons.more_horiz,
                            color: AppColors.accentGold,
                            size: 22,
                          ),
                          onSelected: (v) {
                            if (v == 'delete') onMenuDelete(row);
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('حذف'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              row['name'] as String,
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodyLarge,
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle,
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
        labelStyle: const TextStyle(color: AppColors.accentGold),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.accentGold.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accentGold, width: 2),
        ),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          dropdownColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          isExpanded: true,
          value: value,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
