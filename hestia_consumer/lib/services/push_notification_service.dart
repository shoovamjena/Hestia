import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../firebase_options.dart';
import 'notifications_state.dart';
import 'supabase_service.dart';

/// Registers FCM tokens so the server can push when the app is killed/backgrounded.
///
/// Requires Firebase setup:
/// 1. `flutterfire configure` (creates `lib/firebase_options.dart` + platform files)
/// 2. Place `android/app/google-services.json`
/// 3. Set Edge secret `FCM_SERVER_KEY`
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  bool _ready = false;
  String? _currentToken;

  bool get isReady => _ready;

  Future<void> initialize() async {
    if (kIsWeb) return;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (Platform.isIOS) {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        _onOpened(initial);
      }

      messaging.onTokenRefresh.listen(_persistToken);
      final token = await messaging.getToken();
      if (token != null) {
        await _persistToken(token);
      }

      _ready = true;
      debugPrint(
        'PushNotificationService ready (FCM token registered when signed in)',
      );
    } catch (e) {
      debugPrint('PushNotificationService init error: $e');
      _ready = false;
    }
  }

  Future<void> syncTokenForCurrentUser() async {
    if (!_ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _persistToken(token);
    } catch (e) {
      debugPrint('FCM token sync failed: $e');
    }
  }

  Future<void> clearTokenOnLogout() async {
    final user = SupabaseService.currentUser;
    final token = _currentToken;
    if (user != null && token != null) {
      try {
        await SupabaseService.deleteDeviceToken(userId: user.id, token: token);
      } catch (e) {
        debugPrint('Failed to delete device token: $e');
      }
    }
    _currentToken = null;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  Future<void> _persistToken(String token) async {
    _currentToken = token;
    final user = SupabaseService.currentUser;
    if (user == null) return;
    final platform = Platform.isIOS ? 'ios' : 'android';
    try {
      await SupabaseService.upsertDeviceToken(
        userId: user.id,
        token: token,
        platform: platform,
      );
    } catch (e) {
      debugPrint('Failed to upsert device token: $e');
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        'Hestia Update';
    final body = message.notification?.body ??
        message.data['body']?.toString() ??
        '';
    final id = message.messageId ??
        message.data['notification_id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();

    await NotificationsState.instance.showLocalNotification({
      'id': id,
      'title': title,
      'body': body,
    });
  }

  void _onOpened(RemoteMessage message) {
    // Deep-link hooks can route to booking/tracking using message.data['booking_id'].
    debugPrint('FCM opened: ${message.data}');
  }
}

/// Top-level background handler (must be a top-level or static function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (_) {}
}
