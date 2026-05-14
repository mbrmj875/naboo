import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../utils/app_logger.dart';
import 'database_helper.dart';
import 'license_service.dart';

/// نتيجة معالجة mutation واحدة على السيرفر.
/// يتطابق تماماً مع شكل العنصر داخل المصفوفة التي ترجعها الدالة الجديدة
/// `rpc_process_sync_queue` (Step 17):
///
/// ```json
/// { "mutation_id": "<uuid>", "status": "ok"|"fail", "error": null|"<text>" }
/// ```
@immutable
class SyncMutationResult {
  const SyncMutationResult({
    required this.mutationId,
    required this.ok,
    this.error,
  });

  final String mutationId;
  final bool ok;
  final String? error;

  static SyncMutationResult? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['mutation_id']?.toString();
    if (id == null || id.isEmpty) return null;
    final status = raw['status']?.toString().toLowerCase();
    final ok = status == 'ok';
    final err = raw['error'];
    return SyncMutationResult(
      mutationId: id,
      ok: ok,
      error: err?.toString(),
    );
  }
}

/// خطأ يدلّ على فشل الاتصال/RPC ككل قبل أن نحصل على نتائج فردية. عند هذا
/// النوع نُبقي كل الـ mutations في حالتها الحاليّة (تظلّ pending) — لا
/// نزيد retry_count حتى لا نُعاقب الباتش بسبب انقطاع شبكة عابر.
class SyncRpcTransportException implements Exception {
  const SyncRpcTransportException(this.cause);
  final Object cause;
  @override
  String toString() => 'SyncRpcTransportException: $cause';
}

/// توقيع الـ RPC القابل للحقن في الاختبارات.
///
/// عقد النجاح: يُرجع قائمة `SyncMutationResult` بترتيب أو بدون ترتيب — العميل
/// يطابقها بـ `mutationId`.
/// عقد الفشل: يرمي `SyncRpcTransportException` لأخطاء الشبكة/الترخيص.
typedef SyncRpcCall = Future<List<SyncMutationResult>> Function(
  List<Map<String, dynamic>> mutations,
);

class SyncQueueService {
  SyncQueueService._();
  static final SyncQueueService instance = SyncQueueService._();

  static const int _batchSize = 50;
  static const int _maxRetries = 5;

  Timer? _timer;
  bool _isProcessing = false;

  final _uuid = const Uuid();

  /// متاحة للاختبار: قاعدة بيانات بديلة (in-memory) بدل DatabaseHelper.
  @visibleForTesting
  Future<Database> Function()? databaseProviderForTesting;

  /// متاح للاختبار: استبدال الاتصال بـ Supabase RPC بمحاكاة.
  @visibleForTesting
  SyncRpcCall? rpcOverrideForTesting;

  /// متاح للاختبار: تجاوز فحص جلسة Supabase (كما لو كان المستخدم مسجّلاً).
  @visibleForTesting
  bool Function()? authCheckForTesting;

  /// متاح للاختبار: استبدال LicenseService.getDeviceId.
  @visibleForTesting
  Future<String> Function()? deviceIdProviderForTesting;

  void initialize() {
    _startTimer();
  }

