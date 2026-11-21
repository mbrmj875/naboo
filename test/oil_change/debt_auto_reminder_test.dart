// المرحلة 7 — الشريحة 4: تذكير الدين التلقائي. رسالة واحدة لكل عميل يوم تأخّر
// دينه، بالمجموع، ومن يوم التفعيل فقط، ولا تتكرر.
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/debt_settings_data.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/services/app_settings_repository.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/debt_auto_reminder_service.dart';
import 'package:naboo/services/tenant_context.dart';

import 'helpers/oil_change_test_harness.dart';

const _k = 1000;
final _now = DateTime(2026, 11, 22, 10);

DebtReminderParty _party(
  String key,
  List<(int daysAgo, int dinars)> inv, {
  String phone = '07700000001',
  int period = 30,
}) =>
    DebtReminderParty(
      key: key,
      phone: phone,
      name: 'زبون $key',
      periodDays: period,
      invoices: [
        for (final (d, v) in inv)
          (date: _now.subtract(Duration(days: d)), remainingFils: v * _k),
      ],
    );

class _FakeTransport implements DebtReminderTransport {
  _FakeTransport({this.template = 'approved', this.reply = 'sent'});

  String? template;
  String reply;
  final sent = <DebtReminderCandidate>[];

  @override
  bool get signedIn => true;

  @override
  Future<String?> templateStatus() async => template;

  @override
  Future<String?> submitTemplate() async => template = 'pending';

  @override
  Future<({String status, bool retryLater})> send(
    DebtReminderCandidate c,
  ) async {
    sent.add(c);
    return (
      status: reply,
      retryLater: reply != 'sent' && reply != 'opted_out',
    );
  }
}

