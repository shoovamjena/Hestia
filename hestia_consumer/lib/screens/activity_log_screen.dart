import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/colors.dart';
import '../services/supabase_service.dart';

class ActivityLogScreen extends StatefulWidget {
  final Map<String, dynamic> bookingData;

  const ActivityLogScreen({super.key, required this.bookingData});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final List<Map<String, dynamic>> _activityLogs = [];
  RealtimeChannel? _activityChannel;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadActivityLogs();
    _subscribeToActivityLogs();
  }

  @override
  void dispose() {
    if (_activityChannel != null) {
      SupabaseService.client.removeChannel(_activityChannel!);
    }
    super.dispose();
  }

  Future<void> _loadActivityLogs() async {
    final sessionId = widget.bookingData['session_id']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      if (mounted) {
        setState(() {
          _activityLogs.clear();
          _isLoading = false;
        });
      }
      return;
    }

    final logs = await SupabaseService.getActivityLogs(sessionId);
    if (!mounted) return;
    setState(() {
      _activityLogs
        ..clear()
        ..addAll(logs);
      _isLoading = false;
    });
  }

  void _subscribeToActivityLogs() {
    final sessionId = widget.bookingData['session_id']?.toString();
    if (sessionId == null || sessionId.isEmpty) return;

    _activityChannel = Supabase.instance.client
        .channel('session_activity_$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'activity_logs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (payload) {
            if (!mounted) return;
            setState(() {
              _activityLogs.insert(0, Map<String, dynamic>.from(payload.newRecord));
            });
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    final bookingData = widget.bookingData;
    final caregiverName = bookingData['caregiver_name'] ?? 'Sunita Rao';
    final serviceTitle = bookingData['title'] ?? 'Post-Delivery Care';

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
              color: Colors.white,
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
                              '$caregiverName · ${formatTime(bookingData['actual_start'])}',
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
                        'Updates live',
                        style: TextStyle(
                          fontSize: 12,
                          color: HestiaColors.textLight,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: CircularProgressIndicator(color: HestiaColors.primary),
                      ),
                    )
                  else if (_activityLogs.isEmpty)
                    _glassCard(
                      padding: const EdgeInsets.all(18),
                      borderRadius: 18,
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No activity logged yet',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: HestiaColors.textDark,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Activity will appear here as the session progresses.',
                            style: TextStyle(
                              fontSize: 12,
                              color: HestiaColors.textLight,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _activityLogs.length,
                      itemBuilder: (context, index) {
                        final item = _activityLogs[index];
                        final loggedAt = item['logged_at'];
                        final isLatest = index == 0;
                        final primaryText = (item['note']?.toString().trim().isNotEmpty ?? false)
                            ? item['note'].toString().trim()
                            : (item['activity_type']?.toString() ?? 'Activity update');
                        final secondaryType = item['activity_type']?.toString() ?? 'Activity';
                        final secondaryText = '$secondaryType · ${formatTime(loggedAt)}';
                        final isLast = index == _activityLogs.length - 1;

                        return Padding(
                          padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                          child: _glassCard(
                            padding: const EdgeInsets.all(16),
                            borderRadius: 20,
                            tint: isLatest
                                ? Colors.white.withValues(alpha: 0.18)
                                : Colors.white.withValues(alpha: 0.12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: isLatest
                                        ? const Color(0x332ECC71)
                                        : Colors.white.withValues(alpha: 0.16),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.18),
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: isLatest
                                          ? const Color(0xFF2ECC71)
                                          : const Color(0xFFF3C16B),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              primaryText,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                                height: 1.35,
                                              ),
                                            ),
                                          ),
                                          if (isLatest) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0x332ECC71),
                                                borderRadius: BorderRadius.circular(999),
                                              ),
                                              child: const Text(
                                                'New',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        secondaryText,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white.withValues(alpha: 0.82),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  formatTime(loggedAt),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white.withValues(alpha: 0.86),
                                  ),
                                ),
                              ],
                            ),
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
     ),
    );
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
    double borderRadius = 20,
    Color? tint,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint ?? Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
