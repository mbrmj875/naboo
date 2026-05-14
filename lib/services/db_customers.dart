part of 'database_helper.dart';

// ── العملاء ───────────────────────────────────────────────────────────────

Future<void> ensureCustomersGlobalIdSchema(Database db) async {
  Future<void> addColumn(String col, String type) async {
    final rows = await db.rawQuery('PRAGMA table_info(customers)');
    final exists = rows.any((r) => (r['name']?.toString().toLowerCase() ?? '') == col.toLowerCase());
    if (!exists) {
      try {
        await db.execute('ALTER TABLE customers ADD COLUMN $col $type');
      } catch (_) {}
    }
  }

  await addColumn('global_id', 'TEXT');
  await addColumn('tenantId', 'INTEGER NOT NULL DEFAULT 1');

  Future<bool> colExists(String name) async {
    final rows = await db.rawQuery('PRAGMA table_info(customers)');
    return rows.any((r) => (r['name']?.toString().toLowerCase() ?? '') == name.toLowerCase());
  }

  if (await colExists('global_id')) {
    try {
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS uq_customers_global_id
        ON customers(global_id)
        WHERE global_id IS NOT NULL AND TRIM(global_id) != ''
      ''');
    } catch (_) {}
  }

  if (!await colExists('global_id')) return;

  final missing = await db.rawQuery('''
    SELECT id, createdAt FROM customers
    WHERE global_id IS NULL OR TRIM(IFNULL(global_id, '')) = ''
  ''');
  for (final r in missing) {
    final id = r['id'] as int?;
    if (id == null) continue;
    await db.update(
      'customers',
      {
        'global_id': const Uuid().v4(),
        'updatedAt': r['createdAt'] ?? DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  await db.execute('''
    UPDATE customers
    SET updatedAt = createdAt
    WHERE updatedAt IS NULL OR TRIM(IFNULL(updatedAt, '')) = ''
  ''');
}

({List<String> clauses, List<Object?> args}) _customerSearchWhereParts(
  String rawQuery,
) {
  final q = rawQuery.trim().toLowerCase();
  final qDigits = rawQuery.replaceAll(RegExp(r'\D'), '');
  if (q.isEmpty) return (clauses: <String>[], args: <Object?>[]);

  final clauses = <String>[];
  final args = <Object?>[];
  final or = <String>[
    'LOWER(customers.name) LIKE ?',
    "LOWER(IFNULL(customers.phone, '')) LIKE ?",
    "LOWER(IFNULL(customers.email, '')) LIKE ?",
    '''
    EXISTS (
      SELECT 1 FROM customer_extra_phones cep
      WHERE cep.customerId = customers.id
        AND LOWER(IFNULL(cep.phone, '')) LIKE ?
    )
    ''',
  ];
  args.addAll(['%$q%', '%$q%', '%$q%', '%$q%']);
  if (qDigits.length >= 2) {
    or.add("IFNULL(customers.phone, '') LIKE ?");
    args.add('%$qDigits%');
    or.add('''
      EXISTS (
        SELECT 1 FROM customer_extra_phones cep2
        WHERE cep2.customerId = customers.id
          AND IFNULL(cep2.phone, '') LIKE ?
      )
    ''');
    args.add('%$qDigits%');
  }
  if (qDigits.isNotEmpty) {
    or.add('CAST(customers.id AS TEXT) LIKE ?');
    args.add('%$qDigits%');
    or.add("printf('%06d', customers.id) LIKE ?");
    args.add('%$qDigits%');
  }
  clauses.add('(${or.join(' OR ')})');
  return (clauses: clauses, args: args);
}

/// فلترة التبويب: يجب أن تكون متّسقة مع [CustomerRecord.statusLabel].
String? _customerTabBalancePredicate(String statusArabic) {
  final st = statusArabic.trim();
  if (st.isEmpty || st == 'الكل') return null;
  if (st == 'مديون' || st.contains('مدين')) return 'customers.balance > 0.01';
  if (st.contains('دائن')) return 'customers.balance < -0.01';
  if (st.contains('مميز')) return 'ABS(customers.balance) < 1e-6';
  if (st.contains('مصفّى') || st.contains('صفر')) {
    return 'ABS(customers.balance) < 1e-9';
  }
  return null;
}

/// تطابق رقم عميل ورقُم كود ظاهر بعد إزالة غير الأرقام.
void _appendCustomerIdExactIfPresent(
  List<String> where,
  List<Object?> args,
  String raw,
) {
  final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsOnly.isEmpty) return;
  final id = int.tryParse(digitsOnly);
  if (id == null) return;
  where.add('customers.id = ?');
  args.add(id);
}

extension DbCustomers on DatabaseHelper {
  Future<List<Map<String, dynamic>>> getAllCustomers() async {
    final db = await database;
    return db.query('customers', orderBy: 'name COLLATE NOCASE ASC');
  }

  Future<int> countCustomersTotal() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM customers');
    if (r.isEmpty) return 0;
    return (r.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<
      ({
        int all,
        int indebted,
        int creditor,
        int distinguished,
      })> getCustomerTabCountsRaw() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) AS all_c,
        SUM(CASE WHEN balance > 0.01 THEN 1 ELSE 0 END) AS ind,
        SUM(CASE WHEN balance < -0.01 THEN 1 ELSE 0 END) AS cred,
        SUM(CASE WHEN ABS(balance) < 1e-6 THEN 1 ELSE 0 END) AS dist
      FROM customers
      ''');
    int n(Map<String, Object?> row, String k) =>
        row[k] == null ? 0 : (row[k] as num?)?.toInt() ?? 0;
    final m = rows.isEmpty ? <String, Object?>{} : rows.first;
    return (
      all: n(m, 'all_c'),
      indebted: n(m, 'ind'),
      creditor: n(m, 'cred'),
      distinguished: n(m, 'dist'),
    );
  }

  Future<int> countCustomersMatching({
    required String query,
    required String statusArabic,
    String idQuery = '',
  }) async {
    final sr = _customerSearchWhereParts(query);
    final bal = _customerTabBalancePredicate(statusArabic);
    final where = <String>[];
    final args = <Object?>[];
    final b = bal;
    if (b != null) where.add(b);
    where.addAll(sr.clauses);
    args.addAll(sr.args);
    _appendCustomerIdExactIfPresent(where, args, idQuery);
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final db = await database;
    final out =
        await db.rawQuery('SELECT COUNT(*) AS c FROM customers $whereSql', args);
    if (out.isEmpty) return 0;
    return (out.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<Map<int, double>> sumSaleInvoiceTotalsForCustomerIds(
    Iterable<int> ids,
  ) async {
    final idList = ids.toSet().toList();
    if (idList.isEmpty) return {};
    final db = await database;
    final placeholders = List.filled(idList.length, '?').join(',');
    final t = [
      InvoiceType.cash.index,
      InvoiceType.credit.index,
      InvoiceType.installment.index,
      InvoiceType.delivery.index,
    ];
    final typeList = '${t[0]},${t[1]},${t[2]},${t[3]}';
    final rows = await db.rawQuery(
      '''
      SELECT inv.customerId AS cid,
             SUM(
               CASE
                 WHEN IFNULL(inv.totalFils, 0) != 0
                   THEN CAST(inv.totalFils AS REAL) / 1000.0
                 ELSE IFNULL(inv.total, 0)
               END
             ) AS tot
      FROM invoices inv
      WHERE IFNULL(inv.isReturned, 0) = 0
        AND inv.customerId IN ($placeholders)
        AND inv.type IN ($typeList)
      GROUP BY inv.customerId
      ''',
      idList,
    );
    final out = <int, double>{};
    for (final r in rows) {
      final cid = r['cid'] as int?;
      if (cid == null) continue;
      out[cid] = (r['tot'] as num?)?.toDouble() ?? 0;
    }
    return out;
  }

  Future<Map<String, Object?>?> findCustomerRowByInsensitiveNameDup(
    String name, {
    int? excludeId,
  }) async {
    final n = name.trim();
    if (n.length < 2) return null;
    final db = await database;
    final wc = excludeId != null
        ? 'WHERE LOWER(TRIM(name)) = LOWER(TRIM(?)) AND id <> ? LIMIT 1'
        : 'WHERE LOWER(TRIM(name)) = LOWER(TRIM(?)) LIMIT 1';
    final wa = excludeId != null ? <Object?>[n, excludeId] : <Object?>[n];
    final rows =
        await db.rawQuery('SELECT id, name FROM customers $wc', wa);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<Map<String, Object?>?> findCustomerRowByDupEmail(
    String emailRaw, {
    int? excludeId,
  }) async {
    final e = emailRaw.trim().toLowerCase();
    if (!e.contains('@')) return null;
    final db = await database;
    final rows = excludeId == null
        ? await db.rawQuery(
            '''
            SELECT id, name FROM customers
            WHERE LOWER(TRIM(IFNULL(email, ''))) = ?
            LIMIT 1
            ''',
            [e],
          )
        : await db.rawQuery(
            '''
            SELECT id, name FROM customers
            WHERE LOWER(TRIM(IFNULL(email, ''))) = ? AND id <> ?
            LIMIT 1
            ''',
            [e, excludeId],
          );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// استعلام صفحات للعملاء — مع مجموع مشتريات تقريبي لكل عميل إن أمكن.
  ///
  /// - [sortKey]: `name_asc` \| `name_desc` \| `balance_desc` \| `date_desc`
  ///                \| `total_purchases_desc`
  Future<List<Map<String, dynamic>>> queryCustomersPage({
    required String query,
    required String statusArabic,
    required String sortKey,
    required int limit,
    required int offset,
    String idQuery = '',
  }) async {
    final sr = _customerSearchWhereParts(query);
    final bal = _customerTabBalancePredicate(statusArabic);
    final where = <String>[];
    final args = <Object?>[];
    final bp = bal;
    if (bp != null) where.add(bp);
    where.addAll(sr.clauses);
    args.addAll(sr.args);
    _appendCustomerIdExactIfPresent(where, args, idQuery);
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    final t = [
      InvoiceType.cash.index,
      InvoiceType.credit.index,
      InvoiceType.installment.index,
      InvoiceType.delivery.index,
    ];
    final typeList = '${t[0]},${t[1]},${t[2]},${t[3]}';

    final purchaseJoin = '''
LEFT JOIN (
  SELECT customerId AS cid,
         SUM(
           CASE
             WHEN IFNULL(inv.totalFils, 0) != 0
               THEN CAST(inv.totalFils AS REAL) / 1000.0
             ELSE IFNULL(inv.total, 0)
           END
         ) AS purchaseTotal
  FROM invoices inv
  WHERE IFNULL(inv.isReturned, 0) = 0
    AND inv.customerId IS NOT NULL
    AND inv.type IN ($typeList)
  GROUP BY inv.customerId
) pur ON pur.cid = customers.id
''';

    final orderBy = switch (sortKey) {
      'balance_desc' =>
        'customers.balance DESC, customers.name COLLATE NOCASE ASC',
      'date_desc' =>
        'customers.createdAt DESC, customers.name COLLATE NOCASE ASC',
      'name_desc' => 'customers.name COLLATE NOCASE DESC',
      'total_purchases_desc' =>
        'IFNULL(pur.purchaseTotal, 0) DESC, customers.name COLLATE NOCASE ASC',
      _ => 'customers.name COLLATE NOCASE ASC',
    };

    final db = await database;
    return db.rawQuery(
      '''
      SELECT
        customers.id,
        customers.name,
        customers.phone,
        customers.email,
        customers.address,
        customers.notes,
        customers.balance,
        customers.loyaltyPoints,
        customers.createdAt,
        customers.updatedAt,
        IFNULL(pur.purchaseTotal, 0) AS purchaseTotal
      FROM customers
      $purchaseJoin
      $whereSql
      ORDER BY $orderBy
      LIMIT ? OFFSET ?
      ''',
      [...args, limit, offset],
    );
  }

  /// يعيد `id` العميل الذي يملك نفس تسلسل الأرقام (بعد التطبيع) في `customers.phone`
  /// أو في `customer_extra_phones`، أو `null`.
  Future<int?> findCustomerIdOwningNormalizedPhoneAnywhere(
    String normalizedDigits, {
    int? excludeCustomerId,
  }) async {
    if (normalizedDigits.isEmpty) return null;
    final db = await database;
    final rows = await db.query('customers', columns: ['id', 'phone']);
    for (final r in rows) {
      final cid = r['id'] as int;
      if (excludeCustomerId != null && cid == excludeCustomerId) continue;
      final stored = CustomerValidation.normalizePhoneDigits(
        r['phone']?.toString(),
      );
      if (stored != null && stored == normalizedDigits) return cid;
    }
    final extras = await db.query(
      'customer_extra_phones',
      columns: ['customerId', 'phone'],
    );
    for (final r in extras) {
      final cid = r['customerId'] as int;
      if (excludeCustomerId != null && cid == excludeCustomerId) continue;
      final stored = CustomerValidation.normalizePhoneDigits(
        r['phone']?.toString(),
      );
      if (stored != null && stored == normalizedDigits) return cid;
    }
    return null;
  }

  Future<void> _assertPhonesUniqueForSave({
    required String? primaryPhone,
    required List<String> extraPhones,
    int? excludeCustomerId,
  }) async {
    final all = <String>[
      if (primaryPhone != null && primaryPhone.trim().isNotEmpty)
        primaryPhone.trim(),
      ...extraPhones.map((e) => e.trim()).where((s) => s.isNotEmpty),
    ];
    final seen = <String>{};
    for (final raw in all) {
      final n = CustomerValidation.normalizePhoneDigits(raw);
      if (n == null || n.isEmpty) continue;
      if (!seen.add(n)) {
        throw DuplicateCustomerPhoneException(
          'لا يمكن إدخال نفس رقم الهاتف أكثر من مرة لهذا العميل.',
        );
      }
    }
    for (final raw in all) {
      final n = CustomerValidation.normalizePhoneDigits(raw);
      if (n == null || n.isEmpty) continue;
      final other = await findCustomerIdOwningNormalizedPhoneAnywhere(
        n,
        excludeCustomerId: excludeCustomerId,
      );
      if (other != null) {
        throw DuplicateCustomerPhoneException(
          'رقم الهاتف مسجّل مسبقًا لعميل آخر. الأسماء يمكن أن تتشابه، أما رقم الهاتف فيجب أن يكون فريدًا.',
        );
      }
    }
  }

  Future<void> _replaceCustomerExtraPhones(
    DatabaseExecutor db,
    int customerId,
    List<String> phones,
  ) async {
    await db.delete(
      'customer_extra_phones',
      where: 'customerId = ?',
      whereArgs: [customerId],
    );
    final now = DateTime.now().toIso8601String();
    for (var i = 0; i < phones.length; i++) {
      await db.insert('customer_extra_phones', {
        'customerId': customerId,
        'phone': phones[i],
        'sortOrder': i,
        'createdAt': now,
      });
    }
  }

  /// أرقام إضافية محفوظة للعميل (بعد الرقم الأساسي في عمود `customers.phone`).
  Future<List<String>> getCustomerExtraPhones(int customerId) async {
    final db = await database;
    final rows = await db.query(
      'customer_extra_phones',
      columns: ['phone'],
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'sortOrder ASC, id ASC',
    );
    return [
      for (final r in rows)
        (r['phone'] as String?)?.trim() ?? '',
    ].where((s) => s.isNotEmpty).toList();
  }

  Future<int> insertCustomer({
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    List<String> extraPhones = const [],
    int tenantId = 1,
  }) async {
    final extras = extraPhones
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    await _assertPhonesUniqueForSave(
      primaryPhone: phone,
      extraPhones: extras,
      excludeCustomerId: null,
    );
    final db = await database;
    await ensureCustomersGlobalIdSchema(db);
    final now = DateTime.now().toIso8601String();
    final globalId = const Uuid().v4();
    late final int id;
    await db.transaction((txn) async {
      final payload = {
        'global_id': globalId,
        'tenantId': tenantId,
        'name': name.trim(),
        'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
        'email': email?.trim().isEmpty == true ? null : email?.trim(),
        'address': address?.trim().isEmpty == true ? null : address?.trim(),
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        'balance': 0,
        'loyaltyPoints': 0,
        'createdAt': now,
        'updatedAt': now,
      };
      id = await txn.insert('customers', payload);
      await _replaceCustomerExtraPhones(txn, id, extras);

      await SyncQueueService.instance.enqueueMutation(
        txn,
        entityType: 'customer',
        globalId: globalId,
        operation: 'INSERT',
        payload: payload,
      );
    });
    CloudSyncService.instance.scheduleSyncSoon();
    return id;
  }

  Future<void> updateCustomer({
    required int id,
    required String name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    List<String> extraPhones = const [],
  }) async {
    final extras = extraPhones
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    await _assertPhonesUniqueForSave(
      primaryPhone: phone,
      extraPhones: extras,
      excludeCustomerId: id,
    );
    final db = await database;
    await ensureCustomersGlobalIdSchema(db);
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    var gid = (rows.first['global_id'] as String?)?.trim() ?? '';

    await db.transaction((txn) async {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final updatedPayload = {
        'name': name.trim(),
        'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
        'email': email?.trim().isEmpty == true ? null : email?.trim(),
        'address': address?.trim().isEmpty == true ? null : address?.trim(),
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        'updatedAt': nowIso,
      };

      if (gid.isEmpty) {
        gid = const Uuid().v4();
        updatedPayload['global_id'] = gid;
      }

      await txn.update(
        'customers',
        updatedPayload,
        where: 'id = ?',
        whereArgs: [id],
      );
      await _replaceCustomerExtraPhones(txn, id, extras);

      final fullRow = Map<String, dynamic>.from(rows.first)..addAll(updatedPayload);
      await SyncQueueService.instance.enqueueMutation(
        txn,
        entityType: 'customer',
        globalId: gid,
        operation: 'UPDATE',
        payload: fullRow,
      );
    });
    CloudSyncService.instance.scheduleSyncSoon();
  }

  /// يفك ارتباط خطط التقسيط ثم يحذف العميل.
  Future<void> deleteCustomer(int id) async {
    await deleteCustomers([id]);
  }

  /// حذف عدة عملاء في معاملة واحدة (نفس قواعد الحذف الفردي).
  Future<void> deleteCustomers(Iterable<int> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return;
    final db = await database;
    await ensureCustomersGlobalIdSchema(db);

    final placeholders = List.filled(list.length, '?').join(',');
    final rows = await db.query(
      'customers',
      columns: ['id', 'global_id', 'updatedAt'],
      where: 'id IN ($placeholders)',
      whereArgs: list,
    );

    await db.transaction((txn) async {
      for (final id in list) {
        await txn.update(
          'installment_plans',
          {'customerId': null},
          where: 'customerId = ?',
          whereArgs: [id],
        );
        await txn.delete('customers', where: 'id = ?', whereArgs: [id]);
      }

      for (final r in rows) {
        final gid = r['global_id'] as String?;
        if (gid != null && gid.isNotEmpty) {
          await SyncQueueService.instance.enqueueMutation(
            txn,
            entityType: 'customer',
            globalId: gid,
            operation: 'DELETE',
            payload: {'updatedAt': DateTime.now().toIso8601String()},
          );
        }
      }
    });
    CloudSyncService.instance.scheduleSyncSoon();
  }

  Future<Map<String, dynamic>?> getCustomerById(int id) async {
    final db = await database;
    final rows = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// بحث عملاء (الاسم / الهاتف / البريد) للشريط العلوي.
  Future<List<Map<String, dynamic>>> searchCustomers(
    String query, {
    int limit = 20,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final safe = q.replaceAll('%', '').replaceAll('_', '');
    if (safe.isEmpty) return [];
    final like = '%$safe%';
    final digits = q.replaceAll(RegExp(r'\D'), '');
    final likeDigits =
        digits.isEmpty ? null : '%${digits.replaceAll('%', '')}%';
    final db = await database;
    if (likeDigits != null && likeDigits != '%%') {
      return db.rawQuery(
        '''
        SELECT DISTINCT c.*
        FROM customers c
        WHERE c.name LIKE ? COLLATE NOCASE
           OR IFNULL(c.phone, '') LIKE ?
           OR IFNULL(c.phone, '') LIKE ?
           OR IFNULL(c.email, '') LIKE ? COLLATE NOCASE
           OR EXISTS (
                SELECT 1 FROM customer_extra_phones cep
                WHERE cep.customerId = c.id
                  AND IFNULL(cep.phone, '') LIKE ?
              )
        ORDER BY c.name COLLATE NOCASE ASC
        LIMIT ?
        ''',
        [like, like, likeDigits, like, likeDigits, limit],
      );
    }
    return db.rawQuery(
      '''
      SELECT DISTINCT c.*
      FROM customers c
      WHERE c.name LIKE ? COLLATE NOCASE
         OR IFNULL(c.phone, '') LIKE ?
         OR IFNULL(c.email, '') LIKE ? COLLATE NOCASE
         OR EXISTS (
              SELECT 1 FROM customer_extra_phones cep
              WHERE cep.customerId = c.id
                AND LOWER(IFNULL(cep.phone, '')) LIKE ?
            )
      ORDER BY c.name COLLATE NOCASE ASC
      LIMIT ?
      ''',
      [like, like, like, like, limit],
    );
  }

  /// أرقام هواتف لمجموعة أرقام عملاء (للبحث في الفواتير).
  Future<Map<int, String>> getCustomersPhonesByIds(Set<int> ids) async {
    if (ids.isEmpty) return {};
    final db = await database;
    final list = ids.toList();
    final placeholders = List.filled(list.length, '?').join(',');
    final rows = await db.query(
      'customers',
      columns: ['id', 'phone'],
      where: 'id IN ($placeholders)',
      whereArgs: list,
    );
    return {
      for (final r in rows)
        r['id'] as int: (r['phone'] ?? '').toString(),
    };
  }

  /// عدد فواتير «آجل» وخطط تقسيط مرتبطة بكل عميل (دفعة واحدة).
  Future<Map<int, ({int creditInvoices, int installmentPlans})>>
      getCustomerFinanceCountsBatch(Iterable<int> customerIds) async {
    final ids = customerIds.toSet().toList();
    if (ids.isEmpty) return {};
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final args = <Object?>[...ids, InvoiceType.credit.index];

    final creditRows = await db.rawQuery(
      '''
      SELECT customerId AS cid, COUNT(*) AS c
      FROM invoices
      WHERE customerId IN ($placeholders)
        AND type = ?
        AND IFNULL(isReturned, 0) = 0
      GROUP BY customerId
      ''',
      args,
    );

    final planRows = await db.rawQuery(
      '''
      SELECT customerId AS cid, COUNT(*) AS c
      FROM installment_plans
      WHERE customerId IN ($placeholders)
      GROUP BY customerId
      ''',
      ids,
    );

    final out = <int, ({int creditInvoices, int installmentPlans})>{};
    for (final id in ids) {
      out[id] = (creditInvoices: 0, installmentPlans: 0);
    }
    for (final r in creditRows) {
      final cid = r['cid'] as int?;
      final c = (r['c'] as num?)?.toInt() ?? 0;
      if (cid == null) continue;
      final prev = out[cid]!;
      out[cid] = (
        creditInvoices: c,
        installmentPlans: prev.installmentPlans,
      );
    }
    for (final r in planRows) {
      final cid = r['cid'] as int?;
      final c = (r['c'] as num?)?.toInt() ?? 0;
      if (cid == null) continue;
      final prev = out[cid]!;
      out[cid] = (
        creditInvoices: prev.creditInvoices,
        installmentPlans: c,
      );
    }
    return out;
  }

  /// تطابق اسم عميل واحد فقط (لربط الفاتورة بنقاط الولاء).
  Future<int?> tryResolveCustomerIdByExactName(String name) async {
    final n = name.trim();
    if (n.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'customers',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [n],
      limit: 2,
    );
    if (rows.length != 1) return null;
    return rows.first['id'] as int;
  }
}
