// screens/leaderboard_screen.dart
//
// Leaderboard hub with two modes:
//   * Guest — always shown. Displays the player's local high score from
//     StatsRepository. No sign-in required.
//   * Signed-in — shows Play Games / Game Center leaderboard cards when
//     the player opts in. Sign-in is optional and offered as a CTA.
//
// Sign-in is never forced. The guest view is fully functional on its own.

import 'package:flutter/material.dart';

import '../repositories/stats_repository.dart';
import '../services/google_play_games_stub.dart';

class LeaderboardScreen extends StatefulWidget {
  final GooglePlayGamesService? gameServices;
  final StatsRepository statsRepo;

  const LeaderboardScreen({
    super.key,
    this.gameServices,
    required this.statsRepo,
  });

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  bool _signedIn = false;
  String? _playerName;
  bool _busy = false;
  int _localHighScore = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final score = await widget.statsRepo.getHighScore();
    if (!mounted) return;
    setState(() => _localHighScore = score);

    final svc = widget.gameServices;
    if (svc == null) return;
    final signedIn = await svc.isSignedIn();
    if (!mounted) return;
    if (signedIn) {
      final name = await svc.getPlayerName();
      if (!mounted) return;
      setState(() {
        _signedIn = true;
        _playerName = name;
      });
    }
  }

  Future<void> _handleSignIn() async {
    final svc = widget.gameServices;
    if (svc == null) return;
    setState(() => _busy = true);
    final ok = await svc.signIn();
    if (!mounted) return;
    if (ok) {
      final name = await svc.getPlayerName();
      if (!mounted) return;
      setState(() {
        _signedIn = true;
        _playerName = name;
        _busy = false;
      });
    } else {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign-in failed or cancelled'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openLeaderboard(String id) async {
    final svc = widget.gameServices;
    if (svc == null) return;
    final ok = await svc.showLeaderboard(id);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Leaderboard unavailable'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openAllLeaderboards() async {
    final svc = widget.gameServices;
    if (svc == null) return;
    final ok = await svc.showAllLeaderboards();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Leaderboards unavailable'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'LEADERBOARD',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLocalScore(),
                  const SizedBox(height: 28),
                  if (_signedIn) ...[
                    _buildSignedIn(),
                  ] else ...[
                    _buildGlobalSection(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocalScore() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
      ),
      child: Column(
        children: [
          const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 36),
          const SizedBox(height: 8),
          const Text(
            'YOUR BEST SCORE',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              letterSpacing: 3,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _localHighScore > 0 ? '$_localHighScore' : '—',
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 48,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              shadows: [Shadow(color: Color(0xFFFF9100), blurRadius: 16)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalSection() {
    final svc = widget.gameServices;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Sign in with Google Play Games to compare your score with players worldwide.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFCFCFD8),
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: svc == null || _busy ? null : _handleSignIn,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF40E0D0),
              foregroundColor: const Color(0xFF101018),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              _busy ? 'CONNECTING…' : 'SIGN IN FOR GLOBAL RANKINGS',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
        if (svc == null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Global rankings unavailable on this build.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildSignedIn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Signed in as ${_playerName ?? 'Faller'}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF40E0D0),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        _LeaderboardTabCard(
          title: 'BEST SCORE',
          subtitle: 'Highest run score across all zones.',
          accent: const Color(0xFFFFD700),
          onTap: () =>
              _openLeaderboard(GooglePlayGamesService.bestScoreLeaderboardId),
        ),
        const SizedBox(height: 12),
        _LeaderboardTabCard(
          title: 'DEEPEST DIVE',
          subtitle: 'Maximum depth reached, in meters.',
          accent: const Color(0xFF40E0D0),
          onTap: () =>
              _openLeaderboard(GooglePlayGamesService.bestDepthLeaderboardId),
        ),
        const SizedBox(height: 20),
        FilledButton.tonal(
          onPressed: _openAllLeaderboards,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0x33FFFFFF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text(
            'VIEW ALL LEADERBOARDS',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ),
      ],
    );
  }
}

class _LeaderboardTabCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _LeaderboardTabCard({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0x33000000),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent, width: 1.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: accent,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFFCFCFD8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
