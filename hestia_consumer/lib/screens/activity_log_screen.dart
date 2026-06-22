import 'package:flutter/material.dart';
import '../theme/colors.dart';

class ActivityLogScreen extends StatelessWidget {
  final Map<String, dynamic> bookingData;

  const ActivityLogScreen({super.key, required this.bookingData});

  @override
  Widget build(BuildContext context) {
    final caregiverName = bookingData['caregiver_name'] ?? 'Sunita Rao';
    final serviceTitle = bookingData['title'] ?? 'Post-Delivery Care';

    // Timeline items list matching the image specifications
    final List<Map<String, dynamic>> timelineItems = [
      {
        'time': '10:48',
        'title': 'Newborn bathed and swaddled',
        'subtitle': 'Bathing & grooming',
        'isLatest': true,
        'isGreenDot': true,
      },
      {
        'time': '10:22',
        'title': 'Breastfeeding positioning assisted',
        'subtitle': 'Feeding support',
        'isLatest': false,
        'isGreenDot': false,
      },
      {
        'time': '10:05',
        'title': 'Light breakfast prepared for mother',
        'subtitle': 'Meal assistance',
        'isLatest': false,
        'isGreenDot': false,
      },
      {
        'time': '09:52',
        'title': 'Mother rest period — Aryan monitored',
        'subtitle': 'Rest support',
        'isLatest': false,
        'isGreenDot': false,
      },
      {
        'time': '09:38',
        'title': 'Session started. Initial check completed',
        'subtitle': 'Session start',
        'isLatest': false,
        'isGreenDot': false,
      },
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFFCFCFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
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
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.chevron_left_rounded,
                color: HestiaColors.primary,
                size: 22,
              ),
            ),
          ),
        ),
        title: const Text(
          'Activity log',
          style: TextStyle(
            color: HestiaColors.textDark,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Live Header Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDF8F5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: HestiaColors.primary.withValues(alpha: 0.08),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Today · $serviceTitle',
                              style: const TextStyle(
                                fontSize: 13,
                                color: HestiaColors.textLight,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$caregiverName · 9:00 AM',
                              style: const TextStyle(
                                fontSize: 16,
                                color: HestiaColors.textDark,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        // Live badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF2E7D32),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Live',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2E7D32),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Sub-tabs row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        'All entries',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: HestiaColors.textDark,
                        ),
                      ),
                      Text(
                        'Auto-refreshes every 60s',
                        style: TextStyle(
                          fontSize: 12,
                          color: HestiaColors.textLight,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Timeline list
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: timelineItems.length,
                    itemBuilder: (context, index) {
                      final item = timelineItems[index];
                      final isLast = index == timelineItems.length - 1;

                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Time column
                            SizedBox(
                              width: 44,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text(
                                  item['time'],
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: HestiaColors.textLight,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Timeline node connector column
                            Column(
                              children: [
                                // Dot
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(top: 6),
                                  decoration: BoxDecoration(
                                    color: item['isGreenDot']
                                        ? const Color(0xFF2ECC71)
                                        : const Color(0xFFF39C12),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                // Line
                                if (!isLast)
                                  Expanded(
                                    child: Container(
                                      width: 1.5,
                                      color: const Color(0xFFE5DDD5),
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 14),

                            // Timeline details column
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 24.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item['title'],
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: HestiaColors.textDark,
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                        if (item['isLatest']) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE8F5E9),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'New',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF2E7D32),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item['subtitle'],
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: HestiaColors.textLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Download sticky footer
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Downloading activity log...'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text(
                      'Download full log',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: HestiaColors.textDark,
                      ),
                    ),
                    Icon(
                      Icons.download_rounded,
                      color: HestiaColors.primary,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
