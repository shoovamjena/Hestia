import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
        // Deep-link handling can be added here when needed.
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

  Future<void> showLocalNotification(Map<String, dynamic> row) async {
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

    await _localNotifications?.show(id, title, body, details);
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
            await _handleRealtimeNotification(payload.newRecord);
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
              await _handleRealtimeNotification(row);
            }
          },
        )
        .subscribe();
    _realtimeChannels.add(hubBroadcastChannel);

    final arrivalChannel = SupabaseService.client
        .channel('consumer_arrivals_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'sessions',
          callback: (payload) async {
            final row = payload.newRecord;
            final status = row['status']?.toString().toLowerCase();
            final bookingId = row['booking_id']?.toString();
            final sessionId = row['id']?.toString();
            if (status != 'arrived' || bookingId == null || sessionId == null) {
              return;
            }

            if (!_watchedBookingIds.contains(bookingId)) {
              _watchedBookingIds = await SupabaseService.getUserBookingIds(user.id);
              if (!_watchedBookingIds.contains(bookingId)) {
                return;
              }
            }

            final bookingData = await SupabaseService.getBookingStatus(bookingId);
            final caregiverName =
                bookingData?['caregiver_name']?.toString() ?? 'Your professional';
            await _handleRealtimeNotification({
              'id': 'arrival_$sessionId',
              'title': 'Professional arrived',
              'body': '$caregiverName has confirmed arrival at your address.',
            });
          },
        )
        .subscribe();
    _realtimeChannels.add(arrivalChannel);

    // When a professional is assigned (T-45 job), show a local alert if app is open.
    // Killed/background delivery is handled by FCM via send-push-notification.
    final assignChannel = SupabaseService.client
        .channel('consumer_assignments_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'bookings',
          callback: (payload) async {
            final row = payload.newRecord;
            final old = payload.oldRecord;
            final bookingId = row['id']?.toString();
            final newPro = row['professional_id']?.toString();
            final oldPro = old['professional_id']?.toString();
            if (bookingId == null || newPro == null || newPro.isEmpty) return;
            if (oldPro != null && oldPro.isNotEmpty) return;
            if (row['user_id']?.toString() != user.id) {
              if (!_watchedBookingIds.contains(bookingId)) {
                _watchedBookingIds =
                    await SupabaseService.getUserBookingIds(user.id);
                if (!_watchedBookingIds.contains(bookingId)) return;
              }
            }

            final bookingData =
                await SupabaseService.getBookingStatus(bookingId);
            final caregiverName =
                bookingData?['caregiver_name']?.toString() ??
                    'Your professional';
            await _handleRealtimeNotification({
              'id': 'assigned_${bookingId}_$newPro',
              'title': 'Professional assigned',
              'body':
                  '$caregiverName will arrive for your upcoming booking.',
            });
          },
        )
        .subscribe();
    _realtimeChannels.add(assignChannel);
  }

  void disposeSubscription() {
    for (final channel in _realtimeChannels) {
      SupabaseService.client.removeChannel(channel);
    }
    _realtimeChannels.clear();
    _shownNotificationKeys.clear();
  }

  Future<void> _handleRealtimeNotification(Map<String, dynamic> row) async {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty || _shownNotificationKeys.contains(id)) return;
    _shownNotificationKeys.add(id);
    await showLocalNotification(row);
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
