import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';
import '../models/restaurant_models.dart';
import 'restaurant_db_schema.dart';

class FloorsTablesRepository {
  FloorsTablesRepository({
    DatabaseHelper? dbHelper,
    TenantContextService? tenant,
  })  : _dbHelper = dbHelper ?? DatabaseHelper(),
        _tenant = tenant ?? TenantContextService.instance;

  final DatabaseHelper _dbHelper;
  final TenantContextService _tenant;

  Future<void> _ensure() async {
    final db = await _dbHelper.database;
    await ensureRestaurantTables(db);
  }

  int get _tid => _tenant.requireActiveTenantId();

  static String normalizeTableSlug(String raw) {
    var s = raw.trim().toLowerCase();
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < arabic.length; i++) {
      s = s.replaceAll(arabic[i], '$i');
    }
    s = s.replaceAll(RegExp(r'\s+'), '-');
    s = s.replaceAll(RegExp(r'[^a-z0-9\-]'), '');
    if (s.isEmpty) {
      s = 't-${DateTime.now().millisecondsSinceEpoch}';
    }
    return s;
  }

  Future<List<RestaurantFloor>> listFloors() async {
    await _ensure();
    final db = await _dbHelper.database;
    final rows = await db.query(
      'restaurant_floors',
      where: 'tenant_id = ? AND deleted_at IS NULL',
      whereArgs: [_tid],
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(RestaurantFloor.fromMap).toList();
  }

  Future<int> upsertFloor({
    int? id,
    required String nameAr,
    int sortOrder = 0,
  }) async {
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;
    if (id != null) {
      await db.update(
        'restaurant_floors',
        {'name_ar': nameAr, 'sort_order': sortOrder},
        where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
        whereArgs: [id, tid],
      );
      return id;
    }
    return db.insert('restaurant_floors', {
      'tenant_id': tid,
      'name_ar': nameAr,
      'sort_order': sortOrder,
    });
  }

  Future<void> softDeleteFloor(int id) async {
    await _ensure();
    final db = await _dbHelper.database;
    await db.update(
      'restaurant_floors',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
      whereArgs: [id, _tid],
    );
  }

  Future<List<RestaurantTable>> listTables({int? floorId}) async {
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;
    final where = StringBuffer('t.tenant_id = ? AND t.deleted_at IS NULL');
    final args = <Object?>[tid];
    if (floorId != null) {
      where.write(' AND t.floor_id = ?');
      args.add(floorId);
    }
    final rows = await db.rawQuery('''
      SELECT t.*,
             s.id AS active_session_id,
             s.state AS session_state,
             s.opened_at AS session_opened_at
      FROM restaurant_tables t
      LEFT JOIN restaurant_sessions s
        ON s.table_id = t.id
       AND s.tenant_id = t.tenant_id
       AND s.deleted_at IS NULL
       AND s.state IN ('open', 'awaiting_payment')
      WHERE $where
      ORDER BY t.table_number ASC, t.id ASC
    ''', args);

    return rows.map((m) {
      final stateRaw = m['session_state'] as String?;
      final DerivedTableState derived;
      if (stateRaw == 'awaiting_payment') {
        derived = DerivedTableState.awaitingPayment;
      } else if (stateRaw == 'open') {
        derived = DerivedTableState.occupied;
      } else {
        derived = DerivedTableState.available;
      }
      return RestaurantTable.fromMap(
        m,
        derivedState: derived,
        activeSessionId: m['active_session_id'] as int?,
        sessionOpenedAt: m['session_opened_at'] as int?,
      );
    }).toList();
  }

  Future<int> upsertTable({
    int? id,
    required int floorId,
    required String tableNumber,
    required String tableSlug,
    int? capacity,
    int layoutXBp = -1,
    int layoutYBp = -1,
    int layoutRotDeg = 0,
    RestaurantTableSeatStyle seatStyle = RestaurantTableSeatStyle.center,
    int layoutWBp = 900,
    int layoutHBp = 900,
  }) async {
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;
    final slug = normalizeTableSlug(tableSlug);
    var uniqueSlug = slug;
    if (id == null) {
      final clash = await db.query(
        'restaurant_tables',
        columns: ['id'],
        where: 'tenant_id = ? AND table_slug = ? AND deleted_at IS NULL',
        whereArgs: [tid, uniqueSlug],
        limit: 1,
      );
      if (clash.isNotEmpty) {
        uniqueSlug =
            '$slug-${DateTime.now().millisecondsSinceEpoch % 100000}';
      }
    }
    if (uniqueSlug.isEmpty) {
      throw ArgumentError('table_slug فارغ');
    }
    final style =
        seatStyle == RestaurantTableSeatStyle.wall ? 'wall' : 'center';
    if (id != null) {
      await db.update(
        'restaurant_tables',
        {
          'floor_id': floorId,
          'table_number': tableNumber.trim(),
          'table_slug': uniqueSlug,
          'capacity': capacity,
          'layout_x_bp': layoutXBp,
          'layout_y_bp': layoutYBp,
          'layout_rot_deg': layoutRotDeg,
          'seat_style': style,
          'layout_w_bp': layoutWBp.clamp(400, 2500),
          'layout_h_bp': layoutHBp.clamp(400, 2500),
        },
        where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
        whereArgs: [id, tid],
      );
      return id;
    }
    return db.insert('restaurant_tables', {
      'tenant_id': tid,
      'floor_id': floorId,
      'table_number': tableNumber.trim(),
      'table_slug': uniqueSlug,
      'capacity': capacity ?? 4,
      'session_seq': 0,
      'layout_x_bp': layoutXBp,
      'layout_y_bp': layoutYBp,
      'layout_rot_deg': layoutRotDeg,
      'seat_style': style,
      'layout_w_bp': layoutWBp.clamp(400, 2500),
      'layout_h_bp': layoutHBp.clamp(400, 2500),
    });
  }

  Future<void> updateTableLayout({
    required int id,
    required int layoutXBp,
    required int layoutYBp,
    int? layoutRotDeg,
    int? layoutWBp,
    int? layoutHBp,
  }) async {
    await _ensure();
    final db = await _dbHelper.database;
    final map = <String, Object?>{
      'layout_x_bp': layoutXBp.clamp(0, 10000),
      'layout_y_bp': layoutYBp.clamp(0, 10000),
    };
    if (layoutRotDeg != null) {
      map['layout_rot_deg'] = ((layoutRotDeg % 360) + 360) % 360;
    }
    if (layoutWBp != null) {
      map['layout_w_bp'] = layoutWBp.clamp(400, 2500);
    }
    if (layoutHBp != null) {
      map['layout_h_bp'] = layoutHBp.clamp(400, 2500);
    }
    await db.update(
      'restaurant_tables',
      map,
      where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
      whereArgs: [id, _tid],
    );
  }

  Future<void> updateTableStyle({
    required int id,
    required int capacity,
    required RestaurantTableSeatStyle seatStyle,
  }) async {
    await _ensure();
    final db = await _dbHelper.database;
    await db.update(
      'restaurant_tables',
      {
        'capacity': capacity >= 6 ? 6 : 4,
        'seat_style':
            seatStyle == RestaurantTableSeatStyle.wall ? 'wall' : 'center',
      },
      where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
      whereArgs: [id, _tid],
    );
  }

  Future<void> softDeleteTable(int id) async {
    await _ensure();
    final db = await _dbHelper.database;
    await db.update(
      'restaurant_tables',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
      whereArgs: [id, _tid],
    );
  }

  Future<List<RestaurantFloorFixture>> listFixtures({required int floorId}) async {
    await _ensure();
    final db = await _dbHelper.database;
    final rows = await db.query(
      'restaurant_floor_fixtures',
      where: 'tenant_id = ? AND floor_id = ? AND deleted_at IS NULL',
      whereArgs: [_tid, floorId],
      orderBy: 'id ASC',
    );
    return rows.map(RestaurantFloorFixture.fromMap).toList();
  }

  Future<int> upsertFixture({
    int? id,
    required int floorId,
    required RestaurantFloorFixtureKind kind,
    String? labelAr,
    int layoutXBp = 1000,
    int layoutYBp = 1000,
    int layoutWBp = 1200,
    int layoutHBp = 900,
    int layoutRotDeg = 0,
    String? metaJson,
  }) async {
    await _ensure();
    final db = await _dbHelper.database;
    final tid = _tid;
    final map = <String, Object?>{
      'floor_id': floorId,
      'kind': kind.dbValue,
      'label_ar': labelAr,
      'layout_x_bp': layoutXBp.clamp(0, 10000),
      'layout_y_bp': layoutYBp.clamp(0, 10000),
      'layout_w_bp': layoutWBp.clamp(200, 9000),
      'layout_h_bp': layoutHBp.clamp(100, 9000),
      'layout_rot_deg': ((layoutRotDeg % 360) + 360) % 360,
      'meta_json': metaJson,
    };
    if (id != null) {
      await db.update(
        'restaurant_floor_fixtures',
        map,
        where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
        whereArgs: [id, tid],
      );
      return id;
    }
    return db.insert('restaurant_floor_fixtures', {
      'tenant_id': tid,
      ...map,
    });
  }

  Future<void> updateFixtureLayout({
    required int id,
    required int layoutXBp,
    required int layoutYBp,
    int? layoutRotDeg,
    int? layoutWBp,
    int? layoutHBp,
    String? metaJson,
  }) async {
    await _ensure();
    final db = await _dbHelper.database;
    final map = <String, Object?>{
      'layout_x_bp': layoutXBp.clamp(0, 10000),
      'layout_y_bp': layoutYBp.clamp(0, 10000),
    };
    if (layoutRotDeg != null) {
      map['layout_rot_deg'] = ((layoutRotDeg % 360) + 360) % 360;
    }
    if (layoutWBp != null) {
      map['layout_w_bp'] = layoutWBp.clamp(120, 10000);
    }
    if (layoutHBp != null) {
      map['layout_h_bp'] = layoutHBp.clamp(80, 10000);
    }
    if (metaJson != null) {
      map['meta_json'] = metaJson;
    }
    await db.update(
      'restaurant_floor_fixtures',
      map,
      where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
      whereArgs: [id, _tid],
    );
  }

  Future<void> updateFixtureMeta({
    required int id,
    required String metaJson,
  }) async {
    await _ensure();
    final db = await _dbHelper.database;
    await db.update(
      'restaurant_floor_fixtures',
      {'meta_json': metaJson},
      where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
      whereArgs: [id, _tid],
    );
  }

  Future<void> softDeleteFixture(int id) async {
    await _ensure();
    final db = await _dbHelper.database;
    await db.update(
      'restaurant_floor_fixtures',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ? AND tenant_id = ? AND deleted_at IS NULL',
      whereArgs: [id, _tid],
    );
  }
}
