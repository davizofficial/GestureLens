import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../effects/domain/filter_type.dart';
import '../../effects/domain/portal_geometry.dart';
import '../domain/hand_landmarks.dart';

class HandTrackingPainter extends CustomPainter {
  final List<DetectedHand> hands;
  final PortalGeometry portal;
  final FilterType activeFilter;
  final bool showSkeleton;
  final bool showBoundingBoxes;
  final Size sourceImageSize;
  final ui.Image? processedPortalImage;

  const HandTrackingPainter({
    required this.hands,
    required this.portal,
    required this.activeFilter,
    required this.showSkeleton,
    this.showBoundingBoxes = false,
    required this.sourceImageSize,
    this.processedPortalImage,
  });

  /// Maps normalized [0..1] image coordinates into the viewport [size] using cover-fit scaling
  /// so aspect ratio is preserved without stretching.
  Offset mapNormalizedToCanvas(double normX, double normY, Size canvasSize) {
    if (sourceImageSize.width <= 0 || sourceImageSize.height <= 0) {
      return Offset(normX * canvasSize.width, normY * canvasSize.height);
    }
    final srcAspect = sourceImageSize.width / sourceImageSize.height;
    final dstAspect = canvasSize.width / canvasSize.height;

    double renderW;
    double renderH;
    double offsetX = 0.0;
    double offsetY = 0.0;

    if (srcAspect > dstAspect) {
      renderH = canvasSize.height;
      renderW = renderH * srcAspect;
      offsetX = (canvasSize.width - renderW) * 0.5;
    } else {
      renderW = canvasSize.width;
      renderH = renderW / srcAspect;
      offsetY = (canvasSize.height - renderH) * 0.5;
    }

    return Offset(
      offsetX + normX * renderW,
      offsetY + normY * renderH,
    );
  }

  Rect _computeDestRect(Size canvasSize) {
    final topLeft = mapNormalizedToCanvas(0.0, 0.0, canvasSize);
    final bottomRight = mapNormalizedToCanvas(1.0, 1.0, canvasSize);
    return Rect.fromPoints(topLeft, bottomRight);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (portal.isValid) {
      _paintPortalEffect(canvas, size);
      _paintPortalBorders(canvas, size);
    }

    if (showSkeleton && hands.isNotEmpty) {
      _paintHandSkeletons(canvas, size);
    }
  }

  void _paintPortalEffect(Canvas canvas, Size size) {
    final outerPath = _buildPolygonPath(portal.outerPolygon, size);

    canvas.save();
    canvas.clipPath(outerPath);

    final img = processedPortalImage;
    if (img != null) {
      final srcRect = Rect.fromLTWH(
        0,
        0,
        img.width.toDouble(),
        img.height.toDouble(),
      );
      final dstRect = _computeDestRect(size);
      canvas.drawImageRect(
        img,
        srcRect,
        dstRect,
        Paint()..filterQuality = FilterQuality.low,
      );
    } else {
      // Immediate low-latency tint inside the portal while the first pixel buffer is being decoded
      final paint = Paint()
        ..color = _portalAccentColor(activeFilter).withValues(alpha: 0.28)
        ..style = PaintingStyle.fill;
      canvas.drawPath(outerPath, paint);
    }

    canvas.restore();
  }

