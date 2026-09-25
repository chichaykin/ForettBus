import 'schedule_import.dart';
import 'schedule_photo_source.dart';
import 'schedule_photo_import_stub.dart'
    if (dart.library.io) 'schedule_photo_import_native.dart'
    as implementation;

export 'schedule_photo_source.dart';

bool get schedulePhotoImportSupported => implementation.isSupported;

Future<ImportedSchedule?> importSchedulePhoto(SchedulePhotoSource source) =>
    implementation.importSchedulePhoto(source);
