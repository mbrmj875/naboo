import 'package:sqflite/sqflite.dart';

import '../../../services/service_order_kinds.dart';
import '../../../utils/app_logger.dart';
import '../utils/iraq_plate.dart';
import '../utils/oil_change_lookup_normalize.dart';
import '../utils/oil_change_order_status.dart';
import '../utils/oil_odometer_unit.dart';

/// سجل السيارات (المرحلة 6 — الشريحة 1).
///
/// كل سيارة صف واحد في `vehicles`، وكل بطاقة غيار أو غسيل تشير إليها بـ
/// `service_orders.vehicle_global_id`. حقول السيارة (اسمها، صاحبها الحالي،
/// آخر عداد، عدد الزيارات) تُشتق دائماً من بطاقاتها، فلا تنحرف عنها.
///
/// المعرّف العام مشتق من اللوحة (`veh-<tenantId>-<plateKey>`): جهازان يسجّلان
/// اللوحة نفسها دون اتصال يصلان إلى السيارة نفسها بعد المزامنة.
///
/// تاريخ المالكين يُقرأ من البطاقات نفسها (من أحضر السيارة ومتى)، لذا لا جدول
/// منفصل له.
abstract final class VehicleRegistry {
  VehicleRegistry._();

  static const table = 'vehicles';

