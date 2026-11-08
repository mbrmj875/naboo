import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../owner/services/business_audit_log_service.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth/pin_attempt_guard.dart';
import '../../services/database_helper.dart';
import '../../services/permission_service.dart';
import '../../services/returns/return_approval.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../utils/pin_input_constraints.dart';
import '../inputs/pin_four_boxes_field.dart';
import '../secure_screen.dart';

/// يطلب موافقة المالك أو موظف كامل الصلاحية: يختار اسمه ويكتب رمزه بنفسه.
///
/// يعيد موافقة لمرة واحدة مربوطة بالفاتورة والمبلغ، أو `null` عند الإلغاء.
/// [auditEntity] يحدد ما تُسجَّل الموافقة عليه (`invoice_return` أو `car_wash_discount`).
Future<ReturnApproval?> requestReturnApproval(
  BuildContext context, {
  required String invoiceKey,
  required double amount,
  required String reasonsAr,
  required bool blockSelfApproval,
  String title = 'موافقة على الاسترجاع',
  String auditEntity = 'invoice_return',
}) async {
  final auth = context.read<AuthProvider>();
  final db = DatabaseHelper();
  final users = await db.listActiveUsersOrdered();
  final elevated = <int>{};
  for (final u in users) {
    final id = (u['id'] as num?)?.toInt();
    final role = (u['role'] ?? 'staff').toString();
    if (id == null || role == 'owner' || role == 'admin') continue;
    if (await PermissionService.instance.hasElevatedAccess(
      userId: id,
      roleKey: role,
    )) {
      elevated.add(id);
    }
  }
  final candidates = selectApprovers(
    activeUsers: users,
    elevatedStaffIds: elevated,
    currentUserId: auth.userId,
    blockSelfApproval: blockSelfApproval,
  );
  if (!context.mounted) return null;
  if (candidates.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'لا يوجد على هذا الجهاز من يحق له الموافقة (المالك أو موظف كامل الصلاحية).',
        ),
      ),
    );
    return null;
  }
  final result = await showDialog<ReturnApproval>(
    context: context,
    barrierDismissible: false,
    builder: (_) => SecureScreen(
      child: _ApprovalDialog(
        candidates: candidates,
        invoiceKey: invoiceKey,
        amount: amount,
        reasonsAr: reasonsAr,
        title: title,
        auditEntity: auditEntity,
      ),
    ),
  );
  if (result == null) {
    unawaited(
      BusinessAuditLogService.instance.record(
        eventType: 'return_approval_rejected',
        entityType: auditEntity,
        entityId: invoiceKey,
        newValueJson: jsonEncode({'amount': amount, 'cause': 'cancelled'}),
        userId: auth.userId,
        username: auth.displayName,
      ),
    );
  }
  return result;
}

class _ApprovalDialog extends StatefulWidget {
  const _ApprovalDialog({
    required this.candidates,
    required this.invoiceKey,
    required this.amount,
    required this.reasonsAr,
    required this.title,
    required this.auditEntity,
  });

  final List<ApprovalCandidate> candidates;
  final String invoiceKey;
  final double amount;
  final String reasonsAr;
  final String title;
  final String auditEntity;

  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<_ApprovalDialog> {
  late ApprovalCandidate _who = widget.candidates.first;
  final _pin = TextEditingController();
  final _focus = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final pin = _pin.text.trim();
    if (!PinInputConstraints.isValid(pin)) {
      setState(() => _error = PinInputConstraints.invalidMessage);
      return;
    }
    final scope = PinAttemptGuard.userScope(_who.userId);
    final locked = await PinAttemptGuard.remainingLock(scope);
    if (!mounted) return;
    if (locked != null) {
      setState(() {
        _error =
            'محاولات كثيرة. حاول بعد ${PinAttemptGuard.formatRemaining(locked)}';
        _pin.clear();
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    var ok = false;
    try {
      if (_who.isOwner) {
        final owner = await auth.getLocalOwnerRow();
        ok =
            owner != null &&
            await auth.verifyOwnerConfirmationCredential(
              ownerRow: owner,
              credential: pin,
            );
      } else {
        ok = await DatabaseHelper().verifyPinForUser(_who.userId, pin);
      }
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      final lock = await PinAttemptGuard.recordFailure(
        scope,
        userId: _who.userId,
        username: _who.name,
      );
      unawaited(
        BusinessAuditLogService.instance.record(
          eventType: 'return_approval_rejected',
          entityType: widget.auditEntity,
          entityId: widget.invoiceKey,
          newValueJson: jsonEncode({
            'amount': widget.amount,
            'cause': 'wrong_pin',
            'approverId': _who.userId,
          }),
          userId: auth.userId,
          username: auth.displayName,
        ),
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pin.clear();
        _error = lock != null
            ? 'محاولات كثيرة. حاول بعد ${PinAttemptGuard.formatRemaining(lock)}'
            : 'الرمز غير صحيح';
      });
      _focus.requestFocus();
      return;
    }
    await PinAttemptGuard.recordSuccess(scope);
    unawaited(
      BusinessAuditLogService.instance.record(
        eventType: 'return_approved',
        entityType: widget.auditEntity,
        entityId: widget.invoiceKey,
        newValueJson: jsonEncode({
          'amount': widget.amount,
          'approverId': _who.userId,
          'approver': _who.name,
          'reasons': widget.reasonsAr,
        }),
        userId: _who.userId,
        username: _who.name,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(
      ReturnApproval(
        approverUserId: _who.userId,
        approverName: _who.name,
        approverIsOwner: _who.isOwner,
        invoiceGlobalKey: widget.invoiceKey,
        amount: widget.amount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: screen.width.clamp(280.0, 420.0),
          maxHeight: screen.height * 0.82,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                'المبلغ: ${IraqiCurrencyFormat.formatIqd(widget.amount)}\n'
                'السبب: ${widget.reasonsAr}',
                style: TextStyle(height: 1.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _who.userId,
                decoration: const InputDecoration(
                  labelText: 'من يوافق؟',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in widget.candidates)
                    DropdownMenuItem(
                      value: c.userId,
                      child: Text(c.isOwner ? '${c.name} (المالك)' : c.name),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (id) => setState(() {
                        _who = widget.candidates.firstWhere(
                          (c) => c.userId == id,
                        );
                        _pin.clear();
                        _error = null;
                      }),
              ),
              const SizedBox(height: 14),
              PinFourBoxesField(
                controller: _pin,
                focusNode: _focus,
                label: 'رمز ${_who.name}',
                obscureText: _obscure,
                onToggleObscure: () => setState(() => _obscure = !_obscure),
                enabled: !_busy,
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('إلغاء'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _busy ? null : () => unawaited(_submit()),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('موافقة'),
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
