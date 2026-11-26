import 'dart:math' as math;

import '../../navigation/content_navigation.dart';
import '../../services/permission_service.dart';
import '../assistant_tool.dart';
import '../assistant_tool_result.dart';
import '../data/assistant_period.dart';
import '../data/assistant_shop_data.dart';
import '../data/oil_query_normalize.dart';
import 'read_tools.dart';

/// الأدوات الإضافية (4.13ب، 4.13ج، م1-20 إلى م1-31). تقرأ فقط.
List<AssistantTool> buildExtraTools(AssistantShopData data, {required bool Function(String routeId) canOpen}) => [
  ReorderSuggestTool(data),
  DueCustomersTool(data),
  ComparePeriodsTool(data),
  AccountAuditTool(data, canOpen),
  const CalcTool(),
  MyPerformanceTool(data),
  DaySummaryTool(data, canOpen),
  PurchaseHistoryTool(data),
  NabooAccountTool(data),
];

const _kinds = {'oil', 'hydraulic', 'filter', 'general'};
const _periodArg = AssistantArgSpec(AssistantArgType.string, allowed: AssistantPeriod.keys);

int _i(Object? v) => (v as num?)?.toInt() ?? 0;

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// آخر 30 يوماً شاملة اليوم: أساس معدل الاستهلاك.
AssistantPeriod _last30(DateTime now) =>
    AssistantPeriod.resolve('custom', from: _iso(now.subtract(const Duration(days: 29))), to: _iso(now), now: now)!;

// ---------------------------------------------------------------- م1-20

class ReorderSuggestTool extends AssistantTool {
  const ReorderSuggestTool(this.data);
  final AssistantShopData data;

  @override
  String get name => 'reorder_suggest';
  @override
  List<String> get requiredPermissions => const [PermissionKeys.inventoryView];
  @override
  Map<String, AssistantArgSpec> get args => const {'kind': AssistantArgSpec(AssistantArgType.string, allowed: _kinds)};

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final kind = args['kind'] as String?;
    final stock = await data.stockItems();
    final kinds = {for (final x in stock) x['id']: x['kind']};
    final rows = <Map<String, Object?>>[];
    final listed = <Object?>{};
    for (final p in await data.productSales(_last30(ctx.clock))) {
      if (kind != null && kinds[p['id']] != kind) continue;
      final suggest = (p['reorder_qty'] as num?) ?? 0;
      if (suggest <= 0) continue;
      listed.add(p['id']);
      final cover = p['days_of_cover'] as num?;
      rows.add({
        'name': p['name'],
        'qty': p['qty'],
        'unit': p['unit'],
        'sold_30d': p['sold_qty'],
        if (cover != null) 'days_left': cover.floor(),
        'suggest_qty': suggest,
      });
    }
    rows.sort((a, b) => ((a['days_left'] as num?) ?? 0).compareTo((b['days_left'] as num?) ?? 0));
    // ما تحت حدّ التنبيه بلا مبيعات في 30 يوماً: يُقترح بعدها ليرجع فوق حدّه (ت4.8).
    for (final x in stock) {
      if (listed.contains(x['id']) || (kind != null && x['kind'] != kind)) continue;
      final qty = x['qty'] is num ? x['qty']! as num : 0;
      final th = x['threshold'] is num ? x['threshold']! as num : 0;
      if (th <= 0 || qty > th) continue;
      rows.add({
        'name': x['name'],
        'qty': qty,
        'unit': x['unit'],
        'sold_30d': 0,
        'threshold': th,
        'suggest_qty': (th - qty + 1).ceil(),
        'basis': 'below_threshold_no_sales',
      });
    }
    return AssistantToolResult.success(
      name,
      rows,
      source: 'من مبيعات آخر 30 يوماً وحدّ التنبيه',
      extra: const {'basis_days': 30, 'cover_days': 30},
    );
  }
}

// ---------------------------------------------------------------- م1-21

class DueCustomersTool extends AssistantTool {
  const DueCustomersTool(this.data);
  final AssistantShopData data;

