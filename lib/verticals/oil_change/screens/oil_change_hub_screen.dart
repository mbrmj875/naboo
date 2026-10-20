import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../guides/guide_anchor.dart';
import '../../../guides/guide_controller.dart';
import '../../../navigation/app_route_observer.dart';
import '../../../navigation/content_navigation.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/cloud_sync_service.dart';
import '../../../services/customer_search_index.dart';
import '../../../services/database_helper.dart';
import '../services/oil_change_orders_repository.dart';
import '../services/oil_change_post_sale_service.dart';
import '../services/oil_change_settings.dart';
import '../services/oil_change_whatsapp_status_store.dart';
import 'oil_change_whatsapp_connect_screen.dart';
import '../../../services/service_orders_repository.dart';
import '../../../services/tenant_context_service.dart';
import '../../../utils/app_logger.dart';
import '../utils/oil_change_log_format.dart';
import '../utils/oil_change_log_grouping.dart';
import '../utils/oil_change_layout.dart';
import '../utils/oil_change_whatsapp_user_messages.dart';
import '../utils/oil_change_order_status.dart';
import '../../../theme/sale_brand.dart';
import '../../../utils/screen_layout.dart';
import '../widgets/oil_change_form_theme.dart';
import '../widgets/whatsapp_glyph_icon.dart';
import '../widgets/oil_change_log_detail_sheet.dart';
import '../widgets/oil_change_log_stitch.dart';
import '../widgets/oil_change_owner_pin_confirm_dialog.dart';
import '../services/oil_change_whatsapp_outbox.dart';
import '../services/oil_change_whatsapp_gateway_repository.dart';
import 'oil_change_direct_sale_screen.dart';
import 'oil_change_form_screen.dart';
import 'oil_change_whatsapp_messages_screen.dart';

/// سجل غيارات الزيت: بطاقة جديدة + جدول تفصيلي + واتساب.
class OilChangeHubScreen extends StatefulWidget {
  const OilChangeHubScreen({super.key, this.initialSearchQuery});

  /// استعلام أولي من البحث في الرئيسية (لوحة / هاتف / عميل).
  final String? initialSearchQuery;

  @override
  State<OilChangeHubScreen> createState() => _OilChangeHubScreenState();
}

