// screens/achievements_screen.dart
//
// Phase 10 achievements browser. Renders a 2-column grid of every
// catalog row, color-coded by state:
//   * unlocked: gold border, full opacity, trophy icon lit
//   * in-progress: muted border + a 0..1 progress bar with X/Y label
//   * locked: dimmed body, lock icon, no progress text
//
// Reads from [AchievementManager.allAchievements] for the list and
// [AchievementManager.checkUnlocked] / [AchievementManager.getProgress]
// for per-card state. The manager is expected to already be loaded +
// synced before this screen mounts (the route generator handles that).

import 'package:flutter/material.dart';

import '../models/achievement.dart';
import '../systems/achievement_manager.dart';

class AchievementsScreen extends StatefulWidget {
  final AchievementManager achievementManager;

  const AchievementsScreen({
    super.key,
    required this.achievementManager,
  });

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  @override
  Widget build(BuildContext context) {
    final manager = widget.achievementManager;
    final all = manager.allAchievements;
    final unlocked = all.where((a) => manager.checkUnlocked(a.id)).length;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'ACHIEVEMENTS',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
          ),
        ),
      ),
      body: Column(
        children: [
          _buildSummaryHeader(unlocked: unlocked, total: all.length),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.85,
              ),
              itemCount: all.length,
              itemBuilder: (ctx, i) {
                final ach = all[i];
                return _AchievementCard(
                  achievement: ach,
                  unlocked: manager.checkUnlocked(ach.id),
                  progress: manager.getProgress(ach.id),
                  current: manager.currentValueFor(ach.type),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader({required int unlocked, required int total}) {
    final pct = total == 0 ? 0.0 : unlocked / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$unlocked / $total unlocked',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${(pct * 100).round()}%',
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: const Color(0x33FFFFFF),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  final Achievement achievement;
  final bool unlocked;
  final double progress;
  final int current;

  const _AchievementCard({
    required this.achievement,
    required this.unlocked,
    required this.progress,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final inProgress = !unlocked && progress > 0.0;
    final borderColor = unlocked
        ? const Color(0xFFFFD700)
        : inProgress
            ? const Color(0xFF40E0D0)
            : const Color(0x44FFFFFF);
    final iconBg = unlocked
        ? const Color(0xFFFFD700)
        : const Color(0x33FFFFFF);
    return Opacity(
      opacity: unlocked ? 1.0 : 0.85,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF15151F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: unlocked
              ? const [
                  BoxShadow(
                    color: Color(0x55FFD700),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iconBg,
                  ),
                  child: Icon(
                    unlocked ? Icons.emoji_events : Icons.lock_outline,
                    size: 20,
                    color: unlocked
                        ? const Color(0xFF332600)
                        : const Color(0xFFCFCFD8),
                  ),
                ),
                const SizedBox(width: 8),
                if (unlocked)
                  const Text(
                    'UNLOCKED',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              achievement.title,
              style: TextStyle(
                color: unlocked ? Colors.white : const Color(0xFFE0E0E8),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                achievement.description,
                style: const TextStyle(
                  color: Color(0xFFCFCFD8),
                  fontSize: 11,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!unlocked) _buildProgress(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: const Color(0x33FFFFFF),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF40E0D0)),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$current / ${achievement.targetValue}',
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: Color(0xFF80DEEA),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
