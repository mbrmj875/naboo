import '../../../services/product_repository.dart';
import '../../../utils/iqd_money.dart';

/// تقدير سعر بيع مادة الزيت على البطاقة (فلس) — للعرض فقط.
Future<int> estimateOilMaterialSellFils(Map<String, dynamic> order) async {
  if (((order['oilCustomerProvided'] as num?)?.toInt() ?? 0) != 0) {
    return 0;
  }
  final pid = (order['oilProductId'] as num?)?.toInt();
  final liters = (order['oilLitersUsed'] as num?)?.toDouble() ?? 0;
  if (pid == null || pid <= 0 || liters <= 1e-9) return 0;

  final row = await ProductRepository().getProductById(pid);
  if (row == null) return 0;
  final sell = (row['sellPrice'] as num?)?.toDouble() ?? 0;
  if (sell <= 0) return 0;
  return IqdMoney.toFils(sell * liters);
}

Future<String?> oilProductDisplayName(Map<String, dynamic> order) async {
  final pid = (order['oilProductId'] as num?)?.toInt();
  if (pid == null || pid <= 0) return null;
  final row = await ProductRepository().getProductById(pid);
  if (row == null) return null;
  final name = (row['name'] ?? '').toString().trim();
  return name.isEmpty ? null : name;
}
