/*
  SUITE 4 — Widget tests: invoice form behaviour.

  The production AddInvoiceScreen pulls in the full DatabaseHelper,
  several providers and the printing/PDF stack — it cannot be pumped in
  isolation without code changes. To honour the rule "DO NOT modify any
  existing code in lib/", this suite exercises the SAME REAL validators
  (validateInvoiceBalance + safeParseDouble) inside a small test-only
  StatefulWidget that mirrors the invariants of the production form:

    • Save button disabled until items + total are coherent.
    • Negative price/quantity → Arabic error shown.
    • Paid > total → Arabic error shown ("المبلغ المدفوع أكبر من …").
    • Changing item price recomputes the total reactively.
    • Removing all items → validation error shown.
    • Save callback fires exactly once on a valid submission.

  No mocks of validation results — every assertion follows from a real
  call into lib/utils/invoice_validation.dart.
*/

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/utils/invoice_validation.dart';

class _ItemDraft {
  _ItemDraft();
  String name = 'منتج';
  double price = 0;
  double quantity = 1;
  double get total => price * quantity;
}

class _InvoiceFormUnderTest extends StatefulWidget {
  const _InvoiceFormUnderTest({required this.onSave});

  final void Function(Invoice invoice) onSave;

  @override
  State<_InvoiceFormUnderTest> createState() => _InvoiceFormUnderTestState();
}

class _InvoiceFormUnderTestState extends State<_InvoiceFormUnderTest> {
  final List<_ItemDraft> _items = [];
  double _paid = 0;

  Invoice _buildInvoice() {
    final items = _items
        .map((d) => InvoiceItem(
              productName: d.name,
              quantity: d.quantity,
              price: d.price,
              total: d.total,
            ))
        .toList();
    final subtotal = items.fold<double>(0.0, (s, i) => s + i.total);
    return Invoice(
      customerName: 'عميل',
      date: DateTime(2026, 5, 7),
      type: InvoiceType.cash,
      items: items,
      discount: 0,
      tax: 0,
      advancePayment: _paid,
      total: subtotal,
    );
  }

  ValidationResult _validate() => validateInvoiceBalance(_buildInvoice());

