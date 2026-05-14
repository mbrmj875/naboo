import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:naboo/widgets/variants/variant_drafts.dart';
import 'package:naboo/widgets/variants/variants_editor.dart';

class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final drafts = <VariantColorDraft>[
    VariantColorDraft(
      name: 'أسود',
      sizes: [VariantSizeDraft(size: 'M', qty: 3)],
    ),
  ];

  @override
  void dispose() {
    for (final c in drafts) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: VariantsEditor(
                colorDrafts: drafts,
                onChanged: () => setState(() {}),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('VariantsEditor adds color and size without crashing', (tester) async {
    await tester.pumpWidget(const _Host());

    expect(find.text('أسود'), findsOneWidget);
    // حقل المقاس + شريحة مقاس سريع قد يعرضان نفس النص.
    expect(find.text('M'), findsWidgets);

    await tester.tap(find.text('إضافة لون جديد'));
    await tester.pumpAndSettle();

    // Now we have two "اسم اللون" fields (at least).
    expect(find.text('اسم اللون'), findsNWidgets(2));

    // Add a size row to the first color (سطر فارغ يُكمّل من قائمة المقاسات).
    await tester.tap(find.text('مقاس مخصص').first);
    await tester.pumpAndSettle();

    // "المقاس" fields should be at least 2 now.
    expect(find.text('المقاس'), findsAtLeastNWidgets(2));
  });

  testWidgets('Color picker opens and closes without layout crash', (tester) async {
    final drafts = <VariantColorDraft>[
      VariantColorDraft(
        name: 'أبيض',
        sizes: [VariantSizeDraft(size: 'S', qty: 1)],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => SizedBox(
                        height: 600,
                        child: StatefulBuilder(
                          builder: (ctx, ss) => ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              VariantsEditor(
                                colorDrafts: drafts,
                                onChanged: () => ss(() {}),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('فتح'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();

    // Tap the color swatch.
    await tester.tap(find.byKey(const ValueKey('variant_color_swatch_0')));
    await tester.pumpAndSettle();

    // Color picker dialog appears.
    expect(find.text('تأكيد اللون'), findsOneWidget);

    await tester.tap(find.text('تأكيد اللون'));
    await tester.pumpAndSettle();

    for (final c in drafts) {
      c.dispose();
    }
  });
}

