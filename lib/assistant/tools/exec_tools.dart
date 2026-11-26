import '../../home/employee_access_policy.dart';
import '../../navigation/content_navigation.dart';
import '../../services/permission_service.dart';
import '../assistant_tool.dart';
import '../assistant_tool_guard.dart';
import '../assistant_tool_result.dart';
import '../data/assistant_shop_data.dart';
import '../data/oil_query_normalize.dart';
import '../exec/assistant_actions.dart';
import '../exec/assistant_exec_port.dart';
import '../exec/assistant_name_match.dart';
import '../exec/assistant_prefill.dart';
import '../exec/assistant_reminders.dart';

/// أدوات التنفيذ بتأكيد (4.5، م4).
///
/// القاعدة: لا أداة هنا تكتب في القاعدة. كل أداة تفحص وتجهّز وتسجّل اقتراحاً
/// في [AssistantActions]، والبطاقة تعرضه. الحفظ لا يبدأ إلا بضغطة المستخدم:
/// زر «افتح وراجع» يفتح النموذج الحقيقي فيحفظه المستخدم بزره، وزر «تأكيد»
/// يستدعي دالة التطبيق الموجودة. الإلغاء لا يترك أثراً.
///
/// ما لا يوجد هنا عمداً (ممنوع نهائياً): المسح النهائي، المرتجعات، إلغاء الفواتير،
/// الصلاحيات والمستخدمين، ربط واتساب، إغلاق الوردية، المزامنة. «الإيقاف» (ع4)
/// إخفاء يُرجَع من شاشة المخزون، لا مسح.
List<AssistantTool> buildExecTools(
  AssistantShopData data,
  AssistantExecPort port, {
  required bool Function(String routeId) canOpen,
}) => [
  PrepareOilCardTool(data, port, canOpen),
  PrepareCarWashTool(data, port, canOpen),
  PrepareCustomerTool(data, port, canOpen),
  PrepareProductTool(data, port, canOpen),
  PrepareExpenseTool(data, port, canOpen),
  ProposePriceChangeTool(data, port, canOpen),
  ProposeStockAdjustTool(data, port, canOpen),
  ProposeSupplierIntakeTool(data, port, canOpen),
  ProposeStockCountTool(data, port, canOpen),
  OpenPrintPreviewTool(data, port, canOpen),
  ReminderSetTool(data, port, canOpen),
  ProposeProductDeactivateTool(data, port, canOpen),
  ProposeStockTransferTool(data, port, canOpen),
  ProposeDebtPaymentTool(data, port, canOpen),
];

/// أسماء أدوات التنفيذ، لفحص أن الممنوع غير موجود.
const assistantExecToolNames = {
  'prepare_oil_card',
  'prepare_car_wash',
  'prepare_customer',
  'prepare_product',
  'prepare_expense',
  'propose_price_change',
  'propose_stock_adjust',
  'propose_supplier_intake',
  'propose_stock_count',
  'open_print_preview',
  'reminder_set',
  'propose_product_deactivate',
  'propose_stock_transfer',
  'propose_debt_payment',
};

abstract class _ExecTool extends AssistantTool {
  const _ExecTool(this.data, this.port, this.canOpen);

  final AssistantShopData data;
  final AssistantExecPort port;
  final bool Function(String routeId) canOpen;

  AssistantToolResult routeDenied(String routeId, String fallbackLabel) {
    final key = EmployeeAccessPolicy.permissionKeyForRoute(routeId);
    return AssistantToolResult.failure(
      name,
      'forbidden',
      needs: key,
      needsLabel: key == null
          ? fallbackLabel
          : AssistantToolGuard.labelFor(key),
    );
  }

  static String? s(Object? v) {
    final t = v == null ? '' : '$v'.trim();
    return t.isEmpty ? null : t;
  }

  static num? n(Object? v) => v is num
      ? v
      : (v == null ? null : num.tryParse('$v'.replaceAll(',', '').trim()));

  static int? id(Object? v) {
    final x = n(v);
    return x == null || x <= 0 || x != x.roundToDouble() ? null : x.toInt();
  }

  /// صفوف البطاقة: الحقل وقيمته، أو «تكمله أنت بالشاشة».
  static List<Map<String, Object?>> fields(
    AssistantPrefill p,
    List<String> keys, {
    Set<String> required = const {},
  }) => [
    for (final k in keys)
      if (p.filled(only: {k}).firstOrNull case final f?)
        {'key': k, 'label': f.$1, 'value': f.$2}
      else if (required.contains(k))
        {'key': k, 'label': AssistantPrefill.labels[k] ?? k, 'missing': true},
  ];

