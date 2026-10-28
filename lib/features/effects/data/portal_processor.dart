import 'dart:math' as math;
import 'dart:typed_data';
import 'package:hand_detection/hand_detection.dart'
    show CameraFrame, CameraFrameConversion, CameraFrameRotation;
import 'package:image/image.dart' as img;
import '../../hand_tracking/domain/hand_landmarks.dart';
import '../domain/filter_type.dart';
import '../domain/portal_geometry.dart';

class PortalProcessor {
  const PortalProcessor();

  /// Decodes a [CameraFrame] into an upright, optionally horizontally mirrored [img.Image].
  img.Image decodeCameraFrame(
    CameraFrame frame, {
    bool mirrorHorizontally = false,
  }) {
    img.Image rawImage;
    switch (frame.conversion) {
      case CameraFrameConversion.bgra2bgr:
        rawImage = _decodePacked4Channel(
          frame.bytes,
          width: frame.width,
          height: frame.height,
          strideCols: frame.strideCols,
          isBgra: true,
        );
      case CameraFrameConversion.rgba2bgr:
        rawImage = _decodePacked4Channel(
          frame.bytes,
          width: frame.width,
          height: frame.height,
          strideCols: frame.strideCols,
          isBgra: false,
        );
      case CameraFrameConversion.yuv2bgrNv12:
        rawImage = _decodeYuv420(
          frame.bytes,
          width: frame.width,
          height: frame.height,
          isNv12: true,
          isPlanarI420: false,
        );
      case CameraFrameConversion.yuv2bgrNv21:
        rawImage = _decodeYuv420(
          frame.bytes,
          width: frame.width,
          height: frame.height,
          isNv12: false,
          isPlanarI420: false,
        );
      case CameraFrameConversion.yuv2bgrI420:
        rawImage = _decodeYuv420(
          frame.bytes,
          width: frame.width,
          height: frame.height,
          isNv12: false,
          isPlanarI420: true,
        );
    }

    img.Image oriented = switch (frame.rotation) {
      CameraFrameRotation.cw90 => img.copyRotate(rawImage, angle: 90),
      CameraFrameRotation.cw180 => img.copyRotate(rawImage, angle: 180),
      CameraFrameRotation.cw270 => img.copyRotate(rawImage, angle: 270),
      null => rawImage,
    };

    if (mirrorHorizontally) {
      oriented = img.flipHorizontal(oriented);
    }

    return oriented;
  }

  /// Processes [sourceImage] by applying [primaryFilter] inside [portal]'s polygon mask
  /// (and [FilterType.complementary3DFilter] inside the 3D inner layer when in 3D mode),
  /// drawing the portal border, and optionally drawing [hands] skeleton.
  img.Image processFrame({
    required img.Image sourceImage,
    required PortalGeometry portal,
    required FilterType primaryFilter,
    List<DetectedHand> hands = const [],
    bool includeSkeleton = false,
  }) {
    final output = sourceImage.clone();
    final width = output.width;
    final height = output.height;
    if (width <= 1 || height <= 1) return output;

    if (portal.isValid) {
      final (normMinX, normMinY, normMaxX, normMaxY) = portal.normalizedBounds;
      final minX = (normMinX * (width - 1)).floor().clamp(0, width - 1);
      final minY = (normMinY * (height - 1)).floor().clamp(0, height - 1);
      final maxX = (normMaxX * (width - 1)).ceil().clamp(0, width - 1);
      final maxY = (normMaxY * (height - 1)).ceil().clamp(0, height - 1);

      final is3D =
          portal.mode == PortalRenderMode.mode3D &&
          portal.innerPolygon3D.length >= 3;
      final secondaryFilter = primaryFilter.complementary3DFilter;

      // Scanline polygon fill over the ROI bounding box only
      for (int y = minY; y <= maxY; y++) {
        final normY = y / (height - 1);
        final outerSpans = _scanlineIntersections(portal.outerPolygon, normY);
        if (outerSpans.isEmpty) continue;

        final innerSpans = is3D
            ? _scanlineIntersections(portal.innerPolygon3D, normY)
            : const <(double, double)>[];

        for (final (spanStartNorm, spanEndNorm) in outerSpans) {
          final startX = (spanStartNorm * (width - 1)).round().clamp(minX, maxX);
          final endX = (spanEndNorm * (width - 1)).round().clamp(minX, maxX);

          for (int x = startX; x <= endX; x++) {
            final normX = x / (width - 1);
            final inInner = is3D && _isInSpans(innerSpans, normX);
            final activeFilter = inInner ? secondaryFilter : primaryFilter;
            final (r, g, b) = _applyPixelFilter(
              sourceImage,
              x,
              y,
              activeFilter,
            );
            output.setPixelRgb(x, y, r, g, b);
          }
        }
      }

      // Draw portal outline and 3D prism struts
      _drawPortalBorder(output, portal);
    }

    if (includeSkeleton && hands.isNotEmpty) {
      _drawHandsSkeleton(output, hands);
    }

    return output;
  }

