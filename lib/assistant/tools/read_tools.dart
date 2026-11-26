import '../../home/employee_access_policy.dart';
import '../../navigation/content_navigation.dart';
import '../../services/permission_service.dart';
import '../assistant_tool.dart';
import '../assistant_tool_guard.dart';
import '../assistant_tool_result.dart';
import '../data/assistant_period.dart';
import '../data/assistant_shop_data.dart';
import '../data/oil_query_normalize.dart';

/// أدوات القراءة الثلاث عشرة (4.3، م1-5، م1-6). كلها تقرأ فقط، والحارس
/// يحذف الحقول المالية ويقص الصفوف ويحوّل المبالغ إلى علامات.
List<AssistantTool> buildReadTools(AssistantShopData data, {required bool Function(String routeId) canOpen}) => [
  StockSearchTool(data),
  StockLowTool(data),
  ProductDetailTool(data),
  OilCardFindTool(data, canOpen),
  CarHistoryTool(data, canOpen),
  SalesSummaryTool(data),
  TopProductsTool(data),
  DebtsSummaryTool(data),
  CashSummaryTool(data),
  StaffStatusTool(data),
  RatingsSummaryTool(data),
  WaStatusTool(data),
  CustomerFindTool(data),
];

const _kinds = {'oil', 'hydraulic', 'filter', 'general'};
const _periodArg = AssistantArgSpec(AssistantArgType.string, allowed: AssistantPeriod.keys);
const _dateArg = AssistantArgSpec(AssistantArgType.string);

abstract class _ReadTool extends AssistantTool {
  const _ReadTool(this.data);
  final AssistantShopData data;

  AssistantPeriod? period(
    Map<String, Object?> args,
    AssistantToolContext ctx, {
    String key = 'period',
    String fallback = 'today',
  }) => AssistantPeriod.resolve(args[key], from: args['from'], to: args['to'], now: ctx.clock, fallback: fallback);
}

/// مطابقة صنف لما كتبه المستخدم: اللزوجة إن ذُكرت شرط، وباقي الكلمات ترتّب.
/// يعيد درجة المطابقة، و0 = لا يطابق.
int matchScore(Map<String, Object?> item, String query) {
  final v = OilQueryNormalize.viscosityOf(query);
  final name = OilQueryNormalize.key('${item['name'] ?? ''} ${item['brand'] ?? ''}');
  final itemV = item['viscosity'] == null ? null : OilQueryNormalize.viscosityOf('${item['viscosity']}');
  var score = 0;
  if (v != null) {
    final vk = OilQueryNormalize.key(v);
    if (itemV == v || name.contains(vk)) {
      score += 10;
    } else {
      return 0;
    }
  }
  final rest = OilQueryNormalize.normalize(query).replaceAll(v ?? '\u0000', ' ');
  final words = [
    for (final w in rest.split(RegExp(r'\s+')))
      if (OilQueryNormalize.key(w).length >= 2) OilQueryNormalize.key(w),
  ];
  // «زيت» أو «دهن» وحدها: كل الزيوت تطابق، فيختار المستخدم من الأزرار (ق78).
  if (v == null && words.isEmpty) {
    final saidOil = RegExp(r'(^|\s)(ال)?(زيت|دهن|زيوت|دهون)(\s|$)').hasMatch(query.trim());
    return saidOil && (item['kind'] == 'oil' || item['kind'] == 'hydraulic') ? 1 : 0;
  }
  final hits = words.where(name.contains).length;
  if (v == null && words.isNotEmpty && hits == 0) return 0;
  return score + hits * 3 + (words.isNotEmpty && hits == words.length ? 2 : 0);
}

List<Map<String, Object?>> searchItems(List<Map<String, Object?>> items, String query, {String? kind}) {
  final scored = <(int, Map<String, Object?>)>[];
  for (final it in items) {
    if (kind != null && it['kind'] != kind) continue;
    final s = matchScore(it, query);
    if (s > 0) scored.add((s, it));
  }
  scored.sort((a, b) {
    final c = b.$1.compareTo(a.$1);
    return c != 0 ? c : '${a.$2['name']}'.compareTo('${b.$2['name']}');
  });
  return [for (final x in scored) x.$2];
}

