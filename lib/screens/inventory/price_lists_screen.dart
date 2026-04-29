import 'package:flutter/material.dart';

const _navy = Color(0xFF1E3A5F);
const _teal = Color(0xFF0D9488);
const _bg = Color(0xFFF1F5F9);
const _card = Colors.white;
const _border = Color(0xFFE2E8F0);
const _t1 = Color(0xFF0F172A);
const _t2 = Color(0xFF64748B);
const _green = Color(0xFF10B981);
const _orange = Color(0xFFF97316);
const _blue = Color(0xFF3B82F6);
const _red = Color(0xFFEF4444);
const _purple = Color(0xFF8B5CF6);

// ══════════════════════════════════════════════════════════════════════════════
class PriceListsScreen extends StatefulWidget {
  const PriceListsScreen({super.key});

  @override
  State<PriceListsScreen> createState() => _PriceListsScreenState();
}

class _PriceListsScreenState extends State<PriceListsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  final List<Map<String, dynamic>> _lists = [
    {
      'id': 1,
      'name': 'قائمة التجزئة',
      'description': 'أسعار بيع التجزئة للعملاء العاديين',
      'color': _blue,
      'isDefault': true,
      'isActive': true,
      'itemsCount': 248,
      'createdAt': '01/01/2025',
    },
    {
      'id': 2,
      'name': 'قائمة الجملة',
      'description': 'أسعار الجملة للموزعين والتجار',
      'color': _green,
      'isDefault': false,
      'isActive': true,
      'itemsCount': 200,
      'createdAt': '15/02/2025',
    },
    {
      'id': 3,
      'name': 'قائمة العملاء المميزين',
      'description': 'أسعار خاصة للعملاء الدائمين (VIP)',
      'color': _purple,
      'isDefault': false,
      'isActive': true,
      'itemsCount': 150,
      'createdAt': '01/03/2025',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _setDefault(int id) => setState(() {
    for (final l in _lists) l['isDefault'] = l['id'] == id;
  });

  Future<void> _openForm([Map<String, dynamic>? existing]) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PriceListForm(existing: existing),
    );
    if (result == null) return;
    setState(() {
      if (existing != null) {
        final i = _lists.indexWhere((l) => l['id'] == existing['id']);
        if (i >= 0) _lists[i] = {...existing, ...result};
      } else {
        _lists.add({
          'id': _lists.length + 1,
          ...result,
          'itemsCount': 0,
          'createdAt': DateTime.now().toString().substring(0, 10),
          'isDefault': false,
        });
      }
    });
  }

  Future<void> _delete(Map<String, dynamic> l) async {
    if (l['isDefault'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن حذف قائمة الأسعار الافتراضية')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف قائمة الأسعار'),
        content: Text('هل تريد حذف «${l['name']}»؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _lists.removeWhere((x) => x['id'] == l['id']));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: const Text(
            'فوائم الأسعار',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: TabBar(
            controller: _tab,
            indicatorColor: _teal,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: const [
              Tab(text: 'القوائم'),
              Tab(text: 'منتجات بحسب القائمة'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: _teal,
          onPressed: _openForm,
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text(
            'قائمة جديدة',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: TabBarView(
          controller: _tab,
          children: [
            // ── Tab 1: Lists ──────────────────────────────────────────────
            ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
              itemCount: _lists.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _PriceListCard(
                data: _lists[i],
                onEdit: () => _openForm(_lists[i]),
                onDelete: () => _delete(_lists[i]),
                onSetDefault: () => _setDefault(_lists[i]['id'] as int),
                onViewItems: () => _showItems(context, _lists[i]),
              ),
            ),

            // ── Tab 2: Products per list ──────────────────────────────────
            _ProductPriceTable(priceLists: _lists),
          ],
        ),
      ),
    );
  }

  void _showItems(BuildContext ctx, Map<String, dynamic> list) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PriceItemsSheet(list: list),
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
    final color = data['color'] as Color;
    final isDefault = data['isDefault'] as bool;

    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: isDefault ? color.withValues(alpha: 0.5) : _border,
          width: isDefault ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.zero,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Icon(
                    Icons.price_change_outlined,
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
                              data['name'],
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _t1,
                              ),
                            ),
                          ),
                          if (isDefault)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _teal.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.zero,
                                border: Border.all(
                                  color: _teal.withValues(alpha: 0.4),
                                ),
                              ),
                              child: const Text(
                                'افتراضي',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _teal,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        data['description'],
                        style: const TextStyle(fontSize: 12, color: _t2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
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
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: _red,
                          ),
                          SizedBox(width: 8),
                          Text('حذف', style: TextStyle(color: _red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Footer ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: 15, color: color),
                const SizedBox(width: 6),
                Text(
                  '${data['itemsCount']} صنف',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.calendar_today_outlined, size: 14, color: _t2),
                const SizedBox(width: 4),
                Text(
                  data['createdAt'],
                  style: const TextStyle(fontSize: 12, color: _t2),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onViewItems,
                  child: Text(
                    'إدارة الأسعار',
                    style: TextStyle(fontSize: 12, color: color),
                  ),
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
// Products Price Table (Tab 2)
// ══════════════════════════════════════════════════════════════════════════════
class _ProductPriceTable extends StatelessWidget {
  final List<Map<String, dynamic>> priceLists;
  const _ProductPriceTable({required this.priceLists});

  static const _products = [
    ('Pringles-1250', 1000.0),
    ('Coca-Cola 330ml', 750.0),
    ('Pepsi 500ml', 700.0),
    ('رز الحياني 5 كيلو', 3000.0),
    ('مياه نون 1.5L', 250.0),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(14),
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: _border),
        ),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          columns: [
            const DataColumn(
              label: Text(
                'المنتج',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const DataColumn(
              label: Text(
                'سعر الشراء',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final l in priceLists)
              DataColumn(
                label: Text(
                  l['name'],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
          rows: _products.map((p) {
            return DataRow(
              cells: [
                DataCell(Text(p.$1, style: const TextStyle(fontSize: 13))),
                DataCell(
                  Text(
                    '${p.$2.toInt()} د.ع',
                    style: const TextStyle(fontSize: 13, color: _t2),
                  ),
                ),
                // Retail: +30%
                DataCell(
                  Text(
                    '${(p.$2 * 1.30).toInt()} د.ع',
                    style: const TextStyle(
                      fontSize: 13,
                      color: _blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Wholesale: +15%
                DataCell(
                  Text(
                    '${(p.$2 * 1.15).toInt()} د.ع',
                    style: const TextStyle(
                      fontSize: 13,
                      color: _green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // VIP: +20%
                DataCell(
                  Text(
                    '${(p.$2 * 1.20).toInt()} د.ع',
                    style: const TextStyle(
                      fontSize: 13,
                      color: _purple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Price Items Sheet
// ══════════════════════════════════════════════════════════════════════════════
class _PriceItemsSheet extends StatelessWidget {
  final Map<String, dynamic> list;
  const _PriceItemsSheet({required this.list});

  static const _items = [
    ('Pringles-1250', '1,625', '1,300'),
    ('Coca-Cola 330ml', '975', '750'),
    ('Pepsi 500ml', '910', '700'),
    ('رز الحياني 5 كيلو', '3,900', '3,000'),
    ('مياه نون 1.5L', '325', '250'),
  ];

  @override
  Widget build(BuildContext context) {
    final color = list['color'] as Color;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.zero,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.price_change_outlined, color: color, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'أسعار ${list['name']}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _t1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Expanded(
                    flex: 4,
                    child: Text(
                      'المنتج',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _t2,
                      ),
                    ),
                  ),
                  const Expanded(
                    flex: 3,
                    child: Text(
                      'سعر البيع',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _t2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const Expanded(
                    flex: 3,
                    child: Text(
                      'سعر الشراء',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _t2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            const Divider(height: 1, color: _border),
            SizedBox(
              height: 250,
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: _border),
                itemBuilder: (_, i) {
                  final item = _items[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(
                            item.$1,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _t1,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            '${item.$2} د.ع',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            '${item.$3} د.ع',
                            style: const TextStyle(fontSize: 12, color: _t2),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: _t2,
                          ),
                          onPressed: () {},
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Create / Edit Price List Form
// ══════════════════════════════════════════════════════════════════════════════
class _PriceListForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _PriceListForm({this.existing});

  @override
  State<_PriceListForm> createState() => _PriceListFormState();
}

class _PriceListFormState extends State<_PriceListForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _desc;
  Color _color = _blue;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name'] ?? '');
    _desc = TextEditingController(text: e?['description'] ?? '');
    _color = e?['color'] ?? _blue;
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          20,
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
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.existing != null ? 'تعديل القائمة' : 'قائمة أسعار جديدة',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: _t1,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: 'اسم القائمة *',
                  prefixIcon: const Icon(
                    Icons.label_outline,
                    size: 20,
                    color: _t2,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: const BorderSide(color: _border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: const BorderSide(color: _navy, width: 1.5),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _desc,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'الوصف',
                  prefixIcon: const Icon(
                    Icons.description_outlined,
                    size: 20,
                    color: _t2,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: const BorderSide(color: _border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: const BorderSide(color: _navy, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'لون القائمة:',
                style: TextStyle(fontSize: 13, color: _t2),
              ),
              const SizedBox(height: 8),
              Row(
                children: [_blue, _green, _purple, _orange, _teal]
                    .map(
                      (c) => GestureDetector(
                        onTap: () => setState(() => _color = c),
                        child: Container(
                          width: 34,
                          height: 34,
                          margin: const EdgeInsetsDirectional.only(start: 8),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == c
                                  ? Colors.black54
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: _color == c
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : null,
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  Navigator.pop(context, {
                    'name': _name.text.trim(),
                    'description': _desc.text.trim(),
                    'color': _color,
                    'isActive': true,
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: Text(
                  widget.existing != null ? 'حفظ التعديلات' : 'إنشاء القائمة',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