  /// Convenience helper that processes a frame and encodes it to PNG bytes.
  Uint8List renderCapturedPhotoBytes({
    required img.Image sourceImage,
    required PortalGeometry portal,
    required FilterType primaryFilter,
    List<DetectedHand> hands = const [],
    bool includeSkeleton = false,
  }) {
    final processed = processFrame(
      sourceImage: sourceImage,
      portal: portal,
      primaryFilter: primaryFilter,
      hands: hands,
      includeSkeleton: includeSkeleton,
    );
    return Uint8List.fromList(img.encodePng(processed));
  }

  /// Computes horizontal [xStart, xEnd] spans where scanline [normY] intersects [polygon].
  List<(double, double)> _scanlineIntersections(
    List<NormalizedPoint> polygon,
    double normY,
  ) {
    if (polygon.length < 3) return const [];
    final nodes = <double>[];
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final yi = polygon[i].y;
      final yj = polygon[j].y;
      if ((yi < normY && yj >= normY) || (yj < normY && yi >= normY)) {
        final xi = polygon[i].x;
        final xj = polygon[j].x;
        final x = xi + (normY - yi) / (yj - yi) * (xj - xi);
        nodes.add(x.clamp(0.0, 1.0));
      }
    }
    if (nodes.length < 2) return const [];
    nodes.sort();
    final spans = <(double, double)>[];
    for (int i = 0; i + 1 < nodes.length; i += 2) {
      spans.add((nodes[i], nodes[i + 1]));
    }
    return spans;
  }

  bool _isInSpans(List<(double, double)> spans, double normX) {
    for (final (start, end) in spans) {
      if (normX >= start && normX <= end) return true;
    }
    return false;
  }

  /// Applies one of the 11 MVP filters to pixel (x, y) in [src].
  (int, int, int) _applyPixelFilter(
    img.Image src,
    int x,
    int y,
    FilterType filter,
  ) {
    final p = src.getPixel(x, y);
    final r = p.r.toInt();
    final g = p.g.toInt();
    final b = p.b.toInt();
    final luma = ((r * 77 + g * 150 + b * 29) >> 8).clamp(0, 255);

    switch (filter) {
      case FilterType.dualTone:
        // Retro cyan/magenta dual-tone split based on luminance
        if (luma < 128) {
          final t = luma / 128.0;
          return (
            (25 * (1 - t) + 180 * t).round().clamp(0, 255),
            (10 * (1 - t) + 30 * t).round().clamp(0, 255),
            (95 * (1 - t) + 210 * t).round().clamp(0, 255),
          );
        } else {
          final t = (luma - 128) / 127.0;
          return (
            (180 * (1 - t) + 0 * t).round().clamp(0, 255),
            (30 * (1 - t) + 245 * t).round().clamp(0, 255),
            (210 * (1 - t) + 255 * t).round().clamp(0, 255),
          );
        }

      case FilterType.thermal:
        // Thermal infrared palette: deep blue -> purple -> red -> orange -> yellow -> white
        if (luma < 64) {
          final t = luma / 64.0;
          return (
            (t * 120).round(),
            0,
            (80 + t * 175).round().clamp(0, 255),
          );
        } else if (luma < 128) {
          final t = (luma - 64) / 64.0;
          return (
            (120 + t * 135).round().clamp(0, 255),
            (t * 40).round(),
            (255 * (1 - t)).round().clamp(0, 255),
          );
        } else if (luma < 192) {
          final t = (luma - 128) / 64.0;
          return (
            255,
            (40 + t * 185).round().clamp(0, 255),
            0,
          );
        } else {
          final t = (luma - 192) / 63.0;
          return (
            255,
            (225 + t * 30).round().clamp(0, 255),
            (t * 255).round().clamp(0, 255),
          );
        }

      case FilterType.sketch:
        // Pencil sketch using local gradient magnitude inverted on paper tone
        final grad = _sobelMagnitude(src, x, y);
        final ink = (255 - (grad * 2.2).round()).clamp(0, 255);
        final paperShade = ((ink * 0.85) + (luma * 0.15)).round().clamp(0, 255);
        return (paperShade, paperShade, (paperShade * 0.96).round());

      case FilterType.pixelate:
        // Mosaic block pixelation
        final blockSize = math.max(8, src.width ~/ 48);
        final bx = ((x ~/ blockSize) * blockSize + blockSize ~/ 2)
            .clamp(0, src.width - 1);
        final by = ((y ~/ blockSize) * blockSize + blockSize ~/ 2)
            .clamp(0, src.height - 1);
        final bp = src.getPixel(bx, by);
        return (bp.r.toInt(), bp.g.toInt(), bp.b.toInt());

      case FilterType.glitch:
        // Horizontal RGB channel separation + CRT scanlines
        final shift = math.max(4, src.width ~/ 50);
        final sliceOffset = ((y ~/ 12) % 3 == 0) ? shift * 2 : shift;
        final rx = (x + sliceOffset).clamp(0, src.width - 1);
        final bx = (x - sliceOffset).clamp(0, src.width - 1);
        final rp = src.getPixel(rx, y).r.toInt();
        final bp = src.getPixel(bx, y).b.toInt();
        final scanlineFactor = (y % 4 == 0) ? 0.72 : 1.0;
        return (
          (rp * scanlineFactor).round().clamp(0, 255),
          (g * scanlineFactor).round().clamp(0, 255),
          (bp * scanlineFactor).round().clamp(0, 255),
        );

      case FilterType.invert:
        return (255 - r, 255 - g, 255 - b);

      case FilterType.redChannel:
        // High-contrast red channel emphasis with dark shadows
        final boostedRed = (r * 1.15).round().clamp(0, 255);
        final mutedLuma = (luma * 0.18).round().clamp(0, 255);
        return (boostedRed, mutedLuma, mutedLuma);

      case FilterType.edgeDetection:
        // Neon Sobel edge detection on dark background
        final edge = (_sobelMagnitude(src, x, y) * 1.8).round().clamp(0, 255);
        return (
          (edge * 0.25).round(),
          edge,
          (edge * 0.85).round().clamp(0, 255),
        );

      case FilterType.blur:
        // Fast 5x5 box/Cross kernel average inside portal
        int sr = 0, sg = 0, sb = 0, count = 0;
        const step = 2;
        for (int dy = -2 * step; dy <= 2 * step; dy += step) {
          final ny = (y + dy).clamp(0, src.height - 1);
          for (int dx = -2 * step; dx <= 2 * step; dx += step) {
            final nx = (x + dx).clamp(0, src.width - 1);
            final np = src.getPixel(nx, ny);
            sr += np.r.toInt();
            sg += np.g.toInt();
            sb += np.b.toInt();
            count++;
          }
        }
        return (sr ~/ count, sg ~/ count, sb ~/ count);

      case FilterType.cartoon:
        // Color quantization (posterization) + dark edge outlines
        final edge = _sobelMagnitude(src, x, y);
        if (edge > 72) {
          return (18, 18, 24);
        }
        const levels = 48;
        final qr = ((r ~/ levels) * levels + levels ~/ 2).clamp(0, 255);
        final qg = ((g ~/ levels) * levels + levels ~/ 2).clamp(0, 255);
        final qb = ((b ~/ levels) * levels + levels ~/ 2).clamp(0, 255);
        return (qr, qg, qb);

      case FilterType.rainbowWave:
        // Sinusoidal rainbow wave overlay blended with source pixels
        final phase = (x / math.max(1, src.width) * 2.0 * math.pi) +
            (y / math.max(1, src.height) * math.pi);
        final wr = ((math.sin(phase) * 0.5 + 0.5) * 255).round();
        final wg =
            ((math.sin(phase + 2.0 * math.pi / 3.0) * 0.5 + 0.5) * 255).round();
        final wb =
            ((math.sin(phase + 4.0 * math.pi / 3.0) * 0.5 + 0.5) * 255).round();
        return (
          ((r * 0.45) + (wr * 0.55)).round().clamp(0, 255),
          ((g * 0.45) + (wg * 0.55)).round().clamp(0, 255),
          ((b * 0.45) + (wb * 0.55)).round().clamp(0, 255),
        );
    }
  }

  int _sobelMagnitude(img.Image src, int x, int y) {
    final xm1 = (x - 1).clamp(0, src.width - 1);
    final xp1 = (x + 1).clamp(0, src.width - 1);
    final ym1 = (y - 1).clamp(0, src.height - 1);
    final yp1 = (y + 1).clamp(0, src.height - 1);

    int lumaAt(int px, int py) {
      final p = src.getPixel(px, py);
      return (p.r.toInt() * 77 + p.g.toInt() * 150 + p.b.toInt() * 29) >> 8;
    }

    final tl = lumaAt(xm1, ym1);
    final tc = lumaAt(x, ym1);
    final tr = lumaAt(xp1, ym1);
    final ml = lumaAt(xm1, y);
    final mr = lumaAt(xp1, y);
    final bl = lumaAt(xm1, yp1);
    final bc = lumaAt(x, yp1);
    final br = lumaAt(xp1, yp1);

    final gx = -tl - 2 * ml - bl + tr + 2 * mr + br;
    final gy = -tl - 2 * tc - tr + bl + 2 * bc + br;
    return ((gx.abs() + gy.abs()) >> 1).clamp(0, 255);
  }

  void _drawPortalBorder(img.Image canvas, PortalGeometry portal) {
    final w = canvas.width - 1;
    final h = canvas.height - 1;
    final outerColor = portal.mode == PortalRenderMode.mode3D
        ? img.ColorRgb8(255, 70, 220)
        : img.ColorRgb8(0, 240, 255);

    for (int i = 0; i < portal.outerPolygon.length; i++) {
      final a = portal.outerPolygon[i];
      final b = portal.outerPolygon[(i + 1) % portal.outerPolygon.length];
      img.drawLine(
        canvas,
        x1: (a.x * w).round(),
        y1: (a.y * h).round(),
        x2: (b.x * w).round(),
        y2: (b.y * h).round(),
        color: outerColor,
        thickness: 3,
      );
    }

    if (portal.mode == PortalRenderMode.mode3D &&
        portal.innerPolygon3D.length >= 3) {
      final innerColor = img.ColorRgb8(0, 255, 190);
      for (int i = 0; i < portal.innerPolygon3D.length; i++) {
        final a = portal.innerPolygon3D[i];
        final b = portal.innerPolygon3D[(i + 1) % portal.innerPolygon3D.length];
        img.drawLine(
          canvas,
          x1: (a.x * w).round(),
          y1: (a.y * h).round(),
          x2: (b.x * w).round(),
          y2: (b.y * h).round(),
          color: innerColor,
          thickness: 2,
        );
      }

      final strutColor = img.ColorRgb8(255, 215, 0);
      for (final (outerPt, innerPt) in portal.prismEdges) {
        img.drawLine(
          canvas,
          x1: (outerPt.x * w).round(),
          y1: (outerPt.y * h).round(),
          x2: (innerPt.x * w).round(),
          y2: (innerPt.y * h).round(),
          color: strutColor,
          thickness: 2,
        );
      }
    }
  }

  void _drawHandsSkeleton(img.Image canvas, List<DetectedHand> hands) {
    final w = canvas.width - 1;
    final h = canvas.height - 1;
    final boneColor = img.ColorRgb8(60, 255, 130);
    final jointColor = img.ColorRgb8(255, 255, 255);

    for (final hand in hands) {
      if (!hand.hasCompleteLandmarks) continue;
      for (final (startIdx, endIdx) in DetectedHand.skeletonConnections) {
        final s = hand[startIdx];
        final e = hand[endIdx];
        img.drawLine(
          canvas,
          x1: (s.x * w).round().clamp(0, w),
          y1: (s.y * h).round().clamp(0, h),
          x2: (e.x * w).round().clamp(0, w),
          y2: (e.y * h).round().clamp(0, h),
          color: boneColor,
          thickness: 2,
        );
      }
      for (final lm in hand.landmarks) {
        img.fillCircle(
          canvas,
          x: (lm.x * w).round().clamp(0, w),
          y: (lm.y * h).round().clamp(0, h),
          radius: 4,
          color: jointColor,
        );
      }
    }
  }

  img.Image _decodePacked4Channel(
    Uint8List bytes, {
    required int width,
    required int height,
    required int strideCols,
    required bool isBgra,
  }) {
    final out = img.Image(width: width, height: height);
    final rowStride = strideCols * 4;
    for (int y = 0; y < height; y++) {
      final rowStart = y * rowStride;
      for (int x = 0; x < width; x++) {
        final offset = rowStart + x * 4;
        if (offset + 3 >= bytes.length) break;
        final c0 = bytes[offset];
        final c1 = bytes[offset + 1];
        final c2 = bytes[offset + 2];
        if (isBgra) {
          out.setPixelRgb(x, y, c2, c1, c0);
        } else {
          out.setPixelRgb(x, y, c0, c1, c2);
        }
      }
    }
    return out;
  }

  img.Image _decodeYuv420(
    Uint8List bytes, {
    required int width,
    required int height,
    required bool isNv12,
    required bool isPlanarI420,
  }) {
    final out = img.Image(width: width, height: height);
    final frameSize = width * height;
    final uvQuarterSize = frameSize ~/ 4;

    for (int y = 0; y < height; y++) {
      final yRowOffset = y * width;
      final uvRow = y >> 1;
      for (int x = 0; x < width; x++) {
        final yIndex = yRowOffset + x;
        if (yIndex >= bytes.length) break;
        final yVal = bytes[yIndex] & 0xFF;

        final uvCol = x >> 1;
        int uVal = 128;
        int vVal = 128;

        if (isPlanarI420) {
          final uIndex = frameSize + uvRow * (width >> 1) + uvCol;
          final vIndex = frameSize + uvQuarterSize + uvRow * (width >> 1) + uvCol;
          if (vIndex < bytes.length) {
            uVal = bytes[uIndex] & 0xFF;
            vVal = bytes[vIndex] & 0xFF;
          }
        } else {
          final uvIndex = frameSize + uvRow * width + (uvCol << 1);
          if (uvIndex + 1 < bytes.length) {
            if (isNv12) {
              uVal = bytes[uvIndex] & 0xFF;
              vVal = bytes[uvIndex + 1] & 0xFF;
            } else {
              vVal = bytes[uvIndex] & 0xFF;
              uVal = bytes[uvIndex + 1] & 0xFF;
            }
          }
        }

        final u = uVal - 128;
        final v = vVal - 128;
        final r = (yVal + ((1436 * v) >> 10)).clamp(0, 255);
        final g = (yVal - ((352 * u + 731 * v) >> 10)).clamp(0, 255);
        final b = (yVal + ((1815 * u) >> 10)).clamp(0, 255);
        out.setPixelRgb(x, y, r, g, b);
      }
    }
    return out;
  }
}
