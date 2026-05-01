// screens/leaderboard_screen.dart
//
// Phase-9 stub for the global leaderboard. Real Google Play Games /
// Game Center integration lands in Phase 13. For now we render a
// "sign in" prompt so the menu's Leaderboard button has somewhere
// to land, and the analytics route name is stable.

import 'package:flutter/material.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

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
                  const Icon(
                    Icons.leaderboard,
                    color: Color(0xFFFFD700),
                    size: 96,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Sign in with Google Play Games\nto view the leaderboard.',
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
                      onPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Leaderboard sign-in lands in Phase 13'),
                          duration: Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF40E0D0),
                        foregroundColor: const Color(0xFF101018),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'SIGN IN',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
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
}
