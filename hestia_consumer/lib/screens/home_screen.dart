import 'package:flutter/material.dart';
import 'dart:ui';
import '../theme/colors.dart';
import '../services/supabase_service.dart';
import 'service_detail_screen.dart';
import 'repeat_booking_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  String _userName = 'User';
  String _userInitials = 'U';
  String _location = 'Set Address';
  String _primaryReason = '';
  List<dynamic> _members = [];
  String _email = '';
  String _phone = '';
  int _currentTabIndex = 0;
  bool _showAllServices = false;
  final Map<String, int> _serviceMinutes = {};
  Map<String, dynamic>? _activeBooking;
  List<Map<String, dynamic>> _recentSessions = [];

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  void dispose() {
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
        _email = user.email ?? '';
        _phone = user.phone ?? user.userMetadata?['phone'] ?? '';
      });

      try {
        // 1. Fetch relational profile from database tables
        var data = await SupabaseService.getUserProfile(user.id);
        
        // 2. Fallback to legacy Storage JSON if relational DB tables are empty
        if (data == null || data['address'] == null) {
          data = await SupabaseService.downloadProfileJson(user.id);
        }

        final profileData = data;
        if (profileData != null) {
          setState(() {
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
          });
        }
      } catch (e) {
        debugPrint('Error loading profile details: $e');
      }

      // 3. Fetch active booking details dynamically from database
      try {
        final activeBooking = await SupabaseService.getActiveBooking(user.id);
        if (activeBooking != null) {
          setState(() {
            _activeBooking = activeBooking;
          });
        }
      } catch (e) {
        debugPrint('Error loading active booking: $e');
      }

      // 4. Fetch recent sessions dynamically from database
      try {
        final recent = await SupabaseService.getRecentSessions(user.id);
        setState(() {
          _recentSessions = recent;
        });
      } catch (e) {
        debugPrint('Error loading recent sessions: $e');
      }
    }
    setState(() {
      _isLoading = false;
    });
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
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
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

  Widget _serviceTile(
    String label,
    IconData icon,
    String price,
    String originalPrice,
    String rating,
    String ratingCount,
  ) {
    final minutes = _serviceMinutes[label] ?? 0;
    final isAdded = minutes > 0;
    return SizedBox(
      width: 130,
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ServiceDetailScreen(serviceKey: label),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: HestiaColors.primary.withValues(alpha: 0.25),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Image area with rating badge
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 100,
                child: Stack(
                  children: [
                    Container(
                      height: 100,
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(13),
                          topRight: Radius.circular(13),
                        ),
                      ),
                      child: Center(
                        child: Icon(icon, size: 50, color: HestiaColors.primary),
                      ),
                    ),
                    // Rating pill (top-left)
                    Positioned(
                      top: 5,
                      left: 5,
                      child: Container(
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
                            const Icon(Icons.star, color: Colors.white, size: 9),
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
                    ),
                  ],
                ),
              ),
              // Name, price and ADD / stepper
              Padding(
                padding: const EdgeInsets.fromLTRB(7, 90, 7, 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: HestiaColors.textDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          price,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: HestiaColors.textDark,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          originalPrice,
                          style: const TextStyle(
                            fontSize: 9,
                            color: HestiaColors.textLight,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    // ADD button OR [-] Nmin [+] stepper
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
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color: HestiaColors.primary,
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
            ],
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

  Widget _recentSessionCard(String title, String subtitle, {VoidCallback? onRebook}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: HestiaColors.primary, width: 1),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 5,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: HestiaColors.inputBorder,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.person, color: HestiaColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: HestiaColors.primary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: HestiaColors.textMedium,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onRebook ?? () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: HestiaColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Rebook'),
          ),
        ],
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
            children: [
              const SizedBox(width: 8),
              const Text(
                'CARE PROFILE',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: HestiaColors.primary,
                ),
              ),
              const Spacer(),
              if (_primaryReason.isNotEmpty)
                Container(
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

  @override
  Widget build(BuildContext context) {
    Widget buildNavItem(int index, IconData icon) {
      final isSelected = index == _currentTabIndex;
      return GestureDetector(
        onTap: () {
          setState(() {
            _currentTabIndex = index;
          });
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.9)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.25),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: Icon(
            icon,
            color: isSelected ? HestiaColors.primary : Colors.white70,
            size: 24,
          ),
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      backgroundColor: const Color.fromARGB(255, 252, 252, 252),
      body: Stack(
        children: [
          // ── Main content ──────────────────────────────────────────────
          _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: HestiaColors.primary),
                )
              : SingleChildScrollView(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment(0.0, 0.4),
                        colors: [
                          Color.fromARGB(
                            255,
                            94,
                            61,
                            29,
                          ), // Light warm tan/mocha
                          Color.fromARGB(
                            255,
                            139,
                            106,
                            65,
                          ), // Soft warm apricot/cream
                          Color.fromARGB(
                            255,
                            252,
                            252,
                            252,
                          ), // Light pale cream/yellow
                        ],
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 12.0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top greeting
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'HESTIA',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 3,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'WELCOME',
                                        style: TextStyle(
                                          color: HestiaColors.inputBorder,
                                          fontSize: 32,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _userName.toUpperCase(),
                                        style: const TextStyle(
                                          color: Color(0xFFF9EFE3),
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _location,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
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
                                    const SizedBox(height: 6),
                                    // SizedBox(
                                    //   width: 44,
                                    //   height: 28,
                                    //   child: IconButton(
                                    //     padding: EdgeInsets.zero,
                                    //     icon: const Icon(
                                    //       Icons.logout,
                                    //       size: 18,
                                    //       color: Colors.white70,
                                    //     ),
                                    //     onPressed: () async {
                                    //       await SupabaseService.signOut();
                                    //       if (context.mounted) {
                                    //         ScaffoldMessenger.of(
                                    //           context,
                                    //         ).showSnackBar(
                                    //           const SnackBar(
                                    //             content: Text('Signed out'),
                                    //           ),
                                    //         );
                                    //         Navigator.of(
                                    //           context,
                                    //         ).pushAndRemoveUntil(
                                    //           MaterialPageRoute(
                                    //             builder: (c) =>
                                    //                 const LandingScreen(),
                                    //           ),
                                    //           (route) => false,
                                    //         );
                                    //       }
                                    //     },
                                    //     tooltip: 'Logout',
                                    //   ),
                                    // ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Active booking card
                            _activeBooking != null
                                ? GestureDetector(
                                    onTap: () {
                                      // Optional: Navigate to booking detail screen
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
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
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
                                            color: HestiaColors.primary.withValues(alpha: 0.1),
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
                            if (_primaryReason.isNotEmpty ||
                                _members.isNotEmpty) ...[
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
                                      _showAllServices
                                          ? 'Show less'
                                          : 'See all',
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
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
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
                                      child: GridView.count(
                                        crossAxisCount: 3,
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        crossAxisSpacing: 10,
                                        mainAxisSpacing: 10,
                                        childAspectRatio: 0.82,
                                        children: [
                                          _serviceTile(
                                            'Post-Delivery',
                                            Icons.local_hospital,
                                            '₹499',
                                            '₹999',
                                            '4.9',
                                            '38.6k',
                                          ),
                                          _serviceTile(
                                            'Babysitting',
                                            Icons.child_care,
                                            '₹399',
                                            '₹799',
                                            '4.9',
                                            '31.5k',
                                          ),
                                          _serviceTile(
                                            'Mobility',
                                            Icons.accessibility_new,
                                            '₹449',
                                            '₹899',
                                            '4.9',
                                            '39.7k',
                                          ),
                                          _serviceTile(
                                            'Pre-Pregnancy',
                                            Icons.favorite_border,
                                            '₹599',
                                            '₹999',
                                            '4.9',
                                            '13.4k',
                                          ),
                                          _serviceTile(
                                            'Bathing',
                                            Icons.bathtub,
                                            '₹349',
                                            '₹699',
                                            '4.9',
                                            '4.5k',
                                          ),
                                          _serviceTile(
                                            'Concierge',
                                            Icons.room_service,
                                            '₹299',
                                            '₹599',
                                            '4.9',
                                            '3.3k',
                                          ),
                                        ],
                                      ),
                                    )
                                  : KeyedSubtree(
                                      key: const ValueKey('row'),
                                      child: SizedBox(
                                        height: 185,
                                        child: ListView(
                                          scrollDirection: Axis.horizontal,
                                          physics:
                                              const BouncingScrollPhysics(),
                                          children: [
                                            _serviceTile(
                                              'Post-Delivery',
                                              Icons.local_hospital,
                                              '₹499',
                                              '₹999',
                                              '4.9',
                                              '38.6k',
                                            ),
                                            const SizedBox(width: 10),
                                            _serviceTile(
                                              'Babysitting',
                                              Icons.child_care,
                                              '₹399',
                                              '₹799',
                                              '4.9',
                                              '31.5k',
                                            ),
                                            const SizedBox(width: 10),
                                            _serviceTile(
                                              'Mobility',
                                              Icons.accessibility_new,
                                              '₹449',
                                              '₹899',
                                              '4.9',
                                              '39.7k',
                                            ),
                                            const SizedBox(width: 10),
                                            _serviceTile(
                                              'Pre-Pregnancy',
                                              Icons.favorite_border,
                                              '₹599',
                                              '₹999',
                                              '4.9',
                                              '13.4k',
                                            ),
                                            const SizedBox(width: 10),
                                            _serviceTile(
                                              'Bathing',
                                              Icons.bathtub,
                                              '₹349',
                                              '₹699',
                                              '4.9',
                                              '4.5k',
                                            ),
                                            const SizedBox(width: 10),
                                            _serviceTile(
                                              'Concierge',
                                              Icons.room_service,
                                              '₹299',
                                              '₹599',
                                              '4.9',
                                              '3.3k',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 12),

                            // Recent sessions
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Recent Sessions',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {},
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: HestiaColors.primary,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'History',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            _recentSessions.isNotEmpty
                                ? ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: _recentSessions.length,
                                    separatorBuilder: (context, index) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, index) {
                                      final session = _recentSessions[index];
                                      final title = '${session['title']} · ${session['caregiver_name']}';
                                      final date = session['scheduled_start'] as DateTime;
                                      final duration = session['duration_hours'] as num;
                                      
                                      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                                      final dateStr = '${months[date.month - 1]} ${date.day}';
                                      final subtitle = '$dateStr · ${duration % 1 == 0 ? duration.toInt() : duration} hrs';

                                      return _recentSessionCard(
                                        title,
                                        subtitle,
                                        onRebook: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) => RepeatBookingScreen(
                                                serviceTitle: session['title'] == 'Post-Delivery' ? 'Post-Delivery Care' : 
                                                              session['title'] == 'Pre-Pregnancy' ? 'Pre-Pregnancy Care' :
                                                              session['title'] == 'Babysitting' ? 'Certified Babysitting' :
                                                              session['title'] == 'Mobility' ? 'Mobility Support' :
                                                              session['title'] == 'Bathing & Grooming' ? 'Bathing & Grooming' :
                                                              'Admin Concierge',
                                                selectedDate: DateTime.now(),
                                                selectedTime: '8:00 AM',
                                                selectedDuration: '1 hr',
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  )
                                : Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: HestiaColors.primary.withValues(alpha: 0.15),
                                        width: 1.2,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.history_toggle_off,
                                          color: HestiaColors.textLight.withValues(alpha: 0.6),
                                          size: 40,
                                        ),
                                        const SizedBox(height: 12),
                                        const Text(
                                          'No Care History Yet',
                                          style: TextStyle(
                                            color: HestiaColors.textDark,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'Completed care sessions will be listed here.',
                                          style: TextStyle(
                                            color: HestiaColors.textMedium,
                                            fontSize: 12,
                                          ),
                                          textAlign: TextAlign.center,
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
                ),

          // ── Floating cart pill ────────────────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutBack,
            bottom: _serviceMinutes.isNotEmpty ? 140 : -60,
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
                        // TODO: navigate to cart screen
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
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 15,
                spreadRadius: 1,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 4,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      HestiaColors.primary.withValues(alpha: 0.55),
                      HestiaColors.primary.withValues(alpha: 0.35),
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    buildNavItem(0, Icons.home),
                    buildNavItem(1, Icons.calendar_month),
                    buildNavItem(2, Icons.schedule),
                    buildNavItem(3, Icons.person),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
