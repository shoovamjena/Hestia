import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  // Static variable to store signup name in-memory during phone OTP signup flow
  static String? pendingSignUpName;
  static String? pendingSignUpPassword;

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

  /// Sign up a new user using their email and password,
  /// storing additional information such as full name and phone inside the metadata.
  static Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    return await client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': name,
        'phone': phone,
        'phone_verified': false,
        'user_type': 'consumer',
      },
    );
  }

  /// Check if the user's phone is verified.
  static bool isPhoneVerified() {
    final user = currentUser;
    if (user == null) return false;
    if (user.phoneConfirmedAt != null) return true;
    return user.userMetadata?['phone_verified'] == true;
  }

  /// Update phone verification status in user metadata and profile JSON.
  static Future<void> updatePhoneVerifiedStatus(bool verified) async {
    final user = currentUser;
    if (user == null) return;

    // 1. Update user metadata
    await client.auth.updateUser(
      UserAttributes(
        data: {
          'phone_verified': verified,
        },
      ),
    );

    // 2. Update profile JSON
    try {
      final profileData = await downloadProfileJson(user.id) ?? {};
      profileData['phone_verified'] = verified;
      await uploadProfileJson(id: user.id, profileData: profileData);
    } catch (_) {
      // Ignore fallback JSON storage failures
    }
  }

  /// Send phone verification OTP to update the phone number for an already authenticated user.
  static Future<void> sendPhoneVerificationOtp({required String phone}) async {
    final user = currentUser;
    if (user == null) return;
    
    String cleanPhone = phone.trim().replaceAll(' ', '');
    if (cleanPhone.endsWith('8144684265')) {
      await client.auth.updateUser(
        UserAttributes(phone: phone),
      );
    } else {
      // Simulate delay for Twilio trial sandbox bypass
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Check if the user's profile is created in the database.
  /// If the query fails (e.g. table does not exist or network issue),
  /// it returns false gracefully.
  static Future<bool> checkProfileExists(String userId) async {
    try {
      final response = await client
          .from('users')
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

  /// Check if the user's profile is complete by checking if their user_id is in the household_members table.
  static Future<bool> isProfileComplete(String userId) async {
    try {
      final memberRows = await client
          .from('household_members')
          .select('id')
          .eq('user_id', userId)
          .limit(1);
      return memberRows.isNotEmpty;
    } catch (e) {
      // ignore: avoid_print
      print('Warning: isProfileComplete check failed: $e');
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
      String? dbPhone = phone;
      if (dbPhone != null && dbPhone.trim().isEmpty) {
        dbPhone = null;
      }

      await client.from('users').upsert({
        'id': id,
        'full_name': fullName,
        'phone': dbPhone,
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
    String cleanPhone = phone.trim().replaceAll(' ', '');
    if (cleanPhone.endsWith('8144684265')) {
      await client.auth.signInWithOtp(phone: phone);
    } else {
      // Simulate delay for Twilio trial sandbox bypass
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Send an OTP to the user's email address for sign-in.
  static Future<void> signInWithEmailOtp({required String email}) async {
    await client.auth.signInWithOtp(email: email);
  }

  /// Verify the OTP code sent to the user's phone number.
  static Future<AuthResponse> verifyPhoneOtp({
    required String phone,
    required String token,
  }) async {
    final user = currentUser;
    String cleanPhone = phone.trim().replaceAll(' ', '').replaceAll('+', '');
    
    if (user != null) {
      // SCENARIO A: User is already logged in (verifying phone from profile screen)
      if (cleanPhone.endsWith('8144684265')) {
        final response = await client.auth.verifyOTP(
          phone: phone,
          token: token,
          type: OtpType.phoneChange,
        );
        try {
          await client.from('users').update({
            'phone': phone,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', user.id);
        } catch (_) {}
        return response;
      } else {
        if (token == '123456') {
          // Bypass: Update metadata and users table directly without changing current session
          await client.auth.updateUser(
            UserAttributes(
              data: {
                'phone_verified': true,
                'phone': phone,
              },
            ),
          );
          try {
            await client.from('users').update({
              'phone': phone,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', user.id);
          } catch (_) {}
          return AuthResponse(session: currentSession, user: currentUser);
        } else {
          throw const AuthException('Invalid OTP. Use 123456 to bypass Sandbox restrictions.');
        }
      }
    } else {
      // SCENARIO B: User is NOT logged in (sign-in or register flow)
      if (cleanPhone.endsWith('8144684265')) {
        return await client.auth.verifyOTP(
          phone: phone,
          token: token,
          type: OtpType.sms,
        );
      } else {
        if (token == '123456') {
          // Bypass logic for Twilio Sandbox: authenticate via background dummy account
          final email = 'phone_$cleanPhone@hestia.com';
          final password = 'bypass_${cleanPhone}_password';
          try {
            // Attempt to sign in
            return await client.auth.signInWithPassword(
              email: email,
              password: password,
            );
          } catch (_) {
            // If sign in fails, sign up the bypass user
            final response = await client.auth.signUp(
              email: email,
              password: password,
              data: {
                'phone': phone,
                'phone_verified': true,
                'user_type': 'consumer',
              },
            );
            return response;
          }
        } else {
          throw const AuthException('Invalid OTP. Use 123456 to bypass Sandbox restrictions.');
        }
      }
    }
  }

  /// Verify the OTP code sent to the user's email for sign-in.
  static Future<AuthResponse> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    return await client.auth.verifyOTP(
      email: email,
      token: token,
      type: OtpType.email,
    );
  }

  /// Verify the email OTP code sent during sign-up.
  static Future<AuthResponse> verifyEmailSignUp({
    required String email,
    required String token,
  }) async {
    if (token == '123456') {
      // Bypass logic: sign in the user using their pending password
      final password = pendingSignUpPassword ?? 'bypass_password';
      try {
        final response = await client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        
        final user = response.user;
        if (user != null) {
          try {
            await client.from('users').update({
              'email_verified': true,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', user.id);
          } catch (_) {}
        }
        return response;
      } catch (e) {
        // If sign in fails (e.g. Email not confirmed), we can sign in using a bypass dummy account
        final cleanEmail = email.replaceAll('@', '_').replaceAll('.', '_');
        final bypassEmail = 'bypass_$cleanEmail@hestia.com';
        final bypassPassword = 'bypass_${cleanEmail}_password';
        try {
          final response = await client.auth.signInWithPassword(
            email: bypassEmail,
            password: bypassPassword,
          );
          final user = response.user;
          if (user != null) {
            try {
              await client.from('users').update({
                'email_verified': true,
                'updated_at': DateTime.now().toIso8601String(),
              }).eq('id', user.id);
            } catch (_) {}
          }
          return response;
        } catch (_) {
          final response = await client.auth.signUp(
            email: bypassEmail,
            password: bypassPassword,
            data: {
              'email_verified': true,
              'user_type': 'consumer',
            },
          );
          final user = response.user;
          if (user != null) {
            try {
              await client.from('users').update({
                'email_verified': true,
                'updated_at': DateTime.now().toIso8601String(),
              }).eq('id', user.id);
            } catch (_) {}
          }
          return response;
        }
      }
    } else {
      final response = await client.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.signup,
      );
      
      final user = response.user;
      if (user != null) {
        try {
          await client.from('users').update({
            'email_verified': true,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', user.id);
        } catch (_) {}
      }
      return response;
    }
  }

  /// Resend the email OTP for sign-up verification.
  static Future<void> resendEmailOtp({required String email}) async {
    await client.auth.resend(
      type: OtpType.signup,
      email: email,
    );
  }

  /// Resend the email OTP for sign-in.
  static Future<void> resendSignInEmailOtp({required String email}) async {
    await client.auth.resend(
      type: OtpType.email,
      email: email,
    );
  }

  /// Sign out the current authenticated user session.
  static Future<void> signOut() async {
    try {
      await client.auth.signOut().timeout(const Duration(milliseconds: 1000));
    } catch (_) {
      // Catch network errors, timeouts, etc. to prevent hanging.
      // The Supabase client clears local storage/session automatically.
    }
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
    String? phone,
    required String primaryReason,
    required List<dynamic> members,
    required Map<String, dynamic> address,
  }) async {
    try {
      String? dbPhone = phone;
      if (dbPhone != null && dbPhone.trim().isEmpty) {
        dbPhone = null;
      }

      // 1. Update users table
      await client.from('users').upsert({
        'id': id,
        'full_name': fullName,
        'email': email,
        'phone': dbPhone,
        'onboarding_complete': true,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // 2. Resolve Nearest Hub ID from address
      String? hubId;
      try {
        var hubsList = await client.from('hubs').select('id, name');
        if (hubsList.isEmpty) {
          try {
            final newHub = await client.from('hubs').insert({
              'name': 'Default Testing Hub',
              'address': 'Default Address',
            }).select('id, name').single();
            hubsList = [newHub];
          } catch (e) {
            // ignore: avoid_print
            print('Warning: Failed to create default hub in saveUserProfile: $e');
          }
        }
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

      // Set all existing addresses to non-primary first
      try {
        await client
            .from('addresses')
            .update({'is_primary': false})
            .eq('user_id', id);
      } catch (_) {}

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

      // Set all existing addresses to non-primary first
      try {
        await client
            .from('addresses')
            .update({'is_primary': false})
            .eq('user_id', id);
      } catch (_) {}

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
          .select('id, name, relationship, date_of_birth, primary_service_need')
          .eq('user_id', userId);

      final profile = {
        'name': userResponse['full_name'],
        'email': userResponse['email'],
        'phone': userResponse['phone'],
        'phone_verified': isPhoneVerified(),
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
          'id': m['id'],
          'name': m['name'],
          'role': m['relationship'],
          'age': age,
          'dob': m['date_of_birth'],
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
    String? householdMemberId,
  }) async {
    // 1. Fetch primary address for the user
    final addressRes = await client
        .from('addresses')
        .select('id, hub_id')
        .eq('user_id', userId)
        .eq('is_primary', true)
        .limit(1)
        .maybeSingle();

    final backupAddressRes = addressRes ??
        await client
            .from('addresses')
            .select('id, hub_id')
            .eq('user_id', userId)
            .limit(1)
            .maybeSingle();

    final addressId = backupAddressRes?['id'] as String?;
    final hubId = backupAddressRes?['hub_id'] as String?;

    if (addressId == null) {
      throw Exception('No address found for user. Please set an address first.');
    }

    String finalHubId = hubId ?? '';
    if (finalHubId.isEmpty) {
      try {
        final hubRes = await client.from('hubs').select('id').limit(1).maybeSingle();
        finalHubId = hubRes?['id'] as String? ?? '';
      } catch (_) {}
    }

    // Auto-create a default hub if none exists in the database
    if (finalHubId.isEmpty) {
      try {
        final newHubRes = await client.from('hubs').insert({
          'name': 'Default Testing Hub',
          'address': 'Default Address',
        }).select('id').single();
        finalHubId = newHubRes['id'] as String? ?? '';
      } catch (e) {
        // ignore: avoid_print
        print('Warning: Failed to auto-create testing hub: $e');
      }
    }

    // Fallback 1: Resolve hub_id from any professional in the database
    if (finalHubId.isEmpty) {
      try {
        final anyProf = await client.from('professionals').select('hub_id').limit(1).maybeSingle();
        finalHubId = anyProf?['hub_id'] as String? ?? '';
      } catch (_) {}
    }

    // Fallback 2: Resolve hub_id from selected professional by name
    if (finalHubId.isEmpty && selectedProfessionalName.isNotEmpty) {
      try {
        final profRes = await client
            .from('professionals')
            .select('hub_id')
            .eq('full_name', selectedProfessionalName)
            .limit(1)
            .maybeSingle();
        finalHubId = profRes?['hub_id'] as String? ?? '';
      } catch (_) {}
    }

    // Fallback 3: Standard dummy UUID if all else fails
    if (finalHubId.isEmpty) {
      finalHubId = '00000000-0000-0000-0000-000000000000';
    }

    // 2. Fetch household member if not provided
    String? finalMemberId = householdMemberId;
    if (finalMemberId == null || finalMemberId.isEmpty) {
      final memberRes = await client
          .from('household_members')
          .select('id')
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle();
      finalMemberId = memberRes?['id'] as String?;
    }

    // 3. Resolve professional ID
    String? professionalId;
    if (selectedProfessionalName.isNotEmpty) {
      try {
        final profRes = await client
            .from('professionals')
            .select('id')
            .eq('full_name', selectedProfessionalName)
            .limit(1)
            .maybeSingle();
        professionalId = profRes?['id'] as String?;
      } catch (e) {
        // ignore
      }
    }

    if (professionalId == null) {
      try {
        var query = client.from('professionals').select('id');
        if (finalHubId.isNotEmpty) {
          query = query.eq('hub_id', finalHubId);
        }
        final profs = await query;
        if (profs.isNotEmpty) {
          professionalId = profs.first['id'] as String?;
        }
      } catch (e) {
        // ignore
      }
    }

    if (professionalId == null) {
      try {
        final profs = await client.from('professionals').select('id').limit(1);
        if (profs.isNotEmpty) {
          professionalId = profs.first['id'] as String?;
        }
      } catch (e) {
        // ignore
      }
    }

    // 4. Parse duration in hours
    double durationHours = 0.0;
    final dur = selectedDuration.toLowerCase();
    final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(dur);
    if (numMatch != null) {
      durationHours = double.parse(numMatch.group(1)!);
    } else {
      durationHours = 3.0; // fallback
    }

    // 5. Check recurrence schedule
    final isRecurring = repeatOption != 'Once' && repeatOption != 'One-time';
    String? recurrenceId;
    if (isRecurring) {
      final freq = (repeatOption.toLowerCase() == 'daily' || repeatOption.toLowerCase() == 'everyday') ? 'daily' : 'weekly';
      List<int> days = [selectedDate.weekday];
      final endDate = selectedDate.add(const Duration(days: 90)).toIso8601String().substring(0, 10);

      final recResponse = await client.from('recurrence_schedules').insert({
        'user_id': userId,
        'frequency': freq,
        'days_of_week': days,
        'end_date': endDate,
        'prefer_same_professional': preferSameProfessional,
      }).select('id').single();

      recurrenceId = recResponse['id'] as String?;
    }

    // 6. Insert booking
    final parsedStart = _parseScheduledStart(selectedDate, selectedTime);
    final servicePillar = _mapReasonToServicePillar(serviceTitle);

    final bookingRes = await client.from('bookings').insert({
      'user_id': userId,
      'household_member_id': (finalMemberId == null || finalMemberId.isEmpty) ? null : finalMemberId,
      'address_id': addressId,
      'hub_id': finalHubId,
      'professional_id': professionalId,
      'service_pillar': servicePillar,
      'scheduled_start': parsedStart.toIso8601String(),
      'duration_hours': durationHours,
      'status': 'confirmed',
      'is_recurring': isRecurring,
      'recurrence_id': recurrenceId,
      'total_amount': totalAmount,
    }).select('id').single();

    final bookingId = bookingRes['id'] as String;

    // 7. Insert active session if professional assigned
    if (professionalId != null) {
      try {
        final sessionRes = await client.from('sessions').insert({
          'booking_id': bookingId,
          'professional_id': professionalId,
          'status': 'transit',
        }).select('id').single();

        final sessionId = sessionRes['id'] as String;

        // Insert dummy locations for tracking
        await client.from('professional_locations').insert([
          {
            'session_id': sessionId,
            'professional_id': professionalId,
            'coordinates': {
              'type': 'Point',
              'coordinates': [77.6412, 12.9275]
            },
            'recorded_at': DateTime.now().toIso8601String(),
          },
          {
            'session_id': sessionId,
            'professional_id': professionalId,
            'coordinates': {
              'type': 'Point',
              'coordinates': [77.6400, 12.9300]
            },
            'recorded_at': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
          }
        ]);

        // Insert dummy activity logs
        await client.from('activity_logs').insert([
          {
            'session_id': sessionId,
            'professional_id': professionalId,
            'activity_type': 'Feeding support',
            'note': 'Breastfeeding positioning assisted, mother resting',
            'logged_at': DateTime.now().subtract(const Duration(minutes: 20)).toIso8601String(),
          },
          {
            'session_id': sessionId,
            'professional_id': professionalId,
            'activity_type': 'Meal assistance',
            'note': 'Light breakfast prepared for mother',
            'logged_at': DateTime.now().subtract(const Duration(minutes: 40)).toIso8601String(),
          },
          {
            'session_id': sessionId,
            'professional_id': professionalId,
            'activity_type': 'Session start',
            'note': 'Session started. Checked on patient, settled well',
            'logged_at': DateTime.now().subtract(const Duration(minutes: 60)).toIso8601String(),
          },
        ]);
      } catch (e) {
        // ignore: avoid_print
        print('Warning: Failed to insert dummy session/tracking data: $e');
      }
    }
  }

  /// Retrieve the active booking details for the dashboard
  static Future<Map<String, dynamic>?> getActiveBooking(String userId) async {
    try {
      final response = await client
          .from('bookings')
          .select('id, service_pillar, scheduled_start, total_amount, status, professional_id, professionals(full_name)')
          .eq('user_id', userId)
          .inFilter('status', ['pending', 'confirmed', 'active'])
          .order('scheduled_start', ascending: true)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;

      final bookingId = response['id'] as String;
      final servicePillar = response['service_pillar'] as String;
      final scheduledStartStr = response['scheduled_start'] as String;
      final totalAmount = response['total_amount'] != null ? (response['total_amount'] as num).toInt() : 0;
      final status = response['status'] as String;
      
      String caregiverName = 'Sunita Rao';
      if (response['professionals'] != null) {
        caregiverName = (response['professionals'] as Map<String, dynamic>)['full_name'] as String? ?? caregiverName;
      }

      String activeStatus = status;
      String? sessionId;
      String? arrivalConfirmedAtStr;
      try {
        final sessionRes = await client
            .from('sessions')
            .select('id, status, arrival_confirmed_at')
            .eq('booking_id', bookingId)
            .limit(1)
            .maybeSingle();
        if (sessionRes != null) {
          activeStatus = sessionRes['status'] as String;
          sessionId = sessionRes['id'] as String;
          arrivalConfirmedAtStr = sessionRes['arrival_confirmed_at'] as String?;
        }
      } catch (e) {
        // ignore
      }

      return {
        'booking_id': bookingId,
        'session_id': sessionId,
        'title': _mapServicePillarToReason(servicePillar),
        'scheduled_start': DateTime.parse(scheduledStartStr),
        'amount': totalAmount,
        'status': activeStatus,
        'caregiver_name': caregiverName,
        'arrival_requested': arrivalConfirmedAtStr != null && activeStatus == 'transit',
      };
    } catch (e) {
      // ignore: avoid_print
      print('Error in getActiveBooking: $e');
      return null;
    }
  }

  /// Request session start, updating arrival_confirmed_at to now
  static Future<void> requestSessionStart(String bookingId) async {
    try {
      await client
          .from('sessions')
          .update({
            'arrival_confirmed_at': DateTime.now().toIso8601String(),
          })
          .eq('booking_id', bookingId);
    } catch (e) {
      // ignore: avoid_print
      print('Error in requestSessionStart: $e');
    }
  }

  /// Retrieve all active/upcoming bookings/sessions (pending, confirmed, active) for the user
  static Future<List<Map<String, dynamic>>> getUpcomingBookings(String userId) async {
    try {
      final response = await client
          .from('bookings')
          .select('id, service_pillar, scheduled_start, total_amount, status, professional_id, professionals(full_name)')
          .eq('user_id', userId)
          .inFilter('status', ['pending', 'confirmed', 'active'])
          .order('scheduled_start', ascending: true);

      final List<Map<String, dynamic>> list = [];
      for (final item in response) {
        final bookingId = item['id'] as String;
        final servicePillar = item['service_pillar'] as String;
        final scheduledStartStr = item['scheduled_start'] as String;
        final totalAmount = item['total_amount'] != null ? (item['total_amount'] as num).toInt() : 0;
        final status = item['status'] as String;

        String caregiverName = 'Sunita Rao';
        if (item['professionals'] != null) {
          caregiverName = (item['professionals'] as Map<String, dynamic>)['full_name'] as String? ?? caregiverName;
        }

        String activeStatus = status;
        String? sessionId;
        String? arrivalConfirmedAtStr;
        try {
          final sessionRes = await client
              .from('sessions')
              .select('id, status, arrival_confirmed_at')
              .eq('booking_id', bookingId)
              .limit(1)
              .maybeSingle();
          if (sessionRes != null) {
            activeStatus = sessionRes['status'] as String;
            sessionId = sessionRes['id'] as String;
            arrivalConfirmedAtStr = sessionRes['arrival_confirmed_at'] as String?;
          }
        } catch (e) {
          // ignore
        }

        list.add({
          'booking_id': bookingId,
          'session_id': sessionId,
          'title': _mapServicePillarToReason(servicePillar),
          'scheduled_start': DateTime.parse(scheduledStartStr),
          'amount': totalAmount,
          'status': activeStatus,
          'caregiver_name': caregiverName,
          'arrival_requested': arrivalConfirmedAtStr != null && activeStatus == 'transit',
        });
      }
      return list;
    } catch (e) {
      // ignore: avoid_print
      print('Error in getUpcomingBookings: $e');
      return [];
    }
  }

  /// Retrieve the recent completed sessions/bookings for the user
  static Future<List<Map<String, dynamic>>> getRecentSessions(String userId) async {
    try {
      final response = await client
          .from('bookings')
          .select('id, service_pillar, scheduled_start, total_amount, status, professional_id, professionals(full_name)')
          .eq('user_id', userId)
          .eq('status', 'completed')
          .order('scheduled_start', ascending: false);

      final List<Map<String, dynamic>> list = [];
      for (final item in response) {
        final bookingId = item['id'] as String;
        final servicePillar = item['service_pillar'] as String;
        final scheduledStartStr = item['scheduled_start'] as String;
        final totalAmount = item['total_amount'] != null ? (item['total_amount'] as num).toInt() : 0;
        
        String caregiverName = 'Sunita Rao';
        if (item['professionals'] != null) {
          caregiverName = (item['professionals'] as Map<String, dynamic>)['full_name'] as String? ?? caregiverName;
        }

        bool isRated = false;
        int rating = 5;
        int punctuality = 5;
        int professionalism = 5;
        int quality = 5;
        List<String> tags = [];
        String comment = '';
        String? sessionId;

        try {
          final sessionRes = await client
              .from('sessions')
              .select('id')
              .eq('booking_id', bookingId)
              .limit(1)
              .maybeSingle();
          if (sessionRes != null) {
            sessionId = sessionRes['id'] as String;
            final feedbackRes = await client
                .from('session_feedback')
                .select('rating, punctuality, professionalism, quality, comment')
                .eq('session_id', sessionId)
                .eq('user_id', userId)
                .limit(1)
                .maybeSingle();

            if (feedbackRes != null) {
              isRated = true;
              rating = feedbackRes['rating'] as int? ?? 5;
              punctuality = feedbackRes['punctuality'] as int? ?? 5;
              professionalism = feedbackRes['professionalism'] as int? ?? 5;
              quality = feedbackRes['quality'] as int? ?? 5;
              comment = feedbackRes['comment'] as String? ?? '';
              
              if (punctuality == 5) tags.add('Punctual');
              if (professionalism == 5) tags.add('Professional');
              if (quality == 5) tags.add('Caring');
            }
          }
        } catch (e) {
          // ignore
        }

        list.add({
          'booking_id': bookingId,
          'session_id': sessionId,
          'title': _mapServicePillarToReason(servicePillar),
          'scheduled_start': DateTime.parse(scheduledStartStr),
          'duration_hours': 3.0,
          'caregiver_name': caregiverName,
          'amount': totalAmount,
          'status': 'completed',
          'isRated': isRated,
          'rating': rating,
          'rating_punctuality': punctuality,
          'rating_professionalism': professionalism,
          'rating_quality': quality,
          'rating_tags': tags,
          'rating_comment': comment,
        });
      }

      return list;
    } catch (e) {
      // ignore: avoid_print
      print('Error in getRecentSessions: $e');
      return [];
    }
  }

  /// Retrieve the activity logs for a session from the database
  static Future<List<Map<String, dynamic>>> getSessionLogs(String sessionId) async {
    try {
      final response = await client
          .from('activity_logs')
          .select('logged_at, activity_type, note')
          .eq('session_id', sessionId)
          .order('logged_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      // ignore: avoid_print
      print('Error in getSessionLogs: $e');
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

  /// Complete the active session, clearing active status and updating database
  static Future<void> completeMockBooking({
    required String caregiverName,
    required String serviceTitle,
    required int amount,
  }) async {
    try {
      final user = currentUser;
      if (user != null) {
        // Find the active booking
        final activeRes = await client
            .from('bookings')
            .select('id')
            .eq('user_id', user.id)
            .inFilter('status', ['pending', 'confirmed', 'active'])
            .order('scheduled_start', ascending: true)
            .limit(1)
            .maybeSingle();

        if (activeRes != null) {
          final bookingId = activeRes['id'] as String;
          // Update booking status to completed
          await client
              .from('bookings')
              .update({'status': 'completed'})
              .eq('id', bookingId);

          // Update session status to completed
          await client
              .from('sessions')
              .update({'status': 'completed', 'actual_end': DateTime.now().toIso8601String()})
              .eq('booking_id', bookingId);
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error in completeMockBooking: $e');
    }
  }

  /// Start the session, updating status to 'active' and actual_start to now
  static Future<void> startMockSession(String bookingId) async {
    _initMockData();
    if (_mockActiveBooking != null && _mockActiveBooking!['booking_id'] == bookingId) {
      _mockActiveBooking!['status'] = 'active';
      _mockActiveBooking!['actual_start'] = DateTime.now();
    }
    try {
      await client
          .from('sessions')
          .update({
            'status': 'active',
            'actual_start': DateTime.now().toIso8601String(),
          })
          .eq('booking_id', bookingId);

      await client
          .from('bookings')
          .update({'status': 'active'})
          .eq('id', bookingId);
    } catch (e) {
      // ignore: avoid_print
      print('Error in startMockSession: $e');
    }
  }

  /// Retrieve latest status of a booking/session
  static Future<Map<String, dynamic>?> getBookingStatus(String bookingId) async {
    _initMockData();
    if (bookingId == 'mock-booking-active-1' && _mockActiveBooking != null) {
      return _mockActiveBooking;
    }
    try {
      final user = currentUser;
      if (user != null) {
        return await getActiveBooking(user.id);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error in getBookingStatus: $e');
    }
    return null;
  }


  /// Submit rating feedback for a completed session
  static Future<void> rateSession(
    String bookingId, {
    required int overallRating,
    required int punctuality,
    required int professionalism,
    required int qualityOfCare,
    required List<String> tags,
    String? comment,
  }) async {
    _initMockData();
    // Update local in-memory mock if it matches
    if (_mockRecentSessions != null) {
      for (final session in _mockRecentSessions!) {
        if (session['booking_id'] == bookingId) {
          session['isRated'] = true;
          session['rating'] = overallRating;
          session['rating_punctuality'] = punctuality;
          session['rating_professionalism'] = professionalism;
          session['rating_quality'] = qualityOfCare;
          session['rating_tags'] = tags;
          session['rating_comment'] = comment ?? '';
          break;
        }
      }
    }

    try {
      final user = currentUser;
      if (user != null) {
        // Find session for the booking
        final sessionRes = await client
            .from('sessions')
            .select('id')
            .eq('booking_id', bookingId)
            .limit(1)
            .maybeSingle();

        if (sessionRes != null) {
          final sessionId = sessionRes['id'] as String;
          await client.from('session_feedback').insert({
            'session_id': sessionId,
            'user_id': user.id,
            'rating': overallRating,
            'punctuality': punctuality,
            'professionalism': professionalism,
            'quality': qualityOfCare,
            'comment': comment,
          });
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error in rateSession: $e');
    }
  }

  /// Fetch activity logs for a given session from Supabase
  static Future<List<Map<String, dynamic>>> getSessionActivityLogs(String sessionId) async {
    try {
      final response = await client
          .from('activity_logs')
          .select('logged_at, activity_type, note')
          .eq('session_id', sessionId)
          .order('logged_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      // ignore: avoid_print
      print('Error in getSessionActivityLogs: $e');
      return [];
    }
  }

  /// Fetch all saved addresses for a user
  static Future<List<Map<String, dynamic>>> getUserAddresses(String userId) async {
    try {
      final response = await client
          .from('addresses')
          .select('id, flat, street, city, pin_code, is_primary')
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      // ignore: avoid_print
      print('Error fetching user addresses: $e');
      return [];
    }
  }

  /// Delete a saved address by ID
  static Future<void> deleteAddress(String addressId) async {
    try {
      await client.from('addresses').delete().eq('id', addressId);
    } catch (e) {
      // ignore: avoid_print
      print('Error deleting address: $e');
      rethrow;
    }
  }

  /// Set a saved address as primary for a user
  static Future<void> setPrimaryAddress(String userId, String addressId) async {
    try {
      // 1. Set all other addresses to false
      await client
          .from('addresses')
          .update({'is_primary': false})
          .eq('user_id', userId);
      // 2. Set this address to true
      await client
          .from('addresses')
          .update({'is_primary': true})
          .eq('id', addressId);

      // 3. Update legacy profile JSON by fetching the new primary address details
      final newPrimary = await client
          .from('addresses')
          .select('flat, street, city, pin_code')
          .eq('id', addressId)
          .maybeSingle();
      if (newPrimary != null) {
        try {
          final profileData = await downloadProfileJson(userId) ?? {};
          profileData['address'] = {
            'flat': newPrimary['flat'] ?? '',
            'street': newPrimary['street'] ?? '',
            'city': newPrimary['city'] ?? '',
            'pincode': newPrimary['pin_code'] ?? '',
          };
          await uploadProfileJson(id: userId, profileData: profileData);
        } catch (_) {}
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error setting primary address: $e');
      rethrow;
    }
  }

  /// Helper to extract label (Home/Work) from flat field
  static String? getAddressLabel(String flat) {
    if (flat.startsWith('[Home]')) return 'Home';
    if (flat.startsWith('[Work]')) return 'Work';
    return null;
  }

  /// Helper to strip label prefix from flat field
  static String cleanFlatName(String flat) {
    if (flat.startsWith('[Home] ')) return flat.replaceFirst('[Home] ', '');
    if (flat.startsWith('[Home]')) return flat.replaceFirst('[Home]', '');
    if (flat.startsWith('[Work] ')) return flat.replaceFirst('[Work] ', '');
    if (flat.startsWith('[Work]')) return flat.replaceFirst('[Work]', '');
    return flat;
  }

  /// Set label (Home/Work/None) for an address
  static Future<void> setAddressLabel(String userId, String addressId, String? label) async {
    try {
      // 1. Fetch current address row
      final addressRow = await client
          .from('addresses')
          .select('flat')
          .eq('id', addressId)
          .maybeSingle();
      if (addressRow == null) return;
      
      final currentFlat = addressRow['flat'] as String? ?? '';
      final cleanFlat = cleanFlatName(currentFlat);
      
      String newFlat = cleanFlat;
      if (label == 'Home') {
        newFlat = '[Home] $cleanFlat';
        // Clear '[Home]' prefix from all other addresses of this user
        final otherRows = await client
            .from('addresses')
            .select('id, flat')
            .eq('user_id', userId)
            .neq('id', addressId);
        for (var row in otherRows) {
          final flatVal = row['flat'] as String? ?? '';
          if (flatVal.startsWith('[Home]')) {
            await client
                .from('addresses')
                .update({'flat': cleanFlatName(flatVal)})
                .eq('id', row['id']);
          }
        }
      } else if (label == 'Work') {
        newFlat = '[Work] $cleanFlat';
        // Clear '[Work]' prefix from all other addresses of this user
        final otherRows = await client
            .from('addresses')
            .select('id, flat')
            .eq('user_id', userId)
            .neq('id', addressId);
        for (var row in otherRows) {
          final flatVal = row['flat'] as String? ?? '';
          if (flatVal.startsWith('[Work]')) {
            await client
                .from('addresses')
                .update({'flat': cleanFlatName(flatVal)})
                .eq('id', row['id']);
          }
        }
      }
      
      // 2. Update this address
      await client
          .from('addresses')
          .update({'flat': newFlat})
          .eq('id', addressId);
    } catch (e) {
      // ignore: avoid_print
      print('Error setting address label: $e');
      rethrow;
    }
  }
}
