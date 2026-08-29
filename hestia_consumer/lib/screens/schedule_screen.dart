import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../config/razorpay_config.dart';
import '../theme/colors.dart';
import '../services/supabase_service.dart';
import '../services/booking_flow_service.dart';
import '../utils/active_booking_navigation.dart';
import '../utils/string_format.dart';
import 'booking_scheduled_screen.dart';
import 'repeat_booking_screen.dart';
import 'search_location_screen.dart';
import 'service_detail_screen.dart';
import 'time_slot_bottom_sheet.dart';

class ScheduleScreen extends StatefulWidget {
  final String serviceTitle;
  final Map<String, int>? initialServicesMap;
  final ValueChanged<Map<String, int>>? onServicesChanged;
  final DateTime? initialDate;
  final String? initialTimeSlot;

  const ScheduleScreen({
    super.key,
    required this.serviceTitle,
    this.initialServicesMap,
    this.onServicesChanged,
    this.initialDate,
    this.initialTimeSlot,
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late Map<String, int> _servicesMap;
  String _activeTab = 'Scheduled'; // Tabs: 'Instant', 'Scheduled', 'Recurring'
  bool _isBillExpanded = true;
  DateTime? _scheduledDate;
  String? _scheduledTimeSlot;

  // Address and contact state
  String _addressText = '89, Usuw, Pocket 25, Pocket 25, Bharat singh, Pista, New Delhi, Delhi, India, 110085';
  String _phone = '+91 8144684265';
  String _userName = 'Soumya';
  String _userEmail = '';
  bool _isLoadingAddress = false;

  String _repeatOption = 'Once';
  String _endsAfter = '1 session';
  bool _preferSameProfessional = false;
  bool _donateToNgo = false;
  int _donationAmount = 0;
  int? _selectedDonationPreset;
  final TextEditingController _donationController = TextEditingController();

  static const List<int> _donationPresets = [25, 50, 100];

  late Razorpay _razorpay;

  @override
  void initState() {
    super.initState();
    // Initialize services map. If null, create a map with the single item.
    if (widget.initialServicesMap != null) {
      _servicesMap = Map<String, int>.from(widget.initialServicesMap!);
    } else {
      _servicesMap = {widget.serviceTitle: 30};
    }
    _scheduledDate = widget.initialDate;
    _scheduledTimeSlot = widget.initialTimeSlot;
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _loadAddress();
  }

  @override
  void dispose() {
    _donationController.dispose();
    _razorpay.clear();
    super.dispose();
  }

  int _getDonationAmount() {
    if (!_donateToNgo) return 0;
    final parsed = int.tryParse(_donationController.text.trim());
    if (parsed != null && parsed > 0) return parsed;
    return _donationAmount > 0 ? _donationAmount : 0;
  }

  void _setDonationAmount(int amount) {
    setState(() {
      _donationAmount = amount;
      _selectedDonationPreset =
          _donationPresets.contains(amount) ? amount : null;
      _donationController.text = amount > 0 ? amount.toString() : '';
    });
  }

  bool _validateDonationBeforePay() {
    if (!_donateToNgo) return true;
    if (_getDonationAmount() > 0) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Enter a donation amount or uncheck NGO donation'),
        backgroundColor: Colors.redAccent,
      ),
    );
    return false;
  }

  double _calculateFinalPay(double itemTotal, double gstFees) {
    return itemTotal + gstFees + _getDonationAmount();
  }

  bool get _isInstantTab => _activeTab == 'Instant';

  /// Instant bookings start ASAP — no slot picker.
  void _applyInstantScheduleNow() {
    final now = DateTime.now();
    _scheduledDate = DateTime(now.year, now.month, now.day);
    _scheduledTimeSlot = formatBookingTimeLabel(now);
    _repeatOption = 'Once';
  }

