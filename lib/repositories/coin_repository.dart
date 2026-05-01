// repositories/coin_repository.dart
//
// Persisted coin balance + lifetime-earned counter, backed by
// flutter_secure_storage. Secure storage (vs SharedPreferences) so a
// rooted-device user can't trivially edit their balance and unlock
// premium skins for free.
//
// Two scalars stored:
//   - "coin_balance"        spendable balance (decreases when buying skins)
//   - "lifetime_coins_earned" monotonic total ever earned (analytics)
//
// All reads/writes are async because secure_storage is platform IO.
// The repository is injection-friendly: callers pass a [storage]
// instance, so unit tests pass a fake.
//
// Phase 7: balance changes broadcast via [balanceStream] so the HUD
// and main-menu coin counter can refresh live whenever a daily-login
// claim, ad reward, or store purchase moves the number.

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal interface CoinRepository requires from its storage backend.
/// flutter_secure_storage's [FlutterSecureStorage] satisfies it
/// natively; tests provide an in-memory implementation.
abstract class CoinStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Adapter wrapping [FlutterSecureStorage] in the [CoinStorage] shape.
class SecureCoinStorage implements CoinStorage {
  final FlutterSecureStorage _inner;
  const SecureCoinStorage(this._inner);

  @override
  Future<String?> read(String key) => _inner.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _inner.write(key: key, value: value);
}

/// Raised when the caller asks to spend more coins than the balance
/// holds. Caller UI handles this — repository is the source of truth.
class InsufficientCoinsException implements Exception {
  final int requested;
  final int available;
  const InsufficientCoinsException(this.requested, this.available);

  @override
  String toString() =>
      'InsufficientCoinsException(requested=$requested, available=$available)';
}

class CoinRepository {
  /// Storage keys. Public-static so tests can clear them between runs.
  static const String balanceKey = 'coin_balance';
  static const String lifetimeKey = 'lifetime_coins_earned';

  final CoinStorage storage;

  /// Broadcast stream of post-write balances. UI bindings subscribe so
  /// the HUD coin counter and main-menu pill update without polling.
  /// We use a broadcast controller because multiple widgets may listen.
  final StreamController<int> _balanceController =
      StreamController<int>.broadcast();

  CoinRepository({CoinStorage? storage})
      : storage = storage ?? const SecureCoinStorage(FlutterSecureStorage());

  /// Live balance changes. The stream emits the *new* balance after
  /// each successful [addCoins] / [spendCoins]. Does NOT replay the
  /// current value on subscribe — caller should pair with [getBalance].
  Stream<int> get balanceStream => _balanceController.stream;

  /// Current spendable balance. Returns 0 if storage is empty (fresh
  /// install) or holds a malformed value.
  Future<int> getBalance() async => _readInt(balanceKey);

  /// Total coins ever earned. Never decreases.
  Future<int> getLifetimeEarned() async => _readInt(lifetimeKey);

  /// Add [amount] to balance and lifetime earned. Negative amounts are
  /// silently ignored — use [spendCoins] for deductions.
  Future<int> addCoins(int amount) async {
    if (amount <= 0) return getBalance();
    final balance = await getBalance();
    final lifetime = await getLifetimeEarned();
    final next = balance + amount;
    await storage.write(balanceKey, '$next');
    await storage.write(lifetimeKey, '${lifetime + amount}');
    _emit(next);
    return next;
  }

  /// Deduct [amount] from balance. Throws [InsufficientCoinsException]
  /// if the balance can't cover it. Returns the new balance on success.
  Future<int> spendCoins(int amount) async {
    if (amount <= 0) return getBalance();
    final balance = await getBalance();
    if (amount > balance) {
      throw InsufficientCoinsException(amount, balance);
    }
    final next = balance - amount;
    await storage.write(balanceKey, '$next');
    _emit(next);
    return next;
  }

  /// Tear-down. Closes the broadcast stream so subscribers don't leak.
  /// Tests + DI containers should call this when the repo is no longer
  /// reachable.
  Future<void> dispose() => _balanceController.close();

  Future<int> _readInt(String key) async {
    final raw = await storage.read(key);
    if (raw == null) return 0;
    return int.tryParse(raw) ?? 0;
  }

  void _emit(int balance) {
    if (!_balanceController.isClosed) _balanceController.add(balance);
  }
}

/// In-memory CoinStorage useful for tests + headless environments.
class InMemoryCoinStorage implements CoinStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  /// Test helper — preload a value.
  void seed(String key, String value) {
    _data[key] = value;
  }

  /// Test helper — read raw values without going through async.
  String? peek(String key) => _data[key];
}
