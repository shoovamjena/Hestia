import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hestia_consumer_app/config/supabase_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = null;
    const MethodChannel('plugins.flutter.io/shared_preferences')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'getAll') {
        return <String, dynamic>{};
      }
      return true;
    });
  });

  test('debug signUp trigger with phone', () async {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
    final client = Supabase.instance.client;

    final uniqueId = DateTime.now().millisecondsSinceEpoch;
    final testPhone = '+919${uniqueId.toString().substring(uniqueId.toString().length - 9)}';
    final testPassword = 'testpassword123';

    try {
      print('Attempting signup with phone and data user_type consumer...');
      final authRes = await client.auth.signUp(
        phone: testPhone,
        password: testPassword,
        data: {
          'user_type': 'consumer',
          'full_name': 'Debug Phone User',
        },
      );
      print('Signup succeeded! User ID: ${authRes.user?.id}');
    } catch (e) {
      print('Signup failed: $e');
      if (e is AuthException) {
        print('AuthException message: ${e.message}');
        print('StatusCode: ${e.statusCode}');
      }
    }
  });
}
