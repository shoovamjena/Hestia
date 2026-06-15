import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hestia_consumer_app/config/supabase_config.dart';
import 'package:hestia_consumer_app/services/supabase_service.dart';

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
      final hubs = await client.from('hubs').select('id, name');
      print('Seeded Hubs: $hubs');
    } catch (e) {
      print('Error querying hubs: $e');
    }
    try {
      final professionals = await client.from('professionals').select('id, avg_rating');
      print('Seeded Professionals: $professionals');
    } catch (e) {
      print('Error querying professionals: $e');
    }

    final uniqueId = DateTime.now().millisecondsSinceEpoch;
    final testEmail = 'test_consumer_$uniqueId@hestia.com';
    final testPhone = '+919${uniqueId.toString().substring(uniqueId.toString().length - 9)}';
    final testPassword = 'testpassword123';
    final testName = 'Test User $uniqueId';

    print('Signing up test user: $testEmail, Phone: $testPhone');
    
    final authRes = await client.auth.signUp(
      email: testEmail,
      password: testPassword,
    );

    final userId = authRes.user?.id;
    expect(userId, isNotNull);
    print('User registered successfully in Auth. ID: $userId');

    // Wait a brief moment for the database trigger to complete inserting the users row
    await Future.delayed(const Duration(seconds: 2));

    try {
      // 3. Save User Profile (Relational Tables: users, addresses, household_members)
      print('Saving user profile in relational tables...');
      final testAddress = {
        'flat': 'Apartment 402',
        'street': 'Koramangala 4th Block',
        'city': 'Bengaluru',
        'pincode': '560034',
      };
      final testMembers = [
        {'name': 'Baby Aryan', 'age': 0, 'role': 'Newborn'},
        {'name': 'Elder Meera', 'age': 68, 'role': 'Grandmother'},
      ];

      await SupabaseService.saveUserProfile(
        id: userId!,
        fullName: testName,
        email: testEmail,
        phone: testPhone,
        primaryReason: 'New mother',
        members: testMembers,
        address: testAddress,
      );
      print('Profile saved successfully in database.');

      // 4. Retrieve User Profile and Verify details
      print('Retrieving user profile...');
      final profile = await SupabaseService.getUserProfile(userId);
      expect(profile, isNotNull);
      expect(profile!['name'], equals(testName));
      expect(profile['address']['flat'], equals('Apartment 402'));
      expect(profile['household_members'].length, equals(2));
      print('Profile retrieval verification: SUCCESS.');

      // 5. Create Booking
      print('Creating a booking...');
      await SupabaseService.createBooking(
        userId: userId,
        serviceTitle: 'Post-Delivery Care',
        selectedDate: DateTime.now().add(const Duration(days: 1)),
        selectedTime: '9:30 AM',
        selectedDuration: '1.5 hrs',
        selectedProfessionalName: 'Sunita Rao',
        repeatOption: 'Everyday',
        endsAfter: 'Jul 12',
        preferSameProfessional: true,
        totalAmount: 449,
      );
      print('Booking created successfully.');

      // 6. Fetch Active Booking
      print('Fetching active booking...');
      final activeBooking = await SupabaseService.getActiveBooking(userId);
      expect(activeBooking, isNotNull);
      expect(activeBooking!['title'], equals('Post-Delivery'));
      expect(activeBooking['amount'].toString(), contains('449'));
      print('Active booking verified: SUCCESS.');

    } finally {
      // Clean up
      try {
        print('Cleaning up database test rows...');
        await client.from('users').delete().eq('id', userId!);
        print('Cleanup complete.');
      } catch (cleanupErr) {
        print('Cleanup failed: $cleanupErr');
      }
      
      // Sign out
      await client.auth.signOut();
    }
  });
}
