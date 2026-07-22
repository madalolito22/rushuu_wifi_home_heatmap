import 'access_point.dart';

class HeatmapSession {
  /// Path to the floor plan image, copied into app-local storage.
  final String planImagePath;
  final List<AccessPoint> accessPoints;

  const HeatmapSession({
    required this.planImagePath,
    required this.accessPoints,
  });

  AccessPoint? get router {
    for (final ap in accessPoints) {
      if (ap.isRouter) return ap;
    }
    return null;
  }

  List<AccessPoint> get repeaters => accessPoints.where((ap) => !ap.isRouter).toList();

  HeatmapSession copyWith({List<AccessPoint>? accessPoints}) => HeatmapSession(
        planImagePath: planImagePath,
        accessPoints: accessPoints ?? this.accessPoints,
      );

  HeatmapSession replaceAccessPoint(AccessPoint updated) => copyWith(
        accessPoints: [
          for (final ap in accessPoints) if (ap.id == updated.id) updated else ap,
        ],
      );

  Map<String, dynamic> toJson() => {
        'planImagePath': planImagePath,
        'accessPoints': accessPoints.map((a) => a.toJson()).toList(),
      };

  factory HeatmapSession.fromJson(Map<String, dynamic> json) => HeatmapSession(
        planImagePath: json['planImagePath'] as String,
        accessPoints: (json['accessPoints'] as List)
            .map((a) => AccessPoint.fromJson(a as Map<String, dynamic>))
            .toList(),
      );
}