  @override
  String get name => 'due_customers';
  @override
  List<String> get requiredPermissions => const [PermissionKeys.customersView];
  @override
  Map<String, AssistantArgSpec> get args => const {'days_ahead': AssistantArgSpec(AssistantArgType.integer)};

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final ahead = (_i(args['days_ahead']) == 0 ? 7 : _i(args['days_ahead'])).clamp(0, 60);
    final delay = await data.followupDelayDays();
    final today = DateTime(ctx.clock.year, ctx.clock.month, ctx.clock.day);
    final limit = today.add(Duration(days: ahead));
    final rows = <Map<String, Object?>>[];
    for (final v in await data.latestVisitPerCar()) {
      final last = DateTime.tryParse('${v['date']}');
      if (last == null) continue;
      final due = DateTime(last.year, last.month, last.day + delay);
      if (due.isAfter(limit)) continue;
      rows.add({
        'customer': v['customer'],
        'plate': v['plate'],
        'car': v['car'],
        'last_visit': v['date'],
        'due_date': _iso(due),
        'overdue_days': math.max(0, today.difference(due).inDays),
        'next_odometer': ?v['next_odometer'],
      });
    }
    rows.sort((a, b) => _i(b['overdue_days']).compareTo(_i(a['overdue_days'])));
    return AssistantToolResult.success(
      name,
      rows,
      source: 'من سجل الغيارات وقاعدة المتابعة',
      extra: {'delay_days': delay, 'days_ahead': ahead},
    );
  }
}

// ---------------------------------------------------------------- م1-22

class ComparePeriodsTool extends AssistantTool {
  const ComparePeriodsTool(this.data);
  final AssistantShopData data;

  @override
  String get name => 'compare_periods';
  @override
  List<String> get requiredPermissions => const [PermissionKeys.reportsAccess];
  @override
  Map<String, AssistantArgSpec> get args => const {
    'a': AssistantArgSpec(AssistantArgType.string, required: true, allowed: AssistantPeriod.keys),
    'b': AssistantArgSpec(AssistantArgType.string, required: true, allowed: AssistantPeriod.keys),
  };

  Future<Map<String, Object?>> _side(AssistantPeriod p) async {
    var count = 0;
    var total = 0;
    final channels = <String, Object?>{};
    for (final c in const ['oil', 'direct', 'wash']) {
      final s = await data.sales(p, c);
      count += _i(s['count']);
      total += _i(s['total_fils']);
      channels['${c}_count'] = _i(s['count']);
      channels['${c}_fils'] = _i(s['total_fils']);
    }
    return {
      ...p.toJson(),
      'count': count,
      'total_fils': total,
      'avg_fils': count == 0 ? 0 : total ~/ count,
      ...channels,
    };
  }

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final a = AssistantPeriod.resolve(args['a'], now: ctx.clock);
    final b = AssistantPeriod.resolve(args['b'], now: ctx.clock);
    if (a == null || b == null || a.key == 'custom' || b.key == 'custom') {
      return AssistantToolResult.failure(name, 'bad_args:period');
    }
    final sa = await _side(a);
    final sb = await _side(b);
    // أكبر تغيّر في الأصناف والفنيين: أرقام فقط، والتفسير للمستخدم.
    Map<String, int> amounts(List<Map<String, Object?>> rows, String key) => {
      for (final r in rows) '${r['name']}': _i(r[key]),
    };
    final pa = amounts(await data.productSales(a), 'amount_fils');
    final pb = amounts(await data.productSales(b), 'amount_fils');
    final ta = amounts(await data.technicians(a), 'count');
    final tb = amounts(await data.technicians(b), 'count');
    List<Map<String, Object?>> moves(Map<String, int> x, Map<String, int> y, String unit) {
      final out =
          [
            for (final k in {...x.keys, ...y.keys})
              if ((x[k] ?? 0) != (y[k] ?? 0)) {'name': k, 'a_$unit': x[k] ?? 0, 'b_$unit': y[k] ?? 0},
          ]..sort(
            (m, n) =>
                (_i(n['a_$unit']) - _i(n['b_$unit'])).abs().compareTo((_i(m['a_$unit']) - _i(m['b_$unit'])).abs()),
          );
      return out.take(5).toList();
    }

