import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer_debt_models.dart';
import '../models/debt_settings_data.dart';
import '../utils/app_logger.dart';
import '../verticals/oil_change/services/oil_change_whatsapp_gateway_service.dart';
import 'app_settings_repository.dart';
import 'database_helper.dart';

/// عميل عليه دين، كما يحتاجه مخطِّط التذكير.
class DebtReminderParty {
  const DebtReminderParty({
    required this.key,
    required this.phone,
    required this.name,
    required this.periodDays,
    required this.invoices,
  });

  /// معرّف ثابت بين الأجهزة (global_id العميل، وإلا رقمه).
  final String key;
  final String phone;
  final String name;
  final int periodDays;
  final List<({DateTime date, int remainingFils})> invoices;
}

/// تذكير واحد جاهز للإرسال.
class DebtReminderCandidate {
  const DebtReminderCandidate({
    required this.reminderKey,
    required this.phone,
    required this.name,
    required this.openFils,
    required this.oldestDate,
  });

  /// «عميل|يوم الاستحقاق»: لا يُرسل التذكير نفسه مرتين.
  final String reminderKey;
  final String phone;
  final String name;

  /// كل دين العميل المفتوح (لا المتأخر وحده)، كما في زر «ذكّره بالدين».
  final int openFils;
  final DateTime oldestDate;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
String _two(int n) => n.toString().padLeft(2, '0');

/// yyyy-MM-dd بلا تهيئة بيانات اللغة.
String _dayKey(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// يوم تأخّر الفاتورة: أول يوم يصبح فيه `creditInvoiceIsOverdue` صحيحاً.
DateTime debtInvoiceDueDay(DateTime invoiceDate, int periodDays) =>
    _day(invoiceDate).add(Duration(days: periodDays + 1));

/// المرحلة 7 — الشريحة 4: رسالة واحدة لكل عميل يوم تأخّر دينه.
///
/// - العميل بلا هاتف، أو بلا فترة تسديد، لا يُذكَّر.
/// - الفاتورة التي تأخّرت قبل [since] (يوم تفعيل التلقائي) لا تُحسب، حتى لا
///   تخرج رسائل لكل الديون القديمة دفعة واحدة عند التفعيل.
/// - إن تأخّرت عدة فواتير، فالمفتاح بيوم أحدثها: رسالة واحدة بالمجموع، وفاتورة
///   تتأخر لاحقاً تأتي برسالة جديدة.
List<DebtReminderCandidate> planDebtReminders({
  required List<DebtReminderParty> parties,
  required DateTime since,
  required DateTime now,
  required Set<String> alreadySent,
}) {
  final out = <DebtReminderCandidate>[];
  final sinceDay = _day(since);
  for (final p in parties) {
    if (p.periodDays <= 0) continue;
    if (p.phone.replaceAll(RegExp(r'\D'), '').length < 8) continue;
    final open = p.invoices.where((i) => i.remainingFils >= 500).toList();
    if (open.isEmpty) continue;
    DateTime? latestDue;
    for (final i in open) {
      if (!creditInvoiceIsOverdue(
        date: i.date,
        remainingFils: i.remainingFils,
        periodDays: p.periodDays,
        now: now,
      )) {
        continue;
      }
      final due = debtInvoiceDueDay(i.date, p.periodDays);
      if (due.isBefore(sinceDay)) continue;
      if (latestDue == null || due.isAfter(latestDue)) latestDue = due;
    }
    if (latestDue == null) continue;
    final key = '${p.key}|${_dayKey(latestDue)}';
    if (alreadySent.contains(key)) continue;
    var oldest = open.first.date;
    for (final i in open) {
      if (i.date.isBefore(oldest)) oldest = i.date;
    }
    out.add(
      DebtReminderCandidate(
        reminderKey: key,
        phone: p.phone,
        name: p.name,
        openFils: open.fold<int>(0, (s, i) => s + i.remainingFils),
        oldestDate: oldest,
      ),
    );
  }
  return out;
}

/// ما يحتاجه المشغّل من الخادم (يُستبدل في الاختبار).
abstract class DebtReminderTransport {
  bool get signedIn;
  Future<String?> templateStatus();
  Future<String?> submitTemplate();
  Future<({String status, bool retryLater})> send(DebtReminderCandidate c);
}

class _GatewayTransport implements DebtReminderTransport {
  final _gw = OilChangeWhatsappGatewayService.instance;
  final _num = NumberFormat('#,##0', 'en');

  @override
  bool get signedIn {
    try {
      return Supabase.instance.client.auth.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> templateStatus() => _gw.debtReminderTemplateStatus();

  @override
  Future<String?> submitTemplate() => _gw.submitDebtReminderTemplate();

  @override
  Future<({String status, bool retryLater})> send(DebtReminderCandidate c) {
    final d = c.oldestDate;
    return _gw.sendDebtReminder(
      customerPhone: c.phone,
      reminderKey: c.reminderKey,
      customerName: c.name,
      amountText: '${_num.format(c.openFils / 1000.0)} د.ع',
      sinceText: '${d.day}/${d.month}/${d.year}',
      // الخادم يضع اسم المحل الموثَّق.
      shopName: '',
    );
  }
}

/// يُشغَّل عند فتح التطبيق: يرسل تذكيرات الديون التي تأخّرت، مرة في اليوم.
class DebtAutoReminderService {
  DebtAutoReminderService._();

  static final DebtAutoReminderService instance = DebtAutoReminderService._();

  static const sinceKey = 'biz.debt.auto_reminder_since';
  static const sentKey = 'biz.debt.auto_reminder_sent';
  static const _sentCap = 3000;

  DebtReminderTransport transport = _GatewayTransport();
  DateTime Function() clock = DateTime.now;

  String? _lastRunDay;
  bool _running = false;

  final AppSettingsRepository _settings = AppSettingsRepository.instance;
  final DatabaseHelper _db = DatabaseHelper();

  /// يُستدعى عند اختيار «تلقائي» أو «الاثنان»: من اليوم تُحسب الديون.
  /// اختيار «يدوي» أو «بلا تذكير» يمسح اليوم، فإعادة التفعيل تبدأ من جديد.
  Future<void> onModeChanged(DebtReminderMode mode) async {
    final tid = await _settings.getActiveTenantId();
    final auto = mode == DebtReminderMode.auto || mode == DebtReminderMode.both;
    final current = await _settings.getForTenant(sinceKey, tenantId: tid);
    if (auto && (current == null || current.isEmpty)) {
      await _settings.setForTenant(
        sinceKey,
        clock().toIso8601String(),
        tenantId: tid,
      );
    } else if (!auto && current != null && current.isNotEmpty) {
      await _settings.setForTenant(sinceKey, '', tenantId: tid);
    }
  }

  /// حالة قالب التذكير عند ميتا، أو null بلا إنترنت أو بلا دخول.
  Future<String?> templateStatus() async {
    if (!transport.signedIn) return null;
    try {
      return await transport.templateStatus();
    } catch (_) {
      return null;
    }
  }

  /// يرفع القالب للمراجعة (المعتمد أو قيد المراجعة لا يُعاد).
  Future<String?> submitTemplate() async {
    if (!transport.signedIn) return null;
    try {
      return await transport.submitTemplate();
    } catch (_) {
      return null;
    }
  }

  /// يُرجع عدد الرسائل المرسلة. [force] يتجاهل «مرة في اليوم» (للاختبار).
  Future<int> runIfDue({bool force = false}) async {
    final today = _dayKey(clock());
    if (_running || (!force && _lastRunDay == today)) return 0;
    _running = true;
    try {
      final sent = await _run();
      _lastRunDay = today;
      return sent;
    } catch (e, st) {
      AppLogger.error('debt_auto_reminder', 'run failed', e, st);
      return 0;
    } finally {
      _running = false;
    }
  }

  Future<int> _run() async {
    final settings = await _db.getDebtSettings();
    final mode = settings.reminderMode;
    if (mode != DebtReminderMode.auto && mode != DebtReminderMode.both) {
      return 0;
    }
    final tid = await _settings.getActiveTenantId();
    final sinceRaw = await _settings.getForTenant(sinceKey, tenantId: tid);
    final since = DateTime.tryParse(sinceRaw ?? '');
    if (since == null) {
      // مفعَّل من جهاز آخر أو قبل هذا الإصدار: يبدأ العد من اليوم.
      await onModeChanged(mode);
      return 0;
    }
    if (!transport.signedIn) return 0;

    final sentSet = await _readSent(tid);
    final parties = await _loadParties();
    final plan = planDebtReminders(
      parties: parties,
      since: since,
      now: clock(),
      alreadySent: sentSet,
    );
    if (plan.isEmpty) return 0;

    if (await transport.templateStatus() != 'approved') return 0;

    var count = 0;
    final done = <String>[];
    for (final c in plan) {
      final r = await transport.send(c);
      if (r.status == 'sent') count++;
      if (!r.retryLater) {
        done.add(c.reminderKey);
        continue;
      }
      // الرصيد أو الربط أو القالب: لا فائدة من البقية الآن.
      if (r.status != 'failed') break;
    }
    if (done.isNotEmpty) await _writeSent(tid, [...sentSet, ...done]);
    return count;
  }

  Future<List<DebtReminderParty>> _loadParties() async {
    final summaries = await _db.getCustomerDebtSummaries(now: clock());
    final out = <DebtReminderParty>[];
    final db = await _db.database;
    for (final s in summaries) {
      final id = s.customerId;
      if (id == null || s.overdueFils < 500 || s.periodDays <= 0) continue;
      final rows = await db.query(
        'customers',
        columns: ['phone', 'global_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) continue;
      final phone = (rows.first['phone'] ?? '').toString().trim();
      final gid = (rows.first['global_id'] ?? '').toString().trim();
      out.add(
        DebtReminderParty(
          key: gid.isNotEmpty ? gid : 'id$id',
          phone: phone,
          name: s.displayName,
          periodDays: s.periodDays,
          invoices: await _db.openCreditInvoiceAges(
            CustomerDebtParty(
              customerId: id,
              displayName: s.displayName,
              normalizedName: s.displayName.trim().toLowerCase(),
            ),
          ),
        ),
      );
    }
    return out;
  }

  Future<Set<String>> _readSent(int tid) async {
    final raw = await _settings.getForTenant(sentKey, tenantId: tid);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      return {for (final e in jsonDecode(raw) as List) '$e'};
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _writeSent(int tid, List<String> keys) async {
    final unique = keys.toSet().toList();
    final kept = unique.length > _sentCap
        ? unique.sublist(unique.length - _sentCap)
        : unique;
    await _settings.setForTenant(sentKey, jsonEncode(kept), tenantId: tid);
  }
}

/// نص حالة القالب تحت «طريقة تذكير العميل».
String debtTemplateStatusAr(String? status) => switch (status) {
  'approved' => 'رسالة التذكير معتمدة من ميتا: تُرسل يوم تأخّر الدين.',
  'pending' =>
    'رسالة التذكير بانتظار موافقة ميتا (عادة من دقائق إلى يوم). '
        'الديون التي تتأخر قبل الموافقة تُذكَّر بعدها.',
  'rejected' =>
    'رفضت ميتا رسالة التذكير. الزر اليدوي «ذكّره بالدين» يبقى يعمل.',
  'not_official' =>
    'التذكير التلقائي يحتاج ربط واتساب الرسمي من إعدادات الواتساب.',
  'none' => 'لم تُرفع رسالة التذكير بعد: احفظ الإعدادات لرفعها.',
  _ => 'تعذّر معرفة حالة رسالة التذكير الآن (يحتاج إنترنت وتسجيل دخول).',
};
