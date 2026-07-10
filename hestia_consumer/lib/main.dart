import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'screens/splash_screen.dart';
import 'theme/colors.dart';

import 'services/notifications_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  // Initialize local phone push notifications configurations
  await NotificationsState.instance.initLocalNotifications();

  // If a persistent session exists on launch, register real-time updates immediately
  if (Supabase.instance.client.auth.currentSession != null) {
    await NotificationsState.instance.initialize();
  }

  // Debug: Log auth state changes and manage realtime notification subscriptions
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    // ignore: avoid_print
    print('DEBUG AUTH EVENT: ${data.event}, Session User: ${data.session?.user.email ?? data.session?.user.phone ?? 'None'}');
    if (data.session != null) {
      NotificationsState.instance.initialize();
    } else {
      NotificationsState.instance.disposeSubscription();
    }
  });

  runApp(const HestiaApp());
}

class HestiaApp extends StatelessWidget {
  const HestiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hestia',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: HestiaColors.primary,
        scaffoldBackgroundColor: HestiaColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: HestiaColors.primary,
          primary: HestiaColors.primary,
          surface: HestiaColors.background,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            color: HestiaColors.textDark,
            fontWeight: FontWeight.bold,
          ),
          bodyLarge: TextStyle(
            color: HestiaColors.textMedium,
          ),
          bodyMedium: TextStyle(
            color: HestiaColors.textMedium,
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
