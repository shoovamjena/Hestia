import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/mapbox_config.dart';
import '../services/supabase_service.dart';
import '../theme/colors.dart';
import 'home_screen.dart';

class PostSignInJourneyScreen extends StatefulWidget {
  const PostSignInJourneyScreen({super.key});

  @override
  State<PostSignInJourneyScreen> createState() => _PostSignInJourneyScreenState();
}

class _PostSignInJourneyScreenState extends State<PostSignInJourneyScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Profile data state
  String _selectedReason = 'New mother';
  List<Map<String, dynamic>> _members = [];

  // Address controllers
  final TextEditingController _flatController = TextEditingController(text: 'B-402, Green Orchid Apartments');
  final TextEditingController _streetController = TextEditingController(text: 'Koramangala 4th Block');
  final TextEditingController _cityController = TextEditingController(text: 'Bengaluru');
  final TextEditingController _pincodeController = TextEditingController(text: '560034');

  // Map location and dynamic hub details
  LatLng _currentMapPosition = const LatLng(12.9345, 77.6258);
  String _hubName = 'Koramangala Hub';
  String _hubZone = 'South Bengaluru hub';
  String _hubEst = 'Within 24 hrs';

  // Map and Location sync control
  final MapController _mapController = MapController();
  bool _isUpdatingFromMap = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    
    // Listen to changes in address text fields to update coordinates
    _flatController.addListener(_onAddressFieldsChanged);
    _streetController.addListener(_onAddressFieldsChanged);
    _cityController.addListener(_onAddressFieldsChanged);
    _pincodeController.addListener(_onAddressFieldsChanged);

    // Fetch device location and prompt Android location permission on initialization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
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

  void _showDebugSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _safeMoveMap(LatLng point, double zoom) {
    try {
      _mapController.move(point, zoom);
    } catch (e) {
      debugPrint("MapController not ready yet: $e");
    }
  }

  final List<String> _localCities = const [
    'Berhampur',
    'Brahmapur',
    'Bengaluru',
    'Bhubaneswar',
    'Cuttack',
    'Puri',
    'Mumbai',
    'Delhi',
    'Kolkata',
    'Chennai',
    'Hyderabad',
    'Pune',
    'Ahmedabad',
    'Jaipur',
    'Lucknow',
    'Patna',
  ];

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

  bool _isPointInIndia(double lat, double lng) {
    return lat >= 8.0 && lat <= 38.0 && lng >= 68.0 && lng <= 98.0;
  }

  Future<void> _initLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showDebugSnackBar("Location services disabled. Map is centered using address input.");
      await _geocodeAddressFields();
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showDebugSnackBar("Location permission denied. Map is centered using address input.");
        await _geocodeAddressFields();
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      _showDebugSnackBar("Location permission denied forever. Map is centered using address input.");
      await _geocodeAddressFields();
      return;
    }

    // Permission granted, fetch current device position
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      if (!_isPointInIndia(position.latitude, position.longitude)) {
        _showDebugSnackBar("Default emulator GPS (USA) detected. Centering on your address input instead.");
        await _geocodeAddressFields();
        return;
      }
      final point = LatLng(position.latitude, position.longitude);
      _showDebugSnackBar("Resolved GPS position: (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})");
      await _updateLocation(point, performReverseGeocode: true);
      _safeMoveMap(point, 15.0);
    } catch (e) {
      _showDebugSnackBar("GPS fetch failed: $e. Using address input fallback.");
      await _geocodeAddressFields();
    }
  }

  Future<void> _updateLocation(LatLng point, {bool performReverseGeocode = true}) async {
    setState(() {
      _currentMapPosition = point;
      final nearest = _findNearestLocation(point.latitude, point.longitude);
      _hubName = nearest['name']!;
      _hubZone = nearest['zone']!;
      _hubEst = nearest['est']!;
    });

    if (performReverseGeocode) {
      _isUpdatingFromMap = true;
      try {
        final addressData = await _reverseGeocode(point.latitude, point.longitude);
        if (addressData != null) {
          setState(() {
            _flatController.text = addressData['flat'] ?? '';
            _streetController.text = addressData['street'] ?? '';
            _cityController.text = addressData['city'] ?? 'Bengaluru';
            _pincodeController.text = addressData['pincode'] ?? '560034';
          });
        }
      } catch (e) {
        debugPrint("Error reverse geocoding: $e");
      } finally {
        _isUpdatingFromMap = false;
      }
    }
  }

  Future<Map<String, String>?> _reverseGeocode(double lat, double lng) async {
    if (MapboxConfig.accessToken.isNotEmpty) {
      final mapboxResult = await _reverseGeocodeMapbox(lat, lng);
      if (mapboxResult != null) return mapboxResult;
    }
    
    final osmResult = await _reverseGeocodeOSM(lat, lng);
    if (osmResult != null) return osmResult;

    final nearest = _findNearestLocation(lat, lng);
    return {
      'flat': nearest['flat']!,
      'street': nearest['street']!,
      'city': nearest['city']!,
      'pincode': nearest['pincode']!,
    };
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
          final placeName = first['place_name'] as String? ?? '';
          final text = first['text'] as String? ?? '';
          
          String flat = '';
          String street = text;
          String city = 'Bengaluru';
          String pincode = '560034';
          
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
          } else {
            final parts = placeName.split(',');
            if (parts.isNotEmpty) {
              if (parts[0].trim() != text.trim()) {
                flat = parts[0].trim();
              }
            }
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
          final pincode = address['postcode'] as String? ?? '560034';
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
      _safeMoveMap(actualPoint, 15.0);
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

  void _goNext() {
    if (_currentPage == 0) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HestiaColors.background,
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (index) => setState(() => _currentPage = index),
          children: [
            _HouseholdIntroPage(),
            _AddressVerificationPage(),
          ],
        ),
      ),
    );
  }
}

