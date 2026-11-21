import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../utils/app_logger.dart';
import 'database_helper.dart';
import 'license_service.dart';
import 'supabase_config.dart';

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

  /// مفاتيح الطوابع الزمنية التي يفحصها حارس السيرفر `_parse_client_ts`.
  static const List<String> _timestampKeys = [
    'updatedAt',
    'updated_at',
    'createdAt',
    'created_at',
    'occurredAt',
    'occurred_at',
  ];

  /// حدّ إرسال آمن تحت عتبة السيرفر (5 دقائق).
  static const Duration _clientSkewCeiling = Duration(minutes: 4);

  /// مدة اعتبار انحراف الساعة المخزّن صالحاً.
  static const Duration _clockOffsetTtl = Duration(minutes: 15);

  Timer? _timer;
  bool _isProcessing = false;

  final _uuid = const Uuid();

  /// فرق (deviceUtc - serverUtc). موجب ⇒ ساعة الجهاز متقدمة.
  Duration? _deviceAheadOfServer;
  DateTime? _clockOffsetCapturedAt;

  /// متاح للاختبار: حقن وقت السيرفر بدل HTTP Date.
  @visibleForTesting
  Future<DateTime?> Function()? serverUtcProviderForTesting;

  /// يضبط أي طابع زمني في المستقبل (نسبًا إلى [referenceUtc]) إلى [referenceUtc].
  /// يعيد `true` إذا تغيّر الـ payload.
  @visibleForTesting
  static bool sanitizePayloadTimestamps(
    Map<String, dynamic> payload, {
    DateTime? referenceUtc,
    Duration skewCeiling = _clientSkewCeiling,
  }) {
    final reference = (referenceUtc ?? DateTime.now().toUtc()).toUtc();
    final maxAllowed = reference.add(skewCeiling);
    final clampIso = reference.toIso8601String();
    var changed = false;
    for (final key in _timestampKeys) {
      final raw = payload[key];
      if (raw == null) continue;
      final parsed = DateTime.tryParse(raw.toString())?.toUtc();
      if (parsed == null) continue;
      if (!parsed.isBefore(maxAllowed)) {
        payload[key] = clampIso;
        changed = true;
      }
    }
    return changed;
  }

  /// يفرض وقت السيرفر على كل مفاتيح الطوابع الموجودة (بعد clock_skew).
  @visibleForTesting
  static bool forceAlignPayloadTimestamps(
    Map<String, dynamic> payload,
    DateTime serverUtc,
  ) {
    final serverIso = serverUtc.toUtc().toIso8601String();
    var changed = false;
    for (final key in _timestampKeys) {
      if (!payload.containsKey(key) || payload[key] == null) continue;
      if (payload[key] != serverIso) {
        payload[key] = serverIso;
        changed = true;
      }
    }
    return changed;
  }

  /// يحوّل نص timestamptz من Postgres إلى DateTime UTC.
  @visibleForTesting
  static DateTime? tryParsePostgresTimestamptz(String rawIn) {
    var raw = rawIn.trim();
    if (raw.isEmpty) return null;

    if ((raw.startsWith('"') && raw.endsWith('"')) ||
        (raw.startsWith("'") && raw.endsWith("'"))) {
      raw = raw.substring(1, raw.length - 1).trim();
    }

    final direct = DateTime.tryParse(raw)?.toUtc();
    if (direct != null) return direct;

    // Postgres: `2026-07-14 09:15:22.123456+00` أو `+00:00` أو `+0000`
    if (RegExp(r'^\d{4}-\d{2}-\d{2} ').hasMatch(raw)) {
      raw = raw.replaceFirst(' ', 'T');
    }

    if (raw.endsWith(' UTC')) {
      raw = '${raw.substring(0, raw.length - 4)}Z';
    }

    if (RegExp(r'[+-]00$').hasMatch(raw)) {
      raw = '${raw.substring(0, raw.length - 3)}Z';
    }

    final compact = RegExp(r'([+-])(\d{2})(\d{2})$').firstMatch(raw);
    if (compact != null && !raw.contains(':', raw.length - 6)) {
      raw =
          '${raw.substring(0, compact.start)}${compact.group(1)}${compact.group(2)}:${compact.group(3)}';
    }

    return DateTime.tryParse(raw)?.toUtc();
  }

  /// يستخرج `server now` من رسالة `clock_skew_rejected` القادمة من Postgres.
  @visibleForTesting
  static DateTime? tryParseServerNowFromClockSkewError(String error) {
    final serverMatch = RegExp(
      r'server now=([^,\)]+)',
      caseSensitive: false,
    ).firstMatch(error);
    if (serverMatch != null) {
      final parsed = tryParsePostgresTimestamptz(serverMatch.group(1)!);
      if (parsed != null) return parsed;
    }

    // احتياطي: threshold = server now + 5min
    final thrMatch = RegExp(
      r'threshold=([^,\)]+)',
      caseSensitive: false,
    ).firstMatch(error);
    if (thrMatch != null) {
      final thr = tryParsePostgresTimestamptz(thrMatch.group(1)!);
      if (thr != null) {
        return thr.subtract(const Duration(minutes: 5));
      }
    }
    return null;
  }

  /// يفسّر ترويسة HTTP Date (GMT).
  @visibleForTesting
  static DateTime? tryParseHttpDate(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    try {
      final format = DateFormat('EEE, dd MMM yyyy HH:mm:ss', 'en_US');
      final withoutGmt = cleaned
          .replaceAll(RegExp(r'\s+GMT$', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s+UTC$', caseSensitive: false), '')
          .trim();
      return format.parseUtc(withoutGmt);
    } catch (_) {
      return DateTime.tryParse(cleaned)?.toUtc();
    }
  }

  static bool _isClockSkewError(String? error) {
    final text = (error ?? '').toLowerCase();
    return text.contains('clock_skew_rejected');
  }

  void _rememberServerTime(DateTime serverUtc) {
    final device = DateTime.now().toUtc();
    _deviceAheadOfServer = device.difference(serverUtc.toUtc());
    _clockOffsetCapturedAt = DateTime.now();
  }

  bool get _hasFreshClockOffset {
    final ahead = _deviceAheadOfServer;
    final at = _clockOffsetCapturedAt;
    if (ahead == null || at == null) return false;
    return DateTime.now().difference(at) <= _clockOffsetTtl;
  }

  /// تقدير وقت السيرفر الآن (UTC) من الانحراف المخزّن أو الشبكة.
  Future<DateTime> resolveServerUtc({String? clockSkewHint}) async {
    if (clockSkewHint != null && _isClockSkewError(clockSkewHint)) {
      final fromErr = tryParseServerNowFromClockSkewError(clockSkewHint);
      if (fromErr != null) {
        _rememberServerTime(fromErr);
        return fromErr;
      }
    }

    if (_hasFreshClockOffset) {
      return DateTime.now().toUtc().subtract(_deviceAheadOfServer!);
    }

    final override = serverUtcProviderForTesting;
    if (override != null) {
      final v = await override();
      if (v != null) {
        _rememberServerTime(v);
        return v.toUtc();
      }
    }

    final fetched = await _fetchServerUtcFromHttpDate();
    if (fetched != null) {
      _rememberServerTime(fetched);
      return fetched;
    }

    return DateTime.now().toUtc();
  }

  Future<DateTime?> _fetchServerUtcFromHttpDate() async {
    try {
      final base = SupabaseConfig.url.trim();
      if (base.isEmpty) return null;
      final uri = Uri.parse(base);
      final res =
          await http.head(uri).timeout(const Duration(seconds: 4));
      final dateHeader = res.headers['date'] ?? res.headers['Date'];
      if (dateHeader == null || dateHeader.isEmpty) {
        final getRes =
            await http.get(uri).timeout(const Duration(seconds: 4));
        final d = getRes.headers['date'] ?? getRes.headers['Date'];
        return d == null ? null : tryParseHttpDate(d);
      }
      return tryParseHttpDate(dateHeader);
    } catch (e) {
      if (kDebugMode) {
        AppLogger.warn('SyncQueue', 'fetch server Date failed: $e');
      }
      return null;
    }
  }

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
    if (_hasFreshClockOffset) {
      sanitizePayloadTimestamps(
        payload,
        referenceUtc: DateTime.now().toUtc().subtract(_deviceAheadOfServer!),
      );
    } else {
      sanitizePayloadTimestamps(payload);
    }

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

  /// إحصاءات لحظية لطابور المزامنة لاستخدامها في شاشات المراقبة.
  Future<Map<String, int>> getQueueStats() async {
    final db = await _resolveDb();
    final rows = await db.rawQuery('''
      SELECT status, COUNT(*) AS c
      FROM sync_queue
      GROUP BY status
    ''');
    final stats = <String, int>{
      'pending': 0,
      'failed': 0,
      'dead': 0,
      'synced': 0,
    };
    for (final r in rows) {
      final key = (r['status'] ?? '').toString();
      if (key.isEmpty) continue;
      stats[key] = (r['c'] as num?)?.toInt() ?? 0;
    }
    return stats;
  }

  /// أحدث الحركات العالقة للتشخيص التشغيلي في الواجهة.
  /// تركز على الحالات `failed` و`dead` مع ملخص آخر خطأ.
  Future<List<Map<String, dynamic>>> getRecentBlockingMutations({
    int limit = 40,
  }) async {
    final db = await _resolveDb();
    final safeLimit = limit < 1 ? 1 : (limit > 200 ? 200 : limit);
    final rows = await db.rawQuery(
      '''
      SELECT mutation_id, entity_type, operation, status, retry_count,
             last_error, last_attempt_at, created_at
      FROM sync_queue
      WHERE status IN ('failed', 'dead')
      ORDER BY
        CASE status WHEN 'dead' THEN 0 ELSE 1 END ASC,
        datetime(COALESCE(last_attempt_at, created_at)) DESC,
        mutation_id DESC
      LIMIT ?
      ''',
      [safeLimit],
    );
    return rows;
  }

  /// هل توجد طوابير غير مرفوعة قد تسبب فقدان بيانات عند تبديل الحساب/الخروج.
  Future<bool> hasBlockingMutations() async {
    final db = await _resolveDb();
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS c
      FROM sync_queue
      WHERE status IN ('pending', 'failed', 'dead')
    ''');
    final count = (rows.first['c'] as num?)?.toInt() ?? 0;
    return count > 0;
  }

  /// يعيد كل الحركات المتعثرة (failed/dead) إلى pending لإعادة الإرسال يدويًا.
  /// يضبط الطوابع نسبةً لوقت السيرفر (من رسالة الخطأ أو HTTP Date) حتى لا تُرفض مرة أخرى.
  Future<int> retryAllFailedAndDead() async {
    final db = await _resolveDb();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final rows = await db.rawQuery('''
      SELECT mutation_id, payload, last_error
      FROM sync_queue
      WHERE status IN ('failed', 'dead')
    ''');

    // اجمع تلميح clock_skew من أول صف متاح ثم اجلب مرجع السيرفر مرة واحدة.
    String? skewHint;
    for (final row in rows) {
      final err = (row['last_error'] ?? '').toString();
      if (_isClockSkewError(err)) {
        skewHint = err;
        break;
      }
    }
    final serverUtc = await resolveServerUtc(clockSkewHint: skewHint);
    final deviceAhead =
        DateTime.now().toUtc().difference(serverUtc).inMinutes.abs() >= 2;

    await db.transaction((txn) async {
      for (final row in rows) {
        final mutationId = (row['mutation_id'] ?? '').toString();
        if (mutationId.isEmpty) continue;

        var payloadJson = (row['payload'] as String?) ?? '{}';
        final lastError = (row['last_error'] ?? '').toString();
        try {
          final payload =
              jsonDecode(payloadJson) as Map<String, dynamic>;
          final rowServer = _isClockSkewError(lastError)
              ? (tryParseServerNowFromClockSkewError(lastError) ?? serverUtc)
              : serverUtc;

          final mustForce = _isClockSkewError(lastError) || deviceAhead;
          final changed = mustForce
              ? forceAlignPayloadTimestamps(payload, rowServer)
              : sanitizePayloadTimestamps(
                  payload,
                  referenceUtc: rowServer,
                );
          if (changed) {
            payloadJson = jsonEncode(payload);
          }
        } catch (e) {
          if (kDebugMode) {
            AppLogger.warn(
              'SyncQueue',
              'retryAll: failed to sanitize payload for $mutationId: $e',
            );
          }
        }

        await txn.update(
          'sync_queue',
          {
            'payload': payloadJson,
            'status': 'pending',
            'retry_count': 0,
            'last_error': null,
            'last_attempt_at': nowIso,
          },
          where: 'mutation_id = ?',
          whereArgs: [mutationId],
        );
      }
    });

    final affected = rows.length;
    if (affected > 0) {
      scheduleProcessingSoon();
    }
    return affected;
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

      // مرجع السيرفر — مهم عندما تكون ساعة الجهاز متقدمة (لا يكفي DateTime.now).
      String? skewHint;
      for (final r in rows) {
        final err = (r['last_error'] ?? '').toString();
        if (_isClockSkewError(err)) {
          skewHint = err;
          break;
        }
      }
      final serverUtc = await resolveServerUtc(clockSkewHint: skewHint);
      final deviceAheadMinutes =
          DateTime.now().toUtc().difference(serverUtc).inMinutes;
      final forceAlign = deviceAheadMinutes >= 2;

      final deviceId = await _getDeviceId();

      final payloadList = <Map<String, dynamic>>[];
      final payloadJsonById = <String, String>{};
      for (final r in rows) {
        final mutationId = r['mutation_id'] as String;
        final payloadMap =
            jsonDecode(r['payload'] as String) as Map<String, dynamic>;
        final changed = forceAlign
            ? forceAlignPayloadTimestamps(payloadMap, serverUtc)
            : sanitizePayloadTimestamps(
                payloadMap,
                referenceUtc: serverUtc,
              );
        if (changed) {
          final encoded = jsonEncode(payloadMap);
          await db.update(
            'sync_queue',
            {'payload': encoded},
            where: 'mutation_id = ?',
            whereArgs: [mutationId],
          );
          payloadJsonById[mutationId] = encoded;
        } else {
          payloadJsonById[mutationId] = r['payload'] as String;
        }
        payloadMap['_mutation_id'] = mutationId;
        payloadMap['_entity_type'] = r['entity_type'];
        payloadMap['_operation'] = r['operation'];
        payloadMap['_device_id'] = deviceId;
        payloadList.add(payloadMap);
      }

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
          } else if (_isClockSkewError(res.error)) {
            final healed = await _healClockSkewPayload(
              txn,
              mutationId: mutationId,
              payloadJson: payloadJsonById[mutationId] ??
                  ((row['payload'] as String?) ?? '{}'),
              errorMessage: res.error ?? '',
              fallbackServerUtc: serverUtc,
            );
            if (healed) {
              // لا نستهلك retry — أعدنا كتابة الطوابع بوقت السيرفر وسنعيد الإرسال.
              await txn.update(
                'sync_queue',
                {
                  'status': 'pending',
                  'last_error': res.error,
                  'last_attempt_at': nowIso,
                },
                where: 'mutation_id = ?',
                whereArgs: [mutationId],
              );
            } else {
              await _markFailed(
                txn,
                mutationId: mutationId,
                currentRetry: (row['retry_count'] as num?)?.toInt() ?? 0,
                errorMessage: res.error ?? 'clock_skew_rejected',
                nowIso: nowIso,
              );
            }
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

  /// يعيد كتابة طوابع الـ payload إلى وقت السيرفر المستخرج من رسالة clock_skew.
  Future<bool> _healClockSkewPayload(
    DatabaseExecutor txn, {
    required String mutationId,
    required String payloadJson,
    required String errorMessage,
    DateTime? fallbackServerUtc,
  }) async {
    final serverNow =
        tryParseServerNowFromClockSkewError(errorMessage) ?? fallbackServerUtc;
    if (serverNow == null) return false;
    _rememberServerTime(serverNow);
    try {
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
      final touched = forceAlignPayloadTimestamps(payload, serverNow);
      if (!touched) {
        // لا توجد مفاتيح طابع — نخزّن كما هو ونعتبره مُعالَجًا.
        return true;
      }
      await txn.update(
        'sync_queue',
        {'payload': jsonEncode(payload)},
        where: 'mutation_id = ?',
        whereArgs: [mutationId],
      );
      return true;
    } catch (e) {
      if (kDebugMode) {
        AppLogger.warn(
          'SyncQueue',
          'clock_skew heal failed for $mutationId: $e',
        );
      }
      return false;
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
