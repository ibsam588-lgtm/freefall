// screens/run_summary_screen.dart
//
// End-of-run results card. Drives a count-up animation on the score,
// shows depth/coins/gems/near-misses/best-combo lines, fires a
// "NEW BEST!" sting when the run beat the all-time high, and offers
// three actions:
//   * Revive — let the player keep falling. Disabled if not available.
//   * Play Again — restart from depth zero.
//   * Double Coins — watch a rewarded ad (callback hook).
//
// The screen is a Flutter widget, not a Flame component — putting it
// on top of the GameWidget is the host's job (the existing GameScreen
// owns the Stack).

import 'package:flutter/material.dart';

import '../models/run_stats.dart';

class RunSummaryScreen extends StatefulWidget {
  /// Run stats to display. The widget animates the score from 0 up to
  /// [stats.score] when it mounts.
  final RunStats stats;

  /// Called when the player taps Revive. Optional — pass null and the
  /// button will render disabled.
  final VoidCallback? onRevive;

  /// Called when the player taps Play Again. Required.
  final VoidCallback onPlayAgain;

  /// Called when the player taps Double Coins (rewarded ad). Optional —
  /// disabled when null.
  final VoidCallback? onDoubleCoins;

  const RunSummaryScreen({
    super.key,
    required this.stats,
    required this.onPlayAgain,
    this.onRevive,
    this.onDoubleCoins,
  });

  @override
  State<RunSummaryScreen> createState() => _RunSummaryScreenState();
}

class _RunSummaryScreenState extends State<RunSummaryScreen>
    with TickerProviderStateMixin {
  late final AnimationController _scoreController;
  late final Animation<int> _scoreAnimation;
  late final AnimationController _newBestController;

  @override
  void initState() {
    super.initState();
    _scoreController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scoreAnimation = IntTween(begin: 0, end: widget.stats.score)
        .chain(CurveTween(curve: Curves.easeOutCubic))
        .animate(_scoreController);
    _scoreController.forward();

    _newBestController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    if (widget.stats.isNewHighScore) {
      _newBestController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _scoreController.dispose();
    _newBestController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    return Material(
      color: const Color(0xCC000010),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (stats.isNewHighScore) _buildNewBestBanner(),
                  const SizedBox(height: 8),
                  _buildScoreDisplay(),
                  const SizedBox(height: 24),
                  _buildStatRow('Depth',
                      '${stats.depthMeters.toStringAsFixed(0)}m'),
                  _buildStatRow('Coins', '${stats.coinsEarned}'),
                  _buildStatRow('Gems', '${stats.gemsCollected}'),
                  _buildStatRow('Near misses', '${stats.nearMisses}'),
                  _buildStatRow('Best combo', 'x${stats.bestCombo}'),
                  const SizedBox(height: 24),
                  _buildActions(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNewBestBanner() {
    return AnimatedBuilder(
      animation: _newBestController,
      builder: (context, _) {
        final t = _newBestController.value;
        return Transform.scale(
          scale: 1.0 + 0.05 * t,
          child: Text(
            'NEW BEST!',
            style: TextStyle(
              color: Color.lerp(
                const Color(0xFFFFD700),
                const Color(0xFFFFFFFF),
                t,
              ),
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              shadows: const [
                Shadow(color: Color(0xFFFF9100), blurRadius: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildScoreDisplay() {
    return AnimatedBuilder(
      animation: _scoreAnimation,
      builder: (context, _) {
        return Column(
          children: [
            const Text(
              'SCORE',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                letterSpacing: 4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_scoreAnimation.value}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 56,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: widget.onRevive,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF40E0D0),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text(
              'REVIVE',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: widget.onPlayAgain,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF9100),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text(
              'PLAY AGAIN',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: widget.onDoubleCoins,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFFD700),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text(
              '2X COINS (Watch Ad)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
