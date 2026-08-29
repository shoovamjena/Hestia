import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/mapbox_config.dart';
import '../theme/colors.dart';
import '../services/supabase_service.dart';
import '../services/session_arrival_coordinator.dart';
import '../utils/active_booking_navigation.dart';
import 'activity_log_screen.dart';
import 'rate_session_screen.dart';
import 'chat_screen.dart';
import 'emergency_screen.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class TrackingScreen extends StatefulWidget {
  final Map<String, dynamic> bookingData;
  final bool openVerifyOnLoad;

  const TrackingScreen({
    super.key,
    required this.bookingData,
    this.openVerifyOnLoad = false,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with TickerProviderStateMixin {
  late Map<String, dynamic> _bookingData;
  final List<Map<String, dynamic>> _activityLogs = [];
  bool _isOnTheWayView = true;
  late Timer _stopwatchTimer;
  Timer? _statusTimer;
  int _secondsElapsed = 5047; // starts around 01:24:07
  bool _isApologizing = false;
  bool _hasNavigatedToReview = false;

  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _activityChannel;
  RealtimeChannel? _locationChannel;
  RealtimeChannel? _chatChannel;
  Timer? _activityPollTimer;
  bool _isRefreshingActivityLogs = false;
  String? _subscribedActivitySessionId;
  String? _subscribedChatSessionId;
  int _unreadChatCount = 0;
  String _enteredCode = '';
  String? _verificationError;
  bool _isStartingSession = false;
  bool _isEndingSession = false;
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocusNode = FocusNode();

  LatLng? _hubLocation;
  LatLng? _userLocation;
  LatLng? _professionalLocation;
  LatLng? _displayedProfessionalLocation;
  LatLng? _lastRoutedFrom;
  double _carBearingDegrees = 0;
  AnimationController? _markerGlideController;
  List<LatLng> _glidePath = const [];
  List<double> _glideCumulativeKm = const [];
  Timer? _locationTimer;
  Timer? _routeRedrawDebounce;
  bool _routeFetchInFlight = false;
  String? _subscribedLocationSessionId;
  List<LatLng> _routePoints = [];
  /// Full-route totals from the latest Mapbox directions response.
  double _mapboxRouteDistanceKm = 0.0;
  int _mapboxRouteDurationMin = 0;
  double _routeDistanceKm = 0.0;
  int _routeDurationMin = 0;
  double _lastKnownSpeedKmPerMin = 0.35; // fallback ~21 km/h city traffic
  DateTime? _lastMetricsUiUpdateAt;
  bool _isLoadingMap = true;
  final MapController _mapController = MapController();
  final Distance _geoDistance = const Distance();
  LatLng? _currentMapCenter;
  double _currentMapZoom = 13.0;
  /// Tight street-level follow while professional is on the way.
  static const double _liveFollowZoom = 17.0;
  final DraggableScrollableController _onTheWaySheetController =
      DraggableScrollableController();
  bool _isOnTheWaySheetExpanded = false;
  StreamSubscription<SessionArrivalEvent>? _arrivalSub;

  bool _isActiveSessionStatus(String? status) {
    final s = status?.toString().trim().toLowerCase() ?? '';
    return s == 'started' || s == 'active' || s == 'in_progress';
  }

  bool _isCompletedStatus(String? status) {
    final s = status?.toString().trim().toLowerCase() ?? '';
    return s == 'completed';
  }

  void _applyBookingData(Map<String, dynamic> next) {
    final merged = Map<String, dynamic>.from(next);
    final caregiver = merged['caregiver_name']?.toString();
    if (caregiver != null && caregiver.isNotEmpty) {
      merged['caregiver_name'] = displayCaregiverName(caregiver);
    }
    _bookingData = merged;
  }

  void _applyStatusToView(String? status) {
    if (_isCompletedStatus(status) || _hasNavigatedToReview) {
      // Stay on whatever view we had; navigation to review handles exit.
      return;
    }
    _isOnTheWayView = !_isActiveSessionStatus(status);
  }

  void _goToReviewScreen({
    Map<String, dynamic>? data,
    bool force = false,
  }) {
    if (!mounted || _hasNavigatedToReview) return;
    // While End Session owns the API call, ignore realtime/poll navigation.
    if (_isEndingSession && !force) return;

    _hasNavigatedToReview = true;
    _isEndingSession = false;
    _tearDownLiveSessionListeners();

    final sessionData = Map<String, dynamic>.from(data ?? _bookingData);
    sessionData['status'] = 'completed';
    sessionData['caregiver_name'] =
        sessionData['caregiver_name'] ?? 'Professional';
    sessionData['title'] =
        sessionData['title'] ?? sessionData['service_type'] ?? 'Care';

    // Keep Home underneath; never leave Tracking in the stack under Rate.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => RateSessionScreen(sessionData: sessionData),
      ),
      (route) => route.isFirst,
    );
  }

  void _tearDownLiveSessionListeners() {
    _statusTimer?.cancel();
    _statusTimer = null;
    _locationTimer?.cancel();
    _locationTimer = null;
    _activityPollTimer?.cancel();
    _activityPollTimer = null;
    _routeRedrawDebounce?.cancel();
    _routeRedrawDebounce = null;
    try {
      _stopwatchTimer.cancel();
    } catch (_) {}
    try {
      _markerGlideController?.stop();
    } catch (_) {}

    if (_realtimeChannel != null) {
      SupabaseService.client.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
    if (_activityChannel != null) {
      SupabaseService.client.removeChannel(_activityChannel!);
      _activityChannel = null;
    }
    if (_locationChannel != null) {
      SupabaseService.client.removeChannel(_locationChannel!);
      _locationChannel = null;
    }
    if (_chatChannel != null) {
      SupabaseService.client.removeChannel(_chatChannel!);
      _chatChannel = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _applyBookingData(Map<String, dynamic>.from(widget.bookingData));
    final status = _bookingData['status']?.toString();
    _isOnTheWayView = !_isActiveSessionStatus(status);
    _startStopwatch();
    _startStatusPolling();
    _loadRouteAndCoordinates();
    _loadActivityLogs();
    _initRealtimeSubscription();
    _subscribeToActivityLogs();
    _startLocationTracking();
    _subscribeToChatUnread();
    _refreshUnreadChatCount();
    _arrivalSub = SessionArrivalCoordinator.instance.events.listen((event) {
      final bookingId = _bookingData['booking_id']?.toString();
      if (bookingId == null || bookingId != event.bookingId || !mounted) {
        return;
      }
      unawaited(_refreshBookingFromServer(openVerify: event.openVerify));
    });
    _activityPollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _loadActivityLogs(silent: true);
    });

    // Check for no-show / already-completed immediately on launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isCompletedStatus(_bookingData['status'])) {
        _goToReviewScreen(data: _bookingData);
        return;
      }
      _checkNoShowAndApologize(_bookingData);
      if (widget.openVerifyOnLoad ||
          _bookingData['status']?.toString().toLowerCase() == 'arrived') {
        _expandSheetForVerify(focusCode: widget.openVerifyOnLoad);
      }
    });
  }

  @override
  void dispose() {
    _arrivalSub?.cancel();
    _tearDownLiveSessionListeners();
    _markerGlideController?.dispose();
    _codeController.dispose();
    _codeFocusNode.dispose();
    _onTheWaySheetController.dispose();
    super.dispose();
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (_hasNavigatedToReview || _isEndingSession || !mounted) {
        timer.cancel();
        return;
      }
      await _refreshBookingFromServer();
    });
  }

  Future<void> _refreshBookingFromServer({bool openVerify = false}) async {
    if (_hasNavigatedToReview || _isEndingSession || !mounted) return;
    final bookingId = _bookingData['booking_id']?.toString();
    if (bookingId == null || bookingId.isEmpty) return;

    final updated = await SupabaseService.getBookingStatus(bookingId);
    if (_hasNavigatedToReview || _isEndingSession || !mounted) return;
    if (updated == null) return;

    final previousStatus = _bookingData['status']?.toString().toLowerCase();
    final nextStatus = updated['status']?.toString().toLowerCase();
    final previousRouteMode = _shouldRouteFromProfessionalLiveLocation();
    final shouldLoadRoute = _hubLocation == null &&
        (updated['hub_address'] != null || updated['user_address'] != null);

    setState(() {
      _applyBookingData(updated);
      _applyStatusToView(_bookingData['status']?.toString());
    });

    _subscribeToActivityLogs();
    _subscribeToChatUnread();

    if (_isCompletedStatus(updated['status'])) {
      _goToReviewScreen(data: updated);
      return;
    }

    final routeModeChanged =
        previousRouteMode != _shouldRouteFromProfessionalLiveLocation();
    if (shouldLoadRoute || routeModeChanged) {
      _loadRouteAndCoordinates();
    }
    _checkNoShowAndApologize(updated);

    if (nextStatus == 'arrived' && previousStatus != 'arrived') {
      _expandSheetForVerify(focusCode: openVerify);
    } else if (openVerify && nextStatus == 'arrived') {
      _expandSheetForVerify(focusCode: true);
    }
  }

  void _expandSheetForVerify({bool focusCode = false}) {
    if (!mounted) return;
    final isArrived = _bookingData['status']?.toString().toLowerCase() == 'arrived';
    if (!isArrived) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_onTheWaySheetController.isAttached) return;
      final maxSize =
          _bookingData['status']?.toString().toLowerCase() == 'arrived'
              ? 0.82
              : 0.72;
      _onTheWaySheetController.animateTo(
        maxSize,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      if (focusCode) {
        Future.delayed(const Duration(milliseconds: 360), () {
          if (mounted) _codeFocusNode.requestFocus();
        });
      }
    });
  }

  void _startStopwatch() {
    try {
      _stopwatchTimer.cancel();
    } catch (_) {}
    _stopwatchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_hasNavigatedToReview || _isEndingSession || !mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        final actualStartObj = _bookingData['actual_start'];
        if (actualStartObj != null) {
          final startTime = actualStartObj is DateTime
              ? actualStartObj
              : DateTime.parse(actualStartObj.toString());
          // Elapsed time count up from start_time
          _secondsElapsed =
              DateTime.now().toUtc().difference(startTime.toUtc()).inSeconds;
          if (_secondsElapsed < 0) _secondsElapsed = 0;
        } else {
          _secondsElapsed = 0;
        }
      });
    });
  }

  String _formatStopwatch(int totalSeconds) {
    if (totalSeconds <= 0) return '00:00:00';
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _checkNoShowAndApologize(Map<String, dynamic> bookingData) {
    final status = bookingData['status']?.toString().toLowerCase();

    // Session already with the client or finished — no apology flow.
    if (status == 'arrived' ||
        status == 'active' ||
        status == 'in_progress' ||
        status == 'started' ||
        status == 'completed') {
      return;
    }

    final scheduledStartObj = bookingData['scheduled_start'];
    if (scheduledStartObj == null) return;

    final DateTime scheduledStart = scheduledStartObj is DateTime
        ? scheduledStartObj
        : DateTime.parse(scheduledStartObj.toString());

    final double durationHours =
        (bookingData['duration_hours'] as num?)?.toDouble() ?? 2.0;
    final scheduledEnd =
        scheduledStart.add(Duration(minutes: (durationHours * 60).round()));

    // Late past start is OK — keep scheduled / on-the-way screens.
    // Only no-show after the full booked window ends.
    if (DateTime.now().isAfter(scheduledEnd)) {
      _showNoShowApologyAndRedirect(bookingData);
    }
  }

  void _showNoShowApologyAndRedirect(Map<String, dynamic> bookingData) async {
    if (_isApologizing) return;
    setState(() {
      _isApologizing = true;
    });

    // Cancel active polling and stopwatch timers
    _statusTimer?.cancel();
    _stopwatchTimer.cancel();

    final bookingId = bookingData['booking_id']?.toString() ?? '';

    // Mark as no-show in backend
    if (bookingId.isNotEmpty) {
      await SupabaseService.markNoShow(bookingId);
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: const Color(0xFFFAF6F0),
          title: const Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFC0392B),
                size: 28,
              ),
              SizedBox(width: 10),
              Text(
                'We are truly sorry',
                style: TextStyle(
                  color: HestiaColors.textDark,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'It looks like your caregiver, ${bookingData['caregiver_name'] ?? 'your professional'}, was unable to arrive for the scheduled session.',
                style: const TextStyle(
                  color: HestiaColors.textDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'We have automatically cancelled this booking and processed a full refund to your original payment method. We are currently reviewing this incident with our operations team.',
                style: TextStyle(
                  color: HestiaColors.textMedium,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(); // Dismiss apology dialog

                  // Construct session data for rating screen
                  final scheduledStartObj = bookingData['scheduled_start'];
                  final DateTime scheduledStart = scheduledStartObj is DateTime
                      ? scheduledStartObj
                      : (scheduledStartObj != null ? DateTime.parse(scheduledStartObj.toString()) : DateTime.now());

                  final sessionData = {
                    'booking_id': bookingId,
                    'caregiver_name': bookingData['caregiver_name'] ?? 'Professional',
                    'title': bookingData['title'] ?? bookingData['service_type'] ?? 'Care',
                    'scheduled_start': scheduledStart,
                  };

                  // Redirect to RateSessionScreen and clear Tracking from stack
                  _goToReviewScreen(data: sessionData);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: HestiaColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Continue to Review',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : 'P';
  }

  String _formatMetricTime() {
    final start = _bookingData['scheduled_start'];
    if (start is DateTime) {
      int hour = start.hour;
      final minute = start.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;
      return '$hour:$minute\n$period';
    }
    return '--:--\n--';
  }

  String _formatMetricDuration() {
    final amount = _bookingData['amount'];
    if (amount != null && amount is int && amount > 0) {
      return '₹$amount';
    }
    return '';
  }

  String _formatMetricService() {
    final title = _bookingData['title']?.toString() ?? 'Care';
    // Break long service names for the metric block
    if (title.length > 8) {
      final mid = title.indexOf(' ');
      if (mid > 0) {
        return '${title.substring(0, mid)}\n${title.substring(mid + 1)}';
      }
    }
    return title;
  }

  String _formatMetricHub() {
    final hubName = _bookingData['hub_name']?.toString() ?? 'Hub';
    // Split by common dash characters: em dash (—), en dash (–), hyphen (-) to clean up sector/branch names
    final cleanName = hubName.split(RegExp(r'[\u2014\u2013-]')).first.trim();
    if (cleanName.length > 8) {
      final mid = cleanName.indexOf(' ');
      if (mid > 0) {
        return '${cleanName.substring(0, mid)}\n${cleanName.substring(mid + 1)}';
      }
    }
    return cleanName;
  }

  String _formatProfessionalRating() {
    final rating = double.tryParse(_bookingData['professional_rating']?.toString() ?? '');
    if (rating == null || rating <= 0) return '--';
    return rating.toStringAsFixed(1);
  }

  String _formatProfessionalSessions() {
    final count = int.tryParse(_bookingData['professional_total_sessions']?.toString() ?? '') ?? 0;
    if (count <= 0) return '';
    return '$count ${count == 1 ? "session" : "sessions"}';
  }

  String _normalizedTrackingStatus() {
    return _bookingData['status']?.toString().trim().toLowerCase() ?? '';
  }

  bool _shouldRouteFromProfessionalLiveLocation() {
    final status = _normalizedTrackingStatus();
    return status == 'departed' ||
        status == 'transit' ||
        status == 'en_route' ||
        status == 'arrived' ||
        status == 'started' ||
        status == 'active' ||
        status == 'in_progress' ||
        status == 'completed';
  }

  Future<void> _ensureSessionId() async {
    final existing = _bookingData['session_id']?.toString();
    if (existing != null && existing.isNotEmpty) return;
    final bookingId = _bookingData['booking_id']?.toString();
    if (bookingId == null || bookingId.isEmpty) return;
    try {
      final updated = await SupabaseService.getBookingStatus(bookingId);
      final sessionId = updated?['session_id']?.toString();
      if (sessionId != null &&
          sessionId.isNotEmpty &&
          mounted) {
        setState(() {
          _applyBookingData({..._bookingData, ...updated!});
        });
        if (_locationChannel == null ||
            _subscribedLocationSessionId != sessionId) {
          _startLocationTracking();
        }
      }
    } catch (_) {}
  }

  Future<bool> _refreshProfessionalLocation() async {
    await _ensureSessionId();
    final sessionId = _bookingData['session_id']?.toString();
    final professionalId = _bookingData['professional_id']?.toString();
    if ((sessionId == null || sessionId.isEmpty) &&
        (professionalId == null || professionalId.isEmpty)) {
      return false;
    }

    final latestLoc = await SupabaseService.getLatestProfessionalLocation(
      sessionId,
      professionalId: professionalId,
    );
    if (latestLoc == null || !mounted) return false;

    final next = LatLng(latestLoc['latitude']!, latestLoc['longitude']!);
    return _applyProfessionalLocation(next);
  }

  /// Keep the map locked on the professional pin (no free zoom/pan).
  void _centerMapOnLivePin(LatLng point) {
    if (!_isOnTheWayView || !mounted) return;
    _currentMapCenter = point;
    _currentMapZoom = _liveFollowZoom;
    try {
      _mapController.move(point, _liveFollowZoom);
    } catch (_) {
      // MapController may not be ready on the first fix.
    }
  }

  /// Updates the live target and glides the car marker smoothly toward it.
  bool _applyProfessionalLocation(LatLng next) {
    if (!mounted) return false;
    final previousTarget = _professionalLocation;
    final moved = previousTarget == null ||
        (previousTarget.latitude - next.latitude).abs() > 0.000001 ||
        (previousTarget.longitude - next.longitude).abs() > 0.000001;
    if (!moved) return false;

    _professionalLocation = next;
    _recomputeLiveMetrics(next);
    // Keep arrow aligned with travel even before the glide tick runs.
    if (previousTarget != null) {
      final stepKm = _geoDistance.as(
        LengthUnit.Kilometer,
        previousTarget,
        next,
      );
      if (stepKm >= 0.008) {
        _carBearingDegrees = _bearingDegrees(previousTarget, next);
      } else {
        _syncTravelBearing(next);
      }
    } else {
      _syncTravelBearing(next);
    }
    _startMarkerGlide(to: next);
    return true;
  }

  /// Point the navigation arrow the same way staff does: along the live route
  /// toward the booking address (fallback: straight to destination).
  void _syncTravelBearing(LatLng at) {
    if (_routePoints.length >= 2) {
      final idx = _nearestRouteIndex(at);
      final lookAhead = math.min(idx + 4, _routePoints.length - 1);
      if (lookAhead > idx) {
        _carBearingDegrees = _bearingDegrees(_routePoints[idx], _routePoints[lookAhead]);
        return;
      }
      if (idx < _routePoints.length - 1) {
        _carBearingDegrees =
            _bearingDegrees(_routePoints[idx], _routePoints[idx + 1]);
        return;
      }
      if (idx > 0) {
        _carBearingDegrees =
            _bearingDegrees(_routePoints[idx - 1], _routePoints[idx]);
        return;
      }
    }

    final dest = _userLocation;
    if (dest != null) {
      final d = _geoDistance.as(LengthUnit.Kilometer, at, dest);
      if (d > 0.01) {
        _carBearingDegrees = _bearingDegrees(at, dest);
      }
    }
  }

  /// Distance/ETA: prefer Mapbox driving totals (same source as staff).
  /// Only reduce them as the professional moves; never snap to 0/1min while
  /// still far from the booking address.
  void _recomputeLiveMetrics(LatLng current, {bool forceUi = false}) {
    final now = DateTime.now();
    if (!forceUi &&
        _lastMetricsUiUpdateAt != null &&
        now.difference(_lastMetricsUiUpdateAt!) <
            const Duration(milliseconds: 180)) {
      return;
    }
    _lastMetricsUiUpdateAt = now;

    final metrics = _remainingRouteMetrics(current);
    if (!mounted) {
      _routeDistanceKm = metrics.km;
      _routeDurationMin = metrics.min;
      return;
    }
    setState(() {
      _routeDistanceKm = metrics.km;
      _routeDurationMin = metrics.min;
    });
  }

  void _applyMapboxRoute({
    required List<LatLng> points,
    required double distanceKm,
    required int durationMin,
    required LatLng routedFrom,
  }) {
    _routePoints = points;
    _mapboxRouteDistanceKm = distanceKm;
    _mapboxRouteDurationMin = durationMin;
    _routeDistanceKm = distanceKm;
    _routeDurationMin = durationMin;
    _lastRoutedFrom = routedFrom;
    if (durationMin > 0 && distanceKm > 0) {
      _lastKnownSpeedKmPerMin = distanceKm / durationMin;
    }
    final pin = _displayedProfessionalLocation ??
        _professionalLocation ??
        routedFrom;
    _syncTravelBearing(pin);
  }

  ({double km, int min}) _remainingRouteMetrics(LatLng current) {
    final destination = _userLocation;
    final straightKm = destination == null
        ? 0.0
        : _geoDistance.as(LengthUnit.Kilometer, current, destination);

    // While a fresh Mapbox fetch is in flight, keep the last good totals.
    if (_routeFetchInFlight &&
        _mapboxRouteDistanceKm > 0 &&
        _mapboxRouteDurationMin > 0) {
      return (km: _mapboxRouteDistanceKm, min: _mapboxRouteDurationMin);
    }

    if (_mapboxRouteDistanceKm > 0 && _mapboxRouteDurationMin > 0) {
      var remainingKm = _mapboxRouteDistanceKm;
      var remainingMin = _mapboxRouteDurationMin;

      if (_lastRoutedFrom != null) {
        final traveled = _geoDistance.as(
          LengthUnit.Kilometer,
          _lastRoutedFrom!,
          current,
        );
        // Only shrink after meaningful movement; otherwise match staff's
        // full Mapbox ETA/distance for this route fetch.
        if (traveled >= 0.08) {
          remainingKm = (_mapboxRouteDistanceKm - traveled).clamp(
            straightKm > 0.05 ? straightKm * 0.9 : 0.05,
            _mapboxRouteDistanceKm,
          );
          remainingMin = _etaMinutesForRemainingKm(remainingKm);
        }
      }

      // Guard against GPS noise under-reporting while still far away.
      if (straightKm > 0.25 && remainingKm < straightKm * 0.5) {
        remainingKm = math.max(remainingKm, straightKm);
        remainingMin = _etaMinutesForRemainingKm(remainingKm);
      }

      return (km: remainingKm, min: remainingMin);
    }

    // Mapbox not ready yet — straight-line estimate so UI isn't empty.
    if (straightKm > 0.001) {
      return (
        km: straightKm,
        min: _etaMinutesForRemainingKm(straightKm, useSpeedFallback: true),
      );
    }

    return (km: _routeDistanceKm, min: _routeDurationMin);
  }

  int _etaMinutesForRemainingKm(
    double remainingKm, {
    bool useSpeedFallback = false,
  }) {
    if (remainingKm <= 0.02) return 1;

    if (!useSpeedFallback &&
        _mapboxRouteDistanceKm > 0 &&
        _mapboxRouteDurationMin > 0) {
      final ratio = (remainingKm / _mapboxRouteDistanceKm).clamp(0.0, 1.0);
      return math.max(1, (_mapboxRouteDurationMin * ratio).round());
    }

    final speed = _lastKnownSpeedKmPerMin > 0.05
        ? _lastKnownSpeedKmPerMin
        : 0.35;
    return math.max(1, (remainingKm / speed).round());
  }

  void _startMarkerGlide({required LatLng to}) {
    final from = _displayedProfessionalLocation ?? to;

    // First fix: snap into place and aim along the route / destination.
    if (_displayedProfessionalLocation == null) {
      _syncTravelBearing(to);
      setState(() {
        _displayedProfessionalLocation = to;
      });
      _recomputeLiveMetrics(to, forceUi: true);
      _centerMapOnLivePin(to);
      return;
    }

    final distanceKm = _geoDistance.as(LengthUnit.Kilometer, from, to);
    if (distanceKm < 0.003) {
      _syncTravelBearing(to);
      setState(() {
        _displayedProfessionalLocation = to;
      });
      _recomputeLiveMetrics(to, forceUi: true);
      _centerMapOnLivePin(to);
      return;
    }

    _glidePath = _buildGlidePath(from, to);
    _glideCumulativeKm = _buildCumulativeDistancesKm(_glidePath);

    final durationMs = (distanceKm * 9000).clamp(700, 3200).round();
    _markerGlideController?.dispose();
    _markerGlideController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    )..addListener(() {
        if (!mounted || _glidePath.isEmpty) return;
        final t = Curves.easeInOutCubic.transform(
          _markerGlideController!.value,
        );
        final point = _pointAlongGlidePath(t);
        final prev = _displayedProfessionalLocation ?? point;
        final movedEnough =
            (prev.latitude - point.latitude).abs() > 0.0000005 ||
            (prev.longitude - point.longitude).abs() > 0.0000005;
        setState(() {
          _displayedProfessionalLocation = point;
          if (movedEnough) {
            // Prefer route tangent (matches staff) when gliding on the polyline.
            if (_routePoints.length >= 2) {
              _syncTravelBearing(point);
            } else {
              _carBearingDegrees = _bearingDegrees(prev, point);
            }
          }
        });
        _centerMapOnLivePin(point);
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          _syncTravelBearing(to);
          setState(() {
            _displayedProfessionalLocation = to;
          });
          _recomputeLiveMetrics(to, forceUi: true);
          _centerMapOnLivePin(to);
        }
      })
      ..forward(from: 0);
  }

  List<LatLng> _buildGlidePath(LatLng from, LatLng to) {
    if (_routePoints.length < 2) {
      return _densifyStraightPath(from, to);
    }

    final fromIdx = _nearestRouteIndex(from);
    final toIdx = _nearestRouteIndex(to);

    // Prefer gliding forward along the drawn route toward the destination.
    if (toIdx > fromIdx && (toIdx - fromIdx) >= 1) {
      final segment = <LatLng>[from];
      segment.addAll(_routePoints.sublist(fromIdx, toIdx + 1));
      if (segment.last != to) segment.add(to);
      return _densifyPath(segment);
    }

    return _densifyStraightPath(from, to);
  }

  List<LatLng> _densifyStraightPath(LatLng from, LatLng to) {
    const steps = 24;
    return List<LatLng>.generate(steps + 1, (i) {
      final t = i / steps;
      return LatLng(
        from.latitude + (to.latitude - from.latitude) * t,
        from.longitude + (to.longitude - from.longitude) * t,
      );
    });
  }

  List<LatLng> _densifyPath(List<LatLng> points) {
    if (points.length < 2) return points;
    final densified = <LatLng>[points.first];
    for (var i = 1; i < points.length; i++) {
      final a = densified.last;
      final b = points[i];
      final segmentKm = _geoDistance.as(LengthUnit.Kilometer, a, b);
      final steps = (segmentKm / 0.02).ceil().clamp(1, 12); // ~20m steps
      for (var s = 1; s <= steps; s++) {
        final t = s / steps;
        densified.add(
          LatLng(
            a.latitude + (b.latitude - a.latitude) * t,
            a.longitude + (b.longitude - a.longitude) * t,
          ),
        );
      }
    }
    return densified;
  }

  List<double> _buildCumulativeDistancesKm(List<LatLng> points) {
    if (points.isEmpty) return const [];
    final cumulative = <double>[0];
    for (var i = 1; i < points.length; i++) {
      cumulative.add(
        cumulative.last +
            _geoDistance.as(LengthUnit.Kilometer, points[i - 1], points[i]),
      );
    }
    return cumulative;
  }

  LatLng _pointAlongGlidePath(double t) {
    if (_glidePath.isEmpty) {
      return _displayedProfessionalLocation ??
          _professionalLocation ??
          const LatLng(0, 0);
    }
    if (_glidePath.length == 1 || _glideCumulativeKm.isEmpty) {
      return _glidePath.first;
    }
    final total = _glideCumulativeKm.last;
    if (total <= 0) return _glidePath.last;
    final target = (t.clamp(0.0, 1.0)) * total;

    for (var i = 1; i < _glideCumulativeKm.length; i++) {
      if (target <= _glideCumulativeKm[i]) {
        final startKm = _glideCumulativeKm[i - 1];
        final endKm = _glideCumulativeKm[i];
        final span = (endKm - startKm).abs();
        final localT = span <= 0 ? 1.0 : ((target - startKm) / span);
        final a = _glidePath[i - 1];
        final b = _glidePath[i];
        return LatLng(
          a.latitude + (b.latitude - a.latitude) * localT,
          a.longitude + (b.longitude - a.longitude) * localT,
        );
      }
    }
    return _glidePath.last;
  }

  int _nearestRouteIndex(LatLng point) {
    var bestIdx = 0;
    var bestKm = double.infinity;
    for (var i = 0; i < _routePoints.length; i++) {
      final km = _geoDistance.as(LengthUnit.Kilometer, point, _routePoints[i]);
      if (km < bestKm) {
        bestKm = km;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  double _bearingDegrees(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }

  void _scheduleLiveRouteRedraw({bool immediate = false}) {
    if (!_shouldRouteFromProfessionalLiveLocation()) return;
    if (_professionalLocation == null) return;

    _routeRedrawDebounce?.cancel();
    if (immediate) {
      unawaited(_redrawRouteFromLiveLocation());
      return;
    }
    _routeRedrawDebounce = Timer(const Duration(milliseconds: 650), () {
      unawaited(_redrawRouteFromLiveLocation());
    });
  }

  bool _hasMeaningfulRouteMove(LatLng from, LatLng to) {
    // ~12 meters — refresh driving ETA/path often enough.
    final dLat = (from.latitude - to.latitude).abs();
    final dLng = (from.longitude - to.longitude).abs();
    return dLat > 0.00011 || dLng > 0.00011 || _routePoints.isEmpty;
  }

  Future<void> _redrawRouteFromLiveLocation() async {
    if (!mounted || _routeFetchInFlight) return;
    final startLoc = _professionalLocation;
    final userLoc = _userLocation;
    if (startLoc == null) return;

    // Ensure destination exists; prefer saved booking pin, then geocode.
    LatLng? destination = userLoc;
    if (destination == null) {
      final savedLat = (_bookingData['user_latitude'] as num?)?.toDouble();
      final savedLng = (_bookingData['user_longitude'] as num?)?.toDouble();
      if (savedLat != null &&
          savedLng != null &&
          !(savedLat == 0 && savedLng == 0)) {
        destination = LatLng(savedLat, savedLng);
      }
    }
    if (destination == null) {
      final userAddr = _bookingData['user_address']?.toString() ?? '';
      if (userAddr.isEmpty) return;
      destination = await _geocodeAddress(userAddr);
      if (destination == null || !mounted) return;
    }
    if (mounted && _userLocation == null) {
      setState(() => _userLocation = destination);
    }

    if (_lastRoutedFrom != null &&
        !_hasMeaningfulRouteMove(_lastRoutedFrom!, startLoc) &&
        _routePoints.isNotEmpty) {
      _recomputeLiveMetrics(startLoc, forceUi: true);
      return;
    }

    _routeFetchInFlight = true;
    try {
      final url =
          'https://api.mapbox.com/directions/v5/mapbox/driving/${startLoc.longitude},${startLoc.latitude};${destination.longitude},${destination.latitude}?geometries=geojson&overview=full&access_token=${MapboxConfig.accessToken}';
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response =
            await request.close().timeout(const Duration(seconds: 10));
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty && mounted) {
          final route = routes.first as Map<String, dynamic>;
          final geometry = route['geometry'] as Map<String, dynamic>;
          final coordinates = geometry['coordinates'] as List;
          final distance = route['distance'] as num;
          final duration = route['duration'] as num;
          final distKm = distance / 1000.0;
          final durMin = math.max(1, (duration / 60.0).round());
          setState(() {
            _applyMapboxRoute(
              points: coordinates
                  .map((c) => LatLng(c[1] as double, c[0] as double))
                  .toList(),
              distanceKm: distKm,
              durationMin: durMin,
              routedFrom: startLoc,
            );
            _lastMetricsUiUpdateAt = DateTime.now();
            _isLoadingMap = false;
          });
          _recomputeLiveMetrics(startLoc, forceUi: true);
          _centerMapOnLivePin(
            _displayedProfessionalLocation ?? startLoc,
          );
        }
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      debugPrint('Live route redraw failed: $e');
      _recomputeLiveMetrics(startLoc, forceUi: true);
    } finally {
      _routeFetchInFlight = false;
    }
  }

  LatLng? _getRouteStartLocation() {
    // Once the professional has left the hub, always route from their live pin.
    if (_shouldRouteFromProfessionalLiveLocation()) {
      return _displayedProfessionalLocation ?? _professionalLocation;
    }
    return _hubLocation;
  }

  String _formatRouteSourceLabel() {
    if (_shouldRouteFromProfessionalLiveLocation()) {
      if (_professionalLocation != null) {
        return "Professional's live location";
      }
      return 'Waiting for professional live location';
    }
    if ((_bookingData['hub_name']?.toString().trim().isNotEmpty ?? false)) {
      return '${_bookingData['hub_name']} hub';
    }
    return 'Hub location';
  }

  String _formatRouteDestinationLabel() {
    final address = _bookingData['user_address']?.toString().trim() ?? '';
    if (address.isNotEmpty) return address;
    return 'Booking address unavailable';
  }

  Future<LatLng?> _geocodeAddress(String query) async {
    if (MapboxConfig.accessToken.isEmpty) return null;
    try {
      final url = 'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json?access_token=${MapboxConfig.accessToken}&limit=1';
      final response = await HttpClient().getUrl(Uri.parse(url)).then((req) => req.close()).then((res) => res.transform(utf8.decoder).join());
      final data = jsonDecode(response) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features != null && features.isNotEmpty) {
        final center = features.first['center'] as List;
        return LatLng(center[1] as double, center[0] as double);
      }
    } catch (e) {
      debugPrint('Error geocoding address: $e');
    }
    return null;
  }

  Future<void> _loadRouteAndCoordinates() async {
    final hubAddr = _bookingData['hub_address']?.toString() ?? '';
    final userAddr = _bookingData['user_address']?.toString() ?? '';
    final savedLat = (_bookingData['user_latitude'] as num?)?.toDouble();
    final savedLng = (_bookingData['user_longitude'] as num?)?.toDouble();

    if (userAddr.isEmpty && (savedLat == null || savedLng == null)) {
      if (mounted) {
        setState(() {
          _isLoadingMap = false;
        });
      }
      return;
    }

    // Always refresh live professional coordinates before drawing the route.
    if (_shouldRouteFromProfessionalLiveLocation()) {
      await _refreshProfessionalLocation();
    }

    final hubLoc = hubAddr.isEmpty
        ? _hubLocation
        : (_hubLocation ?? await _geocodeAddress(hubAddr));

    LatLng? userLoc = _userLocation;
    if (userLoc == null &&
        savedLat != null &&
        savedLng != null &&
        !(savedLat == 0 && savedLng == 0)) {
      userLoc = LatLng(savedLat, savedLng);
    }
    userLoc ??= userAddr.isEmpty ? null : await _geocodeAddress(userAddr);

    if (userLoc == null) {
      if (mounted) {
        setState(() {
          _isLoadingMap = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        if (hubLoc != null) _hubLocation = hubLoc;
        _userLocation = userLoc;
      });
    }

    if (_shouldRouteFromProfessionalLiveLocation()) {
      if (_professionalLocation == null) {
        if (mounted) {
          setState(() {
            _routePoints = [];
            // Keep prior metrics if we have them; don't blank the sheet.
            _isLoadingMap = false;
          });
        }
        return;
      }
      await _redrawRouteFromLiveLocation();
      return;
    }

    final LatLng? startLoc = _professionalLocation ?? hubLoc;
    if (startLoc == null) {
      if (mounted) {
        setState(() {
          _isLoadingMap = false;
        });
      }
      return;
    }

    try {
      final url =
          'https://api.mapbox.com/directions/v5/mapbox/driving/${startLoc.longitude},${startLoc.latitude};${userLoc.longitude},${userLoc.latitude}?geometries=geojson&access_token=${MapboxConfig.accessToken}';
      final response = await HttpClient()
          .getUrl(Uri.parse(url))
          .then((req) => req.close())
          .then((res) => res.transform(utf8.decoder).join());
      final data = jsonDecode(response) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes != null && routes.isNotEmpty) {
        final route = routes.first as Map<String, dynamic>;
        final geometry = route['geometry'] as Map<String, dynamic>;
        final coordinates = geometry['coordinates'] as List;
        final distance = route['distance'] as num;
        final duration = route['duration'] as num;

        if (mounted) {
          final distKm = distance / 1000.0;
          final durMin = math.max(1, (duration / 60.0).round());
          setState(() {
            _applyMapboxRoute(
              points: coordinates
                  .map((c) => LatLng(c[1] as double, c[0] as double))
                  .toList(),
              distanceKm: distKm,
              durationMin: durMin,
              routedFrom: startLoc,
            );
            _isLoadingMap = false;
          });
          _recomputeLiveMetrics(startLoc, forceUi: true);
          _centerMapOnLivePin(
            _displayedProfessionalLocation ??
                _professionalLocation ??
                startLoc,
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('Error getting directions: $e');
    }

    if (mounted) {
      setState(() {
        _isLoadingMap = false;
      });
    }
  }

  Widget _buildMapWidget() {
    if (_isLoadingMap) {
      return const Center(
        child: CircularProgressIndicator(color: HestiaColors.primary),
      );
    }

    if (_userLocation == null) {
      return const Center(
        child: Text(
          'Map data unavailable',
          style: TextStyle(color: HestiaColors.textLight),
        ),
      );
    }

    final LatLng? startLoc = _getRouteStartLocation();
    final LatLng? livePin =
        _displayedProfessionalLocation ?? _professionalLocation ?? startLoc;

    // On-the-way: lock tightly on the professional (or hub) icon.
    final LatLng mapCenter;
    final double mapZoom;
    if (_isOnTheWayView) {
      mapCenter = livePin ?? _userLocation!;
      mapZoom = _liveFollowZoom;
      _currentMapCenter = mapCenter;
      _currentMapZoom = mapZoom;
    } else {
      mapCenter = _currentMapCenter ??
          (startLoc != null
              ? LatLng(
                  (startLoc.latitude + _userLocation!.latitude) / 2,
                  (startLoc.longitude + _userLocation!.longitude) / 2,
                )
              : _userLocation!);
      mapZoom = _currentMapZoom;
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: mapCenter,
        initialZoom: mapZoom,
        interactionOptions: InteractionOptions(
          // No pinch/scroll zoom or pan while following the pro.
          flags: _isOnTheWayView ? InteractiveFlag.none : InteractiveFlag.all,
        ),
        onPositionChanged: (position, hasGesture) {
          if (_isOnTheWayView) return;
          _currentMapCenter = position.center;
          _currentMapZoom = position.zoom;
        },
      ),
      children: [
        TileLayer(
          urlTemplate: MapboxConfig.accessToken.isNotEmpty
              ? 'https://api.mapbox.com/styles/v1/${MapboxConfig.styleId}/tiles/256/{z}/{x}/{y}@2x?access_token=${MapboxConfig.accessToken}'
              : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.hestia_consumer_app',
        ),
        if (_routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                color: HestiaColors.primary,
                strokeWidth: 4.0,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (startLoc != null)
              Marker(
                point: startLoc,
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: _shouldRouteFromProfessionalLiveLocation()
                    ? Transform.rotate(
                        // Icons.navigation_rounded points up (north). Geographic
                        // bearing is clockwise from north — no extra -90 offset.
                        angle: _carBearingDegrees * math.pi / 180,
                        child: Container(
                          decoration: BoxDecoration(
                            color: HestiaColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: HestiaColors.primary
                                    .withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.navigation_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.store_mall_directory_rounded,
                        color: HestiaColors.primary,
                        size: 30,
                      ),
              ),
            Marker(
              point: _userLocation!,
              width: 40,
              height: 40,
              child: const Icon(
                Icons.location_on_rounded,
                color: Colors.redAccent,
                size: 30,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _mapChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  String _formatEndsAtText() {
    final actualStartObj = _bookingData['actual_start'];
    if (actualStartObj == null) return 'Ends at --:-- · -- min left';
    
    final DateTime actualStart = actualStartObj is DateTime 
        ? actualStartObj 
        : DateTime.parse(actualStartObj.toString());
        
    final double durationHours = (_bookingData['duration_hours'] as num?)?.toDouble() ?? 2.0;
    final int durationMinutes = (durationHours * 60).round();
    final DateTime expectedEnd = actualStart.add(Duration(minutes: durationMinutes));
        
    final DateTime localEnd = expectedEnd.toLocal();
    int hour = localEnd.hour;
    final minute = localEnd.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;
    final endsAtStr = '$hour:$minute $period';
    
    final difference = expectedEnd.toUtc().difference(DateTime.now().toUtc());
    if (difference.isNegative) {
      return 'Ends at $endsAtStr · Completed';
    }
    
    final minutesLeft = difference.inMinutes;
    if (minutesLeft < 60) {
      return 'Ends at $endsAtStr · $minutesLeft min left';
    } else {
      final hoursLeft = minutesLeft ~/ 60;
      final remainingMins = minutesLeft % 60;
      if (remainingMins == 0) {
        return 'Ends at $endsAtStr · $hoursLeft hr left';
      } else {
        return 'Ends at $endsAtStr · $hoursLeft hr $remainingMins min left';
      }
    }
  }

  Future<void> _refreshUnreadChatCount() async {
    final sessionId = _bookingData['session_id']?.toString();
    if (sessionId == null || sessionId.isEmpty) return;
    final count = await SupabaseService.getUnreadChatCount(sessionId);
    if (!mounted) return;
    if (count != _unreadChatCount) {
      setState(() => _unreadChatCount = count);
    }
  }

  void _subscribeToChatUnread() {
    final sessionId = _bookingData['session_id']?.toString();
    if (sessionId == null || sessionId.isEmpty) return;
    if (_subscribedChatSessionId == sessionId && _chatChannel != null) {
      return;
    }

    if (_chatChannel != null) {
      SupabaseService.client.removeChannel(_chatChannel!);
      _chatChannel = null;
    }

    _subscribedChatSessionId = sessionId;
    _chatChannel = SupabaseService.client
        .channel('tracking_chat_unread_$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (payload) {
            final record = Map<String, dynamic>.from(payload.newRecord);
            if (!SupabaseService.isInboundChatMessage(record)) return;
            if (!mounted) return;
            setState(() => _unreadChatCount += 1);
          },
        )
        .subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            _refreshUnreadChatCount();
          }
        });
  }

  String _activityLogKey(Map<String, dynamic> log) {
    final id = log['id']?.toString();
    if (id != null && id.isNotEmpty) return id;
    return '${log['logged_at']}|${log['activity_type']}|${log['note']}';
  }

  void _upsertActivityLog(Map<String, dynamic> record) {
    if (!mounted) return;
    final key = _activityLogKey(record);
    final existingIndex =
        _activityLogs.indexWhere((log) => _activityLogKey(log) == key);

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

  Future<void> _loadActivityLogs({bool silent = false}) async {
    final sessionId = _bookingData['session_id']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      if (mounted && !silent) {
        setState(() {
          _activityLogs.clear();
        });
      }
      return;
    }

    if (_isRefreshingActivityLogs) return;
    _isRefreshingActivityLogs = true;

    try {
      final logs = await SupabaseService.getActivityLogs(sessionId);
      if (!mounted) return;
      setState(() {
        _activityLogs
          ..clear()
          ..addAll(logs);
      });
    } finally {
      _isRefreshingActivityLogs = false;
    }
  }

  void _subscribeToActivityLogs() {
    final sessionId = _bookingData['session_id']?.toString();
    if (sessionId == null || sessionId.isEmpty) return;
    if (_subscribedActivitySessionId == sessionId && _activityChannel != null) {
      return;
    }

    if (_activityChannel != null) {
      SupabaseService.client.removeChannel(_activityChannel!);
      _activityChannel = null;
    }

    _subscribedActivitySessionId = sessionId;
    _activityChannel = SupabaseService.client
        .channel('tracking_activity_live_$sessionId')
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
            _upsertActivityLog(Map<String, dynamic>.from(payload.newRecord));
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
            _upsertActivityLog(Map<String, dynamic>.from(payload.newRecord));
          },
        )
        .subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            _loadActivityLogs(silent: true);
          }
        });
  }

  String _formatActivityTime(dynamic timeObj) {
    if (timeObj == null) return '--:--';
    final parsed =
        timeObj is DateTime ? timeObj : DateTime.parse(timeObj.toString());
    final local = parsed.toLocal();
    int hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;
    return '$hour:$minute $period';
  }

  int _getVisibleLogsCount() {
    return _activityLogs.length;
  }

  Widget _buildActivityLogsList() {
    if (_activityLogs.isEmpty) {
      return _activityLogCard(
        highlight: false,
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
              'Updates from the professional will appear here.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    final previewCount =
        _activityLogs.length > 3 ? 3 : _activityLogs.length;
    return Column(
      children: List.generate(previewCount, (index) {
        final log = _activityLogs[index];
        final message =
            (log['note']?.toString().trim().isNotEmpty ?? false)
                ? log['note'].toString().trim()
                : (log['activity_type']?.toString() ?? 'Activity update');
        final activityType = log['activity_type']?.toString() ?? 'Activity';
        final loggedAt = log['logged_at'];
        final isLatest = index == 0;

        return Padding(
          padding: EdgeInsets.only(bottom: index == previewCount - 1 ? 0 : 12),
          child: _activityLogCard(
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              message,
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(999),
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
                        '$activityType · ${_formatActivityTime(loggedAt)}',
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
                  _formatActivityTime(loggedAt),
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
    );
  }

  Widget _activityLogCard({
    required Widget child,
    required bool highlight,
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

  @override
  Widget build(BuildContext context) {
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
          title: () {
            final status = _bookingData['status']?.toString().toLowerCase();
            final isSessionActive = (status == 'started' || status == 'active' || status == 'in_progress');
            if (!isSessionActive) {
              final firstName = professionalFirstName(
                _bookingData['caregiver_name']?.toString(),
              );
              final runningLate = status != 'arrived' &&
                  isProfessionalRunningLateForBooking(_bookingData);
              final label = status == 'arrived'
                  ? '$firstName has arrived'
                  : runningLate
                      ? '$firstName is running late'
                      : '$firstName is on the way';
              return Text(
                label,
                style: TextStyle(
                  color: runningLate
                      ? const Color(0xFFE65100)
                      : HestiaColors.primary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              );
            }
            return const Text(
              'Active Session',
              style: TextStyle(
                color: HestiaColors.primary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            );
          }(),
          centerTitle: true,
          actions: [
            if (!_isOnTheWayView)
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: GestureDetector(
                  onTap: () async {
                    final sessionId =
                        _bookingData['session_id']?.toString() ?? '';
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(
                          sessionId: sessionId,
                          caregiverName:
                              _bookingData['caregiver_name'] ?? 'Professional',
                          actualStart:
                              _bookingData['actual_start'] as DateTime?,
                          durationHours:
                              (_bookingData['duration_hours'] as num?)
                                  ?.toDouble(),
                        ),
                      ),
                    );
                    if (!mounted) return;
                    SupabaseService.markChatRead(sessionId);
                    setState(() => _unreadChatCount = 0);
                  },
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    HestiaColors.primary.withValues(alpha: 0.15),
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: HestiaColors.primary,
                              size: 18,
                            ),
                          ),
                        ),
                        if (_unreadChatCount > 0)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 18),
                              height: 18,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFC0392B),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _unreadChatCount > 9
                                    ? '9+'
                                    : '$_unreadChatCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
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
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _isOnTheWayView ? _buildOnTheWayView() : _buildActiveSessionView(),
          ),
        ),
        bottomNavigationBar: !_isOnTheWayView
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC0392B),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => EmergencyScreen(
                              bookingData: _bookingData,
                            ),
                          ),
                        );
                      },
                      child: const Text(
                        'Emergency — Contact Dispatch',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildOnTheWayView() {
    final isArrived = _bookingData['status']?.toString().toLowerCase() == 'arrived';
    final isClosed = ['completed', 'no_show', 'cancelled']
        .contains(_bookingData['status']?.toString().toLowerCase());
    final isRunningLate =
        !isArrived && isProfessionalRunningLateForBooking(_bookingData);
    final etaText = _routeDurationMin > 0
        ? '$_routeDurationMin min'
        : (_mapboxRouteDurationMin > 0 ? '$_mapboxRouteDurationMin min' : '--');
    final displayDistanceKm = _routeDistanceKm > 0.001
        ? _routeDistanceKm
        : _mapboxRouteDistanceKm;
    final distanceText = displayDistanceKm > 0.001
        ? (displayDistanceKm < 1
            ? '${(displayDistanceKm * 1000).round()} m'
            : '${displayDistanceKm.toStringAsFixed(1)} km')
        : '--';
    final sessionText = _formatMetricTime().replaceAll('\n', ' ');
    final sheetMessage = isArrived
        ? 'Professional is at the booking address. Expand to verify arrival and see full details.'
        : isRunningLate
            ? professionalRunningLateMessage(
                _bookingData['caregiver_name']?.toString(),
              )
            : _professionalLocation != null
                ? 'Live route from professional to your booking address.'
                : 'Waiting for professional live location to draw the route.';

    return Stack(
      key: const ValueKey('on_the_way'),
      children: [
        Positioned.fill(
          child: Stack(
            children: [
              Positioned.fill(child: _buildMapWidget()),
              Positioned(
                top: 16,
                left: 20,
                right: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isRunningLate && !isArrived) ...[
                      Center(
                        child: Text(
                          'Trying to reach your location quickly',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    Row(
                      children: [
                        _mapChip(
                          icon: Icons.route_rounded,
                          label: isArrived
                              ? 'At your address'
                              : isRunningLate
                                  ? 'Delayed'
                                  : displayDistanceKm > 0.001
                                      ? '$distanceText away'
                                      : 'Updating route',
                        ),
                        const SizedBox(width: 10),
                        _mapChip(
                          icon: Icons.schedule_rounded,
                          label: isArrived
                              ? 'Ready to verify'
                              : isRunningLate
                                  ? 'Past start time'
                                  : (_routeDurationMin > 0 ||
                                          _mapboxRouteDurationMin > 0)
                                      ? 'ETA $etaText'
                                      : 'ETA --',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: NotificationListener<DraggableScrollableNotification>(
              onNotification: (notification) {
                final expandedNow = notification.extent > 0.50;
                if (expandedNow != _isOnTheWaySheetExpanded) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _isOnTheWaySheetExpanded = expandedNow;
                      });
                    }
                  });
                }
                return false;
              },
              child: DraggableScrollableSheet(
                controller: _onTheWaySheetController,
                expand: true,
                initialChildSize: 0.42,
                minChildSize: 0.42,
                maxChildSize: isArrived ? 0.82 : 0.72,
                snap: true,
                snapSizes: <double>[
                  0.42,
                  0.56,
                  if (isArrived) 0.82 else 0.72,
                ],
                builder: (context, scrollController) {
                  return Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF9F6F2),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x26000000),
                          blurRadius: 18,
                          offset: Offset(0, -6),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: CustomScrollView(
                        controller: scrollController,
                        physics: const BouncingScrollPhysics(),
                        slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      final currentSize =
                                          _onTheWaySheetController.isAttached
                                              ? _onTheWaySheetController.size
                                              : 0.42;
                                      final maxSize = isArrived ? 0.82 : 0.72;
                                      final targetSize = currentSize < 0.50
                                          ? 0.56
                                          : (currentSize < (maxSize - 0.04)
                                              ? maxSize
                                              : 0.42);
                                      _onTheWaySheetController.animateTo(
                                        targetSize,
                                        duration: const Duration(milliseconds: 280),
                                        curve: Curves.easeOutCubic,
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Container(
                                        width: 52,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFD8C7B9),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _sheetSummaryMetric('ETA', etaText),
                                    ),
                                    _sheetDivider(),
                                    Expanded(
                                      child: _sheetSummaryMetric('DISTANCE', distanceText),
                                    ),
                                    _sheetDivider(),
                                    Expanded(
                                      child: _sheetSummaryMetric('SESSION', sessionText),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  sheetMessage,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isRunningLate && !isArrived
                                        ? const Color(0xFF8D4E00)
                                        : HestiaColors.textMedium,
                                    height: 1.35,
                                    fontWeight: isRunningLate && !isArrived
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                // Always visible when collapsed — fills empty sheet space.
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: HestiaColors.primary.withValues(alpha: 0.12),
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
                                          _getInitials(
                                            _bookingData['caregiver_name'] ?? 'P',
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
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
                                              _bookingData['caregiver_name'] ??
                                                  'Professional',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: HestiaColors.textDark,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              '${_bookingData['title'] ?? 'Care'} Specialist',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: HestiaColors.textMedium,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.star,
                                                color: Colors.orange,
                                                size: 16,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                _formatProfessionalRating(),
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: HestiaColors.textDark,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (_formatProfessionalSessions()
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              _formatProfessionalSessions(),
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: HestiaColors.textLight,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBF7),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: HestiaColors.primary.withValues(alpha: 0.12),
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'LIVE ROUTE',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: HestiaColors.textLight,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      _routeEndpointRow(
                                        icon: Icons.directions_car_rounded,
                                        label: 'From',
                                        value: _formatRouteSourceLabel(),
                                        iconColor: HestiaColors.primary,
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(left: 10),
                                        child: Container(
                                          width: 1.5,
                                          height: 18,
                                          color: HestiaColors.primary
                                              .withValues(alpha: 0.22),
                                        ),
                                      ),
                                      _routeEndpointRow(
                                        icon: Icons.location_on_rounded,
                                        label: 'To',
                                        value: _formatRouteDestinationLabel(),
                                        iconColor: Colors.redAccent,
                                      ),
                                    ],
                                  ),
                                ),
                                if (isArrived) ...[
                                  const SizedBox(height: 12),
                                  _buildCollapsedVerifyPrompt(),
                                ],
                                AnimatedCrossFade(
                                  duration: const Duration(milliseconds: 220),
                                  firstChild: const SizedBox(height: 12),
                                  secondChild: const SizedBox(height: 18),
                                  crossFadeState: _isOnTheWaySheetExpanded
                                      ? CrossFadeState.showSecond
                                      : CrossFadeState.showFirst,
                                ),
                              ],
                            ),
                          ),
                        ),
                        SliverOpacity(
                          opacity: _isOnTheWaySheetExpanded ? 1 : 0,
                          sliver: SliverIgnorePointer(
                            ignoring: !_isOnTheWaySheetExpanded,
                            sliver: SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        _metricBlock('BOOKED', _formatMetricTime(), _formatMetricDuration()),
                                        const SizedBox(width: 10),
                                        _metricBlock('SERVICE', _formatMetricService(), 'Care'),
                                        const SizedBox(width: 10),
                                        _metricBlock('HUB', _formatMetricHub(), ''),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: HestiaColors.primary.withValues(alpha: 0.12),
                                          width: 1.2,
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.location_on_outlined,
                                            color: Color(0xFFC39365),
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              isArrived
                                                  ? 'Your professional has confirmed arrival. Please verify the arrival code to start the session.'
                                                  : _shouldRouteFromProfessionalLiveLocation()
                                                      ? 'Live route, distance and ETA are calculated from the professional\'s current location updates.'
                                                      : 'Route, distance and ETA are currently calculated from the assigned hub to your booking address until the professional begins transit.',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF78593E),
                                                height: 1.45,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isArrived) ...[
                                      const SizedBox(height: 18),
                                      _buildVerificationCard(),
                                      if (kDebugMode) ...[
                                        const SizedBox(height: 14),
                                        GestureDetector(
                                          onTap: () async {
                                            final bookingId = _bookingData['booking_id'];
                                            if (bookingId != null) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Simulating professional arrival...'),
                                                  duration: Duration(seconds: 1),
                                                ),
                                              );
                                              await SupabaseService.requestSessionStart(bookingId.toString());
                                              final updated = await SupabaseService.getBookingStatus(bookingId.toString());
                                              if (updated != null && mounted) {
                                                setState(() {
                                                  _applyBookingData(updated);
                                                });
                                              }
                                            }
                                          },
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade800,
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            child: const Center(
                                              child: Text(
                                                'Simulate Arrival (Debug Mode)',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ] else if (!isClosed) ...[
                                      const SizedBox(height: 18),
                                      if (kDebugMode) ...[
                                        GestureDetector(
                                          onTap: () async {
                                            final bookingId = _bookingData['booking_id'];
                                            if (bookingId != null) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Simulating professional arrival...'),
                                                  duration: Duration(seconds: 1),
                                                ),
                                              );
                                              await SupabaseService.requestSessionStart(bookingId.toString());
                                              final updated = await SupabaseService.getBookingStatus(bookingId.toString());
                                              if (updated != null && mounted) {
                                                setState(() {
                                                  _applyBookingData(updated);
                                                });
                                              }
                                            }
                                          },
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
                                              ),
                                              borderRadius: BorderRadius.circular(16),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: Color(0x262ECC71),
                                                  blurRadius: 8,
                                                  offset: Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: const Center(
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.play_arrow_rounded, color: Colors.white),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'Simulate Professional Arrival',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ),
      ],
    );
  }

  Widget _buildActiveSessionView() {
    return SingleChildScrollView(
      key: const ValueKey('active_session'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time details panel
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: HestiaColors.primary,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: HestiaColors.primary.withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'SESSION TIME',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white.withValues(alpha: 0.85),
                            letterSpacing: 0.8,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF2ECC71),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Text(
                                'Live',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _formatStopwatch(_secondsElapsed),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _formatEndsAtText(),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Professional',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        (_bookingData['caregiver_name'] ?? 'Professional')
                            .toString()
                            .replaceFirst(' ', '\n'),
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Activity log header
          GestureDetector(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ActivityLogScreen(
                    bookingData: _bookingData,
                  ),
                ),
              );
              if (mounted) {
                _loadActivityLogs(silent: true);
              }
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Activity log',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: HestiaColors.textDark,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_getVisibleLogsCount()} ${_getVisibleLogsCount() == 1 ? "entry" : "entries"}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF2E7D32),
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Activity log entries list
          _buildActivityLogsList(),
          const SizedBox(height: 24),
          // Caregiver Footer Info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: HestiaColors.primary,
              borderRadius: BorderRadius.circular(20),
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
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _getInitials(_bookingData['caregiver_name'] ?? 'P'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _bookingData['caregiver_name'] ?? 'Professional',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_bookingData['title'] ?? 'Care'} Specialist · Verified',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.verified_user_rounded,
                  color: Colors.white.withValues(alpha: 0.95),
                  size: 20,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // End Session Button
          SizedBox(
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
              onPressed: _showEndSessionWarningDialog,
              child: const Text(
                'End Session',
                style: TextStyle(
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

  void _showEndSessionWarningDialog() {
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: const Color(0xFFFAF6F0),
          title: const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFC0392B),
                size: 28,
              ),
              SizedBox(width: 10),
              Text(
                'End Session?',
                style: TextStyle(
                  color: HestiaColors.textDark,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          content: const Text(
            'Are you sure you want to end this session? This action cannot be undone.',
            style: TextStyle(
              color: HestiaColors.textDark,
              fontSize: 14,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: HestiaColors.primary.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: HestiaColors.textMedium,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      if (_isEndingSession || _hasNavigatedToReview) return;
                      Navigator.of(dialogContext).pop(); // close warning dialog

                      var sessionId = _bookingData['session_id']?.toString();
                      final bookingId = _bookingData['booking_id']?.toString();

                      if ((sessionId == null || sessionId.isEmpty) &&
                          bookingId != null &&
                          bookingId.isNotEmpty) {
                        final refreshed =
                            await SupabaseService.getBookingStatus(bookingId);
                        sessionId = refreshed?['session_id']?.toString();
                        if (refreshed != null && mounted) {
                          setState(() => _applyBookingData(refreshed));
                        }
                      }

                      if (sessionId == null || sessionId.isEmpty) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Unable to end session: missing session id.',
                            ),
                          ),
                        );
                        return;
                      }

                      if (!mounted) return;

                      // Block realtime/polling from racing while End Session owns nav.
                      _isEndingSession = true;
                      _tearDownLiveSessionListeners();

                      BuildContext? loadingDialogContext;
                      var loadingOpen = true;
                      showDialog<void>(
                        context: context,
                        useRootNavigator: true,
                        barrierDismissible: false,
                        builder: (ctx) {
                          loadingDialogContext = ctx;
                          return const Center(
                            child: CircularProgressIndicator(
                              color: HestiaColors.primary,
                            ),
                          );
                        },
                      );

                      void dismissLoading() {
                        if (!loadingOpen) return;
                        loadingOpen = false;
                        final dialogCtx = loadingDialogContext;
                        // Only pop the loading dialog — never the review route.
                        if (dialogCtx != null && dialogCtx.mounted) {
                          Navigator.of(dialogCtx).pop();
                        }
                      }

                      try {
                        await SupabaseService.endSessionByClient(
                          sessionId: sessionId,
                        ).timeout(const Duration(seconds: 20));

                        final updated = bookingId != null
                            ? await SupabaseService.getBookingStatus(bookingId)
                                .timeout(
                                  const Duration(seconds: 10),
                                  onTimeout: () => null,
                                )
                            : null;

                        dismissLoading();
                        if (!mounted) return;

                        _goToReviewScreen(
                          data: updated ?? _bookingData,
                          force: true,
                        );
                      } catch (e) {
                        // Allow retry if ending failed.
                        _isEndingSession = false;
                        if (mounted) {
                          dismissLoading();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Failed to end session: $e'),
                            ),
                          );
                          // Resume live listeners after a failed end attempt.
                          _startStopwatch();
                          _startStatusPolling();
                          _initRealtimeSubscription();
                          _subscribeToActivityLogs();
                          _startLocationTracking();
                          _subscribeToChatUnread();
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC0392B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'End Session',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _startLocationTracking() {
    _locationTimer?.cancel();
    if (_locationChannel != null) {
      SupabaseService.client.removeChannel(_locationChannel!);
      _locationChannel = null;
      _subscribedLocationSessionId = null;
    }

    Future<void> pollLiveLocationAndRoute() async {
      final moved = await _refreshProfessionalLocation();
      if (!mounted) return;
      if (_professionalLocation != null) {
        _recomputeLiveMetrics(_professionalLocation!, forceUi: true);
      }
      if (moved ||
          (_shouldRouteFromProfessionalLiveLocation() &&
              _professionalLocation != null &&
              _routePoints.isEmpty)) {
        _scheduleLiveRouteRedraw(immediate: _routePoints.isEmpty || moved);
      }
    }

    // Fast poll so consumer stays close to staff GPS syncs even if realtime lags.
    unawaited(pollLiveLocationAndRoute());
    _locationTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(pollLiveLocationAndRoute());
    });

    final sessionId = _bookingData['session_id']?.toString();
    if (sessionId == null || sessionId.isEmpty) return;
    _subscribedLocationSessionId = sessionId;

    void handleLocationPayload(Map<String, dynamic> record) {
      final parsed = SupabaseService.parseProfessionalCoordinatesPublic(
        record['coordinates'],
      );
      if (parsed != null) {
        final next = LatLng(parsed['latitude']!, parsed['longitude']!);
        final moved = _applyProfessionalLocation(next);
        if (moved) {
          _scheduleLiveRouteRedraw(immediate: true);
        }
        return;
      }
      // Geography payload couldn't be parsed — fall back to RPC lat/lng.
      unawaited(() async {
        final moved = await _refreshProfessionalLocation();
        if (moved) {
          _scheduleLiveRouteRedraw(immediate: true);
        }
      }());
    }

    _locationChannel = SupabaseService.client
        .channel('pro_locations_live_$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'professional_locations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (payload) {
            handleLocationPayload(
              Map<String, dynamic>.from(payload.newRecord),
            );
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'professional_locations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (payload) {
            handleLocationPayload(
              Map<String, dynamic>.from(payload.newRecord),
            );
          },
        )
        .subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(pollLiveLocationAndRoute());
          }
        });
  }

  void _initRealtimeSubscription() {
    final bookingId = _bookingData['booking_id'];
    if (bookingId == null) return;

    _realtimeChannel = SupabaseService.client
        .channel('client_session_$bookingId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: bookingId.toString(),
          ),
          callback: (payload) {
            if (_hasNavigatedToReview || _isEndingSession || !mounted) return;
            final newStatus =
                payload.newRecord['status']?.toString().toLowerCase();
            final oldStatus =
                payload.oldRecord['status']?.toString().toLowerCase();
            if (newStatus == null) return;

            if (newStatus == 'arrived' && oldStatus != 'arrived') {
              unawaited(_refreshBookingFromServer(openVerify: true));
              return;
            }

            final arrivalCode =
                payload.newRecord['arrival_code']?.toString();
            final startTime = payload.newRecord['start_time']?.toString();
            final previousRouteMode =
                _shouldRouteFromProfessionalLiveLocation();
            setState(() {
              _bookingData['status'] = newStatus;
              if (arrivalCode != null) {
                _bookingData['arrival_code'] = arrivalCode;
              }
              if (startTime != null) {
                _bookingData['actual_start'] = DateTime.parse(startTime);
              }
              _applyStatusToView(newStatus);
              if (_isActiveSessionStatus(newStatus)) {
                _startStopwatch();
              }
            });
            if (_isCompletedStatus(newStatus)) {
              _goToReviewScreen(
                data: Map<String, dynamic>.from(_bookingData),
              );
              return;
            }
            if (previousRouteMode !=
                _shouldRouteFromProfessionalLiveLocation()) {
              _startLocationTracking();
              _loadRouteAndCoordinates();
            }
          },
        );
    _realtimeChannel?.subscribe();
  }

  Widget _buildCollapsedVerifyPrompt() {
    return GestureDetector(
      onTap: () => _expandSheetForVerify(focusCode: true),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: HestiaColors.primary.withValues(alpha: 0.2),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.verified_user_rounded,
              color: HestiaColors.primary,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${professionalFirstName(_bookingData['caregiver_name']?.toString())} has arrived',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: HestiaColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Tap to enter the arrival code and start your session',
                    style: TextStyle(
                      fontSize: 12,
                      color: HestiaColors.textMedium,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_up_rounded,
              color: HestiaColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: HestiaColors.primary.withValues(alpha: 0.15),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.verified_user_rounded,
                color: HestiaColors.primary,
                size: 24,
              ),
              SizedBox(width: 8),
              Text(
                'Verify Arrival',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: HestiaColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Ask your professional for the verification code shown on their app.',
            style: TextStyle(
              fontSize: 13,
              color: HestiaColors.textMedium,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          // 6-character text field
          TextField(
            controller: _codeController,
            focusNode: _codeFocusNode,
            maxLength: 6,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: HestiaColors.primary,
              letterSpacing: 8.0,
            ),
            decoration: InputDecoration(
              hintText: 'CODE12',
              hintStyle: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade300,
                letterSpacing: 8.0,
              ),
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              filled: true,
              fillColor: const Color(0xFFFAF6F0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: HestiaColors.primary.withValues(alpha: 0.2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: HestiaColors.primary.withValues(alpha: 0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: HestiaColors.primary, width: 2),
              ),
            ),
            onChanged: (val) {
              setState(() {
                _enteredCode = val;
                _verificationError = null;
              });
            },
          ),
          if (_verificationError != null) ...[
            const SizedBox(height: 8),
            Text(
              _verificationError!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: (_enteredCode.trim().length == 6 && !_isStartingSession)
                  ? _handleStartSession
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: HestiaColors.primary,
                disabledBackgroundColor: HestiaColors.primary.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isStartingSession
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Start Session',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleStartSession() async {
    final sessionId = _bookingData['session_id'];
    if (sessionId == null) {
      setState(() {
        _verificationError = 'Session not found';
      });
      return;
    }

    setState(() {
      _isStartingSession = true;
      _verificationError = null;
    });

    try {
      await SupabaseService.startSessionByClient(
        sessionId: sessionId.toString(),
        arrivalCode: _enteredCode,
      );

      // Immediately refresh status
      final updated = await SupabaseService.getBookingStatus(widget.bookingData['booking_id'].toString());
      if (updated != null && mounted) {
        setState(() {
                          _applyBookingData(updated);
          final status = _bookingData['status'];
          final isSessionActive = (status == 'started' || status == 'active' || status == 'in_progress');
          if (isSessionActive) {
            _isOnTheWayView = false;
            _startStopwatch();
            _statusTimer?.cancel();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _verificationError = "Code doesn't match. Ask your professional to read it again.";
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStartingSession = false;
        });
      }
    }
  }

  Widget _metricBlock(String label, String value, String sub) {
    return Expanded(
      child: Container(
        height: 96,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFDFCFB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: HestiaColors.primary.withValues(alpha: 0.1),
            width: 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: HestiaColors.textLight,
                letterSpacing: 0.6,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: HestiaColors.textDark,
                height: 1.15,
              ),
            ),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                sub,
                style: const TextStyle(
                  fontSize: 9,
                  color: HestiaColors.textLight,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sheetSummaryMetric(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: HestiaColors.textLight,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: HestiaColors.textDark,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetDivider() {
    return Container(
      width: 1,
      height: 40,
      color: HestiaColors.primary.withValues(alpha: 0.12),
    );
  }

  Widget _routeEndpointRow({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: HestiaColors.textLight,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  color: HestiaColors.textDark,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 1. Sage Green Background
    final Paint backgroundPaint = Paint()
      ..color = const Color(0xFFCADFC6)
      ..style = PaintingStyle.fill;
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(20),
      ),
      backgroundPaint,
    );

    // 2. Road Network (Off-white roads)
    final Paint roadPaint = Paint()
      ..color = const Color(0xFFE3EDE0)
      ..strokeWidth = 32.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Draw horizontal grid lines
    canvas.drawLine(Offset(-20, size.height * 0.25), Offset(size.width + 20, size.height * 0.25), roadPaint);
    canvas.drawLine(Offset(-20, size.height * 0.65), Offset(size.width + 20, size.height * 0.65), roadPaint);

    // Draw vertical grid lines
    canvas.drawLine(Offset(size.width * 0.25, -20), Offset(size.width * 0.25, size.height + 20), roadPaint);
    canvas.drawLine(Offset(size.width * 0.75, -20), Offset(size.width * 0.75, size.height + 20), roadPaint);

    // 3. Blocks/Buildings (rectangular overlays)
    final Paint buildingPaint = Paint()
      ..color = const Color(0xFFBED2B9)
      ..style = PaintingStyle.fill;

    // Place building blocks in intersections
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(15, 12, size.width * 0.16, size.height * 0.15), const Radius.circular(8)), buildingPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.32, 12, size.width * 0.36, size.height * 0.15), const Radius.circular(8)), buildingPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(15, size.height * 0.33, size.width * 0.16, size.height * 0.24), const Radius.circular(8)), buildingPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.32, size.height * 0.33, size.width * 0.36, size.height * 0.24), const Radius.circular(8)), buildingPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.82, size.height * 0.33, size.width * 0.15, size.height * 0.24), const Radius.circular(8)), buildingPaint);

    // 4. Dotted route path calculation
    final List<Offset> routePoints = [];
    final int steps = 40;
    
    // Smooth bezier curve from Hub (0.18, 0.25) to Caregiver Location (0.6, 0.65)
    final Offset start = Offset(size.width * 0.18, size.height * 0.25);
    final Offset end = Offset(size.width * 0.7, size.height * 0.65);
    final Offset cp1 = Offset(size.width * 0.18, size.height * 0.65);
    final Offset cp2 = Offset(size.width * 0.5, size.height * 0.65);

    for (int i = 0; i <= steps; i++) {
      final double t = i / steps;
      final double t1 = 1 - t;
      
      // Cubic bezier interpolation
      final double x = t1 * t1 * t1 * start.dx +
          3 * t1 * t1 * t * cp1.dx +
          3 * t1 * t * t * cp2.dx +
          t * t * t * end.dx;
      final double y = t1 * t1 * t1 * start.dy +
          3 * t1 * t1 * t * cp1.dy +
          3 * t1 * t * t * cp2.dy +
          t * t * t * end.dy;
      
      routePoints.add(Offset(x, y));
    }

    // 5. Draw Dotted Path
    final Paint dotPaint = Paint()
      ..color = const Color(0xFF8C6239)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.fill;

    for (int i = 0; i < routePoints.length; i += 2) {
      canvas.drawCircle(routePoints[i], 2.5, dotPaint);
    }

    // 6. Draw Hub Pin anchor point
    final Paint hubAnchorPaint = Paint()
      ..color = const Color(0xFF8C6239)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(start, 4.0, hubAnchorPaint);

    // 7. Caregiver orange location indicator (pulse dot)
    final Paint outerGlowPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    final Paint innerDotPaint = Paint()
      ..color = const Color(0xFFF39C12)
      ..style = PaintingStyle.fill;

    // Position care assistant at t = 0.6 on the route path
    final Offset caregiverPos = routePoints[(steps * 0.55).floor()];
    canvas.drawCircle(caregiverPos, 7.0, outerGlowPaint);
    canvas.drawCircle(caregiverPos, 4.5, innerDotPaint);
  }

  @override
  bool shouldRepaint(covariant MapPainter oldDelegate) => false;
}
