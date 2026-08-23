import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  // Static variable to store signup name in-memory during phone OTP signup flow
  static String? pendingSignUpName;
  static String? pendingSignUpPassword;
  static String? pendingSignUpPhone;
  static String? pendingOnboardingFullName;
  static String? pendingOnboardingEmail;

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
        'scheduled_start': DateTime.now().subtract(
          const Duration(hours: 1, minutes: 24),
        ),
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

  /// Safely get the email for the current user from auth or metadata.
  static String get currentUserEmail {
    final user = currentUser;
    if (user == null) return '';

    final email = user.email;
    if (email != null && email.isNotEmpty) {
      return email;
    }

    final metaEmail = user.userMetadata?['email']?.toString();
    if (metaEmail != null && metaEmail.isNotEmpty) {
      return metaEmail;
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
      data: {'full_name': name, 'email': email, 'user_type': 'consumer'},
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
      UserAttributes(data: {'phone_verified': verified}),
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
      await client.auth.updateUser(UserAttributes(phone: phone));
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

  /// Check if the user has finished the post sign-in onboarding flow.
  static Future<bool> isProfileComplete(String userId) async {
    try {
      final userRow = await client
          .from('users')
          .select('onboarding_complete')
          .eq('id', userId)
          .maybeSingle();
      return userRow?['onboarding_complete'] == true;
    } catch (e) {
      // ignore: avoid_print
      print('Warning: isProfileComplete check failed: $e');
      return false;
    }
  }

  /// Normalize a phone number to E.164 (`+91XXXXXXXXXX`) for consistent storage.
  static String? _normalizeStoredPhone(String? phone) {
    if (phone == null) return null;
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return null;

    var digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) {
      digits = '91$digits';
    }
    if (digits.isEmpty) return null;
    return '+$digits';
  }

  /// Upsert a row in `users`, clearing stale phone conflicts from prior auth
  /// sessions before writing.
  static Future<void> _upsertUserRecord({
    required String id,
    required String fullName,
    String? email,
    String? phone,
    bool? onboardingComplete,
  }) async {
    final trimmedEmail = email?.trim();
    final dbEmail = (trimmedEmail == null || trimmedEmail.isEmpty)
        ? null
        : trimmedEmail;
    final dbPhone = _normalizeStoredPhone(phone);

    if (dbPhone != null) {
      try {
        final conflicting = await client
            .from('users')
            .select('id')
            .eq('phone', dbPhone)
            .maybeSingle();
        if (conflicting != null && conflicting['id']?.toString() != id) {
          await client
              .from('users')
              .update({
                'phone': null,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', conflicting['id']);
        }
      } catch (e) {
        // ignore: avoid_print
        print('Warning: Failed to resolve phone conflict: $e');
      }
    }

    final payload = <String, dynamic>{
      'id': id,
      'full_name': fullName,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (dbEmail != null) payload['email'] = dbEmail;
    if (dbPhone != null) payload['phone'] = dbPhone;
    if (onboardingComplete != null) {
      payload['onboarding_complete'] = onboardingComplete;
    }

    try {
      await client.from('users').upsert(payload);
    } on PostgrestException catch (e) {
      // Last resort: save everything except the conflicting phone.
      if (e.code == '23505' && dbPhone != null) {
        payload.remove('phone');
        await client.from('users').upsert(payload);
      } else {
        rethrow;
      }
    }
  }

  /// Save name and email during the first onboarding step.
  static Future<void> saveOnboardingBasics({
    required String id,
    required String fullName,
    String? email,
    String? phone,
  }) async {
    await _upsertUserRecord(
      id: id,
      fullName: fullName,
      email: email,
      phone: phone,
      onboardingComplete: false,
    );

    try {
      await client.auth.updateUser(
        UserAttributes(data: {'full_name': fullName}),
      );
    } catch (_) {}
  }

  /// Save the user's primary address and mark onboarding complete.
  static Future<void> completeOnboarding({
    required String id,
    required String fullName,
    String? email,
    String? phone,
    required Map<String, dynamic> address,
    bool? withinCoverage,
  }) async {
    await saveAddressOnly(
      id: id,
      address: address,
      withinCoverage: withinCoverage,
    );

    await _upsertUserRecord(
      id: id,
      fullName: fullName,
      email: email,
      phone: phone,
      onboardingComplete: true,
    );

    final trimmedEmail = email?.trim();
    final dbEmail = (trimmedEmail == null || trimmedEmail.isEmpty)
        ? null
        : trimmedEmail;

    try {
      await uploadProfileJson(
        id: id,
        profileData: {
          'id': id,
          'name': fullName,
          'email': dbEmail ?? '',
          'phone': phone,
          'address': {
            'flat': address['flat'] ?? '',
            'street': address['street'] ?? '',
            'city': address['city'] ?? '',
            'pincode': address['pincode'] ?? '',
          },
          'updated_at': DateTime.now().toIso8601String(),
        },
      );
    } catch (_) {}

    pendingOnboardingFullName = null;
    pendingOnboardingEmail = null;
  }

  /// Coverage radius (in km) within which an address is considered serviceable
  /// by a hub. Kept in sync with `public.coverage_radius_km()` (server authority).
  static const double coverageRadiusKm = 7.0;

  /// Server + client coverage check. Prefers DB RPC `resolve_hub_coverage`.
  /// Returns `true` when serviceable, `false` when out of range.
  /// Defaults to `true` only when hub data can't be resolved at all.
  static Future<bool> isPointWithinCoverage(double lat, double lng) async {
    try {
      final resolved = await resolveHubCoverage(lat, lng);
      if (resolved != null) {
        return resolved['zone_verified'] == true;
      }

      final List<dynamic> hubs = await client
          .from('hubs')
          .select('latitude, longitude');
      if (hubs.isEmpty) return true;

      double minDistance = double.infinity;
      for (final hub in hubs) {
        final hubLat = double.tryParse(hub['latitude']?.toString() ?? '');
        final hubLng = double.tryParse(hub['longitude']?.toString() ?? '');
        if (hubLat == null || hubLng == null) continue;
        if (hubLat == 0.0 && hubLng == 0.0) continue;
        final distance = _haversineKm(lat, lng, hubLat, hubLng);
        if (distance < minDistance) minDistance = distance;
      }

      if (minDistance == double.infinity) return true;
      return minDistance <= coverageRadiusKm;
    } catch (e) {
      // ignore: avoid_print
      print('Warning: Failed to evaluate coverage: $e');
      return true;
    }
  }

  /// Calls server RPC that returns hub_id, distance_km, zone_verified.
  static Future<Map<String, dynamic>?> resolveHubCoverage(
    double lat,
    double lng,
  ) async {
    try {
      final data = await client.rpc(
        'resolve_hub_coverage',
        params: {'p_lat': lat, 'p_lng': lng},
      );
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('Warning: resolve_hub_coverage RPC unavailable: $e');
      return null;
    }
  }

  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const p = 0.017453292519943295; // pi / 180
    final a =
        0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }

  /// Parse booking date + time as a **local wall-clock** DateTime.
  /// Handles `7:30 PM`, `19:30`, `19:30:00`, and date-only / ISO date strings.
  /// Never treats naive slot times as UTC (that shifted displays like 7:30→2:00).
  static DateTime? parseScheduledStartLocal(dynamic dateObj, dynamic timeObj) {
    final rawDate = dateObj?.toString().trim() ?? '';
    final rawTime = timeObj?.toString().trim() ?? '';
    if (rawDate.isEmpty) return null;

    try {
      // Date may arrive as "2026-07-22" or "2026-07-22T00:00:00+00:00"
      final dateOnly = rawDate.length >= 10
          ? rawDate.substring(0, 10)
          : rawDate;
      final base = DateTime.parse(dateOnly);
      final y = base.year;
      final m = base.month;
      final d = base.day;

      if (rawTime.isEmpty) {
        return DateTime(y, m, d);
      }

      // Already ISO-ish "HH:MM" / "HH:MM:SS" without AM/PM
      final upper = rawTime.toUpperCase();
      final hasAmPm = upper.contains('AM') || upper.contains('PM');
      if (!hasAmPm) {
        final isoTry = DateTime.tryParse('${dateOnly}T$rawTime');
        if (isoTry != null) {
          return DateTime(y, m, d, isoTry.hour, isoTry.minute, isoTry.second);
        }
      }

      final timeParts = upper.split(':');
      if (timeParts.length < 2) return DateTime(y, m, d);

      var hour = int.tryParse(timeParts[0].trim()) ?? 0;
      final minuteToken = timeParts[1].split(RegExp(r'\s+')).first;
      final minute = int.tryParse(minuteToken) ?? 0;
      final isPm = upper.contains('PM');
      final isAm = upper.contains('AM');
      if (isPm && hour < 12) hour += 12;
      if (isAm && hour == 12) hour = 0;

      return DateTime(y, m, d, hour, minute);
    } catch (_) {
      return null;
    }
  }

  static double _durationHoursFromBooking(Map<String, dynamic> row) {
    return (row['duration_hours'] as num?)?.toDouble() ?? 2.0;
  }

  /// Create a profile record in the database for the user.
  /// Catches and logs errors gracefully so that the app won't get stuck.
  static Future<void> createProfile({
    required String id,
    required String fullName,
    String? email,
    String? phone,
  }) async {
    try {
      await _upsertUserRecord(
        id: id,
        fullName: fullName,
        email: email ?? currentUserEmail,
        phone: phone,
      );
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
    if (cleanPhone.length == 10) {
      cleanPhone = '91$cleanPhone';
    }

    if (user != null) {
      // SCENARIO A: User is already logged in (verifying phone from profile screen)
      if (cleanPhone.endsWith('8144684265')) {
        final response = await client.auth.verifyOTP(
          phone: phone,
          token: token,
          type: OtpType.phoneChange,
        );
        try {
          await client
              .from('users')
              .update({
                'phone': phone,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', user.id);
        } catch (_) {}
        return response;
      } else {
        if (token == '123456') {
          // Bypass: Update metadata and users table directly without changing current session
          await client.auth.updateUser(
            UserAttributes(data: {'phone_verified': true, 'phone': phone}),
          );
          try {
            await client
                .from('users')
                .update({
                  'phone': phone,
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('id', user.id);
          } catch (_) {}
          return AuthResponse(session: currentSession, user: currentUser);
        } else {
          throw const AuthException(
            'Invalid OTP. Use 123456 to bypass Sandbox restrictions.',
          );
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
            final response = await client.auth.signInWithPassword(
              email: email,
              password: password,
            );
            final user = response.user;
            if (user != null) {
              try {
                await createProfile(
                  id: user.id,
                  fullName:
                      user.userMetadata?['full_name'] ??
                      pendingSignUpName ??
                      'User',
                  phone: phone,
                );
              } catch (_) {}
            }
            return response;
          } catch (_) {
            // If sign in fails, sign up the bypass user
            final response = await client.auth.signUp(
              email: email,
              password: password,
              data: {
                'phone': phone,
                'phone_verified': true,
                'user_type': 'consumer',
                if (pendingSignUpName != null) 'full_name': pendingSignUpName,
              },
            );
            final user = response.user;
            if (user != null) {
              try {
                await createProfile(
                  id: user.id,
                  fullName: pendingSignUpName ?? 'User',
                  phone: phone,
                );
              } catch (_) {}
            }
            return response;
          }
        } else {
          throw const AuthException(
            'Invalid OTP. Use 123456 to bypass Sandbox restrictions.',
          );
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
              fullName:
                  user.userMetadata?['full_name'] ??
                  pendingSignUpName ??
                  'User',
              email: user.email ?? email,
              phone: user.userMetadata?['phone'] ?? pendingSignUpPhone,
            );
            await client
                .from('users')
                .update({
                  'email_verified': true,
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('id', user.id);
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
                fullName:
                    user.userMetadata?['full_name'] ??
                    pendingSignUpName ??
                    'User',
                email: user.email ?? email,
                phone: user.userMetadata?['phone'] ?? pendingSignUpPhone,
              );
              await client
                  .from('users')
                  .update({
                    'email_verified': true,
                    'updated_at': DateTime.now().toIso8601String(),
                  })
                  .eq('id', user.id);
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
                fullName:
                    user.userMetadata?['full_name'] ??
                    pendingSignUpName ??
                    'User',
                email: email,
                phone: user.userMetadata?['phone'] ?? pendingSignUpPhone,
              );
              await client
                  .from('users')
                  .update({
                    'email_verified': true,
                    'updated_at': DateTime.now().toIso8601String(),
                  })
                  .eq('id', user.id);
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
            fullName:
                user.userMetadata?['full_name'] ?? pendingSignUpName ?? 'User',
            email: user.email ?? email,
            phone: user.userMetadata?['phone'] ?? pendingSignUpPhone,
          );
          await client
              .from('users')
              .update({
                'email_verified': true,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', user.id);
        } catch (_) {}
      }
      return response;
    }
  }

  /// Resend the email OTP for sign-up verification.
  static Future<void> resendEmailOtp({required String email}) async {
    await client.auth.resend(type: OtpType.signup, email: email);
  }

  /// Resend the email OTP for sign-in.
  static Future<void> resendSignInEmailOtp({required String email}) async {
    await client.auth.resend(type: OtpType.email, email: email);
  }

  /// Sign out the current authenticated user session.
  static Future<void> signOut() async {
    try {
      // Local sign-out clears the session immediately without waiting on the network.
      await client.auth
          .signOut(scope: SignOutScope.local)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Best-effort logout; navigation should still proceed even if this stalls.
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
        await client.storage.createBucket(
          'profiles',
          const BucketOptions(public: true),
        );
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
    required Map<String, dynamic> address,
  }) async {
    try {
      String? dbPhone = phone;
      if (dbPhone != null && dbPhone.trim().isEmpty) {
        dbPhone = null;
      }

      // 1. Update users table
      await _upsertUserRecord(
        id: id,
        fullName: fullName,
        email: email,
        phone: dbPhone,
        onboardingComplete: true,
      );

      // 2. Resolve Nearest Hub ID from address
      String? hubId;
      try {
        var hubsList = await client.from('hubs').select('id, name');
        if (hubsList.isEmpty) {
          try {
            final newHub = await client
                .from('hubs')
                .insert({
                  'name': 'Default Testing Hub',
                  'address': 'Default Address',
                })
                .select('id, name')
                .single();
            hubsList = [newHub];
          } catch (e) {
            // ignore: avoid_print
            print(
              'Warning: Failed to create default hub in saveUserProfile: $e',
            );
          }
        }
        if (hubsList.isNotEmpty) {
          final addressText = '${address['street']} ${address['city']}'
              .toLowerCase();
          final matchingHub = hubsList.firstWhere((h) {
            final hubName = (h['name'] as String)
                .split(' ')
                .first
                .toLowerCase();
            if (hubName == 'brahmapur' &&
                (addressText.contains('berhampur') ||
                    addressText.contains('brahmapur'))) {
              return true;
            }
            return addressText.contains(hubName);
          }, orElse: () => hubsList.first);
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
    bool? withinCoverage,
  }) async {
    try {
      final lat = double.tryParse(
        address['latitude']?.toString() ?? address['lat']?.toString() ?? '',
      );
      final lng = double.tryParse(
        address['longitude']?.toString() ?? address['lng']?.toString() ?? '',
      );

      String? hubId;
      bool zoneVerified = withinCoverage ?? false;

      // Prefer server authority when coordinates exist
      if (lat != null && lng != null) {
        final resolved = await resolveHubCoverage(lat, lng);
        if (resolved != null) {
          hubId = resolved['hub_id']?.toString();
          zoneVerified = resolved['zone_verified'] == true;
        } else {
          // Client fallback until SQL migration is applied
          zoneVerified =
              withinCoverage ?? await isPointWithinCoverage(lat, lng);
          try {
            final hubsList = await client
                .from('hubs')
                .select('id, latitude, longitude');
            double best = double.infinity;
            for (final h in hubsList) {
              final hubLat = double.tryParse(h['latitude']?.toString() ?? '');
              final hubLng = double.tryParse(h['longitude']?.toString() ?? '');
              if (hubLat == null || hubLng == null) continue;
              if (hubLat == 0.0 && hubLng == 0.0) continue;
              final d = _haversineKm(lat, lng, hubLat, hubLng);
              if (d < best) {
                best = d;
                hubId = h['id']?.toString();
              }
            }
            if (best != double.infinity) {
              zoneVerified = best <= coverageRadiusKm;
            }
          } catch (_) {}
        }
      } else {
        // No coordinates: never mark as verified from the client alone
        zoneVerified = false;
        try {
          final hubsList = await client.from('hubs').select('id, name');
          if (hubsList.isNotEmpty) {
            final addressText = '${address['street']} ${address['city']}'
                .toLowerCase();
            Map<String, dynamic>? matchingHub;
            for (final h in hubsList) {
              final hubName = (h['name'] as String)
                  .split(' ')
                  .first
                  .toLowerCase();
              final isMatch =
                  (hubName == 'brahmapur' &&
                      (addressText.contains('berhampur') ||
                          addressText.contains('brahmapur'))) ||
                  addressText.contains(hubName);
              if (isMatch) {
                matchingHub = Map<String, dynamic>.from(h);
                break;
              }
            }
            hubId = (matchingHub ?? hubsList.first)['id'] as String?;
          }
        } catch (e) {
          // ignore: avoid_print
          print('Warning: Failed to resolve hub: $e');
        }
      }

      // Set all existing addresses to non-primary first
      try {
        await client
            .from('addresses')
            .update({'is_primary': false})
            .eq('user_id', id);
      } catch (_) {}

      // 2. Upsert address record (trigger recomputes hub/zone when lat/lng set)
      final addressRow = <String, dynamic>{
        'user_id': id,
        'hub_id': hubId,
        'flat': address['flat'] ?? '',
        'street': address['street'] ?? '',
        'city': address['city'] ?? '',
        'pin_code': address['pincode'] ?? '',
        'is_primary': true,
        'zone_verified': zoneVerified,
      };
      if (lat != null) addressRow['latitude'] = lat;
      if (lng != null) addressRow['longitude'] = lng;

      await client.from('addresses').upsert(addressRow);

      // 3. Update legacy profile JSON by downloading, updating address, and re-uploading
      try {
        final profileData = await downloadProfileJson(id) ?? {};
        profileData['address'] = {
          'flat': address['flat'] ?? '',
          'street': address['street'] ?? '',
          'city': address['city'] ?? '',
          'pincode': address['pincode'] ?? '',
          'latitude': ?lat,
          'longitude': ?lng,
          'zone_verified': zoneVerified,
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

  /// Fetch user profile details by querying users and addresses
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
          .select(
            'flat, street, city, pin_code, zone_verified, latitude, longitude, hub_id',
          )
          .eq('user_id', userId)
          .eq('is_primary', true)
          .limit(1)
          .maybeSingle();

      final profile = {
        'name': userResponse['full_name'],
        'email': (userResponse['email'] as String?)?.isNotEmpty == true
            ? userResponse['email']
            : currentUserEmail,
        'phone': (userResponse['phone'] as String?)?.isNotEmpty == true
            ? userResponse['phone']
            : currentUserPhone,
        'phone_verified': isPhoneVerified(),
      };

      if (addressResponse != null) {
        profile['address'] = {
          'flat': addressResponse['flat'],
          'street': addressResponse['street'],
          'city': addressResponse['city'],
          'pincode': addressResponse['pin_code'],
          'zone_verified': addressResponse['zone_verified'] == true,
          'latitude': addressResponse['latitude'],
          'longitude': addressResponse['longitude'],
          'hub_id': addressResponse['hub_id'],
        };
      }

      try {
        final jsonProfile = await downloadProfileJson(userId);
        if (jsonProfile != null && jsonProfile['primary_reason'] != null) {
          profile['primary_reason'] = jsonProfile['primary_reason'];
        }
      } catch (_) {}

      return profile;
    } catch (e) {
      // ignore: avoid_print
      print('Error loading user profile: $e');
      return null;
    }
  }

  /// Create a new booking transaction record in the database tables
  static Future<String> createBooking({
    required String userId,
    required String serviceTitle,
    required DateTime selectedDate,
    required String selectedTime,
    required String selectedDuration,
    String selectedProfessionalName = '',
    required String repeatOption,
    required String endsAfter,
    required bool preferSameProfessional,
    required int totalAmount,
    String? paymentId,
    String? careNotes,

    /// When false (default), professional assignment is deferred to the
    /// server-side T-45 job. Pass true only for legacy / instant flows.
    bool assignProfessionalNow = false,
    int donationAmount = 0,
    int? serviceSubtotal,
    double? gstAmount,
  }) async {
    // 1. Fetch primary address for the user
    final addressRes = await client
        .from('addresses')
        .select('id, hub_id, zone_verified, latitude, longitude')
        .eq('user_id', userId)
        .eq('is_primary', true)
        .limit(1)
        .maybeSingle();

    final backupAddressRes =
        addressRes ??
        await client
            .from('addresses')
            .select('id, hub_id, zone_verified, latitude, longitude')
            .eq('user_id', userId)
            .limit(1)
            .maybeSingle();

    final addressId = backupAddressRes?['id'] as String?;
    final hubId = backupAddressRes?['hub_id'] as String?;
    final zoneVerified = backupAddressRes?['zone_verified'] == true;
    final addrLat = double.tryParse(
      backupAddressRes?['latitude']?.toString() ?? '',
    );
    final addrLng = double.tryParse(
      backupAddressRes?['longitude']?.toString() ?? '',
    );

    if (addressId == null) {
      throw Exception(
        'No address found for user. Please set an address first.',
      );
    }

    // Server-aligned coverage gate (UX already blocks, this is authority)
    bool coverageOk = zoneVerified;
    if (!coverageOk && addrLat != null && addrLng != null) {
      final resolved = await resolveHubCoverage(addrLat, addrLng);
      coverageOk = resolved?['zone_verified'] == true;
    }
    if (!coverageOk) {
      throw Exception(
        'This address is outside our ${coverageRadiusKm.toStringAsFixed(0)} km '
        'service area. Please choose a location closer to a Hestia hub.',
      );
    }

    String finalHubId = hubId ?? '';
    if (finalHubId.isEmpty && addrLat != null && addrLng != null) {
      final resolved = await resolveHubCoverage(addrLat, addrLng);
      finalHubId = resolved?['hub_id']?.toString() ?? '';
    }
    if (finalHubId.isEmpty) {
      try {
        final hubRes = await client
            .from('hubs')
            .select('id')
            .limit(1)
            .maybeSingle();
        finalHubId = hubRes?['id'] as String? ?? '';
      } catch (_) {}
    }

    // Auto-create a default hub if none exists in the database
    if (finalHubId.isEmpty) {
      try {
        final newHubRes = await client
            .from('hubs')
            .insert({
              'name': 'Default Testing Hub',
              'address': 'Default Address',
            })
            .select('id')
            .single();
        finalHubId = newHubRes['id'] as String? ?? '';
      } catch (e) {
        // ignore: avoid_print
        print('Warning: Failed to auto-create testing hub: $e');
      }
    }

    // Fallback 1: Resolve hub_id from any professional in the database
    if (finalHubId.isEmpty) {
      try {
        final anyProf = await client
            .from('professionals')
            .select('hub_id')
            .limit(1)
            .maybeSingle();
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

    // 2. Resolve professional ID only when assigning immediately
    String? professionalId;
    if (assignProfessionalNow) {
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
          final profs = await client
              .from('professionals')
              .select('id')
              .limit(1);
          if (profs.isNotEmpty) {
            professionalId = profs.first['id'] as String?;
          }
        } catch (e) {
          // ignore
        }
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
      final freq =
          (repeatOption.toLowerCase() == 'daily' ||
              repeatOption.toLowerCase() == 'everyday')
          ? 'daily'
          : 'weekly';
      List<int> days = [selectedDate.weekday];
      final endDate = selectedDate
          .add(const Duration(days: 90))
          .toIso8601String()
          .substring(0, 10);

      final recResponse = await client
          .from('recurrence_schedules')
          .insert({
            'user_id': userId,
            'frequency': freq,
            'days_of_week': days,
            'end_date': endDate,
            'prefer_same_professional': preferSameProfessional,
          })
          .select('id')
          .single();

      recurrenceId = recResponse['id'] as String?;
    }

    // Ensure the professional exists in the caregivers table to satisfy database foreign key constraint
    if (professionalId != null) {
      try {
        await client.from('caregivers').upsert({
          'id': professionalId,
          'full_name': selectedProfessionalName.isNotEmpty
              ? selectedProfessionalName
              : 'Professional',
        });
      } catch (e) {
        // ignore or log
      }
    }

    // 6. Insert booking — professional deferred to T-45 server job by default
    final servicePillar = mapReasonToServicePillar(serviceTitle);

    final metadata = {
      'user_id': userId,
      'address_id': addressId,
      'total_amount': totalAmount,
      'service_subtotal': serviceSubtotal ?? (totalAmount - donationAmount),
      'gst_amount': gstAmount ?? 0,
      'donation_amount': donationAmount,
      'donate_to_ngo': donationAmount > 0,
      'is_recurring': isRecurring,
      'recurrence_id': recurrenceId,
      'service_pillar': servicePillar,
      'prefer_same_professional': preferSameProfessional,
      'repeat_option': repeatOption,
      'ends_after': endsAfter,
      'payment_id': paymentId,
      'care_notes': careNotes,
      'assignment_deferred': !assignProfessionalNow,
    };

    final bookingInsert = <String, dynamic>{
      'hub_id':
          (finalHubId.isEmpty ||
              finalHubId == '00000000-0000-0000-0000-000000000000')
          ? null
          : finalHubId,
      'professional_id': professionalId,
      'service_type': serviceTitle,
      'status': 'confirmed',
      'scheduled_date': selectedDate.toIso8601String().substring(0, 10),
      'scheduled_time': selectedTime,
      'duration_hours': durationHours,
      'user_id': userId,
      'notes': jsonEncode(metadata),
      'assignment_status': professionalId != null ? 'assigned' : 'pending',
    };
    if (professionalId != null) {
      bookingInsert['assigned_at'] = DateTime.now().toIso8601String();
    }

    final bookingRes = await client
        .from('bookings')
        .insert(bookingInsert)
        .select('id')
        .single();

    final bookingId = bookingRes['id'] as String;

    // 7. Insert active session only when a professional was assigned now
    if (professionalId != null) {
      try {
        final sessionRes = await client
            .from('sessions')
            .insert({
              'booking_id': bookingId,
              'professional_id': professionalId,
              'hub_id':
                  (finalHubId.isEmpty ||
                      finalHubId == '00000000-0000-0000-0000-000000000000')
                  ? null
                  : finalHubId,
              'status': 'transit',
            })
            .select('id')
            .single();

        final sessionId = sessionRes['id'] as String;

        // Create a pending invoice for the booking/session.
        await client.from('invoices').insert({
          'session_id': sessionId,
          'user_id': userId,
          'amount': totalAmount,
          'status': 'pending',
          'payment_method': paymentId == null || paymentId.isEmpty
              ? 'unpaid'
              : 'online',
        });

        // Insert dummy locations for tracking
        await client.from('professional_locations').insert([
          {
            'session_id': sessionId,
            'professional_id': professionalId,
            'coordinates': {
              'type': 'Point',
              'coordinates': [77.6412, 12.9275],
            },
            'recorded_at': DateTime.now().toIso8601String(),
          },
          {
            'session_id': sessionId,
            'professional_id': professionalId,
            'coordinates': {
              'type': 'Point',
              'coordinates': [77.6400, 12.9300],
            },
            'recorded_at': DateTime.now()
                .subtract(const Duration(minutes: 5))
                .toIso8601String(),
          },
        ]);

        // Insert dummy activity logs
        await client.from('activity_logs').insert([
          {
            'session_id': sessionId,
            'professional_id': professionalId,
            'activity_type': 'Feeding support',
            'note': 'Breastfeeding positioning assisted, mother resting',
            'logged_at': DateTime.now()
                .subtract(const Duration(minutes: 20))
                .toIso8601String(),
          },
          {
            'session_id': sessionId,
            'professional_id': professionalId,
            'activity_type': 'Meal assistance',
            'note': 'Light breakfast prepared for mother',
            'logged_at': DateTime.now()
                .subtract(const Duration(minutes: 40))
                .toIso8601String(),
          },
          {
            'session_id': sessionId,
            'professional_id': professionalId,
            'activity_type': 'Session start',
            'note': 'Session started. Checked on patient, settled well',
            'logged_at': DateTime.now()
                .subtract(const Duration(minutes: 60))
                .toIso8601String(),
          },
        ]);
      } catch (e) {
        // ignore: avoid_print
        print('Warning: Failed to insert dummy session/tracking data: $e');
      }
    } else {
      // Deferred assignment: still record a pending invoice against the booking
      // via metadata; session is created by the T-45 assign job.
      try {
        // no-op placeholder — invoice created when session is opened at assign time
      } catch (_) {}
    }

    return bookingId;
  }

  /// Debug helper: force-run T-45 assign-professionals for one booking now
  /// (skips the 45-minute window when the edge function receives force=true).
  static Future<Map<String, dynamic>> invokeAssignProfessionalsDebug({
    required String bookingId,
  }) async {
    final response = await client.functions.invoke(
      'assign-professionals',
      body: {'booking_id': bookingId, 'force': true},
    );

    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {
      'ok': response.status == 200,
      'raw': data,
      'status': response.status,
    };
  }

  /// Upsert an FCM device token for the signed-in user.
  static Future<void> upsertDeviceToken({
    required String userId,
    required String token,
    String platform = 'android',
  }) async {
    if (token.trim().isEmpty) return;
    await client.from('device_tokens').upsert({
      'user_id': userId,
      'token': token,
      'platform': platform,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,token');
  }

  /// Remove a device token (e.g. on logout).
  static Future<void> deleteDeviceToken({
    required String userId,
    required String token,
  }) async {
    if (token.trim().isEmpty) return;
    await client
        .from('device_tokens')
        .delete()
        .eq('user_id', userId)
        .eq('token', token);
  }

  /// Retrieve the active booking details for the dashboard.
  /// Auto-marks no-show when the booked window ended without arrival, and
  /// keeps an unrated no-show visible so the home banner can open review.
  static Future<Map<String, dynamic>?> getActiveBooking(String userId) async {
    try {
      final responseList = await client
          .from('bookings')
          .select(
            'id, hub_id, professional_id, service_type, status, scheduled_date, scheduled_time, duration_hours, notes, assignment_status, professionals(full_name, avg_rating, total_sessions), hubs(name, address)',
          )
          .eq('user_id', userId)
          .inFilter('status', [
            'pending',
            'confirmed',
            'departed',
            'active',
            'in_progress',
            'no_show',
          ]);

      final now = DateTime.now();
      Map<String, dynamic>? liveBooking;
      Map<String, dynamic>? noShowForReview;
      DateTime? liveStart;
      DateTime? noShowStart;

      for (final row in responseList) {
        final notesStr = row['notes'] as String?;
        if (notesStr == null) continue;
        Map<String, dynamic> metadata;
        try {
          metadata = jsonDecode(notesStr) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        if (metadata['user_id'] != null && metadata['user_id'] != userId) {
          continue;
        }

        final bookingId = row['id'] as String;
        final bookingStatus = (row['status'] as String? ?? 'pending')
            .toLowerCase();
        final scheduledStart =
            parseScheduledStartLocal(
              row['scheduled_date'],
              row['scheduled_time'],
            ) ??
            now;
        final hours = _durationHoursFromBooking(row);
        final scheduledEnd = scheduledStart.add(
          Duration(minutes: (hours * 60).round()),
        );

        String sessionStatus = bookingStatus;
        String? sessionId;
        DateTime? actualStart;
        DateTime? actualEnd;
        String? arrivalCode;
        try {
          final sessionRes = await client
              .from('sessions')
              .select('id, status, start_time, end_time, arrival_code')
              .eq('booking_id', bookingId)
              .limit(1)
              .maybeSingle();
          if (sessionRes != null) {
            sessionStatus = (sessionRes['status'] as String? ?? sessionStatus)
                .toLowerCase();
            sessionId = sessionRes['id'] as String?;
            arrivalCode = sessionRes['arrival_code']?.toString();
            final startTimeStr = sessionRes['start_time'] as String?;
            final endTimeStr = sessionRes['end_time'] as String?;
            if (startTimeStr != null) {
              actualStart = DateTime.parse(startTimeStr);
            }
            if (endTimeStr != null) {
              actualEnd = DateTime.parse(endTimeStr);
            }
          }
        } catch (_) {}

        const inTransit = {'departed', 'transit', 'en_route'};
        const arrivedOrLive = {'arrived', 'started', 'active', 'in_progress'};
        const terminal = {'completed', 'cancelled', 'no_show', 'unattended'};

        // Slot ended and pro never arrived → auto no-show.
        var effectiveStatus = bookingStatus;
        if (!terminal.contains(bookingStatus) &&
            !arrivedOrLive.contains(sessionStatus) &&
            !inTransit.contains(sessionStatus) &&
            !now.isBefore(scheduledEnd)) {
          try {
            await markNoShow(bookingId)
                .timeout(const Duration(seconds: 5));
          } catch (_) {}
          effectiveStatus = 'no_show';
          sessionStatus = 'no_show';
        } else if (terminal.contains(bookingStatus)) {
          effectiveStatus = bookingStatus;
        } else if (sessionStatus == 'no_show' ||
            sessionStatus == 'unattended') {
          effectiveStatus = 'no_show';
        } else if (inTransit.contains(sessionStatus) ||
            arrivedOrLive.contains(sessionStatus)) {
          // Prefer live session status (e.g. departed) over booking.confirmed.
          effectiveStatus = sessionStatus;
        } else if (inTransit.contains(bookingStatus) ||
            arrivedOrLive.contains(bookingStatus)) {
          effectiveStatus = bookingStatus;
        }

        bool isRated = false;
        if (sessionId != null && effectiveStatus == 'no_show') {
          try {
            final feedbackRes = await client
                .from('session_feedback')
                .select('id')
                .eq('session_id', sessionId)
                .eq('user_id', userId)
                .limit(1)
                .maybeSingle();
            isRated = feedbackRes != null;
          } catch (_) {}
        }

        String caregiverName = 'Professional';
        double professionalRating = 0.0;
        int professionalTotalSessions = 0;
        if (row['professionals'] != null) {
          final professional = row['professionals'] as Map<String, dynamic>;
          caregiverName = professional['full_name'] as String? ?? caregiverName;
          professionalRating =
              double.tryParse(professional['avg_rating']?.toString() ?? '') ??
              0.0;
          professionalTotalSessions =
              int.tryParse(professional['total_sessions']?.toString() ?? '') ??
              0;
        }

        String hubName = '';
        String hubAddress = '';
        if (row['hubs'] != null) {
          final hubMap = row['hubs'] as Map<String, dynamic>;
          hubName = hubMap['name'] as String? ?? '';
          hubAddress = hubMap['address'] as String? ?? '';
        }

        String userAddress = '';
        try {
          final addressId = metadata['address_id'] as String?;
          if (addressId != null) {
            final addrRes = await client
                .from('addresses')
                .select('flat, street, city, pin_code')
                .eq('id', addressId)
                .maybeSingle();
            if (addrRes != null) {
              final flat = addrRes['flat'] ?? '';
              final street = addrRes['street'] ?? '';
              final city = addrRes['city'] ?? '';
              final pin = addrRes['pin_code'] ?? '';
              userAddress = '$flat, $street, $city, $pin';
            }
          }
        } catch (_) {}

        final mapped = <String, dynamic>{
          'booking_id': bookingId,
          'session_id': sessionId,
          'professional_id': row['professional_id']?.toString(),
          'assignment_status':
              row['assignment_status']?.toString() ?? 'pending',
          'title': row['service_type'] as String? ?? 'Care',
          'scheduled_start': scheduledStart,
          'actual_start': actualStart,
          'actual_end': actualEnd,
          'amount': (metadata['total_amount'] as num?)?.toInt() ?? 0,
          'donation_amount':
              (metadata['donation_amount'] as num?)?.toInt() ?? 0,
          'service_subtotal':
              (metadata['service_subtotal'] as num?)?.toInt() ?? 0,
          'gst_amount': (metadata['gst_amount'] as num?)?.toDouble() ?? 0,
          'tip_amount': (metadata['tip_amount'] as num?)?.toInt() ?? 0,
          'status': effectiveStatus,
          'caregiver_name': caregiverName,
          'professional_rating': professionalRating,
          'professional_total_sessions': professionalTotalSessions,
          'hub_name': hubName,
          'hub_address': hubAddress,
          'user_address': userAddress,
          'arrival_requested': sessionStatus == 'arrived',
          'arrival_code': arrivalCode,
          'care_notes': metadata['care_notes'],
          'duration_hours': hours,
          'isRated': isRated,
        };

        if (effectiveStatus == 'no_show') {
          if (!isRated &&
              (noShowStart == null || scheduledStart.isAfter(noShowStart))) {
            noShowForReview = mapped;
            noShowStart = scheduledStart;
          }
          continue;
        }

        final stillLive =
            inTransit.contains(sessionStatus) ||
            arrivedOrLive.contains(sessionStatus) ||
            inTransit.contains(bookingStatus) ||
            arrivedOrLive.contains(bookingStatus) ||
            now.isBefore(scheduledEnd);
        if (stillLive &&
            (liveStart == null || scheduledStart.isBefore(liveStart))) {
          liveBooking = mapped;
          liveStart = scheduledStart;
        }
      }

      return liveBooking ?? noShowForReview;
    } catch (e) {
      // ignore: avoid_print
      print('Error in getActiveBooking: $e');
      return null;
    }
  }

  /// Request session start, updating status to 'arrived' and setting a mock arrival_code
  static Future<void> requestSessionStart(String bookingId) async {
    try {
      await client
          .from('sessions')
          .update({'status': 'arrived', 'arrival_code': 'TEST12'})
          .eq('booking_id', bookingId);
    } catch (e) {
      // ignore: avoid_print
      print('Error in requestSessionStart: $e');
    }
  }

  /// Retrieve a session by its ID
  static Future<Map<String, dynamic>?> getSessionById(String sessionId) async {
    try {
      return await client
          .from('sessions')
          .select()
          .eq('id', sessionId)
          .maybeSingle();
    } catch (e) {
      // ignore: avoid_print
      print('Error in getSessionById: $e');
      return null;
    }
  }

  /// Verification flow for client to verify arrival code and start the session
  static Future<void> startSessionByClient({
    required String sessionId,
    required String arrivalCode,
  }) async {
    final session = await getSessionById(sessionId);
    if (session == null) throw Exception('Session not found');
    if ((session['status'] ?? '').toString().toLowerCase() != 'arrived') {
      throw Exception('Session cannot be started right now');
    }
    final stored = session['arrival_code']?.toString().toUpperCase();
    final provided = arrivalCode.trim().toUpperCase();
    if (stored == null || stored != provided) {
      throw Exception('Invalid verification code');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await client
        .from('sessions')
        .update({
          'status': 'active',
          'start_time': now,
          'client_verified_at': now,
        })
        .eq('id', sessionId);

    final bookingId = session['booking_id']?.toString();
    if (bookingId != null) {
      await client
          .from('bookings')
          .update({'status': 'in_progress'})
          .eq('id', bookingId);
    }
  }

  /// End the session by client
  static Future<void> endSessionByClient({required String sessionId}) async {
    final session = await getSessionById(sessionId);
    if (session == null) throw Exception('Session not found');

    final now = DateTime.now().toUtc().toIso8601String();
    final updatedSession = await client
        .from('sessions')
        .update({'status': 'completed', 'end_time': now})
        .eq('id', sessionId)
        .select('id, booking_id')
        .maybeSingle();
    if (updatedSession == null) {
      throw Exception('Unable to complete session. Please try again.');
    }

    final bookingId =
        updatedSession['booking_id']?.toString() ??
        session['booking_id']?.toString();
    if (bookingId != null) {
      final updatedBooking = await client
          .from('bookings')
          .update({'status': 'completed'})
          .eq('id', bookingId)
          .select('id')
          .maybeSingle();
      if (updatedBooking == null) {
        throw Exception('Session completed, but booking status update failed.');
      }
    }
  }

  /// Cancel an Instant or Scheduled booking from the consumer app.
  /// Also cancels any linked non-terminal session so staff sees it end.
  static Future<void> cancelBookingByClient({required String bookingId}) async {
    if (bookingId.isEmpty) {
      throw Exception('Missing booking id.');
    }

    final booking = await client
        .from('bookings')
        .select('id, status, notes')
        .eq('id', bookingId)
        .maybeSingle();
    if (booking == null) {
      throw Exception('Booking not found.');
    }

    final status = booking['status']?.toString().trim().toLowerCase() ?? '';
    const terminal = {'cancelled', 'completed', 'no_show', 'unattended'};
    if (terminal.contains(status)) {
      throw Exception('This booking can no longer be cancelled.');
    }

    // Block cancel once care has already started — use End Session instead.
    final liveSession = await client
        .from('sessions')
        .select('id, status')
        .eq('booking_id', bookingId)
        .inFilter('status', ['started', 'active', 'in_progress'])
        .limit(1)
        .maybeSingle();
    if (liveSession != null) {
      throw Exception(
        'This session has already started. Use End Session instead of Cancel.',
      );
    }

    final now = DateTime.now().toUtc().toIso8601String();
    Map<String, dynamic> notesMeta = {};
    final notesRaw = booking['notes']?.toString();
    if (notesRaw != null && notesRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(notesRaw);
        if (decoded is Map) {
          notesMeta = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    notesMeta['cancelled_at'] = now;
    notesMeta['cancelled_by'] = 'client';

    final updatedBooking = await client
        .from('bookings')
        .update({
          'status': 'cancelled',
          'notes': jsonEncode(notesMeta),
        })
        .eq('id', bookingId)
        .select('id')
        .maybeSingle();
    if (updatedBooking == null) {
      throw Exception('Unable to cancel booking. Please try again.');
    }

    try {
      await client
          .from('sessions')
          .update({
            'status': 'cancelled',
            'end_time': now,
          })
          .eq('booking_id', bookingId)
          .not('status', 'in', ['completed', 'cancelled', 'no_show', 'unattended']);
    } catch (_) {
      // Booking cancel succeeded; session update is best-effort.
    }
  }

  static Map<String, double>? parseProfessionalCoordinatesPublic(
    dynamic rawCoordinates,
  ) {
    return _parseProfessionalCoordinates(rawCoordinates);
  }

  static Map<String, double>? _parseProfessionalCoordinates(
    dynamic rawCoordinates,
  ) {
    if (rawCoordinates is Map) {
      final map = Map<String, dynamic>.from(rawCoordinates);
      final list = map['coordinates'];
      if (list is List && list.length >= 2) {
        final lng = (list[0] as num?)?.toDouble();
        final lat = (list[1] as num?)?.toDouble();
        if (lat != null && lng != null) {
          return {'latitude': lat, 'longitude': lng};
        }
      }
      final lat = (map['lat'] as num?)?.toDouble() ??
          (map['latitude'] as num?)?.toDouble();
      final lng = (map['lng'] as num?)?.toDouble() ??
          (map['lon'] as num?)?.toDouble() ??
          (map['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        return {'latitude': lat, 'longitude': lng};
      }
    }
    if (rawCoordinates is List && rawCoordinates.length >= 2) {
      final lng = (rawCoordinates[0] as num?)?.toDouble();
      final lat = (rawCoordinates[1] as num?)?.toDouble();
      if (lat != null && lng != null) {
        return {'latitude': lat, 'longitude': lng};
      }
    }
    if (rawCoordinates is String) {
      final text = rawCoordinates.trim();
      // POINT(lng lat) / SRID=4326;POINT(lng lat)
      final pointMatch = RegExp(
        r'POINT\s*\(\s*([-\d.]+)\s+([-\d.]+)\s*\)',
        caseSensitive: false,
      ).firstMatch(text);
      if (pointMatch != null) {
        final lng = double.tryParse(pointMatch.group(1)!);
        final lat = double.tryParse(pointMatch.group(2)!);
        if (lat != null && lng != null) {
          return {'latitude': lat, 'longitude': lng};
        }
      }
      try {
        final decoded = jsonDecode(text);
        return _parseProfessionalCoordinates(decoded);
      } catch (_) {}
    }
    return null;
  }

  /// Retrieve the latest recorded location for a professional.
  /// Prefers the SQL RPC (plain lat/lng from PostGIS), then table select fallback.
  static Future<Map<String, double>?> getLatestProfessionalLocation(
    String? sessionId, {
    String? professionalId,
  }) async {
    try {
      // 1) RPC returns ST_Y/ST_X so Flutter doesn't need to parse geography.
      try {
        final rpcResult = await client.rpc(
          'get_latest_professional_location',
          params: {
            'p_session_id':
                (sessionId != null && sessionId.isNotEmpty) ? sessionId : null,
            'p_professional_id':
                (professionalId != null && professionalId.isNotEmpty)
                    ? professionalId
                    : null,
          },
        );
        final parsedRpc = _parseLatLngPayload(rpcResult);
        if (parsedRpc != null) return parsedRpc;
      } catch (e) {
        // ignore: avoid_print
        print('RPC get_latest_professional_location failed: $e');
      }

      // 2) Fallback: direct table read + geography parsing.
      if (sessionId != null && sessionId.isNotEmpty) {
        var query = client
            .from('professional_locations')
            .select('coordinates, professional_id, recorded_at')
            .eq('session_id', sessionId);
        if (professionalId != null && professionalId.isNotEmpty) {
          query = query.eq('professional_id', professionalId);
        }
        final response = await query
            .order('recorded_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (response != null && response['coordinates'] != null) {
          final parsed = _parseProfessionalCoordinates(response['coordinates']);
          if (parsed != null) return parsed;
          // ignore: avoid_print
          print(
            'Could not parse professional coordinates: ${response['coordinates']}',
          );
        }
      }

      if (professionalId != null && professionalId.isNotEmpty) {
        final response = await client
            .from('professional_locations')
            .select('coordinates, professional_id, recorded_at')
            .eq('professional_id', professionalId)
            .order('recorded_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (response != null && response['coordinates'] != null) {
          final parsed = _parseProfessionalCoordinates(response['coordinates']);
          if (parsed != null) return parsed;
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error in getLatestProfessionalLocation: $e');
    }
    return null;
  }

  static Map<String, double>? _parseLatLngPayload(dynamic raw) {
    if (raw == null) return null;
    if (raw is List && raw.isNotEmpty) {
      return _parseLatLngPayload(raw.first);
    }
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final lat = (map['latitude'] as num?)?.toDouble() ??
          (map['lat'] as num?)?.toDouble();
      final lng = (map['longitude'] as num?)?.toDouble() ??
          (map['lng'] as num?)?.toDouble() ??
          (map['lon'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        return {'latitude': lat, 'longitude': lng};
      }
      if (map['coordinates'] != null) {
        return _parseProfessionalCoordinates(map['coordinates']);
      }
    }
    if (raw is String) {
      try {
        return _parseLatLngPayload(jsonDecode(raw));
      } catch (_) {}
    }
    return null;
  }

  /// Fetch user notifications for the logged-in client
  static Future<List<Map<String, dynamic>>> getUserNotifications({
    int limit = 50,
  }) async {
    try {
      final user = currentUser;
      if (user == null) return [];

      final response = await client
          .from('user_notifications')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      // ignore: avoid_print
      print('Error in getUserNotifications: $e');
      return [];
    }
  }

  /// Fetch broadcast notifications relevant to the current consumer user.
  static Future<List<Map<String, dynamic>>> getBroadcastNotifications({
    int limit = 50,
  }) async {
    try {
      final user = currentUser;
      if (user == null) return [];

      final hubIds = await getCurrentUserHubIds(user.id);
      final response = await client
          .from('notifications')
          .select()
          .eq('target_app', 'consumer')
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(limit);

      final rows = List<Map<String, dynamic>>.from(response);
      return rows.where((row) {
        final audienceType = row['audience_type']?.toString() ?? 'all';
        final audienceId = row['audience_id']?.toString();
        if (audienceType == 'all') return true;
        if (audienceType == 'user') return audienceId == user.id;
        if (audienceType == 'hub') {
          return audienceId != null && hubIds.contains(audienceId);
        }
        return false;
      }).toList();
    } catch (e) {
      // ignore: avoid_print
      print('Error in getBroadcastNotifications: $e');
      return [];
    }
  }

  /// Fetch all hub ids associated with the user's saved addresses.
  static Future<Set<String>> getCurrentUserHubIds(String userId) async {
    try {
      final response = await client
          .from('addresses')
          .select('hub_id')
          .eq('user_id', userId);

      return List<Map<String, dynamic>>.from(response)
          .map((row) => row['hub_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (e) {
      // ignore: avoid_print
      print('Error in getCurrentUserHubIds: $e');
      return <String>{};
    }
  }

  /// Fetch booking ids for the current user, used by realtime arrival alerts.
  static Future<Set<String>> getUserBookingIds(String userId) async {
    try {
      final response = await client
          .from('bookings')
          .select('id')
          .eq('user_id', userId);

      return List<Map<String, dynamic>>.from(response)
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (e) {
      // ignore: avoid_print
      print('Error in getUserBookingIds: $e');
      return <String>{};
    }
  }

  /// Mark a specific notification as read
  static Future<void> markUserNotificationRead(String id) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await client
          .from('user_notifications')
          .update({'read_at': now})
          .eq('id', id);
    } catch (e) {
      // ignore: avoid_print
      print('Error in markUserNotificationRead: $e');
    }
  }

  /// Mark all notifications as read for the current user
  static Future<void> markAllUserNotificationsRead() async {
    try {
      final user = currentUser;
      if (user == null) return;

      final now = DateTime.now().toUtc().toIso8601String();
      await client
          .from('user_notifications')
          .update({'read_at': now})
          .eq('user_id', user.id);
    } catch (e) {
      // ignore: avoid_print
      print('Error in markAllUserNotificationsRead: $e');
    }
  }

  /// Retrieve all active/upcoming bookings/sessions (pending, confirmed, active) for the user
  static Future<List<Map<String, dynamic>>> getUpcomingBookings(
    String userId,
  ) async {
    try {
      final responseList = await client
          .from('bookings')
          .select(
            'id, hub_id, professional_id, service_type, status, scheduled_date, scheduled_time, duration_hours, notes, assignment_status, professionals(full_name, avg_rating, total_sessions)',
          )
          .eq('user_id', userId)
          .inFilter('status', [
            'pending',
            'confirmed',
            'active',
            'in_progress',
          ]);

      final List<Map<String, dynamic>> list = [];
      for (final item in responseList) {
        final notesStr = item['notes'] as String?;
        if (notesStr == null) continue;
        try {
          final metadata = jsonDecode(notesStr) as Map<String, dynamic>;
          final status = item['status'] as String? ?? 'pending';
          if (![
            'pending',
            'confirmed',
            'active',
            'in_progress',
          ].contains(status)) {
            continue;
          }

          final bookingId = item['id'] as String;
          final serviceType = item['service_type'] as String? ?? 'Care';

          DateTime scheduledStart =
              parseScheduledStartLocal(
                item['scheduled_date'],
                item['scheduled_time'],
              ) ??
              DateTime.now();

          final totalAmount = (metadata['total_amount'] as num?)?.toInt() ?? 0;
          final donationAmount =
              (metadata['donation_amount'] as num?)?.toInt() ?? 0;
          final serviceSubtotal =
              (metadata['service_subtotal'] as num?)?.toInt() ?? 0;
          final gstAmount = (metadata['gst_amount'] as num?)?.toDouble() ?? 0;
          final tipAmount = (metadata['tip_amount'] as num?)?.toInt() ?? 0;

          String caregiverName = 'Sunita Rao';
          double professionalRating = 0.0;
          int professionalTotalSessions = 0;
          if (item['professionals'] != null) {
            final professional = item['professionals'] as Map<String, dynamic>;
            caregiverName =
                professional['full_name'] as String? ?? caregiverName;
            professionalRating =
                double.tryParse(professional['avg_rating']?.toString() ?? '') ??
                0.0;
            professionalTotalSessions =
                int.tryParse(
                  professional['total_sessions']?.toString() ?? '',
                ) ??
                0;
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

          String userAddress = '';
          try {
            final addressId = metadata['address_id'] as String?;
            if (addressId != null) {
              final addrRes = await client
                  .from('addresses')
                  .select('flat, street, city, pin_code')
                  .eq('id', addressId)
                  .maybeSingle();
              if (addrRes != null) {
                final flat = addrRes['flat'] ?? '';
                final street = addrRes['street'] ?? '';
                final city = addrRes['city'] ?? '';
                final pin = addrRes['pin_code'] ?? '';
                userAddress = '$flat, $street, $city, $pin';
              }
            }
          } catch (_) {}

          list.add({
            'booking_id': bookingId,
            'session_id': sessionId,
            'professional_id': item['professional_id']?.toString(),
            'assignment_status':
                item['assignment_status']?.toString() ?? 'pending',
            'title': serviceType,
            'scheduled_start': scheduledStart,
            'actual_start': actualStart,
            'actual_end': actualEnd,
            'amount': totalAmount,
            'donation_amount': donationAmount,
            'service_subtotal': serviceSubtotal,
            'gst_amount': gstAmount,
            'tip_amount': tipAmount,
            'status': activeStatus,
            'caregiver_name': caregiverName,
            'professional_rating': professionalRating,
            'professional_total_sessions': professionalTotalSessions,
            'user_address': userAddress,
            'duration_hours':
                (item['duration_hours'] as num?)?.toDouble() ?? 2.0,
            'arrival_requested': activeStatus == 'arrived',
            'care_notes': metadata['care_notes'],
          });
        } catch (_) {}
      }

      list.sort(
        (a, b) => (a['scheduled_start'] as DateTime).compareTo(
          b['scheduled_start'] as DateTime,
        ),
      );
      return list;
    } catch (e) {
      // ignore: avoid_print
      print('Error in getUpcomingBookings: $e');
      return [];
    }
  }

  /// Retrieve the recent completed sessions/bookings for the user
  static Future<List<Map<String, dynamic>>> getRecentSessions(
    String userId,
  ) async {
    try {
      final responseList = await client
          .from('bookings')
          .select(
            'id, hub_id, professional_id, service_type, status, scheduled_date, scheduled_time, duration_hours, notes, professionals(full_name, avg_rating, total_sessions)',
          )
          .eq('user_id', userId)
          .inFilter('status', ['completed', 'no_show']);

      final List<Map<String, dynamic>> list = [];
      for (final item in responseList) {
        final notesStr = item['notes'] as String?;
        if (notesStr == null) continue;
        try {
          final metadata = jsonDecode(notesStr) as Map<String, dynamic>;
          final status = item['status'] as String? ?? 'pending';
          if (status != 'completed' && status != 'no_show') continue;

          final bookingId = item['id'] as String;
          final serviceType = item['service_type'] as String? ?? 'Care';

          DateTime scheduledStart =
              parseScheduledStartLocal(
                item['scheduled_date'],
                item['scheduled_time'],
              ) ??
              DateTime.now();

          final totalAmount = (metadata['total_amount'] as num?)?.toInt() ?? 0;
          final donationAmount =
              (metadata['donation_amount'] as num?)?.toInt() ?? 0;
          final serviceSubtotal =
              (metadata['service_subtotal'] as num?)?.toInt() ?? 0;
          final gstAmount = (metadata['gst_amount'] as num?)?.toDouble() ?? 0;
          final tipAmount = (metadata['tip_amount'] as num?)?.toInt() ?? 0;

          String caregiverName = 'Sunita Rao';
          double professionalRating = 0.0;
          int professionalTotalSessions = 0;
          if (item['professionals'] != null) {
            final professional = item['professionals'] as Map<String, dynamic>;
            caregiverName =
                professional['full_name'] as String? ?? caregiverName;
            professionalRating =
                double.tryParse(professional['avg_rating']?.toString() ?? '') ??
                0.0;
            professionalTotalSessions =
                int.tryParse(
                  professional['total_sessions']?.toString() ?? '',
                ) ??
                0;
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
                  .select(
                    'rating, punctuality, professionalism, quality, comment',
                  )
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
            'professional_rating': professionalRating,
            'professional_total_sessions': professionalTotalSessions,
            'amount': totalAmount,
            'donation_amount': donationAmount,
            'service_subtotal': serviceSubtotal,
            'gst_amount': gstAmount,
            'tip_amount': tipAmount,
            'status': status,
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

      list.sort(
        (a, b) => (b['scheduled_start'] as DateTime).compareTo(
          a['scheduled_start'] as DateTime,
        ),
      );
      return list;
    } catch (e) {
      // ignore: avoid_print
      print('Error in getRecentSessions: $e');
      return [];
    }
  }

  /// Retrieve the activity logs for a session from the database
  static Future<List<Map<String, dynamic>>> getSessionLogs(
    String sessionId,
  ) async {
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
    if (r.contains('mother') ||
        r.contains('post-delivery') ||
        r.contains('postdelivery')) {
      return 'post_delivery_care';
    }
    if (r.contains('pregnancy') || r.contains('pre-pregnancy')) {
      return 'pre_pregnancy_care';
    }
    if (r.contains('child') || r.contains('baby') || r.contains('sit')) {
      return 'certified_babysitting';
    }
    if (r.contains('mobility') ||
        r.contains('elder') ||
        r.contains('surgery')) {
      return 'mobility_support';
    }
    if (r.contains('bath') || r.contains('groom')) {
      return 'bathing_grooming';
    }
    if (r.contains('admin') ||
        r.contains('concierge') ||
        r.contains('organization')) {
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
              .update({
                'status': 'completed',
                'end_time': DateTime.now().toUtc().toIso8601String(),
              })
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
    if (_mockActiveBooking != null &&
        _mockActiveBooking!['booking_id'] == bookingId) {
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
      final endTime = startTime.add(
        Duration(minutes: (durationHours * 60).round()),
      );

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
  static Future<Map<String, dynamic>?> getBookingStatus(
    String bookingId,
  ) async {
    _initMockData();
    if (bookingId == 'mock-booking-active-1' && _mockActiveBooking != null) {
      return _mockActiveBooking;
    }
    try {
      final response = await client
          .from('bookings')
          .select(
            'id, hub_id, professional_id, service_type, status, scheduled_date, scheduled_time, duration_hours, notes, assignment_status, professionals(full_name, avg_rating, total_sessions), hubs(name, address)',
          )
          .eq('id', bookingId)
          .maybeSingle();

      if (response == null) return null;

      final serviceType = response['service_type'] as String? ?? 'Care';
      final status = response['status'] as String? ?? 'pending';

      DateTime scheduledStart =
          parseScheduledStartLocal(
            response['scheduled_date'],
            response['scheduled_time'],
          ) ??
          DateTime.now();

      final notesStr = response['notes'] as String?;
      int totalAmount = 0;
      String? careNotes;
      String? addressId;
      if (notesStr != null) {
        try {
          final metadata = jsonDecode(notesStr) as Map<String, dynamic>;
          totalAmount = metadata['total_amount'] as int? ?? 0;
          careNotes = metadata['care_notes'] as String?;
          addressId = metadata['address_id'] as String?;
        } catch (_) {}
      }

      String caregiverName = 'Professional';
      double professionalRating = 0.0;
      int professionalTotalSessions = 0;
      if (response['professionals'] != null) {
        final professional = response['professionals'] as Map<String, dynamic>;
        caregiverName = professional['full_name'] as String? ?? caregiverName;
        professionalRating =
            double.tryParse(professional['avg_rating']?.toString() ?? '') ??
            0.0;
        professionalTotalSessions =
            int.tryParse(professional['total_sessions']?.toString() ?? '') ?? 0;
      }

      String hubName = '';
      String hubAddress = '';
      if (response['hubs'] != null) {
        final hubMap = response['hubs'] as Map<String, dynamic>;
        hubName = hubMap['name'] as String? ?? '';
        hubAddress = hubMap['address'] as String? ?? '';
      }

      String userAddress = '';
      if (addressId != null) {
        try {
          final addrRes = await client
              .from('addresses')
              .select('flat, street, city, pin_code')
              .eq('id', addressId)
              .maybeSingle();
          if (addrRes != null) {
            final flat = addrRes['flat'] ?? '';
            final street = addrRes['street'] ?? '';
            final city = addrRes['city'] ?? '';
            final pin = addrRes['pin_code'] ?? '';
            userAddress = '$flat, $street, $city, $pin';
          }
        } catch (_) {}
      }

      String activeStatus = status;
      String? sessionId;
      DateTime? actualStart;
      DateTime? actualEnd;
      String? arrivalCode;
      try {
        final sessionRes = await client
            .from('sessions')
            .select('id, status, start_time, end_time, arrival_code')
            .eq('booking_id', bookingId)
            .limit(1)
            .maybeSingle();
        if (sessionRes != null) {
          final sessionStatus =
              (sessionRes['status'] as String? ?? activeStatus).toLowerCase();
          // Prefer booking terminal statuses so no-show isn't overwritten.
          final bookingTerminal = {'no_show', 'cancelled', 'completed'};
          activeStatus = bookingTerminal.contains(status.toLowerCase())
              ? status
              : sessionStatus;
          sessionId = sessionRes['id'] as String?;
          arrivalCode = sessionRes['arrival_code']?.toString();
          final startTimeStr = sessionRes['start_time'] as String?;
          final endTimeStr = sessionRes['end_time'] as String?;
          if (startTimeStr != null) actualStart = DateTime.parse(startTimeStr);
          if (endTimeStr != null) actualEnd = DateTime.parse(endTimeStr);
        }
      } catch (_) {}

      return {
        'booking_id': bookingId,
        'session_id': sessionId,
        'professional_id': response['professional_id']?.toString(),
        'assignment_status': response['assignment_status']?.toString(),
        'title': serviceType,
        'scheduled_start': scheduledStart,
        'actual_start': actualStart,
        'actual_end': actualEnd,
        'amount': totalAmount,
        'status': activeStatus,
        'caregiver_name': caregiverName,
        'professional_rating': professionalRating,
        'professional_total_sessions': professionalTotalSessions,
        'hub_name': hubName,
        'hub_address': hubAddress,
        'user_address': userAddress,
        'arrival_requested': activeStatus == 'arrived',
        'arrival_code': arrivalCode,
        'care_notes': careNotes,
        'duration_hours':
            (response['duration_hours'] as num?)?.toDouble() ?? 2.0,
      };
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
    int tipAmount = 0,
    String? tipPaymentId,
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
      if (user == null) {
        throw Exception('User not logged in');
      }
      // Find session for the booking
      final sessionRes = await client
          .from('sessions')
          .select('id, professional_id')
          .eq('booking_id', bookingId)
          .limit(1)
          .maybeSingle();

      if (sessionRes == null) {
        throw Exception('Session not found for this booking');
      }

      final sessionId = sessionRes['id'] as String;
      final existingFeedback = await client
          .from('session_feedback')
          .select('id, rating')
          .eq('session_id', sessionId)
          .eq('user_id', user.id)
          .maybeSingle();

      // Consumer app only writes session_feedback.
      // professionals.avg_rating / total_sessions are updated by DB triggers.
      final feedbackPayload = {
        'session_id': sessionId,
        'user_id': user.id,
        'rating': overallRating,
        'punctuality': punctuality,
        'professionalism': professionalism,
        'quality': qualityOfCare,
        'comment': comment,
      };

      if (existingFeedback != null) {
        final updated = await client
            .from('session_feedback')
            .update(feedbackPayload)
            .eq('id', existingFeedback['id'])
            .select('id')
            .maybeSingle();
        if (updated == null) {
          throw Exception('Failed to update session feedback.');
        }
      } else {
        await client.from('session_feedback').insert(feedbackPayload);
      }

      if (tipAmount > 0) {
        final bookingRes = await client
            .from('bookings')
            .select('notes')
            .eq('id', bookingId)
            .maybeSingle();
        if (bookingRes != null) {
          Map<String, dynamic> metadata = {};
          final notesStr = bookingRes['notes'] as String?;
          if (notesStr != null) {
            try {
              metadata = Map<String, dynamic>.from(
                jsonDecode(notesStr) as Map<String, dynamic>,
              );
            } catch (_) {}
          }
          metadata['tip_amount'] = tipAmount;
          metadata['tip_payment_id'] = tipPaymentId;
          metadata['tip_paid_at'] = DateTime.now().toIso8601String();
          await client
              .from('bookings')
              .update({'notes': jsonEncode(metadata)})
              .eq('id', bookingId);
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error in rateSession: $e');
      rethrow;
    }
  }

  /// Fetch activity logs for a given session from Supabase.
  static Future<List<Map<String, dynamic>>> getActivityLogs(
    String sessionId,
  ) async {
    try {
      final response = await client
          .from('activity_logs')
          .select('id, logged_at, activity_type, note, session_id')
          .eq('session_id', sessionId)
          .order('logged_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      // ignore: avoid_print
      print('Error in getSessionActivityLogs: $e');
      return [];
    }
  }

  /// Backward-compatible alias.
  static Future<List<Map<String, dynamic>>> getSessionActivityLogs(
    String sessionId,
  ) {
    return getActivityLogs(sessionId);
  }

  /// Fetch chat messages for a session, oldest first for chat rendering.
  static Future<List<Map<String, dynamic>>> getMessages(
    String sessionId,
  ) async {
    try {
      final response = await client
          .from('messages')
          .select('id, session_id, sender_type, sender_id, content, sent_at')
          .eq('session_id', sessionId)
          .order('sent_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      // ignore: avoid_print
      print('Error in getMessages: $e');
      return [];
    }
  }

  /// Realtime stream for session chat messages.
  static Stream<List<Map<String, dynamic>>> getMessagesStream(
    String sessionId,
  ) {
    return client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .order('sent_at', ascending: true)
        .map((rows) {
          final mapped =
              rows.map((row) => Map<String, dynamic>.from(row)).toList();
          mapped.sort((a, b) {
            final aTime = DateTime.tryParse(a['sent_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bTime = DateTime.tryParse(b['sent_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return aTime.compareTo(bTime);
          });
          return mapped;
        });
  }

  /// Send a chat message for a session.
  static Future<void> sendMessage({
    required String sessionId,
    required String senderId,
    required String senderType,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    try {
      await client.from('messages').insert({
        'session_id': sessionId,
        'sender_type': senderType,
        'sender_id': senderId,
        'content': trimmed,
        'sent_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      // ignore: avoid_print
      print('Error in sendMessage: $e');
      rethrow;
    }
  }

  static final Map<String, DateTime> _chatLastReadAtUtc = {};

  static void markChatRead(String sessionId) {
    if (sessionId.isEmpty) return;
    _chatLastReadAtUtc[sessionId] = DateTime.now().toUtc();
  }

  static DateTime? chatLastReadAt(String sessionId) =>
      _chatLastReadAtUtc[sessionId];

  /// Unseen inbound messages for the consumer (not sent by the client).
  static Future<int> getUnreadChatCount(String sessionId) async {
    if (sessionId.isEmpty) return 0;
    try {
      final messages = await getMessages(sessionId);
      final lastRead = _chatLastReadAtUtc[sessionId];
      final userId = currentUser?.id;
      var count = 0;
      for (final message in messages) {
        final senderType = message['sender_type']?.toString() ?? '';
        final senderId = message['sender_id']?.toString();
        if (senderType == 'client' ||
            (userId != null && senderId == userId)) {
          continue;
        }
        final sentAt = DateTime.tryParse(message['sent_at']?.toString() ?? '');
        if (sentAt == null) continue;
        final sentUtc = sentAt.toUtc();
        if (lastRead == null || sentUtc.isAfter(lastRead)) {
          count++;
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  static bool isInboundChatMessage(Map<String, dynamic> message) {
    final senderType = message['sender_type']?.toString() ?? '';
    final senderId = message['sender_id']?.toString();
    final userId = currentUser?.id;
    if (senderType == 'client') return false;
    if (userId != null && senderId == userId) return false;
    return true;
  }

  /// Fetch all saved addresses for a user
  static Future<List<Map<String, dynamic>>> getUserAddresses(
    String userId,
  ) async {
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
  static Future<void> setAddressLabel(
    String userId,
    String addressId,
    String? label,
  ) async {
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
      DateTime? bookingStart;
      try {
        final cleanTime = selectedTime.trim().toUpperCase();
        final maybeIso = DateTime.tryParse(
          '${selectedDate.toIso8601String().substring(0, 10)}T$selectedTime',
        );
        if (maybeIso != null) {
          bookingStart = DateTime(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
            maybeIso.hour,
            maybeIso.minute,
          );
        } else {
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
        }
      } catch (_) {}

      if (bookingStart == null) {
        // Do not apply any hardcoded clock fallback; if selected time cannot
        // be parsed, matching is unreliable.
        return [];
      }

      double durationHours = 2.0;
      try {
        final normalizedDuration = selectedDuration.toLowerCase();
        final hrMatch = RegExp(
          r'(\d+(?:\.\d+)?)\s*(h|hr|hrs|hour)',
        ).firstMatch(normalizedDuration);
        final minMatch = RegExp(
          r'(\d+)\s*(m|min|mins|minute)',
        ).firstMatch(normalizedDuration);
        if (hrMatch != null || minMatch != null) {
          final hrs = hrMatch != null ? double.parse(hrMatch.group(1)!) : 0.0;
          final mins = minMatch != null ? int.parse(minMatch.group(1)!) : 0;
          durationHours = hrs + (mins / 60.0);
        } else {
          final numMatch = RegExp(
            r'(\d+(?:\.\d+)?)',
          ).firstMatch(normalizedDuration);
          if (numMatch != null) {
            durationHours = double.parse(numMatch.group(1)!);
          }
        }
      } catch (_) {}
      if (durationHours <= 0) durationHours = 2.0;

      final bookingEnd = bookingStart.add(
        Duration(minutes: (durationHours * 60).round()),
      );

      DateTime? parseBookingStart(dynamic dateObj, dynamic timeObj) {
        final dateStr = dateObj?.toString() ?? '';
        final rawTime = timeObj?.toString().trim() ?? '';
        if (dateStr.isEmpty) return null;
        try {
          if (rawTime.isEmpty) return DateTime.parse(dateStr);
          final normalized = rawTime.toUpperCase();
          final timeParts = normalized.split(':');
          if (timeParts.length < 2) return DateTime.parse(dateStr);
          int hour = int.tryParse(timeParts[0]) ?? 0;
          final minuteStr = timeParts[1].split(' ').first;
          final minute = int.tryParse(minuteStr) ?? 0;
          final isPm = normalized.contains('PM');
          final isAm = normalized.contains('AM');
          if (isPm && hour < 12) hour += 12;
          if (isAm && hour == 12) hour = 0;
          final baseDate = DateTime.parse(dateStr);
          return DateTime(
            baseDate.year,
            baseDate.month,
            baseDate.day,
            hour,
            minute,
          );
        } catch (_) {
          return null;
        }
      }

      // 3. Fetch all candidate professionals (optionally filtering by hub_id)
      final List<Map<String, dynamic>> professionalsList;
      if (userHubId != null && userHubId.isNotEmpty) {
        final hubScoped = await client
            .from('professionals')
            .select()
            .eq('hub_id', userHubId);
        if (hubScoped.isNotEmpty) {
          professionalsList = List<Map<String, dynamic>>.from(hubScoped);
        } else {
          // Fallback: if no professionals are found in the primary hub, search
          // globally so overlapping/nearby hub coverage can still return a match.
          final global = await client.from('professionals').select();
          professionalsList = List<Map<String, dynamic>>.from(global);
        }
      } else {
        final global = await client.from('professionals').select();
        professionalsList = List<Map<String, dynamic>>.from(global);
      }

      if (professionalsList.isEmpty) return [];

      final proIds = professionalsList.map((p) => p['id'] as String).toList();

      // 4. Fetch Shifts to check coverage
      List<Map<String, dynamic>> shifts = [];
      try {
        final shiftRes = await client
            .from('shifts')
            .select(
              'professional_id, start_time, end_time, status, recurring_days, is_standby, hub_id',
            )
            .inFilter('professional_id', proIds)
            .eq('status', 'scheduled');
        shifts = List<Map<String, dynamic>>.from(shiftRes);
      } catch (e) {
        // ignore: avoid_print
        print('Warning: Failed to fetch shifts: $e');
      }

      // 5. Fetch overlapping bookings to avoid repeatedly assigning
      // professionals who are already booked for the same slot.
      List<Map<String, dynamic>> overlappingBookings = [];
      try {
        final bookingRes = await client
            .from('bookings')
            .select(
              'professional_id, scheduled_date, scheduled_time, duration_hours, status',
            )
            .inFilter('professional_id', proIds)
            .inFilter('status', [
              'pending',
              'confirmed',
              'active',
              'in_progress',
            ]);
        overlappingBookings = List<Map<String, dynamic>>.from(bookingRes);
      } catch (e) {
        // ignore: avoid_print
        print('Warning: Failed to fetch overlapping bookings: $e');
      }

      // 6. Fetch Session overlapping calendars
      List<Map<String, dynamic>> overlappingSessions = [];
      try {
        final sessionRes = await client
            .from('sessions')
            .select('professional_id, start_time, end_time, status')
            .inFilter('professional_id', proIds)
            .inFilter('status', [
              'scheduled',
              'in_progress',
              'transit',
              'active',
            ]);
        overlappingSessions = List<Map<String, dynamic>>.from(sessionRes);
      } catch (e) {
        // ignore: avoid_print
        print('Warning: Failed to fetch overlapping sessions: $e');
      }

      // 7. Fetch User feedback for repeat preference scoring
      List<Map<String, dynamic>> userFeedbacks = [];
      List<Map<String, dynamic>> pastSessions = [];
      try {
        final feedbackRes = await client
            .from('session_feedback')
            .select('session_id, rating')
            .eq('user_id', userId);
        userFeedbacks = List<Map<String, dynamic>>.from(feedbackRes);

        final fbSessionIds = userFeedbacks
            .map((f) => f['session_id'] as String)
            .toList();
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

      // 8. Fetch all active sessions this week for workload calculation
      final now = DateTime.now();
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final weekStart = DateTime(
        startOfWeek.year,
        startOfWeek.month,
        startOfWeek.day,
      );
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

      // 9. Filter and Score
      for (final p in professionalsList) {
        final pId = p['id'] as String;
        final dutyStatus = p['duty_status']?.toString().toLowerCase() ?? '';

        // Hard Filter 1: Employment status must be active
        if (p['employment_status']?.toString().toLowerCase() != 'active') {
          continue;
        }

        // Hard Filter 2: Background check must not be failed (allow 'verified', 'passed', or 'pending' fallback for testing, but prefer verified)
        final bgStatus =
            p['background_check_status']?.toString().toLowerCase() ?? '';
        if (bgStatus == 'failed' || bgStatus == 'rejected') continue;

        // Hard Filter 3: Service Pillar compatibility
        final pillars = p['service_pillars'];
        bool supportsPillar = false;
        if (pillars is List) {
          final normalizedPillars = pillars
              .map((e) => e.toString().trim().toLowerCase())
              .where((e) => e.isNotEmpty)
              .toList();
          supportsPillar =
              normalizedPillars.isEmpty ||
              normalizedPillars.contains(servicePillar.toLowerCase());
        } else if (pillars is String) {
          final normalizedPillar = pillars.trim().toLowerCase();
          supportsPillar =
              normalizedPillar.isEmpty ||
              normalizedPillar == servicePillar.toLowerCase();
        } else if (pillars == null) {
          // Do not lock out standby professionals just because service pillars
          // have not been configured yet in admin.
          supportsPillar = true;
        }
        if (!supportsPillar) continue;

        // Hard Filter 4: Shift availability (Scheduled shift must cover booking interval).
        // If shift rows are missing or malformed for a professional, do not
        // eliminate them solely on that basis.
        if (dutyStatus != 'standby' && shifts.isNotEmpty) {
          final proShifts = shifts.where((s) => s['professional_id'] == pId);
          bool hasCoveringShift = false;
          bool hasValidShiftWindow = false;
          for (final s in proShifts) {
            final sStart = DateTime.tryParse(s['start_time']?.toString() ?? '');
            final sEnd = DateTime.tryParse(s['end_time']?.toString() ?? '');
            if (sStart != null && sEnd != null) {
              DateTime shiftWindowStart = sStart;
              DateTime shiftWindowEnd = sEnd;

              final recurringDaysRaw = s['recurring_days'];
              final recurringDays = recurringDaysRaw is List
                  ? recurringDaysRaw
                        .map((e) => int.tryParse(e.toString()))
                        .whereType<int>()
                        .toList()
                  : <int>[];

              if (recurringDays.isNotEmpty) {
                // Use the selected booking date with shift time-of-day so future
                // bookings keep matching recurring weekly shifts correctly.
                if (!recurringDays.contains(selectedDate.weekday)) {
                  continue;
                }
                shiftWindowStart = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  sStart.toLocal().hour,
                  sStart.toLocal().minute,
                );
                shiftWindowEnd = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  sEnd.toLocal().hour,
                  sEnd.toLocal().minute,
                );
                if (!shiftWindowEnd.isAfter(shiftWindowStart)) {
                  shiftWindowEnd = shiftWindowEnd.add(const Duration(days: 1));
                }
              }

              hasValidShiftWindow = true;
              if (shiftWindowStart.isBefore(
                    bookingStart.add(const Duration(seconds: 1)),
                  ) &&
                  shiftWindowEnd.isAfter(
                    bookingEnd.subtract(const Duration(seconds: 1)),
                  )) {
                hasCoveringShift = true;
                break;
              }
            }
          }
          if (hasValidShiftWindow && !hasCoveringShift) continue;
        }

        // Hard Filter 5: Booking overlap conflict checks (30 mins travel buffer)
        bool hasConflict = false;
        final buffer = const Duration(minutes: 30);
        final paddedStart = bookingStart.subtract(buffer);
        final paddedEnd = bookingEnd.add(buffer);

        final proBookings = overlappingBookings.where(
          (b) => b['professional_id'] == pId,
        );
        for (final b in proBookings) {
          final existingStart = parseBookingStart(
            b['scheduled_date'],
            b['scheduled_time'],
          );
          if (existingStart == null) continue;
          final existingDurationHours =
              (b['duration_hours'] as num?)?.toDouble() ?? 2.0;
          final existingEnd = existingStart.add(
            Duration(minutes: (existingDurationHours * 60).round()),
          );
          if (existingStart.isBefore(paddedEnd) &&
              existingEnd.isAfter(paddedStart)) {
            hasConflict = true;
            break;
          }
        }
        if (hasConflict) continue;

        // Hard Filter 6: Session overlap conflict checks (30 mins travel buffer)
        final proSessions = overlappingSessions.where(
          (s) => s['professional_id'] == pId,
        );
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
          final proPastSessions = pastSessions
              .where((s) => s['professional_id'] == pId)
              .map((s) => s['id'] as String)
              .toSet();
          if (proPastSessions.isNotEmpty) {
            final proFeedbacks = userFeedbacks.where(
              (f) => proPastSessions.contains(f['session_id']),
            );
            if (proFeedbacks.isNotEmpty) {
              final avgUserRating =
                  proFeedbacks
                      .map((f) => (f['rating'] as num).toDouble())
                      .reduce((a, b) => a + b) /
                  proFeedbacks.length;
              preferenceScore = avgUserRating >= 4.5 ? 100.0 : 50.0;
            }
          }
        }

        // Scoring factor 2: Star rating (Weight = 0.25)
        final dbRating =
            double.tryParse(p['avg_rating']?.toString() ?? '') ?? 0.0;
        final ratingScore = dbRating * 20.0; // scale 0-5 to 0-100

        // Scoring factor 3: Experience (Weight = 0.15)
        final dbExperience =
            int.tryParse(p['years_of_experience']?.toString() ?? '') ?? 0;
        final experienceScore = (dbExperience * 10.0).clamp(0.0, 100.0);

        // Scoring factor 4: Workload Balance (Weight = 0.20)
        final proWeekSessions = weeklySessions
            .where((s) => s['professional_id'] == pId)
            .length;
        double workloadScore = (100.0 - (proWeekSessions * 10.0)).clamp(
          0.0,
          100.0,
        );

        // Small boost for professionals explicitly marked standby at the hub.
        if (dutyStatus == 'standby') {
          workloadScore = (workloadScore + 10.0).clamp(0.0, 100.0);
        }

        // Final score sum
        final finalScore =
            (preferenceScore * 0.40) +
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
      eligibleAndScored.sort(
        (a, b) => (b['matching_score'] as double).compareTo(
          a['matching_score'] as double,
        ),
      );

      return eligibleAndScored;
    } catch (e) {
      // ignore: avoid_print
      print('Error matching professionals: $e');
      return [];
    }
  }

  /// Mark booking as no-show when the professional fails to arrive.
  /// Closes the session so the staff app drops it from active work.
  static Future<void> markNoShow(String bookingId) async {
    _initMockData();
    if (bookingId == 'mock-booking-active-1' && _mockActiveBooking != null) {
      _mockActiveBooking!['status'] = 'no_show';
    }
    try {
      String? professionalId;
      try {
        final booking = await client
            .from('bookings')
            .select('professional_id')
            .eq('id', bookingId)
            .maybeSingle();
        professionalId = booking?['professional_id']?.toString();
      } catch (_) {}

      await client
          .from('bookings')
          .update({'status': 'no_show'})
          .eq('id', bookingId);

      final nowIso = DateTime.now().toUtc().toIso8601String();
      // Terminal session status shared by consumer + staff apps.
      await client
          .from('sessions')
          .update({'status': 'no_show', 'end_time': nowIso})
          .eq('booking_id', bookingId);

      if (professionalId != null && professionalId.isNotEmpty) {
        try {
          await client
              .from('professionals')
              .update({'duty_status': 'standby'})
              .eq('id', professionalId);
        } catch (_) {}
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error marking booking as no-show: $e');
    }
  }
}
