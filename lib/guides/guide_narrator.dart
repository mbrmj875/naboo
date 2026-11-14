import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_tts/flutter_tts.dart';

import '../utils/app_logger.dart';

/// متحدث عربي أوفلاين — يفضّل الأصوات العصبية ويُحسّن صياغة النص للفظ أوضح وأقل روبوتية.
class GuideNarrator {
  GuideNarrator._();
  static final GuideNarrator instance = GuideNarrator._();

  FlutterTts? _tts;
  bool _ready = false;
  bool _enabled = true;
  bool _pluginMissing = false;
  String? _lastError;
  String? _activeLanguage;
  String? _activeVoiceName;

  bool get enabled => _enabled;
  bool get pluginMissing => _pluginMissing;
  String? get lastError => _lastError;
  String? get activeLanguage => _activeLanguage;
  String? get activeVoiceName => _activeVoiceName;

  set enabled(bool value) {
    _enabled = value;
    if (!value) unawaitedStop();
  }

  FlutterTts get _engine => _tts ??= FlutterTts();

  Future<bool> _safe(String label, Future<dynamic> Function() fn) async {
    if (_pluginMissing) return false;
    try {
      await fn();
      return true;
    } on MissingPluginException catch (e) {
      _pluginMissing = true;
      _ready = false;
      _lastError =
          'المتحدث يحتاج إعادة تشغيل كاملة للتطبيق (أوقف التطبيق ثم افتحه من جديد — Hot Reload لا يكفي).';
      AppLogger.warn('guide_tts', '$label MissingPlugin: $e');
      return false;
    } catch (e) {
      AppLogger.warn('guide_tts', '$label skipped: $e');
      return false;
    }
  }

  Future<void> ensureReady() async {
    if (_pluginMissing) return;
    if (_ready) return;

    await _safe('shared', () => _engine.setSharedInstance(true));
    await _safe(
      'iosAudio',
      () => _engine.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      ),
    );

