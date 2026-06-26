import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../config/mapbox_config.dart';
import '../theme/colors.dart';
import '../services/supabase_service.dart';
import 'home_screen.dart';

class ConfirmLocationScreen extends StatefulWidget {
  final bool editMode;
  final Map<String, dynamic>? initialAddress;
  final LatLng? initialCoords;
  final bool isPostSignInJourney;
  final String? primaryReason;
  final List<Map<String, dynamic>>? members;
  final bool useCurrentLocation;

  const ConfirmLocationScreen({
    super.key,
    this.editMode = false,
    this.initialAddress,
    this.initialCoords,
    this.isPostSignInJourney = false,
    this.primaryReason,
    this.members,
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

  final MapController _mapController = MapController();

  LatLng _currentMapPosition = const LatLng(12.9345, 77.6258);
  bool _isLoading = true;
  Timer? _debounceTimer;

  // Hub coverage state
  String _hubName = 'Koramangala Hub';
  String _hubZone = 'South Bengaluru hub';
  String _hubEst = 'Within 24 hrs';
  bool _isUpdatingFromMap = false;
  bool _isMapEnlarged = false;

  final List<String> _localCities = const [
    'Bengaluru',
    'New Delhi',
    'Delhi',
    'Mumbai',
    'Bhubaneswar',
    'Cuttack',
    'Puri',
    'Kolkata',
    'Chennai',
    'Hyderabad',
    'Pune',
  ];

  @override
  void initState() {
    super.initState();

    // Pre-populate fields if initialAddress is provided
    if (widget.initialAddress != null) {
      _flatController.text = widget.initialAddress!['flat'] ?? '';
      _streetController.text = widget.initialAddress!['street'] ?? '';
      _cityController.text = widget.initialAddress!['city'] ?? '';
      _pincodeController.text = widget.initialAddress!['pincode'] ?? widget.initialAddress!['pin_code'] ?? '';
    }

    if (widget.initialCoords != null) {
      _currentMapPosition = widget.initialCoords!;
      _isLoading = false;
      final nearest = _findNearestLocation(_currentMapPosition.latitude, _currentMapPosition.longitude);
      _hubName = nearest['name']!;
      _hubZone = nearest['zone']!;
      _hubEst = nearest['est']!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(_currentMapPosition, 16.0);
        } catch (_) {}
      });
    } else if (widget.useCurrentLocation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initCurrentLocation();
      });
    } else {
      // Default fallback is to request/use current location
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initCurrentLocation();
      });
    }

    _flatController.addListener(_onAddressFieldsChanged);
    _streetController.addListener(_onAddressFieldsChanged);
    _cityController.addListener(_onAddressFieldsChanged);
    _pincodeController.addListener(_onAddressFieldsChanged);
  }

  @override
  void dispose() {
    _flatController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _pincodeController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onAddressFieldsChanged() {
    if (_isUpdatingFromMap) return;
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
      _geocodeAddressFields();
    });
  }

  Future<void> _geocodeAddressFields() async {
    final street = _streetController.text.trim();
    final city = _cityController.text.trim();
    final pincode = _pincodeController.text.trim();

    if (street.isEmpty && city.isEmpty && pincode.isEmpty) return;

    final query = "$street, $city $pincode".trim();
    LatLng? point;
    if (MapboxConfig.accessToken.isNotEmpty) {
      point = await _geocodeAddressFieldsMapbox(query);
    }
    point ??= await _geocodeAddressFieldsOSM(query);

    if (point != null) {
      final actualPoint = point;
      setState(() {
        _currentMapPosition = actualPoint;
        final nearest = _findNearestLocation(actualPoint.latitude, actualPoint.longitude);
        _hubName = nearest['name']!;
        _hubZone = nearest['zone']!;
        _hubEst = nearest['est']!;
      });
      try {
        _mapController.move(actualPoint, 16.0);
      } catch (_) {}
      
      // Auto-update the rest of the fields by reverse geocoding the resolved coordinate
      await _reverseGeocodeCenter(actualPoint.latitude, actualPoint.longitude);
    }
  }

  Future<LatLng?> _geocodeAddressFieldsMapbox(String query) async {
    try {
      final client = HttpClient();
      final uri = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json?access_token=${MapboxConfig.accessToken}&limit=1&country=in'
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
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1'
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
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _useFallbackDefault("Location services are disabled.");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _useFallbackDefault("Location permission denied.");
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _useFallbackDefault("Location permission permanently denied.");
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );

      final point = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentMapPosition = point;
      });
      try {
        _mapController.move(point, 16.0);
      } catch (_) {}
      await _reverseGeocodeCenter(point.latitude, point.longitude);
    } catch (e) {
      _useFallbackDefault("Error fetching GPS location: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _useFallbackDefault(String warning) {
    debugPrint(warning);
    final fallbackPoint = const LatLng(19.3150, 84.7940);
    setState(() {
      _currentMapPosition = fallbackPoint;
      _isLoading = false;
    });
    try {
      _mapController.move(fallbackPoint, 16.0);
    } catch (_) {}
    _reverseGeocodeCenter(fallbackPoint.latitude, fallbackPoint.longitude);
  }

  Future<void> _goToCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
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
    }
  }

  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    final center = camera.center;

    setState(() {
      _currentMapPosition = center;
    });

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1000), () {
      _reverseGeocodeCenter(center.latitude, center.longitude);
    });
  }

  void _updateLocation(LatLng point) {
    setState(() {
      _currentMapPosition = point;
    });
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

    // Fallback to nearest mock hub location details if online geocoding fails or returns empty/null
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

        _isUpdatingFromMap = true;
        // Don't fill flat number field with general address text
        if (_flatController.text.isEmpty && flat.isNotEmpty) {
          _flatController.text = flat;
        }
        _streetController.text = street;
        _cityController.text = city;
        _pincodeController.text = pincode;
        _isUpdatingFromMap = false;

        final nearest = _findNearestLocation(lat, lng);
        _hubName = nearest['name']!;
        _hubZone = nearest['zone']!;
        _hubEst = nearest['est']!;
      });
    }
  }

  Future<Map<String, String>?> _reverseGeocodeMapbox(double lat, double lng) async {
    try {
      final client = HttpClient();
      final uri = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/$lng,$lat.json?access_token=${MapboxConfig.accessToken}&limit=1&country=in'
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
              } else if (id.startsWith('locality') || id.startsWith('neighborhood')) {
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
        'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=json&addressdetails=1'
      );
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'hestia_consumer_app');
      final response = await request.close();
      if (response.statusCode == 200) {
        final jsonString = await response.transform(utf8.decoder).join();
        final data = json.decode(jsonString);
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          final road = address['road'] as String? ?? address['suburb'] as String? ?? '';
          final suburb = address['suburb'] as String? ?? '';
          final city = address['city'] as String? ?? address['town'] as String? ?? address['state'] as String? ?? 'Bengaluru';
          final pincode = address['postcode'] as String? ?? '';
          final street = road.isNotEmpty ? (suburb.isNotEmpty && suburb != road ? "$suburb, $road" : road) : suburb;
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
      final double d = (loc['lat'] - lat) * (loc['lat'] - lat) + (loc['lng'] - lng) * (loc['lng'] - lng);
      if (d < minDistance) {
        minDistance = d;
        nearest = loc;
      }
    }
    return nearest;
  }

  Future<void> _saveAddress() async {
    final street = _streetController.text.trim();
    final city = _cityController.text.trim();
    final pincode = _pincodeController.text.trim();

    if (street.isEmpty || city.isEmpty || pincode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Street, City, and Pincode are required fields."),
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
        };

        if (widget.isPostSignInJourney) {
          final fullName = user.userMetadata?['full_name'] ?? 'User';
          final phone = user.userMetadata?['phone'] ?? user.phone ?? '8144684265';
          final email = user.userMetadata?['email'] ?? user.email ?? '';

          await SupabaseService.saveUserProfile(
            id: user.id,
            fullName: fullName,
            email: email,
            phone: phone,
            primaryReason: widget.primaryReason ?? 'New mother',
            members: widget.members ?? [],
            address: addressData,
          );

          final profileData = {
            'id': user.id,
            'name': fullName,
            'email': email,
            'phone': phone,
            'primary_reason': widget.primaryReason ?? 'New mother',
            'household_members': widget.members ?? [],
            'address': addressData,
            'updated_at': DateTime.now().toIso8601String(),
          };
          await SupabaseService.uploadProfileJson(
            id: user.id,
            profileData: profileData,
          );

          await SupabaseService.createProfile(
            id: user.id,
            fullName: fullName,
            phone: phone,
          );
        } else {
          await SupabaseService.saveAddressOnly(
            id: user.id,
            address: addressData,
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

  Future<Iterable<String>> searchCities(String query) async {
    if (query.isEmpty) return const Iterable<String>.empty();

    final localMatches = _localCities.where((city) => city.toLowerCase().contains(query.toLowerCase())).toList();

    if (MapboxConfig.accessToken.isNotEmpty) {
      try {
        final client = HttpClient();
        final uri = Uri.parse(
          'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json?access_token=${MapboxConfig.accessToken}&types=place&country=in&limit=5'
        );
        final request = await client.getUrl(uri);
        final response = await request.close();
        if (response.statusCode == 200) {
          final jsonString = await response.transform(utf8.decoder).join();
          final data = json.decode(jsonString);
          final features = data['features'] as List?;
          if (features != null) {
            final apiCities = features.map((f) => f['text'] as String? ?? '').where((c) => c.isNotEmpty).toList();
            for (var city in apiCities) {
              if (!localMatches.contains(city)) {
                localMatches.add(city);
              }
            }
          }
        }
      } catch (e) {
        debugPrint("Error fetching city suggestions from Mapbox: $e");
      }
    }

    return localMatches.take(5);
  }

  @override
  Widget build(BuildContext context) {
    const greenAccent = HestiaColors.primary;
    const textDark = Color(0xFF1E1E1E);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment(0.0, 0.4),
          colors: [
            Color.fromARGB(255, 94, 61, 29),
            Color.fromARGB(255, 139, 106, 65),
            Color.fromARGB(255, 252, 252, 252),
          ],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            widget.isPostSignInJourney
                ? 'Confirm address'
                : (widget.editMode ? 'Edit address' : 'Add address'),
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          titleSpacing: 0,
        ),
        body: SafeArea(
          left: false,
          right: false,
          child: Stack(
            children: [
              SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    // Map section with slide animations on toggle - rounded corners map card
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 16.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          height: _isMapEnlarged ? 550 : 250,
                          child: Stack(
                            children: [
                              FlutterMap(
                                mapController: _mapController,
                                options: MapOptions(
                                  initialCenter: _currentMapPosition,
                                  initialZoom: 16.0,
                                  onPositionChanged: _onMapPositionChanged,
                                  onTap: (tapPosition, point) {
                                    _updateLocation(point);
                                  },
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
                              // Central marker pin
                              Align(
                                alignment: Alignment.center,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 35.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF222222),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          "Pin location",
                                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      CustomPaint(
                                        size: const Size(8, 4),
                                        painter: _TrianglePainter(color: const Color(0xFF222222)),
                                      ),
                                      const SizedBox(height: 4),
                                      const Icon(
                                        Icons.location_on_rounded,
                                        color: Colors.redAccent,
                                        size: 38,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Tap to set pin indicator (Top-Left)
                              Positioned(
                                top: 10,
                                left: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.touch_app, color: Colors.white, size: 14),
                                      SizedBox(width: 4),
                                      Text(
                                        'Tap or drag to set pin',
                                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Fullscreen expand/collapse button (Top-Right)
                              Positioned(
                                top: 10,
                                right: 10,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _isMapEnlarged = !_isMapEnlarged;
                                    });
                                  },
                                  child: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _isMapEnlarged ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ),
                              // GPS center button (Bottom-Right)
                              Positioned(
                                bottom: 16,
                                right: 16,
                                child: GestureDetector(
                                  onTap: _goToCurrentLocation,
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Color(0x1F000000),
                                          blurRadius: 8,
                                          offset: Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.my_location,
                                      color: textDark,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Bottom White card with rounded corners for address details - liquid glass themed
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5ECE3).withValues(alpha: 0.85), // liquid glass tinted brown
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                            border: Border.all(
                              color: const Color(0xFFE6D5C5).withValues(alpha: 0.9),
                              width: 1.5,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInputLabel('FLAT / HOUSE NO.'),
                              const SizedBox(height: 8),
                              _buildTextField(_flatController, 'e.g. B-402, Green Orchid Apartments'),
                              const SizedBox(height: 18),

                              _buildInputLabel('STREET / LOCALITY'),
                              const SizedBox(height: 8),
                              _buildTextField(_streetController, 'e.g. Koramangala 4th Block'),
                              const SizedBox(height: 18),

                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildInputLabel('CITY'),
                                        const SizedBox(height: 8),
                                        _CityAutocompleteField(
                                          controller: _cityController,
                                          placeholder: 'e.g. Bengaluru',
                                          onSearch: (query) => searchCities(query),
                                          onSelected: () => _geocodeAddressFields(),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildInputLabel('PIN CODE'),
                                        const SizedBox(height: 8),
                                        _buildTextField(_pincodeController, 'e.g. 560034', keyboardType: TextInputType.number),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),

                              // Coverage banner
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF2FAE9).withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFB7DDA3)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: Color(0xFF8BC34A), size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Covered by $_hubName',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF3E5C2C),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Great news! Your address falls within our $_hubZone coverage zone. Services available: $_hubEst.',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFF3E5C2C),
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Confirm / Save button
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton(
                                  onPressed: _saveAddress,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: greenAccent,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Text(
                                    widget.isPostSignInJourney
                                        ? 'Confirm & Continue'
                                        : (widget.editMode ? 'Update Address' : 'Save Address'),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
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
                Positioned.fill(
                  child: Container(
                    color: Colors.black12,
                    child: const Center(
                      child: CircularProgressIndicator(color: greenAccent),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Color(0xFF6F4E37),
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(
        color: Color(0xFF1E1E1E),
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.grey.shade500,
          fontWeight: FontWeight.normal,
          fontSize: 15,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: const Color(0xFFE6D5C5).withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: const Color(0xFFE6D5C5).withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: HestiaColors.primary, width: 1.5),
        ),
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

class _CityAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String placeholder;
  final FutureOr<Iterable<String>> Function(String) onSearch;
  final VoidCallback onSelected;

  const _CityAutocompleteField({
    required this.controller,
    required this.placeholder,
    required this.onSearch,
    required this.onSelected,
  });

  @override
  State<_CityAutocompleteField> createState() => _CityAutocompleteFieldState();
}

class _CityAutocompleteFieldState extends State<_CityAutocompleteField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (TextEditingValue textEditingValue) {
        return widget.onSearch(textEditingValue.text);
      },
      onSelected: (String selection) {
        widget.controller.text = selection;
        widget.onSelected();
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          onFieldSubmitted: (value) => onFieldSubmitted(),
          style: const TextStyle(
            color: Color(0xFF1E1E1E),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: widget.placeholder,
            hintStyle: TextStyle(
              color: Colors.grey.shade400,
              fontWeight: FontWeight.normal,
              fontSize: 15,
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.6),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFFE6D5C5).withValues(alpha: 0.5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFFE6D5C5).withValues(alpha: 0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: HestiaColors.primary, width: 1.5),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6.0,
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 170,
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200, width: 0.5),
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final String option = options.elementAt(index);
                  return InkWell(
                    onTap: () {
                      onSelected(option);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      child: Text(
                        option,
                        style: const TextStyle(color: Color(0xFF1E1E1E), fontSize: 14),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
