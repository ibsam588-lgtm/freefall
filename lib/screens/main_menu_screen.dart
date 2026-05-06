// screens/main_menu_screen.dart
//
// Home screen. Modern mobile-game aesthetic:
//   * Deep-space dark gradient background with multiple animated falling orbs.
//   * Glowing FREEFALL title with a pulsing neon PLAY button.
//   * Prominent high-score display.
//   * Glassmorphism bottom nav row (Store / Leaderboard / Settings).
//   * Sound toggle in the top bar.
//   * AdMob banner at the very bottom.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../app/app_dependencies.dart';
import '../app/app_routes.dart';
import '../components/banner_ad_widget.dart';
import '../models/powerup_upgrade.dart';
import '../repositories/coin_repository.dart';
import '../repositories/daily_login_repository.dart';
import '../repositories/stats_repository.dart';
import '../repositories/store_repository.dart';
import '../services/audio_service.dart';
import '../services/settings_service.dart';
import 'daily_login_screen.dart';

class MainMenuScreen extends StatefulWidget {
  final CoinRepository coinRepo;
  final DailyLoginRepository loginRepo;
  final StoreRepository storeRepo;
  final SettingsService settings;
  final StatsRepository statsRepo;
  final AudioService audioService;

  const MainMenuScreen({
    super.key,
    required this.coinRepo,
    required this.loginRepo,
    required this.storeRepo,
    required this.settings,
    required this.statsRepo,
    required this.audioService,
  });

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen>
    with TickerProviderStateMixin {
  late final AnimationController _bgController;
  late final AnimationController _pulseController;
  StreamSubscription<int>? _balanceSub;

  int _coinBalance = 0;
  int _streak = 0;
  int _highScore = 0;
  bool _soundEnabled = true;
  bool _loginOverlayShown = false;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _soundEnabled = widget.settings.soundEnabled;
    _bootstrap();
  }

  @override
  void dispose() {
    _bgController.dispose();
    _pulseController.dispose();
    _balanceSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final balance = await widget.coinRepo.getBalance();
    final streak = await widget.loginRepo.getConsecutiveDays();
    final highScore = await widget.statsRepo.getHighScore();
    if (!mounted) return;
    setState(() {
      _coinBalance = balance;
      _streak = streak;
      _highScore = highScore;
    });

    _balanceSub = widget.coinRepo.balanceStream.listen((next) {
      if (!mounted) return;
      setState(() => _coinBalance = next);
    });

    await _syncAchievementExternals();

    if (await widget.loginRepo.isClaimAvailable() &&
        !_loginOverlayShown &&
        mounted) {
      _loginOverlayShown = true;
      _showDailyLogin();
    }
  }

  Future<void> _syncAchievementExternals() async {
    if (!mounted) return;
    final mgr = AppDependencies.of(context).achievementManager;
    final lifetime = await widget.coinRepo.getLifetimeEarned();
    final streak = await widget.loginRepo.getConsecutiveDays();
    final owned = await widget.storeRepo.getOwnedItems();
    final ownsAnyPaidSkin = owned.any((id) => id.startsWith('skin:'));
    bool anyUpgradeMaxed = false;
    for (final upgrade in PowerupUpgrade.catalog) {
      final level = await widget.storeRepo.getUpgradeLevelById(upgrade.id);
      if (level >= upgrade.maxLevel) {
        anyUpgradeMaxed = true;
        break;
      }
    }
    await mgr.syncExternals(
      lifetimeCoins: lifetime,
      consecutiveDays: streak,
      firstSkinBought: ownsAnyPaidSkin,
      anyUpgradeMaxed: anyUpgradeMaxed,
    );
  }

