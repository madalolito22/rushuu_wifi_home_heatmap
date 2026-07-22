import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/captured_point.dart';
import '../models/heatmap_session.dart';
import '../services/session_storage.dart';
import '../services/wifi_service.dart';
import '../theme/app_theme.dart';
import '../widgets/heatmap_painter.dart';

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
  bool _capturing = false;
  _CaptureFeedback? _feedback;

  Future<void> _capturePoint(Offset localPosition, Size imageSize) async {
    if (_capturing) return;
    setState(() {
      _capturing = true;
      _feedback = null;
    });

    try {
      final reading = await _wifiService.readSignal();
      if (!reading.connected || reading.rssiDbm == null) {
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
      setState(() => _capturing = false);
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Mapa de cobertura'),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(color: scheme.surface.withValues(alpha: 0.55)),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Deshacer último punto',
            onPressed: _session.points.isEmpty ? null : _undoLast,
            icon: const Icon(Icons.undo_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              maxScale: 4,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onTapUp: (details) => _capturePoint(
                      details.localPosition,
                      Size(constraints.maxWidth, constraints.maxHeight),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(_session.planImagePath), fit: BoxFit.fill),
                        CustomPaint(painter: HeatmapPainter(_session.points)),
                        ..._session.points.map(
                          (p) => Positioned(
                            left: p.dx * constraints.maxWidth - 7,
                            top: p.dy * constraints.maxHeight - 7,
                            child: _PointMarker(quality: AppTheme.qualityForRssi(p.rssiDbm)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          if (_capturing)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.08),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + kToolbarHeight + 12,
            right: 16,
            child: const _SignalLegend(),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _BottomBar(pointCount: _session.points.length, feedback: _feedback),
          ),
        ],
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
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: AppTheme.colorForQuality(quality),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4, offset: const Offset(0, 1))],
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
          Text('débil', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int pointCount;
  final _CaptureFeedback? feedback;

  const _BottomBar({required this.pointCount, required this.feedback});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Icon(
            feedback == null
                ? Icons.touch_app_rounded
                : (feedback!.success ? Icons.check_circle_rounded : Icons.error_outline_rounded),
            color: feedback == null
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : (feedback!.success ? AppTheme.colorForQuality(feedback!.quality) : AppTheme.signalWeak),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                feedback?.message ?? 'Toca el plano donde estás para medir la señal ahí',
                key: ValueKey(feedback?.message),
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
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$pointCount',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: child,
        ),
      ),
    );
  }
}