    return AssistantToolResult.success(
      name,
      [
        {'side': 'a', ...sa},
        {'side': 'b', ...sb},
      ],
      source: 'من شاشة التقارير للفترتين',
      extra: {
        'count_diff': _i(sa['count']) - _i(sb['count']),
        'total_diff_fils': _i(sa['total_fils']) - _i(sb['total_fils']),
        'avg_diff_fils': _i(sa['avg_fils']) - _i(sb['avg_fils']),
        'product_moves': moves(pa, pb, 'fils'),
        'technician_moves': moves(ta, tb, 'count'),
      },
    );
  }
}

// ---------------------------------------------------------------- م1-23

/// عتبات فحص الحساب (ق: أرقام فقط، بلا اتهام).
abstract final class AuditThresholds {
  static const pendingCardDays = 3;
  static const oldDebtDays = 60;
}

class AccountAuditTool extends AssistantTool {
  const AccountAuditTool(this.data, this.canOpen);
  final AssistantShopData data;
  final bool Function(String routeId) canOpen;

  @override
  String get name => 'account_audit';
  @override
  List<String> get requiredPermissions => const [];

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    if (!ctx.isOwner) {
      return AssistantToolResult.failure(name, 'forbidden', needs: 'owner', needsLabel: 'صاحب المحل فقط');
    }
    final today = DateTime(ctx.clock.year, ctx.clock.month, ctx.clock.day);
    final items = await data.stockItems();
    final negative = [
      for (final x in items)
        if (((x['qty'] as num?) ?? 0) < 0) x['name'],
    ];
    final noCost = [
      for (final x in items)
        if (_i(x['buy_price_fils']) <= 0 && x['kind'] != 'general') x['name'],
    ];
    final underCost = [
      for (final p in await data.productSales(_last30(ctx.clock)))
        if (p['profit_fils'] != null && _i(p['profit_fils']) < 0) p['name'],
    ];
    final pending = [
      for (final c in await data.oilCards(status: 'pending', limit: 200))
        if ((DateTime.tryParse('${c['date']}') ?? today).isBefore(
          today.subtract(const Duration(days: AuditThresholds.pendingCardDays)),
        ))
          {'id': c['id'], 'plate': c['plate'], 'date': c['date']},
    ];
    final oldDebts = [
      for (final d in await data.debtors())
        if (d['oldest'] != null &&
            (DateTime.tryParse('${d['oldest']}') ?? today).isBefore(
              today.subtract(const Duration(days: AuditThresholds.oldDebtDays)),
            ))
          {'customer': d['customer'], 'amount_fils': d['amount_fils'], 'oldest': d['oldest']},
    ];
    Map<String, Object?> check(String key, String title, List<Object?> list, String route) => {
      'check': key,
      'title': title,
      'count': list.length,
      'ok': list.isEmpty,
      'route': route,
      'examples': list.take(5).toList(),
    };
    final rows = [
      check('negative_stock', 'مخزون بالسالب', negative, AppContentRoutes.inventoryProducts),
      check('no_buy_price', 'صنف بلا سعر شراء', noCost, AppContentRoutes.inventoryProducts),
      check('sold_under_cost', 'بيع تحت الكلفة (30 يوماً)', underCost, AppContentRoutes.reports(0)),
      check(
        'old_pending_cards',
        'بطاقات معلّقة أقدم من ${AuditThresholds.pendingCardDays} أيام',
        pending,
        AppContentRoutes.oilServicesLog,
      ),
      check('old_debts', 'ديون أقدم من ${AuditThresholds.oldDebtDays} يوماً', oldDebts, AppContentRoutes.debts),
    ];
    return AssistantToolResult.success(
      name,
      rows,
      source: 'فحص على جهازك',
      extra: {'issues': rows.where((r) => r['ok'] == false).length},
    );
  }
}

// ---------------------------------------------------------------- م1-25

/// حاسبة الورشة: الهاتف يحسب والنموذج يختار الدالة فقط. المبالغ بالدينار كما
/// كتبها المستخدم، والناتج بالفلس.
class CalcTool extends AssistantTool {
  const CalcTool();

