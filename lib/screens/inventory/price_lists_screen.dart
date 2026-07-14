import 'dart:async';
import 'package:flutter/material.dart';
import 'package:naboo/services/price_list_repository.dart';
import 'package:naboo/theme/design_tokens.dart';
import 'package:naboo/widgets/inputs/app_price_input.dart';
import 'package:naboo/utils/iraqi_currency_format.dart';
import 'package:naboo/utils/app_logger.dart';

class PriceListsScreen extends StatefulWidget {
  const PriceListsScreen({super.key});

  @override
  State<PriceListsScreen> createState() => _PriceListsScreenState();
}

class _PriceListsScreenState extends State<PriceListsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _repo = PriceListRepository();
  
  List<Map<String, dynamic>> _lists = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await _repo.listPriceLists();
      if (mounted) {
        setState(() {
          _lists = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'حدث خطأ أثناء جلب القوائم: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _setDefault(int id) async {
    try {
      await _repo.setDefaultPriceList(id);
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل التعيين كافتراضي: $e')),
        );
      }
    }
  }

  Future<void> _openForm([Map<String, dynamic>? existing]) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PriceListForm(existing: existing, repo: _repo),
    );
    if (result == true) {
      unawaited(_loadData());
    }
  }

  Future<void> _delete(Map<String, dynamic> l) async {
    final id = l['id'] as int;
    final isDefault = (l['isDefault'] as int?) == 1;
    
    if (isDefault) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن حذف القائمة الافتراضية')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('حذف قائمة الأسعار'),
          content: Text('هل تريد حذف «${l['name']}» نهائياً؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      try {
        final success = await _repo.deletePriceList(id);
        if (success) {
          unawaited(_loadData());
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('لا يمكن حذف هذه القائمة.')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ أثناء الحذف: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: const Text(
            'قوائم الأسعار',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          elevation: 0,
          bottom: TabBar(
            controller: _tab,
            indicatorColor: AppColors.accentGold,
            labelColor: AppColors.accentGold,
            unselectedLabelColor: cs.onSurfaceVariant,
            tabs: const [
              Tab(text: 'القوائم'),
              Tab(text: 'منتجات بحسب القائمة'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.accentGold,
          foregroundColor: AppColors.primaryDark,
          onPressed: () => _openForm(),
          icon: const Icon(Icons.add_rounded),
          label: const Text(
            'قائمة جديدة',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: TabBarView(
          controller: _tab,
          children: [
            // ── Tab 1: Lists ──────────────────────────────────────────────
            _buildListsTab(cs),

            // ── Tab 2: Products per list (P2) ──────────────────────────────
            _ComparisonTab(repo: _repo, lists: _lists),
          ],
        ),
      ),
    );
  }

  Widget _buildListsTab(ColorScheme cs) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accentGold));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: cs.error)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    if (_lists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.price_change_outlined, size: 72, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'لا توجد قوائم أسعار بعد',
              style: TextStyle(fontSize: 18, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
      itemCount: _lists.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _PriceListCard(
        data: _lists[i],
        onEdit: () => _openForm(_lists[i]),
        onDelete: () => _delete(_lists[i]),
        onSetDefault: () => _setDefault(_lists[i]['id'] as int),
        onViewItems: () => _showItems(context, _lists[i]),
      ),
    );
  }

  void _showItems(BuildContext ctx, Map<String, dynamic> list) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PriceItemsSheet(list: list, repo: _repo),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Price List Card
// ══════════════════════════════════════════════════════════════════════════════
class _PriceListCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;
  final VoidCallback onViewItems;
  
  const _PriceListCard({
    required this.data,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
    required this.onViewItems,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDefault = (data['isDefault'] as int?) == 1;
    final dateStr = (data['createdAt'] as String?)?.substring(0, 10) ?? '';
    final color = AppColors.accentGold;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDefault ? color : cs.outlineVariant,
          width: isDefault ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.price_change_rounded,
                    color: color,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              data['name']?.toString() ?? '',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          if (isDefault)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Text(
                                'افتراضي',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        data['description']?.toString() ?? 'بدون وصف',
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  iconColor: cs.onSurfaceVariant,
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                    if (v == 'default') onSetDefault();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('تعديل'),
                        ],
                      ),
                    ),
                    if (!isDefault)
                      const PopupMenuItem(
                        value: 'default',
                        child: Row(
                          children: [
                            Icon(Icons.star_outline_rounded, size: 18),
                            SizedBox(width: 8),
                            Text('تعيين كافتراضي'),
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: cs.error,
                          ),
                          const SizedBox(width: 8),
                          Text('حذف', style: TextStyle(color: cs.error)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          // ── Footer ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  dateStr,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: onViewItems,
                  style: FilledButton.styleFrom(
                    backgroundColor: color.withValues(alpha: 0.15),
                    foregroundColor: color,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.settings_suggest_outlined, size: 18),
                  label: const Text('إدارة الأسعار'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Price Items Sheet
// ══════════════════════════════════════════════════════════════════════════════
class _PriceItemsSheet extends StatefulWidget {
  final Map<String, dynamic> list;
  final PriceListRepository repo;
  const _PriceItemsSheet({required this.list, required this.repo});

  @override
  State<_PriceItemsSheet> createState() => _PriceItemsSheetState();
}

class _PriceItemsSheetState extends State<_PriceItemsSheet> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadItems([String query = '']) async {
    setState(() => _isLoading = true);
    try {
      final listId = widget.list['id'] as int;
      final res = await widget.repo.listPriceListItems(listId, query: query);
      if (mounted) {
        setState(() {
          _items = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppLogger.error('PriceItemsSheet', 'Failed to load price items: $e');
      }
    }
  }

  void _onSearchChanged(String val) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _loadItems(val);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = AppColors.accentGold;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.price_change_rounded, color: color, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'أسعار ${widget.list['name']}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'ابحث برقم الباركود أو اسم المنتج...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accentGold))
                  : _items.isEmpty
                      ? Center(child: Text('لا توجد منتجات', style: TextStyle(color: cs.onSurfaceVariant)))
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: cs.outlineVariant),
                          itemBuilder: (ctx, i) {
                            return _PriceItemRow(
                              item: _items[i],
                              listId: widget.list['id'] as int,
                              repo: widget.repo,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceItemRow extends StatefulWidget {
  final Map<String, dynamic> item;
  final int listId;
  final PriceListRepository repo;

  const _PriceItemRow({
    required this.item,
    required this.listId,
    required this.repo,
  });

  @override
  State<_PriceItemRow> createState() => _PriceItemRowState();
}

class _PriceItemRowState extends State<_PriceItemRow> {
  late double _currentPrice;
  late TextEditingController _priceCtrl;
  Timer? _debounce;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final customPrice = (widget.item['customPrice'] as num?)?.toDouble();
    final defaultPrice = (widget.item['defaultSellPrice'] as num?)?.toDouble() ?? 0.0;
    _currentPrice = customPrice ?? defaultPrice;
    _priceCtrl = TextEditingController(text: _currentPrice.toInt().toString());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _onPriceChanged(double newPrice) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    // Save previous in case of revert
    final prevPrice = _currentPrice;
    
    setState(() {
      _currentPrice = newPrice;
      _isSaving = true;
    });

    _debounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        final productId = widget.item['productId'] as int;
        await widget.repo.savePriceListItem(widget.listId, productId, newPrice);
        if (mounted) {
          setState(() => _isSaving = false);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _currentPrice = prevPrice;
            _isSaving = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('خطأ أثناء حفظ السعر. تمت إعادة القيمة السابقة.'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = widget.item['productName']?.toString() ?? '';
    final barcode = widget.item['barcode']?.toString() ?? 'بدون باركود';
    final buyPrice = (widget.item['buyPrice'] as num?)?.toDouble() ?? 0.0;
    
    final hasCustomPrice = widget.item['customPrice'] != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  barcode,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  'الشراء: ${IraqiCurrencyFormat.formatInt(buyPrice)} د.ع',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AppPriceInput(
                  label: 'السعر المخصص',
                  controller: _priceCtrl,
                  onParsedChanged: (int val) => _onPriceChanged(val.toDouble()),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isSaving)
                      const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentGold))
                    else if (hasCustomPrice)
                      const Icon(Icons.check_circle_rounded, size: 14, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      hasCustomPrice ? 'مخصص' : 'الافتراضي',
                      style: TextStyle(
                        fontSize: 10,
                        color: hasCustomPrice ? Colors.green : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Create / Edit Price List Form
// ══════════════════════════════════════════════════════════════════════════════
class _PriceListForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final PriceListRepository repo;
  const _PriceListForm({this.existing, required this.repo});

  @override
  State<_PriceListForm> createState() => _PriceListFormState();
}

class _PriceListFormState extends State<_PriceListForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _desc;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name'] ?? '');
    _desc = TextEditingController(text: e?['description'] ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    
    try {
      if (widget.existing != null) {
        final id = widget.existing!['id'] as int;
        await widget.repo.updatePriceList(id, _name.text.trim(), _desc.text.trim());
      } else {
        await widget.repo.createPriceList(_name.text.trim(), _desc.text.trim());
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء الحفظ: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.existing != null ? 'تعديل القائمة' : 'قائمة أسعار جديدة',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: 'اسم القائمة *',
                  prefixIcon: Icon(Icons.label_outline, color: cs.onSurfaceVariant),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.accentGold, width: 2),
                  ),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _desc,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'الوصف',
                  prefixIcon: Icon(Icons.description_outlined, color: cs.onSurfaceVariant),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.accentGold, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isSaving ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentGold,
                  foregroundColor: AppColors.primaryDark,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(color: AppColors.primaryDark, strokeWidth: 2),
                      )
                    : Text(
                        widget.existing != null ? 'حفظ التعديلات' : 'إنشاء القائمة',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2 — Smart comparison view (P2)
// ─────────────────────────────────────────────────────────────────────────────

class _ComparisonTab extends StatefulWidget {
  const _ComparisonTab({required this.repo, required this.lists});

  final PriceListRepository repo;
  final List<Map<String, dynamic>> lists;

  @override
  State<_ComparisonTab> createState() => _ComparisonTabState();
}

class _ComparisonTabState extends State<_ComparisonTab> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<Map<String, dynamic>> _rows = const [];
  String? _error;

  static const int _kInitialLimit = 100;
  static const int _kSearchLimit = 200;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ComparisonTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lists.length != widget.lists.length) {
      _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = _search.text.trim();
      final rows = await widget.repo.searchComparisonMatrix(
        query: q,
        limit: q.isEmpty ? _kInitialLimit : _kSearchLimit,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.error('PriceLists', 'comparison load failed', e, st);
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل المقارنة: $e';
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), _load);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        // ── Search bar ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'ابحث باسم المنتج أو الباركود…',
              prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'مسح',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _search.clear();
                        _load();
                        setState(() {});
                      },
                    ),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.accentGold, width: 2),
              ),
              isDense: true,
            ),
          ),
        ),
        // ── Hint banner ────────────────────────────────────────────────────
        if (_search.text.trim().isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'يعرض أول $_kInitialLimit منتج — ابحث للوصول إلى منتج بعينه.',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 1),
        Expanded(child: _buildBody(cs)),
      ],
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accentGold),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 56, color: cs.error),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurface)),
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: _load, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox_outlined,
                  size: 64,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                _search.text.trim().isEmpty
                    ? 'لا توجد منتجات نشطة لعرضها.'
                    : 'لا توجد نتائج مطابقة للبحث.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }
    if (widget.lists.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'أنشئ قائمة أسعار من تبويب «القوائم» لبدء المقارنة.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _rows.length,
      cacheExtent: 800,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _ComparisonRowCard(
        row: _rows[i],
        lists: widget.lists,
      ),
    );
  }
}

