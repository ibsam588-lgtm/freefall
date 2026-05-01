// services/settings_service.dart
//
// User preference store. Wraps SharedPreferences with eager-loaded
// in-memory mirrors so widgets can read settings synchronously while
// writes are persisted asynchronously.
//
// Stored keys:
//   sound_enabled       bool   (default true)
//   music_enabled       bool   (default true)
//   haptic_enabled      bool   (default true)
//   control_type        string ('tilt' | 'touch', default 'tilt')
//   tilt_sensitivity    double (0.5..2.0, default 1.0)
//   no_ads_purchased    bool   (default false; flipped by IAP layer)
//
// SettingsService.load() must be awaited once at app start before
// any widget reads its values. Subsequent reads are synchronous.

import 'package:shared_preferences/shared_preferences.dart';

enum ControlType { tilt, touch }

class SettingsService {
  static const String soundKey = 'sound_enabled';
  static const String musicKey = 'music_enabled';
  static const String hapticKey = 'haptic_enabled';
  static const String controlKey = 'control_type';
  static const String sensitivityKey = 'tilt_sensitivity';
  static const String noAdsKey = 'no_ads_purchased';

  static const double minSensitivity = 0.5;
  static const double maxSensitivity = 2.0;
  static const double defaultSensitivity = 1.0;

  /// Underlying SharedPreferences. Late so [load] can populate it.
  late SharedPreferences _prefs;
  bool _loaded = false;

  // In-memory mirrors so widgets can read synchronously.
  bool _soundEnabled = true;
  bool _musicEnabled = true;
  bool _hapticEnabled = true;
  ControlType _controlType = ControlType.tilt;
  double _tiltSensitivity = defaultSensitivity;
  bool _noAdsPurchased = false;

  /// One-shot loader — pull every persisted value into memory. Idempotent.
  Future<void> load({SharedPreferences? overridePrefs}) async {
    if (_loaded) return;
    _prefs = overridePrefs ?? await SharedPreferences.getInstance();
    _soundEnabled = _prefs.getBool(soundKey) ?? true;
    _musicEnabled = _prefs.getBool(musicKey) ?? true;
    _hapticEnabled = _prefs.getBool(hapticKey) ?? true;
    final raw = _prefs.getString(controlKey);
    _controlType = raw == 'touch' ? ControlType.touch : ControlType.tilt;
    _tiltSensitivity =
        (_prefs.getDouble(sensitivityKey) ?? defaultSensitivity)
            .clamp(minSensitivity, maxSensitivity);
    _noAdsPurchased = _prefs.getBool(noAdsKey) ?? false;
    _loaded = true;
  }

  /// True once [load] has run successfully.
  bool get isLoaded => _loaded;

  // ---- read-only getters --------------------------------------------------

  bool get soundEnabled => _soundEnabled;
  bool get musicEnabled => _musicEnabled;
  bool get hapticEnabled => _hapticEnabled;
  ControlType get controlType => _controlType;
  double get tiltSensitivity => _tiltSensitivity;
  bool get noAdsPurchased => _noAdsPurchased;

  // ---- mutators (persist immediately) -------------------------------------

  Future<void> setSoundEnabled(bool value) async {
    _soundEnabled = value;
    await _prefs.setBool(soundKey, value);
  }

  Future<void> setMusicEnabled(bool value) async {
    _musicEnabled = value;
    await _prefs.setBool(musicKey, value);
  }

  Future<void> setHapticEnabled(bool value) async {
    _hapticEnabled = value;
    await _prefs.setBool(hapticKey, value);
  }

  Future<void> setControlType(ControlType value) async {
    _controlType = value;
    await _prefs.setString(controlKey, value == ControlType.touch ? 'touch' : 'tilt');
  }

  Future<void> setTiltSensitivity(double value) async {
    _tiltSensitivity = value.clamp(minSensitivity, maxSensitivity);
    await _prefs.setDouble(sensitivityKey, _tiltSensitivity);
  }

  Future<void> setNoAdsPurchased(bool value) async {
    _noAdsPurchased = value;
    await _prefs.setBool(noAdsKey, value);
  }
}
