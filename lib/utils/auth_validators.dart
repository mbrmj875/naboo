/// تحقق موحّد لحقول التسجيل/الدخول (جوال عراقي + PIN).
abstract final class AuthValidators {
  static final RegExp _iraqiPhone = RegExp(r'^07\d{9}$');
  static final RegExp _pin = RegExp(r'^\d{4}$');

  static bool isValidIraqiPhone(String s) =>
      _iraqiPhone.hasMatch(s.trim());

  static bool isValidPin(String s) => _pin.hasMatch(s.trim());
}
