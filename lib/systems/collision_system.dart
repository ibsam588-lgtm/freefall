// systems/collision_system.dart
//
// Broadphase collision via uniform spatial-grid partitioning. Every
// physics-bearing object registers a Rect; queryRect() returns the IDs
// of objects whose cells overlap a probe rect. Narrowphase (rect-vs-rect)
// happens in queryRect() too — caller doesn't need to recheck.
//
// WHY a grid (not a quadtree): obstacle distribution is roughly uniform
// across the play column and the world is unbounded vertically. A grid's
// O(1) insert/query beats a tree's O(log n) when the cells stay small.

import 'dart:ui';

import 'system_base.dart';

class CollisionSystem implements GameSystem {
  /// Edge length of each grid cell.
  /// Tuned to be ~2x the largest obstacle so the average object hits
  /// 1–4 cells. Smaller = more inserts; bigger = more false positives.
  static const double cellSize = 100;

  // Cell key -> map of object id -> rect.
  // String keys allocate, but the per-frame churn is bounded by entity
  // count (~30 obstacles in flight), well below GC pressure thresholds.
  final Map<String, Map<String, Rect>> _grid = {};

  // Reverse index for cheap removeObject().
  final Map<String, List<String>> _objectCells = {};

  String _cellKey(int cx, int cy) => '$cx,$cy';

  Iterable<String> _cellsForRect(Rect r) sync* {
    final cx0 = (r.left / cellSize).floor();
    final cy0 = (r.top / cellSize).floor();
    final cx1 = (r.right / cellSize).floor();
    final cy1 = (r.bottom / cellSize).floor();
    for (int x = cx0; x <= cx1; x++) {
      for (int y = cy0; y <= cy1; y++) {
        yield _cellKey(x, y);
      }
    }
  }

  /// Place [id] (with bounds [rect]) into every cell it overlaps.
  /// If [id] is already inserted, it's first removed.
  void insertObject(String id, Rect rect) {
    if (_objectCells.containsKey(id)) removeObject(id);

    final cells = _cellsForRect(rect).toList(growable: false);
    for (final k in cells) {
      (_grid[k] ??= <String, Rect>{})[id] = rect;
    }
    _objectCells[id] = cells;
  }

  /// Remove [id] from the grid. No-op if not present.
  void removeObject(String id) {
    final cells = _objectCells.remove(id);
    if (cells == null) return;
    for (final k in cells) {
      final cell = _grid[k];
      if (cell != null) {
        cell.remove(id);
        if (cell.isEmpty) _grid.remove(k);
      }
    }
  }

  /// Returns the IDs of objects whose Rects actually overlap [rect].
  /// Includes the narrowphase check, so callers get only true hits.
  List<String> queryRect(Rect rect) {
    final result = <String>{};
    for (final k in _cellsForRect(rect)) {
      final cell = _grid[k];
      if (cell == null) continue;
      for (final entry in cell.entries) {
        if (entry.value.overlaps(rect)) result.add(entry.key);
      }
    }
    return result.toList(growable: false);
  }

  /// Wipe and re-populate the grid from a fresh snapshot. Cheaper than
  /// per-object updates when the majority of objects move every frame.
  void clearAndRebuild(Map<String, Rect> objects) {
    _grid.clear();
    _objectCells.clear();
    objects.forEach(insertObject);
  }

  /// Fully clear, e.g. on level restart.
  void clear() {
    _grid.clear();
    _objectCells.clear();
  }

  int get cellCount => _grid.length;
  int get objectCount => _objectCells.length;

  @override
  void update(double dt) {
    // The grid is rebuilt by ObstacleSystem each frame via clearAndRebuild;
    // nothing to do here ourselves.
  }
}
