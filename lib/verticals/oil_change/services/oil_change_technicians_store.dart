import 'dart:convert';

import '../../../services/app_settings_repository.dart';
import '../../../services/cloud_sync_service.dart';
import '../../../services/database_helper.dart';
import '../../../services/service_orders_sql_ops.dart';
import '../../../services/sync_entity_types.dart';
import '../../../services/sync_queue_service.dart';
import '../../../utils/app_logger.dart';
import 'package:sqflite/sqflite.dart';

/// فني في القائمة: من حساب موظف أو مضاف يدوياً.
class OilTechnician {
  const OilTechnician({
    required this.name,
    required this.fromAccount,
    required this.stopped,
  });

  final String name;

  /// له حساب موظف في التطبيق (اسمه يُعدَّل من الحساب).
  final bool fromAccount;

  /// موقوف: لا يظهر في البطاقة الجديدة، وبطاقاته وتقريره باقية.
  final bool stopped;
}

/// فنيو المحل (المرحلة 7 — الشريحة 1).
///
/// القائمة = حسابات الموظفين النشطة + الأسماء المضافة يدوياً، بلا تكرار.
/// الاسم هنا هو نفسه المرسَل مع بطاقة واتساب (`employee_name`)، وعليه يُسنَد
/// تقييم العميل — لذلك الاختيار من قائمة ثابتة يمنع اختلاف الكتابة.
///
/// التخزين: [_key] يبقى بصيغته القديمة (أسماء المضافين يدوياً النشطين فقط)
/// حتى تقرأه الأجهزة القديمة كما هو؛ الموقوفون في [_stoppedKey].
class OilChangeTechniciansStore {
  OilChangeTechniciansStore._();

  static final OilChangeTechniciansStore instance =
      OilChangeTechniciansStore._();

  static const _key = 'biz.oil.technicians';
  static const _stoppedKey = 'biz.oil.technicians_stopped';
  static const maxNameLength = 60;

  final AppSettingsRepository _settings = AppSettingsRepository.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// يوحّد المسافات ويقصّ الطول حتى يطابق الاسم ما يُرسل مع البطاقة.
  static String normalize(String raw) {
    final compact = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length > maxNameLength
        ? compact.substring(0, maxNameLength)
        : compact;
  }

  static String keyOf(String name) => normalize(name).toLowerCase();

  /// أسماء الفنيين النشطين، مرتبة. هذه ما تظهر عند اختيار الفني.
  Future<List<String>> load() async {
    final all = await loadAll();
    return [
      for (final t in all)
        if (!t.stopped) t.name,
    ];
  }

