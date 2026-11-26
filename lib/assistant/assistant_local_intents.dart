/// النوايا المحلية للمساعد (ق26، ق69، م1-12، م1-26).
///
/// كلها تُجاب على الجهاز بلا طلب للخادم وبلا كلفة: التحيات، فتح شاشة معروفة،
/// والأسئلة الشائعة التي تُجاب من أداة واحدة ببطاقتها.
///
/// قائمة الأسئلة الشائعة النهائية (15 سؤالاً بخمس صيغ لكل منها) تأتي من م1-12ب
/// بعد تصحيحك للقوائم في `docs/specs/naboo_assistant_seed_lists_ar.md`.
/// الموجود هنا هو الحد الأدنى الذي يذكره شرط م1-12، ويكبر بإضافة صفوف فقط.
library;

/// تطبيع للمطابقة: همزات، تاء مربوطة، ياء، أرقام عربية، تشكيل، ومسافات.
String normalizeArabic(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in s.runes) {
    final c = String.fromCharCode(ch);
    final i = ar.indexOf(c);
    final j = fa.indexOf(c);
    if (i >= 0) {
      b.write(i);
    } else if (j >= 0) {
      b.write(j);
    } else {
      b.write(c);
    }
  }
  return b
      .toString()
      .toLowerCase()
      .replaceAll(RegExp('[ً-ْـ]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('گ', 'ك')
      .replaceAll(RegExp(r'[؟?!.،,]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// يستخرج لزوجة بصيغتها القياسية من كلام دارج: «5 30»، «٥ ٣٠»، «5w30»، «خمسة ثلاثين».
String? extractViscosity(String raw) {
  final s = normalizeArabic(raw);
  final m = RegExp(r'(?<![0-9])(0|5|10|15|20)\s*(?:w|دبليو|ضبليو)?\s*[-/]?\s*(20|30|40|50|60)(?![0-9])').firstMatch(s);
  if (m != null) return '${m.group(1)}W-${m.group(2)}';
  const words = {
    'صفر': '0',
    'خمسه': '5',
    'خمس': '5',
    'عشره': '10',
    'عشر': '10',
    'خمسطعش': '15',
    'خمستعش': '15',
    'عشرين': '20',
  };
  const tens = {'عشرين': '20', 'ثلاثين': '30', 'تلاثين': '30', 'اربعين': '40', 'خمسين': '50'};
  for (final a in words.entries) {
    for (final b in tens.entries) {
      if (s.contains('${a.key} ${b.key}') || s.contains('${a.key} و${b.key}')) {
        return '${a.value}W-${b.value}';
      }
    }
  }
  return null;
}

/// رقم لوحة عراقية: أرقام مع حرف مفرد قبلها أو بعدها.
String? extractPlate(String raw) {
  final s = normalizeArabic(raw);
  final a = RegExp(r'(?<![0-9])(\d{2,6})\s?([ء-ي])(?![ء-ي])').firstMatch(s);
  if (a != null) return '${a.group(1)} ${a.group(2)}';
  final b = RegExp(r'(?<![ء-ي])([ء-ي])\s?(\d{2,6})(?![0-9])').firstMatch(s);
  if (b != null) return '${b.group(2)} ${b.group(1)}';
  return null;
}

enum LocalIntentKind { greeting, thanks, bye, openScreen, data }

/// سؤال بيانات شائع يُجاب من أداة واحدة.
class LocalDataIntent {
  const LocalDataIntent({
    required this.id,
    required this.tool,
    required this.triggers,
    required this.header,
    this.args = const {},
    this.needsViscosity = false,
    this.needsPlate = false,
    this.blockers = const [],
  });

  final String id;
  final String tool;

  /// يكفي أن يحتوي السؤال المطبَّع على واحدة منها.
  final List<String> triggers;

  /// كلمات تعني أن السؤال أعقد من نية محلية، فيذهب للنموذج.
  final List<String> blockers;
  final String header;
  final Map<String, Object?> args;

  /// السؤال يجب أن يحوي لزوجة، وتُمرَّر كـ query.
  final bool needsViscosity;

  /// السؤال يجب أن يحوي لوحة، وتُمرَّر كـ plate.
  final bool needsPlate;
}

/// شاشة تُفتح بأمر صريح.
class LocalScreen {
  const LocalScreen(this.routeId, this.title, this.names);
  final String routeId;
  final String title;
  final List<String> names;
}

abstract final class AssistantLocalIntents {
  static const greetings = [
    'السلام عليكم',
    'سلام عليكم',
    'السلام',
    'سلام',
    'مرحبا',
    'مرحبه',
    'هلا',
    'هلو',
    'هاي',
    'صباح الخير',
    'مساء الخير',
    'صباحو',
    'مساكم',
    'شلونك',
    'شلونكم',
    'اهلا',
    'هلا والله',
  ];
  static const thanks = [
    'شكرا',
    'مشكور',
    'مشكورين',
    'تسلم',
    'تسلم ايدك',
    'الله يخليك',
    'ممنون',
    'عاشت ايدك',
    'يعطيك العافيه',
    'حبيبي تسلم',
  ];
  static const byes = ['مع السلامه', 'باي', 'بامان الله', 'الله وياك', 'نشوفك', 'تصبح على خير'];

  static const greetingReply = 'هلا بيك 👋 شتحتاج؟ اسألني عن المخزون أو البطاقات أو أي شاشة بالتطبيق.';
  static const thanksReply = 'العفو، بالخدمة دائماً.';
  static const byeReply = 'بأمان الله.';

  /// أفعال الأمر بالفتح. «وين» ليست منها: «وين» سؤال يحتاج شرحاً من المساعد.
  static const openVerbs = [
    'افتح',
    'افتحلي',
    'فتحلي',
    'وديني',
    'ودني',
    'روح ل',
    'روحلي',
    'طلعلي شاشه',
    'اريد شاشه',
    'خذني',
  ];

  static const screens = <LocalScreen>[
    LocalScreen('app_inventory', 'المخزون', ['المخزون', 'مخزون', 'المواد', 'البضاعه']),
    LocalScreen('app_oil_invoices', 'الفواتير', ['الفواتير', 'فواتير']),
    LocalScreen('app_customers', 'الزبائن', ['الزباين', 'الزبائن', 'زباين', 'العملاء']),
    LocalScreen('app_debts', 'الديون', ['الديون', 'ديون', 'الدين']),
    LocalScreen('app_expenses', 'المصاريف', ['المصاريف', 'المصروفات', 'مصاريف']),
    LocalScreen('app_cash', 'الصندوق', ['القاصه', 'الصندوق', 'الكاش']),
    LocalScreen('app_reports', 'التقارير', ['التقارير', 'تقارير']),
    LocalScreen('app_oil_services_log', 'سجل الخدمات', ['سجل الخدمات', 'البطاقات', 'السجل']),
    LocalScreen('app_oil_change_create', 'بطاقة غيار جديدة', ['بطاقه جديده', 'غيار جديد', 'بطاقه غيار']),
    LocalScreen('app_car_wash_create', 'غسيل جديد', ['غسيل', 'الغسل']),
    LocalScreen('app_oil_direct_sale', 'البيع المباشر', ['البيع المباشر', 'بيع مباشر']),
    LocalScreen('app_settings_oil_hub', 'إعدادات الزيت', ['اعدادات الزيت', 'اعدادات الغيار']),
    LocalScreen('app_oil_whatsapp_connect', 'واتساب', ['الواتساب', 'واتساب']),
  ];

  static const dataIntents = <LocalDataIntent>[
    LocalDataIntent(
      id: 'stock_viscosity',
      tool: 'stock_search',
      needsViscosity: true,
      triggers: ['شكد باقي', 'شكد عدنا', 'شكد عندي', 'كم باقي', 'كم عدنا', 'اكو', 'موجود', 'عدنا', 'باقي', 'متوفر'],
      blockers: ['سياره', 'كورولا', 'يناسب', 'انسب', 'مناسب', 'اطلب', 'ليش', 'سعر شراء'],
      header: 'الموجود عندك',
    ),
    LocalDataIntent(
      id: 'stock_low',
      tool: 'stock_low',
      triggers: ['النواقص', 'نواقص', 'شنو خلص', 'الخالص', 'اللي خالص', 'اللي خلص', 'شي خلص', 'المواد الناقصه', 'الناقص'],
      blockers: ['اطلب', 'مورد', 'المورد', 'شكد لازم'],
      header: 'الأصناف الناقصة',
    ),
    LocalDataIntent(
      id: 'sales_today',
      tool: 'sales_summary',
      args: {'period': 'today', 'channel': 'all'},
      triggers: ['مبيعات اليوم', 'شكد بعت اليوم', 'شكد بعنا اليوم', 'بيع اليوم', 'مبيعاتي اليوم', 'شكد دخلنا اليوم'],
      blockers: ['امس', 'الاسبوع', 'الشهر', 'قارن', 'غسيل', 'مباشر'],
      header: 'مبيعات اليوم',
    ),
    LocalDataIntent(
      id: 'car_history',
      tool: 'car_history',
      needsPlate: true,
      triggers: ['سجل', 'تاريخ', 'اخر مره', 'شوكت', 'متى بدل', 'متى غير', 'جايه قبل', 'جت قبل'],
      blockers: ['سجل غيار', 'سجل غسيل', 'سجلي', 'سجل مصروف', 'سجل زبون', 'افتح'],
      header: 'سجل السيارة',
    ),
    LocalDataIntent(
      id: 'cards_pending',
      tool: 'oil_card_find',
      args: {'status': 'pending', 'period': 'today'},
      triggers: [
        'البطاقات المعلقه',
        'بطاقات معلقه',
        'المعلقات',
        'شكو معلق',
        'اكو معلق',
        'شنو المعلق',
        'ما مدفوعه',
        'ما انحسبت',
      ],
      blockers: ['وين', 'شلون'],
      header: 'البطاقات المعلّقة',
    ),
    // بقية الأسئلة الشائعة الخمسة عشر (ق26، قائمة البذور 2).
    LocalDataIntent(
      id: 'cards_today',
      tool: 'oil_card_find',
      args: {'status': 'any', 'period': 'today'},
      triggers: ['بطاقات اليوم', 'شكد بطاقه اليوم', 'كم بطاقه اليوم', 'سياره بدلنا اليوم', 'الغيارات اليوم', 'غيارات اليوم', 'سياره اجت اليوم'],
      blockers: ['امس', 'الاسبوع', 'الشهر', 'قارن', 'غسيل', 'غسلنا', 'وين', 'شلون'],
      header: 'بطاقات اليوم',
    ),
    LocalDataIntent(
      id: 'cards_last',
      tool: 'oil_card_find',
      args: {'status': 'any', 'period': 'this_week'},
      triggers: ['اخر بطاقه', 'البطاقه الاخيره', 'اخر سياره', 'اخر غيار', 'اخر وحده سويناها'],
      blockers: ['لوحه', 'زبون', 'شلون', 'امس'], // لا «وين»: هي داخل «سويناها».
      header: 'آخر البطاقات',
    ),
    LocalDataIntent(
      id: 'debts_all',
      tool: 'debts_summary',
      triggers: ['الديون', 'ديون الزباين', 'ديون الزبائن', 'منو مطلوب', 'منو عليه دين', 'المطلوبين'],
      blockers: ['مورد', 'الموردين', 'شركه', 'سجل', 'وين', 'شلون', 'افتح'],
      header: 'أكبر الديون على الزبائن',
    ),
    LocalDataIntent(
      id: 'cash_now',
      tool: 'cash_summary',
      args: {'period': 'today'},
      triggers: ['بالقاصه', 'رصيد الصندوق', 'بالدرج', 'بالصندوق', 'الكاش اللي عندنا', 'رصيد القاصه'],
      blockers: ['امس', 'الاسبوع', 'الشهر', 'قارن', 'وين', 'شلون', 'افتح', 'سحب', 'ايداع'],
      header: 'الصندوق اليوم',
    ),
    LocalDataIntent(
      id: 'expenses_today',
      tool: 'cash_summary',
      args: {'period': 'today'},
      triggers: ['مصاريف اليوم', 'مصروفات اليوم', 'صرفيات اليوم', 'شكد صرفنا', 'شكد صرفت'],
      blockers: ['امس', 'الاسبوع', 'الشهر', 'قارن', 'وين', 'شلون', 'افتح', 'اضيف', 'سجل'],
      header: 'مصاريف اليوم',
    ),
    LocalDataIntent(
      id: 'staff_now',
      tool: 'staff_status',
      triggers: ['منو شغال', 'منو بالورديه', 'الورديه مفتوحه', 'منو موجود اليوم', 'الموظفين اليوم', 'منو داوم'],
      blockers: ['راتب', 'رواتب', 'اداء', 'صلاحي', 'افتح', 'وين', 'شلون'],
      header: 'الوردية الآن',
    ),
    LocalDataIntent(
      id: 'washes_today',
      tool: 'sales_summary',
      args: {'period': 'today', 'channel': 'wash'},
      triggers: ['غسيل اليوم', 'غسلنا اليوم', 'كم سياره غسلنا', 'شكد غسلنا', 'حساب الغسيل', 'الغسلات اليوم'],
      blockers: ['امس', 'الاسبوع', 'الشهر', 'قارن', 'عرض', 'سعر', 'وين', 'شلون', 'افتح'],
      header: 'الغسيل اليوم',
    ),
    LocalDataIntent(
      id: 'top_week',
      tool: 'top_products',
      args: {'period': 'this_week', 'limit': 5},
      triggers: ['اكثر زيت انباع', 'الاكثر بيعا', 'الاكثر مبيعا', 'شنو ماشي', 'اكثر صنف بعناه', 'الزيت الطالب'],
      blockers: ['الشهر', 'امس', 'قارن', 'ليش', 'اطلب'],
      header: 'الأكثر بيعاً هذا الأسبوع',
    ),
    LocalDataIntent(
      id: 'due_soon',
      tool: 'due_customers',
      args: {'days_ahead': 7},
      triggers: ['موعده قريب', 'لازم يبدلون', 'مستحق غيار', 'منو لازم نذكره', 'فات موعدها', 'فات موعده'],
      blockers: ['رساله', 'ارسل', 'واتساب', 'وين', 'شلون'],
      header: 'زبائن موعدهم قريب',
    ),
  ];
}
