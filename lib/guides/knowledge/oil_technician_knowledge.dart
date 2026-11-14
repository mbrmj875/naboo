/// معرفة فنية لغيار الزيت في أجواء العراق — اقتراحات تشغيلية للمحل (ليست بديلاً عن دليل الشركة المصنّعة).
library;

/// أقسام معرفة الفني تُختار حسب السؤال ثم تُجمع دون تجاوز [maxSnippetChars].
///
/// ملاحظة مسار لاحق: `GuidePageKnowledge.select` قد يضيف [packSnippet] كاملاً على
/// `oilChangeCreate` عند غياب مطابقة صريحة — ذلك ما زال يعرّض الناتج للقصّ الأعمى
/// عند 2200 في `select` ويُعالَج في خطوة منفصلة.
abstract final class OilTechnicianKnowledge {
  /// يطابق `GuidePageKnowledge.maxChars`؛ لا ترفع الحد من هنا.
  static const maxSnippetChars = 2200;

  static const rolePack = '''
دور المساعد كفني غيار زيت محترف في العراق:
- اسأل أو استنتج إن نقص: نوع السيارة/الموديل التقريبي، بنزين أم ديزل، عداد تقريبي (كم)، هل المحرك يستهلك زيتاً أو يدخّن، وهل الزيت السابق معدني/نصف تخليقي/تخليقي.
- قدّم اقتراحاً واضحاً: اللزوجة (مثل 5W-30) + نوع الزيت + لماذا تناسب أجواء العراق + متى يُغيَّر تقريباً.
- ذكّر دائماً: الأولوية لدليل الشركة المصنّعة (كتيب الصيانة / غطاء الزيت). اقتراحك عملي للمحل العراقي إن لم يتوفر الدليل.
- لا تخترع أسعاراً ولا ماركات إلزامية؛ اذكر أمثلة شائعة فقط كخيارات.
''';

  static const climatePack = '''
أجواء العراق وتأثيرها على الزيت:
- صيف حار جداً (غالباً 40–50°م في الوسط والجنوب): يفضّل زيت يتحمّل الحرارة ولا يرقّ بسرعة؛ اللزوجات الشائعة عملياً: 5W-30، 5W-40، 10W-40، وللمحركات الأقدم أو عالية العداد أحياناً 15W-40 أو 20W-50.
- شتاء معتدل جنوباً وأبرد شمالاً: رقم W المنخفض (0W/5W) يساعد الإقلاع البارد؛ في البصرة والجنوب 5W أو 10W كافٍ غالباً.
- غبار وازدحام ورحلات قصيرة متكررة = ظروف قاسية: قصّر فترة الغيار قليلاً عن الجدول المثالي.
''';

  static const viscosityPack = '''
قراءة اللزوجة باختصار:
- الرقم قبل W: سيولة عند البرد (أقل = أسهل إقلاع بارد).
- الرقم بعد W: سماكة عند التشغيل الحار (أعلى = حماية أسمك في الحر/المحركات المستهلكة).
''';

  static const practicalPack = '''
اقتراحات عملية شائعة في العراق (إرشادية):
1) سيارات حديثة يابانية/كورية بنزين (تويوتا، هوندا، كيا، هيونداي) عداد منخفض–متوسط + توصية حديثة: غالباً 0W-20 أو 5W-30 تخليقي إن نصّت الشركة؛ إن لم يُعرف الدليل وفي الحر العراقي: 5W-30 أو 5W-40 تخليقي جودة API SP/SN أو أحدث.
2) سيارات بنزين متوسطة العمر شائعة في العراق (عداد تقريباً 80–200 ألف كم): غالباً 5W-40 أو 10W-40 تخليقي أو نصف تخليقي؛ إن بدأ يستهلك زيتاً قليلاً ارتفع بلطف نحو 10W-40 / 15W-40 حسب حالة المحرك.
3) محركات أقدم أو عداد عالي جداً + استهلاك زيت أو صوت طرق خفيف: كثير من الفنيين يستخدم 15W-40 أو 20W-50 معدني/نصف تخليقي بحذر — وضّح أنه حل عملي لا يغني عن فحص تسريب/ضغط.
4) ديزل بيكب وشاحنات خفيفة شائعة: غالباً 15W-40 ديزل بمواصفة مناسبة (مثل API CK-4/CJ-4 حسب المتاح) وفترات أقصر مع الغبار والعمل الشاق.
5) سيارات أوروبية حديثة تتطلب مواصفات ACEA/VW/MB معينة: لا تخمّن المواصفة الدقيقة؛ اطلب الدليل أو غطاء الزيت، وإن اضطررت اقترح تخليقي 5W-30/5W-40 عالي الجودة مع التنبيه لمطابقة الموافقة.
''';