class _ComparisonRowCard extends StatelessWidget {
  const _ComparisonRowCard({required this.row, required this.lists});

  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> lists;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = (row['productName'] as String?) ?? '—';
    final barcode = (row['barcode'] as String?)?.trim() ?? '';
    final defPrice = (row['defaultSellPrice'] as num?)?.toDouble() ?? 0;
    final prices = (row['prices'] as Map?)?.cast<int, double>() ?? const {};

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    if (barcode.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        barcode,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                          fontFamilyFallback: const ['monospace'],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _PriceChip(
                label: 'السعر الافتراضي',
                value: defPrice,
                bold: true,
              ),
            ],
          ),
          if (lists.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final l in lists)
                  _PriceChip(
                    label: (l['name'] as String?) ?? 'قائمة',
                    value: prices[(l['id'] as num).toInt()],
                    isDefaultList: ((l['isDefault'] as int?) ?? 0) == 1,
                    fallbackPrice: defPrice,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PriceChip extends StatelessWidget {
  const _PriceChip({
    required this.label,
    required this.value,
    this.bold = false,
    this.isDefaultList = false,
    this.fallbackPrice,
  });

  final String label;
  final double? value;
  final bool bold;
  final bool isDefaultList;
  final double? fallbackPrice;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasCustom = value != null;
    final shown = value ?? fallbackPrice ?? 0;

    final Color border = hasCustom
        ? AppColors.accentGold
        : cs.outlineVariant.withValues(alpha: 0.7);
    final Color tint = hasCustom
        ? AppColors.accentGold.withValues(alpha: 0.12)
        : cs.surfaceContainerHighest.withValues(alpha: 0.4);
    final Color textColor = hasCustom
        ? AppColors.accentGold
        : cs.onSurfaceVariant;

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: hasCustom ? 1.2 : 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDefaultList) ...[
                const Icon(Icons.star_rounded,
                    size: 12, color: AppColors.accentGold),
                const SizedBox(width: 3),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              if (!hasCustom) ...[
                const SizedBox(width: 4),
                Text(
                  '·افتراضي',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            IraqiCurrencyFormat.formatIqd(shown),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
              color: hasCustom ? AppColors.accentGold : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
