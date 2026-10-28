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

  /// Rolling adaptive baseline of open-eye EAR for the primary user.
  double _leftOpenEarBaseline = 0.22;
  double _rightOpenEarBaseline = 0.22;

  @override
  bool get isReady => _detector?.isReady ?? false;

  @override
  Future<void> initialize() async {
    if (isReady) return;
    try {
      final detector = fd.FaceDetector();
      await detector.initialize(
        model: fd.FaceDetectionModel.frontCamera,
        meshPoolSize: 1,
        enableTracking: true,
        minScore: 0.35,
        minFacePresenceConfidence: 0.25,
      );
      _detector = detector;
    } catch (_) {
      // Fallback to backCamera model if frontCamera fails to initialize on any target
      try {
        final fallbackDetector = fd.FaceDetector();
        await fallbackDetector.initialize(
          model: fd.FaceDetectionModel.backCamera,
          meshPoolSize: 1,
          enableTracking: true,
          minScore: 0.35,
          minFacePresenceConfidence: 0.25,
        );
        _detector = fallbackDetector;
      } catch (e) {
        throw AppError.fromCode(
          AppErrorCode.faceDetectorInitializationFailed,
          cause: e,
        );
      }
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

        final leftProb = _computeAdaptiveEyeOpenProbability(
          blendshapeProb: face.leftEyeOpenProbability,
          eyeContour: face.getContour(fd.FaceContourType.leftEye),
          isLeftEye: true,
        );
        final rightProb = _computeAdaptiveEyeOpenProbability(
          blendshapeProb: face.rightEyeOpenProbability,
          eyeContour: face.getContour(fd.FaceContourType.rightEye),
          isLeftEye: false,
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

  /// Combines MediaPipe Blendshape probability with an adaptive Eye Aspect Ratio (EAR)
  /// relative to the user's own open-eye baseline so webcam angle never locks the detector.
  double? _computeAdaptiveEyeOpenProbability({
    required double? blendshapeProb,
    required List<fd.Point>? eyeContour,
    required bool isLeftEye,
  }) {
    final rawEar = _computeRawEar(eyeContour);
    double? earProb;

    if (rawEar != null) {
      double baseline = isLeftEye
          ? _leftOpenEarBaseline
          : _rightOpenEarBaseline;

      // Adapt baseline smoothly toward upper observed EAR values (normal open eye)
      if (rawEar > baseline) {
        baseline = baseline * 0.75 + rawEar * 0.25;
      } else if (rawEar > baseline * 0.80) {
        baseline = baseline * 0.96 + rawEar * 0.04;
      }
      baseline = baseline.clamp(0.14, 0.36);

      if (isLeftEye) {
        _leftOpenEarBaseline = baseline;
      } else {
        _rightOpenEarBaseline = baseline;
      }

      // Ratio of current EAR to the user's open-eye baseline:
      // >= 0.84 -> fully open (~0.85-1.0); <= 0.66 -> closed (~0.10-0.25)
      final ratio = (rawEar / baseline).clamp(0.0, 1.2);
      earProb = ((ratio - 0.62) / (0.88 - 0.62)).clamp(0.0, 1.0);
    }

    if (blendshapeProb != null && earProb != null) {
      // If either blendshape or adaptive EAR strongly signals a blink closure, surface it
      if (blendshapeProb <= 0.42 || earProb <= 0.28) {
        return math.min(blendshapeProb, earProb);
      }
      // Otherwise weight blendshape higher so normal open eyes stay comfortably >= 0.70
      return (blendshapeProb * 0.65 + earProb * 0.35).clamp(0.0, 1.0);
    }

    return blendshapeProb ?? earProb;
  }

  double? _computeRawEar(List<fd.Point>? contour) {
    if (contour == null || contour.length < 16) return null;

    double dist(fd.Point a, fd.Point b) {
      final dx = a.x - b.x;
      final dy = a.y - b.y;
      return math.sqrt(dx * dx + dy * dy);
    }

    final horiz = dist(contour[0], contour[8]);
    if (horiz <= 1e-4) return null;

    final v1 = dist(contour[3], contour[13]);
    final v2 = dist(contour[4], contour[12]);
    final v3 = dist(contour[5], contour[11]);
    final vert = (v1 + v2 + v3) / 3.0;

    return vert / horiz;
  }

  @override
  void resetTracking() {
    _leftOpenEarBaseline = 0.22;
    _rightOpenEarBaseline = 0.22;
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
