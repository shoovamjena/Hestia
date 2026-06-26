import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../services/notifications_state.dart';
import 'tracking_screen.dart';
import 'rate_session_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  Widget build(BuildContext context) {
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
            'Notifications',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          centerTitle: true,
          actions: [
            TextButton(
              onPressed: () {
                NotificationsState.instance.markAllAsRead();
                setState(() {});
              },
              child: const Text(
                'Mark all read',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: NotificationsState.instance,
          builder: (context, child) {
            final notifications = NotificationsState.instance.notifications;
            
            if (notifications.isEmpty) {
              return _buildEmptyState();
            }

            // Group notifications by section (Today / Yesterday)
            final todayList = notifications.where((n) => n.section == 'TODAY').toList();
            final yesterdayList = notifications.where((n) => n.section == 'YESTERDAY').toList();

            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(24.0),
              children: [
                if (todayList.isNotEmpty) ...[
                  const Text(
                    'TODAY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF8C6239),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: todayList.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _buildNotificationCard(todayList[index]);
                    },
                  ),
                  const SizedBox(height: 24),
                ],
                if (yesterdayList.isNotEmpty) ...[
                  const Text(
                    'YESTERDAY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF8C6239),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: yesterdayList.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _buildNotificationCard(yesterdayList[index]);
                    },
                  ),
                ],
              ],
            );
          },
        ),
      ),
     ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: HestiaColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: HestiaColors.primary,
              size: 32,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'All Caught Up!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: HestiaColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'No new notifications to display right now.',
            style: TextStyle(
              fontSize: 13,
              color: HestiaColors.textMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(HestiaNotification item) {
    // Determine colors and icons based on type
    IconData iconData;
    Color iconColor;
    Color iconBgColor;

    switch (item.iconType) {
      case NotificationIconType.clock:
        iconData = Icons.access_time_rounded;
        iconColor = const Color(0xFFC39365);
        iconBgColor = const Color(0xFFFDF7F0);
        break;
      case NotificationIconType.play:
        iconData = Icons.play_arrow_rounded;
        iconColor = const Color(0xFF2E7D32);
        iconBgColor = const Color(0xFFE8F5E9);
        break;
      case NotificationIconType.location:
        iconData = Icons.location_on_outlined;
        iconColor = const Color(0xFF1E88E5);
        iconBgColor = const Color(0xFFE3F2FD);
        break;
      case NotificationIconType.person:
        iconData = Icons.person_outline_rounded;
        iconColor = const Color(0xFF8E24AA);
        iconBgColor = const Color(0xFFF3E5F5);
        break;
    }

    // Unread styling: thick vertical left border and unread dot
    final decoration = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border(
        left: item.isUnread
            ? const BorderSide(color: Color(0xFF8C6239), width: 4)
            : const BorderSide(color: Color(0xFFFAF2EB), width: 1.2),
        top: const BorderSide(color: Color(0xFFFAF2EB), width: 1.2),
        right: const BorderSide(color: Color(0xFFFAF2EB), width: 1.2),
        bottom: const BorderSide(color: Color(0xFFFAF2EB), width: 1.2),
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x05000000),
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ],
    );

    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        decoration: BoxDecoration(
          color: const Color(0xFFC0392B),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (direction) {
        NotificationsState.instance.dismissNotification(item.id);
      },
      child: GestureDetector(
        onTap: () {
          NotificationsState.instance.markAsRead(item.id);
          
          // Navigation logic for tracking updates or rating
          if (item.title.contains('Rate your session')) {
            final mockSession = {
              'booking_id': 'mock-session-1',
              'session_id': 'mock-session-1',
              'title': 'Post-Delivery',
              'scheduled_start': DateTime.now().subtract(const Duration(hours: 3, minutes: 2)),
              'duration_hours': 3.033,
              'caregiver_name': 'Sunita Rao',
              'amount': 1497,
              'status': 'completed',
              'isRated': false,
            };
            
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => RateSessionScreen(sessionData: mockSession),
              ),
            );
          } else if (item.title.contains('started') || item.title.contains('on the way')) {
            final mockBooking = {
              'id': 'booking_123',
              'booking_id': 'mock-booking-active-1',
              'title': 'Post-Delivery',
              'caregiver_name': 'Sunita Rao',
              'scheduled_start': DateTime.now().subtract(const Duration(hours: 1, minutes: 24)),
              'duration_hours': 3,
              'status': 'transit',
            };
            
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => TrackingScreen(bookingData: mockBooking),
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          decoration: decoration,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon Badge container
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  iconData,
                  color: iconColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              // Text Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: HestiaColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: HestiaColors.textMedium,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.timeAgo,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: HestiaColors.textLight,
                      ),
                    ),
                  ],
                ),
              ),
              // Unread dot badge
              if (item.isUnread) ...[
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF8C6239),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
