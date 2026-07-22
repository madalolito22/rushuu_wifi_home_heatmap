import 'package:flutter/material.dart';

import '../models/captured_point.dart';
import '../models/router_position.dart';
import 'heatmap_painter.dart';

/// Wraps [HeatmapPainter] with an optional "fog of war" mask: the colored
/// signal-quality overlay only shows in a soft circle around each measured
/// point (and a smaller one around the router). The base floor plan image
/// underneath is never touched by this — you always see the walls and room
/// labels so you know where to tap next, only the *data* is hidden until
/// you've actually measured that spot.
class RevealedHeatmapPainter extends CustomPainter {
  final List<CapturedPoint> points;
  final RouterPosition? routerPosition;
  final bool fogEnabled;

  RevealedHeatmapPainter({required this.points, required this.routerPosition, required this.fogEnabled});

  static const _pointRevealFraction = 0.20;
  static const _routerRevealFraction = 0.12;

  @override
  void paint(Canvas canvas, Size size) {
    if (!fogEnabled) {
      HeatmapPainter(points).paint(canvas, size);
      return;
    }

    final fullRect = Offset.zero & size;

    // Layer 1: the heatmap itself, composited onto the real destination
    // normally once this outer layer is restored.
    canvas.saveLayer(fullRect, Paint());
    HeatmapPainter(points).paint(canvas, size);

    // Layer 2: the reveal mask (soft union of circles). Composited onto
    // layer 1 via dstIn on restore, which keeps layer 1's pixels only
    // where this mask is opaque and erases the rest.
    canvas.saveLayer(fullRect, Paint()..blendMode = BlendMode.dstIn);
    void drawReveal(Offset center, double radius) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final paint = Paint()
        ..shader = const RadialGradient(
          colors: [Colors.white, Colors.transparent],
          stops: [0.5, 1.0],
        ).createShader(rect);
      canvas.drawCircle(center, radius, paint);
    }

    final revealRadius = size.shortestSide * _pointRevealFraction;
    for (final p in points) {
      drawReveal(Offset(p.dx * size.width, p.dy * size.height), revealRadius);
    }
    if (routerPosition != null) {
      drawReveal(
        Offset(routerPosition!.dx * size.width, routerPosition!.dy * size.height),
        size.shortestSide * _routerRevealFraction,
      );
    }
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RevealedHeatmapPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.routerPosition != routerPosition ||
      oldDelegate.fogEnabled != fogEnabled;
}
