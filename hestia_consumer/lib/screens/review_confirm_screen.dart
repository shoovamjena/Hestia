import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../config/razorpay_config.dart';
import '../theme/colors.dart';
import '../services/supabase_service.dart';
import 'home_screen.dart';
import 'search_location_screen.dart';
import 'service_detail_screen.dart';

class ReviewConfirmScreen extends StatefulWidget {
  final String serviceTitle;
  final DateTime selectedDate;
  final String selectedTime;
  final String selectedDuration;
  final String selectedProfessionalName;
  final String repeatOption;
  final String endsAfter;
  final bool preferSameProfessional;
  final Map<String, int>? servicesMap;

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
    this.servicesMap,
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
  List<Map<String, dynamic>> _allMembers = [];
  String? _selectedMemberId;
  late Razorpay _razorpay;
  final TextEditingController _careNotesController = TextEditingController();

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
    _careNotesController.dispose();
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
      final itemTotal = _getCartItemTotal();
      final gstFees = itemTotal * 0.18;
      final finalPay = (itemTotal + gstFees).toInt();
      
      if (user != null) {
        final String bookingServiceTitle = widget.servicesMap != null
            ? widget.servicesMap!.keys.join(', ')
            : widget.serviceTitle;
            
        String bookingDuration = widget.selectedDuration;
        if (widget.servicesMap != null) {
          final totalMins = widget.servicesMap!.values.fold<int>(0, (sum, item) => sum + item);
          final double hours = totalMins / 60.0;
          bookingDuration = hours % 1 == 0 ? '${hours.toInt()} hrs' : '${hours.toStringAsFixed(1)} hrs';
        }

        await SupabaseService.createBooking(
          userId: user.id,
          serviceTitle: bookingServiceTitle,
          selectedDate: widget.selectedDate,
          selectedTime: widget.selectedTime,
          selectedDuration: bookingDuration,
          selectedProfessionalName: widget.selectedProfessionalName,
          repeatOption: widget.repeatOption,
          endsAfter: widget.endsAfter,
          preferSameProfessional: widget.preferSameProfessional,
          totalAmount: finalPay,
          paymentId: response.paymentId,
          householdMemberId: _selectedMemberId,
          careNotes: _careNotesController.text.trim().isNotEmpty 
              ? _careNotesController.text.trim() 
              : null,
        );
      }
      if (mounted) {
        HapticFeedback.vibrate();
        Navigator.pop(context); // Pop the loader
        _showBookingSuccessSheet(context, finalPay);
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

  List<Map<String, dynamic>> _getEligibleMembers() {
    return _allMembers;
  }

  Future<void> _loadProfileData() async {
    final user = SupabaseService.currentUser;
    if (user != null) {
      _userEmail = SupabaseService.currentUserEmail;
      _userPhone = SupabaseService.currentUserPhone;
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
            // Load household members under care
            if (profile['household_members'] != null) {
              _allMembers = List<Map<String, dynamic>>.from(profile['household_members']);
              final eligible = _getEligibleMembers();
              if (eligible.isNotEmpty) {
                final firstMember = eligible.first;
                final name = firstMember['name'] ?? '';
                final role = firstMember['role'] ?? '';
                _patientName = role.isNotEmpty ? '$name ($role)' : name;
                _selectedMemberId = firstMember['id'] as String?;
              } else {
                _patientName = 'Tap to select';
                _selectedMemberId = null;
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
              // Load household members under care
              if (data['household_members'] != null) {
                _allMembers = List<Map<String, dynamic>>.from(data['household_members']);
                final eligible = _getEligibleMembers();
                if (eligible.isNotEmpty) {
                  final firstMember = eligible.first;
                  final name = firstMember['name'] ?? '';
                  final role = firstMember['role'] ?? '';
                  _patientName = role.isNotEmpty ? '$name ($role)' : name;
                  _selectedMemberId = firstMember['id'] as String?;
                } else {
                  _patientName = 'Tap to select';
                  _selectedMemberId = null;
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

  ServiceDetail? _getDetail(String rawKey) {
    final key = rawKey.replaceAll('\n', '').replaceAll(' ', '').replaceAll('-', '').toLowerCase();
    if (key.contains('postdelivery')) return ServiceDetailScreen.servicesData['post-delivery'];
    if (key.contains('babysitting')) return ServiceDetailScreen.servicesData['babysitting'];
    if (key.contains('mobility')) return ServiceDetailScreen.servicesData['mobility'];
    if (key.contains('prepregnancy')) return ServiceDetailScreen.servicesData['pre-pregnancy'];
    if (key.contains('bathing')) return ServiceDetailScreen.servicesData['bathing'];
    if (key.contains('concierge')) return ServiceDetailScreen.servicesData['concierge'];
    return null;
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
          final hourlyPrice = _getServiceRateForTitle(key).toDouble();
          total += hourlyPrice * (minutes / 60.0);
        }
      });
      return total;
    } else {
      final hourlyRate = _getServiceRateForTitle(widget.serviceTitle).toDouble();
      final durationHours = _getDurationHours();
      return hourlyRate * durationHours;
    }
  }

  int _getServiceRateForTitle(String serviceTitle) {
    final title = serviceTitle.toLowerCase();
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
    final hourlyRate = _getServiceRateForTitle(widget.serviceTitle);
    final durationHours = _getDurationHours();
    
    // Dynamic values based on servicesMap
    final String serviceNames = widget.servicesMap != null
        ? widget.servicesMap!.keys.join(', ')
        : widget.serviceTitle;

    final double combinedHours;
    if (widget.servicesMap != null) {
      final totalMins = widget.servicesMap!.values.fold<int>(0, (sum, item) => sum + item);
      combinedHours = totalMins / 60.0;
    } else {
      combinedHours = durationHours;
    }

    final double itemTotal = _getCartItemTotal();
    final double gstFees = itemTotal * 0.18;
    final double grandTotal = itemTotal + gstFees;
    final int firstSessionTotal = grandTotal.toInt();
    
    final formattedDate = _formatDate(widget.selectedDate);
    final repeatLabel = widget.repeatOption == 'One-time' 
        ? 'None' 
        : '${widget.repeatOption} · ${widget.endsAfter}';

    final String durationLabel = combinedHours % 1 == 0
        ? '${combinedHours.toInt()} hours'
        : '${combinedHours.toStringAsFixed(1)} hours';

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
                                _buildSummaryItem('Service', serviceNames),
                                Divider(color: HestiaColors.inputBorder.withValues(alpha: 0.3), height: 32, thickness: 1.2),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      _showHouseholdMembersBottomSheet(context);
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              children: [
                                                SizedBox(
                                                  width: 100,
                                                  child: const Text(
                                                    'For',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: HestiaColors.textLight,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    _patientName,
                                                    textAlign: TextAlign.end,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: _patientName == 'Tap to select'
                                                          ? HestiaColors.primary
                                                          : HestiaColors.textDark,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: HestiaColors.primary.withValues(alpha: 0.08),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.chevron_right_rounded,
                                              color: HestiaColors.primary,
                                              size: 20,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Divider(color: HestiaColors.inputBorder.withValues(alpha: 0.3), height: 32, thickness: 1.2),
                                _buildSummaryItem('Date', '$formattedDate · ${widget.selectedTime}'),
                                Divider(color: HestiaColors.inputBorder.withValues(alpha: 0.3), height: 32, thickness: 1.2),
                                _buildSummaryItem('Duration', durationLabel),
                                Divider(color: HestiaColors.inputBorder.withValues(alpha: 0.3), height: 32, thickness: 1.2),
                                _buildSummaryItem('Professional', widget.selectedProfessionalName),
                                Divider(color: HestiaColors.inputBorder.withValues(alpha: 0.3), height: 32, thickness: 1.2),
                                _buildSummaryItem('Repeat', repeatLabel),
                                Divider(color: HestiaColors.inputBorder.withValues(alpha: 0.3), height: 32, thickness: 1.2),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => const SearchLocationScreen(),
                                        ),
                                      ).then((_) => _loadProfileData());
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              children: [
                                                SizedBox(
                                                  width: 100,
                                                  child: const Text(
                                                    'Address',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: HestiaColors.textLight,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    _address,
                                                    textAlign: TextAlign.end,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      color: HestiaColors.textDark,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: HestiaColors.primary.withValues(alpha: 0.08),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.chevron_right_rounded,
                                              color: HestiaColors.primary,
                                              size: 20,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Care Notes Card Container
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.note_alt_outlined,
                                      color: HestiaColors.primary,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Add Care Notes (Optional)',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: HestiaColors.textDark,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _careNotesController,
                                  maxLines: 3,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: HestiaColors.textDark,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'e.g., Baby needs feeding every 2 hours. Keep bedroom temperature at 24°C.',
                                    hintStyle: const TextStyle(
                                      fontSize: 13,
                                      color: HestiaColors.textLight,
                                    ),
                                    contentPadding: const EdgeInsets.all(12),
                                    filled: true,
                                    fillColor: const Color(0xFFFBFBFB),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: HestiaColors.inputBorder,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: HestiaColors.primary,
                                        width: 1.5,
                                      ),
                                    ),
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
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Item total',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: HestiaColors.textMedium,
                                      ),
                                    ),
                                    Text(
                                      '₹${itemTotal.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: HestiaColors.textDark,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'GST & Service Fees (18%)',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: HestiaColors.textMedium,
                                      ),
                                    ),
                                    Text(
                                      '₹${gstFees.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: HestiaColors.textDark,
                                      ),
                                    ),
                                  ],
                                ),
                                Divider(color: HestiaColors.inputBorder.withValues(alpha: 0.3), height: 24, thickness: 1),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'To pay',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: HestiaColors.textDark,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          widget.servicesMap != null
                                              ? '${widget.servicesMap!.length} services included'
                                              : '₹$hourlyRate × ${durationHours % 1 == 0 ? durationHours.toInt() : durationHours} hrs',
                                          style: const TextStyle(
                                            fontSize: 11,
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
                              HapticFeedback.lightImpact();
                              final bool hasRecipient = _patientName.isNotEmpty && _patientName != 'Tap to select';
                              if (!hasRecipient) {
                                _showHouseholdMembersBottomSheet(context);
                              } else {
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
                                  'description': 'Payment for $serviceNames Care Session',
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
                              }
                            },
                            child: Center(
                              child: const Text(
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
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24.0, 12.0, 24.0, 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                
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
                      _buildSummaryRow(
                        'Service',
                        widget.servicesMap != null
                            ? widget.servicesMap!.keys.join(', ')
                            : widget.serviceTitle,
                      ),
                      const Divider(color: Color(0xFFE5DDD5), height: 16),
                      _buildSummaryRow('Date', _formatDate(widget.selectedDate)),
                      const Divider(color: Color(0xFFE5DDD5), height: 16),
                      _buildSummaryRow(
                        'Time',
                        widget.servicesMap != null
                            ? () {
                                final totalMins = widget.servicesMap!.values.fold<int>(0, (sum, item) => sum + item);
                                final double hours = totalMins / 60.0;
                                final dur = hours % 1 == 0 ? '${hours.toInt()} hrs' : '${hours.toStringAsFixed(1)} hrs';
                                return '${widget.selectedTime} ($dur)';
                              }()
                            : '${widget.selectedTime} (${widget.selectedDuration})',
                      ),
                      const Divider(color: Color(0xFFE5DDD5), height: 16),
                      _buildSummaryRow('Caregiver', widget.selectedProfessionalName),
                      const Divider(color: Color(0xFFE5DDD5), height: 16),
                      _buildSummaryRow('Total Paid (Razorpay)', '₹$total'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
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
                      HapticFeedback.lightImpact();
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
                const SizedBox(height: 8),
              ],
            ),
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

  void _showHouseholdMembersBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final eligible = _getEligibleMembers();
            final serviceName = widget.serviceTitle;
            
            return Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Select Recipient of Care',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: HestiaColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Select who will receive the $serviceName service.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: HestiaColors.textMedium,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (eligible.isEmpty) ...[
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24.0),
                        child: Column(
                          children: [
                            Icon(Icons.people_outline_rounded, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'No eligible household members found',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: HestiaColors.textMedium,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              serviceName.toLowerCase().contains('post-delivery') || serviceName.toLowerCase().contains('postdelivery')
                                  ? 'Post-delivery care requires children under 6 months old.'
                                  : 'No household members match the requirements for this service.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.4,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: eligible.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final member = eligible[index];
                          final name = member['name'] ?? '';
                          final role = member['role'] ?? member['relationship'] ?? '';
                          final age = member['age'] ?? 0;
                          
                          String emoji = '👶';
                          Color accentColor = const Color(0xFFFFE6CC);
                          if (age > 2 && age <= 12) {
                            emoji = '🧒';
                            accentColor = const Color(0xFFE1F5FE);
                          } else if (age > 12 && age <= 59) {
                            emoji = '🧑';
                            accentColor = const Color(0xFFFCE4EC);
                          } else if (age >= 60) {
                            emoji = '👵';
                            accentColor = const Color(0xFFE4F1D8);
                          }

                          final isSelected = _selectedMemberId == member['id'];

                          return InkWell(
                            onTap: () {
                              setState(() {
                                _patientName = role.isNotEmpty ? '$name ($role)' : name;
                                _selectedMemberId = member['id'] as String?;
                              });
                              Navigator.pop(sheetCtx);
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isSelected ? HestiaColors.primary.withValues(alpha: 0.05) : const Color(0xFFF8F3EE),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected ? HestiaColors.primary : const Color(0xFFF0E4D9),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: accentColor,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: HestiaColors.textDark,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$role · ${age > 0 ? "$age yrs" : "Newborn"}',
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            color: HestiaColors.textMedium,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      Icons.check_circle,
                                      color: HestiaColors.primary,
                                      size: 24,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: HestiaColors.primary, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _showAddMemberDialog(sheetCtx, setSheetState);
                      },
                      icon: const Icon(Icons.add, color: HestiaColors.primary),
                      label: const Text(
                        'Add household member',
                        style: TextStyle(
                          color: HestiaColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAddMemberDialog(BuildContext sheetContext, StateSetter setSheetState) {
    final nameController = TextEditingController();
    final ageController = TextEditingController();
    String? selectedRole = 'Post-Delivery Care';
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: sheetContext,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'Add Household Member',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: HestiaColors.textDark,
                ),
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MEMBER NAME',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: HestiaColors.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: nameController,
                        decoration: InputDecoration(
                          hintText: 'e.g. Meera',
                          filled: true,
                          fillColor: const Color(0xFFF7F9FC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'AGE (YEARS)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: HestiaColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Enter age. For babies under 1 year, enter 0.',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: HestiaColors.textLight,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: ageController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'e.g. 0 for newborn, 4 for child',
                          filled: true,
                          fillColor: const Color(0xFFF7F9FC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter age';
                          }
                          final age = int.tryParse(value);
                          if (age == null || age < 0) {
                            return 'Please enter a valid age';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'SERVICE PREFERRED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: HestiaColors.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedRole,
                        hint: const Text('Select service preferred'),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFFF7F9FC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        items: [
                          'Post-Delivery Care',
                          'Mobility Support',
                          'Elder Care',
                          'Babysitting',
                          'Other',
                        ].map((val) => DropdownMenuItem(
                          value: val,
                          child: Text(val),
                        )).toList(),
                        onChanged: (val) {
                          setDialogState(() {
                            selectedRole = val;
                          });
                        },
                        validator: (val) => val == null ? 'Select service preferred' : null,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel', style: TextStyle(color: HestiaColors.textMedium)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HestiaColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      final age = int.parse(ageController.text);
                      final name = nameController.text.trim();
                      final role = selectedRole ?? 'Other';
                      
                      // Pop add member dialog immediately
                      Navigator.pop(dialogCtx);
                      
                      // Show loading spinner on sheet
                      showDialog(
                        context: sheetContext,
                        barrierDismissible: false,
                        builder: (ctx) => const Center(
                          child: CircularProgressIndicator(color: HestiaColors.primary),
                        ),
                      );

                      try {
                        final user = SupabaseService.currentUser;
                        if (user != null) {
                          final dob = DateTime.now().subtract(Duration(days: age * 365)).toIso8601String().substring(0, 10);
                          
                          // 1. Insert into Supabase household_members table
                          final newMemberRes = await SupabaseService.client.from('household_members').insert({
                            'user_id': user.id,
                            'name': name,
                            'relationship': role,
                            'date_of_birth': dob,
                            'primary_service_need': SupabaseService.mapReasonToServicePillar(role),
                          }).select('id, name, relationship, date_of_birth').single();

                          final addedMember = {
                            'id': newMemberRes['id'],
                            'name': newMemberRes['name'],
                            'role': newMemberRes['relationship'],
                            'age': age,
                            'dob': newMemberRes['date_of_birth'],
                          };

                          // Update local states
                          setState(() {
                            _allMembers.add(addedMember);
                            _patientName = role.isNotEmpty ? '$name ($role)' : name;
                            _selectedMemberId = newMemberRes['id'] as String?;
                          });

                          setSheetState(() {
                            // Refresh bottom sheet list
                          });
                          
                          // Update legacy profile JSON
                          try {
                            final profileData = await SupabaseService.downloadProfileJson(user.id) ?? {};
                            final existingMembers = List<dynamic>.from(profileData['household_members'] ?? []);
                            existingMembers.add({
                              'name': name,
                              'role': role,
                              'age': age,
                            });
                            profileData['household_members'] = existingMembers;
                            await SupabaseService.uploadProfileJson(id: user.id, profileData: profileData);
                          } catch (e) {
                            debugPrint('Failed to update legacy JSON: $e');
                          }
                        }
                      } catch (e) {
                        debugPrint('Error inserting household member: $e');
                        if (sheetContext.mounted) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(content: Text('Failed to add member: $e')),
                          );
                        }
                      } finally {
                        // Pop loading spinner
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      }
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
