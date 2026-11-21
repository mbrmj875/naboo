import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// سجل أهداف الجولة — يعتمد على عناصر مركّبة (بدون GlobalKey مشترك).
class GuideAnchorRegistry {
  GuideAnchorRegistry._();
  static final GuideAnchorRegistry instance = GuideAnchorRegistry._();

  final Map<String, Set<_GuideAnchorState>> _anchors =
      <String, Set<_GuideAnchorState>>{};

  void _register(String id, _GuideAnchorState state) {
    _anchors.putIfAbsent(id, () => <_GuideAnchorState>{}).add(state);
  }

  void _unregister(String id, _GuideAnchorState state) {
    final set = _anchors[id];
    if (set == null) return;
    set.remove(state);
    if (set.isEmpty) _anchors.remove(id);
  }

  bool isMounted(String id) {
    final set = _anchors[id];
    if (set == null || set.isEmpty) return false;
    return set.any((s) => s.mounted && s._isOnCurrentRoute && s._renderBox != null);
  }

  /// مستطيل الهدف بإحداثيات [overlayContext] المحلية (مهم: الطبقة ليست ملء الشاشة).
  /// يتجاهل العناصر تحت مسار مغطى (مثلاً سجل الزيت تحت بطاقة جديدة).
  Rect? rectFor(String id, BuildContext overlayContext) {
    final overlayBox = overlayContext.findRenderObject();
    if (overlayBox is! RenderBox || !overlayBox.hasSize) return null;

    final set = _anchors[id];
    if (set == null || set.isEmpty) return null;

    Rect? best;
    var bestScore = -1.0;
    final overlaySize = overlayBox.size;
    final overlayRect = Offset.zero & overlaySize;

    for (final state in set) {
      if (!state.mounted) continue;
      // لا تقيس عناصراً على شاشة مخفية تحت Navigator
      if (!state._isOnCurrentRoute) continue;
      final box = state._renderBox;
      if (box == null || !box.hasSize || !box.attached) continue;

      final globalTopLeft = box.localToGlobal(Offset.zero);
      final localTopLeft = overlayBox.globalToLocal(globalTopLeft);
      final rect = localTopLeft & box.size;
      final visible = rect.intersect(overlayRect);
      if (visible.isEmpty) continue;
      // نفضّل العنصر الأكثر ظهوراً و«إحكاماً» (ليس أكبر غلاف بالخطأ)
      final area = visible.width * visible.height;
      final coverage = area / (rect.width * rect.height + 0.01);
      final score = coverage * 1000 - area * 0.0001;
      if (score > bestScore) {
        bestScore = score;
        best = rect;
      }
    }
    return best;
  }

  Future<void> ensureVisible(
    String id, {
    double alignment = 0.18,
    Duration duration = const Duration(milliseconds: 320),
  }) async {
    final set = _anchors[id];
    if (set == null) return;
    for (final state in set) {
      if (!state.mounted || !state._isOnCurrentRoute) continue;
      final ctx = state.context;
      try {
        await Scrollable.ensureVisible(
          ctx,
          duration: duration,
          alignment: alignment,
          curve: Curves.easeOutCubic,
        );
        return;
      } catch (_) {}
    }
  }
}

/// يلف عنصراً واجهياً ليصبح هدفاً لخطوة جولة.
class GuideAnchor extends StatefulWidget {
  const GuideAnchor({
    super.key,
    required this.id,
    required this.child,
  });

  final String id;
  final Widget child;

  @override
  State<GuideAnchor> createState() => _GuideAnchorState();
}

class _GuideAnchorState extends State<GuideAnchor> {
  RenderBox? get _renderBox {
    final obj = context.findRenderObject();
    return obj is RenderBox ? obj : null;
  }

  /// true فقط إذا كان العنصر على المسار الظاهر أعلى المكدس.
  bool get _isOnCurrentRoute {
    final route = ModalRoute.of(context);
    if (route == null) return true;
    return route.isCurrent;
  }

  @override
  void initState() {
    super.initState();
    GuideAnchorRegistry.instance._register(widget.id, this);
  }

