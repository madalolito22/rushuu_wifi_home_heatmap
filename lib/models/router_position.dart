class RouterPosition {
  /// Normalized position within the floor plan image, both in [0, 1].
  final double dx;
  final double dy;

  const RouterPosition({required this.dx, required this.dy});

  Map<String, dynamic> toJson() => {'dx': dx, 'dy': dy};

  factory RouterPosition.fromJson(Map<String, dynamic> json) => RouterPosition(
        dx: (json['dx'] as num).toDouble(),
        dy: (json['dy'] as num).toDouble(),
      );
}
