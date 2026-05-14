// أدوات اختبار خفيفة لمحاكاة قنوات Supabase Realtime بدون إقحام
// مكتبة `supabase_flutter` نفسها (التي تحتاج تهيئة Supabase حقيقية).
//
// الفكرة: نمذجة pub/sub بسيط:
// - منتجو الأحداث ينشرون FakePostgresChange على جدول معيّن.
// - مستهلكون يسجّلون رد نداء على (table, event) ويستقبلون الأحداث.
//
// الكود الإنتاجي الذي نريد اختباره (مثلاً cloud_sync_service.dart)
// سيُعدّل لاحقاً (Step 22) لاستقبال نقطة حقن من نوع FakeRealtimeHub
// أو واجهة مكافئة، فيمكن للاختبارات أن تُطلق UPDATE event دون شبكة حقيقية.

enum FakeChangeEvent { insert, update, delete }

class FakePostgresChange {
  FakePostgresChange({
    required this.schema,
    required this.table,
    required this.event,
    required this.newRecord,
    this.oldRecord = const {},
  });

  final String schema;
  final String table;
  final FakeChangeEvent event;
  final Map<String, dynamic> newRecord;
  final Map<String, dynamic> oldRecord;
}

typedef FakeRealtimeListener = void Function(FakePostgresChange change);

class FakeRealtimeHub {
  final List<FakeRealtimeSubscription> _subscriptions = [];
  final List<FakePostgresChange> emitted = [];

  /// يسجّل مستمعاً على جدول معيّن وأحداث معيّنة.
  /// يُرجع كائن اشتراك يمكن إلغاؤه عبر [FakeRealtimeSubscription.cancel].
  FakeRealtimeSubscription on({
    required String table,
    required FakeChangeEvent event,
    required FakeRealtimeListener listener,
    String schema = 'public',
  }) {
    final sub = FakeRealtimeSubscription._(
      hub: this,
      schema: schema,
      table: table,
      event: event,
      listener: listener,
    );
    _subscriptions.add(sub);
    return sub;
  }

  /// ينشر تغيّراً وهمياً على جدول. كل مشترك مطابق سيستقبله.
  void emit(FakePostgresChange change) {
    emitted.add(change);
    for (final sub in List<FakeRealtimeSubscription>.from(_subscriptions)) {
      if (sub._cancelled) continue;
      if (sub.schema != change.schema) continue;
      if (sub.table != change.table) continue;
      if (sub.event != change.event) continue;
      sub.listener(change);
    }
  }

  /// يعدّ المشتركين النشطين في جدول/حدث محدّد (مفيد للتأكيدات).
  int subscriberCount({
    required String table,
    required FakeChangeEvent event,
    String schema = 'public',
  }) {
    return _subscriptions
        .where((s) =>
            !s._cancelled &&
            s.schema == schema &&
            s.table == table &&
            s.event == event)
        .length;
  }

  void disposeAll() {
    for (final s in _subscriptions) {
      s._cancelled = true;
    }
    _subscriptions.clear();
    emitted.clear();
  }
}

class FakeRealtimeSubscription {
  FakeRealtimeSubscription._({
    required this.hub,
    required this.schema,
    required this.table,
    required this.event,
    required this.listener,
  });

  final FakeRealtimeHub hub;
  final String schema;
  final String table;
  final FakeChangeEvent event;
  final FakeRealtimeListener listener;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    hub._subscriptions.remove(this);
  }
}
