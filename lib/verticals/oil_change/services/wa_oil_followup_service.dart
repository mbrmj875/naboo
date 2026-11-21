import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../utils/app_logger.dart';
import '../models/wa_oil_followup_job.dart';
import '../models/wa_oil_followup_rule.dart';
import 'oil_change_whatsapp_gateway_service.dart';
import 'wa_oil_followup_copy.dart';

enum WaFollowupTemplateUiStatus {
  none,
  draft,
  pending,
  approved,
  rejected,
  qrReady,
}

class WaOilFollowupSnapshot {
  const WaOilFollowupSnapshot({
    required this.rule,
    required this.templateStatus,
    this.templateLastError,
    this.upcoming = const [],
    this.schemaMissing = false,
    this.isOfficialTransport = true,
  });

  final WaOilFollowupRule rule;
  final WaFollowupTemplateUiStatus templateStatus;
  final String? templateLastError;
  final List<WaOilFollowupJob> upcoming;
  final bool schemaMissing;
  final bool isOfficialTransport;

  bool get canSendFollowups {
    if (!rule.enabled) return false;
    if (!isOfficialTransport) return true;
    return templateStatus == WaFollowupTemplateUiStatus.approved;
  }
}

class WaOilFollowupSummary {
  const WaOilFollowupSummary({
    this.enabled = false,
    this.delayValue = 3,
    this.delayUnit = WaOilFollowupDelayUnit.month,
    this.templateStatus = WaFollowupTemplateUiStatus.none,
    this.schemaMissing = false,
  });

  final bool enabled;
  final int delayValue;
  final WaOilFollowupDelayUnit delayUnit;
  final WaFollowupTemplateUiStatus templateStatus;
  final bool schemaMissing;
}

class WaOilFollowupService {
  WaOilFollowupService._();

  static final WaOilFollowupService instance = WaOilFollowupService._();

  SupabaseClient get _client => Supabase.instance.client;

  String? get _uid => _client.auth.currentUser?.id;

  Future<WaOilFollowupSnapshot> load({bool isOfficialTransport = true}) async {
    final uid = _uid;
    if (uid == null) {
      return WaOilFollowupSnapshot(
        rule: WaOilFollowupRule.defaults(),
        templateStatus: WaFollowupTemplateUiStatus.none,
        isOfficialTransport: isOfficialTransport,
      );
    }

    try {
      final ruleRow = await _client
          .from('wa_oil_followup_rules')
          .select()
          .eq('tenant_user_id', uid)
          .maybeSingle();

      var rule = ruleRow != null
          ? WaOilFollowupRule.fromMap(Map<String, dynamic>.from(ruleRow))
          : WaOilFollowupRule.defaults();
      rule = WaOilFollowupRule(
        enabled: rule.enabled,
        delayValue: rule.delayValue,
        delayUnit: rule.delayUnit,
        quietHours: rule.quietHours,
        bodyTemplate: WaOilFollowupCopy.ensureDefault(
          rule.bodyTemplate,
          rule.delayUnit,
        ),
      );

      final tplRows = await _client
          .from('tenant_whatsapp_templates')
          .select('status, last_error, template_key')
          .eq('tenant_user_id', uid)
          .eq('template_key', 'oil_change_followup');

      String? lastErr;
      var tplStatus = WaFollowupTemplateUiStatus.none;
      if (!isOfficialTransport) {
        tplStatus = WaFollowupTemplateUiStatus.qrReady;
      } else if (tplRows is List && tplRows.isNotEmpty) {
        final row = Map<String, dynamic>.from(tplRows.first as Map);
        lastErr = row['last_error']?.toString();
        tplStatus = _mapTemplateStatus(row['status']?.toString());
      } else if (rule.bodyTemplate.trim().isNotEmpty) {
        tplStatus = WaFollowupTemplateUiStatus.draft;
      }

      final jobsRaw = await _client
          .from('wa_oil_followup_jobs')
          .select()
          .eq('tenant_user_id', uid)
          .inFilter('status', ['queued', 'sending', 'skipped_no_wallet', 'skipped_no_template'])
          .order('due_at', ascending: true)
          .limit(5);

      final jobs = (jobsRaw as List<dynamic>)
          .map((e) => WaOilFollowupJob.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();

      return WaOilFollowupSnapshot(
        rule: rule,
        templateStatus: tplStatus,
        templateLastError: lastErr,
        upcoming: jobs,
        isOfficialTransport: isOfficialTransport,
      );
    } on PostgrestException catch (e) {
      if (_isMissingSchema(e)) {
        return WaOilFollowupSnapshot(
          rule: WaOilFollowupRule.defaults(),
          templateStatus: WaFollowupTemplateUiStatus.none,
          schemaMissing: true,
          isOfficialTransport: isOfficialTransport,
        );
      }
      rethrow;
    }
  }

  Future<WaOilFollowupSummary> loadSummary({bool isOfficialTransport = true}) async {
    final snap = await load(isOfficialTransport: isOfficialTransport);
    return WaOilFollowupSummary(
      enabled: snap.rule.enabled,
      delayValue: snap.rule.delayValue,
      delayUnit: snap.rule.delayUnit,
      templateStatus: snap.templateStatus,
      schemaMissing: snap.schemaMissing,
    );
  }

  Future<void> saveRule(WaOilFollowupRule rule) async {
    final uid = _uid;
    if (uid == null) throw StateError('not_authenticated');
    final r = rule.clampDelay();
    await _client.from('wa_oil_followup_rules').upsert({
      'tenant_user_id': uid,
      ...r.toRow(),
    });
    if (!r.enabled) {
      try {
        await _client.rpc('wa_followup_cancel_pending');
      } catch (_) {}
    }
  }

  Future<({bool ok, String? messageAr})> submitTemplateToMeta(
    String bodyTemplate,
  ) async {
    if (WaOilFollowupCopy.hasInvalidBraceSyntax(bodyTemplate)) {
      return (
        ok: false,
        messageAr: 'استخدم الأزرار فوق الصندوق لإضافة اسم الزبون والسيارة.',
      );
    }
    if (WaOilFollowupCopy.renderedLength(bodyTemplate) > 600) {
      return (
        ok: false,
        messageAr: 'النص طويل على واتساب الرسمي. اختصر تحت 600 حرف.',
      );
    }
    final res = await OilChangeWhatsappGatewayService.instance
        .submitFollowupTemplate(bodyTemplate);
    return (ok: res.ok, messageAr: res.messageAr);
  }

  WaFollowupTemplateUiStatus _mapTemplateStatus(String? st) {
    switch (st) {
      case 'approved':
        return WaFollowupTemplateUiStatus.approved;
      case 'pending':
        return WaFollowupTemplateUiStatus.pending;
      case 'rejected':
        return WaFollowupTemplateUiStatus.rejected;
      default:
        return WaFollowupTemplateUiStatus.draft;
    }
  }

  bool _isMissingSchema(PostgrestException e) {
    final m = e.message.toLowerCase();
    return e.code == '42P01' ||
        m.contains('wa_oil_followup') ||
        m.contains('does not exist');
  }
}
