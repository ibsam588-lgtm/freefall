// Phase-15 full-game-flow integration test (outline).
//
// Integration tests run on a real device or emulator via:
//   flutter test integration_test/full_game_flow_test.dart -d <device>
//
// They exercise the same boot path the real app uses (Firebase init,
// real audio plugin, real ad SDK in test mode, real shared-prefs
// storage). Unlike the unit tests they cannot run in `flutter test`
// — that framework lacks the host activity these plugins need.
//
// This file is a TODO. The harness boilerplate is in place; flesh
// out the steps once the QA loop has a hold-of-iOS-and-Android lab.
// Until then, the spec for what we want to cover is documented
// inline so a contributor can pick it up later.

import 'package:flutter_test/flutter_test.dart';

void main() {
  // IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Full game flow', () {
    /// Steps to script:
    ///   1. Launch the app to the main menu.
    ///   2. Verify the coin pill renders 0 on a fresh install.
    ///   3. Tap PLAY to enter the game screen.
    ///   4. Drive the player by simulating accelerometer / touch input
    ///      so the player descends and collects ≥3 coins.
    ///   5. Trigger a fatal collision (move into a stalactite or
    ///      lightning bolt) so the death sequence fires.
    ///   6. Verify the run-summary screen shows the count-up score.
    ///   7. Tap REVIVE — confirm a (mocked) rewarded ad plays and the
    ///      player respawns.
    ///   8. Trigger another death.
    ///   9. Tap PLAY AGAIN — verify the run restarts at 0m.
    ///  10. Pause, navigate to STORE, purchase a Fire skin (after
    ///      seeding enough coins).
    ///  11. Equip the new skin, return to game, verify Player.skin
    ///      reads the equipped value.
    ///
    /// Each step is its own `testWidgets` body in the final test —
    /// keeping them separate lets CI surface which step regressed.
    test('TODO: implement on a device-attached CI runner', () {
      // No-op on the host test runner (which won't include this
      // file). Documented behavior only.
      expect(true, isTrue);
    }, skip: 'Requires a device or emulator');
  });
}