Map<String, Object?> _stockRow(Map<String, Object?> x) {
  final qty = x['qty'] is num ? x['qty']! as num : 0;
  final th = x['threshold'] is num ? x['threshold']! as num : 0;
  return {
    'id': x['id'],
    'name': x['name'],
    'brand': ?x['brand'],
    'viscosity': ?x['viscosity'],
    'kind': x['kind'],
    'qty': qty,
    'unit': x['unit'],
    'sell_price_fils': x['sell_price_fils'],
    'buy_price_fils': x['buy_price_fils'],
    'threshold': th,
    'alert': qty <= 0 ? 'out' : (th > 0 && qty <= th ? 'low' : 'ok'),
  };
}

class StockSearchTool extends _ReadTool {
  const StockSearchTool(super.data);

  @override
  String get name => 'stock_search';
  @override
  List<String> get requiredPermissions => const [PermissionKeys.inventoryView];
  @override
  Set<String> get financialFields => const {'buy_price_fils'};
  @override
  Map<String, AssistantArgSpec> get args => const {
    'query': AssistantArgSpec(AssistantArgType.string, required: true),
    'kind': AssistantArgSpec(AssistantArgType.string, allowed: _kinds),
    'limit': AssistantArgSpec(AssistantArgType.integer),
  };

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final query = '${args['query']}'.trim();
    if (query.isEmpty) return AssistantToolResult.failure(name, 'bad_args:missing_query');
    final found = searchItems(await data.stockItems(), query, kind: args['kind'] as String?);
    final limit = ((args['limit'] as num?)?.toInt() ?? 10).clamp(1, 20);
    return AssistantToolResult.success(
      name,
      [for (final x in found.take(limit)) _stockRow(x)],
      total: found.length,
      source: 'من شاشة المخزون',
      extra: {'searched_as': OilQueryNormalize.normalize(query), if (found.isEmpty) 'no_match': true},
    );
  }
}

class StockLowTool extends _ReadTool {
  const StockLowTool(super.data);

  @override
  String get name => 'stock_low';
  @override
  List<String> get requiredPermissions => const [PermissionKeys.inventoryView];
  @override
  Map<String, AssistantArgSpec> get args => const {'kind': AssistantArgSpec(AssistantArgType.string, allowed: _kinds)};

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final kind = args['kind'] as String?;
    final rows = [
      for (final x in await data.lowStock())
        if (kind == null || x['kind'] == kind) x,
    ]..sort((a, b) => ((a['qty'] as num?) ?? 0).compareTo((b['qty'] as num?) ?? 0));
    return AssistantToolResult.success(name, rows, source: 'من تنبيهات المخزون');
  }
}

class ProductDetailTool extends _ReadTool {
  const ProductDetailTool(super.data);

  @override
  String get name => 'product_detail';
  @override
  List<String> get requiredPermissions => const [PermissionKeys.inventoryView];
  @override
  Set<String> get financialFields => const {'buy_price_fils'};
  @override
  Map<String, AssistantArgSpec> get args => const {
    'product_id': AssistantArgSpec(AssistantArgType.string),
    'name': AssistantArgSpec(AssistantArgType.string),
    'barcode': AssistantArgSpec(AssistantArgType.string),
  };

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    var id = int.tryParse('${args['product_id'] ?? ''}');
    final code = '${args['barcode'] ?? ''}'.trim();
    if (id == null && code.isNotEmpty) {
      id = await data.productIdByBarcode(code);
      if (id == null) {
        return AssistantToolResult.success(name, const [], extra: {'no_match': true, 'barcode': code});
      }
    }
    if (id == null) {
      final q = '${args['name'] ?? ''}'.trim();
      if (q.isEmpty) return AssistantToolResult.failure(name, 'bad_args:missing_product');
      final found = searchItems(await data.stockItems(), q);
      if (found.isEmpty) return AssistantToolResult.success(name, const [], extra: const {'no_match': true});
      // أكثر من صنف بنفس الدرجة: يسأل المستخدم بأزرار (م2-23).
      final top = matchScore(found.first, q);
      final tied = found.where((x) => matchScore(x, q) == top).toList();
      if (tied.length > 1) {
        return AssistantToolResult.success(
          name,
          const [],
          extra: {
            'ambiguous': true,
            'candidates': [
              for (final x in tied.take(20)) {'id': '${x['id']}', 'label': x['name']},
            ],
            'candidates_total': tied.length,
          },
        );
      }
      id = (found.first['id'] as num).toInt();
    }
    final d = await data.productDetail(id);
    if (d == null) return AssistantToolResult.success(name, const [], extra: const {'no_match': true});
    return AssistantToolResult.success(name, [d], source: 'من بطاقة المنتج');
  }
}

