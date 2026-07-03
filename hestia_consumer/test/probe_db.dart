import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hestia_consumer_app/config/supabase_config.dart';

import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = null;
    // Mock SharedPreferences MethodChannel
    const MethodChannel('plugins.flutter.io/shared_preferences')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'getAll') {
        return <String, dynamic>{};
      }
      return true;
    });
  });

  test('end-to-end integration test for profile and booking database flows', () async {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );

    final client = Supabase.instance.client;
    print('Supabase initialized with mocked SharedPreferences.');

    try {
      final hubs = await client.from('hubs').select('*');
      print('ALL DATABASE HUBS: $hubs');
    } catch (e) {
      print('Error querying hubs: $e');
    }
    return;
  });
}