void main() {
  group('المخطِّط', () {
    final since = _now.subtract(const Duration(days: 60));

    test('رسالة واحدة بمجموع الدين كله، ومفتاحها بيوم أحدث تأخّر', () {
      final plan = planDebtReminders(
        parties: [
          _party('a', [(45, 20000), (35, 10000), (5, 7000)]),
        ],
        since: since,
        now: _now,
        alreadySent: {},
      );
      expect(plan, hasLength(1));
      expect(plan.single.openFils, 37000 * _k, reason: 'الدين كله لا المتأخر');
      // أحدث فاتورة متأخرة بتاريخ 18/10 (عمرها 35 يوماً): تأخّرت يوم 18/11.
      expect(plan.single.reminderKey, 'a|2026-11-18');
      expect(plan.single.oldestDate, _now.subtract(const Duration(days: 45)));
    });

    test('لا تكرار، وفاتورة تتأخر لاحقاً تأتي برسالة جديدة', () {
      final first = planDebtReminders(
        parties: [_party('a', [(40, 20000)])],
        since: since,
        now: _now,
        alreadySent: {},
      );
      final again = planDebtReminders(
        parties: [_party('a', [(40, 20000)])],
        since: since,
        now: _now,
        alreadySent: {first.single.reminderKey},
      );
      expect(again, isEmpty);
      final later = planDebtReminders(
        parties: [_party('a', [(40, 20000), (31, 5000)])],
        since: since,
        now: _now,
        alreadySent: {first.single.reminderKey},
      );
      expect(later, hasLength(1));
      expect(later.single.reminderKey, isNot(first.single.reminderKey));
    });

    test('ما تأخّر قبل يوم التفعيل لا يُرسل', () {
      final plan = planDebtReminders(
        parties: [_party('a', [(200, 20000)])],
        since: _now.subtract(const Duration(days: 3)),
        now: _now,
        alreadySent: {},
      );
      expect(plan, isEmpty);
      // تأخّرت أمس (عمرها 31 يوماً) والتفعيل قبل 3 أيام: تُرسل.
      expect(
        planDebtReminders(
          parties: [_party('a', [(200, 20000), (31, 1000)])],
          since: _now.subtract(const Duration(days: 3)),
          now: _now,
          alreadySent: {},
        ),
        hasLength(1),
      );
    });

    test('بلا هاتف أو بلا فترة أو دين غير متأخر: لا رسالة', () {
      expect(
        planDebtReminders(
          parties: [
            _party('a', [(40, 20000)], phone: ''),
            _party('b', [(40, 20000)], period: 0),
            _party('c', [(30, 20000)]),
            _party('d', [(40, 0)]),
          ],
          since: since,
          now: _now,
          alreadySent: {},
        ),
        isEmpty,
      );
    });
  });

  group('التشغيل', () {
    setUpAll(initOilChangeTestEnvironment);
    late OilChangeTestHarness h;
    late _FakeTransport fake;
    final svc = DebtAutoReminderService.instance;

    Future<int> customer(String name, String phone) async {
      final db = await h.database;
      return db.insert('customers', {
        'tenantId': await h.tenantId(),
        'name': name,
        'phone': phone,
        'global_id': 'cust-$name',
        'balance': 0,
        'loyaltyPoints': 0,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
    }

    Future<void> credit(int cid, String name, int daysAgo, int dinars) async {
      final db = await h.database;
      await db.insert('invoices', {
        'tenantId': await h.tenantId(),
        'customerId': cid,
        'customerName': name,
        'date': DateTime.now().subtract(Duration(days: daysAgo)).toIso8601String(),
        'type': InvoiceType.credit.index,
        'total': dinars.toDouble(),
        'totalFils': dinars * _k,
        'advancePayment': 0.0,
        'advancePaymentFils': 0,
        'isReturned': 0,
      });
    }

    setUp(() async {
      TenantContext.instance.set('debt-auto-reminder-test');
      addTearDown(TenantContext.instance.clear);
      h = OilChangeTestHarness.instance;
      await h.reset();
      await h.configureHybrid();
      fake = _FakeTransport();
      svc.transport = fake;
      svc.clock = DateTime.now;
      await DatabaseHelper().saveDebtSettings(
        DebtSettingsData.defaults().copyWith(
          reminderMode: DebtReminderMode.auto,
        ),
      );
    });

    Future<void> enableSince(int daysAgo) async {
      final s = AppSettingsRepository.instance;
      await s.setForTenant(
        DebtAutoReminderService.sinceKey,
        DateTime.now().subtract(Duration(days: daysAgo)).toIso8601String(),
        tenantId: await s.getActiveTenantId(),
      );
    }

    test('يرسل للمتأخر مرة واحدة، ولا يرسل ثانية في اليوم نفسه', () async {
      final ali = await customer('علي', '07701112233');
      await credit(ali, 'علي', 32, 20000);
      final kr = await customer('كرار', '07701112244');
      await credit(kr, 'كرار', 10, 9000); // غير متأخر
      await enableSince(5);

      expect(await svc.runIfDue(force: true), 1);
      expect(fake.sent.single.phone, '07701112233');
      expect(fake.sent.single.reminderKey, startsWith('cust-علي|'));
      expect(fake.sent.single.openFils, 20000 * _k);

      expect(await svc.runIfDue(force: true), 0, reason: 'المفتاح محفوظ');
      expect(fake.sent, hasLength(1));
    });

    test('أول تشغيل بلا يوم تفعيل: يبدأ العد من اليوم ولا يرسل للقديم',
        () async {
      final ali = await customer('علي', '07701112233');
      await credit(ali, 'علي', 32, 20000);
      expect(await svc.runIfDue(force: true), 0);
      expect(fake.sent, isEmpty);
      final s = AppSettingsRepository.instance;
      expect(
        await s.getForTenant(
          DebtAutoReminderService.sinceKey,
          tenantId: await s.getActiveTenantId(),
        ),
        isNotEmpty,
      );
    });

    test('القالب غير معتمد أو الرصيد ناقص: لا يُحفظ فيُعاد لاحقاً', () async {
      final ali = await customer('علي', '07701112233');
      await credit(ali, 'علي', 32, 20000);
      await enableSince(5);

      fake.template = 'pending';
      expect(await svc.runIfDue(force: true), 0);
      expect(fake.sent, isEmpty);

      fake.template = 'approved';
      fake.reply = 'insufficient_balance';
      expect(await svc.runIfDue(force: true), 0);
      expect(fake.sent, hasLength(1));

      fake.reply = 'sent';
      expect(await svc.runIfDue(force: true), 1, reason: 'أُعيد بعد شحن الرصيد');
    });

    test('«يدوي» لا يرسل شيئاً ويمسح يوم التفعيل', () async {
      final ali = await customer('علي', '07701112233');
      await credit(ali, 'علي', 32, 20000);
      await enableSince(5);
      await DatabaseHelper().saveDebtSettings(
        DebtSettingsData.defaults(),
      );
      await svc.onModeChanged(DebtReminderMode.manual);
      expect(await svc.runIfDue(force: true), 0);
      expect(fake.sent, isEmpty);
      final s = AppSettingsRepository.instance;
      expect(
        await s.getForTenant(
          DebtAutoReminderService.sinceKey,
          tenantId: await s.getActiveTenantId(),
        ),
        '',
      );
    });
  });
}
