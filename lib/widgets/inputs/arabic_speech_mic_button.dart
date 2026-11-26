import 'dart:async' show Timer, unawaited;
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'arabic_speech_helpers.dart';

/// على macOS استدعاء SpeechToText.initialize قد يقتل العملية بـ TCC
/// (حتى مع وجود NSSpeechRecognitionUsageDescription في بيئات debug).
bool get _blockSpeechEngineOnPlatform {
  if (kIsWeb) return true;
  return defaultTargetPlatform == TargetPlatform.macOS;
}

/// زر مايك داخل حقل النص — اضغط للاستماع ثم يُكتب النص مباشرة في الحقل.
///
/// محسَّن للهجة العراقية: تهيئة مبكرة، تفضيل `ar_IQ`/خليجي، سحابة عند الاتصال،
/// إعادة استماع تلقائية حتى يضغط المستخدم للإيقاف، وصمت أطول في البداية
/// للأصوات الهادئة ثم تقصير الصمت بعد أول كلام للاستجابة السريعة.
/// حالة التسجيل بالضغط المطوّل (ط8)، يرسم منها الحقل شريط التسجيل مكان النص.
class SpeechHoldState {
  const SpeechHoldState({
    required this.startedAt,
    this.level = 0,
    this.cancelProgress = 0,
    this.lockProgress = 0,
    this.locked = false,
  });

  final DateTime startedAt;

  /// مستوى الصوت 0..1 للموجة.
  final double level;

  /// 0..1: كم سحب باتجاه الإلغاء (1 = يُلغى عند الرفع).
  final double cancelProgress;

  /// 0..1: كم سحب للأعلى باتجاه القفل.
  final double lockProgress;

  /// مقفل: يستمر التسجيل بلا إصبع حتى يضغط «إرسال» أو «إلغاء».
  final bool locked;

  SpeechHoldState copyWith({double? level, double? cancelProgress, double? lockProgress, bool? locked}) =>
      SpeechHoldState(
        startedAt: startedAt,
        level: level ?? this.level,
        cancelProgress: cancelProgress ?? this.cancelProgress,
        lockProgress: lockProgress ?? this.lockProgress,
        locked: locked ?? this.locked,
      );
}

/// أوامر شريط التسجيل المقفل (إرسال أو إلغاء) تصل للزر بهذا المتحكم.
class SpeechHoldController {
  _ArabicSpeechMicButtonState? _owner;

  /// ينهي التسجيل المقفل ويرسل النص.
  void finish() => _owner?._finishHold(send: true);

  /// يلغي التسجيل ويعيد الحقل كما كان.
  void cancel() => _owner?._finishHold(send: false);
}

class ArabicSpeechMicButton extends StatefulWidget {
  const ArabicSpeechMicButton({
    super.key,
    required this.controller,
    this.enabled = true,
    this.onTextUpdated,
    this.tooltip = 'إملاء بالصوت',
    this.onListeningChanged,
    this.size = 40,
    this.holdState,
    this.holdController,
    this.onHoldSend,
  });

  /// ط8 (المساعد فقط): الضغط المطوّل يسجّل مثل واتساب. null = السلوك القديم وحده.
  final ValueNotifier<SpeechHoldState?>? holdState;
  final SpeechHoldController? holdController;

  /// رفع الإصبع بعد كلام: يُرسل نص الحقل.
  final ValueChanged<String>? onHoldSend;

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback? onTextUpdated;
  final String tooltip;

  /// يُبلَّغ عند بدء الاستماع وانتهائه (لرمز المساعد).
  final ValueChanged<bool>? onListeningChanged;
  final double size;

  /// يجهّز محرك الصوت مسبقاً (locale + صلاحية) لتقليل تأخير أول ضغط.
  static Future<void> warmUp() => _ArabicSpeechMicButtonState.warmUpShared();

  @override
  State<ArabicSpeechMicButton> createState() => _ArabicSpeechMicButtonState();
}

