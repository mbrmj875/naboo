import 'dart:async';
import 'dart:convert';

import '../services/permission_service.dart';
import 'assistant_access.dart';
import 'assistant_money_refs.dart';
import 'assistant_tool.dart';
import 'assistant_tool_result.dart';

/// الحارس: كل نداء أداة يمر من هنا قبل وبعد التنفيذ (خطة المساعد 4.2، م1-4).
///
/// قبل: مستوى المساعد، الصلاحية، صحة المعطيات.
/// أثناء: مهلة 4 ثوانٍ، وأي استثناء يصبح `failed`.
/// بعد: حذف الحقول المالية من البيانات نفسها، قص 20 صفاً، المبالغ إلى علامات.
class AssistantToolGuard {
  const AssistantToolGuard({this.timeout = const Duration(seconds: 4), this.maxRows = 20});

  final Duration timeout;
  final int maxRows;

  /// أسماء الصلاحيات كما يفهمها صاحب المحل (ق49).
  static const permissionLabels = <String, String>{
    PermissionKeys.inventoryView: 'عرض المخزون',
    PermissionKeys.inventoryProductsManage: 'إدارة المنتجات',
    PermissionKeys.inventoryVoucherIn: 'سندات الإدخال',
    PermissionKeys.inventoryVoucherOut: 'سندات الإخراج',
    PermissionKeys.customersView: 'عرض الزبائن',
    PermissionKeys.customersManage: 'إدارة الزبائن',
    PermissionKeys.cashView: 'عرض الصندوق',
    PermissionKeys.cashManual: 'حركات الصندوق اليدوية',
    PermissionKeys.debtsPanel: 'الديون',
    PermissionKeys.reportsAccess: 'التقارير',
    PermissionKeys.printingAccess: 'الطباعة',
    PermissionKeys.usersView: 'عرض المستخدمين',
    PermissionKeys.shiftsAccess: 'الورديات',
    PermissionKeys.settingsApp: 'إعدادات التطبيق',
    PermissionKeys.ownerKpiFinancial: 'المؤشرات المالية',
    PermissionKeys.assistantFull: 'المساعد الكامل',
  };

  static String labelFor(String key) => permissionLabels[key] ?? key;

  Future<AssistantToolResult> run(AssistantTool tool, Map<String, Object?> args, AssistantToolContext ctx) async {
    // 1) مستوى المساعد (ق48).
    if (ctx.level == AssistantLevel.none || (ctx.level == AssistantLevel.guideOnly && !tool.guideLevel)) {
      return AssistantToolResult.failure(
        tool.name,
        'forbidden',
        needs: PermissionKeys.assistantFull,
        needsLabel: labelFor(PermissionKeys.assistantFull),
      );
    }

    // 2) الصلاحية.
    final perms = tool.requiredPermissions;
    if (perms.isNotEmpty && !perms.any(ctx.has)) {
      return AssistantToolResult.failure(tool.name, 'forbidden', needs: perms.first, needsLabel: labelFor(perms.first));
    }

    // 3) المعطيات.
    final argError = validateArgs(tool.args, args);
    if (argError != null) {
      return AssistantToolResult.failure(tool.name, 'bad_args:$argError');
    }

    // 4) التنفيذ بمهلة.
    AssistantToolResult raw;
    try {
      raw = await tool.run(args, ctx).timeout(timeout);
    } on TimeoutException {
      return AssistantToolResult.failure(tool.name, 'timeout');
    } catch (_) {
      return AssistantToolResult.failure(tool.name, 'failed');
    }
    if (!raw.ok) return raw;

    // 5) المالي يُحذف من البيانات نفسها، فلا يصل للنموذج ولا للبطاقة.
    final financial = ctx.has(PermissionKeys.ownerKpiFinancial);
    var rows = raw.rows;
    if (!financial && tool.financialFields.isNotEmpty) {
      rows = [
        for (final r in rows)
          {
            for (final e in r.entries)
              if (!tool.financialFields.contains(e.key)) e.key: e.value,
          },
      ];
    }
    var extra = raw.extra;
    if (!financial && tool.financialFields.isNotEmpty) {
      extra = {
        for (final e in extra.entries)
          if (!tool.financialFields.contains(e.key)) e.key: e.value,
      };
    }

    // 6) حد الصفوف مع العدد الكلي.
    final total = raw.total < rows.length ? rows.length : raw.total;
    final truncated = raw.truncated || rows.length > maxRows;
    if (rows.length > maxRows) rows = rows.sublist(0, maxRows);

    return raw.copyWith(rows: rows, total: total, truncated: truncated, extra: extra);
  }

  /// ما يُرسل للنموذج: النتيجة بعد تحويل المبالغ إلى علامات.
  static String encodeForModel(AssistantToolResult result, AssistantMoneyRefs refs) {
    return jsonEncode(refs.wrap(result.toJson()));
  }

  /// يعيد سبب الخطأ أو null. المعطيات الزائدة تُتجاهل.
  static String? validateArgs(Map<String, AssistantArgSpec> spec, Map<String, Object?> args) {
    for (final e in spec.entries) {
      final v = args[e.key];
      if (v == null) {
        if (e.value.required) return 'missing_${e.key}';
        continue;
      }
      final okType = switch (e.value.type) {
        AssistantArgType.string => v is String,
        AssistantArgType.integer => v is int || (v is num && v == v.roundToDouble()),
        AssistantArgType.number => v is num,
        AssistantArgType.boolean => v is bool,
        AssistantArgType.list => v is List,
        AssistantArgType.map => v is Map,
      };
      if (!okType) return 'type_${e.key}';
      final allowed = e.value.allowed;
      if (allowed != null && v is String && !allowed.contains(v)) {
        return 'value_${e.key}';
      }
    }
    return null;
  }
}
