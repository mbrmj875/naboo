/// قرار إرسال واتساب عند تصحيح بطاقة غيار مفوترة.
///
/// البطاقة نفسها تبقى (نفس المعرّف واليوم والفاتورة)؛ عند تغيّر رقم الهاتف فقط
/// نعيد إرسال قالب البطاقة الرسمي للرقم الجديد — كإنشاء بطاقة من ناحية الرسالة.
bool oilChangeAmendShouldResendWhatsapp({
  required bool amendInvoicedOrder,
  required String currentPhoneDigits,
  required String? baselinePhoneDigits,
}) {
  if (!amendInvoicedOrder) return false;
  final now = currentPhoneDigits.trim();
  if (now.isEmpty) return false;
  return now != (baselinePhoneDigits ?? '').trim();
}
