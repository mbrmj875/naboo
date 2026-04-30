import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/license_service.dart';
import 'subscription_plans_screen.dart';

class LicenseExpiredScreen extends StatefulWidget {
  const LicenseExpiredScreen({super.key, required this.state});
  final LicenseState state;

  @override
  State<LicenseExpiredScreen> createState() => _LicenseExpiredScreenState();
}

class _LicenseExpiredScreenState extends State<LicenseExpiredScreen> {
  bool _checking = false;
  final _keyCtrl = TextEditingController();
  bool _activating = false;
  String? _activateError;

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  bool get _isDeviceLimitExceeded =>
      widget.state.status == LicenseStatus.suspended &&
      (widget.state.message?.contains('الحد الأقصى') ?? false);

  bool get _isSuspended =>
      widget.state.status == LicenseStatus.suspended && !_isDeviceLimitExceeded;

  String get _title {
    if (widget.state.lockReason == LockReason.timeTamper) {
      return 'تعارض في إعدادات الوقت';
    }
    if (_isSuspended) return 'الترخيص موقوف';
    if (_isDeviceLimitExceeded) return 'تجاوز حد الأجهزة';
    return 'انتهى الاشتراك';
  }

  String get _bodyMessage {
    if (widget.state.lockReason == LockReason.timeTamper) {
      return 'تم اكتشاف تعارض في إعدادات الوقت. تواصل مع الدعم للمساعدة في إعادة التحقق.';
    }
    return widget.state.message ??
        (_isSuspended
            ? 'تم إيقاف حسابك. تواصل مع الدعم الفني.'
            : 'انتهى اشتراكك. جدّد للمتابعة.');
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_activating) return;
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() => _activateError = 'أدخل مفتاح الترخيص');
      return;
    }
    setState(() {
      _activating = true;
      _activateError = null;
    });
    final isJwt = key.split('.').length == 3;
    final result = isJwt
        ? await LicenseService.instance.activateSignedToken(key)
        : await LicenseService.instance.activateLicense(key);
    if (!mounted) return;
    setState(() => _activating = false);
    if (!result.ok) {
      setState(() => _activateError = result.message);
      return;
    }
    await LicenseService.instance.checkLicense(forceRemote: true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
                // ── الحالة الرئيسية ────────────────────────────────────
                _StatusBadge(
                  icon: _isDeviceLimitExceeded
                      ? Icons.devices_other_outlined
                      : _isSuspended
                          ? Icons.block_outlined
                          : Icons.access_time_outlined,
                  color: _isDeviceLimitExceeded
                      ? cs.tertiary
                      : _isSuspended
                          ? cs.error
                          : cs.secondary,
                  label: _title,
                ),
                const SizedBox(height: 20),

                // ── البطاقة الرئيسية ──────────────────────────────────
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.all(24),
                      child: Column(
                        children: [
                      // اسم النشاط
                      if (widget.state.businessName?.isNotEmpty == true) ...[
                        Text(
                          widget.state.businessName!,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],

                      // الرسالة
                      Text(
                        _bodyMessage,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 16),

                      // معلومات الخطة والأجهزة
                      if (widget.state.plan != null) ...[
                        _InfoRow(
                          icon:  Icons.inventory_2_outlined,
                          label: 'خطتك الحالية',
                          value: widget.state.plan!.nameAr,
                          valueColor: cs.onSurface,
                        ),
                        if (!widget.state.isUnlimited)
                          _InfoRow(
                            icon:  Icons.devices_outlined,
                            label: 'الأجهزة المسجّلة',
                            value: widget.state.devicesInfo,
                            valueColor: _isDeviceLimitExceeded
                                ? cs.tertiary
                                : cs.onSurface,
                          ),
                      ],

                      // تاريخ الانتهاء
                      if (widget.state.expiresAt != null || widget.state.trialEndsAt != null)
                        _InfoRow(
                          icon:  Icons.calendar_today_outlined,
                          label: widget.state.expiresAt != null
                              ? 'انتهاء الاشتراك'
                              : 'انتهاء التجربة',
                          value: _fmtDate(
                            widget.state.expiresAt ?? widget.state.trialEndsAt,
                          ),
                          valueColor: cs.error,
                        ),

                      const SizedBox(height: 20),
                      Divider(color: cs.outlineVariant),
                      const SizedBox(height: 16),

                      // ── خيارات الترقية / التجديد ─────────────────────

                      // زر عرض خطط الاشتراك
                      if (!_isSuspended) ...[
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            icon: const Icon(Icons.upgrade_outlined),
                            label: Text(
                              _isDeviceLimitExceeded
                                  ? 'ترقية الخطة لإضافة أجهزة'
                                  : 'تجديد الاشتراك',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SubscriptionPlansScreen(
                                  currentPlan: widget.state.plan,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // عرض مقارنة الخطط
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.compare_arrows_outlined, size: 18),
                            label: const Text('مقارنة خطط الاشتراك'),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SubscriptionPlansScreen(
                                  currentPlan: widget.state.plan,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ── إدخال مفتاح جديد (Legacy أو JWT) ─────────────────
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          'إدخال مفتاح جديد',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _keyCtrl,
                        textDirection: TextDirection.ltr,
                        maxLines: 3,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: 'NABOO-XXXX-XXXX-XXXX أو JWT',
                          errorText: _activateError,
                        ),
                        onChanged: (_) => setState(() => _activateError = null),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[a-zA-Z0-9\-\._]'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _activating ? null : _activate,
                          child: _activating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('تفعيل'),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // زر إعادة التحقق
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: _checking
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_outlined, size: 18),
                          label: const Text('إعادة التحقق'),
                          onPressed: _checking
                              ? null
                              : () async {
                                  setState(() => _checking = true);
                                  await LicenseService.instance
                                      .checkLicense(forceRemote: true);
                                  if (mounted) setState(() => _checking = false);
                                },
                        ),
                      ),

                      const SizedBox(height: 8),

                      // تغيير المفتاح
                      TextButton.icon(
                        icon: const Icon(Icons.vpn_key_outlined,
                            size: 16),
                        label: const Text(
                          'استخدام مفتاح آخر',
                          style: TextStyle(fontSize: 12),
                        ),
                        onPressed: () async =>
                            LicenseService.instance.deactivate(),
                      ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                Text(
                  'NaBoo v2.0 — جميع الحقوق محفوظة',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── مكونات مساعدة ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color    color;
  final String   label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.3), width: 2),
          ),
          child: Icon(icon, color: color, size: 36),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor = Colors.white,
  });
  final IconData icon;
  final String   label;
  final String   value;
  final Color    valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
