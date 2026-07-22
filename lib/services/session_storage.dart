import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/heatmap_session.dart';

/// Persists a single active heatmap session (floor plan + captured points)
/// to the app's local documents directory.
class SessionStorage {
  static const _sessionFileName = 'session.json';
  static const _planFileName = 'plan_image';

  Future<Directory> _appDir() => getApplicationDocumentsDirectory();

  Future<File> _sessionFile() async {
    final dir = await _appDir();
    return File('${dir.path}/$_sessionFileName');
  }

  Future<HeatmapSession?> load() async {
    final file = await _sessionFile();
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return HeatmapSession.fromJson(json);
  }

  Future<void> save(HeatmapSession session) async {
    final file = await _sessionFile();
    await file.writeAsString(jsonEncode(session.toJson()));
  }

  /// Copies a picked plan image into local storage and starts a fresh
  /// session (discarding any previously captured points).
  Future<HeatmapSession> startNewSession(String pickedImagePath) async {
    final dir = await _appDir();
    final extension = pickedImagePath.split('.').last;
    final destPath = '${dir.path}/$_planFileName.$extension';
    await File(pickedImagePath).copy(destPath);

    final session = HeatmapSession(planImagePath: destPath, accessPoints: const []);
    await save(session);
    return session;
  }
}
