import 'package:flutter/material.dart';

import '../models/captured_point.dart';
import '../theme/app_theme.dart';

/// Shared inverse-distance-weighting interpolation, used both by the
/// single-AP heatmap and the multi-AP combined view so the two stay
/// mathematically consistent.
class HeatmapMath {
  static const idwPower = 2.0;
  static const gridStep = 8.0; // pixels per cell, in canvas space — fine since the layer gets blurred afterwards
  static const fadeRadiusFraction = 0.22; // fraction of the shorter canvas side

  HeatmapMath._();

  /// Returns (interpolated quality 0..1, distance to nearest sample in px),
  /// or null if [points] is empty.
  static (double, double)? interpolate(List<CapturedPoint> points, Offset cell, Size size) {
    if (points.isEmpty) return null;

    double weightSum = 0;
    double valueSum = 0;
    double nearestDist = double.infinity;

    for (final p in points) {
      final pos = Offset(p.dx * size.width, p.dy * size.height);
      final dist = (pos - cell).distance;
      nearestDist = dist < nearestDist ? dist : nearestDist;

      if (dist < 1) {
        return (AppTheme.qualityForRssi(p.rssiDbm), 0);
      }
      final w = 1 / _pow(dist, idwPower);
      weightSum += w;
      valueSum += w * AppTheme.qualityForRssi(p.rssiDbm);
    }

    if (weightSum == 0) return null;
    return (valueSum / weightSum, nearestDist);
  }

  static double _pow(double base, double exp) {
    var result = 1.0;
    var n = exp;
    while (n > 0) {
      result *= base;
      n -= 1;
    }
    return result;
  }
}
