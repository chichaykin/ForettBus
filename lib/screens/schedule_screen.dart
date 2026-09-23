import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../notifications.dart';
import '../schedule.dart';
import '../schedule_import.dart';
import '../widgets/direction_toggle.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    this.isActive = true,
    this.direction = Direction.forettToBeautyWorld,
    required this.onDirectionChanged,
    this.now = BusSchedule.now,
  });

  final bool isActive;
  final Direction direction;
  final ValueChanged<Direction> onDirectionChanged;
  final DateTime Function() now;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

enum _ScheduleScrollTarget { departure, start, end }

class _ScheduleFocus {
  const _ScheduleFocus.departure(this.time)
    : scrollTarget = _ScheduleScrollTarget.departure;

  const _ScheduleFocus.start()
    : time = null,
      scrollTarget = _ScheduleScrollTarget.start;

  const _ScheduleFocus.end()
    : time = null,
      scrollTarget = _ScheduleScrollTarget.end;

  final String? time;
  final _ScheduleScrollTarget scrollTarget;
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _scrollDuration = Duration(milliseconds: 250);
  static const _blinkDuration = Duration(milliseconds: 900);

  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _departureKeys = {};
  late final AnimationController _blinkController;
  Timer? _minuteTimer;
  String? _highlightedTime;
  int _focusRevision = 0;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: _blinkDuration,
    )..addListener(_handleBlinkFrame);
    WidgetsBinding.instance.addObserver(this);
    BusSchedule.active.addListener(_handleScheduleChanged);
    if (widget.isActive) {
      _scheduleFocus(reveal: true, blink: true);
      _startMinuteTimer();
    }
  }

  @override
  void didUpdateWidget(ScheduleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameActive = !oldWidget.isActive && widget.isActive;
    final directionChanged = oldWidget.direction != widget.direction;

    if (!widget.isActive) {
      _stopMinuteTimer();
      _cancelBlink();
      return;
    }
    if (becameActive || directionChanged) {
      _scheduleFocus(reveal: true, blink: true);
    }
    if (becameActive) _startMinuteTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.isActive) return;
    if (state == AppLifecycleState.resumed) {
      _scheduleFocus();
      _startMinuteTimer();
    } else {
      _stopMinuteTimer();
    }
  }

  @override
  void dispose() {
    _focusRevision++;
    _stopMinuteTimer();
    BusSchedule.active.removeListener(_handleScheduleChanged);
    WidgetsBinding.instance.removeObserver(this);
    _blinkController
      ..removeListener(_handleBlinkFrame)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScheduleChanged() {
    if (!mounted) return;
    setState(() {});
    if (widget.isActive) _scheduleFocus(reveal: true, blink: true);
  }

  void _handleBlinkFrame() {
    if (mounted) setState(() {});
  }

  void _startMinuteTimer() {
    _stopMinuteTimer();
    if (!widget.isActive) return;
    final now = widget.now();
    final nextMinute = now.add(
      Duration(
        minutes: 1,
        seconds: -now.second,
        milliseconds: -now.millisecond,
        microseconds: -now.microsecond,
      ),
    );
    _minuteTimer = Timer(nextMinute.difference(now), () {
      if (!mounted || !widget.isActive) return;
      _scheduleFocus();
      _startMinuteTimer();
    });
  }

  void _stopMinuteTimer() {
    _minuteTimer?.cancel();
    _minuteTimer = null;
  }

  void _cancelBlink() {
    _blinkController
      ..stop()
      ..value = 0;
  }

  _ScheduleFocus _focusForCurrentTime() {
    final times = BusSchedule.getTimesForDirection(widget.direction);
    final now = widget.now();
    if (!BusSchedule.isOperatingDay(now)) return const _ScheduleFocus.start();
    final next = BusSchedule.getNextBus(now, widget.direction);
    if (next == null) return const _ScheduleFocus.end();
    final time =
        '${next.hour.toString().padLeft(2, '0')}:'
        '${next.minute.toString().padLeft(2, '0')}';
    if (!times.contains(time)) return const _ScheduleFocus.end();
    return _ScheduleFocus.departure(time);
  }

  void _scheduleFocus({bool reveal = false, bool blink = false}) {
    if (!widget.isActive) return;
    final focus = _focusForCurrentTime();
    final revision = ++_focusRevision;
    _cancelBlink();
    final nextHighlight = focus.time;
    if (_highlightedTime != nextHighlight) {
      setState(() => _highlightedTime = nextHighlight);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_applyFocus(focus, revision, reveal: reveal, blink: blink));
    });
  }

  Future<void> _applyFocus(
    _ScheduleFocus focus,
    int revision, {
    required bool reveal,
    required bool blink,
  }) async {
    if (!mounted || !widget.isActive || revision != _focusRevision) return;
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    final duration = animationsDisabled ? Duration.zero : _scrollDuration;

    if (reveal && _scrollController.hasClients) {
      switch (focus.scrollTarget) {
        case _ScheduleScrollTarget.departure:
          var rowContext = _departureKeys[focus.time]?.currentContext;
          if (rowContext == null) {
            final items = _displayItems(
              BusSchedule.getTimesForDirection(widget.direction),
              BusSchedule.active.value.breaks,
            );
            final itemIndex = items.indexWhere(
              (item) => item.time == focus.time,
            );
            if (itemIndex >= 0 && items.length > 1) {
              final target =
                  _scrollController.position.maxScrollExtent *
                  itemIndex /
                  (items.length - 1);
              if (duration == Duration.zero) {
                _scrollController.jumpTo(target);
              } else {
                await _scrollController.animateTo(
                  target,
                  duration: duration,
                  curve: Curves.easeOutCubic,
                );
              }
              await WidgetsBinding.instance.endOfFrame;
              if (!mounted || !widget.isActive || revision != _focusRevision) {
                return;
              }
              rowContext = _departureKeys[focus.time]?.currentContext;
            }
          }
          if (rowContext != null && rowContext.mounted) {
            await Scrollable.ensureVisible(
              rowContext,
              alignment: 0.33,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: duration,
              curve: Curves.easeOutCubic,
            );
          }
        case _ScheduleScrollTarget.start:
          if (duration == Duration.zero) {
            _scrollController.jumpTo(0);
          } else {
            await _scrollController.animateTo(
              0,
              duration: duration,
              curve: Curves.easeOutCubic,
            );
          }
        case _ScheduleScrollTarget.end:
          final target = _scrollController.position.maxScrollExtent;
          if (duration == Duration.zero) {
            _scrollController.jumpTo(target);
          } else {
            await _scrollController.animateTo(
              target,
              duration: duration,
              curve: Curves.easeOutCubic,
            );
          }
      }
    }
    if (!mounted || !widget.isActive || revision != _focusRevision || !blink) {
      return;
    }
    if (focus.time != null && !animationsDisabled) {
      _blinkController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final schedule = BusSchedule.active.value;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Full Schedule',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        actions: [
          PopupMenuButton<_Action>(
            onSelected: (action) => _runAction(context, action),
            itemBuilder: (context) => const [
              PopupMenuItem(value: _Action.photo, child: Text('Import photo')),
              PopupMenuItem(value: _Action.csv, child: Text('Import CSV')),
              PopupMenuItem(
                value: _Action.export,
                child: Text('Export CSV sample'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _Action.restore,
                child: Text('Restore original'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: DirectionToggle(
              direction: widget.direction,
              onChanged: widget.onDirectionChanged,
            ),
          ),
          _ImportHeader(
            hasHolidayCalendar: schedule.hasHolidayCalendarFor(widget.now()),
            onPhoto: () => _runAction(context, _Action.photo),
            onCsv: () => _runAction(context, _Action.csv),
          ),
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              children:
                  _displayItems(
                        schedule.timesFor(widget.direction),
                        schedule.breaks,
                      )
                      .map(
                        (item) => item.breakItem == null
                            ? _DepartureTile(
                                key: _departureKeys.putIfAbsent(
                                  item.time!,
                                  () => GlobalKey(),
                                ),
                                time: item.time!,
                                highlighted: _highlightedTime == item.time,
                                blinkStrength: _highlightedTime == item.time
                                    ? _blinkStrength
                                    : 0,
                              )
                            : _BreakTile(item.breakItem!),
                      )
                      .toList(),
            ),
          ),
        ],
      ),
    );
  }

  double get _blinkStrength {
    final blink = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 25),
    ]);
    return blink.evaluate(_blinkController);
  }

  Future<void> _runAction(BuildContext context, _Action action) async {
    switch (action) {
      case _Action.photo:
        await _photo(context);
      case _Action.csv:
        await _csv(context);
      case _Action.export:
        await _export(context);
      case _Action.restore:
        await _restore(context);
    }
  }

  Future<void> _photo(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        imageQuality: 100,
      );
      if (image == null || !context.mounted) return;
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final result = await recognizer.processImage(
          InputImage.fromFilePath(image.path),
        );
        final imported = ScheduleImporter.fromOcrLines(
          result.blocks
              .expand((block) => block.lines)
              .map(
                (line) => OcrLine(
                  text: line.text,
                  centerX: line.boundingBox.center.dx,
                ),
              )
              .toList(),
        );
        if (context.mounted) {
          await _review(context, imported, 'Photo');
        }
      } finally {
        recognizer.close();
      }
    } on ScheduleImportException catch (error) {
      if (context.mounted) {
        _message(context, error.message);
      }
    } on Object {
      if (context.mounted) {
        _message(
          context,
          'Could not read this photo. Try a clearer, front-facing photo.',
        );
      }
    }
  }

  Future<void> _csv(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty || !context.mounted) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        _message(context, 'Could not read the selected CSV file.');
        return;
      }
      await _review(
        context,
        ScheduleImporter.fromCsv(utf8.decode(bytes)),
        'CSV',
      );
    } on ScheduleImportException catch (error) {
      if (context.mounted) {
        _message(context, error.message);
      }
    } on Object {
      if (context.mounted) {
        _message(context, 'Could not import that CSV file.');
      }
    }
  }

  Future<void> _export(BuildContext context) async {
    try {
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save timetable CSV',
        fileName: 'forett-shuttle-schedule.csv',
        bytes: Uint8List.fromList(
          utf8.encode(ScheduleImporter.exportCsv(BusSchedule.active.value)),
        ),
      );
      if (savedPath != null && context.mounted) {
        _message(context, 'CSV sample saved');
      }
    } on Object {
      if (context.mounted) {
        _message(context, 'Could not export the CSV sample.');
      }
    }
  }

  Future<void> _restore(BuildContext context) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore original schedule?'),
        content: const Text(
          'Your imported departures and breaks will be replaced with the original timetable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    await BusSchedule.restoreOriginal();
    await NotificationService().cancelReminderIfInvalid();
    if (context.mounted) _message(context, 'Original schedule restored');
  }

  Future<void> _review(
    BuildContext context,
    ImportedSchedule imported,
    String source,
  ) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => ScheduleImportReviewScreen(
          imported: imported,
          sourceLabel: source,
          previousSchedule: BusSchedule.active.value,
        ),
      ),
    );
    if (saved == true && context.mounted) _message(context, 'Schedule updated');
  }

  void _message(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

enum _Action { photo, csv, export, restore }

class _ImportHeader extends StatelessWidget {
  const _ImportHeader({
    required this.hasHolidayCalendar,
    required this.onPhoto,
    required this.onCsv,
  });

  final bool hasHolidayCalendar;
  final VoidCallback onPhoto;
  final VoidCallback onCsv;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Monday–Saturday · excluding Singapore public holidays'),
          if (!hasHolidayCalendar)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Holiday calendar is unavailable for this year. Reminders are disabled.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: onPhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Import photo'),
              ),
              TextButton.icon(
                onPressed: onCsv,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Import CSV'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _DisplayItem {
  const _DisplayItem.time(this.time) : breakItem = null;
  const _DisplayItem.breakItem(this.breakItem) : time = null;
  final String? time;
  final ScheduleBreak? breakItem;
}

List<_DisplayItem> _displayItems(
  List<String> times,
  List<ScheduleBreak> breaks,
) {
  final result = <_DisplayItem>[];
  final ordered = [...breaks]..sort((a, b) => a.start.compareTo(b.start));
  for (var index = 0; index < times.length; index++) {
    final time = times[index];
    result.add(_DisplayItem.time(time));
    final next = index + 1 == times.length ? null : times[index + 1];
    for (final item in ordered) {
      if (time.compareTo(item.start) < 0 &&
          (next == null || next.compareTo(item.end) >= 0)) {
        result.add(_DisplayItem.breakItem(item));
      }
    }
  }
  return result;
}

class _DepartureTile extends StatelessWidget {
  const _DepartureTile({
    super.key,
    required this.time,
    required this.highlighted,
    required this.blinkStrength,
  });

  final String time;
  final bool highlighted;
  final double blinkStrength;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final calmHighlight = colors.primaryContainer.withValues(alpha: 0.45);
    final backgroundColor = highlighted
        ? Color.lerp(calmHighlight, colors.primaryContainer, blinkStrength)
        : Colors.transparent;

    return Semantics(
      label: highlighted ? 'Next departure at $time' : 'Departure at $time',
      child: AnimatedContainer(
        key: ValueKey('schedule-departure-$time'),
        duration: Duration.zero,
        curve: Curves.linear,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: Icon(Icons.access_time, color: colors.primary),
          title: Text(
            time,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

class _BreakTile extends StatelessWidget {
  const _BreakTile(this.item);
  final ScheduleBreak item;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text('Driver’s break ${item.start} – ${item.end}'),
  );
}

class ScheduleImportReviewScreen extends StatefulWidget {
  const ScheduleImportReviewScreen({
    super.key,
    required this.imported,
    required this.sourceLabel,
    required this.previousSchedule,
  });
  final ImportedSchedule imported;
  final String sourceLabel;
  final ShuttleSchedule previousSchedule;

  @override
  State<ScheduleImportReviewScreen> createState() =>
      _ScheduleImportReviewScreenState();
}

class _ScheduleImportReviewScreenState
    extends State<ScheduleImportReviewScreen> {
  late final List<TextEditingController> _forett;
  late final List<TextEditingController> _beauty;
  late final List<_BreakFields> _breaks;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _forett = widget.imported.forettTimes
        .map((time) => TextEditingController(text: time))
        .toList();
    _beauty = widget.imported.beautyWorldTimes
        .map((time) => TextEditingController(text: time))
        .toList();
    _breaks = widget.imported.breaks
        .map((item) => _BreakFields(item.start, item.end))
        .toList();
  }

  @override
  void dispose() {
    for (final item in [..._forett, ..._beauty]) {
      item.dispose();
    }
    for (final item in _breaks) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Review ${widget.sourceLabel} import')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Nothing changes until you save this review.'),
        const SizedBox(height: 8),
        ...widget.imported.notices.map(
          (notice) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(notice),
          ),
        ),
        Text(
          'Imported ${_forett.length} Forett, ${_beauty.length} Beauty World departures and ${_breaks.length} breaks.',
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
        Text(
          'Current: ${widget.previousSchedule.forettTimes.length} Forett, '
          '${widget.previousSchedule.beautyWorldTimes.length} Beauty World departures and '
          '${widget.previousSchedule.breaks.length} breaks.',
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        _TimeEditor(
          title: 'Forett departures',
          fields: _forett,
          onChanged: () => setState(() {}),
        ),
        _TimeEditor(
          title: 'Beauty World departures',
          fields: _beauty,
          onChanged: () => setState(() {}),
        ),
        _BreakEditor(fields: _breaks, onChanged: () => setState(() {})),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving...' : 'Save schedule'),
        ),
      ],
    ),
  );

  Future<void> _save() async {
    final schedule = ShuttleSchedule(
      forettTimes: _forett.map((item) => item.text.trim()).toList(),
      beautyWorldTimes: _beauty.map((item) => item.text.trim()).toList(),
      breaks: _breaks
          .map(
            (item) => ScheduleBreak(
              start: item.start.text.trim(),
              end: item.end.text.trim(),
            ),
          )
          .toList(),
      holidayDates: BusSchedule.active.value.holidayDates,
      holidayStartYear: BusSchedule.active.value.holidayStartYear,
      holidayEndYear: BusSchedule.active.value.holidayEndYear,
    );
    final errors = schedule.validate();
    if (errors.isNotEmpty) {
      setState(() => _error = errors.first);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await BusSchedule.save(schedule);
      await NotificationService().cancelReminderIfInvalid();
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save the timetable. Please try again.';
        });
      }
    }
  }
}

