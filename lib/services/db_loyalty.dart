part of 'database_helper.dart';

// ── نقاط الولاء ──────────────────────────────────────────────────────────

extension DbLoyalty on DatabaseHelper {
  Future<LoyaltySettingsData> _readLoyaltySettings(
    DatabaseExecutor ex,
  ) async {
    final settingsRows = await ex.query(
      'loyalty_settings',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    final loyaltyPayload = settingsRows.isEmpty
        ? null
        : settingsRows.first['payload'] as String?;
    return LoyaltySettingsData.mergeFromJsonString(loyaltyPayload);
  }

  Future<void> _applyLoyaltyForNewInvoice(
    Transaction txn, {
    required int invoiceId,
    required Invoice invoice,
    required double effectiveLoyaltyDiscount,
    required int effectiveLoyaltyRedeem,
    required LoyaltySettingsData settings,
  }) async {
    final cid = invoice.customerId;
    if (cid == null) return;

    final rows = await txn.query(
      'customers',
      columns: ['loyaltyPoints'],
      where: 'id = ?',
      whereArgs: [cid],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final balance = (rows.first['loyaltyPoints'] as num?)?.toInt() ?? 0;
    if (effectiveLoyaltyRedeem < 0 || effectiveLoyaltyRedeem > balance) {
      throw StateError('loyalty_insufficient_points');
    }
    if (effectiveLoyaltyRedeem > 0) {
      final expected = LoyaltyMath.discountFromPoints(
        effectiveLoyaltyRedeem,
        settings,
      );
      if ((expected - effectiveLoyaltyDiscount).abs() > 2) {
        throw StateError('loyalty_discount_mismatch');
      }
    }

    final earned = LoyaltyMath.computeEarnedPoints(
      s: settings,
      invoice: invoice,
    );
    await txn.update(
      'invoices',
      {'loyaltyPointsEarned': earned},
      where: 'id = ?',
      whereArgs: [invoiceId],
    );

    var running = balance;
    final now = DateTime.now().toIso8601String();
    final ledgerCols = await txn.rawQuery('PRAGMA table_info(loyalty_ledger)');
    final ledgerNames = ledgerCols
        .map((e) => (e['name'] as String?)?.toLowerCase() ?? '')
        .toSet();
    final hasPoints = ledgerNames.contains('points');
    final hasDeltaPoints = ledgerNames.contains('deltapoints');

    Map<String, Object?> buildLedgerRow({
      required int delta,
      required String kind,
      required int balanceAfter,
      required String note,
    }) {
      final m = <String, Object?>{
        'customerId': cid,
        'invoiceId': invoiceId,
        'kind': kind,
        'balanceAfter': balanceAfter,
        'note': note,
        'createdAt': now,
      };
      if (hasPoints) m['points'] = delta;
      if (hasDeltaPoints) m['deltaPoints'] = delta;
      return m;
    }

    if (effectiveLoyaltyRedeem > 0) {
      running -= effectiveLoyaltyRedeem;
      await txn.insert(
        'loyalty_ledger',
        buildLedgerRow(
          delta: -effectiveLoyaltyRedeem,
          kind: 'redeem',
          balanceAfter: running,
          note: 'استبدال نقاط — فاتورة #$invoiceId',
        ),
      );
    }
    if (earned > 0) {
      running += earned;
      await txn.insert(
        'loyalty_ledger',
        buildLedgerRow(
          delta: earned,
          kind: 'earn',
          balanceAfter: running,
          note: 'مكافأة شراء — فاتورة #$invoiceId',
        ),
      );
    }
    if (effectiveLoyaltyRedeem > 0 || earned > 0) {
      await txn.update(
        'customers',
        {'loyaltyPoints': running, 'updatedAt': now},
        where: 'id = ?',
        whereArgs: [cid],
      );
    }
  }

  /// سجل حركات نقاط الولاء (الأحدث أولاً).
  Future<List<Map<String, dynamic>>> getLoyaltyLedger({
    int? customerId,
    int limit = 500,
  }) async {
    final db = await database;
    if (customerId != null) {
      return db.query(
        'loyalty_ledger',
        where: 'customerId = ?',
        whereArgs: [customerId],
        orderBy: 'id DESC',
        limit: limit,
      );
    }
    return db.query('loyalty_ledger', orderBy: 'id DESC', limit: limit);
  }
}
