import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../config/mapbox_config.dart';
import '../services/supabase_service.dart';
import 'confirm_location_screen.dart';
import '../theme/colors.dart';
import 'home_screen.dart';

class SearchLocationScreen extends StatefulWidget {
  final bool isPostSignInJourney;
  final String? primaryReason;
  final List<Map<String, dynamic>>? members;

  const SearchLocationScreen({
    super.key,
    this.isPostSignInJourney = false,
    this.primaryReason,
    this.members,
  });

  @override
  State<SearchLocationScreen> createState() => _SearchLocationScreenState();
}

class _SearchLocationScreenState extends State<SearchLocationScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _isLoading = true;
  Timer? _debounceTimer;

  Map<String, dynamic>? _dbAddress;
  String _phone = '';
  bool _useFallbackMock = true;
  List<Map<String, dynamic>> _savedAddresses = [];

  @override
  void initState() {
    super.initState();
    _loadAddress();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAddress() async {
    final user = SupabaseService.currentUser;
    if (user != null) {
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }
      try {
        final addresses = await SupabaseService.getUserAddresses(user.id);
        if (mounted) {
          setState(() {
            _savedAddresses = addresses;
            if (addresses.isNotEmpty) {
              final primaryAddress = addresses.firstWhere((a) => a['is_primary'] == true, orElse: () => addresses.first);
              _dbAddress = primaryAddress;
              _useFallbackMock = false;
            } else {
              _dbAddress = null;
              _useFallbackMock = true;
            }
          });
        }

        // Also fetch user profile details to resolve phone if needed
        Map<String, dynamic>? profileData = await SupabaseService.getUserProfile(user.id);
        if (profileData != null && mounted) {
          setState(() {
            final authPhone = SupabaseService.currentUserPhone;
            _phone = (profileData['phone'] as String?)?.isNotEmpty == true
                ? profileData['phone'] as String
                : authPhone;
          });
        }
      } catch (e) {
        debugPrint('Error loading address: $e');
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () async {
      if (query.trim().isEmpty) {
        if (mounted) {
          setState(() {
            _searchResults = [];
            _isSearching = false;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _isSearching = true;
        });
      }
      final results = await _searchPlaces(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
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
              
              String street = f['text'] as String? ?? '';
              String city = 'Bengaluru';
              String pincode = '';
              
              final contextList = f['context'] as List?;
              if (contextList != null) {
                for (var item in contextList) {
                  final id = item['id'] as String? ?? '';
                  if (id.startsWith('postcode')) {
                    pincode = item['text'] as String? ?? '';
                  } else if (id.startsWith('place')) {
                    city = item['text'] as String? ?? '';
                  } else if (id.startsWith('locality') || id.startsWith('neighborhood')) {
                    street = "${item['text']}, $street";
                  }
                }
              }
              
              return {
                'place_name': placeName,
                'lat': lat,
                'lng': lng,
                'flat': '',
                'street': street,
                'city': city,
                'pincode': pincode,
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

  @override
  Widget build(BuildContext context) {
    const greenAccent = HestiaColors.primary;

    // Format address text to display
    String addressText = "89, Usuw, Pocket 25, Pocket 25, Bharat singh, Pista, New Delhi, Delhi, India, 110085,";
    if (!_useFallbackMock && _dbAddress != null) {
      final flat = _dbAddress!['flat'] ?? '';
      final street = _dbAddress!['street'] ?? '';
      final city = _dbAddress!['city'] ?? '';
      final pin = _dbAddress!['pincode'] ?? _dbAddress!['pin_code'] ?? '';
      List<String> parts = [];
      if (flat.toString().isNotEmpty) parts.add(flat);
      if (street.toString().isNotEmpty) parts.add(street);
      if (city.toString().isNotEmpty) parts.add(city);
      parts.add("India");
      if (pin.toString().isNotEmpty) parts.add(pin);
      addressText = "${parts.join(", ")},";
    }

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
          title: const Text(
            'Search your location',
            style: TextStyle(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search box - liquid glass
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                          width: 1.5,
                        ),
                      ),
                      child: TextFormField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search locality, sector, area',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontWeight: FontWeight.normal,
                            fontSize: 15,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.white,
                            size: 24,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Search Suggestions or Action Items & Saved Addresses
              Expanded(
                child: _searchController.text.trim().isNotEmpty
                    ? _buildSearchSuggestions(greenAccent)
                    : _buildHomeState(greenAccent, addressText),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchSuggestions(Color greenAccent) {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: Colors.white70),
            const SizedBox(height: 12),
            Text(
              "No results found",
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 15),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
                width: 1.5,
              ),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              itemCount: _searchResults.length,
              separatorBuilder: (context, index) => Divider(color: Colors.white.withValues(alpha: 0.15), height: 1),
              itemBuilder: (context, index) {
                final item = _searchResults[index];
                return ListTile(
                  leading: const Icon(Icons.location_on_outlined, color: Colors.white),
                  title: Text(
                    item['place_name'],
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                  onTap: () {
                    // Push ConfirmLocationScreen with search data pre-filled
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ConfirmLocationScreen(
                          editMode: true,
                          initialAddress: {
                            'flat': '',
                            'street': item['street'],
                            'city': item['city'],
                            'pincode': item['pincode'],
                          },
                          initialCoords: LatLng(item['lat'], item['lng']),
                          isPostSignInJourney: widget.isPostSignInJourney,
                          primaryReason: widget.primaryReason,
                          members: widget.members,
                        ),
                      ),
                    ).then((_) => _loadAddress());
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeState(Color greenAccent, String addressText) {
    return _isLoading
        ? Center(
            child: CircularProgressIndicator(color: greenAccent),
          )
        : SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Grouped Card: Add Address + Use Current Location - liquid glass
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          // "+ Add address"
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => ConfirmLocationScreen(
                                    editMode: false,
                                    isPostSignInJourney: widget.isPostSignInJourney,
                                    primaryReason: widget.primaryReason,
                                    members: widget.members,
                                  ),
                                ),
                              ).then((_) => _loadAddress());
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 18.0),
                              child: Row(
                                children: [
                                  const Icon(Icons.add, color: Colors.white, size: 22),
                                  const SizedBox(width: 14),
                                  const Expanded(
                                    child: Text(
                                      'Add address',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.6), size: 20),
                                ],
                              ),
                            ),
                          ),
                          
                          // Divider
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0),
                            child: Divider(color: Colors.white.withValues(alpha: 0.15), height: 1),
                          ),

                          // "Use current location"
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => ConfirmLocationScreen(
                                    editMode: false,
                                    useCurrentLocation: true,
                                    isPostSignInJourney: widget.isPostSignInJourney,
                                    primaryReason: widget.primaryReason,
                                    members: widget.members,
                                  ),
                                ),
                              ).then((_) => _loadAddress());
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 18.0),
                              child: Row(
                                children: [
                                  const Icon(Icons.my_location, color: Colors.white, size: 20),
                                  const SizedBox(width: 16),
                                  const Expanded(
                                    child: Text(
                                      'Use current location',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.6), size: 20),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                if (_savedAddresses.isNotEmpty) ...[
                  const SizedBox(height: 28),

                  // SAVED ADDRESSES header
                  const Text(
                    'SAVED ADDRESSES',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6F4E37),
                      letterSpacing: 1.2,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Column(
                    children: _savedAddresses.map((address) {
                      final flatVal = address['flat'] ?? '';
                      final label = SupabaseService.getAddressLabel(flatVal);
                      final cleanFlat = SupabaseService.cleanFlatName(flatVal);
                      
                      final street = address['street'] ?? '';
                      final city = address['city'] ?? '';
                      final pin = address['pin_code'] ?? address['pincode'] ?? '';
                      final isPrimary = _dbAddress != null && address['id'] == _dbAddress!['id'];

                      List<String> parts = [];
                      if (cleanFlat.isNotEmpty) parts.add(cleanFlat);
                      if (street.isNotEmpty) parts.add(street);
                      if (city.isNotEmpty) parts.add(city);
                      parts.add("India");
                      if (pin.toString().isNotEmpty) parts.add(pin.toString());
                      final currentAddressText = "${parts.join(", ")},";

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
                            child: GestureDetector(
                              onTap: () async {
                                final user = SupabaseService.currentUser;
                                if (user != null && !isPrimary) {
                                  setState(() {
                                    _isLoading = true;
                                  });
                                  await SupabaseService.setPrimaryAddress(user.id, address['id'] as String);
                                  await _loadAddress();
                                }
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(20.0),
                                decoration: BoxDecoration(
                                  color: isPrimary
                                      ? const Color(0xFFF5ECE3).withValues(alpha: 0.9)
                                      : const Color(0xFFF5ECE3).withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isPrimary
                                        ? const Color(0xFFD4BCA2)
                                        : const Color(0xFFE6D5C5).withValues(alpha: 0.6),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Location Pin / Home / Work badge (brown tinted glass container)
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE6D5C5).withValues(alpha: 0.4),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        label == 'Home'
                                            ? Icons.home_outlined
                                            : (label == 'Work' ? Icons.work_outline : Icons.location_on_outlined),
                                        color: const Color(0xFF6F4E37),
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    
                                    // Address Details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Expanded(
                                                child: Wrap(
                                                  crossAxisAlignment: WrapCrossAlignment.center,
                                                  spacing: 8,
                                                  runSpacing: 4,
                                                  children: [
                                                    Text(
                                                      label ?? 'Address',
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.bold,
                                                        color: Color(0xFF5E3D1D),
                                                      ),
                                                    ),
                                                    if (isPrimary)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFFAF2EB),
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: const Text(
                                                          'Currently selected',
                                                          style: TextStyle(
                                                            color: HestiaColors.primary,
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuButton<String>(
                                                icon: const Icon(
                                                  Icons.more_vert,
                                                  color: Color(0xFF6F4E37),
                                                  size: 20,
                                                ),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(
                                                  minWidth: 150,
                                                ),
                                                onSelected: (value) async {
                                                  final user = SupabaseService.currentUser;
                                                  if (user == null) return;

                                                  if (value == 'edit') {
                                                    Navigator.of(context).push(
                                                      MaterialPageRoute(
                                                        builder: (context) => ConfirmLocationScreen(
                                                          editMode: true,
                                                          initialAddress: {
                                                            'flat': cleanFlat,
                                                            'street': street,
                                                            'city': city,
                                                            'pincode': pin,
                                                          },
                                                          initialCoords: const LatLng(28.6139, 77.2090),
                                                          isPostSignInJourney: widget.isPostSignInJourney,
                                                          primaryReason: widget.primaryReason,
                                                          members: widget.members,
                                                        ),
                                                      ),
                                                    ).then((_) => _loadAddress());
                                                  } else if (value == 'home') {
                                                    setState(() {
                                                      _isLoading = true;
                                                    });
                                                    final newLabel = label == 'Home' ? null : 'Home';
                                                    await SupabaseService.setAddressLabel(user.id, address['id'] as String, newLabel);
                                                    await _loadAddress();
                                                  } else if (value == 'work') {
                                                    setState(() {
                                                      _isLoading = true;
                                                    });
                                                    final newLabel = label == 'Work' ? null : 'Work';
                                                    await SupabaseService.setAddressLabel(user.id, address['id'] as String, newLabel);
                                                    await _loadAddress();
                                                  } else if (value == 'delete') {
                                                    final confirm = await showDialog<bool>(
                                                      context: context,
                                                      builder: (context) => AlertDialog(
                                                        title: const Text('Delete Address'),
                                                        content: const Text('Are you sure you want to delete this saved address?'),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () => Navigator.pop(context, false),
                                                            child: const Text('Cancel'),
                                                          ),
                                                          TextButton(
                                                            onPressed: () => Navigator.pop(context, true),
                                                            child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                    if (confirm == true) {
                                                      setState(() {
                                                        _isLoading = true;
                                                      });
                                                      await SupabaseService.deleteAddress(address['id'] as String);
                                                      await _loadAddress();
                                                    }
                                                  }
                                                },
                                                itemBuilder: (context) => [
                                                  const PopupMenuItem<String>(
                                                    value: 'edit',
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.edit_outlined, size: 18, color: Color(0xFF6F4E37)),
                                                        SizedBox(width: 8),
                                                        Text('Edit Address'),
                                                      ],
                                                    ),
                                                  ),
                                                  PopupMenuItem<String>(
                                                    value: 'home',
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          label == 'Home' ? Icons.home : Icons.home_outlined,
                                                          size: 18,
                                                          color: const Color(0xFF6F4E37),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Text(label == 'Home' ? 'Remove Home Label' : 'Mark as Home'),
                                                      ],
                                                    ),
                                                  ),
                                                  PopupMenuItem<String>(
                                                    value: 'work',
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          label == 'Work' ? Icons.work : Icons.work_outline,
                                                          size: 18,
                                                          color: const Color(0xFF6F4E37),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Text(label == 'Work' ? 'Remove Work Label' : 'Mark as Work'),
                                                      ],
                                                    ),
                                                  ),
                                                  const PopupMenuItem<String>(
                                                    value: 'delete',
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                                        SizedBox(width: 8),
                                                        Text(
                                                          'Delete Address',
                                                          style: TextStyle(color: Colors.redAccent),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            currentAddressText,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFF6F4E37),
                                              height: 1.45,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Mobile: $_phone',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFF6F4E37),
                                            ),
                                          ),
                                          if (widget.isPostSignInJourney && isPrimary) ...[
                                            const SizedBox(height: 16),
                                            GestureDetector(
                                              onTap: () => _confirmExistingAddress(context, currentAddressText),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: HestiaColors.primary,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Text(
                                                  'CONFIRM & CONTINUE',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          );
  }

  Future<void> _confirmExistingAddress(BuildContext context, String addressText) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          color: HestiaColors.primary,
        ),
      ),
    );

    final user = SupabaseService.currentUser;
    if (user != null) {
      final fullName = user.userMetadata?['full_name'] ?? 'User';
      final authPhone = SupabaseService.currentUserPhone;
      final phone = authPhone.isNotEmpty
          ? authPhone
          : (_phone.isNotEmpty ? _phone : null);
      final email = user.userMetadata?['email'] ?? user.email ?? '';

      final addressToSave = _useFallbackMock || _dbAddress == null
          ? {
              'flat': '89, Usuw',
              'street': 'Pocket 25, Pocket 25, Bharat singh, Pista',
              'city': 'New Delhi',
              'pincode': '110085',
            }
          : {
              'flat': _dbAddress!['flat'] ?? '',
              'street': _dbAddress!['street'] ?? '',
              'city': _dbAddress!['city'] ?? '',
              'pincode': _dbAddress!['pincode'] ?? _dbAddress!['pin_code'] ?? '',
            };

      try {
        await SupabaseService.saveUserProfile(
          id: user.id,
          fullName: fullName,
          email: email,
          phone: phone,
          primaryReason: widget.primaryReason ?? 'New mother',
          members: widget.members ?? [],
          address: addressToSave,
        );

        final profileData = {
          'id': user.id,
          'name': fullName,
          'email': email,
          'phone': phone,
          'primary_reason': widget.primaryReason ?? 'New mother',
          'household_members': widget.members ?? [],
          'address': addressToSave,
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
      } catch (e) {
        debugPrint('Warning: Could not save profile: $e');
      }
    }

    if (context.mounted) {
      Navigator.of(context).pop(); // Pop loading dialog
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    }
  }
}
