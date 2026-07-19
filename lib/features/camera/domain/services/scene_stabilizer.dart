import 'package:pov_agent/features/camera/domain/entities/detection.dart';
import 'package:pov_agent/features/camera/domain/entities/normalized_box.dart';
import 'package:pov_agent/shared/domain/scene_region.dart';
import 'package:pov_agent/shared/domain/scene_snapshot.dart';
import 'package:pov_agent/shared/domain/tracked_object.dart';

const _historyLength = 5;
const _minimumPresenceCount = 3;
const _maximumMissCount = 3;
const _minimumMatchOverlap = 0.5;
const _overlapComparisonTolerance = 1e-12;
const _overlapQuantizationScale = 1000000;

/// Converts serial detection frames into stable semantic scene changes.
///
/// One instance owns one runtime session. It preserves IDs across [reset] so
/// consumers cannot confuse a later object with an earlier object from the
/// same session. Calls are synchronous and must arrive in frame order.
final class SceneStabilizer {
  /// Creates an empty stabilizer for a runtime session.
  SceneStabilizer();

  final List<_ObjectTrack> _tracks = <_ObjectTrack>[];
  SceneSnapshot _current = const SceneSnapshot.empty();
  int _nextTrackId = 1;

  /// The last published stable scene.
  SceneSnapshot get current => _current;

  /// Processes one frame and returns a snapshot only for a semantic change.
  ///
  /// Bounding-box and confidence jitter stays internal. Appearance,
  /// disappearance, label changes, and confirmed 3×3 region changes are
  /// observable. A new region requires three matching observations; misses
  /// neither advance nor discard that positional evidence.
  SceneSnapshot? processFrame(List<Detection> detections) {
    final canonicalDetections = List<Detection>.of(detections)..sort(_compareDetections);
    final matches = _matchExistingTracks(canonicalDetections);
    final matchedTracks = <_ObjectTrack>{};
    final matchedDetectionIndexes = <int>{};

    for (final match in matches) {
      match.track.recordDetection(canonicalDetections[match.detectionIndex]);
      matchedTracks.add(match.track);
      matchedDetectionIndexes.add(match.detectionIndex);
    }

    final tracksBeforeThisFrame = List<_ObjectTrack>.of(_tracks);
    for (final track in tracksBeforeThisFrame) {
      if (matchedTracks.contains(track)) {
        continue;
      }
      track.recordMiss();
      if (track.shouldDisappearAfterCurrentMiss) {
        _tracks.remove(track);
      }
    }

    for (var index = 0; index < canonicalDetections.length; index += 1) {
      if (matchedDetectionIndexes.contains(index)) {
        continue;
      }
      _tracks.add(
        _ObjectTrack(
          id: _nextTrackId,
          firstDetection: canonicalDetections[index],
        ),
      );
      _nextTrackId += 1;
    }

    return _publishIfSceneChanged();
  }

  /// Clears all tracking evidence and publishes empty only when necessary.
  ///
  /// The next ID is deliberately retained because reset starts a new tracking
  /// epoch inside the same runtime session rather than a new session.
  SceneSnapshot? reset() {
    _tracks.clear();
    if (_current.isEmpty) {
      return null;
    }
    return _current = const SceneSnapshot.empty();
  }

