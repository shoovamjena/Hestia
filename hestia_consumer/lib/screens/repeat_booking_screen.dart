import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import 'choose_professional_screen.dart';
import 'time_slot_bottom_sheet.dart';

class RepeatBookingScreen extends StatefulWidget {
  final String serviceTitle;
  final DateTime selectedDate;
  final String? selectedTime;
  final String selectedDuration;

  const RepeatBookingScreen({
    super.key,
    required this.serviceTitle,
    required this.selectedDate,
    this.selectedTime,
    required this.selectedDuration,
  });

  @override
  State<RepeatBookingScreen> createState() => _RepeatBookingScreenState();
}

class _RepeatBookingScreenState extends State<RepeatBookingScreen> {
  // Frequency
  String _selectedFrequency = 'Everyday';

  int _getServiceRate() {
    final title = widget.serviceTitle.toLowerCase();
    if (title.contains('post-delivery') || title.contains('postdelivery')) return 499;
    if (title.contains('babysitting')) return 399;
    if (title.contains('mobility')) return 449;
    if (title.contains('pre-pregnancy') || title.contains('prepregnancy')) return 599;
    if (title.contains('bathing')) return 349;
    if (title.contains('concierge')) return 299;
    return 499; // Fallback
  }

  // Duration chips
  List<Map<String, dynamic>> get _durations {
    final rate = _getServiceRate();
    return [
      {'label': '0.5 hr', 'price': '₹${(rate * 0.5).toInt()}', 'value': 0.5},
      {'label': '1 hr', 'price': '₹$rate', 'value': 1.0},
      {'label': '1.5 hrs', 'price': '₹${(rate * 1.5).toInt()}', 'value': 1.5},
      {'label': '2 hrs', 'price': '₹${(rate * 2.0).toInt()}', 'value': 2.0},
    ];
  }
  double _selectedDurationValue = 0.5;

  // Date range
  late DateTime _startDate;
  late DateTime _endDate;

  // Computed visits
  int get _visitCount {
    final diff = _endDate.difference(_startDate).inDays;
    if (_selectedFrequency == 'Everyday') return diff + 1;
    if (_selectedFrequency == 'Weekly') return (diff / 7).floor() + 1;
    if (_selectedFrequency == 'Alternate Days') return (diff / 2).floor() + 1;
    return diff + 1;
  }

  String? _selectedTimeSlot;

  // Frequency options
  final List<String> _frequencyOptions = [
    'Everyday',
    'Alternate Days',
    'Weekly',
  ];

  @override
  void initState() {
    super.initState();
    _startDate = widget.selectedDate;
    _endDate = _startDate.add(const Duration(days: 29));
    final initialTime = widget.selectedTime?.trim();
    if (initialTime != null && initialTime.isNotEmpty) {
      _selectedTimeSlot = initialTime;
    }
  }

