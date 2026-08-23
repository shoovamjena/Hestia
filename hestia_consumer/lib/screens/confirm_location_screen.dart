import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../config/mapbox_config.dart';
import '../theme/colors.dart';
import '../services/supabase_service.dart';
import '../services/location_acquisition_service.dart';
import 'home_screen.dart';

class ConfirmLocationScreen extends StatefulWidget {
  final bool editMode;
  final Map<String, dynamic>? initialAddress;
  final LatLng? initialCoords;
  final bool isPostSignInJourney;
  final bool useCurrentLocation;

  const ConfirmLocationScreen({
    super.key,
    this.editMode = false,
    this.initialAddress,
    this.initialCoords,
    this.isPostSignInJourney = false,
    this.useCurrentLocation = false,
  });

  @override
  State<ConfirmLocationScreen> createState() => _ConfirmLocationScreenState();
}

class _ConfirmLocationScreenState extends State<ConfirmLocationScreen> {
  final _flatController = TextEditingController();
  final _streetController = TextEditingController();
  final _cityController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _searchController = TextEditingController();

  final MapController _mapController = MapController();

  LatLng _currentMapPosition = const LatLng(12.9345, 77.6258);
  bool _isLoading = true;
  Timer? _debounceTimer;

  // Hub coverage state
  bool _isWithinCoverage = true;
  List<Map<String, dynamic>> _dbHubs = [];

  final List<Map<String, dynamic>> _mockHubs = const [
    {
      'name': 'Koramangala Hub',
      'latitude': 12.9345,
      'longitude': 77.6258,
      'zone': 'South Bengaluru hub',
      'est': 'Within 24 hrs',
    },
    {
      'name': 'Delhi Hub',
      'latitude': 28.6139,
      'longitude': 77.2090,
      'zone': 'New Delhi hub',
      'est': 'Within 12 hrs',
    },
    {
      'name': 'Bellandur Hub',
      'latitude': 12.9304,
      'longitude': 77.6784,
      'zone': 'East Bengaluru hub',
      'est': 'Within 12 hrs',
    },
    {
      'name': 'Whitefield Hub',
      'latitude': 12.9698,
      'longitude': 77.7499,
      'zone': 'East Bengaluru hub',
      'est': 'Within 24 hrs',
    },
  ];