  /// يسجّل فتح النموذج كاقتراح قابل للتكرار: يُفتح، وإن أُغلق بلا حفظ يبقى جاهزاً.
  AssistantToolResult prepared(
    AssistantPrefill p, {
    required String route,
    required String entityType,
    required List<Map<String, Object?>> fieldRows,
    required AssistantToolContext ctx,
    Map<String, Object?> more = const {},
    AssistantPrefill Function(AssistantPrefill p, String choice)? withChoice,
  }) {
    final actionId = AssistantActions.register((choice) async {
      final use = choice == null || withChoice == null
          ? p
          : withChoice(p, choice);
      final out = await port.openForm(use);
      if (!out.saved) return AssistantActions.reopen;
      await AssistantPrefill.recordSaved(
        use,
        entityType: entityType,
        entityId: out.entityId,
        username: ctx.userName,
      );
      return null;
    }, repeatable: true);
    return AssistantToolResult.success(
      name,
      [
        {
          'prepared': true,
          'saved': false,
          'filled': [
            for (final f in fieldRows)
              if (f['missing'] != true) f['label'],
          ],
          'missing': [
            for (final f in fieldRows)
              if (f['missing'] == true) f['label'],
          ],
          ...more,
        },
      ],
      extra: {
        'action_id': actionId,
        'route': route,
        'fields': fieldRows,
        ...more,
      },
    );
  }
}

// ------------------------------------------------------------------ البطاقات المعبّأة

class PrepareOilCardTool extends _ExecTool {
  const PrepareOilCardTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'prepare_oil_card';

  @override
  List<String> get requiredPermissions => const [];

  @override
  Map<String, AssistantArgSpec> get args => const {
    'plate': AssistantArgSpec(AssistantArgType.string),
    'customer': AssistantArgSpec(AssistantArgType.string),
    'oil': AssistantArgSpec(AssistantArgType.string),
    'liters': AssistantArgSpec(AssistantArgType.number),
    'odometer': AssistantArgSpec(AssistantArgType.integer),
    'extras': AssistantArgSpec(AssistantArgType.list),
  };

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    if (!canOpen(AppContentRoutes.oilChangeCreate)) {
      return routeDenied(AppContentRoutes.oilChangeCreate, 'بطاقة غيار جديدة');
    }
    final odo = _ExecTool.n(args['odometer']);
    final liters = _ExecTool.n(args['liters']);
    final p = AssistantPrefill(
      tool: name,
      turnId: ctx.turnId,
      values: {
        'plate': _ExecTool.s(args['plate']),
        'customer': _ExecTool.s(args['customer']),
        'oil': _ExecTool.s(args['oil']),
        if (liters != null && liters > 0 && liters <= 60) 'liters': liters,
        if (odo != null && odo >= 0 && odo < 5000000) 'odometer': odo.toInt(),
        'extras': [for (final e in (args['extras'] as List?) ?? const []) '$e'],
      },
    );
    final stock = await _stockCheck(p.str('oil'), liters?.toDouble());
    return prepared(
      p,
      route: AppContentRoutes.oilChangeCreate,
      entityType: 'service_order',
      ctx: ctx,
      fieldRows: _ExecTool.fields(
        p,
        const ['plate', 'customer', 'oil', 'liters', 'odometer', 'extras'],
        required: const {'plate', 'odometer'},
      ),
      more: {'stock': ?stock},
      withChoice: (p, choice) => AssistantPrefill(
        tool: p.tool,
        turnId: p.turnId,
        values: {...p.values, 'oil': choice},
      ),
    );
  }

  /// م4-12: قبل فتح البطاقة، هل الزيت المطلوب يكفي؟ إن نقص: المتوفر والبدائل
  /// بنفس اللزوجة من المخزون، والمستخدم يختار. قواعد المخزون السالب عند
  /// الحفظ تبقى للتطبيق.
  Future<Map<String, Object?>?> _stockCheck(String? oil, double? liters) async {
    if (oil == null) return null;
    final items = (await data.stockItems())
        .where((x) => x['kind'] == 'oil')
        .toList();
    if (items.isEmpty) return null;
    final m = AssistantNameMatch.match(oil, items);
    final pid =
        m.productId ??
        (m.candidates.length == 1 ? m.candidates.first.$1 : null);
    if (pid == null) return null;
    final item = items.firstWhere((x) => x['id'] == pid);
    final have = (item['qty'] as num?)?.toDouble() ?? 0;
    final need = liters ?? 0.0001;
    if (have >= need) return null;
    final visc = '${item['viscosity'] ?? ''}'.trim().isNotEmpty
        ? '${item['viscosity']}'
        : OilQueryNormalize.viscosityOf('${item['name']}');
    final alternatives =
        [
          for (final x in items)
            if (x['id'] != pid &&
                ((x['qty'] as num?)?.toDouble() ?? 0) >= need &&
                visc != null &&
                ('${x['viscosity'] ?? ''}' == visc ||
                    OilQueryNormalize.viscosityOf('${x['name']}') == visc))
              {'name': x['name'], 'qty': x['qty'], 'unit': x['unit']},
        ]..sort(
          (a, b) =>
              ((b['qty'] as num?) ?? 0).compareTo((a['qty'] as num?) ?? 0),
        );
    return {
      'requested': item['name'],
      'available': have,
      'needed': ?liters,
      'unit': item['unit'],
      'short': true,
      'alternatives': alternatives.take(4).toList(),
    };
  }
}

