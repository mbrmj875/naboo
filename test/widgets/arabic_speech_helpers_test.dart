import 'package:naboo/widgets/inputs/arabic_speech_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pickBestArabicSpeechLocale', () {
    test('يفضّل العراقي عند توفره بأي شكل', () {
      expect(
        pickBestArabicSpeechLocale(const ['en_US', 'ar-IQ', 'ar_SA']),
        'ar-IQ',
      );
      expect(
        pickBestArabicSpeechLocale(const ['ar_EG', 'ar_IQ']),
        'ar_IQ',
      );
    });

    test('يفضّل الخليج عند غياب العراقي', () {
      expect(
        pickBestArabicSpeechLocale(const ['ar_EG', 'ar_KW', 'en_US']),
        'ar_KW',
      );
    });

    test('يرجع أي عربي إن لم يوجد مفضّل', () {
      expect(
        pickBestArabicSpeechLocale(const ['fr_FR', 'ar_MA']),
        'ar_MA',
      );
    });

    test('null عند عدم وجود عربي', () {
      expect(pickBestArabicSpeechLocale(const ['en_US', 'fr_FR']), isNull);
    });
  });

  group('mergeSpeechChunk', () {
    test('يدمج ويوسّع دون تكرار', () {
      expect(mergeSpeechChunk('', 'مرحبا'), 'مرحبا');
      expect(mergeSpeechChunk('مرحبا', 'مرحبا شلونك'), 'مرحبا شلونك');
      expect(mergeSpeechChunk('مرحبا شلونك', 'شلونك'), 'مرحبا شلونك');
      expect(mergeSpeechChunk('أ', 'ب'), 'أ ب');
    });
  });

  group('polishIraqiSpeechText', () {
    test('يحوّل الأرقام ويصحّح أخطاء عراقية شائعة', () {
      expect(polishIraqiSpeechText('السعر ١٢٣ دينار'), 'السعر 123 دينار');
      expect(polishIraqiSpeechText('شلونج انت'), 'شلونك انت');
      expect(polishIraqiSpeechText('زيت الماكينة'), 'زيت المكينة');
    });
  });
}
