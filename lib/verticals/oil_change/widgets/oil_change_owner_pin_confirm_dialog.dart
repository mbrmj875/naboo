import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/pin_input_constraints.dart';
import '../../../widgets/inputs/pin_four_boxes_field.dart';

/// يطلب رمز PIN للمالك (4 أرقام) قبل عملية حسّاسة (مثل إلغاء ربط واتساب).
Future<bool> confirmOwnerPinForWhatsappAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأكيد',
  bool destructive = false,
}) async {
  final auth = context.read<AuthProvider>();
  final owner = await auth.getLocalOwnerRow();
  if (owner == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر العثور على حساب المالك على هذا الجهاز'),
        ),
      );
    }
    return false;
  }

  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _OwnerPinConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
      ownerRow: owner,
    ),
  );
  return ok == true;
}

class _OwnerPinConfirmDialog extends StatefulWidget {
  const _OwnerPinConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.destructive,
    required this.ownerRow,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;
  final Map<String, dynamic> ownerRow;

  @override
  State<_OwnerPinConfirmDialog> createState() => _OwnerPinConfirmDialogState();
}

class _OwnerPinConfirmDialogState extends State<_OwnerPinConfirmDialog> {
  final _pin = TextEditingController();
  final _focus = FocusNode();
  bool _obscure = true;
  bool _verifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pin.addListener(_onPinChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _onPinChanged() {
    if (!mounted || _error == null || _pin.text.isEmpty) return;
    setState(() => _error = null);
  }

  @override
  void dispose() {
    _pin.removeListener(_onPinChanged);
    _pin.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pin.text.trim();
    if (!PinInputConstraints.isValid(pin)) {
      setState(() => _error = PinInputConstraints.invalidMessage);
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    final ok = await auth.verifyOwnerConfirmationCredential(
      ownerRow: widget.ownerRow,
      credential: pin,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _verifying = false;
        _error = 'رمز PIN غير صحيح';
        _pin.clear();
      });
      _focus.requestFocus();
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final danger = widget.destructive;
    final screen = MediaQuery.sizeOf(context);
    final maxW = screen.width.clamp(280.0, 400.0);

    // Dialog بدل AlertDialog: AlertDialog يستخدم IntrinsicWidth
    // و PinFourBoxesField يعتمد على LayoutBuilder — يتعارضان.
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxW,
          maxHeight: screen.height * 0.78,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.message,
                style: TextStyle(
                  height: 1.45,
                  color: cs.onSurface.withValues(alpha: 0.82),
                ),
              ),
              const SizedBox(height: 18),
              PinFourBoxesField(
                controller: _pin,
                focusNode: _focus,
                label: 'رمز PIN للمالك (4 أرقام)',
                obscureText: _obscure,
                onToggleObscure: () => setState(() => _obscure = !_obscure),
                enabled: !_verifying,
                onCompleted: (_) => unawaited(_submit()),
                onEditingComplete: () => unawaited(_submit()),
                autovalidateMode: AutovalidateMode.disabled,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(
                    color: cs.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.start,
                ),
              ],
              if (_verifying) ...[
                const SizedBox(height: 12),
                const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed:
                        _verifying ? null : () => Navigator.pop(context, false),
                    child: const Text('إلغاء'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed:
                        _verifying ? null : () => unawaited(_submit()),
                    style: FilledButton.styleFrom(
                      backgroundColor: danger ? cs.error : AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(widget.confirmLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