  @override
  String get name => 'calc';
  @override
  List<String> get requiredPermissions => const [];
  @override
  bool get guideLevel => true;
  @override
  Map<String, AssistantArgSpec> get args => const {
    'fn': AssistantArgSpec(
      AssistantArgType.string,
      required: true,
      allowed: {
        'liter_price_from_bulk',
        'bottles_for_capacity',
        'next_change_km',
        'full_change_total',
        'qty_times_price',
        'percent_off',
      },
    ),
    'args': AssistantArgSpec(AssistantArgType.map, required: true),
  };

  static num? _n(Map a, String k) {
    final v = a[k];
    if (v is num) return v;
    return num.tryParse(OilQueryNormalize.normalize('${v ?? ''}').replaceAll(',', ''));
  }

  /// الناتج أو رسالة خطأ بالحقل الناقص.
  static Map<String, Object?> compute(String fn, Map a) {
    num need(String k) {
      final v = _n(a, k);
      if (v == null || v < 0 || !v.isFinite) throw ArgumentError(k);
      return v;
    }

    switch (fn) {
      case 'liter_price_from_bulk':
        // سعر البرميل أو الجالون ÷ لتراته.
        final price = need('bulk_price_iqd');
        final liters = need('liters');
        if (liters == 0) throw ArgumentError('liters');
        return {'liter_price_fils': (price * 1000 / liters).round()};
      case 'bottles_for_capacity':
        final cap = need('capacity_l');
        final bottle = need('bottle_l');
        if (bottle == 0) throw ArgumentError('bottle_l');
        final n = (cap / bottle - 1e-9).ceil();
        return {'bottles': n, 'leftover_l': double.parse((n * bottle - cap).toStringAsFixed(2))};
      case 'next_change_km':
        final odo = need('odometer');
        final interval = need('interval_km');
        return {'next_km': (odo + interval).round()};
      case 'full_change_total':
        final liters = need('liters');
        final lp = need('liter_price_iqd');
        final filter = _n(a, 'filter_price_iqd') ?? 0;
        final labor = _n(a, 'labor_iqd') ?? 0;
        final oil = (liters * lp * 1000).round();
        return {
          'oil_fils': oil,
          'filter_fils': (filter * 1000).round(),
          'labor_fils': (labor * 1000).round(),
          'total_fils': oil + (filter * 1000).round() + (labor * 1000).round(),
        };
      case 'qty_times_price':
        // «4 لتر بـ 7000 اللتر»، «3 علب بـ 28000».
        final qty = need('qty');
        final unit = need('unit_price_iqd');
        return {'total_fils': (qty * unit * 1000).round()};
      case 'percent_off':
        final amount = need('amount_iqd');
        final pct = need('percent');
        if (pct > 100) throw ArgumentError('percent');
        final off = (amount * pct * 10).round();
        return {'discount_fils': off, 'after_fils': (amount * 1000).round() - off};
    }
    throw ArgumentError('fn');
  }

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    try {
      final out = compute('${args['fn']}', (args['args'] as Map?) ?? const {});
      return AssistantToolResult.success(name, [out], source: 'حساب على جهازك');
    } on ArgumentError catch (e) {
      return AssistantToolResult.failure(name, 'bad_args:${e.message}');
    }
  }
}

// ---------------------------------------------------------------- م1-27

class MyPerformanceTool extends AssistantTool {
  const MyPerformanceTool(this.data);
  final AssistantShopData data;

  @override
  String get name => 'my_performance';
  @override
  List<String> get requiredPermissions => const [];
  @override
  Map<String, AssistantArgSpec> get args => const {'period': _periodArg};

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    // لا معطى لاسم: الأداة لا تستطيع أن ترى غير صاحبها مهما كُتب السؤال.
    final me = OilQueryNormalize.key(ctx.userName ?? '');
    if (me.isEmpty) return AssistantToolResult.failure(name, 'failed');
    final p = AssistantPeriod.resolve(args['period'], now: ctx.clock, fallback: 'this_week');
    if (p == null) return AssistantToolResult.failure(name, 'bad_args:period');
    final today = AssistantPeriod.resolve('today', now: ctx.clock)!;
    bool mine(Map<String, Object?> c) => OilQueryNormalize.key('${c['technician'] ?? ''}') == me;
    final cards = (await data.oilCards(period: p, limit: 1000)).where(mine).toList();
    final todayCards = (await data.oilCards(period: today, limit: 1000)).where(mine).length;
    final rating = (await data.ratingsByEmployee()).where((r) => OilQueryNormalize.key('${r['employee']}') == me);
    return AssistantToolResult.success(name, [
      {
        ...p.toJson(),
        'cards': cards.length,
        'cards_today': todayCards,
        if (rating.isNotEmpty) 'rating_avg': rating.first['avg'],
        if (rating.isNotEmpty) 'rating_count': rating.first['count'],
      },
    ], source: 'من بطاقاتك أنت فقط');
  }
}

