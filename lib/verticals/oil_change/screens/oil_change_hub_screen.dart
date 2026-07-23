import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/oil_change_whatsapp_config.dart';
import '../../../navigation/app_route_observer.dart';
import '../../../navigation/content_navigation.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/cloud_sync_service.dart';
import '../../../services/database_helper.dart';
import '../services/oil_change_settings.dart';
import '../services/oil_change_whatsapp_status_store.dart';
import 'oil_change_whatsapp_connect_screen.dart';
import '../../../services/print_settings_repository.dart';
import '../../../services/service_orders_repository.dart';
import '../../../services/tenant_context_service.dart';
import '../../../utils/app_logger.dart';
import '../utils/oil_change_log_format.dart';
import '../utils/oil_change_log_grouping.dart';
import '../utils/oil_change_whatsapp_user_messages.dart';
import '../utils/oil_change_order_status.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/sale_brand.dart';
import '../../../utils/screen_layout.dart';
import '../widgets/oil_change_form_theme.dart';
import '../widgets/oil_change_log_detail_sheet.dart';
import '../widgets/oil_change_log_stitch.dart';
import '../widgets/oil_change_whatsapp_campaign_progress.dart';
import 'oil_change_whatsapp_campaign_screen.dart';
import 'oil_change_whatsapp_resend_screen.dart';
import 'oil_change_form_screen.dart';

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
  late final TabController _logTabController;
  static const double _phoneSearchHeaderExtent = 64;

  OilChangeLogStatusFilter get _logStatusFilter =>
      _logTabController.index == 1
          ? OilChangeLogStatusFilter.suspended
          : OilChangeLogStatusFilter.active;

  bool get _showSuspendedLog =>
      _logStatusFilter == OilChangeLogStatusFilter.suspended;

  void _rebuildDayGroups() {
    final groups = groupOilChangeLogsByDay(_logs);
    final defaults = defaultExpandedOilChangeDayKeys(groups);
    if (_expandedDayKeys.isEmpty) {
      _expandedDayKeys = defaults;
    } else {
      final valid = groups.map((g) => g.dayKey).toSet();
      _expandedDayKeys = {
        ..._expandedDayKeys.where(valid.contains),
        ...defaults,
      };
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
    unawaited(_reload());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshSilently());
    }
  }

  @override
  void didPopNext() {
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
      unawaited(_reload());
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
    await DatabaseHelper().ensureDefaultTenantSeedIfNeeded();
    await DatabaseHelper().ensureServiceOrdersReadRepair();
    final tenantCtx = TenantContextService.instance;
    if (!tenantCtx.loaded) {
      await tenantCtx.load();
    }

    final rows = await ServiceOrdersRepository.instance.getOilChangeLogPage(
      searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      afterId: afterId,
      limit: 50,
      statusFilter: _logStatusFilter,
    );
    return rows;
  }

  void _replaceFirstPage(List<Map<String, dynamic>> rows) {
    _logs
      ..clear()
      ..addAll(rows);
    _hasMore = rows.length >= 50;
    _rebuildDayGroups();
  }

  /// تحديث خلفي دون شاشة تحميل كاملة — عند العودة للسجل أو بعد المزامنة.
  Future<void> _refreshSilently() async {
    if (!mounted || _loading) return;
    try {
      final rows = await _fetchLogPage();
      if (!mounted) return;
      setState(() => _replaceFirstPage(rows));
    } catch (e) {
      AppLogger.warn('oil_change_hub', 'silent refresh failed: $e');
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _hasMore = true;
    });
    try {
      final rows = await _fetchLogPage();
      final waDisconnected =
          await OilChangeWhatsappStatusStore.instance.isDisconnectedBannerVisible();
      await OilChangeWhatsappStatusStore.instance.syncFromCloudIfPossible();
      final waDisconnectedAfterSync =
          await OilChangeWhatsappStatusStore.instance.isDisconnectedBannerVisible();
      if (!mounted) return;
      setState(() {
        _replaceFirstPage(rows);
        _waGatewayDisconnected = waDisconnectedAfterSync || waDisconnected;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.error('oil_change_hub', 'reload failed', e, st);
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
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
        _hasMore = rows.length >= 50;
        _loadingMore = false;
        _rebuildDayGroups();
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
        builder: (_) => OilChangeFormScreen(editOrderId: id),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم استكمال البطاقة وإنشاء الفاتورة')),
      );
      unawaited(_reload());
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

  /// زر واتساب في السجل:
  /// - حملة جماعية: فقط إذا الـ flag مفتوح + المستخدم مالك
  /// - وإلا: قائمة إعادة إرسال فردية (موظف ومالك)
  Future<void> _openWhatsAppEntry() async {
    if (_showSuspendedLog) return;
    final isOwner = context.read<AuthProvider>().isOwner;
    final openCampaign =
        OilChangeWhatsappConfig.campaignUiEnabled && isOwner;
    if (openCampaign) {
      final printData = await PrintSettingsRepository.instance.load();
      if (!mounted) return;
      await OilChangeWhatsappCampaignScreen.open(
        context,
        storeTitle: printData.whatsappStoreTitle,
        gatewayConnected: !_waGatewayDisconnected,
      );
      return;
    }
    await OilChangeWhatsappResendScreen.open(context);
  }

  Future<void> _openWhatsappConnect() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const OilChangeWhatsappConnectScreen(),
      ),
    );
    if (!mounted) return;
    await OilChangeWhatsappStatusStore.instance.syncFromCloudIfPossible();
    final disconnected =
        await OilChangeWhatsappStatusStore.instance.isDisconnectedBannerVisible();
    setState(() => _waGatewayDisconnected = disconnected);
  }

  Future<void> _openHubSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => const _OilChangeHubSettingsSheet(),
    );
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
      ),
    );
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
      onWhatsApp: _openWhatsAppEntry,
      stacked: layout.isPhoneXS,
      compactWhatsAppLabel: layout.isPhoneVariant,
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
        tabs: const [
          Tab(text: 'السجل'),
          Tab(text: 'المعلّقة'),
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
    return Row(
      children: [
        Expanded(child: _buildSearchField()),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: _openNewCard,
          style: FilledButton.styleFrom(
            backgroundColor: OilChangeLogStitchMetrics.primaryContainer,
            foregroundColor: Colors.white,
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 20,
              vertical: 14,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          icon: const Icon(Icons.add_circle_rounded),
          label: const Text(
            'سجل تبديل زيت جديد',
            style: TextStyle(fontWeight: FontWeight.w800),
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
        IconButton(
          tooltip: 'ربط واتساب المحل',
          onPressed: () => unawaited(_openWhatsappConnect()),
          icon: const Icon(Icons.qr_code_2_rounded),
        ),
        IconButton(
          tooltip: 'تحديث السجل',
          onPressed: _loading ? null : () => unawaited(_reload()),
          icon: const Icon(Icons.refresh_rounded),
        ),
        IconButton(
          tooltip: 'إعدادات غيار الزيت',
          onPressed: () => unawaited(_openHubSettings()),
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    );

    return Theme(
      data: OilChangeFormTheme.wrap(context, Theme.of(context)),
      child: Scaffold(
        backgroundColor: OilChangeLogStitchMetrics.background,
        appBar: appBar,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Column(
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
                      !keyboardOpen && constraints.maxHeight > 280;

                  if (_loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (_error != null) {
                    return _buildErrorView(cs);
                  }
                  if (_logs.isEmpty) {
                    return _buildEmptyView(cs, layout);
                  }

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
                        onRowTap: _onLogRowPrimaryAction,
                        onRowDetail: (r) => unawaited(_showLogRowDetail(r)),
                        onRefresh: () => unawaited(_reload()),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
        ),
            if (OilChangeWhatsappConfig.campaignUiEnabled)
              const OilChangeWhatsappCampaignProgressLayer(),
          ],
        ),
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
  bool _whatsappAutoAfterSave = false;
  bool _whatsappManualAfterSave = false;
  bool _waGatewayConnected = false;
  String? _busyKey;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final stock = await OilChangeSettings.stockFromWarehouseEnabled();
    final hydStock =
        await OilChangeSettings.hydraulicStockFromWarehouseEnabled();
    final waAuto = await OilChangeSettings.whatsappAutoAfterSaveEnabled();
    var waManual = await OilChangeSettings.whatsappManualAfterSaveEnabled();
    if (waAuto && waManual) {
      await OilChangeSettings.setWhatsappManualAfterSave(false);
      waManual = false;
    }
    await OilChangeWhatsappStatusStore.instance.syncFromCloudIfPossible();
    final waStatus = await OilChangeWhatsappStatusStore.instance.readStatus(
      refreshFromServer: true,
    );
    if (!mounted) return;
    setState(() {
      _stockFromWarehouse = stock;
      _hydraulicStockFromWarehouse = hydStock;
      _whatsappAutoAfterSave = waAuto;
      _whatsappManualAfterSave = waManual;
      _waGatewayConnected =
          waStatus == OilChangeWhatsappGatewayStatus.connected;
      _loading = false;
    });
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

  Widget _settingSwitch({
    required ColorScheme cs,
    required String key,
    required IconData icon,
    required String title,
    required String subtitleOn,
    required String subtitleOff,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final busy = _busyKey == key;
    return SwitchListTile(
      value: value,
      onChanged: busy ? null : onChanged,
      secondary: Icon(icon, color: value ? _royalGold : cs.onSurfaceVariant),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(
        value ? subtitleOn : subtitleOff,
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.35),
        textAlign: TextAlign.start,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    final bottom = mq.padding.bottom;
    final layout = context.screenLayout;
    final maxW = layout.isHandsetForLayout ? double.infinity : 440.0;
    final sheetMaxH = mq.size.height * (layout.isHandsetForLayout ? 0.92 : 0.85);

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
                boxShadow: const [
                  BoxShadow(
                    color: AppGlass.goldGlow,
                    blurRadius: 18,
                    offset: Offset(0, 4),
                  ),
                ],
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
                                    _settingSwitch(
                                      cs: cs,
                                      key: 'wa_auto',
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
                                    ListTile(
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
                                      trailing: const Icon(Icons.chevron_left),
                                      onTap: () {
                                        Navigator.pop(context);
                                        unawaited(
                                          Navigator.of(context).push<void>(
                                            MaterialPageRoute<void>(
                                              builder: (_) =>
                                                  const OilChangeWhatsappConnectScreen(),
                                            ),
                                          ),
                                        );
                                      },
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
