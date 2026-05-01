// screens/settings_screen.dart
//
// Player-facing settings panel. Reads from + writes through to the
// injected [SettingsService] so toggles take effect (and persist)
// the moment the user flips them.
//
// Surface area matches the Phase-7 spec:
//   * sound on/off
//   * music on/off
//   * haptic on/off
//   * control type — Tilt vs Touch
//   * tilt sensitivity slider 0.5–2.0
//
// Settings UI is a stateful widget that rebuilds locally on each
// change. The service handles persistence; this widget just observes.

import 'package:flutter/material.dart';

import '../services/audio_service.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService settings;

  /// Phase 11: optional audio backend. When wired, sound/music toggles
  /// are mirrored into [AudioService] so the change is audible
  /// instantly (without waiting for a fresh game session to read
  /// settings on launch).
  final AudioService? audioService;

  const SettingsScreen({
    super.key,
    required this.settings,
    this.audioService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsService get _s => widget.settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'SETTINGS',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildToggle(
            'Sound effects',
            _s.soundEnabled,
            (v) async {
              await _s.setSoundEnabled(v);
              widget.audioService?.syncFromSettings(_s);
              setState(() {});
            },
          ),
          _buildToggle(
            'Music',
            _s.musicEnabled,
            (v) async {
              await _s.setMusicEnabled(v);
              widget.audioService?.syncFromSettings(_s);
              setState(() {});
            },
          ),
          _buildToggle(
            'Haptic feedback',
            _s.hapticEnabled,
            (v) async {
              await _s.setHapticEnabled(v);
              setState(() {});
            },
          ),
          const Divider(color: Colors.white24, height: 32),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              'CONTROLS',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 12,
                letterSpacing: 3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _buildControlRadio(),
          const SizedBox(height: 16),
          _buildSensitivitySlider(),
        ],
      ),
    );
  }

  Widget _buildToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile.adaptive(
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildControlRadio() {
    return Column(
      children: [
        RadioListTile<ControlType>(
          title: const Text(
            'Tilt',
            style: TextStyle(color: Colors.white),
          ),
          subtitle: const Text(
            'Use the device accelerometer.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          value: ControlType.tilt,
          groupValue: _s.controlType,
          onChanged: (v) async {
            if (v == null) return;
            await _s.setControlType(v);
            setState(() {});
          },
        ),
        RadioListTile<ControlType>(
          title: const Text(
            'Touch',
            style: TextStyle(color: Colors.white),
          ),
          subtitle: const Text(
            'Tap left/right edges of the screen.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          value: ControlType.touch,
          groupValue: _s.controlType,
          onChanged: (v) async {
            if (v == null) return;
            await _s.setControlType(v);
            setState(() {});
          },
        ),
      ],
    );
  }

  Widget _buildSensitivitySlider() {
    final v = _s.tiltSensitivity;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Text(
              'Tilt sensitivity   ${v.toStringAsFixed(2)}x',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          Slider(
            value: v,
            min: SettingsService.minSensitivity,
            max: SettingsService.maxSensitivity,
            divisions: 30,
            label: v.toStringAsFixed(2),
            onChanged: (next) async {
              await _s.setTiltSensitivity(next);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}
