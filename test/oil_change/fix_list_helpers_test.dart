// إصلاحات اختبار الهاتف: عدّ الزيارات، القراءة الفارغة، ومطابقة عائلة الزيت.
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/oil_product_grades_repository.dart';
import 'package:naboo/utils/arabic_count.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_log_format.dart';

OilPickLine _line(int id, String name, String vis, {int? parent}) =>
    OilPickLine(
      parentProductId: parent,
      parentName: name,
      gradeId: null,
      viscosity: vis,
      linkedProductId: id,
      packs: const [],
    );

void main() {
  test('عدّ الزيارات بالعربية', () {
    expect(arabicVisitsCount(0), 'لا زيارات');
    expect(arabicVisitsCount(1), 'زيارة واحدة');
    expect(arabicVisitsCount(2), 'زيارتان');
    expect(arabicVisitsCount(5), '5 زيارات');
    expect(arabicVisitsCount(10), '10 زيارات');
    expect(arabicVisitsCount(11), '11 زيارة');
    expect(arabicVisitsCount(103), '103 زيارات');
  });

  test('عدّ السيارات بالعربية', () {
    expect(arabicCarsCount(1), 'سيارة واحدة');
    expect(arabicCarsCount(2), 'سيارتان');
    expect(arabicCarsCount(10), '10 سيارات');
    expect(arabicCarsCount(11), '11 سيارة');
    expect(arabicCarsCount(103), '103 سيارات');
  });

  test('القراءة الفارغة «—» بلا وحدة، والمكتوبة بوحدتها', () {
    expect(oilFormatOdoWithUnit('', const {}), '—');
    expect(oilFormatOdoWithUnit(null, const {'odometerUnit': 'mi'}), '—');
    expect(oilFormatOdoWithUnit('85000', const {}), '85000 كم');
    expect(
      oilFormatOdoWithUnit('5000', const {'odometerUnit': 'mi'}),
      '5000 ميل',
    );
  });

  test('عائلة الزيت تُطابق بالاسم واللزوجة ثم بالاسم وحده', () {
    final lines = [
      _line(1, 'Total Quartz', '5W-30', parent: 10),
      _line(2, 'Total Quartz', '10W-40', parent: 10),
      _line(3, 'Mobil 1', '5W-40', parent: 20),
    ];
    expect(
      matchOilPickLineByName(lines, name: ' total quartz ', viscosity: '10w-40')
          ?.linkedProductId,
      2,
    );
    expect(
      matchOilPickLineByName(lines, name: 'Mobil 1', viscosity: '0W-20')
          ?.parentProductId,
      20,
      reason: 'لزوجة غير موجودة: العائلة وحدها',
    );
    expect(matchOilPickLineByName(lines, name: 'Castrol'), isNull);
    expect(matchOilPickLineByName(lines, name: ''), isNull);
  });
}
