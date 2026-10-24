import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../guides/guide_anchor.dart';
import '../../../guides/guide_controller.dart';
import '../../../navigation/content_navigation.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/screen_layout.dart';
import '../models/tenant_whatsapp_gateway_record.dart';
import '../models/whatsapp_connect_method.dart';
import '../services/oil_change_whatsapp_gateway_repository.dart';
import '../services/oil_change_whatsapp_gateway_service.dart';
import '../services/oil_change_whatsapp_status_store.dart';
import '../services/wa_message_wallet_service.dart';
import '../widgets/oil_change_form_theme.dart';
import '../widgets/oil_change_owner_pin_confirm_dialog.dart';
import '../widgets/whatsapp_connect_method_picker.dart';
import '../widgets/whatsapp_official_connect_panel.dart';
import 'oil_change_whatsapp_followup_screen.dart';
import 'oil_change_whatsapp_wallet_screen.dart';
import '../services/wa_oil_followup_service.dart';
import 'whatsapp_meta_es_web_screen.dart';

/// شاشة ربط واتساب المحل — ثلاث طرق: Meta مباشرة / رقم نابو الرسمي / QR.
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
  /// عند true تُعرض لوحة QR؛ وإلا شاشة اختيار الطريقة / حالة رسمية.
  bool _showConnectFlow = false;
  /// مسار رسمي قيد التنفيذ (Meta مباشرة أو رقم نابو) — قبل أو أثناء التجهيز.
  bool _showOfficialFlow = false;
  String? _error;
  TenantWhatsappGatewayRecord? _record;
  String? _qrBase64;
  String? _pairingCode;
  String? _onboardingUrl;
  String? _officialMessage;
  WhatsappConnectMethod _selectedMethod = WhatsappConnectMethod.nabooShared;
  Timer? _pollTimer;
  Timer? _qrRefreshTimer;
  Timer? _readyPollTimer;
  /// أثناء جولة الإرشاد: اعرض بطاقات الطرق حتى لو كان الحساب متصلاً.
  bool _guideForceMethods = false;
  /// معاينة أزرار الفصل/إعادة الربط إن لم يكن متصلاً أثناء الجولة.
  bool _guideConnectedPreview = false;

  bool get _connected =>
      _record?.isConnected == true ||
      _record?.readyState == WhatsappReadyState.ready;

  bool get _officialPreparing =>
      _record?.isOfficialTransport == true &&
      _record?.readyState == WhatsappReadyState.preparing;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _qrRefreshTimer?.cancel();
    _readyPollTimer?.cancel();
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
    _selectedMethod = WhatsappConnectMethodX.fromRecord(_record);

    if (_connected) {
      await OilChangeWhatsappStatusStore.instance.markConnected();
      _pollTimer?.cancel();
      _readyPollTimer?.cancel();
      _showConnectFlow = false;
      _showOfficialFlow = false;
      _qrBase64 = null;
      _pairingCode = null;
      _onboardingUrl = null;
    } else {
      await OilChangeWhatsappStatusStore.instance.markDisconnectedLocalOnly();
      _showConnectFlow = false;
      _qrBase64 = null;
      _pairingCode = null;
      _pollTimer?.cancel();
      if (_officialPreparing) {
        _showOfficialFlow = true;
        _officialMessage = _record?.readyStateLabelAr ??
            'جاري تجهيز خدمة واتساب…';
        _startReadyPolling();
      } else if (
        _record?.provider == TenantWhatsappProvider.cloudApi &&
        !_connected
      ) {
        // مسار Meta: أظهر لوحة الرسمي لا واتس360 ولا اختيار الطرق فقط.
        _showOfficialFlow = true;
        _selectedMethod = WhatsappConnectMethod.metaDirect;
        _officialMessage =
            'أكمل تسجيل Meta من الصفحة التي فُتحت، ثم اضغط تحديث الحالة.';
        _readyPollTimer?.cancel();
      } else {
        _showOfficialFlow = false;
        _readyPollTimer?.cancel();
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _continueWithSelectedMethod() async {
    switch (_selectedMethod) {
      case WhatsappConnectMethod.metaDirect:
      case WhatsappConnectMethod.nabooShared:
        await _startOfficialMethod(_selectedMethod);
      case WhatsappConnectMethod.qrCode:
        await _startConnectFlowWithProvider(
          WhatsappConnectMethod.qrCode.providerApiValue,
        );
    }
  }

  bool get _dedicatedCloudReady {
    final existing = _record;
    return existing != null &&
        existing.provider == TenantWhatsappProvider.cloudApi &&
        existing.isConnected &&
        (existing.whatsappPhone ?? '').trim().isNotEmpty;
  }

  Future<void> _startOfficialMethod(WhatsappConnectMethod method) async {
    // لا تسمح بالرجوع لرقم نابو المشترك طالما الرقم الخاص جاهز على السحابة.
    if (_dedicatedCloudReady && method == WhatsappConnectMethod.nabooShared) {
      if (!mounted) return;
      setState(() {
        _error =
            'هذا الحساب مربوط برقم واتساب خاص بالمحل. لا يمكن التبديل إلى رقم نابو من التطبيق.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_error!)),
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _showConnectFlow = false;
      _showOfficialFlow = true;
      _selectedMethod = method;
      _officialMessage = 'جاري بدء الربط الرسمي…';
      _onboardingUrl = null;
    });
    try {
      final setRes = await OilChangeWhatsappGatewayService.instance
          .setProvider(method.providerApiValue);
      if (!setRes.ok) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = setRes.messageAr ?? 'تعذّر اختيار طريقة الربط الرسمي.';
        });
        return;
      }

      final res =
          await OilChangeWhatsappGatewayService.instance.connectOfficial();
      _record = await OilChangeWhatsappGatewayRepository.instance
          .refreshStatusFromServer();
      if (!mounted) return;

      final url = (res.onboardingUrl ?? '').trim();
      final msg = res.messageAr ??
          (_record?.readyStateLabelAr ??
              (res.ok
                  ? 'أكمل خطوات Meta ثم اضغط تحديث الحالة.'
                  : 'تعذّر بدء الربط الرسمي. يمكنك المحاولة لاحقاً أو اختيار طريقة أخرى.'));
      setState(() {
        _busy = false;
        _onboardingUrl = url.isEmpty ? null : url;
        _officialMessage = msg;
        _error = res.ok ? null : msg;
      });

      if (url.isNotEmpty) {
        // لا نفتح المتصفح تلقائياً — صاحب المحل يختار رقم جديد أو تعايش.
      }
      if (res.ok || _officialPreparing) {
        _startReadyPolling();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_officialMessage ?? method.titleAr)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'تعذّر بدء ربط واتساب.';
      });
    }
  }

  Future<void> _openOnboardingUrl(
    String raw, {
    bool autoStart = false,
    bool coexistence = false,
    String shopPhone = '',
  }) async {
    final parsed = Uri.tryParse(raw.trim());
    if (parsed == null) return;

    final q = Map<String, String>.from(parsed.queryParameters);
    if (autoStart) q['auto'] = '1';
    if (coexistence) {
      q['feature_type'] = 'whatsapp_business_app_onboarding';
    } else {
      q.remove('feature_type');
    }
    final phone = shopPhone.replaceAll(RegExp(r'\D'), '');
    if (phone.isNotEmpty) q['business_phone'] = phone;
    final uri = parsed.replace(queryParameters: q);

    final isMetaEs = uri.path.contains('whatsapp-meta-es');
    if (isMetaEs && mounted) {
      await Navigator.of(context).push<void>(
        FastContentPageRoute<void>(
          builder: (_) => WhatsappMetaEsWebScreen(pageUrl: uri.toString()),
        ),
      );
      if (!mounted) return;
      setState(() {
        _officialMessage = 'جاري التحقق من إكمال الربط…';
      });
      await OilChangeWhatsappGatewayService.instance.fetchReadyStatus();
      _record = await OilChangeWhatsappGatewayRepository.instance
          .refreshStatusFromServer();
      if (!mounted) return;
      setState(() {
        _officialMessage = _record?.readyStateLabelAr ??
            'إن أكملت Meta، ستظهر حالة التجهيز خلال لحظات.';
      });
      return;
    }

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح رابط إكمال الربط.')),
      );
    }
  }

  void _startReadyPolling() {
    _readyPollTimer?.cancel();
    _readyPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_pollReadyStatus());
    });
  }

  Future<void> _pollReadyStatus() async {
    final result =
        await OilChangeWhatsappGatewayService.instance.fetchReadyStatus();
    if (!mounted) return;
    if (!result.ok) return;

    _record = await OilChangeWhatsappGatewayRepository.instance
        .refreshStatusFromServer();
    if (!mounted) return;

    final ready = result.readyState == 'ready' ||
        result.connected ||
        _record?.readyState == WhatsappReadyState.ready;

    setState(() {
      _officialMessage = result.messageAr ?? _record?.readyStateLabelAr;
      if (ready) {
        _showOfficialFlow = false;
        _showConnectFlow = false;
        _onboardingUrl = null;
      } else if (_record?.readyState == WhatsappReadyState.preparing) {
        _showOfficialFlow = true;
      }
    });

    if (ready) {
      _readyPollTimer?.cancel();
      await OilChangeWhatsappStatusStore.instance.markConnected();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('واتساب المحل جاهز للإرسال')),
      );
    }
  }

  void _backToMethodPicker() {
    _readyPollTimer?.cancel();
    _pollTimer?.cancel();
    _qrRefreshTimer?.cancel();
    setState(() {
      _showOfficialFlow = false;
      _showConnectFlow = false;
      _qrBase64 = null;
      _pairingCode = null;
      _onboardingUrl = null;
      _officialMessage = null;
      _error = null;
    });
  }

  Future<void> _saveWhats360Credentials({
    required String token,
    required String instanceId,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await OilChangeWhatsappGatewayService.instance
          .configureWhats360(token: token, instanceId: instanceId);
      _record = await OilChangeWhatsappGatewayRepository.instance
          .refreshStatusFromServer();
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.messageAr ??
                (res.ok ? 'تم حفظ إعدادات واتس360.' : 'تعذّر الحفظ.'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'تعذّر حفظ إعدادات واتس360.';
      });
    }
  }

  Future<void> _startConnectFlowWithProvider(String provider) async {
    setState(() {
      _busy = true;
      _error = null;
      _showOfficialFlow = false;
      _selectedMethod = WhatsappConnectMethod.qrCode;
    });
    try {
      final res =
          await OilChangeWhatsappGatewayService.instance.setProvider(provider);
      if (!res.ok) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = res.messageAr ?? 'تعذّر اختيار طريقة الربط.';
        });
        return;
      }
      await _startConnectFlow();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'تعذّر بدء الربط.';
      });
    }
  }

  Future<void> _startConnectFlow() async {
    setState(() {
      _busy = true;
      _error = null;
      _showConnectFlow = true;
      _showOfficialFlow = false;
      _qrBase64 = null;
      _pairingCode = null;
    });
    try {
      // تحقق أولاً — إن الجلسة المركزية متصلة لا تفصلها ولا تطلب QR.
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
      // إن فشل الاستعلام الحي: اعتمد السحابة إن كانت «متصل» (تجنّب دوامة التحميل).
      final cloud = await OilChangeWhatsappGatewayRepository.instance
          .fetchForCurrentUser();
      if (cloud?.isConnected == true) {
        await OilChangeWhatsappStatusStore.instance.markConnected();
        if (!mounted) return;
        setState(() {
          _record = cloud;
          _showConnectFlow = false;
          _qrBase64 = null;
          _pairingCode = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'واتساب المحل متصل على السحابة — لا حاجة لمسح QR الآن',
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

    // الحساب ما زال على مزود رسمي — ارجع لاختيار الطريقة بدل دوامة QR.
    if (qr.errorCode == 'official_no_qr' || qr.errorCode == 'whats360_no_qr') {
      _pollTimer?.cancel();
      _qrRefreshTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _showConnectFlow = false;
        _qrBase64 = null;
        _pairingCode = null;
        _error = qr.messageAr ??
            'الربط الرسمي لا يستخدم مسح QR. اختر الطريقة المناسبة ثم تابع.';
        _selectedMethod = WhatsappConnectMethod.nabooShared;
      });
      return;
    }

    setState(() {
      _qrBase64 = qr.base64;
      _pairingCode = qr.pairingCode;
      if (!qr.ok && (_qrBase64 == null || _qrBase64!.isEmpty)) {
        _error = (qr.messageAr ?? '').trim().isNotEmpty
            ? qr.messageAr
            : 'تعذّر جلب رمز QR. اضغط «تحديث رمز QR» أو جرّب الربط الرسمي.';
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

  Future<void> _relinkOfficialWithPin() async {
    // رقم المحل الخاص عبر Cloud API جاهز مسبقاً: لا نعيد set_provider
    // (يمسح المعرّفات أو يعيد رقم نابو المشترك بالخطأ).
    final existing = _record;
    if (_dedicatedCloudReady && existing != null) {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        _record = await OilChangeWhatsappGatewayRepository.instance
            .refreshStatusFromServer();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'واتساب مربوط مسبقاً بالرقم '
              '${(_record?.whatsappPhone ?? existing.whatsappPhone)!.trim()}',
            ),
          ),
        );
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    final confirmed = await confirmOwnerPinForWhatsappAction(
      context,
      title: 'إعادة الربط الرسمي',
      message:
          'سيتم إعادة بدء مسار الربط الرسمي لواتساب المحل.\n'
          'قد تحتاج إكمال خطوات Meta من جديد.\n\n'
          'أدخل رمز PIN للمالك (4 أرقام) للمتابعة.',
      confirmLabel: 'إعادة الربط',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _startOfficialMethod(
      WhatsappConnectMethodX.fromRecord(_record),
    );
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
      _readyPollTimer?.cancel();
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
        _showOfficialFlow = false;
        _onboardingUrl = null;
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
      child: Consumer<GuideController>(
        builder: (context, guide, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _syncGuideActions(guide);
          });
          return Scaffold(
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
                    absorbing: _busy && !guide.isRunning,
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
                            onRetry: () => unawaited(
                              _showConnectFlow
                                  ? _loadQr(forceReset: false)
                                  : _bootstrap(),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_busy)
                          const Padding(
                            padding: EdgeInsetsDirectional.only(bottom: 16),
                            child: LinearProgressIndicator(minHeight: 3),
                          ),
                        if (_showConnectedPanel)
                          _ConnectedPanel(
                            phone: _guideConnectedPreview
                                ? null
                                : _record?.whatsappPhone,
                            readyLabel: _guideConnectedPreview
                                ? 'معاينة الشرح'
                                : (_record?.readyStateLabelAr ?? 'جاهز'),
                            methodLabel: _guideConnectedPreview
                                ? 'عند الاتصال تظهر أزرار الفصل وإعادة الربط هنا'
                                : WhatsappConnectMethodX.fromRecord(_record)
                                    .titleAr,
                            usesQr: _guideConnectedPreview
                                ? false
                                : _record?.usesQr == true,
                            isOfficialTransport: _guideConnectedPreview
                                ? true
                                : _record?.isOfficialTransport == true,
                            onDisconnect: _guideConnectedPreview
                                ? () {}
                                : () => unawaited(_disconnectWithPin()),
                            onRelink: _guideConnectedPreview
                                ? () {}
                                : () => unawaited(
                                      _record?.usesQr == true
                                          ? _relinkWithPin()
                                          : _relinkOfficialWithPin(),
                                    ),
                          )
                        else if (_record?.isWhats360 == true &&
                            _record?.cloudSetupStatus != 'ready' &&
                            !_guideForceMethods)
                          _Whats360SetupPanel(
                            busy: _busy,
                            isReady: _record?.isConnected == true &&
                                _record?.cloudSetupStatus == 'ready',
                            onSave: (token, instanceId) => unawaited(
                              _saveWhats360Credentials(
                                token: token,
                                instanceId: instanceId,
                              ),
                            ),
                            onSwitchToQr: () => unawaited(
                              _startConnectFlowWithProvider('evolution'),
                            ),
                          )
                        else if (_showConnectFlow && !_guideForceMethods)
                          _ConnectingPanel(
                            qrBase64: _qrBase64,
                            pairingCode: _pairingCode,
                            failed: _error != null &&
                                (_qrBase64 == null || _qrBase64!.isEmpty),
                            onRefreshQr: () =>
                                unawaited(_loadQr(forceReset: false)),
                            onTryOfficial: () {
                              _pollTimer?.cancel();
                              _qrRefreshTimer?.cancel();
                              setState(() {
                                _showConnectFlow = false;
                                _qrBase64 = null;
                                _pairingCode = null;
                                _error = null;
                                _selectedMethod =
                                    WhatsappConnectMethod.nabooShared;
                              });
                              unawaited(
                                _startOfficialMethod(
                                  WhatsappConnectMethod.nabooShared,
                                ),
                              );
                            },
                            onCancel: () {
                              _pollTimer?.cancel();
                              _qrRefreshTimer?.cancel();
                              setState(() {
                                _showConnectFlow = false;
                                _qrBase64 = null;
                                _pairingCode = null;
                                _error = null;
                              });
                            },
                          )
                        else if ((_showOfficialFlow || _officialPreparing) &&
                            !_guideForceMethods)
                          WhatsappOfficialConnectPanel(
                            method: _selectedMethod.isOfficial
                                ? _selectedMethod
                                : WhatsappConnectMethodX.fromRecord(_record),
                            preparing: _officialPreparing || _busy,
                            messageAr:
                                (_officialMessage ?? '').trim().isNotEmpty
                                    ? _officialMessage!
                                    : 'أكمل خطوات الربط الرسمي ثم حدّث الحالة.',
                            onboardingUrl: _onboardingUrl,
                            onOpenOnboarding: _onboardingUrl == null
                                ? null
                                : (phone) => unawaited(
                                      _openOnboardingUrl(
                                        _onboardingUrl!,
                                        autoStart: true,
                                        shopPhone: phone,
                                      ),
                                    ),
                            onOpenCoexistence: _onboardingUrl == null
                                ? null
                                : (phone) => unawaited(
                                      _openOnboardingUrl(
                                        _onboardingUrl!,
                                        autoStart: true,
                                        coexistence: true,
                                        shopPhone: phone,
                                      ),
                                    ),
                            onRefresh: () => unawaited(_pollReadyStatus()),
                            onBack: _backToMethodPicker,
                            onContinue: _officialPreparing
                                ? null
                                : () => unawaited(
                                      _startOfficialMethod(
                                        _selectedMethod.isOfficial
                                            ? _selectedMethod
                                            : WhatsappConnectMethod
                                                .nabooShared,
                                      ),
                                    ),
                          )
                        else if (_showMethodsPanel)
                          _MethodSelectPanel(
                            selected: _selectedMethod,
                            onChanged: (m) =>
                                setState(() => _selectedMethod = m),
                            onContinue: () =>
                                unawaited(_continueWithSelectedMethod()),
                            guideMode: _guideForceMethods,
                          ),
                        const SizedBox(height: 20),
                        const _InfoTipsCard(),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }

  void _syncGuideActions(GuideController guide) {
    if (!guide.isRunning) {
      if (_guideForceMethods || _guideConnectedPreview) {
        setState(() {
          _guideForceMethods = false;
          _guideConnectedPreview = false;
        });
      }
      return;
    }
    final action = guide.currentStep?.action;
    if (action == 'wa.show_methods') {
      if (!_guideForceMethods || _guideConnectedPreview) {
        setState(() {
          _guideForceMethods = true;
          _guideConnectedPreview = false;
          _showConnectFlow = false;
          _showOfficialFlow = false;
          _error = null;
        });
      }
    } else if (action == 'wa.show_connected') {
      final needPreview = !_connected;
      if (_guideForceMethods || _guideConnectedPreview != needPreview) {
        setState(() {
          _guideForceMethods = false;
          _guideConnectedPreview = needPreview;
        });
      }
    }
  }

  bool get _showConnectedPanel =>
      ((_connected && !_guideForceMethods) || _guideConnectedPreview) &&
      !(_record?.isWhats360 == true &&
          _record?.cloudSetupStatus != 'ready' &&
          !_guideConnectedPreview);

  bool get _showMethodsPanel =>
      _guideForceMethods ||
      (!_connected &&
          !_showConnectFlow &&
          !_showOfficialFlow &&
          !_officialPreparing &&
          !(_record?.isWhats360 == true &&
              _record?.cloudSetupStatus != 'ready'));
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

class _ConnectedPanel extends StatefulWidget {
  const _ConnectedPanel({
    required this.phone,
    required this.readyLabel,
    required this.methodLabel,
    required this.usesQr,
    required this.isOfficialTransport,
    required this.onDisconnect,
    required this.onRelink,
  });

  final String? phone;
  final String readyLabel;
  final String methodLabel;
  final bool usesQr;
  final bool isOfficialTransport;
  final VoidCallback onDisconnect;
  final VoidCallback onRelink;

  @override
  State<_ConnectedPanel> createState() => _ConnectedPanelState();
}

class _ConnectedPanelState extends State<_ConnectedPanel> {
  int? _balance;
  bool _walletLoading = true;
  WaOilFollowupSummary? _followupSummary;
  bool _followupLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBalance());
    unawaited(_loadFollowupSummary());
  }

  Future<void> _loadFollowupSummary() async {
    try {
      final snap = await WaOilFollowupService.instance.loadSummary(
        isOfficialTransport: widget.isOfficialTransport,
      );
      if (!mounted) return;
      setState(() {
        _followupSummary = snap;
        _followupLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _followupSummary = null;
        _followupLoading = false;
      });
    }
  }

  Future<void> _loadBalance() async {
    try {
      final snap = await WaMessageWalletService.instance.load();
      if (!mounted) return;
      setState(() {
        _balance = snap.schemaMissing ? null : snap.balance;
        _walletLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _balance = null;
        _walletLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final phoneText = (widget.phone ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GuideAnchor(
          id: OilGuideAnchors.waStatus,
          child: Container(
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
                widget.readyLabel,
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                widget.methodLabel,
                style: const TextStyle(
                  color: OilChangeFormTheme.gold,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                widget.usesQr
                    ? 'كل أجهزة الحساب تستخدم نفس جلسة QR على السيرفر.'
                    : 'الربط الرسمي فعّال — القوالب والإرسال عبر السحابة.',
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
        ),
        const SizedBox(height: 18),
        GuideAnchor(
          id: OilGuideAnchors.waRelink,
          child: FilledButton.icon(
          onPressed: widget.onRelink,
          icon: Icon(
            widget.usesQr ? Icons.qr_code_2_rounded : Icons.sync_rounded,
          ),
          label: Text(
            widget.usesQr ? 'فصل ثم ربط برقم/QR جديد' : 'إعادة الربط الرسمي',
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: AppColors.primary,
          ),
        ),
        ),
        const SizedBox(height: 10),
        GuideAnchor(
          id: OilGuideAnchors.waDisconnect,
          child: OutlinedButton.icon(
          onPressed: widget.onDisconnect,
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
        ),
        const SizedBox(height: 8),
        Text(
          'إلغاء الربط أو إعادة الربط يتطلبان رمز PIN للمالك.',
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant,
            height: 1.35,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        _WalletDetailsTile(
          balance: _balance,
          loading: _walletLoading,
          onTap: () async {
            await OilChangeWhatsappWalletScreen.open(context);
            if (!mounted) return;
            await _loadBalance();
          },
        ),
        const SizedBox(height: 10),
        _FollowupDetailsTile(
          summary: _followupSummary,
          loading: _followupLoading,
          onTap: () async {
            await OilChangeWhatsappFollowupScreen.open(
              context,
              isOfficialTransport: widget.isOfficialTransport,
            );
            if (!mounted) return;
            await _loadFollowupSummary();
          },
        ),
      ],
    );
  }
}

class _FollowupDetailsTile extends StatelessWidget {
  const _FollowupDetailsTile({
    required this.summary,
    required this.loading,
    required this.onTap,
  });

  final WaOilFollowupSummary? summary;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = summary;
    final accent = s == null || s.schemaMissing
        ? OilChangeFormTheme.gold
        : !s.enabled
            ? const Color(0xFFEA580C)
            : s.templateStatus == WaFollowupTemplateUiStatus.approved ||
                    s.templateStatus == WaFollowupTemplateUiStatus.qrReady
                ? AppSemanticColors.success
                : s.templateStatus == WaFollowupTemplateUiStatus.pending
                    ? AppSemanticColors.info
                    : s.templateStatus == WaFollowupTemplateUiStatus.rejected
                        ? cs.error
                        : OilChangeFormTheme.gold;

    String subtitle;
    if (loading) {
      subtitle = 'جاري قراءة التذكير…';
    } else if (s == null || s.schemaMissing) {
      subtitle = 'التذكير التلقائي · اضغط للضبط';
    } else if (!s.enabled) {
      subtitle = 'متوقف — اضغط للتشغيل والضبط';
    } else if (s.templateStatus == WaFollowupTemplateUiStatus.pending) {
      subtitle = 'بعد كل غيار · بانتظار موافقة واتساب';
    } else if (s.templateStatus == WaFollowupTemplateUiStatus.rejected) {
      subtitle = 'ميتا رفضت القالب — اضغط للتعديل';
    } else if (s.templateStatus == WaFollowupTemplateUiStatus.draft) {
      subtitle = 'مضبوط · أرسل القالب للمراجعة حتى يشتغل';
    } else {
      subtitle =
          'يعمل · بعد كل غيار نرسل بعد ${s.delayUnit.labelAr(s.delayValue)}';
    }

    final badge = s == null || s.schemaMissing
        ? null
        : s.delayUnit.badgeShort(s.delayValue);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              colors: [
                accent.withValues(alpha: 0.12),
                cs.surfaceContainerHighest.withValues(alpha: 0.5),
              ],
            ),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.16),
                ),
                child: Icon(Icons.schedule_send_rounded, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تذكير الزبون بعد الغيار',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: OilChangeFormTheme.emphasisText(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null && !loading)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(fontWeight: FontWeight.w900, color: accent),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_left_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletDetailsTile extends StatelessWidget {
  const _WalletDetailsTile({
    required this.balance,
    required this.loading,
    required this.onTap,
  });

  final int? balance;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final low = balance != null && balance! > 0 && balance! <= 20;
    final empty = balance != null && balance! <= 0;
    final accent = empty
        ? const Color(0xFFEA580C)
        : low
            ? OilChangeFormTheme.gold
            : AppColors.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              colors: [
                accent.withValues(alpha: 0.12),
                cs.surfaceContainerHighest.withValues(alpha: 0.5),
              ],
            ),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.16),
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'محفظة WhatsApp',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: OilChangeFormTheme.emphasisText(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      loading
                          ? 'جاري قراءة الرصيد…'
                          : balance == null
                              ? 'المحفظة · اضغط للاشتراك والتفاصيل'
                              : balance! <= 0
                                  ? 'لا يوجد رصيد — اشترك الآن'
                                  : 'الرصيد: $balance رسالة'
                                      '${low ? ' · منخفضة' : ''}',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: empty
                            ? const Color(0xFFC2410C)
                            : cs.onSurfaceVariant,
                        fontWeight: empty ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (!loading && balance != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$balance',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: accent,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_left_rounded,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
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

class _Whats360SetupPanel extends StatefulWidget {
  const _Whats360SetupPanel({
    required this.busy,
    required this.isReady,
    required this.onSave,
    required this.onSwitchToQr,
  });

  final bool busy;
  final bool isReady;
  final void Function(String token, String instanceId) onSave;
  final VoidCallback onSwitchToQr;

  @override
  State<_Whats360SetupPanel> createState() => _Whats360SetupPanelState();
}

class _Whats360SetupPanelState extends State<_Whats360SetupPanel> {
  final _tokenCtrl = TextEditingController();
  final _instanceCtrl = TextEditingController();

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _instanceCtrl.dispose();
    super.dispose();
  }

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
            color: AppColors.primary.withValues(alpha: 0.08),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: [
              Icon(
                widget.isReady
                    ? Icons.verified_rounded
                    : Icons.key_rounded,
                size: 40,
                color: AppColors.primary,
              ),
              const SizedBox(height: 12),
              Text(
                widget.isReady ? 'واتس360 جاهز' : 'إعداد واتس360',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                widget.isReady
                    ? 'الإرسال يتم عبر واتس360. يمكنك تحديث التوكن أدناه إن لزم.'
                    : 'من لوحة whats360.live:\n'
                        '1) جدّد Access Token وانسخه وحده\n'
                        '2) من تبويب الأجهزة انسخ معرّف الجهاز فقط (مثل device_xxxx)\n'
                        'لا تلصق رابط send-text كاملاً، ولا تترك INSTANCE_ID كما في المثال.',
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _tokenCtrl,
          obscureText: true,
          enabled: !widget.busy,
          decoration: const InputDecoration(
            labelText: 'Access Token',
            hintText: 'الصق التوكن بعد تجديده',
            border: OutlineInputBorder(),
          ),
          textDirection: TextDirection.ltr,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _instanceCtrl,
          enabled: !widget.busy,
          decoration: const InputDecoration(
            labelText: 'معرّف الجهاز (instance_id)',
            hintText: 'مثال: device_xxxxx',
            border: OutlineInputBorder(),
          ),
          textDirection: TextDirection.ltr,
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: widget.busy
              ? null
              : () {
                  final token = _tokenCtrl.text.trim();
                  final id = _instanceCtrl.text.trim();
                  if (token.length < 20 || id.length < 3) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'أدخل التوكن ومعرّف الجهاز بشكل صحيح.',
                        ),
                      ),
                    );
                    return;
                  }
                  widget.onSave(token, id);
                },
          icon: const Icon(Icons.save_rounded),
          label: const Text('حفظ وربط واتس360'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: AppColors.primary,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: widget.busy ? null : widget.onSwitchToQr,
          icon: const Icon(Icons.qr_code_2_rounded),
          label: const Text('الرجوع لربط QR'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }
}

class _MethodSelectPanel extends StatelessWidget {
  const _MethodSelectPanel({
    required this.selected,
    required this.onChanged,
    required this.onContinue,
    this.guideMode = false,
  });

  final WhatsappConnectMethod selected;
  final ValueChanged<WhatsappConnectMethod> onChanged;
  final VoidCallback onContinue;
  final bool guideMode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GuideAnchor(
          id: OilGuideAnchors.waMethodIntro,
          child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [
                AppColors.primary,
                AppColors.primary.withValues(alpha: 0.88),
                OilChangeFormTheme.gold.withValues(alpha: 0.35),
              ],
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.12),
                  border: Border.all(
                    color: OilChangeFormTheme.gold.withValues(alpha: 0.55),
                  ),
                ),
                child: const Icon(
                  Icons.hub_rounded,
                  size: 34,
                  color: OilChangeFormTheme.gold,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                guideMode
                    ? 'شرح طرق الربط الثلاث'
                    : 'اختر طريقة ربط واتساب',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'ثلاث مسارات واضحة — الرسمي أقوى للاستقرار، وQR للربط السريع.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.84),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        ),
        const SizedBox(height: 16),
        WhatsappConnectMethodPicker(
          selected: selected,
          onChanged: onChanged,
          enabled: !guideMode,
        ),
        const SizedBox(height: 18),
        GuideAnchor(
          id: OilGuideAnchors.waContinue,
          child: FilledButton.icon(
            onPressed: guideMode ? null : onContinue,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(guideMode ? 'متابعة (بعد اختيار الطريقة)' : 'متابعة'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: AppColors.primary,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          selected.showStabilityWarning
              ? 'اخترت مساراً سريعاً — قد تحتاج إعادة مسح لاحقاً.'
              : 'بعد المتابعة سنوجّهك لإكمال الربط دون إنشاء قوالب يدوياً.',
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

class _ConnectingPanel extends StatelessWidget {
  const _ConnectingPanel({
    required this.qrBase64,
    required this.pairingCode,
    required this.failed,
    required this.onRefreshQr,
    required this.onTryOfficial,
    required this.onCancel,
  });

  final String? qrBase64;
  final String? pairingCode;
  final bool failed;
  final VoidCallback onRefreshQr;
  final VoidCallback onTryOfficial;
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
                else if (failed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Column(
                      children: [
                        Icon(
                          Icons.qr_code_scanner_rounded,
                          size: 72,
                          color: cs.error.withValues(alpha: 0.75),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'تعذّر عرض رمز QR حالياً',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: OilChangeFormTheme.emphasisText(context),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'حدّث الرمز، أو استخدم الربط الرسمي الأكثر ثباتاً.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
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
        if (failed) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onTryOfficial,
            icon: const Icon(Icons.handshake_rounded),
            label: const Text('جرّب رقم نابو الرسمي (موصى به)'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: AppColors.primary,
            ),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: onCancel,
          child: const Text('العودة لاختيار طريقة الربط'),
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
      'اختر رقم نابو الرسمي أو Meta مباشرة لاستقرار أفضل وإرسال بالقوالب.',
      'مسح QR سريع لكنه قد ينقطع — مناسب كخيار احتياطي.',
      'الربط مرة واحدة فقط للحساب على السيرفر — الحاسوب الثاني لا يحتاج QR جديد.',
      'لا تضغط «إعادة الربط» على جهاز آخر: ذلك قد يفصل واتساب عن كل الأجهزة.',
      'إلغاء الربط أو إعادة الربط يتطلب رمز PIN للمالك.',
    ];

    return GuideAnchor(
      id: OilGuideAnchors.waTips,
      child: Container(
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
    ),
    );
  }
}
