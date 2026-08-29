import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../config/razorpay_config.dart';
import '../theme/colors.dart';
import '../services/supabase_service.dart';
import '../utils/string_format.dart';

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
  bool _addTip = false;
  int _tipAmount = 0;
  int? _selectedTipPreset;
  bool _isSubmitting = false;

  final Set<String> _selectedTags = {'Punctual', 'Caring', 'Great with Aryan'};
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _tipController = TextEditingController();
  late Razorpay _razorpay;

  static const List<int> _tipPresets = [50, 100, 200];

  final List<String> _feedbackTags = [
    'Punctual',
    'Caring',
    'Great with Aryan',
    'Professional',
    'Thorough',
  ];

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleTipPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleTipPaymentError);
  }

  @override
  void dispose() {
    _commentController.dispose();
    _tipController.dispose();
    _razorpay.clear();
    super.dispose();
  }

  int _getTipAmount() {
    if (!_addTip) return 0;
    final parsed = int.tryParse(_tipController.text.trim());
    if (parsed != null && parsed > 0) return parsed;
    return _tipAmount > 0 ? _tipAmount : 0;
  }

  void _setTipAmount(int amount) {
    setState(() {
      _tipAmount = amount;
      _selectedTipPreset = _tipPresets.contains(amount) ? amount : null;
      _tipController.text = amount > 0 ? amount.toString() : '';
    });
  }

  void _handleTipPaymentSuccess(PaymentSuccessResponse response) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: HestiaColors.primary),
      ),
    );
    _completeSubmission(
      tipAmount: _getTipAmount(),
      tipPaymentId: response.paymentId,
    );
  }

  void _handleTipPaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Tip payment failed: ${response.message ?? 'Payment cancelled'}',
        ),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  Future<void> _submitFeedback() async {
    if (_isSubmitting) return;

    if (_addTip && _getTipAmount() <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a tip amount or turn off tipping'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final tip = _getTipAmount();
    if (tip > 0) {
      setState(() => _isSubmitting = true);
      final caregiverName = displayPersonName(
        widget.sessionData['caregiver_name']?.toString(),
        fallback: 'your professional',
      );
      final authEmail = SupabaseService.currentUserEmail;

      try {
        _razorpay.open({
          'key': RazorpayConfig.keyId,
          'amount': tip * 100,
          'name': 'Hestia',
          'description': 'Tip for $caregiverName',
          'timeout': 300,
          'prefill': {
            'email': authEmail.isNotEmpty ? authEmail : 'user@example.com',
          },
        });
      } catch (e) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open payment: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    await _completeSubmission();
  }

  Future<void> _completeSubmission({
    int tipAmount = 0,
    String? tipPaymentId,
  }) async {
    if (!mounted) return;

    final bookingId = widget.sessionData['booking_id'] ?? 'mock-session-1';

    if (!_isSubmitting) {
      setState(() => _isSubmitting = true);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: HestiaColors.primary),
        ),
      );
    }

    try {
      await SupabaseService.rateSession(
        bookingId,
        overallRating: _overallRating,
        punctuality: _punctualityRating,
        professionalism: _professionalismRating,
        qualityOfCare: _qualityRating,
        tags: _selectedTags.toList(),
        comment: _commentController.text.trim(),
        tipAmount: tipAmount,
        tipPaymentId: tipPaymentId,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // loader

      final message = tipAmount > 0
          ? 'Thank you! Your feedback and ₹$tipAmount tip were sent.'
          : 'Feedback submitted successfully! Thank you.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFF2E6B4A),
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit feedback: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Widget _buildTipSection(String caregiverName) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _addTip
              ? HestiaColors.primary.withValues(alpha: 0.35)
              : HestiaColors.primary.withValues(alpha: 0.15),
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
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              setState(() {
                _addTip = !_addTip;
                if (!_addTip) {
                  _tipAmount = 0;
                  _selectedTipPreset = null;
                  _tipController.clear();
                } else if (_tipAmount == 0) {
                  _setTipAmount(_tipPresets[1]);
                }
              });
            },
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: _addTip,
                    activeColor: HestiaColors.primary,
                    side: BorderSide(color: Colors.grey.shade400),
                    onChanged: (checked) {
                      setState(() {
                        _addTip = checked ?? false;
                        if (!_addTip) {
                          _tipAmount = 0;
                          _selectedTipPreset = null;
                          _tipController.clear();
                        } else if (_tipAmount == 0) {
                          _setTipAmount(_tipPresets[1]);
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.favorite_outline,
                  color: HestiaColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tip $caregiverName',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: HestiaColors.textDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_addTip) ...[
            const SizedBox(height: 8),
            Text(
              '100% of your tip goes directly to your caregiver.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _tipController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: 'Enter tip amount',
                prefixText: '₹ ',
                prefixStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: HestiaColors.textDark,
                ),
                filled: true,
                fillColor: const Color(0xFFFAF7F4),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: HestiaColors.primary,
                    width: 1.4,
                  ),
                ),
              ),
              onChanged: (value) {
                final amount = int.tryParse(value.trim()) ?? 0;
                setState(() {
                  _tipAmount = amount;
                  _selectedTipPreset =
                      _tipPresets.contains(amount) ? amount : null;
                });
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: _tipPresets.map((preset) {
                final isSelected = _selectedTipPreset == preset;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: preset == _tipPresets.last ? 0 : 8,
                    ),
                    child: OutlinedButton(
                      onPressed: () => _setTipAmount(preset),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            isSelected ? Colors.white : HestiaColors.primary,
                        backgroundColor:
                            isSelected ? HestiaColors.primary : Colors.white,
                        side: BorderSide(
                          color: HestiaColors.primary.withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        '₹$preset',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final caregiverName = displayPersonName(
      widget.sessionData['caregiver_name']?.toString(),
      fallback: 'Sunita Rao',
    );
    final title = widget.sessionData['title'] ?? 'Post-Delivery';
    final displayTitle = title.endsWith('Care') ? title : '$title Care';
    final professionalRating =
        double.tryParse(widget.sessionData['professional_rating']?.toString() ?? '');
    final professionalSessions =
        int.tryParse(widget.sessionData['professional_total_sessions']?.toString() ?? '') ?? 0;

    final start = (widget.sessionData['actual_start'] ?? widget.sessionData['scheduled_start']) as DateTime;
    final explicitEnd = widget.sessionData['actual_end'] as DateTime?;
    final durationHours = (widget.sessionData['duration_hours'] as num?)?.toDouble() ?? 2.0;
    final end = explicitEnd ?? start.add(Duration(minutes: (durationHours * 60).round()));
    final durationStr = _formatDuration(start, end, durationHours);

    String formatTime(DateTime time) {
      int hour = time.hour;
      final minute = time.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;
      return '$hour:$minute $period';
    }

    final dateStr = 'Today · ${formatTime(start)} – ${formatTime(end)}';
    final tip = _getTipAmount();
    final submitLabel = tip > 0
        ? 'Submit & pay ₹$tip tip'
        : 'Submit feedback';

    return Container(
        color: HestiaColors.appBackground,
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
              color: HestiaColors.textDark,
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
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF2EB),
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
                                if (professionalRating != null && professionalRating > 0) ...[
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        size: 14,
                                        color: Color(0xFFDCA857),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        professionalSessions > 0
                                            ? '${professionalRating.toStringAsFixed(1)} ($professionalSessions ${professionalSessions == 1 ? "session" : "sessions"})'
                                            : professionalRating.toStringAsFixed(1),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: HestiaColors.textLight,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                ],
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

                    const SizedBox(height: 24),
                    _buildTipSection(caregiverName),

                    const SizedBox(height: 28),

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
                  onPressed: _isSubmitting ? null : _submitFeedback,
                  child: Text(
                    submitLabel,
                    style: const TextStyle(
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

  String _formatDuration(DateTime start, DateTime end, double fallbackHours) {
    int minutes = end.toUtc().difference(start.toUtc()).inMinutes;
    if (minutes <= 0) {
      minutes = (fallbackHours * 60).round();
    }
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    if (hours == 0) return '$remaining min';
    if (remaining == 0) return '$hours hr';
    return '$hours hr $remaining min';
  }
}
