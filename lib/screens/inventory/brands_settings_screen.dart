import 'package:flutter/material.dart';

import '../../services/product_repository.dart';

/// إدارة العلامات التجارية — واجهة بحث/قائمة، بدون بيانات وهمية (من قاعدة البيانات فقط).
class BrandsSettingsScreen extends StatefulWidget {
  const BrandsSettingsScreen({super.key});

  @override
  State<BrandsSettingsScreen> createState() => _BrandsSettingsScreenState();
}

class _BrandsSettingsScreenState extends State<BrandsSettingsScreen> {
  final _repo = ProductRepository();
  final _nameFilterCtrl = TextEditingController();

  bool _loading = true;
  bool _filterExpanded = true;
  bool _sortNameAsc = true;

  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _nameFilterCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      _rows = await _repo.listBrandsForSettings();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _nameFilterCtrl.text.trim().toLowerCase();
    var list = List<Map<String, dynamic>>.from(_rows);
    if (q.isNotEmpty) {
      list = list
          .where((r) => (r['name'] as String).toLowerCase().contains(q))
          .toList();
    }
    list.sort((a, b) {
      final an = (a['name'] as String).toLowerCase();
      final bn = (b['name'] as String).toLowerCase();
      final c = an.compareTo(bn);
      return _sortNameAsc ? c : -c;
    });
    return list;
  }

  Future<void> _showAddBrandDialog() async {
    final ctrl = TextEditingController();
    final theme = Theme.of(context);
    final err = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('ماركة جديدة'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                labelText: 'اسم الماركة',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                child: const Text('حفظ'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    if (err == null) return;
    final name = err.trim();
    if (name.isEmpty) return;

    final message = await _repo.insertBrandByName(name);
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
        content: const Text('تم حفظ الماركة'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: theme.colorScheme.primary,
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الماركة'),
          content: Text('حذف «${row['name']}»؟'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    await _repo.deleteBrand(row['id'] as int);
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

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          title: const Text(
            'العلامات التجارية',
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
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _showAddBrandDialog,
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('ماركة جديدة'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SearchFilterCard(
                    expanded: _filterExpanded,
                    nameController: _nameFilterCtrl,
                    onToggleExpand: () =>
                        setState(() => _filterExpanded = !_filterExpanded),
                    onSearch: () => setState(() {}),
                    onReset: () {
                      _nameFilterCtrl.clear();
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                  _BrandsTableCard(
                    sortAsc: _sortNameAsc,
                    onToggleSort: () =>
                        setState(() => _sortNameAsc = !_sortNameAsc),
                    rows: _filtered,
                    onMenuDelete: _confirmDelete,
                  ),
                ],
              ),
      ),
    );
  }
}

class _SearchFilterCard extends StatelessWidget {
  const _SearchFilterCard({
    required this.expanded,
    required this.nameController,
    required this.onToggleExpand,
    required this.onSearch,
    required this.onReset,
  });

  final bool expanded;
  final TextEditingController nameController;
  final VoidCallback onToggleExpand;
  final VoidCallback onSearch;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'بحث وتصفية',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onToggleExpand,
                  icon: Icon(
                    expanded ? Icons.horizontal_rule : Icons.add,
                    size: 18,
                  ),
                  label: Text(expanded ? 'إخفاء' : 'إظهار'),
                ),
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: nameController,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        hintText: 'الاسم',
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      onSubmitted: (_) => onSearch(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: onSearch,
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primaryContainer,
                      foregroundColor: cs.onPrimaryContainer,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                    ),
                    child: const Text('بحث'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onReset,
                    child: const Text('إعادة تعيين'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BrandsTableCard extends StatelessWidget {
  const _BrandsTableCard({
    required this.sortAsc,
    required this.onToggleSort,
    required this.rows,
    required this.onMenuDelete,
  });

  final bool sortAsc;
  final VoidCallback onToggleSort;
  final List<Map<String, dynamic>> rows;
  final void Function(Map<String, dynamic>) onMenuDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                InkWell(
                  onTap: onToggleSort,
                  borderRadius: BorderRadius.zero,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          sortAsc
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 18,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'ترتيب',
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
                  'الاسم',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Text(
                'لا توجد علامات تجارية بعد.\nاضغط «ماركة جديدة» لإضافة أول ماركة.',
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
                  Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
              itemBuilder: (context, i) {
                final row = rows[i];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Material(
                        color: cs.primaryContainer.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.zero,
                        child: PopupMenuButton<String>(
                          padding: const EdgeInsets.all(8),
                          child: Icon(Icons.more_horiz,
                              color: cs.primary, size: 20),
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
                        child: Text(
                          row['name'] as String,
                          textAlign: TextAlign.right,
                          style: theme.textTheme.bodyLarge,
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
