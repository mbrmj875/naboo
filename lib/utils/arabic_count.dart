/// عدّ الزيارات بالعربية الصحيحة: «زيارة واحدة»، «زيارتان»، «5 زيارات»،
/// «11 زيارة». الصفر «لا زيارات».
String arabicVisitsCount(int n) {
  if (n <= 0) return 'لا زيارات';
  if (n == 1) return 'زيارة واحدة';
  if (n == 2) return 'زيارتان';
  final mod100 = n % 100;
  if (mod100 >= 3 && mod100 <= 10) return '$n زيارات';
  return '$n زيارة';
}

/// عدّ السيارات: «سيارة واحدة»، «سيارتان»، «5 سيارات»، «11 سيارة»، «0 سيارة».
String arabicCarsCount(int n) {
  if (n == 1) return 'سيارة واحدة';
  if (n == 2) return 'سيارتان';
  final mod100 = n % 100;
  if (mod100 >= 3 && mod100 <= 10) return '$n سيارات';
  return '$n سيارة';
}
