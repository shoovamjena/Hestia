import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../config/mapbox_config.dart';
import '../theme/colors.dart';
import '../services/supabase_service.dart';
import '../services/session_arrival_coordinator.dart';
import 'service_detail_screen.dart';
import 'repeat_booking_screen.dart';
import 'schedule_screen.dart';
import '../utils/active_booking_navigation.dart';
import '../utils/string_format.dart';
import 'rate_session_screen.dart';
import 'session_detail_screen.dart';
import 'receipt_screen.dart';
import 'search_location_screen.dart';
import 'profile_screen.dart';
import 'pronto_money_screen.dart';
import 'refer_and_earn_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String _userName = 'User';
  String _userInitials = 'U';
  String _location = 'Set Address';
  String _primaryReason = '';
  String _email = '';
  String _phone = '';
  int _currentTabIndex = 0;
  int _oldTabIndex = 0;
  int _heroPageIndex = 0;
  bool _isWithinCoverage = true;
  String? _cancellingBookingId;
  bool _notifyRequested = false;
  final Map<String, int> _serviceMinutes = {};
  Map<String, dynamic>? _activeBooking;
  int? _activeBookingEtaMin;
  Timer? _activeBookingPollTimer;
  StreamSubscription<SessionArrivalEvent>? _arrivalSub;
  List<Map<String, dynamic>> _recentSessions = [];
  AnimationController? _navAnimationController;
  String _selectedSessionCategory = 'All';
  String _sessionSearchQuery = '';
  List<Map<String, dynamic>> _upcomingBookings = [];
  int _bookingsSubTab = 0; // 0 for Upcoming, 1 for History

  static const List<
    ({
      String label,
      String price,
      String originalPrice,
      String rating,
      String ratingCount,
    })
  >
  _homeServiceCatalog = [
    (
      label: 'Post-Delivery',
      price: '₹499',
      originalPrice: '₹999',
      rating: '4.9',
      ratingCount: '38.6k',
    ),
    (
      label: 'Babysitting',
      price: '₹399',
      originalPrice: '₹799',
      rating: '4.9',
      ratingCount: '31.5k',
    ),
    (
      label: 'Mobility',
      price: '₹449',
      originalPrice: '₹899',
      rating: '4.9',
      ratingCount: '39.7k',
    ),
    (
      label: 'Pre-Pregnancy',
      price: '₹599',
      originalPrice: '₹999',
      rating: '4.9',
      ratingCount: '13.4k',
    ),
    (
      label: 'Bathing',
      price: '₹349',
      originalPrice: '₹699',
      rating: '4.9',
      ratingCount: '4.5k',
    ),
    (
      label: 'Concierge',
      price: '₹299',
      originalPrice: '₹599',
      rating: '4.9',
      ratingCount: '3.3k',
    ),
  ];

  Widget _buildServiceIconImage(
    String label, {
    double size = 50,
    bool cover = false,
  }) {
    final assetPath = ServiceDetailScreen.iconAssetFor(label);

    if (cover) {
      return Image.asset(
        assetPath,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: const Color(0xFFBCA99B),
            alignment: Alignment.center,
            child: Icon(
              Icons.medical_services_outlined,
              size: size * 0.55,
              color: HestiaColors.primary,
            ),
          );
        },
      );
    }

    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Icon(
          Icons.medical_services_outlined,
          size: size,
          color: HestiaColors.primary,
        );
      },
    );
  }

  Widget _buildServiceIconBadge(
    String title, {
    double size = 44,
    double iconSize = 28,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFFAF2EB),
        shape: BoxShape.circle,
      ),
      padding: EdgeInsets.all((size - iconSize) / 2),
      child: Image.asset(
        ServiceDetailScreen.iconAssetFor(title),
        width: iconSize,
        height: iconSize,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Icon(
            Icons.medical_services_outlined,
            color: HestiaColors.primary,
            size: iconSize,
          );
        },
      ),
    );
  }

  void _initAnimationController() {
    _navAnimationController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..value = 1.0;
  }

  @override
  void initState() {
    super.initState();
    _initAnimationController();
    _loadProfileData();
    _arrivalSub = SessionArrivalCoordinator.instance.events.listen((_) {
      if (mounted) _refreshActiveBookingQuietly();
    });
    _activeBookingPollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _refreshActiveBookingQuietly();
    });
  }

  @override
  void dispose() {
    _arrivalSub?.cancel();
    _activeBookingPollTimer?.cancel();
    _navAnimationController?.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    // Set defaults from Auth user metadata first
    final metadataName = displayPersonName(
      user.userMetadata?['full_name']?.toString(),
      fallback: 'User',
    );
    if (mounted) {
      setState(() {
        _userName = metadataName;
        _userInitials = _getInitials(metadataName);
        _email = SupabaseService.currentUserEmail;
        _phone = SupabaseService.currentUserPhone;
      });
    }

    Map<String, dynamic>? profileData;
    Map<String, dynamic>? activeBooking;
    List<Map<String, dynamic>> recent = [];
    List<Map<String, dynamic>> upcoming = [];

    try {
      // Resolve no-shows before loading upcoming, so lists stay in sync.
      activeBooking = await SupabaseService.getActiveBooking(user.id)
          .timeout(const Duration(seconds: 12), onTimeout: () => null);
      final results = await Future.wait<dynamic>([
        () async {
          var data = await SupabaseService.getUserProfile(user.id);
          if (data == null || data['address'] == null) {
            data = await SupabaseService.downloadProfileJson(user.id);
          }
          return data;
        }(),
        SupabaseService.getRecentSessions(user.id),
        SupabaseService.getUpcomingBookings(user.id),
      ]).timeout(
        const Duration(seconds: 15),
        onTimeout: () => <dynamic>[null, <Map<String, dynamic>>[], <Map<String, dynamic>>[]],
      );

      profileData = results[0] as Map<String, dynamic>?;
      recent = (results[1] as List?)?.cast<Map<String, dynamic>>() ?? [];
      upcoming = (results[2] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      debugPrint('Error loading home screen data: $e');
    } finally {
      if (mounted) {
        setState(() {
          if (profileData != null) {
            _userName = displayPersonName(
              profileData['name']?.toString(),
              fallback: _userName,
            );
            _userInitials = _getInitials(_userName);
            _email = profileData['email'] ?? _email;
            _phone = profileData['phone'] ?? _phone;
            _primaryReason = profileData['primary_reason'] ?? '';
            if (profileData['address'] != null) {
              final street = profileData['address']['street'] ?? '';
              final city = profileData['address']['city'] ?? '';
              _location = street.isNotEmpty ? '$street · $city' : city;
              _isWithinCoverage =
                  profileData['address']['zone_verified'] == true;
            }
          }
          _activeBooking = activeBooking;
          if (activeBooking == null ||
              !isProfessionalOnTheWay(activeBooking)) {
            _activeBookingEtaMin = null;
          }
          _recentSessions = recent;
          _upcomingBookings = upcoming;
          _isLoading = false;
        });
      }
    }

    if (!mounted) return;

    if (activeBooking != null && isProfessionalOnTheWay(activeBooking)) {
      // Never block home render on ETA lookups.
      unawaited(_refreshActiveBookingEta(activeBooking));
    }

    // Align home coverage with the same geo check assign-professionals uses
    final addr = profileData?['address'] as Map<String, dynamic>?;
    final lat = double.tryParse(addr?['latitude']?.toString() ?? '');
    final lng = double.tryParse(addr?['longitude']?.toString() ?? '');
    if (lat != null && lng != null) {
      try {
        final within = await SupabaseService.isPointWithinCoverage(lat, lng)
            .timeout(const Duration(seconds: 6), onTimeout: () => _isWithinCoverage);
        if (mounted && within != _isWithinCoverage) {
          setState(() => _isWithinCoverage = within);
        }
      } catch (_) {}
    }
  }

  Future<void> _refreshActiveBookingQuietly() async {
    final user = SupabaseService.currentUser;
    if (user == null || !mounted) return;
    try {
      final activeBooking = await SupabaseService.getActiveBooking(user.id);
      if (!mounted) return;
      final previousId = _activeBooking?['booking_id']?.toString();
      final nextId = activeBooking?['booking_id']?.toString();
      final previousStatus = _activeBooking?['status']?.toString();
      final nextStatus = activeBooking?['status']?.toString();
      setState(() {
        _activeBooking = activeBooking;
        if (activeBooking == null ||
            !isProfessionalOnTheWay(activeBooking)) {
          _activeBookingEtaMin = null;
        }
      });
      if (activeBooking != null &&
          isProfessionalOnTheWay(activeBooking) &&
          (previousId != nextId ||
              previousStatus != nextStatus ||
              _activeBookingEtaMin == null)) {
        _refreshActiveBookingEta(activeBooking);
      }
    } catch (_) {}
  }

  Future<Map<String, double>?> _geocodeAddressForEta(String address) async {
    if (address.trim().isEmpty) return null;
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final url =
          'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(address)}.json?access_token=${MapboxConfig.accessToken}&limit=1';
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(const Duration(seconds: 8));
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return null;
      final center = (features.first as Map<String, dynamic>)['center'] as List?;
      if (center == null || center.length < 2) return null;
      return {
        'lng': (center[0] as num).toDouble(),
        'lat': (center[1] as num).toDouble(),
      };
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  Future<void> _refreshActiveBookingEta(Map<String, dynamic> booking) async {
    final bookingId = booking['booking_id']?.toString();
    final hubAddr = booking['hub_address']?.toString() ?? '';
    final userAddr = booking['user_address']?.toString() ?? '';
    if (hubAddr.isEmpty || userAddr.isEmpty) return;

    // Prefer professional live location when available.
    Map<String, double>? start;
    final sessionId = booking['session_id']?.toString();
    if (sessionId != null && sessionId.isNotEmpty) {
      try {
        final live = await SupabaseService.getLatestProfessionalLocation(
          sessionId,
          professionalId: booking['professional_id']?.toString(),
        ).timeout(const Duration(seconds: 6), onTimeout: () => null);
        if (live != null) {
          start = {
            'lat': live['latitude']!,
            'lng': live['longitude']!,
          };
        }
      } catch (_) {}
    }
    start ??= await _geocodeAddressForEta(hubAddr);
    final end = await _geocodeAddressForEta(userAddr);
    if (start == null || end == null) return;

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final url =
          'https://api.mapbox.com/directions/v5/mapbox/driving/${start['lng']},${start['lat']};${end['lng']},${end['lat']}?access_token=${MapboxConfig.accessToken}';
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(const Duration(seconds: 8));
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return;
      final durationSec =
          (routes.first as Map<String, dynamic>)['duration'] as num?;
      if (durationSec == null) return;
      final minutes = (durationSec / 60.0).round().clamp(1, 999);
      if (!mounted) return;
      if (_activeBooking?['booking_id']?.toString() != bookingId) return;
      setState(() => _activeBookingEtaMin = minutes);
    } catch (_) {
    } finally {
      client?.close(force: true);
    }
  }

  String _getInitials(String name) {
    if (name.isEmpty) return 'U';
    final parts = name.trim().split(' ');
    if (parts.length > 1) {
      return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  String _formatBookingDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final bookingDay = DateTime(date.year, date.month, date.day);

    if (bookingDay == today) {
      return 'Today';
    } else if (bookingDay == tomorrow) {
      return 'Tomorrow';
    } else {
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[date.month - 1]} ${date.day}';
    }
  }

  String _formatBookingTime(DateTime date) {
    int hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;
    return '$hour:$minute $period';
  }

  _AvailableSlot _getRecentAvailableSlot() {
    final now = DateTime.now();
    final limitTime = now.add(const Duration(hours: 1));

    final List<String> slots = [
      '7:00 AM',
      '7:30 AM',
      '8:00 AM',
      '8:30 AM',
      '9:00 AM',
      '9:30 AM',
      '10:00 AM',
      '10:30 AM',
      '11:00 AM',
      '11:30 AM',
      '12:00 PM',
      '12:30 PM',
      '1:00 PM',
      '1:30 PM',
      '2:00 PM',
      '2:30 PM',
      '3:00 PM',
      '3:30 PM',
      '4:00 PM',
      '4:30 PM',
      '5:00 PM',
      '5:30 PM',
      '6:00 PM',
      '6:30 PM',
      '7:00 PM',
      '7:30 PM',
      '8:00 PM',
      '8:30 PM',
    ];

    DateTime? parseSlot(String slotStr) {
      try {
        final parts = slotStr.split(' ');
        final timeParts = parts[0].split(':');
        int hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        final amPm = parts[1].toUpperCase();

        if (amPm == 'PM' && hour != 12) {
          hour += 12;
        } else if (amPm == 'AM' && hour == 12) {
          hour = 0;
        }
        return DateTime(now.year, now.month, now.day, hour, minute);
      } catch (_) {
        return null;
      }
    }

    for (final slot in slots) {
      if (slot == '7:00 PM' || slot == '8:00 PM' || slot == '8:30 PM') continue;
      final slotTime = parseSlot(slot);
      if (slotTime != null && slotTime.isAfter(limitTime)) {
        return _AvailableSlot(
          displayString: 'Next slot at $slot',
          date: DateTime(now.year, now.month, now.day),
          slot: slot,
        );
      }
    }

    final tomorrow = now.add(const Duration(days: 1));
    return _AvailableSlot(
      displayString: 'Next slot tomorrow 7:00 AM',
      date: DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
      slot: '7:00 AM',
    );
  }

  Widget _serviceTile(
    String label,
    String price,
    String originalPrice,
    String rating,
    String ratingCount,
  ) {
    final minutes = _serviceMinutes[label] ?? 0;
    final isAdded = minutes > 0;
    final isBlocked = _isServiceBlockedByActiveBooking(label);
    final double hourlyPrice =
        double.tryParse(price.replaceAll('₹', '').trim()) ?? 0.0;
    final double origHourlyPrice =
        double.tryParse(originalPrice.replaceAll('₹', '').trim()) ?? 0.0;
    final displayPrice = isAdded
        ? '₹${(hourlyPrice * (minutes / 60.0)).toStringAsFixed(0)}'
        : '₹${hourlyPrice.toStringAsFixed(0)}';
    final displayOriginalPrice = isAdded
        ? '₹${(origHourlyPrice * (minutes / 60.0)).toStringAsFixed(0)}'
        : '₹${origHourlyPrice.toStringAsFixed(0)}';

    Future<void> addService() async {
      if (isBlocked) {
        _showSameReasonBookingBlocked(label);
        return;
      }
      setState(() {
        _serviceMinutes[label] = 30;
      });
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      _openServiceDetail(label);
    }

    return Opacity(
      opacity: isBlocked ? 0.55 : 1,
      child: GestureDetector(
        onTap: () => _openServiceDetail(label),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isBlocked
                  ? HestiaColors.primary.withValues(alpha: 0.35)
                  : const Color(0xFFEEE6DE),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 96,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(15),
                      ),
                      child: _buildServiceIconImage(label, cover: true),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star,
                            color: Color(0xFFFFB300),
                            size: 11,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '$rating ($ratingCount)',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: HestiaColors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_isWithinCoverage && !isAdded)
                    Positioned(
                      right: 8,
                      bottom: -14,
                      child: GestureDetector(
                        onTap: () {
                          addService();
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: HestiaColors.primary,
                              width: 1.6,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.add,
                            color: HestiaColors.primary,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                10,
                _isWithinCoverage && !isAdded ? 14 : 6,
                10,
                8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: HestiaColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        displayPrice,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: HestiaColors.textDark,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          displayOriginalPrice,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9E9186),
                            decoration: TextDecoration.lineThrough,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (_isWithinCoverage && isAdded) ...[
                    const SizedBox(height: 8),
                    _buildStepper(label, minutes),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  bool _isServiceBlockedByActiveBooking(String label) {
    return isServiceBlockedByActiveBooking(_activeBooking, label);
  }

  void _showSameReasonBookingBlocked(String label) {
    final activeTitle =
        _activeBooking?['title']?.toString() ?? 'this care service';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'You already have an active $activeTitle booking. '
          'You can book a different care service.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openServiceDetail(String label) {
    if (_isServiceBlockedByActiveBooking(label)) {
      _showSameReasonBookingBlocked(label);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ServiceDetailScreen(
          serviceKey: label,
          initialServicesMap: Map<String, int>.from(_serviceMinutes),
          bookingEnabled: _isWithinCoverage,
          onMinutesChanged: (newMinutes) {
            setState(() {
              if (newMinutes <= 0) {
                _serviceMinutes.remove(label);
              } else {
                _serviceMinutes[label] = newMinutes;
              }
            });
          },
        ),
      ),
    );
  }

  Widget _buildStepper(String label, int minutes) {
    return Container(
      key: const ValueKey('stepper'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: HestiaColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Minus button
          GestureDetector(
            onTap: () {
              setState(() {
                final next = minutes - 30;
                if (next <= 0) {
                  _serviceMinutes.remove(label);
                } else {
                  _serviceMinutes[label] = next;
                }
              });
            },
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              child: const Icon(Icons.remove, color: Colors.white, size: 14),
            ),
          ),
          // Duration label
          Expanded(
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Text(
                  key: ValueKey(minutes),
                  '$minutes min',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
          // Plus button
          GestureDetector(
            onTap: () {
              setState(() {
                _serviceMinutes[label] = minutes + 30;
              });
            },
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              child: const Icon(Icons.add, color: Colors.white, size: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _busyPartnerCard({
    required String nextSlot,
    required String duration,
    required String price,
    required String originalPrice,
    required String saveAmount,
    required String serviceTitle,
    required int durationMinutes,
    required DateTime initialDate,
    required String initialTimeSlot,
  }) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Colors.white, Color(0xFFFAF2EB)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              border: Border.all(
                color: HestiaColors.primary.withValues(alpha: 0.15),
                width: 1.2,
              ),
            ),
          ),
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CustomPaint(
                painter: CardGridPainter(
                  color: HestiaColors.primary.withValues(alpha: 0.04),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nextSlot,
                  style: const TextStyle(
                    fontSize: 12,
                    color: HestiaColors.textMedium,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  duration,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: HestiaColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      price,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: HestiaColors.textDark,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      originalPrice,
                      style: const TextStyle(
                        fontSize: 11,
                        color: HestiaColors.textLight,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  saveAmount,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: HestiaColors.primary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    if (_isServiceBlockedByActiveBooking(serviceTitle)) {
                      _showSameReasonBookingBlocked(serviceTitle);
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ScheduleScreen(
                          serviceTitle: serviceTitle,
                          initialServicesMap: {serviceTitle: durationMinutes},
                          initialDate: initialDate,
                          initialTimeSlot: initialTimeSlot,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: HestiaColors.primary,
                        width: 1.5,
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'Schedule',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: HestiaColors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bookLaterCard({
    required String title,
    required String pillText,
    required Widget illustration,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Colors.white, Color(0xFFFAF2EB)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            border: Border.all(
              color: HestiaColors.primary.withValues(alpha: 0.15),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: CustomPaint(
                    painter: CardGridPainter(
                      color: HestiaColors.primary.withValues(alpha: 0.04),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14.0,
                  vertical: 12.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: HestiaColors.textDark,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: HestiaColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        pillText,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: HestiaColors.primary,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(bottom: 8, right: 8, child: illustration),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trustCard({
    required String title,
    required IconData icon,
    required List<Color> gradientColors,
  }) {
    return Expanded(
      child: Container(
        height: 135,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: HestiaColors.primary.withValues(alpha: 0.15),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: HestiaColors.primary.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: HestiaColors.primary, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: HestiaColors.textDark,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookingsTab() {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F0),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            color: HestiaColors.primary,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'My Bookings',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _bookingsSubTab == 0
                          ? 'Upcoming care visits'
                          : 'Past sessions & reviews',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 44,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _bookingsSegmentButton(
                              label: 'Upcoming',
                              selected: _bookingsSubTab == 0,
                              onTap: () => setState(() => _bookingsSubTab = 0),
                            ),
                          ),
                          Expanded(
                            child: _bookingsSegmentButton(
                              label: 'History',
                              selected: _bookingsSubTab == 1,
                              onTap: () => setState(() => _bookingsSubTab = 1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _bookingsSubTab == 0
                ? _buildUpcomingView()
                : _buildHistoryView(),
          ),
        ],
      ),
    );
  }

  Widget _bookingsSegmentButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? HestiaColors.primary : Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildUpcomingView() {
    if (_upcomingBookings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 100),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF2EB),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: HestiaColors.primary.withValues(alpha: 0.15),
                  ),
                ),
                child: const Icon(
                  Icons.calendar_today_rounded,
                  color: HestiaColors.primary,
                  size: 34,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No upcoming bookings',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: HestiaColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Book a care visit from Home and it will show up here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProfileData,
      color: HestiaColors.primary,
      child: ListView.separated(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        itemCount: _upcomingBookings.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final booking = _upcomingBookings[index];
          return _buildUpcomingCard(booking);
        },
      ),
    );
  }

  Widget _buildUpcomingCard(Map<String, dynamic> booking) {
    final caregiverName = displayCaregiverName(
      booking['caregiver_name']?.toString(),
      fallback: 'Sunita Rao',
    );
    final title = booking['title'] ?? 'Post-Delivery';
    final displayTitle = title.endsWith('Care') ? title : '$title Care';
    final status = booking['status'] as String? ?? 'pending';
    final start = booking['scheduled_start'] as DateTime;
    final totalAmount = booking['amount'] != null
        ? (booking['amount'] as num).toInt()
        : 0;
    final bookingId = booking['booking_id']?.toString() ?? '';

    final now = DateTime.now();
    final isToday =
        start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow =
        start.year == tomorrow.year &&
        start.month == tomorrow.month &&
        start.day == tomorrow.day;

    final String dateStr = isToday
        ? 'Today'
        : isTomorrow
        ? 'Tomorrow'
        : _formatBookingDate(start);
    final String timeStr = _formatBookingTime(start);
    final String iconTitle = title;

    Color statusBgColor;
    Color statusTextColor;
    String statusLabel = status.toUpperCase();
    final runningLate = isProfessionalRunningLateForBooking(booking);
    final isNoShow = isNoShowBooking(booking);
    final canCancel = _canCancelUpcomingBooking(status, isNoShow);
    final isCancellingThis = _cancellingBookingId == bookingId;

    if (isNoShow) {
      statusBgColor = const Color(0xFFFDECEA);
      statusTextColor = const Color(0xFFC0392B);
      statusLabel = 'NO SHOW';
    } else if (runningLate) {
      statusBgColor = const Color(0xFFFFF3E0);
      statusTextColor = const Color(0xFFE65100);
      statusLabel = 'RUNNING LATE';
    } else if (status == 'active' ||
        status == 'in_progress' ||
        status == 'arrived') {
      statusBgColor = const Color(0xFFE8F5ED);
      statusTextColor = const Color(0xFF2E6B4A);
      statusLabel = 'ACTIVE NOW';
    } else if (status == 'confirmed' ||
        status == 'scheduled' ||
        status == 'departed' ||
        status == 'transit') {
      statusBgColor = const Color(0xFFFAF2EB);
      statusTextColor = HestiaColors.primary;
      statusLabel = status == 'departed' || status == 'transit'
          ? 'ON THE WAY'
          : 'CONFIRMED';
    } else {
      statusBgColor = const Color(0xFFFAF2EB);
      statusTextColor = HestiaColors.mutedBrown;
      statusLabel = 'PENDING';
    }

    return GestureDetector(
      onTap: () {
        openActiveBookingScreen(
          context,
          booking: booking,
          userName: _userName,
        ).then((_) => _loadProfileData());
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: HestiaColors.primary.withValues(alpha: 0.14),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildServiceIconBadge(iconTitle),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              displayTitle,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: HestiaColors.textDark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusBgColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                                color: statusTextColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$dateStr · $timeStr',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        runningLate
                            ? professionalRunningLateMessage(
                                caregiverName?.toString(),
                              )
                            : 'Professional: $caregiverName',
                        style: TextStyle(
                          fontSize: 12,
                          color: runningLate
                              ? const Color(0xFF8D4E00)
                              : Colors.grey.shade600,
                          fontWeight:
                              runningLate ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(color: const Color(0xFFF0E6DC), height: 1, thickness: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '₹$totalAmount',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: HestiaColors.textDark,
                  ),
                ),
                const Spacer(),
                if (canCancel) ...[
                  GestureDetector(
                    onTap: isCancellingThis
                        ? null
                        : () => _confirmAndCancelUpcomingBooking(booking),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        isCancellingThis ? 'Cancelling…' : 'Cancel',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isCancellingThis
                              ? Colors.grey.shade500
                              : const Color(0xFFC0392B),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Row(
                  children: [
                    Text(
                      isNoShow
                          ? 'Leave review'
                          : status == 'active' ||
                                  status == 'departed' ||
                                  status == 'transit' ||
                                  status == 'en_route'
                              ? 'Track care'
                              : 'View details',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: HestiaColors.primary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: HestiaColors.primary,
                      size: 18,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _canCancelUpcomingBooking(String status, bool isNoShow) {
    if (isNoShow) return false;
    final s = status.trim().toLowerCase();
    // Once care has started, consumer should End Session instead.
    if (s == 'active' ||
        s == 'in_progress' ||
        s == 'started' ||
        s == 'arrived' ||
        s == 'completed' ||
        s == 'cancelled' ||
        s == 'unattended' ||
        s == 'no_show') {
      return false;
    }
    return true;
  }

  Future<void> _confirmAndCancelUpcomingBooking(
    Map<String, dynamic> booking,
  ) async {
    final bookingId = booking['booking_id']?.toString() ?? '';
    if (bookingId.isEmpty || _cancellingBookingId != null) return;

    final status = (booking['status']?.toString() ?? '').trim().toLowerCase();
    if (!_canCancelUpcomingBooking(status, isNoShowBooking(booking))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This booking can no longer be cancelled.'),
          backgroundColor: Color(0xFFC0392B),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: HestiaColors.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Cancel booking?',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: HestiaColors.textDark,
            ),
          ),
          content: const Text(
            'This will cancel your Instant or Scheduled booking for both you and the professional. This cannot be undone.',
            style: TextStyle(
              color: HestiaColors.textMedium,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'Keep booking',
                style: TextStyle(
                  color: HestiaColors.textMedium,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'Cancel booking',
                style: TextStyle(
                  color: Color(0xFFC0392B),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cancellingBookingId = bookingId);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: HestiaColors.primary),
      ),
    );

    try {
      await SupabaseService.cancelBookingByClient(bookingId: bookingId);
      if (!mounted) return;
      Navigator.of(context).pop(); // loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking cancelled successfully.'),
          backgroundColor: HestiaColors.primary,
        ),
      );
      await _loadProfileData();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to cancel booking: $e'),
          backgroundColor: const Color(0xFFC0392B),
        ),
      );
    } finally {
      if (mounted) setState(() => _cancellingBookingId = null);
    }
  }

  Widget _buildHistoryView() {
    final filteredSessions = _recentSessions.where((session) {
      final title = session['title'] as String? ?? '';
      final caregiver = session['caregiver_name'] as String? ?? '';
      final matchesQuery =
          title.toLowerCase().contains(_sessionSearchQuery) ||
          caregiver.toLowerCase().contains(_sessionSearchQuery);
      final matchesCat =
          _selectedSessionCategory == 'All' ||
          title.toLowerCase().contains(
            _selectedSessionCategory
                .toLowerCase()
                .replaceAll('-care', '')
                .replaceAll(' care', ''),
          );
      return matchesQuery && matchesCat;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: HestiaColors.primary.withValues(alpha: 0.16),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: Colors.grey.shade500, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: (val) {
                      setState(() {
                        _sessionSearchQuery = val.toLowerCase();
                      });
                    },
                    style: const TextStyle(
                      fontSize: 14,
                      color: HestiaColors.textDark,
                      fontWeight: FontWeight.w500,
                    ),
                    cursorColor: HestiaColors.primary,
                    decoration: InputDecoration(
                      hintText: 'Search sessions',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: ['All', 'Post-Delivery', 'Mobility', 'Babysitting'].map((
              cat,
            ) {
              final isSelected = _selectedSessionCategory == cat;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedSessionCategory = cat;
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? HestiaColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isSelected
                          ? HestiaColors.primary
                          : HestiaColors.primary.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : HestiaColors.primary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadProfileData,
            color: HestiaColors.primary,
            child: filteredSessions.isNotEmpty
                ? ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                    itemCount: filteredSessions.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final session = filteredSessions[index];
                      return _buildSessionCard(session);
                    },
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.45,
                        child: _buildNoSessionsState(),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoSessionsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: HestiaColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.history_toggle_off_rounded,
              color: HestiaColors.primary,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No matching sessions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: HestiaColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Try adjusting your filters or search query.',
            style: TextStyle(fontSize: 13, color: HestiaColors.textMedium),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session) {
    final caregiverName = displayCaregiverName(
      session['caregiver_name']?.toString(),
      fallback: 'Sunita Rao',
    );
    final title = session['title'] ?? 'Post-Delivery';
    final displayTitle = title.endsWith('Care') ? title : '$title Care';

    // Parse duration formatting
    final double durationHrs =
        (session['duration_hours'] as num?)?.toDouble() ?? 3.0;
    String durationStr = '${durationHrs.toInt()} hrs';
    if (durationHrs == 3.033) {
      durationStr = '3 hrs 2 min';
    } else if (durationHrs % 1 != 0) {
      final mins = ((durationHrs % 1) * 60).round();
      durationStr = '${durationHrs.toInt()} hrs $mins min';
    }

    final start = session['scheduled_start'] as DateTime;

    // Check if date is today
    final now = DateTime.now();
    final isToday =
        start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
    final String datePrefix = isToday ? 'Today' : _formatBookingDate(start);

    final subtitle = '$datePrefix • $caregiverName';

    final bool isRated = session['isRated'] ?? false;
    final int ratingValue = session['rating'] ?? 5;

    // Logo icon from PNG asset
    final String iconTitle = title;

    return GestureDetector(
      onTap: () {
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (context) => SessionDetailScreen(sessionData: session),
              ),
            )
            .then((_) {
              // reload when coming back to capture new ratings
              setState(() {});
            });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: HestiaColors.primary.withValues(alpha: 0.14),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category circular logo
                _buildServiceIconBadge(iconTitle),
                const SizedBox(width: 14),
                // Titles and rating row
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              displayTitle,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: HestiaColors.textDark,
                              ),
                            ),
                          ),
                          // Rating Stars
                          if (isRated)
                            Row(
                              children: List.generate(5, (idx) {
                                return Icon(
                                  Icons.star_rounded,
                                  color: idx < ratingValue
                                      ? const Color(0xFFDCA857)
                                      : const Color(0xFFE2E2E2),
                                  size: 13,
                                );
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(color: Color(0xFFF0E6DC), height: 1, thickness: 1),
            const SizedBox(height: 12),

            // Completed badge and Rebook buttons
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: session['status'] == 'no_show'
                        ? const Color(0xFFFDE8E8)
                        : const Color(0xFFE8F5ED),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    session['status'] == 'no_show' ? 'No-Show' : 'Completed',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: session['status'] == 'no_show'
                          ? const Color(0xFFB94A4A)
                          : const Color(0xFF2E6B4A),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  durationStr,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                // Rebook action
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => RepeatBookingScreen(
                          serviceTitle: title == 'Post-Delivery'
                              ? 'Post-Delivery Care'
                              : title == 'Mobility'
                              ? 'Mobility Support'
                              : title == 'Babysitting'
                              ? 'Certified Babysitting'
                              : 'Admin Concierge',
                          selectedDate: DateTime.now(),
                          selectedDuration: '3 hrs',
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: HestiaColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Rebook',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Unrated / view receipt links
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  if (!isRated) ...[
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    RateSessionScreen(sessionData: session),
                              ),
                            )
                            .then((_) {
                              setState(() {});
                            });
                      },
                      child: const Text(
                        'Rate this session',
                        style: TextStyle(
                          fontSize: 12,
                          color: HestiaColors.primary,
                          fontWeight: FontWeight.w800,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              ReceiptScreen(sessionData: session),
                        ),
                      );
                    },
                    child: Text(
                      'View receipt',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
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

  Widget _buildCareProfileSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HestiaColors.primary, width: 1),
        boxShadow: const [
          BoxShadow(
            color: HestiaColors.primary,
            blurRadius: 10,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text(
                  'CARE PROFILE',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: HestiaColors.primary,
                  ),
                ),
              ),
              if (_primaryReason.isNotEmpty)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: HestiaColors.primary.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _primaryReason,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: HestiaColors.primary),
      );
    }
    switch (_currentTabIndex) {
      case 0:
        return _buildHomeTab();
      case 1:
        return _buildBookingsTab();
      case 2:
        return ProntoMoneyScreen(
          showBackButton: true,
          onBack: () {
            setState(() {
              _oldTabIndex = _currentTabIndex;
              _currentTabIndex = 0;
            });
          },
        );
      default:
        return _buildHomeTab();
    }
  }

  // Shown on the Home tab when the user's primary address is outside the
  // coverage range of every hub. Mirrors the "coming soon" experience: a hero
  // message, a notify CTA, a way to change location, and a preview of the
  // services that will be available once we reach them.
  List<Widget> _buildComingSoonContent() {
    return [
      const SizedBox(height: 28),
      Center(
        child: RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: 0.5,
            ),
            children: [
              TextSpan(
                text: 'WE ARE\nCOMING ',
                style: TextStyle(color: Color(0xFFBCA99B)),
              ),
              TextSpan(
                text: 'SOON',
                style: TextStyle(color: HestiaColors.primary),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      const Center(
        child: Text(
          "We're currently live in select areas and expanding quickly. "
          'Get notified when we are near you!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.4,
            color: HestiaColors.textMedium,
          ),
        ),
      ),
      const SizedBox(height: 24),
      Center(
        child: ElevatedButton.icon(
          onPressed: () {
            setState(() => _notifyRequested = true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Thanks! We'll notify you as soon as we're live in your area.",
                ),
                backgroundColor: HestiaColors.primary,
              ),
            );
          },
          icon: Icon(
            _notifyRequested
                ? Icons.check_circle_outline
                : Icons.notifications_active_outlined,
            size: 20,
          ),
          label: Text(_notifyRequested ? "You're on the list" : 'Notify me!'),
          style: ElevatedButton.styleFrom(
            backgroundColor: HestiaColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
        ),
      ),
      const SizedBox(height: 14),
      Center(
        child: TextButton(
          onPressed: () {
            Navigator.of(context)
                .push(
                  MaterialPageRoute(
                    builder: (context) => const SearchLocationScreen(),
                  ),
                )
                .then((_) => _loadProfileData());
          },
          child: const Text(
            'Change location',
            style: TextStyle(
              color: HestiaColors.primary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
      const SizedBox(height: 32),
      const Center(
        child: Text(
          'Services we offer',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
        ),
      ),
      const SizedBox(height: 16),
      _buildServicesGrid(),
      const SizedBox(height: 120),
    ];
  }

  Widget _buildServicesGrid() {
    final services = _homeServiceCatalog;
    const crossAxisCount = 3;
    const spacing = 10.0;

    final rows = <Widget>[];
    for (var i = 0; i < services.length; i += crossAxisCount) {
      final rowItems = services.skip(i).take(crossAxisCount).toList();
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var j = 0; j < crossAxisCount; j++) ...[
              if (j > 0) const SizedBox(width: spacing),
              Expanded(
                child: j < rowItems.length
                    ? _serviceTile(
                        rowItems[j].label,
                        rowItems[j].price,
                        rowItems[j].originalPrice,
                        rowItems[j].rating,
                        rowItems[j].ratingCount,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
      if (i + crossAxisCount < services.length) {
        rows.add(const SizedBox(height: spacing));
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }

  Widget _buildActiveBookingBanner() {
    final booking = _activeBooking!;
    final isNoShow = isNoShowBooking(booking);
    final onTheWay = !isNoShow && isProfessionalOnTheWay(booking);
    final undergoing = !isNoShow && !onTheWay && isSessionUndergoing(booking);
    final runningLate = !isNoShow &&
        !onTheWay &&
        !undergoing &&
        isProfessionalRunningLateForBooking(booking);
    final caregiverName = booking['caregiver_name']?.toString();
    final scheduledStart = booking['scheduled_start'] is DateTime
        ? booking['scheduled_start'] as DateTime
        : DateTime.tryParse(booking['scheduled_start']?.toString() ?? '') ??
            DateTime.now();

    final accent = isNoShow
        ? const Color(0xFFC0392B)
        : undergoing
            ? const Color(0xFF2E6B4A)
            : runningLate
                ? const Color(0xFFE65100)
                : HestiaColors.primary;
    final accentSoft = isNoShow
        ? const Color(0xFFFDECEA)
        : undergoing
            ? const Color(0xFFE8F5ED)
            : runningLate
                ? const Color(0xFFFFF3E0)
                : const Color(0xFFFAF2EB);
    final label = isNoShow
        ? 'NO SHOW'
        : undergoing
            ? 'SESSION UNDERWAY'
            : onTheWay
                ? 'ON THE WAY'
                : runningLate
                    ? 'RUNNING LATE'
                    : 'ACTIVE BOOKING';

    final headline = isNoShow
        ? 'Session marked as no-show'
        : undergoing
            ? '${professionalFirstName(caregiverName)} is with you now'
            : onTheWay
                ? professionalOnTheWayMessage(caregiverName)
                : runningLate
                    ? professionalRunningLateMessage(caregiverName)
                    : '${booking['title']} · ${_formatBookingDate(scheduledStart)}';

    final etaLabel = _activeBookingEtaMin != null
        ? 'ETA $_activeBookingEtaMin min'
        : 'ETA updating…';

    final subtitle = isNoShow
        ? 'Tap to leave a review'
        : undergoing
            ? '${booking['title']} · started ${_formatBookingTime(scheduledStart)}'
            : onTheWay
                ? '$etaLabel · ${booking['title']} · ${_formatBookingTime(scheduledStart)}'
                : runningLate
                    ? '${booking['title']} · ${_formatBookingTime(scheduledStart)}'
                    : '${displayCaregiverName(booking['caregiver_name']?.toString())} · ${_formatBookingTime(scheduledStart)}';

    return GestureDetector(
      onTap: () async {
        await openActiveBookingScreen(
          context,
          booking: booking,
          userName: _userName,
        );
        if (mounted) _loadProfileData();
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accent.withValues(alpha: 0.35),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 5,
                color: accent,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: accentSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isNoShow
                              ? Icons.person_off_rounded
                              : undergoing
                                  ? Icons.play_circle_fill_rounded
                                  : onTheWay
                                      ? Icons.directions_car_rounded
                                      : runningLate
                                          ? Icons.schedule_rounded
                                          : Icons.health_and_safety,
                          color: accent,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 10,
                                color: isNoShow ||
                                        runningLate ||
                                        onTheWay ||
                                        undergoing
                                    ? accent
                                    : HestiaColors.textAccent,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              headline,
                              style: TextStyle(
                                color: HestiaColors.textDark,
                                fontWeight: FontWeight.w800,
                                fontSize: onTheWay ||
                                        runningLate ||
                                        undergoing
                                    ? 17
                                    : 14,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (onTheWay) ...[
                              const SizedBox(height: 6),
                              Text(
                                etaLabel,
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${booking['title']} · ${_formatBookingTime(scheduledStart)}',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ] else ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  color: isNoShow || runningLate || undergoing
                                      ? accent
                                      : HestiaColors.textMedium,
                                  fontSize: 12,
                                  fontWeight: isNoShow ||
                                          runningLate ||
                                          undergoing
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: accent,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveSessionFocusPanel() {
    final booking = _activeBooking!;
    final isNoShow = isNoShowBooking(booking);
    final onTheWay = !isNoShow && isProfessionalOnTheWay(booking);
    final undergoing = !isNoShow && isSessionUndergoing(booking);
    final arrived = !isNoShow &&
        !onTheWay &&
        !undergoing &&
        booking['status']?.toString().toLowerCase() == 'arrived';
    final caregiverName = booking['caregiver_name']?.toString();
    final firstName = professionalFirstName(caregiverName);
    final title = booking['title']?.toString() ?? 'Care session';
    final scheduledStart = booking['scheduled_start'] is DateTime
        ? booking['scheduled_start'] as DateTime
        : DateTime.tryParse(booking['scheduled_start']?.toString() ?? '') ??
            DateTime.now();

    final accent = isNoShow
        ? const Color(0xFFC0392B)
        : undergoing
            ? const Color(0xFF2E6B4A)
            : HestiaColors.primary;
    final soft = isNoShow
        ? const Color(0xFFFDECEA)
        : undergoing
            ? const Color(0xFFE8F5ED)
            : const Color(0xFFFAF2EB);

    final badge = isNoShow
        ? 'NO SHOW'
        : undergoing
            ? 'SESSION UNDERWAY'
            : onTheWay
                ? 'ON THE WAY'
                : arrived
                    ? 'ARRIVED'
                    : 'ACTIVE SESSION';

    final headline = isNoShow
        ? 'This session needs your review'
        : undergoing
            ? 'Your session is underway'
            : onTheWay
                ? professionalOnTheWayMessage(caregiverName)
                : arrived
                    ? '$firstName has arrived'
                    : '$firstName is assigned for your care';

    final support = isNoShow
        ? 'Tap below to leave feedback and close this booking.'
        : undergoing
            ? '$firstName is currently providing $title.'
            : onTheWay
                ? (_activeBookingEtaMin != null
                    ? 'ETA $_activeBookingEtaMin min · $title'
                    : 'Live tracking available · $title')
                : arrived
                    ? 'Verify arrival to start the care session.'
                    : '$title · ${_formatBookingDate(scheduledStart)} · ${_formatBookingTime(scheduledStart)}';

    final cta = isNoShow
        ? 'Leave a review'
        : undergoing
            ? 'Open active session'
            : onTheWay
                ? 'Track professional'
                : arrived
                    ? 'Verify & start'
                    : 'View active session';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badge,
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: soft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isNoShow
                      ? Icons.rate_review_rounded
                      : undergoing
                          ? Icons.play_circle_fill_rounded
                          : onTheWay
                              ? Icons.directions_car_rounded
                              : Icons.health_and_safety_rounded,
                  color: accent,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: HestiaColors.textDark,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      support,
                      style: const TextStyle(
                        fontSize: 14,
                        color: HestiaColors.textMedium,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F3EF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _sessionFocusMetaRow(
                  Icons.person_outline_rounded,
                  'Professional',
                  firstName,
                ),
                const SizedBox(height: 10),
                _sessionFocusMetaRow(
                  Icons.medical_services_outlined,
                  'Service',
                  title,
                ),
                const SizedBox(height: 10),
                _sessionFocusMetaRow(
                  Icons.schedule_rounded,
                  undergoing ? 'Started' : 'Scheduled',
                  _formatBookingTime(scheduledStart),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () async {
                await openActiveBookingScreen(
                  context,
                  booking: booking,
                  userName: _userName,
                );
                if (mounted) _loadProfileData();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                cta,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'You can book other care services below — just not another '
            '${booking['title'] ?? 'session'} while this one is active.',
            style: const TextStyle(
              fontSize: 12.5,
              color: HestiaColors.textMedium,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sessionFocusMetaRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: HestiaColors.primary),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            color: HestiaColors.textMedium,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13.5,
              color: HestiaColors.textDark,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildPromoHero() {
    final slides = [
      (
        title: 'First 3 bookings at just ',
        highlight: '₹25*',
        titleSuffix: ' each',
        subtitle: 'Families trust Hestia for safe, reliable care at home.',
        cta: 'BOOK NOW',
        icon: Icons.local_offer_rounded,
      ),
      (
        title: 'Verified professionals ',
        highlight: 'you can trust',
        titleSuffix: '',
        subtitle: 'Background-checked caregivers for every booking.',
        cta: 'EXPLORE',
        icon: Icons.verified_rounded,
      ),
      (
        title: 'Safe care, ',
        highlight: 'every time',
        titleSuffix: '',
        subtitle: 'Consistent, trained, and reliable home care support.',
        cta: 'BOOK NOW',
        icon: Icons.health_and_safety_rounded,
      ),
    ];

    return Column(
      children: [
        SizedBox(
          height: 190,
          child: PageView.builder(
            itemCount: slides.length,
            onPageChanged: (index) {
              setState(() => _heroPageIndex = index);
            },
            itemBuilder: (context, index) {
              final slide = slides[index];
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF4E3626),
                      HestiaColors.primary,
                      Color(0xFF8B6B4A),
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -20,
                      bottom: -30,
                      child: Icon(
                        slide.icon,
                        size: 160,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.2,
                              ),
                              children: [
                                TextSpan(text: slide.title),
                                TextSpan(
                                  text: slide.highlight,
                                  style: const TextStyle(
                                    color: Color(0xFFF5D9A8),
                                  ),
                                ),
                                TextSpan(text: slide.titleSuffix),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            slide.subtitle,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              final first = _homeServiceCatalog.first.label;
                              _openServiceDetail(first);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                slide.cta,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: HestiaColors.primary,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(slides.length, (index) {
            final active = index == _heroPageIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active
                    ? HestiaColors.primary
                    : HestiaColors.primary.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildBrandBlock() {
    return const SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Safe Home.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: Color(0xFFBCA99B),
              height: 1.05,
            ),
          ),
          Text(
            'Zero Stress.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: HestiaColors.textDark,
              height: 1.05,
            ),
          ),
          Text(
            'Hestia',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              color: HestiaColors.primary,
              height: 1.1,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Trusted by families like yours',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: HestiaColors.textMedium),
          ),
        ],
      ),
    );
  }

  Widget _buildTrustBadgesRow() {
    Widget badge(IconData icon, String label) {
      return Expanded(
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFFAF2EB),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: HestiaColors.primary, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            badge(Icons.verified_user_outlined, 'Verified'),
            VerticalDivider(color: Colors.grey.shade300, width: 1),
            badge(Icons.handshake_outlined, 'Trained'),
            VerticalDivider(color: Colors.grey.shade300, width: 1),
            badge(Icons.timer_outlined, 'Reliable'),
          ],
        ),
      ),
    );
  }

  Widget _buildBusyPartnersSection() {
    final slot = _getRecentAvailableSlot();
    final cards = [
      (
        duration: '0.5 hr',
        price: '₹25',
        original: '₹125',
        save: 'Save ₹100',
        minutes: 30,
      ),
      (
        duration: '1 hr',
        price: '₹49',
        original: '₹249',
        save: 'Save ₹200',
        minutes: 60,
      ),
      (
        duration: '1.5 hr',
        price: '₹75',
        original: '₹375',
        save: 'Save ₹300',
        minutes: 90,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Our partners are busy right now',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: HestiaColors.textDark,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Schedule & book for later',
          style: TextStyle(fontSize: 14, color: HestiaColors.textMedium),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 210,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final card = cards[index];
              final service =
                  _homeServiceCatalog[index % _homeServiceCatalog.length];
              return _busyPartnerCard(
                nextSlot: slot.displayString,
                duration: card.duration,
                price: card.price,
                originalPrice: card.original,
                saveAmount: card.save,
                serviceTitle: service.label,
                durationMinutes: card.minutes,
                initialDate: slot.date,
                initialTimeSlot: slot.slot,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTrustworthySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reliable & Trustworthy',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: HestiaColors.textDark,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Ensuring integrity through verified standards',
          style: TextStyle(fontSize: 14, color: HestiaColors.textMedium),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _trustCard(
              title: 'Background\nVerified',
              icon: Icons.shield_outlined,
              gradientColors: const [Color(0xFFFAF2EB), Colors.white],
            ),
            const SizedBox(width: 10),
            _trustCard(
              title: 'Trained\nCaregivers',
              icon: Icons.school_outlined,
              gradientColors: const [Color(0xFFF5ECE3), Colors.white],
            ),
            const SizedBox(width: 10),
            _trustCard(
              title: 'Consistent\nQuality',
              icon: Icons.star_outline,
              gradientColors: const [Color(0xFFFAF2EB), Colors.white],
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildInCoverageContent() {
    final active = _activeBooking;
    final showFocusPanel =
        active != null && shouldFocusHomeOnActiveBooking(active);

    return [
      if (active != null) ...[
        if (showFocusPanel)
          _buildActiveSessionFocusPanel()
        else
          _buildActiveBookingBanner(),
        const SizedBox(height: 14),
      ],
      _buildPromoHero(),
      const SizedBox(height: 18),
      const Text(
        'All care services',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: HestiaColors.textDark,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        active != null
            ? 'Book another care reason anytime — not a duplicate of your active one'
            : 'Schedule & book for later',
        style: const TextStyle(fontSize: 14, color: HestiaColors.textMedium),
      ),
      const SizedBox(height: 12),
      _buildServicesGrid(),
      const SizedBox(height: 20),
      _buildBusyPartnersSection(),
      const SizedBox(height: 16),
      const Text(
        'Book for Later',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: HestiaColors.textDark,
        ),
      ),
      const SizedBox(height: 2),
      const Text(
        'Select your slot & stay worry-free',
        style: TextStyle(fontSize: 14, color: HestiaColors.textMedium),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          _bookLaterCard(
            title: 'Schedule\nBooking',
            pillText: 'UP TO 50% OFF',
            illustration: const ClockIllustration(
              primaryColor: HestiaColors.primary,
            ),
            onTap: () {
              const serviceTitle = 'Post-Delivery Care';
              if (_isServiceBlockedByActiveBooking(serviceTitle)) {
                _showSameReasonBookingBlocked(serviceTitle);
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      const ScheduleScreen(serviceTitle: serviceTitle),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          _bookLaterCard(
            title: 'Recurring\nBooking',
            pillText: 'UP TO 25% OFF',
            illustration: const CalendarIllustration(
              primaryColor: HestiaColors.primary,
            ),
            onTap: () {
              const serviceTitle = 'Post-Delivery Care';
              if (_isServiceBlockedByActiveBooking(serviceTitle)) {
                _showSameReasonBookingBlocked(serviceTitle);
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => RepeatBookingScreen(
                    serviceTitle: serviceTitle,
                    selectedDate: DateTime.now(),
                    selectedDuration: '3 hrs',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildTrustworthySection(),
      const SizedBox(height: 20),
      _buildBrandBlock(),
      const SizedBox(height: 12),
      _buildTrustBadgesRow(),
      const SizedBox(height: 88),
    ];
  }

  Widget _buildTopAppBar() {
    final parts = _location.split(' · ');
    final String primaryLabel =
        (parts.isNotEmpty && parts.first.trim().isNotEmpty)
        ? parts.first.trim()
        : _location;

    return Container(
      width: double.infinity,
      color: HestiaColors.primary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (context) => const SearchLocationScreen(),
                          ),
                        )
                        .then((_) => _loadProfileData());
                  },
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    primaryLabel,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ],
                            ),
                            Text(
                              _location,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _appBarActionCircle(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const ProntoMoneyScreen(),
                    ),
                  );
                },
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: HestiaColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              _appBarActionCircle(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const ReferAndEarnScreen(),
                    ),
                  );
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.card_giftcard,
                      color: HestiaColors.primary,
                      size: 22,
                    ),
                    Positioned(
                      bottom: -10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: HestiaColors.primary,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                        child: const Text(
                          '₹100',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (context) => const ProfileScreen(),
                        ),
                      )
                      .then((_) => _loadProfileData());
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2B2B2B),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _userInitials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appBarActionCircle({required Widget child, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      child: Container(
        color: HestiaColors.appBackground,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopAppBar(),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_isWithinCoverage) ..._buildComingSoonContent(),

                  if (_isWithinCoverage) ..._buildInCoverageContent(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _initAnimationController();
    final controller = _navAnimationController!;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final navVisible = _currentTabIndex != 2;
    final cartVisible = _serviceMinutes.isNotEmpty && _isWithinCoverage;
    // Nav bar: ~74px content + 12px bottom margin, plus gap above it.
    final cartBottom = cartVisible
        ? (navVisible ? bottomInset + 102 : bottomInset + 24)
        : -60.0;

    return Scaffold(
      extendBody: true,
      backgroundColor: HestiaColors.appBackground,
      body: Stack(
        children: [
          _buildBody(),

          // ── Floating cart pill ────────────────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutBack,
            bottom: cartBottom,
            left: 24,
            right: 24,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: cartVisible ? 1.0 : 0.0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color.fromARGB(255, 65, 40, 18),
                      Color.fromARGB(255, 120, 80, 40),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(50),
                  boxShadow: [
                    BoxShadow(
                      color: HestiaColors.primary.withValues(alpha: 0.45),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Cart icon + count pill
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.shopping_cart_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Label
                    Expanded(
                      child: Text(
                        '${_serviceMinutes.length} ${_serviceMinutes.length == 1 ? 'service' : 'services'} added',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    // Go to Cart button
                    GestureDetector(
                      onTap: () {
                        if (_serviceMinutes.isNotEmpty) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => ScheduleScreen(
                                serviceTitle: _serviceMinutes.keys.first,
                                initialServicesMap: Map<String, int>.from(
                                  _serviceMinutes,
                                ),
                                onServicesChanged: (updatedMap) {
                                  setState(() {
                                    _serviceMinutes.clear();
                                    _serviceMinutes.addAll(updatedMap);
                                  });
                                },
                              ),
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              'Go to Cart',
                              style: TextStyle(
                                color: HestiaColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: HestiaColors.primary,
                              size: 11,
                            ),
                          ],
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
      bottomNavigationBar: _currentTabIndex == 2
          ? null
          : SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
                decoration: BoxDecoration(
                  color: HestiaColors.primary,
                  borderRadius: BorderRadius.circular(50),
                  boxShadow: [
                    BoxShadow(
                      color: HestiaColors.primary.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: 66,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final double totalWidth = constraints.maxWidth;
                      final double tabWidth = totalWidth / 3;

                      return AnimatedBuilder(
                        animation: controller,
                        builder: (context, child) {
                          final double t = controller.value;
                          final double pillNormalWidth = tabWidth - 8;

                          final double centerSource =
                              (_oldTabIndex + 0.5) * tabWidth;
                          final double centerTarget =
                              (_currentTabIndex + 0.5) * tabWidth;

                          double tLeft;
                          double tRight;

                          if (_currentTabIndex > _oldTabIndex) {
                            tRight = CurveTween(
                              curve: Curves.easeOutQuart,
                            ).transform(t);
                            tLeft = CurveTween(
                              curve: Curves.easeInQuad,
                            ).transform(t);
                          } else if (_currentTabIndex < _oldTabIndex) {
                            tLeft = CurveTween(
                              curve: Curves.easeOutQuart,
                            ).transform(t);
                            tRight = CurveTween(
                              curve: Curves.easeInQuad,
                            ).transform(t);
                          } else {
                            tLeft = t;
                            tRight = t;
                          }

                          final double leftSource =
                              centerSource - pillNormalWidth / 2;
                          final double leftTarget =
                              centerTarget - pillNormalWidth / 2;
                          final double rightSource =
                              centerSource + pillNormalWidth / 2;
                          final double rightTarget =
                              centerTarget + pillNormalWidth / 2;

                          double currentLeft =
                              leftSource + (leftTarget - leftSource) * tLeft;
                          double currentRight =
                              rightSource +
                              (rightTarget - rightSource) * tRight;

                          if (currentLeft < 0.0) {
                            currentLeft = 0.0;
                          }
                          if (currentRight > totalWidth) {
                            currentRight = totalWidth;
                          }
                          final double currentWidth =
                              (currentRight - currentLeft).clamp(
                                pillNormalWidth,
                                totalWidth,
                              );

                          Color getNavItemColor(int index) {
                            const Color activeColor = HestiaColors.primary;
                            final Color inactiveColor = Colors.white.withValues(
                              alpha: 0.7,
                            );
                            if (_oldTabIndex == _currentTabIndex) {
                              return index == _currentTabIndex
                                  ? activeColor
                                  : inactiveColor;
                            }
                            if (index == _currentTabIndex) {
                              return Color.lerp(
                                    inactiveColor,
                                    activeColor,
                                    t,
                                  ) ??
                                  activeColor;
                            } else if (index == _oldTabIndex) {
                              return Color.lerp(
                                    activeColor,
                                    inactiveColor,
                                    t,
                                  ) ??
                                  inactiveColor;
                            } else {
                              return inactiveColor;
                            }
                          }

                          String getTabLabel(int index) {
                            switch (index) {
                              case 0:
                                return 'Home';
                              case 1:
                                return 'Bookings';
                              case 2:
                                return 'Money';
                              default:
                                return '';
                            }
                          }

                          IconData getIconData(int index) {
                            final bool isSelectedAtRest =
                                _oldTabIndex == _currentTabIndex &&
                                index == _currentTabIndex;

                            bool isEngulfed = false;
                            if (isSelectedAtRest) {
                              isEngulfed = true;
                            } else if (index == _currentTabIndex) {
                              isEngulfed = t >= 0.5;
                            } else if (index == _oldTabIndex) {
                              isEngulfed = t < 0.5;
                            }

                            switch (index) {
                              case 0:
                                return isEngulfed
                                    ? Icons.home
                                    : Icons.home_outlined;
                              case 1:
                                return isEngulfed
                                    ? Icons.calendar_month
                                    : Icons.calendar_month_outlined;
                              case 2:
                                return isEngulfed
                                    ? Icons.account_balance_wallet
                                    : Icons.account_balance_wallet_outlined;
                              default:
                                return Icons.home_outlined;
                            }
                          }

                          Widget buildNavItemInternal(int index) {
                            final Color color = getNavItemColor(index);
                            return Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  if (_currentTabIndex == index) return;
                                  setState(() {
                                    _oldTabIndex = _currentTabIndex;
                                    _currentTabIndex = index;
                                  });
                                  controller.reset();
                                  controller.forward();
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        getIconData(index),
                                        color: color,
                                        size: 22,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        getTabLabel(index),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: color,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }

                          return Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.centerLeft,
                            children: [
                              // Background sliding pill
                              Positioned(
                                left: currentLeft,
                                width: currentWidth,
                                top: 0,
                                bottom: 0,
                                child: Align(
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: currentWidth,
                                    height: 66.0,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(50),
                                    ),
                                  ),
                                ),
                              ),
                              // Row of items
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  buildNavItemInternal(0),
                                  buildNavItemInternal(1),
                                  buildNavItemInternal(2),
                                ],
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
    );
  }
}

// ── Custom Illustration & Painter Widgets for Hestia Theme ──────────────

class CardGridPainter extends CustomPainter {
  final Color color;

  CardGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final double step = 15.0;

    // Draw diagonal lines from bottom-left to top-right
    for (double offset = -size.height; offset < size.width; offset += step) {
      canvas.drawLine(
        Offset(offset, size.height),
        Offset(offset + size.height, 0),
        paint,
      );
    }

    // Draw diagonal lines from top-left to bottom-right (mesh effect)
    for (double offset = -size.height; offset < size.width; offset += step) {
      canvas.drawLine(
        Offset(offset, 0),
        Offset(offset + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CardGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

class ClockPainter extends CustomPainter {
  final Color primaryColor;

  ClockPainter({required this.primaryColor});

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final Offset center = Offset(size.width / 2, size.height / 2);

    final Paint outerPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final double startAngle = -pi * 0.25;
    final double sweepAngle = pi * 1.6;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 3),
      startAngle,
      sweepAngle,
      false,
      outerPaint,
    );

    final double endAngle = startAngle + sweepAngle;
    final Offset arrowTip = Offset(
      center.dx + (radius - 3) * cos(endAngle),
      center.dy + (radius - 3) * sin(endAngle),
    );

    final double arrowAngle = endAngle + pi / 2;
    final double arrowSize = 6.0;

    final Path arrowPath = Path()
      ..moveTo(arrowTip.dx, arrowTip.dy)
      ..lineTo(
        arrowTip.dx + arrowSize * cos(arrowAngle + 2.5),
        arrowTip.dy + arrowSize * sin(arrowAngle + 2.5),
      )
      ..lineTo(
        arrowTip.dx + arrowSize * cos(arrowAngle - 2.5),
        arrowTip.dy + arrowSize * sin(arrowAngle - 2.5),
      )
      ..close();

    final Paint fillPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(arrowPath, fillPaint);

    final Paint innerCirclePaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 10, innerCirclePaint);

    final Paint innerBorderPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius - 10, innerBorderPaint);

    final Paint handPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, 2.0, fillPaint);

    canvas.drawLine(
      center,
      Offset(
        center.dx + (radius - 18) * cos(0.2),
        center.dy + (radius - 18) * sin(0.2),
      ),
      handPaint,
    );

    canvas.drawLine(
      center,
      Offset(
        center.dx + (radius - 14) * cos(-pi / 2),
        center.dy + (radius - 14) * sin(-pi / 2),
      ),
      handPaint,
    );
  }

  @override
  bool shouldRepaint(covariant ClockPainter oldDelegate) =>
      oldDelegate.primaryColor != primaryColor;
}

class ClockIllustration extends StatelessWidget {
  final Color primaryColor;

  const ClockIllustration({super.key, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 50,
      child: CustomPaint(painter: ClockPainter(primaryColor: primaryColor)),
    );
  }
}

class CalendarIllustration extends StatelessWidget {
  final Color primaryColor;

  const CalendarIllustration({super.key, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 2,
            child: Container(
              width: 42,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: primaryColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Column(
                  children: [
                    Container(height: 8, color: primaryColor),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 4,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(3, (row) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: List.generate(4, (col) {
                                return Container(
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: (row == 2 && col == 3)
                                        ? primaryColor
                                        : primaryColor.withValues(alpha: 0.3),
                                    shape: BoxShape.circle,
                                  ),
                                );
                              }),
                            );
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 2,
            left: 10,
            child: Container(
              width: 4,
              height: 10,
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 10,
            child: Container(
              width: 4,
              height: 10,
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableSlot {
  final String displayString;
  final DateTime date;
  final String slot;

  _AvailableSlot({
    required this.displayString,
    required this.date,
    required this.slot,
  });
}
