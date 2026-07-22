import 'captured_point.dart';
import 'router_position.dart';

class HeatmapSession {
  /// Path to the floor plan image, copied into app-local storage.
  final String planImagePath;
  final List<CapturedPoint> points;
  final RouterPosition? routerPosition;

  const HeatmapSession({
    required this.planImagePath,
    required this.points,
    this.routerPosition,
  });

  HeatmapSession copyWith({List<CapturedPoint>? points, RouterPosition? routerPosition}) => HeatmapSession(
        planImagePath: planImagePath,
        points: points ?? this.points,
        routerPosition: routerPosition ?? this.routerPosition,
      );

  Map<String, dynamic> toJson() => {
        'planImagePath': planImagePath,
        'points': points.map((p) => p.toJson()).toList(),
        'routerPosition': routerPosition?.toJson(),
      };

  factory HeatmapSession.fromJson(Map<String, dynamic> json) => HeatmapSession(
        planImagePath: json['planImagePath'] as String,
        points: (json['points'] as List)
            .map((p) => CapturedPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
        routerPosition: json['routerPosition'] != null
            ? RouterPosition.fromJson(json['routerPosition'] as Map<String, dynamic>)
            : null,
      );
}
