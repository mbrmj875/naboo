import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/restaurant_models.dart';
import '../services/floors_tables_repository.dart';
import '../services/restaurant_qr_service.dart';
import '../services/restaurant_tenant_slug_service.dart';
import '../services/table_fsm_service.dart';
import '../theme/restaurant_os_tokens.dart';
import '../utils/wall_path.dart';
import '../widgets/floor_plan_painters.dart';

const int _kLayoutMax = 10000;
/// مساحة تصميم واسعة — يمكنك التحرك بحرية في كل الاتجاهات.
const double _kVirtualCanvasW = 4800;
const double _kVirtualCanvasH = 3600;

Size get _virtualCanvas => const Size(_kVirtualCanvasW, _kVirtualCanvasH);

enum _EditTool { select, table, fixture }

/// ترتيب القاعة — مخطّط حر باحترافية (طاولات مرسومة + عناصر معمارية).
class FloorMapScreen extends StatefulWidget {
  const FloorMapScreen({super.key});

  @override
  State<FloorMapScreen> createState() => _FloorMapScreenState();
}

class _FloorMapScreenState extends State<FloorMapScreen> {
  final _floorsRepo = FloorsTablesRepository();
  final _fsm = TableFSMService();
  final _viewerController = TransformationController();
  final _canvasHostKey = GlobalKey();

  bool _loading = true;
  bool _busyMutating = false;
  String? _error;
  List<RestaurantFloor> _floors = const [];
  List<RestaurantTable> _tables = const [];
  List<RestaurantFloorFixture> _fixtures = const [];
  int? _selectedFloorId;
  RestaurantTable? _selectedTable;
  RestaurantFloorFixture? _selectedFixture;
  String? _tenantSlug;
  bool _editLayout = false;
  bool _previewFinalFrame = false;
  bool _didInitialFit = false;
  _EditTool _tool = _EditTool.select;
  RestaurantFloorFixtureKind _fixtureKind = RestaurantFloorFixtureKind.cashier;
  int _draftSeats = 4;
  RestaurantTableSeatStyle _draftSeatStyle = RestaurantTableSeatStyle.center;
  Timer? _occupiedTick;