  static const _kinds = [
    ServiceOrderKinds.oilChange,
    ServiceOrderKinds.carWash,
  ];

  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vehicles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        global_id TEXT NOT NULL UNIQUE,
        tenantId INTEGER NOT NULL,
        plate_key TEXT NOT NULL,
        plate_display TEXT,
        plate_number TEXT,
        plate_letter TEXT,
        plate_province TEXT,
        name TEXT,
        model TEXT,
        engine_size TEXT,
        customer_global_id TEXT,
        customer_id INTEGER,
        customer_name TEXT,
        customer_phone TEXT,
        last_odometer INTEGER,
        last_odometer_unit TEXT,
        last_visit_at TEXT,
        visits_count INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        deletedAt TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_vehicles_plate '
      'ON vehicles(tenantId, plate_key)',
    );
    // وحدة آخر عداد (كم/ميل) — سجل قديم بلا العمود يُكمَّل من آخر بطاقة.
    // وإعادة الحساب القديمة كانت تكتب «كم» لكل سيارة (لم تقرأ وحدة البطاقة)،
    // فتُصحَّح في كل فتح السيارات التي لها زيارة بالميل فقط (عدد صغير).
    final vcols = await db.rawQuery('PRAGMA table_info(vehicles)');
    final fresh = !vcols.any((c) => c['name'] == 'last_odometer_unit');
    if (fresh) {
      await db.execute(
        'ALTER TABLE vehicles ADD COLUMN last_odometer_unit TEXT',
      );
    }
    try {
      await db.execute('''
        UPDATE vehicles SET last_odometer_unit = (
          SELECT so.odometerUnit FROM service_orders so
          WHERE so.vehicle_global_id = vehicles.global_id
            AND so.deletedAt IS NULL
            AND TRIM(IFNULL(so.status, '')) NOT IN ('suspended', 'cancelled')
            AND TRIM(IFNULL(so.odometerCurrent, '')) <> ''
          ORDER BY so.createdAt DESC, so.id DESC
          LIMIT 1
        )
        ${fresh ? '' : '''
        WHERE global_id IN (
          SELECT vehicle_global_id FROM service_orders
          WHERE odometerUnit = 'mi' AND deletedAt IS NULL
        )'''}
      ''');
    } catch (e) {
      AppLogger.warn('VehicleRegistry', 'odometer unit backfill: $e');
    }
    final cols = await db.rawQuery('PRAGMA table_info(service_orders)');
    if (cols.isEmpty) return;
    final has = cols.any((c) => c['name'] == 'vehicle_global_id');
    if (!has) {
      await db.execute(
        'ALTER TABLE service_orders ADD COLUMN vehicle_global_id TEXT',
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_service_orders_vehicle '
      'ON service_orders(tenantId, vehicle_global_id)',
    );
  }

  static String vehicleGlobalId(int tenantId, String plateKey) =>
      'veh-$tenantId-$plateKey';

  /// الرقم فقط إن كانت اللوحة أرقاماً بلا رمز ولا حرف؛ غير ذلك يُكمَّل لاحقاً.
  static String? plateNumberIfPlain(String plate) {
    final digits = OilChangeLookupNormalize.toWesternDigits(plate);
    // المسافات تنسيق فقط؛ الشرطة وما بعدها رمز محافظة.
    final compact = plate.replaceAll(RegExp(r'\s'), '');
    if (digits.isEmpty || digits.length != compact.length) return null;
    return digits;
  }

  /// السيارة بهذه اللوحة في هذا المحل، أو null.
  static Future<Map<String, dynamic>?> findByPlate(
    DatabaseExecutor db,
    int tenantId,
    String plate,
  ) async {
    final key = OilChangeLookupNormalize.normalizePlateKey(plate);
    if (key.isEmpty) return null;
    final rows = await db.query(
      table,
      where: 'tenantId = ? AND plate_key = ? AND deletedAt IS NULL',
      whereArgs: [tenantId, key],
      orderBy: 'id ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// يربط البطاقة [orderId] بسيارتها ويعيد حساب السيارة (والقديمة إن تغيّرت
  /// اللوحة). لا يرمي أبداً: فشل السجل لا يوقف حفظ البطاقة.
  static Future<void> linkOrder(
    DatabaseExecutor db,
    int tenantId,
    int orderId,
  ) async {
    try {
      final rows = await db.query(
        'service_orders',
        columns: [
          'id',
          'orderKind',
          'deviceSerial',
          'vehicle_global_id',
          'deletedAt',
        ],
        where: 'id = ? AND tenantId = ?',
        whereArgs: [orderId, tenantId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final r = rows.first;
      final kind = (r['orderKind'] ?? '').toString();
      if (!_kinds.contains(kind)) return;
      final oldGid = (r['vehicle_global_id'] ?? '').toString();
      final key = OilChangeLookupNormalize.normalizePlateKey(
        (r['deviceSerial'] ?? '').toString(),
      );
      var newGid = '';
      if (key.isNotEmpty) {
        final existing = await db.query(
          table,
          columns: ['global_id'],
          where: 'tenantId = ? AND plate_key = ?',
          whereArgs: [tenantId, key],
          orderBy: 'id ASC',
          limit: 1,
        );
        newGid = existing.isNotEmpty
            ? existing.first['global_id'].toString()
            : vehicleGlobalId(tenantId, key);
      }
      if (newGid != oldGid) {
        await db.update(
          'service_orders',
          {'vehicle_global_id': newGid.isEmpty ? null : newGid},
          where: 'id = ?',
          whereArgs: [orderId],
        );
      }
      if (newGid.isNotEmpty) await rebuild(db, tenantId, newGid);
      if (oldGid.isNotEmpty && oldGid != newGid) {
        await rebuild(db, tenantId, oldGid);
      }
    } catch (e, st) {
      AppLogger.error('VehicleRegistry', 'linkOrder failed', e, st);
    }
  }

  static const _orderCols = [
    'id',
    'tenantId',
    'orderKind',
    'status',
    'createdAt',
    'deviceSerial',
    'deviceName',
    'carModel',
    'engineSize',
    'odometerCurrent',
    'odometerUnit',
    'customerId',
    'customerNameSnapshot',
    'customerPhone',
    'vehicle_global_id',
  ];

  /// يعيد حساب سيارة واحدة من بطاقاتها.
  static Future<void> rebuild(
    DatabaseExecutor db,
    int tenantId,
    String gid,
  ) async {
    final orders = await db.query(
      'service_orders',
      columns: _orderCols,
      where: 'tenantId = ? AND vehicle_global_id = ? AND deletedAt IS NULL',
      whereArgs: [tenantId, gid],
    );
    await _writeVehicle(db, tenantId, gid, orders);
  }

  /// يربط كل بطاقة غير مربوطة ثم يعيد حساب السيارات. يُستدعى عند فتح
  /// القاعدة (يعيد الحساب فقط إن رُبط شيء) وبعد سحب لقطة من السحابة
  /// ([always]: بطاقات مربوطة وصلت من جهاز آخر). آمن للتكرار.
  static Future<int> reconcile(
    DatabaseExecutor db, {
    bool always = false,
  }) async {
    try {
      final unlinked = await db.query(
        'service_orders',
        columns: ['id', 'tenantId', 'deviceSerial'],
        where:
            "(vehicle_global_id IS NULL OR vehicle_global_id = '') "
            'AND deletedAt IS NULL '
            "AND deviceSerial IS NOT NULL AND trim(deviceSerial) != '' "
            'AND orderKind IN (?, ?)',
        whereArgs: _kinds,
      );
      final keyToGid = <String, String>{};
      final existing = await db.query(
        table,
        columns: ['tenantId', 'plate_key', 'global_id'],
        orderBy: 'id DESC',
      );
      for (final v in existing) {
        keyToGid['${v['tenantId']}|${v['plate_key']}'] = v['global_id']
            .toString();
      }
      var linked = 0;
      for (final r in unlinked) {
        final tid = (r['tenantId'] as num?)?.toInt() ?? 1;
        final key = OilChangeLookupNormalize.normalizePlateKey(
          (r['deviceSerial'] ?? '').toString(),
        );
        if (key.isEmpty) continue;
        final gid = keyToGid.putIfAbsent(
          '$tid|$key',
          () => vehicleGlobalId(tid, key),
        );
        await db.update(
          'service_orders',
          {'vehicle_global_id': gid},
          where: 'id = ?',
          whereArgs: [r['id']],
        );
        linked++;
      }
      if (linked > 0 || always) await rebuildAll(db);
      return linked;
    } catch (e, st) {
      AppLogger.error('VehicleRegistry', 'reconcile failed', e, st);
      return 0;
    }
  }

  /// يعيد حساب كل السيارات بقراءة واحدة للبطاقات المربوطة.
  static Future<void> rebuildAll(DatabaseExecutor db) async {
    final orders = await db.query(
      'service_orders',
      columns: _orderCols,
      where:
          "vehicle_global_id IS NOT NULL AND vehicle_global_id != '' "
          'AND deletedAt IS NULL',
    );
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final o in orders) {
      final tid = (o['tenantId'] as num?)?.toInt() ?? 1;
      groups.putIfAbsent('$tid|${o['vehicle_global_id']}', () => []).add(o);
    }
    final known = await db.query(table);
    final byGid = <String, Map<String, dynamic>>{};
    for (final v in known) {
      byGid[v['global_id'].toString()] = v;
      if (v['deletedAt'] == null) {
        groups.putIfAbsent('${v['tenantId']}|${v['global_id']}', () => []);
      }
    }
    final customerGids = <int, String>{};
    try {
      final cs = await db.rawQuery(
        "SELECT id, global_id FROM customers WHERE global_id IS NOT NULL AND global_id != ''",
      );
      for (final c in cs) {
        customerGids[(c['id'] as num).toInt()] = c['global_id'].toString();
      }
    } catch (_) {}
    for (final e in groups.entries) {
      final sep = e.key.indexOf('|');
      final tid = int.tryParse(e.key.substring(0, sep)) ?? 1;
      final gid = e.key.substring(sep + 1);
      await _writeVehicle(
        db,
        tid,
        gid,
        e.value,
        current: byGid[gid],
        customerGids: customerGids,
      );
    }
  }

  static DateTime _at(Map<String, dynamic> o) =>
      DateTime.tryParse((o['createdAt'] ?? '').toString()) ??
      DateTime.fromMillisecondsSinceEpoch(0);

  static int _byTime(Map<String, dynamic> a, Map<String, dynamic> b) {
    final c = _at(a).compareTo(_at(b));
    if (c != 0) return c;
    return ((a['id'] as num?) ?? 0).compareTo((b['id'] as num?) ?? 0);
  }

  static String _s(Object? v) => (v ?? '').toString().trim();

  static Future<void> _writeVehicle(
    DatabaseExecutor db,
    int tenantId,
    String gid,
    List<Map<String, dynamic>> ordersRaw, {
    Map<String, dynamic>? current,
    Map<int, String>? customerGids,
  }) async {
    final cur =
        current ??
        (await db.query(
          table,
          where: 'global_id = ?',
          whereArgs: [gid],
          limit: 1,
        )).firstOrNull;
    final now = DateTime.now().toUtc().toIso8601String();
    final orders =
        ordersRaw.where((o) => !OilChangeOrderStatus.isCancelled(o)).toList()
          ..sort(_byTime);

    if (orders.isEmpty) {
      if (cur != null && cur['deletedAt'] == null) {
        await db.update(
          table,
          {'deletedAt': now, 'updatedAt': now, 'visits_count': 0},
          where: 'global_id = ?',
          whereArgs: [gid],
        );
      }
      return;
    }

    String latest(String col) {
      for (final o in orders.reversed) {
        final v = _s(o[col]);
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final visits = orders
        .where((o) => !OilChangeOrderStatus.isSuspended(o))
        .toList();
    int? lastOdo;
    String? lastOdoUnit;
    for (final o in visits.reversed) {
      final d = OilChangeLookupNormalize.toWesternDigits(
        _s(o['odometerCurrent']),
      );
      final n = int.tryParse(d);
      if (n != null && n > 0) {
        lastOdo = n;
        lastOdoUnit = OilOdometerUnit.of(o);
        break;
      }
    }

    Map<String, dynamic>? owner;
    for (final o in orders.reversed) {
      final cid = (o['customerId'] as num?)?.toInt() ?? 0;
      if (cid > 0 || _s(o['customerNameSnapshot']).isNotEmpty) {
        owner = o;
        break;
      }
    }
    final ownerId = (owner?['customerId'] as num?)?.toInt();
    String? ownerGid;
    if (customerGids != null) {
      ownerGid = ownerId == null ? null : customerGids[ownerId];
    } else if (ownerId != null && ownerId > 0) {
      try {
        final c = await db.query(
          'customers',
          columns: ['global_id'],
          where: 'id = ?',
          whereArgs: [ownerId],
          limit: 1,
        );
        if (c.isNotEmpty) {
          final g = _s(c.first['global_id']);
          ownerGid = g.isEmpty ? null : g;
        }
      } catch (_) {}
    }

    final plateDisplay = latest('deviceSerial');
    final parts = IraqPlate.parse(plateDisplay);
    final values = <String, Object?>{
      'tenantId': tenantId,
      'plate_key': OilChangeLookupNormalize.normalizePlateKey(plateDisplay),
      'plate_display': plateDisplay,
      'plate_number': plateNumberIfPlain(parts.number),
      'plate_letter': parts.letter,
      'plate_province': parts.province,
      'name': latest('deviceName'),
      'model': latest('carModel'),
      'engine_size': latest('engineSize'),
      'customer_global_id': ownerGid,
      'customer_id': (ownerId ?? 0) > 0 ? ownerId : null,
      'customer_name': owner == null ? null : _s(owner['customerNameSnapshot']),
      'customer_phone': owner == null ? null : _s(owner['customerPhone']),
      'last_odometer': lastOdo,
      'last_odometer_unit': lastOdoUnit,
      'last_visit_at': visits.isEmpty ? null : _s(visits.last['createdAt']),
      'visits_count': visits.length,
      'deletedAt': null,
    };

    if (cur == null) {
      await db.insert(table, {
        'global_id': gid,
        ...values,
        'createdAt': _s(orders.first['createdAt']).isEmpty
            ? now
            : _s(orders.first['createdAt']),
        'updatedAt': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return;
    }
    final changed = values.entries.any((e) => cur[e.key] != e.value);
    if (!changed) return;
    await db.update(
      table,
      {...values, 'updatedAt': now},
      where: 'global_id = ?',
      whereArgs: [gid],
    );
  }

  /// آخر قراءة عداد مسجّلة لسيارة [plate] قبل هذه البطاقة. عند تعديل بطاقة
  /// ([excludeOrderId]) تُؤخذ القراءات التي قبلها فقط. المعلّقة والملغاة
  /// ليست زيارات. null إن لم تُعرف السيارة؛ `km == null` إن لم تُسجَّل قراءة.
  /// [unit]: وحدة تلك القراءة ('km' أو 'mi') — الرقم بوحدة السيارة لا بالكيلومتر.
  static Future<({int? km, String? at, String unit})?> previousReading(
    DatabaseExecutor db,
    int tenantId, {
    required String plate,
    int? excludeOrderId,
  }) async {
    final v = await findByPlate(db, tenantId, plate);
    if (v == null) return null;
    DateTime? before;
    if (excludeOrderId != null && excludeOrderId > 0) {
      final self = await db.query(
        'service_orders',
        columns: ['createdAt'],
        where: 'id = ?',
        whereArgs: [excludeOrderId],
        limit: 1,
      );
      if (self.isNotEmpty)
        before = DateTime.tryParse(_s(self.first['createdAt']));
    }
    final rows = [
      ...await db.query(
        'service_orders',
        columns: ['id', 'createdAt', 'odometerCurrent', 'odometerUnit', 'status'],
        where:
            'tenantId = ? AND vehicle_global_id = ? AND deletedAt IS NULL '
            "AND status NOT IN ('${OilChangeOrderStatus.suspended}', "
            "'${OilChangeOrderStatus.cancelled}')"
            '${excludeOrderId != null ? ' AND id != ?' : ''}',
        whereArgs: [
          tenantId,
          v['global_id'],
          if (excludeOrderId != null) excludeOrderId,
        ],
      ),
    ];
    rows.sort((a, b) => _byTime(b, a));
    for (final o in rows) {
      if (before != null && !_at(o).isBefore(before)) continue;
      final n = int.tryParse(
        OilChangeLookupNormalize.toWesternDigits(_s(o['odometerCurrent'])),
      );
      if (n != null && n > 0) {
        return (
          km: n,
          at: _s(o['createdAt']),
          unit: OilOdometerUnit.of(o),
        );
      }
    }
    return (km: null, at: null, unit: OilOdometerUnit.km);
  }

  /// أول رقم في اللوحة (قبل أي شرطة أو رمز)، بأرقام غربية.
  static String _leadingDigits(String number) {
    final m = RegExp(r'^[0-9٠-٩۰-۹]+').firstMatch(number.trim());
    return m == null
        ? ''
        : OilChangeLookupNormalize.toWesternDigits(m.group(0)!);
  }

  /// سيارات قديمة ناقصة اللوحة (بلا حرف ولا محافظة) رقمها = رقم [plate].
  /// مثال: كُتبت «12345 B البصرة» وفي السجل «12345» أو «12345-14»: قد تكون
  /// السيارة نفسها، فيُسأل الموظف. لا شيء إن لم تحمل اللوحة حرفاً ولا محافظة.
  static Future<List<Map<String, dynamic>>> legacyCandidates(
    DatabaseExecutor db,
    int tenantId,
    String plate,
  ) async {
    final p = IraqPlate.parse(plate);
    if (!p.isPlainNumber) return const [];
    if ((p.letter ?? '').isEmpty && (p.province ?? '').isEmpty) return const [];
    final digits = _leadingDigits(p.number);
    if (digits.isEmpty) return const [];
    final fullKey = OilChangeLookupNormalize.normalizePlateKey(plate);
    final rows = await db.query(
      table,
      where:
          'tenantId = ? AND deletedAt IS NULL AND plate_key LIKE ? '
          'AND plate_key != ? '
          "AND (plate_letter IS NULL OR plate_letter = '') "
          "AND (plate_province IS NULL OR plate_province = '')",
      whereArgs: [tenantId, '$digits%', fullKey],
      orderBy: 'last_visit_at DESC',
      limit: 20,
    );
    return rows
        .where((v) {
          final n = IraqPlate.parse(_s(v['plate_display'])).number;
          return _leadingDigits(n) == digits;
        })
        .take(5)
        .toList();
  }

  /// الموظف أكّد أن [plate] هي السيارة [gid]: تأخذ السيارة اللوحة الكاملة
  /// فتُربط بها البطاقة عند الحفظ. لا شيء إن كانت اللوحة لسيارة أخرى.
  static Future<bool> adoptPlate(
    DatabaseExecutor db,
    int tenantId,
    String gid,
    String plate,
  ) async {
    final key = OilChangeLookupNormalize.normalizePlateKey(plate);
    if (key.isEmpty) return false;
    final other = await findByPlate(db, tenantId, plate);
    if (other != null) return other['global_id'] == gid;
    final p = IraqPlate.parse(plate);
    final n = await db.update(
      table,
      {
        'plate_key': key,
        'plate_display': plate.trim(),
        'plate_number': plateNumberIfPlain(p.number),
        'plate_letter': p.letter,
        'plate_province': p.province,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'global_id = ? AND tenantId = ?',
      whereArgs: [gid, tenantId],
    );
    return n > 0;
  }

  /// آخر بطاقة مكتملة (زيت أو غسيل حسب [orderKind]) لهذه السيارة، باستعلام
  /// مفهرس واحد. المعلّقة ليست زيارة.
  static Future<Map<String, dynamic>?> latestOrderForVehicle(
    DatabaseExecutor db,
    int tenantId, {
    required String vehicleGlobalId,
    required String orderKind,
    int? excludeOrderId,
  }) async {
    final where = StringBuffer(
      'tenantId = ? AND vehicle_global_id = ? AND deletedAt IS NULL '
      'AND orderKind = ? AND status != ?',
    );
    final args = <Object?>[
      tenantId,
      vehicleGlobalId,
      orderKind,
      OilChangeOrderStatus.suspended,
    ];
    if (excludeOrderId != null && excludeOrderId > 0) {
      where.write(' AND id != ?');
      args.add(excludeOrderId);
    }
    final rows = await db.query(
      'service_orders',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  // ─────────────── الربط بالعملاء (الشريحة 5) ───────────────

  /// سيارات يملكها العميل الآن (هو صاحب آخر بطاقة لها)، الأحدث زيارة أولاً.
  static Future<List<Map<String, dynamic>>> vehiclesForCustomer(
    DatabaseExecutor db,
    int tenantId,
    int customerId,
  ) async {
    if (customerId <= 0) return const [];
    String gid = '';
    try {
      final c = await db.query(
        'customers',
        columns: ['global_id'],
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1,
      );
      if (c.isNotEmpty) gid = _s(c.first['global_id']);
    } catch (_) {}
    return db.query(
      table,
      where:
          'tenantId = ? AND deletedAt IS NULL AND '
          "(customer_id = ?${gid.isEmpty ? '' : ' OR customer_global_id = ?'})",
      whereArgs: [tenantId, customerId, if (gid.isNotEmpty) gid],
      orderBy: 'last_visit_at IS NULL, last_visit_at DESC, id DESC',
    );
  }

  // ─────────────── صفحة سجل السيارات (الشريحة 4) ───────────────

  /// سيارات المحل، الأحدث زيارة أولاً. [query] يبحث في اللوحة (بأي كتابة)
  /// واسم السيارة وموديلها واسم صاحبها وهاتفه.
  static Future<List<Map<String, dynamic>>> listVehicles(
    DatabaseExecutor db,
    int tenantId, {
    String query = '',
    int limit = 50,
    int offset = 0,
  }) async {
    final where = StringBuffer('tenantId = ? AND deletedAt IS NULL');
    final args = <Object?>[tenantId];
    final q = query.trim();
    if (q.isNotEmpty) {
      final key = OilChangeLookupNormalize.normalizePlateKey(q);
      final digits = OilChangeLookupNormalize.toWesternDigits(q);
      final like = '%${q.toLowerCase()}%';
      where.write(
        ' AND (plate_key LIKE ? OR lower(name) LIKE ? OR lower(model) LIKE ? '
        'OR lower(customer_name) LIKE ?',
      );
      args.addAll(['%$key%', like, like, like]);
      if (digits.length >= 4) {
        where.write(' OR customer_phone LIKE ?');
        // الهاتف محفوظ +9647…: آخر الأرقام تكفي («07701234567» أو «7701234567»).
        final tail = digits.startsWith('0') ? digits.substring(1) : digits;
        args.add('%$tail%');
      }
      where.write(')');
    }
    return db.query(
      table,
      where: where.toString(),
      whereArgs: args,
      orderBy: 'last_visit_at IS NULL, last_visit_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
  }

  static Future<Map<String, dynamic>?> getByGlobalId(
    DatabaseExecutor db,
    int tenantId,
    String gid,
  ) async {
    final rows = await db.query(
      table,
      where: 'tenantId = ? AND global_id = ?',
      whereArgs: [tenantId, gid],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// كل بطاقات السيارة (زيت وغسيل)، الأحدث أولاً. المعلّقة والملغاة خارجها.
  static Future<List<Map<String, dynamic>>> visits(
    DatabaseExecutor db,
    int tenantId,
    String gid,
  ) async {
    final rows = [
      ...await db.query(
        'service_orders',
        where:
            'tenantId = ? AND vehicle_global_id = ? AND deletedAt IS NULL '
            "AND status NOT IN ('${OilChangeOrderStatus.suspended}', "
            "'${OilChangeOrderStatus.cancelled}')",
        whereArgs: [tenantId, gid],
      ),
    ];
    rows.sort((a, b) => _byTime(b, a));
    return rows;
  }

  /// من أحضر السيارة ومتى: فترات متتالية بالمالك نفسه، الأقدم أولاً.
  /// بطاقة بلا اسم زبون لا تقطع الفترة. [visitsNewestFirst] من [visits].
  static List<VehicleOwnerPeriod> ownerPeriods(
    List<Map<String, dynamic>> visitsNewestFirst,
  ) {
    final out = <VehicleOwnerPeriod>[];
    for (final o in visitsNewestFirst.reversed) {
      final name = _s(o['customerNameSnapshot']);
      final cid = (o['customerId'] as num?)?.toInt() ?? 0;
      if (name.isEmpty && cid <= 0) continue;
      final phone = _s(o['customerPhone']);
      final at = _at(o);
      final last = out.isEmpty ? null : out.last;
      // الشخص نفسه: العميل المسجّل نفسه، أو الهاتف نفسه بأي كتابة، أو الاسم
      // نفسه (بلا فرق الهمزة) وأحد الهاتفين فارغ.
      final bothPhones = phone.isNotEmpty && (last?.phone.isNotEmpty ?? false);
      final same = last != null &&
          ((cid > 0 && last.customerId == cid) ||
              (bothPhones && _phoneTail(phone) == _phoneTail(last.phone)) ||
              (!bothPhones && _nameFold(name) == _nameFold(last.name)));
      if (same) {
        out[out.length - 1] = last.extend(at, phone: phone, name: name);
      } else {
        out.add(
          VehicleOwnerPeriod(
            name: name,
            phone: phone,
            customerId: cid > 0 ? cid : null,
            from: at,
            to: at,
            visits: 1,
          ),
        );
      }
    }
    return out;
  }

  static String _nameFold(String n) =>
      OilChangeLookupNormalize.normalizeNameKey(n)
          .replaceAll(RegExp('[أإآ]'), 'ا')
          .replaceAll('ة', 'ه')
          .replaceAll('ى', 'ي');

  static String _phoneTail(String p) {
    final d = OilChangeLookupNormalize.toWesternDigits(p);
    return d.length <= 9 ? d : d.substring(d.length - 9);
  }
}

/// فترة ملكية مشتقة من البطاقات.
class VehicleOwnerPeriod {
  const VehicleOwnerPeriod({
    required this.name,
    required this.phone,
    required this.customerId,
    required this.from,
    required this.to,
    required this.visits,
  });

  final String name;
  final String phone;
  final int? customerId;
  final DateTime from;
  final DateTime to;
  final int visits;

  /// زيارة أحدث للمالك نفسه: الاسم والهاتف الأحدث يُعرضان إن كُتبا.
  VehicleOwnerPeriod extend(DateTime at, {String phone = '', String name = ''}) =>
      VehicleOwnerPeriod(
        name: name.trim().isEmpty ? this.name : name.trim(),
        phone: phone.isEmpty ? this.phone : phone,
        customerId: customerId,
        from: from,
        to: at.isAfter(to) ? at : to,
        visits: visits + 1,
      );
}