  List<_TrackMatch> _matchExistingTracks(List<Detection> detections) {
    final tracks = List<_ObjectTrack>.of(_tracks)..sort((left, right) => left.id.compareTo(right.id));
    final tracksByClass = <int, List<_ObjectTrack>>{};
    for (final track in tracks) {
      tracksByClass.putIfAbsent(track.classId, () => []).add(track);
    }
    final detectionIndexesByClass = <int, List<int>>{};
    for (var index = 0; index < detections.length; index += 1) {
      detectionIndexesByClass.putIfAbsent(detections[index].classId, () => []).add(index);
    }

    final classIds = tracksByClass.keys.where(detectionIndexesByClass.containsKey).toList()..sort();
    final matches = <_TrackMatch>[];
    for (final classId in classIds) {
      final classTracks = tracksByClass[classId]!;
      final detectionIndexes = detectionIndexesByClass[classId]!;
      final candidates = List.generate(
        classTracks.length,
        (_) => List<_MatchCandidate?>.filled(detectionIndexes.length, null),
      );
      for (var trackIndex = 0; trackIndex < classTracks.length; trackIndex += 1) {
        final track = classTracks[trackIndex];
        for (var detectionRank = 0; detectionRank < detectionIndexes.length; detectionRank += 1) {
          final detectionIndex = detectionIndexes[detectionRank];
          final overlap = track.lastBox.intersectionOverUnion(detections[detectionIndex].box);
          // Decimal plugin coordinates can place a mathematical 0.5 one floating
          // point step below the policy boundary.
          if (overlap + _overlapComparisonTolerance < _minimumMatchOverlap) {
            continue;
          }
          candidates[trackIndex][detectionRank] = _MatchCandidate(
            track: track,
            detectionIndex: detectionIndex,
            overlap: overlap,
          );
        }
      }
      matches.addAll(
        _OptimalClassAssignment(
          tracks: classTracks,
          candidates: candidates,
        ).solve(),
      );
    }
    return matches;
  }

  SceneSnapshot? _publishIfSceneChanged() {
    final next = SceneSnapshot(
      objects: _tracks.where((track) => track.isStable).map((track) => track.toTrackedObject()),
    );
    if (next == _current) {
      return null;
    }
    _current = next;
    return next;
  }
}

final class _ObjectTrack {
  _ObjectTrack({required this.id, required Detection firstDetection})
    : classId = firstDetection.classId,
      _label = firstDetection.label,
      _lastBox = firstDetection.box,
      _recentPresence = <bool>[true];

  final int id;
  final int classId;
  final List<bool> _recentPresence;
  String _label;
  NormalizedBox _lastBox;
  bool _isStable = false;
  SceneRegion? _publishedRegion;
  SceneRegion? _pendingRegion;
  int _pendingRegionObservationCount = 0;

  NormalizedBox get lastBox => _lastBox;

  bool get isStable => _isStable;

  bool get shouldDisappearAfterCurrentMiss {
    return _recentPresence.where((present) => !present).length >= _maximumMissCount;
  }

  void recordDetection(Detection detection) {
    _label = detection.label;
    _lastBox = detection.box;
    _appendPresence(present: true);
    final observedRegion = _regionOf(detection.box);
    if (!_isStable && _recentPresence.where((present) => present).length >= _minimumPresenceCount) {
      _isStable = true;
      _publishedRegion = observedRegion;
      return;
    }
    if (_isStable) _recordRegionObservation(observedRegion);
  }

  void recordMiss() {
    _appendPresence(present: false);
  }

  TrackedObject toTrackedObject() {
    final publishedRegion = _publishedRegion;
    if (publishedRegion == null) {
      throw StateError('A stable track must have a published scene region.');
    }
    return TrackedObject(
      id: id,
      classId: classId,
      label: _label,
      region: publishedRegion,
    );
  }

  void _recordRegionObservation(SceneRegion observedRegion) {
    if (observedRegion == _publishedRegion) {
      _clearPendingRegion();
      return;
    }
    if (observedRegion != _pendingRegion) {
      _pendingRegion = observedRegion;
      _pendingRegionObservationCount = 1;
      return;
    }

    _pendingRegionObservationCount += 1;
    if (_pendingRegionObservationCount < _minimumPresenceCount) return;
    _publishedRegion = observedRegion;
    _clearPendingRegion();
  }

  void _clearPendingRegion() {
    _pendingRegion = null;
    _pendingRegionObservationCount = 0;
  }

  void _appendPresence({required bool present}) {
    _recentPresence.add(present);
    if (_recentPresence.length > _historyLength) {
      _recentPresence.removeAt(0);
    }
  }
}

SceneRegion _regionOf(NormalizedBox box) {
  return SceneRegion.fromNormalizedPoint(x: box.centerX, y: box.centerY);
}

final class _MatchCandidate {
  const _MatchCandidate({
    required this.track,
    required this.detectionIndex,
    required this.overlap,
  });

  final _ObjectTrack track;
  final int detectionIndex;
  final double overlap;
}

