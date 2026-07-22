import 'dart:ui' show Offset;

import '../models/access_point.dart';
import '../models/captured_point.dart';
import '../models/heatmap_session.dart';
import '../theme/app_theme.dart';

class RepeaterSuggestion {
  /// Normalized position within the floor plan image, both in [0, 1].
  final double dx;
  final double dy;
  final int weakPointCount;
  final int coverageBeforePercent;
  final int coverageAfterPercent;

  const RepeaterSuggestion({
    required this.dx,
    required this.dy,
    required this.weakPointCount,
    required this.coverageBeforePercent,
    required this.coverageAfterPercent,
  });
}

/// Computes where the *next* repeater would actually help, from real
/// measurements across every access point you already have (router and any
/// existing repeaters) — not a fabricated location. It finds the weighted
/// centroid of the weak points in the combined coverage, then places the
/// suggestion partway between the *nearest existing AP* and that centroid
/// (a repeater sitting right in the dead zone would itself have bad signal
/// and have nothing to repeat), and simulates the coverage improvement
/// using the same IDW model the heatmap itself uses to render the
/// interpolated signal.
class RepeaterSuggester {
  static const _goodQualityThreshold = 0.5;
  static const _nearestApFraction = 0.6;
  static const _minPointsRequired = 4;

  RepeaterSuggestion? suggest(HeatmapSession session) {
    final accessPoints = session.accessPoints;
    final points = accessPoints.expand((ap) => ap.points).toList();
    if (points.length < _minPointsRequired || accessPoints.isEmpty) return null;

    final qualities = <CapturedPoint, double>{
      for (final p in points) p: AppTheme.qualityForRssi(p.rssiDbm),
    };
    final weakPoints = points.where((p) => qualities[p]! < _goodQualityThreshold).toList();
    if (weakPoints.isEmpty) return null;

    double weightSum = 0, cx = 0, cy = 0;
    for (final p in weakPoints) {
      final w = 1 - qualities[p]!;
      weightSum += w;
      cx += w * p.dx;
      cy += w * p.dy;
    }
    cx /= weightSum;
    cy /= weightSum;
    final weakCentroid = Offset(cx, cy);

    final nearestAp = _nearestAccessPoint(accessPoints, weakCentroid);
    final anchor = Offset(nearestAp.dx, nearestAp.dy);

    final suggestedDx = (anchor.dx + _nearestApFraction * (weakCentroid.dx - anchor.dx)).clamp(0.0, 1.0);
    final suggestedDy = (anchor.dy + _nearestApFraction * (weakCentroid.dy - anchor.dy)).clamp(0.0, 1.0);
    final repeaterPos = Offset(suggestedDx, suggestedDy);

    final coverageBefore = _coveragePercent(qualities.values);

    final afterQualities = points.map((p) {
      return _predictWithRepeater(
        target: Offset(p.dx, p.dy),
        others: points.where((o) => o != p),
        qualities: qualities,
        repeaterPos: repeaterPos,
      );
    });
    final coverageAfter = _coveragePercent(afterQualities);

    return RepeaterSuggestion(
      dx: suggestedDx,
      dy: suggestedDy,
      weakPointCount: weakPoints.length,
      coverageBeforePercent: coverageBefore,
      coverageAfterPercent: coverageAfter,
    );
  }

  AccessPoint _nearestAccessPoint(List<AccessPoint> accessPoints, Offset target) {
    var nearest = accessPoints.first;
    var nearestDist = (Offset(nearest.dx, nearest.dy) - target).distance;
    for (final ap in accessPoints.skip(1)) {
      final dist = (Offset(ap.dx, ap.dy) - target).distance;
      if (dist < nearestDist) {
        nearest = ap;
        nearestDist = dist;
      }
    }
    return nearest;
  }

  int _coveragePercent(Iterable<double> qualities) {
    final list = qualities.toList();
    if (list.isEmpty) return 0;
    final good = list.where((q) => q >= _goodQualityThreshold).length;
    return ((good / list.length) * 100).round();
  }

  /// Predicts the quality a spot would measure if the repeater existed,
  /// via inverse-distance weighting over every other real measurement plus
  /// a virtual sample at the repeater's position assuming it regenerates
  /// a full-strength signal.
  double _predictWithRepeater({
    required Offset target,
    required Iterable<CapturedPoint> others,
    required Map<CapturedPoint, double> qualities,
    required Offset repeaterPos,
  }) {
    double weightSum = 0;
    double valueSum = 0;
    void addSample(Offset pos, double quality) {
      final dist = (pos - target).distance;
      final w = 1 / (dist * dist + 0.0001);
      weightSum += w;
      valueSum += w * quality;
    }

    for (final o in others) {
      addSample(Offset(o.dx, o.dy), qualities[o]!);
    }
    addSample(repeaterPos, 1.0);

    return weightSum == 0 ? 0 : valueSum / weightSum;
  }
}
