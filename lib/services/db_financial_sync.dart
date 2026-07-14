part of 'database_helper.dart';

extension DbFinancialSync on DatabaseHelper {
  /// إضافة أعمدة المزامنة الأساسية للجداول المالية (المرحلة 5.5).
  Future<void> ensureFinancialGlobalIdSchema(Database db) async {
    final tables = [
      'installment_plans',
      'installments',
      'customer_debt_payments',
      'supplier_bills',
      'supplier_payouts'
    ];
    for (final table in tables) {
      try {
        if (!await _tableHasColumn(db, table, 'global_id')) {
          await db.execute('ALTER TABLE $table ADD COLUMN global_id TEXT');
          await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_${table}_global_id ON $table(global_id)');
        }
        if (!await _tableHasColumn(db, table, 'updatedAt')) {
          await db.execute('ALTER TABLE $table ADD COLUMN updatedAt TEXT');
        }
      } catch (e, st) {
        AppLogger.error('DBSync', 'فشل ترحيل الجدول $table', e, st);
      }
    }

    // إضافة معرفات الربط السحابي (Foreign Global IDs)
    Future<void> addCol(String table, String col) async {
      try {
        if (!await _tableHasColumn(db, table, col)) {
          await db.execute('ALTER TABLE $table ADD COLUMN $col TEXT');
        }
      } catch (e, st) {
        AppLogger.error('DBSync', 'فشل إضافة عمود $table.$col', e, st);
      }
    }

    await addCol('installments', 'plan_global_id');
    await addCol('installment_plans', 'customer_global_id');
    await addCol('installment_plans', 'invoice_global_id');
    await addCol('customer_debt_payments', 'customer_global_id');
    await addCol('supplier_bills', 'supplier_global_id');
    await addCol('supplier_payouts', 'supplier_global_id');
  }

  /// إضافة أعمدة المزامنة الأساسية للفواتير.
  Future<void> ensureInvoicesGlobalIdSchema(Database db) async {
    try {
      final pragma = await db.rawQuery('PRAGMA table_info(invoices)');
      final cols = pragma.map((r) => r['name'] as String).toList();
      if (!cols.contains('global_id')) {
        await db.execute('ALTER TABLE invoices ADD COLUMN global_id TEXT');
      }
      if (!cols.contains('updatedAt')) {
        await db.execute('ALTER TABLE invoices ADD COLUMN updatedAt TEXT');
      }
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_invoices_global_id ON invoices(global_id)',
      );

      // توليد معرفات للفواتير القديمة (إن وجدت)
      final rows = await db.query(
        'invoices',
        columns: ['id'],
        where: "global_id IS NULL OR TRIM(global_id) = ''",
      );
      if (rows.isNotEmpty) {
        await db.transaction((txn) async {
          final now = DateTime.now().toUtc().toIso8601String();
          for (final row in rows) {
            final uuid = const Uuid().v4();
            await txn.update(
              'invoices',
              {'global_id': uuid, 'updatedAt': now},
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          }
        });
      }

      final pragmaItems = await db.rawQuery('PRAGMA table_info(invoice_items)');
      final colsItems = pragmaItems.map((r) => r['name'] as String).toList();
      if (!colsItems.contains('global_id')) {
        await db.execute('ALTER TABLE invoice_items ADD COLUMN global_id TEXT');
      }
      if (!colsItems.contains('invoice_global_id')) {
        await db.execute('ALTER TABLE invoice_items ADD COLUMN invoice_global_id TEXT');
      }
      if (!colsItems.contains('product_global_id')) {
        await db.execute('ALTER TABLE invoice_items ADD COLUMN product_global_id TEXT');
      }
      if (!colsItems.contains('updatedAt')) {
        await db.execute('ALTER TABLE invoice_items ADD COLUMN updatedAt TEXT');
      }
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_invoice_items_global_id ON invoice_items(global_id)',
      );

      // توليد معرفات للعناصر القديمة.
      final itemRows = await db.query(
        'invoice_items',
        columns: ['id'],
        where: "global_id IS NULL OR TRIM(global_id) = ''",
      );
      if (itemRows.isNotEmpty) {
        await db.transaction((txn) async {
          final now = DateTime.now().toUtc().toIso8601String();
          for (final row in itemRows) {
            final uuid = const Uuid().v4();
            await txn.update(
              'invoice_items',
              {'global_id': uuid, 'updatedAt': now},
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          }
        });
      }

      // ربط العناصر القديمة بمعرّفات الفاتورة/الصنف السحابية.
      await db.execute('''
        UPDATE invoice_items
        SET invoice_global_id = (
          SELECT i.global_id FROM invoices i WHERE i.id = invoice_items.invoiceId
        )
        WHERE (invoice_global_id IS NULL OR TRIM(invoice_global_id) = '')
          AND invoiceId IS NOT NULL
      ''');
      await db.execute('''
        UPDATE invoice_items
        SET product_global_id = (
          SELECT p.global_id FROM products p WHERE p.id = invoice_items.productId
        )
        WHERE (product_global_id IS NULL OR TRIM(product_global_id) = '')
          AND productId IS NOT NULL
      ''');
    } catch (e, st) {
      AppLogger.error('DBSync', 'فشل ترحيل جدول الفواتير', e, st);
    }
  }
}
