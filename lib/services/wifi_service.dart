import 'dart:io';

import 'package:flutter/services.dart';

class WifiSignalReading {
  final bool connected;
  final String? ssid;
  final int? rssiDbm;

  const WifiSignalReading({required this.connected, this.ssid, this.rssiDbm});

  static const disconnected = WifiSignalReading(connected: false);
}

/// Reads the RSSI (signal strength in dBm) of the currently connected wifi
/// network. Implementation differs per platform since neither Android nor
/// Linux expose this the same way, and there is no cross-platform package
/// that covers both.
class WifiService {
  static const _channel = MethodChannel('rushuu_wifi_home_heatmap/wifi');

  Future<WifiSignalReading> readSignal() {
    if (Platform.isAndroid) return _readAndroid();
    if (Platform.isLinux) return _readLinux();
    throw UnsupportedError('WifiService is only implemented for Android and Linux.');
  }

  Future<WifiSignalReading> _readAndroid() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('getSignalInfo');
    if (result == null || result['connected'] != true) {
      return WifiSignalReading.disconnected;
    }
    return WifiSignalReading(
      connected: true,
      ssid: result['ssid'] as String?,
      rssiDbm: result['rssiDbm'] as int?,
    );
  }

  /// Linux desktops don't need a native platform channel: we can shell out
  /// to NetworkManager / iw directly, since Flutter desktop apps run with
  /// normal process privileges.
  Future<WifiSignalReading> _readLinux() async {
    final device = await _activeWifiDevice();
    if (device == null) return WifiSignalReading.disconnected;

    final link = await Process.run('iw', ['dev', device, 'link']);
    final output = link.stdout as String;
    if (output.contains('Not connected')) return WifiSignalReading.disconnected;

    final signalMatch = RegExp(r'signal:\s*(-?\d+)\s*dBm').firstMatch(output);
    final ssidMatch = RegExp(r'SSID:\s*(.+)').firstMatch(output);

    final rssi = signalMatch != null ? int.tryParse(signalMatch.group(1)!) : null;
    if (rssi == null) return WifiSignalReading.disconnected;

    return WifiSignalReading(
      connected: true,
      ssid: ssidMatch?.group(1)?.trim(),
      rssiDbm: rssi,
    );
  }

  Future<String?> _activeWifiDevice() async {
    final status = await Process.run('nmcli', ['-t', '-f', 'DEVICE,TYPE,STATE', 'dev', 'status']);
    final lines = (status.stdout as String).split('\n');
    for (final line in lines) {
      final parts = line.split(':');
      if (parts.length >= 3 && parts[1] == 'wifi' && parts[2] == 'connected') {
        return parts[0];
      }
    }
    return null;
  }
}
