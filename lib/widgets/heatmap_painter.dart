import 'package:flutter/material.dart';

import '../models/captured_point.dart';
import '../theme/app_theme.dart';
import 'heatmap_math.dart';

/// Paints a coverage heatmap for a single access point's measurements,
/// using inverse-distance-weighted interpolation. Cells far from any
/// measurement fade out rather than extrapolating a confident color.
class HeatmapPainter extends CustomPainter {
  final List<CapturedPoint> points;

  HeatmapPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final fadeRadius = size.shortestSide * HeatmapMath.fadeRadiusFraction;
    final paint = Paint()..style = PaintingStyle.fill;

    for (double y = 0; y < size.height; y += HeatmapMath.gridStep) {
      for (double x = 0; x < size.width; x += HeatmapMath.gridStep) {
        final cellCenter = Offset(x + HeatmapMath.gridStep / 2, y + HeatmapMath.gridStep / 2);
        final result = HeatmapMath.interpolate(points, cellCenter, size);
        if (result == null) continue;

        final (value, nearestDist) = result;
        final alpha = (1 - (nearestDist / fadeRadius)).clamp(0.0, 1.0);
        if (alpha <= 0.02) continue;

        paint.color = AppTheme.colorForQuality(value).withValues(alpha: alpha * 0.65);
        canvas.drawRect(Rect.fromLTWH(x, y, HeatmapMath.gridStep, HeatmapMath.gridStep), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant HeatmapPainter oldDelegate) => oldDelegate.points != points;
}
