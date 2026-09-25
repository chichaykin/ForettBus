import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../bus_arrivals.dart';
import '../notifications.dart';
import '../schedule.dart';
import '../trip_cards.dart';
import '../widgets/direction_toggle.dart';
import '../widgets/trip_card_view.dart';
import 'trip_cards_screen.dart';

enum _ArrivalStatus { idle, loading, loaded, empty }

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.isActive = true,
    this.direction = Direction.forettToBeautyWorld,
    required this.onDirectionChanged,
    this.arrivalRepository,
    this.tripCardsController,
    this.tripArrivalRepository,
  });

  final bool isActive;
  final Direction direction;
  final ValueChanged<Direction> onDirectionChanged;
  final BusArrivalsRepository? arrivalRepository;
  final TripCardsController? tripCardsController;
  final HttpBusStopArrivalsRepository? tripArrivalRepository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final BusArrivalsRepository _arrivalRepository;
  late final bool _ownsArrivalRepository;
  late final HttpBusStopArrivalsRepository _tripArrivalRepository;
  late final bool _ownsTripArrivalRepository;

  DateTime _now = BusSchedule.now();
  Timer? _timer;
  Timer? _arrivalTimer;
  bool _isAppActive = true;
  bool _isEditorOpen = false;
  DateTime? _reminderBusTime;
  Direction? _reminderDirection;
  bool _isUpdatingReminder = false;
  int _reminderRevision = 0;

  _ArrivalStatus _arrivalStatus = _ArrivalStatus.idle;
  BusArrivalsSnapshot? _arrivalSnapshot;
  String? _arrivalNotice;
  bool _isFetchingArrivals = false;
  int _arrivalRequestRevision = 0;
  final Map<String, StopArrivalsSnapshot> _tripStops = {};
  bool _isFetchingTripArrivals = false;
  int _tripArrivalRevision = 0;

  @override
  void initState() {
    super.initState();
    _ownsArrivalRepository = widget.arrivalRepository == null;
    _arrivalRepository =
        widget.arrivalRepository ?? HttpBusArrivalsRepository();
    _ownsTripArrivalRepository = widget.tripArrivalRepository == null;
    _tripArrivalRepository =
        widget.tripArrivalRepository ?? HttpBusStopArrivalsRepository();
    WidgetsBinding.instance.addObserver(this);
    BusSchedule.active.addListener(_handleScheduleChanged);
    widget.tripCardsController?.addListener(_handleTripCardsChanged);
    NotificationService().activeReminder.addListener(_handleReminderChanged);
    unawaited(_restoreReminder());
    if (widget.isActive) {
      _startTimer();
      _startArrivalPolling();
    }
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (_shouldRun) {
        _refreshClock(rebuild: false);
        _startTimer();
        _startArrivalPolling();
      } else {
        _stopTimers();
      }
    }
    if (oldWidget.direction != widget.direction) {
      _arrivalSnapshot = null;
      _arrivalStatus = _arrivalRepository.isConfigured
          ? _ArrivalStatus.loading
          : _ArrivalStatus.idle;
      _arrivalNotice = null;
      if (_shouldRun) unawaited(_refreshArrivals());
    }
  }

  void _handleScheduleChanged() {
    if (mounted) _refreshClock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppActive = state == AppLifecycleState.resumed;
    if (_shouldRun) {
      _refreshClock();
      _startTimer();
      _startArrivalPolling();
    } else {
      _stopTimers();
    }
  }

  bool get _shouldRun => widget.isActive && _isAppActive && !_isEditorOpen;

  void _stopTimers() {
    _timer?.cancel();
    _timer = null;
    _arrivalTimer?.cancel();
    _arrivalTimer = null;
    _tripArrivalRevision++;
  }

  void _refreshClock({bool rebuild = true}) {
    final now = BusSchedule.now();
    if (rebuild && mounted) {
      setState(() => _applyNow(now));
    } else {
      _applyNow(now);
    }
    NotificationService().expireReminderIfNeeded(now);
  }

  void _startTimer() {
    if (!_shouldRun) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_shouldRun) return;
      _refreshClock();
    });
  }

  void _startArrivalPolling() {
    if (!_shouldRun) return;
    if (!_arrivalRepository.isConfigured) {
      unawaited(_refreshTripArrivals());
      _useStaticFallback(widget.direction);
      _arrivalTimer?.cancel();
      _arrivalTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        _useStaticFallback(widget.direction);
        unawaited(_refreshTripArrivals());
      });
      return;
    }
    _arrivalTimer?.cancel();
    unawaited(_refreshArrivals());
    _arrivalTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_refreshArrivals());
      unawaited(_refreshTripArrivals());
    });
    unawaited(_refreshTripArrivals());
  }

  void _handleTripCardsChanged() {
    _tripArrivalRevision++;
    if (!mounted) return;
    setState(() => _tripStops.clear());
    if (_shouldRun) unawaited(_refreshTripArrivals());
  }

  Future<void> _refreshTripArrivals() async {
    final controller = widget.tripCardsController;
    if (!_shouldRun ||
        controller == null ||
        !_tripArrivalRepository.isConfigured ||
        _isFetchingTripArrivals) {
      return;
    }
    final revision = ++_tripArrivalRevision;
    final codes = controller.cards
        .expand((card) => card.selectedPlan.legs)
        .where((leg) => leg.isBus)
        .map((leg) => leg.from.code)
        .toSet();
    if (codes.isEmpty) return;
    setState(() => _isFetchingTripArrivals = true);
    final results = await Future.wait(
      codes.map((code) async {
        try {
          return await _tripArrivalRepository.fetch(code);
        } on Object {
          return null;
        }
      }),
    );
    if (!mounted) return;
    setState(() {
      _isFetchingTripArrivals = false;
      if (revision == _tripArrivalRevision && _shouldRun) {
        for (final snapshot in results.whereType<StopArrivalsSnapshot>()) {
          _tripStops[snapshot.stopCode] = snapshot;
        }
      }
    });
    // A direction change while fetching needs a new snapshot. The repository
    // shares/throttles stop requests, including across direction changes.
    if (revision != _tripArrivalRevision && _shouldRun) {
      unawaited(_refreshTripArrivals());
    }
  }

  Future<void> _editTripCard(TripCard card) async {
    _isEditorOpen = true;
    _stopTimers();
    final updated = await Navigator.of(context).push<TripCard>(
      MaterialPageRoute(builder: (_) => TripCardEditor(card: card)),
    );
    if (!mounted) return;
    if (updated != null) {
      await widget.tripCardsController?.update(updated);
      if (!mounted) return;
    }
    _isEditorOpen = false;
    if (_shouldRun) {
      _startTimer();
      _startArrivalPolling();
    }
  }

  Future<void> _refreshArrivals() async {
    if (!_shouldRun || _isFetchingArrivals) {
      return;
    }

    final direction = widget.direction;
    if (!_arrivalRepository.isConfigured) {
      _useStaticFallback(direction);
      return;
    }
    final requestRevision = ++_arrivalRequestRevision;
    _isFetchingArrivals = true;
    if (mounted) {
      setState(() {
        if (_arrivalSnapshot == null) _arrivalStatus = _ArrivalStatus.loading;
        _arrivalNotice = null;
      });
    }

    try {
      final snapshot = await _arrivalRepository.fetch(direction);
      if (!mounted ||
          requestRevision != _arrivalRequestRevision ||
          widget.direction != direction) {
        return;
      }
      final hasArrivals = snapshot.routes.any(
        (route) => route.arrivals.isNotEmpty,
      );
      setState(() {
        _arrivalSnapshot = snapshot;
        _arrivalStatus = hasArrivals
            ? _ArrivalStatus.loaded
            : _ArrivalStatus.empty;
        _arrivalNotice = null;
      });
    } on BusArrivalsException catch (error) {
      if (!mounted ||
          requestRevision != _arrivalRequestRevision ||
          widget.direction != direction) {
        return;
      }
      _useStaticFallback(
        direction,
        notice: error.type == BusArrivalsErrorType.unauthorized
            ? 'Live access unavailable · using Scheduled times'
            : 'Live data unavailable · using Scheduled times',
      );
    } on Object {
      if (!mounted ||
          requestRevision != _arrivalRequestRevision ||
          widget.direction != direction) {
        return;
      }
      _useStaticFallback(
        direction,
        notice: 'Live data unavailable · using Scheduled times',
      );
    } finally {
      _isFetchingArrivals = false;
      if (mounted && _shouldRun && widget.direction != direction) {
        unawaited(_refreshArrivals());
      }
    }
  }

  void _useStaticFallback(Direction direction, {String? notice}) {
    if (!mounted || widget.direction != direction) return;
    final snapshot = StaticBusSchedule.forDirection(
      direction: direction,
      now: _now,
    );
    final hasArrivals = snapshot.routes.any(
      (route) => route.arrivals.isNotEmpty,
    );
    setState(() {
      _arrivalSnapshot = snapshot;
      _arrivalStatus = hasArrivals
          ? _ArrivalStatus.loaded
          : _ArrivalStatus.empty;
      _arrivalNotice = notice;
    });
  }

  void _handleReminderChanged() {
    if (!mounted) return;
    final reminder = NotificationService().activeReminder.value;
    setState(() {
      _reminderBusTime = reminder?.busTime;
      _reminderDirection = reminder?.direction;
    });
  }

  void _applyNow(DateTime now) {
    _now = now;
    final busTime = _reminderBusTime;
    if (busTime != null && !now.isBefore(busTime)) {
      _reminderBusTime = null;
      _reminderDirection = null;
    }
  }

  Future<void> _restoreReminder() async {
    final revision = _reminderRevision;
    try {
      final reminder = await NotificationService().pendingBusReminder();
      if (!mounted || reminder == null || revision != _reminderRevision) return;
      setState(() {
        _reminderBusTime = reminder.busTime;
        _reminderDirection = reminder.direction;
      });
    } catch (_) {
      // The schedule remains usable when the platform cannot query alarms.
    }
  }

  @override
  void dispose() {
    _stopTimers();
    WidgetsBinding.instance.removeObserver(this);
    BusSchedule.active.removeListener(_handleScheduleChanged);
    widget.tripCardsController?.removeListener(_handleTripCardsChanged);
    NotificationService().activeReminder.removeListener(_handleReminderChanged);
    if (_ownsArrivalRepository) {
      (_arrivalRepository as HttpBusArrivalsRepository).close();
    }
    if (_ownsTripArrivalRepository) _tripArrivalRepository.close();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  bool _hasReminderFor(DateTime busTime, Direction direction) {
    return _reminderBusTime == busTime && _reminderDirection == direction;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleReminder(DateTime nextBus) async {
    if (_isUpdatingReminder) return;
    _reminderRevision++;
    final direction = widget.direction;
    final isReminderSet = _hasReminderFor(nextBus, direction);
    setState(() => _isUpdatingReminder = true);

    try {
      if (isReminderSet) {
        await NotificationService().cancelReminder();
        if (!mounted) return;
        setState(() {
          _reminderBusTime = null;
          _reminderDirection = null;
        });
        _showMessage('Reminder cancelled');
        return;
      }

      final granted = await NotificationService().requestPermission();
      if (!mounted) return;
      if (!granted) {
        _showMessage('Notification and alarm permissions are required');
        return;
      }

      final scheduled = await NotificationService().scheduleBusReminder(
        nextBus,
        direction,
      );
      if (!mounted) return;
      if (!scheduled) {
        _showMessage('Too close to departure to set reminder');
        return;
      }

      setState(() {
        _reminderBusTime = nextBus;
        _reminderDirection = direction;
      });
      _showMessage('Reminder set for 5 mins before departure');
    } catch (_) {
      if (mounted) {
        _showMessage('Could not update the reminder. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isUpdatingReminder = false);
    }
  }

  void _selectDirection(Direction direction) {
    if (_isUpdatingReminder || widget.direction == direction) return;
    widget.onDirectionChanged(direction);
  }

  String _formatArrival(BusArrival arrival, {required bool showCountdown}) {
    if (arrival.isScheduled) return 'Scheduled';
    if (!showCountdown) return 'Stale';

    final duration = arrival.estimatedArrival.difference(_now);
    if (duration < const Duration(minutes: 1)) return 'Arriving';
    return 'in ${duration.inMinutes} min';
  }

  String _formatSingaporeTime(DateTime value) {
    final singapore = tz.TZDateTime.from(value, BusSchedule.singaporeLocation);
    return DateFormat('HH:mm').format(singapore);
  }

  String _formatNextService(DateTime value) {
    final singapore = tz.TZDateTime.from(value, BusSchedule.singaporeLocation);
    return DateFormat('EEE, d MMM · HH:mm').format(singapore);
  }

  Widget _buildShuttleCard({
    required ColorScheme colors,
    required bool isOperating,
    required DateTime? nextBus,
    required bool isReminderSet,
    required bool hasHolidayCalendar,
  }) {
    final hasEnded = !isOperating || nextBus == null;
    if (hasEnded) {
      final nextService = BusSchedule.getNextOperatingDayBus(
        _now,
        widget.direction,
      );
      return Container(
        constraints: const BoxConstraints(minHeight: 136),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.directions_bus_outlined, color: colors.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Forett Shuttle',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOperating ? 'Service ended' : 'No shuttle today',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isOperating
                        ? 'The last shuttle has departed'
                        : 'Shuttle operates Monday–Saturday',
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (nextService != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Next service: ${_formatNextService(nextService)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
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

    return Container(
      constraints: const BoxConstraints(minHeight: 320),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.directions_bus_outlined, color: colors.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Forett Shuttle',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Next departure in',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _formatDuration(nextBus.difference(_now)),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.bold,
                    color: colors.onSurface,
                    letterSpacing: -2,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.schedule, size: 18, color: colors.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Departs at ${_formatSingaporeTime(nextBus)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isUpdatingReminder || !hasHolidayCalendar
                    ? null
                    : () => _toggleReminder(nextBus),
                icon: _isUpdatingReminder
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        isReminderSet
                            ? Icons.notifications_active
                            : Icons.notifications_none,
                      ),
                label: Text(
                  _isUpdatingReminder
                      ? 'Updating...'
                      : isReminderSet
                      ? 'Reminder Set'
                      : 'Remind me (5m before)',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isReminderSet
                      ? colors.primary
                      : colors.surface,
                  foregroundColor: isReminderSet
                      ? colors.onPrimary
                      : colors.onSurface,
                  elevation: 0,
                  side: BorderSide(
                    color: isReminderSet ? colors.primary : colors.outline,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
              if (!hasHolidayCalendar) ...[
                const SizedBox(height: 12),
                Text(
                  'Holiday calendar is unavailable for this date. Reminders are disabled.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArrivalBadge(
    BusArrival arrival,
    ColorScheme colors, {
    required String serviceNumber,
    required bool showCountdown,
  }) {
    final scheduledLabel = arrival.isScheduled ? ' · Scheduled' : '';
    final arrivalTime = _formatSingaporeTime(arrival.estimatedArrival);
    final arrivalStatus = _formatArrival(arrival, showCountdown: showCountdown);
    final statusStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: colors.onSurface,
    );
    return Tooltip(
      message: 'Route $serviceNumber · $arrivalTime$scheduledLabel',
      child: Semantics(
        container: true,
        label: 'Route $serviceNumber, $arrivalStatus, arrives at $arrivalTime',
        child: Container(
          constraints: const BoxConstraints(minWidth: 68, minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compactStatus = arrival.isScheduled
                  ? 'Sched.'
                  : arrivalStatus.startsWith('in ')
                  ? arrivalStatus.substring(3)
                  : arrivalStatus == 'Arriving'
                  ? 'Due'
                  : arrivalStatus;
              final statusCandidates = <String>[
                arrivalStatus,
                compactStatus,
                if (arrival.isScheduled) 'Sch.',
                if (arrivalStatus.startsWith('in '))
                  '${arrival.estimatedArrival.difference(_now).inMinutes}m',
                if (arrivalStatus == 'Stale') 'Old',
                '•',
              ];
              bool fits(String value) {
                final painter = TextPainter(
                  text: TextSpan(
                    text: value,
                    style: DefaultTextStyle.of(
                      context,
                    ).style.merge(statusStyle),
                  ),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 1,
                )..layout();
                final result = painter.width <= constraints.maxWidth;
                painter.dispose();
                return result;
              }

              final visibleStatus = statusCandidates.firstWhere(
                fits,
                orElse: () => statusCandidates.last,
              );

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    visibleStatus,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: statusStyle,
                  ),
                  Text(
                    arrivalTime,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildArrivalStatus({
    required BusArrivalsSnapshot snapshot,
    required bool isFallback,
    required bool isStale,
    required ColorScheme colors,
  }) {
    final String label;
    final Color color;
    final String updatedLabel;
    if (isFallback) {
      label = 'Scheduled timetable';
      color = colors.tertiary;
      updatedLabel = 'Static schedule';
    } else if (isStale) {
      label = 'Live data stale';
      color = colors.error;
      updatedLabel = 'Updated ${_formatSingaporeTime(snapshot.fetchedAt)}';
    } else {
      final arrivals = snapshot.routes
          .expand((route) => route.arrivals)
          .where((arrival) => !arrival.estimatedArrival.isBefore(_now));
      final hasLive = arrivals.any((arrival) => arrival.monitored);
      final hasScheduled = arrivals.any((arrival) => !arrival.monitored);
      label = hasLive
          ? (hasScheduled ? 'Live + scheduled' : 'Live ETA')
          : 'Scheduled';
      color = hasLive ? colors.primary : colors.tertiary;
      updatedLabel = 'Updated ${_formatSingaporeTime(snapshot.fetchedAt)}';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 2,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 9, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          Text(
            updatedLabel,
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildPublicBusesCard(ColorScheme colors) {
    final snapshot = _arrivalSnapshot;
    final isFallback = snapshot?.isFallback == true;
    final isStale =
        snapshot != null &&
        _now.difference(snapshot.fetchedAt) > const Duration(seconds: 60);
    final visibleRoutes = <BusRouteArrivals>[];
    if (snapshot != null) {
      for (final route in snapshot.routes) {
        final arrivals = route.arrivals
            .where((arrival) => !arrival.estimatedArrival.isBefore(_now))
            .take(3)
            .toList();
        if (arrivals.isNotEmpty) {
          visibleRoutes.add(
            BusRouteArrivals(
              serviceNumber: route.serviceNumber,
              arrivals: arrivals,
            ),
          );
        }
      }
      visibleRoutes.sort(
        (a, b) => a.arrivals.first.estimatedArrival.compareTo(
          b.arrivals.first.estimatedArrival,
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerHighest,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.directions_bus_outlined, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Public buses',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isFetchingArrivals
                      ? null
                      : () => _refreshArrivals(),
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh public buses',
                ),
              ],
            ),
            Text(
              '${BusStopConfig.forDirection(widget.direction).name} · routes 41 and 77',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
            ),
            if (snapshot != null)
              _buildArrivalStatus(
                snapshot: snapshot,
                isFallback: isFallback,
                isStale: isStale,
                colors: colors,
              ),
            const SizedBox(height: 6),
            if (isFallback)
              Text(
                _arrivalNotice ?? 'Scheduled timetable · live data unavailable',
                style: TextStyle(color: colors.tertiary),
              )
            else if (!_arrivalRepository.isConfigured)
              Text(
                'Live arrivals are not configured for this build.',
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              )
            else if (_arrivalStatus == _ArrivalStatus.loading &&
                snapshot == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (isStale && !isFallback)
              Text(
                'Live data is more than a minute old. Tap refresh to try again.',
                style: TextStyle(color: colors.error),
              ),
            if (snapshot != null && visibleRoutes.isEmpty)
              Text(
                isFallback
                    ? 'No upcoming scheduled buses are listed.'
                    : 'No upcoming buses are currently predicted.',
                style: TextStyle(color: colors.onSurfaceVariant),
              )
            else if (visibleRoutes.isNotEmpty) ...[
              for (final route in visibleRoutes)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 36,
                        child: Text(
                          route.serviceNumber,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: colors.primary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final textScale =
                                MediaQuery.textScalerOf(context).scale(14) / 14;
                            final columns =
                                (constraints.maxWidth / (80 * textScale))
                                    .floor()
                                    .clamp(1, route.arrivals.length);
                            const spacing = 6.0;
                            final badgeWidth =
                                (constraints.maxWidth -
                                    spacing * (columns - 1)) /
                                columns;
                            return Wrap(
                              spacing: spacing,
                              runSpacing: spacing,
                              children: [
                                for (final arrival in route.arrivals)
                                  SizedBox(
                                    width: badgeWidth,
                                    child: _buildArrivalBadge(
                                      arrival,
                                      colors,
                                      serviceNumber: route.serviceNumber,
                                      showCountdown: !isFallback && !isStale,
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTripCard(TripCard card, ColorScheme colors) => TripCardView(
    key: ValueKey(card.id),
    card: card,
    stops: _tripStops,
    now: _now,
    isLoading: _isFetchingTripArrivals,
    onDirectionChanged: (direction) =>
        widget.tripCardsController?.selectDirection(card.id, direction),
    onEdit: () => _editTripCard(card),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isOperating = BusSchedule.isOperatingDay(_now);
    final nextBus = BusSchedule.getNextBus(_now, widget.direction);
    final isReminderSet =
        nextBus != null && _hasReminderFor(nextBus, widget.direction);
    final hasHolidayCalendar = BusSchedule.hasHolidayCalendarFor(_now);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxHeight < 720;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isCompact ? 16 : 24,
                isCompact ? 12 : 24,
                isCompact ? 16 : 24,
                isCompact ? 16 : 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: isCompact ? 0 : 8),
                  DirectionToggle(
                    direction: widget.direction,
                    onChanged: _selectDirection,
                    multilineLabels: !isCompact,
                  ),
                  SizedBox(height: isCompact ? 12 : 16),
                  _buildShuttleCard(
                    colors: colors,
                    isOperating: isOperating,
                    nextBus: nextBus,
                    isReminderSet: isReminderSet,
                    hasHolidayCalendar: hasHolidayCalendar,
                  ),
                  SizedBox(height: isCompact ? 12 : 16),
                  _buildPublicBusesCard(colors),
                  if (widget.tripCardsController != null)
                    AnimatedBuilder(
                      animation: widget.tripCardsController!,
                      builder: (context, _) => Column(
                        children: [
                          for (final card
                              in widget.tripCardsController!.cards) ...[
                            const SizedBox(height: 12),
                            _buildTripCard(card, colors),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
