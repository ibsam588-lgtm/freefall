// screens/stats_screen.dart
//
// Lifetime stats panel. Reads from StatsRepository for the persisted
// counters and from StoreRepository for "first skin bought" achievement
// progress. Renders five featured achievement progress bars per the
// Phase-9 spec; the full list lands in Phase 10.

import 'package:flutter/material.dart';

import '../app/app_routes.dart';
import '../repositories/coin_repository.dart';
import '../repositories/stats_repository.dart';
import '../repositories/store_repository.dart';

class StatsScreen extends StatefulWidget {
  final StatsRepository statsRepo;
  final StoreRepository storeRepo;
  final CoinRepository coinRepo;

  const StatsScreen({
    super.key,
    required this.statsRepo,
    required this.storeRepo,
    required this.coinRepo,
  });

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  /// Snapshot of every persisted stat. Null while loading.
  LifetimeStats? _stats;

  /// Lifetime coins (from CoinRepository's lifetime counter — separate
  /// from the stats repo's accumulator so we use the secure store as
  /// the source of truth for currency).
  int _lifetimeCoins = 0;

  /// First-skin achievement: derived from StoreRepository owned set.
  bool _ownsAnyPaidSkin = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final snap = await widget.statsRepo.snapshot();
    final lifetime = await widget.coinRepo.getLifetimeEarned();
    final owned = await widget.storeRepo.getOwnedItems();
    if (!mounted) return;
    setState(() {
      _stats = snap;
      _lifetimeCoins = lifetime;
      _ownsAnyPaidSkin = owned.any((id) => id.startsWith('skin:'));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'STATS',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
          ),
        ),
      ),
      body: _stats == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSectionTitle('LIFETIME'),
                _buildStatCard(_buildLifetimeStats(_stats!)),
                const SizedBox(height: 16),
                _buildSectionTitle('PERSONAL BESTS'),
                _buildStatCard(_buildPersonalBests(_stats!)),
                const SizedBox(height: 16),
                _buildSectionTitle('ACHIEVEMENTS'),
                _buildAchievements(_stats!),
                const SizedBox(height: 16),
                _buildAllAchievementsButton(),
                const SizedBox(height: 8),
                _buildViewLeaderboardButton(),
              ],
            ),
    );
  }

  // ---- sections -----------------------------------------------------------

  Widget _buildSectionTitle(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white60,
          fontSize: 12,
          letterSpacing: 4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildStatCard(List<Widget> rows) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x44000000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Column(children: rows),
    );
  }

  List<Widget> _buildLifetimeStats(LifetimeStats s) {
    // We measure "total depth fallen" as cumulative high-depth
    // contributions — StatsRepository doesn't carry a per-run depth
    // accumulator, so the closest single number we have is the
    // best-ever depth. We surface both, separately labelled.
    return [
      _buildRow(Icons.arrow_downward, 'Best depth',
          '${s.highDepthMeters}m'),
      _buildRow(
        Icons.monetization_on,
        'Total coins earned',
        '$_lifetimeCoins',
      ),
      _buildRow(Icons.diamond, 'Total gems', '${s.totalGems}'),
      _buildRow(Icons.flash_on, 'Total near-misses', '${s.totalNearMisses}'),
      _buildRow(Icons.replay, 'Games played', '${s.totalGamesPlayed}'),
    ];
  }

  List<Widget> _buildPersonalBests(LifetimeStats s) {
    return [
      _buildRow(Icons.emoji_events, 'High score', '${s.highScore}'),
      _buildRow(Icons.south, 'High depth (single run)', '${s.highDepthMeters}m'),
    ];
  }

  Widget _buildRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFFD700), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ---- achievements -------------------------------------------------------

  /// Five-up featured achievement list. Progress is computed from the
  /// already-loaded snapshot — no extra IO. Phase 10 will move these
  /// definitions into a real registry; for now they're inline.
  Widget _buildAchievements(LifetimeStats s) {
    final entries = <_AchievementEntry>[
      _AchievementEntry(
        title: 'Fall 10,000m total',
        // We don't have a true "total depth" counter; until Phase 10
        // adds one we approximate using best-ever depth × games played
        // (capped) as a directional proxy. Players will see steady
        // progress on every run that beats their PR.
        progress: ((s.highDepthMeters * s.totalGamesPlayed) / 10000)
            .clamp(0.0, 1.0)
            .toDouble(),
      ),
      const _AchievementEntry(
        title: 'Get a 10x combo',
        // Best combo isn't persisted by StatsRepository (it lives on
        // RunStats). Lock to 0% until Phase 10 wires the persistence.
        // The bar is still visible so the player knows the ach exists.
        progress: 0,
      ),
      _AchievementEntry(
        title: 'Collect 1,000 lifetime coins',
        progress: (_lifetimeCoins / 1000).clamp(0.0, 1.0).toDouble(),
      ),
      const _AchievementEntry(
        title: 'Survive 3 zones without a hit',
        // Same as above: per-run "hits taken" isn't persisted yet.
        progress: 0,
      ),
      _AchievementEntry(
        title: 'Buy your first skin',
        progress: _ownsAnyPaidSkin ? 1 : 0,
      ),
    ];
    return _buildStatCard([
      for (final e in entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _AchievementProgress(entry: e),
        ),
    ]);
  }

  Widget _buildAllAchievementsButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonal(
        onPressed: () =>
            Navigator.of(context).pushNamed(AppRoutes.achievements),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: const Text(
          'VIEW ALL ACHIEVEMENTS',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildViewLeaderboardButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () =>
            Navigator.of(context).pushNamed(AppRoutes.leaderboard),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF80DEEA),
          side: const BorderSide(color: Color(0xFF80DEEA), width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: const Icon(Icons.leaderboard, size: 18),
        label: const Text(
          'VIEW LEADERBOARD',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

class _AchievementEntry {
  final String title;
  final double progress;

  const _AchievementEntry({required this.title, required this.progress});
}

class _AchievementProgress extends StatelessWidget {
  final _AchievementEntry entry;
  const _AchievementProgress({required this.entry});

  @override
  Widget build(BuildContext context) {
    final pct = (entry.progress * 100).clamp(0, 100).toStringAsFixed(0);
    final completed = entry.progress >= 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                entry.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              completed ? 'DONE' : '$pct%',
              style: TextStyle(
                color: completed
                    ? const Color(0xFF40E0D0)
                    : Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: entry.progress.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: const Color(0x22FFFFFF),
            valueColor: AlwaysStoppedAnimation(
              completed
                  ? const Color(0xFF40E0D0)
                  : const Color(0xFFFFD700),
            ),
          ),
        ),
      ],
    );
  }
}