  static const intervalPack = '''
فترات الغيار التقريبية في العراق (ظروف قاسية):
- تخليقي جيد: غالباً كل 7–10 آلاف كم أو 6 أشهر أيّهما أقرب (أقصر مع غبار/زحام).
- نصف تخليقي: غالباً 5–7 آلاف كم.
- معدني: غالباً 3–5 آلاف كم.
- مع الغيار: فلتر زيت جديد دائماً؛ راجع فلتر الهواء إن كان مسدوداً من الغبار.
''';

  static const stylePack = '''
نصائح فني محترف عند الرد:
- ابدأ بتوصية واحدة واضحة ثم بديل واحد.
- اربط التوصية بالحر والعداد ونوع المحرك.
- حذّر من خلط زيوت مختلفة المواصفات بلا داعٍ، ومن زيادة الزيت فوق العلامة.
- إن السؤال عن تسجيل البطاقة في نابو: اربط باختصار ثم ارجع للتوصية الفنية أو افتح جولة التطبيق إن طُلبت خطوات الشاشة.
''';

  /// الحزمة الكاملة (R+C+V+P+I+S) — للتوافق مع المسارات التي ما زالت تطلب النص كله.
  static String get packSnippet =>
      [
        rolePack,
        climatePack,
        viscosityPack,
        practicalPack,
        intervalPack,
        stylePack,
      ].map((s) => s.trim()).join('\n\n');

  static String? matchSnippet(String normalizedQuestion) {
    // السؤال يصل مطبّعاً من GuidePageKnowledge؛ نطبّع المفاتيح بنفس القواعد
    // حتى لا تفشل صيغ مثل «أي زيت» / «أجواء» بعد أ→ا.
    final q = _normalizeHit(normalizedQuestion);
    if (!_isTechnicianQuestion(q)) return null;

    final sections = _sectionsForQuestion(q);
    return _assembleWithinBudget(sections);
  }

  /// ترتيب الإدراج: R دائماً أولاً، ثم الموضوعي، ثم S، ثم أي متبقٍ حسب القائمة.
  static List<String> _sectionsForQuestion(String q) {
    final wantsNaboo = _wantsNabooRecording(q);
    final wantsVisc = _wantsViscosity(q);
    final wantsClimate = _wantsClimate(q);
    final wantsInterval = _wantsInterval(q);
    final wantsService = _wantsOilService(q);

    if (wantsNaboo) {
      return [rolePack, stylePack];
    }

    if (wantsVisc) {
      final out = <String>[rolePack, viscosityPack, practicalPack];
      if (wantsClimate) out.add(climatePack);
      out.add(stylePack);
      return out;
    }

    if (wantsClimate) {
      final out = <String>[rolePack, climatePack, practicalPack];
      // V عند الحاجة فقط (درجات/لزوجة صريحة — هنا wantsVisc كان false)
      out.add(stylePack);
      return out;
    }

    if (wantsInterval) {
      final out = <String>[rolePack, intervalPack];
      if (wantsClimate ||
          q.contains('غبار') ||
          q.contains('قاسي') ||
          q.contains('ظروف')) {
        out.add(climatePack);
      }
      out.add(stylePack);
      return out;
    }

    if (wantsService) {
      return [rolePack, stylePack];
    }

    // ماركات / عداد / محرك / فني / استهلاك… → توصيات عملية مع أسلوب الرد
    return [rolePack, practicalPack, stylePack];
  }

  static String _assembleWithinBudget(List<String> wanted) {
    final parts = <String>[];
    for (final raw in wanted) {
      final section = raw.trim();
      if (section.isEmpty) continue;
      final candidate =
          parts.isEmpty ? section : '${parts.join('\n\n')}\n\n$section';
      if (candidate.length <= maxSnippetChars) {
        parts.add(section);
      }
      // لا نُدرج قسماً جزئياً؛ نتخطاه ونُكمِل إن وُجدت أقسام أقصر لاحقاً.
    }
    if (parts.isEmpty) return rolePack.trim();
    return parts.join('\n\n');
  }

