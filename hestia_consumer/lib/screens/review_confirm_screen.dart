import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../config/razorpay_config.dart';
import '../theme/colors.dart';
import '../services/supabase_service.dart';
import 'home_screen.dart';
import 'search_location_screen.dart';

class ReviewConfirmScreen extends StatefulWidget {
  final String serviceTitle;
  final DateTime selectedDate;
  final String selectedTime;
  final String selectedDuration;
  final String selectedProfessionalName;
  final String repeatOption;
  final String endsAfter;
  final bool preferSameProfessional;

  const ReviewConfirmScreen({
    super.key,
    required this.serviceTitle,
    required this.selectedDate,
    required this.selectedTime,
    required this.selectedDuration,
    required this.selectedProfessionalName,
    required this.repeatOption,
    required this.endsAfter,
    required this.preferSameProfessional,
  });

  @override
  State<ReviewConfirmScreen> createState() => _ReviewConfirmScreenState();
}

class _ReviewConfirmScreenState extends State<ReviewConfirmScreen> {
  bool _isLoadingProfile = true;
  String _address = 'B-402, Koramangala';
  String _patientName = 'Aryan (Newborn)';
  String _userName = '';
  String _userEmail = '';
  String _userPhone = '';
  late Razorpay _razorpay;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    // Hide the loader dialog if it is showing
    Navigator.pop(context);