class PrepareCarWashTool extends _ExecTool {
  const PrepareCarWashTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'prepare_car_wash';

  @override
  List<String> get requiredPermissions => const [];

  @override
  Map<String, AssistantArgSpec> get args => const {
    'plate': AssistantArgSpec(AssistantArgType.string),
    'customer': AssistantArgSpec(AssistantArgType.string),
    'services': AssistantArgSpec(AssistantArgType.list),
  };

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    if (!canOpen(AppContentRoutes.carWashCreate))
      return routeDenied(AppContentRoutes.carWashCreate, 'غسيل جديد');
    final p = AssistantPrefill(
      tool: name,
      turnId: ctx.turnId,
      values: {
        'plate': _ExecTool.s(args['plate']),
        'customer': _ExecTool.s(args['customer']),
        'services': [
          for (final e in (args['services'] as List?) ?? const []) '$e',
        ],
      },
    );
    return prepared(
      p,
      route: AppContentRoutes.carWashCreate,
      entityType: 'service_order',
      ctx: ctx,
      fieldRows: _ExecTool.fields(
        p,
        const ['plate', 'customer', 'services'],
        required: const {'plate'},
      ),
    );
  }
}

class PrepareCustomerTool extends _ExecTool {
  const PrepareCustomerTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'prepare_customer';

  @override
  List<String> get requiredPermissions => const [
    PermissionKeys.customersManage,
  ];

  @override
  Map<String, AssistantArgSpec> get args => const {
    'name': AssistantArgSpec(AssistantArgType.string, required: true),
    'phone': AssistantArgSpec(AssistantArgType.string),
  };

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    final phone = _ExecTool.s(
      args['phone'],
    )?.replaceAll(RegExp(r'[^\d+٠-٩]'), '');
    final p = AssistantPrefill(
      tool: name,
      turnId: ctx.turnId,
      values: {
        'name': _ExecTool.s(args['name']),
        'phone': phone == null || phone.length < 6 ? null : phone,
      },
    );
    if (p.str('name') == null)
      return AssistantToolResult.failure(name, 'bad_args:name');
    return prepared(
      p,
      route: AppContentRoutes.customersAdd,
      entityType: 'customer',
      ctx: ctx,
      fieldRows: _ExecTool.fields(
        p,
        const ['name', 'phone'],
        required: const {'phone'},
      ),
    );
  }
}

class PrepareProductTool extends _ExecTool {
  const PrepareProductTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'prepare_product';

  @override
  List<String> get requiredPermissions => const [
    PermissionKeys.inventoryProductsManage,
  ];

  @override
  Map<String, AssistantArgSpec> get args => const {
    'name': AssistantArgSpec(AssistantArgType.string, required: true),
    'kind': AssistantArgSpec(
      AssistantArgType.string,
      allowed: {'oil', 'hydraulic', 'filter', 'general'},
    ),
    'brand': AssistantArgSpec(AssistantArgType.string),
    'sell_price': AssistantArgSpec(AssistantArgType.integer),
    'qty': AssistantArgSpec(AssistantArgType.number),
  };

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    final price = _ExecTool.n(args['sell_price']);
    final qty = _ExecTool.n(args['qty']);
    final p = AssistantPrefill(
      tool: name,
      turnId: ctx.turnId,
      values: {
        'name': _ExecTool.s(args['name']),
        'kind': _ExecTool.s(args['kind']),
        'brand': _ExecTool.s(args['brand']),
        if (price != null && price > 0) 'sell_price': price.toInt(),
        if (qty != null && qty > 0) 'qty': qty,
      },
    );
    if (p.str('name') == null)
      return AssistantToolResult.failure(name, 'bad_args:name');
    // اسم موجود بالمخزون: لا صنف مكرر، يرجع للنموذج ليقترح تعديل الموجود.
    final existing = AssistantNameMatch.match(
      p.str('name')!,
      await data.stockItems(),
    );
    if (existing.grade == AssistantMatchGrade.matched) {
      return AssistantToolResult.success(name, [
        {
          'prepared': false,
          'exists': true,
          'product_id': existing.productId,
          'name': existing.candidates.first.$2,
        },
      ]);
    }
    return prepared(
      p,
      route: AppContentRoutes.addProduct,
      entityType: 'product',
      ctx: ctx,
      fieldRows: _ExecTool.fields(
        p,
        const ['name', 'brand', 'sell_price', 'qty'],
        required: const {'sell_price'},
      ),
    );
  }
}

