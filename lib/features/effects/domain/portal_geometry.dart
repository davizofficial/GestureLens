import 'dart:math' as math;
import '../../hand_tracking/domain/hand_landmarks.dart';
import 'filter_type.dart';

class NormalizedPoint {
  final double x;
  final double y;

  const NormalizedPoint(this.x, this.y);

  double distanceTo(NormalizedPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

class PortalGeometry {
  /// Outer polygon vertices in normalized [0..1] image coordinates.
  final List<NormalizedPoint> outerPolygon;

  /// Optional inner/layered polygon for 3D-inspired mode in normalized [0..1] coordinates.
  final List<NormalizedPoint> innerPolygon3D;

  /// Pairs of (outerVertex, innerVertex) forming 3D prism struts in 3D-inspired mode.
  final List<(NormalizedPoint, NormalizedPoint)> prismEdges;

  final PortalRenderMode mode;
  final bool isTwoHandPortal;

  const PortalGeometry({
    required this.outerPolygon,
    this.innerPolygon3D = const [],
    this.prismEdges = const [],
    required this.mode,
    required this.isTwoHandPortal,
  });

  static const PortalGeometry empty = PortalGeometry(
    outerPolygon: [],
    innerPolygon3D: [],
    prismEdges: [],
    mode: PortalRenderMode.mode2D,
    isTwoHandPortal: false,
  );

  bool get isValid => outerPolygon.length >= 3 && polygonArea(outerPolygon) >= 0.002;

  /// Normalized bounding box: (minX, minY, maxX, maxY) clamped to [0.0, 1.0].
  (double, double, double, double) get normalizedBounds {
    if (outerPolygon.isEmpty) return (0.0, 0.0, 0.0, 0.0);
    double minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
    for (final p in outerPolygon) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    return (
      minX.clamp(0.0, 1.0),
      minY.clamp(0.0, 1.0),
      maxX.clamp(0.0, 1.0),
      maxY.clamp(0.0, 1.0),
    );
  }

  /// Constructs a portal geometry from 1 or 2 detected hands.
  static PortalGeometry fromHands(
    List<DetectedHand> hands, {
    required PortalRenderMode mode,
  }) {
    final validHands = hands.where((h) => h.hasCompleteLandmarks).toList();
    if (validHands.isEmpty) {
      return PortalGeometry.empty;
    }

    if (validHands.length >= 2) {
      return _buildTwoHandPortal(validHands[0], validHands[1], mode);
    } else {
      return _buildOneHandPortal(validHands[0], mode);
    }
  }

  static PortalGeometry _buildTwoHandPortal(
    DetectedHand handA,
    DetectedHand handB,
    PortalRenderMode mode,
  ) {
    // Order left-most hand first in image space for consistent vertex ordering
    final leftHand =
        handA[DetectedHand.wrist].x <= handB[DetectedHand.wrist].x ? handA : handB;
    final rightHand = identical(leftHand, handA) ? handB : handA;

    // Collect key boundary landmarks across both hands (RetroLens fingertip portal style)
    final candidatePoints = <NormalizedPoint>[
      _toPoint(leftHand[DetectedHand.thumbTip]),
      _toPoint(leftHand[DetectedHand.indexTip]),
      _toPoint(leftHand[DetectedHand.middleTip]),
      _toPoint(leftHand[DetectedHand.ringTip]),
      _toPoint(leftHand[DetectedHand.pinkyTip]),
      _toPoint(leftHand[DetectedHand.wrist]),
      _toPoint(rightHand[DetectedHand.wrist]),
      _toPoint(rightHand[DetectedHand.pinkyTip]),
      _toPoint(rightHand[DetectedHand.ringTip]),
      _toPoint(rightHand[DetectedHand.middleTip]),
      _toPoint(rightHand[DetectedHand.indexTip]),
      _toPoint(rightHand[DetectedHand.thumbTip]),
    ];

    final hull = computeConvexHull(candidatePoints);
    if (hull.length < 3 || polygonArea(hull) < 0.0025) {
      return PortalGeometry.empty;
    }

    if (mode == PortalRenderMode.mode2D) {
      return PortalGeometry(
        outerPolygon: hull,
        mode: mode,
        isTwoHandPortal: true,
      );
    }

    // 3D-inspired mode: construct a layered inner perspective portal shifted by hand depth/tilt
    final center = polygonCentroid(hull);
    final depthDeltaX =
        ((rightHand[DetectedHand.indexTip].y - leftHand[DetectedHand.indexTip].y) * 0.08)
            .clamp(-0.04, 0.04);
    final depthDeltaY =
        ((leftHand[DetectedHand.thumbTip].x - rightHand[DetectedHand.thumbTip].x).abs() * 0.04 -
                0.02)
            .clamp(-0.04, 0.04);

    final innerPoly = <NormalizedPoint>[];
    final edges = <(NormalizedPoint, NormalizedPoint)>[];
    for (final v in hull) {
      final ix = (center.x + (v.x - center.x) * 0.58 + depthDeltaX).clamp(0.0, 1.0);
      final iy = (center.y + (v.y - center.y) * 0.58 + depthDeltaY).clamp(0.0, 1.0);
      final innerPt = NormalizedPoint(ix, iy);
      innerPoly.add(innerPt);
      edges.add((v, innerPt));
    }

    return PortalGeometry(
      outerPolygon: hull,
      innerPolygon3D: innerPoly,
      prismEdges: edges,
      mode: mode,
      isTwoHandPortal: true,
    );
  }

  static PortalGeometry _buildOneHandPortal(
    DetectedHand hand,
    PortalRenderMode mode,
  ) {
    final rawPoints = <NormalizedPoint>[
      _toPoint(hand[DetectedHand.thumbTip]),
      _toPoint(hand[DetectedHand.indexTip]),
      _toPoint(hand[DetectedHand.middleTip]),
      _toPoint(hand[DetectedHand.ringTip]),
      _toPoint(hand[DetectedHand.pinkyTip]),
      _toPoint(hand[DetectedHand.wrist]),
    ];

    final hull = computeConvexHull(rawPoints);
    if (hull.length < 3 || polygonArea(hull) < 0.002) {
      return PortalGeometry.empty;
    }

    if (mode == PortalRenderMode.mode2D) {
      return PortalGeometry(
        outerPolygon: hull,
        mode: mode,
        isTwoHandPortal: false,
      );
    }

    final center = polygonCentroid(hull);
    final innerPoly = <NormalizedPoint>[];
    final edges = <(NormalizedPoint, NormalizedPoint)>[];
    for (final v in hull) {
      final ix = (center.x + (v.x - center.x) * 0.55).clamp(0.0, 1.0);
      final iy = (center.y + (v.y - center.y) * 0.55).clamp(0.0, 1.0);
      final innerPt = NormalizedPoint(ix, iy);
      innerPoly.add(innerPt);
      edges.add((v, innerPt));
    }

    return PortalGeometry(
      outerPolygon: hull,
      innerPolygon3D: innerPoly,
      prismEdges: edges,
      mode: mode,
      isTwoHandPortal: false,
    );
  }

  static NormalizedPoint _toPoint(HandLandmarkPoint lm) {
    return NormalizedPoint(
      lm.x.clamp(0.0, 1.0),
      lm.y.clamp(0.0, 1.0),
    );
  }

  /// Monotone chain convex hull algorithm to guarantee a non-self-intersecting polygon.
  static List<NormalizedPoint> computeConvexHull(List<NormalizedPoint> points) {
    if (points.length <= 3) return List<NormalizedPoint>.from(points);

    final sorted = List<NormalizedPoint>.from(points)
      ..sort((a, b) {
        final cmpX = a.x.compareTo(b.x);
        return cmpX != 0 ? cmpX : a.y.compareTo(b.y);
      });

    double cross(NormalizedPoint o, NormalizedPoint a, NormalizedPoint b) {
      return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    }

    final lower = <NormalizedPoint>[];
    for (final p in sorted) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final upper = <NormalizedPoint>[];
    for (int i = sorted.length - 1; i >= 0; i--) {
      final p = sorted[i];
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  static double polygonArea(List<NormalizedPoint> polygon) {
    if (polygon.length < 3) return 0.0;
    double sum = 0.0;
    for (int i = 0; i < polygon.length; i++) {
      final current = polygon[i];
      final next = polygon[(i + 1) % polygon.length];
      sum += (current.x * next.y) - (next.x * current.y);
    }
    return sum.abs() * 0.5;
  }

  static NormalizedPoint polygonCentroid(List<NormalizedPoint> polygon) {
    if (polygon.isEmpty) return const NormalizedPoint(0.5, 0.5);
    double sx = 0.0, sy = 0.0;
    for (final p in polygon) {
      sx += p.x;
      sy += p.y;
    }
    return NormalizedPoint(sx / polygon.length, sy / polygon.length);
  }

  /// Ray-casting point-in-polygon check.
  static bool containsPoint(
    List<NormalizedPoint> polygon,
    double x,
    double y,
  ) {
    if (polygon.length < 3) return false;
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].x, yi = polygon[i].y;
      final xj = polygon[j].x, yj = polygon[j].y;

      final intersect = ((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / ((yj - yi) == 0 ? 1e-9 : (yj - yi)) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  bool containsOuter(double normX, double normY) =>
      containsPoint(outerPolygon, normX, normY);

  bool containsInner3D(double normX, double normY) =>
      innerPolygon3D.length >= 3 && containsPoint(innerPolygon3D, normX, normY);
}
