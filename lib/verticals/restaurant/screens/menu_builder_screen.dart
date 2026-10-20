import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/screen_layout.dart';
import '../models/restaurant_models.dart';
import '../services/menu_repository.dart';
import '../theme/restaurant_os_tokens.dart';
import '../utils/restaurant_money.dart';
import 'menu_item_edit_screen.dart';

/// إدارة أصناف المنيو — منفصلة عن ترتيب القاعة.
class MenuBuilderScreen extends StatefulWidget {
  const MenuBuilderScreen({super.key});

  @override
  State<MenuBuilderScreen> createState() => _MenuBuilderScreenState();
}

class _MenuBuilderScreenState extends State<MenuBuilderScreen> {
  final _repo = MenuRepository();
  bool _loading = true;
  String? _error;
  List<RestaurantMenuCategory> _categories = const [];
  List<RestaurantMenuItem> _items = const [];
  int? _categoryId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cats = await _repo.listCategories();
      var catId = _categoryId;
      if (catId == null && cats.isNotEmpty) catId = cats.first.id;
      final items = await _repo.listItems(categoryId: catId);
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _items = items;
        _categoryId = catId;
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

  Future<void> _addCategory() async {
    final name = await _prompt('قسم جديد', 'اسم القسم');
    if (name == null || name.trim().isEmpty) return;
    await _repo.upsertCategory(nameAr: name.trim());
    await _reload();
  }

  Future<void> _addItem() async {
    final catId = _categoryId;
    if (catId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف قسماً أولاً')),
      );
      return;
    }
    final name = await _prompt('صنف جديد', 'اسم الصنف');
    if (name == null || name.trim().isEmpty) return;
    final priceText = await _prompt(
      'السعر',
      'السعر بالدينار العراقي (مثال 8,000)',
    );
    if (priceText == null) return;
    final dinar = double.tryParse(priceText.replaceAll(',', ''));
    if (dinar == null || dinar < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سعر غير صالح')),
      );
      return;
    }
    final priceFils = (dinar * 1000).round();
    final id = await _repo.upsertItem(
      categoryId: catId,
      nameAr: name.trim(),
      priceFils: priceFils,
      isAvailable: false,
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MenuItemEditScreen(menuItemId: id),
      ),
    );
    await _reload();
  }

  Future<String?> _prompt(String title, String label) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => Theme(
        data: RestaurantOsTokens.darkTheme(ctx),
        child: AlertDialog(
          backgroundColor: RestaurantOsTokens.charcoalElevated,
          title: Text(title),
          content: TextField(
            controller: c,
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(color: RestaurantOsTokens.boneMuted),
            ),
            style: const TextStyle(color: RestaurantOsTokens.bone),
            keyboardType: title.contains('سعر')
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            inputFormatters: title.contains('سعر')
                ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
                : null,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openItem(RestaurantMenuItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MenuItemEditScreen(menuItemId: item.id),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final sl = ScreenLayout.of(context);
    final crossAxis = switch (sl.layoutVariant) {
      DeviceVariant.phoneXS || DeviceVariant.phoneSM => 2,
      DeviceVariant.tabletSM => 3,
      DeviceVariant.tabletLG => 4,
      DeviceVariant.desktopSM || DeviceVariant.desktopLG => 5,
    };

    return Theme(
      data: RestaurantOsTokens.darkTheme(context),
      child: Scaffold(
        backgroundColor: RestaurantOsTokens.charcoal,
        appBar: AppBar(
          title: const Text(
            'المنيو',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              tooltip: 'قسم جديد',
              onPressed: _addCategory,
              icon: const Icon(Icons.category_outlined),
              color: RestaurantOsTokens.amberSoft,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addItem,
          backgroundColor: RestaurantOsTokens.amber,
          foregroundColor: RestaurantOsTokens.charcoal,
          icon: const Icon(Icons.add),
          label: const Text('صنف'),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: RestaurantOsTokens.amber),
              )
            : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: RestaurantOsTokens.bone),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_categories.isNotEmpty)
                        SizedBox(
                          height: 48,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsetsDirectional.fromSTEB(
                              16,
                              8,
                              16,
                              0,
                            ),
                            itemCount: _categories.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 16),
                            itemBuilder: (context, i) {
                              final c = _categories[i];
                              final selected = c.id == _categoryId;
                              return InkWell(
                                onTap: () {
                                  setState(() => _categoryId = c.id);
                                  _reload();
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.nameAr,
                                      style: TextStyle(
                                        color: selected
                                            ? RestaurantOsTokens.bone
                                            : RestaurantOsTokens.boneMuted,
                                        fontWeight: selected
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      height: 2,
                                      width: 28,
                                      color: selected
                                          ? RestaurantOsTokens.amber
                                          : Colors.transparent,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      Expanded(
                        child: _categories.isEmpty
                            ? const Center(
                                child: Text(
                                  'أضف قسماً لبدء بناء المنيو',
                                  style: TextStyle(
                                    color: RestaurantOsTokens.boneMuted,
                                  ),
                                ),
                              )
                            : _items.isEmpty
                                ? const Center(
                                    child: Text(
                                      'لا أصناف في هذا القسم',
                                      style: TextStyle(
                                        color: RestaurantOsTokens.boneMuted,
                                      ),
                                    ),
                                  )
                                : GridView.builder(
                                    padding: const EdgeInsetsDirectional.all(12),
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: crossAxis,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: 1,
                                    ),
                                    itemCount: _items.length,
                                    itemBuilder: (context, i) {
                                      final item = _items[i];
                                      return _MenuItemSquareCard(
                                        item: item,
                                        onTap: () => _openItem(item),
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

/// بطاقة مربعة: نصف علوي صورة، نصف سفلي اسم + سعر.
class _MenuItemSquareCard extends StatelessWidget {
  const _MenuItemSquareCard({required this.item, required this.onTap});

  final RestaurantMenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ready = item.canBeAvailable;
    final status = ready
        ? (item.isAvailable ? 'متاح' : 'غير مفعّل')
        : 'يحتاج وصفة';

    return Material(
      color: RestaurantOsTokens.charcoalElevated,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestaurantOsTokens.radiusSm),
        side: BorderSide(
          color: RestaurantOsTokens.bone.withValues(alpha: 0.08),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 1, child: _MenuItemImage(url: item.imageUrl)),
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.nameAr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: RestaurantOsTokens.bone,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: item.isAvailable
                            ? RestaurantOsTokens.success
                            : RestaurantOsTokens.boneMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      RestaurantMoney.formatFils(item.priceFils),
                      style: const TextStyle(
                        color: RestaurantOsTokens.amber,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItemImage extends StatelessWidget {
  const _MenuItemImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: RestaurantOsTokens.charcoalHigh,
      child: Center(
        child: Icon(
          Icons.restaurant_rounded,
          size: 36,
          color: RestaurantOsTokens.bone.withValues(alpha: 0.28),
        ),
      ),
    );
    final u = url?.trim();
    if (u == null || u.isEmpty) return placeholder;
    if (u.startsWith('http://') || u.startsWith('https://')) {
      return Image.network(
        u,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => placeholder,
      );
    }
    if (!kIsWeb) {
      final file = File(u);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => placeholder,
        );
      }
    }
    return placeholder;
  }
}