class PrepareExpenseTool extends _ExecTool {
  const PrepareExpenseTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'prepare_expense';

  @override
  List<String> get requiredPermissions => const [PermissionKeys.cashManual];

  @override
  Map<String, AssistantArgSpec> get args => const {
    'amount': AssistantArgSpec(AssistantArgType.integer, required: true),
    'category': AssistantArgSpec(AssistantArgType.string),
    'note': AssistantArgSpec(AssistantArgType.string),
  };

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    if (!canOpen(AppContentRoutes.expenses))
      return routeDenied(AppContentRoutes.expenses, 'المصاريف');
    final amount = _ExecTool.n(args['amount']);
    if (amount == null || amount <= 0 || amount > 1e10)
      return AssistantToolResult.failure(name, 'bad_args:amount');
    final p = AssistantPrefill(
      tool: name,
      turnId: ctx.turnId,
      values: {
        'amount': amount.toInt(),
        'category': _ExecTool.s(args['category']),
        'note': _ExecTool.s(args['note']),
      },
    );
    return prepared(
      p,
      route: AppContentRoutes.expenses,
      entityType: 'expense',
      ctx: ctx,
      fieldRows: _ExecTool.fields(
        p,
        const ['amount', 'category', 'note'],
        required: const {'category'},
      ),
    );
  }
}

// ------------------------------------------------------------------ بطاقات التأكيد

class ProposePriceChangeTool extends _ExecTool {
  const ProposePriceChangeTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'propose_price_change';

  @override
  List<String> get requiredPermissions => const [
    PermissionKeys.inventoryProductsManage,
  ];

  @override
  Map<String, AssistantArgSpec> get args => const {
    'product_id': AssistantArgSpec(AssistantArgType.string, required: true),
    'new_sell_price': AssistantArgSpec(
      AssistantArgType.integer,
      required: true,
    ),
  };

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    final pid = _ExecTool.id(args['product_id']);
    final price = _ExecTool.n(args['new_sell_price']);
    if (pid == null)
      return AssistantToolResult.failure(name, 'bad_args:product_id');
    if (price == null || price <= 0 || price > 1e9)
      return AssistantToolResult.failure(name, 'bad_args:new_sell_price');
    final d = await data.productDetail(pid);
    if (d == null) return AssistantToolResult.failure(name, 'not_found');
    final before = (d['sell_price_fils'] as num?)?.toInt() ?? 0;
    final after = (price * 1000).round();
    if (before == after) {
      return AssistantToolResult.success(name, [
        {'product': d['name'], 'unchanged': true},
      ]);
    }
    final buy = (d['buy_price_fils'] as num?)?.toInt() ?? 0;
    // المالي لمن يملكه فقط: البيع تحت سعر الشراء تحذير لا منع.
    final belowCost =
        ctx.has(PermissionKeys.ownerKpiFinancial) && buy > 0 && after < buy;
    final actionId = AssistantActions.register((_) async {
      final err = await port.applyPriceChange(
        productId: pid,
        newSellFils: after,
      );
      if (err != null) return err;
      await AssistantPrefill.recordSaved(
        AssistantPrefill(
          tool: name,
          values: {'product_id': pid},
          turnId: ctx.turnId,
        ),
        entityType: 'product',
        entityId: '$pid',
        username: ctx.userName,
      );
      return null;
    });
    final row = {
      'product': d['name'],
      'before_fils': before,
      'after_fils': after,
      'awaiting_confirm': true,
    };
    return AssistantToolResult.success(
      name,
      [row],
      extra: {
        'action_id': actionId,
        ...row,
        'below_cost': ?(belowCost ? true : null),
      },
    );
  }
}

class ProposeStockAdjustTool extends _ExecTool {
  const ProposeStockAdjustTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'propose_stock_adjust';

  @override
  List<String> get requiredPermissions => const [
    PermissionKeys.inventoryVoucherIn,
    PermissionKeys.inventoryVoucherOut,
  ];

