import 'dart:async' show unawaited;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// زر مايك داخل حقل النص — اضغط للاستماع ثم يُكتب النص مباشرة في الحقل.
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

  @override
  State<ArabicSpeechMicButton> createState() => _ArabicSpeechMicButtonState();
}

class _ArabicSpeechMicButtonState extends State<ArabicSpeechMicButton> {
  final stt.SpeechToText _speech = stt.SpeechToText();

  var _initialized = false;
  var _listening = false;
  var _starting = false;
  var _heardWords = false;
  String? _localeId;
  String _prefixBeforeSession = '';
  String _sessionCommitted = '';
  String _currentPartial = '';

  @override
  void dispose() {
    unawaited(_speech.stop());
    unawaited(_speech.cancel());
    super.dispose();
  }

  Future<bool> _ensureInitialized() async {
    if (_initialized && _speech.isAvailable) {
      if (await _speech.hasPermission) return true;
      _initialized = false;
    }

    final ok = await _speech.initialize(
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

    _localeId = await _resolveArabicLocale();
    if (_localeId == null) {
      final system = await _speech.systemLocale();
      _localeId = system?.localeId;
    }

    _initialized = true;
    return true;
  }

  Future<String?> _resolveArabicLocale() async {
    final locales = await _speech.locales();
    const preferred = ['ar-IQ', 'ar_SA', 'ar_EG', 'ar'];
    for (final code in preferred) {
      for (final l in locales) {
        if (l.localeId == code) return l.localeId;
      }
    }
    for (final l in locales) {
      if (l.localeId.startsWith('ar')) return l.localeId;
    }
    return null;
  }

  Future<bool> _deviceHasNetwork() async {
    final results = await Connectivity().checkConnectivity();
    return results.any(
      (r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet,
    );
  }

  void _onStatus(String status) {
    if (!mounted) return;
    if (status == stt.SpeechToText.listeningStatus) {
      setState(() => _listening = true);
    } else if (status == stt.SpeechToText.notListeningStatus ||
        status == stt.SpeechToText.doneStatus) {
      setState(() {
        _listening = false;
        _starting = false;
      });
    }
  }

  bool _isTransientError(String code) {
    return code.contains('error_no_match') ||
        code.contains('error_speech_timeout') ||
        code.contains('error_busy') ||
        code.contains('error_client');
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;

    final code = error.errorMsg;

    // أخطاء عابرة أثناء الاستماع — لا نُظهر رسالة ولا نُوقف المايك.
    if (_isTransientError(code)) {
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
      _initialized = false;
      setState(() {
        _listening = false;
        _starting = false;
      });
      _showSnack('يُرجى السماح باستخدام الميكروفون');
      return;
    }

    if (code.contains('error_network') ||
        code.contains('error_network_timeout') ||
        code.contains('error_server')) {
      if (_speech.isListening) return;
      setState(() {
        _listening = false;
        _starting = false;
      });
      _showSnack('تحقق من الإنترنت أو حزمة Google العربية للصوت');
      return;
    }

    // أخطاء أخرى — لا نُقطع الجلسة إن كان المايك ما زال يعمل.
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

    if (_listening || _speech.isListening) {
      if (_currentPartial.isNotEmpty) {
        _sessionCommitted = _mergeChunk(_sessionCommitted, _currentPartial);
        _currentPartial = '';
        _applySessionTextToField();
      }
      await _speech.stop();
      if (mounted) {
        setState(() {
          _listening = false;
          _starting = false;
        });
      }
      return;
    }

    setState(() {
      _starting = true;
      _heardWords = false;
    });

    try {
      final ready = await _ensureInitialized();
      if (!ready || !mounted) return;

      _prefixBeforeSession = widget.controller.text.trim();
      _sessionCommitted = '';
      _currentPartial = '';

      if (_speech.isListening) {
        await _speech.stop();
      }
      await _speech.cancel();

      final online = await _deviceHasNetwork();
      await _speech.listen(
        localeId: _localeId,
        onResult: _onResult,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          onDevice: !online,
          listenFor: const Duration(seconds: 120),
          pauseFor: const Duration(seconds: 8),
          cancelOnError: false,
        ),
      );

      // على بعض الأجهزة listen() تُرجع false لكن المايك يعمل فعلاً.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;

      if (_speech.isListening) {
        setState(() {
          _listening = true;
          _starting = false;
        });
        return;
      }

      setState(() {
        _listening = false;
        _starting = false;
      });
      _showSnack('تعذّر تشغيل المايك — حاول مرة أخرى');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _listening = false;
        _starting = false;
      });
      _showSnack('تعذّر تشغيل المايك — حاول مرة أخرى');
    } finally {
      if (mounted && _starting && !_speech.isListening) {
        setState(() => _starting = false);
      }
    }
  }

  String _joinText(String first, String second) {
    if (first.isEmpty) return second;
    if (second.isEmpty) return first;
    return '$first $second';
  }

  /// يدمج مقطعاً جديداً دون مسح ما سبق — يدعم التوقف القصير ثم متابعة الكلام.
  String _mergeChunk(String existing, String incoming) {
    if (incoming.isEmpty) return existing;
    if (existing.isEmpty) return incoming;
    if (existing == incoming) return existing;
    if (incoming.startsWith(existing)) return incoming;
    if (existing.endsWith(incoming)) return existing;
    return _joinText(existing, incoming);
  }

  String _composeSessionText() {
    final body = _currentPartial.isEmpty
        ? _sessionCommitted
        : _mergeChunk(_sessionCommitted, _currentPartial);
    return _joinText(_prefixBeforeSession, body);
  }

  void _applySessionTextToField() {
    widget.controller.text = _composeSessionText();
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    widget.onTextUpdated?.call();
  }

  /// هل [later] امتداد أو تصحيح لـ [earlier] (نفس المقطع)؟
  bool _isSameOrRefinement(String earlier, String later) {
    if (earlier.isEmpty || later.isEmpty) return true;
    final e = earlier.trim();
    final l = later.trim();
    if (e == l) return true;
    if (l.startsWith(e) || e.startsWith(l)) return true;
    return false;
  }

  /// يثبّت المقطع الجاري في الذاكرة قبل بدء مقطع جديد.
  void _commitCurrentPartialIfNewSegment(String incoming) {
    if (_currentPartial.isEmpty) return;
    if (_isSameOrRefinement(_currentPartial, incoming)) return;
    _sessionCommitted = _mergeChunk(_sessionCommitted, _currentPartial);
    _currentPartial = '';
  }

  void _onResult(SpeechRecognitionResult result) {
    final spoken = result.recognizedWords.trim();
    if (spoken.isEmpty) return;

    _heardWords = true;

    if (result.finalResult) {
      _commitCurrentPartialIfNewSegment(spoken);
      _sessionCommitted = _mergeChunk(_sessionCommitted, spoken);
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
    final active = _listening || _starting || _speech.isListening;

    return IconButton(
      tooltip: widget.tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      onPressed: !widget.enabled ? null : () => unawaited(_toggleListening()),
      icon: Icon(
        active ? Icons.mic_rounded : Icons.mic_none_rounded,
        color: active ? cs.error : cs.primary,
      ),
    );
  }
}
