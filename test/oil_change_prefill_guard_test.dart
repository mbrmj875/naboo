import 'package:flutter_test/flutter_test.dart';

import 'package:naboo/verticals/oil_change/screens/oil_change_form_screen.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_prefill_guard.dart';

void main() {
  group('oilChangeFormStableKey', () {
    test('uses edit id for edit mode', () {
      expect(
        oilChangeFormStableKey(editOrderId: 42, prefillFromOrder: null),
        42,
      );
    });

    test('uses negative source id for prefill from log row', () {
      expect(
        oilChangeFormStableKey(
          prefillFromOrder: {'id': 99, 'oilType': 'faza'},
        ),
        -99,
      );
    });

    test('null for blank new card', () {
      expect(oilChangeFormStableKey(), isNull);
    });
  });

  group('shouldBlockFluidReconcileAfterPrefill', () {
    test('blocks after first catalog sync for log prefill', () {
      expect(
        shouldBlockFluidReconcileAfterPrefill(
          isPrefillFromLog: true,
          prefillCatalogSyncedOnce: true,
        ),
        isTrue,
      );
    });

    test('allows first sync before seal', () {
      expect(
        shouldBlockFluidReconcileAfterPrefill(
          isPrefillFromLog: true,
          prefillCatalogSyncedOnce: false,
        ),
        isFalse,
      );
    });

    test('ignores blank new card', () {
      expect(
        shouldBlockFluidReconcileAfterPrefill(
          isPrefillFromLog: false,
          prefillCatalogSyncedOnce: true,
        ),
        isFalse,
      );
    });
  });

  group('shouldBlockAutoVisitLookup', () {
    test('blocks auto lookup for frozen log prefill', () {
      expect(
        shouldBlockAutoVisitLookup(
          isPrefillFromLog: true,
          allowAutoVisitLookup: false,
        ),
        isTrue,
      );
    });

    test('manual sync bypasses block', () {
      expect(
        shouldBlockAutoVisitLookup(
          isPrefillFromLog: true,
          allowAutoVisitLookup: false,
          force: true,
        ),
        isFalse,
      );
    });

    test('allows lookup after plate change unlock', () {
      expect(
        shouldBlockAutoVisitLookup(
          isPrefillFromLog: true,
          allowAutoVisitLookup: true,
        ),
        isFalse,
      );
    });
  });
}
