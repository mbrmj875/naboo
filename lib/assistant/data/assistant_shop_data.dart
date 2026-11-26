import 'assistant_period.dart';

/// ما يقرأه المساعد من بيانات المحل (4.3، م1-5، م1-6).
///
/// كل دالة تعيد صفوفاً بشكل نتيجة الأداة مباشرة: المبالغ بالفلس في حقول
/// `*_fils`، ولا رقم هاتف زبون أبداً. التنفيذ على الجهاز في
/// `device_shop_data.dart` يستعمل مستودعات الشاشات نفسها حتى تطابق الأرقام
/// ما يراه المستخدم. منفصل حتى تُختبر الأدوات بلا قاعدة.
abstract class AssistantShopData {
  /// كل الأصناف النشطة (بلا آباء عائلات الزيت). يكفي للبحث على الجهاز.
  /// الحقول: id، name، brand، viscosity، kind، qty، unit، sell_price_fils،
  /// buy_price_fils، threshold، barcode.
  Future<List<Map<String, Object?>>> stockItems();

  /// الأصناف الناقصة أو المنتهية بنفس قاعدة إشعارات المخزون.
  Future<List<Map<String, Object?>>> lowStock();

  /// تفاصيل صنف مع كميته في كل مخزن. null إن لم يوجد.
  Future<Map<String, Object?>?> productDetail(int id);

  /// معرّف المنتج صاحب الباركود (منتج أو وحدة بيع)، بلا إنترنت (م1-24).
  Future<int?> productIdByBarcode(String code);

  /// بطاقات الغيار. [status]: pending | invoiced | any.
  Future<List<Map<String, Object?>>> oilCards({
    int? id,
    String? plate,
    String? customer,
    AssistantPeriod? period,
    String status = 'any',
    int limit = 20,
  });

  /// آخر زيارات سيارة بلوحتها أو بزبونها.
  Future<List<Map<String, Object?>>> carVisits({String? plate, int? customerId, int limit = 5});

  /// ملخص المبيعات لقناة: oil | direct | wash. الحقول: count، total_fils،
  /// returns، returns_fils، cost_fils (إن عُرفت).
  Future<Map<String, Object?>> sales(AssistantPeriod period, String channel);

  /// الأصناف المباعة في الفترة: name، sold_qty، amount_fils، profit_fils،
  /// qty، unit، is_liter، days_of_cover، reorder_qty.
  Future<List<Map<String, Object?>>> productSales(AssistantPeriod period);

  /// open_total_fils وdebtors.
  Future<Map<String, Object?>> debtTotals();

  /// المدينون: customer، customer_id، amount_fils، invoices، oldest.
  Future<List<Map<String, Object?>>> debtors();

  /// balance_fils للصندوق كله، وin_fils وout_fils وexpenses_fils للفترة.
  Future<Map<String, Object?>> cash(AssistantPeriod period);

  /// open_shift، staff، invoices، returns، opened_at.
  Future<Map<String, Object?>> shift();

  /// لكل موظف: employee، count، avg، notes، last_at.
  Future<List<Map<String, Object?>>> ratingsByEmployee();

  /// connected، status، sent، delivered، failed، total.
  Future<Map<String, Object?>> whatsapp(AssistantPeriod period);

  /// الزبائن المطابقون: id، name، last_visit، open_debt_fils. بلا هاتف.
  Future<List<Map<String, Object?>>> customers(String query, {int limit = 8});

  // ------------------------------------------------ الإضافية (4.13ب)

  /// آخر بطاقة زيت لكل سيارة: plate، car، customer، customer_id، date،
  /// odometer، next_odometer. للزبائن الذين حان غيارهم.
  Future<List<Map<String, Object?>>> latestVisitPerCar();

  /// مدة المتابعة بالأيام من قاعدة متابعة واتساب (الافتراضي 3 أشهر).
  Future<int> followupDelayDays();

  /// الفنيون في الفترة: name، count، amount_fils.
  Future<List<Map<String, Object?>>> technicians(AssistantPeriod period);

  /// سندات الإدخال لصنف: date، supplier، qty، unit_price_fils، voucher_no.
  Future<List<Map<String, Object?>>> purchases(int productId, {int limit = 10});

  /// حساب نابو: status، expires، days_left، plan، wa_balance.
  Future<Map<String, Object?>> nabooAccount();
}