/// دخول سجل الزيت شرط لأداتي البطاقات والسيارة، بنفس قرار القائمة.
AssistantToolResult? _oilLogDenied(String tool, bool Function(String) canOpen) {
  if (canOpen(AppContentRoutes.oilServicesLog)) return null;
  final key = EmployeeAccessPolicy.permissionKeyForRoute(AppContentRoutes.oilServicesLog);
  return AssistantToolResult.failure(
    tool,
    'forbidden',
    needs: key,
    needsLabel: key == null ? 'سجل غيارات الزيت' : AssistantToolGuard.labelFor(key),
  );
}

class OilCardFindTool extends _ReadTool {
  const OilCardFindTool(super.data, this.canOpen);
  final bool Function(String routeId) canOpen;

  @override
  String get name => 'oil_card_find';
  @override
  List<String> get requiredPermissions => const [];
  @override
  Map<String, AssistantArgSpec> get args => const {
    'card_id': AssistantArgSpec(AssistantArgType.string),
    'plate': AssistantArgSpec(AssistantArgType.string),
    'customer': AssistantArgSpec(AssistantArgType.string),
    'period': _periodArg,
    'from': _dateArg,
    'to': _dateArg,
    'status': AssistantArgSpec(AssistantArgType.string, allowed: {'pending', 'invoiced', 'any'}),
  };

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final denied = _oilLogDenied(name, canOpen);
    if (denied != null) return denied;
    final status = (args['status'] as String?) ?? 'any';
    final plate = (args['plate'] as String?)?.trim();
    final customer = (args['customer'] as String?)?.trim();
    // بطاقة بعينها (من سياق الشاشة): بلا فترة ولا حالة.
    final cardId = int.tryParse('${args['card_id'] ?? ''}');
    if (cardId != null) {
      final rows = await data.oilCards(id: cardId, limit: 1);
      return AssistantToolResult.success(name, rows, source: 'من بطاقة الغيار', extra: {if (rows.isEmpty) 'no_match': true});
    }
    // المعلّقة تُبحث في كل الأيام، وغيرها في الفترة (اليوم افتراضياً) إن لم تُذكر لوحة أو زبون.
    final hasKey = (plate?.isNotEmpty ?? false) || (customer?.isNotEmpty ?? false);
    AssistantPeriod? p;
    if (args['period'] != null || (!hasKey && status != 'pending')) {
      p = period(args, ctx);
      if (p == null) return AssistantToolResult.failure(name, 'bad_args:period');
    }
    final rows = await data.oilCards(plate: plate, customer: customer, period: p, status: status);
    return AssistantToolResult.success(
      name,
      rows,
      source: 'من سجل غيارات الزيت',
      extra: {...?p?.toJson(), 'status': status},
    );
  }
}

class CarHistoryTool extends _ReadTool {
  const CarHistoryTool(super.data, this.canOpen);
  final bool Function(String routeId) canOpen;

  @override
  String get name => 'car_history';
  @override
  List<String> get requiredPermissions => const [];
  @override
  Map<String, AssistantArgSpec> get args => const {
    'plate': AssistantArgSpec(AssistantArgType.string),
    'customer_id': AssistantArgSpec(AssistantArgType.string),
  };

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final denied = _oilLogDenied(name, canOpen);
    if (denied != null) return denied;
    final plate = (args['plate'] as String?)?.trim();
    final cid = int.tryParse('${args['customer_id'] ?? ''}');
    if ((plate == null || plate.isEmpty) && cid == null) {
      return AssistantToolResult.failure(name, 'bad_args:missing_plate');
    }
    final rows = await data.carVisits(plate: plate, customerId: cid);
    final next = rows.isEmpty ? null : rows.first['next_odometer'];
    return AssistantToolResult.success(
      name,
      rows,
      source: 'من سجل السيارة',
      extra: {'next_odometer': ?next, if (rows.isEmpty) 'no_match': true},
    );
  }
}