  @override
  void didUpdateWidget(covariant GuideAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      GuideAnchorRegistry.instance._unregister(oldWidget.id, this);
      GuideAnchorRegistry.instance._register(widget.id, this);
    }
  }

  @override
  void dispose() {
    GuideAnchorRegistry.instance._unregister(widget.id, this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// معرّفات مثبتة لجولات غيار الزيت.
abstract final class OilGuideAnchors {
  static const hubNewCard = 'oil.hub.new_card';
  static const hubWhatsappConnect = 'oil.hub.whatsapp_connect';
  static const hubPendingTab = 'oil.hub.pending_tab';
  static const hubSettings = 'oil.hub.settings';

  /// صفوف لوحة إعدادات السجل.
  static const settingsStockOil = 'oil.settings.stock_oil';
  static const settingsStockHydraulic = 'oil.settings.stock_hydraulic';
  static const settingsOptionalExtras = 'oil.settings.optional_extras';
  static const settingsWaAuto = 'oil.settings.wa_auto';
  static const settingsWaManual = 'oil.settings.wa_manual';
  static const settingsWaRating = 'oil.settings.wa_rating';
  static const settingsWaConnect = 'oil.settings.wa_connect';

  /// أزرار/عناوين الكتالوج.
  static const formOilCatalogBtn = 'oil.form.oil_catalog_btn';
  static const formFilterCatalogBtn = 'oil.form.filter_catalog_btn';
  static const formHydraulicCatalogBtn = 'oil.form.hydraulic_catalog_btn';
  static const catalogOilTitle = 'oil.catalog.oil_title';
  static const catalogOilAdd = 'oil.catalog.oil_add';
  static const catalogFilterTitle = 'oil.catalog.filter_title';
  static const catalogFilterAdd = 'oil.catalog.filter_add';
  static const catalogHydraulicTitle = 'oil.catalog.hydraulic_title';
  static const catalogHydraulicAdd = 'oil.catalog.hydraulic_add';

  /// شاشة الخدمات.
  static const servicesBasePrice = 'oil.services.base_price';
  static const servicesExtrasList = 'oil.services.extras_list';

  /// غسيل السيارات — الرئيسية والتخصيص والبطاقة.
  static const homeCarWashCta = 'home.car_wash_cta';
  static const settingsCarWashToggle = 'settings.car_wash_toggle';
  static const carWashFormPlate = 'car_wash.form.plate';
  static const carWashFormServices = 'car_wash.form.services';
  static const carWashFormSave = 'car_wash.form.save';

  /// المستخدمون / الموظفون / النموذج / الهويات / الورديات.
  static const usersListTitle = 'users.list_title';
  static const usersFabAdd = 'users.fab_add';
  static const usersFormName = 'users.form.name';
  static const usersFormPin = 'users.form.pin';
  static const usersFormPerms = 'users.form.perms';
  static const usersFormSave = 'users.form.save';
  static const usersIdentityTitle = 'users.identity.title';
  static const usersShiftsTitle = 'users.shifts.title';

  /// منتجات / إضافة منتج / قائمة المخزون.
  static const productListTitle = 'product.list_title';
  static const productListAddCta = 'product.list.add_cta';
  static const productFormName = 'product.form.name';
  static const productFormDescription = 'product.form.description';
  static const productFormImage = 'product.form.image';
  static const productFormCategory = 'product.form.category';
  static const productFormBrand = 'product.form.brand';
  static const productFormWarehouse = 'product.form.warehouse';
  static const productFormStockType = 'product.form.stock_type';
  static const productFormExtraUnits = 'product.form.extra_units';
  static const productFormFluidGrades = 'product.form.fluid_grades';
  static const productFormSupplier = 'product.form.supplier';
  static const productFormPricing = 'product.form.pricing';
  static const productFormTrackInventory = 'product.form.track_inventory';
  static const productFormQty = 'product.form.qty';
  static const productFormLowStock = 'product.form.low_stock';
  static const productFormSave = 'product.form.save';

  /// بطاقة «بيانات العميل» كاملة.
  static const formCustomer = 'oil.form.customer';
  static const formCustomerName = 'oil.form.customer_name';
  static const formCustomerPhone = 'oil.form.customer_phone';

  /// بطاقة «بيانات السيارة» كاملة.
  static const formCar = 'oil.form.car';
  static const formPlate = 'oil.form.plate';

  /// بطاقة «تغيير الزيت» كاملة.
  static const formOil = 'oil.form.oil';
  static const formOdoCurrent = 'oil.form.odo_current';
  static const formOilBrand = 'oil.form.oil_brand';

  /// إضافات اختيارية (فلاتر / منتجات / هيدروليك).
  static const formExtras = 'oil.form.extras';

  /// الفني والملاحظات.
  static const formTechnician = 'oil.form.technician';

  /// السعر والدفع.
  static const formPayment = 'oil.form.payment';

  static const formSuspend = 'oil.form.suspend';
  static const formSave = 'oil.form.save';

  /// شاشة ربط واتساب المحل.
  static const waStatus = 'oil.wa.status';
  static const waMethodIntro = 'oil.wa.method_intro';
  static const waMethodNaboo = 'oil.wa.method_naboo';
  static const waMethodMeta = 'oil.wa.method_meta';
  static const waMethodQr = 'oil.wa.method_qr';
  static const waContinue = 'oil.wa.continue';
  static const waRelink = 'oil.wa.relink';
  static const waDisconnect = 'oil.wa.disconnect';
  static const waTips = 'oil.wa.tips';
}
