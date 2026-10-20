/// معرفة تشغيلية ثابتة لإعدادات سجل غيار الزيت (بدون قيم حية).
library;

class OilSettingsKnowledgeEntry {
  const OilSettingsKnowledgeEntry({
    required this.key,
    required this.titleAr,
    required this.whyAr,
    required this.howToReachAr,
    required this.commonMistakeAr,
  });

  final String key;
  final String titleAr;
  final String whyAr;
  final String howToReachAr;
  final String commonMistakeAr;

  String toPromptSnippet() =>
      '$titleAr: $whyAr الوصول: $howToReachAr خطأ شائع: $commonMistakeAr';
}

abstract final class OilSettingsKnowledge {
  static const howToOpenSheet =
      'من سجل غيارات الزيت اضغط أيقونة إعدادات غيار الزيت (ضبط) أعلى الشاشة.';

  static const entries = <OilSettingsKnowledgeEntry>[
    OilSettingsKnowledgeEntry(
      key: 'biz.oil.stock_from_warehouse',
      titleAr: 'صرف الزيت من المخزون',
      whyAr:
          'عند التشغيل يخصم النظام لترات الزيت من عائلة المخزون عند حفظ البطاقة. عند الإيقاف يبقى التسجيل يدوياً بلا خصم مخزون.',
      howToReachAr: howToOpenSheet,
      commonMistakeAr:
          'تفعيل الصرف دون تجهيز عائلات الزيت في المخزون يمنع الخصم الصحيح.',
    ),
    OilSettingsKnowledgeEntry(
      key: 'biz.oil.hydraulic_stock_from_warehouse',
      titleAr: 'صرف الهيدروليك من المخزون',
      whyAr:
          'نفس فكرة صرف الزيت لكن لعائلات الهيدروليك (كير/باور): خصم لترات عند الحفظ إن كان مفعّلاً.',
      howToReachAr: howToOpenSheet,
      commonMistakeAr:
          'خلط تسجيل الهيدروليك اليدوي مع تفعيل الصرف دون اختيار عائلة المخزون.',
    ),
    OilSettingsKnowledgeEntry(
      key: 'biz.oil.whatsapp_after_save',
      titleAr: 'إرسال تلقائي للزبون (واتساب المحل)',
      whyAr:
          'بعد حفظ بطاقة جديدة تُرسل الرسالة من رقم المحل دون فتح تطبيق واتساب. يحتاج ربط واتساب ناجحاً ورقم زبون صحيح.',
      howToReachAr: howToOpenSheet,
      commonMistakeAr:
          'تفعيل التلقائي بينما واتساب غير مربوط أو بدون رقم زبون — لن تصل الرسالة.',
    ),
    OilSettingsKnowledgeEntry(
      key: 'biz.oil.whatsapp_manual_after_save',
      titleAr: 'فتح واتساب يدوياً بعد الحفظ',
      whyAr:
          'يفتح واتساب برسالة جاهزة بعد الحفظ. متعارض مع الإرسال التلقائي — لا يعملان معاً.',
      howToReachAr: howToOpenSheet,
      commonMistakeAr: 'ترك التلقائي واليدوي معاً؛ النظام يُبقي أحدهما فقط.',
    ),
    OilSettingsKnowledgeEntry(
      key: 'biz.oil.whatsapp_ask_rating',
      titleAr: 'طلب تقييم من الزبون في الرسالة',
      whyAr:
          'يُلحق دعوة تقييم (من 1 إلى 10 أو ملاحظة) بنهاية رسالة واتساب بعد الحفظ.',
      howToReachAr: howToOpenSheet,
      commonMistakeAr:
          'توقّع ظهور التقييم في السجل دون إرسال رسالة أصلاً (ربط/رقم).',
    ),
  ];

  static String packSnippet() {
    final buf = StringBuffer(
      'معرفة إعدادات غيار الزيت (لوحة السجل). الوصول: $howToOpenSheet\n',
    );
    for (final e in entries) {
      buf.writeln('- ${e.toPromptSnippet()}');
    }
    buf.writeln(
      '- ربط واتساب المحل: من نفس اللوحة أو أيقونة QR في شريط السجل.',
    );
    return buf.toString().trim();
  }

  static String? matchSnippet(String normalizedQuestion) {
    final q = normalizedQuestion;
    if (q.contains('اعداد') ||
        q.contains('ضبط') ||
        q.contains('مفتاح') ||
        q.contains('صرف الزيت') ||
        q.contains('صرف الهيدروليك') ||
        q.contains('تلقائي') ||
        q.contains('تقييم')) {
      return packSnippet();
    }
    return null;
  }
}
