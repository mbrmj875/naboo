import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../utils/app_logger.dart';

/// صفحة «ما يقوله المجيب للزبائن» وقوائمه (ب7، ق83–ق85، ق90).
///
/// على الخادم مثل باقي إعدادات واتساب: المجيب يقرؤها مع الرسالة التالية مباشرة.
/// RLS تحصر كل شيء على حساب المحل الحالي.
class WhatsappResponderProfile {
  WhatsappResponderProfile({
    this.enabled = false,
    this.hours = '',
    List<String>? services,
    this.serviceDuration = '',
    this.offerText = '',
    this.offerUntil,
    List<ResponderNote>? notes,
    this.mentionPrices = true,
    this.mentionStock = true,
    this.oilAdvice = true,
    this.tone = 'playful',
    this.silence = '2h',
  })  : services = services ?? [],
        notes = notes ?? [];

  bool enabled;
  String hours;
  List<String> services;
  String serviceDuration;
  String offerText;
  DateTime? offerUntil;
  List<ResponderNote> notes;
  bool mentionPrices;
  bool mentionStock;
  bool oilAdvice;

  /// playful | calm | formal
  String tone;

  /// 30m | 2h | eod
  String silence;

  static const maxNotes = 20;
  static const maxNoteChars = 200;

  factory WhatsappResponderProfile.fromMap(Map<String, dynamic> m) {
    final rawNotes = m['notes'];
    return WhatsappResponderProfile(
      enabled: m['enabled'] == true,
      hours: (m['hours'] ?? '').toString(),
      services: (m['services'] as List?)?.map((e) => '$e').where((e) => e.trim().isNotEmpty).toList(),
      serviceDuration: (m['service_duration'] ?? '').toString(),
      offerText: (m['offer_text'] ?? '').toString(),
      offerUntil: DateTime.tryParse((m['offer_until'] ?? '').toString()),
      notes: rawNotes is List
          ? [
              for (final n in rawNotes)
                if (n is Map && '${n['text'] ?? ''}'.trim().isNotEmpty)
                  ResponderNote('${n['text']}'.trim(), fromCorrection: n['source'] == 'correction', at: '${n['at'] ?? ''}'),
            ]
          : [],
      mentionPrices: m['mention_prices'] != false,
      mentionStock: m['mention_stock'] != false,
      oilAdvice: m['oil_advice'] != false,
      tone: const {'playful', 'calm', 'formal'}.contains(m['tone']) ? m['tone'] as String : 'playful',
      silence: const {'30m', '2h', 'eod'}.contains(m['silence']) ? m['silence'] as String : '2h',
    );
  }

  Map<String, dynamic> toRow(String tenantUserId) => {
        'tenant_user_id': tenantUserId,
        'enabled': enabled,
        'hours': hours.trim(),
        'services': [for (final s in services) if (s.trim().isNotEmpty) s.trim()],
        'service_duration': serviceDuration.trim(),
        'offer_text': offerText.trim(),
        'offer_until': offerUntil == null
            ? null
            : '${offerUntil!.year.toString().padLeft(4, '0')}-${offerUntil!.month.toString().padLeft(2, '0')}-'
                '${offerUntil!.day.toString().padLeft(2, '0')}',
        'notes': [
          for (final n in notes.take(maxNotes))
            {'text': n.text, 'source': n.fromCorrection ? 'correction' : 'owner', if (n.at.isNotEmpty) 'at': n.at},
        ],
        'mention_prices': mentionPrices,
        'mention_stock': mentionStock,
        'oil_advice': oilAdvice,
        'tone': tone,
        'silence': silence,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  /// ما يمنع الحفظ، أو null. نفس حدود الجدول على الخادم.
  String? validate() {
    if (hours.trim().length > 300) return 'الدوام أطول من 300 حرف';
    if (services.length > 30) return 'الخدمات أكثر من 30';
    if (serviceDuration.trim().length > 120) return 'مدة الخدمة أطول من 120 حرفاً';
    if (offerText.trim().length > 300) return 'العرض أطول من 300 حرف';
    if (notes.length > maxNotes) return 'الملاحظات أكثر من $maxNotes';
    for (final n in notes) {
      if (n.text.length > maxNoteChars) return 'ملاحظة أطول من $maxNoteChars حرف';
    }
    if (enabled && hours.trim().isEmpty) return 'اكتب الدوام قبل تشغيل المجيب الذكي';
    return null;
  }
}

class ResponderNote {
  ResponderNote(this.text, {this.fromCorrection = false, this.at = ''});
  final String text;

  /// جاء من زر «رد خاطئ».
  final bool fromCorrection;
  final String at;
}

class WhatsappHandoff {
  const WhatsappHandoff({
    required this.id,
    required this.phone,
    required this.reason,
    required this.question,
    required this.startedAt,
    required this.endsAt,
  });

  final int id;
  final String phone;
  final String reason;
  final String question;
  final DateTime startedAt;
  final DateTime endsAt;

