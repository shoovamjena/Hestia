import 'package:flutter/material.dart';
import '../theme/colors.dart';

class TimeSlotBottomSheet extends StatefulWidget {
  final void Function(DateTime date, String timeSlot) onConfirm;
  final DateTime? initialDate;
  final String? initialTimeSlot;

  const TimeSlotBottomSheet({
    super.key,
    required this.onConfirm,
    this.initialDate,
    this.initialTimeSlot,
  });

  @override
  State<TimeSlotBottomSheet> createState() => _TimeSlotBottomSheetState();
}

class _TimeSlotBottomSheetState extends State<TimeSlotBottomSheet> {
  int _selectedDateIndex = 0;
  String? _selectedTime;

  // All potential slots (Morning/afternoon and evening slots).
  final List<String> _allSlots = [
    '7:00 AM',
    '7:30 AM',
    '8:00 AM',
    '8:30 AM',
    '9:00 AM', // disabled on future days
    '9:30 AM',
    '10:00 AM',
    '10:30 AM',
    '11:00 AM',
    '11:30 AM',
    '12:00 PM',
    '12:30 PM',
    '1:00 PM',
    '1:30 PM',
    '2:00 PM',
    '2:30 PM',
    '3:00 PM',
    '3:30 PM',
    '4:00 PM',
    '4:30 PM',
    '5:00 PM',
    '5:30 PM',
    '6:00 PM',
    '6:30 PM',
    '7:00 PM', // disabled on today
    '7:30 PM',
    '8:00 PM', // disabled
    '8:30 PM', // disabled
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialTimeSlot != null) {
      final currentSlots = _getCurrentSlots();
      final isDisabled = _isSlotDisabled(widget.initialTimeSlot!);
      if (currentSlots.contains(widget.initialTimeSlot) && !isDisabled) {
        _selectedTime = widget.initialTimeSlot;
      }
    }
  }

  DateTime? _parseSlotTimeToToday(String slotStr) {
    try {
      final parts = slotStr.split(' ');
      if (parts.length != 2) return null;
      final timeParts = parts[0].split(':');
      if (timeParts.length != 2) return null;
      int hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final amPm = parts[1].toUpperCase();

      if (amPm == 'PM' && hour != 12) {
        hour += 12;
      } else if (amPm == 'AM' && hour == 12) {
        hour = 0;
      }

      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  bool _isDateToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  List<String> _getCurrentSlots() {
    final dates = _getDates();
    final selectedDate = dates[_selectedDateIndex];
    if (_isDateToday(selectedDate)) {
      // Today: start the slots from 1 hour later as of current time
      final limitTime = DateTime.now().add(const Duration(hours: 1));
      return _allSlots.where((slot) {
        final slotTime = _parseSlotTimeToToday(slot);
        if (slotTime == null) return false;
        return slotTime.isAfter(limitTime);
      }).toList();
    } else {
      return _allSlots;
    }
  }

  bool _isSlotDisabled(String slot) {
    final dates = _getDates();
    final selectedDate = dates[_selectedDateIndex];
    if (_isDateToday(selectedDate)) {
      // Today: 7:00 PM, 8:00 PM, 8:30 PM are disabled
      return slot == '7:00 PM' || slot == '8:00 PM' || slot == '8:30 PM';
    } else {
      // Future days: 9:00 AM, 8:00 PM, 8:30 PM are disabled
      return slot == '9:00 AM' || slot == '8:00 PM' || slot == '8:30 PM';
    }
  }

  List<DateTime> _getDates() {
    final start = widget.initialDate ?? DateTime.now();
    return List.generate(4, (index) => start.add(Duration(days: index)));
  }

  String _getMonthName(int month) {
    const actualMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return actualMonths[month - 1];
  }

  String _getWeekdayName(DateTime date, int index) {
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) return 'Today';
    
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = date.year == tomorrow.year && date.month == tomorrow.month && date.day == tomorrow.day;
    if (isTomorrow) return 'Tomorrow';
    
    const weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    return weekdays[date.weekday % 7];
  }

  @override
  Widget build(BuildContext context) {
    final dates = _getDates();
    final isConfirmEnabled = _selectedTime != null;
    final currentSlots = _getCurrentSlots();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title and Close Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Select start time of service',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: HestiaColors.textDark,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: HestiaColors.textMedium,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Date Tabs Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(dates.length, (index) {
              final date = dates[index];
              final isSelected = index == _selectedDateIndex;
              final month = _getMonthName(date.month);
              final weekday = _getWeekdayName(date, index);

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDateIndex = index;
                      _selectedTime = null; // Reset selected time when date changes
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isSelected ? HestiaColors.primary : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${date.day} $month',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? HestiaColors.primary : HestiaColors.textMedium,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          weekday,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isSelected ? HestiaColors.primary : HestiaColors.textLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),

          // Start Times Grid
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 245),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: currentSlots.length,
              itemBuilder: (context, index) {
                final time = currentSlots[index];
                final isDisabled = _isSlotDisabled(time);
                final isSelected = time == _selectedTime;

                return GestureDetector(
                  onTap: isDisabled
                      ? null
                      : () {
                          setState(() {
                            _selectedTime = time;
                          });
                        },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDisabled
                          ? const Color(0xFFF3F3F5)
                          : isSelected
                              ? HestiaColors.primary
                              : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDisabled
                            ? Colors.transparent
                            : isSelected
                                ? HestiaColors.primary
                                : Colors.grey.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      time,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDisabled
                            ? Colors.grey.shade400
                            : isSelected
                                ? Colors.white
                                : HestiaColors.textDark,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Text Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2F1), // Light teal background container
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Professional will arrive within 30 mins of the selected slot.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFF004D40), // Dark green/teal text
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Confirm Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: isConfirmEnabled
                  ? () {
                      final selectedDate = dates[_selectedDateIndex];
                      widget.onConfirm(selectedDate, _selectedTime!);
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: HestiaColors.primary,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Confirm',
                style: TextStyle(
                  color: isConfirmEnabled ? Colors.white : Colors.grey.shade500,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