  void _proceedToPay() {
    if (!_validateDonationBeforePay()) return;

    if (_isInstantTab) {
      _applyInstantScheduleNow();
    } else if (_scheduledDate == null || _scheduledTimeSlot == null) {
      _openTimeSlotBottomSheet(context);
      return;
    }

    final itemTotal = _getItemTotal();
    final gstFees = itemTotal * 0.18;
    final donation = _getDonationAmount();
    final finalPay = _calculateFinalPay(itemTotal, gstFees).toInt();
    final serviceNames = _servicesMap.keys.join(', ');
    final authEmail = SupabaseService.currentUserEmail;

    final options = {
      'key': RazorpayConfig.keyId,
      'amount': finalPay * 100,
      'name': 'Hestia',
      'description': donation > 0
          ? 'Payment for $serviceNames + NGO donation'
          : _isInstantTab
              ? 'Instant booking for $serviceNames'
              : 'Payment for $serviceNames Care Session',
      'timeout': 300,
      'prefill': {
        'name': _userName.isNotEmpty ? _userName : 'Guest User',
        'contact': _phone.isNotEmpty ? _phone : '9876543210',
        'email': _userEmail.isNotEmpty
            ? _userEmail
            : (authEmail.isNotEmpty ? authEmail : 'user@example.com'),
      },
      'external': {
        'wallets': ['paytm'],
      },
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open Razorpay checkout: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _openRepeatBooking() async {
    final firstService =
        _servicesMap.keys.isNotEmpty ? _servicesMap.keys.first : widget.serviceTitle;
    final matchedTitle = _getDetail(firstService)?.title ?? widget.serviceTitle;

    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => RepeatBookingScreen(
          serviceTitle: matchedTitle,
          selectedDate: _scheduledDate ?? DateTime.now(),
          selectedTime: _scheduledTimeSlot,
          selectedDuration: _getSelectedDurationLabel(),
        ),
      ),
    );

    if (!mounted || result == null) return;

    setState(() {
      _scheduledDate = result['date'] as DateTime? ?? _scheduledDate;
      _scheduledTimeSlot = result['time'] as String? ?? _scheduledTimeSlot;
      _repeatOption = result['frequency'] as String? ?? 'Everyday';
      _endsAfter = result['endsAfter'] as String? ?? _endsAfter;
      _preferSameProfessional = true;
      _activeTab = 'Scheduled';
    });

    if (_scheduledDate != null && _scheduledTimeSlot != null) {
      _proceedToPay();
    }
  }

  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;

    final wasInstant = _isInstantTab;
    if (wasInstant) {
      _applyInstantScheduleNow();
    }
    if (_scheduledDate == null || _scheduledTimeSlot == null) return;

