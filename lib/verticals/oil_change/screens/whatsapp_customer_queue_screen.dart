import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../assistant/exec/assistant_prefill.dart';
import '../../../navigation/content_navigation.dart';
import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';
import '../services/whatsapp_responder_repository.dart';
import '../widgets/oil_change_form_theme.dart';
import 'oil_change_form_screen.dart';

/// زبائن ينتظرون رد المحل (ق84) وزبائن قادمون (ق85) من مجيب واتساب.
class WhatsappCustomerQueueScreen extends StatefulWidget {
  const WhatsappCustomerQueueScreen({super.key, this.repository});

  final WhatsappResponderRepository? repository;

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      FastContentPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const WhatsappCustomerQueueScreen(),
      ),
    );
  }

  @override
  State<WhatsappCustomerQueueScreen> createState() => _WhatsappCustomerQueueScreenState();
}

class _WhatsappCustomerQueueScreenState extends State<WhatsappCustomerQueueScreen> {
  late final WhatsappResponderRepository _repo = widget.repository ?? WhatsappResponderRepository.instance;
  List<WhatsappHandoff> _waiting = const [];
  List<WhatsappVisitRequest> _visits = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await Future.wait([_repo.openHandoffs(), _repo.openVisits()]);
    if (!mounted) return;
    setState(() {
      _waiting = r[0] as List<WhatsappHandoff>;
      _visits = r[1] as List<WhatsappVisitRequest>;
      _loading = false;
    });
  }

  Future<void> _run(Future<void> Function() f, String done) async {
    setState(() => _busy = true);
    try {
      await f();
      _snack(done);
      await _load();
    } catch (_) {
      _snack('تعذّر التنفيذ. تأكد من الاتصال.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _openChat(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final ok = await launchUrl(Uri.parse('https://wa.me/$digits'), mode: LaunchMode.externalApplication);
    if (!ok) _snack('تعذّر فتح واتساب');
  }

  /// بطاقة غيار معبّأة بالاسم والرقم والسيارة. تُغلق الزيارة إن حُفظت بطاقة.
  Future<void> _openCard(WhatsappVisitRequest v) async {
    final since = DateTime.now().toIso8601String();
    final prefill = AssistantPrefill(tool: 'prepare_oil_card', values: {
      if (v.name.isNotEmpty) 'customer': v.name,
      'phone': _localPhone(v.phone),
      if (v.car.isNotEmpty) 'car': v.car,
    });
    await Navigator.of(context).push<void>(
      contentMaterialRoute<void>(
        routeId: AppContentRoutes.oilChangeCreate,
        breadcrumbTitle: 'بطاقة غيار زيت جديدة',
        builder: (_) => OilChangeFormScreen(key: UniqueKey(), assistantPrefill: prefill),
      ),
    );
    if (!mounted || !await _cardSavedSince(since)) return;
    await _run(() => _repo.closeVisit(v.id, carded: true), 'فُتحت له بطاقة');
  }

  static Future<bool> _cardSavedSince(String since) async {
    try {
      final t = TenantContextService.instance;
      if (!t.loaded) await t.load();
      final db = await DatabaseHelper().database;
      final rows = await db.query(
        'service_orders',
        columns: ['id'],
        where: 'tenantId = ? AND createdAt >= ?',
        whereArgs: [t.requireActiveTenantId(), since],
        limit: 1,
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 9647701234567 ← 07701234567: الرقم كما يكتبه المحل في البطاقة.
  static String _localPhone(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    return d.startsWith('964') && d.length > 10 ? '0${d.substring(3)}' : d;
  }

  static String _ago(DateTime t) {
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 1) return 'الآن';
    if (m < 60) return 'قبل $m دقيقة';
    if (m < 24 * 60) return 'قبل ${m ~/ 60} ساعة';
    return 'قبل ${m ~/ (24 * 60)} يوم';
  }

  @override
  Widget build(BuildContext context) {
    final muted = OilChangeFormTheme.secondaryText(context);
    return Theme(
      data: OilChangeFormTheme.wrap(context, Theme.of(context)),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: OilChangeFormTheme.appBar(
            context: context,
            title: 'زبائن واتساب',
            actions: [
              IconButton(
                tooltip: 'تحديث',
                onPressed: _loading ? null : () => unawaited(_load()),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
                    children: [
                      _Header('ينتظرون ردكم (${_waiting.length})',
                          'المجيب ساكت في محادثاتهم حتى تردّوا أو تنتهي المدة.'),
                      if (_waiting.isEmpty) _Empty('لا أحد ينتظر الآن.', muted),
                      for (final h in _waiting)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${h.reasonLabel} · ${_ago(h.startedAt)}', style: TextStyle(color: muted)),
                                const SizedBox(height: 4),
                                Text(h.question.isEmpty ? '—' : h.question),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: () => unawaited(_openChat(h.phone)),
                                      icon: const Icon(Icons.chat_rounded),
                                      label: const Text('افتح المحادثة'),
                                    ),
                                    OutlinedButton(
                                      onPressed: _busy
                                          ? null
                                          : () => unawaited(_run(() => _repo.endHandoff(h.id), 'رجع المجيب يرد عليه')),
                                      child: const Text('رددتُ عليه'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _Header('زبائن قادمون (${_visits.length})',
                          'طلبوا الزيارة من واتساب. الطلب يُغلق حين تُفتح له بطاقة أو بعد 3 أيام.'),
                      if (_visits.isEmpty) _Empty('لا طلبات زيارة الآن.', muted),
                      for (final v in _visits)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  [if (v.name.isNotEmpty) v.name, if (v.car.isNotEmpty) v.car, _ago(v.createdAt)]
                                      .join(' · '),
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                if (v.request.isNotEmpty) ...[const SizedBox(height: 4), Text(v.request)],
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: _busy ? null : () => unawaited(_openCard(v)),
                                      icon: const Icon(Icons.oil_barrel_rounded),
                                      label: const Text('افتح بطاقة'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () => unawaited(_openChat(v.phone)),
                                      child: const Text('المحادثة'),
                                    ),
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => unawaited(_run(() => _repo.closeVisit(v.id, carded: false), 'أُغلق الطلب')),
                                      child: const Text('أغلق'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          Text(subtitle, style: TextStyle(color: OilChangeFormTheme.secondaryText(context))),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(text, style: TextStyle(color: color)));
}
