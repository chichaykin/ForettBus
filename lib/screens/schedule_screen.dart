import 'package:flutter/material.dart';

import '../schedule.dart';
import '../widgets/direction_toggle.dart';

class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({
    super.key,
    this.direction = Direction.forettToBeautyWorld,
    required this.onDirectionChanged,
  });

  final Direction direction;
  final ValueChanged<Direction> onDirectionChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final times = BusSchedule.getTimesForDirection(direction);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Full Schedule',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: DirectionToggle(
              direction: direction,
              onChanged: onDirectionChanged,
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              itemCount: times.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final time = times[index];
                final breakText = switch (time) {
                  '09:10' ||
                  '09:17' => "Driver's break 09:30 - 10:00 (30 mins)",
                  '12:40' || '12:47' => "Driver's break 13:00 - 14:30 (1.5 hr)",
                  '16:10' ||
                  '16:17' => "Driver's break 16:30 - 17:00 (30 mins)",
                  _ => null,
                };

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.access_time, color: colors.primary),
                      title: Text(
                        time,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (breakText != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16, top: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.tertiaryContainer,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.free_breakfast,
                              size: 16,
                              color: colors.onTertiaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                breakText,
                                style: TextStyle(
                                  color: colors.onTertiaryContainer,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
