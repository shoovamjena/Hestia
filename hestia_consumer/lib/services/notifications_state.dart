import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/string_format.dart';
import 'session_arrival_coordinator.dart';
import 'supabase_service.dart';

class NotificationsState {
  static final NotificationsState instance = NotificationsState._internal();

  NotificationsState._internal();

  final List<RealtimeChannel> _realtimeChannels = [];
  FlutterLocalNotificationsPlugin? _localNotifications;
  Set<String> _watchedBookingIds = <String>{};
  Set<String> _watchedHubIds = <String>{};
  final Set<String> _shownNotificationKeys = <String>{};

  Future<void> initLocalNotifications() async {
    _localNotifications = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _localNotifications?.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        SessionArrivalCoordinator.instance
            .handleNotificationPayload(details.payload);
      },
    );
    await requestPermissions();
  }

  Future<void> requestPermissions() async {
    if (_localNotifications == null) return;

    final android = _localNotifications!
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();

    final ios = _localNotifications!
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);

    final macos = _localNotifications!
        .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
    await macos?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> showLocalNotification(
    Map<String, dynamic> row, {
    Map<String, dynamic>? tapPayload,
  }) async {
    if (_localNotifications == null) return;

    const androidDetails = AndroidNotificationDetails(
      'hestia_channel',
      'Hestia Notifications',
      channelDescription: 'Realtime alerts for Hestia sessions',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    final id = row['id']?.toString().hashCode ?? 0;
    final title = row['title']?.toString() ?? 'Hestia Update';
    final body = row['body']?.toString() ?? '';
    final payload = tapPayload == null ? null : jsonEncode(tapPayload);

    await _localNotifications?.show(id, title, body, details, payload: payload);
  }

  /// Shows a local notification once per logical event (FCM + realtime share keys).
  Future<void> handleIncomingNotification(Map<String, dynamic> row) async {
    final keys = _dedupeKeysFor(row);
    if (keys.isEmpty) return;
    if (keys.any(_shownNotificationKeys.contains)) return;
    _shownNotificationKeys.addAll(keys);

    final tapPayload =
        SessionArrivalCoordinator.instance.payloadForLocalNotification(row);
    await showLocalNotification(row, tapPayload: tapPayload);
  }

  Future<void> initialize() async {
    disposeSubscription();

    final user = SupabaseService.currentUser;
    if (user == null) return;
    _watchedBookingIds = await SupabaseService.getUserBookingIds(user.id);
    _watchedHubIds = await SupabaseService.getCurrentUserHubIds(user.id);

    final userChannel = SupabaseService.client
        .channel('client_notifications_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'user_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) async {
            final row = Map<String, dynamic>.from(payload.newRecord);
            final type = row['notification_type']?.toString();
            if (type == 'professional_arrived') {
              SessionArrivalCoordinator.instance
                  .notifyArrivedFromNotificationRow(row);
            }
            await handleIncomingNotification(row);
          },
        )
        .subscribe();
    _realtimeChannels.add(userChannel);

    final hubBroadcastChannel = SupabaseService.client
        .channel('consumer_hub_broadcasts_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'target_app',
            value: 'consumer',
          ),
          callback: (payload) async {
            final row = payload.newRecord;
            if (_isRelevantBroadcast(row, user.id, _watchedHubIds)) {
              await handleIncomingNotification(row);
            }
          },
        )
        .subscribe();
    _realtimeChannels.add(hubBroadcastChannel);

    // Staff is source of truth for arrival. Listen for UI refresh only — do NOT
    // show a second local notification here (user_notifications + FCM handle that).
    final arrivalChannel = SupabaseService.client
        .channel('consumer_arrivals_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'sessions',
          callback: (payload) async {
            final row = payload.newRecord;
            final old = payload.oldRecord;
            final status = row['status']?.toString().toLowerCase();
            final oldStatus = old['status']?.toString().toLowerCase();
            if (status != 'arrived' || oldStatus == 'arrived') return;

            final bookingId = row['booking_id']?.toString();
            final sessionId = row['id']?.toString();
            if (bookingId == null || sessionId == null) return;

            if (!_watchedBookingIds.contains(bookingId)) {
              _watchedBookingIds =
                  await SupabaseService.getUserBookingIds(user.id);
              if (!_watchedBookingIds.contains(bookingId)) return;
            }

            final bookingData =
                await SupabaseService.getBookingStatus(bookingId);
            SessionArrivalCoordinator.instance.notifySessionArrived(
              bookingId: bookingId,
              sessionId: sessionId,
              caregiverName: displayPersonName(
                bookingData?['caregiver_name']?.toString(),
                fallback: 'Your professional',
              ),
              openVerify: true,
            );
          },
        )
        .subscribe();
    _realtimeChannels.add(arrivalChannel);

    // Assignment alerts come from user_notifications + FCM (deduped). Do not also
    // listen to bookings updates here — that caused a third duplicate notification.
  }

  void disposeSubscription() {
    for (final channel in _realtimeChannels) {
      SupabaseService.client.removeChannel(channel);
    }
    _realtimeChannels.clear();
    _shownNotificationKeys.clear();
  }

  Set<String> _dedupeKeysFor(Map<String, dynamic> row) {
    final keys = <String>{};
    final id = row['id']?.toString() ?? '';
    if (id.isNotEmpty) keys.add('id:$id');

    final type = (row['notification_type'] ?? row['type'])?.toString();
    final bookingId = row['booking_id']?.toString();
    final sessionId = row['session_id']?.toString();
    if (type != null &&
        type.isNotEmpty &&
        bookingId != null &&
        bookingId.isNotEmpty) {
      keys.add('event:$type:$bookingId');
    }
    if (type == 'professional_arrived' &&
        sessionId != null &&
        sessionId.isNotEmpty) {
      keys.add('event:professional_arrived_session:$sessionId');
    }

    final title = row['title']?.toString() ?? '';
    final body = row['body']?.toString() ?? '';
    if (title.isNotEmpty && body.isNotEmpty) {
      keys.add('content:$title|$body');
    }
    return keys;
  }

  bool _isRelevantBroadcast(
    Map<String, dynamic> row,
    String userId,
    Set<String> hubIds,
  ) {
    final audienceType = row['audience_type']?.toString() ?? 'all';
    final audienceId = row['audience_id']?.toString();
    if (audienceType == 'all') return true;
    if (audienceType == 'user') return audienceId == userId;
    if (audienceType == 'hub') return audienceId != null && hubIds.contains(audienceId);
    return false;
  }
}
