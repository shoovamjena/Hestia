import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../services/supabase_service.dart';
import 'home_screen.dart';

class SessionCompleteScreen extends StatefulWidget {
  final Map<String, dynamic> bookingData;

  const SessionCompleteScreen({super.key, required this.bookingData});

  @override
  State<SessionCompleteScreen> createState() => _SessionCompleteScreenState();
}

class _SessionCompleteScreenState extends State<SessionCompleteScreen> {
  int _userRating = 4; // Defaults to 4 gold stars as seen in the image
  final Set<String> _selectedTags = {};

  final List<String> _feedbackTags = [
    'Punctual',
    'Caring',
    'Professional',
    'Thorough',
  ];

  @override
  Widget build(BuildContext context) {
    final caregiverName = widget.bookingData['caregiver_name'] ?? 'Sunita Rao';
    final serviceTitle = widget.bookingData['title'] ?? 'Post-Delivery Care';
    final totalAmount = widget.bookingData['amount'] ?? 1497;

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
    
    int visibleLogsCount = 0;
    if (actualStartObj != null) {
      final DateTime actualStart = actualStartObj is DateTime 
          ? actualStartObj 
          : DateTime.parse(actualStartObj.toString()).toLocal();
      final DateTime referenceTime = actualEndObj != null 
          ? (actualEndObj is DateTime ? actualEndObj : DateTime.parse(actualEndObj.toString()))
          : DateTime.now();
      final elapsedMinutes = referenceTime.toUtc().difference(actualStart.toUtc()).inMinutes;
      final offsets = [70, 44, 27, 14, 0];
      for (final offset in offsets) {
        if (elapsedMinutes >= offset) visibleLogsCount++;
      }
    }

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
          automaticallyImplyLeading: false, // No back button on complete screen
          title: const Text(
            'Session complete',
            style: TextStyle(
              color: Colors.white,
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
                        '$serviceTitle · 3 hrs 2 min',
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
                          const Divider(color: Color(0xFFF0EAE4), height: 32, thickness: 1),
                          _buildDetailRow('Started', formatTime(widget.bookingData['actual_start'])),
                          const Divider(color: Color(0xFFF0EAE4), height: 32, thickness: 1),
                          _buildDetailRow('Ended', formatTime(widget.bookingData['actual_end'])),
                          const Divider(color: Color(0xFFF0EAE4), height: 32, thickness: 1),
                          _buildDetailRow('Activities logged', '$visibleLogsCount ${visibleLogsCount == 1 ? "entry" : "entries"}'),
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
                    // Update Supabase mock service state to complete this booking
                    SupabaseService.completeMockBooking(
                      caregiverName: caregiverName,
                      serviceTitle: serviceTitle,
                      amount: totalAmount,
                    );

                    // Navigate back to HomeScreen clearing stack
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => const HomeScreen()),
                      (route) => false,
                    );
                  },
                  child: const Text(
                    'Submit feedback',
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
}
