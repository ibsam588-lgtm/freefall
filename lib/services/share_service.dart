// services/share_service.dart
//
// Phase 13 score-share pipeline. Renders a 400×300 branded card from
// the run's stats + the player's equipped skin, dumps it to a temp
// PNG, and hands the file to share_plus' platform share sheet.
//
// The image is built with `dart:ui` (PictureRecorder + Canvas) so we
// don't pull in a render-flutter dependency — the same primitives
// already drive every Phase-2..11 visual. That keeps the pipeline
// testable headlessly: [generateShareImage] returns the raw PNG
// bytes and never touches the platform until the caller hands them
// to [share_plus].
//
// Composition (top → bottom):
//   * radial gradient backdrop tinted with the deepest zone reached
//   * orb circle in the equipped skin's primary color
//   * "FREEFALL" wordmark
//   * depth in big numerals + zone name
//   * score
//   * "Can you beat me?" tagline

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/player_skin.dart';
import '../models/run_stats.dart';
import '../models/zone.dart';

/// Result of [ShareService.shareScore]. Returned to the caller so it
/// can swap the share button into a "Shared!" state when the platform
/// reports success.
enum ShareOutcome {
  /// Share sheet completed and the user picked a target.
  shared,

  /// User dismissed the share sheet.
  dismissed,

  /// Could not present the share sheet (no platform plugin, error).
  failed,
}

class ShareService {
  /// Output image dimensions. 400×300 is large enough to read on a
  /// social feed thumbnail without triggering re-encode passes on
  /// Twitter / iMessage.
  static const int imageWidth = 400;
  static const int imageHeight = 300;

  /// Tagline rendered along the bottom edge.
  static const String tagline = 'Can you beat me?';

  /// Override for tests — defaults to [SharePlus.instance].
  final SharePlus? _shareOverride;

  /// Override for tests — defaults to [getTemporaryDirectory()].
  final Future<Directory> Function()? _tempDirOverride;

  ShareService({
    SharePlus? share,
    Future<Directory> Function()? tempDirProvider,
  })  : _shareOverride = share,
        _tempDirOverride = tempDirProvider;

  // ---- public API --------------------------------------------------------

  /// Build the share image, persist it to a temp PNG, and trigger
  /// the platform share sheet. [equippedSkin] determines the orb
  /// color + which skin's identity gets highlighted on the card.
  ///
  /// Defensive on every step — image generation, file IO, and the
  /// platform share call are wrapped in try/catch so a missing
  /// platform plugin (web, headless tests) returns
  /// [ShareOutcome.failed] instead of crashing.
  Future<ShareOutcome> shareScore(
    RunStats stats,
    SkinId equippedSkin,
  ) async {
    try {
      final png = await generateShareImage(stats, equippedSkin);
      final file = await _writeToTempFile(png);
      final share = _shareOverride ?? SharePlus.instance;
      final params = ShareParams(
        text: _shareText(stats),
        files: [XFile(file.path)],
      );
      final result = await share.share(params);
      switch (result.status) {
        case ShareResultStatus.success:
          return ShareOutcome.shared;
        case ShareResultStatus.dismissed:
          return ShareOutcome.dismissed;
        case ShareResultStatus.unavailable:
          return ShareOutcome.failed;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ShareService] shareScore failed: $e');
      return ShareOutcome.failed;
    }
  }

  /// Render the share image and return the raw PNG bytes. Useful for
  /// tests + analytics (you can persist the bytes without going
  /// through the platform share sheet).
  Future<Uint8List> generateShareImage(
    RunStats stats,
    SkinId equippedSkin,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(
          0, 0, imageWidth.toDouble(), imageHeight.toDouble()),
    );
    final skin = PlayerSkin.byId(equippedSkin);
    final zone = _zoneForDepth(stats.depthMeters);
    _paintBackground(canvas, zone);
    _paintOrb(canvas, skin);
    _paintWordmark(canvas);
    _paintDepth(canvas, stats);
    _paintZoneLabel(canvas, zone);
    _paintScore(canvas, stats);
    _paintTagline(canvas);

