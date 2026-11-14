import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_logger.dart';
import 'change_capture.dart';
import 'sync_safety.dart';

/// الطرف الآخر للمرحلة 4: دالتا الخادم `rpc_push_changes` و`rpc_pull_changes`.
abstract class DeltaBackend {
  Future<Map<String, dynamic>> push({
    required String deviceId,
    required int generation,
    required List<Map<String, dynamic>> changes,
  });

  Future<Map<String, dynamic>> pull({
    required String deviceId,
    required int afterSeq,
    required int generation,
    required int limit,
  });
}

class SupabaseDeltaBackend implements DeltaBackend {
  Map<String, dynamic> _map(dynamic res) =>
      res is Map ? Map<String, dynamic>.from(res) : {'ok': false};

  @override
  Future<Map<String, dynamic>> push({
    required String deviceId,
    required int generation,
    required List<Map<String, dynamic>> changes,
  }) async =>
      _map(await Supabase.instance.client.rpc('rpc_push_changes', params: {
        'p_device_id': deviceId,
        'p_generation': generation,
        'p_changes': changes,
      }));

  @override
  Future<Map<String, dynamic>> pull({
    required String deviceId,
    required int afterSeq,
    required int generation,
    required int limit,
  }) async =>
      _map(await Supabase.instance.client.rpc('rpc_pull_changes', params: {
        'p_device_id': deviceId,
        'p_after_seq': afterSeq,
        'p_generation': generation,
        'p_limit': limit,
      }));
}

/// ما حدث في دورة واحدة، للسجل والاختبارات.
class DeltaCycleResult {
  int pushed = 0;
  int received = 0;
  int rejected = 0;
  bool snapshotRequired = false;
  String? stoppedBy;

  /// المرحلة 5: الخادم جعل التعديلات الطريق الأساسي لهذا الحساب.
  bool primary = false;

  /// ما بقي في سجل الجهاز بعد الإرسال.
  int leftInOutbox = -1;

  /// الدورة أوصلت كل شيء في الاتجاهين، فالنسخة الكاملة غير لازمة الآن.
  bool get coversSnapshot =>
      primary && stoppedBy == null && !snapshotRequired && leftInOutbox == 0;

  @override
  String toString() =>
      'pushed=$pushed received=$received rejected=$rejected '
      'snapshot=$snapshotRequired primary=$primary left=$leftInOutbox'
      '${stoppedBy == null ? '' : ' stop=$stoppedBy'}';
}

/// المرحلة 4 على الجهاز: يرسل ما في سجل التعديلات ويستلم ما بعد مؤشره.
///
/// * النسخة الكاملة لا تتغير ولا تتوقف (إرسال مزدوج)، فأي خلل هنا لا يضيّع
///   شيئاً: النسخة تحمل كل البيانات كما اليوم.
/// * مفتاح عدم التكرار لكل تعديل `<الجهاز>:<رقم السجل>`: إعادة الإرسال بعد
///   انقطاع لا تُدخل نسخة ثانية. سطر تعدّل بعد قراءته يأخذ رقماً جديداً فيُرسل
///   مرة أخرى.
/// * التعديلات الواردة تُطبَّق ومؤشر الاستلام يُكتب في معاملة واحدة، فلا يُطبَّق
///   تعديل مرتين ولا يُتجاوز.
/// * تعديلات الجهاز نفسه تُتخطى عند الاستلام، والمؤشر يتقدم فوقها.
/// * الخادم يرفض الحساب غير المشغّل بـ 'disabled'، فيهدأ الجهاز 30 دقيقة.
class DeltaSyncService {
  DeltaSyncService._();
  static final DeltaSyncService instance = DeltaSyncService._();

  DeltaBackend backend = SupabaseDeltaBackend();

  /// مسارات قاعدة الجهاز ومعرّفه وتطبيق التعديلات، تُربط من [CloudSyncService].
  late Future<Database> Function() database;
  late Future<String> Function() deviceId;
  late Future<void> Function(
    List<CapturedChange> changes, {
    ({int lastSeq, int generation})? cursor,
  }) apply;

  /// يأخذ النسخة الكاملة من جديد (استرجاع أو جهاز غاب طويلاً).
  Future<void> Function()? onSnapshotRequired;

  static const pushBatch = 200;
  static const pullPage = 500;
  static const disabledBackoff = Duration(minutes: 30);

  DateTime? _disabledUntil;
  Future<DeltaCycleResult>? _running;

  bool get active => SyncSafety.changeCapture && SyncSafety.deltaSync;

  /// الخادم شغّل الحساب لاحقاً: لا انتظار.
  void resetBackoff() => _disabledUntil = null;

