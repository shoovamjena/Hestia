import 'package:flutter/material.dart';
import '../theme/colors.dart';
import 'repeat_booking_screen.dart';

class ScheduleScreen extends StatefulWidget {
  final String serviceTitle;

  const ScheduleScreen({
    super.key,
    required this.serviceTitle,
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  // Initial selected date is June 12, 2026
  DateTime _selectedDate = DateTime(2026, 6, 12);
  final DateTime _today = DateTime(2026, 6, 9); // Defined as June 9, 2026 per current local time & design
  
  String _selectedTime = '9:00 AM';
  String _selectedDuration = '3 hrs';
  int _durationOffsetMinutes = 0; // Cumulative offset in minutes (can be +/- multiples of 30)
  bool _isMinButtonFlashing = false;
  bool _isPlusButtonFlashing = false;

  int _getBaseHours() {
    final regExp = RegExp(r'(\d+)');
    final match = regExp.firstMatch(_selectedDuration);
    if (match != null) {
      return int.parse(match.group(1)!);
    }
    return 3; // Fallback
  }

  // Format combined duration based on total minutes
  String _getCombinedDuration() {
    final baseHours = _getBaseHours();
    final totalMinutes = baseHours * 60 + _durationOffsetMinutes;
    if (totalMinutes <= 0) {
      return '0 mins';
    }
    
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    
    if (hours == 0) {
      return '$mins mins';
    } else if (mins == 0) {
      return '$hours ${hours == 1 ? "hr" : "hrs"}';
    } else {
      return '$hours ${hours == 1 ? "hr" : "hrs"} $mins mins';
    }
  }

  Widget _buildOffsetButton(String label, int val) {
    final isPlus = val > 0;
    final isSelected = isPlus ? _isPlusButtonFlashing : _isMinButtonFlashing;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isPlus) {
            _isPlusButtonFlashing = true;
            _durationOffsetMinutes += 30;
          } else {
            _isMinButtonFlashing = true;
            // Prevent total duration going below 30 minutes
            final baseHours = _getBaseHours();
            final currentTotalMinutes = baseHours * 60 + _durationOffsetMinutes;
            if (currentTotalMinutes > 30) {
              _durationOffsetMinutes -= 30;
            }
          }
        });
        
        // Tap animation: fill only for a split second (150ms) then unfill
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) {
            setState(() {
              if (isPlus) {
                _isPlusButtonFlashing = false;
              } else {
                _isMinButtonFlashing = false;
              }
            });
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? HestiaColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: HestiaColors.primary,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 4,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : HestiaColors.textDark,
          ),
        ),
      ),
    );
  }

  // Days in June 2026: 30 days. Starts on Monday (index 1 of week).
  final int _daysInMonth = 30;
  final int _startWeekdayOffset = 1; // June 1, 2026 is Monday (0 offset for Sunday start? No, Monday is index 1, meaning Sunday is 0. So offset is 1 empty space under Sunday).

  final List<String> _timeSlots = [
    '7:00 AM', // Now completely selectable
    '8:00 AM',
    '9:00 AM',
    '10:00 AM',
    '11:00 AM',
    '2:00 PM',
  ];

  final List<String> _durations = [
    '2 hrs',
    '3 hrs',
    '4 hrs',
    '8 hrs',
  ];

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
                        child: const Text(
                          'Schedule',
                          style: TextStyle(
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

              // Scrollable Options
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),

                      // Calendar Card Container
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: HestiaColors.primary,
                            width: 1,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 5,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Calendar Header: "< June 2026 >"
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.chevron_left, color: HestiaColors.textLight),
                                  onPressed: () {}, // Month change locked per mockup
                                ),
                                const Text(
                                  'June 2026',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: HestiaColors.textDark,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.chevron_right, color: HestiaColors.textLight),
                                  onPressed: () {}, // Month change locked per mockup
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // S M T W T F S row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: const [
                                _WeekdayHeader('S'),
                                _WeekdayHeader('M'),
                                _WeekdayHeader('T'),
                                _WeekdayHeader('W'),
                                _WeekdayHeader('T'),
                                _WeekdayHeader('F'),
                                _WeekdayHeader('S'),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Calendar Grid
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                              ),
                              itemCount: _daysInMonth + _startWeekdayOffset,
                              itemBuilder: (context, index) {
                                if (index < _startWeekdayOffset) {
                                  return const SizedBox.shrink(); // Empty space
                                }

                                final dayNum = index - _startWeekdayOffset + 1;
                                final date = DateTime(2026, 6, dayNum);
                                
                                final isToday = date.day == _today.day && date.month == _today.month && date.year == _today.year;
                                final isSelected = date.day == _selectedDate.day && date.month == _selectedDate.month && date.year == _selectedDate.year;
                                final isPast = date.isBefore(_today);

                                return GestureDetector(
                                  onTap: isPast
                                      ? null
                                      : () {
                                          setState(() {
                                            _selectedDate = date;
                                          });
                                        },
                                  child: Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.rectangle,
                                      borderRadius: BorderRadius.circular(10),
                                      color: isSelected
                                          ? HestiaColors.primary
                                          : Colors.transparent,
                                      border: isToday && !isSelected
                                          ? Border.all(color: HestiaColors.primary, width: 1.5)
                                          : null,
                                    ),
                                    child: Text(
                                      '$dayNum',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isSelected || isToday
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isSelected
                                            ? Colors.white
                                            : isPast
                                                ? Colors.grey.shade300
                                                : HestiaColors.textDark,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Time Section Heading
                      const Text(
                        'Time',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: HestiaColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Time Selection Grid
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 2.2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: _timeSlots.length,
                        itemBuilder: (context, index) {
                          final time = _timeSlots[index];
                          final isSelected = time == _selectedTime;

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedTime = time;
                              });
                            },
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? HestiaColors.primary
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: HestiaColors.primary,
                                  width: isSelected ? 2.0 : 1.0,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x12000000),
                                    blurRadius: 4,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Text(
                                time,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected
                                      ? Colors.white
                                      : HestiaColors.textDark,
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      // Duration Section Heading
                      const Text(
                        'Duration',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: HestiaColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Duration Selector Row
                      Row(
                        children: _durations.map((duration) {
                          final isSelected = duration == _selectedDuration;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedDuration = duration;
                                    _durationOffsetMinutes = 0; // Reset offset when selecting base duration
                                  });
                                },
                                child: Container(
                                  height: 44,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? HestiaColors.primary
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: HestiaColors.primary,
                                      width: isSelected ? 2.0 : 1.0,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x12000000),
                                        blurRadius: 4,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    duration,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isSelected
                                          ? Colors.white
                                          : HestiaColors.textDark,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 16),

                      // Duration Offset Buttons (+/- 30 mins) with central dynamic filled pill
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildOffsetButton('- 30 mins', -30),
                          const SizedBox(width: 12),
                          
                          // Dynamic Filled Pill showing combined duration with increased height
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                            decoration: BoxDecoration(
                              color: HestiaColors.primary,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x14000000),
                                  blurRadius: 5,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Text(
                              _getCombinedDuration(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          
                          const SizedBox(width: 12),
                          _buildOffsetButton('+ 30 mins', 30),
                        ],
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // Sticky Bottom Continue Button
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
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => RepeatBookingScreen(
                                serviceTitle: widget.serviceTitle,
                                selectedDate: _selectedDate,
                                selectedTime: _selectedTime,
                                selectedDuration: _getCombinedDuration(),
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
}

class _WeekdayHeader extends StatelessWidget {
  final String label;
  const _WeekdayHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: HestiaColors.textLight,
        ),
      ),
    );
  }
}
