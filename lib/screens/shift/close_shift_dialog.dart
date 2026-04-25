import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../navigation/app_root_navigator_key.dart';
import '../../providers/notification_provider.dart';
import '../../providers/shift_provider.dart';
import '../../services/database_helper.dart';
import '../../services/password_hashing.dart';
import '../../theme/app_corner_style.dart';

final _numFmt = NumberFormat('#,##0.##', 'ar');

/// إغلاق الوردية: عرض الرصيد تلقائياً، جرد الصندوق، المبلغ المسحوب، وملخص الفواتير.
Future<void> showCloseShiftDialog(BuildContext context) async {
  final shift = context.read<ShiftProvider>().activeShift;
  if (shift == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('لا توجد وردية مفتوحة')),
    );
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
  final _withdrawCtrl = TextEditingController(text: '0');
  final _passwordVerifyCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  String? _error;
  double _systemBalance = 0;
  Map<String, int> _counts = const {'sales': 0, 'returns': 0};
  int? _shiftStaffUserId;
  String _shiftStaffName = '';

  @override
  void initState() {
    super.initState();
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
        _inBoxCtrl.text = _formatNum(bal);
        _counts = c;
        final rawUid = shiftRow?['shiftStaffUserId'];
        if (rawUid is int) {
          _shiftStaffUserId = rawUid;
        } else if (rawUid is num) {
          _shiftStaffUserId = rawUid.toInt();
        } else {
          _shiftStaffUserId = null;
        }
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

  String _formatNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return _numFmt.format(v);
  }

  double _parse(String? s) {
    if (s == null || s.trim().isEmpty) return 0;
    return double.tryParse(s.replaceAll(',', '').trim()) ?? 0;
  }

  @override
  void dispose() {
    _inBoxCtrl.dispose();
    _withdrawCtrl.dispose();
    _passwordVerifyCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final pwdIn = _passwordVerifyCtrl.text.trim();
    if (pwdIn.isNotEmpty) {
      final sid = _shiftStaffUserId;
      if (sid == null || sid <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'هذه الوردية لا ترتبط بمستخدم في النظام. اترك كلمة المرور فارغة للمتابعة أو أعد فتح الوردية بالإصدار الحديث.',
            ),
          ),
        );
        return;
      }
      final row = await _db.getUserById(sid);
      if (!mounted) return;
      if (row == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر التحقق من حساب موظف الوردية')),
        );
        return;
      }
      final salt = row['passwordSalt'] as String?;
      final hash = row['passwordHash'] as String?;
      if (salt == null ||
          hash == null ||
          salt.isEmpty ||
          hash.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'لا توجد كلمة مرور محلية لحساب موظف الوردية. اترك الحقل فارغاً أو عيّن كلمة مرور للمستخدم.',
            ),
          ),
        );
        return;
      }
      if (!PasswordHashing.verify(pwdIn, salt, hash)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('كلمة مرور الدخول لا تطابق حساب موظف الوردية'),
          ),
        );
        return;
      }
    }

    final inBox = _parse(_inBoxCtrl.text);
    final withdraw = _parse(_withdrawCtrl.text);

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الإغلاق: $e')),
        );
      }
      return;
    }

    final staffLabel =
        _shiftStaffName.isEmpty ? '—' : _shiftStaffName;
    final detailBuf = StringBuffer()
      ..writeln('موظف الوردية: $staffLabel')
      ..writeln(
        'رصيد النظام لحظة الإغلاق: ${_formatNum(systemNow)} د.ع',
      )
      ..writeln('المبلغ المُعلَن في الصندوق: ${_formatNum(inBox)} د.ع')
      ..writeln('المبلغ المسحوب: ${_formatNum(withdraw)} د.ع')
      ..writeln(
        'المتبقّي في الصندوق بعد السحب: ${_formatNum(remaining)} د.ع',
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
    Navigator.of(context).pop();
    widget.onClosedSuccess(detail);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ac = context.appCorners;
    final isDark = theme.brightness == Brightness.dark;
    final titleStyle = theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ) ??
        TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: ac.lg),
        title: Row(
          children: [
            Icon(Icons.lock_clock_rounded, color: cs.primary, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'إغلاق الوردية',
                style: titleStyle,
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _error != null
                  ? SingleChildScrollView(
                      child: Text(_error!, style: const TextStyle(color: Colors.red)),
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
                                  ) ??
                                  TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: cs.onSurfaceVariant,
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
                            const SizedBox(height: 12),
                            Text(
                              'تأكيد بكلمة مرور موظف الوردية (اختياري)',
                              style: theme.textTheme.labelLarge?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ) ??
                                  TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'أدخل كلمة مرور الدخول لحساب «$_shiftStaffName» إن أردت التحقق. اترك الحقل فارغاً لتخطّي التحقق.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    height: 1.3,
                                  ) ??
                                  TextStyle(
                                    fontSize: 11,
                                    height: 1.3,
                                    color: cs.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _passwordVerifyCtrl,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'كلمة مرور الدخول (اختياري)',
                                hintText: 'نفس كلمة مرور تسجيل الدخول للموظف',
                                border: OutlineInputBorder(
                                  borderRadius: ac.sm,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'يُحدَّد الرصيد تلقائياً من حركات الصندوق. راجع القيم ثم أكّد السحب.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    height: 1.35,
                                  ) ??
                                  TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: cs.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            _BalanceHero(
                              label: 'رصيد الصندوق (حسب النظام)',
                              amount: _systemBalance,
                              onRefresh: _reload,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'المبلغ في الصندوق',
                              style: theme.textTheme.labelLarge?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ) ??
                                  TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _inBoxCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]'),
                                ),
                              ],
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: cs.surfaceContainerHighest.withValues(
                                  alpha: isDark ? 0.45 : 0.65,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 18,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: ac.sm,
                                  borderSide: BorderSide(
                                    color: cs.primary.withValues(alpha: 0.5),
                                    width: 1.5,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: ac.sm,
                                  borderSide: BorderSide(
                                    color: cs.primary.withValues(alpha: 0.35),
                                  ),
                                ),
                                hintText: 'المبلغ الظاهر عند الجرد',
                              ),
                              validator: (v) {
                                final n = _parse(v);
                                if (n < 0) return 'قيمة غير صالحة';
                                return null;
                              },
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'المبلغ الذي تريد أخذه',
                              style: theme.textTheme.labelLarge?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ) ??
                                  TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _withdrawCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]'),
                                ),
                              ],
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: ac.sm,
                                ),
                                hintText: '0',
                              ),
                              validator: (v) {
                                final n = _parse(v);
                                if (n < 0) return 'قيمة غير صالحة';
                                return null;
                              },
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 14),
                            Builder(
                              builder: (context) {
                                final inB = _parse(_inBoxCtrl.text);
                                final w = _parse(_withdrawCtrl.text);
                                final rem = inB - w;
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cs.primary.withValues(alpha: 0.08),
                                    borderRadius: ac.sm,
                                    border: Border.all(
                                      color: cs.primary.withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'المتبقي في الصندوق بعد السحب',
                                        style: theme.textTheme.bodyMedium
                                                ?.copyWith(fontSize: 13) ??
                                            TextStyle(
                                              fontSize: 13,
                                              color: cs.onSurface,
                                            ),
                                      ),
                                      Text(
                                        '${_numFmt.format(rem)} د.ع',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: cs.primary,
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
        actions: [
          TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: _loading ? null : _confirm,
            icon: const Icon(Icons.check_rounded, size: 20),
            label: const Text('تأكيد وإغلاق الوردية'),
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
            ),
          ),
        ],
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
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
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
    required this.amount,
    required this.onRefresh,
  });

  final String label;
  final double amount;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final onHero = cs.onPrimary;
    final ts = MediaQuery.textScalerOf(context);
    final labelSize = ts.scale(12.0);
    final amountSize = ts.scale(26.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary.withValues(alpha: 0.95),
            Color.lerp(cs.primary, Colors.black, 0.28)!,
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
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
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: onHero.withValues(alpha: 0.92),
                    fontSize: labelSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: onRefresh,
                icon: Icon(
                  Icons.refresh_rounded,
                  color: onHero.withValues(alpha: 0.95),
                  size: 20,
                ),
                tooltip: 'تحديث الرصيد',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_numFmt.format(amount)} د.ع',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: onHero,
              fontSize: amountSize,
              fontWeight: FontWeight.w200,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
