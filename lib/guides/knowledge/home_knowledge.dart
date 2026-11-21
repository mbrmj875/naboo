/// معرفة الشاشة الرئيسية — البطاقات والاختصارات الظاهرة.
library;

import 'car_wash_knowledge.dart';

abstract final class HomeKnowledge {
  static const packSnippet = '''
الشاشة الرئيسية (عند تفعيل عمودي غيار الزيت):
- زر رئيسي: «غيار زيت جديد» → بطاقة تسجيل غيار زيت.
- زر ثانوي (اختياري): «غسيل السيارات» / «بطاقة غسيل سريعة» → بطاقة غسيل.
- بلاطات سريعة لسجل الغيارات وواتساب وغيرها حسب التخصيص.
تخصيص الظهور والترتيب: الإعدادات → «تخصيص الشاشة الرئيسية».
''';

  static String? matchSnippet(String normalizedQuestion) {
    final q = normalizedQuestion;
    if (q.contains('الرئيسيه') ||
        q.contains('الرئيسية') ||
        q.contains('شاشه الرئيسيه') ||
        q.contains('شاشة الرئيسية') ||
        q.contains('بطاقه على الرئيسيه') ||
        q.contains('زر على الرئيسيه') ||
        q.contains('اختصار') ||
        q.contains('تخصيص الشاشه') ||
        q.contains('تخصيص الشاشة')) {
      return '${packSnippet.trim()}\n---\n${CarWashKnowledge.packSnippet.trim()}';
    }
    return null;
  }
}