    final picture = recorder.endRecording();
    final image = await picture.toImage(imageWidth, imageHeight);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) {
      throw StateError('toByteData returned null — encoder failure');
    }
    return bytes.buffer.asUint8List();
  }

  // ---- composition primitives --------------------------------------------

  void _paintBackground(ui.Canvas canvas, Zone zone) {
    final rect = ui.Rect.fromLTWH(
        0, 0, imageWidth.toDouble(), imageHeight.toDouble());
    final paint = ui.Paint()
      ..shader = ui.Gradient.radial(
        const ui.Offset(imageWidth / 2, imageHeight * 0.35),
        imageWidth * 0.7,
        [
          zone.topColor,
          zone.bottomColor,
          const ui.Color(0xFF050510),
        ],
        const [0.0, 0.6, 1.0],
      );
    canvas.drawRect(rect, paint);
    // Subtle vignette so text contrast holds even on the lightest zone.
    final vignette = ui.Paint()
      ..shader = ui.Gradient.radial(
        const ui.Offset(imageWidth / 2, imageHeight / 2),
        imageWidth * 0.7,
        [
          const ui.Color(0x00000000),
          const ui.Color(0x88000000),
        ],
        const [0.5, 1.0],
      );
    canvas.drawRect(rect, vignette);
  }

  void _paintOrb(ui.Canvas canvas, PlayerSkin skin) {
    const center = ui.Offset(72, 116);
    final glow = ui.Paint()
      ..shader = ui.Gradient.radial(
        center,
        56,
        [
          skin.glowColor.withValues(alpha: 0.85),
          skin.glowColor.withValues(alpha: 0.0),
        ],
      );
    canvas.drawCircle(center, 56, glow);
    final body = ui.Paint()..color = skin.primaryColor;
    canvas.drawCircle(center, 24, body);
    final highlight = ui.Paint()
      ..color = const ui.Color(0xCCFFFFFF);
    canvas.drawCircle(center.translate(-7, -7), 6, highlight);
  }

  void _paintWordmark(ui.Canvas canvas) {
    _drawText(
      canvas,
      'FREEFALL',
      const ui.Offset(135, 36),
      fontSize: 28,
      letterSpacing: 6,
      color: const ui.Color(0xFFFFFFFF),
      fontWeight: ui.FontWeight.w900,
      shadowBlur: 12,
      shadowColor: const ui.Color(0xFF40E0D0),
    );
  }

  void _paintDepth(ui.Canvas canvas, RunStats stats) {
    final depthLabel = '${stats.depthMeters.round()}m';
    _drawText(
      canvas,
      depthLabel,
      const ui.Offset(135, 78),
      fontSize: 56,
      color: const ui.Color(0xFFFFD700),
      fontWeight: ui.FontWeight.w900,
      shadowBlur: 14,
      shadowColor: const ui.Color(0xFFFF9100),
    );
  }

  void _paintZoneLabel(ui.Canvas canvas, Zone zone) {
    _drawText(
      canvas,
      zone.name.toUpperCase(),
      const ui.Offset(135, 150),
      fontSize: 14,
      letterSpacing: 4,
      color: zone.accentColor,
      fontWeight: ui.FontWeight.w700,
    );
  }

  void _paintScore(ui.Canvas canvas, RunStats stats) {
    _drawText(
      canvas,
      'SCORE: ${stats.score}',
      const ui.Offset(20, 200),
      fontSize: 18,
      color: const ui.Color(0xFFE0E0E8),
      fontWeight: ui.FontWeight.w800,
      letterSpacing: 2,
    );
  }

  void _paintTagline(ui.Canvas canvas) {
    _drawText(
      canvas,
      tagline,
      const ui.Offset(20, 256),
      fontSize: 18,
      color: const ui.Color(0xFFFFFFFF),
      fontWeight: ui.FontWeight.w900,
      letterSpacing: 1.2,
      shadowBlur: 8,
      shadowColor: const ui.Color(0xFF000000),
    );
  }

  // ---- helpers ----------------------------------------------------------

  /// Map the deepest depth to the zone the player was in at the
  /// moment of death. Wraps within a cycle (depth % cycleDepth) so a
  /// cross-cycle run still reads as Stratosphere etc., not the
  /// fictional 6th zone.
  Zone _zoneForDepth(double depthMeters) {
    final inCycle =
        depthMeters <= 0 ? 0.0 : depthMeters % Zone.cycleDepth;
    for (final z in Zone.defaultCycle) {
      if (inCycle < z.endDepth) return z;
    }
    return Zone.defaultCycle.last;
  }

  String _shareText(RunStats stats) {
    final depth = stats.depthMeters.round();
    return 'I fell ${depth}m and scored ${stats.score} in Freefall! '
        'Can you beat me? #Freefall';
  }

  Future<File> _writeToTempFile(Uint8List bytes) async {
    final dir = await (_tempDirOverride?.call() ?? getTemporaryDirectory());
    final file = File('${dir.path}/freefall_share.png');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  void _drawText(
    ui.Canvas canvas,
    String text,
    ui.Offset offset, {
    required double fontSize,
    required ui.Color color,
    ui.FontWeight fontWeight = ui.FontWeight.w400,
    double letterSpacing = 0,
    double? shadowBlur,
    ui.Color? shadowColor,
  }) {
    final shadows = (shadowBlur != null && shadowColor != null)
        ? <ui.Shadow>[
            ui.Shadow(
              color: shadowColor,
              blurRadius: shadowBlur,
            ),
          ]
        : const <ui.Shadow>[];
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: ui.TextAlign.left,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
    )
      ..pushStyle(
        ui.TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
          shadows: shadows,
        ),
      )
      ..addText(text);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 380));
    canvas.drawParagraph(paragraph, offset);
  }
}
