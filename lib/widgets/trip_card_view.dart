import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../bus_arrivals.dart';
import '../schedule.dart';
import '../trip_cards.dart';
import '../trip_forecast.dart';

class TripCardView extends StatelessWidget {
  const TripCardView({
    super.key,
    required this.card,
    required this.stops,
    required this.now,
    required this.onDirectionChanged,
    required this.onEdit,
    this.isLoading = false,
    this.compact = false,
    this.collapsed = false,
    this.stacked = false,
    this.onToggleExpanded,
  });

  final TripCard card;
  final Map<String, StopArrivalsSnapshot> stops;
  final DateTime now;
  final ValueChanged<TripDirection> onDirectionChanged;
  final VoidCallback onEdit;
  final bool isLoading;
  final bool compact;
  final bool collapsed;
  final bool stacked;
  final VoidCallback? onToggleExpanded;

  String _time(DateTime value) => DateFormat(
    'HH:mm',
  ).format(tz.TZDateTime.from(value, BusSchedule.singaporeLocation));

  String _countdown(TripBoarding boarding) {
    if (!boarding.arrival.monitored) {
      return _time(boarding.arrival.estimatedArrival);
    }
    final seconds = boarding.arrival.estimatedArrival.difference(now).inSeconds;
    return seconds < 60 ? 'Arriving' : 'in ${(seconds / 60).ceil()} min';
  }

