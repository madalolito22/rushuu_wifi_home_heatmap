import 'package:flutter/material.dart';

import '../models/captured_point.dart';
import 'combined_heatmap_painter.dart';
import 'heatmap_painter.dart';

/// Wraps the heatmap (single-AP or combined) with an optional "fog of war"
/// mask: the colored signal-quality overlay only shows in a soft circle
/// around each measured point and each AP anchor. The base floor plan image
/// underneath is never touched by this — you always see the walls and room
/// labels so you know where to tap next, only the *data* is hidden until
/// you've actually measured that spot.
class RevealedHeatmapPainter extends CustomPainter {
  /// One list per access point. A single-element list renders as a normal
  /// single-AP heatmap; more than one renders the combined "best AP here"
  /// view via [CombinedHeatmapPainter].
  final List<List<CapturedPoint>> pointGroups;
  final List<Offset> anchors;
  final bool fogEnabled;

  RevealedHeatmapPainter({required this.pointGroups, required this.anchors, required this.fogEnabled});

  static const _pointRevealFraction = 0.20;
  static const _anchorRevealFraction = 0.12;

  @override
  void paint(Canvas canvas, Size size) {
    void paintHeatmap() {
      if (pointGroups.length <= 1) {
        HeatmapPainter(pointGroups.isEmpty ? const [] : pointGroups.first).paint(canvas, size);
      } else {
        CombinedHeatmapPainter(pointGroups).paint(canvas, size);
      }
    }

    if (!fogEnabled) {
      paintHeatmap();
      return;
    }

    final fullRect = Offset.zero & size;

    // Layer 1: the heatmap itself, composited onto the real destination
    // normally once this outer layer is restored.
    canvas.saveLayer(fullRect, Paint());
    paintHeatmap();

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
    for (final group in pointGroups) {
      for (final p in group) {
        drawReveal(Offset(p.dx * size.width, p.dy * size.height), revealRadius);
      }
    }
    for (final anchor in anchors) {
      drawReveal(
        Offset(anchor.dx * size.width, anchor.dy * size.height),
        size.shortestSide * _anchorRevealFraction,
      );
    }
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RevealedHeatmapPainter oldDelegate) =>
      oldDelegate.pointGroups != pointGroups ||
      oldDelegate.anchors != anchors ||
      oldDelegate.fogEnabled != fogEnabled;
}
