import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../services/app_settings_repository.dart';
import '../../../services/database_helper.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/customer_validation.dart';
import '../models/oil_change_whatsapp_notify_outcome.dart';
import '../utils/whatsapp_failure_reason_ar.dart';
import 'oil_change_whatsapp_gateway_service.dart';
import 'oil_change_whatsapp_messages_repository.dart';

/// رسالة بطاقة لم تصل للزبون — محفوظة محلياً لإعادة الإرسال بعد عودة الإنترنت.
class OilChangeOutboxEntry {
  const OilChangeOutboxEntry({
    required this.id,
    required this.orderId,
    required this.customerPhone,
    required this.customerName,
    required this.createdAt,
    this.shopName = '',
    this.detailsBlock = '',
    this.messageText = '',
    this.employeeName = '',
    this.templateParams = const {},
    this.reason = '',
    this.attempts = 0,
    this.lastTriedAt,
    this.attemptId = '',
    this.nextAttemptAt,
  });

  factory OilChangeOutboxEntry.fromMap(Map<String, dynamic> map) {
    Map<String, String> params = const {};
    final raw = (map['templateParams'] ?? '').toString();
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          params = decoded.map(
            (k, v) => MapEntry(k.toString(), (v ?? '').toString()),
          );
        }
      } catch (_) {
        params = const {};
      }
    }
    final lastTried = (map['lastTriedAt'] ?? '').toString();
    final nextAt = (map['nextAttemptAt'] ?? '').toString();

    return OilChangeOutboxEntry(
      id: (map['id'] as num?)?.toInt() ?? 0,
      orderId: (map['orderId'] as num?)?.toInt() ?? 0,
      customerPhone: (map['customerPhone'] ?? '').toString(),
      customerName: (map['customerName'] ?? '').toString(),
      createdAt: DateTime.tryParse((map['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      shopName: (map['shopName'] ?? '').toString(),
      detailsBlock: (map['detailsBlock'] ?? '').toString(),
      messageText: (map['messageText'] ?? '').toString(),
      employeeName: (map['employeeName'] ?? '').toString(),
      templateParams: params,
      reason: (map['reason'] ?? '').toString(),
      attempts: (map['attempts'] as num?)?.toInt() ?? 0,
      lastTriedAt: lastTried.isEmpty ? null : DateTime.tryParse(lastTried),
      attemptId: (map['attemptId'] ?? '').toString(),
      nextAttemptAt: nextAt.isEmpty ? null : DateTime.tryParse(nextAt),
    );
  }

  final int id;
  final int orderId;
  final String customerPhone;
  final String customerName;
  final DateTime createdAt;
  final String shopName;
  final String detailsBlock;
  final String messageText;
  final String employeeName;
  final Map<String, String> templateParams;
  final String reason;
  final int attempts;
  final DateTime? lastTriedAt;
  final String attemptId;
  final DateTime? nextAttemptAt;

  String get reasonAr {
    return WhatsappFailureReasonAr.parse(
      reason,
      fromLocalOutbox: true,
    ).messageAr;
  }

  bool get isDueForAttempt {
    final next = nextAttemptAt;
    if (next == null) return true;
    return !next.isAfter(DateTime.now());
  }
}

/// طابور محلي للبطاقات التي فشل إرسالها (انقطاع إنترنت غالباً).
class OilChangeWhatsappOutbox {
  OilChangeWhatsappOutbox._();

  static final OilChangeWhatsappOutbox instance = OilChangeWhatsappOutbox._();

  static const _table = 'oil_change_wa_outbox';
  static const _uuid = Uuid();

  /// حد أقصى لمحاولات الإرسال الفعلية (تلقائي أو يدوي بعد فشل غامض).
  static const maxAutoRetryAttempts = 3;

  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// قفل لكل صف — يمنع Auto Retry والزر اليدوي من إرسال نفس الرسالة معاً.
  final Map<int, Future<OilChangeWhatsappNotifyReason>> _inFlight = {};

  Future<Database> get _db async => _dbHelper.database;

  Future<int> _tenantId() =>
      AppSettingsRepository.instance.getActiveTenantId();

  Future<void> _ensureTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenantId INTEGER NOT NULL,
        orderId INTEGER NOT NULL DEFAULT 0,
        customerPhone TEXT NOT NULL,
        customerName TEXT,
        shopName TEXT,
        detailsBlock TEXT,
        messageText TEXT,
        employeeName TEXT,
        templateParams TEXT,
        reason TEXT,
        attempts INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        lastTriedAt TEXT,
        sentAt TEXT,
        attemptId TEXT,
        nextAttemptAt TEXT
      )
    ''');
    await _ensureColumn(db, 'attemptId', 'TEXT');
    await _ensureColumn(db, 'nextAttemptAt', 'TEXT');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${_table}_tenant_pending '
      'ON $_table (tenantId, sentAt, createdAt DESC)',
    );
  }

  Future<void> _ensureColumn(Database db, String name, String type) async {
    final info = await db.rawQuery('PRAGMA table_info($_table)');
    final exists = info.any((c) => (c['name'] ?? '').toString() == name);
    if (!exists) {
      await db.execute('ALTER TABLE $_table ADD COLUMN $name $type');
    }
  }

  /// يُرجع E.164 فقط — الرقم غير القابل للتطبيع لا يدخل الطابور.
  String? _storePhoneOrNull(String raw) {
    return CustomerValidation.toE164IraqMobile(raw);
  }

  /// يحفظ محاولة فاشلة. بطاقة واحدة لا تتكرر — يُحدَّث المحتوى دون زيادة attempts.
  Future<void> enqueueFailure({
    required String customerPhone,
    required String customerName,
    required String shopName,
    required String detailsBlock,
    required String messageText,
    required Map<String, String> templateParams,
    required OilChangeWhatsappNotifyReason reason,
    int orderId = 0,
    String employeeName = '',
  }) async {
    final phone = _storePhoneOrNull(customerPhone);
    if (phone == null || phone.isEmpty) {
      AppLogger.warn(
        'oil_change_wa_outbox',
        'enqueue skipped — invalid phone (not E.164)',
      );
      return;
    }
    try {
      final db = await _db;
      await _ensureTable(db);
      final tenantId = await _tenantId();
      final now = DateTime.now().toIso8601String();
      final row = <String, Object?>{
        'tenantId': tenantId,
        'orderId': orderId,
        'customerPhone': phone,
        'customerName': customerName.trim(),
        'shopName': shopName.trim(),
        'detailsBlock': detailsBlock,
        'messageText': messageText,
        'employeeName': employeeName.trim(),
        'templateParams':
            templateParams.isEmpty ? '' : jsonEncode(templateParams),
        'reason': reason.name,
        'lastTriedAt': now,
        'nextAttemptAt': now,
      };

      if (orderId > 0) {
        final existing = await db.query(
          _table,
          columns: const ['id', 'attemptId'],
          where: 'tenantId = ? AND orderId = ? AND sentAt IS NULL',
          whereArgs: [tenantId, orderId],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final id = (existing.first['id'] as num).toInt();
          final existingAttempt =
              (existing.first['attemptId'] ?? '').toString().trim();
          await db.update(
            _table,
            {
              ...row,
              // لا تزد attempts هنا — attempts = محاولات إرسال فعلية فقط.
              if (existingAttempt.isEmpty) 'attemptId': _uuid.v4(),
            },
            where: 'tenantId = ? AND id = ?',
            whereArgs: [tenantId, id],
          );
          return;
        }
      }

      await db.insert(_table, {
        ...row,
        'attempts': 0,
        'attemptId': _uuid.v4(),
        'createdAt': now,
      });
    } catch (e) {
      AppLogger.warn('oil_change_wa_outbox', 'enqueue failed :: $e');
    }
  }

  Future<List<OilChangeOutboxEntry>> loadPending({
    int limit = 50,
    int? afterId,
    bool onlyDue = false,
  }) async {
    try {
      final db = await _db;
      await _ensureTable(db);
      final tenantId = await _tenantId();
      final now = DateTime.now().toIso8601String();
      // فلترة الاستحقاق في SQL — لا تحميل أحدث N ثم استبعادها في الذاكرة.
      final where = StringBuffer('tenantId = ? AND sentAt IS NULL');
      final args = <Object?>[tenantId];
      if (onlyDue) {
        where.write(
          ' AND (nextAttemptAt IS NULL OR nextAttemptAt = \'\' '
          'OR nextAttemptAt <= ?)',
        );
        args.add(now);
      }
      if (afterId != null) {
        where.write(' AND id < ?');
        args.add(afterId);
      }
      final rows = await db.query(
        _table,
        where: where.toString(),
        whereArgs: args,
        orderBy: onlyDue
            ? 'CASE WHEN nextAttemptAt IS NULL OR nextAttemptAt = \'\' '
                'THEN createdAt ELSE nextAttemptAt END ASC, id ASC'
            : 'id DESC',
        limit: limit,
      );
      return rows.map(OilChangeOutboxEntry.fromMap).toList();
    } catch (e) {
      AppLogger.warn('oil_change_wa_outbox', 'load failed :: $e');
      rethrow;
    }
  }

  Future<int> pendingCount() async {
    try {
      final db = await _db;
      await _ensureTable(db);
      final tenantId = await _tenantId();
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM $_table '
        'WHERE tenantId = ? AND sentAt IS NULL',
        [tenantId],
      );
      return (rows.first['c'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<int> totalNotSentCount() async {
    final local = await pendingCount();
    final cloud =
        await OilChangeWhatsappMessagesRepository.instance.countFailed();
    return local + cloud;
  }

  /// يعيد إرسال بطاقة من الطابور — بقفل صف + attemptId دائم في SQLite.
  Future<OilChangeWhatsappNotifyReason> retry(
    OilChangeOutboxEntry entry, {
    bool forceNewAttempt = false,
  }) {
    final existing = _inFlight[entry.id];
    if (existing != null) return existing;

    final future = _retryLocked(entry, forceNewAttempt: forceNewAttempt);
    _inFlight[entry.id] = future;
    return future.whenComplete(() {
      _inFlight.remove(entry.id);
    });
  }

  Future<OilChangeWhatsappNotifyReason> _retryLocked(
    OilChangeOutboxEntry entry, {
    required bool forceNewAttempt,
  }) async {
    final gateway = OilChangeWhatsappGatewayService.instance;
    final attemptId = await _resolvePersistentAttemptId(
      entry,
      forceNew: forceNewAttempt,
    );
    final phone = _storePhoneOrNull(entry.customerPhone);
    if (phone == null) {
      await _markAttempt(
        entry.id,
        OilChangeWhatsappNotifyReason.invalidPhone,
        newAttemptId: _uuid.v4(),
        nextAttemptAt: DateTime.now().add(const Duration(days: 365)),
      );
      return OilChangeWhatsappNotifyReason.invalidPhone;
    }

    WhatsappGatewaySendResult result;
    if (entry.templateParams.isNotEmpty || entry.detailsBlock.isNotEmpty) {
      result = await gateway.sendOilChangeCard(
        customerPhone: phone,
        customerName: entry.customerName,
        shopName: entry.shopName,
        detailsBlock: entry.detailsBlock,
        templateParams: entry.templateParams,
        orderId: entry.orderId > 0 ? entry.orderId : null,
        employeeName: entry.employeeName,
        resend: true,
        attemptId: attemptId,
      );
    } else {
      result = await gateway.sendText(
        customerPhone: phone,
        messageText: entry.messageText,
        orderId: entry.orderId > 0 ? entry.orderId : null,
        employeeName: entry.employeeName,
        resend: true,
        attemptId: attemptId,
      );
    }

    if (result.ok) {
      // لا تمسح attemptId قبل نجاح markSent — وإلا إعادة التشغيل قد تكرّر الإرسال.
      final marked = await markSent(entry.id);
      if (marked) {
        await _clearAttemptId(entry.id);
      }
      return OilChangeWhatsappNotifyReason.sent;
    }

    final reason = _reasonFor(result);
    final detail = '${result.reason} ${result.detail}'.toLowerCase();
    final keepSameKey = reason == OilChangeWhatsappNotifyReason.timeout ||
        reason == OilChangeWhatsappNotifyReason.noInternet ||
        detail.contains('previous_attempt') ||
        detail.contains('wallet_duplicate');
    // فشل مؤكد فقط → مفتاح جديد؛ Timeout / محاولة سابقة معلّقة → نفس المفتاح.
    await _markAttempt(
      entry.id,
      reason,
      newAttemptId: keepSameKey ? null : _uuid.v4(),
      nextAttemptAt: detail.contains('previous_attempt') ||
              detail.contains('wallet_duplicate')
          ? DateTime.now().add(const Duration(hours: 6))
          : _nextAttemptFor(reason),
    );
    return reason;
  }

  Future<String> _resolvePersistentAttemptId(
    OilChangeOutboxEntry entry, {
    required bool forceNew,
  }) async {
    final db = await _db;
    await _ensureTable(db);
    final tenantId = await _tenantId();
    final rows = await db.query(
      _table,
      columns: const ['attemptId'],
      where: 'tenantId = ? AND id = ?',
      whereArgs: [tenantId, entry.id],
      limit: 1,
    );
    final stored = rows.isEmpty
        ? ''
        : (rows.first['attemptId'] ?? '').toString().trim();
    if (!forceNew && stored.isNotEmpty) return stored;

    final created = (forceNew || stored.isEmpty) ? _uuid.v4() : stored;
    await db.update(
      _table,
      {'attemptId': created},
      where: 'tenantId = ? AND id = ?',
      whereArgs: [tenantId, entry.id],
    );
    return created;
  }

  Future<bool> markSent(int id) async {
    try {
      final db = await _db;
      await _ensureTable(db);
      final tenantId = await _tenantId();
      final n = await db.update(
        _table,
        {'sentAt': DateTime.now().toIso8601String()},
        where: 'tenantId = ? AND id = ?',
        whereArgs: [tenantId, id],
      );
      return n > 0;
    } catch (e) {
      AppLogger.warn('oil_change_wa_outbox', 'mark sent failed :: $e');
      return false;
    }
  }

  Future<void> _clearAttemptId(int id) async {
    try {
      final db = await _db;
      final tenantId = await _tenantId();
      await db.update(
        _table,
        {'attemptId': null},
        where: 'tenantId = ? AND id = ?',
        whereArgs: [tenantId, id],
      );
    } catch (e) {
      AppLogger.warn('oil_change_wa_outbox', 'clear attemptId failed :: $e');
    }
  }

  Future<void> discard(int id) async {
    try {
      final db = await _db;
      await _ensureTable(db);
      final tenantId = await _tenantId();
      await db.delete(
        _table,
        where: 'tenantId = ? AND id = ?',
        whereArgs: [tenantId, id],
      );
    } catch (e) {
      AppLogger.warn('oil_change_wa_outbox', 'discard failed :: $e');
    }
  }

  /// أسباب يُعاد إرسالها تلقائياً عند عودة الشبكة فقط.
  static bool isAutoRetryableReason(String reason) {
    switch (reason.trim()) {
      case 'noInternet':
      case 'timeout':
      case 'rateLimited':
        return true;
      default:
        return false;
    }
  }

  Future<void> updatePhoneForOrder({
    required int orderId,
    required String newPhone,
  }) async {
    if (orderId <= 0) return;
    final phone = _storePhoneOrNull(newPhone);
    if (phone == null || phone.isEmpty) return;
    try {
      final db = await _db;
      await _ensureTable(db);
      final tenantId = await _tenantId();
      // رقم جديد = عملية إرسال جديدة بمفتاح جديد.
      await db.update(
        _table,
        {
          'customerPhone': phone,
          'reason': 'noInternet',
          'lastTriedAt': DateTime.now().toIso8601String(),
          'nextAttemptAt': DateTime.now().toIso8601String(),
          'attemptId': _uuid.v4(),
        },
        where: 'tenantId = ? AND orderId = ? AND sentAt IS NULL',
        whereArgs: [tenantId, orderId],
      );
    } catch (e) {
      AppLogger.warn('oil_change_wa_outbox', 'updatePhoneForOrder failed :: $e');
    }
  }

  Future<void> discardPendingForOrder(int orderId) async {
    if (orderId <= 0) return;
    try {
      final db = await _db;
      await _ensureTable(db);
      final tenantId = await _tenantId();
      await db.delete(
        _table,
        where: 'tenantId = ? AND orderId = ? AND sentAt IS NULL',
        whereArgs: [tenantId, orderId],
      );
    } catch (e) {
      AppLogger.warn(
        'oil_change_wa_outbox',
        'discardPendingForOrder failed :: $e',
      );
    }
  }

  DateTime _nextAttemptFor(OilChangeWhatsappNotifyReason reason) {
    final now = DateTime.now();
    switch (reason) {
      case OilChangeWhatsappNotifyReason.rateLimited:
        return now.add(const Duration(minutes: 2));
      case OilChangeWhatsappNotifyReason.timeout:
        return now.add(const Duration(seconds: 45));
      case OilChangeWhatsappNotifyReason.noInternet:
        return now.add(const Duration(seconds: 20));
      case OilChangeWhatsappNotifyReason.unknown:
        // غالباً previous_attempt_pending — امنع Auto Retry السريع.
        return now.add(const Duration(hours: 6));
      default:
        return now.add(const Duration(minutes: 5));
    }
  }

  Future<void> _markAttempt(
    int id,
    OilChangeWhatsappNotifyReason reason, {
    String? newAttemptId,
    DateTime? nextAttemptAt,
  }) async {
    try {
      final db = await _db;
      final tenantId = await _tenantId();
      final lastTried = DateTime.now().toIso8601String();
      final nextAt =
          (nextAttemptAt ?? DateTime.now()).toIso8601String();
      if (newAttemptId != null) {
        await db.rawUpdate(
          'UPDATE $_table SET attempts = attempts + 1, lastTriedAt = ?, '
          'reason = ?, nextAttemptAt = ?, attemptId = ? '
          'WHERE tenantId = ? AND id = ?',
          [lastTried, reason.name, nextAt, newAttemptId, tenantId, id],
        );
      } else {
        await db.rawUpdate(
          'UPDATE $_table SET attempts = attempts + 1, lastTriedAt = ?, '
          'reason = ?, nextAttemptAt = ? WHERE tenantId = ? AND id = ?',
          [lastTried, reason.name, nextAt, tenantId, id],
        );
      }
    } catch (e) {
      AppLogger.warn('oil_change_wa_outbox', 'attempt update failed :: $e');
    }
  }

  OilChangeWhatsappNotifyReason _reasonFor(WhatsappGatewaySendResult result) {
    final r = '${result.reason} ${result.detail}'.toLowerCase();
    if (r.contains('invalid_phone')) {
      return OilChangeWhatsappNotifyReason.invalidPhone;
    }
    // خصم سابق بنفس المفتاح دون نتيجة واضحة — لا تُعد تلقائياً (ليست شبكة).
    if (r.contains('previous_attempt') || r.contains('wallet_duplicate')) {
      return OilChangeWhatsappNotifyReason.unknown;
    }
    if (r.contains('timeout') ||
        r.contains('gateway_unreachable') ||
        r.contains('invoke_null')) {
      return OilChangeWhatsappNotifyReason.timeout;
    }
    if (r.contains('disconnect') || r.contains('not_connected')) {
      return OilChangeWhatsappNotifyReason.whatsappDisconnected;
    }
    if (r.contains('rate')) return OilChangeWhatsappNotifyReason.rateLimited;
    if (r.contains('not_ready') || r.contains('preparing')) {
      return OilChangeWhatsappNotifyReason.skippedNotConfigured;
    }
    return OilChangeWhatsappNotifyReason.unknown;
  }
}
