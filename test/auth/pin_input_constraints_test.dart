import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/utils/pin_input_constraints.dart';

void main() {
  group('PinInputConstraints', () {
    test('validateRequired rejects empty and non-4-digit', () {
      expect(PinInputConstraints.validateRequired(null), isNotNull);
      expect(PinInputConstraints.validateRequired(''), isNotNull);
      expect(PinInputConstraints.validateRequired('123'), isNotNull);
      expect(PinInputConstraints.validateRequired('12345'), isNotNull);
      expect(PinInputConstraints.validateRequired('12ab'), isNotNull);
      expect(PinInputConstraints.validateRequired('2580'), isNull);
    });

    test('validateRequired rejects weak pins', () {
      expect(PinInputConstraints.validateRequired('1234'), isNotNull);
      expect(PinInputConstraints.validateRequired('0000'), isNotNull);
      expect(PinInputConstraints.validateRequired('4321'), isNotNull);
    });

    test('validateOptional allows empty but rejects weak', () {
      expect(PinInputConstraints.validateOptional(''), isNull);
      expect(PinInputConstraints.validateOptional('123'), isNotNull);
      expect(PinInputConstraints.validateOptional('1357'), isNull);
      expect(PinInputConstraints.validateOptional('5678'), isNotNull);
    });

    test('isWeak detects repeats and sequences', () {
      expect(PinInputConstraints.isWeak('0000'), isTrue);
      expect(PinInputConstraints.isWeak('9999'), isTrue);
      expect(PinInputConstraints.isWeak('1234'), isTrue);
      expect(PinInputConstraints.isWeak('4321'), isTrue);
      expect(PinInputConstraints.isWeak('0123'), isTrue);
      expect(PinInputConstraints.isWeak('3210'), isTrue);
      expect(PinInputConstraints.isWeak('2580'), isFalse);
      expect(PinInputConstraints.isWeak('1357'), isFalse);
      expect(PinInputConstraints.isWeak('2468'), isFalse);
    });

    test('matches requires equal valid pins', () {
      expect(PinInputConstraints.matches('2580', '2580'), isTrue);
      expect(PinInputConstraints.matches('2580', '1357'), isFalse);
      expect(PinInputConstraints.matches('123', '123'), isFalse);
    });

    test('formatters cap at 4 digits', () {
      expect(PinInputConstraints.formatters.length, 2);
      expect(PinInputConstraints.length, 4);
    });
  });
}
