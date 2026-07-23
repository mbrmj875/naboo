import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../theme/design_tokens.dart';
import '../../../utils/screen_layout.dart';
import '../models/tenant_whatsapp_gateway_record.dart';
import '../services/oil_change_whatsapp_gateway_repository.dart';
import '../services/oil_change_whatsapp_gateway_service.dart';
import '../services/oil_change_whatsapp_status_store.dart';
import '../widgets/oil_change_form_theme.dart';
import '../widgets/oil_change_owner_pin_confirm_dialog.dart';

/// شاشة ربط واتساب المحل عبر QR — مرة واحدة لكل حساب (كل المستخدمين).
class OilChangeWhatsappConnectScreen extends StatefulWidget {
  const OilChangeWhatsappConnectScreen({super.key});

  @override
  State<OilChangeWhatsappConnectScreen> createState() =>
      _OilChangeWhatsappConnectScreenState();
}

class _OilChangeWhatsappConnectScreenState
    extends State<OilChangeWhatsappConnectScreen> {
  bool _loading = true;
  bool _busy = false;
  /// عند true تُعرض لوحة QR؛ وإلا شاشة «غير متصل» مع زر بدء الربط.
  bool _showConnectFlow = false;
  String? _error;
  TenantWhatsappGatewayRecord? _record;
  String? _qrBase64;
  String? _pairingCode;
  Timer? _pollTimer;
  Timer? _qrRefreshTimer;

  bool get _connected => _record?.isConnected == true;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _qrRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (Supabase.instance.client.auth.currentUser == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'سجّل الدخول للحساب السحابي (Google) أولاً.';
      });
      return;
    }

    await OilChangeWhatsappGatewayService.instance.provision();
    _record = await OilChangeWhatsappGatewayRepository.instance
        .refreshStatusFromServer();

    if (_record?.isConnected == true) {
      await OilChangeWhatsappStatusStore.instance.markConnected();
      _pollTimer?.cancel();
      _showConnectFlow = false;
      _qrBase64 = null;
      _pairingCode = null;
    } else {
      await OilChangeWhatsappStatusStore.instance.markDisconnectedLocalOnly();
      _showConnectFlow = false;
      _qrBase64 = null;
      _pairingCode = null;
      _pollTimer?.cancel();
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _startConnectFlow() async {
    setState(() {
      _busy = true;
      _error = null;
      _showConnectFlow = true;
      _qrBase64 = null;
      _pairingCode = null;
    });
    try {
      // تحقق أولاً — إن الجلسة المركزية متصلة لا تفصلها بـ force_reset.
      final status =
          await OilChangeWhatsappGatewayService.instance.checkStatus();
      if (status.ok && status.connected) {
        await OilChangeWhatsappStatusStore.instance.markConnected();
        _record = await OilChangeWhatsappGatewayRepository.instance
            .fetchForCurrentUser();
        if (!mounted) return;
        setState(() {
          _showConnectFlow = false;
          _qrBase64 = null;
          _pairingCode = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'واتساب المحل متصل مسبقاً على السيرفر — لا حاجة لإعادة QR من هذا الجهاز',
            ),
          ),
        );
        return;
      }
      // جلسة مغلقة: اجلب QR بدون logout إجباري أولاً.
      await _loadQr(forceReset: false);
      _startPolling();
      _startQrAutoRefresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadQr({bool forceReset = false}) async {
    final qr = await OilChangeWhatsappGatewayService.instance.fetchQr(
      forceReset: forceReset,
    );
    if (!mounted) return;

    if (qr.alreadyConnected) {
      _pollTimer?.cancel();
      _qrRefreshTimer?.cancel();
      await OilChangeWhatsappStatusStore.instance.markConnected();
      _record = await OilChangeWhatsappGatewayRepository.instance
          .refreshStatusFromServer();
      if (!mounted) return;
      setState(() {
        _showConnectFlow = false;
        _qrBase64 = null;
        _pairingCode = null;
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('واتساب المحل متصل — لم تُفصل الجلسة')),
      );
      return;
    }

    setState(() {
      _qrBase64 = qr.base64;
      _pairingCode = qr.pairingCode;
      if (!qr.ok && (_qrBase64 == null || _qrBase64!.isEmpty)) {
        _error = (qr.messageAr ?? '').trim().isNotEmpty
            ? qr.messageAr
            : 'تعذّر جلب رمز QR. اضغط «تحديث رمز QR» أو تحقق من الإنترنت.';
      } else {
        _error = null;
      }
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_pollStatus());
    });
  }

  /// الرمز ينتهي خلال أقل من دقيقة — جدّده تلقائياً.
  void _startQrAutoRefresh() {
    _qrRefreshTimer?.cancel();
    _qrRefreshTimer = Timer.periodic(const Duration(seconds: 40), (_) {
      if (!_showConnectFlow || _connected || _busy) return;
      unawaited(_loadQr());
    });
  }

  Future<void> _pollStatus() async {
    final result =
        await OilChangeWhatsappGatewayService.instance.checkStatus();
    if (!mounted) return;
    if (result.ok && result.connected) {
      _pollTimer?.cancel();
      _qrRefreshTimer?.cancel();
      await OilChangeWhatsappStatusStore.instance.markConnected();
      _record = await OilChangeWhatsappGatewayRepository.instance
          .fetchForCurrentUser();
      setState(() {
        _showConnectFlow = false;
        _qrBase64 = null;
        _pairingCode = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم ربط واتساب المحل بنجاح')),
      );
    }
  }

  Future<void> _relinkWithPin() async {
    final confirmed = await confirmOwnerPinForWhatsappAction(
      context,
      title: 'إعادة ربط واتساب',
      message:
          'سيتم أولاً إلغاء الربط الحالي على السيرفر (كل الأجهزة)، '
          'ثم عرض QR لرقم جديد أو نفس الرقم.\n'
          'لا تستخدم هذا عند فتح حاسوب ثانٍ — الربط مرة واحدة للحساب.\n\n'
          'أدخل رمز PIN للمالك (4 أرقام) للمتابعة.',
      confirmLabel: 'فصل ثم QR جديد',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _showConnectFlow = true;
      _qrBase64 = null;
      _pairingCode = null;
    });
    try {
      // المسار الآمن: disconnect ثم QR — لا force_reset والجلسة ما زالت open.
      final disconnected =
          await OilChangeWhatsappStatusStore.instance.disconnectGateway();
      if (!disconnected.ok) {
        if (!mounted) return;
        setState(() {
          _showConnectFlow = false;
          _error =
              'تعذّر إلغاء الربط قبل إعادة المسح. تحقق من الإنترنت ثم أعد المحاولة.';
        });
        return;
      }
      await OilChangeWhatsappStatusStore.instance.markDisconnectedLocalOnly();
      _record = await OilChangeWhatsappGatewayRepository.instance
          .fetchForCurrentUser();
      // بعد الفصل: اجلب QR بدون force_reset إضافي (السيرفر يصفّر فقط عند الحاجة).
      await _loadQr(forceReset: false);
      if (_connected) return;
      _startPolling();
      _startQrAutoRefresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnectWithPin() async {
    final phone = (_record?.whatsappPhone ?? '').trim();
    final confirmed = await confirmOwnerPinForWhatsappAction(
      context,
      title: 'إلغاء ربط واتساب المحل',
      message:
          'سيتم فصل جلسة واتساب المحل عن هذا الجهاز.\n'
          'يتوقف الإرسال التلقائي على كل الأجهزة حتى إعادة الربط.\n'
          '${phone.isEmpty ? '' : 'الرقم الحالي: $phone\n'}'
          'أدخل رمز PIN للمالك (4 أرقام) للتأكيد.',
      confirmLabel: 'إلغاء الربط',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await OilChangeWhatsappStatusStore.instance.disconnectGateway();
      _pollTimer?.cancel();
      _qrRefreshTimer?.cancel();
      _record = await OilChangeWhatsappGatewayRepository.instance
          .fetchForCurrentUser();
      // إن بقيت السحابة «متصل» رغم نجاح البلاغ المحلي — اعرض غير متصل فوراً.
      if (result.ok && (_record?.isConnected ?? false)) {
        final name = (_record?.evolutionInstanceName ?? '').trim();
        _record = TenantWhatsappGatewayRecord(
          evolutionInstanceName: name,
          status: TenantWhatsappGatewayStatus.disconnected,
          whatsappPhone: null,
          updatedAt: DateTime.now().toUtc(),
        );
      }
      if (!mounted) return;
      setState(() {
        _qrBase64 = null;
        _pairingCode = null;
        _showConnectFlow = false;
      });

      final String snack;
      if (!result.ok) {
        snack =
            'تعذّر إلغاء الربط. تحقق من الإنترنت ثم حاول مرة أخرى.';
      } else if (result.usedStatusFallback && !result.evolutionLoggedOut) {
        snack =
            'تم إيقاف إرسال واتساب على الحساب. إن بقي الرقم مرتبطاً افصله من واتساب ← الأجهزة المرتبطة.';
      } else {
        snack = 'تم إلغاء ربط واتساب المحل';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(snack)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final layout = context.screenLayout;

    return Theme(
      data: OilChangeFormTheme.wrap(context, Theme.of(context)),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: OilChangeFormTheme.appBar(
          context: context,
          title: 'ربط واتساب المحل',
          actions: [
            if (!_loading)
              IconButton(
                tooltip: 'تحديث الحالة',
                onPressed: _busy ? null : () => unawaited(_bootstrap()),
                icon: const Icon(Icons.refresh_rounded),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : AbsorbPointer(
                absorbing: _busy,
                child: ListView(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    layout.pageHorizontalGap,
                    16,
                    layout.pageHorizontalGap,
                    28,
                  ),
                  children: [
                    if (_error != null) ...[
                      _ErrorCard(
                        message: _error!,
                        onRetry: () => unawaited(_bootstrap()),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_busy)
                      const Padding(
                        padding: EdgeInsetsDirectional.only(bottom: 16),
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                    if (_connected)
                      _ConnectedPanel(
                        phone: _record?.whatsappPhone,
                        onDisconnect: () => unawaited(_disconnectWithPin()),
                        onRelink: () => unawaited(_relinkWithPin()),
                      )
                    else if (_showConnectFlow)
                      _ConnectingPanel(
                        qrBase64: _qrBase64,
                        pairingCode: _pairingCode,
                        onRefreshQr: () => unawaited(_loadQr(forceReset: false)),
                        onCancel: () {
                          _pollTimer?.cancel();
                          _qrRefreshTimer?.cancel();
                          setState(() {
                            _showConnectFlow = false;
                            _qrBase64 = null;
                            _pairingCode = null;
                          });
                        },
                      )
                    else
                      _DisconnectedIdlePanel(
                        onStart: () => unawaited(_startConnectFlow()),
                      ),
                    const SizedBox(height: 20),
                    const _InfoTipsCard(),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.errorContainer.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 10, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: cs.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: cs.onErrorContainer, height: 1.4),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('إعادة')),
          ],
        ),
      ),
    );
  }
}

class _ConnectedPanel extends StatelessWidget {
  const _ConnectedPanel({
    required this.phone,
    required this.onDisconnect,
    required this.onRelink,
  });

  final String? phone;
  final VoidCallback onDisconnect;
  final VoidCallback onRelink;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final phoneText = (phone ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [
                const Color(0xFF00C853).withValues(alpha: 0.14),
                AppColors.primary.withValues(alpha: 0.08),
              ],
            ),
            border: Border.all(
              color: const Color(0xFF00C853).withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00C853).withValues(alpha: 0.18),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 40,
                  color: Color(0xFF00C853),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'واتساب المحل متصل',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: OilChangeFormTheme.emphasisText(context),
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'كل أجهزة الحساب (حاسوب/هاتف) تستخدم نفس الجلسة على السيرفر.\n'
                'فتح التطبيق من جهاز آخر لا يتطلب إعادة QR — ولا يجب إعادة الربط.',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              if (phoneText.isNotEmpty) ...[
                const SizedBox(height: 16),
                _MetaChip(
                  icon: Icons.phone_rounded,
                  label: phoneText,
                  ltr: true,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onRelink,
          icon: const Icon(Icons.qr_code_2_rounded),
          label: const Text('فصل ثم ربط برقم/QR جديد'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: AppColors.primary,
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onDisconnect,
          icon: Icon(Icons.link_off_rounded, color: cs.error),
          label: Text(
            'إلغاء الربط',
            style: TextStyle(
              color: cs.error,
              fontWeight: FontWeight.w700,
            ),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            side: BorderSide(color: cs.error.withValues(alpha: 0.55)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'إلغاء الربط وفصل الجلسة يتطلبان رمز PIN للمالك.',
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant,
            height: 1.35,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.ltr = false,
  });

  final IconData icon;
  final String label;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: OilChangeFormTheme.gold),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DisconnectedIdlePanel extends StatelessWidget {
  const _DisconnectedIdlePanel({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.error.withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.link_off_rounded,
                  size: 36,
                  color: cs.error,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'واتساب المحل غير متصل',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: OilChangeFormTheme.emphasisText(context),
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'لن يُرسل التطبيق إشعارات واتساب تلقائياً حتى تربط رقم المحل.',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.qr_code_2_rounded),
          label: const Text('بدء الربط (مسح QR)'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

class _ConnectingPanel extends StatelessWidget {
  const _ConnectingPanel({
    required this.qrBase64,
    required this.pairingCode,
    required this.onRefreshQr,
    required this.onCancel,
  });

  final String? qrBase64;
  final String? pairingCode;
  final VoidCallback onRefreshQr;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasQr = qrBase64 != null && qrBase64!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'امسح الرمز من واتساب المحل',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: 8),
        Text(
          'واتساب → الأجهزة المرتبطة → ربط جهاز → امسح QR أدناه.\n'
          'الرمز ينتهي خلال أقل من دقيقة — إن فشل المسح اضغط «تحديث رمز QR».',
          style: TextStyle(color: cs.onSurfaceVariant, height: 1.45),
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: 18),
        Material(
          color: Colors.white,
          elevation: 2,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (hasQr)
                  Image.memory(
                    base64Decode(
                      qrBase64!.contains(',')
                          ? qrBase64!.split(',').last
                          : qrBase64!,
                    ),
                    width: 260,
                    height: 260,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      size: 120,
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: CircularProgressIndicator(),
                  ),
                if (_displayPairing != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'رمز الربط: $_displayPairing',
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: onRefreshQr,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('تحديث رمز QR'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            foregroundColor: OilChangeFormTheme.gold,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onCancel,
          child: const Text('إلغاء وعودة'),
        ),
      ],
    );
  }

  String? get _displayPairing {
    final t = (pairingCode ?? '').trim();
    if (t.length < 4 || t.length > 16) return null;
    if (t.contains('@') || t.contains(',')) return null;
    return t;
  }
}

class _InfoTipsCard extends StatelessWidget {
  const _InfoTipsCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tips = const [
      'الربط مرة واحدة فقط للحساب على السيرفر — الحاسوب الثاني لا يحتاج QR جديد.',
      'لا تضغط «إعادة الربط» على جهاز آخر: ذلك يفصل واتساب عن كل الأجهزة.',
      'أغلق واتساب ويب على المتصفح إن وُجد، واترك جلسة نابو فقط في الأجهزة المرتبطة.',
      'إلغاء الربط أو إعادة الربط يتطلب رمز PIN للمالك.',
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: OilChangeFormTheme.gold.withValues(alpha: 0.08),
        border: Border.all(
          color: OilChangeFormTheme.gold.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: OilChangeFormTheme.gold),
              const SizedBox(width: 8),
              Text(
                'ملاحظات مهمة',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: OilChangeFormTheme.emphasisText(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final tip in tips) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: TextStyle(color: cs.onSurfaceVariant)),
                Expanded(
                  child: Text(
                    tip,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}
