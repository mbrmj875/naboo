import 'dart:async' show Timer, unawaited;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../auth/ensure_fresh_session.dart';
import '../database_helper.dart';
import '../tenant_context_service.dart';
import '../../models/marketplace_catalog_sync_result.dart';
import '../../utils/app_logger.dart';
import 'marketplace_orders_service.dart';
import 'marketplace_product_image_uploader.dart';

/// يرفع منتجات ERP المحلية إلى [marketplace_products] للمتجر المربوط.
class MarketplaceCatalogSyncService {
  MarketplaceCatalogSyncService._();

  static final MarketplaceCatalogSyncService instance =
      MarketplaceCatalogSyncService._();

  final DatabaseHelper _db = DatabaseHelper();
  final MarketplaceOrdersService _stores = MarketplaceOrdersService();
  final MarketplaceProductImageUploader _images = MarketplaceProductImageUploader();
  final SupabaseClient _client = Supabase.instance.client;

  Timer? _debounce;
  bool _running = false;
  bool _queued = false;

  /// مزامنة فورية تقريباً بعد حفظ المنتج (~400ms).
  void scheduleSyncSoon({Duration delay = const Duration(milliseconds: 400)}) {
    _debounce?.cancel();
    _debounce = Timer(delay, () {
      unawaited(syncNow());
    });
  }

  Future<MarketplaceCatalogSyncResult?> syncNow() async {
    if (_running) {
      _queued = true;
      return null;
    }
    _running = true;
    try {
      MarketplaceCatalogSyncResult? last;
      last = await _syncInternal();
      while (_queued) {
        _queued = false;
        last = await _syncInternal();
      }
      return last;
    } on PostgrestException catch (e, st) {
      AppLogger.warn('MarketCatalogSync', 'syncNow Postgrest: $e');
      AppLogger.error('MarketCatalogSync', 'syncNow stack', e, st);
      return null;
    } catch (e, st) {
      AppLogger.warn('MarketCatalogSync', 'syncNow failed: $e');
      AppLogger.error('MarketCatalogSync', 'syncNow stack', e, st);
      return null;
    } finally {
      _running = false;
    }
  }

  Future<MarketplaceCatalogSyncResult> _syncInternal() async {
    if (_client.auth.currentUser == null) {
      throw const SessionExpiredException(
        'سجّل الدخول للحساب السحابي لمزامنة Market',
      );
    }
    await ensureFreshSession();

    final linked = await _stores.fetchLinkedStores();
    if (linked.isEmpty) {
      throw StateError(
        'لا يوجد متجر Market مربوط — افتح «طلبات Market» واربط متجرك أولاً',
      );
    }
    final store = linked.first;
    final tenantId = TenantContextService.instance.requireActiveTenantId();
    await _ensureProductGlobalIds(tenantId);
    final rows = await _loadLocalProducts(tenantId);

    var published = 0;
    var skipped = 0;
    final activeGlobalIds = <String>{};
    final payloads = <Map<String, dynamic>>[];

    for (final row in rows) {
      final globalId = (row['global_id'] as String?)?.trim() ?? '';
      if (globalId.isEmpty) {
        skipped++;
        continue;
      }

      final payload = await _toMarketplaceRow(row, store.id);
      if (payload == null) {
        skipped++;
        continue;
      }

      activeGlobalIds.add(globalId);
      payloads.add(payload);
      if (payload['is_published'] == true) {
        published++;
      }
    }

    await _upsertProductsInBatches(payloads);

    final unpublished = await _unpublishMissing(store.id, activeGlobalIds);

    await _triggerAiClassification(payloads);

    AppLogger.info(
      'MarketCatalogSync',
      'store=${store.name} published=$published unpublished=$unpublished skipped=$skipped',
    );

    return MarketplaceCatalogSyncResult(
      published: published,
      unpublished: unpublished,
      skipped: skipped,
      storeName: store.name,
    );
  }

