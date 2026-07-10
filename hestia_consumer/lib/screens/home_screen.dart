import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math';
import '../theme/colors.dart';
import '../services/supabase_service.dart';
import 'service_detail_screen.dart';
import 'repeat_booking_screen.dart';
import 'schedule_screen.dart';
import 'tracking_screen.dart';
import 'rate_session_screen.dart';
import 'session_detail_screen.dart';
import 'receipt_screen.dart';
import 'search_location_screen.dart';
import 'profile_screen.dart';

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
  List<dynamic> _members = [];
  String _email = '';
  String _phone = '';
  int _currentTabIndex = 0;
  int _oldTabIndex = 0;
  bool _showAllServices = false;
  final Map<String, int> _serviceMinutes = {};
  Map<String, dynamic>? _activeBooking;
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
    bool fullWidth = false,
    double? height,
    double imageHeightMultiplier = 2.5,
  }) {
    final assetPath = ServiceDetailScreen.iconAssetFor(label);

    if (fullWidth) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final boxHeight =
              constraints.maxHeight.isFinite ? constraints.maxHeight : (height ?? 96);
          final boxWidth =
              constraints.maxWidth.isFinite ? constraints.maxWidth : double.infinity;
          final renderedImageHeight = boxHeight * imageHeightMultiplier;

          return ClipRect(
            child: Align(
              alignment: Alignment.center,
              child: Image.asset(
                assetPath,
                width: boxWidth,
                height: renderedImageHeight,
                fit: BoxFit.fitWidth,
                alignment: Alignment.center,
                errorBuilder: (context, error, stackTrace) {
                  return SizedBox(
                    height: renderedImageHeight,
                    child: Align(
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.medical_services_outlined,
                        size: boxHeight * 0.55,
                        color: HestiaColors.primary,
                      ),
                    ),
                  );
                },
              ),
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
  }

  @override
  void dispose() {
    _navAnimationController?.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    final user = SupabaseService.currentUser;
    if (user != null) {
      // Set defaults from Auth user metadata first
      final metadataName = user.userMetadata?['full_name'] ?? 'User';
      setState(() {
        _userName = metadataName;
        _userInitials = _getInitials(metadataName);
        _email = SupabaseService.currentUserEmail;
        _phone = SupabaseService.currentUserPhone;
      });

      Map<String, dynamic>? profileData;
      Map<String, dynamic>? activeBooking;
      List<Map<String, dynamic>> recent = [];
      List<Map<String, dynamic>> upcoming = [];

      try {
        final results = await Future.wait<dynamic>([
          () async {
            var data = await SupabaseService.getUserProfile(user.id);
            if (data == null || data['address'] == null) {
              data = await SupabaseService.downloadProfileJson(user.id);
            }
            return data;
          }(),
          SupabaseService.getActiveBooking(user.id),
          SupabaseService.getRecentSessions(user.id),
          SupabaseService.getUpcomingBookings(user.id),
        ]);

        profileData = results[0] as Map<String, dynamic>?;
        activeBooking = results[1] as Map<String, dynamic>?;
        recent = results[2] as List<Map<String, dynamic>>;
        upcoming = results[3] as List<Map<String, dynamic>>;
      } catch (e) {
        debugPrint('Error loading home screen data: $e');
      }

      if (mounted) {
        setState(() {
          if (profileData != null) {
            _userName = profileData['name'] ?? _userName;
            _userInitials = _getInitials(_userName);
            _email = profileData['email'] ?? _email;
            _phone = profileData['phone'] ?? _phone;
            _primaryReason = profileData['primary_reason'] ?? '';
            _members = profileData['household_members'] ?? [];
            if (profileData['address'] != null) {
              final street = profileData['address']['street'] ?? '';
              final city = profileData['address']['city'] ?? '';
              _location = street.isNotEmpty ? '$street · $city' : city;
            }
          }
          _activeBooking = activeBooking;
          _recentSessions = recent;
          _upcomingBookings = upcoming;
          _isLoading = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
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

  String _getEmojiForAge(int age) {
    if (age <= 2) return '👶';
    if (age <= 12) return '🧒';
    if (age <= 19) return '🧑';
    if (age <= 59) return '🧑';
    return '👵';
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
    final double hourlyPrice =
        double.tryParse(price.replaceAll('₹', '').trim()) ?? 0.0;
    final double origHourlyPrice =
        double.tryParse(originalPrice.replaceAll('₹', '').trim()) ?? 0.0;
    final displayPrice = isAdded
        ? '₹${(hourlyPrice * (minutes / 60.0)).toStringAsFixed(0)}'
        : '₹${hourlyPrice.toStringAsFixed(0)}/hr';
    final displayOriginalPrice = isAdded
        ? '₹${(origHourlyPrice * (minutes / 60.0)).toStringAsFixed(0)}'
        : '₹${origHourlyPrice.toStringAsFixed(0)}/hr';
    return SizedBox(
      width: 130,
      height: double.infinity,
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ServiceDetailScreen(
                serviceKey: label,
                initialServicesMap: Map<String, int>.from(_serviceMinutes),
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
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.42),
                    Colors.white.withValues(alpha: 0.18),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.55),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _buildServiceIconImage(
                        label,
                        fullWidth: true,
                        imageHeightMultiplier: 5.6,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: HestiaColors.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star,
                                  color: Colors.white,
                                  size: 9,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  rating,
                                  style: const TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: HestiaColors.textDark,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                displayPrice,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: HestiaColors.textDark,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  displayOriginalPrice,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: HestiaColors.textLight,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: isAdded
                                ? _buildStepper(label, minutes)
                                : GestureDetector(
                                    key: const ValueKey('add_btn'),
                                    onTap: () {
                                      setState(() {
                                        _serviceMinutes[label] = 30;
                                      });
                                    },
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.34,
                                        ),
                                        borderRadius: BorderRadius.circular(7),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.65,
                                          ),
                                          width: 1.2,
                                        ),
                                      ),
                                      child: const Center(
                                        child: Text(
                                          'ADD',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: HestiaColors.primary,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
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
    return Container(
      color: HestiaColors.appBackground,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          title: const Text(
            'My Bookings',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: HestiaColors.textDark,
            ),
          ),
          centerTitle: true,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Segmented Control Toggle
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 8.0,
              ),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _bookingsSubTab = 0;
                          });
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _bookingsSubTab == 0
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Upcoming',
                            style: TextStyle(
                              color: _bookingsSubTab == 0
                                  ? HestiaColors.primary
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _bookingsSubTab = 1;
                          });
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _bookingsSubTab == 1
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'History',
                            style: TextStyle(
                              color: _bookingsSubTab == 1
                                  ? HestiaColors.primary
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Expanded content based on selected segment
            Expanded(
              child: _bookingsSubTab == 0
                  ? _buildUpcomingView()
                  : _buildHistoryView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingView() {
    if (_upcomingBookings.isEmpty) {
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
                Icons.calendar_today_rounded,
                color: HestiaColors.primary,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No upcoming bookings',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: HestiaColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Book a care visit from the Home screen.',
              style: TextStyle(fontSize: 13, color: HestiaColors.textMedium),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProfileData,
      color: HestiaColors.primary,
      child: ListView.separated(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          24,
          8,
          24,
          120,
        ), // padded to avoid floating navbar
        itemCount: _upcomingBookings.length,
        separatorBuilder: (context, index) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final booking = _upcomingBookings[index];
          return _buildUpcomingCard(booking);
        },
      ),
    );
  }

  Widget _buildUpcomingCard(Map<String, dynamic> booking) {
    final caregiverName = booking['caregiver_name'] ?? 'Sunita Rao';
    final title = booking['title'] ?? 'Post-Delivery';
    final displayTitle = title.endsWith('Care') ? title : '$title Care';
    final status = booking['status'] as String? ?? 'pending';
    final start = booking['scheduled_start'] as DateTime;
    final totalAmount = booking['amount'] != null
        ? (booking['amount'] as num).toInt()
        : 0;

    // Check if date is today/tomorrow
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

    // Service icon from PNG asset
    final String iconTitle = title;

    // Status styling
    Color statusBgColor;
    Color statusTextColor;
    String statusLabel = status.toUpperCase();

    if (status == 'active') {
      statusBgColor = const Color(0xFFE8F5ED);
      statusTextColor = const Color(0xFF2E6B4A);
      statusLabel = 'ACTIVE NOW';
    } else if (status == 'confirmed') {
      statusBgColor = const Color(0xFFE3F2FD);
      statusTextColor = const Color(0xFF1E88E5);
      statusLabel = 'CONFIRMED';
    } else {
      statusBgColor = const Color(0xFFFFF3E0);
      statusTextColor = const Color(0xFFE65100);
      statusLabel = 'PENDING';
    }

    return GestureDetector(
      onTap: () {
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (context) => TrackingScreen(bookingData: booking),
              ),
            )
            .then((_) => _loadProfileData());
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF8C6239).withValues(alpha: 0.18),
            width: 3.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                _buildServiceIconBadge(iconTitle),
                const SizedBox(width: 14),
                // Text details
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
                                fontWeight: FontWeight.bold,
                                color: HestiaColors.textDark,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusBgColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: statusTextColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$dateStr at $timeStr',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: HestiaColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Professional: $caregiverName',
                        style: const TextStyle(
                          fontSize: 12,
                          color: HestiaColors.textMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFFF5EBE0), height: 1, thickness: 1.2),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Amount: ₹$totalAmount',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: HestiaColors.textDark,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      status == 'active' ? 'Track Care' : 'View Details',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: HestiaColors.primary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: HestiaColors.primary,
                      size: 16,
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
        // Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white24),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.search, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: (val) {
                      setState(() {
                        _sessionSearchQuery = val.toLowerCase();
                      });
                    },
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Search sessions',
                      hintStyle: TextStyle(color: Colors.white70, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 2.0),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Horizontal Categories filter
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
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
                    horizontal: 18,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.2),
                      width: 1.2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? HestiaColors.primary : Colors.white,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 20),

        // Sessions Card List
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadProfileData,
            color: HestiaColors.primary,
            child: filteredSessions.isNotEmpty
                ? ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      24.0,
                      0.0,
                      24.0,
                      120.0,
                    ), // spacer for floating nav
                    itemCount: filteredSessions.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final session = filteredSessions[index];
                      return _buildSessionCard(session);
                    },
                  )
                : _buildNoSessionsState(),
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
    final caregiverName = session['caregiver_name'] ?? 'Sunita Rao';
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
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF8C6239).withValues(alpha: 0.18),
            width: 3.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
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
                          Text(
                            displayTitle,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: HestiaColors.textDark,
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
                        style: const TextStyle(
                          fontSize: 12,
                          color: HestiaColors.textMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(color: Color(0xFFF5EBE0), height: 1, thickness: 1.2),
            const SizedBox(height: 16),

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
                      fontWeight: FontWeight.bold,
                      color: session['status'] == 'no_show'
                          ? const Color(0xFFB94A4A)
                          : const Color(0xFF2E6B4A),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  durationStr,
                  style: const TextStyle(
                    fontSize: 12,
                    color: HestiaColors.textLight,
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
                      horizontal: 18,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFE5D5C5),
                        width: 1.2,
                      ),
                    ),
                    child: const Text(
                      'Rebook',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: HestiaColors.textMedium,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Unrated / view receipt links
            Padding(
              padding: const EdgeInsets.only(top: 14.0),
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
                          color: Color(0xFF8C6239),
                          fontWeight: FontWeight.bold,
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
                    child: const Text(
                      'View receipt',
                      style: TextStyle(
                        fontSize: 12,
                        color: HestiaColors.textMedium,
                        fontWeight: FontWeight.bold,
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
          if (_members.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: HestiaColors.primary, height: 1),
            const SizedBox(height: 12),
            const Text(
              'MEMBERS UNDER CARE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.black,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _members.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final member = _members[index];
                final name = member['name'] ?? '';
                final age = member['age'] ?? 0;
                final role = member['role'] ?? '';
                return Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: HestiaColors.inputBorder,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _getEmojiForAge(age),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: HestiaColors.primary,
                            ),
                          ),
                          Text(
                            role,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: HestiaColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        age > 0 ? '$age yrs' : 'Newborn',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
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
        return const ProfileScreen(showBackButton: false);
      default:
        return _buildHomeTab();
    }
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      child: Container(
        color: HestiaColors.appBackground,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top bar
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(context)
                              .push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const SearchLocationScreen(),
                                ),
                              )
                              .then((_) => _loadProfileData());
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on,
                              color: HestiaColors.primary,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _location,
                                style: const TextStyle(
                                  color: HestiaColors.textMedium,
                                  fontSize: 13,
                                  decoration: TextDecoration.underline,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                            width: 60,
                            height: 60,
                            decoration: const BoxDecoration(
                              color: Color.fromARGB(255, 73, 46, 27),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _userInitials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Active booking card
                _activeBooking != null
                    ? GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) =>
                                  TrackingScreen(bookingData: _activeBooking!),
                            ),
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(255, 65, 42, 27),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: HestiaColors.primary),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 8,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.health_and_safety,
                                  color: HestiaColors.primary,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'ACTIVE BOOKING',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: HestiaColors.inputBorder,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${_activeBooking!['title']} · ${_formatBookingDate(_activeBooking!['scheduled_start'] as DateTime)}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_activeBooking!['caregiver_name']} · ${_formatBookingTime(_activeBooking!['scheduled_start'] as DateTime)}',
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: HestiaColors.inputBorder,
                              ),
                            ],
                          ),
                        ),
                      )
                    : Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: HestiaColors.primary.withValues(alpha: 0.25),
                            width: 1.2,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0A000000),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: HestiaColors.primary.withValues(
                                  alpha: 0.1,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.calendar_today_outlined,
                                color: HestiaColors.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'NO ACTIVE BOOKING',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: HestiaColors.textAccent,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'No upcoming sessions scheduled',
                                    style: TextStyle(
                                      color: HestiaColors.textDark,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Select a service below to book a care visit',
                                    style: TextStyle(
                                      color: HestiaColors.textMedium,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                const SizedBox(height: 18),

                // Household Care Profile (if data loaded)
                if (_primaryReason.isNotEmpty || _members.isNotEmpty) ...[
                  _buildCareProfileSection(),
                  const SizedBox(height: 18),
                ],

                // Our Services heading
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Our Services',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _showAllServices = !_showAllServices;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _showAllServices
                              ? Colors.white
                              : HestiaColors.primary,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: HestiaColors.primary,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          _showAllServices ? 'Show less' : 'See all',
                          style: TextStyle(
                            color: _showAllServices
                                ? HestiaColors.primary
                                : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Services — single row or 2-row grid depending on _showAllServices
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SizeTransition(
                      sizeFactor: animation,
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                  ),
                  child: _showAllServices
                      ? KeyedSubtree(
                          key: const ValueKey('grid'),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final double totalWidth = constraints.maxWidth;
                              final double columnWidth =
                                  (totalWidth - 20.0) / 3;
                              final double desiredHeight = 185.0;
                              final double aspect = columnWidth / desiredHeight;

                              return GridView.count(
                                crossAxisCount: 3,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: aspect,
                                children: _homeServiceCatalog
                                    .map(
                                      (service) => _serviceTile(
                                        service.label,
                                        service.price,
                                        service.originalPrice,
                                        service.rating,
                                        service.ratingCount,
                                      ),
                                    )
                                    .toList(),
                              );
                            },
                          ),
                        )
                      : KeyedSubtree(
                          key: const ValueKey('row'),
                          child: SizedBox(
                            height: 185,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              children: [
                                for (
                                  int i = 0;
                                  i < _homeServiceCatalog.length;
                                  i++
                                ) ...[
                                  if (i > 0) const SizedBox(width: 10),
                                  _serviceTile(
                                    _homeServiceCatalog[i].label,
                                    _homeServiceCatalog[i].price,
                                    _homeServiceCatalog[i].originalPrice,
                                    _homeServiceCatalog[i].rating,
                                    _homeServiceCatalog[i].ratingCount,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 18),

                // ── Busy Partners Section ───────────────────
                const Text(
                  'Our partners are busy right now',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Schedule & book for later',
                  style: TextStyle(
                    fontSize: 14,
                    color: HestiaColors.textMedium,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 200,
                  child: Builder(
                    builder: (context) {
                      final slotInfo = _getRecentAvailableSlot();
                      return ListView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _busyPartnerCard(
                            nextSlot: slotInfo.displayString,
                            duration: '0.5 hr',
                            price: '₹250',
                            originalPrice: '₹500',
                            saveAmount: 'Save ₹250',
                            serviceTitle: 'Post-Delivery Care',
                            durationMinutes: 30,
                            initialDate: slotInfo.date,
                            initialTimeSlot: slotInfo.slot,
                          ),
                          _busyPartnerCard(
                            nextSlot: slotInfo.displayString,
                            duration: '1 hr',
                            price: '₹499',
                            originalPrice: '₹999',
                            saveAmount: 'Save ₹500',
                            serviceTitle: 'Post-Delivery Care',
                            durationMinutes: 60,
                            initialDate: slotInfo.date,
                            initialTimeSlot: slotInfo.slot,
                          ),
                          _busyPartnerCard(
                            nextSlot: slotInfo.displayString,
                            duration: '1.5 hr',
                            price: '₹749',
                            originalPrice: '₹1499',
                            saveAmount: 'Save ₹750',
                            serviceTitle: 'Post-Delivery Care',
                            durationMinutes: 90,
                            initialDate: slotInfo.date,
                            initialTimeSlot: slotInfo.slot,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),

                // ── Book for Later Section ──────────────────
                const Text(
                  'Book for Later',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select your slot & stay worry-free',
                  style: TextStyle(
                    fontSize: 14,
                    color: HestiaColors.textMedium,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _bookLaterCard(
                      title: 'Schedule\nBooking',
                      pillText: 'UP TO 50% OFF',
                      illustration: const ClockIllustration(
                        primaryColor: HestiaColors.primary,
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const ScheduleScreen(
                              serviceTitle: 'Post-Delivery Care',
                            ),
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
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => RepeatBookingScreen(
                              serviceTitle: 'Post-Delivery Care',
                              selectedDate: DateTime.now(),
                              selectedDuration: '3 hrs',
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Reliable & Trustworthy Section ──────────
                const SizedBox(height: 12),
                const Text(
                  'Reliable & Trustworthy',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ensuring integrity through verified standards',
                  style: TextStyle(
                    fontSize: 14,
                    color: HestiaColors.textMedium,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _trustCard(
                      title: 'Verified\nProfessionals\nYou Can Trust',
                      icon: Icons.verified_user_rounded,
                      gradientColors: [Colors.white, const Color(0xFFF9EFE3)],
                    ),
                    const SizedBox(width: 10),
                    _trustCard(
                      title: 'Well Trained to\ndeliver great\nservice',
                      icon: Icons.school_rounded,
                      gradientColors: [Colors.white, const Color(0xFFFAF2EB)],
                    ),
                    const SizedBox(width: 10),
                    _trustCard(
                      title:
                          'Safe, reliable,\nand consistent\nevery single time',
                      icon: Icons.health_and_safety_rounded,
                      gradientColors: [Colors.white, const Color(0xFFFFF9F5)],
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // ── Hestia Brand Footer ─────────────────────
                Center(
                  child: Column(
                    children: [
                      const Text(
                        'Safe Care.\nZero Stress.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: HestiaColors.primary,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'HESTIA',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: HestiaColors.primary,
                          letterSpacing: 3.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Trusted by 450k+ families',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: HestiaColors.textMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  height: 120,
                ), // Spacer so scrolling content goes behind navbar
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _initAnimationController();
    final controller = _navAnimationController!;

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
            bottom: _serviceMinutes.isNotEmpty ? 100 : -60,
            left: 24,
            right: 24,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: _serviceMinutes.isNotEmpty ? 1.0 : 0.0,
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
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 0),

          child: ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
                decoration: BoxDecoration(
                  color: HestiaColors.primary.withValues(alpha: 0.3),
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

                          // Clamping to avoid overflow on extremely small screens
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
                            final Color activeColor = HestiaColors.primary;
                            final Color inactiveColor = Colors.brown.withValues(
                              alpha: 0.5,
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
                                return 'Profile';
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
                                    ? Icons.person
                                    : Icons.person_outline;
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
                                      color: Colors.white.withValues(
                                        alpha: 0.25,
                                      ),
                                      borderRadius: BorderRadius.circular(50),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 1,
                                        ),
                                        width: 1.5,
                                      ),
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
