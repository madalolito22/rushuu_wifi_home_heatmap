import 'captured_point.dart';

class HeatmapSession {
  /// Path to the floor plan image, copied into app-local storage.
  final String planImagePath;
  final List<CapturedPoint> points;

  const HeatmapSession({
    required this.planImagePath,
    required this.points,
  });

  HeatmapSession copyWith({List<CapturedPoint>? points}) => HeatmapSession(
        planImagePath: planImagePath,
        points: points ?? this.points,
      );

  Map<String, dynamic> toJson() => {
        'planImagePath': planImagePath,
        'points': points.map((p) => p.toJson()).toList(),
      };

  factory HeatmapSession.fromJson(Map<String, dynamic> json) => HeatmapSession(
        planImagePath: json['planImagePath'] as String,
        points: (json['points'] as List)
            .map((p) => CapturedPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}
