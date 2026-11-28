import 'dart:convert';

import 'package:flutter/material.dart';

import '../../owner/services/business_audit_log_service.dart';
import '../../theme/design_tokens.dart';
import '../ui/assistant_view_models.dart' show isolateLtr;

/// قيم عبّأها المساعد في نموذج حقيقي (4.5، م4-2، م4-3).
///
/// النموذج يقرأ ما يعرفه منها ويترك الباقي للمستخدم. لا شيء يُحفظ من هنا:
/// الحفظ زر النموذج نفسه بمساره المعتاد، فتمر البطاقة بالمزامنة كأي بطاقة.
@immutable
class AssistantPrefill {
  const AssistantPrefill({required this.tool, required this.values, this.turnId});

  /// prepare_oil_card | prepare_car_wash | prepare_customer | prepare_product | prepare_expense | prepare_direct_sale
  final String tool;
  final Map<String, Object?> values;

  /// سؤال المساعد الذي أنتجها، لتسجيل الحفظ عليه.
  final String? turnId;

  String? str(String key) {
    final v = values[key];
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty ? null : s;
  }

  num? number(String key) {
    final v = values[key];
    if (v is num) return v;
    return v == null ? null : num.tryParse('$v'.replaceAll(',', '').trim());
  }

  List<String> list(String key) {
    final v = values[key];
    return v is List
        ? [
            for (final e in v)
              if ('$e'.trim().isNotEmpty) '$e'.trim(),
          ]
        : const [];
  }

  /// أسماء الحقول للعرض، بترتيب ثابت.
  static const labels = <String, String>{
    'plate': 'اللوحة',
    'customer': 'الزبون',
    'name': 'الاسم',
    'phone': 'الهاتف',
    'car': 'السيارة',
    'oil': 'الزيت',
    'liters': 'اللترات',
    'odometer': 'العدّاد',
    'extras': 'إضافات',
    'services': 'الخدمات',
    'brand': 'الماركة',
    'sell_price': 'سعر البيع',
    'qty': 'الكمية',
    'amount': 'المبلغ',
    'category': 'الفئة',
    'note': 'ملاحظة',
    'items': 'الأصناف',
    'payment': 'الدفع',
  };

  /// الحقول التي امتلأت فعلاً، كما تظهر في شريط النموذج.
  List<(String, String)> filled({Set<String>? only}) => [
    for (final e in labels.entries)
      if ((only == null || only.contains(e.key)) && _display(e.key) != null) (e.value, _display(e.key)!),
  ];

  String? _display(String key) {
    final l = list(key);
    if (l.isNotEmpty) return l.join('، ');
    return str(key);
  }

  /// يُستدعى بعد حفظ نموذج فتحه المساعد. يضبطه المساعد عند تشغيله.
  static void Function(AssistantPrefill p, {required String entityType, String? entityId})? onSaved;

  /// يسجّل الحفظ في سجل المالك (م4-5) ويرسل إشارة `s_action_saved`.
  /// المالك يرى الصف باسم الموظف، ولا يرى المحادثة (ق16).
  static Future<void> recordSaved(
    AssistantPrefill p, {
    required String entityType,
    String? entityId,
    String? username,
    int? userId,
  }) async {
    try {
      await BusinessAuditLogService.instance.record(
        eventType: 'assistant_action',
        entityType: entityType,
        entityId: entityId,
        userId: userId,
        username: username,
        newValueJson: jsonEncode({'tool': p.tool, 'turn_id': ?p.turnId}),
      );
    } catch (_) {
      // السجل لا يُفشل الحفظ نفسه.
    }
    onSaved?.call(p, entityType: entityType, entityId: entityId);
  }
}

/// شريط أعلى النموذج: «عبّأ المساعد هذه البطاقة. راجعها ثم احفظ» مع الحقول
/// التي ملأها بلون مميز، حتى يعرف المستخدم ما يراجعه (م4-3).
class AssistantPrefillBanner extends StatelessWidget {
  const AssistantPrefillBanner({super.key, required this.prefill, this.only, this.what = 'هذه البطاقة'});

  final AssistantPrefill prefill;

  /// الحقول التي يعرفها هذا النموذج فقط.
  final Set<String>? only;
  final String what;

  /// يضع الشريط فوق جسم الشاشة إن وُجدت تعبئة، وإلا يرجع الجسم كما هو.
  static Widget wrap(
    AssistantPrefill? prefill, {
    required Widget child,
    Set<String>? only,
    String what = 'هذه البطاقة',
  }) {
    if (prefill == null) return child;
    return Column(
      children: [
        AssistantPrefillBanner(prefill: prefill, only: only, what: what),
        Expanded(child: child),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final fields = prefill.filled(only: only);
    return Semantics(
      container: true,
      label: 'عبّأ المساعد $what. راجعها ثم احفظ',
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: cs.secondaryContainer.withValues(alpha: 0.55),
          border: BorderDirectional(
            start: BorderSide(color: cs.secondary, width: 4),
            bottom: BorderSide(color: cs.outlineVariant),
          ),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: cs.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'عبّأ المساعد $what. راجعها ثم احفظ.',
                    style: t.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            if (fields.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (label, value) in fields)
                    Container(
                      padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        border: Border.all(color: cs.secondary, width: 1.5),
                        borderRadius: AppShape.none,
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '$label: ',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                            TextSpan(
                              text: isolateLtr(value),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        style: t.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
