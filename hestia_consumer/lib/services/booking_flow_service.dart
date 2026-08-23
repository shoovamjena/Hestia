import 'professional_matching_service.dart';
import 'supabase_service.dart';

class ConfirmedBookingDetails {
  final String bookingId;
  final String userName;
  final String addressLine;
  final String serviceTitle;
  final String durationLabel;
  final int amountPaid;
  final DateTime scheduledDate;
  final String scheduledTime;
  final int serviceCount;
  final String? professionalName;
  final int donationAmount;
  final int serviceSubtotal;
  final double gstAmount;
  final bool assignedImmediately;

  const ConfirmedBookingDetails({
    required this.bookingId,
    required this.userName,
    required this.addressLine,
    required this.serviceTitle,
    required this.durationLabel,
    required this.amountPaid,
    required this.scheduledDate,
    required this.scheduledTime,
    required this.serviceCount,
    this.professionalName,
    this.donationAmount = 0,
    this.serviceSubtotal = 0,
    this.gstAmount = 0,
    this.assignedImmediately = false,
  });
}

/// Creates a booking after payment.
/// Scheduled bookings defer assignment to the T-45 job.
/// Instant bookings assign a professional immediately.
class BookingFlowService {
  BookingFlowService._();

  static String serviceNamesLabel(Map<String, int>? servicesMap, String fallback) {
    if (servicesMap != null && servicesMap.isNotEmpty) {
      return servicesMap.keys.join(', ');
    }
    return fallback;
  }

  static String durationLabel(Map<String, int>? servicesMap, String fallback) {
    if (servicesMap != null && servicesMap.isNotEmpty) {
      final totalMins =
          servicesMap.values.fold<int>(0, (sum, item) => sum + item);
      final hours = totalMins / 60.0;
      return hours % 1 == 0
          ? '${hours.toInt()} hrs'
          : '${hours.toStringAsFixed(1)} hrs';
    }
    return fallback;
  }

  static Future<String> _formatPrimaryAddress(String userId) async {
    final addresses = await SupabaseService.getUserAddresses(userId);
    Map<String, dynamic>? primary;
    for (final a in addresses) {
      if (a['is_primary'] == true) {
        primary = a;
        break;
      }
    }
    primary ??= addresses.isNotEmpty ? addresses.first : null;
    if (primary == null) return '';

    final flat = SupabaseService.cleanFlatName(
      primary['flat']?.toString() ?? '',
    );
    final parts = [
      flat,
      primary['street']?.toString() ?? '',
      primary['city']?.toString() ?? '',
      primary['pin_code']?.toString() ?? '',
    ].where((p) => p.trim().isNotEmpty).toList();
    return parts.join(', ');
  }

  static Future<String> _resolveUserName(String userId) async {
    try {
      final profile = await SupabaseService.getUserProfile(userId);
      final name = profile?['name']?.toString() ?? '';
      if (name.isNotEmpty) return name;
    } catch (_) {}
    return SupabaseService.currentUser?.userMetadata?['full_name']
            ?.toString() ??
        'you';
  }

  /// Creates the booking after payment.
  /// Scheduled: assignment deferred (~45 min before slot).
  /// Instant (`assignProfessionalNow: true`): match + assign now.
  static Future<ConfirmedBookingDetails> confirmAfterPayment({
    required String serviceTitle,
    required DateTime selectedDate,
    required String selectedTime,
    required String selectedDuration,
    required String repeatOption,
    required String endsAfter,
    required bool preferSameProfessional,
    required int totalAmount,
    String? paymentId,
    Map<String, int>? servicesMap,
    int donationAmount = 0,
    int? serviceSubtotal,
    double? gstAmount,
    bool assignProfessionalNow = false,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      throw Exception('Please sign in to confirm your booking.');
    }

    final label = serviceNamesLabel(servicesMap, serviceTitle);
    final duration = durationLabel(servicesMap, selectedDuration);

    String selectedProfessionalName = '';
    if (assignProfessionalNow) {
      try {
        final best = await ProfessionalMatchingService.findBestMatch(
          userId: user.id,
          serviceTitle: label,
          selectedDate: selectedDate,
          selectedTime: selectedTime,
          selectedDuration: duration,
          preferSameProfessional: preferSameProfessional,
        );
        selectedProfessionalName = best?.name ?? '';
      } catch (_) {
        // createBooking still falls back to any hub professional.
      }
    }

    final bookingId = await SupabaseService.createBooking(
      userId: user.id,
      serviceTitle: label,
      selectedDate: selectedDate,
      selectedTime: selectedTime,
      selectedDuration: duration,
      selectedProfessionalName: selectedProfessionalName,
      repeatOption: repeatOption,
      endsAfter: endsAfter,
      preferSameProfessional: preferSameProfessional,
      totalAmount: totalAmount,
      paymentId: paymentId,
      assignProfessionalNow: assignProfessionalNow,
      donationAmount: donationAmount,
      serviceSubtotal: serviceSubtotal,
      gstAmount: gstAmount,
    );

    final addressLine = await _formatPrimaryAddress(user.id);
    final userName = await _resolveUserName(user.id);

    String? professionalName = selectedProfessionalName.isNotEmpty
        ? selectedProfessionalName
        : null;
    if (assignProfessionalNow && professionalName == null) {
      try {
        final status = await SupabaseService.getBookingStatus(bookingId);
        final name = status?['caregiver_name']?.toString();
        if (name != null &&
            name.isNotEmpty &&
            name.toLowerCase() != 'professional') {
          professionalName = name;
        }
      } catch (_) {}
    }

    return ConfirmedBookingDetails(
      bookingId: bookingId,
      userName: userName.isNotEmpty ? userName : 'you',
      addressLine: addressLine,
      serviceTitle: label,
      durationLabel: duration,
      amountPaid: totalAmount,
      scheduledDate: selectedDate,
      scheduledTime: selectedTime,
      serviceCount: servicesMap?.length ?? 1,
      professionalName: professionalName,
      donationAmount: donationAmount,
      serviceSubtotal: serviceSubtotal ?? (totalAmount - donationAmount),
      gstAmount: gstAmount ?? 0,
      assignedImmediately:
          assignProfessionalNow && professionalName != null,
    );
  }
}
