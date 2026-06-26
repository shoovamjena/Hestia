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

  test('scan addresses table for hub_id', () async {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
    final client = Supabase.instance.client;

    try {
      print('Querying addresses table...');
      final addresses = await client.from('addresses').select('id, user_id, hub_id').limit(20);
      print('Addresses list: $addresses');
      
      final nonNullHub = addresses.firstWhere(
        (a) => a['hub_id'] != null,
        orElse: () => <String, dynamic>{},
      );
      print('Found address with non-null hub: $nonNullHub');
    } catch (e) {
      print('Error querying addresses: $e');
    }
  });
}
