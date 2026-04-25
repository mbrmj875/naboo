import 'package:flutter/material.dart';

/// يُعرض عندما يكون هذا الجهاز مفصولاً من الحساب (فصل من جهاز آخر).
class DeviceRevokedScreen extends StatelessWidget {
  const DeviceRevokedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF1E3A5F),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'NaBoo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 28),
                Icon(
                  Icons.phonelink_erase_rounded,
                  size: 72,
                  color: Colors.red.shade300,
                ),
                const SizedBox(height: 24),
                const Text(
                  'تم إزالة هذا الجهاز من الحساب',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'لا يمكنك تسجيل الدخول من هذا الجهاز حتى يوافق أحد الأجهزة '
                  'المفعّلة على نفس الحساب من الإعدادات ← الحساب والاشتراك ← «السماح بالعودة».',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    height: 1.45,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('العودة لتسجيل الدخول'),
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
