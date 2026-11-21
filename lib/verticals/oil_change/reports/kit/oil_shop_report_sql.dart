import '../../../../services/service_order_kinds.dart';
import '../../services/oil_change_direct_sale_service.dart';

/// قنوات البيع في محل الزيت. كل فاتورة تنتمي لقناة واحدة فقط.
enum OilShopChannel { oilCard, carWash, directSale, quickSale }

/// قطع SQL مشتركة بين تقارير محل الزيت، حتى تُحسب الأرقام بالقواعد نفسها
/// في كل تقرير وتطابق لوحة المالك.
abstract final class OilShopReportSql {
  /// فاتورة بيع حيّة: غير محذوفة وليست مرتجعاً ومن أنواع البيع.
  static String aliveSale(String i) =>
      "$i.deleted_at IS NULL AND IFNULL($i.isReturned, 0) = 0 "
      "AND $i.type IN (0,1,2,3)";

  /// مرتجع حيّ.
  static String aliveReturn(String i) =>
      "$i.deleted_at IS NULL AND IFNULL($i.isReturned, 0) = 1";

  /// مبلغ الفاتورة بالفلس. السجلات القديمة قد تحمل `total` فقط.
  static String totalFils(String i) =>
      'CAST(ROUND(CASE WHEN IFNULL($i.totalFils, 0) > 0 THEN $i.totalFils '
      'ELSE IFNULL($i.total, 0) * 1000 END) AS INTEGER)';

  /// تكلفة سطر بالدينار: المثبّتة لحظة البيع، وإلا سعر الشراء الحالي.
  static String lineCostIqd(String ii, String p) =>
      'CASE WHEN IFNULL($ii.unitCost, 0) > 0 THEN $ii.unitCost * $ii.quantity '
      'WHEN IFNULL($p.buyPrice, 0) > 0 THEN $p.buyPrice * $ii.quantity ELSE 0 END';

  /// 0 = مثبّتة، 1 = تقديرية من سعر الشراء الحالي، 2 = بلا تكلفة،
  /// 3 = خدمة أو سطر بلا منتج (لا تكلفة له أصلاً، فلا يُعدّ ناقصاً).
  ///
  /// التكلفة الصفرية تُعامل كغياب تكلفة، لأن الصنف بلا سعر شراء يُثبَّت صفراً
  /// فيظهر ربحه كاملاً وهامشه قرب 100%.
  static String lineCostSource(String ii, String p) =>
      'CASE WHEN $ii.productId IS NULL OR IFNULL($p.isService, 0) = 1 THEN 3 '
      'WHEN IFNULL($ii.unitCost, 0) > 0 THEN 0 '
      'WHEN IFNULL($p.buyPrice, 0) > 0 THEN 1 ELSE 2 END';

  /// قناة الفاتورة (رقم [OilShopChannel.index]).
  ///
  /// للمرتجع: مرّر رقم الفاتورة الأصلية وعنوانها حتى يُنسب لقناتها.
  static String channelOf({
    required String invoiceId,
    required String tenant,
    required String deliveryAddress,
  }) =>
      "CASE "
      "WHEN EXISTS (SELECT 1 FROM service_orders sc WHERE sc.invoiceId = $invoiceId "
      "AND sc.tenantId = $tenant AND sc.orderKind = '${ServiceOrderKinds.carWash}') "
      "THEN ${OilShopChannel.carWash.index} "
      "WHEN EXISTS (SELECT 1 FROM service_orders sc WHERE sc.invoiceId = $invoiceId "
      "AND sc.tenantId = $tenant AND IFNULL(sc.orderKind, '') != '${ServiceOrderKinds.carWash}') "
      "THEN ${OilShopChannel.oilCard.index} "
      "WHEN $deliveryAddress = '${OilChangeDirectSaleService.sourceTag}' "
      "THEN ${OilShopChannel.directSale.index} "
      "ELSE ${OilShopChannel.quickSale.index} END";

  /// بطاقة خدمة غير ملغاة وغير محذوفة.
  static String aliveOrder(String so) =>
      "($so.deletedAt IS NULL OR TRIM(COALESCE($so.deletedAt, '')) = '') "
      "AND IFNULL($so.status, '') != 'cancelled'";
}
