import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const WifiHeatmapApp());
}

class WifiHeatmapApp extends StatelessWidget {
  const WifiHeatmapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wifi Home Heatmap',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