class _ArabicSpeechMicButtonState extends State<ArabicSpeechMicButton> {
  static final stt.SpeechToText _speech = stt.SpeechToText();
  static String? _sharedLocaleId;
  static Future<bool>? _initFuture;
  static bool? _cachedOnline;
  static DateTime? _onlineCheckedAt;

  var _listening = false;
  var _reportedActive = false;
  var _starting = false;
  var _wantListening = false;
  var _heardWords = false;
  var _ownsSession = false;
  double _soundLevel = 0;
  int _autoRestartCount = 0;

  String _prefixBeforeSession = '';
  String _sessionCommitted = '';
  String _currentPartial = '';

  Timer? _restartTimer;
  Timer? _soundDecayTimer;

  // ط8: التسجيل بالضغط المطوّل.
  bool _holding = false;
  String _holdPrefix = '';
  static const _cancelDistance = 110.0;
  static const _lockDistance = 80.0;

  bool get _holdEnabled => widget.holdState != null;

  void _setHold(SpeechHoldState? v) {
    final n = widget.holdState;
    if (n != null) n.value = v;
  }

  Future<void> _startHold() async {
    if (!widget.enabled || _starting || _holding) return;
    if (_blockSpeechEngineOnPlatform) {
      _showSnack('الإملاء بالصوت غير متاح على هذا الجهاز — اكتب يدوياً');
      return;
    }
    if (_wantListening || _listening || _speech.isListening) await _stopByUser();
    _holding = true;
    _holdPrefix = widget.controller.text;
    unawaited(HapticFeedback.mediumImpact());
    _setHold(SpeechHoldState(startedAt: DateTime.now()));
    await _toggleListening();
  }

  void _moveHold(Offset delta) {
    final h = widget.holdState?.value;
    if (!_holding || h == null || h.locked) return;
    // في العربية الزر في طرف الحقل الأيسر، فالسحب نحو بداية السطر (اليمين) يلغي.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final toward = rtl ? delta.dx : -delta.dx;
    final cancel = (toward / _cancelDistance).clamp(0.0, 1.0);
    final lock = (-delta.dy / _lockDistance).clamp(0.0, 1.0);
    if (lock >= 1) {
      unawaited(HapticFeedback.selectionClick());
      _setHold(h.copyWith(locked: true, lockProgress: 1, cancelProgress: 0));
      return;
    }
    _setHold(h.copyWith(cancelProgress: cancel, lockProgress: lock));
  }

  void _endHold() {
    final h = widget.holdState?.value;
    if (!_holding || h == null) return;
    if (h.locked) return; // يكمل حتى «إرسال» أو «إلغاء» من الشريط.
    unawaited(_finishHold(send: h.cancelProgress < 1));
  }

  Future<void> _finishHold({required bool send}) async {
    if (!_holding) return;
    _holding = false;
    final started = widget.holdState?.value?.startedAt;
    _setHold(null);
    await _stopByUser();
    if (!mounted) return;
    final tooShort = started != null && DateTime.now().difference(started) < const Duration(milliseconds: 450);
    if (!send || tooShort) {
      widget.controller.text = _holdPrefix;
      widget.controller.selection = TextSelection.collapsed(offset: _holdPrefix.length);
      if (tooShort && send) _showSnack('اضغط مطوّلاً وتكلّم، ثم ارفع إصبعك');
      return;
    }
    final text = widget.controller.text.trim();
    if (text.isEmpty) {
      _showSnack('ما سمعت كلام — اضغط مطوّلاً وتكلّم مرة ثانية');
      return;
    }
    unawaited(HapticFeedback.lightImpact());
    widget.onHoldSend?.call(text);
  }

  static const _maxAutoRestarts = 40;
  static const _initialPause = Duration(seconds: 12);
  static const _activePause = Duration(seconds: 5);
  static const _maxListen = Duration(minutes: 3);

