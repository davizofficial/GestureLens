import 'package:hand_detection/hand_detection.dart' as hd;
import '../../../core/errors/app_error.dart';
import '../domain/hand_landmarks.dart';

abstract class HandTrackingGateway {
  bool get isReady;
  Future<void> initialize();
  Future<List<DetectedHand>> detectHandsFromFrame(
    hd.CameraFrame frame, {
    required bool mirrorHorizontally,
    required DateTime timestamp,
  });
  Future<void> resetTracking();
  Future<void> dispose();
}

class HandTrackingService implements HandTrackingGateway {
  hd.HandDetector? _detector;

  @override
  bool get isReady => _detector?.isReady ?? false;

  @override
  Future<void> initialize() async {
    if (isReady) return;
    try {
      final detector = hd.HandDetector();
      await detector.initialize(
        mode: hd.HandMode.boxesAndLandmarks,
        landmarkModel: hd.HandLandmarkModel.full,
        maxDetections: 2,
        detectorConf: 0.5,
        minLandmarkScore: 0.5,
        enableTracking: true,
        enableGestures: false,
      );
      _detector = detector;
    } catch (e) {
      throw AppError.fromCode(
        AppErrorCode.handDetectorInitializationFailed,
        cause: e,
      );
    }
  }

  @override
  Future<List<DetectedHand>> detectHandsFromFrame(
    hd.CameraFrame frame, {
    required bool mirrorHorizontally,
    required DateTime timestamp,
  }) async {
    final detector = _detector;
    if (detector == null || !detector.isReady) {
      return const [];
    }

    try {
      final rawHands = await detector.detectFromCameraFrame(
        frame,
        maxDim: 640,
      );
      if (rawHands.isEmpty) return const [];

      final mapped = <DetectedHand>[];
      for (final hand in rawHands.take(2)) {
        if (!hand.hasLandmarks || hand.landmarks.length < 21) continue;
        final imgW = hand.imageWidth > 0 ? hand.imageWidth.toDouble() : 1.0;
        final imgH = hand.imageHeight > 0 ? hand.imageHeight.toDouble() : 1.0;

        final points = <HandLandmarkPoint>[];
        for (int i = 0; i < hand.landmarks.length; i++) {
          final lm = hand.landmarks[i];
          final rawNormX = (lm.x / imgW).clamp(0.0, 1.0);
          final normX = mirrorHorizontally ? (1.0 - rawNormX) : rawNormX;
          final normY = (lm.y / imgH).clamp(0.0, 1.0);
          points.add(
            HandLandmarkPoint(
              index: i,
              x: normX,
              y: normY,
              z: lm.z,
              visibility: lm.visibility,
            ),
          );
        }

        final handedness = switch (hand.handedness) {
          hd.Handedness.left =>
            mirrorHorizontally ? Handedness.right : Handedness.left,
          hd.Handedness.right =>
            mirrorHorizontally ? Handedness.left : Handedness.right,
          null => Handedness.unknown,
        };

        mapped.add(
          DetectedHand(
            landmarks: points,
            handedness: handedness,
            confidence: hand.score,
            timestamp: timestamp,
          ),
        );
      }
      return mapped;
    } catch (e) {
      throw AppError.fromCode(
        AppErrorCode.modelInferenceFailed,
        cause: e,
        customDetail: 'Hand inference error',
      );
    }
  }

  @override
  Future<void> resetTracking() async {
    final detector = _detector;
    if (detector != null && detector.isReady) {
      await detector.resetTracking();
    }
  }

  @override
  Future<void> dispose() async {
    final detector = _detector;
    _detector = null;
    if (detector != null) {
      await detector.dispose();
    }
  }
}
