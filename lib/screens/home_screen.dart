import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/heatmap_session.dart';
import '../services/session_storage.dart';
import '../theme/app_theme.dart';
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
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, animation, _) => FadeTransition(
          opacity: animation,
          child: HeatmapScreen(initialSession: session),
        ),
      ),
    );
    _loadExisting();
  }

  Future<void> _continueSession() async {
    if (_existingSession == null) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, animation, _) => FadeTransition(
          opacity: animation,
          child: HeatmapScreen(initialSession: _existingSession!),
        ),
      ),
    );
    _loadExisting();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: AppTheme.heroGradient(scheme)),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(scheme: scheme),
                      const SizedBox(height: 40),
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_existingSession != null)
                                  _SessionCard(
                                    pointCount: _existingSession!.accessPoints
                                        .fold(0, (sum, ap) => sum + ap.points.length),
                                    onContinue: _continueSession,
                                  ),
                                if (_existingSession != null) const SizedBox(height: 16),
                                _NewPlanButton(
                                  hasExisting: _existingSession != null,
                                  onTap: _pickPlanAndStart,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final ColorScheme scheme;
  const _Header({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, scheme.tertiary],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: scheme.primary.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10)),
            ],
          ),
          child: const Icon(Icons.wifi_rounded, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 20),
        Text('Wifi Home Heatmap', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Recorre tu casa punto a punto y descubre dónde llega bien la señal — y dónde no.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  final int pointCount;
  final VoidCallback onContinue;

  const _SessionCard({required this.pointCount, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onContinue,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.map_rounded, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sesión en curso', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text('$pointCount puntos capturados', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewPlanButton extends StatelessWidget {
  final bool hasExisting;
  final VoidCallback onTap;

  const _NewPlanButton({required this.hasExisting, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = hasExisting ? 'Empezar con otro plano' : 'Importar plano de la casa';
    return SizedBox(
      width: double.infinity,
      child: hasExisting
          ? OutlinedButton.icon(onPressed: onTap, icon: const Icon(Icons.image_rounded), label: Text(label))
          : FilledButton.icon(onPressed: onTap, icon: const Icon(Icons.image_rounded), label: Text(label)),
    );
  }
}
