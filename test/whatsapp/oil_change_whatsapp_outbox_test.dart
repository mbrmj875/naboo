import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/utils/customer_validation.dart';
import 'package:naboo/verticals/oil_change/models/oil_change_whatsapp_notify_outcome.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_whatsapp_outbox.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('OilChangeWhatsappOutbox', () {
    late DatabaseHelper dbHelper;
    late OilChangeWhatsappOutbox outbox;

    setUp(() async {
      CloudSyncService.instance.suppressUserDirectoryPushSoonForTesting = true;
      dbHelper = DatabaseHelper();
      await dbHelper.closeAndDeleteDatabaseFile();
      outbox = OilChangeWhatsappOutbox.instance;
    });

    tearDown(() async {
      CloudSyncService.instance.suppressUserDirectoryPushSoonForTesting = false;
      await dbHelper.closeAndDeleteDatabaseFile();
    });

    Future<void> enqueue({
      required int orderId,
      String phone = '07801146032',
      OilChangeWhatsappNotifyReason reason =
          OilChangeWhatsappNotifyReason.noInternet,
    }) {
      return outbox.enqueueFailure(
        customerPhone: phone,
        customerName: 'باقر',
        shopName: 'نابو',
        detailsBlock: 'تفاصيل البطاقة',
        messageText: '',
        templateParams: const {'customer_name': 'باقر'},
        reason: reason,
        orderId: orderId,
        employeeName: 'ail',
      );
    }

    test('فشل الإرسال يُحفظ في الطابور مع attemptId دائم', () async {
      await enqueue(orderId: 101);
      expect(await outbox.pendingCount(), 1);
      final pending = await outbox.loadPending();
      expect(pending, hasLength(1));
      expect(pending.first.orderId, 101);
      expect(
        pending.first.customerPhone,
        CustomerValidation.toE164IraqMobile('07801146032'),
      );
      expect(pending.first.reason, 'noInternet');
      expect(pending.first.reasonAr, contains('إنترنت'));
      expect(pending.first.attempts, 0);
      expect(pending.first.attemptId, isNotEmpty);
    });

    test('نفس orderId لا يكرّر الصف — يحدّث السبب دون زيادة attempts', () async {
      await enqueue(orderId: 202);
      final firstId = (await outbox.loadPending()).single.attemptId;
      await enqueue(
        orderId: 202,
        reason: OilChangeWhatsappNotifyReason.timeout,
      );
      expect(await outbox.pendingCount(), 1);
      final pending = await outbox.loadPending();
      expect(pending.single.attempts, 0);
      expect(pending.single.reason, 'timeout');
      expect(pending.single.attemptId, firstId);
    });

    test('markSent يشيل الرسالة من قائمة المعلّق', () async {
      await enqueue(orderId: 303);
      final id = (await outbox.loadPending()).single.id;
      expect(await outbox.markSent(id), isTrue);
      expect(await outbox.pendingCount(), 0);
      expect(await outbox.loadPending(), isEmpty);
    });

    test('discard يحذف الرسالة يدوياً', () async {
      await enqueue(orderId: 404);
      final id = (await outbox.loadPending()).single.id;
      await outbox.discard(id);
      expect(await outbox.pendingCount(), 0);
    });

    test('رقم فارغ لا يدخل الطابور', () async {
      await outbox.enqueueFailure(
        customerPhone: '   ',
        customerName: 'x',
        shopName: 'نابو',
        detailsBlock: '',
        messageText: 'مرحبا',
        templateParams: const {},
        reason: OilChangeWhatsappNotifyReason.noInternet,
        orderId: 505,
      );
      expect(await outbox.pendingCount(), 0);
    });

    test('toE164IraqMobile يوحّد الصيغ', () {
      expect(
        CustomerValidation.toE164IraqMobile('07801112233'),
        '+9647801112233',
      );
      expect(
        CustomerValidation.toE164IraqMobile('+9647801112233'),
        '+9647801112233',
      );
      expect(
        CustomerValidation.toE164IraqMobile('9647801112233'),
        '+9647801112233',
      );
      expect(
        CustomerValidation.phoneMatchKey('07801112233'),
        CustomerValidation.phoneMatchKey('+9647801112233'),
      );
      expect(
        CustomerValidation.coerceIraqiMobileDigits('+9647884289711'),
        '07884289711',
      );
      expect(
        CustomerValidation.iraqiMobilePhone(
          CustomerValidation.coerceIraqiMobileDigits('+9647884289711'),
        ),
        isNull,
      );
    });

    test('رقم غير قابل للتطبيع لا يدخل الطابور', () async {
      await outbox.enqueueFailure(
        customerPhone: '123',
        customerName: 'x',
        shopName: 'نابو',
        detailsBlock: '',
        messageText: 'مرحبا',
        templateParams: const {},
        reason: OilChangeWhatsappNotifyReason.noInternet,
        orderId: 606,
      );
      expect(await outbox.pendingCount(), 0);
    });

    test('loadPending(onlyDue) يصل للصفوف القديمة المستحقة', () async {
      await enqueue(orderId: 701);
      await enqueue(orderId: 702);
      final rows = await outbox.loadPending();
      expect(rows, hasLength(2));
      final newer = rows.firstWhere((e) => e.orderId == 702);
      final db = await DatabaseHelper().database;
      await db.update(
        'oil_change_wa_outbox',
        {
          'nextAttemptAt':
              DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [newer.id],
      );
      final due = await outbox.loadPending(onlyDue: true);
      expect(due.map((e) => e.orderId), contains(701));
      expect(due.map((e) => e.orderId), isNot(contains(702)));
    });
  });
}
