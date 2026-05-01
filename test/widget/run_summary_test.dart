// Phase-15 run-summary widget tests.
//
// RunSummaryScreen owns:
//   * a count-up animation that lands on the final score,
//   * a "NEW BEST!" banner gated on RunStats.isNewHighScore,
//   * a SHARE button gated on whether a ShareService was wired,
//   * a REVIVE button that disables itself after a successful watch.
//
// We pump the screen with synthetic [RunStats] and verify the
// surfaces. The ad service is left null so the revive/double-coins
// CTAs render disabled — keeps the test deterministic.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:freefall/models/run_stats.dart';
import 'package:freefall/screens/run_summary_screen.dart';

const RunStats _stats = RunStats(
  score: 12345,
  depthMeters: 1234,
  coinsEarned: 100,
  gemsCollected: 5,
  nearMisses: 12,
  bestCombo: 7,
  isNewHighScore: true,
);

void main() {
  testWidgets('score count-up animation eventually shows the final '
      'score', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RunSummaryScreen(
          stats: _stats,
          onPlayAgain: () {},
        ),
      ),
    );
    // Initial frame: animation hasn't run yet, score should still be
    // climbing — but by the end of the 1.2s controller window it
    // should land at exactly the final score.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('${_stats.score}'), findsOneWidget);
  });

  testWidgets('"NEW BEST!" banner is visible when isNewHighScore is '
      'true', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RunSummaryScreen(
          stats: _stats,
          onPlayAgain: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('NEW BEST!'), findsOneWidget);
  });

  testWidgets('"NEW BEST!" banner is hidden when isNewHighScore is '
      'false', (tester) async {
    final notHigh = _stats.copyWith(isNewHighScore: false);
    await tester.pumpWidget(
      MaterialApp(
        home: RunSummaryScreen(
          stats: notHigh,
          onPlayAgain: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('NEW BEST!'), findsNothing);
  });

  testWidgets('PLAY AGAIN button fires onPlayAgain', (tester) async {
    var played = false;
    await tester.pumpWidget(
      MaterialApp(
        home: RunSummaryScreen(
          stats: _stats,
          onPlayAgain: () => played = true,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('PLAY AGAIN'));
    expect(played, isTrue);
  });

  testWidgets('REVIVE button is hidden when adService is null',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RunSummaryScreen(
          stats: _stats,
          onPlayAgain: () {},
          // adService null ⇒ revive CTA is hidden entirely (no
          // confused tap on a non-functional button).
          onRevive: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('REVIVE'), findsNothing);
  });

  testWidgets('depth + score lines render the canonical labels',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RunSummaryScreen(
          stats: _stats,
          onPlayAgain: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Depth'), findsOneWidget);
    expect(find.text('1234m'), findsOneWidget);
    expect(find.text('Coins'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('Best combo'), findsOneWidget);
    expect(find.text('x7'), findsOneWidget);
  });
}
