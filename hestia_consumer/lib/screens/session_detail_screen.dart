import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../services/supabase_service.dart';
import 'receipt_screen.dart';
import 'rate_session_screen.dart';

class SessionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> sessionData;
  const SessionDetailScreen({super.key, required this.sessionData});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  late Map<String, dynamic> _session;
  List<Map<String, dynamic>> _activityLog = [];
  bool _isLoadingLogs = true;

  @override
  void initState() {
    super.initState();
    _session = Map<String, dynamic>.from(widget.sessionData);
    _loadActivityLogs();
  }

  Future<void> _loadActivityLogs() async {
    final sessionId = _session['session_id'];
    if (sessionId != null) {
      final logs = await SupabaseService.getSessionActivityLogs(sessionId.toString());
      if (logs.isNotEmpty) {
        if (mounted) {
          setState(() {
            _activityLog = logs;
            _isLoadingLogs = false;
          });
        }
        return;
      }
    }
    // Fallback to mock log if DB has no entries or query fails
    if (mounted) {
      setState(() {
        _activityLog = List<Map<String, dynamic>>.from(_mockActivityLog);
        _isLoadingLogs = false;
      });
    }
  }

  final List<Map<String, String>> _mockActivityLog = [
    {
      'time': '11:51',
      'title': 'Mother settled for afternoon rest',
      'category': 'Rest support',
    },
    {
      'time': '11:22',
      'title': 'Expressed milk warmed and fed to Aryan',
      'category': 'Feeding support',
    },
    {
      'time': '10:48',
      'title': 'Newborn bathed and swaddled comfortably',
      'category': 'Bathing & grooming',
    },
    {
      'time': '10:22',
      'title': 'Breastfeeding positioning assisted',
      'category': 'Feeding support',
    },
    {
      'time': '10:05',
      'title': 'Light breakfast prepared for mother',
      'category': 'Nutrition support',
    },
    {
      'time': '09:38',
      'title': 'Session started. Checked on Aryan, settled well',
      'category': 'Check-in',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final caregiverName = _session['caregiver_name'] ?? 'Sunita Rao';
    final title = _session['title'] ?? 'Post-Delivery';
    final displayTitle = title.endsWith('Care') ? title : '$title Care';
    
    // Parse date/time strings
    final start = _session['scheduled_start'] as DateTime;
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
    
    final bool isRated = _session['isRated'] ?? false;
    final int ratingValue = _session['rating'] ?? 0;

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
            'Session detail',
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
                    // Top Session Summary Card
                    Container(
                      padding: const EdgeInsets.all(20.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFFF5EBE0),
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                displayTitle,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: HestiaColors.textDark,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F5ED),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Completed',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2E6B4A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            dateStr,
                            style: const TextStyle(
                              fontSize: 13,
                              color: HestiaColors.textMedium,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$caregiverName · $durationStr',
                            style: const TextStyle(
                              fontSize: 13,
                              color: HestiaColors.textLight,
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          const Divider(color: Color(0xFFF5EBE0), height: 1, thickness: 1.2),
                          const SizedBox(height: 16),
                          
                          // Ratings block
                          isRated
                              ? Row(
                                  children: [
                                    Row(
                                      children: List.generate(5, (idx) {
                                        return Icon(
                                          Icons.star_rounded,
                                          color: idx < ratingValue ? const Color(0xFFDCA857) : const Color(0xFFE2E2E2),
                                          size: 18,
                                        );
                                      }),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Your rating',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: HestiaColors.textLight,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                )
                              : GestureDetector(
                                  onTap: () async {
                                    final rated = await Navigator.of(context).push<bool>(
                                      MaterialPageRoute(
                                        builder: (context) => RateSessionScreen(sessionData: _session),
                                      ),
                                    );
                                    if (rated == true) {
                                      setState(() {
                                        _session['isRated'] = true;
                                        _session['rating'] = 5; // reflect locally
                                      });
                                    }
                                  },
                                  child: Row(
                                    children: const [
                                      Icon(Icons.star_outline_rounded, color: Color(0xFF8C6239), size: 18),
                                      SizedBox(width: 6),
                                      Text(
                                        'Rate this session',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF8C6239),
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Activity Log Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Activity log · ${_isLoadingLogs ? "..." : _activityLog.length} entries',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: HestiaColors.textDark,
                          ),
                        ),
                        // Download button
                        GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Downloading activity log csv...'),
                                backgroundColor: HestiaColors.primary,
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: HestiaColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.file_download_outlined, color: HestiaColors.primary, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Download',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: HestiaColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Activity log list items
                    _isLoadingLogs
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 24.0),
                              child: CircularProgressIndicator(color: HestiaColors.primary),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _activityLog.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final entry = _activityLog[index];
                              return _buildTimelineEntry(entry);
                            },
                          ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Persistent Footer Button
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
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ReceiptScreen(sessionData: _session),
                      ),
                    );
                  },
                  child: const Text(
                    'Download receipt',
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

  Widget _buildTimelineEntry(Map<String, dynamic> entry) {
    // Parse time
    String timeStr = '10:00';
    try {
      final loggedAt = entry['logged_at'];
      if (loggedAt != null) {
        final time = loggedAt is DateTime ? loggedAt : DateTime.parse(loggedAt.toString()).toLocal();
        int hour = time.hour;
        final minute = time.minute.toString().padLeft(2, '0');
        final period = hour >= 12 ? 'PM' : 'AM';
        if (hour > 12) hour -= 12;
        if (hour == 0) hour = 12;
        timeStr = '$hour:$minute $period';
      } else if (entry['time'] != null) {
        timeStr = entry['time'].toString();
      }
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF5EBE0), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time label
          Text(
            timeStr,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: HestiaColors.textMedium,
            ),
          ),
          const SizedBox(width: 12),
          // Colored Bullet point
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFFC39365),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry['note'] ?? entry['title'] ?? '',
                  style: const TextStyle(
                    fontSize: 13,
                    color: HestiaColors.textDark,
                    height: 1.35,
                  ),
                ),
                if (entry['activity_type'] != null || entry['category'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry['activity_type'] ?? entry['category']!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: HestiaColors.textLight,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
