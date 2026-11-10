import 'dart:async';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Why a location answer is missing.
enum LocationProblem {
  /// A position was found.
  none,

  /// The phone-wide Location switch is off.
  ///
  /// Separate from the app permission: permission can be granted while the
  /// switch is off, and then no fix can ever arrive.
  servicesOff,

  /// The user has not allowed location access.
  permissionDenied,

  /// Location access is switched off for Cue in Settings.
  permissionBlocked,

  /// The phone has no providers enabled, or no fix arrived in time.
  noFix,
}

/// One position, with whatever place name the phone could resolve.
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    this.locality,
    this.subLocality,
    this.city,
    this.state,
    this.country,
  });

  final double latitude;
  final double longitude;
  final String? locality;
  final String? subLocality;
  final String? city;
  final String? state;
  final String? country;

  /// The most specific human place name available.
  String? get placeName {
    for (final candidate in [subLocality, locality, city, state, country]) {
      final clean = candidate?.trim();
      if (clean != null && clean.isNotEmpty) return clean;
    }
    return null;
  }

  /// A second, larger place for disambiguation ("Andheri, Mumbai").
  String? get widerPlaceName {
    final primary = placeName;
    for (final candidate in [city, state]) {
      final clean = candidate?.trim();
      if (clean != null && clean.isNotEmpty && clean != primary) return clean;
    }
    return null;
  }

  /// Whether the coordinates are the only thing Cue can honestly say.
  bool get hasPlaceName => placeName != null;
}

/// Result of a "where am I" attempt.
class LocationResult {
  const LocationResult(this.fix, this.problem);

  final LocationFix? fix;
  final LocationProblem problem;
}

/// Reads the phone's position through a native channel.
///
/// Cue has no servers, so the coordinates never leave the handset. The place
/// name comes from the phone's own geocoder, which may need a network
/// connection; when it is unavailable the answer is honest coordinates instead
/// of a made-up address.
class LocationService {
  LocationService._();

  static final LocationService instance = LocationService._();

  static const MethodChannel _channel = MethodChannel('cue/location');

  /// Asks for location and waits for a fix.
  ///
  /// [timeout] covers the native wait only; permission is requested first and
  /// is not counted against it.
  Future<LocationResult> current({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    // The phone-wide switch is checked first. With it off, asking for
    // permission or waiting for a provider would only end in a misleading
    // "move near a window" answer.
    if (!await servicesEnabled()) {
      return const LocationResult(null, LocationProblem.servicesOff);
    }

    final status = await _ensurePermission();
    if (status != LocationProblem.none) {
      return LocationResult(null, status);
    }

    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('current', <String, dynamic>{
            'timeoutMs': timeout.inMilliseconds,
          })
          .timeout(timeout + const Duration(seconds: 4));
      if (raw == null) {
        return const LocationResult(null, LocationProblem.noFix);
      }

      final latitude = (raw['latitude'] as num?)?.toDouble();
      final longitude = (raw['longitude'] as num?)?.toDouble();
      if (latitude == null || longitude == null) {
        return const LocationResult(null, LocationProblem.noFix);
      }

      return LocationResult(
        LocationFix(
          latitude: latitude,
          longitude: longitude,
          locality: raw['locality'] as String?,
          subLocality: raw['subLocality'] as String?,
          city: raw['city'] as String?,
          state: raw['state'] as String?,
          country: raw['country'] as String?,
        ),
        LocationProblem.none,
      );
    } catch (_) {
      return const LocationResult(null, LocationProblem.noFix);
    }
  }

  /// Whether the phone-wide Location switch is on.
  ///
  /// Returns true when the probe itself fails, so a platform hiccup falls back
  /// to the normal "no fix" answer instead of blaming a switch that may be on.
  Future<bool> servicesEnabled() async {
    try {
      final enabled = await _channel.invokeMethod<bool>('servicesEnabled');
      return enabled ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Opens the system screen where the Location switch lives.
  ///
  /// Android does not allow an app to turn location on, so the best Cue can do
  /// is take the user straight to the switch instead of describing where it is.
  Future<bool> openLocationSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openLocationSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Cue's own settings page, where a blocked permission can be allowed.
  Future<bool> openAppSettingsPage() async {
    try {
      return await openAppSettings();
    } catch (_) {
      return false;
    }
  }

  /// Whether the phone still has to ask the user for location access.
  ///
  /// The caller speaks an explanation first, because the system dialog is
  /// silent for a blind user and would otherwise appear out of nowhere.
  Future<bool> needsPermission() async {
    try {
      final status = await Permission.locationWhenInUse.status;
      return !status.isGranted;
    } catch (_) {
      return true;
    }
  }

  Future<LocationProblem> _ensurePermission() async {
    try {
      var status = await Permission.locationWhenInUse.status;
      if (status.isGranted) return LocationProblem.none;
      if (status.isPermanentlyDenied) {
        return LocationProblem.permissionBlocked;
      }

      status = await Permission.locationWhenInUse.request();
      if (status.isGranted) return LocationProblem.none;
      return status.isPermanentlyDenied
          ? LocationProblem.permissionBlocked
          : LocationProblem.permissionDenied;
    } catch (_) {
      return LocationProblem.permissionDenied;
    }
  }
}
