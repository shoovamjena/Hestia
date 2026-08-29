import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/supabase_service.dart';
import '../theme/colors.dart';
import '../utils/active_booking_navigation.dart';
import '../utils/string_format.dart';
import 'home_screen.dart';
import 'refer_and_earn_screen.dart';

class BookingScheduledScreen extends StatefulWidget {
  final String bookingId;
  final String userName;
  final String address;
  final String serviceTitle;
  final String durationLabel;
  final int amountPaid;
  final DateTime scheduledDate;
  final String scheduledTime;
  final String? serviceImageAsset;
  final int serviceCount;
  final String? caregiverName;
  final bool isAwaitingDeparture;
  final int donationAmount;
  final int serviceSubtotal;
  final double gstAmount;
  final String? bookingStatus;

  const BookingScheduledScreen({
    super.key,
    required this.bookingId,
    required this.userName,
    required this.address,
    required this.serviceTitle,
    required this.durationLabel,
    required this.amountPaid,
    required this.scheduledDate,
    required this.scheduledTime,
    this.serviceImageAsset,
    this.serviceCount = 1,
    this.caregiverName,
    this.isAwaitingDeparture = false,
    this.donationAmount = 0,
    this.serviceSubtotal = 0,
    this.gstAmount = 0,
    this.bookingStatus,
  });

  @override
  State<BookingScheduledScreen> createState() => _BookingScheduledScreenState();
}

class _BookingScheduledScreenState extends State<BookingScheduledScreen> {
  String? _caregiverName;
  double _professionalRating = 0;
  int _professionalSessions = 0;
  bool _isAssigned = false;
  bool _refreshing = false;
  bool _isCancelling = false;
  String? _bookingStatus;
  bool _isInstant = false;
  DateTime? _expectedArrivalAt;
  Timer? _lateTimer;

  @override
  void initState() {
    super.initState();
    _bookingStatus = widget.bookingStatus;
    final initial = widget.caregiverName?.trim();
    if (initial != null &&
        initial.isNotEmpty &&
        initial.toLowerCase() != 'professional') {
      _caregiverName = displayPersonName(initial, fallback: initial);
      _isAssigned = true;
    }
    _refreshAssignment();
    _lateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _lateTimer?.cancel();
    super.dispose();
  }

  DateTime? get _scheduledStartLocal =>
      SupabaseService.parseScheduledStartLocal(
        widget.scheduledDate,
        widget.scheduledTime,
      );

  bool get _isRunningLate =>
      _isAssigned &&
      isProfessionalRunningLateForBooking(_lateCheckBooking);

  Map<String, dynamic> get _lateCheckBooking => {
        'status': _bookingStatus,
        'scheduled_start': _scheduledStartLocal,
        'is_instant': _isInstant,
        'expected_arrival_at': _expectedArrivalAt,
      };

