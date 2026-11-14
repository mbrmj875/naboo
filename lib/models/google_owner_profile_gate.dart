/// حالة ملف المالك بعد hydrate — يحدد OTP أو إكمال ملف أو bootstrap.
enum GoogleOwnerProfileGate {
  /// hash محلي جاهز — متابعة bootstrap.
  complete,

  /// سر على السحابة لكن SQLite فارغ — OTP إلزامي.
  cloudHasSecretButLocalEmpty,

  /// لا سر سحابي ولا hash محلي — مستخدم جديد.
  needsCompleteProfile,
}
