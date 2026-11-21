import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/utils/customer_validation.dart';

void main() {
  final formatter = CustomerValidation.iraqiMobileInputFormatters().single;

  TextEditingValue apply(TextEditingValue oldValue, TextEditingValue newValue) {
    return formatter.formatEditUpdate(oldValue, newValue);
  }

  test('تحديد 07 ثم كتابة رقم يضع الرقم بعدها', () {
    final next = apply(
      const TextEditingValue(
        text: '07',
        selection: TextSelection(baseOffset: 0, extentOffset: 2),
      ),
      const TextEditingValue(
        text: '4',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    expect(next.text, '074');
    expect(next.selection.extentOffset, 3);
  });

  test('الكتابة في نهاية الرقم تبقى في النهاية', () {
    final next = apply(
      const TextEditingValue(
        text: '0746',
        selection: TextSelection.collapsed(offset: 4),
      ),
      const TextEditingValue(
        text: '07468',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    expect(next.text, '07468');
    expect(next.selection.extentOffset, 5);
  });

  test('المسح عند بداية الرقم لا يحذف 07', () {
    final next = apply(
      const TextEditingValue(
        text: '074',
        selection: TextSelection.collapsed(offset: 2),
      ),
      const TextEditingValue(
        text: '04',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    expect(next.text, '074');
    expect(next.selection.extentOffset, 2);
  });
}
