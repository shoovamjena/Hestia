import 'dart:convert';
import 'dart:io';

import '../config/mapbox_config.dart';

class LocationGeocodingService {
  static Future<Map<String, String>?> reverseGeocode(
    double lat,
    double lng,
  ) async {
    if (MapboxConfig.accessToken.isNotEmpty) {
      final mapboxResult = await _reverseGeocodeMapbox(lat, lng);
      if (mapboxResult != null) return mapboxResult;
    }
    return _reverseGeocodeOsm(lat, lng);
  }

  static Future<Map<String, String>?> _reverseGeocodeMapbox(
    double lat,
    double lng,
  ) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final uri = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/$lng,$lat.json'
        '?access_token=${MapboxConfig.accessToken}&limit=1&country=in',
      );
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      final response = await request.close().timeout(
            const Duration(seconds: 8),
          );
      if (response.statusCode != 200) return null;

      final jsonString = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));
      final data = json.decode(jsonString) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return null;

      final first = features.first as Map<String, dynamic>;
      final text = first['text'] as String? ?? '';

      var flat = '';
      var street = text;
      var city = 'Bengaluru';
      var pincode = '';

      final contextList = first['context'] as List?;
      if (contextList != null) {
        for (final item in contextList) {
          final map = item as Map<String, dynamic>;
          final id = map['id'] as String? ?? '';
          if (id.startsWith('postcode')) {
            pincode = map['text'] as String? ?? pincode;
          } else if (id.startsWith('place')) {
            city = map['text'] as String? ?? city;
          } else if (id.startsWith('locality') || id.startsWith('neighborhood')) {
            street = '${map['text']}, $street';
          }
        }
      }

      final addressNum = first['address'] as String?;
      if (addressNum != null) {
        flat = 'No. $addressNum';
      }

      return {
        'flat': flat,
        'street': street,
        'city': city,
        'pincode': pincode,
      };
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  static Future<Map<String, String>?> _reverseGeocodeOsm(
    double lat,
    double lng,
  ) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lng&format=json&addressdetails=1',
      );
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.set('User-Agent', 'hestia_consumer_app');
      final response = await request.close().timeout(
            const Duration(seconds: 8),
          );
      if (response.statusCode != 200) return null;

      final jsonString = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));
      final data = json.decode(jsonString) as Map<String, dynamic>;
      final address = data['address'] as Map<String, dynamic>?;
      if (address == null) return null;

      final road =
          address['road'] as String? ?? address['suburb'] as String? ?? '';
      final suburb = address['suburb'] as String? ?? '';
      final city = address['city'] as String? ??
          address['town'] as String? ??
          address['state'] as String? ??
          'Bengaluru';
      final pincode = address['postcode'] as String? ?? '';
      final street = road.isNotEmpty
          ? (suburb.isNotEmpty && suburb != road ? '$suburb, $road' : road)
          : suburb;

      return {
        'flat': '',
        'street': street,
        'city': city,
        'pincode': pincode,
      };
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }
}
