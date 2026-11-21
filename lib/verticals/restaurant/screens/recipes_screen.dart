import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';
import '../models/restaurant_models.dart';
import '../services/menu_repository.dart';
import '../services/recipes_repository.dart';
import '../theme/restaurant_os_tokens.dart';

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key});

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  final _menuRepo = MenuRepository();
  final _recipesRepo = RecipesRepository();

  bool _loading = true;
  String? _error;
  List<RestaurantMenuItem> _items = const [];
  RestaurantMenuItem? _selected;
  RestaurantRecipe? _recipe;
  List<RestaurantRecipeLine> _lines = const [];

  @override
  void initState() {
    super.initState();
    _reloadItems();
  }

  Future<void> _reloadItems() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _menuRepo.listItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      if (_selected != null) {
        await _loadRecipe(_selected!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadRecipe(RestaurantMenuItem item) async {
    setState(() {
      _selected = item;
      _loading = true;
    });
    try {
      var recipe = await _recipesRepo.recipeForMenuItem(item.id);
      recipe ??= RestaurantRecipe(
        id: await _recipesRepo.upsertRecipe(menuItemId: item.id),
        tenantId: TenantContextService.instance.requireActiveTenantId(),
        menuItemId: item.id,
        yieldQty: 1,
      );
      final lines = await _recipesRepo.listLines(recipe.id);
      if (!mounted) return;
      setState(() {
        _recipe = recipe;
        _lines = lines;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _addLine() async {
    final recipe = _recipe;
    if (recipe == null) return;

    final db = await DatabaseHelper().database;
    final tid = TenantContextService.instance.requireActiveTenantId();
    final products = await db.query(
      'products',
      columns: ['id', 'name'],
      where: 'tenantId = ?',
      whereArgs: [tid],
      orderBy: 'name ASC',
      limit: 200,
    );
    if (!mounted) return;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا منتجات في المخزون لإضافتها')),
      );
      return;
    }

    int? productId = products.first['id'] as int?;
    var unit = RecipeBaseUnit.g;
    final qtyCtrl = TextEditingController(text: '1000');
    var critical = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('مكوّن جديد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: productId,
                  decoration: const InputDecoration(labelText: 'المنتج'),
                  items: [
                    for (final p in products)
                      DropdownMenuItem(
                        value: p['id'] as int,
                        child: Text('${p['name']}'),
                      ),
                  ],
                  onChanged: (v) => setLocal(() => productId = v),
                ),
                DropdownButtonFormField<RecipeBaseUnit>(
                  value: unit,
                  decoration: const InputDecoration(labelText: 'الوحدة'),
                  items: const [
                    DropdownMenuItem(value: RecipeBaseUnit.g, child: Text('غرام')),
                    DropdownMenuItem(value: RecipeBaseUnit.ml, child: Text('مل')),
                    DropdownMenuItem(
                      value: RecipeBaseUnit.piece,
                      child: Text('قطعة'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => unit = v);
                  },
                ),
                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الكمية بالميكرو (1000 = 1 وحدة)',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('مكوّن حرج'),
                  value: critical,
                  onChanged: (v) => setLocal(() => critical = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || productId == null) return;
    final qty = int.tryParse(qtyCtrl.text) ?? 0;
    await _recipesRepo.addLine(
      recipeId: recipe.id,
      productId: productId!,
      baseUnit: unit,
      qtyMicro: qty,
      isCritical: critical,
    );
    await _loadRecipe(_selected!);
  }

  String _unitLabel(RecipeBaseUnit u) {
    switch (u) {
      case RecipeBaseUnit.g:
        return 'غ';
      case RecipeBaseUnit.ml:
        return 'مل';
      case RecipeBaseUnit.piece:
        return 'قطعة';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: RestaurantOsTokens.darkTheme(context),
      child: Scaffold(
        backgroundColor: RestaurantOsTokens.charcoal,
        appBar: AppBar(
          title: const Text(
            'الوصفات',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      floatingActionButton: _recipe == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _addLine,
              icon: const Icon(Icons.add),
              label: const Text('مكوّن'),
            ),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items.isEmpty
              ? Center(child: Text(_error!))
              : Row(
                  children: [
                    SizedBox(
                      width: 220,
                      child: ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, i) {
                          final item = _items[i];
                          final selected = item.id == _selected?.id;
                          return ListTile(
                            selected: selected,
                            title: Text(item.nameAr),
                            subtitle: Text(
                              item.hasRecipe ? 'لديه وصفة' : 'بدون وصفة',
                            ),
                            onTap: () => _loadRecipe(item),
                          );
                        },
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _selected == null
                          ? const Center(child: Text('اختر صنفاً لعرض وصفتها'))
                          : _loading
                              ? const Center(child: CircularProgressIndicator())
                              : ListView.builder(
                                  padding: const EdgeInsetsDirectional.all(16),
                                  itemCount: _lines.length + 1,
                                  itemBuilder: (context, i) {
                                    if (i == 0) {
                                      return Padding(
                                        padding: const EdgeInsetsDirectional.only(
                                          bottom: 12,
                                        ),
                                        child: Text(
                                          'وصفة: ${_selected!.nameAr}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge,
                                        ),
                                      );
                                    }
                                    final line = _lines[i - 1];
                                    return ListTile(
                                      title: Text(
                                        line.productNameAr ?? '#${line.productId}',
                                      ),
                                      subtitle: Text(
                                        '${line.qtyMicro} ميكرو · ${_unitLabel(line.baseUnit)}'
                                        '${line.isCritical ? ' · حرج' : ''}',
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () async {
                                          await _recipesRepo.softDeleteLine(line.id);
                                          await _loadRecipe(_selected!);
                                        },
                                      ),
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
