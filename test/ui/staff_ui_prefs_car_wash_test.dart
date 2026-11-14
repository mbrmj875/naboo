import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/staff_ui_prefs_repository.dart';

void main() {
  group('StaffUiPrefs.fromJson', () {
    test('يحافظ على الإخفاء عند false', () {
      expect(
        StaffUiPrefs.fromJson({'carWashButtonVisible': false})
            .carWashButtonVisible,
        isFalse,
      );
    });

    test('يقبل false كنص أو صفر', () {
      expect(
        StaffUiPrefs.fromJson({'carWashButtonVisible': 'false'})
            .carWashButtonVisible,
        isFalse,
      );
      expect(
        StaffUiPrefs.fromJson({'carWashButtonVisible': 0})
            .carWashButtonVisible,
        isFalse,
      );
    });

    test('من JSON string', () {
      expect(
        StaffUiPrefs.fromJsonString('{"carWashButtonVisible":false}')
            .carWashButtonVisible,
        isFalse,
      );
    });
  });
}
