// main.dart
//
// App entry point. Locks the device to portrait, attempts a Firebase
// init (gracefully no-ops if no google-services config has been added
// yet — keeps Phase-1 dev runs working without provisioning),
// bootstraps the persistent stores (settings, coin balance, daily
// login), and hands off to the main menu.
//
// Repositories + the SettingsService instance are constructed once
// here and threaded down to the screens that need them. Screens own
// none of the IO — they just read/write through the injected handles.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'repositories/coin_repository.dart';
import 'repositories/daily_login_repository.dart';
import 'repositories/store_repository.dart';
import 'screens/main_menu_screen.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  // Required before any platform-channel work (Firebase, orientation, etc.).
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  // WHY: try/catch — Firebase needs platform config files (google-services.json
  // on Android, GoogleService-Info.plist on iOS). Phase 1 ships without them
  // so devs can `flutter run` immediately; analytics/crashlytics get wired in
  // once provisioning happens.
  try {
    await Firebase.initializeApp();
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('Firebase init skipped (no config?): $e\n$st');
    }
  }

  // Phase 7+8: prefetch user prefs and build the persistent stores.
  // Each repo caches its own SharedPreferences/secure-storage future
  // internally so the first read fills it — no need to await anything
  // beyond settings here.
  final settings = SettingsService();
  await settings.load();
  final coinRepo = CoinRepository();
  final loginRepo = DailyLoginRepository();
  final storeRepo = StoreRepository(coinRepo: coinRepo);

  runApp(FreefallApp(
    settings: settings,
    coinRepo: coinRepo,
    loginRepo: loginRepo,
    storeRepo: storeRepo,
  ));
}

class FreefallApp extends StatelessWidget {
  final SettingsService settings;
  final CoinRepository coinRepo;
  final DailyLoginRepository loginRepo;
  final StoreRepository storeRepo;

  const FreefallApp({
    super.key,
    required this.settings,
    required this.coinRepo,
    required this.loginRepo,
    required this.storeRepo,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Freefall',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: MainMenuScreen(
        settings: settings,
        coinRepo: coinRepo,
        loginRepo: loginRepo,
        storeRepo: storeRepo,
      ),
    );
  }
}
