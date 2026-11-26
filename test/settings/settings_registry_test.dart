import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/navigation/content_navigation.dart';
import 'package:naboo/screens/settings/settings_registry.dart';
import 'package:naboo/services/business_setup_settings.dart';

BusinessSetupSettingsData _retail({
  bool debts = true,
  bool installments = true,
  bool loyalty = true,
}) =>
    BusinessSetupSettingsData.createForVertical(
      BusinessVertical.generalRetail,
    ).copyWith(
      enableDebts: debts,
      enableInstallments: installments,
      enableLoyalty: loyalty,
      enableOilChange: false,
      enablePos: true,
    );

BusinessSetupSettingsData _oil() =>
    BusinessSetupSettingsData.createForVertical(BusinessVertical.oilChange);

SettingsAccess _access({
  required bool owner,
  required BusinessSetupSettingsData features,
  Set<String> hiddenRoutes = const {},
}) =>
    SettingsAccess(
      isOwner: owner,
      features: features,
      canSeeRoute: (r) => !hiddenRoutes.contains(r),
    );

Set<String> _ids(SettingsAccess a) =>
    visibleSettingsEntries(a).map((e) => e.id).toSet();

void main() {
  test('معرّفات البنود غير مكررة', () {
    final ids = kSettingsEntries.map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('كل بند له مجموعة لها عنوان', () {
    for (final e in kSettingsEntries) {
      expect(kSettingsGroupTitles[e.group], isNotNull, reason: e.id);
    }
  });

  group('الظهور', () {
    test('المالك في متجر تجزئة يرى الديون والتقسيط والولاء والمخزون', () {
      final ids = _ids(_access(owner: true, features: _retail()));
      expect(
        ids,
        containsAll([
          SettingsEntryIds.storeInfo,
          SettingsEntryIds.salePos,
          SettingsEntryIds.loyalty,
          SettingsEntryIds.debtSettings,
          SettingsEntryIds.installmentSettings,
          SettingsEntryIds.inventorySettings,
          SettingsEntryIds.returnPolicy,
          SettingsEntryIds.ownerAlerts,
          SettingsEntryIds.help,
        ]),
      );
      expect(ids, isNot(contains(SettingsEntryIds.branchInfo)));
      expect(ids, isNot(contains(SettingsEntryIds.oilHub)));
      expect(ids, isNot(contains(SettingsEntryIds.washOffers)));
    });

    test('الموظف لا يرى بنود المالك', () {
      final ids = _ids(_access(owner: false, features: _retail()));
      expect(ids, contains(SettingsEntryIds.branchInfo));
      for (final ownerOnly in [
        SettingsEntryIds.storeInfo,
        SettingsEntryIds.returnPolicy,
        SettingsEntryIds.debtsToggle,
        SettingsEntryIds.cashAudit,
        SettingsEntryIds.ownerAlerts,
        SettingsEntryIds.ownerDashboardCards,
        SettingsEntryIds.marketPickup,
      ]) {
        expect(ids, isNot(contains(ownerOnly)), reason: ownerOnly);
      }
    });

    test('إعدادات الدين تختفي إذا لم يُسمح بمسار الديون (صلاحية أو تخصص)', () {
      final ids = _ids(
        _access(
          owner: false,
          features: _retail(),
          hiddenRoutes: {AppContentRoutes.debts},
        ),
      );
      expect(ids, isNot(contains(SettingsEntryIds.debtSettings)));
    });

    test('الميزات المطفأة تخفي بنودها', () {
      final ids = _ids(
        _access(
          owner: true,
          features: _retail(debts: false, installments: false, loyalty: false),
        ),
      );
      expect(ids, isNot(contains(SettingsEntryIds.debtSettings)));
      expect(ids, isNot(contains(SettingsEntryIds.installmentSettings)));
      expect(ids, isNot(contains(SettingsEntryIds.loyalty)));
      // مفتاح تفعيل الديون يبقى، وإلا لا طريق لتشغيلها.
      expect(ids, contains(SettingsEntryIds.debtsToggle));
    });

    test('محل الزيت يرى إعدادات غيار الزيت، وعروض الغسيل للمالك فقط', () {
      expect(
        _ids(_access(owner: true, features: _oil())),
        containsAll([SettingsEntryIds.oilHub, SettingsEntryIds.washOffers]),
      );
      final staff = _ids(_access(owner: false, features: _oil()));
      expect(staff, contains(SettingsEntryIds.oilHub));
      expect(staff, isNot(contains(SettingsEntryIds.washOffers)));
    });

    test('ما يخفيه التخصص من المسارات يختفي من الإعدادات', () {
      final ids = _ids(
        _access(
          owner: true,
          features: _retail(),
          hiddenRoutes: {
            AppContentRoutes.salePosSettings,
            AppContentRoutes.inventorySettings,
          },
        ),
      );
      expect(ids, isNot(contains(SettingsEntryIds.salePos)));
      expect(ids, isNot(contains(SettingsEntryIds.inventorySettings)));
    });

    test('بند تثبيت الويب لا يظهر إلا حيث يُدعم', () {
      expect(
        _ids(_access(owner: true, features: _retail())),
        isNot(contains(SettingsEntryIds.pwaInstall)),
      );
      final web = SettingsAccess(
        isOwner: true,
        features: _retail(),
        canSeeRoute: (_) => true,
        pwaInstallSupported: true,
      );
      expect(_ids(web), contains(SettingsEntryIds.pwaInstall));
    });

    test('البنود مرتبة حسب المجموعات', () {
      final list = visibleSettingsEntries(
        _access(owner: true, features: _retail()),
      );
      final groups = list.map((e) => e.group.index).toList();
      final sorted = [...groups]..sort();
      expect(groups, sorted);
    });

    test('اللغة ظاهرة لكنها معطّلة', () {
      final lang = kSettingsEntries.firstWhere(
        (e) => e.id == SettingsEntryIds.language,
      );
      expect(lang.enabled, isFalse);
    });
  });

  group('البحث', () {
    List<String> search(String q, {bool owner = true}) =>
        visibleSettingsEntries(_access(owner: owner, features: _retail()))
            .where((e) => settingsEntryMatches(e, q))
            .map((e) => e.id)
            .toList();

    test('يجد الإعداد باسمه الداخلي', () {
      expect(search('ضريبة'), contains(SettingsEntryIds.salePos));
      expect(search('سقف'), contains(SettingsEntryIds.debtSettings));
      expect(search('طابعة'), contains(SettingsEntryIds.printing));
      expect(search('الباركود'), contains(SettingsEntryIds.inventorySettings));
      expect(search('واتساب'), contains(SettingsEntryIds.help));
    });

    test('التذييل والشعار صارا في الطباعة بعد حذف شاشة الفواتير الوهمية', () {
      expect(search('التذييل'), [SettingsEntryIds.printing]);
      expect(search('الشعار'), contains(SettingsEntryIds.printing));
      expect(search('ضريبة'), isNot(contains('invoice_settings')));
    });

    test('يتجاهل الهمزات والتاء المربوطة والتشكيل', () {
      expect(search('الضريبه'), contains(SettingsEntryIds.salePos));
      expect(search('اعدادات الدين'), contains(SettingsEntryIds.debtSettings));
      expect(search('الطَّابِعَة'), contains(SettingsEntryIds.printing));
    });

    test('كل الكلمات يجب أن تطابق', () {
      expect(search('إعدادات الدين'), [SettingsEntryIds.debtSettings]);
    });

    test('لا يُظهر بنداً مخفياً على المستخدم', () {
      expect(
        search('سياسة الاسترجاع', owner: false),
        isNot(contains(SettingsEntryIds.returnPolicy)),
      );
    });

    test('بحث فارغ يطابق الكل، وكلمة غريبة لا تطابق شيئاً', () {
      final all = visibleSettingsEntries(
        _access(owner: true, features: _retail()),
      );
      expect(search('').length, all.length);
      expect(search('زززز'), isEmpty);
    });
  });
}