  /// كل الفنيين: النشطون والموقوفون.
  Future<List<OilTechnician>> loadAll() async {
    final tenantId = await _settings.getActiveTenantId();
    final manual = await _manualNames(tenantId);
    final stopped = await _readList(_stoppedKey, tenantId);
    final accounts = await _accountNames();

    final stoppedKeys = stopped.map(keyOf).toSet();
    final accountKeys = accounts.map(keyOf).toSet();
    final byKey = <String, OilTechnician>{};
    void put(String name) {
      final k = keyOf(name);
      if (k.isEmpty || byKey.containsKey(k)) return;
      byKey[k] = OilTechnician(
        name: normalize(name),
        fromAccount: accountKeys.contains(k),
        stopped: stoppedKeys.contains(k),
      );
    }

    // اسم الحساب أولاً: إن كُتب يدوياً بالاسم نفسه يبقى واحداً.
    accounts.forEach(put);
    manual.forEach(put);
    stopped.forEach(put);

    final list = byKey.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// يُرجع النشطين بعد الإضافة. الاسم الموجود لا يتكرر، والموقوف يعود.
  Future<List<String>> add(String rawName) async {
    final name = normalize(rawName);
    if (name.isEmpty) return await load();
    final k = keyOf(name);
    final all = await loadAll();
    final existing = all.where((t) => keyOf(t.name) == k).firstOrNull;
    if (existing != null) {
      if (existing.stopped) await restore(existing.name);
      return await load();
    }
    final tenantId = await _settings.getActiveTenantId();
    final manual = await _manualNames(tenantId);
    await _writeList(_key, [...manual, name]..sort(), tenantId);
    return await load();
  }

  /// إيقاف بدل الحذف.
  Future<List<String>> stop(String rawName) async {
    final name = normalize(rawName);
    final k = keyOf(name);
    if (k.isEmpty) return await load();
    final tenantId = await _settings.getActiveTenantId();
    final manual = await _manualNames(tenantId);
    final stopped = await _readList(_stoppedKey, tenantId);
    // يخرج من المفتاح القديم حتى لا تعرضه الأجهزة القديمة.
    await _writeList(
      _key,
      manual.where((n) => keyOf(n) != k).toList(),
      tenantId,
    );
    if (!stopped.any((n) => keyOf(n) == k)) {
      await _writeList(_stoppedKey, [...stopped, name], tenantId);
    }
    return await load();
  }

  Future<List<String>> restore(String rawName) async {
    final name = normalize(rawName);
    final k = keyOf(name);
    if (k.isEmpty) return await load();
    final tenantId = await _settings.getActiveTenantId();
    final stopped = await _readList(_stoppedKey, tenantId);
    await _writeList(
      _stoppedKey,
      stopped.where((n) => keyOf(n) != k).toList(),
      tenantId,
    );
    final accounts = await _accountNames();
    if (!accounts.any((n) => keyOf(n) == k)) {
      final manual = await _manualNames(tenantId);
      if (!manual.any((n) => keyOf(n) == k)) {
        await _writeList(_key, [...manual, name]..sort(), tenantId);
      }
    }
    return await load();
  }

  /// عدد بطاقات الفني على هذا الجهاز (للتنبيه قبل تعديل الاسم).
  Future<int> countCards(String rawName) async {
    final tenantId = await _settings.getActiveTenantId();
    final db = await _dbHelper.database;
    return (await _cardsOf(db, tenantId, keyOf(rawName))).length;
  }

  /// تعديل اسم فني مضاف يدوياً (الشريحة 2). يحدّث الاسم في القائمة وفي كل
  /// بطاقاته على الجهاز، وتُرسل البطاقات للمزامنة. إن كان الاسم الجديد
  /// لفني موجود تُجمع بطاقاتهما تحت اسم واحد. يُرجع عدد البطاقات المحدّثة.
  /// اسم حساب الموظف يُعدَّل من حسابه لا من هنا.
  Future<int> rename(String rawOld, String rawNew) async {
    final oldName = normalize(rawOld);
    final newName = normalize(rawNew);
    final oldKey = keyOf(oldName);
    if (oldKey.isEmpty || newName.isEmpty || oldName == newName) return 0;
    final accounts = await _accountNames();
    if (accounts.any((n) => keyOf(n) == oldKey)) {
      throw StateError('اسم حساب الموظف يُعدَّل من حسابه');
    }
    final newKey = keyOf(newName);
    final tenantId = await _settings.getActiveTenantId();

    final manual = await _manualNames(tenantId);
    final stopped = await _readList(_stoppedKey, tenantId);
    bool has(List<String> l, String k) => l.any((n) => keyOf(n) == k);
    final wasStopped = has(stopped, oldKey);
    final newIsAccount = has(accounts, newKey);
    final targetExists = newIsAccount || has(manual, newKey) || has(stopped, newKey);
    // الدمج مع فني نشط يجعل الناتج نشطاً.
    final resultStopped =
        wasStopped && (!targetExists || has(stopped, newKey));
    List<String> without(List<String> l) => [
          for (final n in l)
            if (keyOf(n) != oldKey && keyOf(n) != newKey) n,
        ];
    final nextManual = without(manual);
    final nextStopped = without(stopped);
    if (resultStopped) {
      nextStopped.add(newName);
    } else if (!newIsAccount) {
      nextManual.add(newName);
    }
    nextManual.sort();
    await _writeList(_key, nextManual, tenantId);
    await _writeList(_stoppedKey, nextStopped, tenantId);

    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    final updated = await db.transaction((txn) async {
      final rows = await _cardsOf(txn, tenantId, oldKey);
      for (final r in rows) {
        final id = (r['id'] as num).toInt();
        final values = {'technicianName': newName, 'updatedAt': now};
        await ServiceOrdersSqlOps.updateServiceOrderById(
          txn,
          tenantId,
          id: id,
          values: values,
        );
        final gid = (r['global_id'] ?? '').toString().trim();
        if (gid.isNotEmpty) {
          await SyncQueueService.instance.enqueueMutation(
            txn,
            entityType: SyncEntityTypes.serviceOrder,
            globalId: gid,
            operation: 'UPDATE',
            payload: {'id': gid, ...values},
          );
        }
      }
      return rows.length;
    });
    if (updated > 0) {
      try {
        CloudSyncService.instance.scheduleSyncSoon();
      } catch (_) {}
    }
    return updated;
  }

  Future<List<Map<String, Object?>>> _cardsOf(
    DatabaseExecutor db,
    int tenantId,
    String key,
  ) async {
    final rows = await db.query(
      'service_orders',
      columns: ['id', 'global_id', 'technicianName'],
      where: "tenantId = ? AND deletedAt IS NULL "
          "AND TRIM(COALESCE(technicianName, '')) <> ''",
      whereArgs: [tenantId],
    );
    return [
      for (final r in rows)
        if (keyOf((r['technicianName'] ?? '').toString()) == key) r,
    ];
  }

  /// الاسم القديم للدالة: صار إيقافاً، فلا يضيع تاريخ الفني.
  Future<List<String>> remove(String rawName) => stop(rawName);

  /// المضافون يدوياً. أول تشغيل (المفتاح لم يُكتب قط): تُلتقط الأسماء
  /// المكتوبة سابقاً في البطاقات حتى لا تضيع.
  Future<List<String>> _manualNames(int tenantId) async {
    final raw = await _rawFor(_key, tenantId);
    if (raw != null) return _decode(raw);
    final seeded = await _namesFromPastOrders(tenantId);
    await _writeList(_key, seeded, tenantId);
    return seeded;
  }

  Future<String?> _rawFor(String key, int tenantId) async {
    try {
      return await _settings.getForTenant(key, tenantId: tenantId);
    } catch (e) {
      AppLogger.warn('oil_change_techs', 'read failed :: $e');
      return null;
    }
  }

  Future<List<String>> _readList(String key, int tenantId) async {
    final raw = await _rawFor(key, tenantId);
    return raw == null ? const [] : _decode(raw);
  }

  static List<String> _decode(String raw) {
    if (raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((e) => normalize(e.toString()))
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeList(String key, List<String> names, int tenantId) async {
    try {
      await _settings.setForTenant(key, jsonEncode(names), tenantId: tenantId);
    } catch (e) {
      AppLogger.warn('oil_change_techs', 'write failed :: $e');
    }
  }

  /// حسابات الموظفين النشطة على هذا الجهاز.
  Future<List<String>> _accountNames() async {
    try {
      final db = await _dbHelper.database;
      final rows = await db.query(
        'users',
        columns: ['displayName', 'username'],
        where: 'IFNULL(isActive, 1) = 1',
      );
      return [
        for (final r in rows)
          normalize(
            ((r['displayName'] ?? '').toString().trim().isNotEmpty
                    ? r['displayName']
                    : r['username'] ?? '')
                .toString(),
          ),
      ].where((n) => n.isNotEmpty).toList(growable: false);
    } catch (e) {
      AppLogger.warn('oil_change_techs', 'accounts read failed :: $e');
      return const [];
    }
  }

  Future<List<String>> _namesFromPastOrders(int tenantId) async {
    try {
      final db = await _dbHelper.database;
      final rows = await db.rawQuery(
        "SELECT DISTINCT TRIM(technicianName) AS name FROM service_orders "
        "WHERE tenantId = ? AND deletedAt IS NULL "
        "AND TRIM(COALESCE(technicianName, '')) <> '' "
        "ORDER BY name COLLATE NOCASE",
        [tenantId],
      );
      return rows
          .map((r) => normalize((r['name'] ?? '').toString()))
          .where((n) => n.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      AppLogger.warn('oil_change_techs', 'seed from orders failed :: $e');
      return const [];
    }
  }
}