  static bool _isTechnicianQuestion(String q) {
    const hits = <String>[
      'لزوج',
      'لزوجة',
      'زيت مناسب',
      'اي زيت',
      'أي زيت',
      'شنو الزيت',
      'ما الزيت',
      'نوع الزيت',
      'زيوت',
      'تخليقي',
      'معدني',
      'نصف تخليقي',
      '5w',
      '10w',
      '15w',
      '20w',
      'w-30',
      'w-40',
      'w-50',
      'فني',
      'غيار زيت',
      'غيار الزيت',
      'تغيير زيت',
      'تغيير الزيت',
      'تبديل زيت',
      'تبديل الزيت',
      'ابدل الزيت',
      'ابدّل الزيت',
      'اغير الزيت',
      'اغيّر الزيت',
      'محرك',
      'عداد',
      'كم قطع',
      'كيلو',
      'تويوتا',
      'هيونداي',
      'كيا',
      'نيسان',
      'هوندا',
      'ديزل',
      'بنزين',
      'اجواء العراق',
      'أجواء العراق',
      'حر العراق',
      'صيف',
      'فلتر زيت',
      'يستهلك زيت',
      'دخان',
    ];
    for (final h in hits) {
      final hit = _normalizeHit(h);
      if (hit == 'عداد') {
        if (q.contains('عداد') && !q.contains('اعداد')) return true;
        continue;
      }
      if (q.contains(hit)) return true;
    }
    return false;
  }

  static bool _wantsNabooRecording(String q) {
    final mentioneNaboo = q.contains('نابو');
    final recording = q.contains('سجل') ||
        q.contains('تسجيل') ||
        q.contains('اسجل') ||
        q.contains('بطاق');
    final service = q.contains('تبديل') ||
        q.contains('غيار') ||
        q.contains('تغيير') ||
        q.contains('عمليه') ||
        q.contains('عملية') ||
        q.contains('خدمه') ||
        q.contains('خدمة');
    return mentioneNaboo && (recording || service);
  }

  static bool _wantsViscosity(String q) {
    const keys = <String>[
      'لزوج',
      'لزوجة',
      'زيت مناسب',
      'اي زيت',
      'أي زيت',
      'شنو الزيت',
      'ما الزيت',
      'نوع الزيت',
      'زيوت',
      'تخليقي',
      'معدني',
      'نصف تخليقي',
      '5w',
      '10w',
      '15w',
      '20w',
      'w-30',
      'w-40',
      'w-50',
    ];
    for (final k in keys) {
      if (q.contains(_normalizeHit(k))) return true;
    }
    return false;
  }

  static bool _wantsClimate(String q) {
    return q.contains(_normalizeHit('اجواء العراق')) ||
        q.contains(_normalizeHit('أجواء العراق')) ||
        q.contains('حر العراق') ||
        q.contains('صيف') ||
        q.contains('باجواء') ||
        q.contains('بأجواء');
  }

  static bool _wantsInterval(String q) {
    // بعد التطبيع: ى→ي فيصبح «متى» → «متي».
    if (q.contains('متي') ||
        q.contains('متى') ||
        q.contains('فتره') ||
        q.contains('فترة') ||
        q.contains('كم قطع') ||
        q.contains('كل كم') ||
        q.contains('موعد')) {
      return true;
    }
    return false;
  }

  static bool _wantsOilService(String q) {
    const keys = <String>[
      'غيار زيت',
      'غيار الزيت',
      'تغيير زيت',
      'تغيير الزيت',
      'تبديل زيت',
      'تبديل الزيت',
      'ابدل الزيت',
      'ابدّل الزيت',
      'اغير الزيت',
      'اغيّر الزيت',
    ];
    for (final k in keys) {
      if (q.contains(_normalizeHit(k))) return true;
    }
    return false;
  }

  /// مطابق لتطبيع GuidePageKnowledge._normalize (أ/ة/ى + مسافات).
  static String _normalizeHit(String s) {
    return s
        .trim()
        .toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
