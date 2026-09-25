import 'dart:async';

import 'package:flutter/material.dart';
import 'app_settings.dart';
import 'notifications.dart';
import 'schedule.dart';
import 'screens/home_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/profile_screen.dart';
import 'trip_cards.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  late final AppSettings settings;
  try {
    settings = await AppSettings.load();
  } on Object {
    // A preferences plugin failure must not prevent the timetable from opening.
    settings = AppSettings.defaults();
  }
  try {
    await BusSchedule.load();
  } on Object {
    // The bundled timetable is always safe to use.
  }
  runApp(ShuttleBusApp(initialSettings: settings));
  unawaited(_initializeNotifications());
  unawaited(BusSchedule.refreshHolidayCalendar());
}

Future<void> _initializeNotifications() async {
  try {
    await NotificationService().init();
    await NotificationService().cancelReminderIfInvalid();
  } on Object catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        context: ErrorDescription('while initializing notifications'),
      ),
    );
  }
}

class ShuttleBusApp extends StatefulWidget {
  const ShuttleBusApp({super.key, this.initialSettings});

  final AppSettings? initialSettings;

  @override
  State<ShuttleBusApp> createState() => _ShuttleBusAppState();
}

class _ShuttleBusAppState extends State<ShuttleBusApp> {
  late bool _darkModeEnabled;
  late Direction _currentDirection;
  late final AppSettings _settings;
  late final TripCardsController _tripCardsController;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings ?? _defaultSettings();
    _darkModeEnabled = _settings.darkModeEnabled;
    _currentDirection = _directionFromLaunchUri() ?? _settings.direction;
    _tripCardsController = TripCardsController();
    unawaited(_tripCardsController.load());
    BusSchedule.active.addListener(_validateReminderAfterScheduleChange);
  }

  AppSettings _defaultSettings() {
    // Direct widget construction is useful in tests and previews. The real
    // entry point loads settings before runApp in main().
    return AppSettings.defaults();
  }

  Direction? _directionFromLaunchUri() {
    final value = Uri.base.queryParameters['direction'];
    if (value == null) return null;
    try {
      return Direction.values.byName(value);
    } on ArgumentError {
      return null;
    }
  }

  @override
  void dispose() {
    BusSchedule.active.removeListener(_validateReminderAfterScheduleChange);
    _tripCardsController.dispose();
    super.dispose();
  }

  void _validateReminderAfterScheduleChange() {
    unawaited(NotificationService().cancelReminderIfInvalid());
  }

  @override
  Widget build(BuildContext context) {
    final lightScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E7D32),
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF81C784),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Forett Shuttle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: lightScheme,
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        colorScheme: darkScheme,
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      themeMode: _darkModeEnabled ? ThemeMode.dark : ThemeMode.light,
      home: MainAppScreen(
        darkModeEnabled: _darkModeEnabled,
        onDarkModeChanged: (enabled) {
          setState(() => _darkModeEnabled = enabled);
          unawaited(_settings.setDarkModeEnabled(enabled));
        },
        direction: _currentDirection,
        onDirectionChanged: _setDirection,
        tripCardsController: _tripCardsController,
      ),
    );
  }

  void _setDirection(Direction direction) {
    if (_currentDirection == direction) return;
    setState(() => _currentDirection = direction);
    unawaited(_settings.setDirection(direction));
  }
}

class MainAppScreen extends StatefulWidget {
  const MainAppScreen({
    super.key,
    required this.darkModeEnabled,
    required this.onDarkModeChanged,
    required this.direction,
    required this.onDirectionChanged,
    required this.tripCardsController,
  });

  final bool darkModeEnabled;
  final ValueChanged<bool> onDarkModeChanged;
  final Direction direction;
  final ValueChanged<Direction> onDirectionChanged;
  final TripCardsController tripCardsController;

  @override
  State<MainAppScreen> createState() => _MainAppScreenState();
}

class _MainAppScreenState extends State<MainAppScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late final AnimationController _tabTransitionController;
  late final Animation<double> _tabFade;
  late final Animation<Offset> _tabSlide;

  @override
  void initState() {
    super.initState();
    _tabTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1,
    );
    final curve = CurvedAnimation(
      parent: _tabTransitionController,
      curve: Curves.easeOutCubic,
    );
    _tabFade = Tween<double>(begin: 0, end: 1).animate(curve);
    _tabSlide = Tween<Offset>(
      begin: const Offset(0, 0.025),
      end: Offset.zero,
    ).animate(curve);
  }

  @override
  void dispose() {
    _tabTransitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: FadeTransition(
        opacity: _tabFade,
        child: SlideTransition(
          position: _tabSlide,
          child: IndexedStack(
            index: _currentIndex,
            children: [
              HomeScreen(
                isActive: _currentIndex == 0,
                direction: widget.direction,
                onDirectionChanged: widget.onDirectionChanged,
                tripCardsController: widget.tripCardsController,
              ),
              ScheduleScreen(
                isActive: _currentIndex == 1,
                direction: widget.direction,
                onDirectionChanged: widget.onDirectionChanged,
              ),
              ProfileScreen(
                darkModeEnabled: widget.darkModeEnabled,
                onDarkModeChanged: widget.onDarkModeChanged,
                tripCardsController: widget.tripCardsController,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          if (index == _currentIndex) return;
          setState(() {
            _currentIndex = index;
          });
          if (MediaQuery.disableAnimationsOf(context)) {
            _tabTransitionController.value = 1;
          } else {
            _tabTransitionController.forward(from: 0);
          }
        },
        backgroundColor: theme.colorScheme.surface,
        indicatorColor: theme.colorScheme.primaryContainer,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: theme.colorScheme.primary),
            label: 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(
              Icons.calendar_today,
              color: theme.colorScheme.primary,
            ),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: theme.colorScheme.primary),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
