import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../config/mapbox_config.dart';
import '../theme/colors.dart';
import 'add_address_screen.dart';

class ConfirmLocationScreen extends StatefulWidget {
  final bool isPostSignInJourney;
  final String? primaryReason;
  final List<Map<String, dynamic>>? members;

  const ConfirmLocationScreen({
    super.key,
    this.isPostSignInJourney = false,
    this.primaryReason,
    this.members,
  });

  @override
  State<ConfirmLocationScreen> createState() => _ConfirmLocationScreenState();
}

class _ConfirmLocationScreenState extends State<ConfirmLocationScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();
  
  LatLng _currentMapPosition = const LatLng(12.9345, 77.6258);
  bool _isLoading = true;
  Timer? _debounceTimer;

  // Search state
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  // Geocoded location state
  String _resolvedLocality = "Sriramnagar";
  String _resolvedFullAddress = "Sriramnagar, Brahmapur, Odisha, India, 760006";
  String _flat = "";
  String _street = "Sriramnagar";
  String _city = "Brahmapur";
  String _pincode = "760006";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCurrentLocation();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
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
      _mapController.move(point, 16.0);
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
    // Center map on Brahmapur, Sriramnagar mockup coordinate (approx 19.315, 84.794)
    final fallbackPoint = const LatLng(19.3150, 84.7940);
    setState(() {
      _currentMapPosition = fallbackPoint;
      _isLoading = false;
    });
    _mapController.move(fallbackPoint, 16.0);
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
      _mapController.move(point, 16.0);
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
      _resolvedLocality = "Locating...";
      _resolvedFullAddress = "Fetching address details...";
    });

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1000), () {
      _reverseGeocodeCenter(center.latitude, center.longitude);
    });
  }

  Future<void> _reverseGeocodeCenter(double lat, double lng) async {
    Map<String, String>? addressData;
    if (MapboxConfig.accessToken.isNotEmpty) {
      addressData = await _reverseGeocodeMapbox(lat, lng);
    }
    addressData ??= await _reverseGeocodeOSM(lat, lng);

    if (addressData != null && mounted) {
      setState(() {
        final flat = addressData!['flat'] ?? '';
        final street = addressData['street'] ?? '';
        final city = addressData['city'] ?? '';
        final pincode = addressData['pincode'] ?? '';

        _resolvedLocality = street.isNotEmpty ? street.split(',').first : city;

        List<String> parts = [];
        if (flat.isNotEmpty) parts.add(flat);
        if (street.isNotEmpty) parts.add(street);
        if (city.isNotEmpty) parts.add(city);
        parts.add("India");
        if (pincode.isNotEmpty) parts.add(pincode);

        _resolvedFullAddress = parts.join(", ");

        _flat = flat;
        _street = street;
        _city = city;
        _pincode = pincode;
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
          final placeName = first['place_name'] as String? ?? '';
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

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () async {
      if (query.trim().isEmpty) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
        return;
      }
      setState(() {
        _isSearching = true;
      });
      final results = await _searchPlaces(query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    });
  }

  Future<List<Map<String, dynamic>>> _searchPlaces(String query) async {
    if (query.trim().isEmpty) return [];

    if (MapboxConfig.accessToken.isNotEmpty) {
      try {
        final client = HttpClient();
        final uri = Uri.parse(
          'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json?access_token=${MapboxConfig.accessToken}&country=in&limit=5'
        );
        final request = await client.getUrl(uri);
        final response = await request.close();
        if (response.statusCode == 200) {
          final jsonString = await response.transform(utf8.decoder).join();
          final data = json.decode(jsonString);
          final features = data['features'] as List?;
          if (features != null) {
            return features.map<Map<String, dynamic>>((f) {
              final placeName = f['place_name'] as String? ?? '';
              final center = f['center'] as List?;
              double lat = 12.9345;
              double lng = 77.6258;
              if (center != null && center.length >= 2) {
                lng = (center[0] as num).toDouble();
                lat = (center[1] as num).toDouble();
              }
              return {
                'place_name': placeName,
                'lat': lat,
                'lng': lng,
              };
            }).toList();
          }
        }
      } catch (e) {
        debugPrint("Error searching Mapbox places: $e");
      }
    }
    return [];
  }

  Future<void> _confirmLocation() async {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => AddAddressScreen(
          editMode: true,
          initialAddress: {
            'flat': _flat,
            'street': _street,
            'city': _city,
            'pincode': _pincode,
          },
          initialCoords: _currentMapPosition,
          isPostSignInJourney: widget.isPostSignInJourney,
          primaryReason: widget.primaryReason,
          members: widget.members,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const greenAccent = HestiaColors.primary;
    const darkText = Color(0xFF1E1E1E);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background map
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

          // Central Marker Pin + Callout tooltip overlay
          // Stack coordinates for center of screen
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40.0), // Offset slightly to align pin point at screen center
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Black callout tooltip bubble
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF222222),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "Set this as your location",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _resolvedLocality,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Tooltip bottom arrow triangle pointer
                    CustomPaint(
                      size: const Size(12, 6),
                      painter: _TrianglePainter(color: const Color(0xFF222222)),
                    ),
                    const SizedBox(height: 8),
                    // Green location marker icon
                    const Icon(
                      Icons.location_on,
                      color: greenAccent,
                      size: 40,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Custom AppBar Overlaid on Top
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Column(
              children: [
                // Custom App Bar Header Row
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: darkText,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        "Confirm your location",
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: darkText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Search Input box Overlay
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1F000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextFormField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(
                      color: darkText,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search locality, sector, area',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.normal,
                        fontSize: 15,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: greenAccent,
                        size: 24,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                
                // Live Search Results Dropdown Overlay
                if (_searchController.text.trim().isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 220),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1F000000),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator(color: greenAccent)),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shrinkWrap: true,
                            itemCount: _searchResults.length,
                            separatorBuilder: (context, index) => const Divider(color: Color(0xFFF0F0F0), height: 1),
                            itemBuilder: (context, index) {
                              final item = _searchResults[index];
                              return ListTile(
                                leading: const Icon(Icons.location_on_outlined, color: Colors.grey),
                                title: Text(
                                  item['place_name'],
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: darkText),
                                ),
                                onTap: () {
                                  final point = LatLng(item['lat'], item['lng']);
                                  _mapController.move(point, 16.0);
                                  setState(() {
                                    _currentMapPosition = point;
                                    _searchController.clear();
                                    _searchResults = [];
                                  });
                                  _reverseGeocodeCenter(point.latitude, point.longitude);
                                },
                              );
                            },
                          ),
                  ),
              ],
            ),
          ),

          // Floating GPS Target button (Top-Right)
          Positioned(
            top: MediaQuery.of(context).padding.top + 130,
            right: 16,
            child: GestureDetector(
              onTap: _goToCurrentLocation,
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.my_location,
                  color: darkText,
                  size: 24,
                ),
              ),
            ),
          ),

          // "Go to current location" Button centered above bottom panel
          Positioned(
            bottom: 220,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _goToCurrentLocation,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.my_location,
                        color: greenAccent,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        "Go to current location",
                        style: TextStyle(
                          color: greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom sheet details panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 16,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Bottom sheet green pin icon container
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFAF2EB),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.location_on,
                          color: greenAccent,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      
                      // Address textual info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _resolvedLocality,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: darkText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _resolvedFullAddress,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade500,
                                height: 1.4,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Confirm location button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _confirmLocation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: greenAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        "Confirm location",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Initial Loading indicator overlay
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
