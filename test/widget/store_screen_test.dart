// Phase-15 store-screen widget tests.
//
// We assert three contracts the spec called out:
//   * the default skin renders an "EQUIPPED" badge on a fresh
//     install (no purchase needed),
//   * a paid item with insufficient coins shows a disabled buy
//     button (the buy button uses the cost as its label, e.g. "300";
//     when the player can't afford it `onPressed` is null),
//   * tab switching navigates through all six tabs without an
//     exception. We widen the test viewport so every tab fits on
//     screen — at the default 800px the right-hand tabs land
//     off-screen and `tester.tap` warns about a missed hit.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/screens/store_screen.dart';

import 'test_harness.dart';

/// Run [body] with a 1200×900 logical viewport — enough headroom for
/// the full TabBar to render. Resets afterwards.
Future<void> _withWideViewport(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await body();
}

void main() {
  testWidgets('default skin shows the "EQUIPPED" badge', (tester) async {
    await _withWideViewport(tester, () async {
      final env = await buildTestEnv();
      await tester.pumpWidget(
        wrapWithDeps(
          StoreScreen(
            coinRepo: env.coinRepo,
            storeRepo: env.storeRepo,
            iapService: env.iapService,
          ),
          env,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // The default skin's card renders the EQUIPPED badge in place
      // of the buy/equip button.
      expect(find.text('EQUIPPED'), findsWidgets,
          reason: 'at least one default-tier item is equipped on a '
              'fresh install');
    });
  });

  testWidgets('a paid skin with 0 coins disables its buy button',
      (tester) async {
    await _withWideViewport(tester, () async {
      final env = await buildTestEnv(); // 0 coins
      await tester.pumpWidget(
        wrapWithDeps(
          StoreScreen(
            coinRepo: env.coinRepo,
            storeRepo: env.storeRepo,
            iapService: env.iapService,
          ),
          env,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Walk every FilledButton on screen — at least one (a paid
      // skin's "buy" button) should be disabled because the player
      // can't afford it.
      final filledButtons = find.byType(FilledButton);
      expect(filledButtons, findsWidgets);
      var disabledCount = 0;
      for (var i = 0; i < tester.widgetList(filledButtons).length; i++) {
        final btn = tester.widget<FilledButton>(filledButtons.at(i));
        if (btn.onPressed == null) disabledCount++;
      }
      expect(disabledCount, greaterThan(0),
          reason: 'with 0 coins, paid skins should render at least '
              'one disabled buy button');
    });
  });

  testWidgets('every tab can be tapped without throwing',
      (tester) async {
    await _withWideViewport(tester, () async {
      final env = await buildTestEnv(seedCoins: 100000);
      await tester.pumpWidget(
        wrapWithDeps(
          StoreScreen(
            coinRepo: env.coinRepo,
            storeRepo: env.storeRepo,
            iapService: env.iapService,
          ),
          env,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      const tabLabels = [
        'Skins',
        'Trails',
        'Shields',
        'Death FX',
        'Upgrades',
        'Coin Packs',
      ];
      for (final label in tabLabels) {
        final tab = find.text(label);
        expect(tab, findsWidgets, reason: '$label tab should be present');
        await tester.tap(tab.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }
      // No exceptions thrown ⇒ the test passes.
    });
  });
}
