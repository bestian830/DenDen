import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:dart_geohash/dart_geohash.dart';
import 'package:permission_handler/permission_handler.dart';

/// Location service with privacy protection via Geohash
/// CRITICAL: Geohash precision is 5 (~5km radius) for privacy
class LocationService {
  static const int _geohashPrecision = 5; // DO NOT CHANGE - Privacy requirement

  /// Request location permission (lazy - only when called)
  /// Returns true if granted, false otherwise
  /// Works with both Precise and Approximate (Coarse) location on Android 12+
  static Future<bool> requestLocationPermission() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('📍 Location services disabled');
        return false;
      }

      // Request permission using permission_handler
      // This works with both precise and approximate location
      var status = await Permission.locationWhenInUse.request();
      
      if (status.isGranted) {
        debugPrint('📍 Location permission granted');
        return true;
      }
      
      debugPrint('📍 Location permission denied: $status');
      return false;
    } catch (e) {
      debugPrint('📍 Permission error: $e');
      return false;
    }
  }

  /// Get current location as a Nostr tag
  /// Returns ['g', geohash, cityName] or null if failed
  /// 
  /// Fallback chain for city name:
  /// 1. locality (city)
  /// 2. administrativeArea (province/state)
  /// 3. "Location" (fallback string)
  static Future<List<String>?> getCurrentLocationTag() async {
    try {
      // Get GPS coordinates (works with Coarse location too)
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low, // Low accuracy is fine for 5km geohash
        timeLimit: const Duration(seconds: 5), // 5 second timeout - don't make user wait forever
      );

      debugPrint('📍 Got position: ${position.latitude}, ${position.longitude}');

      // CRITICAL: Encode to Geohash with precision 5 (~5km radius)
      // dart_geohash 2.x API: use constructor + substring for precision control
      final hasher = GeoHasher();
      final fullHash = hasher.encode(position.longitude, position.latitude); // Note: lon first, lat second
      final geoHash = fullHash.substring(0, _geohashPrecision); // Truncate to 5 chars
      
      debugPrint('📍 Geohash (precision $_geohashPrecision): $geoHash');

      // Reverse geocoding to get human-readable name
      String locationName = await _getLocationName(position.latitude, position.longitude);
      
      debugPrint('📍 Location name: $locationName');

      // Return Nostr 'g' tag format
      return ['g', geoHash, locationName];
      
    } catch (e) {
      debugPrint('📍 Location error: $e');
      return null;
    }
  }

  /// Get human-readable location name with fallback chain
  static Future<String> _getLocationName(double lat, double lon) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lon);
      
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        
        // Fallback chain: city → province → "Location"
        if (place.locality != null && place.locality!.isNotEmpty) {
          return place.locality!;
        }
        if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
          return place.administrativeArea!;
        }
        if (place.country != null && place.country!.isNotEmpty) {
          return place.country!;
        }
      }
    } catch (e) {
      debugPrint('📍 Geocoding failed: $e');
    }
    
    // Ultimate fallback - never crash
    return 'Location';
  }

  /// Parse location tag from event tags
  /// Returns city name or null if no location tag
  static String? parseLocationFromTags(List<dynamic>? tags) {
    if (tags == null) return null;
    
    for (var tag in tags) {
      if (tag is List && tag.length >= 3 && tag[0] == 'g') {
        // ['g', geohash, cityName]
        return tag[2] as String?;
      }
    }
    return null;
  }

  /// Get geohash from event tags
  static String? parseGeohashFromTags(List<dynamic>? tags) {
    if (tags == null) return null;
    
    for (var tag in tags) {
      if (tag is List && tag.length >= 2 && tag[0] == 'g') {
        return tag[1] as String?;
      }
    }
    return null;
  }
}
