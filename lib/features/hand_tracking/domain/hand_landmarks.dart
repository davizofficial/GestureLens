import 'dart:math' as math;

enum Handedness {
  left,
  right,
  unknown,
}

class HandLandmarkPoint {
  final int index;
  /// Normalized x coordinate in [0.0, 1.0] within the oriented/mirrored image space.
  final double x;
  /// Normalized y coordinate in [0.0, 1.0] within the oriented/mirrored image space.
  final double y;
  /// Relative depth z coordinate.
  final double z;
  final double visibility;

  const HandLandmarkPoint({
    required this.index,
    required this.x,
    required this.y,
    this.z = 0.0,
    this.visibility = 1.0,
  });

  double distanceTo(HandLandmarkPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

class DetectedHand {
  static const int expectedLandmarkCount = 21;

  // Standard 21 MediaPipe hand landmark indices
  static const int wrist = 0;
  static const int thumbCmc = 1;
  static const int thumbMcp = 2;
  static const int thumbIp = 3;
  static const int thumbTip = 4;
  static const int indexMcp = 5;
  static const int indexPip = 6;
  static const int indexDip = 7;
  static const int indexTip = 8;
  static const int middleMcp = 9;
  static const int middlePip = 10;
  static const int middleDip = 11;
  static const int middleTip = 12;
  static const int ringMcp = 13;
  static const int ringPip = 14;
  static const int ringDip = 15;
  static const int ringTip = 16;
  static const int pinkyMcp = 17;
  static const int pinkyPip = 18;
  static const int pinkyDip = 19;
  static const int pinkyTip = 20;

  /// Connections for rendering the 21-point hand skeleton (joints, fingers, palm, wrist).
  static const List<(int, int)> skeletonConnections = [
    // Thumb
    (wrist, thumbCmc),
    (thumbCmc, thumbMcp),
    (thumbMcp, thumbIp),
    (thumbIp, thumbTip),
    // Index finger
    (wrist, indexMcp),
    (indexMcp, indexPip),
    (indexPip, indexDip),
    (indexDip, indexTip),
    // Middle finger
    (middleMcp, middlePip),
    (middlePip, middleDip),
    (middleDip, middleTip),
    // Ring finger
    (ringMcp, ringPip),
    (ringPip, ringDip),
    (ringDip, ringTip),
    // Little finger (pinky)
    (wrist, pinkyMcp),
    (pinkyMcp, pinkyPip),
    (pinkyPip, pinkyDip),
    (pinkyDip, pinkyTip),
    // Palm knuckles
    (indexMcp, middleMcp),
    (middleMcp, ringMcp),
    (ringMcp, pinkyMcp),
  ];

  final List<HandLandmarkPoint> landmarks;
  final Handedness handedness;
  final double confidence;
  final DateTime timestamp;

  const DetectedHand({
    required this.landmarks,
    this.handedness = Handedness.unknown,
    this.confidence = 1.0,
    required this.timestamp,
  });

  bool get hasCompleteLandmarks => landmarks.length >= expectedLandmarkCount;

  HandLandmarkPoint operator [](int index) => landmarks[index];

  /// Characteristic palm size (distance from wrist to middle MCP) used for scale-invariant gesture checks.
  double get palmScale {
    if (!hasCompleteLandmarks) return 0.1;
    final scale = landmarks[wrist].distanceTo(landmarks[middleMcp]);
    return scale > 0.01 ? scale : 0.1;
  }

  /// Bounding box in normalized [0..1] coordinates: (minX, minY, maxX, maxY).
  (double, double, double, double) get boundingBox {
    if (landmarks.isEmpty) return (0.0, 0.0, 0.0, 0.0);
    double minX = landmarks.first.x;
    double minY = landmarks.first.y;
    double maxX = landmarks.first.x;
    double maxY = landmarks.first.y;
    for (final pt in landmarks) {
      if (pt.x < minX) minX = pt.x;
      if (pt.y < minY) minY = pt.y;
      if (pt.x > maxX) maxX = pt.x;
      if (pt.y > maxY) maxY = pt.y;
    }
    return (minX, minY, maxX, maxY);
  }
}