  void dispose() {
    _timer?.cancel();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      processQueue();
    });
  }

  /// Adds a mutation to the queue inside the same transaction as the local DB update.
  Future<void> enqueueMutation(
    DatabaseExecutor txn, {
    required String entityType,
    required String globalId,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    final mutationId = _uuid.v4();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    payload['global_id'] = globalId;

    await txn.insert('sync_queue', {
      'mutation_id': mutationId,
      'entity_type': entityType,
      'operation': operation,
      'payload': jsonEncode(payload),
      'created_at': nowIso,
      'status': 'pending',
      'retry_count': 0,
    });

    scheduleProcessingSoon();
  }

  void scheduleProcessingSoon() {
    if (_isProcessing) return;
    Future.delayed(const Duration(seconds: 2), () {
      processQueue();
    });
  }

  Future<Database> _resolveDb() async {
    final override = databaseProviderForTesting;
    if (override != null) return override();
    return await DatabaseHelper().database;
  }

  bool _isSignedIn() {
    final override = authCheckForTesting;
    if (override != null) return override();
    return Supabase.instance.client.auth.currentUser != null;
  }

  Future<String> _getDeviceId() async {
    final override = deviceIdProviderForTesting;
    if (override != null) return override();
    return LicenseService.instance.getDeviceId();
  }

  Future<List<SyncMutationResult>> _callRpc(
    List<Map<String, dynamic>> payload,
  ) async {
    final override = rpcOverrideForTesting;
    if (override != null) {
      return override(payload);
    }
    try {
      final response = await Supabase.instance.client.rpc(
        'rpc_process_sync_queue',
        params: {'mutations_json': payload},
      );
      return _parseRpcResponse(response);
    } catch (e) {
      throw SyncRpcTransportException(e);
    }
  }

  /// تحويل ردّ Supabase إلى `List<SyncMutationResult>`.
  /// `client.rpc` يُرجع `dynamic`؛ نتوقّع `List` من `Map`. غير ذلك = استجابة
  /// سيئة → نعاملها كأنّها transport error حتى لا نُحدّث الصفوف بناءً على
  /// نتائج لا نفهمها.
  static List<SyncMutationResult> _parseRpcResponse(Object? response) {
    if (response is! List) {
      throw SyncRpcTransportException(
        FormatException('rpc_process_sync_queue returned non-list: $response'),
      );
    }
    final out = <SyncMutationResult>[];
    for (final item in response) {
      final parsed = SyncMutationResult.tryParse(item);
      if (parsed == null) {
        throw SyncRpcTransportException(
          FormatException('Malformed result entry: $item'),
        );
      }
      out.add(parsed);
    }
    return out;
  }

  Future<void> processQueue() async {
    if (_isProcessing) return;
    if (!_isSignedIn()) return;

    final db = await _resolveDb();

    _isProcessing = true;
    try {
      final candidates = await db.rawQuery(
        '''
        SELECT * FROM sync_queue
        WHERE status = 'pending'
           OR (status = 'failed' AND retry_count < ?)
        ORDER BY created_at ASC
        LIMIT ?
        ''',
        [_maxRetries, _batchSize * 4],
      );

      if (candidates.isEmpty) {
        return;
      }

      final nowUtc = DateTime.now().toUtc();
      final rows = <Map<String, dynamic>>[];
      for (final r in candidates) {
        final st = (r['status'] ?? '').toString();
        if (st == 'pending') {
          rows.add(r);
        } else if (st == 'failed') {
          final retryCount = (r['retry_count'] as num?)?.toInt() ?? 0;
          final backoffSeconds = min(30 * pow(2, retryCount), 300).toInt();
          final lastRaw = r['last_attempt_at'] as String?;
          if (lastRaw == null || lastRaw.isEmpty) {
            rows.add(r);
          } else {
            final lastAt = DateTime.tryParse(lastRaw)?.toUtc();
            if (lastAt != null &&
                nowUtc.difference(lastAt).inSeconds >= backoffSeconds) {
              rows.add(r);
            }
          }
        }
        if (rows.length >= _batchSize) break;
      }

      if (rows.isEmpty) {
        return;
      }

      final deviceId = await _getDeviceId();

      final payloadList = rows.map((r) {
        final payloadMap =
            jsonDecode(r['payload'] as String) as Map<String, dynamic>;
        payloadMap['_mutation_id'] = r['mutation_id'];
        payloadMap['_entity_type'] = r['entity_type'];
        payloadMap['_operation'] = r['operation'];
        payloadMap['_device_id'] = deviceId;
        return payloadMap;
      }).toList();

      List<SyncMutationResult> results;
      try {
        results = await _callRpc(payloadList);
      } on SyncRpcTransportException catch (e) {
        // فشل اتصال/خطأ عام — لا نُحدّث أيّ صف. التشغيلات الدورية ستعيد
        // المحاولة مع نفس الـ rows (تظلّ pending).
        if (kDebugMode) {
          AppLogger.error('SyncQueue', 'RPC transport error', e.cause);
        }
        return;
      }

      // فهرسة النتائج بـ mutation_id لمطابقتها مع الـ rows دون افتراض ترتيب.
      final resultsById = <String, SyncMutationResult>{
        for (final r in results) r.mutationId: r,
      };

      final nowIso = DateTime.now().toUtc().toIso8601String();

      await db.transaction((txn) async {
        for (final row in rows) {
          final mutationId = row['mutation_id'] as String;
          final res = resultsById[mutationId];

          if (res == null) {
            // السيرفر لم يُعطِ نتيجة لهذه الـ mutation. نعامله كفشل غير
            // مُحدَّد — لا نتجاهلها (وإلّا تبقى pending للأبد).
            await _markFailed(
              txn,
              mutationId: mutationId,
              currentRetry: (row['retry_count'] as num?)?.toInt() ?? 0,
              errorMessage:
                  'no_result_for_mutation: server did not return a status',
              nowIso: nowIso,
            );
            continue;
          }

          if (res.ok) {
            await txn.update(
              'sync_queue',
              {
                'status': 'synced',
                'synced_at': nowIso,
                'last_error': null,
                'last_attempt_at': null,
              },
              where: 'mutation_id = ?',
              whereArgs: [mutationId],
            );
          } else {
            await _markFailed(
              txn,
              mutationId: mutationId,
              currentRetry: (row['retry_count'] as num?)?.toInt() ?? 0,
              errorMessage: res.error ?? 'unknown_failure',
              nowIso: nowIso,
            );
          }
        }
      });
    } finally {
      _isProcessing = false;
      scheduleProcessingSoon();
    }
  }

  Future<void> _markFailed(
    DatabaseExecutor txn, {
    required String mutationId,
    required int currentRetry,
    required String errorMessage,
    required String nowIso,
  }) async {
    final newRetry = currentRetry + 1;
    final newStatus = newRetry >= _maxRetries ? 'dead' : 'failed';

    if (newStatus == 'dead' && kDebugMode) {
      AppLogger.warn(
        'SyncQueue',
        'DEAD mutation: $mutationId - $errorMessage',
      );
    }

    await txn.update(
      'sync_queue',
      {
        'status': newStatus,
        'retry_count': newRetry,
        'last_error': errorMessage,
        'last_attempt_at': nowIso,
      },
      where: 'mutation_id = ?',
      whereArgs: [mutationId],
    );
  }
}