    // Show a new persistent loader for supabase booking confirmation
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: HestiaColors.primary),
      ),
    );

    try {
      final user = SupabaseService.currentUser;
      final hourlyRate = _getServiceRate();
      final durationHours = _getDurationHours();
      final firstSessionTotal = (hourlyRate * durationHours).toInt();
      
      if (user != null) {
        await SupabaseService.createBooking(
          userId: user.id,
          serviceTitle: widget.serviceTitle,
          selectedDate: widget.selectedDate,
          selectedTime: widget.selectedTime,
          selectedDuration: widget.selectedDuration,
          selectedProfessionalName: widget.selectedProfessionalName,
          repeatOption: widget.repeatOption,
          endsAfter: widget.endsAfter,
          preferSameProfessional: widget.preferSameProfessional,
          totalAmount: firstSessionTotal,
          paymentId: response.paymentId,
        );
      }
      if (mounted) {
        Navigator.pop(context); // Pop the loader
        _showBookingSuccessSheet(context, firstSessionTotal);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Pop the loader
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
    // Hide the loader dialog
    Navigator.pop(context);
    
    // Show a premium design-aligned failure message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Payment Failed: ${response.message ?? "User cancelled payment"}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('External wallet selected: ${response.walletName}');
  }

  Future<void> _loadProfileData() async {
    final user = SupabaseService.currentUser;
    if (user != null) {
      _userEmail = user.email ?? '';
      _userPhone = user.phone ?? '';
      try {
        final profile = await SupabaseService.getUserProfile(user.id);
        if (profile != null) {
          setState(() {
            _userName = profile['name'] ?? '';
            if (profile['email'] != null && (profile['email'] as String).isNotEmpty) {
              _userEmail = profile['email'];
            }
            if (profile['phone'] != null && (profile['phone'] as String).isNotEmpty) {
              _userPhone = profile['phone'];
            }
            
            // Load address if available
            if (profile['address'] != null) {
              final street = profile['address']['street'] ?? '';
              final city = profile['address']['city'] ?? '';
              if (street.isNotEmpty || city.isNotEmpty) {
                _address = street.isNotEmpty ? '$street, $city' : city;
              }
            }
            // Load first household member under care
            final members = profile['household_members'] as List<dynamic>?;
            if (members != null && members.isNotEmpty) {
              final firstMember = members.first;
              final name = firstMember['name'] ?? '';
              final role = firstMember['role'] ?? '';
              if (name.isNotEmpty) {
                _patientName = role.isNotEmpty ? '$name ($role)' : name;
              }
            }
          });
        } else {
          // Fallback to legacy profile json
          final data = await SupabaseService.downloadProfileJson(user.id);
          if (data != null) {
            setState(() {
              _userName = data['full_name'] ?? data['name'] ?? '';
              // Load address if available
              if (data['address'] != null) {
                final street = data['address']['street'] ?? '';
                final city = data['address']['city'] ?? '';
                if (street.isNotEmpty || city.isNotEmpty) {
                  _address = street.isNotEmpty ? '$street, $city' : city;
                }
              }
              // Load first household member under care
              final members = data['household_members'] as List<dynamic>?;
              if (members != null && members.isNotEmpty) {
                final firstMember = members.first;
                final name = firstMember['name'] ?? '';
                final role = firstMember['role'] ?? '';
                if (name.isNotEmpty) {
                  _patientName = role.isNotEmpty ? '$name ($role)' : name;
                }
              }
            });
          }
        }
      } catch (e) {
        debugPrint('Error loading profile details in ReviewConfirmScreen: $e');
      }
    }
    setState(() {
      _isLoadingProfile = false;
    });
  }

  // Get service hourly rate based on title
  int _getServiceRate() {
    final title = widget.serviceTitle.toLowerCase();
    if (title.contains('post-delivery') || title.contains('postdelivery')) return 499;
    if (title.contains('babysitting')) return 399;
    if (title.contains('mobility')) return 449;
    if (title.contains('pre-pregnancy') || title.contains('prepregnancy')) return 599;
    if (title.contains('bathing')) return 349;
    if (title.contains('concierge')) return 299;
    return 499; // Fallback
  }

  // Parse hours from duration string (e.g. "3 hrs 30 mins" -> 3.5)
  double _getDurationHours() {
    final String dur = widget.selectedDuration.toLowerCase();
    double hours = 0.0;
    
    // Check if it contains hours
    final hrMatch = RegExp(r'(\d+)\s*hr').firstMatch(dur);
    if (hrMatch != null) {
      hours += double.parse(hrMatch.group(1)!);
    }
    
    // Check if it contains mins
    final minMatch = RegExp(r'(\d+)\s*min').firstMatch(dur);
    if (minMatch != null) {
      hours += double.parse(minMatch.group(1)!) / 60.0;
    }
    
    if (hours == 0.0) {
      // Fallback: search for first number (integer or float)
      final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(dur);
      if (numMatch != null) {
        return double.parse(numMatch.group(1)!);
      }
      return 3.0; // Default fallback
    }
    return hours;
  }

  // Format date helper: "Fri, Jun 12"
  String _formatDate(DateTime date) {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    final weekdayStr = weekdays[date.weekday - 1];
    final monthStr = months[date.month - 1];
    return '$weekdayStr, $monthStr ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final hourlyRate = _getServiceRate();
    final durationHours = _getDurationHours();
    final firstSessionTotal = (hourlyRate * durationHours).toInt();
    
    final formattedDate = _formatDate(widget.selectedDate);
    final repeatLabel = widget.repeatOption == 'One-time' 
        ? 'None' 
        : '${widget.repeatOption} · ${widget.endsAfter}';

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 252, 252, 252),
      body: Container(
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
        child: SafeArea(
          child: _isLoadingProfile
              ? const Center(
                  child: CircularProgressIndicator(color: HestiaColors.primary),
                )
              : Column(
                  children: [
                    // Custom App Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      child: Row(
                        children: [
                          // Back Button (Circular)
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
                          ),
                          
                          // App Bar Title (Centered)
                          Expanded(
                            child: Center(
                              child: const Text(
                                'Review & confirm',
                                style: TextStyle(
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
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 12),

                          // Summary Box Container
                          Container(
                            padding: const EdgeInsets.all(20.0),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: HestiaColors.primary,
                                width: 1,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x14000000),
                                  blurRadius: 5,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                _buildSummaryItem('Service', widget.serviceTitle),
                                Divider(color: HestiaColors.inputBorder.withValues(alpha: 0.3), height: 32, thickness: 1.2),
                                _buildSummaryItem('For', _patientName),
                                Divider(color: HestiaColors.inputBorder.withValues(alpha: 0.3), height: 32, thickness: 1.2),
                                _buildSummaryItem('Date', '$formattedDate · ${widget.selectedTime}'),
                                Divider(color: HestiaColors.inputBorder.withValues(alpha: 0.3), height: 32, thickness: 1.2),
                                _buildSummaryItem(
                                  'Duration',
                                  durationHours % 1 == 0
                                      ? '${durationHours.toInt()} hours'
                                      : '$durationHours hours',
                                ),
                                Divider(color: HestiaColors.inputBorder.withValues(alpha: 0.3), height: 32, thickness: 1.2),
                                _buildSummaryItem('Professional', widget.selectedProfessionalName),
                                Divider(color: HestiaColors.inputBorder.withValues(alpha: 0.3), height: 32, thickness: 1.2),
                                _buildSummaryItem('Repeat', repeatLabel),
                                Divider(color: HestiaColors.inputBorder.withValues(alpha: 0.3), height: 32, thickness: 1.2),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) => const SearchLocationScreen(),
                                      ),
                                    ).then((_) => _loadProfileData());
                                  },
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _buildSummaryItem('Address', _address),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.chevron_right,
                                        color: HestiaColors.primary,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Pricing Card Container
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: HestiaColors.primary,
                                width: 1,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x14000000),
                                  blurRadius: 5,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'First session total',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: HestiaColors.textMedium,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '₹$hourlyRate × ${durationHours % 1 == 0 ? durationHours.toInt() : durationHours} hrs',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: HestiaColors.textLight,
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '₹${firstSessionTotal.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: HestiaColors.textDark,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'payable now',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: HestiaColors.textLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Security Alert Callout Container
                          Container(
                            padding: const EdgeInsets.all(16.0),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: HestiaColors.primary,
                                width: 1,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x14000000),
                                  blurRadius: 5,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.lock_outline,
                                  color: HestiaColors.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Pay securely now via Razorpay. Cancel free and get a full refund up to 2 hrs before.',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF1E1E1E),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),

                  // Sticky Confirm Booking Button
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
                              final hourlyRate = _getServiceRate();
                              final durationHours = _getDurationHours();
                              final firstSessionTotal = (hourlyRate * durationHours).toInt();

                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (ctx) => const Center(
                                  child: CircularProgressIndicator(color: HestiaColors.primary),
                                ),
                              );

                              final options = {
                                'key': RazorpayConfig.keyId,
                                'amount': firstSessionTotal * 100, // in paise
                                'name': 'Hestia',
                                'description': 'Payment for ${widget.serviceTitle} Care Session',
                                'timeout': 300, // 5 minutes
                                'prefill': {
                                  'name': _userName.isNotEmpty ? _userName : 'Guest User',
                                  'contact': _userPhone.isNotEmpty ? _userPhone : '9876543210',
                                  'email': _userEmail.isNotEmpty ? _userEmail : 'user@example.com',
                                },
                                'external': {
                                  'wallets': ['paytm']
                                }
                              };

                              try {
                                _razorpay.open(options);
                              } catch (e) {
                                Navigator.pop(context); // dismiss loader
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Could not open Razorpay checkout: $e'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            },
                            child: const Center(
                              child: Text(
                                'Confirm booking',
                                style: TextStyle(
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
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: HestiaColors.textLight,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 14,
              color: HestiaColors.textDark,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  void _showBookingSuccessSheet(BuildContext context, int total) {
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
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              
              // Success Circle
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
              const SizedBox(height: 20),
              
              const Text(
                'Booking Confirmed!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: HestiaColors.textDark,
                ),
              ),
              const SizedBox(height: 16),
              
              // Summary details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: HestiaColors.primary,
                    width: 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 5,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildSummaryRow('Service', widget.serviceTitle),
                    const Divider(color: Color(0xFFE5DDD5), height: 16),
                    _buildSummaryRow('Date', _formatDate(widget.selectedDate)),
                    const Divider(color: Color(0xFFE5DDD5), height: 16),
                    _buildSummaryRow('Time', '${widget.selectedTime} (${widget.selectedDuration})'),
                    const Divider(color: Color(0xFFE5DDD5), height: 16),
                    _buildSummaryRow('Caregiver', widget.selectedProfessionalName),
                    const Divider(color: Color(0xFFE5DDD5), height: 16),
                    _buildSummaryRow('Total Paid (Razorpay)', '₹$total'),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              
              // Go to home button
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
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => const HomeScreen()),
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
              const SizedBox(height: 12),
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
        Text(
          value,
          style: const TextStyle(
            color: HestiaColors.textDark,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