class SalesSummaryTool extends _ReadTool {
  const SalesSummaryTool(super.data);

  @override
  String get name => 'sales_summary';
  @override
  List<String> get requiredPermissions => const [PermissionKeys.reportsAccess];
  @override
  Set<String> get financialFields => const {'profit_fils'};
  @override
  Map<String, AssistantArgSpec> get args => const {
    'period': _periodArg,
    'from': _dateArg,
    'to': _dateArg,
    'channel': AssistantArgSpec(AssistantArgType.string, allowed: {'oil', 'direct', 'wash', 'all'}),
  };

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final p = period(args, ctx);
    if (p == null) return AssistantToolResult.failure(name, 'bad_args:period');
    final channel = (args['channel'] as String?) ?? 'all';
    final channels = channel == 'all' ? const ['oil', 'direct', 'wash'] : [channel];
    var count = 0;
    var total = 0;
    var returns = 0;
    int? cost = channel == 'oil' ? 0 : null;
    final parts = <Map<String, Object?>>[];
    for (final c in channels) {
      final s = await data.sales(p, c);
      final n = (s['count'] as num?)?.toInt() ?? 0;
      final t = (s['total_fils'] as num?)?.toInt() ?? 0;
      count += n;
      total += t;
      returns += (s['returns'] as num?)?.toInt() ?? 0;
      if (cost != null) cost += (s['cost_fils'] as num?)?.toInt() ?? 0;
      parts.add({'channel': c, 'count': n, 'total_fils': t});
    }
    return AssistantToolResult.success(name, [
      {
        ...p.toJson(),
        'channel': channel,
        'count': count,
        'total_fils': total,
        'avg_fils': count == 0 ? 0 : total ~/ count,
        'returns': returns,
        if (cost != null && cost > 0) 'profit_fils': total - cost,
      },
      if (channels.length > 1) ...parts,
    ], source: 'من شاشة التقارير');
  }
}

class TopProductsTool extends _ReadTool {
  const TopProductsTool(super.data);

  @override
  String get name => 'top_products';
  @override
  List<String> get requiredPermissions => const [PermissionKeys.reportsAccess];
  @override
  Set<String> get financialFields => const {'profit_fils'};
  @override
  Map<String, AssistantArgSpec> get args => const {
    'period': _periodArg,
    'from': _dateArg,
    'to': _dateArg,
    'limit': AssistantArgSpec(AssistantArgType.integer),
  };

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final p = period(args, ctx, fallback: 'this_month');
    if (p == null) return AssistantToolResult.failure(name, 'bad_args:period');
    final sold = [
      for (final x in await data.productSales(p))
        if (((x['sold_qty'] as num?) ?? 0) > 0) x,
    ]..sort((a, b) => ((b['amount_fils'] as num?) ?? 0).compareTo((a['amount_fils'] as num?) ?? 0));
    final limit = ((args['limit'] as num?)?.toInt() ?? 10).clamp(1, 20);
    return AssistantToolResult.success(
      name,
      [
        for (final x in sold.take(limit))
          {
            'name': x['name'],
            'sold_qty': x['sold_qty'],
            'unit': x['unit'],
            'amount_fils': x['amount_fils'],
            'profit_fils': ?x['profit_fils'],
          },
      ],
      total: sold.length,
      source: 'من تقرير المنتجات',
      extra: p.toJson(),
    );
  }
}

class DebtsSummaryTool extends _ReadTool {
  const DebtsSummaryTool(super.data);

