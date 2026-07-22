import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/heatmap_session.dart';
import '../services/session_storage.dart';
import 'heatmap_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storage = SessionStorage();
  final _picker = ImagePicker();
  HeatmapSession? _existingSession;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    HeatmapSession? session;
    try {
      session = await _storage.load();
    } catch (_) {
      session = null;
    }
    if (!mounted) return;
    setState(() {
      _existingSession = session;
      _loading = false;
    });
  }

  Future<void> _pickPlanAndStart() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final session = await _storage.startNewSession(picked.path);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HeatmapScreen(initialSession: session)),
    );
    _loadExisting();
  }

  Future<void> _continueSession() async {
    if (_existingSession == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HeatmapScreen(initialSession: _existingSession!)),
    );
    _loadExisting();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Wifi Home Heatmap')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi, size: 72),
              const SizedBox(height: 16),
              const Text(
                'Importa el plano de tu casa y toca cada punto donde midas la señal para ir generando el mapa de calor.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_existingSession != null) ...[
                FilledButton.icon(
                  onPressed: _continueSession,
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Continuar sesión (${_existingSession!.points.length} puntos)'),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: _pickPlanAndStart,
                icon: const Icon(Icons.image),
                label: Text(_existingSession == null ? 'Importar plano de la casa' : 'Empezar con otro plano'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
