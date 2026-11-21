import 'package:flutter_test/flutter_test.dart';

import 'package:naboo/verticals/oil_change/models/wa_oil_followup_rule.dart';
import 'package:naboo/verticals/oil_change/services/wa_oil_followup_copy.dart';

void main() {
  test('toMetaBody maps tokens in order', () {
    const ar = 'مرحباً {الاسم} من {المحل}';
    expect(WaOilFollowupCopy.toMetaBody(ar), 'مرحباً {{1}} من {{2}}');
  });

  test('month default body includes car token', () {
    final body = WaOilFollowupCopy.defaultBodyForUnit(
      WaOilFollowupDelayUnit.month,
    );
    expect(body, contains(WaOilFollowupVars.car));
  });
}
