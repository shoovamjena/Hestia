import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hestia_consumer_app/config/supabase_config.dart';
import 'package:hestia_consumer_app/services/supabase_service.dart';

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

  test('scan professionals table authenticated', () async {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
    final client = Supabase.instance.client;

    final uniqueId = DateTime.now().millisecondsSinceEpoch;
    final testEmail = 'inspect_profs_$uniqueId@hestia.com';
    final testPhone = '+919${uniqueId.toString().substring(uniqueId.toString().length - 9)}';
    final testPassword = 'testpassword123';
    final testName = 'Inspect User';

    try {
      print('Registering test user: $testEmail');
      await SupabaseService.signUp(
        email: testEmail,
        password: testPassword,
        name: testName,
        phone: testPhone,
      );

      print('Authenticating via verifyEmailSignUp...');
      await SupabaseService.verifyEmailSignUp(email: testEmail, token: '123456');

      print('Querying professionals table with authenticated session...');
      final profs = await client.from('professionals').select('*');
      print('Authenticated Professionals list: $profs');

      // Cleanup
      final user = client.auth.currentUser;
      if (user != null) {
        await client.from('users').delete().eq('id', user.id);
      }
    } catch (e) {
      print('Error during authenticated scan: $e');
    } finally {
      await client.auth.signOut();
    }
  });
}
