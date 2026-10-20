/// معرفة شاشة الخدمات والسعر الأساسي.
library;

abstract final class OilServicesKnowledge {
  static const packSnippet = '''
شاشة الخدمات وأسعارها (من قائمة غيار الزيت الفرعية):
- سعر تبديل الزيت الأساسي: مبلغ ثابت يُضاف لكل بطاقة غيار جديدة. يُحفظ محلياً للمحل. ليس سعر لتر الماركة في كتالوج الزيت.
- خدمات إضافية: كتالوج أسماء وأسعار تُختار داخل البطاقة عند الحاجة.
- الوصول: سجل الغيارات أو محور غيار الزيت → «الخدمات وأسعارها».
خطأ شائع: تعديل سعر اللتر في كتالوج الماركات بدل السعر الأساسي أو العكس.
''';

  static String? matchSnippet(String normalizedQuestion) {
    final q = normalizedQuestion;
    if (q.contains('سعر اساسي') ||
        q.contains('السعر الاساسي') ||
        q.contains('سعر تبديل') ||
        q.contains('خدمات اضاف') ||
        q.contains('الخدمات واسعار') ||
        q.contains('الخدمات وأسعار') ||
        q.contains('اسعار الخدمات') ||
        q.contains('أسعار الخدمات')) {
      return packSnippet.trim();
    }
    return null;
  }
}
