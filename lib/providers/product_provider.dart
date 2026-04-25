import 'package:flutter/material.dart';
import '../models/new_product_extra_unit.dart';
import '../services/product_repository.dart';
import '../services/tenant_context_service.dart';
import '../utils/iqd_money.dart';

class AddProductFormData {
  AddProductFormData({
    required this.productCodeHint,
    required this.categories,
    required this.brands,
    required this.warehouses,
    required this.suppliers,
  });

  /// تلميح عرض: رموز تُولَّد تلقائياً (`N{tenantId}-…`) وليست `MAX(id)+1`.
  final String productCodeHint;
  final List<String> categories;
  final List<String> brands;
  final List<Map<String, dynamic>> warehouses;
  final List<String> suppliers;
}

class ProductProvider extends ChangeNotifier {
  final ProductRepository _repo = ProductRepository();

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> get products => _products;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> loadProducts({bool seedIfEmpty = false}) async {
    _isLoading = true;
    notifyListeners();

    if (seedIfEmpty) {
      await _repo.seedIfEmpty();
    }
    _products = await _repo.getProducts();

    _isLoading = false;
    notifyListeners();
  }

  Future<AddProductFormData> loadAddProductFormData() async {
    final productCodeHint = _repo.defaultProductCodeDisplayHint();
    final categories = await _repo.listCategoryNames();
    final brands = await _repo.listBrandNames();
    final warehouses = await _repo.listWarehouses();
    final suppliers = await _repo.listDistinctSupplierNames();
    return AddProductFormData(
      productCodeHint: productCodeHint,
      categories: categories,
      brands: brands,
      warehouses: warehouses,
      suppliers: suppliers,
    );
  }

  /// يضيف منتجًا جديدًا.
  /// يُرجع `null` عند النجاح، أو رسالة خطأ عربية عند الفشل.
  Future<String?> addProduct({
    required String name,
    String? barcode,
    String? categoryName,
    String? brandName,
    required double buyPrice,
    required double sellPrice,
    double? minSellPrice,
    required double qty,
    required double lowStockThreshold,
    int? warehouseId,
    String? description,
    String? imagePath,
    String? internalNotes,
    String? tags,
    int stockBaseKind = 0,
    String? supplierName,
    double taxPercent = 0,
    String discountType = '%',
    double discountValue = 0,
    bool trackInventory = true,
    String? supplierItemCode,
    double? netWeightGrams,
    String? manufacturingDate,
    String? expiryDate,
    String? grade,
    int? expiryAlertDaysBefore,
    List<NewProductExtraUnit> extraUnits = const [],
  }) async {
    try {
      int? categoryId;
      int? brandId;
      if (categoryName != null && categoryName.trim().isNotEmpty) {
        categoryId = await _repo.getOrCreateCategoryId(categoryName);
      }
      if (brandName != null && brandName.trim().isNotEmpty) {
        brandId = await _repo.getOrCreateBrandId(brandName);
      }

      final minP = minSellPrice ?? sellPrice;
      final buyN = IqdMoney.normalizeDinar(buyPrice);
      final sellN = IqdMoney.normalizeDinar(sellPrice);
      final minN = IqdMoney.normalizeDinar(minP);

      double discountPercent = 0;
      double discountAmount = 0;
      if (discountValue > 0) {
        if (discountType == '%') {
          discountPercent = discountValue;
        } else {
          discountAmount = discountValue;
        }
      }

      final ti = trackInventory ? 1 : 0;
      final qtyFinal = trackInventory ? qty : 0.0;
      final lowFinal = trackInventory ? lowStockThreshold : 0.0;

      await _repo.insertProductComplete(
        name: name,
        barcode: barcode,
        categoryId: categoryId,
        brandId: brandId,
        tenantId: TenantContextService.instance.activeTenantId,
        buyPrice: buyN,
        sellPrice: sellN,
        minSellPrice: minN,
        qty: qtyFinal,
        lowStockThreshold: lowFinal,
        description: description,
        imagePath: imagePath,
        internalNotes: internalNotes,
        tags: tags,
        supplierName: supplierName,
        taxPercent: taxPercent,
        discountPercent: discountPercent,
        discountAmount: discountAmount,
        trackInventory: ti,
        allowNegativeStock: 0,
        supplierItemCode: supplierItemCode,
        netWeightGrams: netWeightGrams,
        manufacturingDate: manufacturingDate,
        expiryDate: expiryDate,
        grade: grade,
        expiryAlertDaysBefore: expiryAlertDaysBefore,
        stockBaseKind: stockBaseKind,
        extraUnits: extraUnits,
        warehouseId: warehouseId,
      );

      _products = await _repo.getProducts();
      notifyListeners();
      return null;
    } on StateError catch (e) {
      if (e.message == 'duplicate_barcode') {
        return 'هذا الباركود مستخدم لمنتج آخر.';
      }
      if (e.message == 'bad_unit_factor') {
        return 'عامل التحويل يجب أن يكون أكبر من 0 لكل وحدة إضافية.';
      }
      return e.message;
    } catch (e) {
      return 'تعذر حفظ المنتج: $e';
    }
  }

  Future<Map<String, dynamic>?> findProductByBarcode(String barcode) {
    return _repo.findProductByBarcode(barcode);
  }

  Future<Map<String, dynamic>?> resolveProductByAnyBarcode(String barcode) {
    return _repo.resolveProductByAnyBarcode(barcode);
  }

  Future<List<Map<String, dynamic>>> listActiveUnitVariantsForProduct(int productId) {
    return _repo.listActiveUnitVariantsForProduct(productId);
  }

  Future<int> addUnitVariant({
    required int productId,
    required String unitName,
    String? unitSymbol,
    required double factorToBase,
    String? barcode,
    double? sellPrice,
    double? minSellPrice,
    bool isDefault = false,
  }) {
    return _repo.insertProductUnitVariant(
      productId: productId,
      unitName: unitName,
      unitSymbol: unitSymbol,
      factorToBase: factorToBase,
      barcode: barcode,
      sellPrice: sellPrice,
      minSellPrice: minSellPrice,
      isDefault: isDefault,
      isActive: true,
    );
  }

  Future<Map<String, dynamic>?> getProductById(int id) {
    return _repo.getProductById(id);
  }
}
