import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'screens/splash_screen.dart';
import 'theme/colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  // Debug: Log auth state changes
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    // ignore: avoid_print
    print('DEBUG AUTH EVENT: ${data.event}, Session User: ${data.session?.user.email ?? data.session?.user.phone ?? 'None'}');
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