class _JourneyShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget primaryButton;
  final Widget? secondaryButton;

  const _JourneyShell({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.primaryButton,
    this.secondaryButton,
  });

  @override
  Widget build(BuildContext context) {
    final parentState = context.findAncestorStateOfType<_PostSignInJourneyScreenState>();
    final currentPage = parentState?._currentPage ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: HestiaColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.chevron_left,
                    color: HestiaColors.primary,
                    size: 28,
                  ),
                ),
              ),
              const Text(
                'Hestia',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: HestiaColors.primary,
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: List.generate(
              2,
              (index) => Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: index == 1 ? 0 : 8),
                  decoration: BoxDecoration(
                    color: index <= currentPage ? HestiaColors.primary : HestiaColors.indicatorInactive,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: HestiaColors.textDark,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 15,
              color: HestiaColors.textMedium,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(child: child),
          const SizedBox(height: 20),
          if (secondaryButton != null) ...[
            secondaryButton!,
            const SizedBox(height: 14),
          ],
          primaryButton,
        ],
      ),
    );
  }
}

class _HouseholdIntroPage extends StatefulWidget {
  const _HouseholdIntroPage();

  @override
  State<_HouseholdIntroPage> createState() => _HouseholdIntroPageState();
}

class _HouseholdIntroPageState extends State<_HouseholdIntroPage> {
  String _selectedReason = 'New mother';
  final List<Map<String, dynamic>> _members = [];

  // Helper to determine emoji based on age
  String _getEmojiForAge(int age) {
    if (age <= 2) return '👶';
    if (age <= 12) return '🧒';
    if (age <= 19) return '🧑';
    if (age <= 59) return '🧑';
    return '👵';
  }

  // Helper to determine accent color based on age
  Color _getColorForAge(int age) {
    if (age <= 2) return const Color(0xFFFFE6CC);
    if (age <= 12) return const Color(0xFFE1F5FE);
    if (age <= 19) return const Color(0xFFEDE7F6);
    if (age <= 59) return const Color(0xFFFCE4EC);
    return const Color(0xFFE4F1D8);
  }