  @override
  Map<String, AssistantArgSpec> get args => const {
    'product_id': AssistantArgSpec(AssistantArgType.string, required: true),
    'delta': AssistantArgSpec(AssistantArgType.number, required: true),
    'reason': AssistantArgSpec(AssistantArgType.string, required: true),
  };

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    final pid = _ExecTool.id(args['product_id']);
    final delta = _ExecTool.n(args['delta'])?.toDouble();
    final reason = _ExecTool.s(args['reason']);
    if (pid == null)
      return AssistantToolResult.failure(name, 'bad_args:product_id');
    if (delta == null || delta == 0 || delta.abs() > 100000)
      return AssistantToolResult.failure(name, 'bad_args:delta');
    if (reason == null)
      return AssistantToolResult.failure(name, 'bad_args:reason');
    // الاتجاه يحدد الصلاحية: إضافة تحتاج إذن الإضافة، والنقص إذن الصرف.
    final need = delta > 0
        ? PermissionKeys.inventoryVoucherIn
        : PermissionKeys.inventoryVoucherOut;
    if (!ctx.has(need)) {
      return AssistantToolResult.failure(
        name,
        'forbidden',
        needs: need,
        needsLabel: AssistantToolGuard.labelFor(need),
      );
    }
    final d = await data.productDetail(pid);
    if (d == null) return AssistantToolResult.failure(name, 'not_found');
    final before = (d['qty'] as num?)?.toDouble() ?? 0;
    final buyIqd = ((d['buy_price_fils'] as num?)?.toDouble() ?? 0) / 1000;
    final actionId = AssistantActions.register((_) async {
      final err = await port.applyStockMoves(
        moves: [(productId: pid, delta: delta, unitPriceIqd: buyIqd)],
        reason: reason,
        sourceType: 'assistant',
      );
      if (err != null) return err;
      await AssistantPrefill.recordSaved(
        AssistantPrefill(
          tool: name,
          values: {'product_id': pid, 'delta': delta},
          turnId: ctx.turnId,
        ),
        entityType: 'stock_voucher',
        entityId: '$pid',
        username: ctx.userName,
      );
      return null;
    });
    final row = {
      'product': d['name'],
      'before_qty': before,
      'after_qty': before + delta,
      'unit': d['unit'],
      'reason': reason,
      'awaiting_confirm': true,
    };
    return AssistantToolResult.success(
      name,
      [row],
      extra: {'action_id': actionId, ...row},
    );
  }
}

/// المشترك بين فاتورة المورّد والجرد: مطابقة كل سطر ثم جدول مراجعة.
abstract class _ReviewTool extends _ExecTool {
  const _ReviewTool(super.data, super.port, super.canOpen);

  String get mode;

  Future<AssistantToolResult> review(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    final raw = (args['items'] as List?) ?? const [];
    if (raw.isEmpty || raw.length > 40)
      return AssistantToolResult.failure(name, 'bad_args:items');
    final stock = await data.stockItems();
    final lines = <AssistantReviewLine>[];
    for (final it in raw) {
      if (it is! Map) continue;
      final readName = _ExecTool.s(it['name']);
      final qty = _ExecTool.n(it['qty'])?.toDouble();
      if (readName == null || qty == null || qty < 0 || qty > 100000) continue;
      final price = _ExecTool.n(it['unit_price']);
      final m = AssistantNameMatch.match(readName, stock);
      final line = AssistantReviewLine(
        readName: readName,
        qty: qty,
        unitPriceFils: price == null || price <= 0
            ? null
            : (price * 1000).round(),
        match: m,
      );
      if (line.productId != null) {
        final item = stock.firstWhere((x) => x['id'] == line.productId);
        line
          ..productName = '${item['name']}'
          ..currentQty = (item['qty'] as num?)?.toDouble();
      }
      lines.add(line);
    }
    if (lines.isEmpty)
      return AssistantToolResult.failure(name, 'bad_args:items');
    final draft = AssistantReviewDraft(
      mode: mode,
      lines: lines,
      supplier: _ExecTool.s(args['supplier']),
      image: ctx.image,
      turnId: ctx.turnId,
    );
    final actionId = AssistantActions.register((_) async {
      final committed = await port.openReview(draft);
      if (!committed) return AssistantActions.reopen;
      await AssistantPrefill.recordSaved(
        AssistantPrefill(
          tool: name,
          values: {'lines': lines.where((l) => !l.removed).length},
          turnId: ctx.turnId,
        ),
        entityType: 'stock_voucher',
        username: ctx.userName,
      );
      return null;
    }, repeatable: true);
    int count(AssistantMatchGrade g) =>
        lines.where((l) => l.match.grade == g).length;
    final summary = {
      'lines': lines.length,
      'matched': count(AssistantMatchGrade.matched),
      'likely': count(AssistantMatchGrade.likely),
      'new': count(AssistantMatchGrade.none),
      'supplier': ?draft.supplier,
      'awaiting_review': true,
    };
    return AssistantToolResult.success(
      name,
      [summary],
      extra: {'action_id': actionId, 'mode': mode, ...summary},
    );
  }
}

