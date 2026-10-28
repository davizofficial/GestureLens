import 'dart:math' as math;
import '../../../core/constants/app_constants.dart';

enum BlinkDetectorState {
  /// Waiting for a reliable face and at least [requiredInitialOpenFrames] open-eye frames.
  unarmed,

  /// Face is stable and both eyes have been confirmed open; ready to detect closure.
  armedOpen,

  /// Both eyes have transitioned to the closed state; measuring closure duration.
  eyesClosed,

  /// Cooldown active after a completed blink capture event.
  cooldown,
}

class FaceEyeObservation {
  final int? trackingId;
  final double confidence;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  /// Normalized bounding box [xmin, ymin, xmax, ymax] in [0.0, 1.0].
  final double xmin;
  final double ymin;
  final double xmax;
  final double ymax;

  const FaceEyeObservation({
    this.trackingId,
    required this.confidence,
    required this.leftEyeOpenProbability,
    required this.rightEyeOpenProbability,
    required this.xmin,
    required this.ymin,
    required this.xmax,
    required this.ymax,
  });

  double get width => (xmax - xmin).clamp(0.0, 1.0);
  double get height => (ymax - ymin).clamp(0.0, 1.0);
  double get area => width * height;
  double get centerX => (xmin + xmax) * 0.5;
  double get centerY => (ymin + ymax) * 0.5;

  double get distanceFromFrameCenter {
    final dx = centerX - 0.5;
    final dy = centerY - 0.5;
    return math.sqrt(dx * dx + dy * dy);
  }

  bool get hasReliableEyes =>
      leftEyeOpenProbability != null && rightEyeOpenProbability != null;

  double get averageEyeOpenProbability {
    if (!hasReliableEyes) return 0.0;
    return (leftEyeOpenProbability! + rightEyeOpenProbability!) * 0.5;
  }
}

class BlinkEvaluationResult {
  final BlinkDetectorState state;
  final bool blinkTriggered;
  final FaceEyeObservation? selectedFace;
  final bool hasAmbiguousMultipleFaces;

  const BlinkEvaluationResult({
    required this.state,
    required this.blinkTriggered,
    this.selectedFace,
    this.hasAmbiguousMultipleFaces = false,
  });
}

class BlinkDetector {
  final double openThreshold;
  final double closedThreshold;
  final double minFaceConfidence;
  final double minFaceWidthFraction;
  final int requiredInitialOpenFrames;
  final Duration minClosureDuration;
  final Duration maxClosureDuration;
  final Duration cooldownDuration;

  /// Optional relative drop from the user's open-eye baseline that counts as a blink closure.
  final double relativeDropThreshold;

  /// Optional duration where holding eyes closed (e.g. 1.5s) immediately triggers capture
  /// without waiting for reopening.
  final Duration? triggerOnHoldDuration;

  BlinkDetectorState _state = BlinkDetectorState.unarmed;
  int _consecutiveOpenFrames = 0;
  DateTime? _closedStartedAt;
  DateTime? _cooldownUntil;
  int? _lockedTrackingId;
  double _rollingOpenBaseline = 0.80;

  BlinkDetector({
    this.openThreshold = AppConstants.defaultEyesOpenProbability,
    this.closedThreshold = AppConstants.defaultEyesClosedProbability,
    this.minFaceConfidence = 0.55,
    this.minFaceWidthFraction = 0.10,
    this.requiredInitialOpenFrames = AppConstants.requiredInitialOpenFrames,
    this.minClosureDuration = AppConstants.minBlinkClosureDuration,
    this.maxClosureDuration = AppConstants.maxBlinkClosureDuration,
    this.cooldownDuration = AppConstants.captureCooldownDuration,
    this.relativeDropThreshold = 0.25,
    this.triggerOnHoldDuration,
  });

  BlinkDetectorState get state => _state;
  int get consecutiveOpenFrames => _consecutiveOpenFrames;

  /// Selects a single clearly visible face near the center of the frame.
  /// Returns `(null, true)` if multiple faces are equally plausible (ambiguous).
  (FaceEyeObservation?, bool) selectPrimaryFace(List<FaceEyeObservation> faces) {
    final eligible = faces
        .where((f) =>
            f.confidence >= minFaceConfidence &&
            f.width >= minFaceWidthFraction &&
            f.hasReliableEyes)
        .toList();

    if (eligible.isEmpty) {
      return (null, false);
    }
    if (eligible.length == 1) {
      return (eligible.first, false);
    }

    // Score each face by area weighted by proximity to frame center.
    double scoreFace(FaceEyeObservation f) {
      final centerWeight = (1.0 - f.distanceFromFrameCenter).clamp(0.2, 1.0);
      return f.area * centerWeight;
    }

    eligible.sort((a, b) => scoreFace(b).compareTo(scoreFace(a)));
    final best = eligible[0];
    final second = eligible[1];
    final bestScore = scoreFace(best);
    final secondScore = scoreFace(second);

    // If two faces are nearly identical in prominence (within 15%), treat as ambiguous.
    if (bestScore > 0 && (secondScore / bestScore) >= 0.85) {
      return (null, true);
    }

    return (best, false);
  }

