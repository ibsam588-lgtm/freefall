// screens/daily_login_screen.dart
//
// One-shot login bonus card. Shows a 7-day calendar with the current
// day highlighted, the coin reward for today's slot, and a "Claim!"
// CTA. Tapping Claim awards the coins via the injected
// [DailyLoginRepository] + [CoinRepository] and dismisses the screen.
//
// The host (main_menu_screen) decides when to show this — usually
// once on app launch if `repo.isClaimAvailable()` returns true.

import 'package:flutter/material.dart';

import '../models/daily_login_bonus.dart';
import '../repositories/coin_repository.dart';
import '../repositories/daily_login_repository.dart';

class DailyLoginScreen extends StatefulWidget {
  final DailyLoginRepository loginRepo;
  final CoinRepository coinRepo;

  /// Called after the claim completes (or was rejected). Caller routes
  /// the user back to wherever they came from.
  final VoidCallback onDismiss;

  const DailyLoginScreen({
    super.key,
    required this.loginRepo,
    required this.coinRepo,
    required this.onDismiss,
  });

  @override
  State<DailyLoginScreen> createState() => _DailyLoginScreenState();
}

class _DailyLoginScreenState extends State<DailyLoginScreen> {
  /// The day the player is *about* to claim (1..7). Resolved on init.
  int? _pendingDay;

  /// Coin reward for that day.
  int _pendingCoins = 0;

  /// True once the claim has landed; suppresses double-taps.
  bool _claimed = false;

  /// True while the async claim is in flight.
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _resolvePending();
  }

  Future<void> _resolvePending() async {
    final available = await widget.loginRepo.isClaimAvailable();
    final coins = available ? await widget.loginRepo.getPendingReward() : 0;
    final streak = await widget.loginRepo.getConsecutiveDays();
    // The "next day" the user will claim today: if streak is 0 or
    // they missed days, it's Day 1; otherwise streak+1 (wrap at 7).
    int nextDay;
    if (!available) {
      nextDay = streak == 0 ? 1 : streak;
    } else if (streak == 0) {
      nextDay = 1;
    } else if (streak >= DailyLoginBonus.cycleLength) {
      nextDay = 1;
    } else {
      nextDay = streak + 1;
    }
    if (!mounted) return;
    setState(() {
      _pendingDay = nextDay;
      _pendingCoins = coins;
      // If nothing to claim, mark already-claimed to disable the button.
      _claimed = !available;
    });
  }

  Future<void> _onClaim() async {
    if (_claiming || _claimed) return;
    setState(() => _claiming = true);

    final result = await widget.loginRepo.recordLogin();
    if (result.claimed && result.coins > 0) {
      await widget.coinRepo.addCoins(result.coins);
    }
    if (!mounted) return;
    setState(() {
      _claimed = true;
      _claiming = false;
      _pendingCoins = result.coins;
      _pendingDay = result.day;
    });

    // Auto-dismiss after a short delay so the player can read the
    // banner — feels rewarding without trapping them on the screen.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pendingDay;
    return Material(
      color: const Color(0xCC000010),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'DAILY BONUS',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (pending != null) _buildCalendar(pending),
                  const SizedBox(height: 20),
                  Text(
                    _claimed ? '+$_pendingCoins coins!' : '$_pendingCoins coins today',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: (_claimed || _claiming) ? null : _onClaim,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: const Color(0xFF101018),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        _claimed ? 'CLAIMED' : 'CLAIM!',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendar(int currentDay) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: List.generate(
        DailyLoginBonus.cycleLength,
        (i) {
          final day = i + 1;
          final isCurrent = day == currentDay;
          final reward = DailyLoginBonus.bonusCoins[i];
          return Container(
            width: 64,
            height: 70,
            decoration: BoxDecoration(
              color: isCurrent
                  ? const Color(0xFFFFD700)
                  : const Color(0x33FFFFFF),
              border: Border.all(
                color: isCurrent
                    ? const Color(0xFFFFFFFF)
                    : const Color(0x55FFFFFF),
                width: isCurrent ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Day $day',
                  style: TextStyle(
                    color: isCurrent
                        ? const Color(0xFF101018)
                        : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '+$reward',
                  style: TextStyle(
                    color: isCurrent
                        ? const Color(0xFF101018)
                        : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
