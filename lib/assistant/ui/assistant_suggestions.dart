import '../assistant_access.dart';

/// الأسئلة المقترحة في شاشة البداية (م2-5، ق47).
///
/// قائمة ثابتة لكل مجموعة شاشات، تتغير حسب الشاشة التي فُتح منها المساعد
/// وحسب الدور: «إرشاد فقط» يرى أسئلة «وين» و«شلون» فقط، والموظف لا يُقترح
/// عليه سؤال مالي. بعد تشغيل التعلّم (ب6) تحلّ محلها أنجح الأسئلة لكل شاشة.
abstract final class AssistantSuggestions {
  static const _max = 4;

  /// يظهر للمالك ما دام التجهيز ناقصاً (ق30، م3-9ب).
  static const setupPrompt = 'جهّز محلي معي';

  /// يُبنى على الجهاز بلا نموذج (م3-13).
  static const explainPrompt = 'اشرح لي هذه الشاشة';

  static List<String> forScreen({
    required String? routeId,
    required AssistantLevel level,
    required bool isOwner,
    bool offerSetup = false,
    bool canExplain = false,
  }) {
    final base = _forScreen(routeId: routeId, level: level, isOwner: isOwner);
    final lead = [if (offerSetup && isOwner) setupPrompt, if (canExplain) explainPrompt];
    if (lead.isEmpty) return base;
    return [...lead, ...base.where((q) => !lead.contains(q))].take(_max).toList();
  }

  static List<String> _forScreen({required String? routeId, required AssistantLevel level, required bool isOwner}) {
    final group = _group(routeId ?? '');
    final guide = _guide[group] ?? _guide['home']!;
    if (level != AssistantLevel.full) return guide.take(_max).toList();
    final data = [...?_data[group], if (isOwner) ...?_owner[group]];
    // سؤالا بيانات أولاً ثم إرشاد، أو إرشاد فقط إن لم تكن للشاشة بيانات.
    final out = <String>[...data.take(isOwner ? 3 : 2)];
    for (final g in guide) {
      if (out.length >= _max) break;
      if (!out.contains(g)) out.add(g);
    }
    return out;
  }

  static String _group(String r) {
    if (r.startsWith('app_oil_services') || r.startsWith('app_oil_change') || r.startsWith('app_oil_')) return 'oil';
    if (r.startsWith('app_car_wash')) return 'wash';
    if (r.startsWith('app_inventory') || r.startsWith('app_products')) return 'inventory';
    if (r.startsWith('app_customer') || r.startsWith('app_debts') || r.startsWith('app_installments'))
      return 'customers';
    if (r.startsWith('app_cash') || r.startsWith('app_expenses')) return 'cash';
    if (r.startsWith('app_reports')) return 'reports';
    if (r.startsWith('app_invoices') || r.startsWith('app_add_invoice') || r.startsWith('app_sale')) return 'sales';
    if (r.startsWith('app_users') ||
        r.startsWith('app_user_') ||
        r.startsWith('app_staff') ||
        r.startsWith('app_employee')) {
      return 'staff';
    }
    if (r.startsWith('app_settings') || r.startsWith('app_printing')) return 'settings';
    return 'home';
  }

  static const Map<String, List<String>> _data = {
    'home': ['شنو الناقص بالمخزون؟', 'كم بطاقة غيار مفتوحة هسه؟'],
    'oil': ['شنو البطاقات المعلّقة اليوم؟', 'آخر غيار لسيارة رقمها…'],
    'wash': ['شنو البطاقات المعلّقة اليوم؟'],
    'inventory': ['شنو الناقص بالمخزون؟', 'شكد عندي زيت 5W-30؟'],
    'customers': ['آخر غيار لسيارة رقمها…'],
    'sales': ['شنو الناقص بالمخزون؟'],
    'staff': ['منو شغال هسه بالوردية؟'],
  };

  /// أسئلة مالية للمالك فقط.
  static const Map<String, List<String>> _owner = {
    'home': ['شكد بعنا اليوم؟', 'شكد بالصندوق هسه؟'],
    'oil': ['شكد بعنا اليوم؟'],
    'inventory': ['شكد قيمة المخزون؟'],
    'customers': ['منو أكثر واحد عليه دين؟'],
    'cash': ['شكد بالصندوق هسه؟', 'شكد مصاريف هذا الشهر؟'],
    'reports': ['شكد بعنا هذا الأسبوع؟', 'شنو أكثر صنف انباع؟'],
    'sales': ['شكد بعنا اليوم؟'],
  };

  static const Map<String, List<String>> _guide = {
    'home': ['شلون أسوي بطاقة غيار؟', 'وين أضيف منتج جديد؟', 'شلون أضيف موظف؟', 'وين أشوف التقارير؟'],
    'oil': [
      'شلون أسوي بطاقة غيار؟',
      'شلون أذكّر الزبون بموعد الغيار؟',
      'شلون أحوّل البطاقة لفاتورة؟',
      'وين سجل الخدمات؟',
    ],
    'wash': ['شلون أسجل غسلة جديدة؟', 'شلون أضيف خدمة غسيل؟', 'وين أشوف الغسلات المعلّقة؟'],
    'inventory': ['وين أضيف منتج جديد؟', 'شلون أعدّل الكمية؟', 'شلون أطبع باركود؟', 'شلون أسوي جرد؟'],
    'customers': ['شلون أضيف زبون؟', 'شلون أسجل تسديد دين؟', 'وين أشوف كشف حساب الزبون؟'],
    'cash': ['شلون أسجل مصروف؟', 'شلون أسكّر الصندوق آخر اليوم؟', 'وين أشوف حركة الصندوق؟'],
    'reports': ['وين تقرير المبيعات؟', 'شلون أطبع التقرير؟', 'شلون أغيّر الفترة؟'],
    'sales': ['شلون أسوي فاتورة؟', 'شلون أرجّع فاتورة؟', 'وين الفواتير المعلّقة؟'],
    'staff': ['شلون أضيف موظف؟', 'شلون أحدد صلاحيات الموظف؟', 'وين جدول الورديات؟'],
    'settings': ['شلون أربط الطابعة؟', 'شلون أغيّر شعار الوصل؟', 'شلون أربط واتساب؟'],
  };
}
