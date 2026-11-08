import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/navigation/home_barcode_route_coordinator.dart';
import 'package:naboo/navigation/scanned_receipt_lookup.dart';
import 'package:naboo/printing/receipt_builders.dart';
import 'package:naboo/printing/receipt_model.dart';
import 'package:naboo/services/service_order_kinds.dart';
import 'package:naboo/services/service_orders_sql_ops.dart';
import 'package:naboo/utils/invoice_deep_link.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _g = '3f2a1c9e-7b4d-4e8a-9c1f-0a2b3c4d5e6f';

Invoice _invoice({int id = 1024, String? globalId = _g}) => Invoice(
  id: id,
  customerName: 'أحمد علي',
  date: DateTime(2026, 11, 8, 10, 30),
  type: InvoiceType.cash,
  items: const [],
  discount: 0,
  tax: 0,
  advancePayment: 42000,
  total: 42000,
  globalId: globalId,
);

void main() {
  group('صيغة رمز الإيصال', () {
    test('الرمز الجديد يحمل المعرّف العالمي ويُقرأ كما هو', () {
      final uri = InvoiceDeepLink.uriForInvoiceId(1024, globalId: _g);
      expect(uri, 'basrainvoice://invoice/1024?g=$_g');
      final ref = InvoiceDeepLink.parse(Uri.parse(uri))!;
      expect(ref.localId, 1024);
      expect(ref.globalId, _g);
      expect(ref.isLegacy, isFalse);
    });

    test('الرمز القديم بلا معرّف يبقى مقروءاً ويُعلَّم قديماً', () {
      final ref = InvoiceDeepLink.parse(
        Uri.parse('basrainvoice://invoice/77'),
      )!;
      expect(ref.localId, 77);
      expect(ref.isLegacy, isTrue);
      expect(InvoiceDeepLink.uriForInvoiceId(77), 'basrainvoice://invoice/77');
    });

    test('معرّف معطوب يُرفض ولا يسقط للرقم المحلي', () {
      expect(
        InvoiceDeepLink.parse(
          Uri.parse('basrainvoice://invoice/1024?g=not-a-uuid'),
        ),
        isNull,
      );
    });

    test('الأحرف الكبيرة في المعرّف تُوحَّد', () {
      final ref = InvoiceDeepLink.parse(
        Uri.parse('basrainvoice://invoice/5?g=${_g.toUpperCase()}'),
      )!;
      expect(ref.globalId, _g);
    });

    test('إيصال الفاتورة يطبع الرمز بالمعرّف العالمي', () {
      final doc = ReceiptBuilders.fromInvoice(_invoice());
      expect(doc.qrData, 'basrainvoice://invoice/1024?g=$_g');
    });
  });

  group('البحث عن الإيصال الممسوح', () {
    tearDown(() {
      ScannedReceiptLookup.idForGlobalId = (_) async => null;
    });

    test('معرّف غير موجود في المحل: رسالة واضحة ولا فتح', () async {
      ScannedReceiptLookup.idForGlobalId = (_) async => null;
      ScannedReceiptLookup.loadInvoice = (_) async => fail('لا يُحمَّل شيء');
      final r = await ScannedReceiptLookup.resolve(const InvoiceLinkRef(1024, _g));
      expect(r.receipt, isNull);
      expect(r.error, contains('غير موجود في محلك'));
    });

    test('الرقم المطبوع لا يُستخدم: الفاتورة بمعرّفها العالمي', () async {
      // على هذا الجهاز نفس الفاتورة رقمها 88 لا 1024.
      ScannedReceiptLookup.idForGlobalId = (g) async => g == _g ? 88 : null;
      ScannedReceiptLookup.loadInvoice = (id) async => _invoice(id: id);
      ScannedReceiptLookup.loadOrder = (_) async => {
        'orderKind': ServiceOrderKinds.oilChange,
        'deviceSerial': '12345 بصرة',
      };
      final r = await ScannedReceiptLookup.resolve(const InvoiceLinkRef(1024, _g));
      expect(r.receipt!.invoiceId, 88);
      expect(r.receipt!.kind, ReceiptKind.oilChange);
      expect(r.receipt!.legacy, isFalse);
    });

    test('الغسيل يُكتشف من بطاقته', () async {
      ScannedReceiptLookup.idForGlobalId = (_) async => 5;
      ScannedReceiptLookup.loadInvoice = (id) async => _invoice(id: id);
      ScannedReceiptLookup.loadOrder = (_) async => {
        'orderKind': ServiceOrderKinds.carWash,
      };
      final r = await ScannedReceiptLookup.resolve(const InvoiceLinkRef(5, _g));
      expect(r.receipt!.kind, ReceiptKind.carWash);
    });

    test('الرمز القديم يُبحث برقمه المحلي ويبقى معلَّماً', () async {
      ScannedReceiptLookup.loadInvoice = (id) async => _invoice(id: id);
      ScannedReceiptLookup.loadOrder = (_) async => null;
      final r = await ScannedReceiptLookup.resolve(
        const InvoiceLinkRef(77, null),
      );
      expect(r.receipt!.invoiceId, 77);
      expect(r.receipt!.legacy, isTrue);
      expect(r.receipt!.kind, ReceiptKind.sale);
    });
  });

  group('تحذير غيار اليوم', () {
    final now = DateTime(2026, 11, 8, 15);
    test('بطاقة اليوم تُرجع وقتها', () {
      final t = HomeBarcodeRouteCoordinator.sameDayTime(
        {'createdAt': DateTime(2026, 11, 8, 10, 30).toIso8601String()},
        now: now,
      );
      expect(t, isNotNull);
      expect(t!.hour, 10);
    });

    test('بطاقة الأمس لا تحذير', () {
      expect(
        HomeBarcodeRouteCoordinator.sameDayTime(
          {'createdAt': DateTime(2026, 11, 7, 23).toIso8601String()},
          now: now,
        ),
        isNull,
      );
    });

    test('تاريخ مفقود لا تحذير', () {
      expect(HomeBarcodeRouteCoordinator.sameDayTime({}, now: now), isNull);
    });
  });

  group('آخر زيارة باللوحة', () {
    late Database db;
    setUpAll(sqfliteFfiInit);
    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE service_orders (
          id INTEGER PRIMARY KEY, tenantId INTEGER, orderKind TEXT,
          status TEXT, deviceSerial TEXT, deletedAt TEXT, note TEXT
        )''');
      Future<void> add(int id, String kind, String plate, [String? del]) =>
          db.insert('service_orders', {
            'id': id,
            'tenantId': 1,
            'orderKind': kind,
            'status': 'delivered',
            'deviceSerial': plate,
            'deletedAt': del,
            'note': '$kind-$id',
          });
      await add(1, ServiceOrderKinds.oilChange, '12345 بصرة');
      await add(2, ServiceOrderKinds.carWash, '12345 بصرة');
      await add(3, ServiceOrderKinds.oilChange, '12345 بصرة');
      await add(4, ServiceOrderKinds.carWash, '12345 بصرة');
      await add(5, ServiceOrderKinds.carWash, '12345 بصرة', '2026-11-08');
      await add(6, ServiceOrderKinds.carWash, '999 بغداد');
    });
    tearDown(() => db.close());

    test('الإيصال القديم للزيت يعبّئ من آخر غيار لا من الغسيل', () async {
      final row = await ServiceOrdersSqlOps.getLatestOilChangeByPlate(
        db,
        1,
        deviceSerial: '12345 بصرة',
      );
      expect(row!['id'], 3);
    });

    test('آخر غسلة للوحة تتجاهل المحذوفة وسيارات أخرى', () async {
      final row = await ServiceOrdersSqlOps.getLatestByPlate(
        db,
        1,
        deviceSerial: '12345 بصرة',
        orderKind: ServiceOrderKinds.carWash,
      );
      expect(row!['id'], 4);
    });

    test('محل آخر لا يرى شيئاً', () async {
      final row = await ServiceOrdersSqlOps.getLatestByPlate(
        db,
        2,
        deviceSerial: '12345 بصرة',
        orderKind: ServiceOrderKinds.carWash,
      );
      expect(row, isNull);
    });
  });
}