  String _formatMonthDay(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  String get _selectedDurationLabel {
    final match = _durations.firstWhere(
      (d) => d['value'] == _selectedDurationValue,
      orElse: () => _durations.first,
    );
    return match['label'] as String;
  }

  void _showFrequencySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Frequency',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: HestiaColors.textDark,
                  ),
                ),
                const SizedBox(height: 16),
                ..._frequencyOptions.map((option) {
                  final isSelected = option == _selectedFrequency;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedFrequency = option);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? HestiaColors.primary.withValues(alpha: 0.08)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? HestiaColors.primary
                              : HestiaColors.inputBorder,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              option,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: HestiaColors.textDark,
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check,
                                color: HestiaColors.primary, size: 20),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: HestiaColors.primary,
              onPrimary: Colors.white,
              onSurface: HestiaColors.textDark,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          _selectedTimeSlot = null; // Reset selected time slot when start date changes
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate.add(const Duration(days: 29));
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  void _openTimeSlotBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TimeSlotBottomSheet(
        initialDate: _startDate,
        initialTimeSlot: _selectedTimeSlot,
        onConfirm: (selectedDate, timeSlot) {
          setState(() {
            _startDate = selectedDate;
            _selectedTimeSlot = timeSlot;
            if (_endDate.isBefore(_startDate)) {
              _endDate = _startDate.add(const Duration(days: 29));
            }
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  bool get _canContinue => _selectedTimeSlot != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 252, 252, 252),
      body: Container(
        color: HestiaColors.appBackground,
        child: SafeArea(
          child: Column(
            children: [
              // ── App Bar ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 12.0),
                child: Row(
                  children: [
                    // Back Button (Circular)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                      },
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
                    // Title (Centered)
                    Expanded(
                      child: Center(
                        child: const Text(
                          'Recurring Booking',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // Balance spacer
                    const SizedBox(width: 44),
                  ],
                ),
              ),

              // ── Scrollable Body ──────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20.0, vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Select Frequency ───────────────────────────
                      _sectionTitle('Select Frequency', light: true),
                      const SizedBox(height: 2),
                      const Text(
                        'Days when you want this service for',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white60,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: _showFrequencySheet,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _selectedFrequency,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: HestiaColors.textDark,
                                  ),
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: HestiaColors.primary, size: 22),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── How long? ──────────────────────────────────
                      _sectionTitle('How long do you want this service for?'),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              // Start date
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _pickDate(isStart: true),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              'Start date',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF1E1E1E),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            const Icon(Icons.edit,
                                                color: HestiaColors.primary,
                                                size: 13),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _formatMonthDay(_startDate),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: HestiaColors.textDark,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              VerticalDivider(
                                  color: Colors.grey.shade200,
                                  width: 1,
                                  thickness: 1),
                              // End date
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _pickDate(isStart: false),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                             Text(
                                               'End date',
                                               style: const TextStyle(
                                                 fontSize: 12,
                                                 color: Color(0xFF1E1E1E),
                                               ),
                                             ),
                                            const SizedBox(width: 4),
                                            const Icon(Icons.edit,
                                                color: HestiaColors.primary,
                                                size: 13),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _formatMonthDay(_endDate),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: HestiaColors.textDark,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              VerticalDivider(
                                  color: Colors.grey.shade200,
                                  width: 1,
                                  thickness: 1),
                              // Visits
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Visits',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF1E1E1E),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '$_visitCount',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: HestiaColors.textDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── Select Duration ────────────────────────────
                      _sectionTitle('Select Duration'),
                      const SizedBox(height: 12),
                      Row(
                        children: _durations.map((dur) {
                          final isSelected =
                              dur['value'] == _selectedDurationValue;
                          return Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4.0),
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedDurationValue =
                                        dur['value'] as double;
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? HestiaColors.primary
                                          : HestiaColors.inputBorder,
                                      width: isSelected ? 2.0 : 1.0,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x0A000000),
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        dur['label'] as String,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: HestiaColors.textDark,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        dur['price'] as String,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isSelected
                                              ? HestiaColors.primary
                                              : const Color(0xFF1E1E1E),
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 24),

                      // ── Select Time Slot ───────────────────────────
                      _sectionTitle('Select Time Slot'),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () => _openTimeSlotBottomSheet(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.timer_outlined,
                                  color: HestiaColors.primary, size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Preferred slot',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: HestiaColors.textMedium,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _selectedTimeSlot ?? 'Select slot',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: _selectedTimeSlot != null
                                            ? HestiaColors.textDark
                                            : HestiaColors.textMedium,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: HestiaColors.primary, size: 22),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // ── Continue booking button ────────────────────────────
              SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(20.0, 8.0, 20.0, 20.0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _canContinue
                          ? HestiaColors.primary
                          : const Color(0xFFCFCFCF),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: _canContinue
                          ? [
                              BoxShadow(
                                color: HestiaColors.primary
                                    .withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : [],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(28),
                        onTap: _canContinue
                            ? () {
                                HapticFeedback.lightImpact();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        ChooseProfessionalScreen(
                                      serviceTitle: widget.serviceTitle,
                                      selectedDate: _startDate,
                                      selectedTime: _selectedTimeSlot!,
                                      selectedDuration: _selectedDurationLabel,
                                      repeatOption: _selectedFrequency,
                                      endsAfter:
                                          _formatMonthDay(_endDate),
                                      preferSameProfessional: true,
                                    ),
                                  ),
                                );
                              }
                            : null,
                        child: const Center(
                          child: Text(
                            'Continue booking',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
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

  Widget _sectionTitle(String title, {bool light = false}) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: light ? Colors.white : HestiaColors.textDark,
      ),
    );
  }
}
