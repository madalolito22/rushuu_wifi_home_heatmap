import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../models/access_point.dart';
import '../models/captured_point.dart';
import '../models/heatmap_session.dart';
import '../services/session_storage.dart';
import '../services/wifi_service.dart';
import '../theme/app_theme.dart';
import '../widgets/revealed_heatmap_painter.dart';
import 'insight_screen.dart';

enum _HeatmapMenuAction { toggleLegend, moveActiveAp, deleteActiveAp, toggleFog }

/// Describes what the next tap on the plan should do: place a brand-new
/// access point ([existingApId] null) or move an existing one to a new
/// spot (keeping its measured points).
class _PendingPlacement {
  final String? existingApId;
  final bool isRouter;
  final String label;

  const _PendingPlacement({required this.existingApId, required this.isRouter, required this.label});
}

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
  bool _fogEnabled = true;
  bool _combinedView = false;
  String? _activeApId;

  _PendingPlacement? _pendingPlacement;
  Offset? _pendingTapPosition;
  _CaptureFeedback? _feedback;

  AccessPoint? get _activeAp {
    if (_activeApId == null) return null;
    for (final ap in _session.accessPoints) {
      if (ap.id == _activeApId) return ap;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _resolvePlanAspectRatio();
    if (_session.accessPoints.isEmpty) {
      _pendingPlacement = const _PendingPlacement(existingApId: null, isRouter: true, label: 'Router');
    } else {
      _activeApId = (_session.router ?? _session.accessPoints.first).id;
    }
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
    if (_pendingPlacement != null) {
      await _placeAp(localPosition, imageSize);
    } else if (!_combinedView) {
      await _capturePoint(localPosition, imageSize);
    }
  }

  Future<void> _placeAp(Offset localPosition, Size imageSize) async {
    final pending = _pendingPlacement!;
    final dx = (localPosition.dx / imageSize.width).clamp(0.0, 1.0);
    final dy = (localPosition.dy / imageSize.height).clamp(0.0, 1.0);

    HeatmapSession updated;
    String newActiveId;

    if (pending.existingApId == null) {
      final newAp = AccessPoint(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        label: pending.label,
        isRouter: pending.isRouter,
        dx: dx,
        dy: dy,
        points: const [],
      );
      updated = _session.copyWith(accessPoints: [..._session.accessPoints, newAp]);
      newActiveId = newAp.id;
    } else {
      final existing = _session.accessPoints.firstWhere((a) => a.id == pending.existingApId);
      updated = _session.replaceAccessPoint(existing.copyWith(dx: dx, dy: dy));
      newActiveId = existing.id;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _session = updated;
      _activeApId = newActiveId;
      _combinedView = false;
      _pendingPlacement = null;
      _feedback = _CaptureFeedback(message: '${pending.label} colocado', success: true, quality: 1);
    });
    await _storage.save(updated);
  }

  Future<void> _capturePoint(Offset localPosition, Size imageSize) async {
    final activeAp = _activeAp;
    if (activeAp == null || _pendingTapPosition != null) return;
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

      final updated = _session.replaceAccessPoint(activeAp.copyWith(points: [...activeAp.points, point]));
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
    final activeAp = _activeAp;
    if (activeAp == null || activeAp.points.isEmpty) return;
    final updated = _session.replaceAccessPoint(
      activeAp.copyWith(points: activeAp.points.sublist(0, activeAp.points.length - 1)),
    );
    setState(() {
      _session = updated;
      _feedback = null;
    });
    await _storage.save(updated);
  }

  Future<void> _deletePointAt(int index) async {
    final activeAp = _activeAp;
    if (activeAp == null) return;
    final point = activeAp.points[index];
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

    final points = List.of(activeAp.points)..removeAt(index);
    final updated = _session.replaceAccessPoint(activeAp.copyWith(points: points));
    setState(() => _session = updated);
    await _storage.save(updated);
  }

  void _startAddingRepeater() {
    final repeaterCount = _session.repeaters.length;
    setState(() {
      _pendingPlacement = _PendingPlacement(
        existingApId: null,
        isRouter: false,
        label: 'Repetidor ${repeaterCount + 1}',
      );
      _combinedView = false;
    });
  }

  void _startMovingActiveAp() {
    final ap = _activeAp;
    if (ap == null) return;
    setState(() {
      _pendingPlacement = _PendingPlacement(existingApId: ap.id, isRouter: ap.isRouter, label: ap.label);
    });
  }

  Future<void> _deleteActiveAp() async {
    final ap = _activeAp;
    if (ap == null || ap.isRouter) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar repetidor'),
        content: Text('¿Eliminar "${ap.label}" y sus ${ap.points.length} puntos medidos?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmed != true) return;

    final remaining = _session.accessPoints.where((a) => a.id != ap.id).toList();
    final updated = _session.copyWith(accessPoints: remaining);
    setState(() {
      _session = updated;
      _activeApId = _session.router?.id;
    });
    await _storage.save(updated);
  }

  String _placementBannerText(_PendingPlacement p) {
    if (p.existingApId != null) return 'Toca la nueva posición de "${p.label}"';
    if (p.isRouter) return 'Toca el plano donde está tu router';
    return 'Toca el plano donde está tu "${p.label}"';
  }

  @override
  Widget build(BuildContext context) {
    final activeAp = _activeAp;
    final canAddRepeater = _session.router != null && _pendingPlacement == null;

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
            tooltip: 'Deshacer último punto',
            onPressed: (_combinedView || activeAp == null || activeAp.points.isEmpty) ? null : _undoLast,
            icon: const Icon(Icons.undo_rounded),
          ),
          PopupMenuButton<_HeatmapMenuAction>(
            tooltip: 'Más opciones',
            onSelected: (action) {
              switch (action) {
                case _HeatmapMenuAction.toggleLegend:
                  setState(() => _showLegend = !_showLegend);
                case _HeatmapMenuAction.moveActiveAp:
                  _startMovingActiveAp();
                case _HeatmapMenuAction.deleteActiveAp:
                  _deleteActiveAp();
                case _HeatmapMenuAction.toggleFog:
                  setState(() => _fogEnabled = !_fogEnabled);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _HeatmapMenuAction.toggleFog,
                child: ListTile(
                  leading: Icon(_fogEnabled ? Icons.visibility_off_rounded : Icons.cloud_rounded),
                  title: Text(_fogEnabled ? 'Ver mapa completo' : 'Activar niebla'),
                ),
              ),
              PopupMenuItem(
                value: _HeatmapMenuAction.toggleLegend,
                child: ListTile(
                  leading: Icon(_showLegend ? Icons.info_rounded : Icons.info_outline_rounded),
                  title: Text(_showLegend ? 'Ocultar leyenda' : 'Mostrar leyenda'),
                ),
              ),
              PopupMenuItem(
                value: _HeatmapMenuAction.moveActiveAp,
                enabled: _pendingPlacement == null && activeAp != null && !_combinedView,
                child: ListTile(
                  leading: const Icon(Icons.open_with_rounded),
                  title: Text(activeAp == null ? 'Mover' : 'Mover "${activeAp.label}"'),
                ),
              ),
              PopupMenuItem(
                value: _HeatmapMenuAction.deleteActiveAp,
                enabled: activeAp != null && !activeAp.isRouter && !_combinedView,
                child: ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: Text(activeAp == null || activeAp.isRouter ? 'Eliminar repetidor' : 'Eliminar "${activeAp.label}"'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_session.accessPoints.isNotEmpty)
            IgnorePointer(
              ignoring: _pendingPlacement != null,
              child: Opacity(
                opacity: _pendingPlacement != null ? 0.4 : 1,
                child: _ApSwitcher(
                  accessPoints: _session.accessPoints,
                  activeApId: _activeApId,
                  combinedView: _combinedView,
                  canAddRepeater: canAddRepeater,
                  onSelectAp: (id) => setState(() {
                    _activeApId = id;
                    _combinedView = false;
                  }),
                  onSelectCombined: () => setState(() => _combinedView = true),
                  onAddRepeater: _startAddingRepeater,
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _planAspectRatio == null
                      ? const Center(child: CircularProgressIndicator())
                      : _PlanCanvas(
                          planImagePath: _session.planImagePath,
                          aspectRatio: _planAspectRatio!,
                          pointGroups: _combinedView
                              ? _session.accessPoints.map((a) => a.points).toList()
                              : [activeAp?.points ?? const []],
                          displayPoints: _combinedView
                              ? _session.accessPoints.expand((a) => a.points).toList()
                              : (activeAp?.points ?? const []),
                          anchors: _combinedView
                              ? _session.accessPoints
                              : (activeAp == null ? const [] : [activeAp]),
                          showAnchorLabels: _combinedView,
                          pendingTapPosition: _pendingTapPosition,
                          fogEnabled: _fogEnabled,
                          onTapImage: _handleTap,
                          onDeletePoint: _combinedView ? null : _deletePointAt,
                        ),
                ),
                if (_pendingPlacement != null)
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: SafeArea(
                      bottom: false,
                      child: _PlacementBanner(
                        text: _placementBannerText(_pendingPlacement!),
                        canCancel: _session.accessPoints.isNotEmpty,
                        onCancel: () => setState(() => _pendingPlacement = null),
                      ),
                    ),
                  ),
                if (_showLegend)
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: const _SignalLegend(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _BottomBar(
            pointCount: _combinedView
                ? _session.accessPoints.fold(0, (sum, a) => sum + a.points.length)
                : (activeAp?.points.length ?? 0),
            feedback: _feedback,
            hintText: _combinedView
                ? 'Vista combinada: comparando la cobertura de todos tus puntos de acceso'
                : 'Toca el plano donde estás para medir la señal ahí',
          ),
        ],
      ),
    );
  }
}

class _ApSwitcher extends StatelessWidget {
  final List<AccessPoint> accessPoints;
  final String? activeApId;
  final bool combinedView;
  final bool canAddRepeater;
  final void Function(String apId) onSelectAp;
  final VoidCallback onSelectCombined;
  final VoidCallback onAddRepeater;

  const _ApSwitcher({
    required this.accessPoints,
    required this.activeApId,
    required this.combinedView,
    required this.canAddRepeater,
    required this.onSelectAp,
    required this.onSelectCombined,
    required this.onAddRepeater,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final ap in accessPoints)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(ap.label),
                avatar: Icon(ap.isRouter ? Icons.router_rounded : Icons.settings_input_antenna_rounded, size: 18),
                selected: !combinedView && activeApId == ap.id,
                onSelected: (_) => onSelectAp(ap.id),
              ),
            ),
          if (accessPoints.length >= 2)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: const Text('Vista combinada'),
                avatar: const Icon(Icons.layers_rounded, size: 18),
                selected: combinedView,
                onSelected: (_) => onSelectCombined(),
              ),
            ),
          if (canAddRepeater)
            ActionChip(
              label: const Text('Añadir repetidor'),
              avatar: const Icon(Icons.add_rounded, size: 18),
              onPressed: onAddRepeater,
            ),
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
  final List<List<CapturedPoint>> pointGroups;
  final List<CapturedPoint> displayPoints;
  final List<AccessPoint> anchors;
  final bool showAnchorLabels;
  final Offset? pendingTapPosition;
  final bool fogEnabled;
  final void Function(Offset localPosition, Size imageSize) onTapImage;
  final void Function(int index)? onDeletePoint;

  const _PlanCanvas({
    required this.planImagePath,
    required this.aspectRatio,
    required this.pointGroups,
    required this.displayPoints,
    required this.anchors,
    required this.showAnchorLabels,
    required this.pendingTapPosition,
    required this.fogEnabled,
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
                    // The plan itself (walls, room labels) is always fully
                    // visible — fog only ever hides the colored signal data
                    // on top of it, never the map you need to navigate by.
                    Image.file(File(planImagePath), fit: BoxFit.fill),
                    // Blurring the interpolation grid turns its discrete cells
                    // into a smooth continuous gradient instead of a visible
                    // mosaic of squares; it also softens the fog reveal edge.
                    ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10, tileMode: TileMode.decal),
                      child: CustomPaint(
                        painter: RevealedHeatmapPainter(
                          pointGroups: pointGroups,
                          anchors: anchors.map((a) => Offset(a.dx, a.dy)).toList(),
                          fogEnabled: fogEnabled,
                        ),
                      ),
                    ),
                    for (var i = 0; i < displayPoints.length; i++)
                      Positioned(
                        left: displayPoints[i].dx * size.width - 10,
                        top: displayPoints[i].dy * size.height - 10,
                        child: onDeletePoint == null
                            ? _PointMarker(quality: AppTheme.qualityForRssi(displayPoints[i].rssiDbm))
                            : GestureDetector(
                                onLongPress: () => onDeletePoint!(i),
                                child: _PointMarker(quality: AppTheme.qualityForRssi(displayPoints[i].rssiDbm)),
                              ),
                      ),
                    for (final ap in anchors)
                      Positioned(
                        left: ap.dx * size.width - 18,
                        top: ap.dy * size.height - 18,
                        child: _ApAnchorMarker(ap: ap, showLabel: showAnchorLabels),
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

/// Distinct landmark marker for a router or repeater, so it's never
/// confused with a signal-quality measurement dot.
class _ApAnchorMarker extends StatelessWidget {
  final AccessPoint ap;
  final bool showLabel;

  const _ApAnchorMarker({required this.ap, required this.showLabel});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ap.isRouter ? scheme.primary : scheme.tertiary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Icon(
        ap.isRouter ? Icons.router_rounded : Icons.settings_input_antenna_rounded,
        color: Colors.white,
        size: 20,
      ),
    );

    if (!showLabel) return icon;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
          child: Text(ap.label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _PlacementBanner extends StatelessWidget {
  final String text;
  final bool canCancel;
  final VoidCallback onCancel;

  const _PlacementBanner({required this.text, required this.canCancel, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.touch_app_rounded, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          if (canCancel) TextButton(onPressed: onCancel, child: const Text('Cancelar')),
        ],
      ),
    );
  }
}

class _SignalLegend extends StatelessWidget {
  const _SignalLegend();

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${AppTheme.bestRssiDbm}', style: labelStyle?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Container(
            width: 56,
            height: 8,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.signalStrong, AppTheme.signalMid, AppTheme.signalWeak],
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 6),
          Text('${AppTheme.worstRssiDbm} dBm', style: labelStyle?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int pointCount;
  final _CaptureFeedback? feedback;
  final String hintText;

  const _BottomBar({required this.pointCount, required this.feedback, required this.hintText});

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
                  feedback?.message ?? hintText,
                  key: ValueKey(feedback?.message ?? hintText),
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
