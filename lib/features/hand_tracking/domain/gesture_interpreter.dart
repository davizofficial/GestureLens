import '../../../core/constants/app_constants.dart';
import 'hand_landmarks.dart';

enum GestureActionType {
  none,
  nextFilter,
  togglePortalMode,
  trackingLost,
}

enum PortalTrackingState {
  none,
  oneHandPortal,
  twoHandPortal,
}

class GestureInterpretationResult {
  final List<DetectedHand> activeHands;
  final PortalTrackingState portalState;
  final GestureActionType triggeredAction;
  final bool isGracePeriodActive;

  const GestureInterpretationResult({
    required this.activeHands,
    required this.portalState,
    required this.triggeredAction,
    this.isGracePeriodActive = false,
  });
}

class GestureInterpreter {
  final double minConfidence;
  final double pinchTriggerRatio;
  final double pinchReleaseRatio;
  final Duration gestureCooldown;
  final Duration trackingGracePeriod;
  final int requiredStableFistFrames;

  List<DetectedHand> _lastValidHands = const [];
  PortalTrackingState _lastPortalState = PortalTrackingState.none;
  DateTime? _lastValidHandTimestamp;

  bool _isPinchLatched = false;
  DateTime? _lastPinchTriggeredAt;

  int _consecutiveBothFistFrames = 0;
  bool _isBothFistsLatched = false;
  DateTime? _lastModeToggleTriggeredAt;

  GestureInterpreter({
    this.minConfidence = AppConstants.minHandConfidence,
    this.pinchTriggerRatio = AppConstants.pinchNormalizedDistanceThreshold,
    this.pinchReleaseRatio = AppConstants.pinchReleaseNormalizedThreshold,
    this.gestureCooldown = AppConstants.gestureCooldownDuration,
    this.trackingGracePeriod = AppConstants.trackingGracePeriod,
    this.requiredStableFistFrames = 2,
  });

  GestureInterpretationResult interpret(
    List<DetectedHand> detectedHands,
    DateTime now,
  ) {
    final eligibleHands = detectedHands
        .where((h) => h.confidence >= minConfidence && h.hasCompleteLandmarks)
        .take(2)
        .toList();

    if (eligibleHands.isEmpty) {
      return _handleMissingHands(now);
    }

    _lastValidHands = eligibleHands;
    _lastValidHandTimestamp = now;

    var action = GestureActionType.none;

    // Evaluate Gesture D: Both fists to toggle 2D/3D mode
    if (eligibleHands.length == 2 &&
        isClosedFist(eligibleHands[0]) &&
        isClosedFist(eligibleHands[1])) {
      _consecutiveBothFistFrames++;
      if (_consecutiveBothFistFrames >= requiredStableFistFrames &&
          !_isBothFistsLatched &&
          _isCooldownElapsed(_lastModeToggleTriggeredAt, now)) {
        _isBothFistsLatched = true;
        _lastModeToggleTriggeredAt = now;
        action = GestureActionType.togglePortalMode;
      }
    } else {
      _consecutiveBothFistFrames = 0;
      _isBothFistsLatched = false;
    }

    // Evaluate Gesture C: Pinch (thumb tip and little finger tip) to advance filter
    final anyPinching = eligibleHands.any(_isThumbPinkyPinchActive);
    final allReleased = eligibleHands.every(_isThumbPinkyPinchReleased);

    if (anyPinching) {
      if (!_isPinchLatched &&
          action == GestureActionType.none &&
          _isCooldownElapsed(_lastPinchTriggeredAt, now)) {
        _isPinchLatched = true;
        _lastPinchTriggeredAt = now;
        action = GestureActionType.nextFilter;
      }
    } else if (allReleased) {
      _isPinchLatched = false;
    }

    // Determine Portal State (Gesture A: Two-hand portal, Gesture B: One-hand portal)
    final portalState = _determinePortalState(eligibleHands);
    _lastPortalState = portalState;

    return GestureInterpretationResult(
      activeHands: eligibleHands,
      portalState: portalState,
      triggeredAction: action,
      isGracePeriodActive: false,
    );
  }

