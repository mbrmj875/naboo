import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../navigation/app_root_navigator_key.dart';
import '../providers/auth_provider.dart';
import '../services/auth/auth_network_guard.dart';
import '../services/auth/cloud_session_link_state.dart';
import '../theme/design_tokens.dart';
import 'glass/glass_background.dart';
import 'glass/glass_surface.dart';

/// حاجز إعادة ربط السحابة — نفس لغة شاشات الدخول (كحلي + ذهب + زجاج).
/// لا يمسح البيانات. ينقل إلى شاشة الدخول فقط حيث لا توجد استعادة Google صامتة.
class CloudReconnectGate extends StatefulWidget {
  const CloudReconnectGate({super.key});

  @override
  State<CloudReconnectGate> createState() => _CloudReconnectGateState();
}

class _CloudReconnectGateState extends State<CloudReconnectGate> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    final link = CloudSessionLinkController.instance;
    final width = MediaQuery.sizeOf(context).width;
    final maxCard = width >= 720 ? 440.0 : 520.0;

    return Material(
      color: AppColors.primary,
      child: GlassBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 24, 20, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxCard),
                child: GlassSurface(
                  padding: const EdgeInsetsDirectional.fromSTEB(22, 26, 22, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        color: AppColors.accentGold,
                        size: 36,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'انقطع ربط الحساب بالسحابة',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: width < 640 ? 20 : 22,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'بيانات المحل على هذا الجهاز محفوظة ولن تُمسح. '
                        'أعد الربط للمتابعة حتى تعود مزامنة الأجهزة '
                        'وواتساب البطاقات.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFCBD5E1),
                          height: 1.45,
                          fontSize: 14,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFFCA5A5),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accentGold,
                          foregroundColor: AppColors.primaryDark,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: link.reconnecting
                            ? null
                            : () => _reconnect(context),
                        child: link.reconnecting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('إعادة الربط'),
                      ),
                      // يظهر على كل المنصات: بلا زر متابعة، صاحب حساب البريد يحتاجه.
                      ...[
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: link.reconnecting
                              ? null
                              : _signInAgainWithEmail,
                          child: const Text(
                            'الدخول بالبريد ورمز PIN',
                            style: TextStyle(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signInAgainWithEmail() async {
    final link = CloudSessionLinkController.instance;
    link.continueLocally();
    try {
      await appRootNavigatorKey.currentState?.pushNamed('/login');
    } finally {
      // رجع من شاشة الدخول دون ربط: يعود الحاجز.
      link.endEmailSignInDetour();
    }
  }

  Future<void> _reconnect(BuildContext context) async {
    final link = CloudSessionLinkController.instance;
    final auth = context.read<AuthProvider>();
    link.setReconnecting(true);
    setState(() => _error = null);
    try {
      final ok = await auth.ensureCloudSessionActive(
        allowInteractiveGoogle: true,
      );
      if (!mounted) return;
      if (ok) {
        link.markConnected();
        return;
      }
      link.markLocked();
      if (!await AuthNetworkGuard.hasNetworkLink()) {
        link.setOffline(true);
        return;
      }
      if (!mounted) return;
      setState(() {
        _error =
            auth.lastCloudReconnectError ??
            'لم يكتمل الربط. أعد المحاولة وأكمل الدخول بحساب Google الخاص بالمتجر.';
      });
    } finally {
      if (link.reconnecting) link.setReconnecting(false);
    }
  }
}

/// شريط ثابت: الجلسة مفقودة والإنترنت مقطوع. البيع مستمر حتى عودة الشبكة.
class CloudOfflineLockedBanner extends StatelessWidget {
  const CloudOfflineLockedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: Color(0xFF991B1B),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
          child: Text(
            'الحساب منفصل عن السحابة ولا يوجد إنترنت. البيع يُحفظ على الجهاز، '
            'وستُطلب إعادة الربط عند عودة الإنترنت.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// شريط رفيع — فشل مؤقت. لا يحجب العمل.
class CloudDegradedBanner extends StatelessWidget {
  const CloudDegradedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: Color(0xFF92400E),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
          child: Text(
            'السحابة غير مستقرة — نعيد المحاولة. البيع المحلي مستمر.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