class ProposeSupplierIntakeTool extends _ReviewTool {
  const ProposeSupplierIntakeTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'propose_supplier_intake';

  @override
  String get mode => 'intake';

  @override
  List<String> get requiredPermissions => const [
    PermissionKeys.inventoryVoucherIn,
  ];

  @override
  Map<String, AssistantArgSpec> get args => const {
    'supplier': AssistantArgSpec(AssistantArgType.string),
    'items': AssistantArgSpec(AssistantArgType.list, required: true),
  };

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) => review(args, ctx);
}

/// الجرد بالصوت (ق72، م4-14): الجمل المقروءة تصير قائمة مراجعة، والفرق عن
/// المخزون الحالي يُسجَّل بسندات بعد التأكيد فقط.
class ProposeStockCountTool extends _ReviewTool {
  const ProposeStockCountTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'propose_stock_count';

  @override
  String get mode => 'count';

  @override
  List<String> get requiredPermissions => const [
    PermissionKeys.inventoryVoucherIn,
    PermissionKeys.inventoryVoucherOut,
  ];

  @override
  Map<String, AssistantArgSpec> get args => const {
    'items': AssistantArgSpec(AssistantArgType.list, required: true),
  };

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    // الجرد يضيف وينقص، فيحتاج الإذنين معاً.
    for (final k in const [
      PermissionKeys.inventoryVoucherIn,
      PermissionKeys.inventoryVoucherOut,
    ]) {
      if (!ctx.has(k))
        return AssistantToolResult.failure(
          name,
          'forbidden',
          needs: k,
          needsLabel: AssistantToolGuard.labelFor(k),
        );
    }
    return review(args, ctx);
  }
}

// ------------------------------------------------------------------ الطباعة والتذكير

class OpenPrintPreviewTool extends _ExecTool {
  const OpenPrintPreviewTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'open_print_preview';

  @override
  List<String> get requiredPermissions => const [PermissionKeys.printingAccess];

  @override
  Map<String, AssistantArgSpec> get args => const {
    'kind': AssistantArgSpec(
      AssistantArgType.string,
      required: true,
      allowed: {'receipt', 'report', 'label'},
    ),
    'ref': AssistantArgSpec(AssistantArgType.string),
  };

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    final kind = '${args['kind']}';
    // فتح المعاينة ليس كتابة: الطباعة نفسها بضغطة المستخدم من المعاينة.
    final err = await port.openPrintPreview(
      kind: kind,
      ref: _ExecTool.s(args['ref']),
    );
    if (err != null) return AssistantToolResult.failure(name, err);
    return AssistantToolResult.success(name, [
      {'opened': kind, 'printed': false},
    ]);
  }
}

class ReminderSetTool extends _ExecTool {
  const ReminderSetTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'reminder_set';

  @override
  List<String> get requiredPermissions => const [];

  @override
  Map<String, AssistantArgSpec> get args => const {
    'text': AssistantArgSpec(AssistantArgType.string, required: true),
    'when': AssistantArgSpec(AssistantArgType.string, required: true),
  };

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    final text = _ExecTool.s(args['text']);
    if (text == null || text.length > 200)
      return AssistantToolResult.failure(name, 'bad_args:text');
    final when = AssistantReminderWhen.parse('${args['when']}', ctx.clock);
    if (when == null) return AssistantToolResult.failure(name, 'bad_args:when');
    final actionId = AssistantActions.register(
      (_) => port.setReminder(text: text, when: when),
    );
    final row = {
      'text': text,
      'when': when.toIso8601String(),
      'awaiting_confirm': true,
    };
    return AssistantToolResult.success(
      name,
      [row],
      extra: {'action_id': actionId, ...row},
    );
  }
}

// ------------------------------------------------------------------ 5.ث-12 المرحلة 1 (ع4)

/// إيقاف صنف: يختفي من البيع والقوائم ويبقى بسجلاته، ويُرجَع من شاشة المخزون.
class ProposeProductDeactivateTool extends _ExecTool {
  const ProposeProductDeactivateTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'propose_product_deactivate';

  @override
  List<String> get requiredPermissions => const [
    PermissionKeys.inventoryProductsManage,
  ];