  void _paintPortalBorders(Canvas canvas, Size size) {
    final outerPath = _buildPolygonPath(portal.outerPolygon, size);
    final is3D =
        portal.mode == PortalRenderMode.mode3D &&
        portal.innerPolygon3D.length >= 3;

    // Outer glow
    final glowPaint = Paint()
      ..color = (is3D ? Colors.purpleAccent : Colors.cyanAccent)
          .withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawPath(outerPath, glowPaint);

    // Crisp outer border
    final borderPaint = Paint()
      ..color = is3D ? const Color(0xFFFF46DC) : const Color(0xFF00F0FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(outerPath, borderPaint);

    if (is3D) {
      final innerPath = _buildPolygonPath(portal.innerPolygon3D, size);
      final innerPaint = Paint()
        ..color = const Color(0xFF00FFBE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(innerPath, innerPaint);

      final strutPaint = Paint()
        ..color = const Color(0xFFFFD700).withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;

      for (final (outerPt, innerPt) in portal.prismEdges) {
        final p1 = mapNormalizedToCanvas(outerPt.x, outerPt.y, size);
        final p2 = mapNormalizedToCanvas(innerPt.x, innerPt.y, size);
        canvas.drawLine(p1, p2, strutPaint);
      }
    }
  }

  void _paintHandSkeletons(Canvas canvas, Size size) {
    final connectionPaint = Paint()
      ..color = const Color(0xFF3CFF82)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final jointFillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final jointRingPaint = Paint()
      ..color = const Color(0xFF00C853)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    for (final hand in hands) {
      if (!hand.hasCompleteLandmarks) continue;

      for (final (startIdx, endIdx) in DetectedHand.skeletonConnections) {
        final start = hand[startIdx];
        final end = hand[endIdx];
        final p1 = mapNormalizedToCanvas(start.x, start.y, size);
        final p2 = mapNormalizedToCanvas(end.x, end.y, size);
        canvas.drawLine(p1, p2, connectionPaint);
      }

      for (int i = 0; i < hand.landmarks.length; i++) {
        final lm = hand.landmarks[i];
        final center = mapNormalizedToCanvas(lm.x, lm.y, size);
        final isFingertip =
            i == DetectedHand.thumbTip ||
            i == DetectedHand.indexTip ||
            i == DetectedHand.middleTip ||
            i == DetectedHand.ringTip ||
            i == DetectedHand.pinkyTip;
        final radius = isFingertip ? 5.2 : 3.6;
        canvas.drawCircle(center, radius, jointFillPaint);
        canvas.drawCircle(center, radius, jointRingPaint);
      }

      if (showBoundingBoxes) {
        final (minX, minY, maxX, maxY) = hand.boundingBox;
        final tl = mapNormalizedToCanvas(minX, minY, size);
        final br = mapNormalizedToCanvas(maxX, maxY, size);
        final boxPaint = Paint()
          ..color = Colors.amberAccent.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4;
        canvas.drawRect(Rect.fromPoints(tl, br), boxPaint);
      }
    }
  }

  Path _buildPolygonPath(List<NormalizedPoint> polygon, Size size) {
    final path = Path();
    if (polygon.isEmpty) return path;
    final first = mapNormalizedToCanvas(polygon.first.x, polygon.first.y, size);
    path.moveTo(first.dx, first.dy);
    for (int i = 1; i < polygon.length; i++) {
      final pt = mapNormalizedToCanvas(polygon[i].x, polygon[i].y, size);
      path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    return path;
  }

  Color _portalAccentColor(FilterType filter) {
    switch (filter) {
      case FilterType.dualTone:
        return Colors.cyanAccent;
      case FilterType.thermal:
        return Colors.deepOrangeAccent;
      case FilterType.sketch:
        return Colors.blueGrey;
      case FilterType.pixelate:
        return Colors.greenAccent;
      case FilterType.glitch:
        return Colors.pinkAccent;
      case FilterType.invert:
        return Colors.purpleAccent;
      case FilterType.redChannel:
        return Colors.redAccent;
      case FilterType.edgeDetection:
        return Colors.tealAccent;
      case FilterType.blur:
        return Colors.lightBlueAccent;
      case FilterType.cartoon:
        return Colors.amberAccent;
      case FilterType.rainbowWave:
        return Colors.indigoAccent;
    }
  }

  @override
  bool shouldRepaint(covariant HandTrackingPainter oldDelegate) {
    return oldDelegate.hands != hands ||
        oldDelegate.portal != portal ||
        oldDelegate.activeFilter != activeFilter ||
        oldDelegate.showSkeleton != showSkeleton ||
        oldDelegate.showBoundingBoxes != showBoundingBoxes ||
        oldDelegate.sourceImageSize != sourceImageSize ||
        oldDelegate.processedPortalImage != processedPortalImage;
  }
}
