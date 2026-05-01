// systems/performance_monitor.dart
//
// Phase 14 adaptive perf monitor. Tracks a rolling window of frame
// dts and exposes:
//   * a 0..1 [performanceLevel] derived from the average frame time,
//   * particle / background-layer budgets matched to that level,
//   * an [isStruggling] boolean for "the device can't hold 50fps".
//
// Engine-agnostic. The host (FreefallGame.update) feeds [recordFrame]
// once per tick; gameplay components read [maxParticles] and
// [backgroundLayers] each render to decide how much to draw.
//
// Sliding window math: a 60-sample buffer covers ~1s at 60fps. We
// compute the moving average on every recordFrame as a single sum
// (kept incrementally) divided by the sample count — O(1) read,
// O(1) write, no per-frame allocation.

class PerformanceMonitor {
  /// Number of frames in the rolling average. ~1s at 60fps; long
  /// enough to wash out a single GC pause, short enough to react
  /// when the device genuinely starts struggling.
  static const int sampleWindow = 60;

  /// Frame target in seconds. 60fps ⇒ 16.6ms.
  static const double targetFrameSeconds = 1.0 / 60.0;

  /// Frame time at which we declare full performance loss (level 0).
  /// 33.3ms ⇒ 30fps.
  static const double worstFrameSeconds = 1.0 / 30.0;

  /// Threshold for [isStruggling] — average above this means the
  /// device can't sustain 50fps and the game should de-spec visuals.
  static const double strugglingFrameSeconds = 1.0 / 50.0;

  /// Particle budgets per performance tier. Spec calls out 60/30/15.
  static const int particlesHigh = 60;
  static const int particlesMedium = 30;
  static const int particlesLow = 15;

  /// Background parallax-layer budgets. Spec calls out 2/1/0.
  static const int layersHigh = 2;
  static const int layersMedium = 1;
  static const int layersLow = 0;

  /// Tier boundaries on [performanceLevel] (0..1):
  ///   level >= 0.7 → high
  ///   level >= 0.35 → medium
  ///   else → low
  static const double mediumTierThreshold = 0.35;
  static const double highTierThreshold = 0.7;

  // Ring buffer of dt samples. Index walks forward modulo sampleWindow.
  final List<double> _samples = List<double>.filled(sampleWindow, 0);
  int _head = 0;

  // Number of recorded samples (caps at sampleWindow). Lets the
  // average be sane while the buffer is still warming up.
  int _filled = 0;

  // Running sum so the average is O(1) per [recordFrame].
  double _sum = 0;

  /// Add [dt] (seconds) to the sample window. The host clamps dt
  /// elsewhere so we don't have to worry about stalls — but defensive
  /// against zero / negative just in case (a paused frame can land 0).
  void recordFrame(double dt) {
    if (dt <= 0) return;
    final old = _samples[_head];
    _samples[_head] = dt;
    _sum += dt - old;
    _head = (_head + 1) % sampleWindow;
    if (_filled < sampleWindow) _filled++;
  }

  /// Drop every recorded frame. Call between runs so a slow death
  /// animation doesn't bleed pessimism into a fresh respawn.
  void reset() {
    for (int i = 0; i < sampleWindow; i++) {
      _samples[i] = 0;
    }
    _head = 0;
    _filled = 0;
    _sum = 0;
  }

  /// Number of frames currently in the rolling window. Useful for
  /// tests — `level` is meaningful even when only a couple of frames
  /// are recorded.
  int get sampleCount => _filled;

  /// Average frame time in seconds. Returns the target (16.6ms) when
  /// nothing has been recorded — avoids reporting "0fps == perfect"
  /// before the first frame.
  double get averageFrameSeconds {
    if (_filled == 0) return targetFrameSeconds;
    return _sum / _filled;
  }

  /// 0.0 (struggling at 30fps) → 1.0 (locked at 60fps). Linear
  /// interpolation between target and worst frame times.
  double get performanceLevel {
    if (_filled == 0) return 1.0;
    final avg = averageFrameSeconds;
    if (avg <= targetFrameSeconds) return 1.0;
    if (avg >= worstFrameSeconds) return 0.0;
    const span = worstFrameSeconds - targetFrameSeconds;
    return 1.0 - ((avg - targetFrameSeconds) / span);
  }

  /// True iff average frame time has crept above the 50fps threshold.
  /// Once true, the game should drop a visual tier.
  bool get isStruggling {
    if (_filled == 0) return false;
    return averageFrameSeconds > strugglingFrameSeconds;
  }

  /// Particle budget for the current tier. Read by [PlayerParticleSystem]
  /// + ZoneBackground each frame to cap visible counts.
  int get maxParticles {
    final level = performanceLevel;
    if (level >= highTierThreshold) return particlesHigh;
    if (level >= mediumTierThreshold) return particlesMedium;
    return particlesLow;
  }

  /// Number of parallax background layers to render. 2 = far + near,
  /// 1 = near only, 0 = gradient + ambient particles only.
  int get backgroundLayers {
    final level = performanceLevel;
    if (level >= highTierThreshold) return layersHigh;
    if (level >= mediumTierThreshold) return layersMedium;
    return layersLow;
  }
}
