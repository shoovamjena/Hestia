import 'dart:async';

import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../theme/colors.dart';
import 'rate_session_screen.dart';

class EmergencyScreen extends StatefulWidget {
  final Map<String, dynamic> bookingData;
  const EmergencyScreen({super.key, required this.bookingData});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen>
    with SingleTickerProviderStateMixin {
  int _secondsLeft = 5;
  Timer? _timer;
  bool _callInitiated = false;
  bool _isEndingSession = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft > 1) {
        setState(() {
          _secondsLeft--;
        });
      } else {
        _timer?.cancel();
        setState(() {
          _secondsLeft = 0;
          _callInitiated = true;
        });
        unawaited(_callDispatchAndEndSession());
      }
    });
  }

  void _cancelCountdown() {
    _timer?.cancel();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Emergency call cancelled.'),
        backgroundColor: HestiaColors.primary,
      ),
    );
  }

  void _triggerCall(String serviceName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Calling $serviceName...'),
        backgroundColor: const Color(0xFFC0392B),
      ),
    );
  }

  String get _hubName {
    final raw = widget.bookingData['hub_name']?.toString().trim() ?? '';
    return raw.isEmpty ? 'Assigned Hub' : raw;
  }

  String get _hubAddress {
    final raw = widget.bookingData['hub_address']?.toString().trim() ?? '';
    return raw.isEmpty ? 'Hub address unavailable' : raw;
  }

  String get _dispatchLabel => '$_hubName Dispatch';

  Future<String?> _resolveSessionId() async {
    final existing = widget.bookingData['session_id']?.toString();
    if (existing != null && existing.isNotEmpty) return existing;

    final bookingId = widget.bookingData['booking_id']?.toString();
    if (bookingId == null || bookingId.isEmpty) return null;

    final refreshed = await SupabaseService.getBookingStatus(bookingId);
    return refreshed?['session_id']?.toString();
  }

  Future<void> _callDispatchAndEndSession() async {
    if (_isEndingSession) return;
    _timer?.cancel();

    final messenger = ScaffoldMessenger.of(context);
    if (mounted) {
      setState(() {
        _callInitiated = true;
        _isEndingSession = true;
      });
    }

    _triggerCall(_dispatchLabel);

    try {
      final sessionId = await _resolveSessionId();
      if (sessionId == null || sessionId.isEmpty) {
        throw Exception('Missing session id for emergency dispatch.');
      }

      await SupabaseService.endSessionByClient(sessionId: sessionId);

      final bookingId = widget.bookingData['booking_id']?.toString();
      final refreshed = bookingId != null && bookingId.isNotEmpty
          ? await SupabaseService.getBookingStatus(bookingId)
          : null;
      final sessionData = Map<String, dynamic>.from(
        refreshed ?? widget.bookingData,
      );
      sessionData['status'] = 'completed';
      sessionData['session_id'] = sessionId;
      sessionData['caregiver_name'] =
          sessionData['caregiver_name'] ?? 'Professional';
      sessionData['title'] =
          sessionData['title'] ?? sessionData['service_type'] ?? 'Care';

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => RateSessionScreen(sessionData: sessionData),
        ),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _callInitiated = false;
        _isEndingSession = false;
        _secondsLeft = 5;
      });
      _startCountdown();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Emergency dispatch failed: $e'),
          backgroundColor: const Color(0xFFC0392B),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final caregiver = widget.bookingData['caregiver_name'] ?? 'Sunita Rao';
    final service = widget.bookingData['title'] ?? 'Post-Delivery Care';

    return Container(
        color: HestiaColors.appBackground,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: _cancelCountdown,
          ),
        ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            children: [
              const Spacer(),

              // Pulsing emergency circle icon
              ScaleTransition(
                scale: Tween<double>(begin: 0.95, end: 1.05).animate(
                  CurvedAnimation(
                    parent: _pulseController,
                    curve: Curves.easeInOut,
                  ),
                ),
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC0392B).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFC0392B).withValues(alpha: 0.3),
                      width: 4,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: const BoxDecoration(
                      color: Color(0xFFC0392B),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x66C0392B),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: _callInitiated
                        ? const Icon(
                            Icons.phone_in_talk_rounded,
                            color: Colors.white,
                            size: 44,
                          )
                        : Text(
                            '$_secondsLeft',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 44,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              Text(
                _callInitiated
                    ? 'Connecting to $_dispatchLabel...'
                    : 'Emergency Escalation',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _callInitiated
                    ? 'Ending the session and notifying the professional hub now.'
                    : 'Calling $_dispatchLabel automatically in $_secondsLeft seconds...',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),

              const Spacer(),

              // Dispatch reference info card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2C),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white12,
                    width: 1.2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ACTIVE SESSION REFERENCE',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildReferenceRow('Professional', caregiver),
                    const Divider(color: Colors.white10, height: 20),
                    _buildReferenceRow('Service Type', service),
                    const Divider(color: Colors.white10, height: 20),
                    _buildReferenceRow('Hub', _hubName),
                    const Divider(color: Colors.white10, height: 20),
                    _buildReferenceRow('Hub Address', _hubAddress),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action buttons
              if (!_callInitiated) ...[
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
                    onPressed: _callDispatchAndEndSession,
                    child: Text(
                      'Call $_dispatchLabel Now',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white30, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  onPressed: () {
                    _timer?.cancel();
                    setState(() {
                      _callInitiated = true;
                    });
                    _triggerCall("Emergency Services (112)");
                  },
                  child: const Text(
                    'Call Emergency Services (112)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              TextButton(
                onPressed: _isEndingSession ? null : _cancelCountdown,
                child: const Text(
                  'Cancel & Go Back',
                  style: TextStyle(
                    color: Colors.white60,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
     ),
    );
  }

  Widget _buildReferenceRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
