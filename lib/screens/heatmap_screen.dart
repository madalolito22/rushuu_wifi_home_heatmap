import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../models/captured_point.dart';
import '../models/heatmap_session.dart';
import '../models/router_position.dart';
import '../services/session_storage.dart';
import '../services/wifi_service.dart';
import '../theme/app_theme.dart';
import '../widgets/heatmap_painter.dart';
import 'insight_screen.dart';

class HeatmapScreen extends StatefulWidget {
  final HeatmapSession initialSession;

  const HeatmapScreen({super.key, required this.initialSession});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  final _wifiService = WifiService();
  final _storage = SessionStorage();
  late HeatmapSession _session = widget.initialSession;
  double? _planAspectRatio;
  bool _showLegend = false;

  /// True while the next tap on the plan should place the router marker
  /// instead of capturing a signal reading. Starts true when a session has
  /// no router yet, since that's the first thing you need to mark.
  late bool _placingRouter = _session.routerPosition == null;

  /// Position of an in-flight capture, shown as a small local spinner
  /// instead of dimming the whole screen so the user can keep walking
  /// and tapping without losing sight of the plan.
  Offset? _pendingTapPosition;
  _CaptureFeedback? _feedback;

  @override
  void initState() {
    super.initState();
    _resolvePlanAspectRatio();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLocationPermission());
  }

  /// Android hides the real SSID unless location permission is granted at
  /// runtime, regardless of what the manifest declares. Ask once per visit,
  /// with a plain-language rationale first so the OS prompt isn't a surprise.
  Future<void> _ensureLocationPermission() async {
    final status = await _wifiService.checkLocationPermissionStatus();
    if (status != LocationPermissionResult.denied || !mounted) return;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permiso de ubicación'),
        content: const Text(
          'Android exige el permiso de ubicación para poder leer el nombre (SSID) de la red wifi conectada. '
          'La app no usa tu posición GPS, solo necesita el permiso para esa lectura.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Ahora no')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Conceder')),
        ],
      ),
    );
    if (proceed != true) return;

    final result = await _wifiService.requestLocationPermission();
    if (result != LocationPermissionResult.permanentlyDenied || !mounted) return;

    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permiso bloqueado'),
        content: const Text(
          'Denegaste el permiso de forma permanente. Puedes concederlo desde los ajustes de la app para ver el SSID de la red.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cerrar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Abrir ajustes')),
        ],
      ),
    );
    if (openSettings == true) await openAppSettings();
  }

  /// Reads the plan image's real pixel dimensions so it can be displayed
  /// with correct proportions (an AspectRatio box) instead of being
  /// stretched to whatever shape the screen happened to be.
  Future<void> _resolvePlanAspectRatio() async {
    final bytes = await File(_session.planImagePath).readAsBytes();
    final image = await decodeImageFromList(bytes);
    if (!mounted) return;
    setState(() => _planAspectRatio = image.width / image.height);
  }

  Future<void> _handleTap(Offset localPosition, Size imageSize) async {
    if (_placingRouter) {
      await _placeRouter(localPosition, imageSize);
    } else {
      await _capturePoint(localPosition, imageSize);
    }
  }

  Future<void> _placeRouter(Offset localPosition, Size imageSize) async {
    final position = RouterPosition(
      dx: (localPosition.dx / imageSize.width).clamp(0.0, 1.0),
      dy: (localPosition.dy / imageSize.height).clamp(0.0, 1.0),
    );
    final updated = _session.copyWith(routerPosition: position);
    HapticFeedback.mediumImpact();
    setState(() {
      _session = updated;
      _placingRouter = false;
      _feedback = const _CaptureFeedback(message: 'Router colocado', success: true, quality: 1);
    });
    await _storage.save(updated);
  }

  Future<void> _capturePoint(Offset localPosition, Size imageSize) async {
    if (_pendingTapPosition != null) return;
    setState(() {
      _pendingTapPosition = localPosition;
      _feedback = null;
    });

    try {
      final reading = await _wifiService.readSignal();
      if (!mounted) return;

      if (!reading.connected || reading.rssiDbm == null) {
        HapticFeedback.selectionClick();
        setState(() => _feedback = const _CaptureFeedback(
              message: 'No hay wifi conectado ahora mismo',
              success: false,
            ));
        return;
      }

      final point = CapturedPoint(
        dx: (localPosition.dx / imageSize.width).clamp(0.0, 1.0),
        dy: (localPosition.dy / imageSize.height).clamp(0.0, 1.0),
        rssiDbm: reading.rssiDbm!,
        ssid: reading.ssid,
        capturedAt: DateTime.now(),
      );

      final updated = _session.copyWith(points: [..._session.points, point]);
      HapticFeedback.lightImpact();
      setState(() {
        _session = updated;
        _feedback = _CaptureFeedback(
          message: '${reading.rssiDbm} dBm · ${reading.ssid ?? 'red desconocida'}',
          success: true,
          quality: AppTheme.qualityForRssi(reading.rssiDbm!),
        );
      });
      await _storage.save(updated);
    } finally {
      if (mounted) setState(() => _pendingTapPosition = null);
    }
  }

  Future<void> _undoLast() async {
    if (_session.points.isEmpty) return;
    final updated = _session.copyWith(points: _session.points.sublist(0, _session.points.length - 1));
    setState(() {
      _session = updated;
      _feedback = null;
    });
    await _storage.save(updated);
  }

  Future<void> _deletePointAt(int index) async {
    final point = _session.points[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar punto'),
        content: Text('¿Quitar la medición de ${point.rssiDbm} dBm en este sitio?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmed != true) return;

    final points = List.of(_session.points)..removeAt(index);
    final updated = _session.copyWith(points: points);
    setState(() => _session = updated);
    await _storage.save(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de cobertura'),
        actions: [
          IconButton(
            tooltip: 'Análisis con IA',
            icon: const Icon(Icons.auto_awesome_rounded),
            onPressed: () => Navigator.of(context).push(
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 300),
                pageBuilder: (_, animation, _) => FadeTransition(
                  opacity: animation,
                  child: InsightScreen(session: _session),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: _session.routerPosition == null ? 'Colocar router' : 'Mover router',
            onPressed: _placingRouter ? null : () => setState(() => _placingRouter = true),
            isSelected: _placingRouter,
            icon: const Icon(Icons.router_outlined),
            selectedIcon: const Icon(Icons.router_rounded),
          ),
          IconButton(
            tooltip: 'Leyenda de señal',
            onPressed: () => setState(() => _showLegend = !_showLegend),
            isSelected: _showLegend,
            icon: const Icon(Icons.info_outline_rounded),
            selectedIcon: const Icon(Icons.info_rounded),
          ),
          IconButton(
            tooltip: 'Deshacer último punto',
            onPressed: _session.points.isEmpty ? null : _undoLast,
            icon: const Icon(Icons.undo_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _planAspectRatio == null
                      ? const Center(child: CircularProgressIndicator())
                      : _PlanCanvas(
                          planImagePath: _session.planImagePath,
                          aspectRatio: _planAspectRatio!,
                          points: _session.points,
                          routerPosition: _session.routerPosition,
                          pendingTapPosition: _pendingTapPosition,
                          placingRouter: _placingRouter,
                          onTapImage: _handleTap,
                          onDeletePoint: _deletePointAt,
                        ),
                ),
                if (_placingRouter)
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: SafeArea(
                      bottom: false,
                      child: _RouterPlacementBanner(
                        canCancel: _session.routerPosition != null,
                        onCancel: () => setState(() => _placingRouter = false),
                      ),
                    ),
                  ),
                if (_showLegend)
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12, right: 12),
                        child: const _SignalLegend(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _BottomBar(pointCount: _session.points.length, feedback: _feedback, placingRouter: _placingRouter),
        ],
      ),
    );
  }
}

/// Renders the floor plan at its true aspect ratio (centered, letterboxed
/// if needed) so it's never stretched, and keeps tap/marker coordinates
/// mapped to that same box regardless of screen orientation.
class _PlanCanvas extends StatelessWidget {
  final String planImagePath;
  final double aspectRatio;
  final List<CapturedPoint> points;
  final RouterPosition? routerPosition;
  final Offset? pendingTapPosition;
  final bool placingRouter;
  final void Function(Offset localPosition, Size imageSize) onTapImage;
  final void Function(int index) onDeletePoint;

  const _PlanCanvas({
    required this.planImagePath,
    required this.aspectRatio,
    required this.points,
    required this.routerPosition,
    required this.pendingTapPosition,
    required this.placingRouter,
    required this.onTapImage,
    required this.onDeletePoint,
  });

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      maxScale: 4,
      child: Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                onTapUp: (details) => onTapImage(details.localPosition, size),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(planImagePath), fit: BoxFit.fill),
                    CustomPaint(painter: HeatmapPainter(points)),
                    for (var i = 0; i < points.length; i++)
                      Positioned(
                        left: points[i].dx * size.width - 10,
                        top: points[i].dy * size.height - 10,
                        child: GestureDetector(
                          onLongPress: () => onDeletePoint(i),
                          child: _PointMarker(quality: AppTheme.qualityForRssi(points[i].rssiDbm)),
                        ),
                      ),
                    if (routerPosition != null)
                      Positioned(
                        left: routerPosition!.dx * size.width - 18,
                        top: routerPosition!.dy * size.height - 18,
                        child: IgnorePointer(ignoring: placingRouter, child: const _RouterMarker()),
                      ),
                    if (pendingTapPosition != null)
                      Positioned(
                        left: pendingTapPosition!.dx - 12,
                        top: pendingTapPosition!.dy - 12,
                        child: const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CaptureFeedback {
  final String message;
  final bool success;
  final double quality;

  const _CaptureFeedback({required this.message, required this.success, this.quality = 0});
}

class _PointMarker extends StatelessWidget {
  final double quality;
  const _PointMarker({required this.quality});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: AppTheme.colorForQuality(quality),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4, offset: const Offset(0, 1))],
        ),
      ),
    );
  }
}

