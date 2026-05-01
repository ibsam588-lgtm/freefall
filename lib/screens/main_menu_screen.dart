// screens/main_menu_screen.dart
//
// First screen the player sees after the splash. Animates a falling
// orb behind a "FREEFALL" wordmark + a stack of CTAs (Play, Store,
// Stats, Settings, Leaderboard). The animated background is a tiny
// custom painter — full ZoneBackground requires a CameraSystem and
// is overkill for an idle title screen.
//
// Side effects on first frame:
//   * If the daily-login claim is available, push the login overlay.
//   * Subscribe to coinRepository.balanceStream so the top-right pill
//     updates the moment the player claims a bonus.
//
// Routing:
//   * Play → GameScreen (existing).
//   * Settings → SettingsScreen.
//   * Store / Stats / Leaderboard are stubbed for later phases — they
//     show a brief "Coming soon" snackbar so the buttons aren't dead
//     on tap.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../repositories/coin_repository.dart';
import '../repositories/daily_login_repository.dart';
import '../repositories/store_repository.dart';
import '../services/settings_service.dart';
import 'daily_login_screen.dart';
import 'game_screen.dart';
import 'settings_screen.dart';
import 'store_screen.dart';

class MainMenuScreen extends StatefulWidget {
  final CoinRepository coinRepo;
  final DailyLoginRepository loginRepo;
  final StoreRepository storeRepo;
  final SettingsService settings;

  const MainMenuScreen({
    super.key,
    required this.coinRepo,
    required this.loginRepo,
    required this.storeRepo,
    required this.settings,
  });

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bgController;
  StreamSubscription<int>? _balanceSub;

  int _coinBalance = 0;
  int _streak = 0;
  bool _loginOverlayShown = false;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final balance = await widget.coinRepo.getBalance();
    final streak = await widget.loginRepo.getConsecutiveDays();
    if (!mounted) return;
    setState(() {
      _coinBalance = balance;
      _streak = streak;
    });

    _balanceSub = widget.coinRepo.balanceStream.listen((next) {
      if (!mounted) return;
      setState(() => _coinBalance = next);
    });

    if (await widget.loginRepo.isClaimAvailable() &&
        !_loginOverlayShown &&
        mounted) {
      _loginOverlayShown = true;
      _showDailyLogin();
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    _balanceSub?.cancel();
    super.dispose();
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

  void _comingSoon(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label coming soon'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050510),
      body: Stack(
        fit: StackFit.expand,
        children: [
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
                const SizedBox(height: 32),
                _buildButtons(),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildStreakPill(),
          _buildCoinPill(),
        ],
      ),
    );
  }

  Widget _buildStreakPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x55FFFFFF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_month, size: 16, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            '$_streak day${_streak == 1 ? '' : 's'}',
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

  Widget _buildCoinPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x55000000),
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

  Widget _buildTitle() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        'FREEFALL',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 56,
          fontWeight: FontWeight.w900,
          letterSpacing: 6,
          shadows: [
            Shadow(color: Color(0xFF40E0D0), blurRadius: 20),
            Shadow(color: Color(0xFFFFD700), blurRadius: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildButtons() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _menuButton(
            'PLAY',
            const Color(0xFF40E0D0),
            () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const GameScreen(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _menuButton(
            'STORE',
            const Color(0xFFFF9100),
            () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => StoreScreen(
                  coinRepo: widget.coinRepo,
                  storeRepo: widget.storeRepo,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _menuButton('STATS', const Color(0xFFFFD700),
              () => _comingSoon('Stats')),
          const SizedBox(height: 10),
          _menuButton(
            'SETTINGS',
            const Color(0xFF80DEEA),
            () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(settings: widget.settings),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _menuButton('LEADERBOARD', const Color(0xFFB388FF),
              () => _comingSoon('Leaderboard')),
        ],
      ),
    );
  }

  Widget _menuButton(String label, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: const Color(0xFF101018),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
      ),
    );
  }
}

/// Stylized stratosphere → core gradient with a slowly-falling orb.
/// Cheap enough to repaint every frame at 60fps even on low-end Android.
class _MenuBackgroundPainter extends CustomPainter {
  /// 0..1 phase. The orb's vertical position lerps over the cycle.
  final double phase;

  _MenuBackgroundPainter(this.phase);

  @override
  void paint(Canvas canvas, Size size) {
    // Background gradient — top sky to deep core.
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF1A1A3E),
          Color(0xFF0A0A14),
          Color(0xFF200008),
        ],
        stops: [0, 0.6, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    // Falling orb — drifts vertically with a slight horizontal sway so
    // it doesn't read as static.
    final orbY = size.height * (phase * 1.2 - 0.1);
    final orbX = size.width * (0.3 + 0.4 * math.sin(phase * math.pi * 2));
    if (orbY > -40 && orbY < size.height + 40) {
      final glow = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF40E0D0).withValues(alpha: 0.6),
            const Color(0xFF40E0D0).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(
          center: Offset(orbX, orbY),
          radius: 80,
        ));
      canvas.drawCircle(Offset(orbX, orbY), 80, glow);
      canvas.drawCircle(
        Offset(orbX, orbY),
        14,
        Paint()..color = const Color(0xFFE0FFFF),
      );
    }

    // A handful of stationary "stars" — randomised but seeded by their
    // index so they don't shimmer between frames.
    for (int i = 0; i < 30; i++) {
      final px = (i * 73) % size.width.toInt();
      final py = (i * 137) % size.height.toInt();
      final r = 0.6 + (i % 3) * 0.4;
      final alpha = 0.3 + ((i * 19) % 7) * 0.08;
      canvas.drawCircle(
        Offset(px.toDouble(), py.toDouble()),
        r,
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_MenuBackgroundPainter old) => old.phase != phase;
}