// ---------------------------------------------------------------- م1-28

class DaySummaryTool extends AssistantTool {
  const DaySummaryTool(this.data, this.canOpen);
  final AssistantShopData data;
  final bool Function(String routeId) canOpen;

  @override
  String get name => 'day_summary';
  @override
  List<String> get requiredPermissions => const [];

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final today = AssistantPeriod.resolve('today', now: ctx.clock)!;
    final out = <String, Object?>{...today.toJson()};
    final sections = <String>[];
    if (ctx.has(PermissionKeys.reportsAccess)) {
      var count = 0;
      var total = 0;
      for (final c in const ['oil', 'direct', 'wash']) {
        final s = await data.sales(today, c);
        count += _i(s['count']);
        total += _i(s['total_fils']);
        out['${c}_count'] = _i(s['count']);
      }
      out['sales_count'] = count;
      out['sales_fils'] = total;
      sections.add('sales');
    }
    if (ctx.has(PermissionKeys.cashView)) {
      final c = await data.cash(today);
      out['cash_in_fils'] = c['in_fils'];
      out['cash_out_fils'] = c['out_fils'];
      out['expenses_fils'] = c['expenses_fils'];
      sections.add('cash');
    }
    if (canOpen(AppContentRoutes.oilServicesLog)) {
      out['pending_cards'] = (await data.oilCards(status: 'pending', limit: 200)).length;
      sections.add('cards');
    }
    if (ctx.has(PermissionKeys.inventoryView)) {
      out['low_stock'] = (await data.lowStock()).length;
      sections.add('stock');
    }
    if (ctx.has(PermissionKeys.debtsPanel)) {
      out['open_debts_fils'] = (await data.debtTotals())['open_total_fils'];
      sections.add('debts');
    }
    return AssistantToolResult.success(name, [out], source: 'ملخص اليوم حسب صلاحيتك', extra: {'sections': sections});
  }
}

// ---------------------------------------------------------------- م1-29

class PurchaseHistoryTool extends AssistantTool {
  const PurchaseHistoryTool(this.data);
  final AssistantShopData data;

  @override
  String get name => 'purchase_history';
  @override
  List<String> get requiredPermissions => const [PermissionKeys.ownerKpiFinancial];
  @override
  Map<String, AssistantArgSpec> get args => const {
    'product_id': AssistantArgSpec(AssistantArgType.string),
    'name': AssistantArgSpec(AssistantArgType.string),
  };

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    var id = int.tryParse('${args['product_id'] ?? ''}');
    String? label;
    if (id == null) {
      final q = '${args['name'] ?? ''}'.trim();
      if (q.isEmpty) return AssistantToolResult.failure(name, 'bad_args:missing_product');
      final found = searchItems(await data.stockItems(), q);
      if (found.isEmpty) return AssistantToolResult.success(name, const [], extra: const {'no_match': true});
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
      label = '${found.first['name']}';
    }
    final rows = await data.purchases(id);
    return AssistantToolResult.success(
      name,
      rows,
      source: 'من سندات الإدخال',
      extra: {'product': ?label, if (rows.isEmpty) 'no_match': true},
    );
  }
}

// ---------------------------------------------------------------- م1-31

class NabooAccountTool extends AssistantTool {
  const NabooAccountTool(this.data);
  final AssistantShopData data;

  @override
  String get name => 'naboo_account';
  @override
  List<String> get requiredPermissions => const [PermissionKeys.settingsApp];

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async =>
      AssistantToolResult.success(name, [await data.nabooAccount()], source: 'من حسابك في نابو');
}