class _TimeEditor extends StatelessWidget {
  const _TimeEditor({
    required this.title,
    required this.fields,
    required this.onChanged,
  });
  final String title;
  final List<TextEditingController> fields;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => _EditorCard(
    title: title,
    child: Column(
      children: [
        for (var index = 0; index < fields.length; index++)
          Row(
            children: [
              SizedBox(width: 36, child: Text((index + 1).toString())),
              Expanded(
                child: TextFormField(
                  controller: fields[index],
                  decoration: const InputDecoration(hintText: 'HH:mm'),
                ),
              ),
              IconButton(
                tooltip: 'Remove departure',
                onPressed: () {
                  final item = fields.removeAt(index);
                  item.dispose();
                  onChanged();
                },
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              fields.add(TextEditingController());
              onChanged();
            },
            icon: const Icon(Icons.add),
            label: const Text('Add departure'),
          ),
        ),
      ],
    ),
  );
}

class _BreakFields {
  _BreakFields(String startValue, String endValue)
    : start = TextEditingController(text: startValue),
      end = TextEditingController(text: endValue);
  final TextEditingController start;
  final TextEditingController end;
  void dispose() {
    start.dispose();
    end.dispose();
  }
}

class _BreakEditor extends StatelessWidget {
  const _BreakEditor({required this.fields, required this.onChanged});
  final List<_BreakFields> fields;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => _EditorCard(
    title: 'Driver breaks',
    child: Column(
      children: [
        if (fields.isEmpty)
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('No breaks imported.'),
          ),
        for (var index = 0; index < fields.length; index++)
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: fields[index].start,
                  decoration: const InputDecoration(labelText: 'Start'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: fields[index].end,
                  decoration: const InputDecoration(labelText: 'End'),
                ),
              ),
              IconButton(
                tooltip: 'Remove break',
                onPressed: () {
                  final item = fields.removeAt(index);
                  item.dispose();
                  onChanged();
                },
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              fields.add(_BreakFields('', ''));
              onChanged();
            },
            icon: const Icon(Icons.add),
            label: const Text('Add break'),
          ),
        ),
      ],
    ),
  );
}

class _EditorCard extends StatelessWidget {
  const _EditorCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          child,
        ],
      ),
    ),
  );
}