  @override
  String get name => 'debts_summary';
  @override
  List<String> get requiredPermissions => const [PermissionKeys.debtsPanel];
  @override
  Map<String, AssistantArgSpec> get args => const {'customer': AssistantArgSpec(AssistantArgType.string)};

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final who = (args['customer'] as String?)?.trim() ?? '';
    var list = await data.debtors();
    if (who.isNotEmpty) {
      final k = OilQueryNormalize.key(who);
      list = [
        for (final d in list)
          if (OilQueryNormalize.key('${d['customer']}').contains(k)) d,
      ];
    } else {
      list.sort((a, b) => ((b['amount_fils'] as num?) ?? 0).compareTo((a['amount_fils'] as num?) ?? 0));
      list = list.take(10).toList();
    }
    final head = await data.debtTotals();
    return AssistantToolResult.success(
      name,
      [head, ...list],
      source: 'من شاشة الديون',
      extra: {if (who.isNotEmpty && list.isEmpty) 'no_match': true},
    );
  }
}

class CashSummaryTool extends _ReadTool {
  const CashSummaryTool(super.data);

  @override
  String get name => 'cash_summary';
  @override
  List<String> get requiredPermissions => const [PermissionKeys.cashView];
  @override
  Map<String, AssistantArgSpec> get args => const {'period': _periodArg, 'from': _dateArg, 'to': _dateArg};

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final p = period(args, ctx);
    if (p == null) return AssistantToolResult.failure(name, 'bad_args:period');
    final c = await data.cash(p);
    return AssistantToolResult.success(name, [
      {...p.toJson(), ...c},
    ], source: 'من شاشة الصندوق');
  }
}

class StaffStatusTool extends _ReadTool {
  const StaffStatusTool(super.data);

  @override
  String get name => 'staff_status';
  @override
  List<String> get requiredPermissions => const [PermissionKeys.usersView, PermissionKeys.shiftsAccess];

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async =>
      AssistantToolResult.success(name, [await data.shift()], source: 'من الورديات');
}

class RatingsSummaryTool extends _ReadTool {
  const RatingsSummaryTool(super.data);

  @override
  String get name => 'ratings_summary';
  @override
  List<String> get requiredPermissions => const [PermissionKeys.reportsAccess];
  @override
  Map<String, AssistantArgSpec> get args => const {'period': _periodArg, 'from': _dateArg, 'to': _dateArg};

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final rows = (await data.ratingsByEmployee()).where((r) => ((r['count'] as num?) ?? 0) > 0).toList();
    var n = 0;
    var sum = 0.0;
    for (final r in rows) {
      final c = (r['count'] as num).toInt();
      n += c;
      sum += c * ((r['avg'] as num?)?.toDouble() ?? 0);
    }
    return AssistantToolResult.success(
      name,
      rows,
      source: 'من شاشة التقييمات',
      // الشاشة تعرض المجموع منذ البداية؛ الفترة لا تُطبَّق هنا.
      extra: {'count': n, if (n > 0) 'avg': double.parse((sum / n).toStringAsFixed(2)), 'scope': 'all_time'},
    );
  }
}

class WaStatusTool extends _ReadTool {
  const WaStatusTool(super.data);

  @override
  String get name => 'wa_status';
  @override
  List<String> get requiredPermissions => const [PermissionKeys.settingsApp];
  @override
  Map<String, AssistantArgSpec> get args => const {'period': _periodArg, 'from': _dateArg, 'to': _dateArg};

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final p = period(args, ctx, fallback: 'this_month');
    if (p == null) return AssistantToolResult.failure(name, 'bad_args:period');
    return AssistantToolResult.success(name, [
      {...p.toJson(), ...await data.whatsapp(p)},
    ], source: 'من شاشة رسائل واتساب');
  }
}

class CustomerFindTool extends _ReadTool {
  const CustomerFindTool(super.data);

  @override
  String get name => 'customer_find';
  @override
  List<String> get requiredPermissions => const [PermissionKeys.customersView];
  @override
  Set<String> get financialFields => const {};
  @override
  Map<String, AssistantArgSpec> get args => const {'query': AssistantArgSpec(AssistantArgType.string, required: true)};

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final q = '${args['query']}'.trim();
    if (q.isEmpty) return AssistantToolResult.failure(name, 'bad_args:missing_query');
    final rows = [
      // الهاتف لا يصل للنموذج أبداً، حتى لو أرجعه المصدر خطأً.
      for (final r in await data.customers(q)) {...r}..remove('phone'),
    ];
    return AssistantToolResult.success(
      name,
      rows,
      source: 'من شاشة الزبائن',
      extra: {if (rows.isEmpty) 'no_match': true},
    );
  }
}
