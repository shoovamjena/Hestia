import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Resolves the device's current coordinates with emulator-friendly fallbacks.
class LocationAcquisitionService {
  static Future<Position?> acquirePosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception(
        'Location services are disabled. Please turn on GPS and try again.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw Exception('Location permission is required.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. Enable it in app settings.',
      );
    }

    final attempts = <Future<Position?> Function()>[
      if (!kIsWeb && Platform.isAndroid) _androidForceManagerFix,
      _standardLowAccuracyFix,
      _lastKnownFix,
      _positionStreamFix,
    ];

    for (final attempt in attempts) {
      final position = await attempt();
      if (position != null) {
        debugPrint(
          'Location acquired: ${position.latitude}, ${position.longitude}',
        );
        return position;
      }
    }

    return null;
  }

  /// Uses the legacy LocationManager API — more reliable on Android emulators.
  static Future<Position?> _androidForceManagerFix() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 20),
          forceLocationManager: true,
        ),
      ).timeout(const Duration(seconds: 22));
    } catch (e) {
      debugPrint('Android forceLocationManager fix failed: $e');
      return null;
    }
  }

  static Future<Position?> _standardLowAccuracyFix() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.lowest,
          timeLimit: Duration(seconds: 20),
        ),
      ).timeout(const Duration(seconds: 22));
    } catch (e) {
      debugPrint('Standard low-accuracy fix failed: $e');
      return null;
    }
  }

  static Future<Position?> _lastKnownFix() async {
    try {
      return await Geolocator.getLastKnownPosition().timeout(
        const Duration(seconds: 5),
      );
    } catch (e) {
      debugPrint('Last known position failed: $e');
      return null;
    }
  }

  /// Some emulators only emit a fix through the position stream after
  /// "Set location" is pressed in Extended Controls.
  static Future<Position?> _positionStreamFix() async {
    try {
      final stream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.lowest,
          distanceFilter: 0,
          timeLimit: Duration(seconds: 20),
        ),
      );

      return await stream.first.timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('Position stream fix failed: $e');
      return null;
    }
  }
}
