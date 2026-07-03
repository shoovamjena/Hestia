import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/colors.dart';
import 'review_confirm_screen.dart';

class ProfessionalProfile {
  final String id;
  final String name;
  final String initials;
  final Color avatarBg;
  final String rating;
  final int sessionsCount;
  final int distanceKm;
  final List<String> tags; // e.g. ['Verified', 'Regular']

  const ProfessionalProfile({
    required this.id,
    required this.name,
    required this.initials,
    required this.avatarBg,
    required this.rating,
    required this.sessionsCount,
    required this.distanceKm,
    required this.tags,
  });
}

class ChooseProfessionalScreen extends StatefulWidget {
  final String serviceTitle;
  final DateTime selectedDate;
  final String selectedTime;
  final String selectedDuration;
  final String repeatOption;
  final String endsAfter;
  final bool preferSameProfessional;
  final Map<String, int>? servicesMap;

  const ChooseProfessionalScreen({
    super.key,
    required this.serviceTitle,
    required this.selectedDate,
    required this.selectedTime,
    required this.selectedDuration,
    required this.repeatOption,
    required this.endsAfter,
    required this.preferSameProfessional,
    this.servicesMap,
  });

  @override
  State<ChooseProfessionalScreen> createState() => _ChooseProfessionalScreenState();
}

class _ChooseProfessionalScreenState extends State<ChooseProfessionalScreen> {
  bool _isSearching = true;
  bool _fetchError = false;
  Timer? _searchTimer;
  ProfessionalProfile? _matchedProfessional;
  List<ProfessionalProfile> _professionals = [];

  // Deterministic avatar colours derived from a professional's DB id
  static const List<Color> _avatarPalette = [
    Color(0xFF7A9B82), // sage green
    Color(0xFF8C7AA5), // muted purple
    Color(0xFF7A8FAB), // slate blue
    Color(0xFFAB7A7A), // dusty rose
    Color(0xFFAB9A7A), // warm sand
    Color(0xFF7AABA5), // teal
  ];

  Color _avatarColorForId(String id) {
    final hash = id.codeUnits.fold(0, (prev, e) => prev + e);
    return _avatarPalette[hash % _avatarPalette.length];
  }

  String _initialsForName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  void initState() {
    super.initState();
    _fetchAndSearch();
  }

