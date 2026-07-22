import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Result of checking/requesting the location permission Android requires
/// to reveal the connected network's SSID (RSSI itself doesn't need it).
enum LocationPermissionResult { granted, denied, permanentlyDenied, notApplicable }

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

  /// Android hides the connected SSID (returns a placeholder) unless the
  /// app holds a granted location permission, even though the manifest
  /// declares it — the OS still requires the runtime grant. Not applicable
  /// on Linux, which has no such restriction.
  Future<LocationPermissionResult> checkLocationPermissionStatus() async {
    if (!Platform.isAndroid) return LocationPermissionResult.notApplicable;
    final status = await Permission.locationWhenInUse.status;
    return _mapStatus(status);
  }

  Future<LocationPermissionResult> requestLocationPermission() async {
    if (!Platform.isAndroid) return LocationPermissionResult.notApplicable;
    final status = await Permission.locationWhenInUse.request();
    return _mapStatus(status);
  }

  LocationPermissionResult _mapStatus(PermissionStatus status) {
    if (status.isGranted) return LocationPermissionResult.granted;
    if (status.isPermanentlyDenied) return LocationPermissionResult.permanentlyDenied;
    return LocationPermissionResult.denied;
  }

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
