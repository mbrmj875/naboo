import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../../verticals/oil_change/widgets/oil_change_owner_pin_confirm_dialog.dart';

/// إلغاء دفعة خاطئة (عميل أو مورد) — المرحلة 5، الشريحة 3.
///
/// يطلب سبباً مكتوباً ثم رمز المالك دائماً. يُعيد السبب عند الموافقة،
/// أو null إن تراجع المستخدم أو أخطأ الرمز.
Future<String?> confirmVoidPayment(
  BuildContext context, {
  required String title,
  required String amountLabel,
  required String effect,
}) async {
  final reason = await showDialog<String>(
    context: context,
    builder: (_) => VoidPaymentReasonDialog(
      title: title,
      amountLabel: amountLabel,
      effect: effect,
    ),
  );
  if (reason == null || !context.mounted) return null;
  final ok = await confirmOwnerPinForSensitiveAction(
    context,
    title: 'رمز المالك',
    message: 'إلغاء دفعة $amountLabel يحتاج رمز المالك.',
    confirmLabel: 'إلغاء الدفعة',
    destructive: true,
  );
  return ok ? reason : null;
}

class VoidPaymentReasonDialog extends StatefulWidget {
  const VoidPaymentReasonDialog({
    super.key,
    required this.title,
    required this.amountLabel,
    required this.effect,
  });

  final String title;
  final String amountLabel;
  final String effect;

  @override
  State<VoidPaymentReasonDialog> createState() =>
      _VoidPaymentReasonDialogState();
}

class _VoidPaymentReasonDialogState extends State<VoidPaymentReasonDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _valid => _ctrl.text.trim().length >= 3;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.amountLabel,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(widget.effect, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('voidPaymentReason'),
              controller: _ctrl,
              maxLength: 200,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'سبب الإلغاء',
                hintText: 'مثال: سُجّلت مرتين بالخطأ',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تراجع'),
          ),
          FilledButton(
            key: const Key('voidPaymentConfirm'),
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            onPressed: _valid
                ? () => Navigator.pop(context, _ctrl.text.trim())
                : null,
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
  }
}
