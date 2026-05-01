// systems/ghost_runner.dart
//
// Phase 10 ghost runner: records the player's horizontal position +
// timestamp every 0.1s during a run, persists the best run as a
// "ghost" trace, and replays it during subsequent runs as a faint
// orb the player can race against.
//
// Storage layout (LoginStorage backend):
//   * ghost_best_score      — best score that produced [ghost_samples]
//   * ghost_samples         — semicolon-joined list of `t,x` pairs;
//                             t is seconds since start, x is world-x.
//
// Two consumers:
//   * recordSample(t, x): host calls this every step with the player's
//     elapsed time and current x. The recorder coalesces samples to a
//     fixed 0.1s spacing so storage stays bounded.
//   * sampleAt(t): replay query — returns the stored ghost's x at t,
//     interpolated between the two nearest samples. Returns null if the
//     ghost has no data yet or t is past its end.
//
// At run end, [maybeSaveBestRun] persists the new trace iff [score]
// exceeds the previous best.

import '../repositories/daily_login_repository.dart';

/// Single recorded sample: time-since-run-start (seconds) + horizontal
/// position (world pixels).
class GhostSample {
  final double t;
  final double x;
  const GhostSample(this.t, this.x);

  /// Compact serialization. We avoid JSON because we'd be paying the
  /// parser tax on a list that's already trivially shape-uniform.
  String encode() => '${_fmt(t)},${_fmt(x)}';

  static GhostSample? decode(String raw) {
    final parts = raw.split(',');
    if (parts.length != 2) return null;
    final t = double.tryParse(parts[0]);
    final x = double.tryParse(parts[1]);
    if (t == null || x == null) return null;
    return GhostSample(t, x);
  }

  static String _fmt(double v) {
    // Three decimal places is plenty — pixel jitter under 0.001 is
    // imperceptible at 60fps and keeps the serialized size compact.
    return v.toStringAsFixed(3);
  }
}

class GhostRunner {
  /// Spacing between recorded samples, in seconds. Tuned so a 5-minute
  /// run lands at ~3000 samples — comfortable for SharedPreferences.
  static const double sampleIntervalSeconds = 0.1;

  /// Hard cap on samples per run. Stops a stuck/long run from blowing
  /// up storage. At 0.1s spacing this is ~10 minutes of ghost.
  static const int maxSamples = 6000;

  static const String bestScoreKey = 'ghost_best_score';
  static const String samplesKey = 'ghost_samples';
  static const String _sampleSep = ';';

  final LoginStorage storage;

  GhostRunner({LoginStorage? storage})
      : storage = storage ?? SharedPreferencesLoginStorage();

  // ---- recording (current run) -------------------------------------------

  final List<GhostSample> _currentSamples = [];
  double _nextSampleAt = 0;

  /// Newest-first read of the current in-progress run's samples.
  List<GhostSample> get currentSamples => List.unmodifiable(_currentSamples);

  /// Drop in-progress run state for a new run.
  void onRunStarted() {
    _currentSamples.clear();
    _nextSampleAt = 0;
  }

  /// Feed a fresh (t, x) pair from the host. Coalesces to the fixed
  /// 0.1s spacing so callers can call this every frame.
  void recordSample(double t, double x) {
    if (t < _nextSampleAt) return;
    if (_currentSamples.length >= maxSamples) return;
    _currentSamples.add(GhostSample(t, x));
    _nextSampleAt = t + sampleIntervalSeconds;
  }

  // ---- replay (loaded ghost from prior run) -------------------------------

  List<GhostSample> _ghostSamples = const [];
  int _bestScore = 0;
  bool _loaded = false;

  /// Best score that produced the currently-loaded ghost trace.
  int get bestScore => _bestScore;

  /// True iff a previous run's ghost is loaded (non-empty).
  bool get hasGhost => _ghostSamples.isNotEmpty;

  /// Number of samples in the loaded ghost — for diagnostics.
  int get ghostSampleCount => _ghostSamples.length;

  /// Newest-first read of the loaded ghost samples.
  List<GhostSample> get ghostSamples => List.unmodifiable(_ghostSamples);

  /// Hydrate the previously-saved ghost. Idempotent.
  Future<void> load() async {
    if (_loaded) return;
    _bestScore = await storage.getInt(bestScoreKey);
    final raw = await storage.getString(samplesKey);
    if (raw != null && raw.isNotEmpty) {
      _ghostSamples = raw
          .split(_sampleSep)
          .map(GhostSample.decode)
          .whereType<GhostSample>()
          .toList(growable: false);
    }
    _loaded = true;
  }

  /// Interpolated x at time [t]. Returns null when [t] is before the
  /// first sample or after the last (caller hides the orb in that case).
  double? sampleAt(double t) {
    if (_ghostSamples.isEmpty) return null;
    if (t < _ghostSamples.first.t) return null;
    if (t > _ghostSamples.last.t) return null;
    // Linear scan is fine — sample count is bounded by [maxSamples] and
    // callers query monotonically. A binary search would be faster but
    // the constant factor isn't worth it at this scale.
    for (int i = 1; i < _ghostSamples.length; i++) {
      final a = _ghostSamples[i - 1];
      final b = _ghostSamples[i];
      if (t >= a.t && t <= b.t) {
        final span = b.t - a.t;
        if (span <= 0) return a.x;
        final f = (t - a.t) / span;
        return a.x + (b.x - a.x) * f;
      }
    }
    return _ghostSamples.last.x;
  }

  // ---- end-of-run save ----------------------------------------------------

  /// Persist the current run as the new best ghost iff [score] beats
  /// the previously-saved score. Returns true iff the trace was saved.
  Future<bool> maybeSaveBestRun(int score) async {
    if (!_loaded) await load();
    if (score <= _bestScore) return false;
    if (_currentSamples.isEmpty) return false;
    _bestScore = score;
    _ghostSamples = List<GhostSample>.from(_currentSamples);
    await storage.setInt(bestScoreKey, score);
    final encoded =
        _currentSamples.map((s) => s.encode()).join(_sampleSep);
    await storage.setString(samplesKey, encoded);
    return true;
  }
}
