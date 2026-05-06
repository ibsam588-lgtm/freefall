// screens/run_summary_screen.dart
//
// End-of-run results card. Drives a count-up animation on the score,
// shows depth/coins/gems/near-misses/best-combo lines, fires a
// "NEW BEST!" sting when the run beat the all-time high, and offers
// three actions:
//   * Revive — watch a rewarded ad to keep falling.
//   * Double Coins — watch a rewarded ad to 2× the run's coins.
//   * Play Again — restart the run from depth zero.
//
// The screen is a Flutter widget, not a Flame component — putting it
// on top of the GameWidget is the host's job (the GameScreen owns
// the Stack).

import 'package:flutter/material.dart';

import '../components/banner_ad_widget.dart';
import '../models/player_skin.dart';
import '../models/run_stats.dart';
import '../repositories/coin_repository.dart';
import '../services/ad_service.dart';
import '../services/share_service.dart';

class RunSummaryScreen extends StatefulWidget {
  /// Run stats to display. The widget animates the score from 0 up to
  /// [stats.score] when it mounts.
  final RunStats stats;

  /// Called when the player taps Play Again. Required.
  final VoidCallback onPlayAgain;

  /// Called after a successful Revive flow (rewarded ad watched +
  /// player wants to continue). Optional — if null the Revive button
  /// is hidden entirely (e.g. for a hard game-over).
  final VoidCallback? onRevive;

  /// Optional ad service. When non-null, Revive + Double Coins watch
  /// a rewarded ad before crediting their reward; when null, both
  /// buttons render disabled. Tests pass a fake here.
  final AdService? adService;

  /// Required when [adService] is non-null and the player can earn
  /// the 2× coins reward. The screen credits the bonus coins through
  /// this repo on a successful watch.
  final CoinRepository? coinRepo;

  /// Phase 13: optional share pipeline. When wired, the SHARE button
  /// renders + builds a branded image of the run and hands it to the
  /// platform share sheet.
  final ShareService? shareService;

  /// Player's currently equipped skin id — drives the orb color on
  /// the share card. Defaults to the default skin so the screen
  /// renders without the cosmetics state being threaded through.
  final SkinId equippedSkin;

  const RunSummaryScreen({
    super.key,
    required this.stats,
    required this.onPlayAgain,
    this.onRevive,
    this.adService,
    this.coinRepo,
    this.shareService,
    this.equippedSkin = SkinId.defaultOrb,
  });

  @override
  State<RunSummaryScreen> createState() => _RunSummaryScreenState();
}

class _RunSummaryScreenState extends State<RunSummaryScreen>
    with TickerProviderStateMixin {
  late final AnimationController _scoreController;
  late final Animation<int> _scoreAnimation;
  late final AnimationController _newBestController;

  /// Whether the Double Coins reward has already been claimed this
  /// summary view. Locks the button after a successful watch.
  bool _doubledCoins = false;

  /// Whether an ad watch is currently in flight. Disables both ad
  /// buttons so a flaky double-tap doesn't queue two reward grants.
  bool _adInFlight = false;

  /// True while the share image is rendering / the share sheet is
  /// open. Disables the SHARE button so a flaky double-tap doesn't
  /// queue two share intents.
  bool _shareInFlight = false;

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

  // ---- ad-driven actions --------------------------------------------------

  Future<void> _onReviveTapped() async {
    final ads = widget.adService;
    final onRevive = widget.onRevive;
    if (ads == null || onRevive == null || _adInFlight) return;
    setState(() => _adInFlight = true);
    await ads.showRewardedAd(
      onRewarded: (_) {
        if (!mounted) return;
        setState(() => _adInFlight = false);
        onRevive();
      },
      onFailed: () {
        if (!mounted) return;
        setState(() => _adInFlight = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Revive ad unavailable'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  Future<void> _onShareTapped() async {
    final share = widget.shareService;
    if (share == null || _shareInFlight) return;
    setState(() => _shareInFlight = true);
    final outcome =
        await share.shareScore(widget.stats, widget.equippedSkin);
    if (!mounted) return;
    setState(() => _shareInFlight = false);
    if (outcome == ShareOutcome.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sharing unavailable'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _onDoubleCoinsTapped() async {
    final ads = widget.adService;
    final coinRepo = widget.coinRepo;
    if (ads == null || coinRepo == null || _adInFlight) return;
    setState(() => _adInFlight = true);
    await ads.showRewardedAd(
      onRewarded: (_) async {
        // Award an extra `stats.coinsEarned` — i.e. doubling. The ad
        // service's flat per-watch reward is intentionally ignored
        // here; this CTA's contract is "match what you just earned".
        final bonus = widget.stats.coinsEarned;
        if (bonus > 0) {
          await coinRepo.addCoins(bonus);
        }
        if (!mounted) return;
        setState(() {
          _adInFlight = false;
          _doubledCoins = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('+$bonus bonus coins!'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      onFailed: () {
        if (!mounted) return;
        setState(() => _adInFlight = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Coin ad unavailable'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    return Material(
      color: const Color(0xCC000010),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (stats.isNewHighScore) _buildNewBestBanner(),
                        const SizedBox(height: 8),
                        _buildScoreDisplay(),
                        const SizedBox(height: 24),
                        _buildStatRow(
                            'Depth', '${stats.depthMeters.toStringAsFixed(0)}m'),
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
            const BannerAdWidget(),
          ],
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
    final reviveAvailable =
        widget.onRevive != null && widget.adService != null;
    final doubleCoinsAvailable = widget.adService != null &&
        widget.coinRepo != null &&
        widget.stats.coinsEarned > 0 &&
        !_doubledCoins;

    return Column(
      children: [
        if (reviveAvailable) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _adInFlight ? null : _onReviveTapped,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF40E0D0),
                foregroundColor: const Color(0xFF101018),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                _adInFlight ? 'PLEASE WAIT…' : 'REVIVE (Watch Ad)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _adInFlight ? null : widget.onPlayAgain,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF9100),
              foregroundColor: const Color(0xFF101018),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text(
              'PLAY AGAIN',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: doubleCoinsAvailable && !_adInFlight
                ? _onDoubleCoinsTapped
                : null,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFFD700),
              disabledForegroundColor: const Color(0x55FFD700),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              _doubledCoins
                  ? 'COINS DOUBLED ✓'
                  : '2X COINS (Watch Ad)',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
        if (widget.shareService != null) ...[
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _shareInFlight ? null : _onShareTapped,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF80DEEA),
                side: const BorderSide(color: Color(0xFF80DEEA), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.share, size: 18),
              label: Text(
                _shareInFlight ? 'PREPARING…' : 'SHARE SCORE',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
