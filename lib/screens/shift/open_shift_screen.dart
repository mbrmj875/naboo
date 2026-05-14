import 'dart:async' show unawaited;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
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
import '../../utils/iraqi_currency_format.dart';
import '../../utils/screen_layout.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/inputs/app_input.dart';
import 'staff_qr_scan_screen.dart';

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
  bool _openingShift = false;
  double _systemBalance = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
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
        unawaited(Navigator.of(context).pushReplacementNamed('/home'));
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
    } catch (e) {
      if (e is StateError && e.message.contains('TenantContext')) {
        // الجلسة انتهت في الخلفية أثناء تحميل الشاشة (سباق زمني)، نعود لشاشة الدخول.
        if (mounted) await _logout();
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ غير متوقع أثناء التهيئة: $e'),
            duration: const Duration(seconds: 10),
          ),
        );
        setState(() => _checking = false);
      }
    }
  }

  /// عند العودة إلى التطبيق بوردية مفتوحة أصلاً: نطلب كلمة مرور موظف الوردية
  /// حتى لا يتجاوز شخصٌ آخر هوية الموظف بمجرد إعادة تسجيل دخول عبر Google
  /// على نفس الجهاز — كلمة مرور الموظف تحرس المحاسبية، لا الدخول للتطبيق.
  Future<bool> _verifyShiftStaffResume(Map<String, dynamic> openShift) async {
    final staffId = openShift['shiftStaffUserId'] as int?;
    if (staffId == null || staffId <= 0) return true;

    final auth = context.read<AuthProvider>();
    if (staffId == auth.userId) {
      // المستخدم الحالي هو نفسه صاحب الوردية المفتوحة، لا داعي لطلب كلمة المرور مرة أخرى
      return true;
    }

    final row = await _db.getUserById(staffId);
    if (row == null) {
      final currentUserId = auth.userId;
      final currentName = auth.displayName.trim();
      final shiftId = (openShift['id'] as num?)?.toInt() ?? 0;
      if (currentUserId != null && currentUserId > 0 && shiftId > 0) {
        final db = await _db.database;
        await db.update(
          'work_shifts',
          {
            'shiftStaffUserId': currentUserId,
            'shiftStaffName': currentName.isEmpty ? auth.username : currentName,
          },
          where: 'id = ?',
          whereArgs: [shiftId],
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تم إصلاح بيانات موظف الوردية تلقائياً على هذا الجهاز. يمكنك المتابعة.',
              ),
            ),
          );
        }
        return true;
      }
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
      useRootNavigator: true,
      builder: (ctx) =>
          _ShiftStaffResumeLockDialog(staffName: name, salt: salt, hash: hash),
    );
    return ok == true;
  }

  String _formatInitial(double v) {
    return IraqiCurrencyFormat.formatInt(v);
  }

  double _parseMoney(String s) {
    return IraqiCurrencyFormat.parseIqdInt(s).toDouble();
  }

  void _showOpenShiftMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openShift() async {
    if (_openingShift) return;
    final auth = context.read<AuthProvider>();
    final uid = auth.userId;
    if (uid == null) {
      _showOpenShiftMessage('انتهت جلسة المستخدم. سجّل الدخول مرة أخرى.');
      return;
    }

    final physical = _parseMoney(_physical.text);
    final addPart = _parseMoney(_addCash.text);
    if (addPart < 0) {
      _showOpenShiftMessage('لا يمكن أن يكون المبلغ المضاف سالباً');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _openingShift = true);

    Map<String, dynamic>? identity;
    try {
      identity = await showDialog<Map<String, dynamic>?>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _ShiftStaffIdentityDialog(db: _db),
      );
    } catch (e) {
      _showOpenShiftMessage('تعذر فتح نافذة اختيار موظف الوردية: $e');
      if (mounted) setState(() => _openingShift = false);
      return;
    }

    if (!mounted) return;
    if (identity == null) {
      setState(() => _openingShift = false);
      _showOpenShiftMessage('لم يتم اختيار موظف الوردية.');
      return;
    }

    final staffUserId = identity['shiftStaffUserId'];
    if (staffUserId is! int || staffUserId <= 0) {
      setState(() => _openingShift = false);
      _showOpenShiftMessage('بيانات موظف الوردية غير مكتملة. اختر الموظف مرة أخرى.');
      return;
    }

    final nameRaw = ((identity['name'] as String?) ?? '').trim();
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

      String iq(double v) => IraqiCurrencyFormat.formatIqd(v);

      final detailBuf = StringBuffer()
        ..writeln('موظف الوردية: $name')
        ..writeln('رصيد النظام عند الفتح: ${iq(_systemBalance)}')
        ..writeln('الجرد اليدوي (الصندوق): ${iq(physical)}')
        ..writeln('المبلغ المضاف عند الفتح: ${iq(addPart)}');

      final detail = detailBuf.toString().trim();
      openedShiftId = shiftId;
      openedDetail = detail;

      // [NotificationProvider.refresh] ثقيل (عدة استعلامات للإشعارات) — لا ننتظره على
      // الخيط الرئيسي قبل الانتقال للرئيسية وإلا يبدو التطبيق «مجمّداً».
      if (mounted) {
        final notif = context.read<NotificationProvider>();
        unawaited(
          notif
              .recordShiftLifecycleEvent(
                isClose: false,
                shiftId: shiftId,
                title: 'فتح وردية #$shiftId',
                body: detail,
              )
              .catchError((Object e, StackTrace st) {
                if (kDebugMode) {
                  debugPrint(
                    '[ShiftLifecycle] recordShiftLifecycleEvent: $e\n$st',
                  );
                }
              }),
        );
      }
    } catch (e) {
      if (mounted) {
        _showOpenShiftMessage('تعذر فتح الوردية: $e');
      }
      return;
    } finally {
      if (mounted) setState(() => _openingShift = false);
    }

    if (!mounted) return;
    if (openedShiftId == 0 || openedDetail.isEmpty) {
      _showOpenShiftMessage('تمت العملية بدون رقم وردية صالح. حاول مرة أخرى.');
      return;
    }

    unawaited(Navigator.of(context).pushReplacementNamed('/home'));
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

  /// رفض التحقق من موظف الوردية: يجب عدم فتح التطبيق على وردية مفتوحة دون إثبات الهوية.
  /// لذلك نسجّل خروج الجلسة على هذا الجهاز ونعود لشاشة تسجيل الدخول.
  Future<void> _logout() async {
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    final root = appRootNavigatorKey.currentState;
    if (root != null && root.mounted) {
      unawaited(root.pushNamedAndRemoveUntil('/login', (r) => false));
      return;
    }
    unawaited(Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
      '/login',
      (r) => false,
    ));
  }

  @override
  void dispose() {
    _physical.dispose();
    _addCash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: GlassBackground(
          backgroundImage: AssetImage('assets/images/splash_bg.png'),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.accentGold),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
          child: GlassBackground(
            backgroundImage: const AssetImage('assets/images/splash_bg.png'),
            overlayOpacity: 0.38,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              extendBody: true,
              resizeToAvoidBottomInset: true,
              body: LayoutBuilder(
                builder: (context, constraints) {
                  final layout = ScreenLayout.of(context);
                  final isPhone = layout.isPhoneVariant;
                  final compact = isPhone ||
                      layout.isCompactHeight ||
                      constraints.maxHeight < 720;
                  final mediaPadding = MediaQuery.paddingOf(context);
                  final horizontalPadding = layout.isNarrowWidth
                      ? 12.0
                      : (isPhone ? 16.0 : 20.0);
                  final topPadding = mediaPadding.top + (compact ? 14 : 20);
                  final bottomPadding =
                      mediaPadding.bottom + (compact ? 14 : 20);
                  final availableHeight =
                      constraints.maxHeight - topPadding - bottomPadding;
                  return Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: horizontalPadding,
                      end: horizontalPadding,
                      top: topPadding,
                      bottom: bottomPadding,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: SizedBox(
                          height: availableHeight.clamp(420.0, 900.0),
                          child: GlassSurface(
                            borderRadius: BorderRadius.all(
                              Radius.circular(compact ? 18 : 22),
                            ),
                            blurSigma: 16,
                            tintColor: AppGlass.surfaceTintStrong,
                            strokeColor: AppGlass.stroke,
                            padding: EdgeInsetsDirectional.all(
                              compact ? 18 : 22,
                            ),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _OpenShiftHeader(compact: compact),
                                  SizedBox(height: compact ? 14 : 18),
                                  _SystemCashCard(
                                    amount: _systemBalance,
                                    compact: compact,
                                  ),
                                  SizedBox(height: compact ? 16 : 20),
                                  _MoneyGlassField(
                                    label: 'المبلغ الظاهر عند الجرد',
                                    subtitle:
                                        'اكتب المبلغ الموجود فعلياً داخل الصندوق الآن.',
                                    hint: 'مثال: 50,000',
                                    controller: _physical,
                                    keyboardType: TextInputType.number,
                                  ),
                                  SizedBox(height: compact ? 12 : 14),
                                  _MoneyGlassField(
                                    label: 'إضافة مال للصندوق',
                                    subtitle:
                                        'اختياري: استخدمه إذا أضفت نقداً قبل بداية البيع.',
                                    hint: '0',
                                    controller: _addCash,
                                    keyboardType: TextInputType.number,
                                  ),
                                  SizedBox(height: compact ? 18 : 22),
                                  _OpenShiftActionButton(
                                    opening: _openingShift,
                                    onPressed:
                                        _openingShift ? null : _openShift,
                                  ),
                                  SizedBox(height: compact ? 10 : 12),
                                  TextButton(
                                    onPressed: _openingShift ? null : _logout,
                                    child: Text(
                                      'الخروج من الحساب',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.70,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OpenShiftHeader extends StatelessWidget {
  const _OpenShiftHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            padding: EdgeInsets.all(compact ? 10 : 12),
            decoration: BoxDecoration(
              color: AppColors.accentGold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(compact ? 12 : 14),
              border: Border.all(
                color: AppColors.accentGold.withValues(alpha: 0.35),
              ),
            ),
            child: Icon(
              Icons.schedule_rounded,
              color: AppColors.accentGold,
              size: compact ? 24 : 28,
            ),
          ),
        ),
        SizedBox(height: compact ? 14 : 18),
        Text(
          'فتح الوردية',
          style: TextStyle(
            color: const Color(0xFFF8FAFC),
            fontSize: compact ? 22 : 24,
            fontWeight: FontWeight.bold,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'راجع رصيد الصندوق حسب النظام، ثم سجّل الجرد الفعلي قبل بدء العمل. إذا أضفت نقداً جديداً للصندوق، اكتبه في الحقل الاختياري ليظهر في سجل الوردية.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: compact ? 12.8 : 14,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

class _SystemCashCard extends StatelessWidget {
  const _SystemCashCard({required this.amount, required this.compact});

  final double amount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsetsDirectional.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: AppColors.accentGold.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(compact ? 14 : 16),
        border: Border.all(
          color: AppColors.accentGold.withValues(alpha: 0.34),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            color: AppColors.accentGold,
            size: compact ? 24 : 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'رصيد الصندوق حسب النظام',
                  style: TextStyle(
                    fontSize: compact ? 11.5 : 12.5,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      IraqiCurrencyFormat.formatInt(amount),
                      style: TextStyle(
                        fontSize: compact ? 22 : 26,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFF8FAFC),
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'د.ع',
                      style: TextStyle(
                        fontSize: compact ? 12 : 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyGlassField extends StatelessWidget {
  const _MoneyGlassField({
    required this.label,
    required this.subtitle,
    required this.hint,
    required this.controller,
    required this.keyboardType,
  });

  final String label;
  final String subtitle;
  final String hint;
  final TextEditingController controller;
  final TextInputType keyboardType;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          textAlign: TextAlign.start,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.90),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          textAlign: TextAlign.start,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.58),
            fontSize: 11,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.start,
              cursorColor: AppColors.accentGold,
              inputFormatters: [IraqiCurrencyFormat.moneyInputFormatter()],
              style: const TextStyle(
                color: Color(0xFFF8FAFC),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                hintText: hint,
                hintTextDirection: TextDirection.rtl,
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.40),
                  fontWeight: FontWeight.w500,
                ),
                suffixIcon: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 12),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      'د.ع',
                      style: TextStyle(
                        color: AppColors.accentGold.withValues(alpha: 0.88),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                contentPadding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: radius,
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.20),
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: radius,
                  borderSide: BorderSide(
                    color: AppColors.accentGold.withValues(alpha: 0.78),
                    width: 1.4,
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: radius,
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.20),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OpenShiftActionButton extends StatelessWidget {
  const _OpenShiftActionButton({
    required this.opening,
    required this.onPressed,
  });

  final bool opening;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: opening
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            )
          : const Icon(Icons.lock_open_rounded),
      label: Text(opening ? 'جاري فتح الوردية…' : 'فتح الوردية'),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accentGold,
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
    late final List<Map<String, dynamic>> eligible;
    try {
      eligible = await widget.db.listActiveUsersOrdered();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingUsers = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تحميل مستخدمي الوردية: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
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
    _displayNameCtrl.text = disp.isNotEmpty
        ? disp
        : (row['username'] as String? ?? '');
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
        const SnackBar(
          content: Text('اختر مستخدم الوردية من القائمة أو امسح البطاقة'),
        ),
      );
      return;
    }
    final row = await widget.db.getUserById(id);
    if (!mounted) return;
    if (row == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر العثور على المستخدم المختار. اختر مستخدماً آخر.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final pwd = _passwordCtrl.text;
    final salt = row['passwordSalt'] as String?;
    final hash = row['passwordHash'] as String?;
    if (salt == null || hash == null || salt.isEmpty || hash.isEmpty) {
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
    Navigator.pop(context, {'shiftStaffUserId': id, 'name': name});
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
    final inputDecoration = _dialogInputDecoration;
    final bodyStyle = TextStyle(
      fontSize: 12.5,
      height: 1.45,
      color: Colors.white.withValues(alpha: 0.76),
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 430,
            maxHeight: MediaQuery.sizeOf(context).height * 0.84,
          ),
          child: GlassSurface(
            borderRadius: const BorderRadius.all(Radius.circular(22)),
            blurSigma: 18,
            tintColor: AppGlass.surfaceTintStrong,
            strokeColor: AppGlass.stroke,
            padding: const EdgeInsetsDirectional.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.accentGold.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.accentGold.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Icon(
                        Icons.badge_outlined,
                        color: AppColors.accentGold,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'موظف الوردية',
                        style: TextStyle(
                          color: Color(0xFFF8FAFC),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'اختر الموظف المسؤول عن الصندوق في هذه الوردية، ثم أدخل كلمة مرور دخوله. سجلات البيع والصلاحيات أثناء الوردية ستُحسب على هذا الموظف.',
                  style: bodyStyle,
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_loadingUsers)
                          const Padding(
                            padding: EdgeInsets.all(18),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppColors.accentGold,
                              ),
                            ),
                          )
                        else if (_eligible.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFB4AB).withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFFFB4AB).withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                            child: const Text(
                              'لا يوجد مستخدمون نشطون في النظام. أضف مستخدماً من إدارة المستخدمين.',
                              style: TextStyle(
                                color: Color(0xFFFFDAD6),
                                fontSize: 12.5,
                                height: 1.45,
                              ),
                            ),
                          )
                        else
                          InputDecorator(
                            decoration: inputDecoration(
                              labelText: 'مستخدم الوردية',
                              prefixIcon: Icons.person_outline,
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                isExpanded: true,
                                value: _selectedUserId,
                                dropdownColor: const Color(0xFF17243A),
                                iconEnabledColor: AppColors.accentGold,
                                style: const TextStyle(
                                  color: Color(0xFFF8FAFC),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                hint: Text(
                                  'اختر مستخدماً',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.48),
                                  ),
                                ),
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
                          style: const TextStyle(color: Color(0xFFF8FAFC)),
                          decoration: inputDecoration(
                            labelText: 'الاسم الظاهر',
                            hintText: 'يُحدَّد تلقائياً',
                            prefixIcon: Icons.account_circle_outlined,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                'يمكن اختيار المستخدم عبر الكاميرا أو قارئ خارجي، ثم إدخال كلمة المرور للتأكيد.',
                                style: bodyStyle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: 'مسح بالكاميرا',
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.accentGold
                                    .withValues(alpha: 0.16),
                                foregroundColor: AppColors.accentGold,
                              ),
                              icon: const Icon(Icons.qr_code_scanner_rounded),
                              onPressed: () async {
                                final parsed = await Navigator.of(context)
                                    .push<StaffQrData>(
                                      MaterialPageRoute(
                                        fullscreenDialog: true,
                                        builder: (_) =>
                                            const StaffQrScanScreen(),
                                      ),
                                    );
                                if (parsed == null || !mounted) return;
                                await _applyParsed(parsed);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: wedgeCtrl,
                          focusNode: _wedgeFocus,
                          style: const TextStyle(color: Color(0xFFF8FAFC)),
                          decoration: inputDecoration(
                            labelText: 'قارئ خارجي',
                            hintText: 'اضغط هنا ثم امسح البطاقة',
                            prefixIcon: Icons.usb_rounded,
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
                                  content: Text(
                                    'النص المقروء ليس رمز هوية صالحاً',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordCtrl,
                          obscureText: true,
                          style: const TextStyle(color: Color(0xFFF8FAFC)),
                          cursorColor: AppColors.accentGold,
                          decoration: inputDecoration(
                            labelText: 'كلمة مرور الدخول',
                            hintText: 'كلمة مرور المستخدم المختار',
                            prefixIcon: Icons.lock_outline_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, null),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white.withValues(alpha: 0.82),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: (_loadingUsers || _eligible.isEmpty)
                            ? null
                            : _confirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accentGold,
                          foregroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('تأكيد'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dialogInputDecoration({
    required String labelText,
    String? hintText,
    IconData? prefixIcon,
  }) {
    final radius = BorderRadius.circular(14);
    final borderColor = Colors.white.withValues(alpha: 0.20);
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.58)),
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.42)),
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, color: AppColors.accentGold, size: 20),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(
          color: AppColors.accentGold.withValues(alpha: 0.78),
          width: 1.4,
        ),
      ),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: borderColor),
      ),
      contentPadding: const EdgeInsetsDirectional.symmetric(
        horizontal: 14,
        vertical: 13,
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
  final _focusPwd = FocusNode();
  bool _error = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusPwd.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusPwd.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (PasswordHashing.verify(_ctrl.text, widget.salt, widget.hash)) {
      Navigator.of(context, rootNavigator: true).pop(true);
      return;
    }
    setState(() {
      _error = true;
      _ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final base = Theme.of(context);
    final glassAuthTheme = base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        primary: AppColors.accentBlue,
        secondary: AppColors.accentGold,
        surface: AppColors.primary,
        onSurface: Colors.white,
        onSurfaceVariant: Colors.white.withValues(alpha: 0.72),
        outline: AppGlass.stroke,
      ),
      scaffoldBackgroundColor: Colors.transparent,
    );

    return Theme(
      data: glassAuthTheme,
      child: PopScope(
        canPop: false,
        child: Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          child: SizedBox(
            width: MediaQuery.sizeOf(context).width,
            height: MediaQuery.sizeOf(context).height,
            child: GlassBackground(
              backgroundImage: const AssetImage('assets/images/splash_bg.png'),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + kb),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: GlassSurface(
                        borderRadius: const BorderRadius.all(Radius.circular(16)),
                        tintColor: AppGlass.surfaceTint,
                        strokeColor: AppGlass.stroke,
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          18,
                          18,
                          18,
                          16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Center(
                              child: Container(
                                width: 46,
                                height: 3,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(2),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFB8960C),
                                      Color(0xFFFFE08A),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Icon(
                              Icons.verified_user_rounded,
                              size: 48,
                              color: AppColors.accentGold,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'متابعة الوردية',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.tajawal(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'توجد وردية مفتوحة باسم "${widget.staffName}". '
                              'أدخل كلمة مرور الموظف للمتابعة.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.tajawal(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.72),
                                height: 1.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 20),
                            AppInput(
                              label: 'كلمة مرور الموظف',
                              labelFontWeight: FontWeight.w700,
                              isRequired: true,
                              hint: 'أدخل كلمة المرور',
                              controller: _ctrl,
                              focusNode: _focusPwd,
                              useGlass: true,
                              cursorColor: Colors.white,
                              obscureText: _obscurePassword,
                              textDirection: TextDirection.ltr,
                              densePrefixConstraints: const BoxConstraints(
                                minHeight: 48,
                                minWidth: 48,
                              ),
                              prefixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'إظهار الرمز'
                                    : 'إخفاء الرمز',
                                splashRadius: 22,
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: Colors.white.withValues(alpha: 0.82),
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                              suffixIcon: Icon(
                                Icons.lock_outline_rounded,
                                color: Colors.white.withValues(alpha: 0.82),
                                size: 20,
                              ),
                              warningText: _error
                                  ? 'كلمة المرور غير صحيحة'
                                  : null,
                              onChanged: (_) => setState(() => _error = false),
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 52,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF071A36),
                                      Color(0xFF0D1F3C),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.28,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    'متابعة',
                                    style: GoogleFonts.tajawal(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () => Navigator.of(
                                context,
                                rootNavigator: true,
                              ).pop(false),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFF5C518),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: Text(
                                'تسجيل الخروج',
                                style: GoogleFonts.tajawal(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
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
