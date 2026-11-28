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
import '../exec/assistant_settings_catalog.dart';

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
  PrepareDirectSaleTool(data, port, canOpen),
  ProposePriceChangeTool(data, port, canOpen),
  ProposeStockAdjustTool(data, port, canOpen),
  ProposeSupplierIntakeTool(data, port, canOpen),
  ProposeStockCountTool(data, port, canOpen),
  OpenPrintPreviewTool(data, port, canOpen),
  ReminderSetTool(data, port, canOpen),
  ProposeProductDeactivateTool(data, port, canOpen),
  ProposeStockTransferTool(data, port, canOpen),
  ProposeDebtPaymentTool(data, port, canOpen),
  ProposeProductEditTool(data, port, canOpen),
  ProposeProductReactivateTool(data, port, canOpen),
  UndoLastActionTool(data, port, canOpen),
  SettingsGetTool(data, port, canOpen),
  ProposeSettingChangeTool(data, port, canOpen),
  OpenEntityTool(data, port, canOpen),
];

/// أسماء أدوات التنفيذ، لفحص أن الممنوع غير موجود.
const assistantExecToolNames = {
  'prepare_oil_card',
  'prepare_car_wash',
  'prepare_customer',
  'prepare_product',
  'prepare_expense',
  'prepare_direct_sale',
  'propose_price_change',
  'propose_stock_adjust',
  'propose_supplier_intake',
  'propose_stock_count',
  'open_print_preview',
  'reminder_set',
  'propose_product_deactivate',
  'propose_stock_transfer',
  'propose_debt_payment',
  'propose_product_edit',
  'propose_product_reactivate',
  'undo_last_action',
  'settings_get',
  'propose_setting_change',
  'open_entity',
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

  /// ع7 (المسار الموحّد): سؤال واحد بأزرار. كل زر يرسل اسمه كجواب، فيعيد
  /// النموذج الاستدعاء بالاختيار. أكثر من ثمانية = سؤال بلا أزرار.
  AssistantToolResult askPick(
    String ask,
    List<String> labels, {
    Map<String, Object?> more = const {},
  }) {
    final row = {ask: true, 'choices': labels, ...more};
    return AssistantToolResult.success(
      name,
      [row],
      extra: {
        'ambiguous': true,
        'candidates': [
          for (final l in labels.take(8)) {'label': l},
        ],
        'candidates_total': labels.length,
      },
    );
  }

  /// أسماء الزبائن للأزرار: الاسم المكرر يُميَّز بآخر زيارة (أو بالرقم إن
  /// تشابهت)، فيصير لكل زر زبون واحد. كان «ابو علي» مرتين يظهر زراً واحداً.
  static List<String> customerLabels(
    List<Map<String, Object?>> hits, {
    String nameKey = 'name',
    String idKey = 'id',
  }) {
    final names = [for (final c in hits) '${c[nameKey]}'.trim()];
    String hint(Map<String, Object?> c) {
      final v = c['last_visit'];
      return v != null ? 'آخر زيارة $v' : 'زبون رقم ${c[idKey]}';
    }

    final out = [
      for (var i = 0; i < hits.length; i++)
        names.where((n) => n == names[i]).length > 1
            ? '${names[i]} · ${hint(hits[i])}'
            : names[i],
    ];
    // تشابه حتى بعد التمييز: الرقم يحسم.
    return [
      for (var i = 0; i < out.length; i++)
        out.where((l) => l == out[i]).length > 1
            ? '${names[i]} · زبون رقم ${hits[i][idKey]}'
            : out[i],
    ];
  }

  /// الاسم الأصلي من جواب الزر («ابو علي · آخر زيارة …» ← «ابو علي»).
  static String baseName(String q) => q.split(' · ').first.trim();

  /// الزبون الذي يطابق نص زر بعينه، أو null.
  static Map<String, Object?>? pickByLabel(
    String q,
    List<Map<String, Object?>> hits, {
    String nameKey = 'name',
    String idKey = 'id',
  }) {
    final labels = customerLabels(hits, nameKey: nameKey, idKey: idKey);
    final i = labels.indexOf(q.trim());
    return i < 0 ? null : hits[i];
  }

  /// ع7: الصنف بمعرّفه، أو باسمه من المخزون نفسه. يرجع المعرّف، أو نتيجة
  /// السؤال (أي واحد؟ / ما لقيته) لتُعاد كما هي.
  Future<(int?, AssistantToolResult?)> resolveProduct(
    Map<String, Object?> args, {
    List<Map<String, Object?>>? pool,
  }) async {
    final pid = id(args['product_id']);
    if (pid != null) return (pid, null);
    final q = s(args['product']);
    if (q == null) {
      return (null, AssistantToolResult.failure(name, 'bad_args:product'));
    }
    final items = pool ?? await data.stockItems();
    final m = AssistantNameMatch.match(q, items);
    if (m.productId != null) return (m.productId, null);
    if (m.candidates.length == 1) return (m.candidates.first.$1, null);
    if (m.candidates.isEmpty) {
      // الاسم المختصر («كاسترول»): كل كلماته داخل اسم الصنف.
      final qt = AssistantNameMatch.tokens(q);
      final hits = [
        for (final it in items)
          if (qt.isNotEmpty &&
              it['id'] is num &&
              AssistantNameMatch.tokens(
                '${it['name'] ?? ''} ${it['brand'] ?? ''}',
              ).containsAll(qt))
            it,
      ];
      if (hits.length == 1) return ((hits.single['id'] as num).toInt(), null);
      if (hits.isNotEmpty) {
        return (
          null,
          askPick('ask_product', [for (final h in hits) '${h['name']}']),
        );
      }
      return (
        null,
        AssistantToolResult.success(name, [
          {'not_found': true, 'product': q},
        ]),
      );
    }
    return (null, askPick('ask_product', [for (final c in m.candidates) c.$2]));
  }

  /// ع11: يلف العملية العكسية بتسجيلها في سجل المالك «عبر المساعد»، أياً
  /// كان مصدرها (زر «تراجع» أو «ارجع آخر عملية»).
  AssistantActionUndo logged(
    AssistantToolContext ctx,
    String entityType,
    Object entityId,
    AssistantActionUndo fn,
  ) => () async {
    final err = await fn();
    if (err == null) {
      await AssistantPrefill.recordSaved(
        AssistantPrefill(
          tool: 'undo:$name',
          values: const {},
          turnId: ctx.turnId,
        ),
        entityType: entityType,
        entityId: '$entityId',
        username: ctx.userName,
      );
    }
    return err;
  };

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

  static const _receiptTools = {'prepare_direct_sale', 'prepare_oil_card', 'prepare_car_wash'};

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
    if (_receiptTools.contains(name)) AssistantActions.pendingUnsaved = name;
    final actionId = AssistantActions.register((choice) async {
      final use = choice == null || withChoice == null
          ? p
          : withChoice(p, choice);
      final out = await port.openForm(use);
      if (!out.saved) return AssistantActions.reopen;
      if (AssistantActions.pendingUnsaved == name) AssistantActions.pendingUnsaved = null;
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

/// ح2: سلة البيع المباشر معبّأة: الأصناف من المخزون بكمياتها، والزبون،
/// ونقد أو آجل. السعر سعر الصنف المسجّل، والبيع بزر الشاشة فقط.
class PrepareDirectSaleTool extends _ExecTool {
  const PrepareDirectSaleTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'prepare_direct_sale';

  @override
  List<String> get requiredPermissions => const [];

  @override
  Map<String, AssistantArgSpec> get args => const {
    'items': AssistantArgSpec(AssistantArgType.list, required: true),
    'customer': AssistantArgSpec(AssistantArgType.string),
    'payment': AssistantArgSpec(AssistantArgType.string),
  };

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    if (!canOpen(AppContentRoutes.oilDirectSale))
      return routeDenied(AppContentRoutes.oilDirectSale, 'البيع المباشر');
    final raw = (args['items'] as List?) ?? const [];
    if (raw.isEmpty || raw.length > 20)
      return AssistantToolResult.failure(name, 'bad_args:items');
    final stock = await data.stockItems();
    final lines = <Map<String, Object?>>[];
    final labels = <String>[];
    final short = <Map<String, Object?>>[];
    for (final it in raw) {
      if (it is! Map) continue;
      final qty = _ExecTool.n(it['qty'])?.round() ?? 1;
      if (qty <= 0 || qty > 1000) continue;
      final (pid, ask) = await resolveProduct({
        'product_id': it['product_id'],
        'product': it['product'] ?? it['name'],
      }, pool: stock);
      if (ask != null) return ask;
      if (pid == null) continue;
      final item = stock.where((x) => x['id'] == pid).firstOrNull;
      final label = '${item?['name'] ?? pid}';
      lines.add({'product_id': pid, 'qty': qty});
      labels.add('$label ×$qty');
      final have = (item?['qty'] as num?)?.toDouble();
      if (have != null && have < qty) {
        short.add({'product': label, 'available': have, 'needed': qty});
      }
    }
    if (lines.isEmpty) return AssistantToolResult.failure(name, 'bad_args:items');
    // الزبون: يُربط إن طابق اسماً واحداً، وإلا يبقى الاسم كما قاله.
    var cname = _ExecTool.s(args['customer']);
    int? cid;
    if (cname != null) {
      final base = _ExecTool.baseName(cname);
      final hits = await data.customers(base, limit: 8);
      final exact = hits.where((c) => '${c['name']}'.trim() == base).toList();
      final one =
          _ExecTool.pickByLabel(cname, hits) ??
          (hits.length == 1 ? hits.single : (exact.length == 1 ? exact.single : null));
      if (one == null && hits.length > 1) {
        return askPick('ask_customer', _ExecTool.customerLabels(hits));
      }
      cid = _ExecTool.id(one?['id']);
      if (one != null) cname = '${one['name']}';
    }
    final pay = '${args['payment'] ?? ''}'.trim().toLowerCase();
    final credit = const {'credit', 'debt', 'آجل', 'اجل', 'دين', 'بالدين'}.contains(pay);
    final p = AssistantPrefill(
      tool: name,
      turnId: ctx.turnId,
      values: {
        'lines': lines,
        'items': labels,
        'customer': cname,
        'customer_id': cid,
        'credit': credit,
        'payment': credit ? 'آجل' : 'نقد',
      },
    );
    return prepared(
      p,
      route: AppContentRoutes.oilDirectSale,
      entityType: 'invoice',
      ctx: ctx,
      fieldRows: _ExecTool.fields(
        p,
        const ['items', 'customer', 'payment'],
        required: credit ? const {'customer'} : const {},
      ),
      more: {if (short.isNotEmpty) 'stock_short': short},
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
    final actionId = AssistantActions.register(
      label: 'تغيير سعر ${d['name']}',
      undo: logged(
        ctx,
        'product',
        pid,
        () => port.applyPriceChange(productId: pid, newSellFils: before),
      ),
      (_) async {
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
      },
    );
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
    final actionId = AssistantActions.register(
      label: 'تعديل كمية ${d['name']}',
      // ع11: سند معاكس، لا حذف للسند الأول.
      undo: logged(
        ctx,
        'stock_voucher',
        pid,
        () => port.applyStockMoves(
          moves: [(productId: pid, delta: -delta, unitPriceIqd: buyIqd)],
          reason: 'تراجع: $reason',
          sourceType: 'assistant',
        ),
      ),
      (_) async {
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
      },
    );
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
    final ref = _ExecTool.s(args['ref']);
    // وصل بلا رقم وهناك بيع أو بطاقة لم تُحفظ: لا نفتح وصلاً قديماً.
    final pending = AssistantActions.pendingUnsaved;
    if (kind == 'receipt' && ref == null && pending != null) {
      return AssistantToolResult.success(name, [
        {'unsaved_draft': pending, 'printed': false, 'opened': false},
      ]);
    }
    // فتح المعاينة ليس كتابة: الطباعة نفسها بضغطة المستخدم من المعاينة.
    final err = await port.openPrintPreview(kind: kind, ref: ref);
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
    final actionId = AssistantActions.register(
      label: 'إيقاف ${d['name']}',
      undo: logged(ctx, 'product', pid, () => port.activateProduct(pid)),
      (_) async {
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
      },
    );
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
      return askPick(
        'ask_warehouse',
        names,
        more: {'which': to == null ? 'to' : 'from'},
      );
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
    final actionId = AssistantActions.register(
      label: 'نقل ${d['name']}',
      // ع11: سند تحويل معاكس.
      undo: logged(
        ctx,
        'stock_voucher',
        pid,
        () => port.transferStock(
          productId: pid,
          qty: qty,
          fromWarehouseId: to.id,
          toWarehouseId: from.id,
          unitPriceIqd: buyIqd,
          note: 'تراجع',
        ),
      ),
      (_) async {
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
      },
    );
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
    // «نصها»، «ربعه»: النموذج يرى الدين علامة لا رقماً، فالكسر يُحسب هنا (قياس ذ3).
    'fraction': AssistantArgSpec(AssistantArgType.number),
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
    final fraction = _ExecTool.n(args['fraction']);
    if (fraction != null && (fraction <= 0 || fraction > 1))
      return AssistantToolResult.failure(name, 'bad_args:fraction');
    final wantId = _ExecTool.id(args['customer_id']);
    // نفس قائمة شاشة الديون، حتى لا يختلف «عليه دين» بين المساعد والشاشة.
    final debtors = [
      for (final d in await data.debtors())
        if (((d['amount_fils'] as num?) ?? 0) > 0) d,
    ];
    final nq = _norm(_ExecTool.baseName(q));
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
        : (_ExecTool.pickByLabel(q, near, nameKey: 'customer', idKey: 'customer_id') ??
              (near.length == 1 ? near.first : null));
    if (pick == null) {
      if (near.isEmpty) {
        return AssistantToolResult.success(name, [
          {'no_debt': true, 'customer': q},
        ]);
      }
      // ع7: سؤال واحد «أي واحد منهم؟» بأزرار الأسماء.
      return askPick(
        'ask_customer',
        _ExecTool.customerLabels(near, nameKey: 'customer', idKey: 'customer_id'),
        more: {
          'ids': [for (final d in near) d['customer_id']],
        },
      );
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
    if (amount == null && fraction == null) {
      // ع7: المبلغ هو السؤال الوحيد الباقي.
      return AssistantToolResult.success(name, [
        {'ask_amount': true, 'customer': cname, 'open_debt_fils': open},
      ]);
    }
    // الكسر يُقرَّب لأقرب دينار، والمبلغ الصريح يغلبه إن جاءا معاً.
    final want = amount != null
        ? (amount * 1000).round()
        : ((open * fraction!) / 1000).round() * 1000;
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

// ------------------------------------------------------------------ السيطرة الكاملة (5.ث-12 و)

/// س2: تعديل الصنف بحقول شاشة التعديل نفسها (الاسم، الباركود، سعر الشراء،
/// سعر البيع، أدنى سعر، حد التنبيه). الكمية لا تُعدَّل هنا: لها سند.
/// التخفيض على الصنف ليس هنا عمداً: حقلاه في الجدول لا يطبّقهما البيع اليوم،
/// فيأتي مع محرك العروض (س8).
class ProposeProductEditTool extends _ExecTool {
  const ProposeProductEditTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'propose_product_edit';

  @override
  List<String> get requiredPermissions => const [
    PermissionKeys.inventoryProductsManage,
  ];

  /// سعر الشراء القديم مالي: لا يراه من لا يملك المالي، حتى لو عدّله.
  @override
  Set<String> get financialFields => const {'buy_before_fils'};

  @override
  Map<String, AssistantArgSpec> get args => const {
    'product_id': AssistantArgSpec(AssistantArgType.string),
    'product': AssistantArgSpec(AssistantArgType.string),
    'name': AssistantArgSpec(AssistantArgType.string),
    'barcode': AssistantArgSpec(AssistantArgType.string),
    'buy_price': AssistantArgSpec(AssistantArgType.integer),
    'sell_price': AssistantArgSpec(AssistantArgType.integer),
    'min_sell_price': AssistantArgSpec(AssistantArgType.integer),
    'low_stock': AssistantArgSpec(AssistantArgType.number),
  };

  static int? _fils(Object? v) {
    final x = _ExecTool.n(v);
    if (x == null) return null;
    if (x < 0 || x > 1e9) return -1;
    return (x * 1000).round();
  }

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    final (pid, ask) = await resolveProduct(args);
    if (ask != null) return ask;
    final d = await data.productDetail(pid!);
    if (d == null) return AssistantToolResult.failure(name, 'not_found');

    final newName0 = _ExecTool.s(args['name']);
    final barcode0 = _ExecTool.s(
      args['barcode'],
    )?.replaceAll(RegExp(r'\s'), '');
    final buy0 = _fils(args['buy_price']);
    final sell0 = _fils(args['sell_price']);
    final minSell0 = _fils(args['min_sell_price']);
    final low0 = _ExecTool.n(args['low_stock'])?.toDouble();
    for (final (k, v) in [
      ('buy_price', buy0),
      ('sell_price', sell0),
      ('min_sell_price', minSell0),
    ]) {
      if (v == -1) return AssistantToolResult.failure(name, 'bad_args:$k');
    }
    if (sell0 == 0)
      return AssistantToolResult.failure(name, 'bad_args:sell_price');
    if (low0 != null && (low0 < 0 || low0 > 100000)) {
      return AssistantToolResult.failure(name, 'bad_args:low_stock');
    }

    int f(String k) => (d[k] as num?)?.toInt() ?? 0;
    final changes = <Map<String, Object?>>[];
    void add(String field, Object? before, Object? after) {
      if (after == null || '$after' == '$before') return;
      changes.add({'field': field, 'before': before, 'after': after});
    }

    add('name', d['name'], newName0);
    add('barcode', d['barcode'] ?? '', barcode0);
    add('sell_fils', f('sell_price_fils'), sell0);
    add('min_sell_fils', d['min_sell_price_fils'] ?? 0, minSell0);
    add('buy_fils', f('buy_price_fils'), buy0);
    add('low_stock', (d['threshold'] as num?)?.toDouble() ?? 0, low0);
    if (changes.isEmpty) {
      // ع7: ما ذُكر شيء يتغير؛ سؤال واحد عن الحقل.
      return AssistantToolResult.success(name, [
        {
          'ask_field': true,
          'product': d['name'],
          'fields': [
            'الاسم',
            'الباركود',
            'سعر البيع',
            'أدنى سعر',
            'سعر الشراء',
            'حد التنبيه',
          ],
        },
      ]);
    }
    final changed = {for (final c in changes) c['field']};
    final newName = changed.contains('name') ? newName0 : null;
    final barcode = changed.contains('barcode') ? barcode0 : null;
    final buy = changed.contains('buy_fils') ? buy0 : null;
    final sell = changed.contains('sell_fils') ? sell0 : null;
    final minSell = changed.contains('min_sell_fils') ? minSell0 : null;
    final low = changed.contains('low_stock') ? low0 : null;
    final effSell = sell ?? f('sell_price_fils');
    final effMin = minSell ?? (d['min_sell_price_fils'] as num?)?.toInt() ?? 0;
    if (effMin > effSell) {
      return AssistantToolResult.success(name, [
        {
          'min_above_sell': true,
          'product': d['name'],
          'sell_fils': effSell,
          'min_sell_fils': effMin,
        },
      ]);
    }
    if (barcode != null && barcode != '${d['barcode'] ?? ''}') {
      final owner = await data.productIdByBarcode(barcode);
      if (owner != null && owner != pid) {
        return AssistantToolResult.success(name, [
          {'barcode_taken': true, 'barcode': barcode},
        ]);
      }
    }
    final effBuy = buy ?? f('buy_price_fils');
    final belowCost =
        ctx.has(PermissionKeys.ownerKpiFinancial) &&
        effBuy > 0 &&
        effSell < effBuy;

    final oldName = '${d['name']}';
    final oldBarcode = '${d['barcode'] ?? ''}';
    final oldSell = f('sell_price_fils');
    final oldMin = (d['min_sell_price_fils'] as num?)?.toInt();
    final oldBuy = f('buy_price_fils');
    final oldLow = (d['threshold'] as num?)?.toDouble();
    final actionId = AssistantActions.register(
      label: 'تعديل $oldName',
      // ع11: يرجع الحقول التي تغيّرت لقيمها قبل التعديل، بنفس الدالة.
      undo: logged(
        ctx,
        'product',
        pid,
        () => port.editProduct(
          productId: pid,
          name: newName == null ? null : oldName,
          barcode: barcode == null ? null : oldBarcode,
          sellFils: sell == null ? null : oldSell,
          minSellFils: minSell == null ? null : oldMin,
          buyFils: buy == null ? null : oldBuy,
          lowStock: low == null ? null : oldLow,
        ),
      ),
      (_) async {
        final err = await port.editProduct(
          productId: pid,
          name: newName,
          barcode: barcode,
          buyFils: buy,
          sellFils: sell,
          minSellFils: minSell,
          lowStock: low,
        );
        if (err != null) return err;
        await AssistantPrefill.recordSaved(
          AssistantPrefill(
            tool: name,
            values: {
              'product_id': pid,
              'fields': [for (final c in changes) c['field']],
            },
            turnId: ctx.turnId,
          ),
          entityType: 'product',
          entityId: '$pid',
          username: ctx.userName,
        );
        return null;
      },
    );
    final row = {
      'product': d['name'],
      'changes': [
        for (final c in changes)
          if (c['field'] == 'buy_fils')
            {'field': 'buy_fils', 'after': c['after']}
          else
            c,
      ],
      'buy_before_fils': ?(buy == null ? null : oldBuy),
      'awaiting_confirm': true,
    };
    return AssistantToolResult.success(
      name,
      [row],
      extra: {
        'action_id': actionId,
        ...row,
        'unit': d['unit'],
        'below_cost': ?(belowCost ? true : null),
      },
    );
  }
}

/// س3: إرجاع صنف موقوف، بالاسم من قائمة الموقوفة نفسها.
class ProposeProductReactivateTool extends _ExecTool {
  const ProposeProductReactivateTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'propose_product_reactivate';

  @override
  List<String> get requiredPermissions => const [
    PermissionKeys.inventoryProductsManage,
  ];

  @override
  Map<String, AssistantArgSpec> get args => const {
    'product_id': AssistantArgSpec(AssistantArgType.string),
    'product': AssistantArgSpec(AssistantArgType.string),
  };

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    final pool = await port.inactiveProducts();
    if (pool.isEmpty) {
      return AssistantToolResult.success(name, [
        {'none_inactive': true},
      ]);
    }
    final (pid, ask) = await resolveProduct(args, pool: pool);
    if (ask != null) return ask;
    final p = pool.where((x) => x['id'] == pid).firstOrNull;
    if (p == null) {
      return AssistantToolResult.success(name, [
        {'not_inactive': true},
      ]);
    }
    final pname = '${p['name']}';
    final actionId = AssistantActions.register(
      label: 'إرجاع $pname',
      undo: logged(ctx, 'product', pid!, () => port.deactivateProduct(pid)),
      (_) async {
        final err = await port.activateProduct(pid);
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
      },
    );
    final row = {'product': pname, 'qty': p['qty'], 'awaiting_confirm': true};
    return AssistantToolResult.success(
      name,
      [row],
      extra: {'action_id': actionId, ...row},
    );
  }
}

/// ع11: «ارجع آخر عملية». يعرض ما سيُرجَع ببطاقة تأكيد، والإرجاع عملية
/// عكسية مسجّلة لا محو. يعمل على ما نُفّذ في هذه الجلسة فقط.
class UndoLastActionTool extends _ExecTool {
  const UndoLastActionTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'undo_last_action';

  @override
  List<String> get requiredPermissions => const [];

  @override
  Map<String, AssistantArgSpec> get args => const {};

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    final last = AssistantActions.lastUndoable();
    if (last == null) {
      return AssistantToolResult.success(name, [
        {'nothing_to_undo': true},
      ]);
    }
    final label = AssistantActions.of(last).label ?? 'آخر عملية';
    final actionId = AssistantActions.register((_) async {
      // العملية العكسية نفسها تُسجَّل في سجل المالك (logged).
      return AssistantActions.undo(last);
    });
    final row = {'undo': label, 'awaiting_confirm': true};
    return AssistantToolResult.success(
      name,
      [row],
      extra: {'action_id': actionId, ...row},
    );
  }
}

/// ك1: الإعدادات التي يقدر المساعد يقرؤها ويغيّرها، بقيمها الحالية.
/// ما يخص المالك وحده لا يظهر لغيره، كما في شاشة الإعدادات.
class SettingsGetTool extends _ExecTool {
  const SettingsGetTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'settings_get';

  // بلا صلاحية خاصة: شرط المالك داخل الفهرس نفسه، كما في شاشة الإعدادات.
  @override
  List<String> get requiredPermissions => const [];

  @override
  Map<String, AssistantArgSpec> get args => const {};

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    final rows = <Map<String, Object?>>[];
    for (final spec in AssistantSettingsCatalog.all) {
      if (spec.ownerOnly && !ctx.isOwner) continue;
      final v = await port.readSetting(spec.key);
      rows.add({
        'setting': spec.key,
        'name': spec.label,
        'value': v == null ? null : spec.display(v),
        if (spec.kind == AssistantSettingKind.choice)
          'choices': spec.choices.values.toList(),
      });
    }
    return AssistantToolResult.success(name, rows);
  }
}

/// ك1: بطاقة تغيير إعداد «قبل ← بعد». الحفظ بدالة شاشة الإعداد نفسها،
/// والتراجع يرجع القيمة السابقة.
class ProposeSettingChangeTool extends _ExecTool {
  const ProposeSettingChangeTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'propose_setting_change';

  // بلا صلاحية خاصة: شرط المالك داخل الفهرس نفسه، كما في شاشة الإعدادات.
  @override
  List<String> get requiredPermissions => const [];

  @override
  Map<String, AssistantArgSpec> get args => const {
    'setting': AssistantArgSpec(AssistantArgType.string, required: true),
    'value': AssistantArgSpec(AssistantArgType.string, required: true),
  };

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    final spec = AssistantSettingsCatalog.byKey(_ExecTool.s(args['setting']));
    if (spec == null) {
      return AssistantToolResult.failure(name, 'bad_args:setting');
    }
    if (spec.ownerOnly && !ctx.isOwner) {
      return AssistantToolResult.failure(
        name,
        'forbidden',
        needsLabel: 'صاحب المحل',
      );
    }
    final value = spec.parse(args['value']);
    if (value == null) {
      if (spec.kind == AssistantSettingKind.choice) {
        return askPick('ask_value', spec.choices.values.toList());
      }
      return AssistantToolResult.failure(name, 'bad_args:value');
    }
    final before = await port.readSetting(spec.key);
    if (before == null) return AssistantToolResult.failure(name, 'failed');
    if (before == value) {
      return AssistantToolResult.success(name, [
        {
          'setting': spec.label,
          'value': spec.display(value),
          'unchanged': true,
        },
      ]);
    }
    final actionId = AssistantActions.register(
      label: 'تغيير ${spec.label}',
      undo: logged(
        ctx,
        'setting',
        spec.key,
        () => port.writeSetting(spec.key, before),
      ),
      (_) async {
        final err = await port.writeSetting(spec.key, value);
        if (err != null) return err;
        await AssistantPrefill.recordSaved(
          AssistantPrefill(
            tool: name,
            values: {'setting': spec.key},
            turnId: ctx.turnId,
          ),
          entityType: 'setting',
          entityId: spec.key,
          username: ctx.userName,
        );
        return null;
      },
    );
    final row = {
      'setting': spec.label,
      'before': spec.display(before),
      'after': spec.display(value),
      'awaiting_confirm': true,
    };
    return AssistantToolResult.success(
      name,
      [row],
      extra: {'action_id': actionId, ...row},
    );
  }
}

/// ك2: يفتح شاشة شيء محدد باسمه أو معرّفه: حساب زبون، دينه، صنف، آخر بطاقة
/// غيار لسيارة. لا يكتب شيئاً. الشاشة نفسها تُفحص كما يفحصها التطبيق: من لا
/// يرى قائمتها لا يفتحها.
class OpenEntityTool extends _ExecTool {
  const OpenEntityTool(super.data, super.port, super.canOpen);

  @override
  String get name => 'open_entity';

  @override
  List<String> get requiredPermissions => const [];

  @override
  Map<String, AssistantArgSpec> get args => const {
    'kind': AssistantArgSpec(AssistantArgType.string, required: true),
    'id': AssistantArgSpec(AssistantArgType.string),
    'name': AssistantArgSpec(AssistantArgType.string),
  };

  static const _routes = {
    'customer': (AppContentRoutes.customers, 'العملاء'),
    'debt': (AppContentRoutes.debts, 'الديون'),
    'product': (AppContentRoutes.inventoryProducts, 'المخزون'),
    'oil_card': (AppContentRoutes.oilServicesLog, 'سجل غيارات الزيت'),
    // ك2-ب: شاشات شيء محدد كانت تُفتح من داخل شاشة أخرى فقط.
    'product_edit': (AppContentRoutes.productEdit, 'تعديل المنتج'),
    'oil_card_edit': (AppContentRoutes.oilCardEdit, 'تعديل البطاقة'),
    'supplier': (AppContentRoutes.supplierDetail, 'حساب المورد'),
    'installment': (AppContentRoutes.installments, 'الأقساط'),
    'invoice_return': (AppContentRoutes.invoiceReturn, 'مرتجع الفاتورة'),
  };

  @override
  Future<AssistantToolResult> run(
    Map<String, Object?> args,
    AssistantToolContext ctx,
  ) async {
    final kind = _ExecTool.s(args['kind']);
    final route = _routes[kind];
    if (kind == null || route == null) {
      return AssistantToolResult.failure(name, 'bad_args:kind');
    }
    if (!canOpen(route.$1)) return routeDenied(route.$1, route.$2);
    final q = _ExecTool.s(args['name']);
    var id = _ExecTool.id(args['id']);
    String? label = q;
    if (id == null) {
      if (q == null) return AssistantToolResult.failure(name, 'bad_args:name');
      switch (kind) {
        case 'product' || 'product_edit':
          final (pid, ask) = await resolveProduct({'product': q});
          if (ask != null) return ask;
          id = pid;
        case 'invoice_return':
          // الفاتورة تُحدَّد برقمها فقط، فلا يُرجَع على فاتورة خاطئة.
          return AssistantToolResult.failure(name, 'bad_args:id');
        case 'supplier' || 'installment':
          final hits = await port.findEntities(kind, q);
          if (hits.isEmpty) {
            return AssistantToolResult.success(name, [
              {'not_found': true, 'name': q},
            ]);
          }
          final exact = hits.where((h) => '${h['name']}'.trim() == q).toList();
          final pick = hits.length == 1
              ? hits.single
              : exact.length == 1
              ? exact.single
              : null;
          if (pick == null) {
            return askPick(kind == 'supplier' ? 'ask_supplier' : 'ask_plan', [
              for (final h in hits) '${h['name']}',
            ]);
          }
          id = _ExecTool.id(pick['id']);
          label = '${pick['name']}';
        case 'oil_card' || 'oil_card_edit':
          final cards = await data.oilCards(plate: q, limit: 1);
          if (cards.isEmpty) {
            return AssistantToolResult.success(name, [
              {'not_found': true, 'plate': q},
            ]);
          }
          id = _ExecTool.id(cards.first['id']);
          label = 'بطاقة ${cards.first['plate']} (${cards.first['date']})';
        default:
          final base = _ExecTool.baseName(q);
          final hits = await data.customers(base, limit: 8);
          if (kind == 'debt')
            hits.retainWhere((c) => ((c['open_debt_fils'] as num?) ?? 0) > 0);
          if (hits.isEmpty) {
            return AssistantToolResult.success(name, [
              {'not_found': true, 'customer': q},
            ]);
          }
          if (hits.length > 1) {
            final exact = hits
                .where((c) => '${c['name']}'.trim() == base)
                .toList();
            final chosen = _ExecTool.pickByLabel(q, hits) ??
                (exact.length == 1 ? exact.single : null);
            if (chosen == null) {
              return askPick('ask_customer', _ExecTool.customerLabels(hits));
            }
            hits
              ..clear()
              ..add(chosen);
          }
          id = _ExecTool.id(hits.single['id']);
          label = '${hits.single['name']}';
      }
    }
    if (id == null) return AssistantToolResult.failure(name, 'not_found');
    final err = await port.openEntity(kind, id);
    if (err != null) return AssistantToolResult.failure(name, 'failed:$err');
    return AssistantToolResult.success(name, [
      {'opened': true, 'kind': kind, 'name': ?label},
    ]);
  }
}