final class _TrackMatch {
  const _TrackMatch({required this.track, required this.detectionIndex});

  final _ObjectTrack track;
  final int detectionIndex;
}

/// Finds the optimal one-to-one assignment for detections of one class.
///
/// The Hungarian algorithm is cubic in the larger partition. Its tuple score
/// compares cardinality, stable tracks, quantized IoU, matched lower track IDs,
/// and a deterministic pairing preference derived from canonical detection
/// order, without large integer weights or floating sums.
final class _OptimalClassAssignment {
  _OptimalClassAssignment({
    required this.tracks,
    required this.candidates,
  });

  final List<_ObjectTrack> tracks;
  final List<List<_MatchCandidate?>> candidates;

  List<_TrackMatch> solve() {
    if (tracks.isEmpty || candidates.first.isEmpty) return const [];
    final detectionCount = candidates.first.length;
    final assignmentSize = tracks.length > detectionCount ? tracks.length : detectionCount;
    final rowToColumn = _minimumCostAssignment(assignmentSize);
    final matches = <_TrackMatch>[];
    for (var trackIndex = 0; trackIndex < tracks.length; trackIndex += 1) {
      final detectionRank = rowToColumn[trackIndex];
      if (detectionRank >= detectionCount) continue;
      final candidate = candidates[trackIndex][detectionRank];
      if (candidate == null) continue;
      matches.add(
        _TrackMatch(
          track: candidate.track,
          detectionIndex: candidate.detectionIndex,
        ),
      );
    }
    return matches;
  }

  List<int> _minimumCostAssignment(int size) {
    final rowPotentials = List<_AssignmentScore>.filled(size + 1, _AssignmentScore.zero);
    final columnPotentials = List<_AssignmentScore>.filled(size + 1, _AssignmentScore.zero);
    final columnToRow = List<int>.filled(size + 1, 0);
    final predecessorColumns = List<int>.filled(size + 1, 0);

    for (var row = 1; row <= size; row += 1) {
      columnToRow[0] = row;
      var currentColumn = 0;
      final minimumReducedCosts = List<_AssignmentScore?>.filled(size + 1, null);
      final usedColumns = List<bool>.filled(size + 1, false);
      do {
        usedColumns[currentColumn] = true;
        final currentRow = columnToRow[currentColumn];
        _AssignmentScore? delta;
        var nextColumn = 0;
        for (var column = 1; column <= size; column += 1) {
          if (usedColumns[column]) continue;
          final reducedCost =
              -_scoreAt(currentRow - 1, column - 1) - rowPotentials[currentRow] - columnPotentials[column];
          final existingCost = minimumReducedCosts[column];
          if (existingCost == null || reducedCost.compareTo(existingCost) < 0) {
            minimumReducedCosts[column] = reducedCost;
            predecessorColumns[column] = currentColumn;
          }
          final candidateDelta = minimumReducedCosts[column]!;
          if (delta == null || candidateDelta.compareTo(delta) < 0) {
            delta = candidateDelta;
            nextColumn = column;
          }
        }
        if (delta == null) {
          throw StateError('A square assignment must have an augmenting column.');
        }
        for (var column = 0; column <= size; column += 1) {
          if (usedColumns[column]) {
            final assignedRow = columnToRow[column];
            rowPotentials[assignedRow] = rowPotentials[assignedRow] + delta;
            columnPotentials[column] = columnPotentials[column] - delta;
          } else {
            final reducedCost = minimumReducedCosts[column];
            if (reducedCost != null) {
              minimumReducedCosts[column] = reducedCost - delta;
            }
          }
        }
        currentColumn = nextColumn;
      } while (columnToRow[currentColumn] != 0);

      do {
        final previousColumn = predecessorColumns[currentColumn];
        columnToRow[currentColumn] = columnToRow[previousColumn];
        currentColumn = previousColumn;
      } while (currentColumn != 0);
    }

    final rowToColumn = List<int>.filled(size, 0);
    for (var column = 1; column <= size; column += 1) {
      rowToColumn[columnToRow[column] - 1] = column - 1;
    }
    return rowToColumn;
  }

