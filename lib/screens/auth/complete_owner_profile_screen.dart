import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../services/cloud_sync_service.dart' show kDeviceAccessRevokedCode;
import '../../providers/auth_provider.dart';
import '../../providers/business_features_provider.dart';
import '../../theme/design_tokens.dart';
import '../../utils/auth_validators.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/inputs/app_input.dart';
import '../../widgets/inputs/pin_four_boxes_field.dart';
import '../../widgets/secure_screen.dart';

/// يكمّل بيانات المالك بعد OAuth Google (جوال + PIN) قبل bootstrap.
class CompleteOwnerProfileScreen extends StatefulWidget {
  const CompleteOwnerProfileScreen({super.key});

  @override
  State<CompleteOwnerProfileScreen> createState() =>
      _CompleteOwnerProfileScreenState();
}

class _CompleteOwnerProfileScreenState extends State<CompleteOwnerProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  final _focusPhone = FocusNode();
  final _focusPin = FocusNode();
  final _focusConfirmPin = FocusNode();

  bool _busy = false;
  bool _obscurePin = true;
  bool _obscureConfirmPin = true;
  bool _blurredPhone = false;
  bool _blurredPin = false;
  bool _blurredConfirmPin = false;
  Future<void>? _sessionPrimeFuture;

  static const Color _gold = AppColors.accentGold;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sessionPrimeFuture = context
          .read<AuthProvider>()
          .ensureSupabaseSessionForOwnerProfileCompletion(
            allowInteractiveGoogle: false,
          );
      unawaited(_sessionPrimeFuture);
    });
    _focusPhone.addListener(() {
      if (!_focusPhone.hasFocus && mounted) {
        setState(() => _blurredPhone = true);
      }
    });
    _focusPin.addListener(() {
      if (!_focusPin.hasFocus && mounted) {
        setState(() => _blurredPin = true);
      }
    });
    _focusConfirmPin.addListener(() {
      if (!_focusConfirmPin.hasFocus && mounted) {
        setState(() => _blurredConfirmPin = true);
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    _focusPhone.dispose();
    _focusPin.dispose();
    _focusConfirmPin.dispose();
    super.dispose();
  }

  bool _iraqMobileOk(String raw) => AuthValidators.isValidIraqiPhone(raw);

  String? _validatePhone(String? value) {
    if (!_blurredPhone) return null;
    final t = (value ?? '').trim();
    if (t.isEmpty) return 'هذا الحقل مطلوب';
    if (!_iraqMobileOk(t)) {
      return 'أدخل رقم جوال عراقي صحيح (11 رقماً يبدأ بـ 07)';
    }
    return null;
  }

  String? _validatePin(String? value) {
    if (!_blurredPin) return null;
    final t = (value ?? '').trim();
    if (t.isEmpty) return 'هذا الحقل مطلوب';
    if (!AuthValidators.isValidPin(t)) {
      return 'رمز PIN يجب أن يكون 4 أرقام';
    }
    return null;
  }

  String? _validateConfirmPin(String? value) {
    if (!_blurredConfirmPin) return null;
    final t = (value ?? '').trim();
    if (t.isEmpty) return 'هذا الحقل مطلوب';
    if (t != _pinController.text.trim()) {
      return 'رمز PIN غير مطابق';
    }
    return null;
  }

  Future<void> _submit() async {
    setState(() {
      _blurredPhone = true;
      _blurredPin = true;
      _blurredConfirmPin = true;
    });
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final prime = _sessionPrimeFuture;
    if (prime != null) {
      try {
        await prime.timeout(const Duration(seconds: 20));
      } catch (_) {}
    }

    final err = await auth.completeGoogleOwnerProfile(
      phone: _phoneController.text.trim(),
      pin: _pinController.text.trim(),
    );
    if (!mounted) return;
    if (err != null) {
      setState(() => _busy = false);
      if (err == kDeviceAccessRevokedCode) {
        unawaited(nav.pushReplacementNamed('/device-access-revoked'));
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final target = await auth.resolveRouteAfterOwnerProfileCompletion();
      if (!mounted) return;
      try {
        await context.read<BusinessFeaturesProvider>().refresh();
      } catch (_) {}
      if (!mounted) return;
      unawaited(nav.pushReplacementNamed(target));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SecureScreen(
      child: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            brightness: Brightness.dark,
            primary: AppColors.accentBlue,
            onSurface: Colors.white,
          ),
          scaffoldBackgroundColor: Colors.transparent,
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Text(
              'إكمال الحساب',
              style: GoogleFonts.tajawal(
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            centerTitle: true,
          ),
          body: GlassBackground(
            backgroundImage: const AssetImage('assets/images/splash_bg.png'),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    20,
                    12,
                    20,
                    24 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: GlassSurface(
                      borderRadius: const BorderRadius.all(Radius.circular(16)),
                      tintColor: AppGlass.surfaceTint,
                      strokeColor: AppGlass.stroke,
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        18,
                        20,
                        18,
                        18,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'أكمل بياناتك',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.tajawal(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'أدخل رقم جوالك ورمز PIN للدخول اليومي في التطبيق',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.tajawal(
                                fontSize: 14,
                                height: 1.5,
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
                            ),
                            const SizedBox(height: 22),
                            AppInput(
                              label: 'رقم الجوال',
                              labelFontWeight: FontWeight.w700,
                              isRequired: true,
                              hint: '07xxxxxxxxx',
                              controller: _phoneController,
                              focusNode: _focusPhone,
                              useGlass: true,
                              cursorColor: Colors.white,
                              keyboardType: TextInputType.phone,
                              textDirection: TextDirection.ltr,
                              textInputAction: TextInputAction.next,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(11),
                              ],
                              onFieldSubmitted: (_) =>
                                  FocusScope.of(context).requestFocus(_focusPin),
                              validator: _validatePhone,
                            ),
                            const SizedBox(height: 14),
                            PinFourBoxesField(
                              useGlass: true,
                              controller: _pinController,
                              focusNode: _focusPin,
                              label: 'رمز PIN *',
                              obscureText: _obscurePin,
                              onToggleObscure: () =>
                                  setState(() => _obscurePin = !_obscurePin),
                              textInputAction: TextInputAction.next,
                              onCompleted: (_) => FocusScope.of(context)
                                  .requestFocus(_focusConfirmPin),
                              onEditingComplete: () => FocusScope.of(context)
                                  .requestFocus(_focusConfirmPin),
                              validator: _validatePin,
                            ),
                            const SizedBox(height: 14),
                            PinFourBoxesField(
                              useGlass: true,
                              controller: _confirmPinController,
                              focusNode: _focusConfirmPin,
                              label: 'تأكيد رمز PIN *',
                              obscureText: _obscureConfirmPin,
                              onToggleObscure: () => setState(
                                () => _obscureConfirmPin = !_obscureConfirmPin,
                              ),
                              textInputAction: TextInputAction.done,
                              onCompleted: (_) {
                                if (!_busy) unawaited(_submit());
                              },
                              onEditingComplete: () {
                                if (!_busy) unawaited(_submit());
                              },
                              validator: _validateConfirmPin,
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _busy ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _gold,
                                  foregroundColor: Colors.black,
                                  disabledBackgroundColor:
                                      _gold.withValues(alpha: 0.45),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _busy
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.black,
                                        ),
                                      )
                                    : Text(
                                        'متابعة',
                                        style: GoogleFonts.tajawal(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
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
            ),
          ),
        ),
      ),
    );
  }
}
