import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/tenant_context_service.dart';
import '../utils/app_logger.dart';
import 'push_device_registry.dart';

/// الأحداث الفورية (خطة الإشعارات، المرحلة 2): الجهاز يكتب الحدث صفا صغيرا في
/// notification_events لحظة وقوعه، والخادم يكتب النص ويرسل.
///
/// طابور محلي مستقل عن طابور المزامنة (لا يمس مسار المزامنة الفورية):
/// - يُحفظ أولا، فالحدث الذي وقع بلا إنترنت يصل عند عودة الاتصال.
/// - مفتاح الحدث ثابت (الجهاز + النوع + المرجع)، فالإرسال المكرر لا يكرر الإشعار.
/// - لا استعلام دوري: المؤقت يعمل فقط ما دام في الطابور شيء.
class NotificationEventOutbox {
  NotificationEventOutbox._();
  static final NotificationEventOutbox instance = NotificationEventOutbox._();

  static const _prefsKey = 'notif_event_outbox_v1';
  static const _maxQueue = 300;
  static const _retryEvery = Duration(minutes: 2);

  Timer? _retry;
  bool _flushing = false;

  /// المبالغ في التطبيق بالدينار، والحدث يحملها بالفلس (أعداد صحيحة).
  static int fils(num? iqd) => ((iqd ?? 0) * 1000).round();

  /// [ref] يميّز الحدث داخل نوعه (رقم الوردية، رقم الفاتورة...).
  Future<void> record({
    required String type,
    required String ref,
    required Map<String, Object?> payload,
    required String staffName,
    required String actorRole,
    String staffGlobalId = '',
    DateTime? at,
  }) async {
    try {
      final deviceId = await PushDeviceRegistry.instance.deviceId();
      final event = <String, Object?>{
        'event_key': '$deviceId:$type:$ref',
        'type': type,
        'tenant': TenantContextService.instance.activeTenantId,
        'payload': {
          ...payload,
          'staff_name': staffName,
          'actor_role': actorRole,
        },
        'occurred_at': (at ?? DateTime.now()).toUtc().toIso8601String(),
        'device_id': deviceId,
        'staff_global_id': staffGlobalId,
      };
      final p = await SharedPreferences.getInstance();
      final list = _read(p)..add(event);
      while (list.length > _maxQueue) {
        list.removeAt(0);
      }
      await p.setString(_prefsKey, jsonEncode(list));
    } catch (e) {
      AppLogger.warn('EventOutbox', 'record $type: $e');
      return;
    }
    unawaited(flush());
  }

  List<Map<String, dynamic>> _read(SharedPreferences p) {
    final raw = p.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// يرفع ما في الطابور. يُستدعى بعد كل حدث، وعند فتح التطبيق، وكل دقيقتين ما دام الطابور غير فارغ.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      final p = await SharedPreferences.getInstance();
      var list = _read(p);
      if (list.isEmpty) {
        _retry?.cancel();
        _retry = null;
        return;
      }
      if (user == null) {
        _armRetry();
        return;
      }
      final done = <String>{};
      for (final e in list) {
        final key = e['event_key']?.toString() ?? '';
        try {
          await client.from('notification_events').insert({
            'user_id': user.id,
            'local_tenant_id': (e['tenant'] as num?)?.toInt() ?? 1,
            'event_key': key,
            'type': e['type'],
            'payload': e['payload'],
            'occurred_at': e['occurred_at'],
            'device_id': e['device_id'],
            'staff_global_id':
                (e['staff_global_id']?.toString().isEmpty ?? true)
                ? null
                : e['staff_global_id'],
          });
          done.add(key);
        } on PostgrestException catch (err) {
          // 23505: وصل من قبل (إعادة بعد انقطاع). 42P01: الخادم أقدم من الميزة.
          if (err.code == '23505' || err.code == '42P01') {
            done.add(key);
            continue;
          }
          AppLogger.warn('EventOutbox', 'insert ${e['type']}: ${err.message}');
          break; // نحاول لاحقا بالترتيب نفسه
        } catch (err) {
          break; // بلا اتصال
        }
      }
      list = _read(p)
        ..removeWhere((e) => done.contains(e['event_key']?.toString()));
      await p.setString(_prefsKey, jsonEncode(list));
      if (list.isEmpty) {
        _retry?.cancel();
        _retry = null;
      } else {
        _armRetry();
      }
    } catch (e) {
      AppLogger.warn('EventOutbox', 'flush: $e');
      _armRetry();
    } finally {
      _flushing = false;
    }
  }

  void _armRetry() {
    _retry ??= Timer.periodic(_retryEvery, (_) => unawaited(flush()));
  }
}
