import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/shift_provider.dart';
import '../../services/database_helper.dart';
import '../../theme/design_tokens.dart';
import '../../navigation/app_root_navigator_key.dart';
import '../../services/password_hashing.dart';
import '../../utils/staff_identity_apply.dart';
import '../../utils/staff_identity_qr.dart';
import 'staff_qr_scan_screen.dart';

final _numFmt = NumberFormat('#,##0.##', 'en');

/// بعد تسجيل الدخول: عرض رصيد الصندوق، الجرد، إضافة مال، ثم تمييز موظف الوردية.
class OpenShiftScreen extends StatefulWidget {
  const OpenShiftScreen({super.key});

  @override
  State<OpenShiftScreen> createState() => _OpenShiftScreenState();
}

class _OpenShiftScreenState extends State<OpenShiftScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  final _physical = TextEditingController();
  final _addCash = TextEditingController();

  bool _checking = true;
  double _systemBalance = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final open = await _db.getOpenWorkShift();
    if (!mounted) return;
    if (open != null) {
      final ok = await _verifyShiftStaffResume(open);
      if (!mounted) return;
      if (!ok) {
        await _logout();
        return;
      }
      await context.read<ShiftProvider>().refresh();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
      return;
    }
    final sum = await _db.getCashSummary();
    if (!mounted) return;
    final bal = sum['balance'] ?? 0.0;
    setState(() {
      _systemBalance = bal;
      _physical.text = _formatInitial(bal);
      _checking = false;
    });
  }

  /// عند العودة إلى التطبيق بوردية مفتوحة أصلاً: نطلب كلمة مرور موظف الوردية
  /// حتى لا يتجاوز شخصٌ آخر هوية الموظف بمجرد إعادة تسجيل دخول عبر Google
  /// على نفس الجهاز — كلمة مرور الموظف تحرس المحاسبية، لا الدخول للتطبيق.
  Future<bool> _verifyShiftStaffResume(Map<String, dynamic> openShift) async {
    final staffId = openShift['shiftStaffUserId'] as int?;
    if (staffId == null || staffId <= 0) return true;

    final row = await _db.getUserById(staffId);
    if (row == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'موظف الوردية المسجَّل لم يعد موجوداً. أغلق الوردية من جهاز آخر أو اتصل بالمسؤول.',
            ),
          ),
        );
      }
      return false;
    }

    final salt = (row['passwordSalt'] as String?) ?? '';
    final hash = (row['passwordHash'] as String?) ?? '';
    if (salt.isEmpty || hash.isEmpty) return true;

    final disp = (row['displayName'] as String?)?.trim() ?? '';
    final name = disp.isNotEmpty ? disp : (row['username'] as String? ?? '');

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ShiftStaffResumeLockDialog(
        staffName: name,
        salt: salt,
        hash: hash,
      ),
    );
    return ok == true;
  }

  String _formatInitial(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return _numFmt.format(v);
  }

  double _parseMoney(String s) {
    final t = s.replaceAll(',', '').trim();
    if (t.isEmpty) return 0;
    return double.tryParse(t) ?? 0;
  }

  Future<void> _openShift() async {
    final auth = context.read<AuthProvider>();
    final uid = auth.userId;
    if (uid == null) return;

    final physical = _parseMoney(_physical.text);
    final addPart = _parseMoney(_addCash.text);
    if (addPart < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن أن يكون المبلغ المضاف سالباً')),
      );
      return;
    }

    final identity = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ShiftStaffIdentityDialog(db: _db),
    );

    if (identity == null || !mounted) return;

    final staffUserId = identity['shiftStaffUserId'];
    if (staffUserId is! int || staffUserId <= 0) return;

    final nameRaw = (identity['name'] ?? '').trim();
    final name = nameRaw.isEmpty ? '—' : nameRaw;

    var openedShiftId = 0;
    var openedDetail = '';

    try {
      final shiftId = await context.read<ShiftProvider>().openShift(
            sessionUserId: uid,
            shiftStaffUserId: staffUserId,
            systemBalanceAtOpen: _systemBalance,
            declaredPhysicalCash: physical,
            addedCashAtOpen: addPart,
            shiftStaffName: name,
            // لا نخزّن كلمة مرور الدخول — التحقق كان في الحوار فقط.
            shiftStaffPin: '',
          );

      final arFmt = NumberFormat('#,##0.##', 'ar');
      String iq(double v) => '${arFmt.format(v)} د.ع';

      final detailBuf = StringBuffer()
        ..writeln('موظف الوردية: $name')
        ..writeln('رصيد النظام عند الفتح: ${iq(_systemBalance)}')
        ..writeln('الجرد اليدوي (الصندوق): ${iq(physical)}')
        ..writeln('المبلغ المضاف عند الفتح: ${iq(addPart)}');

      final detail = detailBuf.toString().trim();
      openedShiftId = shiftId;
      openedDetail = detail;

      if (mounted) {
        await context.read<NotificationProvider>().recordShiftLifecycleEvent(
              isClose: false,
              shiftId: shiftId,
              title: 'فتح وردية #$shiftId',
              body: detail,
            );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فتح الوردية: $e')),
        );
      }
      return;
    }

    if (!mounted) return;
    if (openedShiftId == 0 || openedDetail.isEmpty) return;

    Navigator.of(context).pushReplacementNamed('/home');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = appRootNavigatorKey.currentContext;
      if (ctx == null) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          content: Text('تم فتح الوردية #$openedShiftId\n$openedDetail'),
        ),
      );
    });
  }

  Future<void> _logout() async {
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
  }

  @override
  void dispose() {
    _physical.dispose();
    _addCash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_checking) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: const Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Card(
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppShape.none,
                        side: BorderSide(
                          color: isDark
                              ? AppColors.borderDark
                              : AppColors.borderLight,
                        ),
                      ),
                      color: isDark ? AppColors.cardDark : AppColors.cardLight,
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  color: AppColors.accent,
                                  size: 28,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'فتح الوردية',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white
                                          : AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'راجع رصيد الصندوق حسب النظام، ثم سجّل الجرد الفعلي أو أضف نقداً قبل بدء العمل.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.12),
                                borderRadius: AppShape.none,
                                border: Border.all(
                                  color: AppColors.accent.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.account_balance_wallet_outlined,
                                    color: AppColors.accent,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'رصيد الصندوق (حسب النظام)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_numFmt.format(_systemBalance)} د.ع',
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              controller: _physical,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]'),
                                ),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'المبلغ الظاهر عند الجرد (د.ع)',
                                hintText: 'ما يطابق النقد أمامك',
                                border: OutlineInputBorder(
                                  borderRadius: AppShape.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _addCash,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]'),
                                ),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'إضافة مال للصندوق (اختياري)',
                                hintText: '0',
                                border: OutlineInputBorder(
                                  borderRadius: AppShape.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            FilledButton.icon(
                              onPressed: _openShift,
                              icon: const Icon(Icons.lock_open_rounded),
                              label: const Text('فتح الوردية'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _logout,
                              child: Text(
                                'الخروج من الحساب',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// حوار موظف الوردية: اختيار مستخدم مسجّل في النظام + رمز البطاقة، أو مسح QR.
class _ShiftStaffIdentityDialog extends StatefulWidget {
  const _ShiftStaffIdentityDialog({required this.db});

  final DatabaseHelper db;

  @override
  State<_ShiftStaffIdentityDialog> createState() =>
      _ShiftStaffIdentityDialogState();
}

class _ShiftStaffIdentityDialogState extends State<_ShiftStaffIdentityDialog> {
  final _displayNameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final wedgeCtrl = TextEditingController();
  final _wedgeFocus = FocusNode();
  bool _wedgeBusy = false;

  List<Map<String, dynamic>> _eligible = [];
  bool _loadingUsers = true;
  int? _selectedUserId;

  @override
  void initState() {
    super.initState();
    wedgeCtrl.addListener(_onWedgeChanged);
    unawaited(_loadEligibleUsers());
  }

  Future<void> _loadEligibleUsers() async {
    // كل المستخدمين النشطين — لا نُصفّي بـ shifts.access لأن صفوف user_permissions قد تمنع
    // الصلاحية صراحةً فيظهر فقط المدير. التحقق الحقيقي: رمز بطاقة الوردية + صلاحيات الجلسة لاحقاً.
    final eligible = await widget.db.listActiveUsersOrdered();
    if (!mounted) return;
    setState(() {
      _eligible = eligible;
      _loadingUsers = false;
      if (eligible.length == 1) {
        _selectedUserId = eligible.first['id'] as int;
        _syncDisplayNameForId(_selectedUserId!);
      }
    });
  }

  void _syncDisplayNameForId(int userId) {
    Map<String, dynamic>? row;
    for (final m in _eligible) {
      if ((m['id'] as int) == userId) {
        row = m;
        break;
      }
    }
    if (row == null) return;
    final disp = (row['displayName'] as String?)?.trim() ?? '';
    _displayNameCtrl.text =
        disp.isNotEmpty ? disp : (row['username'] as String? ?? '');
  }

  void _onWedgeChanged() {
    if (_wedgeBusy) return;
    final t = wedgeCtrl.text;
    if (!RegExp(r'[\r\n]').hasMatch(t)) return;
    _wedgeBusy = true;
    final clean = t.replaceAll(RegExp(r'[\r\n]+'), '').trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        wedgeCtrl.text = '';
        wedgeCtrl.selection = const TextSelection.collapsed(offset: 0);
      }
      _wedgeBusy = false;
      if (clean.isNotEmpty) {
        final parsed = StaffIdentityQr.tryParse(clean);
        if (parsed != null) {
          _applyParsed(parsed);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('النص المقروء ليس رمز هوية صالحاً')),
          );
        }
      }
    });
  }

  Future<void> _applyParsed(StaffQrData parsed) async {
    final err = await StaffIdentityApply.applyQrPayloadSelectUserOnly(
      db: widget.db,
      data: parsed,
      nameCtrl: _displayNameCtrl,
    );
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() => _selectedUserId = parsed.userId);
  }

  void _confirm() async {
    final id = _selectedUserId;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر مستخدم الوردية من القائمة أو امسح البطاقة')),
      );
      return;
    }
    final row = await widget.db.getUserById(id);
    if (row == null || !mounted) return;
    final pwd = _passwordCtrl.text;
    final salt = row['passwordSalt'] as String?;
    final hash = row['passwordHash'] as String?;
    if (salt == null ||
        hash == null ||
        salt.isEmpty ||
        hash.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لا توجد كلمة مرور محلية لهذا الحساب. عيّن كلمة مرور من إدارة المستخدمين (أو استخدم حساباً ليس دخوله عبر Google فقط).',
          ),
        ),
      );
      return;
    }
    if (!PasswordHashing.verify(pwd, salt, hash)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('كلمة مرور الدخول غير صحيحة')),
      );
      return;
    }
    final disp = (row['displayName'] as String?)?.trim() ?? '';
    final name = disp.isNotEmpty ? disp : (row['username'] as String? ?? '');
    if (!mounted) return;
    Navigator.pop(context, {
      'shiftStaffUserId': id,
      'name': name,
    });
  }

  @override
  void dispose() {
    wedgeCtrl.removeListener(_onWedgeChanged);
    _displayNameCtrl.dispose();
    _passwordCtrl.dispose();
    wedgeCtrl.dispose();
    _wedgeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('موظف الوردية'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'اختر موظف الوردية ثم أدخل كلمة مرور الدخول الخاصة به (نفس كلمة مرور تسجيل الدخول). يمكن مسح QR لاختيار المستخدم فقط، ثم إدخال كلمة المرور. الصلاحيات أثناء العمل تتبع حساب الموظف المختار.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 14),
              if (_loadingUsers)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_eligible.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'لا يوجد مستخدمين نشطين في النظام. أضف مستخدماً من إدارة المستخدمين.',
                    style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                  ),
                )
              else
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'مستخدم الوردية (من النظام)',
                    border: OutlineInputBorder(borderRadius: AppShape.none),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: _selectedUserId,
                      hint: const Text('اختر مستخدماً'),
                      items: [
                        for (final r in _eligible)
                          DropdownMenuItem<int>(
                            value: r['id'] as int,
                            child: Text(
                              _labelForUserRow(r),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _selectedUserId = v;
                          if (v != null) _syncDisplayNameForId(v);
                        });
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _displayNameCtrl,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'الاسم الظاهر',
                  border: OutlineInputBorder(borderRadius: AppShape.none),
                  hintText: 'يُحدَّد تلقائياً من المستخدم أو البطاقة',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'مسح QR لاختيار المستخدم (كاميرا أو قارئ يعمل كلوحة مفاتيح):',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'مسح بالكاميرا',
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    onPressed: () async {
                      final parsed = await Navigator.of(context).push<StaffQrData>(
                        MaterialPageRoute(
                          fullscreenDialog: true,
                          builder: (_) => const StaffQrScanScreen(),
                        ),
                      );
                      if (parsed == null || !mounted) return;
                      await _applyParsed(parsed);
                    },
                  ),
                ],
              ),
              TextField(
                controller: wedgeCtrl,
                focusNode: _wedgeFocus,
                decoration: const InputDecoration(
                  labelText: 'جهاز قراءة خارجي (اضغط هنا ثم امسح)',
                  hintText: 'يُستقبل نص QR ثم Enter تلقائياً',
                  border: OutlineInputBorder(borderRadius: AppShape.none),
                  prefixIcon: Icon(Icons.usb_rounded),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  final clean = wedgeCtrl.text.trim();
                  wedgeCtrl.clear();
                  if (clean.isEmpty) return;
                  final parsed = StaffIdentityQr.tryParse(clean);
                  if (parsed != null) {
                    _applyParsed(parsed);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('النص المقروء ليس رمز هوية صالحاً'),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة مرور الدخول (المستخدم المختار)',
                  hintText: 'نفس كلمة مرور تسجيل الدخول',
                  border: OutlineInputBorder(borderRadius: AppShape.none),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: (_loadingUsers || _eligible.isEmpty) ? null : _confirm,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }

  String _labelForUserRow(Map<String, dynamic> r) {
    final disp = (r['displayName'] as String?)?.trim() ?? '';
    final u = (r['username'] as String?)?.trim() ?? '';
    final email = (r['email'] as String?)?.trim() ?? '';
    final head = disp.isNotEmpty ? disp : u;
    if (email.isNotEmpty) return '$head · $email';
    return head.isEmpty ? 'مستخدم #${r['id']}' : head;
  }
}

/// حوار قفل يُعرض عندما يعود المستخدم للتطبيق ووردية مفتوحة: يلزم موظف
/// الوردية بإعادة إدخال كلمة مروره لمنع تجاوز هويته عبر إعادة تسجيل دخول
/// Google صامت.
class _ShiftStaffResumeLockDialog extends StatefulWidget {
  const _ShiftStaffResumeLockDialog({
    required this.staffName,
    required this.salt,
    required this.hash,
  });

  final String staffName;
  final String salt;
  final String hash;

  @override
  State<_ShiftStaffResumeLockDialog> createState() =>
      _ShiftStaffResumeLockDialogState();
}

class _ShiftStaffResumeLockDialogState
    extends State<_ShiftStaffResumeLockDialog> {
  final _ctrl = TextEditingController();
  bool _error = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (PasswordHashing.verify(_ctrl.text, widget.salt, widget.hash)) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _error = true;
      _ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('متابعة الوردية'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'توجد وردية مفتوحة باسم "${widget.staffName}". '
                'أدخل كلمة مرور الموظف للمتابعة.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ctrl,
                autofocus: true,
                obscureText: true,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'كلمة مرور الموظف',
                  errorText: _error ? 'كلمة المرور غير صحيحة' : null,
                  border: const OutlineInputBorder(borderRadius: AppShape.none),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('تسجيل خروج'),
            ),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
  }
}
