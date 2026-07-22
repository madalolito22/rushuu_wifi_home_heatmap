import 'package:flutter/material.dart';

import '../models/captured_point.dart';

/// Paints a coverage heatmap over a floor plan using inverse-distance-weighted
/// interpolation between captured points. Cells far from any measurement
/// fade out rather than extrapolating a confident color.
class HeatmapPainter extends CustomPainter {
  final List<CapturedPoint> points;
  static const _gridStep = 14.0; // pixels per cell, in canvas space
  static const _idwPower = 2.0;
  static const _fadeRadiusFraction = 0.22; // fraction of the shorter canvas side

  HeatmapPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final fadeRadius = size.shortestSide * _fadeRadiusFraction;
    final paint = Paint()..style = PaintingStyle.fill;

    for (double y = 0; y < size.height; y += _gridStep) {
      for (double x = 0; x < size.width; x += _gridStep) {
        final cellCenter = Offset(x + _gridStep / 2, y + _gridStep / 2);
        final result = _interpolate(cellCenter, size);
        if (result == null) continue;

        final (value, nearestDist) = result;
        final alpha = (1 - (nearestDist / fadeRadius)).clamp(0.0, 1.0);
        if (alpha <= 0.02) continue;

        paint.color = _colorForQuality(value).withValues(alpha: alpha * 0.65);
        canvas.drawRect(Rect.fromLTWH(x, y, _gridStep, _gridStep), paint);
      }
    }
  }

  /// Returns (interpolated quality 0..1, distance to nearest sample in px).
  (double, double)? _interpolate(Offset cell, Size size) {
    double weightSum = 0;
    double valueSum = 0;
    double nearestDist = double.infinity;

    for (final p in points) {
      final pos = Offset(p.dx * size.width, p.dy * size.height);
      final dist = (pos - cell).distance;
      nearestDist = dist < nearestDist ? dist : nearestDist;

      if (dist < 1) {
        return (_qualityFor(p.rssiDbm), 0);
      }
      final w = 1 / _pow(dist, _idwPower);
      weightSum += w;
      valueSum += w * _qualityFor(p.rssiDbm);
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

  /// Maps RSSI in dBm to a 0..1 quality scale. -30 dBm (excellent) -> 1.0,
  /// -85 dBm (unusable) -> 0.0.
  double _qualityFor(int rssiDbm) {
    const best = -30.0;
    const worst = -85.0;
    return ((rssiDbm - worst) / (best - worst)).clamp(0.0, 1.0);
  }

  Color _colorForQuality(double quality) {
    // Red (bad) -> yellow -> green (good), via HSV hue 0..120.
    final hue = quality * 120.0;
    return HSVColor.fromAHSV(1.0, hue, 0.85, 0.95).toColor();
  }

  @override
  bool shouldRepaint(covariant HeatmapPainter oldDelegate) => oldDelegate.points != points;
}
