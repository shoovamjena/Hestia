import 'package:flutter/material.dart';

import '../screens/booking_scheduled_screen.dart';
import '../screens/rate_session_screen.dart';
import '../screens/tracking_screen.dart';
import '../services/supabase_service.dart';
import 'string_format.dart';

/// Instant bookings include ~30 min travel time before the pro is considered late.
const Duration instantTravelBuffer = Duration(minutes: 30);

/// Whether the consumer should see live tracking (pro has left the hub).
bool shouldOpenTrackingForBooking(Map<String, dynamic> booking) {
  final professionalId = booking['professional_id']?.toString();
  if (professionalId == null || professionalId.isEmpty) return false;

  final assignmentStatus =
      booking['assignment_status']?.toString().toLowerCase() ?? 'pending';
  if (assignmentStatus == 'pending' ||
      assignmentStatus == 'unassigned_failed') {
    return false;
  }

  final status = booking['status']?.toString().trim().toLowerCase() ?? '';
  // Staff app sets "departed" on leave-hub; older flows used "transit"/"en_route".
  const departedStatuses = {
    'departed',
    'transit',
    'en_route',
    'arrived',
    'started',
    'active',
    'in_progress',
  };
  return departedStatuses.contains(status);
}

bool isNoShowBooking(Map<String, dynamic> booking) {
  final status = booking['status']?.toString().trim().toLowerCase() ?? '';
  return status == 'no_show' || status == 'unattended';
}

/// Professional has left the hub and is traveling to the customer.
bool isProfessionalOnTheWay(Map<String, dynamic> booking) {
  final status = booking['status']?.toString().trim().toLowerCase() ?? '';
  return status == 'departed' ||
      status == 'transit' ||
      status == 'en_route';
}

/// Care session has started and is currently underway.
bool isSessionUndergoing(Map<String, dynamic> booking) {
  final status = booking['status']?.toString().trim().toLowerCase() ?? '';
  return status == 'started' ||
      status == 'active' ||
      status == 'in_progress';
}

/// Whether home should show the richer active-session card (still with discovery below).
bool shouldFocusHomeOnActiveBooking(Map<String, dynamic> booking) {
  if (isNoShowBooking(booking)) return true;
  if (isProfessionalOnTheWay(booking)) return true;
  if (isSessionUndergoing(booking)) return true;

  final status = booking['status']?.toString().trim().toLowerCase() ?? '';
  if (status == 'arrived') return true;

  // Assigned booking waiting to start / depart.
  final caregiver = booking['caregiver_name']?.toString().trim() ?? '';
  final hasCaregiver =
      caregiver.isNotEmpty && caregiver.toLowerCase() != 'professional';
  if (hasCaregiver &&
      (status == 'confirmed' ||
          status == 'scheduled' ||
          status == 'assigned')) {
    return true;
  }

  return false;
}

/// Stable key so "Post-Delivery" and "Post-Delivery Care" match as one reason.
String serviceReasonKey(String? raw) {
  final normalized = (raw ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-_/]+'), '')
      .replaceAll('care', '');
  if (normalized.contains('postdelivery')) return 'postdelivery';
  if (normalized.contains('babysitting')) return 'babysitting';
  if (normalized.contains('mobility')) return 'mobility';
  if (normalized.contains('prepregnancy')) return 'prepregnancy';
  if (normalized.contains('bathing') || normalized.contains('grooming')) {
    return 'bathing';
  }
  if (normalized.contains('concierge') ||
      normalized.contains('administrative')) {
    return 'concierge';
  }
  return normalized;
}

bool isSameServiceReason(String? a, String? b) {
  final keyA = serviceReasonKey(a);
  final keyB = serviceReasonKey(b);
  if (keyA.isEmpty || keyB.isEmpty) return false;
  return keyA == keyB;
}

/// True when [serviceLabel] matches the active booking's care reason.
bool isServiceBlockedByActiveBooking(
  Map<String, dynamic>? activeBooking,
  String serviceLabel,
) {
  if (activeBooking == null) return false;
  final activeTitle = activeBooking['title']?.toString() ??
      activeBooking['service_type']?.toString();
  return isSameServiceReason(activeTitle, serviceLabel);
}

