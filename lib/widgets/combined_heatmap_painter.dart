import 'package:flutter/material.dart';

import '../models/captured_point.dart';
import '../theme/app_theme.dart';
import 'heatmap_math.dart';

/// Paints the combined coverage of several access points. Each AP's
/// measurements are interpolated independently (they're different radios
/// with independent propagation, so pooling all points into a single IDW
/// would incorrectly blend them into one fictitious transmitter); this
/// then shows, per cell, whichever AP gives the best signal there — i.e.
/// "how well does the network as a whole cover this spot".
class CombinedHeatmapPainter extends CustomPainter {
  final List<List<CapturedPoint>> apPointGroups;

  CombinedHeatmapPainter(this.apPointGroups);

  @override
  void paint(Canvas canvas, Size size) {
    final groups = apPointGroups.where((g) => g.isNotEmpty).toList();
    if (groups.isEmpty) return;

    final fadeRadius = size.shortestSide * HeatmapMath.fadeRadiusFraction;
    final paint = Paint()..style = PaintingStyle.fill;

    for (double y = 0; y < size.height; y += HeatmapMath.gridStep) {
      for (double x = 0; x < size.width; x += HeatmapMath.gridStep) {
        final cellCenter = Offset(x + HeatmapMath.gridStep / 2, y + HeatmapMath.gridStep / 2);

        double? bestScore;
        double bestQuality = 0;
        double bestAlpha = 0;

        for (final group in groups) {
          final result = HeatmapMath.interpolate(group, cellCenter, size);
          if (result == null) continue;
          final (quality, nearestDist) = result;
          final alpha = (1 - (nearestDist / fadeRadius)).clamp(0.0, 1.0);
          if (alpha <= 0.02) continue;

          final score = quality * alpha;
          if (bestScore == null || score > bestScore) {
            bestScore = score;
            bestQuality = quality;
            bestAlpha = alpha;
          }
        }

        if (bestScore == null) continue;
        paint.color = AppTheme.colorForQuality(bestQuality).withValues(alpha: bestAlpha * 0.65);
        canvas.drawRect(Rect.fromLTWH(x, y, HeatmapMath.gridStep, HeatmapMath.gridStep), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CombinedHeatmapPainter oldDelegate) => oldDelegate.apPointGroups != apPointGroups;
}
