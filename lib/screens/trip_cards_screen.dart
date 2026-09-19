import 'package:flutter/material.dart';

import '../trip_cards.dart';
import '../trip_planning.dart';

class TripCardsScreen extends StatefulWidget {
  const TripCardsScreen({super.key, required this.controller});

  final TripCardsController controller;

  @override
  State<TripCardsScreen> createState() => _TripCardsScreenState();
}

class _TripCardsScreenState extends State<TripCardsScreen> {
  Future<void> _edit([TripCard? card]) async {
    final result = await Navigator.of(context).push<TripCard>(
      MaterialPageRoute(builder: (_) => TripCardEditor(card: card)),
    );
    if (!mounted || result == null) return;
    if (card == null) {
      await widget.controller.add(result);
    } else {
      await widget.controller.update(result);
    }
  }

  Future<void> _delete(TripCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${card.title}?'),
        content: const Text('This removes the saved trip from Home.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed == true) await widget.controller.remove(card.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cards')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add card'),
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final cards = widget.controller.cards;
          if (cards.isEmpty) {
            return const Center(child: Text('No saved trips yet.'));
          }
          return ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: cards.length,
            // Flutter 3.41 introduces onReorderItem, but onReorder is still
            // supported by the minimum SDK used by this project.
            // ignore: deprecated_member_use
            onReorder: (oldIndex, newIndex) =>
                widget.controller.reorder(oldIndex, newIndex),
            itemBuilder: (context, index) {
              final card = cards[index];
              return Card(
                key: ValueKey(card.id),
                child: ListTile(
                  leading: const Icon(Icons.route_outlined),
                  title: Text(card.title),
                  subtitle: Text(
                    '${card.originName} → ${card.destinationName}\n${card.selectedLabel}',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _edit(card),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit',
                      ),
                      IconButton(
                        onPressed: () => _delete(card),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete',
                      ),
                      const Icon(Icons.drag_handle),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class TripCardEditor extends StatefulWidget {
  const TripCardEditor({super.key, this.card});

  final TripCard? card;

  @override
  State<TripCardEditor> createState() => _TripCardEditorState();
}

class _TripCardEditorState extends State<TripCardEditor> {
  late final TextEditingController _title;
  late final TextEditingController _origin;
  late final TextEditingController _destination;
  late _PlanDraft _toDestination;
  late _PlanDraft _toOrigin;
  bool _isSearching = false;
  PlaceSearchResult? _selectedOrigin;
  PlaceSearchResult? _selectedDestination;
  String? _searchNotice;
  final TripPlannerClient _planner = TripPlannerClient();

  @override
  void initState() {
    super.initState();
    final card = widget.card;
    _title = TextEditingController(text: card?.title ?? '');
    _origin = TextEditingController(text: card?.originName ?? 'Forett');
    _destination = TextEditingController(text: card?.destinationName ?? '');
    _toDestination = _PlanDraft.fromPlan(card?.toDestination);
    _toOrigin = _PlanDraft.fromPlan(card?.toOrigin);
  }

  @override
  void dispose() {
    _title.dispose();
    _origin.dispose();
    _destination.dispose();
    _toDestination.dispose();
    _toOrigin.dispose();
    _planner.close();
    super.dispose();
  }

  Future<void> _searchDestination() async {
    final query = _destination.text.trim();
    if (query.length < 2) return;
    setState(() {
      _isSearching = true;
      _searchNotice = null;
    });
    try {
      final results = await _planner.searchPlaces(query);
      if (!mounted) return;
      if (results.isEmpty) {
        setState(
          () => _searchNotice =
              'No places found. You can still enter a destination name.',
        );
        return;
      }
      final selected = await showModalBottomSheet<PlaceSearchResult>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final result in results.take(5))
                ListTile(
                  title: Text(result.name),
                  subtitle: Text(result.address),
                  onTap: () => Navigator.pop(context, result),
                ),
            ],
          ),
        ),
      );
      if (!mounted || selected == null) return;
      setState(() {
        _destination.text = selected.name;
        _selectedDestination = selected;
      });
    } on TripPlanningException catch (error) {
      if (mounted) setState(() => _searchNotice = error.message);
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _findRoutes() async {
    if (_isSearching) return;
    setState(() {
      _isSearching = true;
      _searchNotice = null;
    });
    try {
      final origin =
          _selectedOrigin ??
          (await _planner.searchPlaces(_origin.text.trim())).firstOrNull;
      if (!mounted) return;
      final destination =
          _selectedDestination ??
          (await _planner.searchPlaces(_destination.text.trim())).firstOrNull;
      if (!mounted) return;
      if (origin == null || destination == null) {
        setState(
          () => _searchNotice =
              'Search for an address or postal code for both locations.',
        );
        return;
      }
      _selectedOrigin = origin;
      _selectedDestination = destination;
      final outbound = await _planner.planTrips(
        startLatitude: origin.latitude,
        startLongitude: origin.longitude,
        endLatitude: destination.latitude,
        endLongitude: destination.longitude,
      );
      if (!mounted) return;
      if (outbound.isEmpty) {
        setState(() => _searchNotice = 'No bus route found for this trip.');
        return;
      }
      final selectedOutbound = await _pickPlan(
        outbound,
        'Choose route to destination',
      );
      if (!mounted || selectedOutbound == null) return;
      final inbound = await _planner.planTrips(
        startLatitude: destination.latitude,
        startLongitude: destination.longitude,
        endLatitude: origin.latitude,
        endLongitude: origin.longitude,
      );
      if (!mounted) return;
      if (inbound.isEmpty) {
        setState(
          () => _searchNotice =
              'No return route found. Your saved route has not changed.',
        );
        return;
      }
      final selectedInbound = await _pickPlan(inbound, 'Choose return route');
      if (!mounted || selectedInbound == null) return;
      setState(() {
        _toDestination.dispose();
        _toOrigin.dispose();
        _toDestination = _PlanDraft.fromPlan(selectedOutbound);
        _toOrigin = _PlanDraft.fromPlan(selectedInbound);
        _destination.text = destination.address;
      });
    } on TripPlanningException catch (error) {
      if (mounted) setState(() => _searchNotice = error.message);
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _pickStop(_LegDraft leg, bool from) async {
    final controller = from ? leg.fromController : leg.toController;
    List<TransitStop> results;
    try {
      results = await _planner.searchStops(controller.text.trim());
    } on TripPlanningException catch (error) {
      if (mounted) setState(() => _searchNotice = error.message);
      return;
    }
    if (!mounted) return;
    if (results.isEmpty) {
      setState(
        () => _searchNotice = 'No stops found. Try a five-digit stop code.',
      );
      return;
    }
    final selected = await showModalBottomSheet<TransitStop>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final stop in results.take(10))
              ListTile(
                title: Text(stop.name),
                subtitle: Text(stop.code),
                onTap: () => Navigator.pop(context, stop),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (from) {
      leg.fromController.text = selected.name;
      leg.fromCodeController.text = selected.code;
    } else {
      leg.toController.text = selected.name;
      leg.toCodeController.text = selected.code;
    }
    leg.durationMinutes = null;
    _toDestination.durationMinutes = null;
    _toOrigin.durationMinutes = null;
    setState(() {});
  }

  Future<TripPlan?> _pickPlan(List<TripPlan> plans, String title) {
    return showModalBottomSheet<TripPlan>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final plan in plans.take(3))
              ListTile(
                leading: const Icon(Icons.route_outlined),
                title: Text(
                  '${plan.durationMinutes == null ? '' : '~${plan.durationMinutes} min · '}${plan.transferCount} transfer${plan.transferCount == 1 ? '' : 's'}',
                ),
                subtitle: Text(
                  plan.legs
                      .map(
                        (leg) => leg.isBus
                            ? 'Bus ${leg.services.join(', ')}'
                            : 'Walk',
                      )
                      .join(' · '),
                ),
                onTap: () => Navigator.pop(context, plan),
              ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final title = _title.text.trim();
    final origin = _origin.text.trim();
    final destination = _destination.text.trim();
    if (title.isEmpty ||
        origin.isEmpty ||
        destination.isEmpty ||
        !_toDestination.isValid ||
        !_toOrigin.isValid) {
      setState(
        () => _searchNotice =
            'Enter a name, both locations, five-digit bus stop codes and bus numbers in each direction.',
      );
      return;
    }
    final existing = widget.card;
    Navigator.pop(
      context,
      TripCard(
        id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        originName: origin,
        destinationName: destination,
        toDestination: _toDestination.toPlan(),
        toOrigin: _toOrigin.toPlan(),
        selectedDirection:
            existing?.selectedDirection ?? TripDirection.toDestination,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.card == null ? 'Add card' : 'Edit card'),
        actions: [
          TextButton(
            onPressed: _isSearching ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Card name',
              hintText: 'Grab HQ',
              helperText: 'Shown on Home and the direction switch',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _origin,
            onChanged: (_) => _selectedOrigin = null,
            decoration: const InputDecoration(
              labelText: 'Origin',
              hintText: 'Forett',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _destination,
            onChanged: (_) => _selectedDestination = null,
            decoration: InputDecoration(
              labelText: 'Destination address',
              hintText: '3 Media Close or 138498',
              suffixIcon: IconButton(
                onPressed: _isSearching ? null : _searchDestination,
                icon: _isSearching
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
              ),
            ),
          ),
          if (_searchNotice != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _searchNotice!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isSearching ? null : _findRoutes,
            icon: const Icon(Icons.alt_route),
            label: Text(
              _isSearching
                  ? 'Searching…'
                  : widget.card == null
                  ? 'Find bus routes'
                  : 'Find alternatives',
            ),
          ),
          const SizedBox(height: 24),
          _PlanEditor(
            title: 'To destination',
            draft: _toDestination,
            onChanged: () => setState(() {}),
            onPickStop: _pickStop,
          ),
          const SizedBox(height: 18),
          _PlanEditor(
            title: 'To origin',
            draft: _toOrigin,
            onChanged: () => setState(() {}),
            onPickStop: _pickStop,
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _isSearching ? null : _save,
            icon: const Icon(Icons.check),
            label: const Text('Save card'),
          ),
        ],
      ),
    );
  }
}

class _PlanDraft {
  _PlanDraft(this.legs, {this.durationMinutes});

  int? durationMinutes;

  final List<_LegDraft> legs;

  factory _PlanDraft.fromPlan(TripPlan? plan) {
    if (plan == null) return _PlanDraft([_LegDraft()]);
    return _PlanDraft(
      plan.legs.map(_LegDraft.fromLeg).toList(),
      durationMinutes: plan.durationMinutes,
    );
  }

  bool get isValid =>
      legs.any((leg) => leg.type == TripLegType.bus) &&
      legs.every((leg) => leg.isValid);

  TripPlan toPlan() => TripPlan(
    legs: List.unmodifiable(legs.map((leg) => leg.toLeg())),
    durationMinutes: durationMinutes,
  );

  void dispose() {
    for (final leg in legs) {
      leg.dispose();
    }
  }
}

class _LegDraft {
  _LegDraft({
    this.type = TripLegType.bus,
    String? from,
    String? fromName,
    String? to,
    String? toName,
    String? services,
    this.durationMinutes,
  }) : fromController = TextEditingController(text: fromName ?? from ?? ''),
       fromCodeController = TextEditingController(text: from ?? ''),
       toController = TextEditingController(text: toName ?? to ?? ''),
       toCodeController = TextEditingController(text: to ?? ''),
       servicesController = TextEditingController(text: services ?? '');

  TripLegType type;
  int? durationMinutes;
  final TextEditingController fromController;
  final TextEditingController fromCodeController;
  final TextEditingController toController;
  final TextEditingController toCodeController;
  final TextEditingController servicesController;

  factory _LegDraft.fromLeg(TripLeg leg) => _LegDraft(
    type: leg.type,
    from: leg.from.code,
    fromName: leg.from.name,
    to: leg.to.code,
    toName: leg.to.name,
    services: leg.services.join(', '),
    durationMinutes: leg.durationMinutes,
  );

  bool get isValid =>
      fromController.text.trim().isNotEmpty &&
      toController.text.trim().isNotEmpty &&
      (type == TripLegType.walk ||
          (RegExp(r'^\d{5}$').hasMatch(fromCodeController.text.trim()) &&
              RegExp(r'^\d{5}$').hasMatch(toCodeController.text.trim()) &&
              servicesController.text
                  .split(',')
                  .every((s) => normalizeBusService(s) != null)));

  TripLeg toLeg() => TripLeg(
    type: type,
    durationMinutes: durationMinutes,
    from: TransitStop(
      code: fromCodeController.text.trim().isEmpty
          ? fromController.text.trim()
          : fromCodeController.text.trim(),
      name: fromController.text.trim(),
    ),
    to: TransitStop(
      code: toCodeController.text.trim().isEmpty
          ? toController.text.trim()
          : toCodeController.text.trim(),
      name: toController.text.trim(),
    ),
    services: servicesController.text
        .split(',')
        .map(normalizeBusService)
        .whereType<String>()
        .toSet()
        .toList(),
  );

  void dispose() {
    fromController.dispose();
    fromCodeController.dispose();
    toController.dispose();
    toCodeController.dispose();
    servicesController.dispose();
  }
}

class _PlanEditor extends StatelessWidget {
  const _PlanEditor({
    required this.title,
    required this.draft,
    required this.onChanged,
    required this.onPickStop,
  });

  final String title;
  final _PlanDraft draft;
  final VoidCallback onChanged;
  final Future<void> Function(_LegDraft leg, bool from) onPickStop;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                draft.legs.add(_LegDraft());
                draft.durationMinutes = null;
                onChanged();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add leg'),
            ),
          ],
        ),
        for (var index = 0; index < draft.legs.length; index++)
          _LegEditor(
            key: ObjectKey(draft.legs[index]),
            index: index,
            leg: draft.legs[index],
            canRemove: draft.legs.length > 1,
            onRemove: () {
              draft.durationMinutes = null;
              final leg = draft.legs.removeAt(index);
              leg.dispose();
              onChanged();
            },
            onChanged: () {
              draft.durationMinutes = null;
              draft.legs[index].durationMinutes = null;
              onChanged();
            },
            onPickStop: onPickStop,
          ),
      ],
    );
  }
}

