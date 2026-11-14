/// معرفة خفيفة لإعدادات عامة تؤثر على غيار الزيت (مسار فقط).
library;

abstract final class OilGlobalSettingsKnowledge {
  static const packSnippet = '''
إعدادات عامة تؤثر على غيار الزيت (شرح المسار فقط، بلا حالة اشتراك سرية):
- بيانات المتجر/الفرع: اسم وهاتف يظهران في رسائل واتساب → الإعدادات → بيانات المتجر.
- تذييل الفواتير/الرسائل: إعدادات → الفواتير (إن وُجد تذييل للرسائل).
- تفعيل عمودي غيار الزيت: الإعدادات → ميزات المتجر → غيار الزيت.
- الترخيص/الاشتراك: يؤثر على إتاحة التطبيق عموماً → الإعدادات → الحساب/الاشتراك.
لا تُرسل للنموذج قيم الاشتراك أو التوكنات أو أرقام سرية.
''';

  static String? matchSnippet(String normalizedQuestion) {
    final q = normalizedQuestion;
    if (q.contains('بيانات المتجر') ||
        q.contains('اسم المحل') ||
        q.contains('تذييل') ||
        q.contains('ميزات المتجر') ||
        q.contains('تفعيل الزيت') ||
        q.contains('اشتراك') ||
        q.contains('ترخيص') ||
        q.contains('اعدادات عامه') ||
        q.contains('إعدادات عامة')) {
      return packSnippet.trim();
    }
    return null;
  }
}
