import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart' show CameraFrame;

enum CameraLifecycleStatus {
  uninitialized,
  cameraInitializing,
  cameraReady,
  cameraPaused,
  cameraError,
}

enum TrackingStatus {
  idle,
  trackingActive,
  trackingLost,
  detectorUnavailable,
}

enum AutoCaptureStatus {
  autoCaptureDisabled,
  waitingForFace,
  autoCaptureArmed,
  captureInProgress,
  savingPhoto,
  captureCooldown,
  captureFailed,
}

class NormalizedCameraFramePacket {
  final CameraFrame rawFrame;
  final Size orientedSize;
  final bool mirrorHorizontally;
  final DateTime timestamp;

  const NormalizedCameraFramePacket({
    required this.rawFrame,
    required this.orientedSize,
    required this.mirrorHorizontally,
    required this.timestamp,
  });
}