  static Future<void> warmUpShared() async {
    if (_blockSpeechEngineOnPlatform) return;
    try {
      await _ensureSharedInitialized(
        onStatus: (_) {},
        onError: (_) {},
      );
    } catch (_) {
      // فشل التهيئة المسبقة لا يمنع فتح الشاشة — يُعاد المحاولة عند ضغط المايك.
      _initFuture = null;
    }
  }

  static Future<bool> _ensureSharedInitialized({
    required void Function(String) onStatus,
    required void Function(SpeechRecognitionError) onError,
  }) async {
    if (_blockSpeechEngineOnPlatform) return false;

    // SpeechToText مفرد: أعد ربط المستمعين دائماً لصاحب الجلسة الحالي.
    _speech.statusListener = onStatus;
    _speech.errorListener = onError;

    if (_speech.isAvailable && _initFuture == null) {
      _sharedLocaleId ??= await _resolveArabicLocaleStatic();
      return true;
    }

    _initFuture ??= () async {
      final ok = await _speech.initialize(
        onStatus: onStatus,
        onError: onError,
        finalTimeout: const Duration(milliseconds: 700),
        options: [
          // تجنّب طلب بلوتوث غير لازم — يسرّع init على أندرويد.
          stt.SpeechToText.androidNoBluetooth,
        ],
      );
      if (ok) {
        _sharedLocaleId = await _resolveArabicLocaleStatic();
      }
      return ok;
    }();

    final ok = await _initFuture!;
    // بعد أول init، المستمعون يُثبَّتون داخلياً — أعد التعيين يدوياً.
    _speech.statusListener = onStatus;
    _speech.errorListener = onError;
    if (!ok) _initFuture = null;
    return ok;
  }

  static Future<String?> _resolveArabicLocaleStatic() async {
    final locales = await _speech.locales();
    final picked = pickBestArabicSpeechLocale(locales.map((l) => l.localeId));
    if (picked != null) return picked;
    final system = await _speech.systemLocale();
    return system?.localeId;
  }

  @override
  void initState() {
    super.initState();
    widget.holdController?._owner = this;
    // لا تهيئة تلقائية على macOS — تمنع قتل التطبيق عند فتح بطاقة الزيت.
    if (!_blockSpeechEngineOnPlatform) {
      unawaited(_warmUpIfAlreadyPermitted());
      unawaited(_refreshOnlineCache());
    }
  }