  @override
  Map<String, AssistantArgSpec> get args => const {
    'product_id': AssistantArgSpec(AssistantArgType.string, required: true),
  };

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    final pid = _ExecTool.id(args['product_id']);
    if (pid == null)
      return AssistantToolResult.failure(name, 'bad_args:product_id');
    final d = await data.productDetail(pid);
    if (d == null) return AssistantToolResult.failure(name, 'not_found');
    final qty = (d['qty'] as num?)?.toDouble() ?? 0;
    final actionId = AssistantActions.register((_) async {
      final err = await port.deactivateProduct(pid);
      if (err != null) return err;
      await AssistantPrefill.recordSaved(
        AssistantPrefill(
          tool: name,
          values: {'product_id': pid},
          turnId: ctx.turnId,
        ),
        entityType: 'product',
        entityId: '$pid',
        username: ctx.userName,
      );
      return null;
    });
    final row = {
      'product': d['name'],
      'qty': qty,
      'unit': d['unit'],
      'awaiting_confirm': true,
    };
    return AssistantToolResult.success(
      name,
      [row],
      extra: {'action_id': actionId, ...row},
    );
  }
}

/// نقل كمية بين مخزنين بسند تحويل. بلا «من» = المخزن الرئيسي.
class ProposeStockTransferTool extends _ExecTool {
  const ProposeStockTransferTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'propose_stock_transfer';

  @override
  List<String> get requiredPermissions => const [
    PermissionKeys.inventoryVoucherTransfer,
  ];

  @override
  Map<String, AssistantArgSpec> get args => const {
    'product_id': AssistantArgSpec(AssistantArgType.string, required: true),
    'qty': AssistantArgSpec(AssistantArgType.number, required: true),
    'to_warehouse': AssistantArgSpec(AssistantArgType.string, required: true),
    'from_warehouse': AssistantArgSpec(AssistantArgType.string),
  };

  static String _norm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    final pid = _ExecTool.id(args['product_id']);
    final qty = _ExecTool.n(args['qty'])?.toDouble();
    final toName = _ExecTool.s(args['to_warehouse']);
    if (pid == null)
      return AssistantToolResult.failure(name, 'bad_args:product_id');
    if (qty == null || qty <= 0 || qty > 100000)
      return AssistantToolResult.failure(name, 'bad_args:qty');
    if (toName == null)
      return AssistantToolResult.failure(name, 'bad_args:to_warehouse');
    final wh = await port.listWarehouses();
    final names = [for (final w in wh) w.name];
    if (wh.length < 2) {
      return AssistantToolResult.success(name, [
        {'single_warehouse': true, 'warehouses': names},
      ]);
    }
    ({int id, String name})? find(String? q) {
      if (q == null) return null;
      final n = _norm(q);
      final exact = wh.where((w) => _norm(w.name) == n).firstOrNull;
      if (exact != null) return exact;
      final near = wh
          .where((w) => _norm(w.name).contains(n) || n.contains(_norm(w.name)))
          .toList();
      return near.length == 1 ? near.first : null;
    }

    final to = find(toName);
    final fromName = _ExecTool.s(args['from_warehouse']);
    final from = fromName == null ? wh.first : find(fromName);
    // ع7: سؤال واحد. إن لم يُعرف المخزن نرجع القائمة ليسأل المساعد عنه وحده.
    if (to == null || from == null) {
      return AssistantToolResult.success(name, [
        {'ask_warehouse': to == null ? 'to' : 'from', 'warehouses': names},
      ]);
    }
    if (to.id == from.id)
      return AssistantToolResult.failure(name, 'bad_args:same_warehouse');
    final d = await data.productDetail(pid);
    if (d == null) return AssistantToolResult.failure(name, 'not_found');
    final perWh = (d['warehouses'] as List?) ?? const [];
    double? qtyIn(String whName) {
      for (final w in perWh) {
        if (w is Map && _norm('${w['warehouse']}') == _norm(whName))
          return (w['qty'] as num?)?.toDouble();
      }
      return null;
    }

    final fromQty =
        qtyIn(from.name) ??
        (from.id == wh.first.id ? (d['qty'] as num?)?.toDouble() : null);
    final toQty = qtyIn(to.name) ?? 0;
    final buyIqd = ((d['buy_price_fils'] as num?)?.toDouble() ?? 0) / 1000;
    final actionId = AssistantActions.register((_) async {
      final err = await port.transferStock(
        productId: pid,
        qty: qty,
        fromWarehouseId: from.id,
        toWarehouseId: to.id,
        unitPriceIqd: buyIqd,
      );
      if (err != null) return err;
      await AssistantPrefill.recordSaved(
        AssistantPrefill(
          tool: name,
          values: {'product_id': pid, 'qty': qty},
          turnId: ctx.turnId,
        ),
        entityType: 'stock_voucher',
        entityId: '$pid',
        username: ctx.userName,
      );
      return null;
    });
    final row = {
      'product': d['name'],
      'qty': qty,
      'unit': d['unit'],
      'from': from.name,
      'to': to.name,
      'from_before': ?fromQty,
      'to_before': toQty,
      'short': ?(fromQty != null && fromQty < qty ? true : null),
      'awaiting_confirm': true,
    };
    return AssistantToolResult.success(
      name,
      [row],
      extra: {'action_id': actionId, ...row},
    );
  }
}