  Future<void> _upsertProductsInBatches(
    List<Map<String, dynamic>> payloads,
  ) async {
    if (payloads.isEmpty) return;
    const chunkSize = 50;
    for (var i = 0; i < payloads.length; i += chunkSize) {
      final end = i + chunkSize > payloads.length ? payloads.length : i + chunkSize;
      try {
        await _client.from('marketplace_products').upsert(
              payloads.sublist(i, end),
              onConflict: 'product_global_id',
            );
      } on PostgrestException catch (e) {
        if (e.code == '42501') {
          AppLogger.warn(
            'MarketCatalogSync',
            'RLS denied marketplace_products upsert (batch ${i ~/ chunkSize + 1}): ${e.message}',
          );
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> _ensureProductGlobalIds(int tenantId) async {
    final db = await _db.database;
    final rows = await db.query(
      'products',
      columns: ['id'],
      where:
          'tenantId = ? AND (global_id IS NULL OR TRIM(global_id) = "")',
      whereArgs: [tenantId],
    );
    if (rows.isEmpty) return;
    const uuid = Uuid();
    for (final row in rows) {
      final id = row['id'];
      if (id == null) continue;
      await db.update(
        'products',
        {'global_id': uuid.v4()},
        where: 'id = ? AND tenantId = ?',
        whereArgs: [id, tenantId],
      );
    }
  }

  Future<List<Map<String, dynamic>>> _loadLocalProducts(int tenantId) async {
    final db = await _db.database;
    return db.rawQuery(
      '''
      SELECT
        p.global_id,
        p.name,
        p.description,
        p.sellPrice,
        p.qty,
        p.status,
        p.isActive,
        p.imagePath,
        p.imageUrl,
        p.barcode,
        p.productCode,
        p.tags,
        p.saleUnit,
        c.global_id AS category_global_id,
        c.name AS category_name,
        b.global_id AS brand_global_id,
        b.name AS brand_name
      FROM products p
      LEFT JOIN categories c ON p.categoryId = c.id
      LEFT JOIN brands b ON p.brandId = b.id
      WHERE p.tenantId = ?
        AND p.isActive = 1
      ORDER BY p.name COLLATE NOCASE ASC
      ''',
      [tenantId],
    );
  }

  Future<Map<String, dynamic>?> _toMarketplaceRow(
    Map<String, dynamic> row,
    String storeId,
  ) async {
    final globalId = (row['global_id'] as String?)?.trim() ?? '';
    if (globalId.isEmpty) return null;

    final name = (row['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;

    final sellPrice = (row['sellPrice'] as num?)?.toDouble() ?? 0;
    final priceFils = sellPrice.round();
    // عمود price_fils من نوع integer (int4) في Postgres — الحد الأقصى
    // 2,147,483,647. قيم أكبر (غالباً باركود أُدخل خطأً كسعر) تُفشل الدفعة
    // كلها، لذا نتجاوزها بدل إسقاط مزامنة الكتالوج بالكامل.
    const maxInt4 = 2147483647;
    if (priceFils <= 0 || priceFils > maxInt4) return null;

    final qty = (row['qty'] as num?)?.toDouble() ?? 0;
    final stockQuantity = qty < 0 ? 0 : qty.round();
    final status = (row['status'] as String?)?.trim() ?? 'instock';
    final inStock = qty > 0 && status != 'outofstock';

    final categoryGlobalId = (row['category_global_id'] as String?)?.trim();
    final categoryName = (row['category_name'] as String?)?.trim();
    final brandGlobalId = (row['brand_global_id'] as String?)?.trim();
    final brandName = (row['brand_name'] as String?)?.trim();

    // فشل رفع صورة منتج واحد يجب ألا يُجهض مزامنة الكتالوج بالكامل — ننشر
    // المنتج بدون صورة بدل إسقاط كل الدفعة.
    List<String> images;
    try {
      images = await _images.resolveImages(
        storeId: storeId,
        productGlobalId: globalId,
        imagePath: row['imagePath'] as String?,
        imageUrl: row['imageUrl'] as String?,
      );
    } catch (e) {
      AppLogger.warn(
        'MarketCatalogSync',
        'image resolve failed for $globalId: $e',
      );
      images = const [];
    }

    if (images.isNotEmpty) {
      final uploaded = images.first;
      final existingUrl = (row['imageUrl'] as String?)?.trim() ?? '';
      if (uploaded != existingUrl &&
          uploaded.contains('marketplace-product-images')) {
        await _persistImageUrl(globalId, uploaded);
      }
    }

    return {
      'store_id': storeId,
      'product_global_id': globalId,
      'name': name,
      'description': (row['description'] as String?)?.trim(),
      'category_id': categoryGlobalId ?? _slugCategory(categoryName),
      'category_name': categoryName,
      'merchant_category_raw': categoryName,
      'merchant_category_id': categoryGlobalId,
      'brand_id': brandGlobalId,
      'brand_name': brandName,
      'barcode': (row['barcode'] as String?)?.trim(),
      'product_code': (row['productCode'] as String?)?.trim(),
      'erp_tags': (row['tags'] as String?)?.trim(),
      'sale_unit': (row['saleUnit'] as String?)?.trim(),
      'price_fils': priceFils,
      'images': images,
      'in_stock': inStock,
      'stock_quantity': stockQuantity,
      'classification_status': 'pending',
      'is_published': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  String? _slugCategory(String? name) {
    if (name == null || name.trim().isEmpty) return 'uncategorized';
    return name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF-]'), '');
  }

  Future<void> _persistImageUrl(String globalId, String url) async {
    final db = await _db.database;
    await db.update(
      'products',
      {'imageUrl': url},
      where: 'global_id = ?',
      whereArgs: [globalId],
    );
  }

  /// بعد رفع منتجات ERP — يستدعي Edge Function لتصنيف AI/قواعد.
  Future<void> _triggerAiClassification(
    List<Map<String, dynamic>> payloads,
  ) async {
    if (payloads.isEmpty) return;

    final globalIds = payloads
        .map((p) => p['product_global_id']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (globalIds.isEmpty) return;

    for (final gid in globalIds) {
      try {
        await _client.rpc('marketplace_enqueue_classification', params: {
          'p_product_global_id': gid,
        });
      } catch (e) {
        AppLogger.warn('MarketCatalogSync', 'enqueue classification $gid: $e');
      }
    }

    const chunkSize = 40;
    for (var i = 0; i < globalIds.length; i += chunkSize) {
      final end = i + chunkSize > globalIds.length ? globalIds.length : i + chunkSize;
      final chunk = globalIds.sublist(i, end);
      try {
        await _client.functions.invoke(
          'classify-product',
          body: {'product_global_ids': chunk},
        );
        AppLogger.info(
          'MarketCatalogSync',
          'classify-product invoked for ${chunk.length} ERP products',
        );
      } catch (e) {
        AppLogger.warn('MarketCatalogSync', 'classify-product failed: $e');
      }
    }
  }

  Future<int> _unpublishMissing(
    String storeId,
    Set<String> activeGlobalIds,
  ) async {
    if (activeGlobalIds.isEmpty) return 0;

    final existing = await _client
        .from('marketplace_products')
        .select('id, product_global_id, is_published')
        .eq('store_id', storeId);

    var count = 0;
    for (final raw in existing as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final gid = row['product_global_id']?.toString() ?? '';
      if (gid.isEmpty || activeGlobalIds.contains(gid)) continue;
      if (row['is_published'] != true) continue;
      await _client.from('marketplace_products').update({
        'is_published': false,
        'in_stock': false,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', row['id']);
      count++;
    }
    return count;
  }
}