String professionalFirstName(String? caregiverName) {
  final trimmed = caregiverName?.trim() ?? '';
  if (trimmed.isEmpty || trimmed.toLowerCase() == 'professional') {
    return 'Your professional';
  }
  return capitalizeWords(trimmed.split(RegExp(r'\s+')).first);
}

String displayCaregiverName(
  String? caregiverName, {
  String fallback = 'Professional',
}) {
  return displayPersonName(caregiverName, fallback: fallback);
}

String professionalOnTheWayMessage(String? caregiverName) {
  return '${professionalFirstName(caregiverName)} is on the way';
}

/// Instant bookings assign a professional immediately (`assignment_deferred: false`).
bool isInstantBooking(Map<String, dynamic> booking) {
  if (booking['is_instant'] == true) return true;
  if (booking['assignment_deferred'] == false) return true;
  return false;
}

/// For instant bookings, ignore the initial session `transit` row created at
/// payment — only treat `departed` / `en_route` as having left the hub.
bool hasDepartedHubForLateCheck(Map<String, dynamic> booking) {
  final status = booking['status']?.toString().trim().toLowerCase() ?? '';
  if (isInstantBooking(booking)) {
    return status == 'departed' || status == 'en_route';
  }
  return status == 'departed' ||
      status == 'transit' ||
      status == 'en_route';
}

DateTime? expectedArrivalDeadline(Map<String, dynamic> booking) {
  final raw = booking['expected_arrival_at'];
  if (raw is DateTime) return raw;
  if (raw != null) return DateTime.tryParse(raw.toString());
  return null;
}

DateTime? scheduledStartFromBooking(Map<String, dynamic> booking) {
  final raw = booking['scheduled_start'];
  if (raw is DateTime) return raw;
  if (raw != null) return DateTime.tryParse(raw.toString());
  return SupabaseService.parseScheduledStartLocal(
    booking['scheduled_date'],
    booking['scheduled_time'],
  );
}

/// True when the scheduled start has passed and the pro has not arrived yet.
bool isProfessionalRunningLate({
  required DateTime? scheduledStart,
  String? status,
  DateTime? now,
}) {
  if (scheduledStart == null) return false;
  final current = now ?? DateTime.now();
  if (!current.isAfter(scheduledStart)) return false;

  final normalized = (status ?? '').trim().toLowerCase();
  const arrivedOrDone = {
    'arrived',
    'started',
    'active',
    'in_progress',
    'completed',
    'cancelled',
    'no_show',
    'unattended',
  };
  return !arrivedOrDone.contains(normalized);
}

bool isProfessionalRunningLateForBooking(
  Map<String, dynamic> booking, {
  DateTime? now,
}) {
  if (isNoShowBooking(booking)) return false;

  final status = booking['status']?.toString().trim().toLowerCase() ?? '';
  const arrivedOrDone = {
    'arrived',
    'started',
    'active',
    'in_progress',
    'completed',
    'cancelled',
    'no_show',
    'unattended',
  };
  if (arrivedOrDone.contains(status)) return false;

  final current = now ?? DateTime.now();

  if (isInstantBooking(booking)) {
    // Never late until the pro has actually left the hub.
    if (!hasDepartedHubForLateCheck(booking)) return false;

    // One-time ETA snapshot taken when staff marks departed.
    final deadline = expectedArrivalDeadline(booking);
    if (deadline != null) {
      return current.isAfter(deadline);
    }
    return false;
  }

  return isProfessionalRunningLate(
    scheduledStart: scheduledStartFromBooking(booking),
    status: status,
    now: current,
  );
}

/// Short first-name friendly late message for consumer UI.
String professionalRunningLateMessage(String? caregiverName) {
  return '${professionalFirstName(caregiverName)} is running late and trying to reach your location quickly.';
}

String formatBookingTimeLabel(DateTime dateTime) {
  final hour = dateTime.hour;
  final minute = dateTime.minute;
  final period = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  final displayMinute = minute.toString().padLeft(2, '0');
  return '$displayHour:$displayMinute $period';
}