  /// التهيئة تطلب إذن الميكروفون — لا نفعلها قبل أن يضغط المستخدم زر الصوت،
  /// إلا إن كان الإذن ممنوحاً مسبقاً فيُسرّع ذلك أول إملاء.
  Future<void> _warmUpIfAlreadyPermitted() async {
    try {
      if (!await _speech.hasPermission || !mounted) return;
      await _ensureSharedInitialized(
        onStatus: _onStatus,
        onError: _onSpeechError,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    if (widget.holdController?._owner == this) widget.holdController?._owner = null;
    if (_holding) widget.holdState?.value = null;
    _restartTimer?.cancel();
    _soundDecayTimer?.cancel();
    final shouldStop = _wantListening || _ownsSession || _listening;
    _wantListening = false;
    _ownsSession = false;
    if (shouldStop && _speech.isListening) {
      unawaited(_speech.stop());
    }
    super.dispose();
  }

  Future<void> _refreshOnlineCache() async {
    try {
      final results = await Connectivity().checkConnectivity();
      _cachedOnline = results.any(
        (r) =>
            r == ConnectivityResult.mobile ||
            r == ConnectivityResult.wifi ||
            r == ConnectivityResult.ethernet,
      );
      _onlineCheckedAt = DateTime.now();
    } catch (_) {
      // افترض اتصالاً — السحابة أفضل للهجة؛ الفشل يُعالَج في onError.
      _cachedOnline = true;
      _onlineCheckedAt = DateTime.now();
    }
  }

  Future<bool> _isOnline() async {
    final checked = _onlineCheckedAt;
    if (_cachedOnline != null &&
        checked != null &&
        DateTime.now().difference(checked) < const Duration(seconds: 20)) {
      return _cachedOnline!;
    }
    await _refreshOnlineCache();
    return _cachedOnline ?? true;
  }

  Future<bool> _ensureInitialized() async {
    final ok = await _ensureSharedInitialized(
      onStatus: _onStatus,
      onError: _onSpeechError,
    );
    if (!mounted) return false;
    if (!ok) {
      final permitted = await _speech.hasPermission;
      _showSnack(
        permitted
            ? 'التعرف على الصوت غير متاح على هذا الجهاز'
            : 'اضغط المايك واختر «السماح» لاستخدام الميكروفون',
      );
      return false;
    }
    if (!await _speech.hasPermission) {
      _showSnack('اضغط المايك واختر «السماح» لاستخدام الميكروفون');
      return false;
    }
    return true;
  }

  void _onStatus(String status) {
    if (!mounted || !_ownsSession) return;

    if (status == stt.SpeechToText.listeningStatus) {
      setState(() {
        _listening = true;
        _starting = false;
      });
      return;
    }

    if (status == stt.SpeechToText.notListeningStatus ||
        status == stt.SpeechToText.doneStatus) {
      setState(() {
        _listening = false;
        _starting = false;
        _soundLevel = 0;
      });
      // إعادة تشغيل تلقائية طالما المستخدم لم يوقف المايك — ضروري لأن أندرويد
      // يقطع الجلسة بسرعة عند الكلام الهادئ أو التوقف القصير باللهجة.
      if (_wantListening) {
        _scheduleAutoRestart();
      } else {
        _ownsSession = false;
      }
    }
  }

  void _scheduleAutoRestart() {
    if (!_wantListening || !_ownsSession) return;
    if (_autoRestartCount >= _maxAutoRestarts) {
      _wantListening = false;
      _ownsSession = false;
      _showSnack('انتهت جلسة الإملاء — اضغط المايك للمتابعة');
      return;
    }
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 280), () {
      if (!mounted || !_wantListening || !_ownsSession) return;
      if (_speech.isListening) return;
      _autoRestartCount++;
      unawaited(_startListening(isRestart: true));
    });
  }

  bool _isTransientError(String code) {
    return code.contains('error_no_match') ||
        code.contains('error_speech_timeout') ||
        code.contains('error_busy') ||
        code.contains('error_client') ||
        code.contains('error_retry');
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted || !_ownsSession) return;

    final code = error.errorMsg;

    if (_isTransientError(code)) {
      // أخطاء عابرة: أعد الاستماع بهدوء إن الجلسة ما زالت مطلوبة.
      if (_wantListening) {
        setState(() {
          _listening = false;
          _starting = false;
        });
        _scheduleAutoRestart();
        return;
      }
      if (_speech.isListening) return;
      setState(() {
        _listening = false;
        _starting = false;
      });
      if (!_heardWords) {
        _showSnack('لم يُسمع كلام — اضغط المايك وتحدّث مجدداً');
      }
      return;
    }

    if (code.contains('error_permission')) {
      _wantListening = false;
      _ownsSession = false;
      _initFuture = null;
      setState(() {
        _listening = false;
        _starting = false;
      });
      _showSnack('يُرجى السماح باستخدام الميكروفون');
      return;
    }

    if (code.contains('error_network') ||
        code.contains('error_network_timeout') ||
        code.contains('error_server') ||
        code.contains('error_too_many_requests')) {
      _cachedOnline = false;
      _onlineCheckedAt = DateTime.now();
      if (_wantListening) {
        setState(() {
          _listening = false;
          _starting = false;
        });
        // أعد المحاولة على الجهاز عند فشل الشبكة.
        _scheduleAutoRestart();
        return;
      }
      if (_speech.isListening) return;
      setState(() {
        _listening = false;
        _starting = false;
      });
      _showSnack('تحقق من الإنترنت أو حزمة Google العربية للصوت');
      return;
    }