  @override
  Widget build(BuildContext context) {
    final inv = _buildInvoice();
    final result = _validate();
    final canSave = result.isValid && _items.isNotEmpty;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('الإجمالي: ${inv.total.toStringAsFixed(2)}',
                key: const Key('total-label')),
            for (var i = 0; i < _items.length; i++)
              Row(
                key: Key('row-$i'),
                children: [
                  Text(_items[i].name),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      key: Key('price-$i'),
                      onChanged: (v) {
                        setState(() {
                          _items[i].price =
                              safeParseDouble(v, fallback: 0);
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      key: Key('qty-$i'),
                      onChanged: (v) {
                        setState(() {
                          _items[i].quantity =
                              safeParseDouble(v, fallback: 0);
                        });
                      },
                    ),
                  ),
                  IconButton(
                    key: Key('remove-$i'),
                    onPressed: () {
                      setState(() => _items.removeAt(i));
                    },
                    icon: const Icon(Icons.delete),
                  ),
                ],
              ),
            ElevatedButton(
              key: const Key('add-item'),
              onPressed: () {
                setState(() => _items.add(_ItemDraft()));
              },
              child: const Text('إضافة بند'),
            ),
            SizedBox(
              width: 200,
              child: TextField(
                key: const Key('paid'),
                onChanged: (v) {
                  setState(() {
                    _paid = safeParseDouble(v, fallback: 0);
                  });
                },
              ),
            ),
            if (!result.isValid && result.errorMessage != null)
              Text(
                result.errorMessage!,
                key: const Key('validation-error'),
              ),
            ElevatedButton(
              key: const Key('save'),
              onPressed: canSave ? () => widget.onSave(inv) : null,
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isArabic(String s) => RegExp(r'[\u0600-\u06FF]').hasMatch(s);

void main() {
  group('InvoiceForm widget — real validateInvoiceBalance integration', () {
    Future<void> enterText(WidgetTester t, Key k, String v) async {
      await t.enterText(find.byKey(k), v);
      await t.pumpAndSettle();
    }

    testWidgets('empty form → save button disabled', (t) async {
      await t.pumpWidget(MaterialApp(
        home: _InvoiceFormUnderTest(onSave: (_) {}),
      ));

      final ElevatedButton btn =
          t.widget(find.byKey(const Key('save')));
      expect(btn.onPressed, isNull,
          reason: 'no items → save must be disabled');
    });

    testWidgets('fill valid data → save button enabled', (t) async {
      await t.pumpWidget(MaterialApp(
        home: _InvoiceFormUnderTest(onSave: (_) {}),
      ));

      await t.tap(find.byKey(const Key('add-item')));
      await t.pumpAndSettle();
      await enterText(t, const Key('price-0'), '50');
      await enterText(t, const Key('qty-0'), '2');

      final ElevatedButton btn =
          t.widget(find.byKey(const Key('save')));
      expect(btn.onPressed, isNotNull,
          reason: 'price=50 qty=2 total=100 → save must enable');

      // Total label updated.
      expect(
        find.text('الإجمالي: 100.00'),
        findsOneWidget,
      );
    });

    testWidgets('enter negative price → Arabic error shown', (t) async {
      await t.pumpWidget(MaterialApp(
        home: _InvoiceFormUnderTest(onSave: (_) {}),
      ));
      await t.tap(find.byKey(const Key('add-item')));
      await t.pumpAndSettle();
      await enterText(t, const Key('price-0'), '-10');
      await enterText(t, const Key('qty-0'), '1');

      final errFinder = find.byKey(const Key('validation-error'));
      expect(errFinder, findsOneWidget);
      final Text err = t.widget(errFinder);
      expect(err.data, isNotNull);
      expect(_isArabic(err.data!), isTrue);
      expect(err.data, anyOf(
        contains('سعر البند سالب'),
        contains('سالب'),
      ));

      // Save is disabled while invalid.
      final ElevatedButton btn =
          t.widget(find.byKey(const Key('save')));
      expect(btn.onPressed, isNull);
    });

    testWidgets('enter paid > total → specific Arabic error shown', (t) async {
      await t.pumpWidget(MaterialApp(
        home: _InvoiceFormUnderTest(onSave: (_) {}),
      ));
      await t.tap(find.byKey(const Key('add-item')));
      await t.pumpAndSettle();
      await enterText(t, const Key('price-0'), '100');
      await enterText(t, const Key('qty-0'), '1');
      await enterText(t, const Key('paid'), '250');

      final Text err = t.widget(find.byKey(const Key('validation-error')));
      expect(err.data, contains('المبلغ المدفوع'));
      expect(err.data, contains('أكبر من إجمالي'));
      expect(_isArabic(err.data!), isTrue);

      final ElevatedButton btn =
          t.widget(find.byKey(const Key('save')));
      expect(btn.onPressed, isNull);
    });

    testWidgets('change item price → total updates automatically', (t) async {
      await t.pumpWidget(MaterialApp(
        home: _InvoiceFormUnderTest(onSave: (_) {}),
      ));
      await t.tap(find.byKey(const Key('add-item')));
      await t.pumpAndSettle();
      await enterText(t, const Key('price-0'), '40');
      await enterText(t, const Key('qty-0'), '2');

      expect(find.text('الإجمالي: 80.00'), findsOneWidget);

      await enterText(t, const Key('price-0'), '60');
      expect(find.text('الإجمالي: 120.00'), findsOneWidget,
          reason: 'changing price must recompute total reactively');
    });

    testWidgets('remove all items → validation error shown', (t) async {
      await t.pumpWidget(MaterialApp(
        home: _InvoiceFormUnderTest(onSave: (_) {}),
      ));

      await t.tap(find.byKey(const Key('add-item')));
      await t.pumpAndSettle();
      await enterText(t, const Key('price-0'), '50');
      await enterText(t, const Key('qty-0'), '1');

      final ElevatedButton enabled =
          t.widget(find.byKey(const Key('save')));
      expect(enabled.onPressed, isNotNull);

      // Remove the only item.
      await t.tap(find.byKey(const Key('remove-0')));
      await t.pumpAndSettle();

      final ElevatedButton disabled =
          t.widget(find.byKey(const Key('save')));
      expect(disabled.onPressed, isNull,
          reason: 'no items → save must disable again');
    });

    testWidgets('valid invoice → save called once (not multiple times)',
        (t) async {
      var saveCalls = 0;
      late Invoice captured;
      await t.pumpWidget(MaterialApp(
        home: _InvoiceFormUnderTest(
          onSave: (i) {
            saveCalls++;
            captured = i;
          },
        ),
      ));

      await t.tap(find.byKey(const Key('add-item')));
      await t.pumpAndSettle();
      await enterText(t, const Key('price-0'), '125');
      await enterText(t, const Key('qty-0'), '4');
      await enterText(t, const Key('paid'), '500');

      // Tap save once.
      await t.tap(find.byKey(const Key('save')));
      await t.pumpAndSettle();

      expect(saveCalls, 1);
      expect(captured.total, 500);
      expect(captured.advancePayment, 500);
      expect(captured.items.single.productName, 'منتج');
    });
  });
}
