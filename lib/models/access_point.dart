import 'captured_point.dart';

class AccessPoint {
  final String id;
  final String label;
  final bool isRouter;
  final double dx;
  final double dy;
  final List<CapturedPoint> points;

  const AccessPoint({
    required this.id,
    required this.label,
    required this.isRouter,
    required this.dx,
    required this.dy,
    required this.points,
  });

  AccessPoint copyWith({double? dx, double? dy, List<CapturedPoint>? points}) => AccessPoint(
        id: id,
        label: label,
        isRouter: isRouter,
        dx: dx ?? this.dx,
        dy: dy ?? this.dy,
        points: points ?? this.points,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'isRouter': isRouter,
        'dx': dx,
        'dy': dy,
        'points': points.map((p) => p.toJson()).toList(),
      };

  factory AccessPoint.fromJson(Map<String, dynamic> json) => AccessPoint(
        id: json['id'] as String,
        label: json['label'] as String,
        isRouter: json['isRouter'] as bool,
        dx: (json['dx'] as num).toDouble(),
        dy: (json['dy'] as num).toDouble(),
        points: (json['points'] as List)
            .map((p) => CapturedPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}
