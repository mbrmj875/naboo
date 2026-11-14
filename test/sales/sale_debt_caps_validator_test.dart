import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/debt_settings_data.dart';
import 'package:naboo/services/cloud_sync_service.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/sale_debt_caps_validator.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SaleDebtCapsValidator', () {
    late DatabaseHelper db;

    setUp(() async {
      CloudSyncService.instance.suppressUserDirectoryPushSoonForTesting = true;
      TenantContext.instance.set('local-debt-caps-test');
      db = DatabaseHelper();
      await db.closeAndDeleteDatabaseFile();
    });

    tearDown(() async {
      CloudSyncService.instance.suppressUserDirectoryPushSoonForTesting = false;
      TenantContext.instance.clear();
      await db.closeAndDeleteDatabaseFile();
    });

    test('بلا سقف فعّال — يسمح بأي متبقٍ', () async {
      await db.saveDebtSettings(
        const DebtSettingsData(
          maxTotalOpenDebtPerCustomer: 0,
          maxOpenRemainingPerInvoice: 0,
          warnDebtAgeDays: 0,
          enforceCustomerCapAtSale: true,
          enforceSingleInvoiceCapAtSale: true,
        ),
      );

      final msg = await SaleDebtCapsValidator.validate(
        customerId: 1,
        customerName: 'علي',
        remainderFils: 5_000_000, // 5000 د.ع
        db: db,
      );
      expect(msg, isNull);
    });

    test('سقف الفاتورة الواحدة يرفض متبقياً أعلى من الحد', () async {
      await db.saveDebtSettings(
        const DebtSettingsData(
          maxTotalOpenDebtPerCustomer: 0,
          maxOpenRemainingPerInvoice: 100, // 100 د.ع
          warnDebtAgeDays: 0,
          enforceCustomerCapAtSale: false,
          enforceSingleInvoiceCapAtSale: true,
        ),
      );

      final msg = await SaleDebtCapsValidator.validate(
        customerId: null,
        customerName: 'زبون',
        remainderFils: 150_000, // 150 د.ع
        db: db,
      );
      expect(msg, isNotNull);
      expect(msg!, contains('حد الدين للفاتورة'));
    });

    test('سقف الفاتورة الواحدة يسمح بمتبقٍ ضمن الحد', () async {
      await db.saveDebtSettings(
        const DebtSettingsData(
          maxTotalOpenDebtPerCustomer: 0,
          maxOpenRemainingPerInvoice: 100,
          warnDebtAgeDays: 0,
          enforceCustomerCapAtSale: false,
          enforceSingleInvoiceCapAtSale: true,
        ),
      );

      final msg = await SaleDebtCapsValidator.validate(
        customerId: null,
        customerName: 'زبون',
        remainderFils: 80_000, // 80 د.ع
        db: db,
      );
      expect(msg, isNull);
    });

    test('سقف العميل يرفض عندما المتبقي وحده يتجاوز السقف', () async {
      await db.saveDebtSettings(
        const DebtSettingsData(
          maxTotalOpenDebtPerCustomer: 200,
          maxOpenRemainingPerInvoice: 0,
          warnDebtAgeDays: 0,
          enforceCustomerCapAtSale: true,
          enforceSingleInvoiceCapAtSale: false,
        ),
      );

      final msg = await SaleDebtCapsValidator.validate(
        customerId: 99,
        customerName: 'باقر',
        remainderFils: 250_000, // 250 د.ع — لا دين سابق
        db: db,
      );
      expect(msg, isNotNull);
      expect(msg!, contains('حد الدين للعميل'));
    });

    test('تعطل إنفاذ سقف الفاتورة يتجاهل الحد حتى لو مُعرَّف', () async {
      await db.saveDebtSettings(
        const DebtSettingsData(
          maxTotalOpenDebtPerCustomer: 0,
          maxOpenRemainingPerInvoice: 10,
          warnDebtAgeDays: 0,
          enforceCustomerCapAtSale: false,
          enforceSingleInvoiceCapAtSale: false,
        ),
      );

      final msg = await SaleDebtCapsValidator.validate(
        customerId: null,
        customerName: 'زبون',
        remainderFils: 500_000,
        db: db,
      );
      expect(msg, isNull);
    });
  });
}
