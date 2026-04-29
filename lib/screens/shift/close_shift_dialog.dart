import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../navigation/app_root_navigator_key.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/shift_provider.dart';
import '../../services/database_helper.dart';
import '../../services/password_hashing.dart';
import '../../theme/app_corner_style.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../utils/numeric_format.dart';
import '../../widgets/inputs/app_input.dart';
import '../../widgets/inputs/app_price_input.dart';

/// إغلاق الوردية: عرض الرصيد تلقائياً، جرد الصندوق، المبلغ المسحوب، وملخص الفواتير.
Future<void> showCloseShiftDialog(BuildContext context) async {
  final shift = context.read<ShiftProvider>().activeShift;
  if (shift == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('لا توجد وردية مفتوحة')));
    return;
  }

  final shiftId = shift['id'] as int;
  final nav = Navigator.of(context, rootNavigator: true);

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _CloseShiftDialog(
      shiftId: shiftId,
      onClosedSuccess: (String detail) {
        nav.pushReplacementNamed('/open-shift');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final rootCtx = appRootNavigatorKey.currentContext;
          if (rootCtx == null) return;
          ScaffoldMessenger.of(rootCtx).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 7),
              content: Text(
                'تم إغلاق الوردية. افتح وردية جديدة للمتابعة.\n\n$detail',
              ),
            ),
          );
        });
      },
    ),
  );
}

class _CloseShiftDialog extends StatefulWidget {
  const _CloseShiftDialog({
    required this.shiftId,
    required this.onClosedSuccess,
  });

  final int shiftId;
  final ValueChanged<String> onClosedSuccess;

