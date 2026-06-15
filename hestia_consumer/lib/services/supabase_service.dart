import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
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
  }) async {
    try {
      // 1. Retrieve user address and hub
      final address = await client
          .from('addresses')
          .select('id, hub_id')
          .eq('user_id', userId)
          .eq('is_primary', true)
          .limit(1)
          .maybeSingle();

      if (address == null) {
        throw Exception('User has no primary address verified in database.');
      }

      final addressId = address['id'] as String;
      final hubId = address['hub_id'] as String? ?? '00000000-0000-0000-0000-000000000010';

      // 2. Retrieve first household member ID
      final member = await client
          .from('household_members')
          .select('id')
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle();
      final memberId = member?['id'] as String?;

      // 3. Resolve caregiver professional ID
      final profId = _resolveProfessionalId(selectedProfessionalName);

      // 4. Handle recurrence schedules if necessary
      String? recurrenceId;
      if (repeatOption != 'One-time') {
        final recurrenceFreq = repeatOption.toLowerCase().contains('week') ? 'weekly' : 'daily';
        final endDate = _parseEndDate(endsAfter, selectedDate);
        
        final recRes = await client.from('recurrence_schedules').insert({
          'user_id': userId,
          'frequency': recurrenceFreq,
          'end_date': endDate.toIso8601String().substring(0, 10),
          'prefer_same_professional': preferSameProfessional,
          'is_paused': false,
        }).select('id').single();
        
        recurrenceId = recRes['id'] as String;
      }

      // 5. Create booking record
      final scheduledStart = _parseScheduledStart(selectedDate, selectedTime);
      final durationHours = _parseDurationHours(selectedDuration);
      final pillar = _mapReasonToServicePillar(serviceTitle);

      final bookingRes = await client.from('bookings').insert({
        'user_id': userId,
        'household_member_id': memberId,
        'address_id': addressId,
        'hub_id': hubId,
        'professional_id': profId,
        'service_pillar': pillar,
        'scheduled_start': scheduledStart.toIso8601String(),
        'duration_hours': durationHours,
        'status': 'pending',
        'is_recurring': repeatOption != 'One-time',
        'recurrence_id': recurrenceId,
        'total_amount': totalAmount,
      }).select('id').single();

      final bookingId = bookingRes['id'] as String;

      // 6. Automatically create the first session visit for this booking
      if (profId != null) {
        final sessionRes = await client.from('sessions').insert({
          'booking_id': bookingId,
          'professional_id': profId,
          'status': 'transit',
        }).select('id').single();

        final sessionId = sessionRes['id'] as String;

        // 7. Create the invoice record
        await client.from('invoices').insert({
          'session_id': sessionId,
          'user_id': userId,
          'amount': totalAmount,
          'status': 'pending',
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error creating booking: $e');
      rethrow;
    }
  }

  /// Retrieve the active booking details for the dashboard
  static Future<Map<String, dynamic>?> getActiveBooking(String userId) async {
    try {
      final res = await client
          .from('bookings')
          .select('id, service_pillar, scheduled_start, total_amount, status, professionals(full_name)')
          .eq('user_id', userId)
          .or('status.eq.pending,status.eq.confirmed,status.eq.active')
          .order('scheduled_start', ascending: true)
          .limit(1)
          .maybeSingle();

      if (res != null) {
        final pillar = res['service_pillar'] as String;
        final scheduledStart = DateTime.tryParse(res['scheduled_start'] as String) ?? DateTime.now();
        final professionalsMap = res['professionals'] as Map<String, dynamic>?;
        final caregiverName = professionalsMap?['full_name'] as String? ?? 'Assigned Caregiver';
        
        return {
          'booking_id': res['id'],
          'title': _mapServicePillarToReason(pillar),
          'scheduled_start': scheduledStart,
          'amount': res['total_amount'],
          'status': res['status'],
          'caregiver_name': caregiverName,
        };
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('Error getting active booking: $e');
      return null;
    }
  }

  /// Retrieve the recent completed sessions/bookings for the user
  static Future<List<Map<String, dynamic>>> getRecentSessions(String userId) async {
    try {
      final res = await client
          .from('bookings')
          .select('id, service_pillar, scheduled_start, duration_hours, total_amount, status, professionals(full_name)')
          .eq('user_id', userId)
          .eq('status', 'completed')
          .order('scheduled_start', ascending: false)
          .limit(5);

      return (res as List).map((item) {
        final map = item as Map<String, dynamic>;
        final pillar = map['service_pillar'] as String;
        final scheduledStart = DateTime.tryParse(map['scheduled_start'] as String) ?? DateTime.now();
        final professionalsMap = map['professionals'] as Map<String, dynamic>?;
        final caregiverName = professionalsMap?['full_name'] as String? ?? 'Caregiver';
        final durationHours = map['duration_hours'] as num? ?? 1;

        return {
          'booking_id': map['id'],
          'title': _mapServicePillarToReason(pillar),
          'scheduled_start': scheduledStart,
          'duration_hours': durationHours,
          'caregiver_name': caregiverName,
          'amount': map['total_amount'],
          'status': map['status'],
        };
      }).toList();
    } catch (e) {
      // ignore: avoid_print
      print('Error getting recent sessions: $e');
      return [];
    }
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

  static String? _resolveProfessionalId(String name) {
    final n = name.toLowerCase();
    if (n.contains('sunita')) return '00000000-0000-0000-0000-000000000001';
    if (n.contains('kavita')) return '00000000-0000-0000-0000-000000000002';
    if (n.contains('anjali')) return '00000000-0000-0000-0000-000000000003';
    return null;
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

  static double _parseDurationHours(String durationStr) {
    final clean = durationStr.toLowerCase();
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(clean);
    if (match != null) {
      return double.parse(match.group(1)!);
    }
    return 1.0;
  }

  static DateTime _parseEndDate(String endsAfterStr, DateTime startDate) {
    try {
      final clean = endsAfterStr.trim().toLowerCase();
      final months = [
        'jan', 'feb', 'mar', 'apr', 'may', 'jun',
        'jul', 'aug', 'sep', 'oct', 'nov', 'dec'
      ];
      final monthMatch = months.indexWhere((m) => clean.contains(m));
      final numMatch = RegExp(r'(\d+)').firstMatch(clean);
      if (monthMatch != -1 && numMatch != null) {
        final day = int.parse(numMatch.group(1)!);
        final month = monthMatch + 1;
        int year = startDate.year;
        if (month < startDate.month) {
          year += 1;
        }
        return DateTime(year, month, day);
      }
    } catch (_) {}
    return startDate.add(const Duration(days: 30));
  }
}
