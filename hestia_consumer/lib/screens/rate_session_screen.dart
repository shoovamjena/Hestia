import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../services/supabase_service.dart';

class RateSessionScreen extends StatefulWidget {
  final Map<String, dynamic> sessionData;
  const RateSessionScreen({super.key, required this.sessionData});

  @override
  State<RateSessionScreen> createState() => _RateSessionScreenState();
}

class _RateSessionScreenState extends State<RateSessionScreen> {
  int _overallRating = 5;
  int _punctualityRating = 5;
  int _professionalismRating = 5;
  int _qualityRating = 5;

  final Set<String> _selectedTags = {'Punctual', 'Caring', 'Great with Aryan'};
  final TextEditingController _commentController = TextEditingController();

  final List<String> _feedbackTags = [
    'Punctual',
    'Caring',
    'Great with Aryan',
    'Professional',
    'Thorough',
  ];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submitFeedback() {
    final bookingId = widget.sessionData['booking_id'] ?? 'mock-session-1';
    
    // Call service to update state
    SupabaseService.rateSession(
      bookingId,
      overallRating: _overallRating,
      punctuality: _punctualityRating,
      professionalism: _professionalismRating,
      qualityOfCare: _qualityRating,
      tags: _selectedTags.toList(),
      comment: _commentController.text.trim(),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Feedback submitted successfully! Thank you.'),
        backgroundColor: Color(0xFF2E6B4A),
      ),
    );

    Navigator.of(context).pop(true); // Return true to indicate reload needed
  }

  @override
  Widget build(BuildContext context) {
    final caregiverName = widget.sessionData['caregiver_name'] ?? 'Sunita Rao';
    final title = widget.sessionData['title'] ?? 'Post-Delivery';
    final displayTitle = title.endsWith('Care') ? title : '$title Care';

    // Parse date/time strings
    final start = widget.sessionData['scheduled_start'] as DateTime;
    final end = start.add(const Duration(hours: 3, minutes: 2));
    final durationStr = '3 hrs 2 min';

    // Format start time
    String formatTime(DateTime time) {
      int hour = time.hour;
      final minute = time.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;
      return '$hour:$minute $period';
    }

    final dateStr = 'Today · ${formatTime(start)} – ${formatTime(end)}';

    return Container(
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
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: Padding(
            padding: const EdgeInsets.all(8.0),
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: HestiaColors.primary.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.chevron_left_rounded,
                  color: HestiaColors.primary,
                  size: 20,
                ),
              ),
            ),
          ),
          title: const Text(
            'Rate your session',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          centerTitle: true,
        ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Caregiver Summary Card
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF2EB), // Warm beige container from screenshot
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: HestiaColors.primary.withValues(alpha: 0.1),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: const BoxDecoration(
                              color: Color(0xFF8C6239),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _getInitials(caregiverName),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  caregiverName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: HestiaColors.textDark,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$displayTitle · $durationStr',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: HestiaColors.textMedium,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  dateStr,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: HestiaColors.textLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Overall Experience Header
                    const Center(
                      child: Text(
                        'Overall experience',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: HestiaColors.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Gold Star Overall Selector
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final starIndex = index + 1;
                        final isGold = starIndex <= _overallRating;
                        return GestureDetector(
                          onTap: () => setState(() => _overallRating = starIndex),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: Icon(
                              Icons.star_rounded,
                              color: isGold ? const Color(0xFFDCA857) : const Color(0xFFE2E2E2),
                              size: 38,
                            ),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 28),

                    // RATE BY CATEGORY Card Container
                    Container(
                      padding: const EdgeInsets.all(20.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: HestiaColors.primary.withValues(alpha: 0.15),
                          width: 1.2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x05000000),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'RATE BY CATEGORY',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF8C6239),
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildCategoryRow('Punctuality', _punctualityRating, (rating) {
                            setState(() => _punctualityRating = rating);
                          }),
                          const Divider(color: Color(0xFFFAF2EB), height: 32, thickness: 1.2),
                          _buildCategoryRow('Professionalism', _professionalismRating, (rating) {
                            setState(() => _professionalismRating = rating);
                          }),
                          const Divider(color: Color(0xFFFAF2EB), height: 32, thickness: 1.2),
                          _buildCategoryRow('Quality of care', _qualityRating, (rating) {
                            setState(() => _qualityRating = rating);
                          }),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Selectable Tag Badges
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _feedbackTags.map((tag) {
                        final isSelected = _selectedTags.contains(tag);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedTags.remove(tag);
                              } else {
                                _selectedTags.add(tag);
                              }
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFFAF2EB) : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF8C6239) : const Color(0xFFE5D5C5),
                                width: 1.2,
                              ),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? const Color(0xFF8C6239) : HestiaColors.textMedium,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 24),

                    // Optional Comment Field
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF2EB).withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFFAF2EB),
                          width: 1.5,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: TextField(
                        controller: _commentController,
                        maxLines: 3,
                        style: const TextStyle(fontSize: 14, color: HestiaColors.textDark),
                        decoration: const InputDecoration(
                          hintText: 'Add a comment (optional)',
                          hintStyle: TextStyle(
                            color: HestiaColors.textLight,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Submit Button Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HestiaColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _submitFeedback,
                  child: const Text(
                    'Submit feedback',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
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

  Widget _buildCategoryRow(String categoryName, int rating, Function(int) onRatingChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          categoryName,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: HestiaColors.textDark,
          ),
        ),
        Row(
          children: List.generate(5, (index) {
            final starIndex = index + 1;
            final isGold = starIndex <= rating;
            return GestureDetector(
              onTap: () => onRatingChanged(starIndex),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: Icon(
                  Icons.star_rounded,
                  color: isGold ? const Color(0xFFDCA857) : const Color(0xFFE2E2E2),
                  size: 20,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length > 1) {
      return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }
}