/// Distinct landmark marker for the router, so it's never confused with a
/// signal-quality measurement dot.
class _RouterMarker extends StatelessWidget {
  const _RouterMarker();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: const Icon(Icons.router_rounded, color: Colors.white, size: 20),
    );
  }
}

class _RouterPlacementBanner extends StatelessWidget {
  final bool canCancel;
  final VoidCallback onCancel;

  const _RouterPlacementBanner({required this.canCancel, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.router_rounded, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Toca el plano donde está el router',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (canCancel)
            TextButton(onPressed: onCancel, child: const Text('Cancelar')),
        ],
      ),
    );
  }
}

class _SignalLegend extends StatelessWidget {
  const _SignalLegend();

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('Señal', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          Container(
            width: 14,
            height: 70,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppTheme.signalStrong, AppTheme.signalMid, AppTheme.signalWeak],
              ),
              borderRadius: BorderRadius.circular(7),
            ),
          ),
          const SizedBox(height: 6),
          Text('fuerte', style: Theme.of(context).textTheme.labelSmall),
          Text('${AppTheme.bestRssiDbm} dBm', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text('débil', style: Theme.of(context).textTheme.labelSmall),
          Text('${AppTheme.worstRssiDbm} dBm', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int pointCount;
  final _CaptureFeedback? feedback;
  final bool placingRouter;

  const _BottomBar({required this.pointCount, required this.feedback, required this.placingRouter});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
        ),
        child: Row(
          children: [
            Icon(
              feedback == null
                  ? Icons.touch_app_rounded
                  : (feedback!.success ? Icons.check_circle_rounded : Icons.error_outline_rounded),
              color: feedback == null
                  ? scheme.onSurfaceVariant
                  : (feedback!.success ? AppTheme.colorForQuality(feedback!.quality) : AppTheme.signalWeak),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  feedback?.message ??
                      (placingRouter
                          ? 'Toca el plano donde está el router'
                          : 'Toca el plano donde estás para medir la señal ahí'),
                  key: ValueKey(feedback?.message ?? placingRouter),
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$pointCount',
                style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const _GlassCard({required this.child, required this.padding});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: child,
    );
  }
}
