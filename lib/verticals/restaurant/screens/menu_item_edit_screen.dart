import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/iqd_money.dart';
import '../models/restaurant_models.dart';
import '../services/menu_media_service.dart';
import '../services/menu_repository.dart';
import '../services/recipes_repository.dart';

class MenuItemEditScreen extends StatefulWidget {
  const MenuItemEditScreen({super.key, required this.menuItemId});

  final int menuItemId;

  @override
  State<MenuItemEditScreen> createState() => _MenuItemEditScreenState();
}

class _MenuItemEditScreenState extends State<MenuItemEditScreen> {
  final _menuRepo = MenuRepository();
  final _media = MenuMediaService();
  final _recipes = RecipesRepository();

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  RestaurantMenuItem? _item;
  List<RestaurantMenuItemImage> _images = const [];
  bool _isAvailable = false;
  int? _directSkuId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final item = await _menuRepo.getItem(widget.menuItemId);
      if (item == null) throw StateError('الصنف غير موجود');
      final images = await _media.listImages(widget.menuItemId);
      if (!mounted) return;
      _nameCtrl.text = item.nameAr;
      _descCtrl.text = item.descriptionAr ?? '';
      _priceCtrl.text = item.priceFils % 1000 == 0
          ? IraqiCurrencyFormat.formatInt(IqdMoney.fromFils(item.priceFils))
          : IraqiCurrencyFormat.formatDecimal2(IqdMoney.fromFils(item.priceFils));
      setState(() {
        _item = item;
        _images = images;
        _isAvailable = item.isAvailable;
        _directSkuId = item.directStockSkuId;
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

  Future<void> _save() async {
    final item = _item;
    if (item == null) return;
    final dinar = double.tryParse(_priceCtrl.text.replaceAll(',', ''));
    if (dinar == null || dinar < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سعر غير صالح')),
      );
      return;
    }
    try {
      await _menuRepo.upsertItem(
        id: item.id,
        categoryId: item.categoryId,
        nameAr: _nameCtrl.text,
        descriptionAr: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text,
        priceFils: (dinar * 1000).round(),
        isAvailable: _isAvailable,
        directStockSkuId: _directSkuId,
        sortOrder: item.sortOrder,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم الحفظ')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _pickImage() async {
    final x = ImagePicker();
    final file = await x.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 88,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر قراءة الصورة')),
      );
      return;
    }
    try {
      await _media.addImage(
        menuItemId: widget.menuItemId,
        rawBytes: Uint8List.fromList(bytes),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _ensureRecipeStub() async {
    await _recipes.upsertRecipe(menuItemId: widget.menuItemId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم إنشاء وصفة فارغة — أضف المكونات من شاشة الوصفات'),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل صنف'),
        actions: [
          TextButton(onPressed: _save, child: const Text('حفظ')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsetsDirectional.all(16),
                  children: [
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'اسم الصنف'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descCtrl,
                      decoration: const InputDecoration(labelText: 'الوصف'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _priceCtrl,
                      decoration: const InputDecoration(
                        labelText: 'السعر (د.ع)',
                        hintText: 'مثال: 8,000',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('متاح للطلب'),
                      subtitle: Text(
                        (_item?.canBeAvailable ?? false)
                            ? 'يتطلب وصفة أو مخزون مباشر'
                            : 'أضف وصفة أو ربط مخزون قبل التفعيل',
                      ),
                      value: _isAvailable,
                      onChanged: (v) => setState(() => _isAvailable = v),
                    ),
                    if (!(_item?.hasRecipe ?? false))
                      OutlinedButton.icon(
                        onPressed: _ensureRecipeStub,
                        icon: const Icon(Icons.soup_kitchen_outlined),
                        label: const Text('إنشاء وصفة'),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'الصور (حتى 5)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'نص بديل موضوعي مثل: «برغر لحم مشوي مع جبن» — ليس تسويقياً',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final img in _images)
                          Stack(
                            children: [
                              Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: img.isPrimary
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.black12,
                                    width: img.isPrimary ? 2 : 1,
                                  ),
                                  color: Colors.black12,
                                ),
                                alignment: Alignment.center,
                                child: const Icon(Icons.image),
                              ),
                              PositionedDirectional(
                                top: 0,
                                end: 0,
                                child: IconButton(
                                  iconSize: 18,
                                  onPressed: () async {
                                    await _media.softDeleteImage(img.id);
                                    await _load();
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                              ),
                            ],
                          ),
                        if (_images.length < MenuMediaService.maxImagesPerItem)
                          OutlinedButton(
                            onPressed: _pickImage,
                            child: const Text('إضافة صورة'),
                          ),
                      ],
                    ),
                  ],
                ),
    );
  }
}
