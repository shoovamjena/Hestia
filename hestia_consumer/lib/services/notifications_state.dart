import 'package:flutter/material.dart';

enum NotificationIconType { clock, play, location, person }

class HestiaNotification {
  final String id;
  final String title;
  final String description;
  final String timeAgo;
  final String section; // 'TODAY' or 'YESTERDAY'
  final bool isUnread;
  final NotificationIconType iconType;

  HestiaNotification({
    required this.id,
    required this.title,
    required this.description,
    required this.timeAgo,
    required this.section,
    required this.isUnread,
    required this.iconType,
  });

  HestiaNotification copyWith({
    bool? isUnread,
  }) {
    return HestiaNotification(
      id: id,
      title: title,
      description: description,
      timeAgo: timeAgo,
      section: section,
      isUnread: isUnread ?? this.isUnread,
      iconType: iconType,
    );
  }
}

class NotificationsState extends ChangeNotifier {
  static final NotificationsState instance = NotificationsState._internal();

  NotificationsState._internal();

  final List<HestiaNotification> _notifications = [
    HestiaNotification(
      id: '0',
      title: 'Rate your session with Sunita',
      description: 'Your session has ended. Tap here to rate Sunita Rao\'s care.',
      timeAgo: '30 min ago',
      section: 'TODAY',
      isUnread: true,
      iconType: NotificationIconType.person,
    ),
    HestiaNotification(
      id: '1',
      title: 'Activity update from Sunita',
      description: 'Newborn bathed and swaddled comfortably',
      timeAgo: '2 min ago',
      section: 'TODAY',
      isUnread: true,
      iconType: NotificationIconType.clock,
    ),
    HestiaNotification(
      id: '2',
      title: 'Session started',
      description: 'Sunita Rao has started your Post-Delivery Care session',
      timeAgo: '1 hr 26 min ago',
      section: 'TODAY',
      isUnread: true,
      iconType: NotificationIconType.play,
    ),
    HestiaNotification(
      id: '3',
      title: 'Sunita is on the way',
      description: 'ETA 23 minutes · 2.4 km away from your address',
      timeAgo: '2 hrs ago',
      section: 'TODAY',
      isUnread: false,
      iconType: NotificationIconType.location,
    ),
    HestiaNotification(
      id: '4',
      title: 'Professional assigned',
      description: 'Sunita Rao has been assigned to your booking today',
      timeAgo: '3 hrs ago',
      section: 'TODAY',
      isUnread: false,
      iconType: NotificationIconType.person,
    ),
  ];

  List<HestiaNotification> get notifications => List.unmodifiable(_notifications);

  int get unreadCount => _notifications.where((n) => n.isUnread).length;

  void markAsRead(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index != -1 && _notifications[index].isUnread) {
      _notifications[index] = _notifications[index].copyWith(isUnread: false);
      notifyListeners();
    }
  }

  void markAllAsRead() {
    bool changed = false;
    for (int i = 0; i < _notifications.length; i++) {
      if (_notifications[i].isUnread) {
        _notifications[i] = _notifications[i].copyWith(isUnread: false);
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  void dismissNotification(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index != -1) {
      _notifications.removeAt(index);
      notifyListeners();
    }
  }

  void addNotification(HestiaNotification notification) {
    _notifications.insert(0, notification);
    notifyListeners();
  }
}
