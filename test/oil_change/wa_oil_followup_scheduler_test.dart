import 'dart:async';
import 'dart:io';

import 'package:naboo/verticals/oil_change/services/wa_oil_followup_scheduler.dart';
import 'package:naboo/verticals/oil_change/widgets/wa_reminder_consent_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<(String, Map<String, dynamic>)> calls;
  late FutureOr<dynamic> Function(String) respond;

  WaOilFollowupScheduler build([String uid = 'u1']) =>
      WaOilFollowupScheduler.forTest((fn, params) async {
        calls.add((fn, params));
        return respond(fn);
      }, uid);

  Future<void> enqueue(WaOilFollowupScheduler s, {bool? consent, int id = 7}) =>
      s.enqueueAfterSave(
        orderId: id,
        customerPhone: '07701234567',
        order: const {},
        storeTitle: 'المحل',
        consent: consent,
      );

  List<String> names() => calls.map((c) => c.$1).toList();

  setUpAll(() => initializeDateFormatting('ar_SA'));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    respond = (fn) => fn == 'wa_recipient_consent_set' ? 'consented' : null;
  });

  test('الخيار المفعّل يسجل الموافقة ثم يجدول التذكير', () async {
    await enqueue(build(), consent: true);
    expect(names(), ['wa_recipient_consent_set', 'wa_followup_schedule_job']);
    expect(calls.first.$2['p_consented'], true);
  });

  test('رفض الزبون لا يجدول تذكيرًا', () async {
    respond = (fn) => 'opted_out';
    await enqueue(build(), consent: false);
    expect(names(), ['wa_recipient_consent_set']);
  });

  test('تصحيح البطاقة لا يغيّر الموافقة', () async {
    await enqueue(build());
    expect(names(), ['wa_followup_schedule_job']);
  });

  test('غياب دالة الموافقة قبل النشر لا يوقف التذكير', () async {
    respond = (fn) {
      if (fn == 'wa_recipient_consent_set') {
        throw const PostgrestException(message: 'x', code: '42883');
      }
    };
    await enqueue(build(), consent: true);
    expect(names().last, 'wa_followup_schedule_job');
  });

  test('انقطاع الشبكة لا يضيّع التذكير ويحفظ وقت الحفظ الأصلي', () async {
    final s = build();
    respond = (fn) => throw const SocketException('offline');
    await enqueue(s);
    final savedAt = calls.single.$2['p_saved_at'];

    calls.clear();
    respond = (fn) => null;
    await s.flushPending();
    expect(names(), ['wa_followup_schedule_job']);
    expect(calls.single.$2['p_saved_at'], savedAt);

    calls.clear();
    await s.flushPending();
    expect(calls, isEmpty);
  });

  test('الانقطاع يحفظ قرار الرفض أيضًا', () async {
    final s = build();
    respond = (fn) => throw const SocketException('offline');
    await enqueue(s, consent: false);

    calls.clear();
    respond = (fn) => 'opted_out';
    await s.flushPending();
    expect(names(), ['wa_recipient_consent_set']);
    expect(calls.single.$2['p_consented'], false);
  });

  test('المعلّق لحساب آخر لا يُرسل بهذا الحساب', () async {
    respond = (fn) => throw const SocketException('offline');
    await enqueue(build('u1'));

    calls.clear();
    respond = (fn) => null;
    await build('u2').flushPending();
    expect(calls, isEmpty);
    await build('u1').flushPending();
    expect(calls, hasLength(1));
  });

  test('رفض الخادم للطلب لا يبقى يتكرر', () async {
    final s = build();
    respond = (fn) =>
        throw const PostgrestException(message: 'bad', code: '22000');
    await enqueue(s);

    calls.clear();
    await s.flushPending();
    expect(calls, isEmpty);
  });

  Future<Switch> pumpTile(
    WidgetTester t,
    WaRecipientConsentStatus prior,
    bool value,
  ) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WaReminderConsentTile(
          value: value,
          prior: prior,
          onChanged: (_) {},
        ),
      ),
    ));
    return t.widget<Switch>(find.byType(Switch));
  }

  testWidgets('طلب الزبون الإيقاف لا يلغيه الموظف', (t) async {
    final sw =
        await pumpTile(t, WaRecipientConsentStatus.customerOptedOut, true);
    expect(sw.value, false);
    expect(sw.onChanged, isNull);
  });

  testWidgets('رفض سابق عند الموظف يمكن تفعيله إذا وافق الزبون', (t) async {
    final sw =
        await pumpTile(t, WaRecipientConsentStatus.staffDeclined, false);
    expect(sw.value, false);
    expect(sw.onChanged, isNotNull);
    expect(find.textContaining('رفض الزبون'), findsOneWidget);
  });
}
