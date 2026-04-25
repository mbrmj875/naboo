import 'package:flutter/material.dart';

import '../../services/license_service.dart';
import 'subscription_plans_screen.dart';

const Color _kAccent = Color(0xFF1E3A5F);

class LicenseExpiredScreen extends StatefulWidget {
  const LicenseExpiredScreen({super.key, required this.state});
  final LicenseState state;

  @override
  State<LicenseExpiredScreen> createState() => _LicenseExpiredScreenState();
}

class _LicenseExpiredScreenState extends State<LicenseExpiredScreen> {
  bool _checking = false;

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  bool get _isDeviceLimitExceeded =>
      widget.state.status == LicenseStatus.suspended &&
      (widget.state.message?.contains('الحد الأقصى') ?? false);

  bool get _isSuspended =>
      widget.state.status == LicenseStatus.suspended && !_isDeviceLimitExceeded;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1B2A),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
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
                      ? Colors.orange
                      : _isSuspended
                          ? Colors.red
                          : Colors.amber,
                  label: _isDeviceLimitExceeded
                      ? 'تجاوز حد الأجهزة'
                      : _isSuspended
                          ? 'الترخيص موقوف'
                          : 'انتهى الاشتراك',
                ),
                const SizedBox(height: 20),

                // ── البطاقة الرئيسية ──────────────────────────────────
                Container(
                  width: 460,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      // اسم النشاط
                      if (widget.state.businessName?.isNotEmpty == true) ...[
                        Text(
                          widget.state.businessName!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],

                      // الرسالة
                      Text(
                        widget.state.message ??
                            (_isSuspended
                                ? 'تم إيقاف حسابك. تواصل مع الدعم الفني.'
                                : 'انتهى اشتراكك. جدّد للمتابعة.'),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
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
                          valueColor: Colors.white,
                        ),
                        if (!widget.state.isUnlimited)
                          _InfoRow(
                            icon:  Icons.devices_outlined,
                            label: 'الأجهزة المسجّلة',
                            value: widget.state.devicesInfo,
                            valueColor: _isDeviceLimitExceeded
                                ? Colors.orange
                                : Colors.white,
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
                          valueColor: Colors.red.shade300,
                        ),

                      const SizedBox(height: 20),
                      Divider(color: Colors.white.withOpacity(0.1)),
                      const SizedBox(height: 16),

                      // ── خيارات الترقية / التجديد ─────────────────────

                      // زر عرض خطط الاشتراك
                      if (!_isSuspended) ...[
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _kAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
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
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: BorderSide(color: Colors.white.withOpacity(0.2)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
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

                      // زر إعادة التحقق
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white54,
                            side: BorderSide(color: Colors.white.withOpacity(0.15)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: _checking
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white54,
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
                            size: 16, color: Colors.white38),
                        label: const Text(
                          'استخدام مفتاح آخر',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                        onPressed: () async =>
                            LicenseService.instance.deactivate(),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                Text(
                  'NaBoo v2.0 — جميع الحقوق محفوظة',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.2),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white38),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
