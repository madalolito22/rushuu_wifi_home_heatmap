import 'dart:math';

import '../models/heatmap_session.dart';
import '../theme/app_theme.dart';
import 'repeater_suggester.dart';

enum WifiVerdict { noData, poor, mediocre, good, excellent }

class InsightReport {
  final WifiVerdict verdict;
  final int qualityScore; // 0..100
  final int coveragePercent; // % of points with acceptable-or-better signal
  final int weakPointCount;
  final int totalPoints;
  final int confidencePercent; // playful "how much to trust this" stat
  final List<String> tips;
  final RepeaterSuggestion? repeaterSuggestion;

  const InsightReport({
    required this.verdict,
    required this.qualityScore,
    required this.coveragePercent,
    required this.weakPointCount,
    required this.totalPoints,
    required this.confidencePercent,
    required this.tips,
    this.repeaterSuggestion,
  });
}

/// Turns the raw captured points + router position into a friendly
/// "verdict" about wifi coverage. It's plain arithmetic over real
/// measurements dressed up as an insight, not a real ML model.
class InsightGenerator {
  static const _weakThresholdDbm = -75;
  static const _goodQualityThreshold = 0.5;

  InsightReport generate(HeatmapSession session) {
    final points = session.accessPoints.expand((ap) => ap.points).toList();
    if (points.isEmpty) {
      return const InsightReport(
        verdict: WifiVerdict.noData,
        qualityScore: 0,
        coveragePercent: 0,
        weakPointCount: 0,
        totalPoints: 0,
        confidencePercent: 0,
        tips: ['Captura algunos puntos por la casa para que el análisis tenga algo que decir.'],
      );
    }

    final qualities = points.map((p) => AppTheme.qualityForRssi(p.rssiDbm)).toList();
    final avgQuality = qualities.reduce((a, b) => a + b) / qualities.length;
    final qualityScore = (avgQuality * 100).round();

    final goodPoints = qualities.where((q) => q >= _goodQualityThreshold).length;
    final coveragePercent = ((goodPoints / points.length) * 100).round();
    final weakPointCount = points.where((p) => p.rssiDbm <= _weakThresholdDbm).length;

    final confidence = min(97, 45 + points.length * 4);
    final repeaterSuggestion = RepeaterSuggester().suggest(session);

    final tips = <String>[];

    final router = session.router;
    if (router == null) {
      tips.add('Coloca el router en el plano para que el análisis tenga en cuenta su posición.');
    } else if (session.repeaters.isEmpty) {
      final dx = router.dx - 0.5;
      final dy = router.dy - 0.5;
      final offCenter = sqrt(dx * dx + dy * dy);
      if (offCenter > 0.32) {
        tips.add('El router está bastante desplazado hacia un lado de la casa; centrarlo podría repartir mejor la señal.');
      }
    }

    if (repeaterSuggestion != null) {
      tips.add(
        'Un repetidor en el punto sugerido podría subir la cobertura buena de '
        '${repeaterSuggestion.coverageBeforePercent}% a ${repeaterSuggestion.coverageAfterPercent}%.',
      );
    } else if (weakPointCount > 0) {
      tips.add(
        'Hay $weakPointCount ${weakPointCount == 1 ? 'punto' : 'puntos'} con señal débil (≤ $_weakThresholdDbm dBm); '
        'un repetidor cerca de esa zona ayudaría.',
      );
    }

    if (points.length < 6) {
      tips.add('Con más puntos medidos el análisis será más fiable.');
    }

    if (tips.isEmpty) {
      tips.add('La cobertura es sólida en toda la zona medida. Buen trabajo.');
    }

    return InsightReport(
      verdict: _verdictFor(qualityScore),
      qualityScore: qualityScore,
      coveragePercent: coveragePercent,
      weakPointCount: weakPointCount,
      totalPoints: points.length,
      confidencePercent: confidence,
      tips: tips.take(3).toList(),
      repeaterSuggestion: repeaterSuggestion,
    );
  }

  WifiVerdict _verdictFor(int score) {
    if (score >= 80) return WifiVerdict.excellent;
    if (score >= 60) return WifiVerdict.good;
    if (score >= 40) return WifiVerdict.mediocre;
    return WifiVerdict.poor;
  }
}