  String get _displayBookingId =>
      widget.bookingId.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '').toUpperCase();

  String get _formattedAssignmentBy {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[widget.scheduledDate.month - 1]} ${widget.scheduledDate.day}, ${widget.scheduledTime}';
  }

  String get _friendlyDuration {
    final lower = widget.durationLabel.toLowerCase();
    final hourMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(lower);
    if (hourMatch != null &&
        (lower.contains('hr') || lower.contains('hour'))) {
      final hours = double.tryParse(hourMatch.group(1)!) ?? 0;
      if (hours > 0 && hours < 1) {
        return '${(hours * 60).round()} Minutes';
      }
      if (hours == 1) return '1 Hour';
      if (hours == hours.roundToDouble()) {
        return '${hours.toInt()} Hours';
      }
      return '${hours.toStringAsFixed(1)} Hours';
    }
    if (lower.contains('min')) {
      return widget.durationLabel;
    }
    return widget.durationLabel;
  }

  Future<void> _refreshAssignment() async {
    if (widget.bookingId.isEmpty || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      final status =
          await SupabaseService.getBookingStatus(widget.bookingId);
      if (!mounted || status == null) return;

      final proId = status['professional_id']?.toString();
      final name = status['caregiver_name']?.toString().trim();
      final assigned = (proId != null && proId.isNotEmpty) ||
          (name != null &&
              name.isNotEmpty &&
              name.toLowerCase() != 'professional');

      setState(() {
        _isAssigned = assigned;
        _bookingStatus = status['status']?.toString() ?? _bookingStatus;
        _isInstant = status['is_instant'] == true;
        final expectedRaw = status['expected_arrival_at'];
        if (expectedRaw is DateTime) {
          _expectedArrivalAt = expectedRaw;
        } else if (expectedRaw != null) {
          _expectedArrivalAt = DateTime.tryParse(expectedRaw.toString());
        }
        if (assigned) {
          _caregiverName = (name != null &&
                  name.isNotEmpty &&
                  name.toLowerCase() != 'professional')
              ? displayPersonName(name, fallback: 'Your professional')
              : 'Your professional';
          _professionalRating = double.tryParse(
                status['professional_rating']?.toString() ?? '',
              ) ??
              0;
          _professionalSessions = int.tryParse(
                status['professional_total_sessions']?.toString() ?? '',
              ) ??
              0;
        }
      });
    } catch (_) {
      // keep current UI
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _goHome() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is coming soon'),
        backgroundColor: HestiaColors.primary,
      ),
    );
  }

  Future<void> _confirmAndCancelBooking() async {
    if (_isCancelling || widget.bookingId.isEmpty) return;

    final status = (_bookingStatus ?? '').trim().toLowerCase();
    if (status == 'cancelled' ||
        status == 'completed' ||
        status == 'no_show' ||
        status == 'unattended') {
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

    setState(() => _isCancelling = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: HestiaColors.primary),
      ),
    );

    try {
      await SupabaseService.cancelBookingByClient(bookingId: widget.bookingId);
      if (!mounted) return;
      Navigator.of(context).pop(); // loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking cancelled successfully.'),
          backgroundColor: HestiaColors.primary,
        ),
      );
      _goHome();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // loading
      setState(() => _isCancelling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to cancel booking: $e'),
          backgroundColor: const Color(0xFFC0392B),
        ),
      );
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    if (parts.isEmpty || parts.first.isEmpty) return 'P';
    return parts.first[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final firstName = widget.userName.trim().isEmpty
        ? 'you'
        : widget.userName.trim().split(RegExp(r'\s+')).first;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goHome();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F2F0),
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  children: [
                    if (_isAssigned && _caregiverName != null)
                      _buildAssignedProfessionalCard()
                    else ...[
                      _buildPendingAssignmentCard(),
                      if (kDebugMode && widget.bookingId.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _DebugAssignProfessionalsButton(
                          bookingId: widget.bookingId,
                          onAssigned: _refreshAssignment,
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    _buildLocationCard(firstName),
                    const SizedBox(height: 12),
                    _buildSummaryCard(),
                    const SizedBox(height: 12),
                    _buildModifyCard(),
                    const SizedBox(height: 12),
                    _buildReferBanner(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: HestiaColors.primary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 28),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: _goHome,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onSelected: (value) {
                      if (value == 'home') _goHome();
                      if (value == 'help') _showComingSoon('Help & Support');
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'home', child: Text('Go to Home')),
                      PopupMenuItem(value: 'help', child: Text('Help & Support')),
                    ],
                  ),
                ],
              ),
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: HestiaColors.primary,
                  size: 36,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _isAssigned ? 'Professional assigned' : 'Booking scheduled',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingAssignmentCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HestiaColors.primary, width: 1.2),
      ),
      child: Text(
        'A professional will be assigned about 45 minutes before '
        'your booking ($_formattedAssignmentBy). You\'ll get a notification '
        'when they\'re confirmed.',
        style: const TextStyle(
          fontSize: 14,
          height: 1.4,
          fontWeight: FontWeight.w500,
          color: HestiaColors.textDark,
        ),
      ),
    );
  }

  Widget _buildAssignedProfessionalCard() {
    final name = _caregiverName!;
    final ratingLabel = _professionalRating > 0
        ? _professionalRating.toStringAsFixed(1)
        : null;
    final sessionsLabel = _professionalSessions > 0
        ? '$_professionalSessions ${_professionalSessions == 1 ? "session" : "sessions"}'
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: HestiaColors.primary.withValues(alpha: 0.35),
          width: 1.2,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _isRunningLate
                      ? const Color(0xFFFFF3E0)
                      : const Color(0xFFE8F5ED),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isRunningLate ? 'RUNNING LATE' : 'ASSIGNED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: _isRunningLate
                        ? const Color(0xFFE65100)
                        : const Color(0xFF2E6B4A),
                  ),
                ),
              ),
              if (_refreshing) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: HestiaColors.primary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFF8C6239),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(name),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: HestiaColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (ratingLabel != null || sessionsLabel != null)
                      Row(
                        children: [
                          if (ratingLabel != null) ...[
                            const Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: Color(0xFFDCA857),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              ratingLabel,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: HestiaColors.textDark,
                              ),
                            ),
                          ],
                          if (ratingLabel != null && sessionsLabel != null)
                            Text(
                              ' · ',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          if (sessionsLabel != null)
                            Text(
                              sessionsLabel,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      )
                    else
                      Text(
                        'Your caregiver for $_formattedAssignmentBy',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isRunningLate)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8F0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFE0B2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: Color(0xFFE65100),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      professionalRunningLateMessage(name),
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8D4E00),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              'Live tracking opens once $name leaves the hub for your booking.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.grey.shade700,
              ),
            ),
        ],
      ),
    );
  }

  void _showBookingSummarySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Booking summary',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: HestiaColors.textDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Booking id - $_displayBookingId',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 20),
              _sheetRow('Service', widget.serviceTitle),
              _sheetRow('When', _formattedAssignmentBy),
              _sheetRow('Duration', _friendlyDuration),
              if (_isAssigned && _caregiverName != null)
                _sheetRow('Professional', _caregiverName!),
              if (widget.donationAmount > 0) ...[
                _sheetRow(
                  'Service charges',
                  '₹${widget.serviceSubtotal + widget.gstAmount.round()}',
                ),
                _sheetRow('NGO donation', '₹${widget.donationAmount}'),
              ],
              _sheetRow('Amount paid', '₹${widget.amountPaid}'),
              _sheetRow(
                'Location',
                widget.address.isNotEmpty ? widget.address : 'Saved address',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HestiaColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sheetRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: HestiaColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard(String firstName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFFF0EEEC),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on_outlined,
              color: Color(0xFF5A5A5A),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Service for $firstName',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: HestiaColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.address.isNotEmpty
                      ? widget.address
                      : 'Address on file',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final countLabel = widget.serviceCount == 1
        ? '1 service in this booking'
        : '${widget.serviceCount} services in this booking';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFFF0EEEC),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: Color(0xFF5A5A5A),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Booking summary',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: HestiaColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Booking id - $_displayBookingId',
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  countLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: HestiaColors.textDark,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EEEC),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isAssigned ? 'Assigned' : 'Scheduled',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5A5A5A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: widget.serviceImageAsset != null
                      ? Image.asset(
                          widget.serviceImageAsset!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _imageFallback(),
                        )
                      : _imageFallback(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.serviceTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: HestiaColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _friendlyDuration,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '₹${widget.amountPaid}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: HestiaColors.textDark,
                ),
              ),
            ],
          ),
          if (widget.donationAmount > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F3EF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE8DDD2)),
              ),
              child: Column(
                children: [
                  _invoiceRow(
                    'Service + GST',
                    '₹${widget.serviceSubtotal + widget.gstAmount.round()}',
                  ),
                  const SizedBox(height: 6),
                  _invoiceRow('NGO donation', '₹${widget.donationAmount}'),
                  const SizedBox(height: 6),
                  const Divider(height: 1, color: Color(0xFFE8DDD2)),
                  const SizedBox(height: 6),
                  _invoiceRow(
                    'Total paid',
                    '₹${widget.amountPaid}',
                    isBold: true,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE8E4E0)),
          TextButton(
            onPressed: _showBookingSummarySheet,
            child: const Text(
              'View booking summary',
              style: TextStyle(
                color: HestiaColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageFallback() {
    return Container(
      color: const Color(0xFFFAF2EB),
      child: const Icon(
        Icons.home_repair_service_outlined,
        color: HestiaColors.primary,
      ),
    );
  }

  Widget _invoiceRow(String label, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: HestiaColors.textDark,
          ),
        ),
      ],
    );
  }

  Widget _buildModifyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Modify your booking',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: HestiaColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Need to make changes? Reschedule or cancel your booking below.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isCancelling ? null : _confirmAndCancelBooking,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFC0392B),
                    side: const BorderSide(
                      color: Color(0xFFC0392B),
                      width: 1.4,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: Text(
                    _isCancelling ? 'Cancelling…' : 'Cancel booking',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _showComingSoon('Reschedule'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HestiaColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text(
                    'Reschedule',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReferBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF8B5E3C),
            HestiaColors.primary,
            Color(0xFF4A3224),
          ],
        ),
      ),
      child: Column(
        children: [
          const Text(
            'Bring a friend',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Get ₹100',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your friend gets flat ₹50 off on their first order',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ReferAndEarnScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: HestiaColors.primary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text(
                'Refer now',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Debug-only control to force-run assign-professionals without waiting for T-45.
class _DebugAssignProfessionalsButton extends StatefulWidget {
  final String bookingId;
  final Future<void> Function()? onAssigned;

  const _DebugAssignProfessionalsButton({
    required this.bookingId,
    this.onAssigned,
  });

  @override
  State<_DebugAssignProfessionalsButton> createState() =>
      _DebugAssignProfessionalsButtonState();
}

class _DebugAssignProfessionalsButtonState
    extends State<_DebugAssignProfessionalsButton> {
  bool _loading = false;
  String? _lastResult;

  Future<void> _run() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _lastResult = null;
    });

    try {
      final result = await SupabaseService.invokeAssignProfessionalsDebug(
        bookingId: widget.bookingId,
      );
      if (!mounted) return;

      final ok = result['ok'] == true;
      final results = result['results'];
      String message;
      var assignedOk = false;
      if (!ok) {
        message = result['error']?.toString() ?? 'Assign failed';
      } else if (results is List && results.isNotEmpty) {
        final first = results.first;
        if (first is Map && first['assigned'] == true) {
          assignedOk = true;
          message =
              'Assigned: ${first['professional_name'] ?? first['professional_id']}';
        } else if (first is Map) {
          final err = first['error']?.toString();
          final hubPros = first['hub_pro_count'];
          final available = first['available_count'];
          if (err != null && err.isNotEmpty) {
            message = err;
          } else if (hubPros == 0) {
            message =
                'No professionals linked to this hub. Add pros in Supabase → professionals.';
          } else if (available == 0) {
            message = 'Professionals found but all are busy for this slot.';
          } else {
            message = 'Ran, but no professional was assigned';
          }
        } else {
          message = 'Function ran';
        }
      } else {
        message = 'Function ran — no bookings in result';
      }

      setState(() => _lastResult = message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              assignedOk ? const Color(0xFF2E6B4A) : Colors.redAccent,
        ),
      );

      if (assignedOk) {
        await widget.onAssigned?.call();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastResult = e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Debug assign failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0C56E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DEBUG',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Skip the 45-minute wait and run assign-professionals now.',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: HestiaColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _run,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.bolt, size: 18),
              label: Text(
                _loading ? 'Assigning…' : 'Assign professional now',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8A6A10),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF8A6A10),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (_lastResult != null) ...[
            const SizedBox(height: 8),
            Text(
              _lastResult!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
