part of 'database_helper.dart';

// ── العملاء ───────────────────────────────────────────────────────────────

extension DbCustomers on DatabaseHelper {
  Future<List<Map<String, dynamic>>> getAllCustomers() async {
    final db = await database;
    return db.query('customers', orderBy: 'name COLLATE NOCASE ASC');
  }

  /// استعلام صفحات للعملاء (بدون تحميل كامل الجدول).
  ///
  /// - [statusArabic]: "الكل" أو قيمة [CustomerRecord.statusLabel] (مثلاً: "مدين"... حسب نموذجك).
  /// - [sortKey]: name_asc | balance_desc | date_desc
  Future<List<Map<String, dynamic>>> queryCustomersPage({
    required String query,
    required String statusArabic,
    required String sortKey,
    required int limit,
    required int offset,
  }) async {
    final db = await database;
    final q = query.trim().toLowerCase();
    final qDigits = query.replaceAll(RegExp(r'\\D'), '');

    final where = <String>[];
    final args = <Object?>[];

    // فلترة حالة (نربطها عملياً بالرصيد لأن statusLabel مشتقة من balance عادةً)
    // لو statusLabel عندك مبني على قواعد أخرى، سنربطه هنا لاحقاً.
    if (statusArabic != 'الكل') {
      if (statusArabic.contains('مدين')) {
        where.add('balance > 0');
      } else if (statusArabic.contains('دائن')) {
        where.add('balance < 0');
      } else if (statusArabic.contains('مصفّى') || statusArabic.contains('صفر')) {
        where.add('ABS(balance) < 1e-9');
      }
    }

    if (q.isNotEmpty) {
      final or = <String>[
        'LOWER(name) LIKE ?',
        "LOWER(IFNULL(phone, '')) LIKE ?",
        "LOWER(IFNULL(email, '')) LIKE ?",
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
        or.add("IFNULL(phone, '') LIKE ?");
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
      // دعم بحث "الكود/المعرف" كما يظهر في شاشة جهات الاتصال.
      // - يطابق: 12 أو 000012 أو #000012
      if (qDigits.isNotEmpty) {
        or.add("CAST(id AS TEXT) LIKE ?");
        args.add('%$qDigits%');
        or.add("printf('%06d', id) LIKE ?");
        args.add('%$qDigits%');
      }
      where.add('(${or.join(' OR ')})');
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final orderBy = switch (sortKey) {
      'balance_desc' => 'balance DESC, name COLLATE NOCASE ASC',
      'date_desc' => 'createdAt DESC, name COLLATE NOCASE ASC',
      _ => 'name COLLATE NOCASE ASC',
    };

    return db.rawQuery('''
      SELECT
        id, name, phone, email, address, notes, balance, loyaltyPoints, createdAt, updatedAt
      FROM customers
      $whereSql
      ORDER BY $orderBy
      LIMIT ? OFFSET ?
    ''', [...args, limit, offset]);
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
    final now = DateTime.now().toIso8601String();
    late final int id;
    await db.transaction((txn) async {
      id = await txn.insert('customers', {
        'name': name.trim(),
        'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
        'email': email?.trim().isEmpty == true ? null : email?.trim(),
        'address': address?.trim().isEmpty == true ? null : address?.trim(),
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
        'balance': 0,
        'createdAt': now,
        'updatedAt': now,
      });
      await _replaceCustomerExtraPhones(txn, id, extras);
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
    await db.transaction((txn) async {
      await txn.update(
        'customers',
        {
          'name': name.trim(),
          'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
          'email': email?.trim().isEmpty == true ? null : email?.trim(),
          'address': address?.trim().isEmpty == true ? null : address?.trim(),
          'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _replaceCustomerExtraPhones(txn, id, extras);
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
