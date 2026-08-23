import 'package:flutter/material.dart';

import 'supabase_service.dart';

/// Matched caregiver profile used by booking / assignment flows.
class ProfessionalProfile {
  final String id;
  final String name;
  final String initials;
  final Color avatarBg;
  final String rating;
  final int sessionsCount;
  final int distanceKm;
  final List<String> tags;
  final double matchScore;

  const ProfessionalProfile({
    required this.id,
    required this.name,
    required this.initials,
    required this.avatarBg,
    required this.rating,
    required this.sessionsCount,
    required this.distanceKm,
    required this.tags,
    this.matchScore = 0,
  });
}

/// Professional matching helpers kept for future assignment UX.
///
/// Currently used silently after payment to pick a caregiver for [createBooking].
class ProfessionalMatchingService {
  ProfessionalMatchingService._();

  static const List<Color> avatarPalette = [
    Color(0xFF7A9B82),
    Color(0xFF8C7AA5),
    Color(0xFF7A8FAB),
    Color(0xFFAB7A7A),
    Color(0xFFAB9A7A),
    Color(0xFF7AABA5),
  ];

  static Color avatarColorForId(String id) {
    final hash = id.codeUnits.fold(0, (prev, e) => prev + e);
    return avatarPalette[hash % avatarPalette.length];
  }

  static String initialsForName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  static String roleForServiceTitle(String serviceTitle) {
    final title = serviceTitle.toLowerCase();
    if (title.contains('post-delivery') || title.contains('pregnancy')) {
      return 'Post-Delivery Specialist';
    }
    if (title.contains('babysitting')) {
      return 'Infant Care Provider';
    }
    if (title.contains('mobility')) {
      return 'Geriatric Mobility Specialist';
    }
    if (title.contains('bathing')) {
      return 'Personal Hygiene Specialist';
    }
    if (title.contains('concierge')) {
      return 'Concierge Care Coordinator';
    }
    return 'Senior Care Specialist';
  }

  /// Maps a raw matching row into a [ProfessionalProfile].
  static ProfessionalProfile fromMatchRow(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    final name = row['full_name']?.toString() ?? 'Professional';
    final sessions =
        int.tryParse(row['total_sessions']?.toString() ?? '') ?? 0;
    final avgRatingVal =
        double.tryParse(row['avg_rating']?.toString() ?? '') ?? 5.0;
    final rating = avgRatingVal.toStringAsFixed(1);
    final isVerified =
        row['background_check_status']?.toString() == 'verified';
    final isTopRated = avgRatingVal >= 4.8;
    final matchScore = row['matching_score'] as double? ?? 0.0;

    final tags = <String>[
      if (isVerified) 'Verified',
      if (isTopRated) 'Top rated',
      if (matchScore > 0) 'Match: ${matchScore.toStringAsFixed(0)}%',
    ];

    return ProfessionalProfile(
      id: id,
      name: name,
      initials: initialsForName(name),
      avatarBg: avatarColorForId(id),
      rating: rating,
      sessionsCount: sessions,
      distanceKm: 5,
      tags: tags.isEmpty ? const ['Verified'] : tags,
      matchScore: matchScore,
    );
  }

  /// Runs hub / availability matching and returns ranked profiles.
  static Future<List<ProfessionalProfile>> findMatches({
    required String userId,
    required String serviceTitle,
    required DateTime selectedDate,
    required String selectedTime,
    required String selectedDuration,
    bool preferSameProfessional = false,
  }) async {
    final rows = await SupabaseService.matchProfessionals(
      userId: userId,
      serviceTitle: serviceTitle,
      selectedDate: selectedDate,
      selectedTime: selectedTime,
      selectedDuration: selectedDuration,
      preferSameProfessional: preferSameProfessional,
    );
    return rows.map(fromMatchRow).toList();
  }

  /// Best match, or null when none are available.
  static Future<ProfessionalProfile?> findBestMatch({
    required String userId,
    required String serviceTitle,
    required DateTime selectedDate,
    required String selectedTime,
    required String selectedDuration,
    bool preferSameProfessional = false,
  }) async {
    final matches = await findMatches(
      userId: userId,
      serviceTitle: serviceTitle,
      selectedDate: selectedDate,
      selectedTime: selectedTime,
      selectedDuration: selectedDuration,
      preferSameProfessional: preferSameProfessional,
    );
    return matches.isNotEmpty ? matches.first : null;
  }
}