class _LegEditor extends StatelessWidget {
  const _LegEditor({
    super.key,
    required this.index,
    required this.leg,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
    required this.onPickStop,
  });

  final int index;
  final _LegDraft leg;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final Future<void> Function(_LegDraft leg, bool from) onPickStop;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'Leg ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                DropdownButton<TripLegType>(
                  value: leg.type,
                  items: const [
                    DropdownMenuItem(
                      value: TripLegType.bus,
                      child: Text('Bus'),
                    ),
                    DropdownMenuItem(
                      value: TripLegType.walk,
                      child: Text('Walk'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      leg.type = value;
                      onChanged();
                    }
                  },
                ),
                if (canRemove)
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: leg.fromController,
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(
                      labelText: 'From stop / place',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => onPickStop(leg, true),
                  icon: const Icon(Icons.search),
                  tooltip: 'Search stop',
                ),
              ],
            ),
            TextField(
              controller: leg.fromCodeController,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Boarding stop code',
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: leg.toController,
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(
                      labelText: 'To stop / place',
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => onPickStop(leg, false),
                  icon: const Icon(Icons.search),
                  tooltip: 'Search stop',
                ),
              ],
            ),
            TextField(
              controller: leg.toCodeController,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Alighting stop code',
              ),
            ),
            if (leg.type == TripLegType.bus)
              TextField(
                controller: leg.servicesController,
                onChanged: (_) => onChanged(),
                decoration: const InputDecoration(
                  labelText: 'Bus numbers',
                  hintText: '41, 77, 963',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
