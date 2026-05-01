// screens/game_screen.dart
//
// Thin Flutter scaffold that hosts the FreefallGame. Owns a single
// FreefallGame instance for its lifetime and routes the Android back
// button into a pause overlay rather than letting it pop the route
// (which would tear the GameWidget down mid-run).

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/freefall_game.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final FreefallGame _game;

  // Pause UI state. The Flame engine is paused via [game.pauseEngine].
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _game = FreefallGame();
  }

  void _togglePause() {
    setState(() {
      _paused = !_paused;
      if (_paused) {
        _game.pauseEngine();
      } else {
        _game.resumeEngine();
      }
    });
  }

  Future<bool> _handleBackPressed() async {
    if (_paused) {
      // Already paused — allow exit.
      return true;
    }
    _togglePause();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _paused,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _handleBackPressed();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            GameWidget<FreefallGame>(game: _game),
            if (_paused) _PauseOverlay(onResume: _togglePause),
          ],
        ),
      ),
    );
  }
}

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({required this.onResume});

  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xCC000000),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Paused',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onResume,
                child: const Text('Resume'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text(
                  'Quit',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
