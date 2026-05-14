/// أسماء كيانات المزامنة (sync_queue.entity_type).
///
/// تجنّب كتابة strings يدوياً في كل مكان — أي typo هنا يكسر المزامنة بصمت.
class SyncEntityTypes {
  // موجودة في النظام الحالي
  static const cashLedger = 'cash_ledger';
  static const workShift = 'work_shift';
  static const expense = 'expense';
  static const customer = 'customer';
  static const supplier = 'supplier';
  static const productVariant = 'product_variant';

  // خدمات + تذاكر صيانة
  static const serviceOrder = 'service_order';
  static const serviceOrderItem = 'service_order_item';
}