String formatDurationLabel(double hours) {
  if (hours <= 0) return '2 Hours';
  if (hours == 1) return '1 Hour';
  if (hours == hours.roundToDouble()) return '${hours.toInt()} Hours';
  return '${hours.toStringAsFixed(1)} Hours';
}

BookingScheduledScreen bookingScheduledScreenFromActiveBooking({
  required Map<String, dynamic> booking,
  required String userName,
}) {
  final scheduledStart = booking['scheduled_start'] is DateTime
      ? booking['scheduled_start'] as DateTime
      : DateTime.tryParse(booking['scheduled_start']?.toString() ?? '') ??
          DateTime.now();
  final durationHours =
      (booking['duration_hours'] as num?)?.toDouble() ?? 2.0;
  final caregiverName = booking['caregiver_name']?.toString();
  final hasAssignedCaregiver = caregiverName != null &&
      caregiverName.isNotEmpty &&
      caregiverName != 'Professional';

  return BookingScheduledScreen(
    bookingId: booking['booking_id']?.toString() ?? '',
    userName: userName,
    address: booking['user_address']?.toString() ?? '',
    serviceTitle: booking['title']?.toString() ?? 'Care',
    durationLabel: formatDurationLabel(durationHours),
    amountPaid: (booking['amount'] as num?)?.toInt() ?? 0,
    scheduledDate: DateTime(
      scheduledStart.year,
      scheduledStart.month,
      scheduledStart.day,
    ),
    scheduledTime: formatBookingTimeLabel(scheduledStart),
    caregiverName: hasAssignedCaregiver ? caregiverName : null,
    isAwaitingDeparture: hasAssignedCaregiver &&
        !shouldOpenTrackingForBooking(booking),
    donationAmount: (booking['donation_amount'] as num?)?.toInt() ?? 0,
    serviceSubtotal: (booking['service_subtotal'] as num?)?.toInt() ?? 0,
    gstAmount: (booking['gst_amount'] as num?)?.toDouble() ?? 0,
    bookingStatus: booking['status']?.toString(),
  );
}

Map<String, dynamic> rateSessionDataFromBooking(Map<String, dynamic> booking) {
  final scheduledStart = booking['scheduled_start'] is DateTime
      ? booking['scheduled_start'] as DateTime
      : DateTime.tryParse(booking['scheduled_start']?.toString() ?? '') ??
          DateTime.now();
  return {
    ...booking,
    'scheduled_start': scheduledStart,
    'status': booking['status'] ?? 'no_show',
    'caregiver_name': booking['caregiver_name'] ?? 'Professional',
    'title': booking['title'] ?? booking['service_type'] ?? 'Care',
  };
}

/// Opens scheduled, tracking, or review (no-show) based on booking state.
/// Being late never blocks navigation — it only changes copy on those screens.
Future<void> openActiveBookingScreen(
  BuildContext context, {
  required Map<String, dynamic> booking,
  required String userName,
  bool openVerify = false,
}) async {
  var resolved = Map<String, dynamic>.from(booking);
  final bookingId = resolved['booking_id']?.toString();
  if (bookingId != null && bookingId.isNotEmpty) {
    try {
      final latest = await SupabaseService.getBookingStatus(bookingId);
      if (latest != null) {
        resolved = {...resolved, ...latest};
      }
    } catch (_) {}
  }

  if (!context.mounted) return;

  final status = resolved['status']?.toString().trim().toLowerCase() ?? '';
  if (status == 'completed' || isNoShowBooking(resolved)) {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RateSessionScreen(
          sessionData: rateSessionDataFromBooking({
            ...resolved,
            'status': status.isEmpty ? 'completed' : status,
          }),
        ),
      ),
    );
    return;
  }

  if (shouldOpenTrackingForBooking(resolved)) {
    final shouldVerify = openVerify ||
        resolved['status']?.toString().toLowerCase() == 'arrived';
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrackingScreen(
          bookingData: resolved,
          openVerifyOnLoad: shouldVerify,
        ),
      ),
    );
    return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => bookingScheduledScreenFromActiveBooking(
        booking: resolved,
        userName: userName,
      ),
    ),
  );
}
