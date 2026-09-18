import 'dart:async';

import 'package:flutter/material.dart';
import 'notifications.dart';
import 'schedule.dart';
import 'screens/home_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/profile_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShuttleBusApp());
  unawaited(_initializeNotifications());
}

Future<void> _initializeNotifications() async {
  try {
    await NotificationService().init();
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
  const ShuttleBusApp({super.key});

  @override
  State<ShuttleBusApp> createState() => _ShuttleBusAppState();
}

class _ShuttleBusAppState extends State<ShuttleBusApp> {
  bool _darkModeEnabled = false;

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
        },
      ),
    );
  }
}

class MainAppScreen extends StatefulWidget {
  const MainAppScreen({
    super.key,
    required this.darkModeEnabled,
    required this.onDarkModeChanged,
  });

  final bool darkModeEnabled;
  final ValueChanged<bool> onDarkModeChanged;

  @override
  State<MainAppScreen> createState() => _MainAppScreenState();
}

class _MainAppScreenState extends State<MainAppScreen> {
  int _currentIndex = 0;
  Direction _currentDirection = Direction.forettToBeautyWorld;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(
            isActive: _currentIndex == 0,
            direction: _currentDirection,
            onDirectionChanged: _setDirection,
          ),
          ScheduleScreen(
            direction: _currentDirection,
            onDirectionChanged: _setDirection,
          ),
          ProfileScreen(
            darkModeEnabled: widget.darkModeEnabled,
            onDarkModeChanged: widget.onDarkModeChanged,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
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

  void _setDirection(Direction direction) {
    if (_currentDirection == direction) return;
    setState(() => _currentDirection = direction);
  }
}