  _AssignmentScore _scoreAt(int trackIndex, int detectionRank) {
    if (trackIndex >= tracks.length || detectionRank >= candidates.first.length) {
      return _AssignmentScore.zero;
    }
    final candidate = candidates[trackIndex][detectionRank];
    if (candidate == null) return _AssignmentScore.zero;
    final trackPreference = tracks.length - trackIndex;
    final detectionPreference = candidates.first.length - detectionRank;
    return _AssignmentScore(
      matchCount: 1,
      stableMatchCount: candidate.track.isStable ? 1 : 0,
      quantizedOverlap: (candidate.overlap * _overlapQuantizationScale).round(),
      trackPreference: trackPreference,
      canonicalPairPreference: trackPreference * detectionPreference,
    );
  }
}

final class _AssignmentScore implements Comparable<_AssignmentScore> {
  const _AssignmentScore({
    required this.matchCount,
    required this.stableMatchCount,
    required this.quantizedOverlap,
    required this.trackPreference,
    required this.canonicalPairPreference,
  });

  static const zero = _AssignmentScore(
    matchCount: 0,
    stableMatchCount: 0,
    quantizedOverlap: 0,
    trackPreference: 0,
    canonicalPairPreference: 0,
  );

  final int matchCount;
  final int stableMatchCount;
  final int quantizedOverlap;
  final int trackPreference;
  final int canonicalPairPreference;

  _AssignmentScore operator +(_AssignmentScore other) {
    return _AssignmentScore(
      matchCount: matchCount + other.matchCount,
      stableMatchCount: stableMatchCount + other.stableMatchCount,
      quantizedOverlap: quantizedOverlap + other.quantizedOverlap,
      trackPreference: trackPreference + other.trackPreference,
      canonicalPairPreference: canonicalPairPreference + other.canonicalPairPreference,
    );
  }

  _AssignmentScore operator -(_AssignmentScore other) {
    return _AssignmentScore(
      matchCount: matchCount - other.matchCount,
      stableMatchCount: stableMatchCount - other.stableMatchCount,
      quantizedOverlap: quantizedOverlap - other.quantizedOverlap,
      trackPreference: trackPreference - other.trackPreference,
      canonicalPairPreference: canonicalPairPreference - other.canonicalPairPreference,
    );
  }

  _AssignmentScore operator -() {
    return _AssignmentScore(
      matchCount: -matchCount,
      stableMatchCount: -stableMatchCount,
      quantizedOverlap: -quantizedOverlap,
      trackPreference: -trackPreference,
      canonicalPairPreference: -canonicalPairPreference,
    );
  }

  @override
  int compareTo(_AssignmentScore other) {
    final matchOrder = matchCount.compareTo(other.matchCount);
    if (matchOrder != 0) return matchOrder;
    final stableOrder = stableMatchCount.compareTo(other.stableMatchCount);
    if (stableOrder != 0) return stableOrder;
    final overlapOrder = quantizedOverlap.compareTo(other.quantizedOverlap);
    if (overlapOrder != 0) return overlapOrder;
    final trackOrder = trackPreference.compareTo(other.trackPreference);
    if (trackOrder != 0) return trackOrder;
    return canonicalPairPreference.compareTo(other.canonicalPairPreference);
  }
}

int _compareDetections(Detection left, Detection right) {
  final classOrder = left.classId.compareTo(right.classId);
  if (classOrder != 0) {
    return classOrder;
  }
  final labelOrder = left.label.compareTo(right.label);
  if (labelOrder != 0) {
    return labelOrder;
  }
  final leftOrder = left.box.left.compareTo(right.box.left);
  if (leftOrder != 0) {
    return leftOrder;
  }
  final topOrder = left.box.top.compareTo(right.box.top);
  if (topOrder != 0) {
    return topOrder;
  }
  final rightOrder = left.box.right.compareTo(right.box.right);
  if (rightOrder != 0) {
    return rightOrder;
  }
  final bottomOrder = left.box.bottom.compareTo(right.box.bottom);
  if (bottomOrder != 0) {
    return bottomOrder;
  }
  return right.confidence.compareTo(left.confidence);
}