  GestureInterpretationResult _handleMissingHands(DateTime now) {
    _consecutiveBothFistFrames = 0;
    _isBothFistsLatched = false;
    _isPinchLatched = false;

    if (_lastValidHands.isNotEmpty && _lastValidHandTimestamp != null) {
      final elapsed = now.difference(_lastValidHandTimestamp!);
      if (elapsed <= trackingGracePeriod) {
        return GestureInterpretationResult(
          activeHands: _lastValidHands,
          portalState: _lastPortalState,
          triggeredAction: GestureActionType.none,
          isGracePeriodActive: true,
        );
      }
      _lastValidHands = const [];
      _lastPortalState = PortalTrackingState.none;
      _lastValidHandTimestamp = null;
      return const GestureInterpretationResult(
        activeHands: [],
        portalState: PortalTrackingState.none,
        triggeredAction: GestureActionType.trackingLost,
        isGracePeriodActive: false,
      );
    }

    return const GestureInterpretationResult(
      activeHands: [],
      portalState: PortalTrackingState.none,
      triggeredAction: GestureActionType.none,
      isGracePeriodActive: false,
    );
  }

  PortalTrackingState _determinePortalState(List<DetectedHand> hands) {
    if (hands.length >= 2) {
      // If both hands are in closed fists, still allow portal or keep state coherent,
      // unless the hands are collapsed on the exact same point.
      final wristDist = hands[0][DetectedHand.wrist]
          .distanceTo(hands[1][DetectedHand.wrist]);
      if (wristDist > 0.04) {
        return PortalTrackingState.twoHandPortal;
      }
    }
    if (hands.length == 1) {
      final hand = hands.first;
      if (!isClosedFist(hand) && _hasSufficientOneHandSpread(hand)) {
        return PortalTrackingState.oneHandPortal;
      }
    }
    return PortalTrackingState.none;
  }

  bool _isThumbPinkyPinchActive(DetectedHand hand) {
    final thumbTip = hand[DetectedHand.thumbTip];
    final pinkyTip = hand[DetectedHand.pinkyTip];
    final normalizedDist = thumbTip.distanceTo(pinkyTip) / hand.palmScale;
    // Ensure index or middle finger is extended so a closed fist isn't mistaken for a thumb-pinky pinch
    final indexExtended = _isFingerExtended(
      hand,
      DetectedHand.indexTip,
      DetectedHand.indexPip,
    );
    final middleExtended = _isFingerExtended(
      hand,
      DetectedHand.middleTip,
      DetectedHand.middlePip,
    );
    return normalizedDist <= pinchTriggerRatio && (indexExtended || middleExtended);
  }

  bool _isThumbPinkyPinchReleased(DetectedHand hand) {
    final thumbTip = hand[DetectedHand.thumbTip];
    final pinkyTip = hand[DetectedHand.pinkyTip];
    final normalizedDist = thumbTip.distanceTo(pinkyTip) / hand.palmScale;
    return normalizedDist >= pinchReleaseRatio;
  }

  bool isClosedFist(DetectedHand hand) {
    if (!hand.hasCompleteLandmarks) return false;
    final indexCurled = !_isFingerExtended(
      hand,
      DetectedHand.indexTip,
      DetectedHand.indexPip,
    );
    final middleCurled = !_isFingerExtended(
      hand,
      DetectedHand.middleTip,
      DetectedHand.middlePip,
    );
    final ringCurled = !_isFingerExtended(
      hand,
      DetectedHand.ringTip,
      DetectedHand.ringPip,
    );
    final pinkyCurled = !_isFingerExtended(
      hand,
      DetectedHand.pinkyTip,
      DetectedHand.pinkyPip,
    );
    return indexCurled && middleCurled && ringCurled && pinkyCurled;
  }

  bool _isFingerExtended(DetectedHand hand, int tipIndex, int pipIndex) {
    final wrist = hand[DetectedHand.wrist];
    final tipDist = wrist.distanceTo(hand[tipIndex]);
    final pipDist = wrist.distanceTo(hand[pipIndex]);
    return tipDist > pipDist * 1.08;
  }

  bool _hasSufficientOneHandSpread(DetectedHand hand) {
    final thumbTip = hand[DetectedHand.thumbTip];
    final indexTip = hand[DetectedHand.indexTip];
    final pinkyTip = hand[DetectedHand.pinkyTip];
    final spread1 = thumbTip.distanceTo(indexTip) / hand.palmScale;
    final spread2 = indexTip.distanceTo(pinkyTip) / hand.palmScale;
    return spread1 > 0.35 && spread2 > 0.25;
  }

  bool _isCooldownElapsed(DateTime? lastTriggered, DateTime now) {
    if (lastTriggered == null) return true;
    return now.difference(lastTriggered) >= gestureCooldown;
  }

  void reset() {
    _lastValidHands = const [];
    _lastPortalState = PortalTrackingState.none;
    _lastValidHandTimestamp = null;
    _isPinchLatched = false;
    _lastPinchTriggeredAt = null;
    _consecutiveBothFistFrames = 0;
    _isBothFistsLatched = false;
    _lastModeToggleTriggeredAt = null;
  }
}
