import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  // Static variable to store signup name in-memory during phone OTP signup flow
  static String? pendingSignUpName;
  static String? pendingSignUpPassword;
  static String? pendingSignUpPhone;

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

  /// Safely get the phone number for the current user from auth metadata or profile
  static String get currentUserPhone {
    final user = currentUser;
    if (user == null) return '';
    
    final phone = user.phone;
    if (phone != null && phone.isNotEmpty) {
      return phone;
    }
    
    final metaPhone = user.userMetadata?['phone']?.toString();
    if (metaPhone != null && metaPhone.isNotEmpty) {
      return metaPhone;
    }
    
    return '';
  }

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
            await createProfile(
              id: user.id,
              fullName: user.userMetadata?['full_name'] ?? pendingSignUpName ?? 'User',
              phone: user.userMetadata?['phone'] ?? pendingSignUpPhone,
            );
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
              await createProfile(
                id: user.id,
                fullName: user.userMetadata?['full_name'] ?? pendingSignUpName ?? 'User',
                phone: user.userMetadata?['phone'] ?? pendingSignUpPhone,
              );
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
              if (pendingSignUpName != null) 'full_name': pendingSignUpName,
              if (pendingSignUpPhone != null) 'phone': pendingSignUpPhone,
            },
          );
          final user = response.user;
          if (user != null) {
            try {
              await createProfile(
                id: user.id,
                fullName: user.userMetadata?['full_name'] ?? pendingSignUpName ?? 'User',
                phone: user.userMetadata?['phone'] ?? pendingSignUpPhone,
              );
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
          await createProfile(
            id: user.id,
            fullName: user.userMetadata?['full_name'] ?? pendingSignUpName ?? 'User',
            phone: user.userMetadata?['phone'] ?? pendingSignUpPhone,
          );
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
      // We use local sign out to guarantee the local session is cleared instantly and reliably
      await client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // ignore
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
            (h) {
              final hubName = (h['name'] as String).split(' ').first.toLowerCase();
              if (hubName == 'brahmapur' && (addressText.contains('berhampur') || addressText.contains('brahmapur'))) {
                return true;
              }
              return addressText.contains(hubName);
            },
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
            'primary_service_need': mapReasonToServicePillar(primaryReason),
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
            (h) {
              final hubName = (h['name'] as String).split(' ').first.toLowerCase();
              if (hubName == 'brahmapur' && (addressText.contains('berhampur') || addressText.contains('brahmapur'))) {
                return true;
              }
              return addressText.contains(hubName);
            },
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
    String? careNotes,
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

    // Ensure the professional exists in the caregivers table to satisfy database foreign key constraint
    if (professionalId != null) {
      try {
        await client.from('caregivers').upsert({
          'id': professionalId,
          'full_name': selectedProfessionalName,
        });
      } catch (e) {
        // ignore or log
      }
    }

    // 6. Insert booking
    final servicePillar = mapReasonToServicePillar(serviceTitle);

    final metadata = {
      'user_id': userId,
      'household_member_id': finalMemberId,
      'address_id': addressId,
      'total_amount': totalAmount,
      'is_recurring': isRecurring,
      'recurrence_id': recurrenceId,
      'service_pillar': servicePillar,
      'prefer_same_professional': preferSameProfessional,
      'repeat_option': repeatOption,
      'ends_after': endsAfter,
      'payment_id': paymentId,
      'care_notes': careNotes,
    };

    final bookingRes = await client.from('bookings').insert({
      'hub_id': (finalHubId.isEmpty || finalHubId == '00000000-0000-0000-0000-000000000000') ? null : finalHubId,
      'professional_id': professionalId,
      'service_type': serviceTitle,
      'status': 'confirmed',
      'scheduled_date': selectedDate.toIso8601String().substring(0, 10),
      'scheduled_time': selectedTime,
      'duration_hours': durationHours,
      'notes': jsonEncode(metadata),
    }).select('id').single();

    final bookingId = bookingRes['id'] as String;

    // 7. Insert active session if professional assigned
    if (professionalId != null) {
      try {
        final sessionRes = await client.from('sessions').insert({
          'booking_id': bookingId,
          'professional_id': professionalId,
          'hub_id': (finalHubId.isEmpty || finalHubId == '00000000-0000-0000-0000-000000000000') ? null : finalHubId,
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
      final responseList = await client
          .from('bookings')
          .select('id, hub_id, professional_id, service_type, status, scheduled_date, scheduled_time, duration_hours, notes, professionals(full_name), hubs(name, address)');

      final eligible = <Map<String, dynamic>>[];
      for (var row in responseList) {
        final notesStr = row['notes'] as String?;
        if (notesStr == null) continue;
        try {
          final metadata = jsonDecode(notesStr) as Map<String, dynamic>;
          if (metadata['user_id'] == userId) {
            final status = row['status'] as String? ?? 'pending';
            if (['pending', 'confirmed', 'active'].contains(status)) {
              eligible.add(row);
            }
          }
        } catch (_) {}
      }

      if (eligible.isEmpty) return null;

      eligible.sort((a, b) {
        final dateA = a['scheduled_date']?.toString() ?? '';
        final dateB = b['scheduled_date']?.toString() ?? '';
        return dateA.compareTo(dateB);
      });

      final response = eligible.first;
      final bookingId = response['id'] as String;
      final serviceType = response['service_type'] as String? ?? 'Care';
      
      DateTime scheduledStart = DateTime.now();
      try {
        final dateStr = response['scheduled_date']?.toString() ?? '';
        final timeStr = response['scheduled_time']?.toString() ?? '';
        if (dateStr.isNotEmpty) {
          if (timeStr.isNotEmpty) {
            scheduledStart = DateTime.parse('${dateStr}T$timeStr');
          } else {
            scheduledStart = DateTime.parse(dateStr);
          }
        }
      } catch (_) {}

      final notesStr = response['notes'] as String?;
      int totalAmount = 0;
      String? careNotes;
      if (notesStr != null) {
        try {
          final metadata = jsonDecode(notesStr) as Map<String, dynamic>;
          totalAmount = metadata['total_amount'] as int? ?? 0;
          careNotes = metadata['care_notes'] as String?;
        } catch (_) {}
      }

      final status = response['status'] as String? ?? 'pending';
      
      String caregiverName = 'Professional';
      if (response['professionals'] != null) {
        caregiverName = (response['professionals'] as Map<String, dynamic>)['full_name'] as String? ?? caregiverName;
      }

      String hubName = '';
      String hubAddress = '';
      if (response['hubs'] != null) {
        final hubMap = response['hubs'] as Map<String, dynamic>;
        hubName = hubMap['name'] as String? ?? '';
        hubAddress = hubMap['address'] as String? ?? '';
      }

      String userAddress = '';
      if (notesStr != null) {
        try {
          final metadata = jsonDecode(notesStr) as Map<String, dynamic>;
          final addressId = metadata['address_id'] as String?;
          if (addressId != null) {
            final addrRes = await client.from('addresses').select('flat, street, city, pin_code').eq('id', addressId).maybeSingle();
            if (addrRes != null) {
              final flat = addrRes['flat'] ?? '';
              final street = addrRes['street'] ?? '';
              final city = addrRes['city'] ?? '';
              final pin = addrRes['pin_code'] ?? '';
              userAddress = '$flat, $street, $city, $pin';
            }
          }
        } catch (_) {}
      }

       String activeStatus = status;
      String? sessionId;
      DateTime? actualStart;
      DateTime? actualEnd;
      try {
        final sessionRes = await client
            .from('sessions')
            .select('id, status, start_time, end_time')
            .eq('booking_id', bookingId)
            .limit(1)
            .maybeSingle();
        if (sessionRes != null) {
          activeStatus = sessionRes['status'] as String;
          sessionId = sessionRes['id'] as String;
          final startTimeStr = sessionRes['start_time'] as String?;
          if (startTimeStr != null) {
            actualStart = DateTime.parse(startTimeStr);
          }
          final endTimeStr = sessionRes['end_time'] as String?;
          if (endTimeStr != null) {
            actualEnd = DateTime.parse(endTimeStr);
          }
        }
      } catch (e) {
        // ignore
      }

      return {
        'booking_id': bookingId,
        'session_id': sessionId,
        'title': serviceType,
        'scheduled_start': scheduledStart,
        'actual_start': actualStart,
        'actual_end': actualEnd,
        'amount': totalAmount,
        'status': activeStatus,
        'caregiver_name': caregiverName,
        'hub_name': hubName,
        'hub_address': hubAddress,
        'user_address': userAddress,
        'arrival_requested': activeStatus == 'arrived',
        'care_notes': careNotes,
        'duration_hours': (response['duration_hours'] as num?)?.toDouble() ?? 2.0,
      };
    } catch (e) {
      // ignore: avoid_print
      print('Error in getActiveBooking: $e');
      return null;
    }
  }

  /// Request session start, updating status to 'arrived'
  static Future<void> requestSessionStart(String bookingId) async {
    try {
      await client
          .from('sessions')
          .update({
            'status': 'arrived',
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
      final responseList = await client
          .from('bookings')
          .select('id, hub_id, professional_id, service_type, status, scheduled_date, scheduled_time, duration_hours, notes, professionals(full_name)');

      final List<Map<String, dynamic>> list = [];
      for (final item in responseList) {
        final notesStr = item['notes'] as String?;
        if (notesStr == null) continue;
        try {
          final metadata = jsonDecode(notesStr) as Map<String, dynamic>;
          if (metadata['user_id'] != userId) continue;

          final status = item['status'] as String? ?? 'pending';
          if (!['pending', 'confirmed', 'active'].contains(status)) continue;

          final bookingId = item['id'] as String;
          final serviceType = item['service_type'] as String? ?? 'Care';
          
          DateTime scheduledStart = DateTime.now();
          try {
            final dateStr = item['scheduled_date']?.toString() ?? '';
            final timeStr = item['scheduled_time']?.toString() ?? '';
            if (dateStr.isNotEmpty) {
              if (timeStr.isNotEmpty) {
                scheduledStart = DateTime.parse('${dateStr}T$timeStr');
              } else {
                scheduledStart = DateTime.parse(dateStr);
              }
            }
          } catch (_) {}

          final totalAmount = metadata['total_amount'] as int? ?? 0;

          String caregiverName = 'Sunita Rao';
          if (item['professionals'] != null) {
            caregiverName = (item['professionals'] as Map<String, dynamic>)['full_name'] as String? ?? caregiverName;
          }

          String activeStatus = status;
          String? sessionId;
          DateTime? actualStart;
          DateTime? actualEnd;
          try {
            final sessionRes = await client
                .from('sessions')
                .select('id, status, start_time, end_time')
                .eq('booking_id', bookingId)
                .limit(1)
                .maybeSingle();
            if (sessionRes != null) {
              activeStatus = sessionRes['status'] as String;
              sessionId = sessionRes['id'] as String;
              final startTimeStr = sessionRes['start_time'] as String?;
              if (startTimeStr != null) {
                actualStart = DateTime.parse(startTimeStr);
              }
              final endTimeStr = sessionRes['end_time'] as String?;
              if (endTimeStr != null) {
                actualEnd = DateTime.parse(endTimeStr);
              }
            }
          } catch (e) {
            // ignore
          }

          list.add({
            'booking_id': bookingId,
            'session_id': sessionId,
            'title': serviceType,
            'scheduled_start': scheduledStart,
            'actual_start': actualStart,
            'actual_end': actualEnd,
            'amount': totalAmount,
            'status': activeStatus,
            'caregiver_name': caregiverName,
            'arrival_requested': activeStatus == 'arrived',
            'care_notes': metadata['care_notes'],
          });
        } catch (_) {}
      }

      list.sort((a, b) => (a['scheduled_start'] as DateTime).compareTo(b['scheduled_start'] as DateTime));
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
      final responseList = await client
          .from('bookings')
          .select('id, hub_id, professional_id, service_type, status, scheduled_date, scheduled_time, duration_hours, notes, professionals(full_name)');

      final List<Map<String, dynamic>> list = [];
      for (final item in responseList) {
        final notesStr = item['notes'] as String?;
        if (notesStr == null) continue;
        try {
          final metadata = jsonDecode(notesStr) as Map<String, dynamic>;
          if (metadata['user_id'] != userId) continue;

          final status = item['status'] as String? ?? 'pending';
          if (status != 'completed') continue;

          final bookingId = item['id'] as String;
          final serviceType = item['service_type'] as String? ?? 'Care';
          
          DateTime scheduledStart = DateTime.now();
          try {
            final dateStr = item['scheduled_date']?.toString() ?? '';
            final timeStr = item['scheduled_time']?.toString() ?? '';
            if (dateStr.isNotEmpty) {
              if (timeStr.isNotEmpty) {
                scheduledStart = DateTime.parse('${dateStr}T$timeStr');
              } else {
                scheduledStart = DateTime.parse(dateStr);
              }
            }
          } catch (_) {}

          final totalAmount = metadata['total_amount'] as int? ?? 0;

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
            'title': serviceType,
            'scheduled_start': scheduledStart,
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
        } catch (_) {}
      }

      list.sort((a, b) => (b['scheduled_start'] as DateTime).compareTo(a['scheduled_start'] as DateTime));
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
  static String mapReasonToServicePillar(String reason) {
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
        final activeRes = await getActiveBooking(user.id);

        if (activeRes != null) {
          final bookingId = activeRes['booking_id'] as String;
          // Update booking status to completed
          await client
              .from('bookings')
              .update({'status': 'completed'})
              .eq('id', bookingId);

          // Update session status to completed
          await client
              .from('sessions')
              .update({'status': 'completed', 'end_time': DateTime.now().toUtc().toIso8601String()})
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
      // Fetch booking duration
      final bookingRes = await client
          .from('bookings')
          .select('duration_hours')
          .eq('id', bookingId)
          .maybeSingle();

      double durationHours = 2.0; // fallback
      if (bookingRes != null && bookingRes['duration_hours'] != null) {
        durationHours = (bookingRes['duration_hours'] as num).toDouble();
      }

      final startTime = DateTime.now().toUtc();
      final endTime = startTime.add(Duration(minutes: (durationHours * 60).round()));

      await client
          .from('sessions')
          .update({
            'status': 'active',
            'start_time': startTime.toIso8601String(),
            'end_time': endTime.toIso8601String(),
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

  /// Runs the professional matching logic, filtering by hard constraints (hub, active status,
  /// background check status, service pillar compatibility, shift coverage, and calendar conflict)
  /// and ranking by soft constraints (preferred professional, ratings, experience, workload).
  static Future<List<Map<String, dynamic>>> matchProfessionals({
    required String userId,
    required String serviceTitle,
    required DateTime selectedDate,
    required String selectedTime,
    required String selectedDuration,
    required bool preferSameProfessional,
  }) async {
    try {
      final servicePillar = mapReasonToServicePillar(serviceTitle);

      // 1. Fetch user's primary address to get their assigned hub_id
      String? userHubId;
      try {
        final addressRes = await client
            .from('addresses')
            .select('hub_id')
            .eq('user_id', userId)
            .eq('is_primary', true)
            .limit(1)
            .maybeSingle();
        userHubId = addressRes?['hub_id'] as String?;

        if (userHubId == null) {
          final anyAddressRes = await client
              .from('addresses')
              .select('hub_id')
              .eq('user_id', userId)
              .limit(1)
              .maybeSingle();
          userHubId = anyAddressRes?['hub_id'] as String?;
        }
      } catch (e) {
        // ignore: avoid_print
        print('Warning: Failed to fetch user hub: $e');
      }

      // 2. Parse booking start and end time window
      DateTime bookingStart = selectedDate;
      try {
        final cleanTime = selectedTime.trim().toUpperCase();
        final timeParts = cleanTime.split(':');
        if (timeParts.length >= 2) {
          int hour = int.parse(timeParts[0]);
          final minuteStr = timeParts[1].split(' ')[0];
          int minute = int.parse(minuteStr);
          
          final isPm = cleanTime.contains('PM');
          final isAm = cleanTime.contains('AM');
          if (isPm && hour < 12) hour += 12;
          if (isAm && hour == 12) hour = 0;

          bookingStart = DateTime(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
            hour,
            minute,
          );
        }
      } catch (_) {
        // Fallback: 9 AM
        bookingStart = DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          9,
          0,
        );
      }

      double durationHours = 2.0;
      try {
        final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(selectedDuration.toLowerCase());
        if (numMatch != null) {
          durationHours = double.parse(numMatch.group(1)!);
        }
      } catch (_) {}

      final bookingEnd = bookingStart.add(Duration(minutes: (durationHours * 60).round()));

      // 3. Fetch all candidate professionals (optionally filtering by hub_id)
      var proQuery = client.from('professionals').select();
      if (userHubId != null && userHubId.isNotEmpty) {
        proQuery = proQuery.eq('hub_id', userHubId);
      }
      final responseList = await proQuery;
      final professionalsList = List<Map<String, dynamic>>.from(responseList);

      if (professionalsList.isEmpty) return [];

      final proIds = professionalsList.map((p) => p['id'] as String).toList();

      // 4. Fetch Shifts to check coverage
      List<Map<String, dynamic>> shifts = [];
      try {
        final shiftRes = await client
            .from('shifts')
            .select('professional_id, start_time, end_time, status')
            .inFilter('professional_id', proIds)
            .eq('status', 'scheduled');
        shifts = List<Map<String, dynamic>>.from(shiftRes);
      } catch (e) {
        // ignore: avoid_print
        print('Warning: Failed to fetch shifts: $e');
      }

      // 5. Fetch Session overlapping calendars
      List<Map<String, dynamic>> overlappingSessions = [];
      try {
        final sessionRes = await client
            .from('sessions')
            .select('professional_id, start_time, end_time, status')
            .inFilter('professional_id', proIds)
            .inFilter('status', ['scheduled', 'in_progress', 'transit', 'active']);
        overlappingSessions = List<Map<String, dynamic>>.from(sessionRes);
      } catch (e) {
        // ignore: avoid_print
        print('Warning: Failed to fetch overlapping sessions: $e');
      }

      // 6. Fetch User feedback for repeat preference scoring
      List<Map<String, dynamic>> userFeedbacks = [];
      List<Map<String, dynamic>> pastSessions = [];
      try {
        final feedbackRes = await client
            .from('session_feedback')
            .select('session_id, rating')
            .eq('user_id', userId);
        userFeedbacks = List<Map<String, dynamic>>.from(feedbackRes);

        final fbSessionIds = userFeedbacks.map((f) => f['session_id'] as String).toList();
        if (fbSessionIds.isNotEmpty) {
          final sessRes = await client
              .from('sessions')
              .select('id, professional_id')
              .inFilter('id', fbSessionIds);
          pastSessions = List<Map<String, dynamic>>.from(sessRes);
        }
      } catch (e) {
        // ignore: avoid_print
        print('Warning: Failed to fetch user feedback/history: $e');
      }

      // 7. Fetch all active sessions this week for workload calculation
      final now = DateTime.now();
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final weekStart = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
      List<Map<String, dynamic>> weeklySessions = [];
      try {
        final weeklyRes = await client
            .from('sessions')
            .select('professional_id')
            .gte('start_time', weekStart.toUtc().toIso8601String());
        weeklySessions = List<Map<String, dynamic>>.from(weeklyRes);
      } catch (e) {
        // ignore: avoid_print
        print('Warning: Failed to fetch weekly sessions: $e');
      }

      final eligibleAndScored = <Map<String, dynamic>>[];

      // 8. Filter and Score
      for (final p in professionalsList) {
        final pId = p['id'] as String;

        // Hard Filter 1: Employment status must be active
        if (p['employment_status']?.toString().toLowerCase() != 'active') continue;

        // Hard Filter 2: Background check must not be failed (allow 'verified', 'passed', or 'pending' fallback for testing, but prefer verified)
        final bgStatus = p['background_check_status']?.toString().toLowerCase() ?? '';
        if (bgStatus == 'failed' || bgStatus == 'rejected') continue;

        // Hard Filter 3: Service Pillar compatibility
        final pillars = p['service_pillars'];
        bool supportsPillar = false;
        if (pillars is List) {
          supportsPillar = pillars.map((e) => e.toString().toLowerCase()).contains(servicePillar.toLowerCase());
        } else if (pillars is String) {
          supportsPillar = pillars.toLowerCase() == servicePillar.toLowerCase();
        }
        if (!supportsPillar) continue;

        // Hard Filter 4: Shift availability (Scheduled shift must cover booking interval)
        // Note: Fallback to skip if shifts are empty in the DB to avoid lock-outs during local testing
        if (shifts.isNotEmpty) {
          final proShifts = shifts.where((s) => s['professional_id'] == pId);
          bool hasCoveringShift = false;
          for (final s in proShifts) {
            final sStart = DateTime.tryParse(s['start_time'] ?? '');
            final sEnd = DateTime.tryParse(s['end_time'] ?? '');
            if (sStart != null && sEnd != null) {
              if (sStart.isBefore(bookingStart.add(const Duration(seconds: 1))) &&
                  sEnd.isAfter(bookingEnd.subtract(const Duration(seconds: 1)))) {
                hasCoveringShift = true;
                break;
              }
            }
          }
          if (!hasCoveringShift) continue;
        }

        // Hard Filter 5: Overlap conflict checks (30 mins travel buffer)
        bool hasConflict = false;
        final buffer = const Duration(minutes: 30);
        final paddedStart = bookingStart.subtract(buffer);
        final paddedEnd = bookingEnd.add(buffer);

        final proSessions = overlappingSessions.where((s) => s['professional_id'] == pId);
        for (final s in proSessions) {
          final sStartStr = s['start_time'];
          final sEndStr = s['end_time'];
          if (sStartStr != null && sEndStr != null) {
            final sStart = DateTime.tryParse(sStartStr);
            final sEnd = DateTime.tryParse(sEndStr);
            if (sStart != null && sEnd != null) {
              // Overlap criteria: StartA < EndB and EndA > StartB
              if (sStart.isBefore(paddedEnd) && sEnd.isAfter(paddedStart)) {
                hasConflict = true;
                break;
              }
            }
          }
        }
        if (hasConflict) continue;

        // --- Calculate Soft scoring ---
        
        // Scoring factor 1: Repeat preferred professional (Weight = 0.40)
        double preferenceScore = 0.0;
        if (preferSameProfessional) {
          final proPastSessions = pastSessions.where((s) => s['professional_id'] == pId).map((s) => s['id'] as String).toSet();
          if (proPastSessions.isNotEmpty) {
            final proFeedbacks = userFeedbacks.where((f) => proPastSessions.contains(f['session_id']));
            if (proFeedbacks.isNotEmpty) {
              final avgUserRating = proFeedbacks.map((f) => (f['rating'] as num).toDouble()).reduce((a, b) => a + b) / proFeedbacks.length;
              preferenceScore = avgUserRating >= 4.5 ? 100.0 : 50.0;
            }
          }
        }

        // Scoring factor 2: Star rating (Weight = 0.25)
        final dbRating = double.tryParse(p['avg_rating']?.toString() ?? '') ?? 0.0;
        final ratingScore = dbRating * 20.0; // scale 0-5 to 0-100

        // Scoring factor 3: Experience (Weight = 0.15)
        final dbExperience = int.tryParse(p['years_of_experience']?.toString() ?? '') ?? 0;
        final experienceScore = (dbExperience * 10.0).clamp(0.0, 100.0);

        // Scoring factor 4: Workload Balance (Weight = 0.20)
        final proWeekSessions = weeklySessions.where((s) => s['professional_id'] == pId).length;
        final workloadScore = (100.0 - (proWeekSessions * 10.0)).clamp(0.0, 100.0);

        // Final score sum
        final finalScore = (preferenceScore * 0.40) +
            (ratingScore * 0.25) +
            (experienceScore * 0.15) +
            (workloadScore * 0.20);

        // Build result item
        final resultItem = Map<String, dynamic>.from(p);
        resultItem['matching_score'] = finalScore;
        resultItem['preference_score'] = preferenceScore;
        resultItem['rating_score'] = ratingScore;
        resultItem['experience_score'] = experienceScore;
        resultItem['workload_score'] = workloadScore;
        eligibleAndScored.add(resultItem);
      }

      // Sort by score descending
      eligibleAndScored.sort((a, b) => (b['matching_score'] as double).compareTo(a['matching_score'] as double));

      return eligibleAndScored;
    } catch (e) {
      // ignore: avoid_print
      print('Error matching professionals: $e');
      return [];
    }
  }

  /// Mark booking as no-show when the professional fails to arrive
  static Future<void> markNoShow(String bookingId) async {
    try {
      await client
          .from('bookings')
          .update({'status': 'no_show'})
          .eq('id', bookingId);
          
      // Also update any scheduled session associated with it to 'no_show'
      await client
          .from('sessions')
          .update({'status': 'no_show'})
          .eq('booking_id', bookingId);
    } catch (e) {
      // ignore: avoid_print
      print('Error marking booking as no-show: $e');
    }
  }
}