  void _showAddMemberDialog() {
    final nameController = TextEditingController();
    final ageController = TextEditingController();
    final roleController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: HestiaColors.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Add Household Member',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: HestiaColors.textDark,
            ),
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MEMBER NAME',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: HestiaColors.textAccent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(
                      hintText: 'e.g. Meera',
                      filled: true,
                      fillColor: HestiaColors.inputBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: HestiaColors.inputBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: HestiaColors.inputBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: HestiaColors.primary, width: 1.5),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'AGE (YEARS)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: HestiaColors.textAccent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: ageController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'e.g. 68',
                      filled: true,
                      fillColor: HestiaColors.inputBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: HestiaColors.inputBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: HestiaColors.inputBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: HestiaColors.primary, width: 1.5),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter age';
                      }
                      final age = int.tryParse(value);
                      if (age == null || age < 0) {
                        return 'Please enter a valid age';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'ROLE / CARE REASON',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: HestiaColors.textAccent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: roleController,
                    decoration: InputDecoration(
                      hintText: 'e.g. Grandmother / Mobility Support',
                      filled: true,
                      fillColor: HestiaColors.inputBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: HestiaColors.inputBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: HestiaColors.inputBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: HestiaColors.primary, width: 1.5),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter relationship or role';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: HestiaColors.textMedium)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: HestiaColors.primary,
                foregroundColor: HestiaColors.buttonText,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  final age = int.parse(ageController.text);
                  setState(() {
                    _members.add({
                      'name': nameController.text.trim(),
                      'age': age,
                      'role': roleController.text.trim(),
                    });
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _JourneyShell(
      title: 'Tell us about\nyour household',
      subtitle: 'This helps us personalise your care experience',
      primaryButton: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: () {
            final state = context.findAncestorStateOfType<_PostSignInJourneyScreenState>();
            if (state != null) {
              state.setState(() {
                state._selectedReason = _selectedReason;
                state._members = List<Map<String, dynamic>>.from(_members);
              });
              state._goNext();
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: HestiaColors.primary,
            foregroundColor: HestiaColors.buttonText,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: const Text(
            'Continue',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PRIMARY REASON FOR CARE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: HestiaColors.textLight,
                letterSpacing: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                'New mother',
                'Post-surgery',
                'Elderly care',
                'Childcare',
                'Other',
              ].map((reason) {
                final isSelected = _selectedReason == reason;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedReason = reason;
                    });
                  },
                  child: _ReasonChip(
                    label: reason,
                    selected: isSelected,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 22),
            const Text(
              'Household members',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: HestiaColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
            ..._members.asMap().entries.map((entry) {
              final index = entry.key;
              final member = entry.value;
              final age = member['age'] as int;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _HouseholdMemberCard(
                  name: '${member['name']} (${age > 0 ? '$age yr' : 'Newborn'})',
                  subtitle: member['role'],
                  icon: _getEmojiForAge(age),
                  accentColor: _getColorForAge(age),
                  onRemove: () {
                    setState(() {
                      _members.removeAt(index);
                    });
                  },
                ),
              );
            }),
            GestureDetector(
              onTap: _showAddMemberDialog,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF0E4D9)),
                ),
                child: Row(
                  children: const [
                    _IconBadge(icon: Icons.add, background: Color(0xFFF3E7DB)),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add household member',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: HestiaColors.textDark,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Newborn, elderly parent, patient...',
                            style: TextStyle(
                              fontSize: 13,
                              color: HestiaColors.textMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressVerificationPage extends StatelessWidget {
  const _AddressVerificationPage();

  Future<void> _confirmAddress(BuildContext context) async {
    // Show a loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          color: HestiaColors.primary,
        ),
      ),
    );

    final parentState = context.findAncestorStateOfType<_PostSignInJourneyScreenState>();
    if (parentState == null) {
      Navigator.of(context).pop();
      return;
    }

    final user = SupabaseService.currentUser;
    if (user != null) {
      final fullName = user.userMetadata?['full_name'] ?? 'User';
      final phone = user.userMetadata?['phone'] ?? user.phone ?? '';
      final email = user.userMetadata?['email'] ?? user.email ?? '';

      try {
        // 1. Save profile details inside relational database tables
        await SupabaseService.saveUserProfile(
          id: user.id,
          fullName: fullName,
          email: email,
          phone: phone,
          primaryReason: parentState._selectedReason,
          members: parentState._members,
          address: {
            'flat': parentState._flatController.text,
            'street': parentState._streetController.text,
            'city': parentState._cityController.text,
            'pincode': parentState._pincodeController.text,
          },
        );

        // 2. legacy fallback storage upload
        final profileData = {
          'id': user.id,
          'name': fullName,
          'email': email,
          'phone': phone,
          'primary_reason': parentState._selectedReason,
          'household_members': parentState._members,
          'address': {
            'flat': parentState._flatController.text,
            'street': parentState._streetController.text,
            'city': parentState._cityController.text,
            'pincode': parentState._pincodeController.text,
          },
          'updated_at': DateTime.now().toIso8601String(),
        };
        await SupabaseService.uploadProfileJson(
          id: user.id,
          profileData: profileData,
        );

        // 3. Keep profiles legacy table updated as fallback
        await SupabaseService.createProfile(
          id: user.id,
          fullName: fullName,
          phone: phone,
        );
      } catch (e) {
        debugPrint('Warning: Could not save profile: $e');
      }
    }

    if (context.mounted) {
      // Pop the loading dialog
      Navigator.of(context).pop();
      // Navigate to HomeScreen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final parentState = context.findAncestorStateOfType<_PostSignInJourneyScreenState>();
    if (parentState == null) return const SizedBox();

    final flatController = parentState._flatController;
    final streetController = parentState._streetController;
    final cityController = parentState._cityController;
    final pincodeController = parentState._pincodeController;
    final mapPosition = parentState._currentMapPosition;
    final hubName = parentState._hubName;
    final hubZone = parentState._hubZone;
    final hubEst = parentState._hubEst;

    return _JourneyShell(
      title: 'Your home address',
      subtitle: 'We\'ll verify your area is covered by a Hestia hub',
      secondaryButton: SizedBox(
        width: double.infinity,
        height: 56,
        child: OutlinedButton(
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const HomeScreen()),
              (route) => false,
            );
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: HestiaColors.primary,
            side: const BorderSide(color: HestiaColors.inputBorder, width: 1.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text(
            'Back',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      primaryButton: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: () => _confirmAddress(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: HestiaColors.primary,
            foregroundColor: HestiaColors.buttonText,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: const Text(
            'Confirm Address',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AddressTextField(
              label: 'FLAT / HOUSE NO.',
              controller: flatController,
              placeholder: 'B-402, Green Orchid Apartments',
            ),
            const SizedBox(height: 16),
            _AddressTextField(
              label: 'STREET / LOCALITY',
              controller: streetController,
              placeholder: 'Koramangala 4th Block',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _CityAutocompleteField(
                    label: 'CITY',
                    controller: cityController,
                    placeholder: 'Bengaluru',
                    onSearch: (query) => parentState.searchCities(query),
                    onSelected: () => parentState._geocodeAddressFields(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _AddressTextField(
                    label: 'PIN CODE',
                    controller: pincodeController,
                    placeholder: '560034',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFCDE0B6)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: parentState._mapController,
                      options: MapOptions(
                        initialCenter: mapPosition,
                        initialZoom: 13.0,
                        onTap: (tapPosition, point) {
                          parentState._updateLocation(point);
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: MapboxConfig.accessToken.isNotEmpty
                              ? 'https://api.mapbox.com/styles/v1/${MapboxConfig.styleId}/tiles/256/{z}/{x}/{y}@2x?access_token=${MapboxConfig.accessToken}'
                              : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.hestia_consumer_app',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: mapPosition,
                              width: 50,
                              height: 50,
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: Colors.redAccent,
                                size: 40,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
                              'Tap map to set pin',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: _CoverageCard(
                        hubName: hubName,
                        hubEst: hubEst,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF2FAE9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFB7DDA3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF8BC34A), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Great news! Your address falls within our $hubZone coverage zone. Services are available from tomorrow.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF3E5C2C),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  final String label;
  final bool selected;

  const _ReasonChip({required this.label, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: selected ? HestiaColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: selected ? HestiaColors.primary : HestiaColors.inputBorder,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          color: selected ? Colors.white : HestiaColors.textDark,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HouseholdMemberCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final String icon;
  final Color accentColor;
  final VoidCallback onRemove;

  const _HouseholdMemberCard({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F3EE),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(icon, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: HestiaColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: HestiaColors.textMedium,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, color: HestiaColors.textLight, size: 20),
          ),
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color background;

  const _IconBadge({required this.icon, required this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: HestiaColors.primary, size: 24),
    );
  }
}

class _AddressTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String placeholder;

  const _AddressTextField({
    required this.label,
    required this.controller,
    required this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: HestiaColors.textLight,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontWeight: FontWeight.normal,
            ),
            filled: true,
            fillColor: const Color(0xFF343434),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: HestiaColors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _CoverageCard extends StatelessWidget {
  final String hubName;
  final String hubEst;
  const _CoverageCard({required this.hubName, required this.hubEst});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.circle, size: 10, color: Color(0xFF77B255)),
              const SizedBox(width: 8),
              Text(
                'Covered by $hubName',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: HestiaColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Est. availability: $hubEst',
            style: const TextStyle(
              fontSize: 12,
              color: HestiaColors.textMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _CityAutocompleteField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String placeholder;
  final FutureOr<Iterable<String>> Function(String) onSearch;
  final VoidCallback onSelected;

  const _CityAutocompleteField({
    required this.label,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: HestiaColors.textLight,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        RawAutocomplete<String>(
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
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: widget.placeholder,
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontWeight: FontWeight.normal,
                ),
                filled: true,
                fillColor: const Color(0xFF343434),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
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
                color: const Color(0xFF343434),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 170, // Fits nicely inside half screen Row column
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: const Color(0xFF343434),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: HestiaColors.inputBorder, width: 0.5),
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (BuildContext context, int index) {
                      final String option = options.elementAt(index);
                      return GestureDetector(
                        onTap: () {
                          onSelected(option);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            border: index < options.length - 1
                                ? const Border(bottom: BorderSide(color: Color(0xFF444444), width: 0.5))
                                : null,
                          ),
                          child: Text(
                            option,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
