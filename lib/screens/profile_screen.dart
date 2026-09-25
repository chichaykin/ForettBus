import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../notifications.dart';
import '../trip_cards.dart';
import 'trip_cards_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.darkModeEnabled,
    required this.onDarkModeChanged,
    required this.tripCardsController,
  });

  final bool darkModeEnabled;
  final ValueChanged<bool> onDarkModeChanged;
  final TripCardsController tripCardsController;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _managementEmail = 'mo@forettcondo.sg';
  static const _securityPhone = '60285615';

  bool _notificationsEnabled = false;
  bool _isUpdatingNotifications = false;

  @override
  void initState() {
    super.initState();
    NotificationService().activeReminder.addListener(_handleReminderChanged);
    NotificationService().state.addListener(_handleNotificationStateChanged);
    unawaited(_restoreNotificationState());
  }

  void _handleReminderChanged() {
    if (!mounted) return;

    setState(() {});
  }

  void _handleNotificationStateChanged() {
    if (!mounted) return;
    final subscribed = NotificationService().state.value.subscribed;
    if (_notificationsEnabled == subscribed) return;
    setState(() => _notificationsEnabled = subscribed);
  }

  Future<void> _restoreNotificationState() async {
    try {
      final reminder = await NotificationService().pendingBusReminder();
      if (!mounted) return;
      final subscribed = NotificationService().state.value.subscribed;
      if (reminder != null || subscribed) {
        setState(() => _notificationsEnabled = true);
      }
    } catch (_) {
      // The profile screen remains usable when the platform cannot query alarms.
    }
  }

  Future<void> _setNotificationsEnabled(bool enabled) async {
    if (_isUpdatingNotifications) return;
    setState(() => _isUpdatingNotifications = true);

    try {
      if (enabled) {
        final granted = await NotificationService().requestPermission();
        if (!mounted) return;
        if (!granted) {
          _showMessage('Notification and alarm permissions are required');
          return;
        }
      } else {
        await NotificationService().disableNotifications();
      }

      if (!mounted) return;
      setState(() => _notificationsEnabled = enabled);
      _showMessage(
        enabled ? 'Notifications enabled' : 'Notifications disabled',
      );
    } catch (_) {
      if (mounted) {
        _showMessage('Could not update notification preferences');
      }
    } finally {
      if (mounted) setState(() => _isUpdatingNotifications = false);
    }
  }

  @override
  void dispose() {
    NotificationService().activeReminder.removeListener(_handleReminderChanged);
    NotificationService().state.removeListener(_handleNotificationStateChanged);
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showContactDialog({
    required String title,
    required String label,
    required String value,
    required IconData icon,
    required Uri actionUri,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: Theme.of(dialogContext).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(title)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(dialogContext).textTheme.labelLarge),
            const SizedBox(height: 4),
            SelectableText(
              value,
              style: Theme.of(dialogContext).textTheme.titleMedium,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final launched = await launchUrl(actionUri);
              if (!dialogContext.mounted) return;
              if (launched) Navigator.of(dialogContext).pop();
            },
            icon: Icon(
              actionUri.scheme == 'mailto'
                  ? Icons.email_outlined
                  : Icons.call_outlined,
            ),
            label: Text(actionUri.scheme == 'mailto' ? 'Send' : 'Call'),
          ),
          FilledButton.tonalIcon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
              if (mounted) _showMessage('$label copied');
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'Forett Shuttle',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.directions_bus),
      children: const [Text('Reliable shuttle timings for Forett residents.')],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    TripCardsScreen(controller: widget.tripCardsController),
              ),
            ),
            icon: const Icon(Icons.view_list_outlined),
            label: const Text('Cards'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: CircleAvatar(
              radius: 50,
              backgroundColor: colors.primaryContainer,
              child: Icon(Icons.person, size: 50, color: colors.primary),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Resident',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 32),
          const _SectionHeading(title: 'Settings'),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Notification Preferences'),
            subtitle: Text(_notificationSubtitle()),
            value: _notificationsEnabled,
            onChanged: _isUpdatingNotifications
                ? null
                : _setNotificationsEnabled,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Dark Mode'),
            subtitle: Text(
              widget.darkModeEnabled
                  ? 'Dark theme enabled'
                  : 'Light theme enabled',
            ),
            value: widget.darkModeEnabled,
            onChanged: widget.onDarkModeChanged,
          ),
          const SizedBox(height: 24),
          const _SectionHeading(title: 'Support'),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.email_outlined),
            title: const Text('Management Office'),
            subtitle: const Text(_managementEmail),
            onTap: () => _showContactDialog(
              title: 'Management Office',
              label: 'Email',
              value: _managementEmail,
              icon: Icons.email_outlined,
              actionUri: Uri(scheme: 'mailto', path: _managementEmail),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.security_outlined),
            title: const Text('Forett Security'),
            subtitle: const Text(_securityPhone),
            onTap: () => _showContactDialog(
              title: 'Forett Security',
              label: 'Phone',
              value: _securityPhone,
              icon: Icons.security_outlined,
              actionUri: Uri(scheme: 'tel', path: _securityPhone),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.report_problem_outlined),
            title: const Text('Report Lost Item'),
            subtitle: const Text('Contact Forett Security'),
            onTap: () => _showContactDialog(
              title: 'Report Lost Item',
              label: 'Forett Security',
              value: _securityPhone,
              icon: Icons.report_problem_outlined,
              actionUri: Uri(scheme: 'tel', path: _securityPhone),
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: const Text('About App'),
            subtitle: const Text('Version 1.0.0'),
            onTap: _showAboutDialog,
          ),
        ],
      ),
    );
  }

  String _notificationSubtitle() {
    final service = NotificationService();
    final state = service.state.value;
    final reminder = service.activeReminder.value;
    switch (state.readiness) {
      case NotificationReadiness.unsupported:
        return 'Notifications are not supported in this browser';
      case NotificationReadiness.installRequired:
        return 'Add Forett Shuttle to the Home Screen first';
      case NotificationReadiness.permissionDenied:
        return 'Permission is blocked in system settings';
      case NotificationReadiness.unknown:
        return 'Bus reminder notifications disabled';
      case NotificationReadiness.ready:
        if (reminder != null) {
          final hour = reminder.busTime.hour.toString().padLeft(2, '0');
          final minute = reminder.busTime.minute.toString().padLeft(2, '0');
          return 'Reminder set for $hour:$minute';
        }
        return state.subscribed
            ? 'Bus reminder notifications enabled'
            : 'Bus reminder notifications disabled';
    }
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
