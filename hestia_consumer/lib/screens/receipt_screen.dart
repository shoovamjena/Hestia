import 'package:flutter/material.dart';
import '../theme/colors.dart';

class ReceiptScreen extends StatelessWidget {
  final Map<String, dynamic> sessionData;
  const ReceiptScreen({super.key, required this.sessionData});

  @override
  Widget build(BuildContext context) {
    final caregiverName = sessionData['caregiver_name'] ?? 'Sunita Rao';
    final title = sessionData['title'] ?? 'Post-Delivery';
    final displayTitle = title.endsWith('Care') ? title : '$title Care';
    final totalAmount = sessionData['amount'] ?? 1497;
    
    // Parse date/time strings
    final start = sessionData['scheduled_start'] as DateTime;
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

    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${months[start.month - 1]} ${start.day}, ${start.year}';
    final timeStr = '${formatTime(start)} – ${formatTime(end)}';

    int getServiceRate(String title) {
      final t = title.toLowerCase();
      if (t.contains('post-delivery') || t.contains('postdelivery')) return 499;
      if (t.contains('babysitting')) return 399;
      if (t.contains('mobility')) return 449;
      if (t.contains('pre-pregnancy') || t.contains('prepregnancy')) return 599;
      if (t.contains('bathing')) return 349;
      if (t.contains('concierge')) return 299;
      return 499; // Fallback
    }

    return Container(
        color: HestiaColors.appBackground,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          leading: Padding(
            padding: const EdgeInsets.all(8.0),
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
          title: const Text(
            'Receipt',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: HestiaColors.textDark,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.share_outlined, color: HestiaColors.textDark),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Receipt link copied to clipboard!'),
                    backgroundColor: HestiaColors.primary,
                  ),
                );
              },
            ),
          ],
        ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Header amount area
            Column(
              children: [
                const Text(
                  'AMOUNT PAID',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFDCD2C9),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '₹${totalAmount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$displayTitle · $dateStr',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFDCD2C9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                // Paid Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Paid · collected after session',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // White bottom sheet container
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFFCFCFC),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                  child: Column(
                    children: [
                      // Detailed breakdown card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFF5EBE0),
                            width: 1.2,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x03000000),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _buildReceiptRow('Service', displayTitle),
                            const Divider(color: Color(0xFFFAF2EB), height: 28, thickness: 1),
                            _buildReceiptRow('Professional', caregiverName),
                            const Divider(color: Color(0xFFFAF2EB), height: 28, thickness: 1),
                            _buildReceiptRow('Date', dateStr),
                            const Divider(color: Color(0xFFFAF2EB), height: 28, thickness: 1),
                            _buildReceiptRow('Time', timeStr),
                            const Divider(color: Color(0xFFFAF2EB), height: 28, thickness: 1),
                            _buildReceiptRow('Duration', durationStr),
                            const Divider(color: Color(0xFFFAF2EB), height: 28, thickness: 1),
                            _buildReceiptRow('Rate', '₹${getServiceRate(title)} / hr'),
                            const Divider(color: Color(0xFFFAF2EB), height: 28, thickness: 1),
                            _buildReceiptRow('Member', 'Aryan (Newborn)'),
                            const Divider(color: Color(0xFFFAF2EB), height: 28, thickness: 1),
                            _buildReceiptRow('Payment', 'UPI · collected after session', isBoldValue: false),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 32),

                      // Download action button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: HestiaColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Downloading receipt PDF...'),
                                backgroundColor: Color(0xFF2E6B4A),
                              ),
                            );
                          },
                          icon: const Icon(Icons.file_download_outlined, size: 20),
                          label: const Text(
                            'Download PDF Receipt',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
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

  Widget _buildReceiptRow(String label, String value, {bool isBoldValue = true}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: HestiaColors.textLight,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBoldValue ? FontWeight.bold : FontWeight.w500,
              color: HestiaColors.textDark,
            ),
          ),
        ),
      ],
    );
  }
}
