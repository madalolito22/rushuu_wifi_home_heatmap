import 'dart:io';

import 'package:flutter/material.dart';

import '../models/captured_point.dart';
import '../models/heatmap_session.dart';
import '../services/session_storage.dart';
import '../services/wifi_service.dart';
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
  String? _lastMessage;

  Future<void> _capturePoint(Offset localPosition, Size imageSize) async {
    if (_capturing) return;
    setState(() => _capturing = true);

    try {
      final reading = await _wifiService.readSignal();
      if (!reading.connected || reading.rssiDbm == null) {
        setState(() => _lastMessage = 'No hay wifi conectado ahora mismo.');
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
        _lastMessage = '${reading.rssiDbm} dBm capturado (${reading.ssid ?? 'red desconocida'})';
      });
      await _storage.save(updated);
    } finally {
      setState(() => _capturing = false);
    }
  }

  Future<void> _undoLast() async {
    if (_session.points.isEmpty) return;
    final updated = _session.copyWith(points: _session.points.sublist(0, _session.points.length - 1));
    setState(() => _session = updated);
    await _storage.save(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de cobertura wifi'),
        actions: [
          IconButton(
            tooltip: 'Deshacer último punto',
            onPressed: _session.points.isEmpty ? null : _undoLast,
            icon: const Icon(Icons.undo),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_lastMessage != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(_lastMessage!),
            ),
          Expanded(
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
                            left: p.dx * constraints.maxWidth - 4,
                            top: p.dy * constraints.maxHeight - 4,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.black87,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                        if (_capturing)
                          const Positioned.fill(
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              '${_session.points.length} puntos capturados. Toca el plano en el sitio donde estás para medir la señal ahí.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
