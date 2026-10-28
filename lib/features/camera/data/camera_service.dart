import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:hand_detection/hand_detection.dart'
    show
        CameraFrameRotation,
        detectionSize,
        prepareCameraFrameFromImage,
        rotationForFrame;
import '../../../core/errors/app_error.dart';
import '../domain/camera_frame.dart';

typedef CameraFrameCallback = void Function(NormalizedCameraFramePacket packet);

abstract class CameraGateway {
  bool get isInitialized;
  bool get isStreaming;
  bool get canSwitchCamera;
  bool get isFrontCamera;
  Size get previewSize;

  Future<void> initialize({CameraFrameCallback? onFrame});
  Future<void> switchCamera({CameraFrameCallback? onFrame});
  Future<void> stopStream();
  Future<void> disposeCamera();
  Widget buildPreviewWidget();
}

class CameraService implements CameraGateway {
  List<CameraDescription> _cameras = const [];
  int _selectedCameraIndex = 0;
  CameraController? _controller;
  bool _isStreaming = false;

  @override
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  @override
  bool get isStreaming => _isStreaming;

  @override
  bool get canSwitchCamera => _cameras.length > 1;

  @override
  bool get isFrontCamera {
    if (_cameras.isEmpty || _selectedCameraIndex >= _cameras.length) {
      return true;
    }
    return _cameras[_selectedCameraIndex].lensDirection ==
        CameraLensDirection.front;
  }

  @override
  Size get previewSize {
    final pSize = _controller?.value.previewSize;
    if (pSize == null) return const Size(1280, 720);
    // In landscape mode, ensure width >= height
    final w = pSize.width >= pSize.height ? pSize.width : pSize.height;
    final h = pSize.width >= pSize.height ? pSize.height : pSize.width;
    return Size(w, h);
  }

  @override
  Future<void> initialize({CameraFrameCallback? onFrame}) async {
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      if (_cameras.isEmpty) {
        throw AppError.fromCode(AppErrorCode.cameraUnavailable);
      }

      // Prefer front-facing camera by default (PRD Section A.3)
      final frontIdx = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (frontIdx != -1 && _controller == null) {
        _selectedCameraIndex = frontIdx;
      }

      await _initSelectedCamera(onFrame: onFrame);
    } on CameraException catch (e) {
      if (e.code.toLowerCase().contains('permission') ||
          e.code.toLowerCase().contains('access')) {
        throw AppError.fromCode(
          AppErrorCode.cameraPermissionDenied,
          cause: e,
        );
      }
      throw AppError.fromCode(
        AppErrorCode.cameraInitializationFailed,
        cause: e,
        customDetail: e.description,
      );
    } catch (e) {
      if (e is AppError) rethrow;
      throw AppError.fromCode(
        AppErrorCode.cameraInitializationFailed,
        cause: e,
      );
    }
  }

  Future<void> _initSelectedCamera({CameraFrameCallback? onFrame}) async {
    await disposeCamera();

    final description = _cameras[_selectedCameraIndex];
    final controller = CameraController(
      description,
      ResolutionPreset.high, // ~1280x720
      enableAudio: false,
      imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await controller.initialize();
    _controller = controller;

    if (onFrame != null) {
      await _startFrameStream(controller, description, onFrame);
    }
  }

  Future<void> _startFrameStream(
    CameraController controller,
    CameraDescription description,
    CameraFrameCallback onFrame,
  ) async {
    if (_isStreaming) return;
    await controller.startImageStream((CameraImage image) {
      final deviceOrientation =
          controller.value.deviceOrientation == DeviceOrientation.portraitUp &&
              defaultTargetPlatform == TargetPlatform.android
          ? DeviceOrientation.landscapeLeft
          : controller.value.deviceOrientation;

      final isFront = description.lensDirection == CameraLensDirection.front;
      final CameraFrameRotation? rotation = rotationForFrame(
        width: image.width,
        height: image.height,
        sensorOrientation: description.sensorOrientation,
        isFrontCamera: isFront,
        deviceOrientation: deviceOrientation,
      );

      final rawFrame = prepareCameraFrameFromImage(
        image,
        rotation: rotation,
      );
      if (rawFrame == null) return;

      final orientedSize = detectionSize(
        width: image.width,
        height: image.height,
        rotation: rotation,
        maxDim: 4096,
      );

      // Front camera on mobile requires horizontal mirroring so coordinates match preview
      final shouldMirror =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS
          ? isFront
          : false;

      onFrame(
        NormalizedCameraFramePacket(
          rawFrame: rawFrame,
          orientedSize: orientedSize,
          mirrorHorizontally: shouldMirror,
          timestamp: DateTime.now(),
        ),
      );
    });
    _isStreaming = true;
  }

  @override
  Future<void> switchCamera({CameraFrameCallback? onFrame}) async {
    if (!canSwitchCamera) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _initSelectedCamera(onFrame: onFrame);
  }

  @override
  Future<void> stopStream() async {
    final controller = _controller;
    if (controller != null && _isStreaming && controller.value.isInitialized) {
      try {
        await controller.stopImageStream();
      } catch (_) {}
    }
    _isStreaming = false;
  }

  @override
  Future<void> disposeCamera() async {
    await stopStream();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  @override
  Widget buildPreviewWidget() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.expand();
    }
    return CameraPreview(controller);
  }
}
