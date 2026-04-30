import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/license_service.dart';
import 'license_expired_screen.dart';

/// بوابة الترخيص — تُعرض بدلاً من التطبيق إذا لم يكن الترخيص صالحاً.
/// إذا كان صالحاً تُعرض [child].
class LicenseGate extends StatefulWidget {
  const LicenseGate({super.key, required this.child});

  final Widget child;

  @override
  State<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends State<LicenseGate> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LicenseService>.value(
      value: LicenseService.instance,
      child: Consumer<LicenseService>(
        builder: (context, lic, _) {
          switch (lic.state.status) {
            case LicenseStatus.checking:
              return const _CheckingScreen();

            case LicenseStatus.none:
              return widget.child;

            case LicenseStatus.trial:
            case LicenseStatus.active:
              return widget.child;

            case LicenseStatus.restricted:
            case LicenseStatus.pendingLock:
              // سيتم ربط البانر/الحالة لاحقاً ضمن RestrictedMode + ExpiredPendingLock.
              // الآن نُبقي الدخول متاحاً حتى لا نكسر v1.
              return widget.child;

            case LicenseStatus.expired:
            case LicenseStatus.suspended:
              return LicenseExpiredScreen(state: lic.state);

            case LicenseStatus.offline:
              // إذا كان الكاش يقول نشط → اسمح بالدخول مع تحذير
              return _OfflineWarningWrapper(child: widget.child);
          }
        },
      ),
    );
  }
}

// ── شاشة التحميل ─────────────────────────────────────────────────────────────

class _CheckingScreen extends StatelessWidget {
  const _CheckingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF1E3A5F),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'NaBoo',
              style: TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'نظام إدارة المتاجر',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            SizedBox(height: 32),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'جارٍ التحقق من الترخيص…',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ── شاشة تحذير عدم الاتصال ────────────────────────────────────────────────────

class _OfflineWarningWrapper extends StatefulWidget {
  const _OfflineWarningWrapper({required this.child});
  final Widget child;

  @override
  State<_OfflineWarningWrapper> createState() => _OfflineWarningWrapperState();
}

class _OfflineWarningWrapperState extends State<_OfflineWarningWrapper> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return widget.child;
    return Scaffold(
      backgroundColor: const Color(0xFF1E3A5F),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_outlined,
                size: 56,
                color: Colors.orange,
              ),
              const SizedBox(height: 16),
              const Text(
                'لا يوجد اتصال بالإنترنت',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'يعمل التطبيق بآخر بيانات ترخيص محفوظة.\nتأكد من الاتصال في أقرب فرصة.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A5F),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    await LicenseService.instance.checkLicense(
                      forceRemote: true,
                    );
                    if (mounted) setState(() => _dismissed = true);
                  },
                  child: const Text('إعادة المحاولة'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _dismissed = true),
                child: const Text('الدخول بدون اتصال'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
