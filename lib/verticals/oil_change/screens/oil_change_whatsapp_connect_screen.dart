import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../utils/screen_layout.dart';
import '../models/tenant_whatsapp_gateway_record.dart';
import '../services/oil_change_whatsapp_gateway_repository.dart';
import '../services/oil_change_whatsapp_gateway_service.dart';
import '../services/oil_change_whatsapp_status_store.dart';
import '../widgets/oil_change_form_theme.dart';

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
  String? _error;
  TenantWhatsappGatewayRecord? _record;
  String? _qrBase64;
  String? _pairingCode;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
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
    } else {
      await _loadQr();
      _startPolling();
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadQr() async {
    final qr = await OilChangeWhatsappGatewayService.instance.fetchQr();
    if (!mounted) return;
    setState(() {
      _qrBase64 = qr.base64;
      _pairingCode = qr.pairingCode;
      if (!qr.ok && (_qrBase64 == null || _qrBase64!.isEmpty)) {
        _error = 'تعذّر جلب رمز QR — تحقق من نشر Edge Function على Supabase.';
      }
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_pollStatus());
    });
  }

  Future<void> _pollStatus() async {
    final result =
        await OilChangeWhatsappGatewayService.instance.checkStatus();
    if (!mounted) return;
    if (result.ok && result.connected) {
      _pollTimer?.cancel();
      await OilChangeWhatsappStatusStore.instance.markConnected();
      _record = await OilChangeWhatsappGatewayRepository.instance
          .fetchForCurrentUser();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم ربط واتساب المحل بنجاح')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final layout = context.screenLayout;

    return Theme(
      data: OilChangeFormTheme.wrap(context, Theme.of(context)),
      child: Scaffold(
        appBar: OilChangeFormTheme.appBar(
          context: context,
          title: 'ربط واتساب المحل',
          actions: const [],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: EdgeInsetsDirectional.all(layout.pageHorizontalGap),
                children: [
                  if (_error != null) ...[
                    MaterialBanner(
                      backgroundColor: cs.errorContainer,
                      content: Text(
                        _error!,
                        style: TextStyle(color: cs.onErrorContainer),
                      ),
                      leading: Icon(Icons.error_outline, color: cs.error),
                      actions: [
                        TextButton(
                          onPressed: () => unawaited(_bootstrap()),
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_record?.isConnected == true) ...[
                    Icon(Icons.check_circle_rounded,
                        color: cs.primary, size: 56),
                    const SizedBox(height: 12),
                    Text(
                      'واتساب المحل متصل',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                      textAlign: TextAlign.start,
                    ),
                    if ((_record?.whatsappPhone ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'الرقم: ${_record!.whatsappPhone}',
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'كل أجهزة حسابك (هاتف + حاسوب) ترى نفس الحالة.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                      textAlign: TextAlign.start,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () async {
                        await _loadQr();
                        _startPolling();
                        setState(() {
                          _record = null;
                        });
                      },
                      icon: const Icon(Icons.qr_code_2_rounded),
                      label: const Text('إعادة الربط (QR جديد)'),
                    ),
                  ] else ...[
                    Text(
                      'امسح الرمز من واتساب المحل',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                      textAlign: TextAlign.start,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'واتساب → الأجهزة المرتبطة → ربط جهاز → امسح QR أدناه.',
                      style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                      textAlign: TextAlign.start,
                    ),
                    const SizedBox(height: 20),
                    if (_qrBase64 != null && _qrBase64!.isNotEmpty)
                      Center(
                        child: Image.memory(
                          base64Decode(_qrBase64!.contains(',')
                              ? _qrBase64!.split(',').last
                              : _qrBase64!),
                          width: 260,
                          height: 260,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image_outlined,
                            size: 120,
                          ),
                        ),
                      )
                    else
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    if ((_pairingCode ?? '').isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'رمز الربط: $_pairingCode',
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'انتظر حتى يظهر «متصل» — تُحدَّث الحالة تلقائياً.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                      textAlign: TextAlign.start,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
