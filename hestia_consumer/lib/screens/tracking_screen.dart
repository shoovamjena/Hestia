import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../services/supabase_service.dart';
import 'activity_log_screen.dart';
import 'session_complete_screen.dart';
import 'chat_screen.dart';
import 'emergency_screen.dart';

class TrackingScreen extends StatefulWidget {
  final Map<String, dynamic> bookingData;

  const TrackingScreen({super.key, required this.bookingData});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  late Map<String, dynamic> _bookingData;
  bool _isOnTheWayView = true;
  late Timer _stopwatchTimer;
  Timer? _statusTimer;
  int _secondsElapsed = 5047; // starts around 01:24:07
  bool _isShowingVerificationDialog = false;

  @override
  void initState() {
    super.initState();
    _bookingData = Map<String, dynamic>.from(widget.bookingData);
    final status = _bookingData['status'];
    _isOnTheWayView = !(status == 'started' || status == 'active' || status == 'in_progress');
    _startStopwatch();
    _startStatusPolling();
  }

  @override
  void dispose() {
    _stopwatchTimer.cancel();
    _statusTimer?.cancel();
    super.dispose();
  }

  void _startStatusPolling() {
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      final bookingId = _bookingData['booking_id'];
      if (bookingId != null) {
        final updated = await SupabaseService.getBookingStatus(bookingId.toString());
        if (updated != null && mounted) {
          setState(() {
            _bookingData = updated;
            final status = _bookingData['status'];
            final isSessionActive = (status == 'started' || status == 'active' || status == 'in_progress');
            if (isSessionActive) {
              _isOnTheWayView = false;
            } else {
              _isOnTheWayView = true;
            }
          });
          _checkArrivalRequest(updated);
        }
      }
    });
  }

  void _startStopwatch() {
    _stopwatchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          final actualStart = _bookingData['actual_start'];
          if (actualStart != null) {
            final startTime = actualStart is DateTime ? actualStart : DateTime.parse(actualStart.toString());
            _secondsElapsed = DateTime.now().difference(startTime).inSeconds;
          } else {
            _secondsElapsed++;
          }
        });
      }
    });
  }

  String _formatStopwatch(int totalSeconds) {
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _checkArrivalRequest(Map<String, dynamic> bookingData) {
    if (bookingData['arrival_requested'] == true && !_isShowingVerificationDialog) {
      _showArrivalVerificationDialog(bookingData);
    }
  }

  void _showArrivalVerificationDialog(Map<String, dynamic> bookingData) {
    _isShowingVerificationDialog = true;
    final bookingId = bookingData['booking_id'] as String;
    final caregiverName = bookingData['caregiver_name'] ?? 'Sunita Rao';
    
    // Generate deterministic 6-character code from booking ID
    final code = _generateVerificationCode(bookingId);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: const Color(0xFFFAF6F0),
          title: const Row(
            children: [
              Icon(
                Icons.verified_user_rounded,
                color: HestiaColors.primary,
                size: 28,
              ),
              SizedBox(width: 10),
              Text(
                'Start Session?',
                style: TextStyle(
                  color: HestiaColors.textDark,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$caregiverName has arrived and is ready to start your session.',
                style: const TextStyle(
                  color: HestiaColors.textDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Please verify the 6-digit alphanumeric code shown below with the caregiver before starting:',
                style: TextStyle(
                  color: HestiaColors.textMedium,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: HestiaColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: HestiaColors.primary.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    code,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: HestiaColors.primary,
                      letterSpacing: 4.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      setState(() {
                        _isShowingVerificationDialog = false;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: HestiaColors.primary.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: HestiaColors.textMedium,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      setState(() {
                        _isShowingVerificationDialog = false;
                      });
                      
                      // Actually start the session now
                      await SupabaseService.startMockSession(bookingId);
                      
                      // Immediately refresh state
                      final updated = await SupabaseService.getBookingStatus(bookingId);
                      if (updated != null && mounted) {
                        setState(() {
                          _bookingData = updated;
                          _isOnTheWayView = false;
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HestiaColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Confirm & Start',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _generateVerificationCode(String id) {
    final cleaned = id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    if (cleaned.length >= 6) {
      return cleaned.substring(0, 6);
    }
    return '${cleaned}HESTIA'.substring(0, 6);
  }

  @override
  Widget build(BuildContext context) {
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
          leading: Padding(
            padding: const EdgeInsets.all(8.0),
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: HestiaColors.primary.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.chevron_left_rounded,
                  color: HestiaColors.primary,
                  size: 20,
                ),
              ),
            ),
          ),
          title: () {
            final status = _bookingData['status'];
            final isSessionActive = (status == 'started' || status == 'active' || status == 'in_progress');
            if (!isSessionActive) {
              return const Text(
                'On the Way',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              );
            }
            return const Text(
              'Active Session',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            );
          }(),
          centerTitle: true,
          actions: [
            if (!_isOnTheWayView)
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const ChatScreen(
                          caregiverName: 'Sunita Rao',
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: HestiaColors.primary.withValues(alpha: 0.15),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: HestiaColors.primary,
                      size: 18,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _isOnTheWayView ? _buildOnTheWayView() : _buildActiveSessionView(),
          ),
        ),
        bottomNavigationBar: !_isOnTheWayView
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC0392B),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => EmergencyScreen(
                              bookingData: _bookingData,
                            ),
                          ),
                        );
                      },
                      child: const Text(
                        'Emergency — Contact Dispatch',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildOnTheWayView() {
    return SingleChildScrollView(
      key: const ValueKey('on_the_way'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              'Sunita is on the way',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Stylized custom map container
          Container(
            height: 240,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: HestiaColors.primary.withValues(alpha: 0.15),
                width: 1.2,
              ),
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: MapPainter(),
                  ),
                ),
                // Hub label overlay
                Positioned(
                  top: 40,
                  left: 30,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 6,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: HestiaColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Hub',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: HestiaColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // ETA floating card overlay
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              'ARRIVING IN',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: HestiaColors.textMedium,
                                letterSpacing: 0.5,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '23 min',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: HestiaColors.textDark,
                              ),
                            ),
                          ],
                        ),
                        const Text(
                          '2.4 km away',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: HestiaColors.textMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Caregiver Profile Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: HestiaColors.primary.withValues(alpha: 0.15),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: Color(0xFF8C6239),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'SR',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Sunita Rao',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: HestiaColors.textDark,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Post-Delivery Specialist',
                        style: TextStyle(
                          fontSize: 12,
                          color: HestiaColors.textMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.star, color: Colors.orange, size: 14),
                    SizedBox(width: 4),
                    Text(
                      '4.9',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: HestiaColors.textDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Grid metrics block (Booked, Service, Hub)
          Row(
            children: [
              _metricBlock('BOOKED', '9:00\nAM', '3 hrs'),
              const SizedBox(width: 10),
              _metricBlock('SERVICE', 'Post-\nDelivery', 'Care'),
              const SizedBox(width: 10),
              _metricBlock('HUB', 'Koraman-\ngala', 'South BLR'),
            ],
          ),
          const SizedBox(height: 20),
          // Info banner updates
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFDF7F0),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: HestiaColors.primary.withValues(alpha: 0.15),
                width: 1.2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  color: Color(0xFFC39365),
                  size: 20,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Location updates every 15 seconds. You\'ll be notified when Sunita arrives.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF78593E),
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Contact Dispatcher Button
          GestureDetector(
            onTap: () {},
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: HestiaColors.primary.withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: const Center(
                child: Text(
                  'Contact Hub Dispatch',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: HestiaColors.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () async {
              final bookingId = _bookingData['booking_id'];
              if (bookingId != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Simulating professional arrival...'),
                    duration: Duration(seconds: 1),
                  ),
                );
                
                await SupabaseService.requestSessionStart(bookingId.toString());
                
                // Immediately refresh status
                final updated = await SupabaseService.getBookingStatus(bookingId.toString());
                if (updated != null && mounted) {
                  setState(() {
                    _bookingData = updated;
                  });
                  _checkArrivalRequest(updated);
                }
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x262ECC71),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_arrow_rounded, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Simulate Professional Arrival',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSessionView() {
    return SingleChildScrollView(
      key: const ValueKey('active_session'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              'Active session',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Time details panel (brown card)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF5A3E25),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: HestiaColors.primary.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'SESSION TIME',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFDCD2C9),
                            letterSpacing: 0.8,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF2ECC71),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Text(
                                'Live',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _formatStopwatch(_secondsElapsed),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Ends at 12:00 PM · 1 hr 35 min left',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFFDCD2C9),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: const [
                      Text(
                        'Professional',
                        style: TextStyle(
                          fontSize: 9,
                          color: Color(0xFFDCD2C9),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Sunita\nRao',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Activity log header
          GestureDetector(
             onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ActivityLogScreen(
                    bookingData: _bookingData,
                  ),
                ),
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Activity log',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: HestiaColors.textDark,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        '4 entries',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF2E7D32),
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Activity log entries list
          Column(
            children: [
              _logEntry('10:48', 'Newborn bathed and swaddled comfortably', true, true),
              _logEntry('10:22', 'Breastfeeding positioning assisted, mother resting', false, false),
              _logEntry('10:05', 'Light breakfast prepared for mother', false, false),
              _logEntry('09:38', 'Session started. Checked on Aryan, settled well', false, false),
            ],
          ),
          const SizedBox(height: 24),
          // Caregiver Footer Info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: HestiaColors.primary.withValues(alpha: 0.15),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: Color(0xFF8C6239),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'SR',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Sunita Rao',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: HestiaColors.textDark,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Post-Delivery Specialist · Verified',
                        style: TextStyle(
                          fontSize: 11,
                          color: HestiaColors.textMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.verified_user_rounded,
                  color: Colors.green,
                  size: 20,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // End Session Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC0392B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => SessionCompleteScreen(
                      bookingData: _bookingData,
                    ),
                  ),
                );
              },
              child: const Text(
                'End Session',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricBlock(String label, String value, String sub) {
    return Expanded(
      child: Container(
        height: 90,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFDFCFB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: HestiaColors.primary.withValues(alpha: 0.1),
            width: 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: HestiaColors.textLight,
                letterSpacing: 0.6,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: HestiaColors.textDark,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: const TextStyle(
                fontSize: 9,
                color: HestiaColors.textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logEntry(String time, String message, bool isGreen, bool showNewBadge) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            time,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: HestiaColors.textMedium,
            ),
          ),
          const SizedBox(width: 14),
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isGreen ? const Color(0xFF2ECC71) : const Color(0xFFF39C12),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontSize: 13,
                      color: HestiaColors.textDark,
                      height: 1.35,
                    ),
                  ),
                ),
                if (showNewBadge) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'New',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 1. Sage Green Background
    final Paint backgroundPaint = Paint()
      ..color = const Color(0xFFCADFC6)
      ..style = PaintingStyle.fill;
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(20),
      ),
      backgroundPaint,
    );

    // 2. Road Network (Off-white roads)
    final Paint roadPaint = Paint()
      ..color = const Color(0xFFE3EDE0)
      ..strokeWidth = 32.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Draw horizontal grid lines
    canvas.drawLine(Offset(-20, size.height * 0.25), Offset(size.width + 20, size.height * 0.25), roadPaint);
    canvas.drawLine(Offset(-20, size.height * 0.65), Offset(size.width + 20, size.height * 0.65), roadPaint);

    // Draw vertical grid lines
    canvas.drawLine(Offset(size.width * 0.25, -20), Offset(size.width * 0.25, size.height + 20), roadPaint);
    canvas.drawLine(Offset(size.width * 0.75, -20), Offset(size.width * 0.75, size.height + 20), roadPaint);

    // 3. Blocks/Buildings (rectangular overlays)
    final Paint buildingPaint = Paint()
      ..color = const Color(0xFFBED2B9)
      ..style = PaintingStyle.fill;

    // Place building blocks in intersections
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(15, 12, size.width * 0.16, size.height * 0.15), const Radius.circular(8)), buildingPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.32, 12, size.width * 0.36, size.height * 0.15), const Radius.circular(8)), buildingPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(15, size.height * 0.33, size.width * 0.16, size.height * 0.24), const Radius.circular(8)), buildingPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.32, size.height * 0.33, size.width * 0.36, size.height * 0.24), const Radius.circular(8)), buildingPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.82, size.height * 0.33, size.width * 0.15, size.height * 0.24), const Radius.circular(8)), buildingPaint);

    // 4. Dotted route path calculation
    final List<Offset> routePoints = [];
    final int steps = 40;
    
    // Smooth bezier curve from Hub (0.18, 0.25) to Caregiver Location (0.6, 0.65)
    final Offset start = Offset(size.width * 0.18, size.height * 0.25);
    final Offset end = Offset(size.width * 0.7, size.height * 0.65);
    final Offset cp1 = Offset(size.width * 0.18, size.height * 0.65);
    final Offset cp2 = Offset(size.width * 0.5, size.height * 0.65);

    for (int i = 0; i <= steps; i++) {
      final double t = i / steps;
      final double t1 = 1 - t;
      
      // Cubic bezier interpolation
      final double x = t1 * t1 * t1 * start.dx +
          3 * t1 * t1 * t * cp1.dx +
          3 * t1 * t * t * cp2.dx +
          t * t * t * end.dx;
      final double y = t1 * t1 * t1 * start.dy +
          3 * t1 * t1 * t * cp1.dy +
          3 * t1 * t * t * cp2.dy +
          t * t * t * end.dy;
      
      routePoints.add(Offset(x, y));
    }

    // 5. Draw Dotted Path
    final Paint dotPaint = Paint()
      ..color = const Color(0xFF8C6239)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.fill;

    for (int i = 0; i < routePoints.length; i += 2) {
      canvas.drawCircle(routePoints[i], 2.5, dotPaint);
    }

    // 6. Draw Hub Pin anchor point
    final Paint hubAnchorPaint = Paint()
      ..color = const Color(0xFF8C6239)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(start, 4.0, hubAnchorPaint);

    // 7. Caregiver orange location indicator (pulse dot)
    final Paint outerGlowPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    final Paint innerDotPaint = Paint()
      ..color = const Color(0xFFF39C12)
      ..style = PaintingStyle.fill;

    // Position care assistant at t = 0.6 on the route path
    final Offset caregiverPos = routePoints[(steps * 0.55).floor()];
    canvas.drawCircle(caregiverPos, 7.0, outerGlowPaint);
    canvas.drawCircle(caregiverPos, 4.5, innerDotPaint);
  }

  @override
  bool shouldRepaint(covariant MapPainter oldDelegate) => false;
}