    if (_speech.isListening) return;
    setState(() {
      _listening = false;
      _starting = false;
    });
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _toggleListening() async {
    if (!widget.enabled || _starting) return;

    if (_blockSpeechEngineOnPlatform) {
      _showSnack('الإملاء بالصوت غير متاح على macOS حالياً — اكتب يدوياً');
      return;
    }

    if (_wantListening || _listening || _speech.isListening) {
      await _stopByUser();
      return;
    }

    setState(() {
      _starting = true;
      _wantListening = true;
      _ownsSession = true;
      _heardWords = false;
      _autoRestartCount = 0;
      _soundLevel = 0;
    });

    _prefixBeforeSession = widget.controller.text.trim();
    _sessionCommitted = '';
    _currentPartial = '';

    await _startListening(isRestart: false);
  }

  Future<void> _stopByUser() async {
    _restartTimer?.cancel();
    _wantListening = false;
    _ownsSession = false;

    if (_currentPartial.isNotEmpty) {
      _sessionCommitted = mergeSpeechChunk(_sessionCommitted, _currentPartial);
      _currentPartial = '';
      _applySessionTextToField();
    }

    if (_speech.isListening) {
      await _speech.stop();
    }
    if (mounted) {
      setState(() {
        _listening = false;
        _starting = false;
        _soundLevel = 0;
      });
    }
  }

  Future<void> _startListening({required bool isRestart}) async {
    if (!_wantListening || !mounted) return;

    try {
      final ready = await _ensureInitialized();
      if (!ready || !mounted || !_wantListening) {
        if (mounted) {
          setState(() {
            _starting = false;
            _listening = false;
            _wantListening = false;
            _ownsSession = false;
          });
        }
        return;
      }

      // لا تستدعِ cancel() — يدمّر المتعرف ويبطئ إعادة التشغيل.
      if (_speech.isListening) {
        await _speech.stop();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      final online = await _isOnline();
      // السحابة أدق للهجة العراقية؛ على الجهاز فقط عند عدم الاتصال.
      final onDevice = !online;

      if (!mounted || !_wantListening) return;

      if (!isRestart) {
        setState(() => _starting = true);
      }

      await _speech.listen(
        localeId: _sharedLocaleId,
        onResult: _onResult,
        onSoundLevelChange: _onSoundLevel,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          onDevice: onDevice,
          listenFor: _maxListen,
          // صمت أطول في البداية → يلتقط الكلام الهادئ ولا يقطع بسرعة.
          pauseFor: _heardWords ? _activePause : _initialPause,
          cancelOnError: false,
          autoPunctuation: true,
        ),
      );

      if (!mounted) return;
      // لا ننتظر 450ms — onStatus يضبط الحالة؛ إن بدأ فوراً حدّث الواجهة.
      if (_speech.isListening) {
        setState(() {
          _listening = true;
          _starting = false;
        });
      } else if (_wantListening) {
        // بعض الأجهزة تتأخر قليلاً قبل listeningStatus.
        setState(() => _starting = false);
      }
    } catch (_) {
      if (!mounted) return;
      if (_wantListening && _autoRestartCount < _maxAutoRestarts) {
        _scheduleAutoRestart();
        return;
      }
      setState(() {
        _listening = false;
        _starting = false;
        _wantListening = false;
        _ownsSession = false;
      });
      _showSnack('تعذّر تشغيل المايك — حاول مرة أخرى');
    }
  }

