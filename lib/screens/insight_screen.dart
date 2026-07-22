import 'dart:math';

import 'package:flutter/material.dart';

import '../models/heatmap_session.dart';
import '../services/insight_generator.dart';
import '../theme/app_theme.dart';

class InsightScreen extends StatelessWidget {
  final HeatmapSession session;

  const InsightScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final report = InsightGenerator().generate(session);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [Text('Análisis con IA'), SizedBox(width: 6), Text('✨')],
        ),
      ),
      body: report.totalPoints == 0
          ? _EmptyState(tip: report.tips.first)
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ScoreGauge(score: report.qualityScore, verdict: report.verdict),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          label: 'Cobertura buena',
                          value: '${report.coveragePercent}%',
                          icon: Icons.wifi_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatTile(
                          label: 'Puntos débiles',
                          value: '${report.weakPointCount}',
                          icon: Icons.warning_amber_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatTile(
                          label: 'Medidos',
                          value: '${report.totalPoints}',
                          icon: Icons.location_on_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text('Recomendaciones', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  ...report.tips.map((tip) => _TipCard(text: tip)),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Confianza del análisis: ${report.confidencePercent}% · '
                      'estimación calculada a partir de tus mediciones, no es una IA de verdad',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String tip;
  const _EmptyState({required this.tip});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(tip, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _ScoreGauge extends StatelessWidget {
  final int score;
  final WifiVerdict verdict;

  const _ScoreGauge({required this.score, required this.verdict});

  static const _labels = {
    WifiVerdict.excellent: 'Excelente',
    WifiVerdict.good: 'Buena',
    WifiVerdict.mediocre: 'Mejorable',
    WifiVerdict.poor: 'Deficiente',
    WifiVerdict.noData: 'Sin datos',
  };

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.colorForQuality(score / 100);
    return Center(
      child: SizedBox(
        width: 220,
        height: 220,
        child: CustomPaint(
          painter: _GaugePainter(score: score, color: color, trackColor: Theme.of(context).colorScheme.surfaceContainerHighest),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$score', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 44, color: color)),
                const SizedBox(height: 4),
                Text(_labels[verdict]!, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final int score;
  final Color color;
  final Color trackColor;

  _GaugePainter({required this.score, required this.color, required this.trackColor});

  static const _startAngle = 0.75 * pi; // 135°
  static const _sweep = 1.5 * pi; // 270°

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _startAngle, _sweep, false, track);

    final progress = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _startAngle, _sweep * (score / 100).clamp(0.0, 1.0), false, progress);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.score != score || oldDelegate.color != color;
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatTile({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, color: scheme.primary),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  final String text;
  const _TipCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: scheme.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
            ],
          ),
        ),
      ),
    );
  }
}
