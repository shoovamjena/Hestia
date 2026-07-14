import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/razorpay_config.dart';
import '../theme/colors.dart';
import '../services/supabase_service.dart';
import 'home_screen.dart';
import 'service_detail_screen.dart';

class ProfessionalProfile {
  final String id;
  final String name;
  final String initials;
  final Color avatarBg;
  final String rating;
  final int sessionsCount;
  final int distanceKm;
  final List<String> tags; // e.g. ['Verified', 'Regular']

  const ProfessionalProfile({
    required this.id,
    required this.name,
    required this.initials,
    required this.avatarBg,
    required this.rating,
    required this.sessionsCount,
    required this.distanceKm,
    required this.tags,
  });
}

class ChooseProfessionalScreen extends StatefulWidget {
  final String serviceTitle;
  final DateTime selectedDate;
  final String selectedTime;
  final String selectedDuration;
  final String repeatOption;
  final String endsAfter;
  final bool preferSameProfessional;
  final Map<String, int>? servicesMap;

  /// When set, payment was already completed before this screen (e.g. from the
  /// cart). The screen then just searches and confirms the booking.
  final String? paymentId;

  /// Total already paid (in rupees) when [paymentId] is provided.
  final int? paidAmount;

  const ChooseProfessionalScreen({
    super.key,
    required this.serviceTitle,
    required this.selectedDate,
    required this.selectedTime,
    required this.selectedDuration,
    required this.repeatOption,
    required this.endsAfter,
    required this.preferSameProfessional,
    this.servicesMap,
    this.paymentId,
    this.paidAmount,
  });

  @override
  State<ChooseProfessionalScreen> createState() => _ChooseProfessionalScreenState();
}

class _ChooseProfessionalScreenState extends State<ChooseProfessionalScreen> {
  bool _isSearching = true;
  bool _fetchError = false;
  bool _noProfessionalsFound = false;
  Timer? _searchTimer;
  ProfessionalProfile? _matchedProfessional;
  List<ProfessionalProfile> _professionals = [];
  late Razorpay _razorpay;
  String _userName = '';
  String _userEmail = '';
  String _userPhone = '';

  // Deterministic avatar colours derived from a professional's DB id
  static const List<Color> _avatarPalette = [
    Color(0xFF7A9B82), // sage green
    Color(0xFF8C7AA5), // muted purple
    Color(0xFF7A8FAB), // slate blue
    Color(0xFFAB7A7A), // dusty rose
    Color(0xFFAB9A7A), // warm sand
    Color(0xFF7AABA5), // teal
  ];

  Color _avatarColorForId(String id) {
    final hash = id.codeUnits.fold(0, (prev, e) => prev + e);
    return _avatarPalette[hash % _avatarPalette.length];
  }

