import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/models/print_settings_data.dart';
import 'package:naboo/printing/public_receipt.dart';
import 'package:naboo/printing/receipt_builders.dart';
import 'package:naboo/printing/receipt_design.dart';
import 'package:naboo/printing/receipt_model.dart';
import 'package:naboo/utils/invoice_deep_link.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// المرحلة 6: رابط صفحة الفاتورة على naboo.fun.
///
/// `PUBLIC_RECEIPT_SNAPSHOT_DIR=/path` يحفظ نسخاً حقيقية لمعاينة الصفحة.
const _gid = '3f2a9c4e-8b1d-4f6a-9c2e-1a2b3c4d5e6f';

final _settings = PrintSettingsData.defaults().copyWith(
  storeTitleLine: 'مركز البصرة لتبديل الزيوت',
  storeAddress: 'البصرة — الجزائر',
  storePhones: ['0780 123 4567'],
);

ReceiptDocument _withGid(ReceiptDocument d) =>
    d.withQr(InvoiceDeepLink.uriForInvoiceId(1026, globalId: _gid));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar');
    sqfliteFfiInit();
  });

  group('الرابط', () {
    test('رمز عشوائي بطول 22 من الحروف والأرقام فقط', () {
      final seen = <String>{};
      for (var i = 0; i < 200; i++) {
        final t = PublicReceiptLink.newToken();
        expect(t, matches(RegExp(r'^[A-Za-z0-9]{22}$')));
        seen.add(t);
      }
      expect(seen.length, 200);
    });

    test('صياغة الرابط وقراءته', () {
      final t = PublicReceiptLink.newToken(Random(1));
      final u = PublicReceiptLink.url(t, globalId: _gid);
      expect(u, 'https://naboo.fun/r/$t?g=$_gid');
      final r = PublicReceiptLink.parse(Uri.parse(u))!;
      expect(r.token, t);
      expect(r.globalId, _gid);
      expect(
        PublicReceiptLink.parse(Uri.parse('https://naboo.fun/r/$t'))!.globalId,
        isNull,
      );
      expect(
        PublicReceiptLink.parse(Uri.parse('https://www.naboo.fun/r/$t')),
        isNotNull,
      );
    });

    test('روابط مرفوضة', () {
      final t = PublicReceiptLink.newToken();
      for (final bad in [
        'https://evil.com/r/$t',
        'https://naboo.fun/m/$t',
        'https://naboo.fun/r/short',
        'https://naboo.fun/r/$t/x',
        'https://naboo.fun/r/$t?g=not-a-uuid',
        'basrainvoice://invoice/5',
        'ftp://naboo.fun/r/$t',
      ]) {
        expect(PublicReceiptLink.parse(Uri.parse(bad)), isNull, reason: bad);
      }
    });
  });

  group('النسخة', () {
    test('رقم واتساب العراق من هاتف المحل', () {
      expect(
        PublicReceiptSnapshot.whatsappNumber(['0780 123 4567']),
        '9647801234567',
      );
      expect(
        PublicReceiptSnapshot.whatsappNumber(['+964 780 123 4567']),
        '9647801234567',
      );
      expect(
        PublicReceiptSnapshot.whatsappNumber(['00964 7801234567']),
        '9647801234567',
      );
      expect(
        PublicReceiptSnapshot.whatsappNumber(['040 123', '07801234567']),
        '9647801234567',
      );
      expect(PublicReceiptSnapshot.whatsappNumber(['12345']), isNull);
    });

    test('تحمل ما يظهر في الإيصال فقط', () {
      final doc = ReceiptBuilders.sample(ReceiptKind.oilChange);
      final t = ReceiptTemplate.defaultsFor(ReceiptKind.oilChange);
      final all = PublicReceiptSnapshot.build(
        doc,
        settings: _settings,
        template: t,
      );
      expect(all['title'], 'إيصال غيار زيت');
      expect((all['store'] as Map)['whatsapp'], '9647801234567');
      expect((all['fields'] as List).any((f) => f[0] == 'اللوحة'), isTrue);
      expect((all['loyalty'] as Map)['visit'], 7);
      final hidden = PublicReceiptSnapshot.build(
        doc,
        settings: _settings,
        template: t.copyWith(
          hidden: {ReceiptSection.plate, ReceiptSection.loyalty},
        ),
      );
      expect((hidden['fields'] as List).any((f) => f[0] == 'اللوحة'), isFalse);
      expect(hidden.containsKey('loyalty'), isFalse);
      // لا معرّفات داخلية في النسخة العامة.
      final s = jsonEncode(all);
      expect(s.contains('basrainvoice'), isFalse);
      expect(utf8.encode(s).length, lessThan(8000));
    });

    test('سطر التوقيع لا يظهر في الصفحة', () {
      final doc = ReceiptBuilders.sample(ReceiptKind.expense);
      final s = PublicReceiptSnapshot.build(
        doc,
        settings: _settings,
        template: ReceiptTemplate.defaultsFor(ReceiptKind.expense),
      );
      expect((s['notes'] as List).any((n) => '$n'.contains('توقيع')), isFalse);
    });

    test('حفظ نسخ حقيقية لمعاينة الصفحة', () async {
      final dir = Platform.environment['PUBLIC_RECEIPT_SNAPSHOT_DIR'];
      if (dir == null) return;
      for (final k in [
        ReceiptKind.oilChange,
        ReceiptKind.carWash,
        ReceiptKind.sale,
      ]) {
        final s = PublicReceiptSnapshot.build(
          ReceiptBuilders.sample(k),
          settings: _settings,
          template: ReceiptTemplate.defaultsFor(k),
          design: const ReceiptDesign(
            palette: ReceiptPalette(accent: 0xFF0F4C81),
          ),
        );
        File('$dir/${k.name}.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode(s));
      }
    });
  });

  group('الإرفاق والرفع', () {
    late Database db;
    late List<(String, Map<String, dynamic>)> calls;
    var ready = false;
    var online = true;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await PublicReceiptLinks.ensureSchema(db);
      calls = [];
      ready = false;
      online = true;
      PublicReceiptLinks.database = () async => db;
      PublicReceiptLinks.rpc = (fn, p) async {
        if (!online) throw const SocketException('offline');
        calls.add((fn, p));
      };
      PublicReceiptLinks.serverReady = () async => ready;
      PublicReceiptLinks.markServerReady = () async => ready = true;
    });
    tearDown(() => db.close());

    Future<ReceiptDocument> attach(ReceiptDocument d) =>
        PublicReceiptLinks.attach(
          d,
          settings: _settings,
          template: ReceiptTemplate.defaultsFor(d.kind),
        );

    test(
      'قبل جاهزية الخادم يبقى رمز التطبيق، وأول رفع ناجح يفعّل الرابط',
      () async {
        final doc = _withGid(ReceiptBuilders.sample(ReceiptKind.sale));
        final first = await attach(doc);
        expect(first.qrData, doc.qrData);
        await PublicReceiptLinks.flush();
        expect(calls.single.$1, 'receipt_publish');
        expect(calls.single.$2['p_invoice_global_id'], _gid);
        expect(ready, isTrue);
        final second = await attach(doc);
        final ref = PublicReceiptLink.parse(Uri.parse(second.qrData!))!;
        expect(ref.globalId, _gid);
        expect(ref.token, calls.single.$2['p_token']);
      },
    );

    test('إعادة الطباعة تُبقي الرمز نفسه ولا تعيد الرفع بلا تغيير', () async {
      ready = true;
      final doc = _withGid(ReceiptBuilders.sample(ReceiptKind.sale));
      final a = await attach(doc);
      await PublicReceiptLinks.flush();
      final b = await attach(doc);
      await PublicReceiptLinks.flush();
      expect(a.qrData, b.qrData);
      expect(calls.length, 1);
      final rows = await db.query('receipt_public_links');
      expect(rows.length, 1);
    });

    test('بلا إنترنت: يُطبع الرابط ويُرفع لاحقاً', () async {
      ready = true;
      online = false;
      final doc = _withGid(ReceiptBuilders.sample(ReceiptKind.carWash));
      final out = await attach(doc);
      expect(out.qrData, startsWith('https://naboo.fun/r/'));
      await PublicReceiptLinks.flush();
      expect(calls, isEmpty);
      expect(
        (await db.query('receipt_public_links', where: 'uploaded = 0')).length,
        1,
      );
      online = true;
      await PublicReceiptLinks.flush();
      expect(calls.length, 1);
      expect(
        (await db.query('receipt_public_links', where: 'uploaded = 0')),
        isEmpty,
      );
    });

    test('إيصال بلا معرّف عالمي أو بلا QR لا يُلمس', () async {
      ready = true;
      final legacy = ReceiptBuilders.sample(
        ReceiptKind.sale,
      ).withQr(InvoiceDeepLink.uriForInvoiceId(5));
      expect((await attach(legacy)).qrData, legacy.qrData);
      final none = ReceiptBuilders.sample(ReceiptKind.expense).withQr(null);
      expect((await attach(none)).qrData, isNull);
      expect(await db.query('receipt_public_links'), isEmpty);
    });

    test('المسح داخل التطبيق يعرف الفاتورة من الرابط أو من الجهاز', () async {
      ready = true;
      final out = await attach(
        _withGid(ReceiptBuilders.sample(ReceiptKind.sale)),
      );
      final ref = PublicReceiptLink.parse(Uri.parse(out.qrData!))!;
      expect(await PublicReceiptLinks.globalIdFor(ref), _gid);
      expect(
        await PublicReceiptLinks.globalIdFor(PublicReceiptRef(ref.token, null)),
        _gid,
      );
    });

    test('الاسترجاع الكامل يعلّم روابط الفاتورة فقط إن وُجدت', () async {
      await PublicReceiptLinks.setState(_gid, 'returned');
      expect(calls, isEmpty);
      await attach(_withGid(ReceiptBuilders.sample(ReceiptKind.sale)));
      await PublicReceiptLinks.flush();
      calls.clear();
      await PublicReceiptLinks.setState(_gid, 'returned');
      expect(calls.single.$1, 'receipt_set_state');
      expect(calls.single.$2, {
        'p_invoice_global_id': _gid,
        'p_state': 'returned',
      });
    });
  });
}