  String _place(String name) {
    if (name.toLowerCase() == 'origin') {
      return card.selectedDirection == TripDirection.toOrigin
          ? card.destinationLabel
          : card.originLabel;
    }
    if (name.toLowerCase() == 'destination') {
      return card.selectedDirection == TripDirection.toOrigin
          ? card.originLabel
          : card.destinationLabel;
    }
    return displayPlaceName(name);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final plan = card.selectedPlan;
    final forecast = TripForecast.calculate(plan, stops, now);
    final firstIndex = plan.legs.indexWhere((leg) => leg.isBus);
    final first = firstIndex < 0 ? null : plan.legs[firstIndex];
    final boarding = forecast.boardings[firstIndex];
    final firstSnapshot = first == null ? null : stops[first.from.code];
    final stale = firstSnapshot?.isStale(now) ?? false;
    final busLegs = plan.legs.where((leg) => leg.isBus).toList();
    final walking = plan.legs.take(firstIndex < 0 ? 0 : firstIndex).toList();
    final approachKnown = walking.every((leg) => leg.durationMinutes != null);
    final walkMinutes = walking.fold(
      0,
      (sum, leg) => sum + (leg.durationMinutes ?? 0),
    );
    final collapsedRoute = [
      card.selectedLabel,
      if (busLegs.isNotEmpty)
        'Bus ${busLegs.map((leg) => leg.services.join(' / ')).join(' → ')}',
    ].join(' · ');
    final collapsedStop = [
      if (first != null) 'Board at ${_place(first.from.name)}',
      if (boarding != null) ...[
        _countdown(boarding),
        boarding.arrival.monitored ? 'Live' : 'Scheduled',
      ] else if (stale)
        'Update needed',
    ].join(' · ');

    return Card(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerHighest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: stacked
            ? BorderSide(color: colors.outlineVariant)
            : BorderSide.none,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 16,
          (compact ? 4 : 16) + (stacked ? 8 : 0),
          compact ? 12 : 16,
          compact ? 8 : 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.route_outlined, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: onToggleExpanded,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        card.title,
                        style:
                            (compact
                                    ? Theme.of(context).textTheme.titleMedium
                                    : Theme.of(context).textTheme.titleLarge)
                                ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onEdit,
                  tooltip: 'Edit ${card.title}',
                  icon: const Icon(Icons.edit_outlined),
                ),
                if (onToggleExpanded != null)
                  Semantics(
                    expanded: !collapsed,
                    child: IconButton(
                      onPressed: onToggleExpanded,
                      tooltip:
                          '${collapsed ? 'Show' : 'Hide'} ${card.title} trip',
                      icon: Icon(
                        collapsed ? Icons.expand_more : Icons.expand_less,
                      ),
                    ),
                  ),
              ],
            ),
            if (collapsed)
              InkWell(
                onTap: onToggleExpanded,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(collapsedRoute),
                      if (collapsedStop.isNotEmpty)
                        Text(
                          collapsedStop,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ),
            if (!collapsed) ...[
              const SizedBox(height: 4),
              SegmentedButton<TripDirection>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: TripDirection.toDestination,
                    label: Text('To ${card.destinationLabel}'),
                  ),
                  ButtonSegment(
                    value: TripDirection.toOrigin,
                    label: Text('To ${card.originLabel}'),
                  ),
                ],
                selected: {card.selectedDirection},
                onSelectionChanged: (values) =>
                    onDirectionChanged(values.single),
                style: compact
                    ? const ButtonStyle(
                        minimumSize: WidgetStatePropertyAll(Size(0, 44)),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 8),
                        ),
                      )
                    : null,
              ),
              SizedBox(height: compact ? 8 : 16),
              if (first != null) ...[
                if (!compact)
                  Text(
                    boarding?.connectionChecked == true
                        ? 'Next bus for your trip'
                        : 'Next bus at the stop',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                if (!compact) const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Bus ${boarding?.service ?? first.services.join(' / ')}',
                      style:
                          (compact
                                  ? Theme.of(context).textTheme.titleMedium
                                  : Theme.of(context).textTheme.titleLarge)
                              ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      boarding != null
                          ? _countdown(boarding)
                          : isLoading
                          ? 'Checking…'
                          : stale
                          ? 'Update needed'
                          : 'No prediction',
                      style:
                          (compact
                                  ? Theme.of(context).textTheme.titleMedium
                                  : Theme.of(context).textTheme.titleLarge)
                              ?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                  ],
                ),
                if (boarding != null)
                  Text(
                    '${boarding.arrival.monitored ? 'Live · ${_time(boarding.arrival.estimatedArrival)}' : 'Scheduled'} at boarding stop',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                SizedBox(height: compact ? 4 : 6),
                Text(
                  '${walking.isEmpty
                      ? 'Board at'
                      : approachKnown
                      ? 'Walk $walkMinutes min to'
                      : 'Walk to'} ${_place(first.from.name)}',
                ),
                if (!approachKnown)
                  Text(
                    'Walk time unavailable · allow time to reach the stop',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (boarding == null && !isLoading)
                  Text(
                    stale
                        ? 'Arrival data is over a minute old.'
                        : 'Try again shortly. Your route is saved.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
              SizedBox(height: compact ? 8 : 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < busLegs.length; i++) ...[
                    if (i > 0)
                      Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        busLegs[i].services.join(' / '),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                  Text(
                    plan.transferCount == 0
                        ? 'Direct'
                        : '${plan.transferCount} transfer${plan.transferCount == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (compact &&
                      forecast.arrivalAtDestination != null &&
                      first != null)
                    Text(
                      'Estimated arrival ${_time(forecast.arrivalAtDestination!)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                ],
              ),
              if (!compact &&
                  forecast.arrivalAtDestination != null &&
                  first != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Estimated arrival ${_time(forecast.arrivalAtDestination!)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              SizedBox(height: compact ? 0 : 8),
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: ValueKey('${card.id}-${card.selectedDirection.name}'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  minTileHeight: compact ? 44 : null,
                  title: const Text('Route details'),
                  children: [
                    for (var index = 0; index < plan.legs.length; index++)
                      _leg(
                        context,
                        plan.legs[index],
                        forecast.boardings[index],
                        transfer:
                            plan.legs[index].isBus &&
                            plan.legs.take(index).any((leg) => leg.isBus),
                      ),
                    if (forecast.arrivalAtDestination == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Destination arrival unavailable until all travel times and connections can be estimated.',
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

  Widget _leg(
    BuildContext context,
    TripLeg leg,
    TripBoarding? boarding, {
    required bool transfer,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            leg.isBus ? Icons.directions_bus_outlined : Icons.directions_walk,
            color: colors.primary,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  leg.isBus
                      ? '${transfer ? 'Change to bus' : 'Bus'} ${leg.services.join(' / ')}'
                      : 'Walk${leg.durationMinutes == null ? '' : ' · ${leg.durationMinutes} min'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text('${_place(leg.from.name)} → ${_place(leg.to.name)}'),
                if (leg.isBus)
                  Text(
                    '${leg.from.code} → ${leg.to.code}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                if (boarding != null)
                  Text(
                    '${boarding.connectionChecked ? 'Board' : 'At stop'} ${_time(boarding.arrival.estimatedArrival)} · ${boarding.arrival.monitored ? 'Live' : 'Scheduled'}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colors.primary),
                  ),
                if (leg.isBus && boarding == null)
                  Text(
                    'No current prediction',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
