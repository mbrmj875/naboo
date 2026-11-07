import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../utils/app_logger.dart';
import 'wa_oil_followup_copy.dart';

/// ما سبق تسجيله لهذا الزبون عند هذا المتجر.
enum WaRecipientConsentStatus { none, staffDeclined, customerOptedOut }

typedef WaFollowupRpc = Future<dynamic> Function(
  String fn,
  Map<String, dynamic> params,
);

/// جدولة تذكير بعد حفظ بطاقة غيار — مستقل عن إرسال البطاقة الفوري.
///
/// انقطاع الشبكة لا يُسقط التذكير: يُحفظ على الجهاز بوقت الحفظ الأصلي
/// فيبقى موعده كما هو، ويُعاد مع البطاقة التالية أو عند فتح نموذج البطاقة.
class WaOilFollowupScheduler {
  WaOilFollowupScheduler._();

  static final WaOilFollowupScheduler instance = WaOilFollowupScheduler._();

  @visibleForTesting
  WaOilFollowupScheduler.forTest(this._rpcOverride, this._uidOverride);

  static const _pendingKey = 'wa_followup_pending_v1';
  static const _pendingCap = 500;

  WaFollowupRpc? _rpcOverride;
  String? _uidOverride;

  SupabaseClient get _client => Supabase.instance.client;

  String? get _uid {
    if (_uidOverride != null) return _uidOverride;
    try {
      return _client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> _rpc(String fn, Map<String, dynamic> params) {
    final override = _rpcOverride;
    if (override != null) return override(fn, params);
    return _client.rpc(fn, params: params);
  }

  /// [consent]: true أبلغ الموظف الزبون، false رفض الزبون فلا تذكير،
  /// null تصحيح بطاقة فلا تتغير موافقته.
  Future<void> enqueueAfterSave({
    required int? orderId,
    required String customerPhone,
    required Map<String, dynamic> order,
    required String storeTitle,
    bool? consent,
  }) async {
    final uid = _uid;
    if (uid == null || orderId == null || orderId <= 0) return;
    final phone = customerPhone.trim();
    if (phone.length < 8) return;

    final name = (order['customerNameSnapshot'] ?? '').toString().trim();
    final car = _carLabel(order);
    final odoCur = (order['odometerCurrent'] ?? '').toString().trim();
    final odoNext = (order['odometerNext'] ?? '').toString().trim();
    final visit = _visitDate(order);

    final payload = {
      'customer_name': name.isEmpty ? 'عميلنا الكريم' : name,
      'car': car,
      'shop': storeTitle.trim().isEmpty ? 'المحل' : storeTitle.trim(),
      'odometer_current': odoCur.isEmpty ? '—' : odoCur,
      'odometer_next': odoNext.isEmpty ? '—' : odoNext,
      'visit_date': visit,
    };

    final entry = <String, dynamic>{
      'uid': uid,
      'order_ref': orderId.toString(),
      'phone': phone,
      'payload': payload,
      'saved_at': DateTime.now().toUtc().toIso8601String(),
      'consent': consent,
    };
    await flushPending();
    if (await _deliver(entry)) return;
    await _keepForRetry(entry);
  }

  /// يعيد ما تعذر إرساله سابقًا. مفتاح الطلب ثابت فلا يتكرر التذكير.
  Future<void> flushPending() async {
    final uid = _uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pendingKey) ?? const <String>[];
    if (raw.isEmpty) return;
    final kept = <String>[];
    var offline = false;
    for (final item in raw) {
      final entry = jsonDecode(item) as Map<String, dynamic>;
      if (offline || entry['uid'] != uid) {
        kept.add(item);
        continue;
      }
      if (!await _deliver(entry)) {
        offline = true;
        kept.add(item);
      }
    }
    await prefs.setStringList(_pendingKey, kept);
  }

  /// false يعني لم يصل الخادم أصلًا فيُعاد لاحقًا. رد الخادم بالرفض لا يُعاد.
  Future<bool> _deliver(Map<String, dynamic> entry) async {
    try {
      final consent = entry['consent'] as bool?;
      if (consent != null) {
        final status = await _setConsent(entry['phone'] as String, consent);
        if (status == 'opted_out') return true;
      }
      await _rpc('wa_followup_schedule_job', {
        'p_order_ref': entry['order_ref'],
        'p_phone': entry['phone'],
        'p_payload': entry['payload'],
        'p_saved_at': entry['saved_at'],
      });
      return true;
    } on PostgrestException catch (e) {
      if (_isMissingSchema(e)) {
        AppLogger.warn('wa_followup', 'schema missing — skip schedule');
      } else {
        AppLogger.warn('wa_followup', 'schedule failed: ${e.message}');
      }
      return true;
    } catch (e, st) {
      AppLogger.error('wa_followup', 'schedule will retry', e, st);
      return false;
    }
  }

  /// غياب الدالة قبل نشر الهجرة لا يمنع جدولة التذكير.
  Future<String?> _setConsent(String phone, bool consent) async {
    try {
      final res = await _rpc('wa_recipient_consent_set', {
        'p_phone': phone,
        'p_consented': consent,
      });
      return res?.toString();
    } on PostgrestException catch (e) {
      if (_isMissingSchema(e)) return consent ? null : 'opted_out';
      rethrow;
    }
  }

  Future<void> _keepForRetry(Map<String, dynamic> entry) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = List<String>.of(
      prefs.getStringList(_pendingKey) ?? const <String>[],
    );
    raw.add(jsonEncode(entry));
    await prefs.setStringList(
      _pendingKey,
      raw.length > _pendingCap ? raw.sublist(raw.length - _pendingCap) : raw,
    );
  }

  /// فشل القراءة لا يغيّر الخيار، ويبقى منع الإرسال عند الخادم.
  Future<WaRecipientConsentStatus> recipientConsentStatus(String phone) async {
    final uid = _uid;
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (uid == null || digits.length < 8) return WaRecipientConsentStatus.none;
    final key =
        digits.length > 10 ? digits.substring(digits.length - 10) : digits;
    try {
      final row = await _client
          .from('wa_recipient_consent')
          .select('status, source')
          .eq('tenant_user_id', uid)
          .eq('phone_key', key)
          .maybeSingle();
      if (row == null || row['status'] != 'opted_out') {
        return WaRecipientConsentStatus.none;
      }
      return row['source'] == 'customer_reply'
          ? WaRecipientConsentStatus.customerOptedOut
          : WaRecipientConsentStatus.staffDeclined;
    } catch (_) {
      return WaRecipientConsentStatus.none;
    }
  }

  static String _carLabel(Map<String, dynamic> order) {
    final parts = <String>[
      (order['deviceName'] ?? '').toString().trim(),
      (order['carModel'] ?? '').toString().trim(),
    ].where((s) => s.isNotEmpty);
    if (parts.isEmpty) return 'سيارتكم';
    return parts.join(' · ');
  }

  static String _visitDate(Map<String, dynamic> order) {
    final raw = order['createdAt'] ?? order['created_at'] ?? order['date'];
    final dt = DateTime.tryParse(raw?.toString() ?? '');
    if (dt == null) {
      return DateFormat('d MMMM y', 'ar_SA').format(DateTime.now());
    }
    return DateFormat('d MMMM y', 'ar_SA').format(dt.toLocal());
  }

  bool _isMissingSchema(PostgrestException e) {
    final m = (e.message).toLowerCase();
    return e.code == '42P01' ||
        e.code == '42883' ||
        m.contains('wa_followup') ||
        m.contains('does not exist');
  }
}
