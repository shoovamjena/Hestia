import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../screens/tracking_screen.dart';
import '../utils/active_booking_navigation.dart';
import 'supabase_service.dart';

/// Broadcast when staff auto-confirms arrival (within 50 m) or server inserts
/// a professional_arrived notification.
class SessionArrivalEvent {
  final String bookingId;
  final String? sessionId;
  final String? caregiverName;
  final bool openVerify;

  const SessionArrivalEvent({
    required this.bookingId,
    this.sessionId,
    this.caregiverName,
    this.openVerify = false,
  });
}

/// Routes verify_arrival taps and keeps home / tracking in sync with staff arrival.
class SessionArrivalCoordinator {
  SessionArrivalCoordinator._();

  static final SessionArrivalCoordinator instance = SessionArrivalCoordinator._();

  final StreamController<SessionArrivalEvent> _events =
      StreamController<SessionArrivalEvent>.broadcast();

  GlobalKey<NavigatorState>? _navigatorKey;
  SessionArrivalEvent? _pendingNavigation;

  Stream<SessionArrivalEvent> get events => _events.stream;

  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
    _flushPendingNavigation();
  }

  /// UI refresh signal only — no local notification (staff inserts user_notifications).
  void notifySessionArrived({
    required String bookingId,
    String? sessionId,
    String? caregiverName,
    bool openVerify = false,
  }) {
    final event = SessionArrivalEvent(
      bookingId: bookingId,
      sessionId: sessionId,
      caregiverName: caregiverName,
      openVerify: openVerify,
    );
    _events.add(event);
  }

  void notifyArrivedFromNotificationRow(Map<String, dynamic> row) {
    final parsed = _parsePayload(row);
    notifySessionArrived(
      bookingId: parsed.bookingId ?? '',
      sessionId: parsed.sessionId,
      openVerify: parsed.action == 'verify_arrival',
    );
  }

  Map<String, dynamic> payloadForLocalNotification(Map<String, dynamic> row) {
    final parsed = _parsePayload(row);
    return {
      'action': parsed.action ?? 'verify_arrival',
      'notification_type': parsed.notificationType ?? 'professional_arrived',
      'booking_id': parsed.bookingId,
      'session_id': parsed.sessionId,
      'notification_id': row['id']?.toString(),
    };
  }

  Future<void> handleNotificationPayload(String? rawPayload) async {
    if (rawPayload == null || rawPayload.isEmpty) return;

    Map<String, dynamic>? data;
    try {
      data = jsonDecode(rawPayload) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final parsed = _ParsedArrivalPayload.fromMap(data);
    if (!_shouldOpenVerify(parsed)) return;

    final bookingId = parsed.bookingId;
    if (bookingId == null || bookingId.isEmpty) return;

    await openVerifyArrival(
      bookingId: bookingId,
      sessionId: parsed.sessionId,
    );
  }

  Future<void> openVerifyArrival({
    required String bookingId,
    String? sessionId,
  }) async {
    final nav = _navigatorKey?.currentState;
    if (nav == null) {
      _pendingNavigation = SessionArrivalEvent(
        bookingId: bookingId,
        sessionId: sessionId,
        openVerify: true,
      );
      return;
    }

    Map<String, dynamic>? booking =
        await SupabaseService.getBookingStatus(bookingId);
    booking ??= {
      'booking_id': bookingId,
      if (sessionId != null) 'session_id': sessionId,
      'status': 'arrived',
    };

    if (sessionId != null && booking['session_id'] == null) {
      booking = {...booking, 'session_id': sessionId};
    }

    final status = booking['status']?.toString().toLowerCase() ?? '';
    if (status == 'completed' || isNoShowBooking(booking)) {
      return;
    }

    if (!shouldOpenTrackingForBooking(booking) && status != 'arrived') {
      return;
    }

    await nav.push(
      MaterialPageRoute(
        builder: (_) => TrackingScreen(
          bookingData: booking!,
          openVerifyOnLoad: true,
        ),
      ),
    );
  }

  void _flushPendingNavigation() {
    final pending = _pendingNavigation;
    if (pending == null) return;
    _pendingNavigation = null;
    unawaited(
      openVerifyArrival(
        bookingId: pending.bookingId,
        sessionId: pending.sessionId,
      ),
    );
  }

  bool _shouldOpenVerify(_ParsedArrivalPayload parsed) {
    if (parsed.action == 'verify_arrival') return true;
    return parsed.notificationType == 'professional_arrived';
  }

  _ParsedArrivalPayload _parsePayload(Map<String, dynamic> row) {
    final metadata = _coerceMap(row['metadata']);
    return _ParsedArrivalPayload(
      bookingId: row['booking_id']?.toString() ??
          metadata?['booking_id']?.toString(),
      sessionId: row['session_id']?.toString() ??
          metadata?['session_id']?.toString(),
      notificationType: row['notification_type']?.toString() ??
          row['type']?.toString(),
      action: metadata?['action']?.toString(),
    );
  }

  Map<String, dynamic>? _coerceMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }
}

class _ParsedArrivalPayload {
  final String? bookingId;
  final String? sessionId;
  final String? notificationType;
  final String? action;

  const _ParsedArrivalPayload({
    this.bookingId,
    this.sessionId,
    this.notificationType,
    this.action,
  });

  factory _ParsedArrivalPayload.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? metadata;
    final rawMeta = map['metadata'];
    if (rawMeta is Map) {
      metadata = Map<String, dynamic>.from(rawMeta);
    } else if (rawMeta is String && rawMeta.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawMeta);
        if (decoded is Map) metadata = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }

    return _ParsedArrivalPayload(
      bookingId: map['booking_id']?.toString() ??
          metadata?['booking_id']?.toString(),
      sessionId: map['session_id']?.toString() ??
          metadata?['session_id']?.toString(),
      notificationType:
          map['notification_type']?.toString() ?? map['type']?.toString(),
      action: map['action']?.toString() ?? metadata?['action']?.toString(),
    );
  }
}