  @override
  State<_CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends State<_CloseShiftDialog> {
  final DatabaseHelper _db = DatabaseHelper();
  final _inBoxCtrl = TextEditingController();
  final _withdrawCtrl = TextEditingController();
  final _passwordVerifyCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final _focusPwd = FocusNode();
  final _focusInBox = FocusNode();
  final _focusWithdraw = FocusNode();

  bool _loading = true;
  String? _error;
  double _systemBalance = 0;
  Map<String, int> _counts = const {'sales': 0, 'returns': 0};
  String _shiftStaffName = '';
  String? _passwordInlineError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _withdrawCtrl.text = IraqiCurrencyFormat.formatInt(0);
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sum = await _db.getCashSummary();
      final c = await _db.getWorkShiftInvoiceCounts(widget.shiftId);
      final shiftRow = await _db.getWorkShiftById(widget.shiftId);
      if (!mounted) return;
      final bal = sum['balance'] ?? 0.0;
      setState(() {
        _systemBalance = bal;
        _inBoxCtrl.text = IraqiCurrencyFormat.formatInt(bal.round());
        _counts = c;
        _shiftStaffName =
            (shiftRow?['shiftStaffName'] as String?)?.trim() ?? '';
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  int _inParsed() => NumericFormat.parseNumber(_inBoxCtrl.text);

  int _wdParsed() => NumericFormat.parseNumber(_withdrawCtrl.text);

  String? _withdrawWarn() {
    if (_wdParsed() > _inParsed()) return 'المبلغ أكبر من رصيد الصندوق';
    return null;
  }

  @override
  void dispose() {
    _inBoxCtrl.dispose();
    _withdrawCtrl.dispose();
    _passwordVerifyCtrl.dispose();
    _focusPwd.dispose();
    _focusInBox.dispose();
    _focusWithdraw.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() => _passwordInlineError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final pwdIn = _passwordVerifyCtrl.text.trim();
    final auth = context.read<AuthProvider>();
    if (pwdIn.isNotEmpty) {
      final uid = auth.userId;
      if (uid == null || uid <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر التحقق من كلمة المرور لهذا الحساب'),
          ),
        );
        return;
      }
      final row = await _db.getUserById(uid);
      if (!mounted) return;
      if (row == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر التحقق من المستخدم الحالي')),
        );
        return;
      }
      final salt = row['passwordSalt'] as String?;
      final hash = row['passwordHash'] as String?;
      if (salt == null || hash == null || salt.isEmpty || hash.isEmpty) {
        setState(
          () => _passwordInlineError =
              'لا توجد كلمة مرور محفوظة لهذا الحساب. اترك الحقل فارغاً.',
        );
        return;
      }
      if (!PasswordHashing.verify(pwdIn, salt, hash)) {
        setState(() => _passwordInlineError = 'كلمة المرور غير صحيحة');
        return;
      }
    }

    final inBox = _inParsed().toDouble();
    final withdraw = _wdParsed().toDouble();

    if (withdraw < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المبلغ المسحوب لا يمكن أن يكون سالباً')),
      );
      return;
    }
    if (withdraw > inBox + 0.0001) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('المبلغ المسحوب أكبر من المبلغ الموجود في الصندوق'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    final sum = await _db.getCashSummary();
    if (!mounted) return;
    final systemNow = sum['balance'] ?? 0.0;
    final remaining = inBox - withdraw;

    try {
      await context.read<ShiftProvider>().closeShift(
        shiftId: widget.shiftId,
        systemBalanceAtCloseMoment: systemNow,
        declaredCashInBox: inBox,
        withdrawnAmount: withdraw,
        declaredClosingCash: remaining,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر الإغلاق: $e')));
      }
      return;
    }

    final staffLabel = _shiftStaffName.isEmpty ? '—' : _shiftStaffName;
    final detailBuf = StringBuffer()
      ..writeln('موظف الوردية: $staffLabel')
      ..writeln(
        'رصيد النظام لحظة الإغلاق: ${IraqiCurrencyFormat.formatInt(systemNow.round())} د.ع',
      )
      ..writeln(
        'المبلغ المُعلَن في الصندوق: ${IraqiCurrencyFormat.formatInt(inBox.round())} د.ع',
      )
      ..writeln(
        'المبلغ المسحوب: ${IraqiCurrencyFormat.formatInt(withdraw.round())} د.ع',
      )
      ..writeln(
        'المتبقّي في الصندوق بعد السحب: ${IraqiCurrencyFormat.formatInt(remaining.round())} د.ع',
      );
    final detail = detailBuf.toString().trim();

    if (mounted) {
      await context.read<NotificationProvider>().recordShiftLifecycleEvent(
        isClose: true,
        shiftId: widget.shiftId,
        title: 'إغلاق وردية #${widget.shiftId}',
        body: detail,
      );
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    Navigator.of(context).pop();
    widget.onClosedSuccess(detail);
  }

  static const Color _navyDeep = Color(0xFF1A2340);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ac = context.appCorners;
    final username = context.watch<AuthProvider>().username;
    final uLabel = username.isEmpty ? '' : username;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).maybePop<void>();
        },
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: ac.lg),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          title: Row(
            textDirection: TextDirection.rtl,
            children: [
              Icon(Icons.lock_rounded, color: cs.primary, size: 26),
              Expanded(
                child: Text(
                  'إغلاق الوردية',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 32),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.72,
              ),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _error != null
                  ? SingleChildScrollView(
                      child: Text(_error!, style: TextStyle(color: cs.error)),
                    )
                  : Form(
                      key: _formKey,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'ملخص هذه الوردية',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _StatChip(
                                    icon: Icons.receipt_long_rounded,
                                    label: 'فواتير البيع',
                                    value: '${_counts['sales'] ?? 0}',
                                    color: const Color(0xFF059669),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _StatChip(
                                    icon: Icons.undo_rounded,
                                    label: 'فواتير المرتجع',
                                    value: '${_counts['returns'] ?? 0}',
                                    color: const Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'تأكيد بكلمة مرور موظف الوردية (اختياري)',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              uLabel.isEmpty
                                  ? 'أدخل كلمة مرور حساب الدخول إن أردت التحقق. اترك الحقل فارغاً لتخطّي التحقق'
                                  : 'أدخل كلمة مرور الحساب «$uLabel» إن أردت التحقق. اترك الحقل فارغاً لتخطي التحقق',
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.35,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            AppInput(
                              label: ' ',
                              showLabel: false,
                              hint: 'كلمة مرور الدخول (اختياري)',
                              controller: _passwordVerifyCtrl,
                              focusNode: _focusPwd,
                              obscureText: true,
                              fillColor: Colors.white,
                              cursorColor: theme.colorScheme.onSurface,
                              validator: (_) => _passwordInlineError,
                              onChanged: (_) =>
                                  setState(() => _passwordInlineError = null),
                              textDirection: TextDirection.ltr,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) =>
                                  _focusInBox.requestFocus(),
                            ),
                            const SizedBox(height: 16),
                            _BalanceHero(
                              label: 'رصيد الصندوق (حسب النظام)',
                              amountIQD:
                                  '${IraqiCurrencyFormat.formatInt(_systemBalance.round())} د.ع',
                              onRefresh: _reload,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'يُحدَّد الرصيد تلقائياً من حركات الصندوق. راجع القيم ثم أكّد السحب.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 16),
                            AppPriceInput(
                              label: 'المبلغ في الصندوق',
                              hint: '0 د.ع',
                              controller: _inBoxCtrl,
                              focusNode: _focusInBox,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) =>
                                  _focusWithdraw.requestFocus(),
                              validator: (_) {
                                if (_inParsed() < 0) {
                                  return 'قيمة غير صالحة';
                                }
                                return null;
                              },
                              onParsedChanged: (_) => setState(() {}),
                            ),
                            AppPriceInput(
                              label: 'المبلغ الذي تريد أخذه',
                              hint: '0 د.ع',
                              controller: _withdrawCtrl,
                              focusNode: _focusWithdraw,
                              warningText: _withdrawWarn(),
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) async {
                                if (!_submitting) await _confirm();
                              },
                              validator: (_) {
                                if (_wdParsed() < 0) {
                                  return 'قيمة غير صالحة';
                                }
                                return null;
                              },
                              onParsedChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 12),
                            Builder(
                              builder: (context) {
                                final rem = _inParsed() - _wdParsed();
                                final neg = rem < 0;
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest
                                        .withValues(alpha: 0.45),
                                    borderRadius: ac.sm,
                                    border: Border.all(
                                      color: cs.primary.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'المتبقي في الصندوق بعد السحب',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(fontSize: 13),
                                      ),
                                      Text(
                                        '${IraqiCurrencyFormat.formatInt(rem)} د.ع',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: neg ? cs.error : cs.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
          actionsOverflowButtonSpacing: 8,
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: _loading || _submitting
                  ? null
                  : () {
                      Navigator.of(context).pop<void>();
                    },
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: (_loading || _submitting) ? null : _confirm,
              style: FilledButton.styleFrom(
                backgroundColor: _navyDeep,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.check_rounded, size: 22),
                        SizedBox(width: 8),
                        Text('تأكيد وإغلاق الوردية'),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: ac.sm,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({
    required this.label,
    required this.amountIQD,
    required this.onRefresh,
  });

  final String label;
  final String amountIQD;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final ts = MediaQuery.textScalerOf(context);
    final labelSize = ts.scale(12.0);
    final amountSize = ts.scale(24.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A2340),
            Color.lerp(const Color(0xFF1A2340), Colors.black, 0.32)!,
          ],
          begin: AlignmentDirectional.topEnd,
          end: AlignmentDirectional.bottomStart,
        ),
        borderRadius: ac.lg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: TextDirection.ltr,
            children: [
              IconButton(
                onPressed: onRefresh,
                icon: Icon(
                  Icons.refresh_rounded,
                  color: Colors.white.withValues(alpha: 0.94),
                  size: 22,
                ),
                tooltip: 'تحديث الرصيد',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.94),
                    fontSize: labelSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            amountIQD,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: amountSize,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
