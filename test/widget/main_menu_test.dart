// Phase-15 main-menu widget tests.
//
// MainMenuScreen pulls coin balance + streak from the injected
// repositories on first frame. We seed both, pump the screen, and
// verify the visible UI surfaces the right strings + that the menu
// buttons push the named routes.
//
// We bump the viewport to 1200×900 because the default 800×600 test
// surface clips the bottom CTAs (LEADERBOARD / ACHIEVEMENTS) — the
// menu is laid out for portrait-phone proportions, so the test
// `tester.tap` would otherwise land on an off-screen widget.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/app/app_routes.dart';
import 'package:freefall/screens/main_menu_screen.dart';

import 'test_harness.dart';

Future<void> _withWideViewport(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await body();
}

void main() {
  testWidgets('coin balance is shown in the top-right pill',
      (tester) async {
    await _withWideViewport(tester, () async {
      final env = await buildTestEnv(seedCoins: 1234);
      await tester.pumpWidget(
        wrapWithDeps(
          MainMenuScreen(
            coinRepo: env.coinRepo,
            loginRepo: env.loginRepo,
            storeRepo: env.storeRepo,
            settings: env.settings,
          ),
          env,
        ),
      );
      // initState fires async loaders; pump until they settle.
      await tester.pump();
      await tester.pump();
      expect(find.text('1234'), findsOneWidget);
      expect(find.text('FREEFALL'), findsOneWidget);
    });
  });

  testWidgets('PLAY button pushes the /game route', (tester) async {
    await _withWideViewport(tester, () async {
      final env = await buildTestEnv();
      final recorder = RouteRecorder();
      await tester.pumpWidget(
        wrapWithDeps(
          MainMenuScreen(
            coinRepo: env.coinRepo,
            loginRepo: env.loginRepo,
            storeRepo: env.storeRepo,
            settings: env.settings,
          ),
          env,
          observer: recorder,
          additionalRoutes: {
            AppRoutes.game: (_) =>
                const Scaffold(body: Text('GAME ROUTE')),
          },
        ),
      );
      await tester.pump();
      await tester.tap(find.text('PLAY'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('GAME ROUTE'), findsOneWidget);
      expect(recorder.pushedRoutes, contains(AppRoutes.game));
    });
  });

  testWidgets('STORE button pushes the /store route', (tester) async {
    await _withWideViewport(tester, () async {
      final env = await buildTestEnv();
      final recorder = RouteRecorder();
      await tester.pumpWidget(
        wrapWithDeps(
          MainMenuScreen(
            coinRepo: env.coinRepo,
            loginRepo: env.loginRepo,
            storeRepo: env.storeRepo,
            settings: env.settings,
          ),
          env,
          observer: recorder,
          additionalRoutes: {
            AppRoutes.store: (_) =>
                const Scaffold(body: Text('STORE ROUTE')),
          },
        ),
      );
      await tester.pump();
      await tester.tap(find.text('STORE'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('STORE ROUTE'), findsOneWidget);
      expect(recorder.pushedRoutes, contains(AppRoutes.store));
    });
  });

  testWidgets('LEADERBOARD button pushes the /leaderboard route',
      (tester) async {
    await _withWideViewport(tester, () async {
      final env = await buildTestEnv();
      final recorder = RouteRecorder();
      await tester.pumpWidget(
        wrapWithDeps(
          MainMenuScreen(
            coinRepo: env.coinRepo,
            loginRepo: env.loginRepo,
            storeRepo: env.storeRepo,
            settings: env.settings,
          ),
          env,
          observer: recorder,
          additionalRoutes: {
            AppRoutes.leaderboard: (_) =>
                const Scaffold(body: Text('LEADERBOARD ROUTE')),
          },
        ),
      );
      await tester.pump();
      await tester.tap(find.text('LEADERBOARD'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('LEADERBOARD ROUTE'), findsOneWidget);
    });
  });
}
