import 'dart:math' as math;
import 'package:face_detection_tflite/face_detection_tflite.dart' as fd;
import 'package:hand_detection/hand_detection.dart' show CameraFrame;
import '../../../core/errors/app_error.dart';
import '../domain/blink_detector.dart';

abstract class FaceTrackingGateway {
  bool get isReady;
  Future<void> initialize();
  Future<List<FaceEyeObservation>> detectFacesFromFrame(
    CameraFrame frame, {
    required bool mirrorHorizontally,
  });
  void resetTracking();
  Future<void> dispose();
}

class FaceTrackingService implements FaceTrackingGateway {
  fd.FaceDetector? _detector;

  @override
  bool get isReady => _detector?.isReady ?? false;

  @override
  Future<void> initialize() async {
    if (isReady) return;
    try {
      final detector = fd.FaceDetector();
      // Use backCamera/general model with lower presence threshold so faces are detected
      // reliably at both desktop webcam distance (50-90cm) and mobile selfie distance.
      await detector.initialize(
        model: fd.FaceDetectionModel.backCamera,
        meshPoolSize: 1,
        enableTracking: true,
        minScore: 0.45,
        minFacePresenceConfidence: 0.35,
      );
      _detector = detector;
    } catch (e) {
      throw AppError.fromCode(
        AppErrorCode.faceDetectorInitializationFailed,
        cause: e,
      );
    }
  }

  @override
  Future<List<FaceEyeObservation>> detectFacesFromFrame(
    CameraFrame frame, {
    required bool mirrorHorizontally,
  }) async {
    final detector = _detector;
    if (detector == null || !detector.isReady) {
      return const [];
    }

    try {
      final faces = await detector.detectFacesFromCameraFrame(
        frame,
        mode: fd.FaceDetectionMode.full,
        maxDim: 480,
      );
      if (faces.isEmpty) return const [];

      final observations = <FaceEyeObservation>[];
      for (final face in faces) {
        final rect = face.detectionData.boundingBox;
        final rawXmin = rect.xmin.clamp(0.0, 1.0);
        final rawXmax = rect.xmax.clamp(0.0, 1.0);
        final xmin = mirrorHorizontally ? (1.0 - rawXmax) : rawXmin;
        final xmax = mirrorHorizontally ? (1.0 - rawXmin) : rawXmax;
        final ymin = rect.ymin.clamp(0.0, 1.0);
        final ymax = rect.ymax.clamp(0.0, 1.0);

        final leftProb = _computeCombinedEyeOpenProbability(
          blendshapeProb: face.leftEyeOpenProbability,
          eyeContour: face.getContour(fd.FaceContourType.leftEye),
        );
        final rightProb = _computeCombinedEyeOpenProbability(
          blendshapeProb: face.rightEyeOpenProbability,
          eyeContour: face.getContour(fd.FaceContourType.rightEye),
        );

        observations.add(
          FaceEyeObservation(
            trackingId: face.trackingId,
            confidence: face.score,
            leftEyeOpenProbability: leftProb,
            rightEyeOpenProbability: rightProb,
            xmin: xmin,
            ymin: ymin,
            xmax: xmax,
            ymax: ymax,
          ),
        );
      }
      return observations;
    } catch (e) {
      throw AppError.fromCode(
        AppErrorCode.modelInferenceFailed,
        cause: e,
        customDetail: 'Face inference error',
      );
    }
  }

  /// Combines MediaPipe Blendshape eye-open probability with geometric Eye Aspect Ratio (EAR)
  /// from the 16-point eye contour mesh so fast or partial webcam blinks are captured reliably.
  double? _computeCombinedEyeOpenProbability({
    required double? blendshapeProb,
    required List<fd.Point>? eyeContour,
  }) {
    final earProb = _computeEarOpenProbability(eyeContour);
    if (blendshapeProb != null && earProb != null) {
      // Take the lower value when closing so either blendshape or eyelid geometry can trigger closure,
      // and average when open.
      final minProb = math.min(blendshapeProb, earProb);
      if (minProb <= 0.32) {
        return minProb;
      }
      return (blendshapeProb * 0.5 + earProb * 0.5).clamp(0.0, 1.0);
    }
    return blendshapeProb ?? earProb;
  }

  double? _computeEarOpenProbability(List<fd.Point>? contour) {
    if (contour == null || contour.length < 16) return null;

    double dist(fd.Point a, fd.Point b) {
      final dx = a.x - b.x;
      final dy = a.y - b.y;
      return math.sqrt(dx * dx + dy * dy);
    }

    // Horizontal eye width between outer corner (0) and inner corner (8)
    final horiz = dist(contour[0], contour[8]);
    if (horiz <= 1e-4) return null;

    // Three vertical eyelid distances across the center of the eye
    final v1 = dist(contour[3], contour[13]);
    final v2 = dist(contour[4], contour[12]);
    final v3 = dist(contour[5], contour[11]);
    final vert = (v1 + v2 + v3) / 3.0;

    final ear = vert / horiz;
    // Typical open EAR is ~0.24-0.34; closed EAR is ~0.08-0.17.
    // Normalize [0.15 .. 0.24] -> [0.0 .. 1.0]
    return ((ear - 0.155) / (0.245 - 0.155)).clamp(0.0, 1.0);
  }

  @override
  void resetTracking() {
    _detector?.resetTracking();
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
