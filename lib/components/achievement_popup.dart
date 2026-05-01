// components/achievement_popup.dart
//
// Phase 10 in-game popup overlay for achievement unlocks. A Flutter
// widget (not a Flame component) so it can sit on top of the
// GameWidget/Stack and use Material's Animation pipeline directly.
//
// Usage pattern:
//   final controller = AchievementPopupController();
//   AchievementManager(...).onAchievementUnlocked = controller.enqueue;
//   ...
//   Stack(children: [GameWidget(...), AchievementPopupOverlay(controller: controller)]);
//
// One popup at a time, queued FIFO. Each popup slides in from the
// bottom over 250ms, holds for 3s, then slides back out. The next
// queued unlock starts as soon as the previous slide-out finishes.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../models/achievement.dart';

/// Controller for the popup queue. The achievement manager pushes
/// unlocks here via [enqueue]; the overlay listens to [stream] to know
/// what to show next.
class AchievementPopupController {
  final Queue<Achievement> _pending = Queue<Achievement>();
  final StreamController<Achievement> _controller =
      StreamController<Achievement>.broadcast();

  bool _showing = false;

  /// Achievements to show, one at a time. The overlay subscribes; tests
  /// can subscribe too to assert ordering.
  Stream<Achievement> get stream => _controller.stream;

  /// Number of unlocks queued behind the currently-showing popup.
  int get pendingCount => _pending.length;

  /// True iff a popup is currently on screen.
  bool get isShowing => _showing;

  /// Push an unlock onto the queue. If nothing is currently showing,
  /// the overlay starts animating it on the next frame.
  void enqueue(Achievement achievement) {
    _pending.add(achievement);
    _drain();
  }

  /// The overlay calls this when its hide animation has finished, so
  /// the queue can advance.
  void notifyDismissed() {
    _showing = false;
    _drain();
  }

  void _drain() {
    if (_showing || _pending.isEmpty || _controller.isClosed) return;
    _showing = true;
    _controller.add(_pending.removeFirst());
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}

/// Stack-anchored popup that listens to a [AchievementPopupController]
/// and animates Achievement unlocks in from the bottom.
class AchievementPopupOverlay extends StatefulWidget {
  final AchievementPopupController controller;

  /// Visible duration before the popup auto-dismisses. Defaults to 3s.
  final Duration visibleDuration;

  /// Slide-in / slide-out animation length.
  final Duration slideDuration;

  const AchievementPopupOverlay({
    super.key,
    required this.controller,
    this.visibleDuration = const Duration(seconds: 3),
    this.slideDuration = const Duration(milliseconds: 250),
  });

  @override
  State<AchievementPopupOverlay> createState() =>
      _AchievementPopupOverlayState();
}

class _AchievementPopupOverlayState extends State<AchievementPopupOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide;
  late final Animation<Offset> _offset;
  StreamSubscription<Achievement>? _sub;
  Achievement? _current;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _slide = AnimationController(vsync: this, duration: widget.slideDuration);
    _offset = Tween<Offset>(
      begin: const Offset(0, 1.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slide, curve: Curves.easeOutBack));

    _sub = widget.controller.stream.listen(_onUnlock);
  }

  void _onUnlock(Achievement ach) {
    if (!mounted) return;
    setState(() => _current = ach);
    _slide.forward(from: 0);
    _holdTimer?.cancel();
    _holdTimer = Timer(widget.visibleDuration, _hide);
  }

  Future<void> _hide() async {
    if (!mounted) return;
    await _slide.reverse();
    if (!mounted) return;
    setState(() => _current = null);
    widget.controller.notifyDismissed();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _sub?.cancel();
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ach = _current;
    if (ach == null) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 32,
      child: SafeArea(
        top: false,
        child: SlideTransition(
          position: _offset,
          child: Center(child: _AchievementCard(achievement: ach)),
        ),
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  final Achievement achievement;

  const _AchievementCard({required this.achievement});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xCC0A0A14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80FFD700),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0xFFFFEF80), Color(0xFFFFD700)],
              ),
            ),
            child: const Icon(
              Icons.emoji_events,
              color: Color(0xFF332600),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ACHIEVEMENT UNLOCKED',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  achievement.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  achievement.description,
                  style: const TextStyle(
                    color: Color(0xFFCFCFD8),
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