  String _initialsForName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _loadUserDetails();
    _fetchAndSearch();
  }

  Future<void> _loadUserDetails() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    _userEmail = SupabaseService.currentUserEmail;
    _userPhone = SupabaseService.currentUserPhone;
    try {
      final profile = await SupabaseService.getUserProfile(user.id);
      if (profile != null && mounted) {
        setState(() {
          _userName = profile['name']?.toString() ?? '';
          if ((profile['email'] as String?)?.isNotEmpty == true) {
            _userEmail = profile['email'] as String;
          }
          if ((profile['phone'] as String?)?.isNotEmpty == true) {
            _userPhone = profile['phone'] as String;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading user details for payment: $e');
    }
  }

  Future<void> _fetchAndSearch() async {
    // Start the 4-second searching animation timer
    final Completer<void> timerCompleter = Completer();
    _searchTimer = Timer(const Duration(milliseconds: 4000), () {
      if (!timerCompleter.isCompleted) timerCompleter.complete();
    });

    // Fetch matched professionals from the matching service concurrently with the timer
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('No authenticated user session found.');
      }

      final matchedRows = await SupabaseService.matchProfessionals(
        userId: user.id,
        serviceTitle: widget.serviceTitle,
        selectedDate: widget.selectedDate,
        selectedTime: widget.selectedTime,
        selectedDuration: widget.selectedDuration,
        preferSameProfessional: widget.preferSameProfessional,
      );

      final fetched = matchedRows.map((row) {
        final id = row['id']?.toString() ?? '';
        final name = row['full_name']?.toString() ?? 'Professional';
        final sessions = int.tryParse(row['total_sessions']?.toString() ?? '') ?? 0;
        final avgRatingVal = double.tryParse(row['avg_rating']?.toString() ?? '') ?? 5.0;
        final rating = avgRatingVal.toStringAsFixed(1);
        final distance = 5;
        final isVerified = row['background_check_status']?.toString() == 'verified';
        final isTopRated = avgRatingVal >= 4.8;
        final matchScore = row['matching_score'] as double? ?? 0.0;

        final tags = <String>[
          if (isVerified) 'Verified',
          if (isTopRated) 'Top rated',
          if (matchScore > 0) 'Match: ${matchScore.toStringAsFixed(0)}%',
        ];

        return ProfessionalProfile(
          id: id,
          name: name,
          initials: _initialsForName(name),
          avatarBg: _avatarColorForId(id),
          rating: rating,
          sessionsCount: sessions,
          distanceKm: distance,
          tags: tags.isEmpty ? ['Verified'] : tags,
        );
      }).toList();

      // Wait for the timer to complete before revealing the match
      await timerCompleter.future;

      if (mounted) {
        setState(() {
          _isSearching = false;
          if (fetched.isNotEmpty) {
            _professionals = fetched;
            _matchedProfessional = fetched.first;
            _noProfessionalsFound = false;
          } else {
            _noProfessionalsFound = true;
          }
        });
      }
    } catch (e) {
      // Ensure timer still completes
      await timerCompleter.future;
      if (mounted) {
        setState(() {
          _isSearching = false;
          _fetchError = true;
          _noProfessionalsFound = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _razorpay.clear();
    super.dispose();
  }

  // Map service title to a role label (generic, not name-specific)
  String _getRoleForProfessional(String name) {
    final title = widget.serviceTitle.toLowerCase();
    if (title.contains('post-delivery') || title.contains('pregnancy')) {
      return 'Post-Delivery Specialist';
    } else if (title.contains('babysitting')) {
      return 'Infant Care Provider';
    } else if (title.contains('mobility')) {
      return 'Geriatric Mobility Specialist';
    } else if (title.contains('bathing')) {
      return 'Personal Hygiene Specialist';
    } else if (title.contains('concierge')) {
      return 'Concierge Care Coordinator';
    }
    return 'Senior Care Specialist';
  }

  // Format date helper: "Fri, Jun 12"
  String _formatDate(DateTime date) {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    final weekdayStr = weekdays[date.weekday - 1];
    final monthStr = months[date.month - 1];
    return '$weekdayStr, $monthStr ${date.day}';
  }

  /// Back is blocked while searching. Once the search finishes, the user may
  /// leave if no professional was found or an error occurred. When a
  /// professional is matched after payment (paid mode), the user must stay and
  /// confirm; in the unpaid flow they may still go back to adjust.
  bool get _canLeave {
    if (_isSearching) return false;
    if (_noProfessionalsFound || _fetchError) return true;
    return widget.paymentId == null;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canLeave,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_canLeave) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _isSearching
                    ? 'Please wait while we find your professional.'
                    : 'Please confirm your booking to continue.',
              ),
              backgroundColor: HestiaColors.primary,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: Scaffold(
      backgroundColor: const Color.fromARGB(255, 252, 252, 252),
      body: Container(
        color: HestiaColors.appBackground,
        child: SafeArea(
          child: Column(
            children: [
              // Custom App Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  children: [
                    // Back Button (Circular) - only when the user can leave
                    if (_canLeave)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(context);
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 5,
                                offset: Offset(0, 5),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.chevron_left,
                            color: HestiaColors.primary,
                            size: 24,
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 44),
                    
                    // App Bar Title (Centered)
                    Expanded(
                      child: Center(
                        child: Text(
                           _isSearching
                               ? 'Finding professional...'
                               : _noProfessionalsFound
                                   ? 'No professionals found'
                                   : _fetchError
                                       ? 'Search Error'
                                       : 'Professional found',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    
                    // Spacer to balance back button
                    const SizedBox(width: 44),
                  ],
                ),
              ),

              // Main Content
              Expanded(
                child: _isSearching
                    ? _buildSearchingLayout()
                    : (_fetchError || _noProfessionalsFound)
                        ? _buildErrorLayout(isNetworkError: _fetchError)
                        : _buildFoundLayout(),
              ),

              // Sticky Bottom Book Now Button (only shown once matched, not on error)
              if (!_isSearching && !_fetchError && _matchedProfessional != null)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20.0, 8.0, 20.0, 20.0),
                    child: Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        color: HestiaColors.primary,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: HestiaColors.primary.withValues(alpha: 0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(28),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            final selectedProf =
                                _matchedProfessional ?? _professionals.first;
                            if (widget.paymentId != null) {
                              // Already paid in the cart — just confirm.
                              _confirmBooking(paymentId: widget.paymentId);
                            } else {
                              _startPayment(selectedProf);
                            }
                          },
                          child: Center(
                            child: Text(
                              widget.paymentId != null
                                  ? 'Confirm booking'
                                  : 'Continue',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
      ),
    );
  }

  ServiceDetail? _getDetail(String rawKey) {
    final key = rawKey
        .replaceAll('\n', '')
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .toLowerCase();
    if (key.contains('postdelivery')) {
      return ServiceDetailScreen.servicesData['post-delivery'];
    }
    if (key.contains('babysitting')) {
      return ServiceDetailScreen.servicesData['babysitting'];
    }
    if (key.contains('mobility')) {
      return ServiceDetailScreen.servicesData['mobility'];
    }
    if (key.contains('prepregnancy')) {
      return ServiceDetailScreen.servicesData['pre-pregnancy'];
    }
    if (key.contains('bathing') || key.contains('grooming')) {
      return ServiceDetailScreen.servicesData['bathing'];
    }
    if (key.contains('concierge') || key.contains('administrative')) {
      return ServiceDetailScreen.servicesData['concierge'];
    }
    return null;
  }

  int _getServiceRateForTitle(String serviceTitle) {
    final title = serviceTitle.toLowerCase();
    if (title.contains('post-delivery') || title.contains('postdelivery')) {
      return 499;
    }
    if (title.contains('babysitting')) return 399;
    if (title.contains('mobility')) return 449;
    if (title.contains('pre-pregnancy') || title.contains('prepregnancy')) {
      return 599;
    }
    if (title.contains('bathing')) return 349;
    if (title.contains('concierge')) return 299;
    return 499;
  }

  double _getDurationHours() {
    final String dur = widget.selectedDuration.toLowerCase();
    double hours = 0.0;

    final hrMatch = RegExp(r'(\d+)\s*hr').firstMatch(dur);
    if (hrMatch != null) {
      hours += double.parse(hrMatch.group(1)!);
    }

    final minMatch = RegExp(r'(\d+)\s*min').firstMatch(dur);
    if (minMatch != null) {
      hours += double.parse(minMatch.group(1)!) / 60.0;
    }

    if (hours == 0.0) {
      final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(dur);
      if (numMatch != null) {
        return double.parse(numMatch.group(1)!);
      }
      return 3.0;
    }
    return hours;
  }

  double _getCartItemTotal() {
    if (widget.servicesMap != null) {
      double total = 0;
      widget.servicesMap!.forEach((key, minutes) {
        final detail = _getDetail(key);
        if (detail != null) {
          final priceStr = detail.price.replaceAll('₹', '').trim();
          final hourlyPrice = double.tryParse(priceStr) ?? 0.0;
          total += hourlyPrice * (minutes / 60.0);
        } else {
          total += _getServiceRateForTitle(key) * (minutes / 60.0);
        }
      });
      return total;
    }

    return _getServiceRateForTitle(widget.serviceTitle).toDouble() *
        _getDurationHours();
  }

  String _bookingDurationLabel() {
    if (widget.servicesMap != null) {
      final totalMins =
          widget.servicesMap!.values.fold<int>(0, (sum, item) => sum + item);
      final double hours = totalMins / 60.0;
      return hours % 1 == 0
          ? '${hours.toInt()} hrs'
          : '${hours.toStringAsFixed(1)} hrs';
    }
    return widget.selectedDuration;
  }

  String _serviceNamesLabel() {
    if (widget.servicesMap != null) {
      return widget.servicesMap!.keys.join(', ');
    }
    return widget.serviceTitle;
  }

  void _startPayment(ProfessionalProfile professional) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: HestiaColors.primary),
      ),
    );

    final itemTotal = _getCartItemTotal();
    final finalPay = (itemTotal + itemTotal * 0.18).toInt();
    final serviceNames = _serviceNamesLabel();

    final options = {
      'key': RazorpayConfig.keyId,
      'amount': finalPay * 100,
      'name': 'Hestia',
      'description': 'Payment for $serviceNames Care Session',
      'timeout': 300,
      'prefill': {
        'name': _userName.isNotEmpty ? _userName : 'Guest User',
        'contact': _userPhone.isNotEmpty ? _userPhone : '9876543210',
        'email': _userEmail.isNotEmpty ? _userEmail : 'user@example.com',
      },
      'external': {
        'wallets': ['paytm'],
      },
    };

    try {
      Navigator.pop(context);
      _razorpay.open(options);
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open Razorpay checkout: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    await _confirmBooking(paymentId: response.paymentId);
  }

  /// Creates the booking record. Payment is assumed to be already completed
  /// (either via [widget.paymentId] from the cart, or via [paymentId] returned
  /// from a Razorpay checkout on this screen).
  Future<void> _confirmBooking({required String? paymentId}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: HestiaColors.primary),
      ),
    );

    try {
      final user = SupabaseService.currentUser;
      final itemTotal = _getCartItemTotal();
      final finalPay = widget.paidAmount ?? (itemTotal + itemTotal * 0.18).toInt();
      final professional =
          _matchedProfessional ??
          (_professionals.isNotEmpty ? _professionals.first : null);

      if (user != null && professional != null) {
        await SupabaseService.createBooking(
          userId: user.id,
          serviceTitle: _serviceNamesLabel(),
          selectedDate: widget.selectedDate,
          selectedTime: widget.selectedTime,
          selectedDuration: _bookingDurationLabel(),
          selectedProfessionalName: professional.name,
          repeatOption: widget.repeatOption,
          endsAfter: widget.endsAfter,
          preferSameProfessional: widget.preferSameProfessional,
          totalAmount: finalPay,
          paymentId: paymentId,
        );
      }

      if (mounted) {
        HapticFeedback.vibrate();
        Navigator.pop(context);
        _showBookingSuccessSheet(finalPay, professional?.name ?? 'Professional');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to confirm booking: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Payment failed: ${response.message ?? 'User cancelled payment'}',
        ),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  void _showBookingSuccessSheet(int total, String professionalName) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F5ED),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Color(0xFF2E6B4A),
                  size: 44,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Booking Confirmed!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: HestiaColors.textDark,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: HestiaColors.primary),
                ),
                child: Column(
                  children: [
                    _buildSummaryRow('Service', _serviceNamesLabel()),
                    const Divider(color: Color(0xFFE5DDD5), height: 16),
                    _buildSummaryRow('Date', _formatDate(widget.selectedDate)),
                    const Divider(color: Color(0xFFE5DDD5), height: 16),
                    _buildSummaryRow(
                      'Time',
                      '${widget.selectedTime} (${_bookingDurationLabel()})',
                    ),
                    const Divider(color: Color(0xFFE5DDD5), height: 16),
                    _buildSummaryRow('Caregiver', professionalName),
                    const Divider(color: Color(0xFFE5DDD5), height: 16),
                    _buildSummaryRow('Total Paid', '₹$total'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HestiaColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => const HomeScreen(),
                      ),
                      (route) => false,
                    );
                  },
                  child: const Text(
                    'Go to Home',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: HestiaColors.textMedium,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: HestiaColors.textDark,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchingLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          
          // Searching Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFAF2EB),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: HestiaColors.primary, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: HestiaColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'FINDING CAREGIVER',
                  style: TextStyle(
                    color: HestiaColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 28),

          // Searching Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: HestiaColors.primary,
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 10,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                const RadarPulseAnimation(color: HestiaColors.primary),
                const SizedBox(height: 36),
                const Text(
                  'Finding best professionals...',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: HestiaColors.textDark,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Searching available professionals in your zone for ${_formatDate(widget.selectedDate)} at ${widget.selectedTime}...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: HestiaColors.textMedium,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildErrorLayout({required bool isNetworkError}) {
    final badgeText = isNetworkError ? 'SEARCH ERROR' : 'NO PROFESSIONALS FOUND';
    final titleText = isNetworkError ? 'Search Failed' : 'No professionals found';
    final descText = isNetworkError
        ? 'A system or network error occurred while searching for professionals. Please check your internet connection and try again.'
        : 'We couldn\'t find any available professionals matching your service type, date, or time slot. Please try selecting a different date or time.';
    final mainIcon = isNetworkError ? Icons.error_outline_rounded : Icons.search_off_rounded;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFDE8E8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFB94A4A), width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isNetworkError ? Icons.error_outline_rounded : Icons.warning_amber_rounded, color: const Color(0xFFB94A4A), size: 16),
                const SizedBox(width: 8),
                Text(
                  badgeText,
                  style: const TextStyle(
                    color: Color(0xFFB94A4A),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFB94A4A), width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 10,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(mainIcon, size: 64, color: const Color(0xFFD4A5A5)),
                const SizedBox(height: 20),
                Text(
                  titleText,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: HestiaColors.textDark,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  descText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: HestiaColors.textMedium,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _isSearching = true;
                      _fetchError = false;
                      _noProfessionalsFound = false;
                      _matchedProfessional = null;
                      _professionals = [];
                    });
                    _fetchAndSearch();
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: HestiaColors.primary,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Center(
                      child: Text(
                        'Try Search Again',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
                if (!isNetworkError) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: HestiaColors.primary, width: 1.5),
                      ),
                      child: const Center(
                        child: Text(
                          'Modify Date & Time',
                          style: TextStyle(
                            color: HestiaColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildFoundLayout() {
    final prof = _matchedProfessional ?? _professionals.first;
    final role = _getRoleForProfessional(prof.name);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          
          // Matched Circle Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5ED),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2E6B4A), width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.check_circle, color: Color(0xFF2E6B4A), size: 18),
                SizedBox(width: 8),
                Text(
                  'MATCHED PROFESSIONAL',
                  style: TextStyle(
                    color: Color(0xFF2E6B4A),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 28),

          // Uber-style Driver Detail Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: HestiaColors.primary,
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 10,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                // Avatar circle
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: prof.avatarBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: HestiaColors.primary, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 5,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    prof.initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                Text(
                  prof.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: HestiaColors.textDark,
                  ),
                ),
                
                const SizedBox(height: 6),
                
                Text(
                  role,
                  style: const TextStyle(
                    fontSize: 14,
                    color: HestiaColors.textMedium,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                
                const SizedBox(height: 14),
                
                // Stars & Rating
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ...List.generate(
                      5,
                      (i) {
                        final double rVal = double.tryParse(prof.rating) ?? 0.0;
                        if (i < rVal.floor()) {
                          return const Icon(
                            Icons.star,
                            color: Color(0xFFDCA153),
                            size: 18,
                          );
                        } else if (i < rVal && rVal - i >= 0.25) {
                          return const Icon(
                            Icons.star_half,
                            color: Color(0xFFDCA153),
                            size: 18,
                          );
                        } else {
                          return const Icon(
                            Icons.star,
                            color: Color(0xFFE2E2E2),
                            size: 18,
                          );
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${prof.rating} (${prof.sessionsCount} ${prof.sessionsCount == 1 ? "session" : "sessions"})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: HestiaColors.textMedium,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                const Divider(color: HestiaColors.inputBorder, height: 1, thickness: 1.2),
                const SizedBox(height: 20),
                
                // Route info detail
                Row(
                  children: [
                    const Icon(
                      Icons.directions_car_filled_rounded,
                      color: HestiaColors.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'DISTANCE FROM YOU',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: HestiaColors.textLight,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${prof.distanceKm} km away in your zone',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: HestiaColors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Matched tags wrap
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: prof.tags.map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: tag == 'Verified'
                            ? const Color(0xFFE8F5ED)
                            : tag == 'Top rated'
                                ? const Color(0xFFF3EDFA)
                                : const Color(0xFFFAF2EB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: tag == 'Verified'
                              ? const Color(0xFF2E6B4A)
                              : tag == 'Top rated'
                                  ? const Color(0xFF6B4CA2)
                                  : const Color(0xFF8B5A2B),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// Custom radar pulse animation components
class RadarWavePainter extends CustomPainter {
  final double progress;
  final Color color;

  RadarWavePainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    // Draw 3 expanding pulsing rings
    for (int i = 0; i < 3; i++) {
      final ringProgress = (progress + i / 3.0) % 1.0;
      final radius = maxRadius * ringProgress;
      final opacity = (1.0 - ringProgress).clamp(0.0, 1.0);
      ringPaint.color = color.withValues(alpha: opacity * 0.35);
      canvas.drawCircle(center, radius, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant RadarWavePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class RadarPulseAnimation extends StatefulWidget {
  final Color color;
  const RadarPulseAnimation({super.key, this.color = HestiaColors.primary});

  @override
  State<RadarPulseAnimation> createState() => _RadarPulseAnimationState();
}

class _RadarPulseAnimationState extends State<RadarPulseAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  painter: RadarWavePainter(_controller.value, widget.color),
                  child: const SizedBox.expand(),
                );
              },
            ),
            
            // Central location searching icon
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: HestiaColors.primary,
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
                Icons.location_searching_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
