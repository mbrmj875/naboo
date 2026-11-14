import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/guides/guide_intent_matcher.dart';
import 'package:naboo/guides/guide_tour.dart';

void main() {
  const matcher = GuideIntentMatcher();

  test('matches oil first-run intent with high confidence', () {
    final m = matcher.match('كيف أسجّل غيار زيت؟');
    expect(m, isNotNull);
    expect(m!.tourId, GuideTourIds.oilFirstRun);
    expect(m.confidence, greaterThanOrEqualTo(GuideIntentMatcher.highConfidence));
  });

  test('matches whatsapp intent', () {
    final m = matcher.match('ليش ما يوصل واتساب للزبون');
    expect(m, isNotNull);
    expect(m!.tourId, GuideTourIds.oilWhatsapp);
  });

  test('matches pending tab intent', () {
    final m = matcher.match('وين الفواتير المعلّقة');
    expect(m, isNotNull);
    expect(m!.tourId, GuideTourIds.oilPendingTab);
  });

  test('matches plate autofill intent', () {
    final m = matcher.match('كيف أجيب بيانات السيارة من رقم اللوحة');
    expect(m, isNotNull);
    expect(m!.tourId, GuideTourIds.oilPlateAutofill);
  });

  test('returns null for unrelated question', () {
    final m = matcher.match('كم سعر الدولار اليوم');
    expect(m, isNull);
  });
}