  Future<void> _fetchAndSearch() async {
    // Start the 4-second searching animation timer
    final Completer<void> timerCompleter = Completer();
    _searchTimer = Timer(const Duration(milliseconds: 4000), () {
      if (!timerCompleter.isCompleted) timerCompleter.complete();
    });

    // Fetch professionals from Supabase concurrently with the timer
    try {
      final response = await Supabase.instance.client
          .from('professionals')
          .select('id, full_name, avg_rating, total_sessions, background_check_status')
          .order('full_name');

      final fetched = (response as List).map((row) {
        final id = row['id']?.toString() ?? '';
        final name = row['full_name']?.toString() ?? 'Professional';
        final ratingVal = row['avg_rating'];
        final rating = ratingVal != null
            ? double.tryParse(ratingVal.toString())?.toStringAsFixed(1) ?? '4.5'
            : '4.5';
        final sessions = row['total_sessions'] as int? ?? 0;
        final distance = 5;
        final isVerified = row['background_check_status']?.toString() == 'verified';
        final isTopRated = ratingVal != null && (double.tryParse(ratingVal.toString()) ?? 0.0) >= 4.8;

        final tags = <String>[
          if (isVerified) 'Verified',
          if (isTopRated) 'Top rated',
        ];

        return ProfessionalProfile(
          id: id,
          name: name,
          initials: _initialsForName(name),
          avatarBg: _avatarColorForId(id),
          rating: rating,
          sessionsCount: sessions,
          distanceKm: distance,
          tags: tags.isEmpty ? ['Verified'] : tags,
        );
      }).toList();

      // Wait for the timer to complete before revealing the match
      await timerCompleter.future;

      if (mounted) {
        setState(() {
          _isSearching = false;
          if (fetched.isNotEmpty) {
            _professionals = fetched;
            _matchedProfessional = fetched.first;
          } else {
            _fetchError = true;
          }
        });
      }
    } catch (e) {
      // Ensure timer still completes
      await timerCompleter.future;
      if (mounted) {
        setState(() {
          _isSearching = false;
          _fetchError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  // Map service title to a role label (generic, not name-specific)
  String _getRoleForProfessional(String name) {
    final title = widget.serviceTitle.toLowerCase();
    if (title.contains('post-delivery') || title.contains('pregnancy')) {
      return 'Post-Delivery Specialist';
    } else if (title.contains('babysitting')) {
      return 'Infant Care Provider';
    } else if (title.contains('mobility')) {
      return 'Geriatric Mobility Specialist';
    } else if (title.contains('bathing')) {
      return 'Personal Hygiene Specialist';
    } else if (title.contains('concierge')) {
      return 'Concierge Care Coordinator';
    }
    return 'Senior Care Specialist';
  }

  // Format date helper: "Fri, Jun 12"
  String _formatDate(DateTime date) {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    final weekdayStr = weekdays[date.weekday - 1];
    final monthStr = months[date.month - 1];
    return '$weekdayStr, $monthStr ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 252, 252, 252),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment(0.0, 0.4),
            colors: [
              Color.fromARGB(255, 94, 61, 29),
              Color.fromARGB(255, 139, 106, 65),
              Color.fromARGB(255, 252, 252, 252),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom App Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  children: [
                    // Back Button (Circular)
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 5,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.chevron_left,
                          color: HestiaColors.primary,
                          size: 24,
                        ),
                      ),
                    ),
                    
                    // App Bar Title (Centered)
                    Expanded(
                      child: Center(
                        child: Text(
                           _isSearching
                               ? 'Finding professional...'
                               : _fetchError
                                   ? 'No professionals found'
                                   : 'Professional found',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    
                    // Spacer to balance back button
                    const SizedBox(width: 44),
                  ],
                ),
              ),

              // Main Content
              Expanded(
                child: _isSearching
                    ? _buildSearchingLayout()
                    : _fetchError
                        ? _buildErrorLayout()
                        : _buildFoundLayout(),
              ),

              // Sticky Bottom Book Now Button (only shown once matched, not on error)
              if (!_isSearching && !_fetchError && _matchedProfessional != null)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20.0, 8.0, 20.0, 20.0),
                    child: Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        color: HestiaColors.primary,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: HestiaColors.primary.withValues(alpha: 0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(28),
                          onTap: () {
                            final selectedProf = _matchedProfessional ?? _professionals.first;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => ReviewConfirmScreen(
                                  serviceTitle: widget.serviceTitle,
                                  selectedDate: widget.selectedDate,
                                  selectedTime: widget.selectedTime,
                                  selectedDuration: widget.selectedDuration,
                                  selectedProfessionalName: selectedProf.name,
                                  repeatOption: widget.repeatOption,
                                  endsAfter: widget.endsAfter,
                                  preferSameProfessional: widget.preferSameProfessional,
                                  servicesMap: widget.servicesMap,
                                ),
                              ),
                            );
                          },
                          child: const Center(
                            child: Text(
                              'Continue',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchingLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          
          // Searching Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFAF2EB),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: HestiaColors.primary, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: HestiaColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'FINDING CAREGIVER',
                  style: TextStyle(
                    color: HestiaColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 28),

          // Searching Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: HestiaColors.primary,
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 10,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                const RadarPulseAnimation(color: HestiaColors.primary),
                const SizedBox(height: 36),
                const Text(
                  'Finding best professionals...',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: HestiaColors.textDark,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Searching available professionals in your zone for ${_formatDate(widget.selectedDate)} at ${widget.selectedTime}...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: HestiaColors.textMedium,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildErrorLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFDE8E8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFB94A4A), width: 1.5),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFB94A4A), size: 16),
                SizedBox(width: 8),
                Text(
                  'NO PROFESSIONALS AVAILABLE',
                  style: TextStyle(
                    color: Color(0xFFB94A4A),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFB94A4A), width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 10,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(Icons.search_off_rounded, size: 64, color: Color(0xFFD4A5A5)),
                const SizedBox(height: 20),
                const Text(
                  'No professionals found',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: HestiaColors.textDark,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'We couldn\'t find any available professionals in your zone right now. Please try again shortly.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: HestiaColors.textMedium,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isSearching = true;
                      _fetchError = false;
                      _matchedProfessional = null;
                      _professionals = [];
                    });
                    _fetchAndSearch();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    decoration: BoxDecoration(
                      color: HestiaColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Try again',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildFoundLayout() {
    final prof = _matchedProfessional ?? _professionals.first;
    final role = _getRoleForProfessional(prof.name);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          
          // Matched Circle Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5ED),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2E6B4A), width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.check_circle, color: Color(0xFF2E6B4A), size: 18),
                SizedBox(width: 8),
                Text(
                  'MATCHED CAREGIVER',
                  style: TextStyle(
                    color: Color(0xFF2E6B4A),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 28),

          // Uber-style Driver Detail Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: HestiaColors.primary,
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 10,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                // Avatar circle
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: prof.avatarBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: HestiaColors.primary, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 5,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    prof.initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                Text(
                  prof.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: HestiaColors.textDark,
                  ),
                ),
                
                const SizedBox(height: 6),
                
                Text(
                  role,
                  style: const TextStyle(
                    fontSize: 14,
                    color: HestiaColors.textMedium,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                
                const SizedBox(height: 14),
                
                // Stars & Rating
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ...List.generate(
                      5,
                      (i) => const Icon(
                        Icons.star,
                        color: Color(0xFFDCA153),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${prof.rating} (${prof.sessionsCount} sessions)',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: HestiaColors.textMedium,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                const Divider(color: HestiaColors.inputBorder, height: 1, thickness: 1.2),
                const SizedBox(height: 20),
                
                // Route info detail
                Row(
                  children: [
                    const Icon(
                      Icons.directions_car_filled_rounded,
                      color: HestiaColors.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'DISTANCE FROM YOU',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: HestiaColors.textLight,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${prof.distanceKm} km away in your zone',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: HestiaColors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Matched tags row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: prof.tags.map((tag) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: tag == 'Verified'
                              ? const Color(0xFFE8F5ED)
                              : tag == 'Top rated'
                                  ? const Color(0xFFF3EDFA)
                                  : const Color(0xFFFAF2EB),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: tag == 'Verified'
                                ? const Color(0xFF2E6B4A)
                                : tag == 'Top rated'
                                    ? const Color(0xFF6B4CA2)
                                    : const Color(0xFF8B5A2B),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// Custom radar pulse animation components
class RadarWavePainter extends CustomPainter {
  final double progress;
  final Color color;

  RadarWavePainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    // Draw 3 expanding pulsing rings
    for (int i = 0; i < 3; i++) {
      final ringProgress = (progress + i / 3.0) % 1.0;
      final radius = maxRadius * ringProgress;
      final opacity = (1.0 - ringProgress).clamp(0.0, 1.0);
      ringPaint.color = color.withValues(alpha: opacity * 0.35);
      canvas.drawCircle(center, radius, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant RadarWavePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class RadarPulseAnimation extends StatefulWidget {
  final Color color;
  const RadarPulseAnimation({super.key, this.color = HestiaColors.primary});

  @override
  State<RadarPulseAnimation> createState() => _RadarPulseAnimationState();
}

class _RadarPulseAnimationState extends State<RadarPulseAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  painter: RadarWavePainter(_controller.value, widget.color),
                  child: const SizedBox.expand(),
                );
              },
            ),
            
            // Central location searching icon
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: HestiaColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.location_searching_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