  String get reasonLabel => switch (reason) {
        'low_rating' => 'تقييم منخفض',
        'human' => 'يطلب موظفاً',
        'fault' => 'سؤال عطل',
        'angry' => 'منزعج',
        'media' => 'صورة أو صوت',
        _ => 'سؤال بلا جواب',
      };

  factory WhatsappHandoff.fromMap(Map<String, dynamic> m) => WhatsappHandoff(
        id: (m['id'] as num).toInt(),
        phone: '${m['customer_phone'] ?? ''}',
        reason: '${m['reason'] ?? ''}',
        question: '${m['question'] ?? ''}',
        startedAt: DateTime.tryParse('${m['started_at']}')?.toLocal() ?? DateTime.now(),
        endsAt: DateTime.tryParse('${m['ends_at']}')?.toLocal() ?? DateTime.now(),
      );
}

class WhatsappVisitRequest {
  const WhatsappVisitRequest({
    required this.id,
    required this.phone,
    required this.name,
    required this.car,
    required this.request,
    required this.createdAt,
  });

  final int id;
  final String phone;
  final String name;
  final String car;
  final String request;
  final DateTime createdAt;

  factory WhatsappVisitRequest.fromMap(Map<String, dynamic> m) => WhatsappVisitRequest(
        id: (m['id'] as num).toInt(),
        phone: '${m['customer_phone'] ?? ''}',
        name: '${m['customer_name'] ?? ''}',
        car: '${m['car'] ?? ''}',
        request: '${m['request'] ?? ''}',
        createdAt: DateTime.tryParse('${m['created_at']}')?.toLocal() ?? DateTime.now(),
      );
}

class WhatsappResponderRepository {
  WhatsappResponderRepository({SupabaseClient? client}) : _clientOverride = client;

  static final instance = WhatsappResponderRepository();

  final SupabaseClient? _clientOverride;
  SupabaseClient get _db => _clientOverride ?? Supabase.instance.client;

  String? get _uid => _db.auth.currentUser?.id;

  /// طلب الزيارة يُغلق وحده بعد 3 أيام (م6-10).
  static const visitDays = 3;

  Future<WhatsappResponderProfile> loadProfile() async {
    final uid = _uid;
    if (uid == null) return WhatsappResponderProfile();
    final row = await _db.from('whatsapp_responder_profiles').select().eq('tenant_user_id', uid).maybeSingle();
    return row == null ? WhatsappResponderProfile() : WhatsappResponderProfile.fromMap(row);
  }

  Future<void> saveProfile(WhatsappResponderProfile p) async {
    final uid = _uid;
    if (uid == null) throw StateError('سجّل الدخول أولاً');
    final err = p.validate();
    if (err != null) throw StateError(err);
    await _db.from('whatsapp_responder_profiles').upsert(p.toRow(uid), onConflict: 'tenant_user_id');
  }

  Future<List<WhatsappHandoff>> openHandoffs() async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final rows = await _db
          .from('whatsapp_handoffs')
          .select('id, customer_phone, reason, question, started_at, ends_at')
          .eq('tenant_user_id', uid)
          .isFilter('ended_at', null)
          .gt('ends_at', DateTime.now().toUtc().toIso8601String())
          .order('started_at', ascending: false)
          .limit(50);
      return [for (final r in rows) WhatsappHandoff.fromMap(r)];
    } catch (e) {
      AppLogger.warn('wa_responder', 'handoffs failed: $e');
      return const [];
    }
  }

  /// «رددتُ عليه»: المجيب يرجع يرد على هذا الزبون.
  Future<void> endHandoff(int id) async {
    await _db
        .from('whatsapp_handoffs')
        .update({'ended_at': DateTime.now().toUtc().toIso8601String(), 'ended_by': 'app'}).eq('id', id);
  }

  Future<List<WhatsappVisitRequest>> openVisits() async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final since = DateTime.now().toUtc().subtract(const Duration(days: visitDays)).toIso8601String();
      final rows = await _db
          .from('whatsapp_visit_requests')
          .select('id, customer_phone, customer_name, car, request, created_at')
          .eq('tenant_user_id', uid)
          .eq('status', 'open')
          .gte('created_at', since)
          .order('created_at', ascending: false)
          .limit(50);
      return [for (final r in rows) WhatsappVisitRequest.fromMap(r)];
    } catch (e) {
      AppLogger.warn('wa_responder', 'visits failed: $e');
      return const [];
    }
  }

  /// carded = فُتحت له بطاقة وحُفظت، closed = أغلقه المستخدم.
  Future<void> closeVisit(int id, {required bool carded}) async {
    await _db.from('whatsapp_visit_requests').update({
      'status': carded ? 'carded' : 'closed',
      'closed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// «رد خاطئ» (ق90): الصواب يصير ملاحظة في صفحة المجيب فوراً.
  Future<void> correctReply(String logId, String correct) async {
    await _db.rpc('whatsapp_correct_reply', params: {'p_log_id': logId, 'p_correct': correct.trim()});
  }
}
