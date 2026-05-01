// screens/pause_screen.dart
//
// Paused-game overlay. Shown by GameScreen when the player taps the
// back button (or the pause control once it lands in the HUD). Sits
// on top of the running game widget — the engine is paused via
// FreefallGame.pauseEngine() before this is drawn.
//
// Routing: this widget never pushes routes itself. It calls back into
// the host with one of the four actions (resume/restart/settings/quit)
// and lets the host choose how to react. Keeps the widget pure and
// re-usable from a different game shell later.

import 'package:flutter/material.dart';

class PauseScreen extends StatelessWidget {
  /// Resume the game in-place.
  final VoidCallback onResume;

  /// Restart the run from depth zero.
  final VoidCallback onRestart;

  /// Open the settings overlay (host pushes the SettingsScreen route).
  final VoidCallback onOpenSettings;

  /// Pop back to the main menu.
  final VoidCallback onQuit;

  const PauseScreen({
    super.key,
    required this.onResume,
    required this.onRestart,
    required this.onOpenSettings,
    required this.onQuit,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC000010),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'PAUSED',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _menuButton(
                    label: 'RESUME',
                    color: const Color(0xFF40E0D0),
                    onPressed: onResume,
                  ),
                  const SizedBox(height: 8),
                  _menuButton(
                    label: 'RESTART',
                    color: const Color(0xFFFF9100),
                    onPressed: onRestart,
                  ),
                  const SizedBox(height: 8),
                  _menuButton(
                    label: 'SETTINGS',
                    color: const Color(0xFF80DEEA),
                    onPressed: onOpenSettings,
                  ),
                  const SizedBox(height: 8),
                  _menuButton(
                    label: 'QUIT',
                    color: const Color(0xFFFF5252),
                    onPressed: onQuit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuButton({
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: const Color(0xFF101018),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: 3,
        ),
      ),
    );
  }
}
