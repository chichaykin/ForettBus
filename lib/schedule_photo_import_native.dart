import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'schedule_import.dart';
import 'schedule_photo_source.dart';

const bool isSupported = true;

Future<ImportedSchedule?> importSchedulePhoto(
  SchedulePhotoSource source,
) async {
  final image = await ImagePicker().pickImage(
    source: source == SchedulePhotoSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    imageQuality: 100,
  );
  if (image == null) return null;
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(
      InputImage.fromFilePath(image.path),
    );
    return ScheduleImporter.fromOcrLines(
      result.blocks
          .expand((block) => block.lines)
          .map(
            (line) =>
                OcrLine(text: line.text, centerX: line.boundingBox.center.dx),
          )
          .toList(),
    );
  } finally {
    recognizer.close();
  }
}