  @override
  void initState() {
    super.initState();

    _fetchHubsFromDb();

    // Pre-populate fields if initialAddress is provided
    if (widget.initialAddress != null) {
      _flatController.text = widget.initialAddress!['flat'] ?? '';
      _streetController.text = widget.initialAddress!['street'] ?? '';
      _cityController.text = widget.initialAddress!['city'] ?? '';
      _pincodeController.text = widget.initialAddress!['pincode'] ??
          widget.initialAddress!['pin_code'] ??
          '';
    }

    if (widget.initialCoords != null) {
      _currentMapPosition = widget.initialCoords!;
      _isLoading = false;
      _updateNearestHub(
        _currentMapPosition.latitude,
        _currentMapPosition.longitude,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(_currentMapPosition, 16.0);
        } catch (_) {}
      });
    } else {
      // Default is to request/use current location
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initCurrentLocation();
      });
    }
  }

  @override
  void dispose() {
    _flatController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _pincodeController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _searchAndMove(String query) async {
    if (query.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    LatLng? point;
    if (MapboxConfig.accessToken.isNotEmpty) {
      point = await _geocodeAddressFieldsMapbox(query);
    }
    point ??= await _geocodeAddressFieldsOSM(query);

    if (point != null) {
      _updateLocation(point);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No results found for that search.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }

    if (mounted) setState(() => _isLoading = false);
  }

  String get _addressTitle {
    final street = _streetController.text.trim();
    final city = _cityController.text.trim();
    if (street.isNotEmpty) {
      return street.split(',').first.trim();
    }
    return city.isNotEmpty ? city : 'Selected location';
  }

  String get _addressSubtitle {
    final parts = [
      _flatController.text.trim(),
      _streetController.text.trim(),
      _cityController.text.trim(),
      _pincodeController.text.trim(),
    ].where((e) => e.isNotEmpty).toList();
    return parts.isEmpty
        ? 'Move the map to pick your exact address'
        : parts.join(', ');
  }

  Future<LatLng?> _geocodeAddressFieldsMapbox(String query) async {
    try {
      final client = HttpClient();
      final uri = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json?access_token=${MapboxConfig.accessToken}&limit=1&country=in',
      );
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode == 200) {
        final jsonString = await response.transform(utf8.decoder).join();
        final data = json.decode(jsonString);
        final features = data['features'] as List?;
        if (features != null && features.isNotEmpty) {
          final first = features.first;
          final center = first['center'] as List?;
          if (center != null && center.length >= 2) {
            final double lng = (center[0] as num).toDouble();
            final double lat = (center[1] as num).toDouble();
            return LatLng(lat, lng);
          }
        }
      }
    } catch (e) {
      debugPrint("Mapbox forward geocoding failed: $e");
    }
    return null;
  }

  Future<LatLng?> _geocodeAddressFieldsOSM(String query) async {
    try {
      final client = HttpClient();
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1',
      );
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'hestia_consumer_app');
      final response = await request.close();
      if (response.statusCode == 200) {
        final jsonString = await response.transform(utf8.decoder).join();
        final data = json.decode(jsonString) as List?;
        if (data != null && data.isNotEmpty) {
          final first = data.first as Map<String, dynamic>;
          final double lat = double.parse(first['lat'] as String);
          final double lng = double.parse(first['lon'] as String);
          return LatLng(lat, lng);
        }
      }
    } catch (e) {
      debugPrint("OSM forward geocoding failed: $e");
    }
    return null;
  }

  Future<void> _initCurrentLocation() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final position = await LocationAcquisitionService.acquirePosition();
      if (position == null) {
        _useFallbackDefault("Could not obtain a GPS fix.");
        return;
      }

      final point = LatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _currentMapPosition = point;
        });
      }
      try {
        _mapController.move(point, 16.0);
      } catch (_) {}
      await _reverseGeocodeCenter(point.latitude, point.longitude);
    } catch (e) {
      _useFallbackDefault("Error fetching GPS location: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _useFallbackDefault(String warning) {
    debugPrint(warning);
    final fallbackPoint = const LatLng(19.3150, 84.7940);
    if (mounted) {
      setState(() {
        _currentMapPosition = fallbackPoint;
        _isLoading = false;
      });
    }
    try {
      _mapController.move(fallbackPoint, 16.0);
    } catch (_) {}
    _reverseGeocodeCenter(fallbackPoint.latitude, fallbackPoint.longitude);
  }

  Future<void> _goToCurrentLocation() async {
    setState(() => _isLoading = true);
    try {
      final position = await LocationAcquisitionService.acquirePosition();
      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Couldn't get your current location. Try again."),
            ),
          );
        }
        return;
      }
      final point = LatLng(position.latitude, position.longitude);
      try {
        _mapController.move(point, 16.0);
      } catch (_) {}
      setState(() {
        _currentMapPosition = point;
      });
      await _reverseGeocodeCenter(point.latitude, point.longitude);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not resolve current location: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    final center = camera.center;

    setState(() {
      _currentMapPosition = center;
    });
    _updateNearestHub(center.latitude, center.longitude);

    if (!hasGesture) return;

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      _reverseGeocodeCenter(center.latitude, center.longitude);
    });
  }

  void _updateLocation(LatLng point) {
    if (mounted) {
      setState(() {
        _currentMapPosition = point;
      });
    }
    _updateNearestHub(point.latitude, point.longitude);
    try {
      _mapController.move(point, 16.0);
    } catch (_) {}
    _reverseGeocodeCenter(point.latitude, point.longitude);
  }

  Future<void> _reverseGeocodeCenter(double lat, double lng) async {
    Map<String, String>? addressData;
    if (MapboxConfig.accessToken.isNotEmpty) {
      addressData = await _reverseGeocodeMapbox(lat, lng);
    }
    addressData ??= await _reverseGeocodeOSM(lat, lng);

    // Fallback to nearest mock hub location details if online geocoding fails
    if (addressData == null) {
      final nearest = _findNearestLocation(lat, lng);
      addressData = {
        'flat': nearest['flat'] ?? '',
        'street': nearest['street'] ?? '',
        'city': nearest['city'] ?? '',
        'pincode': nearest['pincode'] ?? '',
      };
    }

    if (mounted) {
      setState(() {
        final flat = addressData!['flat'] ?? '';
        final street = addressData['street'] ?? '';
        final city = addressData['city'] ?? '';
        final pincode = addressData['pincode'] ?? '';

        _flatController.text = flat;
        _streetController.text = street;
        _cityController.text = city;
        _pincodeController.text = pincode;
      });
      _updateNearestHub(lat, lng);
    }
  }

  Future<Map<String, String>?> _reverseGeocodeMapbox(
    double lat,
    double lng,
  ) async {
    try {
      final client = HttpClient();
      final uri = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/$lng,$lat.json?access_token=${MapboxConfig.accessToken}&limit=1&country=in',
      );
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode == 200) {
        final jsonString = await response.transform(utf8.decoder).join();
        final data = json.decode(jsonString);
        final features = data['features'] as List?;
        if (features != null && features.isNotEmpty) {
          final first = features.first;
          final text = first['text'] as String? ?? '';

          String flat = '';
          String street = text;
          String city = 'Bengaluru';
          String pincode = '';

          final contextList = first['context'] as List?;
          if (contextList != null) {
            for (var item in contextList) {
              final id = item['id'] as String? ?? '';
              if (id.startsWith('postcode')) {
                pincode = item['text'] as String? ?? pincode;
              } else if (id.startsWith('place')) {
                city = item['text'] as String? ?? city;
              } else if (id.startsWith('locality') ||
                  id.startsWith('neighborhood')) {
                street = "${item['text']}, $street";
              }
            }
          }

          final addressNum = first['address'] as String?;
          if (addressNum != null) {
            flat = "No. $addressNum";
          }

          return {
            'flat': flat,
            'street': street,
            'city': city,
            'pincode': pincode,
          };
        }
      }
    } catch (e) {
      debugPrint("Mapbox reverse geocode failed: $e");
    }
    return null;
  }

  Future<Map<String, String>?> _reverseGeocodeOSM(double lat, double lng) async {
    try {
      final client = HttpClient();
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=json&addressdetails=1',
      );
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'hestia_consumer_app');
      final response = await request.close();
      if (response.statusCode == 200) {
        final jsonString = await response.transform(utf8.decoder).join();
        final data = json.decode(jsonString);
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          final road =
              address['road'] as String? ?? address['suburb'] as String? ?? '';
          final suburb = address['suburb'] as String? ?? '';
          final city = address['city'] as String? ??
              address['town'] as String? ??
              address['state'] as String? ??
              'Bengaluru';
          final pincode = address['postcode'] as String? ?? '';
          final street = road.isNotEmpty
              ? (suburb.isNotEmpty && suburb != road ? "$suburb, $road" : road)
              : suburb;
          return {
            'flat': '',
            'street': street,
            'city': city,
            'pincode': pincode,
          };
        }
      }
    } catch (e) {
      debugPrint("OSM reverse geocode failed: $e");
    }
    return null;
  }

  Map<String, dynamic> _findNearestLocation(double lat, double lng) {
    final List<Map<String, dynamic>> mockLocations = [
      {
        'name': 'Koramangala Hub',
        'lat': 12.9345,
        'lng': 77.6258,
        'flat': 'B-402, Green Orchid Apartments',
        'street': 'Koramangala 4th Block',
        'city': 'Bengaluru',
        'pincode': '560034',
        'zone': 'South Bengaluru hub',
        'est': 'Within 24 hrs',
      },
      {
        'name': 'Delhi Hub',
        'lat': 28.6139,
        'lng': 77.2090,
        'flat': '89, Usuw',
        'street': 'Pocket 25, Pocket 25, Bharat singh, Pista',
        'city': 'New Delhi',
        'pincode': '110085',
        'zone': 'New Delhi hub',
        'est': 'Within 12 hrs',
      },
      {
        'name': 'Bellandur Hub',
        'lat': 12.9304,
        'lng': 77.6784,
        'flat': 'Flat 108, Sobha Jasmine',
        'street': 'Bellandur Outer Ring Rd',
        'city': 'Bengaluru',
        'pincode': '560103',
        'zone': 'East Bengaluru hub',
        'est': 'Within 12 hrs',
      },
      {
        'name': 'Whitefield Hub',
        'lat': 12.9698,
        'lng': 77.7499,
        'flat': 'Villa 12, Windmills of Your Mind',
        'street': 'Whitefield Hope Farm',
        'city': 'Bengaluru',
        'pincode': '560066',
        'zone': 'East Bengaluru hub',
        'est': 'Within 24 hrs',
      },
    ];

    Map<String, dynamic> nearest = mockLocations[0];
    double minDistance = double.infinity;
    for (final loc in mockLocations) {
      final double d = (loc['lat'] - lat) * (loc['lat'] - lat) +
          (loc['lng'] - lng) * (loc['lng'] - lng);
      if (d < minDistance) {
        minDistance = d;
        nearest = loc;
      }
    }
    return nearest;
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }

  void _updateNearestHub(double lat, double lng) {
    final hubs = _dbHubs.isNotEmpty ? _dbHubs : _mockHubs;
    if (hubs.isEmpty) return;

    double minDistance = double.infinity;

    for (final hub in hubs) {
      final double hubLat = double.tryParse(
              hub['latitude']?.toString() ?? hub['lat']?.toString() ?? '') ??
          0.0;
      final double hubLng = double.tryParse(
              hub['longitude']?.toString() ?? hub['lng']?.toString() ?? '') ??
          0.0;

      final distance = _calculateDistance(lat, lng, hubLat, hubLng);
      if (distance < minDistance) {
        minDistance = distance;
      }
    }

    if (mounted) {
      setState(() {
        _isWithinCoverage =
            minDistance <= SupabaseService.coverageRadiusKm;
      });
    }

    // Prefer server RPC when available (non-blocking refresh)
    SupabaseService.resolveHubCoverage(lat, lng).then((resolved) {
      if (!mounted || resolved == null) return;
      setState(() {
        _isWithinCoverage = resolved['zone_verified'] == true;
      });
    });
  }

  Future<void> _fetchHubsFromDb() async {
    try {
      final List<dynamic> response = await SupabaseService.client
          .from('hubs')
          .select('id, name, latitude, longitude, address');

      final List<Map<String, dynamic>> fetchedHubs = [];
      for (final item in response) {
        final hub = Map<String, dynamic>.from(item);
        double? lat = double.tryParse(hub['latitude']?.toString() ?? '');
        double? lng = double.tryParse(hub['longitude']?.toString() ?? '');

        if (lat == null || lng == null || (lat == 0.0 && lng == 0.0)) {
          final query = hub['address']?.toString() ?? hub['name']?.toString() ?? '';
          if (query.isNotEmpty) {
            LatLng? point;
            if (MapboxConfig.accessToken.isNotEmpty) {
              point = await _geocodeAddressFieldsMapbox(query);
            }
            point ??= await _geocodeAddressFieldsOSM(query);
            if (point != null) {
              hub['latitude'] = point.latitude;
              hub['longitude'] = point.longitude;
            }
          }
        }
        fetchedHubs.add(hub);
      }

      if (mounted) {
        setState(() {
          _dbHubs = fetchedHubs;
          _updateNearestHub(
            _currentMapPosition.latitude,
            _currentMapPosition.longitude,
          );
        });
      }
    } catch (e) {
      debugPrint('Error fetching hubs: $e');
    }
  }

  Future<void> _saveAddress() async {
    final street = _streetController.text.trim();
    final city = _cityController.text.trim();

    if (street.isEmpty && city.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "We couldn't detect this address. Move the map or search again.",
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: HestiaColors.primary),
      ),
    );

    try {
      final user = SupabaseService.currentUser;
      if (user != null) {
        final addressData = {
          'flat': _flatController.text.trim(),
          'street': _streetController.text.trim(),
          'city': _cityController.text.trim(),
          'pincode': _pincodeController.text.trim(),
          'latitude': _currentMapPosition.latitude,
          'longitude': _currentMapPosition.longitude,
        };
        if (widget.isPostSignInJourney) {
          final fullName = SupabaseService.pendingOnboardingFullName ??
              user.userMetadata?['full_name']?.toString() ??
              'User';
          final email = SupabaseService.pendingOnboardingEmail ??
              user.userMetadata?['email']?.toString() ??
              user.email ??
              '';
          final phone = SupabaseService.currentUserPhone.isNotEmpty
              ? SupabaseService.currentUserPhone
              : null;

          await SupabaseService.completeOnboarding(
            id: user.id,
            fullName: fullName,
            email: email,
            phone: phone,
            address: addressData,
            withinCoverage: _isWithinCoverage,
          );
        } else {
          await SupabaseService.saveAddressOnly(
            id: user.id,
            address: addressData,
            withinCoverage: _isWithinCoverage,
          );
        }
      }
      if (mounted) {
        Navigator.pop(context); // Pop loading dialog
        if (widget.isPostSignInJourney) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
          );
        } else {
          Navigator.pop(context); // Pop ConfirmLocationScreen
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Pop loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to save address: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HestiaColors.appBackground,
      appBar: AppBar(
        backgroundColor: HestiaColors.appBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: HestiaColors.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Confirm your location',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: HestiaColors.textDark,
          ),
        ),
        titleSpacing: 0,
      ),
      body: Stack(
        children: [
          // Full-screen map
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentMapPosition,
                initialZoom: 16.0,
                onPositionChanged: _onMapPositionChanged,
              ),
              children: [
                TileLayer(
                  urlTemplate: MapboxConfig.accessToken.isNotEmpty
                      ? 'https://api.mapbox.com/styles/v1/${MapboxConfig.styleId}/tiles/256/{z}/{x}/{y}@2x?access_token=${MapboxConfig.accessToken}'
                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.hestia_consumer_app',
                ),
              ],
            ),
          ),

          // Center pin + tooltip (non-interactive)
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 46),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF222222),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Set this as your location',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            _addressTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    CustomPaint(
                      size: const Size(14, 7),
                      painter: _TrianglePainter(color: const Color(0xFF222222)),
                    ),
                    const SizedBox(height: 2),
                    const Icon(
                      Icons.location_on,
                      color: HestiaColors.primary,
                      size: 44,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Search bar (top)
          Positioned(
            top: 8,
            left: 16,
            right: 16,
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(14),
              shadowColor: Colors.black26,
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: _searchAndMove,
                decoration: InputDecoration(
                  hintText: 'Search locality, sector, area',
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: HestiaColors.primary,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: HestiaColors.primary,
                      width: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom: "Go to current location" pill + address card
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    elevation: 3,
                    borderRadius: BorderRadius.circular(30),
                    shadowColor: Colors.black26,
                    child: InkWell(
                      onTap: _goToCurrentLocation,
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.my_location,
                              color: HestiaColors.primary,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Go to current location',
                              style: TextStyle(
                                color: HestiaColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x1F000000),
                        blurRadius: 16,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: HestiaColors.primary,
                                size: 26,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _addressTitle,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: HestiaColors.textDark,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _addressSubtitle,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: HestiaColors.textMedium,
                                        height: 1.3,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: _saveAddress,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: HestiaColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                widget.isPostSignInJourney
                                    ? 'Confirm & Continue'
                                    : (widget.editMode
                                        ? 'Update location'
                                        : 'Confirm location'),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_isLoading)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black12,
                child: Center(
                  child: CircularProgressIndicator(color: HestiaColors.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;

  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width / 2, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
