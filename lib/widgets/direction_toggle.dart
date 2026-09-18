import 'package:flutter/material.dart';

import '../schedule.dart';

class DirectionToggle extends StatelessWidget {
  const DirectionToggle({
    super.key,
    required this.direction,
    required this.onChanged,
    this.multilineLabels = false,
  });

  final Direction direction;
  final ValueChanged<Direction> onChanged;
  final bool multilineLabels;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SegmentedButton<Direction>(
      segments: [
        ButtonSegment(
          value: Direction.forettToBeautyWorld,
          label: Text(
            multilineLabels ? 'Forett to\nBeauty World' : 'To Beauty World',
            textAlign: TextAlign.center,
          ),
        ),
        ButtonSegment(
          value: Direction.beautyWorldToForett,
          label: Text(
            multilineLabels ? 'Beauty World\nto Forett' : 'To Forett',
            textAlign: TextAlign.center,
          ),
        ),
      ],
      selected: {direction},
      onSelectionChanged: (selection) {
        final selected = selection.first;
        if (selected != direction) onChanged(selected);
      },
      showSelectedIcon: false,
      expandedInsets: EdgeInsets.zero,
      style: ButtonStyle(
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: multilineLabels ? 13 : 11),
        ),
        side: const WidgetStatePropertyAll(BorderSide.none),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? colors.primaryContainer
              : colors.surfaceContainerHighest;
        }),
        foregroundColor: WidgetStatePropertyAll(colors.onSurface),
      ),
    );
  }
}
