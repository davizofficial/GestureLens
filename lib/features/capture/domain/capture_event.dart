enum CaptureTriggerSource {
  manual('Manual Capture'),
  autoBlink('Auto Blink Capture'),
  videoRecording('Video Recording');

  final String label;
  const CaptureTriggerSource(this.label);
}

enum CaptureMediaType {
  photo,
  video,
}

class SavedPhotoItem {
  final String id;
  final String filePath;
  final String filename;
  final DateTime capturedAt;
  final CaptureTriggerSource triggerSource;
  final String filterName;
  final String portalModeLabel;
  final CaptureMediaType mediaType;
  final int? durationSeconds;
  final String? thumbnailPath;

  const SavedPhotoItem({
    required this.id,
    required this.filePath,
    required this.filename,
    required this.capturedAt,
    required this.triggerSource,
    required this.filterName,
    required this.portalModeLabel,
    this.mediaType = CaptureMediaType.photo,
    this.durationSeconds,
    this.thumbnailPath,
  });

  bool get isVideo => mediaType == CaptureMediaType.video;
}

class PhotoFilenameGenerator {
  static int _sequenceCounter = 0;

  static String generate(
    DateTime timestamp, {
    CaptureTriggerSource source = CaptureTriggerSource.manual,
  }) {
    _sequenceCounter = (_sequenceCounter + 1) % 10000;
    final y = timestamp.year.toString().padLeft(4, '0');
    final m = timestamp.month.toString().padLeft(2, '0');
    final d = timestamp.day.toString().padLeft(2, '0');
    final hh = timestamp.hour.toString().padLeft(2, '0');
    final mm = timestamp.minute.toString().padLeft(2, '0');
    final ss = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    final seq = _sequenceCounter.toString().padLeft(4, '0');
    final tag = source == CaptureTriggerSource.autoBlink ? 'BLINK' : 'MANUAL';
    return 'GestureLens_$y$m${d}_$hh$mm${ss}_${ms}_${tag}_$seq.png';
  }

  static String generateVideo(
    DateTime timestamp, {
    int durationSeconds = 0,
    String extension = 'mp4',
  }) {
    _sequenceCounter = (_sequenceCounter + 1) % 10000;
    final y = timestamp.year.toString().padLeft(4, '0');
    final m = timestamp.month.toString().padLeft(2, '0');
    final d = timestamp.day.toString().padLeft(2, '0');
    final hh = timestamp.hour.toString().padLeft(2, '0');
    final mm = timestamp.minute.toString().padLeft(2, '0');
    final ss = timestamp.second.toString().padLeft(2, '0');
    final seq = _sequenceCounter.toString().padLeft(4, '0');
    final dur = durationSeconds.clamp(1, 3600);
    return 'GestureLens_$y$m${d}_$hh$mm${ss}_VIDEO_${dur}s_$seq.$extension';
  }
}
