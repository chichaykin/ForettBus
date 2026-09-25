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
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280);

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: ColoredBox(
        color: colors.surfaceContainerHighest,
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedAlign(
                duration: duration,
                curve: Curves.easeInOutCubic,
                alignment: direction == Direction.forettToBeautyWorld
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  heightFactor: 1,
                  child: DecoratedBox(
                    key: const Key('direction-selection-indicator'),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                _buildOption(
                  context,
                  value: Direction.forettToBeautyWorld,
                  label: multilineLabels
                      ? 'Forett to\nBeauty World'
                      : 'To Beauty World',
                  semanticLabel: 'To Beauty World',
                  duration: duration,
                ),
                _buildOption(
                  context,
                  value: Direction.beautyWorldToForett,
                  label: multilineLabels
                      ? 'Beauty World\nto Forett'
                      : 'To Forett',
                  semanticLabel: 'To Forett',
                  duration: duration,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required Direction value,
    required String label,
    required String semanticLabel,
    required Duration duration,
  }) {
    final colors = Theme.of(context).colorScheme;
    final selected = direction == value;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: semanticLabel,
        onTap: selected ? null : () => onChanged(value),
        child: ExcludeSemantics(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: selected ? null : () => onChanged(value),
              borderRadius: BorderRadius.circular(30),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: multilineLabels ? 13 : 11,
                ),
                child: AnimatedDefaultTextStyle(
                  duration: duration,
                  curve: Curves.easeInOutCubic,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? colors.onPrimaryContainer
                        : colors.onSurface,
                  ),
                  child: Text(label, textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