  BlinkEvaluationResult evaluate(
    List<FaceEyeObservation> faces,
    DateTime now,
  ) {
    // Handle cooldown expiration check first
    if (_state == BlinkDetectorState.cooldown) {
      if (_cooldownUntil != null && now.isBefore(_cooldownUntil!)) {
        final (selected, ambiguous) = selectPrimaryFace(faces);
        return BlinkEvaluationResult(
          state: _state,
          blinkTriggered: false,
          selectedFace: selected,
          hasAmbiguousMultipleFaces: ambiguous,
        );
      }
      // Cooldown finished: transition to unarmed and require stable open eyes before re-arming
      _disarm();
    }

    final (selectedFace, isAmbiguous) = selectPrimaryFace(faces);
    if (selectedFace == null || isAmbiguous) {
      _disarm();
      return BlinkEvaluationResult(
        state: _state,
        blinkTriggered: false,
        selectedFace: null,
        hasAmbiguousMultipleFaces: isAmbiguous,
      );
    }

    // If tracking ID changed mid-sequence, disarm and re-evaluate from scratch
    if (_lockedTrackingId != null &&
        selectedFace.trackingId != null &&
        _lockedTrackingId != selectedFace.trackingId) {
      _disarm();
    }
    _lockedTrackingId = selectedFace.trackingId;

    final leftProb = selectedFace.leftEyeOpenProbability!;
    final rightProb = selectedFace.rightEyeOpenProbability!;
    final avgProb = (leftProb + rightProb) * 0.5;

    final isWink =
        ((leftProb <= closedThreshold && rightProb >= openThreshold) ||
            (rightProb <= closedThreshold && leftProb >= openThreshold)) &&
        (leftProb - rightProb).abs() >= 0.48;

    // A deliberate single-eye wink disarms the detector rather than triggering a blink
    if (isWink) {
      _disarm();
      return BlinkEvaluationResult(
        state: _state,
        blinkTriggered: false,
        selectedFace: selectedFace,
      );
    }

    final bothOpen =
        (leftProb >= openThreshold && rightProb >= openThreshold) ||
        (avgProb >= openThreshold &&
            leftProb >= openThreshold - 0.08 &&
            rightProb >= openThreshold - 0.08);

    final relativeDropTriggered =
        _state == BlinkDetectorState.armedOpen &&
        (_rollingOpenBaseline - avgProb) >= relativeDropThreshold &&
        avgProb <= openThreshold;

    final bothClosed =
        (leftProb <= closedThreshold && rightProb <= closedThreshold) ||
        (avgProb <= closedThreshold &&
            leftProb < openThreshold - 0.06 &&
            rightProb < openThreshold - 0.06) ||
        relativeDropTriggered;

    switch (_state) {
      case BlinkDetectorState.unarmed:
        if (bothOpen) {
          _rollingOpenBaseline =
              _rollingOpenBaseline * 0.7 + avgProb * 0.3;
          _consecutiveOpenFrames++;
          if (_consecutiveOpenFrames >= requiredInitialOpenFrames) {
            _state = BlinkDetectorState.armedOpen;
          }
        } else {
          _consecutiveOpenFrames = 0;
        }
        return BlinkEvaluationResult(
          state: _state,
          blinkTriggered: false,
          selectedFace: selectedFace,
        );

      case BlinkDetectorState.armedOpen:
        if (bothClosed) {
          _state = BlinkDetectorState.eyesClosed;
          _closedStartedAt = now;
          return BlinkEvaluationResult(
            state: _state,
            blinkTriggered: false,
            selectedFace: selectedFace,
          );
        }
        if (bothOpen) {
          _rollingOpenBaseline =
              _rollingOpenBaseline * 0.8 + avgProb * 0.2;
          _consecutiveOpenFrames++;
        }
        return BlinkEvaluationResult(
          state: _state,
          blinkTriggered: false,
          selectedFace: selectedFace,
        );

      case BlinkDetectorState.eyesClosed:
        final closureDuration = now.difference(_closedStartedAt!);

        // If configured to trigger directly when held closed for e.g. 1.5s:
        if (triggerOnHoldDuration != null &&
            closureDuration >= triggerOnHoldDuration!) {
          _state = BlinkDetectorState.cooldown;
          _cooldownUntil = now.add(cooldownDuration);
          _consecutiveOpenFrames = 0;
          _closedStartedAt = null;
          return BlinkEvaluationResult(
            state: _state,
            blinkTriggered: true,
            selectedFace: selectedFace,
          );
        }

        if (closureDuration > maxClosureDuration) {
          // Eyes held closed too long -> disarm so sustained closure never triggers capture
          _disarm();
          return BlinkEvaluationResult(
            state: _state,
            blinkTriggered: false,
            selectedFace: selectedFace,
          );
        }

        if (bothOpen) {
          if (closureDuration >= minClosureDuration &&
              closureDuration <= maxClosureDuration) {
            // Completed valid blink! Enter cooldown and require re-arming afterwards
            _state = BlinkDetectorState.cooldown;
            _cooldownUntil = now.add(cooldownDuration);
            _consecutiveOpenFrames = 0;
            _closedStartedAt = null;
            return BlinkEvaluationResult(
              state: _state,
              blinkTriggered: true,
              selectedFace: selectedFace,
            );
          } else {
            // Closure was too brief -> return to armedOpen
            _state = BlinkDetectorState.armedOpen;
            _closedStartedAt = null;
            return BlinkEvaluationResult(
              state: _state,
              blinkTriggered: false,
              selectedFace: selectedFace,
            );
          }
        }

        // Still closed or intermediate while reopening within maxClosureDuration
        return BlinkEvaluationResult(
          state: _state,
          blinkTriggered: false,
          selectedFace: selectedFace,
        );

      case BlinkDetectorState.cooldown:
        return BlinkEvaluationResult(
          state: _state,
          blinkTriggered: false,
          selectedFace: selectedFace,
        );
    }
  }

  void _disarm() {
    _state = BlinkDetectorState.unarmed;
    _consecutiveOpenFrames = 0;
    _closedStartedAt = null;
    _cooldownUntil = null;
    _lockedTrackingId = null;
  }

  void reset() {
    _disarm();
  }
}
