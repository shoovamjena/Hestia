import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/colors.dart';
import '../services/supabase_service.dart';
import '../utils/string_format.dart';

class ActivityLogScreen extends StatefulWidget {
  final Map<String, dynamic> bookingData;

  const ActivityLogScreen({super.key, required this.bookingData});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final List<Map<String, dynamic>> _activityLogs = [];
  RealtimeChannel? _activityChannel;
  Timer? _pollTimer;
  bool _isLoading = true;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadActivityLogs();
    _subscribeToActivityLogs();
    // Fallback poll so logs still appear if realtime is delayed.
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _loadActivityLogs(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (_activityChannel != null) {
      SupabaseService.client.removeChannel(_activityChannel!);
    }
    super.dispose();
  }

  String? get _sessionId => widget.bookingData['session_id']?.toString();

  String _logKey(Map<String, dynamic> log) {
    final id = log['id']?.toString();
    if (id != null && id.isNotEmpty) return id;
    return '${log['logged_at']}|${log['activity_type']}|${log['note']}';
  }

  void _mergeLogs(List<Map<String, dynamic>> incoming, {bool replace = false}) {
    if (replace) {
      _activityLogs
        ..clear()
        ..addAll(incoming);
      return;
    }

    final existing = <String>{};
    for (final log in _activityLogs) {
      existing.add(_logKey(log));
    }

    for (final log in incoming.reversed) {
      final key = _logKey(log);
      if (existing.contains(key)) continue;
      existing.add(key);
      _activityLogs.insert(0, Map<String, dynamic>.from(log));
    }

    _activityLogs.sort((a, b) {
      final aTime = DateTime.tryParse(a['logged_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = DateTime.tryParse(b['logged_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
  }

  Future<void> _loadActivityLogs({bool silent = false}) async {
    final sessionId = _sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      if (mounted) {
        setState(() {
          _activityLogs.clear();
          _isLoading = false;
        });
      }
      return;
    }

    if (_isRefreshing) return;
    _isRefreshing = true;

    try {
      final logs = await SupabaseService.getActivityLogs(sessionId);
      if (!mounted) return;
      setState(() {
        _mergeLogs(logs, replace: true);
        _isLoading = false;
      });
    } finally {
      _isRefreshing = false;
      if (!silent && mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _upsertRealtimeLog(Map<String, dynamic> record) {
    if (!mounted) return;
    final key = _logKey(record);
    final existingIndex =
        _activityLogs.indexWhere((log) => _logKey(log) == key);

    setState(() {
      if (existingIndex >= 0) {
        _activityLogs[existingIndex] = Map<String, dynamic>.from(record);
      } else {
        _activityLogs.insert(0, Map<String, dynamic>.from(record));
      }
      _activityLogs.sort((a, b) {
        final aTime = DateTime.tryParse(a['logged_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = DateTime.tryParse(b['logged_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
    });
  }

  void _subscribeToActivityLogs() {
    final sessionId = _sessionId;
    if (sessionId == null || sessionId.isEmpty) return;

    _activityChannel = SupabaseService.client
        .channel('session_activity_live_$sessionId')
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
            _upsertRealtimeLog(
              Map<String, dynamic>.from(payload.newRecord),
            );
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'activity_logs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (payload) {
            _upsertRealtimeLog(
              Map<String, dynamic>.from(payload.newRecord),
            );
          },
        )
        .subscribe((status, [error]) {
          // If realtime drops, force a refresh so professional sync still shows.
          if (status == RealtimeSubscribeStatus.subscribed) {
            _loadActivityLogs(silent: true);
          }
        });
  }

  String _formatTime(dynamic timeObj) {
    if (timeObj == null) return '--:--';
    final DateTime parsed =
        timeObj is DateTime ? timeObj : DateTime.parse(timeObj.toString());
    final local = parsed.toLocal();
    int hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final bookingData = widget.bookingData;
    final caregiverName = displayPersonName(
      bookingData['caregiver_name']?.toString(),
      fallback: 'Professional',
    );
    final serviceTitle = bookingData['title'] ?? 'Care';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F2F0),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFAF2EB),
                shape: BoxShape.circle,
                border: Border.all(
                  color: HestiaColors.primary.withValues(alpha: 0.15),
                ),
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
            color: HestiaColors.primary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              color: HestiaColors.primary,
              onRefresh: () => _loadActivityLogs(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: HestiaColors.primary,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: HestiaColors.primary.withValues(alpha: 0.28),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Today · $serviceTitle',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.82),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$caregiverName · ${_formatTime(bookingData['actual_start'])}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF81C784),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Live',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
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
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: HestiaColors.primary,
                          ),
                        ),
                      )
                    else if (_activityLogs.isEmpty)
                      _entryCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'No activity logged yet',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: HestiaColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Activity will appear here as the professional syncs updates.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...List.generate(_activityLogs.length, (index) {
                        final item = _activityLogs[index];
                        final loggedAt = item['logged_at'];
                        final isLatest = index == 0;
                        final primaryText =
                            (item['note']?.toString().trim().isNotEmpty ??
                                    false)
                                ? item['note'].toString().trim()
                                : (item['activity_type']?.toString() ??
                                    'Activity update');
                        final secondaryType =
                            item['activity_type']?.toString() ?? 'Activity';
                        final secondaryText =
                            '$secondaryType · ${_formatTime(loggedAt)}';

                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index == _activityLogs.length - 1 ? 0 : 12,
                          ),
                          child: _entryCard(
                            highlight: isLatest,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: isLatest
                                        ? const Color(0xFFE8F5E9)
                                        : const Color(0xFFFAF2EB),
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: isLatest
                                          ? const Color(0xFF2E7D32)
                                          : HestiaColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              primaryText,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color: HestiaColors.textDark,
                                                height: 1.35,
                                              ),
                                            ),
                                          ),
                                          if (isLatest) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFE8F5E9),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: const Text(
                                                'New',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFF2E7D32),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        secondaryText,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _formatTime(loggedAt),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: HestiaColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
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
                        fontWeight: FontWeight.w800,
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

  Widget _entryCard({
    required Widget child,
    bool highlight = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight
              ? HestiaColors.primary
              : HestiaColors.primary.withValues(alpha: 0.55),
          width: highlight ? 1.6 : 1.3,
        ),
      ),
      child: child,
    );
  }
}
