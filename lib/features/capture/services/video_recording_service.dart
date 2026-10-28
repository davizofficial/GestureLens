import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class RecordedVideoArtifact {
  final String videoFilePath;
  final Uint8List? thumbnailPngBytes;
  final int durationSeconds;

  const RecordedVideoArtifact({
    required this.videoFilePath,
    required this.thumbnailPngBytes,
    required this.durationSeconds,
  });
}

class VideoRecordingService {
  final List<img.Image> _recordedFrames = [];
  DateTime? _recordingStartedAt;
  DateTime? _lastFrameAddedAt;
  bool _isRecording = false;
  bool _isEncoding = false;

  bool get isRecording => _isRecording;
  bool get isEncoding => _isEncoding;
  int get frameCount => _recordedFrames.length;

  int get elapsedSeconds {
    if (!_isRecording || _recordingStartedAt == null) return 0;
    return DateTime.now().difference(_recordingStartedAt!).inSeconds;
  }

  void startRecording(DateTime now) {
    _recordedFrames.clear();
    _recordingStartedAt = now;
    _lastFrameAddedAt = null;
    _isRecording = true;
  }

  bool shouldSampleNextFrame(DateTime now) {
    if (!_isRecording || _isEncoding) return false;
    // Cap buffer at 300 frames (~30 seconds at 10 FPS) to keep memory bounded
    if (_recordedFrames.length >= 300) return false;
    if (_lastFrameAddedAt == null) return true;
    return now.difference(_lastFrameAddedAt!).inMilliseconds >= 100;
  }

  void addProcessedFrame(img.Image frame, DateTime now) {
    if (!_isRecording || _isEncoding) return;
    _lastFrameAddedAt = now;
    // Ensure even dimensions for H.264 yuv420p compatibility
    final targetW = (frame.width > 480 ? 480 : frame.width) & ~1;
    final targetH =
        ((frame.height * targetW / frame.width).round()).clamp(2, 1080) & ~1;
    final resized = (frame.width == targetW && frame.height == targetH)
        ? frame.clone()
        : img.copyResize(frame, width: targetW, height: targetH);
    _recordedFrames.add(resized);
  }

  Future<RecordedVideoArtifact?> stopAndEncodeRecording(DateTime now) async {
    if (!_isRecording) return null;
    _isRecording = false;
    _isEncoding = true;

    final startedAt = _recordingStartedAt ?? now;
    final durationSeconds =
        now.difference(startedAt).inSeconds.clamp(1, 3600);

    try {
      if (_recordedFrames.isEmpty) {
        // Create a single fallback frame if stopped immediately
        final fallback = img.Image(width: 480, height: 270);
        img.fill(fallback, color: img.ColorRgb8(18, 24, 38));
        _recordedFrames.add(fallback);
      }

      final firstFrame = _recordedFrames.first;
      final thumbnailBytes = Uint8List.fromList(img.encodePng(firstFrame));

      final tempDir = await getTemporaryDirectory();
      final sessionDir = Directory(
        '${tempDir.path}/gesturelens_rec_${now.millisecondsSinceEpoch}',
      );
      await sessionDir.create(recursive: true);

      // Try encoding standard H.264 MP4 via ffmpeg first (Linux / macOS / Windows)
      final mp4Path = '${sessionDir.path}/output.mp4';
      final mp4Succeeded = await _tryEncodeMp4WithFfmpeg(
        sessionDir: sessionDir,
        frames: _recordedFrames,
        durationSeconds: durationSeconds,
        outputPath: mp4Path,
      );

      if (mp4Succeeded && await File(mp4Path).exists()) {
        // Also write animated preview at <mp4Path>.gif or use thumbnail for gallery
        return RecordedVideoArtifact(
          videoFilePath: mp4Path,
          thumbnailPngBytes: thumbnailBytes,
          durationSeconds: durationSeconds,
        );
      }

      // Universal pure-Dart fallback: encode multi-frame animated GIF
      final gifPath = '${sessionDir.path}/output.gif';
      final gifBytes = _encodeAnimatedGif(_recordedFrames, durationSeconds);
      await File(gifPath).writeAsBytes(gifBytes, flush: true);

      return RecordedVideoArtifact(
        videoFilePath: gifPath,
        thumbnailPngBytes: thumbnailBytes,
        durationSeconds: durationSeconds,
      );
    } finally {
      _recordedFrames.clear();
      _recordingStartedAt = null;
      _lastFrameAddedAt = null;
      _isEncoding = false;
    }
  }

  Future<bool> _tryEncodeMp4WithFfmpeg({
    required Directory sessionDir,
    required List<img.Image> frames,
    required int durationSeconds,
    required String outputPath,
  }) async {
    if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
      return false;
    }
    try {
      for (var i = 0; i < frames.length; i++) {
        final name = i.toString().padLeft(4, '0');
        final jpgBytes = img.encodeJpg(frames[i], quality: 88);
        await File('${sessionDir.path}/frame_$name.jpg').writeAsBytes(jpgBytes);
      }

      final fps = (frames.length / durationSeconds).clamp(4.0, 24.0);
      final result = await Process.run('ffmpeg', [
        '-y',
        '-framerate',
        fps.toStringAsFixed(2),
        '-i',
        '${sessionDir.path}/frame_%04d.jpg',
        '-c:v',
        'libx264',
        '-preset',
        'ultrafast',
        '-pix_fmt',
        'yuv420p',
        outputPath,
      ]);

      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Uint8List _encodeAnimatedGif(List<img.Image> frames, int durationSeconds) {
    final frameDelayCs =
        ((durationSeconds * 100) / frames.length).round().clamp(6, 25);
    final first = frames.first.clone()..frameDuration = frameDelayCs;
    for (var i = 1; i < frames.length; i++) {
      final f = frames[i].clone()..frameDuration = frameDelayCs;
      first.addFrame(f);
    }
    return Uint8List.fromList(img.encodeGif(first));
  }
}