class _OilChangeHubScreenState extends State<OilChangeHubScreen>
    with RouteAware, WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _royalGold = SaleBrandColors.gold;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  String _searchQuery = '';
  Timer? _debounce;

  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  final List<Map<String, dynamic>> _logs = [];
  List<OilChangeDayGroup> _dayGroups = [];
  Set<String> _expandedDayKeys = {};
  bool _hasMore = true;
  int? _highlightedId;
  bool _waGatewayDisconnected = false;
  int _whatsappPending = 0;
  late final TabController _logTabController;
  static const double _phoneSearchHeaderExtent = 64;

  /// كاش منفصل لكل تبويب — تبديل فوري بلا إعادة تحميل ثقيلة.
  final _activeTabCache = _OilLogTabCache();
  final _suspendedTabCache = _OilLogTabCache();
  OilChangeLogStatusFilter _displayedFilter = OilChangeLogStatusFilter.active;
  var _sqlitePrepared = false;
  static const int _pageSize = 40;
  bool _silentRefreshRunning = false;
  bool _silentRefreshQueued = false;
  /// بعد استكمال بطاقة نحدّث نحن — لا نكرّر الجلب من didPopNext.
  bool _suppressNextPopRefresh = false;

  OilChangeLogStatusFilter get _logStatusFilter =>
      _logTabController.index == 1
          ? OilChangeLogStatusFilter.suspended
          : OilChangeLogStatusFilter.active;

  bool get _showSuspendedLog =>
      _logStatusFilter == OilChangeLogStatusFilter.suspended;

  _OilLogTabCache _cacheFor(OilChangeLogStatusFilter filter) =>
      filter == OilChangeLogStatusFilter.suspended
          ? _suspendedTabCache
          : _activeTabCache;

  void _rebuildDayGroups({bool resetExpanded = false}) {
    final groups = groupOilChangeLogsByDay(_logs);
      final valid = groups.map((g) => g.dayKey).toSet();
    if (resetExpanded || _expandedDayKeys.isEmpty) {
      // افتراضياً: اليوم (وأمس إن وُجد) مفتوحان؛ بقية الأيام مطوية.
      _expandedDayKeys = defaultExpandedOilChangeDayKeys(groups);
    } else {
      // عند تحميل صفحات أقدم: احتفظ باختيار المستخدم ولا تُعِد فتح المطوي.
      _expandedDayKeys = _expandedDayKeys.where(valid.contains).toSet();
    }
    _dayGroups = groups;
  }

  @override
  void initState() {
    super.initState();
    _logTabController = TabController(length: 2, vsync: this);
    _logTabController.addListener(_onLogTabChanged);
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    CloudSyncService.instance.remoteImportGeneration.addListener(
      _onCloudDataImported,
    );
    final seed = widget.initialSearchQuery?.trim();
    if (seed != null && seed.isNotEmpty) {
      _searchController.text = seed;
      _searchQuery = seed;
    }
    unawaited(_reload());
    // لا تبدأ جولة TTS تلقائياً — تتنافس مع فتح الكيبورد وتسبب تأخيراً ملحوظاً.
    // تسخين فهرس العملاء أثناء تصفّح السجل — قبل فتح البطاقة.
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      unawaited(CustomerSearchIndex.instance.ensureFresh());
    });
  }

  void _syncGuidePendingTab(GuideController guide) {
    final action = guide.currentStep?.action;
    if (action == 'oil.select_pending_tab' &&
        _logTabController.index != 1 &&
        !_logTabController.indexIsChanging) {
      _logTabController.animateTo(1);
    }
  }

  void _syncGuideHubSettings(GuideController guide) {
    final step = guide.currentStep;
    final needSheet = guide.isRunning &&
        step != null &&
        (step.action == 'oil.open_hub_settings' ||
            step.anchorId.startsWith('oil.settings.'));
    if (needSheet) {
      if (!_hubSettingsSheetVisible) {
        unawaited(_openHubSettings(fromGuide: true));
      } else {
        _hubSettingsOpenedByGuide = true;
      }
    } else if (_hubSettingsOpenedByGuide && _hubSettingsSheetVisible) {
      // أغلق فقط الورقة التي فتحتها الجولة — لا تلمس فتح المستخدم اليدوي.
      _closeHubSettingsIfOpen();
    }
  }

  RouteObserver<PageRoute<dynamic>>? _homeInnerRouteObserver;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is! PageRoute<dynamic>) return;
    final observer = HomeInnerRouteObserverScope.maybeOf(context);
    if (observer == null) return;
    if (_homeInnerRouteObserver == observer) {
      return;
    }
    if (_homeInnerRouteObserver != null) {
      _homeInnerRouteObserver!.unsubscribe(this);
    }
    _homeInnerRouteObserver = observer;
    observer.subscribe(this, route);
  }

  @override
  void dispose() {
    unsubscribeHomeInnerRouteFromObserver(_homeInnerRouteObserver, this);
    _homeInnerRouteObserver = null;
    WidgetsBinding.instance.removeObserver(this);
    CloudSyncService.instance.remoteImportGeneration.removeListener(
      _onCloudDataImported,
    );
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _debounce?.cancel();
    _logTabController.removeListener(_onLogTabChanged);
    _logTabController.dispose();
    super.dispose();
  }

  void _onLogTabChanged() {
    if (_logTabController.indexIsChanging) return;
    final next = _logStatusFilter;
    if (next == _displayedFilter) return;

    _stashUiIntoCache(_displayedFilter);
    final cached = _cacheFor(next);
    if (cached.loadedOnce) {
      setState(() {
        _restoreUiFromCache(next);
        _loading = false;
        _loadingMore = false;
        _error = cached.error;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final max = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(cached.scrollOffset.clamp(0.0, max));
      });
      // تحديث هادئ بالخلفية — بدون شاشة تحميل.
      unawaited(_refreshSilently());
      return;
    }

    setState(() {
      _displayedFilter = next;
      _logs.clear();
      _dayGroups = [];
      _expandedDayKeys = {};
      _hasMore = true;
      _error = null;
      _loading = true;
      _loadingMore = false;
    });
    unawaited(_reload(showSpinner: true));
  }

  void _stashUiIntoCache(OilChangeLogStatusFilter filter) {
    final cache = _cacheFor(filter);
    cache.logs
      ..clear()
      ..addAll(_logs);
    cache.dayGroups = List<OilChangeDayGroup>.of(_dayGroups);
    cache.expandedDayKeys = Set<String>.of(_expandedDayKeys);
    cache.hasMore = _hasMore;
    cache.error = _error;
    cache.loadedOnce = true;
    if (_scrollController.hasClients) {
      cache.scrollOffset = _scrollController.offset;
    }
  }

  void _restoreUiFromCache(OilChangeLogStatusFilter filter) {
    final cache = _cacheFor(filter);
    _logs
      ..clear()
      ..addAll(cache.logs);
    _dayGroups = List<OilChangeDayGroup>.of(cache.dayGroups);
    _expandedDayKeys = Set<String>.of(cache.expandedDayKeys);
    _hasMore = cache.hasMore;
    _error = cache.error;
    _displayedFilter = filter;
  }

  void _syncCurrentCacheFromUi() {
    _stashUiIntoCache(_displayedFilter);
  }

  void _invalidateTabCaches() {
    _activeTabCache.clear();
    _suspendedTabCache.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshSilently());
    }
  }

  @override
  void didPopNext() {
    // التبويب الآخر قد تغيّر (تعليق/استكمال) — أعد جلبه عند زيارته التالية.
    final other = _showSuspendedLog ? _activeTabCache : _suspendedTabCache;
    other.clear();
    if (_suppressNextPopRefresh) {
      _suppressNextPopRefresh = false;
      return;
    }
    unawaited(_refreshSilently());
  }

  void _onCloudDataImported() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refreshSilently());
    });
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _searchQuery = _searchController.text.trim());
      _invalidateTabCaches();
      // إن كانت القائمة ظاهرة مسبقاً — حدّث بدون شاشة تحميل كاملة.
      unawaited(_reload(showSpinner: _logs.isEmpty));
    });
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 320) {
      unawaited(_loadMore());
    }
  }

  bool _onPhoneScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (!_hasMore || _loadingMore || _loading) return false;
    final metrics = notification.metrics;
    if (metrics.pixels >= metrics.maxScrollExtent - 320) {
      unawaited(_loadMore());
    }
    return false;
  }

  int? get _cursorAfterId {
    if (_logs.isEmpty) return null;
    return (_logs.last['id'] as num?)?.toInt();
  }

  String _friendlyLoadError(Object e) {
    final raw = e.toString();
    if (raw.contains('TenantContext') ||
        raw.contains('tenant') ||
        raw.contains('مستأجر')) {
      return 'تعذّر تحديد بيانات المتجر. أعد فتح التطبيق ثم حاول مرة أخرى.';
    }
    if (raw.contains('no such table') || raw.contains('no such column')) {
      return 'قاعدة البيانات تحتاج تحديثاً. أغلق التطبيق وافتحه من جديد.';
    }
    if (raw.contains('database is locked')) {
      return 'قاعدة البيانات مشغولة. انتظر ثانية ثم أعد المحاولة.';
    }
    return 'تعذّر قراءة السجل من الجهاز. أعد المحاولة.';
  }

  Future<List<Map<String, dynamic>>> _fetchLogPage({int? afterId}) async {
    // قراءة محلية من SQLite فقط — لا شبكة.
    if (!_sqlitePrepared) {
    await DatabaseHelper().ensureDefaultTenantSeedIfNeeded();
      // ensureServiceOrdersReadRepair مُخزَّن مرة واحدة داخل DatabaseHelper.
    await DatabaseHelper().ensureServiceOrdersReadRepair();
    final tenantCtx = TenantContextService.instance;
    if (!tenantCtx.loaded) {
      await tenantCtx.load();
      }
      _sqlitePrepared = true;
    }

    final rows = await ServiceOrdersRepository.instance.getOilChangeLogPage(
      searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      afterId: afterId,
      limit: _pageSize,
      statusFilter: _logStatusFilter,
    );
    return rows;
  }

  void _replaceFirstPage(List<Map<String, dynamic>> rows) {
    _logs
      ..clear()
      ..addAll(rows);
    _hasMore = rows.length >= _pageSize;
    _rebuildDayGroups(resetExpanded: true);
    _displayedFilter = _logStatusFilter;
    _syncCurrentCacheFromUi();
  }

  /// تحديث خلفي دون شاشة تحميل كاملة — عند العودة للسجل أو بعد المزامنة.
  Future<void> _refreshSilently() async {
    if (!mounted || _loading) return;
    if (_silentRefreshRunning) {
      _silentRefreshQueued = true;
      return;
    }
    _silentRefreshRunning = true;
    try {
      do {
        _silentRefreshQueued = false;
        final filterAtStart = _logStatusFilter;
    try {
      final rows = await _fetchLogPage();
      if (!mounted) return;
          // إن بدّل المستخدم التبويب أثناء الجلب — احفظ في كاش ذلك التبويب فقط.
          if (filterAtStart != _logStatusFilter) {
            final cache = _cacheFor(filterAtStart);
            cache.logs
              ..clear()
              ..addAll(rows);
            cache.hasMore = rows.length >= _pageSize;
            cache.dayGroups = groupOilChangeLogsByDay(cache.logs);
            cache.loadedOnce = true;
            cache.error = null;
          } else {
      setState(() => _replaceFirstPage(rows));
          }
    } catch (e) {
      AppLogger.warn('oil_change_hub', 'silent refresh failed: $e');
        }
      } while (_silentRefreshQueued && mounted && !_loading);
    } finally {
      _silentRefreshRunning = false;
    }
  }

  Future<void> _reload({bool showSpinner = true}) async {
    if (showSpinner) {
    setState(() {
      _loading = true;
      _error = null;
      _hasMore = true;
    });
    }
    unawaited(_refreshWhatsappPending());
    final filterAtStart = _logStatusFilter;
    try {
      // السجل من SQLite المحلي أولاً — لا نعلّق الواجهة على شبكة واتساب.
      final rows = await _fetchLogPage();
      final waLocal = await OilChangeWhatsappStatusStore.instance.readStatus(
        refreshFromServer: false,
      );
      if (!mounted) return;
      if (filterAtStart != _logStatusFilter) {
        final cache = _cacheFor(filterAtStart);
        cache.logs
          ..clear()
          ..addAll(rows);
        cache.hasMore = rows.length >= _pageSize;
        cache.dayGroups = groupOilChangeLogsByDay(cache.logs);
        cache.loadedOnce = true;
        cache.error = null;
        if (showSpinner && mounted) {
          setState(() => _loading = false);
        }
        return;
      }
      setState(() {
        _replaceFirstPage(rows);
        _waGatewayDisconnected =
            waLocal == OilChangeWhatsappGatewayStatus.disconnected;
        _loading = false;
        _error = null;
      });
      unawaited(_syncWhatsappStatusInBackground());
    } catch (e, st) {
      AppLogger.error('oil_change_hub', 'reload failed', e, st);
      if (!mounted) return;
      if (filterAtStart != _logStatusFilter) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      _cacheFor(filterAtStart).error = e;
    }
  }

  /// مزامنة حالة واتساب بعد ظهور السجل — لا تحجب التحميل.
  Future<void> _syncWhatsappStatusInBackground() async {
    try {
      await OilChangeWhatsappStatusStore.instance.syncFromCloudIfPossible();
      if (!mounted) return;
      final wa = await OilChangeWhatsappStatusStore.instance.readStatus(
        refreshFromServer: false,
      );
      if (!mounted) return;
      final disconnected = wa == OilChangeWhatsappGatewayStatus.disconnected;
      if (disconnected == _waGatewayDisconnected) return;
      setState(() => _waGatewayDisconnected = disconnected);
    } catch (e) {
      AppLogger.warn('oil_change_hub', 'whatsapp status background sync: $e');
    }
  }

  Future<void> _loadMore() async {
    final after = _cursorAfterId;
    if (after == null) return;
    setState(() => _loadingMore = true);
    try {
      final rows = await _fetchLogPage(afterId: after);
      if (!mounted) return;
      setState(() {
        _logs.addAll(rows);
        _hasMore = rows.length >= _pageSize;
        _loadingMore = false;
        _rebuildDayGroups();
        _syncCurrentCacheFromUi();
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _openNewCard() async {
    final saved = await Navigator.of(context).push<bool>(
      contentMaterialRoute(
        routeId: AppContentRoutes.oilChangeCreate,
        breadcrumbTitle: 'بطاقة غيار زيت جديدة',
        builder: (_) => const OilChangeFormScreen(),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ البطاقة وإنشاء الفاتورة')),
      );
    }
  }

  int? _orderIdFromRow(Map<String, dynamic> r) => (r['id'] as num?)?.toInt();

  Future<void> _showLogRowDetail(Map<String, dynamic> r) async {
    await OilChangeLogDetailSheet.show(
      context,
      row: r,
      onNewCardFromRow: () => unawaited(_openPrefilledNewCard(r)),
    );
  }

  /// بطاقة جديدة بنفس بيانات السجل (لا تعدّل السجل القديم).
  Future<void> _openResumeSuspended(Map<String, dynamic> r) async {
    final id = _orderIdFromRow(r);
    if (id == null || id <= 0) return;
    setState(() => _highlightedId = id);

    final saved = await Navigator.of(context).push<bool>(
      contentMaterialRoute(
        routeId: AppContentRoutes.oilChangeEditId(id),
        breadcrumbTitle: 'استكمال بطاقة معلّقة',
        builder: (_) => OilChangeFormScreen(editOrderId: id, prefillFromOrder: Map<String, dynamic>.from(r)),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم استكمال البطاقة وإنشاء الفاتورة')),
      );
      _suppressNextPopRefresh = true;
      _invalidateTabCaches();
      unawaited(_reload(showSpinner: false));
    }
  }

  Future<void> _confirmAndDiscardSuspended(Map<String, dynamic> r) async {
    final id = _orderIdFromRow(r);
    if (id == null || id <= 0) return;

    final name = (r['customerNameSnapshot'] ?? '').toString().trim();
    final plate = oilFormatPlate(r);
    final subtitle = [
      if (name.isNotEmpty) name,
      if (plate.isNotEmpty && plate != '—') plate,
    ].join(' · ');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            icon: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: OilChangeLogStitchMetrics.error.withValues(alpha: 0.10),
                shape: BoxShape.circle,
                border: Border.all(
                  color: OilChangeLogStitchMetrics.secondaryContainer
                      .withValues(alpha: 0.55),
                ),
              ),
              child: const Icon(
                Icons.cancel_outlined,
                color: OilChangeLogStitchMetrics.error,
                size: 28,
              ),
            ),
            title: const Text(
              'هل تريد إسقاط هذه البطاقة؟',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            content: Text(
              subtitle.isEmpty
                  ? 'ستُزال من المعلّقة ولن يمكن استكمالها لاحقاً.'
                  : 'ستُزال «$subtitle» من المعلّقة ولن يمكن استكمالها لاحقاً.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: OilChangeLogStitchMetrics.primaryContainer,
                ),
                child: const Text('لا'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: OilChangeLogStitchMetrics.error,
                  foregroundColor: Colors.white,
                ),
                child: const Text('نعم، إسقاط'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || confirmed != true) return;

    try {
      final ok = await OilChangeOrdersRepository.instance
          .discardSuspendedOilChangeOrder(id);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذّر إسقاط البطاقة — قد تكون غير معلّقة أو مرتبطة بفاتورة',
            ),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إسقاط البطاقة المعلّقة')),
      );
      _invalidateTabCaches();
      unawaited(_reload(showSpinner: false));
    } catch (e, st) {
      AppLogger.error('oil_hub', 'discard suspended failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر إسقاط البطاقة')),
      );
    }
  }

  void _onLogRowPrimaryAction(Map<String, dynamic> r) {
    if (_showSuspendedLog) {
      unawaited(_openResumeSuspended(r));
    } else {
      unawaited(_openPrefilledNewCard(r));
    }
  }

  /// بطاقة جديدة بنفس بيانات السجل (لا تعدّل السجل القديم).
  Future<void> _openPrefilledNewCard(Map<String, dynamic> r) async {
    final id = _orderIdFromRow(r);
    if (id != null && id > 0) {
      setState(() => _highlightedId = id);
    }

    final saved = await Navigator.of(context).push<bool>(
      contentMaterialRoute(
        routeId: AppContentRoutes.oilChangeCreate,
        breadcrumbTitle: 'بطاقة غيار زيت جديدة',
        builder: (_) => OilChangeFormScreen(
          key: ValueKey(
            id != null && id > 0
                ? 'oil-prefill-$id'
                : 'oil-prefill-gid-${(r['globalId'] ?? '').toString()}',
          ),
          prefillFromOrder: Map<String, dynamic>.from(r),
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ بطاقة الغيار')),
      );
    }
  }

  Future<void> _openWhatsAppMessages() async {
    if (_showSuspendedLog) return;
    await OilChangeWhatsappMessagesScreen.open(context);
      if (!mounted) return;
    await _refreshWhatsappPending();
  }

  Future<void> _refreshWhatsappPending() async {
    final count = await OilChangeWhatsappOutbox.instance.totalNotSentCount();
    if (!mounted || count == _whatsappPending) return;
    setState(() => _whatsappPending = count);
  }

  Future<void> _openWhatsappConnect() async {
    await Navigator.of(context).push<void>(
      contentMaterialRoute(
        routeId: AppContentRoutes.oilWhatsappConnect,
        breadcrumbTitle: 'ربط واتساب المحل',
        builder: (_) => const OilChangeWhatsappConnectScreen(),
      ),
    );
    if (!mounted) return;
    await OilChangeWhatsappStatusStore.instance.syncFromCloudIfPossible();
    final disconnected =
        await OilChangeWhatsappStatusStore.instance.isDisconnectedBannerVisible();
    setState(() => _waGatewayDisconnected = disconnected);
  }

  bool _hubSettingsSheetVisible = false;
  bool _hubSettingsOpenedByGuide = false;
  BuildContext? _hubSettingsSheetContext;

  Future<void> _openHubSettings({bool fromGuide = false}) async {
    if (_hubSettingsSheetVisible) {
      if (fromGuide) _hubSettingsOpenedByGuide = true;
      return;
    }
    _hubSettingsSheetVisible = true;
    _hubSettingsOpenedByGuide = fromGuide;
    try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
        builder: (sheetCtx) {
          _hubSettingsSheetContext = sheetCtx;
          return const _OilChangeHubSettingsSheet();
        },
      );
    } finally {
      _hubSettingsSheetContext = null;
      _hubSettingsSheetVisible = false;
      _hubSettingsOpenedByGuide = false;
    }
  }

  void _closeHubSettingsIfOpen() {
    final sheetCtx = _hubSettingsSheetContext;
    if (sheetCtx == null) return;
    if (Navigator.of(sheetCtx).canPop()) {
      Navigator.of(sheetCtx).pop();
    }
  }

  static const _tableRowHeight = 42.0;


  Widget _wrapRoyalGoldCard({
    required ColorScheme cs,
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double radius = 16,
  }) {
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 10),
      padding: padding ?? const EdgeInsets.all(14),
      decoration: OilChangeLogStitchMetrics.panelDecoration(radius: radius),
      child: child,
    );
  }

  Widget _buildLogPanelHeader(ColorScheme cs, ScreenLayout layout, bool mobile) {
    return OilChangeLogStitchLogPanelHeader(
      showSuspended: _showSuspendedLog,
      mobile: mobile,
      showHint: !layout.isPhoneXS,
    );
  }

  /// عرض ثابت لكل عمود — يحافظ على محاذاة الرأس مع البيانات.
  /// أعمدة مطابقة لحقول بطاقة غيار الزيت (عميل · سيارة · زيت · خدمات).
  static const List<({String label, double width})> _columns = [
    (label: 'اسم العميل', width: 120),
    (label: 'اسم السيارة', width: 104),
    (label: 'الموديل', width: 64),
    (label: 'حجم المحرك', width: 72),
    (label: 'رقم اللوحة', width: 100),
    (label: 'القراءة الحالية', width: 88),
    (label: 'القراءة اللاحقة', width: 88),
    (label: 'مصدر الزيت', width: 84),
    (label: 'نوع الزيت', width: 92),
    (label: 'اللزوجة', width: 68),
    (label: 'اللترات / الحجم', width: 88),
    (label: 'نوع الفلتر', width: 80),
    (label: 'الخدمات الإضافية', width: 168),
    (label: 'السعر', width: 92),
    (label: 'الفني', width: 88),
    (label: 'ملاحظات', width: 120),
    (label: 'تفاصيل', width: 52),
  ];

  double get _minTableWidth =>
      _columns.fold<double>(0, (sum, c) => sum + c.width);

  List<double> _resolveColumnWidths(double availableWidth) {
    final mins = _columns.map((c) => c.width).toList();
    final minTotal = _minTableWidth;
    if (availableWidth <= minTotal) return mins;
    final extra = availableWidth - minTotal;
    return [
      for (var i = 0; i < mins.length; i++)
        mins[i] + extra * (mins[i] / minTotal),
    ];
  }

  Map<int, TableColumnWidth> _columnWidthsFor(double availableWidth) {
    final widths = _resolveColumnWidths(availableWidth);
    return {
      for (var i = 0; i < widths.length; i++) i: FixedColumnWidth(widths[i]),
    };
  }

  Color _tableHeaderBackground(ColorScheme cs) =>
      OilChangeLogStitchMetrics.secondaryContainer.withValues(alpha: 0.25);

  Color _tableRowBackground(
    ColorScheme cs, {
    required int rowIndex,
    required bool selected,
  }) {
    if (selected) {
      return cs.primaryContainer.withValues(alpha: 0.32);
    }
    return rowIndex.isEven ? cs.surface : cs.surfaceContainerLowest;
  }

  Widget _tableCell({
    required Color background,
    required Widget child,
    VoidCallback? onTap,
    ColorScheme? cs,
  }) {
    return Material(
      color: background,
      child: InkWell(
        onTap: onTap,
        hoverColor: cs?.primary.withValues(alpha: 0.06),
        splashColor: cs?.primary.withValues(alpha: 0.10),
        child: SizedBox(
          height: _tableRowHeight,
          width: double.infinity,
          child: child,
        ),
      ),
    );
  }

  Widget _tableCellText(
    String text, {
    TextStyle? style,
    TextAlign textAlign = TextAlign.start,
    TextDirection? textDirection,
    bool compact = false,
  }) {
    final display = text.trim().isEmpty ? '—' : text.trim();
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 6),
      child: Align(
        alignment: textAlign == TextAlign.center
            ? Alignment.center
            : AlignmentDirectional.centerStart,
        child: Text(
          display,
          style: (style ?? TextStyle(fontSize: compact ? 11.5 : 12.5)).copyWith(
            height: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          textDirection: textDirection,
        ),
      ),
    );
  }

  TableRow _headerTableRow(ColorScheme cs) {
    final headerBg = _tableHeaderBackground(cs);
    final headerStyle = TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 11.5,
      color: cs.onSurfaceVariant,
      letterSpacing: 0.1,
    );
    return TableRow(
      children: [
        for (var i = 0; i < _columns.length; i++)
          _tableCell(
            background: headerBg,
            cs: cs,
            child: i == _columns.length - 1
                ? Center(
                    child: Icon(
                      Icons.visibility_rounded,
                      size: 18,
                      color: _royalGold,
                    ),
                  )
                : _tableCellText(
                    _columns[i].label,
                    style: headerStyle,
                  ),
          ),
      ],
    );
  }

  TableRow _dataTableRow(
    BuildContext context,
    Map<String, dynamic> r,
    int index, {
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final id = (r['id'] as num?)?.toInt();
    final selected = id != null && id == _highlightedId;
    final services = parseOilRequestedServices(r['requestedServices']?.toString());
    final rowBg = _tableRowBackground(cs, rowIndex: index, selected: selected);

    Widget cell(Widget w) => _tableCell(
          background: rowBg,
          cs: cs,
          onTap: onTap,
          child: w,
        );

    Widget detailCell() => _tableCell(
          background: rowBg,
          cs: cs,
          onTap: () => unawaited(_showLogRowDetail(r)),
          child: Center(
            child: Tooltip(
              message: 'عرض التفاصيل',
              child: Icon(
                Icons.visibility_rounded,
                color: _royalGold,
                size: 22,
              ),
            ),
          ),
        );

    return TableRow(
      children: [
        cell(
          _tableCellText(
            (r['customerNameSnapshot'] ?? '').toString(),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        cell(_tableCellText((r['deviceName'] ?? '').toString())),
        cell(_tableCellText((r['carModel'] ?? '').toString())),
        cell(_tableCellText((r['engineSize'] ?? '').toString())),
        cell(
          _tableCellText(
            oilFormatPlate(r),
            textDirection: TextDirection.ltr,
          ),
        ),
        cell(
          _tableCellText(
            oilFormatOdo((r['odometerCurrent'] ?? '').toString()),
            textDirection: TextDirection.ltr,
          ),
        ),
        cell(
          _tableCellText(
            oilFormatOdo((r['odometerNext'] ?? '').toString()),
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: cs.primary,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
        cell(_tableCellText(oilFormatOilSource(r))),
        cell(_tableCellText((r['oilType'] ?? '').toString())),
        cell(_tableCellText((r['oilViscosity'] ?? '').toString())),
        cell(_tableCellText(oilFormatLitersOrSize(r))),
        cell(_tableCellText(oilFormatFilterType(r))),
        cell(_tableCellText(oilFormatServicesShort(services))),
        cell(
          _tableCellText(
            oilFormatPrice(r),
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: cs.primary,
            ),
          ),
        ),
        cell(_tableCellText(oilFormatTechnician(r))),
        cell(_tableCellText((r['issueDescription'] ?? '').toString())),
        detailCell(),
      ],
    );
  }

  Widget _buildDayHeader(BuildContext context, OilChangeDayGroup group) {
    final expanded = _expandedDayKeys.contains(group.dayKey);
    final layout = context.screenLayout;
    return OilChangeLogStitchDayHeader(
      group: group,
      expanded: expanded,
      compact: !layout.isDesktopVariant,
      onToggle: () {
          setState(() {
            if (expanded) {
              _expandedDayKeys.remove(group.dayKey);
            } else {
              _expandedDayKeys.add(group.dayKey);
            }
          });
        },
    );
  }

  Widget _buildTableCore(
    BuildContext context,
    double tableWidth,
    List<Map<String, dynamic>> rows,
  ) {
    final cs = Theme.of(context).colorScheme;
    final innerBorder = _royalGold.withValues(alpha: 0.22);

    return SizedBox(
      width: tableWidth,
      child: Table(
        columnWidths: _columnWidthsFor(tableWidth),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder(
          top: BorderSide(color: innerBorder, width: 1),
          bottom: BorderSide(color: innerBorder, width: 1),
          horizontalInside: BorderSide(color: innerBorder, width: 0.5),
        ),
        children: [
          _headerTableRow(cs),
          for (var i = 0; i < rows.length; i++)
            _dataTableRow(
              context,
              rows[i],
              i,
              onTap: () => _onLogRowPrimaryAction(rows[i]),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupedTableCore(BuildContext context, double tableWidth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in _dayGroups) ...[
          _buildDayHeader(context, g),
          if (_expandedDayKeys.contains(g.dayKey))
            _buildTableCore(context, tableWidth, g.rows),
        ],
      ],
    );
  }

  Widget _buildErrorView(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(
              'تعذّر تحميل السجل',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.error,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _error == null
                  ? 'تحقق من الاتصال ثم أعد المحاولة.'
                  : _friendlyLoadError(_error!),
              style: TextStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => unawaited(_reload()),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView(ColorScheme cs, ScreenLayout layout) {
    return OilChangeLogStitchEmptyView(
      searching: _searchQuery.isNotEmpty,
      showSuspended: _showSuspendedLog,
      onNewCard: _openNewCard,
    );
  }

  Widget _buildMobileLogCard(
    BuildContext context,
    Map<String, dynamic> r,
    ScreenLayout layout,
  ) {
    final id = (r['id'] as num?)?.toInt();
    final selected = id != null && id == _highlightedId;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: OilChangeLogStitchMetrics.pagePadding,
        end: OilChangeLogStitchMetrics.pagePadding,
      ),
      child: OilChangeLogStitchVisitCard(
        row: r,
        selected: selected,
        showSuspended: _showSuspendedLog,
          onTap: () => _onLogRowPrimaryAction(r),
        onDetail: () => unawaited(_showLogRowDetail(r)),
        onResume: _showSuspendedLog
            ? () => unawaited(_openResumeSuspended(r))
            : null,
        onDiscard: _showSuspendedLog
            ? () => unawaited(_confirmAndDiscardSuspended(r))
            : null,
        onAmend: !_showSuspendedLog && _rowHasInvoice(r)
            ? () => unawaited(_openAmendInvoiced(r))
            : null,
        onVoid: !_showSuspendedLog && _rowHasInvoice(r)
            ? () => unawaited(_confirmAndVoidInvoiced(r))
            : null,
      ),
    );
  }

  bool _rowHasInvoice(Map<String, dynamic> r) {
    final invoiceId = (r['invoiceId'] as num?)?.toInt() ?? 0;
    return invoiceId > 0;
  }

  Future<void> _openAmendInvoiced(Map<String, dynamic> r) async {
    final id = _orderIdFromRow(r);
    if (id == null || id <= 0) return;
    if (!_rowHasInvoice(r)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه البطاقة غير مربوطة بفاتورة.')),
      );
      return;
    }

    final pinOk = await confirmOwnerPinForSensitiveAction(
      context,
      title: 'تعديل بطاقة غيار مكتملة',
      message:
          'يتطلب موافقة المالك. سيُعدَّل نفس الفاتورة وقيد الصندوق دون إنشاء فاتورة جديدة. '
          'إن صحّحت رقم الهاتف فقط تُعاد إرسال بطاقة واتساب (قالب ميتا) للرقم الجديد.',
      confirmLabel: 'متابعة التعديل',
      bypassIfElevatedAccess: true,
    );
    if (!mounted || !pinOk) return;

    setState(() => _highlightedId = id);
    final saved = await Navigator.of(context).push<bool>(
      contentMaterialRoute(
        routeId: AppContentRoutes.oilChangeEditId(id),
        breadcrumbTitle: 'تعديل بطاقة مكتملة',
        builder: (_) => OilChangeFormScreen(
          editOrderId: id,
          amendInvoicedOrder: true,
          prefillFromOrder: Map<String, dynamic>.from(r),
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تعديل البطاقة والفاتورة والصندوق')),
      );
      _suppressNextPopRefresh = true;
      _invalidateTabCaches();
      unawaited(_reload(showSpinner: false));
    }
  }

  Future<void> _confirmAndVoidInvoiced(Map<String, dynamic> r) async {
    final id = _orderIdFromRow(r);
    if (id == null || id <= 0) return;
    if (!_rowHasInvoice(r)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه البطاقة غير مربوطة بفاتورة.')),
      );
      return;
    }

    final name = (r['customerNameSnapshot'] ?? '').toString().trim();
    final plate = oilFormatPlate(r);
    final subtitle = [
      if (name.isNotEmpty) name,
      if (plate.isNotEmpty && plate != '—') plate,
    ].join(' · ');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'هل تريد حذف هذه البطاقة؟',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            content: Text(
              subtitle.isEmpty
                  ? 'سيُلغى السجل والفاتورة وقيد الصندوق المرتبط، ويُعاد المخزون إن وُجد.'
                  : 'سيُلغى «$subtitle» من السجل مع الفاتورة وقيد الصندوق، ويُعاد المخزون إن وُجد.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.45),
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('لا'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: OilChangeLogStitchMetrics.error,
                  foregroundColor: Colors.white,
                ),
                child: const Text('نعم، حذف'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || confirmed != true) return;

    final pinOk = await confirmOwnerPinForSensitiveAction(
      context,
      title: 'حذف بطاقة غيار مكتملة',
      message:
          'يتطلب موافقة المالك. سيُبطل الفاتورة والصندوق المرتبطين بهذه البطاقة.',
      confirmLabel: 'تأكيد الحذف',
      destructive: true,
      bypassIfElevatedAccess: true,
    );
    if (!mounted || !pinOk) return;

    try {
      final auth = context.read<AuthProvider>();
      await OilChangePostSaleService.instance.voidOrder(
        orderId: id,
        actorUsername: auth.username.trim().isEmpty ? null : auth.username.trim(),
        actorUserId: auth.userId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف البطاقة وإبطال الفاتورة والصندوق')),
      );
      _invalidateTabCaches();
      unawaited(_reload(showSpinner: false));
    } on OilChangePostSaleException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e, st) {
      AppLogger.error('oil_hub', 'void invoiced failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر حذف البطاقة')),
      );
    }
  }

  int _phoneListItemCount() {
    var n = 0;
    for (final g in _dayGroups) {
      n++;
      if (_expandedDayKeys.contains(g.dayKey)) n += g.rows.length;
    }
    if (_loadingMore) n++;
    return n;
  }

  ({OilChangeDayGroup? group, Map<String, dynamic>? row}) _phoneItemAt(
    int index,
  ) {
    var i = 0;
    for (final g in _dayGroups) {
      if (i == index) return (group: g, row: null);
      i++;
      if (_expandedDayKeys.contains(g.dayKey)) {
        for (final r in g.rows) {
          if (i == index) return (group: g, row: r);
          i++;
        }
      }
    }
    return (group: null, row: null);
  }

  Widget _buildPhoneLogList(
    ScreenLayout layout, {
    bool useNestedPrimaryScroll = false,
  }) {
    return ListView.builder(
      controller: useNestedPrimaryScroll ? null : _scrollController,
      padding: const EdgeInsetsDirectional.only(top: 4, bottom: 24),
      itemCount: _phoneListItemCount(),
      itemBuilder: (context, index) {
        if (_loadingMore && index == _phoneListItemCount() - 1) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final item = _phoneItemAt(index);
        if (item.group != null && item.row == null) {
          return Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 12,
              end: 12,
              bottom: 4,
            ),
            child: _buildDayHeader(context, item.group!),
          );
        }
        if (item.row != null) {
          return _buildMobileLogCard(context, item.row!, layout);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildDesktopLogTable(BuildContext context, double viewportWidth) {
    final tableWidth =
        viewportWidth >= _minTableWidth ? viewportWidth : _minTableWidth;

    return SizedBox(
      width: tableWidth,
      child: _buildGroupedTableCore(context, tableWidth),
    );
  }

  Widget _buildActionButtons(ColorScheme cs, ScreenLayout layout) {
    if (_showSuspendedLog) return const SizedBox.shrink();
    return OilChangeLogStitchActionButtons(
      onNewCard: _openNewCard,
      onWhatsApp: _openWhatsAppMessages,
      stacked: oilChangePreferStackedFields(layout.size.width),
      compactWhatsAppLabel: layout.isPhoneVariant,
      pendingCount: _whatsappPending,
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      decoration: oilChangeLogStitchSearchDecoration(
        hasText: _searchController.text.isNotEmpty,
        onClear: _searchController.clear,
      ),
    );
  }

  Widget _buildLogTabBar() {
    return Material(
      color: OilChangeLogStitchMetrics.surfaceWhite,
      child: TabBar(
        controller: _logTabController,
        indicatorColor: OilChangeLogStitchMetrics.primaryContainer,
        labelColor: OilChangeLogStitchMetrics.textPrimary,
        unselectedLabelColor: OilChangeLogStitchMetrics.textMuted,
        indicatorWeight: 3,
        dividerColor: OilChangeLogStitchMetrics.secondaryContainer
            .withValues(alpha: 0.40),
        tabs: [
          const Tab(text: 'السجل'),
          GuideAnchor(
            id: OilGuideAnchors.hubPendingTab,
            child: const Tab(text: 'المعلّقة'),
          ),
        ],
      ),
    );
  }

  Widget _buildLogDataPanel(
    ColorScheme cs,
    ScreenLayout layout,
    bool useMobileList,
  ) {
    if (useMobileList) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              OilChangeLogStitchMetrics.pagePadding,
              4,
              OilChangeLogStitchMetrics.pagePadding,
              8,
            ),
            child: _buildLogPanelHeader(cs, layout, true),
          ),
          Expanded(child: _buildPhoneLogList(layout)),
        ],
      );
    }

    return Container(
      decoration: OilChangeLogStitchMetrics.panelDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          _buildLogPanelHeader(cs, layout, useMobileList),
          Expanded(
            child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: _buildDesktopLogTable(
                                  context,
                                  constraints.maxWidth,
                                ),
                              ),
                              if (_loadingMore)
                                const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneNestedPlaceholder(Widget child) {
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: child,
        ),
      ],
    );
  }

  Widget _buildPhoneNestedBody(
    ColorScheme cs,
    ScreenLayout layout,
    double pagePad,
  ) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onPhoneScrollNotification,
      child: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverPersistentHeader(
            pinned: true,
            delegate: _OilChangeLogSearchSliverDelegate(
              extent: _phoneSearchHeaderExtent,
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(pagePad, 8, pagePad, 8),
                child: _buildSearchField(),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
                _buildLogTabBar(),
                if (!_showSuspendedLog)
          Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(pagePad, 8, pagePad, 8),
                    child: _buildActionButtons(cs, layout),
                  ),
                if (!_loading && _error == null && _logs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      OilChangeLogStitchMetrics.pagePadding,
                      0,
                      OilChangeLogStitchMetrics.pagePadding,
                      8,
                    ),
                    child: _buildLogPanelHeader(cs, layout, true),
                  ),
              ],
            ),
          ),
        ],
        body: _buildMainLogSection(
          cs,
          layout,
          true,
          nestedPhoneBody: true,
        ),
      ),
    );
  }

  Widget _buildMainLogSection(
    ColorScheme cs,
    ScreenLayout layout,
    bool useMobileList, {
    bool nestedPhoneBody = false,
  }) {
    if (nestedPhoneBody) {
      if (_loading) {
        return _buildPhoneNestedPlaceholder(
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          ),
        );
      }
      if (_error != null) {
        return _buildPhoneNestedPlaceholder(_buildErrorView(cs));
      }
      if (_logs.isEmpty) {
        return _buildPhoneNestedPlaceholder(_buildEmptyView(cs, layout));
      }
      return _buildPhoneLogList(layout, useNestedPrimaryScroll: true);
    }

    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_error != null) {
      return _buildErrorView(cs);
    }
    if (_logs.isEmpty) {
      return _buildEmptyView(cs, layout);
    }

    return _buildLogDataPanel(cs, layout, useMobileList);
  }

  Widget _buildDesktopToolbar() {
    if (_showSuspendedLog) {
      return _buildSearchField();
    }
    final pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
    );
    return Row(
      children: [
        Expanded(child: _buildSearchField()),
        const SizedBox(width: 12),
        // نفس زر «إرسال واتساب» الموجود على الهاتف — سجل الإرسال والرسائل المعلّقة.
        FilledButton.icon(
          onPressed: () => unawaited(_openWhatsAppMessages()),
          style: FilledButton.styleFrom(
            backgroundColor: OilChangeLogStitchMetrics.secondaryContainer,
            foregroundColor: OilChangeLogStitchMetrics.onSecondaryContainer,
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 18,
              vertical: 14,
            ),
            shape: pill,
          ),
          icon: _whatsappPending > 0
              ? Badge.count(
                  count: _whatsappPending,
                  child: const Icon(Icons.chat_rounded),
                )
              : const Icon(Icons.chat_rounded),
          label: const Text(
            'إرسال واتساب',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        GuideAnchor(
          id: OilGuideAnchors.hubNewCard,
          child: FilledButton.icon(
            onPressed: _openNewCard,
            style: FilledButton.styleFrom(
              backgroundColor: OilChangeLogStitchMetrics.primaryContainer,
              foregroundColor: Colors.white,
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
              shape: pill,
            ),
            icon: const Icon(Icons.add_circle_rounded),
            label: const Text(
              'سجل تبديل زيت جديد',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final layout = context.screenLayout;
    final useMobileList = !layout.isDesktopVariant;
    final pagePad = layout.pageHorizontalGap;

    final appBar = OilChangeFormTheme.appBar(
      context: context,
      title: 'سجل غيارات الزيت',
      actions: [
        GuideAnchor(
          id: OilGuideAnchors.hubWhatsappConnect,
          child: IconButton(
            tooltip: 'ربط واتساب المحل',
            onPressed: () => unawaited(_openWhatsappConnect()),
            icon: const WhatsappGlyphIcon(),
          ),
        ),
        IconButton(
          tooltip: 'بيع مباشر',
          onPressed: () {
            Navigator.of(context).push(
              FastContentPageRoute<void>(
                settings: const RouteSettings(
                  name: AppContentRoutes.oilDirectSale,
                ),
                builder: (_) => const OilChangeDirectSaleScreen(),
              ),
            );
          },
          icon: const Icon(Icons.point_of_sale_rounded),
        ),
        IconButton(
          tooltip: 'تحديث السجل',
          onPressed: _loading ? null : () => unawaited(_reload()),
          icon: const Icon(Icons.refresh_rounded),
        ),
        GuideAnchor(
          id: OilGuideAnchors.hubSettings,
          child: IconButton(
            tooltip: 'إعدادات غيار الزيت',
            onPressed: () => unawaited(_openHubSettings()),
            icon: const Icon(Icons.tune_rounded),
          ),
        ),
      ],
    );

    return Theme(
      data: OilChangeFormTheme.wrap(context, Theme.of(context)),
      child: Consumer<GuideController>(
        builder: (context, guide, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _syncGuidePendingTab(guide);
            _syncGuideHubSettings(guide);
          });
          return Scaffold(
        backgroundColor: OilChangeLogStitchMetrics.background,
        appBar: appBar,
        body: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
          if (_waGatewayDisconnected)
            MaterialBanner(
              backgroundColor: cs.errorContainer,
              content: Text(
                OilChangeWhatsappUserMessages.gatewayDisconnectedBanner,
                style: TextStyle(color: cs.onErrorContainer),
              ),
              leading: Icon(Icons.link_off_rounded, color: cs.error),
              actions: [
                TextButton(
                  onPressed: () => unawaited(_openWhatsappConnect()),
                  child: const Text('إعادة الربط'),
                ),
                TextButton(
                  onPressed: () => unawaited(_openHubSettings()),
                  child: const Text('الإعدادات'),
                                                        ),
                                                    ],
                                                  ),
          if (useMobileList) ...[
            if (layout.isPhoneVariant)
              Expanded(child: _buildPhoneNestedBody(cs, layout, pagePad))
            else ...[
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(pagePad, 8, pagePad, 8),
                child: _buildSearchField(),
              ),
              _buildLogTabBar(),
              if (!_showSuspendedLog)
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(pagePad, 8, pagePad, 8),
                  child: _buildActionButtons(cs, layout),
                                  ),
                                  Expanded(
                child: _buildMainLogSection(cs, layout, useMobileList),
              ),
            ],
          ] else
            Expanded(
              child: LayoutBuilder(
                                            builder: (context, constraints) {
                  final keyboardOpen =
                      MediaQuery.viewInsetsOf(context).bottom > 0;
                  final showKpi =
                      !keyboardOpen &&
                      constraints.maxHeight > 280 &&
                      !_showSuspendedLog &&
                      _logs.isNotEmpty &&
                      !_loading &&
                      _error == null;

                  // دائماً أبقِ البحث + التبويبات ظاهرة — وإلا عند «لا معلّقات»
                  // تختفي التبويبات ولا يمكن الرجوع للسجل بدون إغلاق الصفحة.
                  return ListView(
                                                controller: _scrollController,
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      24,
                      12,
                      24,
                      16,
                    ),
                    children: [
                      _buildDesktopToolbar(),
                      const SizedBox(height: 8),
                      _buildLogTabBar(),
                      const SizedBox(height: 12),
                      if (_loading)
                                                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_error != null)
                        _buildErrorView(cs)
                      else if (_logs.isEmpty)
                        _buildEmptyView(cs, layout)
                      else ...[
                        if (showKpi) ...[
                          OilChangeLogStitchDesktopKpiRow(
                            stats: OilChangeLogStitchTodayStats.fromDayGroups(
                              _dayGroups,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        OilChangeLogStitchDesktopTableCard(
                          rows: _logs,
                          highlightedId: _highlightedId,
                          loadingMore: _loadingMore,
                          loadedCount: _logs.length,
                          showSuspended: _showSuspendedLog,
                          onRowTap: _onLogRowPrimaryAction,
                          onRowDetail: (r) =>
                              unawaited(_showLogRowDetail(r)),
                          onRefresh: () => unawaited(_reload()),
                          onRowResume: _showSuspendedLog
                              ? (r) => unawaited(_openResumeSuspended(r))
                              : null,
                          onRowDiscard: _showSuspendedLog
                              ? (r) => unawaited(
                                    _confirmAndDiscardSuspended(r),
                                  )
                              : null,
                          onRowAmend: _showSuspendedLog
                              ? null
                              : (r) {
                                  if (_rowHasInvoice(r)) {
                                    unawaited(_openAmendInvoiced(r));
                                  }
                                },
                          onRowVoid: _showSuspendedLog
                              ? null
                              : (r) {
                                  if (_rowHasInvoice(r)) {
                                    unawaited(_confirmAndVoidInvoiced(r));
                                  }
                                },
                        ),
                      ],
                    ],
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
      );
        },
      ),
    );
  }
}

class _OilChangeLogSearchSliverDelegate extends SliverPersistentHeaderDelegate {
  const _OilChangeLogSearchSliverDelegate({
    required this.extent,
    required this.child,
  });

  final double extent;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: OilChangeLogStitchMetrics.background,
      elevation: overlapsContent ? 0.5 : 0,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _OilChangeLogSearchSliverDelegate oldDelegate) {
    return oldDelegate.extent != extent || oldDelegate.child != child;
  }
}

/// لوحة إعدادات السجل — مفاتيح تشغيل بدل قائمة ⋮.
class _OilChangeHubSettingsSheet extends StatefulWidget {
  const _OilChangeHubSettingsSheet();

  @override
  State<_OilChangeHubSettingsSheet> createState() =>
      _OilChangeHubSettingsSheetState();
}

class _OilChangeHubSettingsSheetState extends State<_OilChangeHubSettingsSheet> {
  static const _royalGold = SaleBrandColors.gold;

  bool _loading = true;
  bool _stockFromWarehouse = true;
  bool _hydraulicStockFromWarehouse = true;
  final Map<OilOptionalExtraKind, bool> _optionalExtras = {
    for (final k in OilOptionalExtraKind.values) k: true,
  };
  bool _whatsappAutoAfterSave = false;
  bool _whatsappManualAfterSave = false;
  bool _whatsappAskRating = true;
  bool _whatsappAiAutoReply = true;
  bool _waGatewayConnected = false;
  String? _busyKey;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    // إعدادات محلية فقط — لا نعلّق الورقة على شبكة واتساب.
    final results = await Future.wait<Object?>([
      OilChangeSettings.stockFromWarehouseEnabled(),
      OilChangeSettings.hydraulicStockFromWarehouseEnabled(),
      OilChangeSettings.loadOptionalExtraFlags(),
      OilChangeSettings.whatsappAutoAfterSaveEnabled(),
      OilChangeSettings.whatsappManualAfterSaveEnabled(),
      OilChangeSettings.whatsappAskRatingAfterSaveEnabled(),
      OilChangeWhatsappStatusStore.instance.readStatus(refreshFromServer: false),
    ]);
    if (!mounted) return;

    var waAuto = results[3] as bool;
    var waManual = results[4] as bool;
    if (waAuto && waManual) {
      await OilChangeSettings.setWhatsappManualAfterSave(false);
      waManual = false;
    }
    final waStatus = results[6] as OilChangeWhatsappGatewayStatus;
    final extras =
        Map<OilOptionalExtraKind, bool>.from(
          results[2] as Map<OilOptionalExtraKind, bool>,
        );

    setState(() {
      _stockFromWarehouse = results[0] as bool;
      _hydraulicStockFromWarehouse = results[1] as bool;
      _optionalExtras
        ..clear()
        ..addAll(extras);
      _whatsappAutoAfterSave = waAuto;
      _whatsappManualAfterSave = waManual;
      _whatsappAskRating = results[5] as bool;
      _waGatewayConnected =
          waStatus == OilChangeWhatsappGatewayStatus.connected;
      _loading = false;
    });
    unawaited(_refreshAiAutoReplyInBackground());
    unawaited(_refreshWhatsappGatewayInBackground());
  }

  Future<void> _refreshAiAutoReplyInBackground() async {
    try {
      final enabled = await OilChangeWhatsappGatewayRepository.instance
          .fetchRatingAutoReplyEnabled();
      if (!mounted || enabled == _whatsappAiAutoReply) return;
      setState(() => _whatsappAiAutoReply = enabled);
    } catch (_) {}
  }

  Future<void> _refreshWhatsappGatewayInBackground() async {
    try {
      await OilChangeWhatsappStatusStore.instance.syncFromCloudIfPossible();
      if (!mounted) return;
      final waStatus = await OilChangeWhatsappStatusStore.instance.readStatus(
        refreshFromServer: false,
      );
      if (!mounted) return;
      final connected = waStatus == OilChangeWhatsappGatewayStatus.connected;
      if (connected == _waGatewayConnected) return;
      setState(() => _waGatewayConnected = connected);
    } catch (_) {}
  }

  Future<void> _setStock(bool value) async {
    setState(() {
      _stockFromWarehouse = value;
      _busyKey = 'stock';
    });
    await OilChangeSettings.setStockFromWarehouse(value);
    if (mounted) setState(() => _busyKey = null);
  }

  Future<void> _setHydraulicStock(bool value) async {
    setState(() {
      _hydraulicStockFromWarehouse = value;
      _busyKey = 'hyd_stock';
    });
    await OilChangeSettings.setHydraulicStockFromWarehouse(value);
    if (mounted) setState(() => _busyKey = null);
  }

  Future<void> _setOptionalExtra(OilOptionalExtraKind kind, bool value) async {
    setState(() {
      _optionalExtras[kind] = value;
      _busyKey = kind.settingsKey;
    });
    await OilChangeSettings.setOptionalExtra(kind, value);
    if (mounted) setState(() => _busyKey = null);
  }

  Future<void> _setWhatsAppAuto(bool value) async {
    setState(() {
      _whatsappAutoAfterSave = value;
      if (value) _whatsappManualAfterSave = false;
      _busyKey = 'wa_auto';
    });
    await OilChangeSettings.setWhatsappAutoAfterSave(value);
    if (mounted) setState(() => _busyKey = null);
  }

  Future<void> _setWhatsAppManual(bool value) async {
    setState(() {
      _whatsappManualAfterSave = value;
      if (value) _whatsappAutoAfterSave = false;
      _busyKey = 'wa_manual';
    });
    await OilChangeSettings.setWhatsappManualAfterSave(value);
    if (mounted) setState(() => _busyKey = null);
  }

  Future<void> _setWhatsAppAskRating(bool value) async {
    setState(() {
      _whatsappAskRating = value;
      _busyKey = 'wa_rating';
    });
    await OilChangeSettings.setWhatsappAskRatingAfterSave(value);
    if (mounted) setState(() => _busyKey = null);
  }

  Future<void> _setWhatsAppAiAutoReply(bool value) async {
    setState(() {
      _whatsappAiAutoReply = value;
      _busyKey = 'wa_ai_reply';
    });
    final ok = await OilChangeWhatsappGatewayRepository.instance
        .setRatingAutoReplyEnabled(value);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _whatsappAiAutoReply = !value;
        _busyKey = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر حفظ إعداد الرد التلقائي — تحقق من الاتصال'),
        ),
      );
      return;
    }
    setState(() => _busyKey = null);
  }

  Widget _settingSwitch({
    required ColorScheme cs,
    required String key,
    String? anchorId,
    required IconData icon,
    required String title,
    required String subtitleOn,
    required String subtitleOff,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final busy = _busyKey == key;
    final tile = SwitchListTile(
      value: value,
      onChanged: busy ? null : onChanged,
      secondary: Icon(icon, color: value ? _royalGold : cs.onSurfaceVariant),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(
        value ? subtitleOn : subtitleOff,
        style:
            TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.35),
        textAlign: TextAlign.start,
      ),
    );
    final id = anchorId;
    if (id == null || id.isEmpty) return tile;
    return GuideAnchor(id: id, child: tile);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final layout = context.screenLayout;
    final maxW = layout.isHandsetForLayout ? double.infinity : 440.0;
    final sheetMaxH =
        layout.size.height * (layout.isHandsetForLayout ? 0.92 : 0.85);

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(12, 0, 12, 12 + bottom),
      child: Align(
        alignment: AlignmentDirectional.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW, maxHeight: sheetMaxH),
          child: Material(
            color: cs.surface,
            elevation: 12,
            shadowColor: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _royalGold.withValues(alpha: 0.78),
                  width: 2,
                ),
                boxShadow: oilChangeGoldGlowOf(
                  context,
                    blurRadius: 18,
                  offset: const Offset(0, 4),
                  ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 8),
                    child: Row(
                      children: [
                        Icon(Icons.tune_rounded, color: _royalGold, size: 22),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'إعدادات غيار الزيت',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                            textAlign: TextAlign.start,
                          ),
                        ),
                        IconButton(
                          tooltip: 'إغلاق',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  if (_loading)
                    const Expanded(
                      child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  else
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsetsDirectional.only(bottom: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                    Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                12,
                                0,
                                12,
                                16,
                              ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _royalGold.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _royalGold.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Column(
                          children: [
                            _settingSwitch(
                              cs: cs,
                              key: 'stock',
                                      anchorId: OilGuideAnchors.settingsStockOil,
                              icon: Icons.inventory_2_outlined,
                              title: 'صرف الزيت من المخزون',
                              subtitleOn:
                                  'اختيار صنف من المخزون وخصم اللترات عند الحفظ',
                              subtitleOff:
                                  'تسجيل الزيت يدوياً فقط — بدون خصم مخزون',
                              value: _stockFromWarehouse,
                              onChanged: (v) => unawaited(_setStock(v)),
                            ),
                            Divider(
                              height: 1,
                              color: _royalGold.withValues(alpha: 0.22),
                            ),
                            _settingSwitch(
                              cs: cs,
                              key: 'hyd_stock',
                                      anchorId:
                                          OilGuideAnchors.settingsStockHydraulic,
                              icon: Icons.water_drop_outlined,
                              title: 'صرف الهيدروليك من المخزون',
                              subtitleOn:
                                  'اختيار عائلة هيدروليك من المخزون وخصم اللترات عند الحفظ',
                              subtitleOff:
                                  'تسجيل الهيدروليك يدوياً فقط — بدون خصم مخزون',
                              value: _hydraulicStockFromWarehouse,
                              onChanged: (v) =>
                                  unawaited(_setHydraulicStock(v)),
                            ),
                            Divider(
                              height: 1,
                              color: _royalGold.withValues(alpha: 0.22),
                            ),
                            ...[
                              for (var i = 0;
                                  i < OilOptionalExtraKind.values.length;
                                  i++) ...[
                                if (i > 0)
                                  Divider(
                                    height: 1,
                                    color: _royalGold.withValues(alpha: 0.22),
                                  ),
                                Builder(
                                  builder: (context) {
                                    final kind =
                                        OilOptionalExtraKind.values[i];
                                    return _settingSwitch(
                                      cs: cs,
                                      key: kind.settingsKey,
                                      anchorId: i == 0
                                          ? OilGuideAnchors
                                              .settingsOptionalExtras
                                          : null,
                                      icon: kind.icon,
                                      title: kind.titleAr,
                                      subtitleOn: kind.subtitleOn,
                                      subtitleOff: kind.subtitleOff,
                                      value: _optionalExtras[kind] ?? true,
                                      onChanged: (v) =>
                                          unawaited(_setOptionalExtra(kind, v)),
                                    );
                                  },
                                ),
                              ],
                            ],
                            Divider(
                              height: 1,
                              color: _royalGold.withValues(alpha: 0.22),
                            ),
                            _settingSwitch(
                              cs: cs,
                                      key: 'wa_auto',
                                      anchorId: OilGuideAnchors.settingsWaAuto,
                                      icon: Icons.send_rounded,
                                      title: 'إرسال تلقائي للزبون (واتساب المحل)',
                                      subtitleOn: _waGatewayConnected
                                          ? OilChangeWhatsappUserMessages
                                              .settingsWhatsappAutoHintConnected
                                          : OilChangeWhatsappUserMessages
                                              .settingsWhatsappAutoHintDisconnected,
                                      subtitleOff:
                                          OilChangeWhatsappUserMessages
                                              .settingsWhatsappAutoHintOff,
                                      value: _whatsappAutoAfterSave,
                                      onChanged: (v) =>
                                          unawaited(_setWhatsAppAuto(v)),
                                    ),
                                    Divider(
                                      height: 1,
                                      color: _royalGold.withValues(alpha: 0.22),
                                    ),
                                    _settingSwitch(
                                      cs: cs,
                                      key: 'wa_manual',
                                      anchorId:
                                          OilGuideAnchors.settingsWaManual,
                              icon: Icons.chat_rounded,
                                      title: 'فتح واتساب يدوياً بعد الحفظ',
                                      subtitleOn: OilChangeWhatsappUserMessages
                                          .settingsWhatsappManualHintOn,
                                      subtitleOff: OilChangeWhatsappUserMessages
                                          .settingsWhatsappManualHintOff,
                                      value: _whatsappManualAfterSave,
                                      onChanged: (v) =>
                                          unawaited(_setWhatsAppManual(v)),
                                    ),
                                    Divider(
                                      height: 1,
                                      color: _royalGold.withValues(alpha: 0.22),
                                    ),
                                    _settingSwitch(
                                      cs: cs,
                                      key: 'wa_rating',
                                      anchorId:
                                          OilGuideAnchors.settingsWaRating,
                                      icon: Icons.star_rate_rounded,
                                      title: 'طلب تقييم من الزبون في الرسالة',
                              subtitleOn:
                                          'في نهاية الرسالة يُطلب تقييم من 1 إلى 10 أو ملاحظة قصيرة',
                                      subtitleOff:
                                          'بدون دعوة تقييم — الرسالة تنتهي بالخاتمة فقط',
                                      value: _whatsappAskRating,
                                      onChanged: (v) =>
                                          unawaited(_setWhatsAppAskRating(v)),
                                    ),
                                    Divider(
                                      height: 1,
                                      color: _royalGold.withValues(alpha: 0.22),
                                    ),
                                    _settingSwitch(
                                      cs: cs,
                                      key: 'wa_ai_reply',
                                      icon: Icons.smart_toy_rounded,
                                      title: 'رد تلقائي ذكي داخل واتساب',
                                      subtitleOn:
                                          'يجاوب الزبون تلقائياً في المحادثة (تحية وأسئلة البطاقة)',
                                      subtitleOff:
                                          'الرد التلقائي متوقف — لا يجيب الذكاء الاصطناعي في واتساب',
                                      value: _whatsappAiAutoReply,
                                      onChanged: (v) =>
                                          unawaited(_setWhatsAppAiAutoReply(v)),
                                    ),
                                    Divider(
                                      height: 1,
                                      color: _royalGold.withValues(alpha: 0.22),
                                    ),
                                    GuideAnchor(
                                      id: OilGuideAnchors.settingsWaConnect,
                                      child: ListTile(
                                        leading: Icon(
                                          Icons.qr_code_2_rounded,
                                          color: cs.primary,
                                        ),
                                        title: const Text('ربط واتساب المحل'),
                                        subtitle: Text(
                                          _waGatewayConnected
                                              ? 'متصل — متاح لكل المستخدمين'
                                              : 'غير متصل — اضغط لمسح QR',
                                          textAlign: TextAlign.start,
                                        ),
                                        trailing:
                                            const Icon(Icons.chevron_left),
                                        onTap: () {
                                          Navigator.pop(context);
                                          unawaited(
                                            Navigator.of(context).push<void>(
                                              contentMaterialRoute(
                                                routeId: AppContentRoutes
                                                    .oilWhatsappConnect,
                                                breadcrumbTitle:
                                                    'ربط واتساب المحل',
                                                builder: (_) =>
                                                    const OilChangeWhatsappConnectScreen(),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                20,
                                0,
                                20,
                                18,
                              ),
                      child: Text(
                        'تُطبَّق على بطاقات الغيار الجديدة في هذا المحل.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                        textAlign: TextAlign.start,
                      ),
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
      ),
    );
  }
}

/// كاش تبويب سجل غيار الزيت — للتبديل الفوري بين السجل والمعلّقة.
class _OilLogTabCache {
  final List<Map<String, dynamic>> logs = <Map<String, dynamic>>[];
  List<OilChangeDayGroup> dayGroups = <OilChangeDayGroup>[];
  Set<String> expandedDayKeys = <String>{};
  bool hasMore = true;
  bool loadedOnce = false;
  Object? error;
  double scrollOffset = 0;

  void clear() {
    logs.clear();
    dayGroups = <OilChangeDayGroup>[];
    expandedDayKeys = <String>{};
    hasMore = true;
    loadedOnce = false;
    error = null;
    scrollOffset = 0;
  }
}
