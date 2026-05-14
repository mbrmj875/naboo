import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/invoice.dart';
import '../../navigation/content_navigation.dart';
import '../../providers/sale_draft_provider.dart';
import '../../services/service_orders_repository.dart';
import '../../utils/app_logger.dart';
import '../../utils/iqd_money.dart';
import '../../utils/iraqi_currency_format.dart';
import '../invoices/add_invoice_screen.dart';
import 'service_order_detail_screen.dart';
import 'service_order_form_screen.dart';

class ServiceOrdersHubScreen extends StatefulWidget {
  const ServiceOrdersHubScreen({super.key});

  @override
  State<ServiceOrdersHubScreen> createState() => _ServiceOrdersHubScreenState();
}

class _ServiceOrdersHubScreenState extends State<ServiceOrdersHubScreen>
    with TickerProviderStateMixin {
  static const _tabs = <_ServiceStatusTab>[
    _ServiceStatusTab('pending', 'معلقة', Color(0xFFEF4444)),
    _ServiceStatusTab('in_progress', 'قيد العمل', Color(0xFFF59E0B)),
    _ServiceStatusTab('completed', 'جاهزة للتسليم', Color(0xFF22C55E)),
    _ServiceStatusTab('delivered', 'مسلّمة', Color(0xFF64748B)),
  ];

  late final TabController _tab;
  final TextEditingController _search = TextEditingController();
  Timer? _tick;
  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _rows = const [];
  /// معرّف التذكرة أثناء `_convertToInvoice` (زر أو أيقونة) لمنع النقر المزدوج وإظهار التحميل.
  int? _convertingOrderId;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
    _tab.addListener(() {
      if (_tab.indexIsChanging) return;
      unawaited(_load());
    });
    _search.addListener(() => setState(() {}));
    unawaited(_load());
    // عداد حي: تحديث كل ثانية في تبويب "قيد العمل".
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_tabs[_tab.index].status == 'in_progress') {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _search.dispose();
    _tab.dispose();
    super.dispose();
  }

  static int _partsTotalFils(Map<String, dynamic> r) =>
      (r['partsTotalFils'] as num?)?.toInt() ?? 0;

  static int _remainingFils(Map<String, dynamic> r) {
    final estF = (r['estimatedPriceFils'] as num?)?.toInt() ?? 0;
    final advF = (r['advancePaymentFils'] as num?)?.toInt() ?? 0;
    final agreedF = (r['agreedPriceFils'] as num?)?.toInt();
    final serviceF = agreedF ?? estF;
    final total = serviceF + _partsTotalFils(r);
    final rem = total - advF;
    return rem < 0 ? 0 : rem;
  }

  static DateTime? _workStartedUtc(Map<String, dynamic> r) {
    final ws = (r['workStartedAt'] ?? '').toString().trim();
    if (ws.isEmpty) return null;
    return DateTime.tryParse(ws)?.toUtc();
  }

  static DateTime? _deadlineUtc(Map<String, dynamic> r) {
    final pd = (r['promisedDeliveryAt'] ?? '').toString().trim();
    if (pd.isNotEmpty) {
      final t = DateTime.tryParse(pd)?.toUtc();
      if (t != null) return t;
    }
    final started = _workStartedUtc(r);
    if (started == null) return null;
    final mins = (r['expectedDurationMinutes'] as num?)?.toInt() ?? 0;
    if (mins <= 0) return null;
    return started.add(Duration(minutes: mins));
  }

  static bool _isOverdue(Map<String, dynamic> r) {
    if ((r['status'] ?? '').toString() != 'in_progress') return false;
    final t = _deadlineUtc(r);
    if (t == null) return false;
    return DateTime.now().toUtc().isAfter(t);
  }

  static String _twoDigits(int v) => v.toString().padLeft(2, '0');

  static String? _countdownTimerText(Map<String, dynamic> r) {
    if ((r['status'] ?? '').toString() != 'in_progress') return null;
    final now = DateTime.now().toUtc();
    final deadline = _deadlineUtc(r);
    if (deadline != null) {
      final diff = deadline.difference(now);
      if (diff.isNegative) {
        final late = now.difference(deadline);
        final total = late.inSeconds;
        final h = total ~/ 3600;
        final m = (total % 3600) ~/ 60;
        final s = total % 60;
        return '+${_twoDigits(h)}:${_twoDigits(m)}:${_twoDigits(s)}';
      }
      final total = diff.inSeconds;
      final h = total ~/ 3600;
      final m = (total % 3600) ~/ 60;
      final s = total % 60;
      return '${_twoDigits(h)}:${_twoDigits(m)}:${_twoDigits(s)}';
    }
    final started = _workStartedUtc(r);
    if (started == null) return null;
    final elapsed = now.difference(started);
    final total = elapsed.isNegative ? 0 : elapsed.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    return '${_twoDigits(h)}:${_twoDigits(m)}:${_twoDigits(s)}';
  }

  static String _timerPrefix(Map<String, dynamic> r) {
    final deadline = _deadlineUtc(r);
    if (deadline == null) return 'منذ البدء';
    if (_isOverdue(r)) return 'متأخر';
    return 'الوقت المتبقي';
  }

  /// تلميح عربي قصير يُعرض للمستخدم عند فشل التحميل (بدون تسريب تفاصيل تقنية).
  String _loadErrorHint(Object? err) {
    if (err == null) return '';
    final s = err.toString().toLowerCase();
    if (s.contains('tenantcontextservice') ||
        s.contains('مستأجر') ||
        s.contains('tenant')) {
      return 'جرّب تسجيل الخروج ثم الدخول، أو أعد تشغيل التطبيق.';
    }
    if (s.contains('no such column') ||
        s.contains('no such table') ||
        s.contains('sqlite')) {
      return 'أعد تشغيل التطبيق لإكمال تهيئة قاعدة البيانات.';
    }
    if (s.contains('subtype') ||
        s.contains('type \'') ||
        s.contains('is not a subtype')) {
      return 'بيانات محلية غير متوقعة؛ أعد تشغيل التطبيق. إن تكرّر ذلك، أبلغ الدعم.';
    }
    if (s.contains('database is locked') || s.contains('locked')) {
      return 'قاعدة البيانات مشغولة؛ انتظر ثوانٍ ثم أعد المحاولة.';
    }
    return 'إن استمرّت المشكلة، أعد تشغيل التطبيق.';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = _tabs[_tab.index].status;
      final rows = await ServiceOrdersRepository.instance.getServiceOrders(
        status: status,
        limit: 250,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      AppLogger.error('service_orders_hub', 'load failed', e);
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      contentMaterialRoute(
        routeId: AppContentRoutes.serviceOrdersCreate,
        breadcrumbTitle: 'تذكرة صيانة جديدة',
        builder: (_) => const ServiceOrderFormScreen(),
      ),
    );
    if (!mounted) return;
    if (created == true) {
      unawaited(_load());
    }
  }

  String _statusLabel(String status) {
    for (final t in _tabs) {
      if (t.status == status) return t.label;
    }
    return status;
  }

  Color _statusColor(String status) {
    for (final t in _tabs) {
      if (t.status == status) return t.color;
    }
    return const Color(0xFF64748B);
  }

  bool _matchesSearch(Map<String, dynamic> r, String q) {
    final s = q.trim();
    if (s.isEmpty) return true;
    final v = s.toLowerCase();
    final a = (r['customerNameSnapshot'] ?? '').toString().toLowerCase();
    final b = (r['deviceName'] ?? '').toString().toLowerCase();
    final c = (r['deviceSerial'] ?? '').toString().toLowerCase();
    final gid = (r['global_id'] ?? r['globalId'] ?? '').toString().toLowerCase();
    return a.contains(v) || b.contains(v) || c.contains(v) || gid.contains(v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _search.text;
    final filtered = _rows.where((r) => _matchesSearch(r, q)).toList(growable: false);

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 10),
              Text(
                'تعذر تحميل التذاكر.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                textAlign: TextAlign.center,
              ),
              if (_loadErrorHint(_error).isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _loadErrorHint(_error),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (kDebugMode && _error != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  child: Text(
                    'تفاصيل تقنية (Debug): ${_error.toString()}',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.start,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _load,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    } else if (filtered.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            q.trim().isEmpty ? 'لا توجد تذاكر في هذا التبويب.' : 'لا نتائج مطابقة.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 90),
          itemCount: filtered.length,
          itemBuilder: (context, i) {
            final r = filtered[i];
            final id = (r['id'] as num?)?.toInt();
            final gid = (r['global_id'] ?? '').toString().trim();
            final customer = (r['customerNameSnapshot'] ?? '').toString().trim();
            final device = (r['deviceName'] ?? '').toString().trim();
            final serial = (r['deviceSerial'] ?? '').toString().trim();
            final status = (r['status'] ?? 'pending').toString();

            // ── القيم الأصلية للتذكرة (قبل الفاتورة) ──
            final estF = (r['estimatedPriceFils'] as num?)?.toInt() ?? 0;
            final advF = (r['advancePaymentFils'] as num?)?.toInt() ?? 0;
            final agreedF = (r['agreedPriceFils'] as num?)?.toInt();
            final serviceLineF = agreedF ?? estF;
            final partsF = _partsTotalFils(r);
            final ticketTotalF = serviceLineF + partsF;

            // ── بيانات الفاتورة المرتبطة (NULL إن لم تُصدر فاتورة بعد) ──
            final invTypeRaw = r['invType'];
            final invTotalF = (r['invTotalFils'] as num?)?.toInt();
            final invAdvF = (r['invAdvanceFils'] as num?)?.toInt();
            final invIsReturned = (r['invIsReturned'] as num?)?.toInt() ?? 0;
            final hasInvoice = invTypeRaw != null;
            final invType = hasInvoice ? invoiceTypeFromDb(invTypeRaw) : null;

            // ── الإجمالي الفعّال: الفاتورة أولاً (تشمل تعديلات نقطة البيع) ──
            final effectiveTotalF = invTotalF ?? ticketTotalF;

            // ── المدفوع الفعّال ──
            // نقدي مغلق = تم تحصيل الإجمالي كاملاً
            // آجل/أقساط = المبلغ المدفوع مقدماً في شاشة البيع
            // بدون فاتورة = العربون الأصلي على التذكرة
            final int effectivePaidF;
            if (!hasInvoice) {
              effectivePaidF = advF;
            } else if (invType == InvoiceType.cash ||
                invType == InvoiceType.delivery) {
              effectivePaidF = invTotalF ?? ticketTotalF;
            } else {
              // آجل، تقسيط، سندات قبض…
              effectivePaidF = invAdvF ?? advF;
            }

            final remainingF = _remainingFils(r);
            final linkedInvId = (r['invoiceId'] as num?)?.toInt() ?? 0;
            final hasLinkedInvoice = linkedInvId > 0;
            final canOpenSaleFromTicket = status == 'completed' &&
                id != null &&
                id > 0 &&
                !hasLinkedInvoice &&
                remainingF > 0;

            // ── شارة نوع الفاتورة (تظهر بجانب الإجمالي) ──
            String? invoiceBadgeLabel;
            Color? invoiceBadgeColor;
            if (hasInvoice) {
              if (invIsReturned == 1) {
                invoiceBadgeLabel = 'مرتجع';
                invoiceBadgeColor = const Color(0xFFEF4444);
              } else if (invType == InvoiceType.credit) {
                invoiceBadgeLabel = 'بيع آجل';
                invoiceBadgeColor = const Color(0xFFF59E0B);
              } else if (invType == InvoiceType.installment) {
                invoiceBadgeLabel = 'تقسيط';
                invoiceBadgeColor = const Color(0xFF8B5CF6);
              } else if (invType == InvoiceType.delivery) {
                invoiceBadgeLabel = 'توصيل';
                invoiceBadgeColor = const Color(0xFF3B82F6);
              }
              // نقدي أو سندات: لا شارة — التسليم كافٍ
            }

            final cd = _countdownTimerText(r);
            final statusColor = _statusColor(status);
            final overdue = _isOverdue(r);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: cs.surface,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: overdue
                        ? cs.error
                        : cs.outlineVariant.withValues(alpha: 0.55),
                    width: overdue ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (overdue)
                      Container(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          12,
                          8,
                          12,
                          8,
                        ),
                        color: cs.error.withValues(alpha: 0.12),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: cs.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'تجاوز موعد التسليم المتوقع — أكمل العمل أو حدّث الحالة.',
                                style: TextStyle(
                                  color: cs.error,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                                textAlign: TextAlign.start,
                              ),
                            ),
                          ],
                        ),
                      ),
                    InkWell(
                      onTap: (id == null || gid.isEmpty)
                          ? null
                          : () async {
                              await Navigator.of(context).push<void>(
                                contentMaterialRoute(
                                  routeId: AppContentRoutes.serviceOrdersHub,
                                  breadcrumbTitle: 'تفاصيل التذكرة',
                                  builder: (_) => ServiceOrderDetailScreen(
                                    orderId: id,
                                    orderGlobalId: gid,
                                  ),
                                ),
                              );
                              if (!mounted) return;
                              unawaited(_load());
                            },
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          12,
                          12,
                          12,
                          12,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 10,
                              height: 62,
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          customer.isEmpty ? 'عميل' : customer,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(
                                            color: statusColor.withValues(alpha: 0.22),
                                          ),
                                        ),
                                        child: Text(
                                          _statusLabel(status),
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    device.isEmpty ? '—' : device,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: cs.onSurfaceVariant),
                                  ),
                                  if (serial.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'سيريال/لوحة: $serial',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                      textDirection: TextDirection.ltr,
                                      textAlign: TextAlign.start,
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'القيمة: ${IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(effectiveTotalF))}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                      if (invoiceBadgeLabel != null)
                                        Container(
                                          margin: const EdgeInsetsDirectional.only(end: 6),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: invoiceBadgeColor!.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(99),
                                            border: Border.all(
                                              color: invoiceBadgeColor.withValues(alpha: 0.35),
                                            ),
                                          ),
                                          child: Text(
                                            invoiceBadgeLabel,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: invoiceBadgeColor,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        hasInvoice
                                            ? 'مدفوع: ${IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(effectivePaidF))}'
                                            : 'العربون: ${IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(effectivePaidF))}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: cs.onSurfaceVariant,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (status == 'completed' && remainingF > 0) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'متبقّي: ${IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(remainingF))}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12.5,
                                        color: cs.primary,
                                      ),
                                      textAlign: TextAlign.start,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'تحويل لفاتورة',
                              onPressed: (!canOpenSaleFromTicket ||
                                      _convertingOrderId != null)
                                  ? null
                                  : () async {
                                      setState(() => _convertingOrderId = id);
                                      try {
                                        final ok = await _convertToInvoice(
                                          context,
                                          orderId: id,
                                          orderGlobalId: gid,
                                        );
                                        if (!context.mounted) return;
                                        if (ok) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'تم إرسال البنود إلى شاشة البيع.',
                                              ),
                                            ),
                                          );
                                        } else {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'تعذر فتح البيع — راجع التذكرة أو أعد المحاولة.',
                                              ),
                                            ),
                                          );
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() => _convertingOrderId = null);
                                        }
                                      }
                                    },
                              icon: _convertingOrderId == id
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.open_in_new_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (status == 'pending' && id != null && id > 0)
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          12,
                          0,
                          12,
                          12,
                        ),
                        child: FilledButton.icon(
                          onPressed: () async {
                            await ServiceOrdersRepository.instance
                                .startServiceOrderWork(id);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم بدء العمل وبدء احتساب الموعد')),
                            );
                            _tab.animateTo(1);
                            unawaited(_load());
                          },
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('بدء العمل'),
                        ),
                      ),
                    if (status == 'in_progress' && id != null && id > 0) ...[
                      if (cd != null)
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            12,
                            0,
                            12,
                            6,
                          ),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Container(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                12,
                                8,
                                12,
                                8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A1A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: (overdue ? cs.error : cs.primary)
                                      .withValues(alpha: 0.35),
                                ),
                              ),
                              child: Text(
                                '${_timerPrefix(r)}  $cd',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: overdue
                                      ? const Color(0xFFFF6B6B)
                                      : const Color(0xFF7CFFB2),
                                  fontFamily: 'monospace',
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  shadows: [
                                    Shadow(
                                      color: (overdue
                                              ? const Color(0xFFFF6B6B)
                                              : const Color(0xFF7CFFB2))
                                          .withValues(alpha: 0.45),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                                textAlign: TextAlign.start,
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          12,
                          0,
                          12,
                          12,
                        ),
                        child: FilledButton(
                          onPressed: () async {
                            await ServiceOrdersRepository.instance
                                .markServiceOrderReadyForPickup(id);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم نقل التذكرة إلى جاهزة للتسليم'),
                              ),
                            );
                            _tab.animateTo(2);
                            unawaited(_load());
                          },
                          child: Text(
                            overdue
                                ? 'انتقال إلى جاهز للتسليم'
                                : 'جاهز للتسليم',
                          ),
                        ),
                      ),
                    ],
                    if (status == 'completed' && id != null && id > 0)
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          12,
                          0,
                          12,
                          12,
                        ),
                        child: remainingF > 0
                            ? FilledButton.tonal(
                                onPressed: (!canOpenSaleFromTicket ||
                                        _convertingOrderId != null)
                                    ? null
                                    : () async {
                                        setState(() => _convertingOrderId = id);
                                        try {
                                          final ok = await _convertToInvoice(
                                            context,
                                            orderId: id,
                                            orderGlobalId: gid,
                                          );
                                          if (!mounted) return;
                                          if (ok) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'تم إرسال البنود إلى شاشة البيع.',
                                                ),
                                              ),
                                            );
                                          } else {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'تعذر فتح البيع — راجع التذكرة أو أعد المحاولة.',
                                                ),
                                              ),
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(
                                              () => _convertingOrderId = null,
                                            );
                                          }
                                        }
                                    },
                                child: _convertingOrderId == id
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Text('الانتقال للدفع'),
                                          const SizedBox(width: 6),
                                          Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 18,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSecondaryContainer,
                                          ),
                                        ],
                                      ),
                              )
                            : FilledButton(
                                onPressed: () async {
                                  final ok = await ServiceOrdersRepository
                                      .instance
                                      .markServiceOrderDeliveredIfFullyPaid(id);
                                  if (!mounted) return;
                                  if (ok) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('تم تسجيل التسليم'),
                                      ),
                                    );
                                    _tab.animateTo(3);
                                    unawaited(_load());
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'تعذر التسليم — راجع المبالغ من التفاصيل.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: const Text('تأكيد التسليم'),
                              ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('طلبات الصيانة'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: [
            for (final t in _tabs)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: t.color,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(t.label),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add_rounded),
        label: const Text('تذكرة جديدة'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'بحث بالعميل أو الجهاز أو السيريال…',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  Future<bool> _convertToInvoice(
    BuildContext context, {
    required int orderId,
    required String orderGlobalId,
  }) async {
    final repo = ServiceOrdersRepository.instance;
    final order = await repo.getServiceOrderByGlobalId(orderGlobalId);
    if (order == null) return false;
    final st = (order['status'] ?? '').toString();
    if (st != 'completed') return false;
    final existingInv = (order['invoiceId'] as num?)?.toInt() ?? 0;
    if (existingInv > 0) return false;

    final items = await repo.getItemsForOrderGlobalId(orderGlobalId);

    final draft = context.read<SaleDraftProvider>();

    final serviceId = (order['serviceId'] as num?)?.toInt();
    final serviceName = (order['serviceNameSnapshot'] ?? '').toString().trim();
    final custName = (order['customerNameSnapshot'] ?? '').toString().trim();
    final custId = (order['customerId'] as num?)?.toInt();
    final estF = (order['estimatedPriceFils'] as num?)?.toInt() ?? 0;
    final agreedF = (order['agreedPriceFils'] as num?)?.toInt();
    final advF = (order['advancePaymentFils'] as num?)?.toInt() ?? 0;

    final device = (order['deviceName'] ?? '').toString().trim();
    final serial = (order['deviceSerial'] ?? '').toString().trim();
    final baseName = serviceName.isEmpty ? 'خدمة فنية' : serviceName;
    var finalName = baseName;
    final devDetails = [
      if (device.isNotEmpty) device,
      if (serial.isNotEmpty) 'س: $serial',
    ].join(' - ');
    if (devDetails.isNotEmpty) {
      finalName = '$baseName ($devDetails)';
    }

    // 1) البيانات الوصفية للفاتورة (العميل + ربط التذكرة).
    // لا نُمرّر advance هنا لأن السعر المُرسَل أدناه هو (المتفق - العربون) مباشرة.
    draft.enqueueSaleMeta({
      'customerName': custName,
      'linkedCustomerId': custId,
      'linkedServiceOrderId': orderId,
    });

    // 2) بند الخدمة الفنية: السعر = المتفق عليه ناقص العربون المحصّل مسبقاً.
    final servicePriceF = agreedF ?? estF;
    final remainingF = (servicePriceF - advF).clamp(0, servicePriceF);
    if (serviceId != null && serviceId > 0) {
      draft.enqueueProductLine({
        'name': finalName,
        'sell': IqdMoney.fromFils(remainingF),
        'minSell': IqdMoney.fromFils(remainingF),
        'productId': serviceId,
        'trackInventory': 0,
        'allowNegativeStock': 0,
        'qty': 0,
        'stockBaseKind': 0,
        'isService': 1,
        'addQuantity': 1,
      });
    } else {
      // لا يوجد serviceId: نضيف سطر وصفي فقط كخدمة (بدون productId).
      draft.enqueueProductLine({
        'name': finalName,
        'sell': IqdMoney.fromFils(remainingF),
        'minSell': IqdMoney.fromFils(remainingF),
        'productId': null,
        'trackInventory': 0,
        'allowNegativeStock': 0,
        'qty': 0,
        'stockBaseKind': 0,
        'isService': 1,
        'addQuantity': 1,
      });
    }

    // 3) قطع الغيار: سطر لكل قطعة (quantity يمكن أن يكون > 1).
    for (final it in items) {
      final pid = (it['productId'] as num?)?.toInt();
      if (pid == null || pid <= 0) continue;
      final name = (it['productName'] ?? '').toString().trim();
      final q = (it['quantity'] as num?)?.toInt() ?? 1;
      final pF = (it['priceFils'] as num?)?.toInt() ?? 0;
      draft.enqueueProductLine({
        'name': name.isEmpty ? 'قطعة غيار' : name,
        'sell': IqdMoney.fromFils(pF),
        'minSell': IqdMoney.fromFils(pF),
        'productId': pid,
        'trackInventory': 1,
        'allowNegativeStock': 0,
        'qty': null,
        'stockBaseKind': 0,
        'isService': 0,
        'addQuantity': q,
      });
    }

    if (!draft.isSaleScreenOpen) {
      if (!context.mounted) return false;
      await Navigator.of(context).push(
        contentMaterialRoute(
          routeId: AppContentRoutes.addInvoice,
          breadcrumbTitle: 'بيع جديد',
          builder: (_) => const AddInvoiceScreen(),
        ),
      );
      return true;
    }
    return true;
  }
}

class _ServiceStatusTab {
  final String status;
  final String label;
  final Color color;
  const _ServiceStatusTab(this.status, this.label, this.color);
}