    // محرك Google على أندرويد غالباً أوضح للعربية
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _preferGoogleEngine();
    }

    await _safe('volume', () => _engine.setVolume(1.0));
    // نبرة أخف قليلاً + سرعة أقرب للكلام البشري (البطء الشديد يبدو روبوتياً)
    await _safe('pitch', () => _engine.setPitch(1.06));
    await _safe('rate', () => _engine.setSpeechRate(0.48));
    await _safe('awaitCompletion', () => _engine.awaitSpeakCompletion(true));

    if (_pluginMissing) return;

    final lang = await _pickArabicLanguage();
    if (lang == null) {
      _lastError =
          'لا يتوفر صوت عربي على هذا الجهاز. ثبّت «تحويل النص إلى كلام» من Google بصوت عربي عالي الجودة.';
      _ready = false;
      AppLogger.warn('guide_tts', _lastError!);
      return;
    }

    final langOk = await _safe('language', () => _engine.setLanguage(lang));
    if (!langOk && _pluginMissing) return;
    if (!langOk) {
      _lastError = 'تعذّر ضبط لغة المتحدث العربية';
      _ready = false;
      return;
    }

    _activeLanguage = lang;
    await _preferNaturalArabicVoice(lang);
    _lastError = null;
    _ready = true;
    AppLogger.warn(
      'guide_tts',
      'ready lang=$_activeLanguage voice=${_activeVoiceName ?? "default"}',
    );
  }

  Future<void> _preferGoogleEngine() async {
    try {
      final engines = await _engine.getEngines;
      if (engines is! List) return;
      String? google;
      for (final e in engines) {
        final s = e.toString().toLowerCase();
        if (s.contains('google')) {
          google = e.toString();
          break;
        }
      }
      if (google != null) {
        await _safe('engine', () => _engine.setEngine(google!));
      }
    } catch (e) {
      AppLogger.warn('guide_tts', 'getEngines skipped: $e');
    }
  }

  Future<String?> _pickArabicLanguage() async {
    const preferred = <String>[
      'ar-SA',
      'ar_SA',
      'ar-EG',
      'ar_EG',
      'ar-AE',
      'ar-XA',
      'ar_XA',
      'ar',
    ];

    dynamic langsRaw;
    try {
      if (!_pluginMissing) langsRaw = await _engine.getLanguages;
    } catch (e) {
      if (e is MissingPluginException) {
        _pluginMissing = true;
        _lastError =
            'المتحدث يحتاج إعادة تشغيل كاملة للتطبيق (أوقف التطبيق ثم افتحه من جديد).';
        return null;
      }
    }

    final available = <String>{};
    if (langsRaw is List) {
      for (final item in langsRaw) {
        available.add(item.toString());
      }
    }

    if (available.isNotEmpty) {
      for (final p in preferred) {
        if (available.contains(p)) return p;
      }
      for (final a in available) {
        if (a.toLowerCase().startsWith('ar')) return a;
      }
    }

    for (final p in preferred) {
      try {
        final r = await _engine.isLanguageAvailable(p);
        if (r == true || r == 1) return p;
      } catch (_) {}
    }
    return preferred.first;
  }

  /// يختار أفضل صوت عربي متاح: عصبي/محسّن أولاً، ثم أسماء معروفة بجودة أفضل.
  Future<void> _preferNaturalArabicVoice(String lang) async {
    try {
      final voicesRaw = await _engine.getVoices;
      if (voicesRaw is! List || voicesRaw.isEmpty) return;

      final scored = <({Map<String, String> map, int score, String label})>[];

      for (final raw in voicesRaw) {
        if (raw is! Map) continue;
        final map = <String, String>{
          for (final e in raw.entries)
            e.key.toString(): e.value?.toString() ?? '',
        };
        final locale = (map['locale'] ?? map['localeId'] ?? '').toLowerCase();
        final name = (map['name'] ?? '').toLowerCase();
        final quality = (map['quality'] ?? '').toLowerCase();
        final features = (map['features'] ?? '').toLowerCase();
        final identifier = (map['identifier'] ?? '').toLowerCase();

        final isAr = locale.startsWith('ar') ||
            name.contains('arab') ||
            name.contains('maged') ||
            name.contains('laila') ||
            name.contains('tarik') ||
            name.contains('naayf') ||
            identifier.contains('.ar-') ||
            identifier.contains('.ar_');
        if (!isAr) continue;

        var score = 0;
        // أصوات عصبية / عالية الجودة
        if (name.contains('network') ||
            name.contains('neural') ||
            name.contains('wavenet') ||
            name.contains('studio') ||
            features.contains('neural')) {
          score += 120;
        }
        if (quality.contains('enhanced') ||
            quality.contains('premium') ||
            quality.contains('high') ||
            quality == '2' ||
            quality == '3') {
          score += 80;
        }
        if (identifier.contains('enhanced') ||
            identifier.contains('premium') ||
            identifier.contains('siri')) {
          score += 70;
        }
        // أسماء أصوات عربية أوضح عادةً
        if (name.contains('laila') || name.contains('leila')) score += 40;
        if (name.contains('maged')) score += 35;
        if (name.contains('tarik') || name.contains('tariq')) score += 30;
        if (name.contains('naayf') || name.contains('nasser')) score += 25;
        // تفضيل السعودية/الخليج مع لهجة التطبيق
        final langKey = lang.toLowerCase().replaceAll('_', '-');
        if (locale.contains('sa') || locale.contains(langKey)) score += 25;
        if (locale.contains('eg')) score += 15; // غالباً أوضح في بعض الأجهزة
        // تجنّب أصوات رديئة/قديمة إن وُجدت بدائل
        if (name.contains('compact') && !identifier.contains('enhanced')) {
          score -= 15;
        }
        if ((map['network_required'] ?? '') == '1' ||
            (map['network_required'] ?? '') == 'true') {
          // صوت شبكي قد يكون أجمل لكن نفضّل المحلي إن وُجد عصبي محلي
          score += 10;
        }

        scored.add((
          map: map,
          score: score,
          label: map['name']?.isNotEmpty == true
              ? map['name']!
              : (map['identifier'] ?? locale),
        ));
      }

      if (scored.isEmpty) return;
      scored.sort((a, b) => b.score.compareTo(a.score));
      final best = scored.first;
      final ok = await _safe('voice', () => _engine.setVoice(best.map));
      if (ok) {
        _activeVoiceName = best.label;
      }
    } catch (e) {
      AppLogger.warn('guide_tts', 'setVoice skipped: $e');
    }
  }

  /// يجهّز النص ليُلفظ أوضح: فواصل عربية، إزالة رموز مربكة، تقسيم جمل قصيرة.
  static String humanizeArabicForSpeech(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return t;

    t = t
        .replaceAll('«', '، ')
        .replaceAll('»', '، ')
        .replaceAll('"', ' ')
        .replaceAll('“', ' ')
        .replaceAll('”', ' ')
        .replaceAll('–', '، ')
        .replaceAll('—', '، ')
        .replaceAll('...', '، ')
        .replaceAll('…', '، ')
        .replaceAll(':', '، ')
        .replaceAll('؛', '، ');

    // استبدالات تساعد اللفظ
    t = t
        .replaceAll('واتساب', 'واتس آب')
        .replaceAll('WhatsApp', 'واتس آب')
        .replaceAll('QR', 'كيو آر');
    // "كم" ككلمة مستقلة فقط (لا داخل كيلومتر)
    t = t.replaceAllMapped(
      RegExp(r'(^|[^\u0600-\u06FFa-zA-Z0-9])كم([^\u0600-\u06FFa-zA-Z0-9]|$)'),
      (m) => '${m[1]}كيلومتر${m[2]}',
    );
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  List<String> _speechChunks(String text) {
    final human = humanizeArabicForSpeech(text);
    // تقسيم على الفواصل والنقاط لجمل أقصر = إيقاع أقرب للبشر
    final parts = human
        .split(RegExp(r'[.!?؟!\n]+|،'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length <= 1) return [human];
    // أعد إضافة فاصلة خفيفة بالنطق عبر وقفات بين المقاطع
    return parts;
  }

  Future<bool> speak(String text) async {
    if (!_enabled) return false;
    final t = text.trim();
    if (t.isEmpty) return false;
    if (_pluginMissing) {
      _lastError ??=
          'المتحدث يحتاج إعادة تشغيل كاملة للتطبيق (أوقف التطبيق ثم افتحه من جديد).';
      return false;
    }

    await ensureReady();
    if (_pluginMissing) return false;
    if (!_ready) return false;

    try {
      await _safe('stop', () => _engine.stop());
      final chunks = _speechChunks(t);
      for (var i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        if (i > 0 &&
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android) {
          await _safe('silence', () => _engine.setSilence(220));
        }
        final result = await _engine.speak(chunk);
        final ok = result == 1 ||
            result == true ||
            result == '1' ||
            result == null;
        if (!ok) {
          _lastError = 'تعذّر تشغيل الصوت';
          return false;
        }
      }
      _lastError = null;
      return true;
    } on MissingPluginException catch (_) {
      _pluginMissing = true;
      _lastError =
          'المتحدث يحتاج إعادة تشغيل كاملة للتطبيق (أوقف التطبيق ثم افتحه من جديد).';
      return false;
    } catch (e) {
      _lastError = 'تعذّر تشغيل الصوت';
      AppLogger.warn('guide_tts', 'speak failed: $e');
      return false;
    }
  }

  Future<void> stop() async {
    await _safe('stop', () => _engine.stop());
  }

  void unawaitedStop() {
    unawaited(stop());
  }

  void resetPluginState() {
    _pluginMissing = false;
    _ready = false;
    _lastError = null;
    _activeVoiceName = null;
    _tts = null;
  }
}
