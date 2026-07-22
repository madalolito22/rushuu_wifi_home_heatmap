class CapturedPoint {
  /// Normalized position within the floor plan image, both in [0, 1].
  final double dx;
  final double dy;
  final int rssiDbm;
  final String? ssid;
  final DateTime capturedAt;

  const CapturedPoint({
    required this.dx,
    required this.dy,
    required this.rssiDbm,
    required this.ssid,
    required this.capturedAt,
  });

  Map<String, dynamic> toJson() => {
        'dx': dx,
        'dy': dy,
        'rssiDbm': rssiDbm,
        'ssid': ssid,
        'capturedAt': capturedAt.toIso8601String(),
      };

  factory CapturedPoint.fromJson(Map<String, dynamic> json) => CapturedPoint(
        dx: (json['dx'] as num).toDouble(),
        dy: (json['dy'] as num).toDouble(),
        rssiDbm: json['rssiDbm'] as int,
        ssid: json['ssid'] as String?,
        capturedAt: DateTime.parse(json['capturedAt'] as String),
      );
}
