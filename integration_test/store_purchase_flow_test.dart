// Phase-15 store purchase-flow integration test (outline).
//
// Like full_game_flow_test.dart, this is a TODO that runs on a
// device-attached CI runner. The unit-test suite already exercises
// the IAP credit logic deterministically (test/iap_service_test.dart)
// — what we lose without a real device is the platform purchase
// dialog + the storefront round-trip.
//
// Steps to script once a CI runner is wired up:
//
//   1. Launch the app and seed a known coin balance (test seeded
//      via SharedPreferences mock or a debug menu).
//   2. Navigate STORE → Skins.
//   3. Tap Buy on the Fire skin (cost is in-app currency, not
//      real money).
//   4. Verify the preview overlay appears.
//   5. Confirm purchase.
//   6. Assert Fire skin's card flips to "Equipped"-ready state
//      (Equip button visible, Buy button gone).
//   7. Tap Equip — verify the card now shows "Equipped" badge.
//   8. Switch to Coin Packs tab.
//   9. Tap a coin-pack Buy — confirm the iap_service surfaces a
//      pending purchase. (On a sandboxed test account, the
//      transaction completes; on prod we'd cancel.)
//  10. Tap RESTORE PURCHASES — confirm the listener processes any
//      historical receipts.

import 'package:flutter_test/flutter_test.dart';

void main() {
  // IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Store purchase flow', () {
    test('TODO: implement on a device-attached CI runner', () {
      expect(true, isTrue);
    }, skip: 'Requires a device or emulator');
  });
}
