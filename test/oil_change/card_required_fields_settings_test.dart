// المرحلة 3 — الحقول الإلزامية في بطاقة الغيار من الإعدادات.
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/models/oil_card_required_fields.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_settings.dart';
import 'package:naboo/verticals/oil_change/utils/oil_order_has_oil.dart';

import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  setUp(() async {
    await OilChangeTestHarness.instance.reset();
  });

  test('الافتراضي يطابق السلوك القديم: السيارة واللوحة والعداد والزيت', () async {
    final card = await OilChangeSettings.loadCardSettings();
    final r = card.requiredFields;
    expect(r.isRequired(OilCardField.carName), isTrue);
    expect(r.isRequired(OilCardField.plate), isTrue);
    expect(r.isRequired(OilCardField.odometerCurrent), isTrue);
    expect(r.isRequired(OilCardField.oil), isTrue);
    expect(r.isRequired(OilCardField.carModel), isFalse);
    expect(r.isRequired(OilCardField.engineSize), isFalse);
    expect(r.isRequired(OilCardField.odometerNext), isFalse);
    expect(r.isRequired(OilCardField.technician), isFalse);
  });

  test('المحل يجعل الزيت واللوحة اختيارية والفني إلزامياً', () async {
    await OilChangeSettings.setFieldRequired(OilCardField.oil, false);
    await OilChangeSettings.setFieldRequired(OilCardField.plate, false);
    await OilChangeSettings.setFieldRequired(OilCardField.technician, true);

    final r = (await OilChangeSettings.loadCardSettings()).requiredFields;
    expect(r.isRequired(OilCardField.oil), isFalse);
    expect(r.isRequired(OilCardField.plate), isFalse);
    expect(r.isRequired(OilCardField.technician), isTrue);
    expect(r.isRequired(OilCardField.carName), isTrue, reason: 'لم يتغير');
  });

  test('بطاقة بلا زيت لا تُعدّ بطاقة زيت (لا تذكير غيار)', () {
    expect(oilOrderHasOil({'oilType': '', 'oilSize': '', 'oilLitersUsed': 0}),
        isFalse);
    expect(oilOrderHasOil({'oilType': 'كاسترول 5W-30'}), isTrue);
    expect(oilOrderHasOil({'oilLitersUsed': 4.5}), isTrue);
    expect(oilOrderHasOil({'oilProductId': 12}), isTrue);
  });
}