  Future<void> _showDailyLogin() async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: const Color(0x88000000),
        pageBuilder: (_, __, ___) => DailyLoginScreen(
          loginRepo: widget.loginRepo,
          coinRepo: widget.coinRepo,
          onDismiss: () {
            Navigator.of(context).pop();
            _refreshStreak();
          },
        ),
      ),
    );
  }

  Future<void> _refreshStreak() async {
    final s = await widget.loginRepo.getConsecutiveDays();
    if (!mounted) return;
    setState(() => _streak = s);
  }

  Future<void> _go(String routeName) async {
    await Navigator.of(context).pushNamed(routeName);
    if (!mounted) return;
    await _syncAchievementExternals();
    final hs = await widget.statsRepo.getHighScore();
    if (mounted) setState(() => _highScore = hs);
  }

  Future<void> _toggleSound() async {
    final next = !_soundEnabled;
    await widget.settings.setSoundEnabled(next);
    widget.audioService.syncFromSettings(widget.settings);
    if (mounted) setState(() => _soundEnabled = next);
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Animated multi-particle background.
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, _) => CustomPaint(
              painter: _MenuBackgroundPainter(_bgController.value),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                const Spacer(),
                _buildTitle(),
                const SizedBox(height: 12),
                if (_highScore > 0) _buildHighScore(),
                const Spacer(),
                _buildPlayButton(),
                const Spacer(),
                _buildBottomNavRow(),
                const SizedBox(height: 8),
                _buildSecondaryButtons(),
                const SizedBox(height: 12),
                const BannerAdWidget(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- top bar ------------------------------------------------------------

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildStreakPill(),
          _buildSoundToggle(),
          _buildCoinPill(),
        ],
      ),
    );
  }

  Widget _buildStreakPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department,
            size: 16,
            color: Color(0xFFFF9100),
          ),
          const SizedBox(width: 4),
          Text(
            '$_streak',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoundToggle() {
    return GestureDetector(
      onTap: _toggleSound,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0x33FFFFFF),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(
          _soundEnabled ? Icons.volume_up : Icons.volume_off,
          color: _soundEnabled
              ? const Color(0xFF40E0D0)
              : Colors.white38,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildCoinPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x33000000),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFD700), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFFFD700),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$_coinBalance',
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  // ---- title + score ------------------------------------------------------

  Widget _buildTitle() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        'FREEFALL',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 62,
          fontWeight: FontWeight.w900,
          letterSpacing: 8,
          shadows: [
            Shadow(color: Color(0xFF40E0D0), blurRadius: 20),
            Shadow(color: Color(0xFF7B2FFF), blurRadius: 48),
            Shadow(color: Color(0xFF40E0D0), blurRadius: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildHighScore() {
    return Text(
      'BEST  $_highScore',
      style: const TextStyle(
        color: Color(0xFFFFD700),
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 4,
        shadows: [Shadow(color: Color(0xFFFF9100), blurRadius: 10)],
      ),
    );
  }

  // ---- pulsing PLAY button -------------------------------------------------

  Widget _buildPlayButton() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final t = _pulseController.value;
        final scale = 0.93 + 0.07 * t;
        final glowAlpha = 0.55 + 0.45 * t;
        return Transform.scale(
          scale: scale,
          child: GestureDetector(
            onTap: () => _go(AppRoutes.game),
            child: Container(
              width: 168,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                gradient: const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFF7B2FFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF40E0D0).withValues(alpha: glowAlpha),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: const Color(0xFF7B2FFF)
                        .withValues(alpha: glowAlpha * 0.7),
                    blurRadius: 36,
                    spreadRadius: 6,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text(
                'PLAY',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 7,
                  shadows: [Shadow(color: Colors.white, blurRadius: 10)],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---- glassmorphism bottom nav row ----------------------------------------

  Widget _buildBottomNavRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _glassNavButton(Icons.store, 'STORE', () => _go(AppRoutes.store)),
          _glassNavButton(
              Icons.leaderboard, 'RANKS', () => _go(AppRoutes.leaderboard)),
          _glassNavButton(
              Icons.settings, 'SETTINGS', () => _go(AppRoutes.settings)),
        ],
      ),
    );
  }

  Widget _glassNavButton(
      IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 90,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0x22FFFFFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: const Color(0x55FFFFFF), width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: const Color(0xFF40E0D0), size: 26),
                const SizedBox(height: 5),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- secondary text buttons ---------------------------------------------

  Widget _buildSecondaryButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _textNavButton('STATS', () => _go(AppRoutes.stats)),
        const SizedBox(width: 28),
        _textNavButton('ACHIEVEMENTS', () => _go(AppRoutes.achievements)),
      ],
    );
  }

  Widget _textNavButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

// ---- background painter ---------------------------------------------------

/// Dark deep-space gradient with 8 falling orbs at different speeds + phases,
/// plus twinkling stars. Cheap enough for 60 fps on low-end Android.
class _MenuBackgroundPainter extends CustomPainter {
  final double phase;

  _MenuBackgroundPainter(this.phase);

  // (xFraction, phaseOffset, radius, color, alpha)
  static const _particles = [
    (0.12, 0.00, 7.0, Color(0xFF40E0D0), 0.75),
    (0.35, 0.22, 5.0, Color(0xFFB388FF), 0.55),
    (0.62, 0.47, 9.0, Color(0xFF40E0D0), 0.80),
    (0.82, 0.08, 4.5, Color(0xFFFFD700), 0.45),
    (0.18, 0.73, 6.5, Color(0xFF7B2FFF), 0.60),
    (0.50, 0.34, 4.0, Color(0xFF40E0D0), 0.35),
    (0.88, 0.58, 7.5, Color(0xFFFF9100), 0.50),
    (0.40, 0.88, 5.5, Color(0xFFB388FF), 0.40),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Background gradient.
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF0A0A1A),
          Color(0xFF0D0525),
          Color(0xFF1A0A3A),
        ],
        stops: [0, 0.55, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    // Falling orbs.
    for (final (xFrac, offset, r, color, alpha)
        in _particles) {
      final particlePhase = (phase + offset) % 1.0;
      final orbY = size.height * (particlePhase * 1.1 - 0.05);
      if (orbY < -r * 3 || orbY > size.height + r * 3) continue;
      final sway =
          math.sin(phase * math.pi * 2 + offset * math.pi * 3) * 22;
      final orbX = size.width * xFrac + sway;

      final glow = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(
          center: Offset(orbX, orbY),
          radius: r * 3.5,
        ));
      canvas.drawCircle(Offset(orbX, orbY), r * 3.5, glow);
      canvas.drawCircle(
        Offset(orbX, orbY),
        r,
        Paint()..color = color.withValues(alpha: (alpha * 1.2).clamp(0, 1)),
      );
    }

    // Twinkling stars.
    for (int i = 0; i < 45; i++) {
      final px = (i * 71 + 19) % size.width.toInt();
      final py = (i * 139 + 31) % size.height.toInt();
      final r = 0.5 + (i % 4) * 0.3;
      final twinkle =
          0.15 + 0.45 * math.sin(phase * math.pi * 7 + i * 1.47).abs();
      canvas.drawCircle(
        Offset(px.toDouble(), py.toDouble()),
        r,
        Paint()..color = Colors.white.withValues(alpha: twinkle),
      );
    }
  }

  @override
  bool shouldRepaint(_MenuBackgroundPainter old) => old.phase != phase;
}