/// تسديد دين زبون: بالاسم، وإن تشابه أكثر من زبون يرجع الأسماء ليسأل عنها وحدها.
class ProposeDebtPaymentTool extends _ExecTool {
  const ProposeDebtPaymentTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'propose_debt_payment';

  @override
  List<String> get requiredPermissions => const [PermissionKeys.debtsPanel];

  @override
  Map<String, AssistantArgSpec> get args => const {
    'customer': AssistantArgSpec(AssistantArgType.string, required: true),
    'amount': AssistantArgSpec(AssistantArgType.integer),
    'customer_id': AssistantArgSpec(AssistantArgType.string),
  };

  static String _norm(String s) => s
      .trim()
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'\s+'), ' ');

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    final q = _ExecTool.s(args['customer']);
    if (q == null)
      return AssistantToolResult.failure(name, 'bad_args:customer');
    final amount = _ExecTool.n(args['amount']);
    if (amount != null && (amount <= 0 || amount > 1e10))
      return AssistantToolResult.failure(name, 'bad_args:amount');
    final wantId = _ExecTool.id(args['customer_id']);
    // نفس قائمة شاشة الديون، حتى لا يختلف «عليه دين» بين المساعد والشاشة.
    final debtors = [
      for (final d in await data.debtors())
        if (((d['amount_fils'] as num?) ?? 0) > 0) d,
    ];
    final nq = _norm(q);
    final exact = [
      for (final d in debtors)
        if (_norm('${d['customer']}') == nq) d,
    ];
    final near = exact.isNotEmpty
        ? exact
        : [
            for (final d in debtors)
              if (_norm('${d['customer']}').contains(nq) ||
                  nq.contains(_norm('${d['customer']}')))
                d,
          ];
    final pick = wantId != null
        ? debtors.where((d) => d['customer_id'] == wantId).firstOrNull
        : (near.length == 1 ? near.first : null);
    if (pick == null) {
      if (near.isEmpty) {
        return AssistantToolResult.success(name, [
          {'no_debt': true, 'customer': q},
        ]);
      }
      // ع7: سؤال واحد «أي واحد منهم؟».
      return AssistantToolResult.success(name, [
        {
          'ask_customer': true,
          'choices': [
            for (final d in near)
              {'customer_id': ?d['customer_id'], 'name': d['customer']},
          ],
        },
      ]);
    }
    final cname = '${pick['customer']}';
    final open = (pick['amount_fils'] as num?)?.toInt() ?? 0;
    final cidNum = pick['customer_id'] as num?;
    if (cidNum == null || cidNum <= 0) {
      // الدين مسجّل بالاسم بلا بطاقة زبون: شاشة الديون نفسها تطلب ربطه أولاً.
      return AssistantToolResult.success(name, [
        {'not_linked': true, 'customer': cname, 'open_debt_fils': open},
      ]);
    }
    final cid = cidNum.toInt();
    if (amount == null) {
      // ع7: المبلغ هو السؤال الوحيد الباقي.
      return AssistantToolResult.success(name, [
        {'ask_amount': true, 'customer': cname, 'open_debt_fils': open},
      ]);
    }
    final want = (amount * 1000).round();
    final pay = want > open ? open : want;
    final actionId = AssistantActions.register((_) async {
      final out = await port.recordDebtPayment(
        customerId: cid,
        customerName: cname,
        amountFils: pay,
        userName: ctx.userName ?? '',
      );
      if (out.error != null) return out.error;
      await AssistantPrefill.recordSaved(
        AssistantPrefill(
          tool: name,
          values: {'customer_id': cid, 'amount_fils': pay},
          turnId: ctx.turnId,
        ),
        entityType: 'debt_payment',
        entityId: '$cid',
        username: ctx.userName,
      );
      return null;
    });
    final row = {
      'customer': cname,
      'debt_before_fils': open,
      'pay_fils': pay,
      'debt_after_fils': open - pay,
      'capped': ?(want > open ? true : null),
      'awaiting_confirm': true,
    };
    return AssistantToolResult.success(
      name,
      [row],
      extra: {'action_id': actionId, ...row},
    );
  }
}