  @override
  void initState() {
    super.initState();
    _occupiedTick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      if (_tables.any((t) => t.sessionOpenedAt != null)) {
        setState(() {});
      }
    });
    _reload(showLoading: true).then((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitCanvasToView());
    });
  }

  @override
  void dispose() {
    _occupiedTick?.cancel();
    _viewerController.dispose();
    super.dispose();
  }

  Future<void> _reload({bool showLoading = false}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final slug = await RestaurantTenantSlugService.resolveForCurrentTenant();
      final floors = await _floorsRepo.listFloors();
      var floorId = _selectedFloorId;
      if (floorId == null && floors.isNotEmpty) {
        floorId = floors.first.id;
      }
      final tables = await _floorsRepo.listTables(floorId: floorId);
      final fixtures = floorId == null
          ? const <RestaurantFloorFixture>[]
          : await _floorsRepo.listFixtures(floorId: floorId);
      if (!mounted) return;
      RestaurantTable? selected = _selectedTable;
      if (selected != null) {
        selected = tables.where((t) => t.id == selected!.id).firstOrNull;
      }
      RestaurantFloorFixture? selFix = _selectedFixture;
      if (selFix != null) {
        selFix = fixtures.where((f) => f.id == selFix!.id).firstOrNull;
      }
      setState(() {
        _tenantSlug = slug;
        _floors = floors;
        _tables = tables;
        _fixtures = fixtures;
        _selectedFloorId = floorId;
        _selectedTable = selected;
        _selectedFixture = selFix;
        _loading = false;
      });
      await _ensureDistinctTableLayouts();
      if (!_didInitialFit) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _fitAllContent();
          _didInitialFit = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _syncFloorItems() async {
    final floorId = _selectedFloorId;
    if (floorId == null) return;
    try {
      final tables = await _floorsRepo.listTables(floorId: floorId);
      final fixtures = await _floorsRepo.listFixtures(floorId: floorId);
      if (!mounted) return;
      RestaurantTable? selected = _selectedTable;
      if (selected != null) {
        selected = tables.where((t) => t.id == selected!.id).firstOrNull;
      }
      RestaurantFloorFixture? selFix = _selectedFixture;
      if (selFix != null) {
        selFix = fixtures.where((f) => f.id == selFix!.id).firstOrNull;
      }
      setState(() {
        _tables = tables;
        _fixtures = fixtures;
        _selectedTable = selected;
        _selectedFixture = selFix;
      });
      await _ensureDistinctTableLayouts();
    } catch (_) {}
  }

  /// إذا تراكمت الطاولات على نفس النقطة (أو بلا موضع) — نوزّعها ونحفظ.
  Future<void> _ensureDistinctTableLayouts() async {
    if (_tables.isEmpty) return;
    // فقط الطاولات بلا موضع محفوظ — لا نحرّك ما وضعه المستخدم.
    var changed = false;
    for (var i = 0; i < _tables.length; i++) {
      final t = _tables[i];
      if (t.layoutXBp >= 0 && t.layoutYBp >= 0) continue;
      final slot = _defaultSlot(i);
      await _floorsRepo.updateTableLayout(
        id: t.id,
        layoutXBp: slot.dx.round().clamp(200, _kLayoutMax - 200),
        layoutYBp: slot.dy.round().clamp(200, _kLayoutMax - 200),
        layoutRotDeg: t.layoutRotDeg,
        layoutWBp: t.layoutWBp,
        layoutHBp: t.layoutHBp,
      );
      changed = true;
    }
    if (changed) {
      final floorId = _selectedFloorId;
      if (floorId == null) return;
      final tables = await _floorsRepo.listTables(floorId: floorId);
      if (!mounted) return;
      setState(() => _tables = tables);
    }
  }

  void _fitCanvasToView() {
    _fitAllContent();
  }

  void _fitAllContent() {
    final box = _canvasHostKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final vw = box.size.width;
    final vh = box.size.height;
    if (vw <= 0 || vh <= 0) return;

    double minX = 0;
    double minY = 0;
    double maxX = _kVirtualCanvasW;
    double maxY = _kVirtualCanvasH;
    if (_tables.isNotEmpty || _fixtures.isNotEmpty) {
      minX = double.infinity;
      minY = double.infinity;
      maxX = 0;
      maxY = 0;
      for (var i = 0; i < _tables.length; i++) {
        final p = _tablePos(_tables[i], i);
        final sz = _tablePixelSize(_tables[i]);
        minX = math.min(minX, p.dx);
        minY = math.min(minY, p.dy);
        maxX = math.max(maxX, p.dx + sz.width);
        maxY = math.max(maxY, p.dy + sz.height);
      }
      for (final f in _fixtures) {
        final p = _fixturePos(f);
        final s = _fixtureSize(f);
        minX = math.min(minX, p.dx);
        minY = math.min(minY, p.dy);
        maxX = math.max(maxX, p.dx + s.width);
        maxY = math.max(maxY, p.dy + s.height);
      }
      minX = (minX - 40).clamp(0, _kVirtualCanvasW);
      minY = (minY - 40).clamp(0, _kVirtualCanvasH);
      maxX = (maxX + 40).clamp(0, _kVirtualCanvasW);
      maxY = (maxY + 40).clamp(0, _kVirtualCanvasH);
    }

    final contentW = (maxX - minX).clamp(200.0, _kVirtualCanvasW);
    final contentH = (maxY - minY).clamp(200.0, _kVirtualCanvasH);
    final scale = math.min(vw / contentW, vh / contentH).clamp(0.12, 1.6);
    final dx = (vw - contentW * scale) / 2 - minX * scale;
    final dy = (vh - contentH * scale) / 2 - minY * scale;
    _viewerController.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);
  }

  Future<void> _addFloor() async {
    final name = await _promptText(title: 'طابق جديد', label: 'اسم الطابق');
    if (name == null || name.trim().isEmpty) return;
    await _floorsRepo.upsertFloor(nameAr: name.trim());
    await _reload();
  }

  Offset _defaultSlot(int index) {
    // شبكة واضحة في وسط المخطّط (basis points 0–10000).
    const originX = 1800.0;
    const originY = 1800.0;
    const gapX = 1400.0;
    const gapY = 1400.0;
    final col = index % 4;
    final row = index ~/ 4;
    return Offset(
      (originX + col * gapX).clamp(400, 9000),
      (originY + row * gapY).clamp(400, 9000),
    );
  }

  String _nextTableNumber() {
    var maxN = 0;
    for (final t in _tables) {
      final n = int.tryParse(
        FloorsTablesRepository.normalizeTableSlug(t.tableNumber),
      );
      if (n != null && n > maxN) maxN = n;
    }
    return '${maxN + 1}';
  }

  Future<void> _addTable({Offset? atBp}) async {
    if (_busyMutating) return;
    final floorId = _selectedFloorId;
    if (floorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أنشئ طابقاً أولاً')),
      );
      return;
    }
    final number = _nextTableNumber();
    final slug = 't-$number-${DateTime.now().millisecondsSinceEpoch % 100000}';
    final slot = atBp ?? _viewportCenterBp();
    const wBp = 900;
    const hBp = 900;
    setState(() => _busyMutating = true);
    try {
      await _floorsRepo.upsertTable(
        floorId: floorId,
        tableNumber: number,
        tableSlug: slug,
        capacity: _draftSeats,
        seatStyle: _draftSeatStyle,
        layoutXBp: (slot.dx - wBp / 2).round().clamp(0, _kLayoutMax - wBp),
        layoutYBp: (slot.dy - hBp / 2).round().clamp(0, _kLayoutMax - hBp),
        layoutWBp: wBp,
        layoutHBp: hBp,
      );
      setState(() => _tool = _EditTool.select);
      await _syncFloorItems();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('أُضيفت طاولة $number في وسط الشاشة')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر إضافة الطاولة: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyMutating = false);
    }
  }

  Future<void> _addFixture(
    RestaurantFloorFixtureKind kind, {
    Offset? atBp,
  }) async {
    if (_busyMutating) return;
    final floorId = _selectedFloorId;
    if (floorId == null) return;

    if (kind == RestaurantFloorFixtureKind.hallFrame) {
      final existing = _fixtures
          .where((f) => f.kind == RestaurantFloorFixtureKind.hallFrame)
          .firstOrNull;
      if (existing != null) {
        _selectFixture(existing);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('إطار القاعة موجود — حرّكه وكبّره كما تشاء'),
          ),
        );
        return;
      }
    }

    String? label = kind.labelAr;
    if (kind == RestaurantFloorFixtureKind.text) {
      label = await _promptText(title: 'نص على المخطّط', label: 'النص');
      if (label == null || label.trim().isEmpty) return;
      label = label.trim();
    }
    final slot = atBp ?? _viewportCenterBp();
    var wBp = 900;
    var hBp = 750;
    switch (kind) {
      case RestaurantFloorFixtureKind.arrow:
        wBp = 900;
        hBp = 500;
      case RestaurantFloorFixtureKind.text:
        wBp = 1200;
        hBp = 500;
      case RestaurantFloorFixtureKind.wall:
        wBp = 2400;
        hBp = 200;
      case RestaurantFloorFixtureKind.entrance:
      case RestaurantFloorFixtureKind.exit:
        wBp = 560;
        hBp = 720;
      case RestaurantFloorFixtureKind.hallFrame:
        wBp = 4200;
        hBp = 3200;
      case RestaurantFloorFixtureKind.zoneSeating:
        wBp = 2400;
        hBp = 2000;
      case RestaurantFloorFixtureKind.zoneKitchen:
        wBp = 2000;
        hBp = 1600;
      case RestaurantFloorFixtureKind.zoneCashier:
        wBp = 1600;
        hBp = 1200;
      case RestaurantFloorFixtureKind.zoneBathroom:
        wBp = 1400;
        hBp = 1200;
      default:
        break;
    }
    String? metaJson;
    var xBp = (slot.dx - wBp / 2).round().clamp(0, _kLayoutMax - wBp);
    var yBp = (slot.dy - hBp / 2).round().clamp(0, _kLayoutMax - hBp);
    if (kind == RestaurantFloorFixtureKind.wall) {
      final path = WallPath([
        Offset(slot.dx - 1400, slot.dy),
        Offset(slot.dx + 1400, slot.dy),
      ]);
      metaJson = path.toMetaJson();
      final b = path.boundsBp();
      xBp = b.$1;
      yBp = b.$2;
      wBp = b.$3;
      hBp = b.$4;
    }
    setState(() => _busyMutating = true);
    try {
      await _floorsRepo.upsertFixture(
        floorId: floorId,
        kind: kind,
        labelAr: label,
        layoutXBp: xBp,
        layoutYBp: yBp,
        layoutWBp: wBp,
        layoutHBp: hBp,
        metaJson: metaJson,
      );
      setState(() {
        _tool = _EditTool.select;
        _fixtureKind = kind;
      });
      await _syncFloorItems();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('أُضيف: ${kind.labelAr} في وسط الشاشة')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر إضافة العنصر: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyMutating = false);
    }
  }

  Future<String?> _promptText({
    required String title,
    required String label,
  }) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => Theme(
        data: RestaurantOsTokens.darkTheme(ctx),
        child: AlertDialog(
          backgroundColor: RestaurantOsTokens.charcoalElevated,
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(color: RestaurantOsTokens.boneMuted),
            ),
            style: const TextStyle(color: RestaurantOsTokens.bone),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSelected() async {
    final table = _selectedTable;
    if (table == null) return;
    try {
      await _fsm.openTable(tableId: table.id);
      await _syncFloorItems();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _requestBillSelected() async {
    final table = _selectedTable;
    if (table?.activeSessionId == null) return;
    await _fsm.requestBill(table!.activeSessionId!);
      await _syncFloorItems();
  }

  Future<void> _closeSelected() async {
    final table = _selectedTable;
    if (table?.activeSessionId == null) return;
    await _fsm.closeSession(table!.activeSessionId!);
      await _syncFloorItems();
  }

  String _stateLabel(DerivedTableState s) {
    switch (s) {
      case DerivedTableState.available:
        return 'شاغرة';
      case DerivedTableState.occupied:
        return 'مشغولة';
      case DerivedTableState.awaitingPayment:
        return 'طلب الحساب';
    }
  }

  int get _occupiedCount =>
      _tables.where((t) => t.derivedState != DerivedTableState.available).length;

  int get _freeCount =>
      _tables.where((t) => t.derivedState == DerivedTableState.available).length;

  /// مركز الشاشة الحالية على المخطّط (basis points) — حتى لا تختفي العناصر الجديدة.
  Offset _viewportCenterBp() {
    final box = _canvasHostKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return const Offset(5000, 5000);
    }
    try {
      final inv = Matrix4.inverted(_viewerController.value);
      final local = MatrixUtils.transformPoint(
        inv,
        Offset(box.size.width / 2, box.size.height / 2),
      );
      return Offset(
        ((local.dx / _kVirtualCanvasW) * 10000).clamp(800, 9200),
        ((local.dy / _kVirtualCanvasH) * 10000).clamp(800, 9200),
      );
    } catch (_) {
      return const Offset(5000, 5000);
    }
  }

  Size _tablePixelSize(RestaurantTable t) {
    return Size(
      (t.layoutWBp / 10000) * _kVirtualCanvasW,
      (t.layoutHBp / 10000) * _kVirtualCanvasH,
    );
  }

  Offset _tablePos(RestaurantTable t, int index) {
    final canvas = _virtualCanvas;
    final sz = _tablePixelSize(t);
    final has = t.layoutXBp >= 0 && t.layoutYBp >= 0;
    final xBp = has ? t.layoutXBp : _defaultSlot(index).dx.round();
    final yBp = has ? t.layoutYBp : _defaultSlot(index).dy.round();
    return Offset(
      (xBp / 10000) * (canvas.width - sz.width).clamp(1, canvas.width),
      (yBp / 10000) * (canvas.height - sz.height).clamp(1, canvas.height),
    );
  }

  Size _fixtureSize(RestaurantFloorFixture f) {
    final canvas = _virtualCanvas;
    return Size(
      (f.layoutWBp / 10000) * canvas.width,
      (f.layoutHBp / 10000) * canvas.height,
    );
  }

  Offset _fixturePos(RestaurantFloorFixture f) {
    final canvas = _virtualCanvas;
    final sz = _fixtureSize(f);
    return Offset(
      (f.layoutXBp / 10000) * (canvas.width - sz.width).clamp(1, canvas.width),
      (f.layoutYBp / 10000) * (canvas.height - sz.height).clamp(1, canvas.height),
    );
  }

  Future<void> _commitTableLayout(
    RestaurantTable t,
    Offset local, {
    int? rot,
    int? wBp,
    int? hBp,
    Size? pixelSize,
  }) async {
    final canvas = _virtualCanvas;
    final sz = pixelSize ??
        Size(
          wBp != null
              ? (wBp / 10000) * canvas.width
              : _tablePixelSize(t).width,
          hBp != null
              ? (hBp / 10000) * canvas.height
              : _tablePixelSize(t).height,
        );
    final availW = (canvas.width - sz.width).clamp(1.0, 100000.0);
    final availH = (canvas.height - sz.height).clamp(1.0, 100000.0);
    final xBp = ((local.dx / availW) * 10000).round().clamp(0, _kLayoutMax);
    final yBp = ((local.dy / availH) * 10000).round().clamp(0, _kLayoutMax);
    final nextW = wBp ??
        (pixelSize != null
            ? ((pixelSize.width / canvas.width) * 10000).round()
            : null);
    final nextH = hBp ??
        (pixelSize != null
            ? ((pixelSize.height / canvas.height) * 10000).round()
            : null);
    await _floorsRepo.updateTableLayout(
      id: t.id,
      layoutXBp: xBp,
      layoutYBp: yBp,
      layoutRotDeg: rot ?? t.layoutRotDeg,
      layoutWBp: nextW,
      layoutHBp: nextH,
    );
    await _syncFloorItems();
  }

  Future<void> _commitFixtureLayout(
    RestaurantFloorFixture f,
    Offset local, {
    int? rot,
    int? wBp,
    int? hBp,
    Size? pixelSize,
  }) async {
    final canvas = _virtualCanvas;
    final sz = pixelSize ??
        Size(
          wBp != null
              ? (wBp / 10000) * canvas.width
              : _fixtureSize(f).width,
          hBp != null
              ? (hBp / 10000) * canvas.height
              : _fixtureSize(f).height,
        );
    final availW = (canvas.width - sz.width).clamp(1.0, 100000.0);
    final availH = (canvas.height - sz.height).clamp(1.0, 100000.0);
    final nextW = wBp ??
        (pixelSize != null
            ? ((pixelSize.width / canvas.width) * 10000).round()
            : null);
    final nextH = hBp ??
        (pixelSize != null
            ? ((pixelSize.height / canvas.height) * 10000).round()
            : null);
    await _floorsRepo.updateFixtureLayout(
      id: f.id,
      layoutXBp: ((local.dx / availW) * 10000).round().clamp(0, _kLayoutMax),
      layoutYBp: ((local.dy / availH) * 10000).round().clamp(0, _kLayoutMax),
      layoutRotDeg: rot ?? f.layoutRotDeg,
      layoutWBp: nextW,
      layoutHBp: nextH,
    );
    await _syncFloorItems();
  }

  /// يضع مدخل/مخرج مرتبطاً بالجدار — يتحرك معه وعلى مساره فقط.
  Future<void> _addDoorOnWall(
    RestaurantFloorFixture wall, {
    required bool isExit,
  }) async {
    if (_busyMutating) return;
    final floorId = _selectedFloorId;
    if (floorId == null) return;
    final kind = isExit
        ? RestaurantFloorFixtureKind.exit
        : RestaurantFloorFixtureKind.entrance;
    final path = _wallPathOf(wall);
    const along = 0.5;
    final pt = path.pointAlong(along);
    const doorW = 560;
    const doorH = 720;
    final meta = DoorWallAnchor(wallId: wall.id, along: along).toMetaJson();
    setState(() => _busyMutating = true);
    try {
      await _floorsRepo.upsertFixture(
        floorId: floorId,
        kind: kind,
        labelAr: kind.labelAr,
        layoutXBp: (pt.dx - doorW / 2).round().clamp(0, _kLayoutMax - doorW),
        layoutYBp: (pt.dy - doorH / 2).round().clamp(0, _kLayoutMax - doorH),
        layoutWBp: doorW,
        layoutHBp: doorH,
        metaJson: meta,
      );
      await _syncFloorItems();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'أُضيف ${kind.labelAr} على الجدار — اسحبه على المسار فقط',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyMutating = false);
    }
  }

  WallPath _wallPathOf(RestaurantFloorFixture wall) {
    return WallPath.tryParse(wall.metaJson) ??
        WallPath.fromLegacyRect(
          xBp: wall.layoutXBp,
          yBp: wall.layoutYBp,
          wBp: wall.layoutWBp,
          hBp: wall.layoutHBp,
        );
  }

  Future<void> _commitWallPath(
    RestaurantFloorFixture wall,
    WallPath path,
  ) async {
    final b = path.boundsBp();
    await _floorsRepo.updateFixtureLayout(
      id: wall.id,
      layoutXBp: b.$1,
      layoutYBp: b.$2,
      layoutWBp: b.$3,
      layoutHBp: b.$4,
      metaJson: path.toMetaJson(),
    );
    for (final d in _fixtures) {
      if (d.kind != RestaurantFloorFixtureKind.entrance &&
          d.kind != RestaurantFloorFixtureKind.exit) {
        continue;
      }
      final anchor = DoorWallAnchor.tryParse(d.metaJson);
      if (anchor == null || anchor.wallId != wall.id) continue;
      final pt = path.pointAlong(anchor.along);
      await _floorsRepo.updateFixtureLayout(
        id: d.id,
        layoutXBp: (pt.dx - d.layoutWBp / 2).round().clamp(0, _kLayoutMax),
        layoutYBp: (pt.dy - d.layoutHBp / 2).round().clamp(0, _kLayoutMax),
        metaJson: anchor.toMetaJson(),
      );
    }
    await _syncFloorItems();
  }

  Future<void> _bendWall(RestaurantFloorFixture wall, {required bool left}) async {
    final next = _wallPathOf(wall).bend(left: left);
    await _commitWallPath(wall, next);
  }

  Future<void> _slideDoorAlongWall(
    RestaurantFloorFixture door,
    Offset queryBp,
  ) async {
    final anchor = DoorWallAnchor.tryParse(door.metaJson);
    if (anchor == null) return;
    final wall = _fixtures.where((f) => f.id == anchor.wallId).firstOrNull;
    if (wall == null) return;
    final path = _wallPathOf(wall);
    final projected = path.project(queryBp);
    final next = DoorWallAnchor(wallId: wall.id, along: projected.$2);
    final pt = projected.$1;
    await _floorsRepo.updateFixtureLayout(
      id: door.id,
      layoutXBp: (pt.dx - door.layoutWBp / 2).round().clamp(0, _kLayoutMax),
      layoutYBp: (pt.dy - door.layoutHBp / 2).round().clamp(0, _kLayoutMax),
      metaJson: next.toMetaJson(),
    );
    await _syncFloorItems();
  }

  String? _occupiedDurationLabel(RestaurantTable t) {
    if (t.derivedState == DerivedTableState.available) return null;
    final opened = t.sessionOpenedAt;
    if (opened == null || opened <= 0) return null;
    final mins =
        ((DateTime.now().millisecondsSinceEpoch - opened) / 60000).floor();
    if (mins < 1) return '<1 د';
    if (mins < 60) return '$mins د';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '$h س' : '$h س $m د';
  }

  Future<void> _rotateSelected({required int deltaDeg}) async {
    final table = _selectedTable;
    final fixture = _selectedFixture;
    if (table != null) {
      await _floorsRepo.updateTableLayout(
        id: table.id,
        layoutXBp: table.layoutXBp < 0 ? 4800 : table.layoutXBp,
        layoutYBp: table.layoutYBp < 0 ? 4800 : table.layoutYBp,
        layoutRotDeg: table.layoutRotDeg + deltaDeg,
      );
    } else if (fixture != null) {
      await _floorsRepo.updateFixtureLayout(
        id: fixture.id,
        layoutXBp: fixture.layoutXBp,
        layoutYBp: fixture.layoutYBp,
        layoutRotDeg: fixture.layoutRotDeg + deltaDeg,
      );
    } else {
      return;
    }
      await _syncFloorItems();
  }

  void _clearSelection() {
    setState(() {
      _selectedTable = null;
      _selectedFixture = null;
    });
  }

  void _selectTable(RestaurantTable t) {
    setState(() {
      _selectedTable = t;
      _selectedFixture = null;
    });
  }

  void _selectFixture(RestaurantFloorFixture f) {
    setState(() {
      _selectedFixture = f;
      _selectedTable = null;
    });
  }

  Widget _rotationControls({required int currentDeg}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'تدوير لليسار',
          onPressed: () => _rotateSelected(deltaDeg: -15),
          icon: const Icon(Icons.rotate_left_rounded),
          color: RestaurantOsTokens.amberSoft,
        ),
        Text(
          '${((currentDeg % 360) + 360) % 360}°',
          style: const TextStyle(
            color: RestaurantOsTokens.boneMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        IconButton(
          tooltip: 'تدوير لليمين',
          onPressed: () => _rotateSelected(deltaDeg: 15),
          icon: const Icon(Icons.rotate_right_rounded),
          color: RestaurantOsTokens.amberSoft,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: RestaurantOsTokens.darkTheme(context),
      child: Scaffold(
        backgroundColor: RestaurantOsTokens.charcoal,
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'نابو',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: RestaurantOsTokens.amberSoft,
                ),
              ),
              Text(
                'ترتيب القاعة',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          actions: [
            if (!_loading && _error == null)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Center(
                  child: Text(
                    '$_occupiedCount مشغولة · $_freeCount شاغرة',
                    style: const TextStyle(
                      color: RestaurantOsTokens.boneMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            IconButton(
              tooltip: _editLayout ? 'إنهاء التعديل' : 'تعديل المخطّط',
              onPressed: () => setState(() {
                _editLayout = !_editLayout;
                _tool = _EditTool.select;
                if (!_editLayout) _previewFinalFrame = false;
              }),
              icon: Icon(
                _editLayout
                    ? Icons.check_rounded
                    : Icons.design_services_outlined,
              ),
              color: _editLayout
                  ? RestaurantOsTokens.amber
                  : RestaurantOsTokens.boneMuted,
            ),
            if (_editLayout)
              IconButton(
                tooltip: _previewFinalFrame
                    ? 'إظهار مساحة التصميم'
                    : 'معاينة الإطار النهائي',
                onPressed: () => setState(
                  () => _previewFinalFrame = !_previewFinalFrame,
                ),
                icon: Icon(
                  _previewFinalFrame
                      ? Icons.visibility_off_outlined
                      : Icons.crop_free_rounded,
                ),
                color: _previewFinalFrame
                    ? RestaurantOsTokens.amber
                    : RestaurantOsTokens.boneMuted,
              ),
            IconButton(
              tooltip: 'إظهار كل العناصر',
              onPressed: () async {
                await _ensureDistinctTableLayouts();
                _fitAllContent();
              },
              icon: const Icon(Icons.center_focus_strong_outlined),
              color: RestaurantOsTokens.boneMuted,
            ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
              color: RestaurantOsTokens.amberSoft,
            ),
            IconButton(
              tooltip: 'طابق جديد',
              onPressed: _addFloor,
              icon: const Icon(Icons.layers_outlined),
              color: RestaurantOsTokens.boneMuted,
            ),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: RestaurantOsTokens.amber),
              )
            : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: RestaurantOsTokens.bone),
                    ),
                  )
                : Column(
                    children: [
                      if (_editLayout) _buildEditToolbar(),
                      _buildLegend(),
                      if (_floors.isNotEmpty) _buildFloorTabs(),
                      Expanded(child: _buildCanvas()),
                    ],
                  ),
      ),
    );
  }

  Widget _buildEditToolbar() {
    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: FilterChip(
          selected: selected,
          label: Text(label),
          onSelected: (_) => onTap(),
          selectedColor: RestaurantOsTokens.amber.withValues(alpha: 0.25),
          checkmarkColor: RestaurantOsTokens.amber,
          labelStyle: TextStyle(
            color: selected
                ? RestaurantOsTokens.bone
                : RestaurantOsTokens.boneMuted,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
          side: BorderSide(
            color: selected
                ? RestaurantOsTokens.amber
                : RestaurantOsTokens.bone.withValues(alpha: 0.15),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      color: RestaurantOsTokens.charcoalElevated,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الجدار خط رفيع موحّد: اسحبه للنقل، اسحب نهايته للطول، وعطف يمين/يسار من البطاقة. '
            'المدخل/المخرج مرتبط بالجدار. حجم الطاولة من الشريط فقط — وباقي العناصر باللمس على الحواف.',
            style: TextStyle(
              color: RestaurantOsTokens.boneMuted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                chip(
                  label: 'تحديد',
                  selected: _tool == _EditTool.select,
                  onTap: () => setState(() => _tool = _EditTool.select),
                ),
                chip(
                  label: 'طاولة $_draftSeats ${_draftSeatStyle == RestaurantTableSeatStyle.wall ? 'جدار' : 'وسط'}',
                  selected: _tool == _EditTool.table,
                  onTap: () async {
                    setState(() => _tool = _EditTool.table);
                    await _addTable();
                  },
                ),
                chip(
                  label: '4 كراسي',
                  selected: _draftSeats == 4,
                  onTap: () => setState(() => _draftSeats = 4),
                ),
                chip(
                  label: '6 كراسي',
                  selected: _draftSeats == 6,
                  onTap: () => setState(() => _draftSeats = 6),
                ),
                chip(
                  label: 'وسط',
                  selected: _draftSeatStyle == RestaurantTableSeatStyle.center,
                  onTap: () => setState(
                    () => _draftSeatStyle = RestaurantTableSeatStyle.center,
                  ),
                ),
                chip(
                  label: 'بجانب جدار',
                  selected: _draftSeatStyle == RestaurantTableSeatStyle.wall,
                  onTap: () => setState(
                    () => _draftSeatStyle = RestaurantTableSeatStyle.wall,
                  ),
                ),
                ...RestaurantFloorFixtureKind.values.map(
                  (k) => chip(
                    label: k.labelAr,
                    selected:
                        _tool == _EditTool.fixture && _fixtureKind == k,
                    onTap: () async {
                      setState(() {
                        _tool = _EditTool.fixture;
                        _fixtureKind = k;
                      });
                      await _addFixture(k);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    Widget chip(Color c, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: RestaurantOsTokens.boneMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          chip(const Color(0xFF22C55E), 'شاغرة'),
          chip(const Color(0xFFEF4444), 'مشغولة'),
          chip(const Color(0xFFF59E0B), 'طلب الحساب'),
          if (_editLayout) ...[
            chip(const Color(0xFF1E3A5F), 'جلوس'),
            chip(const Color(0xFF3F3A32), 'مطبخ'),
            chip(RestaurantOsTokens.amber.withValues(alpha: 0.5), 'كاشير'),
            chip(const Color(0xFF2A4A4A), 'حمّامات'),
          ],
        ],
      ),
    );
  }

  Widget _buildFloorTabs() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
        itemCount: _floors.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, i) {
          final f = _floors[i];
          final selected = f.id == _selectedFloorId;
          return InkWell(
            onTap: () {
              setState(() {
                _selectedFloorId = f.id;
                _didInitialFit = false;
              });
              _reload(showLoading: true);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.nameAr,
                  style: TextStyle(
                    color: selected
                        ? RestaurantOsTokens.bone
                        : RestaurantOsTokens.bone.withValues(alpha: 0.55),
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 2,
                  width: 36,
                  color: selected ? RestaurantOsTokens.amber : Colors.transparent,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCanvas() {
    if (_floors.isEmpty) {
      return const Center(
        child: Text(
          'أضف طابقاً ثم ارسم قاعتك',
          style: TextStyle(color: RestaurantOsTokens.boneMuted),
        ),
      );
    }

    final canvas = _virtualCanvas;
    final hallFrames = _fixtures
        .where((f) => f.kind == RestaurantFloorFixtureKind.hallFrame)
        .toList(growable: false);
    final zoneFixtures =
        _fixtures.where((f) => f.kind.isZone).toList(growable: false);
    final wallFixtures = _fixtures
        .where((f) => f.kind == RestaurantFloorFixtureKind.wall)
        .toList(growable: false);
    final linkedDoors = _fixtures.where((f) {
      if (f.kind != RestaurantFloorFixtureKind.entrance &&
          f.kind != RestaurantFloorFixtureKind.exit) {
        return false;
      }
      return DoorWallAnchor.tryParse(f.metaJson) != null;
    }).toList(growable: false);
    final otherFixtures = _fixtures
        .where(
          (f) =>
              f.kind != RestaurantFloorFixtureKind.wall &&
              f.kind != RestaurantFloorFixtureKind.hallFrame &&
              !f.kind.isZone &&
              !linkedDoors.any((d) => d.id == f.id),
        )
        .toList(growable: false);

    Widget planItem(RestaurantFloorFixture f, {bool allowResize = true}) {
      return _DraggablePlanItem(
        origin: _fixturePos(f),
        size: _fixtureSize(f),
        rotationDeg: f.layoutRotDeg.toDouble(),
        editMode: _editLayout,
        selected: f.id == _selectedFixture?.id,
        canvas: canvas,
        allowResize: allowResize,
        edgeHit: f.kind == RestaurantFloorFixtureKind.hallFrame || f.kind.isZone
            ? 36
            : 22,
        onTap: () => _selectFixture(f),
        onGeometryChanged: (origin, size) => _commitFixtureLayout(
          f,
          origin,
          pixelSize: size,
        ),
        child: CustomPaint(
          painter: FloorPlanFixturePainter(
            kind: f.kind,
            label: f.labelAr ?? f.kind.labelAr,
            selected: f.id == _selectedFixture?.id,
          ),
        ),
      );
    }

    Widget linkedDoorItem(RestaurantFloorFixture door) {
      final anchor = DoorWallAnchor.tryParse(door.metaJson)!;
      final wall = wallFixtures.where((w) => w.id == anchor.wallId).firstOrNull;
      final path = wall != null ? _wallPathOf(wall) : null;
      final ptBp = path?.pointAlong(anchor.along);
      final origin = ptBp == null
          ? _fixturePos(door)
          : Offset(
              (ptBp.dx / 10000) * canvas.width - _fixtureSize(door).width / 2,
              (ptBp.dy / 10000) * canvas.height - _fixtureSize(door).height / 2,
            );
      return _DraggablePlanItem(
        origin: origin,
        size: _fixtureSize(door),
        rotationDeg: 0,
        editMode: _editLayout,
        selected: door.id == _selectedFixture?.id,
        canvas: canvas,
        allowResize: false,
        edgeHit: 16,
        onTap: () => _selectFixture(door),
        onGeometryChanged: (o, s) {
          final center = Offset(
            ((o.dx + s.width / 2) / canvas.width) * 10000,
            ((o.dy + s.height / 2) / canvas.height) * 10000,
          );
          _slideDoorAlongWall(door, center);
        },
        child: CustomPaint(
          painter: FloorPlanFixturePainter(
            kind: door.kind,
            label: door.labelAr ?? door.kind.labelAr,
            selected: door.id == _selectedFixture?.id,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.all(8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF0B1220),
              border: Border.all(
                color: RestaurantOsTokens.bone.withValues(alpha: 0.1),
              ),
            ),
            child: ClipRect(
              child: InteractiveViewer(
                key: _canvasHostKey,
                transformationController: _viewerController,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(2000),
                minScale: 0.12,
                maxScale: 3.5,
                panEnabled: true,
                scaleEnabled: true,
                child: SizedBox(
                  width: canvas.width,
                  height: canvas.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        size: canvas,
                        painter: _FloorGridPainter(),
                      ),
                      for (final f in hallFrames) planItem(f),
                      for (final f in zoneFixtures) planItem(f),
                      for (final w in wallFixtures)
                        _WallPathPlanItem(
                          wall: w,
                          path: _wallPathOf(w),
                          canvas: canvas,
                          editMode: _editLayout,
                          selected: w.id == _selectedFixture?.id,
                          onTap: () => _selectFixture(w),
                          onPathChanged: (p) => _commitWallPath(w, p),
                        ),
                      for (final d in linkedDoors) linkedDoorItem(d),
                      for (final f in otherFixtures) planItem(f),
                      for (var i = 0; i < _tables.length; i++)
                        _DraggablePlanItem(
                          origin: _tablePos(_tables[i], i),
                          size: _tablePixelSize(_tables[i]),
                          rotationDeg: _tables[i].layoutRotDeg.toDouble(),
                          editMode: _editLayout,
                          selected: _tables[i].id == _selectedTable?.id,
                          canvas: canvas,
                          allowResize: false,
                          edgeHit: 22,
                          onTap: () => _selectTable(_tables[i]),
                          onGeometryChanged: (origin, size) =>
                              _commitTableLayout(
                            _tables[i],
                            origin,
                            pixelSize: size,
                          ),
                          child: CustomPaint(
                            painter: FloorPlanTablePainter(
                              tableNumber: _tables[i].tableNumber,
                              seatCount: _tables[i].seatCount,
                              seatStyle: _tables[i].seatStyle,
                              state: _tables[i].derivedState,
                              selected: _tables[i].id == _selectedTable?.id,
                              occupiedLabel:
                                  _occupiedDurationLabel(_tables[i]),
                            ),
                          ),
                        ),
                      if (_previewFinalFrame && hallFrames.isNotEmpty)
                        IgnorePointer(
                          child: CustomPaint(
                            size: canvas,
                            painter: _HallFramePreviewPainter(
                              frames: [
                                for (final f in hallFrames)
                                  Rect.fromLTWH(
                                    _fixturePos(f).dx,
                                    _fixturePos(f).dy,
                                    _fixtureSize(f).width,
                                    _fixtureSize(f).height,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      if (_tables.isEmpty && _fixtures.isEmpty)
                        const Center(
                          child: Text(
                            'فعّل التعديل ثم أضف منطقة أو طاولة',
                            style: TextStyle(
                              color: RestaurantOsTokens.boneMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_selectedTable != null || _selectedFixture != null)
            PositionedDirectional(
              bottom: 8,
              start: 8,
              end: 8,
              child: Align(
                alignment: AlignmentDirectional.bottomStart,
                child: _buildSelectionPopup(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionPopup() {
    final table = _selectedTable;
    final fixture = _selectedFixture;
    return Material(
      elevation: 12,
      shadowColor: Colors.black54,
      color: RestaurantOsTokens.charcoalElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: RestaurantOsTokens.amber.withValues(alpha: 0.35),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      table != null
                          ? 'طاولة ${table.tableNumber}'
                          : fixture?.labelAr ?? fixture?.kind.labelAr ?? '',
                      style: const TextStyle(
                        color: RestaurantOsTokens.bone,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق',
                    onPressed: _clearSelection,
                    icon: const Icon(Icons.close_rounded),
                    color: RestaurantOsTokens.boneMuted,
                  ),
                ],
              ),
              if (table != null)
                _tableDetail(table, qrSize: 112)
              else if (fixture != null)
                _fixtureDetail(fixture),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fixtureDetail(RestaurantFloorFixture fixture) {
    final isWall = fixture.kind == RestaurantFloorFixtureKind.wall;
    final isDoor = fixture.kind == RestaurantFloorFixtureKind.entrance ||
        fixture.kind == RestaurantFloorFixtureKind.exit;
    final linked = DoorWallAnchor.tryParse(fixture.metaJson) != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          fixture.kind.labelAr,
          style: const TextStyle(
            color: RestaurantOsTokens.amberSoft,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (_editLayout) ...[
          const SizedBox(height: 6),
          Text(
            isWall
                ? 'سمك موحّد رفيع — اسحب المسار للنقل، والنهاية للطول. عطف يمين/يسار يكمل المسار.'
                : linked
                    ? 'مرتبط بالجدار — اسحبه على المسار فقط'
                    : 'اسحب الحواف لتغيير الحجم، والوسط للنقل',
            style: const TextStyle(
              color: RestaurantOsTokens.boneMuted,
              fontSize: 12,
            ),
          ),
          if (isWall) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () => _bendWall(fixture, left: true),
                  child: const Text('عطف يسار'),
                ),
                FilledButton.tonal(
                  onPressed: () => _bendWall(fixture, left: false),
                  child: const Text('عطف يمين'),
                ),
                OutlinedButton(
                  onPressed: () => _commitWallPath(
                    fixture,
                    _wallPathOf(fixture).extendLast(600),
                  ),
                  child: const Text('إطالة'),
                ),
                OutlinedButton(
                  onPressed: () => _commitWallPath(
                    fixture,
                    _wallPathOf(fixture).extendLast(-600),
                  ),
                  child: const Text('تقصير'),
                ),
                FilledButton.tonal(
                  onPressed: () => _addDoorOnWall(fixture, isExit: false),
                  child: const Text('مدخل على الجدار'),
                ),
                FilledButton.tonal(
                  onPressed: () => _addDoorOnWall(fixture, isExit: true),
                  child: const Text('مخرج على الجدار'),
                ),
              ],
            ),
          ] else if (!isDoor || !linked) ...[
            const SizedBox(height: 10),
            _rotationControls(currentDeg: fixture.layoutRotDeg),
            const SizedBox(height: 8),
            const Text(
              'الحجم باللمس على الحواف',
              style: TextStyle(
                color: RestaurantOsTokens.boneMuted,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: () async {
              await _floorsRepo.softDeleteFixture(fixture.id);
              _clearSelection();
              await _syncFloorItems();
            },
            child: const Text(
              'حذف العنصر',
              style: TextStyle(color: RestaurantOsTokens.danger),
            ),
          ),
        ],
      ],
    );
  }

  Widget _tableDetail(RestaurantTable table, {required double qrSize}) {
    final slug = _tenantSlug;
    final showOpen = !_editLayout &&
        table.derivedState == DerivedTableState.available;
    final showBill = !_editLayout &&
        table.derivedState == DerivedTableState.occupied &&
        table.activeSessionId != null;
    final showClose = !_editLayout &&
        table.derivedState == DerivedTableState.awaitingPayment &&
        table.activeSessionId != null;
    final hasActions = showOpen || showBill || showClose;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_stateLabel(table.derivedState)} · ${table.seatCount} كراسي · '
          '${table.seatStyle == RestaurantTableSeatStyle.wall ? 'جدار' : 'وسط'}'
          '${_occupiedDurationLabel(table) != null ? ' · منذ ${_occupiedDurationLabel(table)}' : ''}',
          style: TextStyle(
            color: table.derivedState == DerivedTableState.available
                ? const Color(0xFF22C55E)
                : table.derivedState == DerivedTableState.occupied
                    ? const Color(0xFFEF4444)
                    : const Color(0xFFF59E0B),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        if (_editLayout) ...[
          _rotationControls(currentDeg: table.layoutRotDeg),
          const SizedBox(height: 8),
          Text(
            'حجم الطاولة: ${table.layoutWBp}',
            style: const TextStyle(
              color: RestaurantOsTokens.boneMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Slider(
            value: table.layoutWBp.clamp(500, 2500).toDouble(),
            min: 500,
            max: 2500,
            divisions: 20,
            activeColor: RestaurantOsTokens.amber,
            label: '${table.layoutWBp}',
            onChanged: (v) {
              final size = v.round();
              setState(() {
                _selectedTable = RestaurantTable(
                  id: table.id,
                  tenantId: table.tenantId,
                  floorId: table.floorId,
                  tableNumber: table.tableNumber,
                  tableSlug: table.tableSlug,
                  sessionSeq: table.sessionSeq,
                  capacity: table.capacity,
                  deletedAt: table.deletedAt,
                  derivedState: table.derivedState,
                  activeSessionId: table.activeSessionId,
                  sessionOpenedAt: table.sessionOpenedAt,
                  layoutXBp: table.layoutXBp,
                  layoutYBp: table.layoutYBp,
                  layoutRotDeg: table.layoutRotDeg,
                  seatStyle: table.seatStyle,
                  layoutWBp: size,
                  layoutHBp: size,
                );
              });
            },
            onChangeEnd: (v) async {
              final size = v.round();
              await _floorsRepo.updateTableLayout(
                id: table.id,
                layoutXBp: table.layoutXBp < 0 ? 4800 : table.layoutXBp,
                layoutYBp: table.layoutYBp < 0 ? 4800 : table.layoutYBp,
                layoutWBp: size,
                layoutHBp: size,
              );
              await _syncFloorItems();
            },
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () async {
                  await _floorsRepo.updateTableStyle(
                    id: table.id,
                    capacity: 4,
                    seatStyle: table.seatStyle,
                  );
                  await _syncFloorItems();
                },
                child: const Text('4 كراسي'),
              ),
              OutlinedButton(
                onPressed: () async {
                  await _floorsRepo.updateTableStyle(
                    id: table.id,
                    capacity: 6,
                    seatStyle: table.seatStyle,
                  );
                  await _syncFloorItems();
                },
                child: const Text('6 كراسي'),
              ),
              OutlinedButton(
                onPressed: () async {
                  await _floorsRepo.updateTableStyle(
                    id: table.id,
                    capacity: table.seatCount,
                    seatStyle: RestaurantTableSeatStyle.center,
                  );
                  await _syncFloorItems();
                },
                child: const Text('وسط'),
              ),
              OutlinedButton(
                onPressed: () async {
                  await _floorsRepo.updateTableStyle(
                    id: table.id,
                    capacity: table.seatCount,
                    seatStyle: RestaurantTableSeatStyle.wall,
                  );
                  await _syncFloorItems();
                },
                child: const Text('جدار'),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (slug == null || slug.isEmpty)
          const Text(
            'لم يُنشر معرّف المنيو العام بعد — سيظهر رمز QR بعد ربط المطعم.',
            style: TextStyle(
              color: RestaurantOsTokens.boneMuted,
              height: 1.4,
            ),
          )
        else ...[
          Center(
            child: RestaurantQrService.qrWidget(
              data: RestaurantQrService.tableUrl(
                tenantSlug: slug,
                tableSlug: table.tableSlug,
              ),
              size: qrSize,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            RestaurantQrService.tableUrl(
              tenantSlug: slug,
              tableSlug: table.tableSlug,
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: RestaurantOsTokens.boneMuted,
              fontSize: 11,
            ),
          ),
        ],
        if (hasActions) ...[
          const SizedBox(height: 12),
          if (showOpen)
            FilledButton(
              onPressed: _openSelected,
              child: const Text('فتح الجلسة'),
            ),
          if (showBill)
            FilledButton(
              onPressed: _requestBillSelected,
              child: const Text('طلب الحساب'),
            ),
          if (showClose)
            FilledButton(
              onPressed: _closeSelected,
              child: const Text('إغلاق بعد الدفع'),
            ),
        ],
      ],
    );
  }
}

class _FloorGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = RestaurantOsTokens.bone.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    const step = 48.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// يُعتّم خارج إطار القاعة — يظهر فقط ما داخل «الإضاءة النهائية».
class _HallFramePreviewPainter extends CustomPainter {
  _HallFramePreviewPainter({required this.frames});

  final List<Rect> frames;

  @override
  void paint(Canvas canvas, Size size) {
    if (frames.isEmpty) return;
    final full = Path()..addRect(Offset.zero & size);
    final holes = Path();
    for (final r in frames) {
      holes.addRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)));
    }
    final dim = Path.combine(PathOperation.difference, full, holes);
    canvas.drawPath(
      dim,
      Paint()..color = const Color(0xFF05080F).withValues(alpha: 0.78),
    );
    for (final r in frames) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(4)),
        Paint()
          ..color = RestaurantOsTokens.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HallFramePreviewPainter oldDelegate) {
    if (oldDelegate.frames.length != frames.length) return true;
    for (var i = 0; i < frames.length; i++) {
      if (oldDelegate.frames[i] != frames[i]) return true;
    }
    return false;
  }
}

class _DraggablePlanItem extends StatefulWidget {
  const _DraggablePlanItem({
    required this.origin,
    required this.size,
    required this.rotationDeg,
    required this.editMode,
    required this.selected,
    required this.canvas,
    required this.onTap,
    required this.onGeometryChanged,
    required this.child,
    this.edgeHit = 22,
    this.allowResize = true,
  });

  final Offset origin;
  final Size size;
  final double rotationDeg;
  final bool editMode;
  final bool selected;
  final Size canvas;
  final VoidCallback onTap;
  final void Function(Offset origin, Size size) onGeometryChanged;
  final Widget child;
  final double edgeHit;
  final bool allowResize;

  @override
  State<_DraggablePlanItem> createState() => _DraggablePlanItemState();
}

enum _ResizeEdge { none, left, right, top, bottom }

class _DraggablePlanItemState extends State<_DraggablePlanItem> {
  Offset? _origin;
  Size? _size;
  _ResizeEdge _edge = _ResizeEdge.none;

  Offset get _o => _origin ?? widget.origin;
  Size get _s => _size ?? widget.size;

  @override
  void didUpdateWidget(covariant _DraggablePlanItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.origin != widget.origin || oldWidget.size != widget.size) {
      _origin = null;
      _size = null;
      _edge = _ResizeEdge.none;
    }
  }

  _ResizeEdge _hitEdge(Offset local) {
    if (!widget.allowResize) return _ResizeEdge.none;
    final hit = widget.edgeHit;
    final s = _s;
    final nearL = local.dx <= hit;
    final nearR = local.dx >= s.width - hit;
    final nearT = local.dy <= hit;
    final nearB = local.dy >= s.height - hit;
    if (s.width >= s.height * 1.6) {
      if (nearL) return _ResizeEdge.left;
      if (nearR) return _ResizeEdge.right;
      if (nearT) return _ResizeEdge.top;
      if (nearB) return _ResizeEdge.bottom;
    } else if (s.height >= s.width * 1.6) {
      if (nearT) return _ResizeEdge.top;
      if (nearB) return _ResizeEdge.bottom;
      if (nearL) return _ResizeEdge.left;
      if (nearR) return _ResizeEdge.right;
    } else {
      if (nearL && !nearT && !nearB) return _ResizeEdge.left;
      if (nearR && !nearT && !nearB) return _ResizeEdge.right;
      if (nearT && !nearL && !nearR) return _ResizeEdge.top;
      if (nearB && !nearL && !nearR) return _ResizeEdge.bottom;
    }
    return _ResizeEdge.none;
  }

  void _applyDelta(Offset delta) {
    var o = _o;
    var s = _s;
    const minW = 28.0;
    const minH = 20.0;
    switch (_edge) {
      case _ResizeEdge.left:
        final nx = (o.dx + delta.dx).clamp(0.0, o.dx + s.width - minW);
        final dw = o.dx - nx;
        o = Offset(nx, o.dy);
        s = Size(s.width + dw, s.height);
      case _ResizeEdge.right:
        final nw = (s.width + delta.dx).clamp(minW, widget.canvas.width - o.dx);
        s = Size(nw, s.height);
      case _ResizeEdge.top:
        final ny = (o.dy + delta.dy).clamp(0.0, o.dy + s.height - minH);
        final dh = o.dy - ny;
        o = Offset(o.dx, ny);
        s = Size(s.width, s.height + dh);
      case _ResizeEdge.bottom:
        final nh =
            (s.height + delta.dy).clamp(minH, widget.canvas.height - o.dy);
        s = Size(s.width, nh);
      case _ResizeEdge.none:
        o = Offset(
          (o.dx + delta.dx).clamp(0.0, widget.canvas.width - s.width),
          (o.dy + delta.dy).clamp(0.0, widget.canvas.height - s.height),
        );
    }
    setState(() {
      _origin = o;
      _size = s;
    });
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final s = _s;
    return Positioned(
      left: o.dx,
      top: o.dy,
      width: s.width,
      height: s.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onPanStart: widget.editMode
            ? (d) {
                _edge = _hitEdge(d.localPosition);
                _origin ??= widget.origin;
                _size ??= widget.size;
              }
            : null,
        onPanUpdate: widget.editMode ? (d) => _applyDelta(d.delta) : null,
        onPanEnd: widget.editMode
            ? (_) {
                widget.onGeometryChanged(_o, _s);
                _edge = _ResizeEdge.none;
              }
            : null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Transform.rotate(
                angle: widget.rotationDeg * math.pi / 180,
                child: widget.child,
              ),
            ),
            if (widget.editMode && widget.selected && widget.allowResize) ...[
              _edgeHandle(Alignment.centerLeft, wide: true),
              _edgeHandle(Alignment.centerRight, wide: true),
              _edgeHandle(Alignment.topCenter, wide: false),
              _edgeHandle(Alignment.bottomCenter, wide: false),
            ],
          ],
        ),
      ),
    );
  }

  Widget _edgeHandle(Alignment align, {required bool wide}) {
    return Align(
      alignment: align,
      child: Container(
        width: wide ? 10 : 28,
        height: wide ? 28 : 10,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: RestaurantOsTokens.amber.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: RestaurantOsTokens.bone, width: 1),
        ),
      ),
    );
  }
}

/// جدار كمسار رفيع على كامل اللوحة.
class _WallPathPlanItem extends StatefulWidget {
  const _WallPathPlanItem({
    required this.wall,
    required this.path,
    required this.canvas,
    required this.editMode,
    required this.selected,
    required this.onTap,
    required this.onPathChanged,
  });

  final RestaurantFloorFixture wall;
  final WallPath path;
  final Size canvas;
  final bool editMode;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<WallPath> onPathChanged;

  @override
  State<_WallPathPlanItem> createState() => _WallPathPlanItemState();
}

class _WallPathPlanItemState extends State<_WallPathPlanItem> {
  WallPath? _live;
  bool _extending = false;

  WallPath get _path => _live ?? widget.path;

  @override
  void didUpdateWidget(covariant _WallPathPlanItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wall.metaJson != widget.wall.metaJson ||
        oldWidget.path.lengthBp != widget.path.lengthBp) {
      _live = null;
      _extending = false;
    }
  }

  double _distToPolyline(Offset p, List<Offset> pts) {
    var best = double.infinity;
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final ab = b - a;
      final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
      final t = len2 <= 0
          ? 0.0
          : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
      final proj = a + ab * t;
      best = math.min(best, (p - proj).distance);
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    final pts = path.toCanvasPixels(widget.canvas);
    final b = path.boundsBp(pad: 160);
    final left = (b.$1 / 10000) * widget.canvas.width;
    final top = (b.$2 / 10000) * widget.canvas.height;
    final width = (b.$3 / 10000) * widget.canvas.width;
    final height = (b.$4 / 10000) * widget.canvas.height;
    final localPts = [
      for (final p in pts) Offset(p.dx - left, p.dy - top),
    ];

    return Positioned(
      left: left,
      top: top,
      width: width.clamp(40, widget.canvas.width),
      height: height.clamp(40, widget.canvas.height),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          if (_distToPolyline(d.localPosition, localPts) <= 28) {
            widget.onTap();
          }
        },
        onPanStart: widget.editMode
            ? (d) {
                if (_distToPolyline(d.localPosition, localPts) > 28) return;
                widget.onTap();
                final end = localPts.last;
                _extending = (d.localPosition - end).distance <= 40;
                _live = widget.path;
              }
            : null,
        onPanUpdate: widget.editMode
            ? (d) {
                if (_live == null) return;
                final dxBp = (d.delta.dx / widget.canvas.width) * 10000;
                final dyBp = (d.delta.dy / widget.canvas.height) * 10000;
                setState(() {
                  if (_extending) {
                    final dir = _live!.lastDirection;
                    final along = dxBp * dir.dx + dyBp * dir.dy;
                    _live = _live!.extendLast(along);
                  } else {
                    _live = _live!.translate(Offset(dxBp, dyBp));
                  }
                });
              }
            : null,
        onPanEnd: widget.editMode
            ? (_) {
                if (_live != null) {
                  widget.onPathChanged(_live!);
                }
                _live = null;
                _extending = false;
              }
            : null,
        child: CustomPaint(
          painter: FloorPlanWallPathPainter(
            pointsPx: localPts,
            selected: widget.selected,
          ),
        ),
      ),
    );
  }
}

