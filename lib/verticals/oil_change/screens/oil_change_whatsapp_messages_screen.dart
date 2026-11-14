import 'dart:async';
import 'dart:ui' as ui show TextDirection;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../services/oil_change_whatsapp_delivery_reconcile.dart';
import '../services/oil_change_whatsapp_gateway_service.dart';
import '../services/oil_change_whatsapp_messages_repository.dart';
import '../services/oil_change_whatsapp_outbox.dart';
import '../utils/whatsapp_failure_reason_ar.dart';
import '../widgets/oil_change_form_theme.dart';
import '../widgets/oil_change_whatsapp_outbox_view.dart';
import '../../../navigation/content_navigation.dart';

/// رسائل واتساب: تم الإرسال / لم يتم الإرسال (قسم جهاز + قسم سحابة).
class OilChangeWhatsappMessagesScreen extends StatefulWidget {
  const OilChangeWhatsappMessagesScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      FastContentPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const OilChangeWhatsappMessagesScreen(),
      ),
    );
  }

  @override
  State<OilChangeWhatsappMessagesScreen> createState() =>
      _OilChangeWhatsappMessagesScreenState();
}

class _OilChangeWhatsappMessagesScreenState
    extends State<OilChangeWhatsappMessagesScreen>
    with SingleTickerProviderStateMixin {
  final _outboxKey = GlobalKey<OilChangeWhatsappOutboxViewState>();
  late final TabController _tabController =
      TabController(length: 2, vsync: this);
  int _pendingCount = 0;

  final _repo = OilChangeWhatsappMessagesRepository.instance;
  final _sentScroll = ScrollController();
  final _failedScroll = ScrollController();
  final _dateFormat = DateFormat('d MMMM · h:mm a', 'ar_SA');
  final _uuid = const Uuid();

  final List<OilChangeMessageLogEntry> _sentEntries = [];
  final List<OilChangeMessageLogEntry> _failedEntries = [];
  bool _sentLoading = true;
  bool _failedLoading = true;
  bool _sentLoadingMore = false;
  bool _failedLoadingMore = false;
  bool _sentHasMore = true;
  bool _failedHasMore = true;
  Object? _sentError;
  Object? _failedError;
  String? _resendingId;
  bool _sendingAllCloud = false;
  /// attempt_id ثابت لكل سجل أثناء إعادة المحاولة (HTTP retry آمن).
  final Map<String, String> _attemptIds = {};

  @override
  void initState() {
    super.initState();
    _sentScroll.addListener(_onSentScroll);
    _failedScroll.addListener(_onFailedScroll);
    unawaited(_reloadAll());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _sentScroll.dispose();
    _failedScroll.dispose();
    super.dispose();
  }

  Future<void> _refreshPendingCount() async {
    final count = await OilChangeWhatsappOutbox.instance.totalNotSentCount();
    if (!mounted) return;
    setState(() => _pendingCount = count);
  }

  void _onSentScroll() {
    if (!_sentScroll.hasClients) return;
    if (_sentScroll.position.pixels >=
        _sentScroll.position.maxScrollExtent - 240) {
      unawaited(_loadMoreSent());
    }
  }

  void _onFailedScroll() {
    if (!_failedScroll.hasClients) return;
    if (_failedScroll.position.pixels >=
        _failedScroll.position.maxScrollExtent - 240) {
      unawaited(_loadMoreFailed());
    }
  }

  Future<void> _reloadAll() async {
    await OilChangeWhatsappDeliveryReconcile.discardProvenOutbox();
    await Future.wait([
      _reloadSent(),
      _reloadFailed(),
      _outboxKey.currentState?.reload() ?? Future<void>.value(),
      _refreshPendingCount(),
    ]);
  }

  Future<void> _reloadSent() async {
    setState(() {
      _sentLoading = true;
      _sentError = null;
    });
    try {
      final rows = await _repo.loadPage(
        bucket: OilChangeMessagesBucket.sent,
      );
      if (!mounted) return;
      setState(() {
        _sentEntries
          ..clear()
          ..addAll(rows);
        _sentHasMore =
            rows.length >= OilChangeWhatsappMessagesRepository.pageSize;
        _sentLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sentError = e;
        _sentLoading = false;
      });
    }
  }

  Future<void> _reloadFailed() async {
    setState(() {
      _failedLoading = true;
      _failedError = null;
    });
    try {
      final rows = await _repo.loadPage(
        bucket: OilChangeMessagesBucket.notSent,
      );
      final hidden = await OilChangeWhatsappDeliveryReconcile
          .dismissProvenFailedTwins(rows);
      final visible =
          rows.where((row) => !hidden.contains(row.id)).toList();
      if (!mounted) return;
      setState(() {
        _failedEntries
          ..clear()
          ..addAll(visible);
        _failedHasMore =
            rows.length >= OilChangeWhatsappMessagesRepository.pageSize;
        _failedLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failedError = e;
        _failedLoading = false;
      });
    }
  }

  Future<void> _loadMoreSent() async {
    if (_sentLoadingMore || !_sentHasMore || _sentLoading || _sentEntries.isEmpty) {
      return;
    }
    setState(() => _sentLoadingMore = true);
    try {
      final rows = await _repo.loadPage(
        bucket: OilChangeMessagesBucket.sent,
        beforeCreatedAt: _sentEntries.last.createdAt,
      );
      if (!mounted) return;
      setState(() {
        _sentEntries.addAll(rows);
        _sentHasMore =
            rows.length >= OilChangeWhatsappMessagesRepository.pageSize;
        _sentLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _sentLoadingMore = false);
    }
  }

  Future<void> _loadMoreFailed() async {
    if (_failedLoadingMore ||
        !_failedHasMore ||
        _failedLoading ||
        _failedEntries.isEmpty) {
      return;
    }
    setState(() => _failedLoadingMore = true);
    try {
      final rows = await _repo.loadPage(
        bucket: OilChangeMessagesBucket.notSent,
        beforeCreatedAt: _failedEntries.last.createdAt,
      );
      final hidden = await OilChangeWhatsappDeliveryReconcile
          .dismissProvenFailedTwins(rows);
      final visible =
          rows.where((row) => !hidden.contains(row.id)).toList();
      if (!mounted) return;
      setState(() {
        _failedEntries.addAll(visible);
        _failedHasMore =
            rows.length >= OilChangeWhatsappMessagesRepository.pageSize;
        _failedLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failedLoadingMore = false);
    }
  }

  bool _canResendEntry(OilChangeMessageLogEntry entry) {
    if (!entry.status.isFailure || !entry.canResend) return false;
    final parsed = WhatsappFailureReasonAr.parse(entry.error);
    return WhatsappFailureReasonAr.cloudCanShowResend(
      statusFailed: true,
      hasContent: entry.canResend,
      code: parsed.code,
      retryableFromServer: parsed.retryable,
    );
  }

  List<OilChangeMessageLogEntry> get _resendableFailed =>
      _failedEntries.where(_canResendEntry).toList();

  Future<bool> _resendCloudEntry(OilChangeMessageLogEntry entry) async {
    if (!_canResendEntry(entry)) return false;

    final attemptId = _attemptIds.putIfAbsent(entry.id, () => _uuid.v4());
    final orderId = int.tryParse(entry.orderRef.trim());
    final result =
        await OilChangeWhatsappGatewayService.instance.sendOilChangeCard(
      customerPhone: entry.toPhone,
      customerName: entry.customerName,
      shopName: entry.cardPayload['shop'] ?? '',
      detailsBlock: entry.body.trim().isNotEmpty
          ? entry.body
          : (entry.cardPayload['details'] ?? ''),
      templateParams: entry.cardPayload,
      orderId: (orderId != null && orderId > 0) ? orderId : null,
      employeeName: entry.employeeName,
      resend: true,
      attemptId: attemptId,
      originalLogId: entry.id,
    );

    if (result.ok) {
      _attemptIds.remove(entry.id);
      if (mounted) {
        setState(() {
          _failedEntries.removeWhere((e) => e.id == entry.id);
          if (_pendingCount > 0) _pendingCount -= 1;
        });
      }
      return true;
    }

    // فشل غامض (قد تكون Meta قبلت الرسالة): أبقِ نفس attempt_id لتفادي خصم مزدوج.
    if (!_isAmbiguousGatewayFailure(result)) {
      _attemptIds[entry.id] = _uuid.v4();
    }
    return false;
  }

  bool _isAmbiguousGatewayFailure(WhatsappGatewaySendResult result) {
    final blob = '${result.reason} ${result.detail}'.toLowerCase();
    return blob.contains('timeout') ||
        blob.contains('gateway_unreachable') ||
        blob.contains('invoke_null') ||
        blob.contains('empty_response') ||
        blob.contains('client_timeout');
  }

  Future<void> _resendAllCloud() async {
    if (_sendingAllCloud || _resendingId != null) return;
    // حمّل المزيد حتى تُغطّى الصفحة الحالية قدر الإمكان قبل الإرسال الجماعي.
    while (_failedHasMore && !_failedLoading && mounted) {
      final before = _failedEntries.length;
      await _loadMoreFailed();
      if (_failedEntries.length <= before) break;
    }
    final queue = _resendableFailed;
    if (queue.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد رسائل قابلة لإعادة الإرسال في هذه القائمة'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إرسال الكل'),
        content: Text(
          'سيتم إعادة إرسال ${queue.length} رسالة فاشلة قابلة للإعادة.\n'
          'الرسائل ذات الرقم غير الصالح تُتخطّى.',
          textAlign: TextAlign.start,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إرسال الكل'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _sendingAllCloud = true);
    var sent = 0;
    var failed = 0;
    for (final entry in List<OilChangeMessageLogEntry>.of(queue)) {
      if (!mounted) break;
      // قد تكون أُزيلت أثناء الحلقة.
      if (!_failedEntries.any((e) => e.id == entry.id)) continue;
      setState(() => _resendingId = entry.id);
      final ok = await _resendCloudEntry(entry);
      if (ok) {
        sent++;
      } else {
        failed++;
      }
      // فاصل بسيط يقلل ضغط Meta عند الإرسال المتتابع.
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }

    if (!mounted) return;
    setState(() {
      _resendingId = null;
      _sendingAllCloud = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? 'أُرسلت $sent رسالة'
              : 'أُرسلت $sent، وبقيت $failed لم تُرسل',
        ),
      ),
    );
    await _reloadAll();
  }

  Future<void> _dismissCloud(OilChangeMessageLogEntry entry) async {
    if (_resendingId != null || _sendingAllCloud) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إسقاط الرسالة'),
        content: const Text(
          'لن تُرسل هذه الرسالة. تُخفى من القائمة فقط — البطاقة في السجل تبقى كما هي.',
          textAlign: TextAlign.start,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إسقاط'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resendingId = entry.id);
    final result =
        await OilChangeWhatsappGatewayService.instance.dismissFailedMessage(
      logId: entry.id,
    );
    if (!mounted) return;
    setState(() => _resendingId = null);

    if (result.ok) {
      setState(() {
        _failedEntries.removeWhere((e) => e.id == entry.id);
        if (_pendingCount > 0) _pendingCount -= 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.messageAr ?? 'تم إسقاط الرسالة من القائمة'),
        ),
      );
      await _refreshPendingCount();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.messageAr ?? 'تعذّر إسقاط الرسالة'),
        ),
      );
      await _reloadFailed();
    }
  }

  Future<void> _showMessageDetail(OilChangeMessageLogEntry entry) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final failure = entry.status.isFailure
        ? WhatsappFailureReasonAr.parse(entry.error)
        : null;
    final canResend = entry.status.isFailure &&
        failure != null &&
        WhatsappFailureReasonAr.cloudCanShowResend(
          statusFailed: true,
          hasContent: entry.canResend,
          code: failure.code,
          retryableFromServer: failure.retryable,
        );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: ui.TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: 20,
                end: 20,
                top: 12,
                bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.outlineVariant,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'تفاصيل الرسالة',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.start,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatusBadge(status: entry.status),
                        if (failure != null &&
                            failure.sourceBadgeAr.isNotEmpty)
                          _SourceBadge(label: failure.sourceBadgeAr),
                        Chip(
                          label: Text(_kindAr(entry)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _DetailRow(
                      label: 'الزبون',
                      value: entry.customerName.isEmpty
                          ? '—'
                          : entry.customerName,
                    ),
                    _DetailRow(label: 'رقم الهاتف', value: entry.toPhone),
                    if (entry.employeeName.isNotEmpty)
                      _DetailRow(label: 'الفني', value: entry.employeeName),
                    if (entry.orderRef.isNotEmpty)
                      _DetailRow(label: 'رقم البطاقة', value: entry.orderRef),
                    _DetailRow(
                      label: 'الوقت',
                      value: _dateFormat.format(entry.createdAt),
                    ),
                    if (failure != null) ...[
                      const SizedBox(height: 8),
                      _DetailRow(
                        label: 'السبب',
                        value: failure.messageAr,
                        emphasize: true,
                      ),
                      if (failure.fixAr.isNotEmpty)
                        _DetailRow(label: 'الحل', value: failure.fixAr),
                      if (failure.code.isNotEmpty && failure.code != 'unknown')
                        _DetailRow(label: 'رمز الخطأ', value: failure.code),
                    ],
                    if (entry.body.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'نص الرسالة',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.start,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.55,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cs.outline.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          entry.body.trim(),
                          textAlign: TextAlign.start,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (canResend)
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          unawaited(_resendCloud(entry));
                        },
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('إعادة الإرسال'),
                      ),
                    if (canResend) const SizedBox(height: 8),
                    if (entry.status.isFailure)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          unawaited(_dismissCloud(entry));
                        },
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('إسقاط من القائمة'),
                      ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إغلاق'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _resendCloud(OilChangeMessageLogEntry entry) async {
    if (!_canResendEntry(entry)) return;
    if (_resendingId != null || _sendingAllCloud) return;

    setState(() => _resendingId = entry.id);
    final ok = await _resendCloudEntry(entry);
    if (!mounted) return;
    setState(() => _resendingId = null);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أُعيد إرسال الرسالة')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      await _reloadAll();
      if (mounted) {
        setState(() {
          _failedEntries.removeWhere((e) => e.id == entry.id);
        });
        await _refreshPendingCount();
      }
    } else {
      final reason = WhatsappFailureReasonAr.parse(entry.error).messageAr;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reason)),
      );
      await _reloadFailed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final notSentLabel = _pendingCount > 0
        ? 'لم يتم الإرسال ($_pendingCount)'
        : 'لم يتم الإرسال';

    return Scaffold(
      appBar: OilChangeFormTheme.appBar(
        context: context,
        title: 'رسائل واتساب',
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: (_sentLoading || _failedLoading)
                ? null
                : () => unawaited(_reloadAll()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: [
              const Tab(text: 'تم الإرسال'),
              Tab(text: notSentLabel),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSentTab(),
                _buildNotSentTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentTab() {
    if (_sentLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sentError != null) {
      return _ErrorState(onRetry: () => unawaited(_reloadSent()));
    }
    if (_sentEntries.isEmpty) {
      return const _EmptyState(
        title: 'لا رسائل مُرسلة بعد',
        body: 'هنا تظهر الرسائل التي قبلتها Meta أو وصلت للزبون.',
      );
    }
    return RefreshIndicator(
      onRefresh: _reloadSent,
      child: ListView.separated(
        controller: _sentScroll,
        padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 28),
        itemCount: _sentEntries.length + (_sentLoadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= _sentEntries.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _buildCloudTile(_sentEntries[index], showResend: false);
        },
      ),
    );
  }

  Widget _buildNotSentTab() {
    return RefreshIndicator(
      onRefresh: () async {
        await _reloadFailed();
        await _outboxKey.currentState?.reload();
        await _refreshPendingCount();
      },
      child: CustomScrollView(
        controller: _failedScroll,
        slivers: [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(16, 14, 16, 6),
              child: Text(
                'معلّقة على الجهاز',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                textAlign: TextAlign.start,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: OilChangeWhatsappOutboxView(
              key: _outboxKey,
              onChanged: () => unawaited(_refreshPendingCount()),
              embedInParentScroll: true,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'فاشلة في السحابة',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.start,
                    ),
                  ),
                  if (_failedEntries.isNotEmpty)
                    FilledButton.icon(
                      onPressed: (_sendingAllCloud ||
                              _resendingId != null ||
                              _failedLoading)
                          ? null
                          : () => unawaited(_resendAllCloud()),
                      icon: _sendingAllCloud
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        _sendingAllCloud ? 'جاري الإرسال…' : 'إرسال الكل',
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_failedLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_failedError != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _ErrorState(onRetry: () => unawaited(_reloadFailed())),
            )
          else if (_failedEntries.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(24, 12, 24, 24),
                child: Text(
                  'لا توجد رسائل فاشلة في السحابة.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 28),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= _failedEntries.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: 8),
                      child: _buildCloudTile(
                        _failedEntries[index],
                        showResend: true,
                      ),
                    );
                  },
                  childCount:
                      _failedEntries.length + (_failedLoadingMore ? 1 : 0),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCloudTile(
    OilChangeMessageLogEntry entry, {
    required bool showResend,
  }) {
    final theme = Theme.of(context);
    final name = entry.customerName;
    final title = name.isNotEmpty ? '$name · ${entry.toPhone}' : entry.toPhone;
    final failure = entry.status.isFailure
        ? WhatsappFailureReasonAr.parse(entry.error)
        : null;
    final canResend = showResend &&
        failure != null &&
        WhatsappFailureReasonAr.cloudCanShowResend(
          statusFailed: true,
          hasContent: entry.canResend,
          code: failure.code,
          retryableFromServer: failure.retryable,
        );
    final busy = _resendingId == entry.id || _sendingAllCloud;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: entry.status.isFailure
              ? theme.colorScheme.error.withValues(alpha: 0.55)
              : theme.dividerColor,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => unawaited(_showMessageDetail(entry)),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusBadge(status: entry.status),
                  if (failure != null && failure.sourceBadgeAr.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _SourceBadge(label: failure.sourceBadgeAr),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      textAlign: TextAlign.start,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.chevron_left_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${_kindAr(entry)} · ${_dateFormat.format(entry.createdAt)}'
                '${entry.employeeName.isNotEmpty ? ' · الفني: ${entry.employeeName}' : ''}',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.start,
              ),
              if (entry.status.isFailure) ...[
                const SizedBox(height: 6),
                Text(
                  'السبب: ${failure?.messageAr ?? WhatsappFailureReasonAr.unknownAr}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.start,
                ),
                if (failure != null &&
                    failure.code.isNotEmpty &&
                    failure.code != 'unknown') ...[
                  const SizedBox(height: 2),
                  Text(
                    'رمز الخطأ: ${failure.code}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.start,
                  ),
                ],
                if (failure != null && failure.fixAr.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'الحل: ${failure.fixAr}',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.start,
                  ),
                ],
              ],
              if (entry.body.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  entry.body.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.start,
                ),
              ],
              if (entry.status.isFailure) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    TextButton(
                      onPressed:
                          busy ? null : () => unawaited(_dismissCloud(entry)),
                      child: const Text('إسقاط'),
                    ),
                    if (canResend)
                      FilledButton.tonal(
                        onPressed: busy
                            ? null
                            : () => unawaited(_resendCloud(entry)),
                        child: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('إعادة الإرسال'),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  String _kindAr(OilChangeMessageLogEntry entry) {
    if (entry.isOilChangeCard) return 'بطاقة غيار';
    if (entry.isAutoReply) return 'رد تلقائي';
    return 'رسالة';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.start,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                color: emphasize ? cs.error : cs.onSurface,
              ),
              textAlign: TextAlign.start,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 3, 8, 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final OilChangeMessageStatus status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (Color color, IconData icon) = switch (status) {
      OilChangeMessageStatus.failed => (cs.error, Icons.error_outline_rounded),
      OilChangeMessageStatus.sent => (cs.outline, Icons.check_rounded),
      OilChangeMessageStatus.delivered => (cs.primary, Icons.done_all_rounded),
      OilChangeMessageStatus.read => (Colors.green, Icons.done_all_rounded),
      OilChangeMessageStatus.unknown => (cs.outline, Icons.help_outline_rounded),
    };

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            status.labelAr,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 40),
        Icon(
          Icons.forum_outlined,
          size: 56,
          color: Theme.of(context).hintColor,
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'تعذّر تحميل الرسائل',
              style: TextStyle(fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
          ],
        ),
      ),
    );
  }
}
