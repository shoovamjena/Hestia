import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../services/supabase_service.dart';
import '../utils/string_format.dart';
import 'rate_session_screen.dart';

class SessionCompleteScreen extends StatefulWidget {
  final Map<String, dynamic> bookingData;

  const SessionCompleteScreen({super.key, required this.bookingData});

  @override
  State<SessionCompleteScreen> createState() => _SessionCompleteScreenState();
}

class _SessionCompleteScreenState extends State<SessionCompleteScreen> {
  int _userRating = 4; // Defaults to 4 gold stars as seen in the image
  final Set<String> _selectedTags = {};
  int _activityLogsCount = 0;

  final List<String> _feedbackTags = [
    'Punctual',
    'Caring',
    'Professional',
    'Thorough',
  ];

  @override
  void initState() {
    super.initState();
    _loadActivityLogCount();
  }

  Future<void> _loadActivityLogCount() async {
    final sessionId = widget.bookingData['session_id']?.toString();
    if (sessionId == null || sessionId.isEmpty) return;
    final logs = await SupabaseService.getActivityLogs(sessionId);
    if (!mounted) return;
    setState(() {
      _activityLogsCount = logs.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final caregiverName = displayPersonName(
      widget.bookingData['caregiver_name']?.toString(),
      fallback: 'Sunita Rao',
    );
    final serviceTitle = widget.bookingData['title'] ?? 'Post-Delivery Care';
    final totalAmount = widget.bookingData['amount'] ?? 1497;
    final professionalRating =
        double.tryParse(widget.bookingData['professional_rating']?.toString() ?? '');
    final professionalSessions =
        int.tryParse(widget.bookingData['professional_total_sessions']?.toString() ?? '') ?? 0;

    String formatTime(dynamic timeObj) {
      if (timeObj == null) return '--:--';
      final DateTime parsed = timeObj is DateTime 
          ? timeObj 
          : DateTime.parse(timeObj.toString());
      final local = parsed.toLocal();
      int hour = local.hour;
      final minute = local.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;
      return '$hour:$minute $period';
    }

    final actualStartObj = widget.bookingData['actual_start'];
    final actualEndObj = widget.bookingData['actual_end'];
    final durationText = _buildDurationText(actualStartObj, actualEndObj, widget.bookingData['duration_hours']);

    return Container(
        color: HestiaColors.appBackground,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false, // No back button on complete screen
          title: const Text(
            'Session complete',
            style: TextStyle(
              color: HestiaColors.textDark,
              fontSize: 20,
              fontWeight: FontWeight.bold,
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
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
  
                      // Success Checkmark Circle
                      Container(
                        width: 80,
                        height: 80,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE8F5ED),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF2E6B4A),
                            size: 48,
                          ),
                        ),
                      ),
  
                      const SizedBox(height: 20),
  
                      // Main Headers
                      const Text(
                        'Session ended',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$serviceTitle · $durationText',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                    const SizedBox(height: 28),

                    // Details Card Container
                    Container(
                      padding: const EdgeInsets.all(20.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: HestiaColors.primary.withValues(alpha: 0.1),
                          width: 1.2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0A000000),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow('Professional', caregiverName),
                          if (professionalRating != null && professionalRating > 0) ...[
                            const Divider(color: Color(0xFFF0EAE4), height: 32, thickness: 1),
                            _buildDetailRow(
                              'Professional rating',
                              professionalSessions > 0
                                  ? '${professionalRating.toStringAsFixed(1)} ($professionalSessions ${professionalSessions == 1 ? "session" : "sessions"})'
                                  : professionalRating.toStringAsFixed(1),
                            ),
                          ],
                          const Divider(color: Color(0xFFF0EAE4), height: 32, thickness: 1),
                          _buildDetailRow('Started', formatTime(widget.bookingData['actual_start'])),
                          const Divider(color: Color(0xFFF0EAE4), height: 32, thickness: 1),
                          _buildDetailRow('Ended', formatTime(widget.bookingData['actual_end'])),
                          const Divider(color: Color(0xFFF0EAE4), height: 32, thickness: 1),
                          _buildDetailRow('Activities logged', '$_activityLogsCount ${_activityLogsCount == 1 ? "entry" : "entries"}'),
                          const Divider(color: Color(0xFFF0EAE4), height: 32, thickness: 1),
                          _buildDetailRow(
                            'Amount', 
                            '₹${totalAmount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                            isAccent: true,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Rating Title
                    const Text(
                      'How was your session?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: HestiaColors.textDark,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Interactive Star Rating
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final starIndex = index + 1;
                        final isGold = starIndex <= _userRating;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _userRating = starIndex;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: Icon(
                              Icons.star_rounded,
                              color: isGold ? const Color(0xFFDCA857) : const Color(0xFFE2E2E2),
                              size: 40,
                            ),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 28),

                    // Selectable Tag Chips Grid
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
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
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFF3EFEB) : Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: isSelected 
                                    ? HestiaColors.primary 
                                    : const Color(0xFFD8C7B9),
                                width: 1.2,
                              ),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? HestiaColors.primary : HestiaColors.textMedium,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Submit Bottom Button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
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
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => RateSessionScreen(
                          sessionData: widget.bookingData,
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'Rate & tip your professional',
                    style: TextStyle(
                      fontSize: 16,
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

  Widget _buildDetailRow(String label, String value, {bool isAccent = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: HestiaColors.textLight,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isAccent ? FontWeight.w900 : FontWeight.bold,
            color: isAccent ? HestiaColors.textDark : HestiaColors.textDark,
          ),
        ),
      ],
    );
  }

  String _buildDurationText(dynamic actualStartObj, dynamic actualEndObj, dynamic durationHoursObj) {
    DateTime? start;
    DateTime? end;
    if (actualStartObj != null) {
      start = actualStartObj is DateTime ? actualStartObj : DateTime.tryParse(actualStartObj.toString());
    }
    if (actualEndObj != null) {
      end = actualEndObj is DateTime ? actualEndObj : DateTime.tryParse(actualEndObj.toString());
    }

    int durationMinutes = 0;
    if (start != null && end != null) {
      durationMinutes = end.toUtc().difference(start.toUtc()).inMinutes;
    } else {
      final hours = (durationHoursObj as num?)?.toDouble() ?? 0.0;
      durationMinutes = (hours * 60).round();
    }

    if (durationMinutes <= 0) return '--';
    final hours = durationMinutes ~/ 60;
    final minutes = durationMinutes % 60;
    if (hours == 0) return '$minutes min';
    if (minutes == 0) return '$hours hr';
    return '$hours hr $minutes min';
  }
}
