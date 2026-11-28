import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/models/print_settings_data.dart';
import 'package:naboo/printing/receipt_builders.dart';
import 'package:naboo/printing/receipt_model.dart';
import 'package:naboo/printing/receipt_printer.dart';
import 'package:naboo/printing/receipt_renderer.dart';
import 'package:naboo/services/service_order_kinds.dart';

/// كل مفتاح في قالب الإيصال يغيّر الورقة فعلاً (لا مفتاح بلا أثر).
Future<void> _loadFonts() async {
  final loader = FontLoader('Tajawal');
  for (final f in [
    'assets/fonts/Tajawal-Regular.ttf',
    'assets/fonts/Tajawal-Bold.ttf',
  ]) {
    loader.addFont(
      Future.value(ByteData.sublistView(File(f).readAsBytesSync())),
    );
  }
  await loader.load();
}

/// عدد الصفحات في PDF (عدّ كائنات `/Type /Page` لا `/Pages`).
int _pdfPages(Uint8List bytes) =>
    RegExp(r'/Type\s*/Page(?![s\w])').allMatches(latin1.decode(bytes)).length;

final _base = PrintSettingsData.defaults().copyWith(
  storeTitleLine: 'مركز البصرة لتبديل الزيوت',
);

Future<RenderedReceipt> _render(
  ReceiptKind kind,
  ReceiptTemplate t, {
  PrintSettingsData? settings,
  ReceiptPaper paper = ReceiptPaper.mm80,
}) => ReceiptRenderer.render(
  ReceiptBuilders.sample(kind),
  settings: settings ?? _base,
  template: t,
  paper: paper,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('en');
    await _loadFonts();
  });

  group('سطر «شكراً لزيارتكم»', () {
    test('بلا اختيار صريح: السلوك القديم (يظهر فقط بلا نص تذييل)', () {
      const t = ReceiptTemplate(autoPrint: true);
      expect(t.showThanks, isNull);
      expect(t.thanksShown(hasFooterText: false), isTrue);
      expect(t.thanksShown(hasFooterText: true), isFalse);
    });

    test('إطفاؤه يقصّر الإيصال، وتشغيله مع تذييل يطوّله', () async {
      final d = ReceiptTemplate.defaultsFor(ReceiptKind.oilChange);
      final on = await _render(ReceiptKind.oilChange, d);
      final off = await _render(
        ReceiptKind.oilChange,
        d.copyWith(showThanks: false),
      );
      expect(off.height, lessThan(on.height));

      final withFooter = _base.copyWith(footerExtra: 'الضمان 5000 كم');
      final footerOnly = await _render(
        ReceiptKind.oilChange,
        d,
        settings: withFooter,
      );
      final footerAndThanks = await _render(
        ReceiptKind.oilChange,
        d.copyWith(showThanks: true),
        settings: withFooter,
      );
      expect(footerAndThanks.height, greaterThan(footerOnly.height));
      for (final r in [on, off, footerOnly, footerAndThanks]) {
        r.dispose();
      }
    });

    test('يُحفظ ويُقرأ، وغيابه من JSON القديم يبقى `null`', () {
      final t = ReceiptTemplate.defaultsFor(
        ReceiptKind.carWash,
      ).copyWith(showThanks: false);
      final back = ReceiptTemplate.fromJson(ReceiptKind.carWash, t.toJson());
      expect(back.showThanks, isFalse);
      expect(back, t);
      final old = ReceiptTemplate.fromJson(ReceiptKind.carWash, {
        'autoPrint': true,
      });
      expect(old.showThanks, isNull);
      expect(old.toJson().containsKey('showThanks'), isFalse);
    });
  });

  group('عدد النسخ على طابعة النظام / PDF', () {
    test('اللفافة: صفحة لكل نسخة', () async {
      final r = await _render(
        ReceiptKind.saleReturn,
        ReceiptTemplate.defaultsFor(ReceiptKind.saleReturn),
      );
      expect(_pdfPages(await ReceiptPrinter.pdfBytes(r, ReceiptPaper.mm80)), 1);
      expect(
        _pdfPages(
          await ReceiptPrinter.pdfBytes(r, ReceiptPaper.mm80, copies: 2),
        ),
        2,
      );
      expect(
        _pdfPages(
          await ReceiptPrinter.pdfBytes(r, ReceiptPaper.mm80, copies: 9),
        ),
        3,
        reason: 'النسخ من 1 إلى 3 فقط',
      );
      r.dispose();
    });

    test('A4: كل صفحات الإيصال تتكرر بعدد النسخ', () async {
      final r = await _render(
        ReceiptKind.oilChange,
        ReceiptTemplate.defaultsFor(ReceiptKind.oilChange),
        paper: ReceiptPaper.a4,
      );
      final one = _pdfPages(await ReceiptPrinter.pdfBytes(r, ReceiptPaper.a4));
      final three = _pdfPages(
        await ReceiptPrinter.pdfBytes(r, ReceiptPaper.a4, copies: 3),
      );
      expect(one, greaterThanOrEqualTo(1));
      expect(three, one * 3);
      r.dispose();
    });
  });

  group('مفتاح «المدفوع والمتبقي»', () {
    test('البيع الآجل: المدفوع والمتبقي مربوطان بالقسم', () {
      final doc = ReceiptBuilders.sample(ReceiptKind.directSale);
      final paid = doc.totals.where(
        (t) => t.label == 'المدفوع' || t.label == 'المتبقي',
      );
      expect(paid, hasLength(2));
      expect(paid.every((t) => t.section == ReceiptSection.payment), isTrue);
      // الإجمالي يبقى دائماً.
      expect(
        doc.totals.firstWhere((t) => t.emphasis).section,
        isNull,
      );
    });

    test('إخفاؤه يقصّر الإيصال فعلاً', () async {
      final d = ReceiptTemplate.defaultsFor(ReceiptKind.directSale);
      final shown = await _render(ReceiptKind.directSale, d);
      final hidden = await _render(
        ReceiptKind.directSale,
        d.copyWith(hidden: {ReceiptSection.payment}),
      );
      expect(hidden.height, lessThan(shown.height));
      shown.dispose();
      hidden.dispose();
    });

    test('يظهر في قوالب الغيار والغسيل والبيع', () {
      for (final k in [
        ReceiptKind.oilChange,
        ReceiptKind.carWash,
        ReceiptKind.directSale,
        ReceiptKind.sale,
      ]) {
        expect(k.sections, contains(ReceiptSection.payment), reason: k.name);
      }
    });
  });

  group('الغسلة داخل بطاقة الزيت', () {
    ReceiptDocument card() => ReceiptBuilders.fromInvoice(
      Invoice(
        id: 7,
        customerName: 'أحمد',
        date: DateTime(2026, 11, 27),
        type: InvoiceType.cash,
        items: [
          InvoiceItem(
            productName: 'غيار زيت',
            quantity: 1,
            price: 30000,
            total: 30000,
          ),
        ],
        discount: 0,
        tax: 0,
        total: 30000,
        advancePayment: 30000,
      ),
      order: {
        'orderKind': ServiceOrderKinds.oilChange,
        'oilType': 'توتال',
        'technicianName': 'علي',
        'cardWashJson':
            '{"lines":[{"name":"خارجي","priceFils":5000000}],'
            '"washer":"كرار","offerNote":"الغسلة الثالثة مجانية"}',
      },
    );

    test('سطرا الغسيل بقسمهما الخاص وبالبيانات نفسها', () {
      final f = {for (final x in card().fields) x.label: x};
      expect(f['الغسيل']!.value, 'خارجي — الغسلة الثالثة مجانية');
      expect(f['الغسيل']!.section, ReceiptSection.wash);
      expect(f['عامل الغسيل']!.value, 'كرار');
      expect(f['عامل الغسيل']!.section, ReceiptSection.wash);
      expect(f['الفني']!.section, ReceiptSection.technician);
      expect(
        ReceiptKind.oilChange.sections,
        contains(ReceiptSection.wash),
      );
    });

    test('إخفاء الفني لا يُخفي الغسلة، وإخفاء الغسيل يُقصّر الإيصال', () async {
      final d = ReceiptTemplate.defaultsFor(ReceiptKind.oilChange);
      Future<RenderedReceipt> r(ReceiptTemplate t) => ReceiptRenderer.render(
        card(),
        settings: _base,
        template: t,
      );
      final all = await r(d);
      final noTech = await r(d.copyWith(hidden: {ReceiptSection.technician}));
      final noWash = await r(d.copyWith(hidden: {ReceiptSection.wash}));
      final none = await r(
        d.copyWith(hidden: {ReceiptSection.technician, ReceiptSection.wash}),
      );
      expect(noTech.height, lessThan(all.height));
      expect(noWash.height, lessThan(all.height));
      expect(none.height, lessThan(noTech.height));
      for (final x in [all, noTech, noWash, none]) {
        x.dispose();
      }
    });
  });

  group('كشفا الحساب بقالبيهما', () {
    test('نوعان مستقلان في قسم الطباعة بعنوانيهما', () {
      expect(ReceiptKind.oilShop, contains(ReceiptKind.customerStatement));
      expect(ReceiptKind.oilShop, contains(ReceiptKind.supplierStatement));
      expect(ReceiptKind.customerStatement.title, 'كشف حساب عميل');
      expect(ReceiptKind.supplierStatement.title, 'كشف حساب مورد');
      expect(ReceiptKind.customerStatement.autoPrintByDefault, isFalse);
    });

    test('تذييل سند الصرف لا يظهر في كشف المورد', () async {
      final doc = ReceiptBuilders.sample(ReceiptKind.supplierStatement);
      final raw = ReceiptTemplates(const {}).withTemplate(
        ReceiptKind.expense,
        ReceiptTemplate.defaultsFor(
          ReceiptKind.expense,
        ).copyWith(footer: 'سطر طويل خاص بسند الصرف فقط\nوسطر ثانٍ'),
      );
      final templates = ReceiptTemplates(raw);
      expect(templates.of(doc.kind).footer, isEmpty);
      expect(templates.of(ReceiptKind.expense).footer, isNotEmpty);
    });

    test('كل الأنواع الجديدة ترسم نموذجها بلا خطأ', () async {
      for (final k in [
        ReceiptKind.customerStatement,
        ReceiptKind.supplierStatement,
      ]) {
        final r = await _render(k, ReceiptTemplate.defaultsFor(k));
        expect(r.width, ReceiptPaper.mm80.dots);
        r.dispose();
      }
    });
  });
}