  /// دورة واحدة: إرسال ثم استلام. دورتان متزامنتان تصيران دورة واحدة.
  Future<DeltaCycleResult> runCycle() {
    final r = DeltaCycleResult();
    if (!active) return Future.value(r..stoppedBy = 'off');
    final until = _disabledUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      return Future.value(r..stoppedBy = 'disabled');
    }
    return _running ??= _cycle(r).whenComplete(() => _running = null);
  }

  Future<DeltaCycleResult> _cycle(DeltaCycleResult r) async {
    try {
      final db = await database();
      final me = await deviceId();
      await ChangeCapture.ensureLateTables(db);
      await _push(db, me, r);
      r.leftInOutbox = await ChangeCapture.pendingCount(db);
      if (r.stoppedBy == null || r.stoppedBy == 'generation_mismatch') {
        r.stoppedBy = null;
        await _pull(db, me, r);
      }
    } catch (e, st) {
      r.stoppedBy = 'error';
      AppLogger.error('DeltaSync', 'cycle failed', e, st);
    }
    return r;
  }

  int? _rejectedOutboxId(Map<String, dynamic> res, String me) {
    if (res['reason'] != 'bad_change') return null;
    final key = (res['key'] ?? '').toString();
    if (!key.startsWith('$me:')) return null;
    return int.tryParse(key.substring(me.length + 1));
  }

  bool _handleRefusal(Map<String, dynamic> res, DeltaCycleResult r) {
    final reason = (res['reason'] ?? 'error').toString();
    r.stoppedBy = reason;
    if (reason == 'disabled') {
      _disabledUntil = DateTime.now().add(disabledBackoff);
    }
    // رفض الإرسال لجيل قديم يُترك للاستلام: رده يحمل آخر رقم.
    return res['snapshot_required'] == true;
  }

  Future<void> _push(Database db, String me, DeltaCycleResult r) async {
    for (var round = 0; round < 50; round++) {
      final batch = await ChangeCapture.pending(db, limit: pushBatch);
      if (batch.isEmpty) return;
      final cursor = await ChangeCapture.readCursor(db);
      final res = await backend.push(
        deviceId: me,
        generation: cursor.generation,
        changes: [
          for (final c in batch)
            {
              'key': '$me:${c.outboxId}',
              'table': c.table,
              'row_key': c.key,
              'op': c.op,
              if (c.row != null) 'row': c.row,
            },
        ],
      );
      if (res['ok'] != true) {
        // تعديل يرفضه الخادم (جدول غير مسموح أو سطر كبير) لا يوقف البقية:
        // يخرج من السجل ويُسجَّل. النسخة الكاملة ما زالت تحمله في هذه المرحلة.
        final bad = _rejectedOutboxId(res, me);
        if (bad != null) {
          final c = batch.where((c) => c.outboxId == bad).firstOrNull;
          AppLogger.warn(
            'DeltaSync',
            'server refused ${c?.table}/${c?.key}: dropped from outbox',
          );
          await ChangeCapture.ack(db, [bad]);
          r.rejected++;
          continue;
        }
        if (_handleRefusal(res, r)) await _resync(db, res, r);
        return;
      }
      await ChangeCapture.ack(db, batch.map((c) => c.outboxId));
      r.pushed += batch.length;
    }
  }

  Future<void> _pull(Database db, String me, DeltaCycleResult r) async {
    for (var page = 0; page < 100; page++) {
      final cursor = await ChangeCapture.readCursor(db);
      final res = await backend.pull(
        deviceId: me,
        afterSeq: cursor.lastSeq,
        generation: cursor.generation,
        limit: pullPage,
      );
      if (res['ok'] != true) {
        if (_handleRefusal(res, r)) await _resync(db, res, r);
        return;
      }
      r.primary = res['primary'] == true;
      final rows = (res['changes'] as List?) ?? const [];
      if (rows.isEmpty) return;
      var maxSeq = cursor.lastSeq;
      final changes = <CapturedChange>[];
      for (final raw in rows) {
        final m = Map<String, dynamic>.from(raw as Map);
        final seq = (m['seq'] as num).toInt();
        if (seq > maxSeq) maxSeq = seq;
        if (m['device_id'] == me) continue;
        changes.add(CapturedChange(
          outboxId: seq,
          table: m['table'].toString(),
          key: m['row_key'].toString(),
          op: m['op'].toString(),
          row: m['row'] == null
              ? null
              : Map<String, dynamic>.from(m['row'] as Map),
        ));
      }
      await apply(
        changes,
        cursor: (lastSeq: maxSeq, generation: cursor.generation),
      );
      r.received += changes.length;
      if (res['has_more'] != true) return;
    }
  }

  /// الجيل تغيّر أو السجل لا يكفي: النسخة الكاملة، ثم المؤشر على الخادم.
  Future<void> _resync(
    Database db,
    Map<String, dynamic> res,
    DeltaCycleResult r,
  ) async {
    r.snapshotRequired = true;
    final gen = (res['generation'] as num?)?.toInt();
    if (gen == null) return;
    final hook = onSnapshotRequired;
    if (hook == null) return;
    await hook();
    final current = await ChangeCapture.readCursor(db);
    final serverSeq = (res['last_seq'] as num?)?.toInt();
    await ChangeCapture.writeCursor(
      db,
      lastSeq: serverSeq ?? current.lastSeq,
      generation: gen,
    );
  }
}
