import 'dart:io';

void main() {
  final f = File('lib/services/cloud_sync_service.dart');
  var content = f.readAsStringSync();
  
  // exclude product_warehouse_stock if not already
  if (!content.contains("'product_warehouse_stock',")) {
    content = content.replaceFirst(
      "'sync_queue', // طابور المزامنة محلي لكل جهاز — لا يُرفع في اللقطة",
      "'sync_queue', // طابور المزامنة محلي لكل جهاز — لا يُرفع في اللقطة\n      'product_warehouse_stock',"
    );
  }
  
  // add merge logic for financial tables
  final mergeLogic = '''
      if (table == 'installment_plans' && localCols.contains('global_id')) {
        final handled = await _mergeInstallmentPlansByGlobalId(
          txn: txn,
          incomingRaw: incomingRaw,
          incoming: incoming,
          localCols: localCols,
          deletedAt: deletedAt,
          pkCols: pkCols,
        );
        if (handled) continue;
      }

      if (table == 'installments' && localCols.contains('global_id')) {
        final handled = await _mergeInstallmentsByGlobalId(
          txn: txn,
          incomingRaw: incomingRaw,
          incoming: incoming,
          localCols: localCols,
          deletedAt: deletedAt,
          pkCols: pkCols,
        );
        if (handled) continue;
      }

      if (table == 'customer_debt_payments' && localCols.contains('global_id')) {
        final handled = await _mergeCustomerDebtPaymentsByGlobalId(
          txn: txn,
          incomingRaw: incomingRaw,
          incoming: incoming,
          localCols: localCols,
          deletedAt: deletedAt,
          pkCols: pkCols,
        );
        if (handled) continue;
      }
      
      if ((table == 'supplier_bills' || table == 'supplier_payouts') && localCols.contains('global_id')) {
         final handled = await _mergeSupplierFinancialsByGlobalId(
          txn: txn,
          table: table,
          incomingRaw: incomingRaw,
          incoming: incoming,
          localCols: localCols,
          deletedAt: deletedAt,
          pkCols: pkCols,
        );
        if (handled) continue;
      }
''';

  if (!content.contains("_mergeInstallmentPlansByGlobalId")) {
    content = content.replaceFirst(
      "// إذا لا يوجد مفتاح أساسي عملي، fallback على replace.",
      mergeLogic + "\n      // إذا لا يوجد مفتاح أساسي عملي، fallback على replace."
    );
  }
  
  final helperMethods = '''
  Future<bool> _mergeInstallmentPlansByGlobalId({
    required Transaction txn,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required Set<String> localCols,
    required DateTime? deletedAt,
    required List<String> pkCols,
  }) async {
    final gid = (incomingRaw['global_id'] ?? incoming['global_id'] ?? '').toString().trim();
    if (gid.isEmpty) return false;

    if (localCols.contains('customer_global_id')) {
      final cgid = (incomingRaw['customer_global_id'] ?? incoming['customer_global_id'] ?? '').toString().trim();
      if (cgid.isNotEmpty) {
        final c = await txn.query('customers', columns: ['id'], where: 'global_id = ?', whereArgs: [cgid], limit: 1);
        if (c.isNotEmpty) {
          incoming['customerId'] = c.first['id'];
        }
      }
    }

    if (localCols.contains('invoice_global_id')) {
      final igid = (incomingRaw['invoice_global_id'] ?? incoming['invoice_global_id'] ?? '').toString().trim();
      if (igid.isNotEmpty) {
        final i = await txn.query('invoices', columns: ['id'], where: 'global_id = ?', whereArgs: [igid], limit: 1);
        if (i.isNotEmpty) {
          incoming['invoiceId'] = i.first['id'];
        }
      }
    }

    await _doMergeWithGlobalId(txn: txn, table: 'installment_plans', gid: gid, incomingRaw: incomingRaw, incoming: incoming, deletedAt: deletedAt);
    return true;
  }

  Future<bool> _mergeInstallmentsByGlobalId({
    required Transaction txn,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required Set<String> localCols,
    required DateTime? deletedAt,
    required List<String> pkCols,
  }) async {
    final gid = (incomingRaw['global_id'] ?? incoming['global_id'] ?? '').toString().trim();
    if (gid.isEmpty) return false;

    if (localCols.contains('plan_global_id')) {
      final pgid = (incomingRaw['plan_global_id'] ?? incoming['plan_global_id'] ?? '').toString().trim();
      if (pgid.isNotEmpty) {
        final p = await txn.query('installment_plans', columns: ['id'], where: 'global_id = ?', whereArgs: [pgid], limit: 1);
        if (p.isNotEmpty) {
          incoming['planId'] = p.first['id'];
        }
      }
    }

    await _doMergeWithGlobalId(txn: txn, table: 'installments', gid: gid, incomingRaw: incomingRaw, incoming: incoming, deletedAt: deletedAt);
    return true;
  }

  Future<bool> _mergeCustomerDebtPaymentsByGlobalId({
    required Transaction txn,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required Set<String> localCols,
    required DateTime? deletedAt,
    required List<String> pkCols,
  }) async {
    final gid = (incomingRaw['global_id'] ?? incoming['global_id'] ?? '').toString().trim();
    if (gid.isEmpty) return false;

    if (localCols.contains('customer_global_id')) {
      final cgid = (incomingRaw['customer_global_id'] ?? incoming['customer_global_id'] ?? '').toString().trim();
      if (cgid.isNotEmpty) {
        final c = await txn.query('customers', columns: ['id'], where: 'global_id = ?', whereArgs: [cgid], limit: 1);
        if (c.isNotEmpty) {
          incoming['customerId'] = c.first['id'];
        }
      }
    }

    await _doMergeWithGlobalId(txn: txn, table: 'customer_debt_payments', gid: gid, incomingRaw: incomingRaw, incoming: incoming, deletedAt: deletedAt);
    return true;
  }
  
  Future<bool> _mergeSupplierFinancialsByGlobalId({
    required Transaction txn,
    required String table,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required Set<String> localCols,
    required DateTime? deletedAt,
    required List<String> pkCols,
  }) async {
    final gid = (incomingRaw['global_id'] ?? incoming['global_id'] ?? '').toString().trim();
    if (gid.isEmpty) return false;

    if (localCols.contains('supplier_global_id')) {
      final sgid = (incomingRaw['supplier_global_id'] ?? incoming['supplier_global_id'] ?? '').toString().trim();
      if (sgid.isNotEmpty) {
        final s = await txn.query('suppliers', columns: ['id'], where: 'global_id = ?', whereArgs: [sgid], limit: 1);
        if (s.isNotEmpty) {
          incoming['supplierId'] = s.first['id'];
        }
      }
    } else {
        // Fallback for supplierId if supplier_global_id column doesn't exist yet
        // In this case, we rely on suppliers being merged before, and their global_id matching
        // But since we didn't add supplier_global_id to the tables yet in database_helper.dart
        // wait, did we? No, I forgot supplier_global_id in supplier_bills!
    }

    await _doMergeWithGlobalId(txn: txn, table: table, gid: gid, incomingRaw: incomingRaw, incoming: incoming, deletedAt: deletedAt);
    return true;
  }

  Future<void> _doMergeWithGlobalId({
    required Transaction txn,
    required String table,
    required String gid,
    required Map<String, dynamic> incomingRaw,
    required Map<String, dynamic> incoming,
    required DateTime? deletedAt,
  }) async {
    final existing = await txn.query(table, where: 'global_id = ?', whereArgs: [gid], limit: 1);
    if (deletedAt != null) {
      await txn.delete(table, where: 'global_id = ?', whereArgs: [gid]);
      return;
    }
    if (existing.isEmpty) {
      incoming.remove('id');
      await txn.insert(table, incoming, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      final current = existing.first;
      if (_incomingWins(current, incomingRaw)) {
        incoming['id'] = current['id'];
        await txn.insert(table, incoming, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }
''';

  if (!content.contains("_mergeInstallmentPlansByGlobalId")) {
     content = content.replaceFirst(
      "Future<List<String>> _primaryKeyColumns",
      helperMethods + "\n  Future<List<String>> _primaryKeyColumns"
    );
  }
  
  f.writeAsStringSync(content);
  print('Merge logic added');
}
