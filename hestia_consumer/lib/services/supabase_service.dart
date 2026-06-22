import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  // Static variables to store in-memory mock bookings during app execution session
  static Map<String, dynamic>? _mockActiveBooking;
  static List<Map<String, dynamic>>? _mockRecentSessions;

  static void _initMockData() {
    _mockActiveBooking ??= {
      'booking_id': 'mock-booking-active-1',
      'title': 'Post-Delivery',
      'scheduled_start': DateTime.now().add(const Duration(hours: 2)),
      'amount': 1497,
      'status': 'transit',
      'caregiver_name': 'Sunita Rao',
    };

    _mockRecentSessions ??= [
      {
        'booking_id': 'mock-session-1',
        'title': 'Post-Delivery',
        'scheduled_start': DateTime.now().subtract(const Duration(hours: 1, minutes: 24)),
        'duration_hours': 3.033, // 3 hrs 2 min
        'caregiver_name': 'Sunita Rao',
        'amount': 1497,
        'status': 'completed',
        'isRated': false,
      },
      {
        'booking_id': 'mock-session-2',
        'title': 'Mobility',
        'scheduled_start': DateTime.now().subtract(const Duration(days: 7)),
        'duration_hours': 2.0,
        'caregiver_name': 'Kavita Menon',
        'amount': 898,
        'status': 'completed',
        'isRated': true,
        'rating': 5,
        'rating_punctuality': 5,
        'rating_professionalism': 5,
        'rating_quality': 5,
        'rating_tags': ['Punctual', 'Professional', 'Caring'],
      },
      {
        'booking_id': 'mock-session-3',
        'title': 'Post-Delivery',
        'scheduled_start': DateTime.now().subtract(const Duration(days: 12)),
        'duration_hours': 3.0,
        'caregiver_name': 'Sunita Rao',
        'amount': 1497,
        'status': 'completed',
        'isRated': true,
        'rating': 5,
        'rating_punctuality': 5,
        'rating_professionalism': 5,
        'rating_quality': 5,
        'rating_tags': ['Professional', 'Thorough'],
      },
    ];
  }

  /// Access to the underlying Supabase client instance
  static SupabaseClient get client => Supabase.instance.client;

  /// Returns the current authenticated User, or null if there is none
  static User? get currentUser => client.auth.currentUser;

  /// Returns the current active Session, or null if there is none
  static Session? get currentSession => client.auth.currentSession;

  /// Sign up a new user using their phone number and password as primary credentials,
  /// storing additional information such as full name and email inside the metadata.
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    return await client.auth.signUp(
      phone: phone,
      password: password,
      data: {
        'full_name': name,
        'email': email,
        'user_type': 'consumer',
      },
    );
  }

  /// Check if the user's profile is created in the database.
  /// If the query fails (e.g. table does not exist or network issue),
  /// it returns false gracefully.
  static Future<bool> checkProfileExists(String userId) async {
    try {
      final response = await client
          .from('profiles')
          .select('id')
          .eq('id', userId)
          .maybeSingle();
      return response != null;
    } catch (e) {
      // Log error and return false (default to routing to setup journey)
      // ignore: avoid_print
      print('Warning: checkProfileExists failed ($e). Defaulting to false.');
      return false;
    }
  }

  /// Create a profile record in the database for the user.
  /// Catches and logs errors gracefully so that the app won't get stuck.
  static Future<void> createProfile({
    required String id,
    required String fullName,
    String? phone,
  }) async {
    try {
      await client.from('profiles').upsert({
        'id': id,
        'full_name': fullName,
        'phone': phone,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // ignore: avoid_print
      print('Error creating profile: $e');
      rethrow;
    }
  }

  /// Sign in an existing user using their email or phone and password.
  static Future<AuthResponse> signIn({
    required String identifier,
    required String password,
  }) async {
    if (identifier.contains('@')) {
      return await client.auth.signInWithPassword(
        email: identifier,
        password: password,
      );
    } else {
      String phone = identifier.trim().replaceAll(' ', '');
      if (!phone.startsWith('+')) {
        phone = '+91$phone';
      }
      return await client.auth.signInWithPassword(
        phone: phone,
        password: password,
      );
    }
  }

  /// Send an OTP to the user's phone number for sign-in.
  static Future<void> signInWithOtp({required String phone}) async {
    await client.auth.signInWithOtp(phone: phone);
  }

  /// Verify the OTP code sent to the user's phone number.
  static Future<AuthResponse> verifyPhoneOtp({
    required String phone,
    required String token,
  }) async {
    return await client.auth.verifyOTP(
      phone: phone,
      token: token,
      type: OtpType.sms,
    );
  }

  /// Verify the email OTP code sent during sign-up.
  static Future<AuthResponse> verifyEmailSignUp({
    required String email,
    required String token,
  }) async {
    return await client.auth.verifyOTP(
      email: email,
      token: token,
      type: OtpType.signup,
    );
  }

  /// Resend the email OTP for sign-up verification.
  static Future<void> resendEmailOtp({required String email}) async {
    await client.auth.resend(
      type: OtpType.signup,
      email: email,
    );
  }

  /// Sign out the current authenticated user session.
  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  /// Upload profile JSON details to Supabase Storage
  static Future<void> uploadProfileJson({
    required String id,
    required Map<String, dynamic> profileData,
  }) async {
    try {
      final bytes = utf8.encode(jsonEncode(profileData));
      
      // Attempt to automatically create the 'profiles' storage bucket if it doesn't exist.
      try {
        await client.storage.createBucket('profiles', const BucketOptions(public: true));
      } catch (e) {
        // Ignore error if bucket already exists or if we lack permissions to create programmatically.
        // ignore: avoid_print
        print('Profiles bucket check/create status: $e');
      }

      await client.storage
          .from('profiles')
          .uploadBinary(
            '$id.json',
            Uint8List.fromList(bytes),
            fileOptions: const FileOptions(upsert: true),
          );
    } catch (e) {
      // ignore: avoid_print
      print('Error uploading profile JSON to storage: $e');
      rethrow;
    }
  }

  /// Download profile JSON details from Supabase Storage
  static Future<Map<String, dynamic>?> downloadProfileJson(String id) async {
    try {
      final bytes = await client.storage.from('profiles').download('$id.json');
      final stringContent = utf8.decode(bytes);
      return jsonDecode(stringContent) as Map<String, dynamic>;
    } catch (e) {
      // ignore: avoid_print
      print('Error downloading profile JSON from storage: $e');
      return null;
    }
  }

  /// Save user profile relational details in the database tables
  static Future<void> saveUserProfile({
    required String id,
    required String fullName,
    required String email,
    required String phone,
    required String primaryReason,
    required List<dynamic> members,
    required Map<String, dynamic> address,
  }) async {
    try {
      // 1. Update users table
      await client.from('users').upsert({
        'id': id,
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'onboarding_complete': true,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // 2. Resolve Nearest Hub ID from address
      String? hubId;
      try {
        final hubsList = await client.from('hubs').select('id, name');
        if (hubsList.isNotEmpty) {
          final addressText = '${address['street']} ${address['city']}'.toLowerCase();
          final matchingHub = hubsList.firstWhere(
            (h) => addressText.contains((h['name'] as String).split(' ').first.toLowerCase()),
            orElse: () => hubsList.first,
          );
          hubId = matchingHub['id'] as String?;
        }
      } catch (e) {
        // ignore: avoid_print
        print('Warning: Failed to resolve hub: $e');
      }

      // 3. Upsert address record
      await client.from('addresses').upsert({
        'user_id': id,
        'hub_id': hubId,
        'flat': address['flat'] ?? '',
        'street': address['street'] ?? '',
        'city': address['city'] ?? '',
        'pin_code': address['pincode'] ?? '',
        'is_primary': true,
        'zone_verified': true,
      });

      // 4. Update household members under care
      // Delete old members for consistency
      await client.from('household_members').delete().eq('user_id', id);

      if (members.isNotEmpty) {
        final membersToInsert = members.map((m) {
          final age = m['age'] as int? ?? 0;
          final dob = DateTime.now().subtract(Duration(days: age * 365)).toIso8601String().substring(0, 10);
          return {
            'user_id': id,
            'name': m['name'] ?? '',
            'relationship': m['role'] ?? '',
            'date_of_birth': dob,
            'primary_service_need': _mapReasonToServicePillar(primaryReason),
          };
        }).toList();

        await client.from('household_members').insert(membersToInsert);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error saving user profile: $e');
      rethrow;
    }
  }

  /// Save user address details in relational database and legacy JSON storage
  static Future<void> saveAddressOnly({
    required String id,
    required Map<String, dynamic> address,
  }) async {
    try {
      // 1. Resolve Nearest Hub ID from address
      String? hubId;
      try {
        final hubsList = await client.from('hubs').select('id, name');
        if (hubsList.isNotEmpty) {
          final addressText = '${address['street']} ${address['city']}'.toLowerCase();
          final matchingHub = hubsList.firstWhere(
            (h) => addressText.contains((h['name'] as String).split(' ').first.toLowerCase()),
            orElse: () => hubsList.first,
          );
          hubId = matchingHub['id'] as String?;
        }
      } catch (e) {
        // ignore: avoid_print
        print('Warning: Failed to resolve hub: $e');
      }

      // 2. Upsert address record
      await client.from('addresses').upsert({
        'user_id': id,
        'hub_id': hubId,
        'flat': address['flat'] ?? '',
        'street': address['street'] ?? '',
        'city': address['city'] ?? '',
        'pin_code': address['pincode'] ?? '',
        'is_primary': true,
        'zone_verified': true,
      });

      // 3. Update legacy profile JSON by downloading, updating address, and re-uploading
      try {
        final profileData = await downloadProfileJson(id) ?? {};
        profileData['address'] = {
          'flat': address['flat'] ?? '',
          'street': address['street'] ?? '',
          'city': address['city'] ?? '',
          'pincode': address['pincode'] ?? '',
        };
        profileData['updated_at'] = DateTime.now().toIso8601String();
        await uploadProfileJson(id: id, profileData: profileData);
      } catch (e) {
        // ignore: avoid_print
        print('Warning: Failed to update legacy JSON: $e');
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error saving user address: $e');
      rethrow;
    }
  }

  /// Fetch user profile details by querying users, addresses, and household_members
  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final userResponse = await client
          .from('users')
          .select('full_name, email, phone')
          .eq('id', userId)
          .maybeSingle();

      if (userResponse == null) return null;

      final addressResponse = await client
          .from('addresses')
          .select('flat, street, city, pin_code')
          .eq('user_id', userId)
          .eq('is_primary', true)
          .limit(1)
          .maybeSingle();

      final membersResponse = await client
          .from('household_members')
          .select('name, relationship, date_of_birth, primary_service_need')
          .eq('user_id', userId);

      final profile = {
        'name': userResponse['full_name'],
        'email': userResponse['email'],
        'phone': userResponse['phone'],
      };

      if (addressResponse != null) {
        profile['address'] = {
          'flat': addressResponse['flat'],
          'street': addressResponse['street'],
          'city': addressResponse['city'],
          'pincode': addressResponse['pin_code'],
        };
      }

      profile['household_members'] = membersResponse.map((m) {
        int age = 0;
        if (m['date_of_birth'] != null) {
          final dob = DateTime.tryParse(m['date_of_birth'] as String);
          if (dob != null) {
            age = (DateTime.now().difference(dob).inDays / 365).floor();
          }
        }
        return {
          'name': m['name'],
          'role': m['relationship'],
          'age': age,
        };
      }).toList();
      
      if (membersResponse.isNotEmpty) {
        profile['primary_reason'] = _mapServicePillarToReason(membersResponse.first['primary_service_need'] as String? ?? '');
      }

      return profile;
    } catch (e) {
      // ignore: avoid_print
      print('Error loading user profile: $e');
      return null;
    }
  }

  /// Create a new booking transaction record in the database tables
  static Future<void> createBooking({
    required String userId,
    required String serviceTitle,
    required DateTime selectedDate,
    required String selectedTime,
    required String selectedDuration,
    required String selectedProfessionalName,
    required String repeatOption,
    required String endsAfter,
    required bool preferSameProfessional,
    required int totalAmount,
    String? paymentId,
  }) async {
    _initMockData();

    // Simulate network delay to make the loader feel natural
    await Future.delayed(const Duration(milliseconds: 600));

    final parsedStart = _parseScheduledStart(selectedDate, selectedTime);
    final cleanTitle = _mapServicePillarToReason(_mapReasonToServicePillar(serviceTitle));

    _mockActiveBooking = {
      'booking_id': 'mock-booking-${DateTime.now().millisecondsSinceEpoch}',
      'title': cleanTitle,
      'scheduled_start': parsedStart,
      'amount': totalAmount,
      'status': 'pending',
      'caregiver_name': selectedProfessionalName.isNotEmpty ? selectedProfessionalName : 'Sunita Rao',
      'payment_id': paymentId,
    };
  }

  /// Retrieve the active booking details for the dashboard
  static Future<Map<String, dynamic>?> getActiveBooking(String userId) async {
    _initMockData();
    return _mockActiveBooking;
  }

  /// Retrieve the recent completed sessions/bookings for the user
  static Future<List<Map<String, dynamic>>> getRecentSessions(String userId) async {
    _initMockData();
    return _mockRecentSessions ?? [];
  }

  // Private helpers for mapping data
  static String _mapReasonToServicePillar(String reason) {
    final r = reason.toLowerCase();
    if (r.contains('mother') || r.contains('post-delivery') || r.contains('postdelivery')) {
      return 'post_delivery_care';
    }
    if (r.contains('pregnancy') || r.contains('pre-pregnancy')) {
      return 'pre_pregnancy_care';
    }
    if (r.contains('child') || r.contains('baby') || r.contains('sit')) {
      return 'certified_babysitting';
    }
    if (r.contains('mobility') || r.contains('elder') || r.contains('surgery')) {
      return 'mobility_support';
    }
    if (r.contains('bath') || r.contains('groom')) {
      return 'bathing_grooming';
    }
    if (r.contains('admin') || r.contains('concierge') || r.contains('organization')) {
      return 'admin_concierge';
    }
    return 'post_delivery_care';
  }

  static String _mapServicePillarToReason(String pillar) {
    switch (pillar) {
      case 'post_delivery_care':
        return 'Post-Delivery';
      case 'pre_pregnancy_care':
        return 'Pre-Pregnancy';
      case 'certified_babysitting':
        return 'Babysitting';
      case 'mobility_support':
        return 'Mobility';
      case 'bathing_grooming':
        return 'Bathing & Grooming';
      case 'admin_concierge':
        return 'Concierge';
      default:
        return 'Care Session';
    }
  }

  static DateTime _parseScheduledStart(DateTime date, String timeStr) {
    final cleanTime = timeStr.trim().toUpperCase();
    final isPM = cleanTime.contains('PM');
    final digits = RegExp(r'(\d+):(\d+)').firstMatch(cleanTime);
    int hour = 9;
    int minute = 0;
    if (digits != null) {
      hour = int.parse(digits.group(1)!);
      minute = int.parse(digits.group(2)!);
      if (isPM && hour < 12) {
        hour += 12;
      } else if (!isPM && hour == 12) {
        hour = 0;
      }
    }
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  /// Complete the active session, clearing active status and appending to recent sessions
  static void completeMockBooking({
    required String caregiverName,
    required String serviceTitle,
    required int amount,
  }) {
    _initMockData();
    _mockActiveBooking = null;

    _mockRecentSessions?.insert(0, {
      'booking_id': 'mock-session-${DateTime.now().millisecondsSinceEpoch}',
      'title': serviceTitle.replaceAll(' Care', ''),
      'scheduled_start': DateTime.now().subtract(const Duration(hours: 3, minutes: 2)),
      'duration_hours': 3.033, // 3 hrs 2 min
      'caregiver_name': caregiverName,
      'amount': amount,
      'status': 'completed',
      'isRated': false,
    });
  }

  /// Submit rating feedback for a completed session
  static void rateSession(
    String bookingId, {
    required int overallRating,
    required int punctuality,
    required int professionalism,
    required int qualityOfCare,
    required List<String> tags,
    String? comment,
  }) {
    _initMockData();
    final index = _mockRecentSessions?.indexWhere((s) => s['booking_id'] == bookingId) ?? -1;
    if (index != -1) {
      _mockRecentSessions![index]['isRated'] = true;
      _mockRecentSessions![index]['rating'] = overallRating;
      _mockRecentSessions![index]['rating_punctuality'] = punctuality;
      _mockRecentSessions![index]['rating_professionalism'] = professionalism;
      _mockRecentSessions![index]['rating_quality'] = qualityOfCare;
      _mockRecentSessions![index]['rating_tags'] = tags;
      _mockRecentSessions![index]['rating_comment'] = comment;
    }
  }
}
