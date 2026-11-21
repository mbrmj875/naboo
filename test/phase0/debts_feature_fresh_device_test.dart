// ميزة الديون في تخصص الزيوت: لا تنطفئ على جهاز جديد، وتُفعَّل تلقائياً لمن
// عنده ديون مفتوحة.
//
// المرحلة 0 أثبتت الخلل: الجهاز الجديد كان يكتب إعدادات الزيوت بقيمة الديون
// المحلية الغائبة (تُقرأ «مطفأ»). الإصلاح في
// OwnerBusinessVerticalCloudService.applyToLocalIfNeeded وDebtsFeatureGuard.
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/services/app_settings_repository.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/debts_feature_guard.dart';

import '../oil_change/helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  setUp(() async {
    await OilChangeTestHarness.instance.reset();
    await DatabaseHelper().runStartupCriticalMigrations();
  });

  test('زيوت + ديون مطفأة + فاتورة آجلة مفتوحة: تُفعَّل الديون تلقائياً',
      () async {
    final repo = AppSettingsRepository.instance;
    await BusinessSetupSettingsData.createForVertical(
      BusinessVertical.oilChange,
      enableDebtsCustom: false,
    ).save(repo, forceVerticalCorrection: true);
    expect((await BusinessSetupSettingsData.load(repo)).enableDebts, isFalse);

    // بلا ديون مفتوحة: لا يتغير شيء.
    expect(await DebtsFeatureGuard.ensureOilDebtsEnabledIfOpenDebts(repo),
        isFalse);
    expect((await BusinessSetupSettingsData.load(repo)).enableDebts, isFalse);

    final db = await DatabaseHelper().database;
    await db.insert('invoices', {
      'customerName': 'زبون آجل',
      'date': DateTime.now().toIso8601String(),
      'type': InvoiceType.credit.index,
      'total': 30000.0,
      'totalFils': 30000000,
      'tenantId': await repo.getActiveTenantId(),
    });

    expect(await DebtsFeatureGuard.ensureOilDebtsEnabledIfOpenDebts(repo),
        isTrue);
    expect((await BusinessSetupSettingsData.load(repo)).enableDebts, isTrue);
  });
}
