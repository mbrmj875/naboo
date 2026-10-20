import 'dart:convert';

import '../../../services/app_settings_repository.dart';
import '../../../services/database_helper.dart';
import '../../../utils/app_logger.dart';

/// أسماء الفنيين المحفوظة لكل محل.
///
/// الاسم هنا هو نفسه المرسَل مع بطاقة واتساب (`employee_name`)، وعليه يُسنَد
/// تقييم العميل — لذلك الاختيار من قائمة ثابتة يمنع اختلاف الكتابة.
class OilChangeTechniciansStore {
  OilChangeTechniciansStore._();

  static final OilChangeTechniciansStore instance =
      OilChangeTechniciansStore._();

  static const _key = 'biz.oil.technicians';
  static const maxNames = 60;
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

  Future<List<String>> load() async {
    final stored = await _readStored();
    if (stored.isNotEmpty) return stored;

    final seeded = await _namesFromPastOrders();
    if (seeded.isEmpty) return const [];
    await _write(seeded);
    return seeded;
  }

  /// يُرجع القائمة بعد الإضافة؛ الاسم المكرر لا يُضاعف.
  Future<List<String>> add(String rawName) async {
    final name = normalize(rawName);
    if (name.isEmpty) return await load();

    final names = await load();
    final exists = names.any(
      (n) => n.toLowerCase() == name.toLowerCase(),
    );
    if (exists) return names;

    final next = [...names, name];
    if (next.length > maxNames) next.removeAt(0);
    next.sort((a, b) => a.compareTo(b));
    await _write(next);
    return next;
  }

  Future<List<String>> remove(String rawName) async {
    final name = normalize(rawName).toLowerCase();
    final names = await load();
    final next =
        names.where((n) => n.toLowerCase() != name).toList(growable: false);
    await _write(next);
    return next;
  }

  Future<List<String>> _readStored() async {
    try {
      final tenantId = await _settings.getActiveTenantId();
      final raw = await _settings.getForTenant(_key, tenantId: tenantId);
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((e) => normalize(e.toString()))
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      AppLogger.warn('oil_change_techs', 'read failed :: $e');
      return const [];
    }
  }

  Future<void> _write(List<String> names) async {
    try {
      final tenantId = await _settings.getActiveTenantId();
      await _settings.setForTenant(
        _key,
        jsonEncode(names),
        tenantId: tenantId,
      );
    } catch (e) {
      AppLogger.warn('oil_change_techs', 'write failed :: $e');
    }
  }

  /// أول تشغيل: تُلتقط الأسماء المكتوبة سابقاً في البطاقات حتى لا تضيع.
  Future<List<String>> _namesFromPastOrders() async {
    try {
      final tenantId = await _settings.getActiveTenantId();
      final db = await _dbHelper.database;
      final rows = await db.rawQuery(
        "SELECT DISTINCT TRIM(technicianName) AS name FROM service_orders "
        "WHERE tenantId = ? AND deletedAt IS NULL "
        "AND TRIM(COALESCE(technicianName, '')) <> '' "
        "ORDER BY name COLLATE NOCASE LIMIT ?",
        [tenantId, maxNames],
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