  void _onSoundLevel(double level) {
    if (!mounted || !_ownsSession) return;
    // المستوى من المحرك غالباً سالب (dB)؛ حوّله لإشارة مرئية ناعمة.
    final normalized = ((level + 2) / 10).clamp(0.0, 1.0);
    if ((normalized - _soundLevel).abs() < 0.05 && normalized > 0) return;
    setState(() => _soundLevel = normalized.toDouble());
    final h = widget.holdState?.value;
    if (_holding && h != null) _setHold(h.copyWith(level: normalized.toDouble()));
    _soundDecayTimer?.cancel();
    _soundDecayTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (_soundLevel > 0) setState(() => _soundLevel = 0);
    });
  }

  String _composeSessionText() {
    final body = _currentPartial.isEmpty
        ? _sessionCommitted
        : mergeSpeechChunk(_sessionCommitted, _currentPartial);
    if (_prefixBeforeSession.isEmpty) return body;
    if (body.isEmpty) return _prefixBeforeSession;
    return '$_prefixBeforeSession $body';
  }

  void _applySessionTextToField() {
    widget.controller.text = _composeSessionText();
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    widget.onTextUpdated?.call();
  }

  void _commitCurrentPartialIfNewSegment(String incoming) {
    if (_currentPartial.isEmpty) return;
    if (isSpeechSameOrRefinement(_currentPartial, incoming)) return;
    _sessionCommitted = mergeSpeechChunk(_sessionCommitted, _currentPartial);
    _currentPartial = '';
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!_ownsSession) return;
    final spoken = polishIraqiSpeechText(result.recognizedWords);
    if (spoken.isEmpty) return;

    final wasFirst = !_heardWords;
    _heardWords = true;

    // بعد أول كلام: قصّر مهلة الصمت لاستجابة أسرع بين الجمل.
    if (wasFirst) {
      try {
        _speech.changePauseFor(_activePause);
      } catch (_) {}
    }

    if (result.finalResult) {
      _commitCurrentPartialIfNewSegment(spoken);
      _sessionCommitted = mergeSpeechChunk(_sessionCommitted, spoken);
      _currentPartial = '';
    } else {
      _commitCurrentPartialIfNewSegment(spoken);
      _currentPartial = spoken;
    }

    _applySessionTextToField();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = _wantListening || _listening || _starting || _speech.isListening;
    if (active != _reportedActive) {
      _reportedActive = active;
      final cb = widget.onListeningChanged;
      if (cb != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) cb(active);
        });
      }
    }
    final hearing = active && _soundLevel > 0.12;
    final pulse = hearing ? (0.55 + 0.45 * math.min(1.0, _soundLevel)) : 1.0;

    final button = IconButton(
      // مع الضغط المطوّل لا تلميح: التلميح يأخذ الضغطة المطوّلة فلا يبدأ التسجيل. الاسم يبقى لقارئ الشاشة بالأسفل.
      tooltip: _holdEnabled ? null : widget.tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: widget.size, minHeight: widget.size),
      onPressed: !widget.enabled ? null : () => unawaited(_holding ? _finishHold(send: true) : _toggleListening()),
      icon: Transform.scale(
        scale: pulse,
        child: Icon(
          active ? Icons.mic_rounded : Icons.mic_none_rounded,
          color: hearing
              ? cs.error
              : (active
                    ? cs.error.withValues(alpha: 0.85)
                    // الكحلي يختفي على الخلفية الداكنة.
                    : (cs.brightness == Brightness.dark ? cs.onSurface : cs.primary)),
        ),
      ),
    );
    if (!_holdEnabled || !widget.enabled) return button;
    // ط8: الضغطة القصيرة كما هي (تبدأ وتوقف)، والمطوّلة تسجّل مثل واتساب.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => unawaited(_startHold()),
      onLongPressMoveUpdate: (d) => _moveHold(d.offsetFromOrigin),
      onLongPressEnd: (_) => _endHold(),
      onLongPressCancel: () {
        if (_holding) unawaited(_finishHold(send: false));
      },
      child: Semantics(
        button: true,
        label: widget.tooltip,
        hint: 'اضغط مطوّلاً وتكلّم',
        child: button,
      ),
    );
  }
}