    final firstService =
        _servicesMap.keys.isNotEmpty ? _servicesMap.keys.first : widget.serviceTitle;
    final matchedTitle = _getDetail(firstService)?.title ?? widget.serviceTitle;
    final itemTotal = _getItemTotal();
    final gstFees = itemTotal * 0.18;
    final donation = _getDonationAmount();
    final finalPay = _calculateFinalPay(itemTotal, gstFees).toInt();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: HestiaColors.primary),
      ),
    );

    try {
      final details = await BookingFlowService.confirmAfterPayment(
        serviceTitle: matchedTitle,
        selectedDate: _scheduledDate!,
        selectedTime: _scheduledTimeSlot!,
        selectedDuration: _getSelectedDurationLabel(),
        repeatOption: wasInstant ? 'Once' : _repeatOption,
        endsAfter: wasInstant ? '1 session' : _endsAfter,
        preferSameProfessional: _preferSameProfessional,
        totalAmount: finalPay,
        paymentId: response.paymentId,
        servicesMap: _servicesMap,
        donationAmount: donation,
        serviceSubtotal: itemTotal.round(),
        gstAmount: gstFees,
        assignProfessionalNow: wasInstant,
      );

      if (!mounted) return;
      Navigator.pop(context); // loading
      HapticFeedback.vibrate();

      final detail = _getDetail(firstService);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => BookingScheduledScreen(
            bookingId: details.bookingId,
            userName: details.userName,
            address: details.addressLine,
            serviceTitle: details.serviceTitle,
            durationLabel: details.durationLabel,
            amountPaid: details.amountPaid,
            scheduledDate: details.scheduledDate,
            scheduledTime: details.scheduledTime,
            serviceImageAsset: detail?.detailImageAsset ?? detail?.iconAsset,
            serviceCount: details.serviceCount,
            caregiverName: details.professionalName,
            isAwaitingDeparture: details.assignedImmediately,
            donationAmount: details.donationAmount,
            serviceSubtotal: details.serviceSubtotal,
            gstAmount: details.gstAmount,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to confirm booking: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Payment failed: ${response.message ?? 'You cancelled the payment'}',
        ),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  Future<void> _loadAddress() async {
    final user = SupabaseService.currentUser;
    if (user != null) {
      setState(() {
        _isLoadingAddress = true;
      });
      try {
        Map<String, dynamic>? data = await SupabaseService.getUserProfile(user.id);
        if (data == null || data['address'] == null) {
          data = await SupabaseService.downloadProfileJson(user.id);
        }
        final profileData = data;
        if (profileData != null) {
          setState(() {
            _userName = displayPersonName(
              (profileData['name'] ?? profileData['full_name'])?.toString(),
              fallback: 'Soumya',
            );
            final authPhone = SupabaseService.currentUserPhone;
            _phone = (profileData['phone'] as String?)?.isNotEmpty == true
                ? profileData['phone'] as String
                : authPhone.isNotEmpty
                    ? authPhone
                    : '+91 8144684265';
            final authEmail = SupabaseService.currentUserEmail;
            _userEmail = (profileData['email'] as String?)?.isNotEmpty == true
                ? profileData['email'] as String
                : authEmail;
            
            if (profileData['address'] != null) {
              final Map<String, dynamic> address = Map<String, dynamic>.from(profileData['address']);
              final flat = address['flat'] ?? '';
              final street = address['street'] ?? '';
              final city = address['city'] ?? '';
              final pin = address['pincode'] ?? address['pin_code'] ?? '';
              
              if (flat.toString().isNotEmpty || street.toString().isNotEmpty || city.toString().isNotEmpty || pin.toString().isNotEmpty) {
                List<String> parts = [];
                if (flat.toString().isNotEmpty) parts.add(flat);
                if (street.toString().isNotEmpty) parts.add(street);
                if (city.toString().isNotEmpty) parts.add(city);
                parts.add("India");
                if (pin.toString().isNotEmpty) parts.add(pin);
                _addressText = parts.join(", ");
              }
            }
          });
        }
      } catch (e) {
        debugPrint('Error loading address in ScheduleScreen: $e');
      } finally {
        setState(() {
          if (mounted) {
            _isLoadingAddress = false;
          }
        });
      }
    }
  }

  String _formatScheduledSlot(DateTime date, String slot) {
    String timeStr = slot.replaceAll(' ', '');
    if (timeStr.indexOf(':') == 1) {
      timeStr = '0$timeStr';
    }
    
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final tomorrowDate = now.add(const Duration(days: 1));
    final isTomorrow = date.year == tomorrowDate.year && date.month == tomorrowDate.month && date.day == tomorrowDate.day;
    
    if (isToday) {
      return 'Today at $timeStr';
    } else if (isTomorrow) {
      return 'Tomorrow at $timeStr';
    } else {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${date.day} ${months[date.month - 1]} at $timeStr';
    }
  }

  void _openTimeSlotBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TimeSlotBottomSheet(
        onConfirm: (selectedDate, timeSlot) {
          setState(() {
            _scheduledDate = selectedDate;
            _scheduledTimeSlot = timeSlot;
          });
          Navigator.pop(context); // Close bottom sheet
        },
      ),
    );
  }

  ServiceDetail? _getDetail(String rawKey) {
    final key = rawKey.replaceAll('\n', '').replaceAll(' ', '').replaceAll('-', '').toLowerCase();
    if (key.contains('postdelivery')) return ServiceDetailScreen.servicesData['post-delivery'];
    if (key.contains('babysitting')) return ServiceDetailScreen.servicesData['babysitting'];
    if (key.contains('mobility')) return ServiceDetailScreen.servicesData['mobility'];
    if (key.contains('prepregnancy')) return ServiceDetailScreen.servicesData['pre-pregnancy'];
    if (key.contains('bathing') || key.contains('grooming')) {
      return ServiceDetailScreen.servicesData['bathing'];
    }
    if (key.contains('concierge') || key.contains('administrative')) {
      return ServiceDetailScreen.servicesData['concierge'];
    }
    return null;
  }

  double _getItemTotal() {
    double total = 0;
    _servicesMap.forEach((key, minutes) {
      final detail = _getDetail(key);
      if (detail != null) {
        final priceStr = detail.price.replaceAll('₹', '').trim();
        final hourlyPrice = double.tryParse(priceStr) ?? 0.0;
        total += hourlyPrice * (minutes / 60.0);
      }
    });
    return total;
  }

  double _getOriginalTotal() {
    double total = 0;
    _servicesMap.forEach((key, minutes) {
      final detail = _getDetail(key);
      if (detail != null) {
        final priceStr = detail.originalPrice.replaceAll('₹', '').trim();
        final hourlyPrice = double.tryParse(priceStr) ?? 0.0;
        total += hourlyPrice * (minutes / 60.0);
      }
    });
    return total;
  }

  String _getSelectedDurationLabel() {
    final totalMinutes =
        _servicesMap.values.fold<int>(0, (sum, item) => sum + item);
    if (totalMinutes <= 0) {
      return '0.5 hr';
    }
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) {
      return '$minutes min';
    }
    if (minutes == 0) {
      return hours == 1 ? '1 hr' : '$hours hrs';
    }
    if (minutes == 30) {
      return hours == 1 ? '1.5 hrs' : '$hours.5 hrs';
    }
    return '${(totalMinutes / 60).toStringAsFixed(1)} hrs';
  }

  @override
  Widget build(BuildContext context) {
    final itemTotal = _getItemTotal();
    final originalTotal = _getOriginalTotal();
    final savings = originalTotal - itemTotal;
    
    // GST (18% & Service Fees)
    final gstFees = itemTotal * 0.18;
    final donation = _getDonationAmount();
    final finalPay = _calculateFinalPay(itemTotal, gstFees);

    final hasItems = _servicesMap.isNotEmpty;

    return Scaffold(
      backgroundColor: HestiaColors.mutedGrey,
      body: Container(
        color: HestiaColors.mutedGrey,
        child: SafeArea(
          child: Column(
            children: [
            // Header (Back Arrow + "My Cart")
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: HestiaColors.textDark),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'My Cart',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: HestiaColors.textDark,
                    ),
                  ),
                ],
              ),
            ),

            if (!hasItems)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shopping_cart_outlined,
                        size: 80,
                        color: HestiaColors.textLight.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Your cart is empty',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: HestiaColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HestiaColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text(
                          'Add services',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Capsular selector: Instant, Scheduled, Recurring
                      Container(
                        padding: const EdgeInsets.all(4.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.15),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            _buildTabItem('Instant'),
                            _buildTabItem('Scheduled'),
                            _buildTabItem('Recurring'),
                          ],
                        ),
                      ),

                      if (_activeTab == 'Recurring') ...[
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: _openRepeatBooking,
                          child: Container(
                            padding: const EdgeInsets.all(20.0),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: HestiaColors.primary.withValues(alpha: 0.15),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Set up recurring service.',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: HestiaColors.textDark,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Pick your days and time once. We\'ll schedule every visit automatically.',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: HestiaColors.textMedium,
                                          height: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.check_circle_outline_rounded,
                                            color: HestiaColors.primary,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          const Expanded(
                                            child: Text(
                                              'Choose days that work for you',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w500,
                                                color: HestiaColors.textDark,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.check_circle_outline_rounded,
                                            color: HestiaColors.primary,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          const Expanded(
                                            child: Text(
                                              'Same slot every time',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w500,
                                                color: HestiaColors.textDark,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Circular Calendar Badge representing the illustration
                                Column(
                                  children: [
                                    Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: HestiaColors.primary.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: HestiaColors.primary.withValues(alpha: 0.2),
                                          width: 1,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.calendar_month_outlined,
                                        color: HestiaColors.primary,
                                        size: 30,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: HestiaColors.textLight,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Review booking section heading
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Review booking',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: HestiaColors.textDark,
                            ),
                          ),
                          Text(
                            '${_servicesMap.length} ${_servicesMap.length == 1 ? 'service' : 'services'}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: HestiaColors.textMedium,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // List of booking cards
                      ..._servicesMap.entries.map((entry) {
                        final key = entry.key;
                        final minutes = entry.value;
                        final detail = _getDetail(key);

                        if (detail == null) return const SizedBox.shrink();

                        // Pricing for this item
                        final priceStr = detail.price.replaceAll('₹', '').trim();
                        final hourlyPrice = double.tryParse(priceStr) ?? 0.0;
                        final origPriceStr = detail.originalPrice.replaceAll('₹', '').trim();
                        final origHourlyPrice = double.tryParse(origPriceStr) ?? 0.0;

                        final itemCost = hourlyPrice * (minutes / 60.0);
                        final itemOrigCost = origHourlyPrice * (minutes / 60.0);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  // Soft round icon background
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: HestiaColors.primary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Image.asset(
                                      detail.iconAsset,
                                      width: 24,
                                      height: 24,
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Icon(
                                          Icons.medical_services_outlined,
                                          color: HestiaColors.primary,
                                          size: 24,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Service title and cost
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          detail.title,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: HestiaColors.textDark,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.baseline,
                                          textBaseline: TextBaseline.alphabetic,
                                          children: [
                                            Text(
                                              '₹${itemCost.toStringAsFixed(0)}',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color: HestiaColors.textDark,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '₹${itemOrigCost.toStringAsFixed(0)}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: HestiaColors.textLight,
                                                decoration: TextDecoration.lineThrough,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Stepper matching mockup with "Minutes" text under the counter
                                  Container(
                                    width: 104,
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    decoration: BoxDecoration(
                                      color: HestiaColors.primary.withValues(alpha: 0.04),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: HestiaColors.primary.withValues(alpha: 0.25),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              final next = minutes - 30;
                                              if (next <= 0) {
                                                _servicesMap.remove(key);
                                              } else {
                                                _servicesMap[key] = next;
                                              }
                                            });
                                            widget.onServicesChanged?.call(_servicesMap);
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                                            child: Icon(Icons.remove, size: 14, color: HestiaColors.primary),
                                          ),
                                        ),
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '$minutes',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: HestiaColors.primary,
                                              ),
                                            ),
                                            const Text(
                                              'Minutes',
                                              style: TextStyle(
                                                fontSize: 7.5,
                                                fontWeight: FontWeight.w500,
                                                color: HestiaColors.textMedium,
                                              ),
                                            ),
                                          ],
                                        ),
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _servicesMap[key] = minutes + 30;
                                            });
                                            widget.onServicesChanged?.call(_servicesMap);
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                                            child: Icon(Icons.add, size: 14, color: HestiaColors.primary),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),

                      // Slots note banner
                      Container(
                        padding: const EdgeInsets.all(12.0),
                        margin: const EdgeInsets.only(bottom: 12.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F4FA), // Soft blue tint container
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, color: Color(0xFF4A7BD0), size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Slots may vary based on partner availability and the selected service.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF4A6080),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Add more services link
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12.0),
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: RichText(
                              text: const TextSpan(
                                style: TextStyle(fontSize: 13, color: HestiaColors.textMedium),
                                children: [
                                  TextSpan(text: 'Missed something? '),
                                  TextSpan(
                                    text: 'Add more services.',
                                    style: TextStyle(
                                      color: HestiaColors.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // View all coupons card
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.local_offer_outlined, color: Colors.grey.shade400, size: 20),
                            const SizedBox(width: 12),
                            const Text(
                              'View all coupons',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: HestiaColors.textDark,
                              ),
                            ),
                            const Spacer(),
                            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Booking details section heading
                      const Text(
                        'Booking details',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: HestiaColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Location & Contact Details card
                      Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            if (_isInstantTab) ...[
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.bolt_rounded,
                                      color: Colors.grey.shade500,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Starts as soon as possible',
                                            style: TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.bold,
                                              color: HestiaColors.textDark,
                                            ),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            'No time slot needed. We\'ll assign a nearby professional right after payment.',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color: HestiaColors.textMedium,
                                              height: 1.35,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
                            ],
                            if (_activeTab == 'Scheduled' && _scheduledDate != null && _scheduledTimeSlot != null) ...[
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.calendar_today_outlined,
                                      color: Colors.grey.shade500,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Scheduled for',
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              color: HestiaColors.textMedium,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _formatScheduledSlot(_scheduledDate!, _scheduledTimeSlot!),
                                            style: const TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.bold,
                                              color: HestiaColors.textDark,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          GestureDetector(
                                            onTap: () => _openTimeSlotBottomSheet(context),
                                            child: const Text(
                                              'Change slot',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: HestiaColors.primary,
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
                              Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
                            ],
                            // Location card item
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => const SearchLocationScreen(),
                                    ),
                                  ).then((_) => _loadAddress());
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.location_on_outlined, color: HestiaColors.primary, size: 22),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Location',
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.bold,
                                                color: HestiaColors.textDark,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _isLoadingAddress ? 'Loading address...' : _addressText,
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                color: HestiaColors.textMedium,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
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
                            Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
                            // Contact card item
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  const Icon(Icons.phone_outlined, color: HestiaColors.primary, size: 22),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _userName,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                            color: HestiaColors.textDark,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _phone,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: HestiaColors.textMedium,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      _buildDonationSection(),

                      const SizedBox(height: 24),

                      // Bill Details Heading
                      const Text(
                        'Bill details',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: HestiaColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Bill breakdown container card
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Bill Summary Row
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isBillExpanded = !_isBillExpanded;
                                });
                              },
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'To pay ₹${(finalPay).toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.bold,
                                            color: HestiaColors.textDark,
                                          ),
                                        ),
                                        if (savings > 0) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            '₹${savings.toStringAsFixed(0)} saved on the total!',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF1E88E5), // Soft accent blue savings
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    _isBillExpanded ? Icons.expand_less : Icons.expand_more,
                                    color: Colors.grey.shade600,
                                    size: 24,
                                  ),
                                ],
                              ),
                            ),

                            if (_isBillExpanded) ...[
                              const SizedBox(height: 12),
                              Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
                              const SizedBox(height: 12),

                              // Item total
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Item total',
                                    style: TextStyle(fontSize: 13, color: HestiaColors.textMedium),
                                  ),
                                  Text(
                                    '₹${itemTotal.toStringAsFixed(0)}',
                                    style: const TextStyle(fontSize: 13, color: HestiaColors.textDark),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              if (donation > 0) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'NGO donation',
                                      style: TextStyle(fontSize: 13, color: HestiaColors.textMedium),
                                    ),
                                    Text(
                                      '₹$donation',
                                      style: const TextStyle(fontSize: 13, color: HestiaColors.textDark),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                              ],

                              // GST & Service Fees
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'GST & Service Fees',
                                        style: TextStyle(fontSize: 13, color: HestiaColors.textMedium),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.info_outline, size: 13, color: Colors.grey.shade400),
                                    ],
                                  ),
                                  Text(
                                    '₹${gstFees.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 13, color: HestiaColors.textDark),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
                              const SizedBox(height: 12),

                              // To pay
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'To pay',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: HestiaColors.textDark),
                                  ),
                                  Text(
                                    '₹${finalPay.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: HestiaColors.textDark),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),

            // Sticky Bottom Checkout Button
            if (hasItems)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20.0, 8.0, 20.0, 20.0),
                  child: Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      color: HestiaColors.primary,
                      borderRadius: BorderRadius.circular(14),
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
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          if (!SupabaseService.isPhoneVerified()) {
                            _showPhoneVerificationPopup(context);
                            return;
                          }
                          if (_activeTab == 'Recurring') {
                            _openRepeatBooking();
                          } else if (_isInstantTab) {
                            if (_validateDonationBeforePay()) {
                              _proceedToPay();
                            }
                          } else {
                            if (_scheduledDate == null || _scheduledTimeSlot == null) {
                              _openTimeSlotBottomSheet(context);
                            } else if (_validateDonationBeforePay()) {
                              _proceedToPay();
                            }
                          }
                        },
                        child: Center(
                          child: Text(
                            _activeTab == 'Recurring'
                                ? 'Select frequency & time slot'
                                : _isInstantTab
                                    ? 'Book instantly'
                                : (_scheduledDate == null || _scheduledTimeSlot == null
                                    ? 'Select time slot'
                                    : 'Proceed to pay'),
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
  );
  }

  Widget _buildDonationSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _donateToNgo
              ? HestiaColors.primary.withValues(alpha: 0.35)
              : Colors.grey.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              setState(() {
                _donateToNgo = !_donateToNgo;
                if (!_donateToNgo) {
                  _donationAmount = 0;
                  _selectedDonationPreset = null;
                  _donationController.clear();
                } else if (_donationAmount == 0) {
                  _setDonationAmount(_donationPresets.first);
                }
              });
            },
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: _donateToNgo,
                    activeColor: HestiaColors.primary,
                    side: BorderSide(color: Colors.grey.shade400),
                    onChanged: (checked) {
                      setState(() {
                        _donateToNgo = checked ?? false;
                        if (!_donateToNgo) {
                          _donationAmount = 0;
                          _selectedDonationPreset = null;
                          _donationController.clear();
                        } else if (_donationAmount == 0) {
                          _setDonationAmount(_donationPresets.first);
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.volunteer_activism_outlined,
                  color: HestiaColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Donate to NGO',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: HestiaColors.textDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_donateToNgo) ...[
            const SizedBox(height: 6),
            Text(
              '100% of your contribution goes to Hestia Care Foundation.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _donationController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: 'Enter amount',
                prefixText: '₹ ',
                prefixStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: HestiaColors.textDark,
                ),
                filled: true,
                fillColor: const Color(0xFFFAF7F4),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: HestiaColors.primary,
                    width: 1.4,
                  ),
                ),
              ),
              onChanged: (value) {
                final amount = int.tryParse(value.trim()) ?? 0;
                setState(() {
                  _donationAmount = amount;
                  _selectedDonationPreset =
                      _donationPresets.contains(amount) ? amount : null;
                });
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: _donationPresets.map((preset) {
                final isSelected = _selectedDonationPreset == preset;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: preset == _donationPresets.last ? 0 : 8,
                    ),
                    child: OutlinedButton(
                      onPressed: () => _setDonationAmount(preset),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isSelected
                            ? Colors.white
                            : HestiaColors.primary,
                        backgroundColor:
                            isSelected ? HestiaColors.primary : Colors.white,
                        side: BorderSide(
                          color: HestiaColors.primary.withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        '₹$preset',
                        style: const TextStyle(fontWeight: FontWeight.w700),
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

  Widget _buildTabItem(String title) {
    final isSelected = title == _activeTab;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _activeTab = title;
            if (title == 'Instant') {
              _applyInstantScheduleNow();
            }
          });
        },
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? HestiaColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : HestiaColors.textMedium,
            ),
          ),
        ),
      ),
    );
  }

  void _showPhoneVerificationPopup(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: HestiaColors.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFC0392B), size: 28),
              SizedBox(width: 10),
              Text(
                'Verify Mobile Number',
                style: TextStyle(fontWeight: FontWeight.bold, color: HestiaColors.textDark, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'To continue and complete your booking, please verify your mobile number. This is required for secure communication with care professionals.',
                style: TextStyle(fontSize: 14.5, color: HestiaColors.textMedium, height: 1.4),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.orangeAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You can complete verification in the Profile screen.',
                        style: TextStyle(color: Colors.orange.shade900, fontSize: 12.5, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: HestiaColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please navigate to the Profile screen to verify your number.'),
                    backgroundColor: HestiaColors.primary,
                  ),
                );
              },
              child: const Text('Verify Now', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}


