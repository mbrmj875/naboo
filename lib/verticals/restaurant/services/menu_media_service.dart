import 'dart:convert';
import 'dart:typed_data';

import '../../../platform/persist_local_bytes.dart';
import '../../../services/database_helper.dart';
import '../../../services/marketplace/marketplace_image_compress.dart';
import '../../../services/tenant_context_service.dart';
import '../models/restaurant_models.dart';
import 'restaurant_db_schema.dart';

/// ضغط محلي + تخزين مسار مؤقت.
/// رفع Storage + Edge `restaurant-image-process` = المرحلة 4.
class MenuMediaService {
  MenuMediaService({
    DatabaseHelper? dbHelper,
    TenantContextService? tenant,
  })  : _dbHelper = dbHelper ?? DatabaseHelper(),
        _tenant = tenant ?? TenantContextService.instance;

  final DatabaseHelper _dbHelper;
  final TenantContextService _tenant;

  static const maxImagesPerItem = 5;

  Future<void> _ensure() async {
    final db = await _dbHelper.database;
    await ensureRestaurantTables(db);
  }

  int get _tid => _tenant.requireActiveTenantId();

  Future<List<RestaurantMenuItemImage>> listImages(int menuItemId) async {
    await _ensure();
    final db = await _dbHelper.database;
    final rows = await db.query(
      'restaurant_menu_item_images',
      where: 'tenant_id = ? AND menu_item_id = ? AND deleted_at IS NULL',
      whereArgs: [_tid, menuItemId],
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(RestaurantMenuItemImage.fromMap).toList();
  }

  Future<RestaurantMenuItemImage> addImage({
    required int menuItemId,
    required Uint8List rawBytes,
    String? altAr,
    String? altEn,
    bool makePrimary = false,
  }) async {
    await _ensure();
    final existing = await listImages(menuItemId);
    if (existing.length >= maxImagesPerItem) {
      throw StateError('الحد الأقصى 5 صور لكل صنف');
    }

    final compressed =
        MarketplaceImageCompress.compressBytes(rawBytes) ?? rawBytes;
    final path = await persistLocalBytes(
      bytes: compressed,
      relativeDir: 'restaurant/menu/$menuItemId',
      fileName: 'img_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    if (path.isEmpty) {
      throw StateError('تعذّر حفظ الصورة محلياً');
    }

    final variants = jsonEncode({
      'thumb': {'webp': path, 'jpg': path},
      'medium': {'webp': path, 'jpg': path},
      'large': {'webp': path, 'jpg': path},
    });

    final db = await _dbHelper.database;
    final tid = _tid;
    final isPrimary = makePrimary || existing.isEmpty;

    return db.transaction((txn) async {
      if (isPrimary && existing.isNotEmpty) {
        await txn.update(
          'restaurant_menu_item_images',
          {'is_primary': 0},
          where:
              'tenant_id = ? AND menu_item_id = ? AND deleted_at IS NULL AND is_primary = 1',
          whereArgs: [tid, menuItemId],
        );
      }
      final id = await txn.insert('restaurant_menu_item_images', {
        'tenant_id': tid,
        'menu_item_id': menuItemId,
        'image_url': path,
        'variants_json': variants,
        'sort_order': existing.length,
        'is_primary': isPrimary ? 1 : 0,
        'bytes': compressed.length,
        'mime': 'image/jpeg',
        'alt_ar': altAr,
        'alt_en': altEn,
      });
      if (isPrimary) {
        await txn.update(
          'restaurant_menu_items',
          {'image_url': path},
          where: 'id = ? AND tenant_id = ?',
          whereArgs: [menuItemId, tid],
        );
      }
      final rows = await txn.query(
        'restaurant_menu_item_images',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      return RestaurantMenuItemImage.fromMap(rows.first);
    });
  }

  Future<void> softDeleteImage(int imageId) async {
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'restaurant_menu_item_images',
        where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
        whereArgs: [imageId, tid],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final row = rows.first;
      final menuItemId = row['menu_item_id'] as int;
      final wasPrimary = ((row['is_primary'] as int?) ?? 0) == 1;
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.update(
        'restaurant_menu_item_images',
        {'deleted_at': now, 'is_primary': 0},
        where: 'id = ?',
        whereArgs: [imageId],
      );
      if (wasPrimary) {
        final others = await txn.query(
          'restaurant_menu_item_images',
          where: 'tenant_id = ? AND menu_item_id = ? AND deleted_at IS NULL',
          whereArgs: [tid, menuItemId],
          orderBy: 'sort_order ASC, id ASC',
          limit: 1,
        );
        if (others.isNotEmpty) {
          final promoteId = others.first['id'] as int;
          final url = others.first['image_url'] as String;
          await txn.update(
            'restaurant_menu_item_images',
            {'is_primary': 1},
            where: 'id = ?',
            whereArgs: [promoteId],
          );
          await txn.update(
            'restaurant_menu_items',
            {'image_url': url},
            where: 'id = ? AND tenant_id = ?',
            whereArgs: [menuItemId, tid],
          );
        } else {
          await txn.update(
            'restaurant_menu_items',
            {'image_url': null},
            where: 'id = ? AND tenant_id = ?',
            whereArgs: [menuItemId, tid],
          );
        }
      }
    });
  }

  Future<void> updateAlts({
    required int imageId,
    String? altAr,
    String? altEn,
  }) async {
    await _ensure();
    final db = await _dbHelper.database;
    await db.update(
      'restaurant_menu_item_images',
      {'alt_ar': altAr, 'alt_en': altEn},
      where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
      whereArgs: [imageId, _tid],
    );
  }
}
