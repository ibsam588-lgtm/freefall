// screens/leaderboard_screen.dart
//
// Phase-13 leaderboard hub. Two states the player can be in:
//   * Signed out — render a single sign-in CTA. Tapping it calls
//     [GooglePlayGamesService.signIn]; on success we drop into the
//     signed-in view.
//   * Signed in — show the player's name, two tab cards (Best Score
//     / Deepest Dive), each with a button that opens the platform
//     leaderboard UI for that ranking, plus a "View All" button that
//     opens the full leaderboards screen.
//
// We don't fetch + render scores in-app yet — Phase 13 leans on the
// platform leaderboard UI. A custom scoreboard with friend-cursor
// + paged pulls lands when the social phase budget allows.

import 'package:flutter/material.dart';

import '../services/google_play_games_stub.dart';

class LeaderboardScreen extends StatefulWidget {
  /// Phase 13: optional Play Games / Game Center backend. When null,
  /// the screen always renders the signed-out state with a disabled
  /// CTA — the route still exists so menu navigation works.
  final GooglePlayGamesService? gameServices;

  const LeaderboardScreen({super.key, this.gameServices});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  bool _signedIn = false;
  String? _playerName;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
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
              child: _signedIn ? _buildSignedIn() : _buildSignedOut(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignedOut() {
    final svc = widget.gameServices;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.leaderboard,
          color: Color(0xFFFFD700),
          size: 96,
        ),
        const SizedBox(height: 24),
        const Text(
          'Sign in with Google Play Games\nto compete on the leaderboards.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
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
              _busy ? 'CONNECTING…' : 'SIGN IN',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
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
        const Icon(
          Icons.leaderboard,
          color: Color(0xFFFFD700),
          size: 64,
        ),
        const SizedBox(height: 12),
        Text(
          'Hi, ${_playerName ?? 'Faller'}!',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 24),
        _LeaderboardTabCard(
          title: 'BEST SCORE',
          subtitle: 'Highest run score across all zones.',
          accent: const Color(0xFFFFD700),
          onTap: () => _openLeaderboard(
              GooglePlayGamesService.bestScoreLeaderboardId),
        ),
        const SizedBox(height: 12),
        _LeaderboardTabCard(
          title: 'DEEPEST DIVE',
          subtitle: 'Maximum depth reached, in meters.',
          accent: const Color(0xFF40E0D0),
          onTap: () => _openLeaderboard(
              GooglePlayGamesService.bestDepthLeaderboardId),
        ),
        const SizedBox(height: 24),
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
