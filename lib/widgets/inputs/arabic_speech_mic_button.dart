import 'dart:async' show Timer, unawaited;
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
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
class ArabicSpeechMicButton extends StatefulWidget {
  const ArabicSpeechMicButton({
    super.key,
    required this.controller,
    this.enabled = true,
    this.onTextUpdated,
    this.tooltip = 'إملاء بالصوت',
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback? onTextUpdated;
  final String tooltip;

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
    // لا تهيئة تلقائية على macOS — تمنع قتل التطبيق عند فتح بطاقة الزيت.
    if (!_blockSpeechEngineOnPlatform) {
      unawaited(
        _ensureSharedInitialized(
          onStatus: _onStatus,
          onError: _onSpeechError,
        ),
      );
      unawaited(_refreshOnlineCache());
    }
  }

  @override
  void dispose() {
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
    final hearing = active && _soundLevel > 0.12;
    final pulse = hearing ? (0.55 + 0.45 * math.min(1.0, _soundLevel)) : 1.0;

    return IconButton(
      tooltip: widget.tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      onPressed: !widget.enabled ? null : () => unawaited(_toggleListening()),
      icon: Transform.scale(
        scale: pulse,
        child: Icon(
          active ? Icons.mic_rounded : Icons.mic_none_rounded,
          color: hearing
              ? cs.error
              : (active ? cs.error.withValues(alpha: 0.85) : cs.primary),
        ),
      ),
    );
  }
}
