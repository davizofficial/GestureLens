import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_detection/hand_detection.dart' show FpsCounter;
import 'package:image/image.dart' as img;
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/orientation/orientation_gate.dart';
import '../../../core/utils/frame_scheduler.dart';
import '../../capture/data/photo_storage_service.dart';
import '../../capture/domain/capture_event.dart';
import '../../capture/services/auto_capture_controller.dart';
import '../../capture/services/video_recording_service.dart';
import '../../effects/data/portal_processor.dart';
import '../../effects/domain/filter_type.dart';
import '../../effects/domain/portal_geometry.dart';
import '../../face_tracking/data/face_tracking_service.dart';
import '../../face_tracking/domain/blink_detector.dart';
import '../../gallery/presentation/photo_gallery_screen.dart';
import '../../hand_tracking/data/hand_tracking_service.dart';
import '../../hand_tracking/domain/gesture_interpreter.dart';
import '../../hand_tracking/domain/hand_landmarks.dart';
import '../../hand_tracking/presentation/hand_tracking_painter.dart';
import '../data/camera_service.dart';
import '../domain/camera_frame.dart';
import 'camera_controls.dart';

class GestureLensSessionController extends ChangeNotifier {
  final CameraGateway cameraService;
  final HandTrackingGateway handTrackingService;
  final FaceTrackingGateway faceTrackingService;
  final GestureInterpreter gestureInterpreter;
  final BlinkDetector blinkDetector;
  final PortalProcessor portalProcessor;
  final AutoCaptureController autoCaptureController;
  final VideoRecordingService videoRecordingService;
  final FrameScheduler frameScheduler;
  final Duration blinkCaptureDelay;

  CameraLifecycleStatus _cameraStatus = CameraLifecycleStatus.uninitialized;
  TrackingStatus _trackingStatus = TrackingStatus.idle;
  AutoCaptureStatus _autoCaptureStatus = AutoCaptureStatus.autoCaptureDisabled;

  FilterType _activeFilter = FilterType.dualTone;
  PortalRenderMode _portalMode = PortalRenderMode.mode2D;
  bool _showSkeleton = true;
  bool _hideUiOverlay = false;

  List<DetectedHand> _activeHands = const [];
  PortalGeometry _portalGeometry = PortalGeometry.empty;
  NormalizedCameraFramePacket? _latestFramePacket;
  ui.Image? _processedPortalPreviewImage;
  bool _isUpdatingPortalPreview = false;

  bool _isBlinkCountdownActive = false;
  double _blinkCountdownRemainingSeconds = 0.0;
  Timer? _blinkCountdownTimer;
  Timer? _recordingUiTimer;

  AppError? _fatalCameraError;
  String? _feedbackBannerMessage;
  bool _isFeedbackError = false;
  bool _showShutterFlash = false;
  int _fps = 0;

  final FpsCounter _fpsCounter = FpsCounter();
  Timer? _feedbackClearTimer;
  bool _isDisposed = false;

  GestureLensSessionController({
    CameraGateway? cameraService,
    HandTrackingGateway? handTrackingService,
    FaceTrackingGateway? faceTrackingService,
    GestureInterpreter? gestureInterpreter,
    BlinkDetector? blinkDetector,
    PortalProcessor? portalProcessor,
    AutoCaptureController? autoCaptureController,
    VideoRecordingService? videoRecordingService,
    FrameScheduler? frameScheduler,
    this.blinkCaptureDelay = const Duration(milliseconds: 1500),
  }) : cameraService = cameraService ?? CameraService(),
       handTrackingService = handTrackingService ?? HandTrackingService(),
       faceTrackingService = faceTrackingService ?? FaceTrackingService(),
       gestureInterpreter = gestureInterpreter ?? GestureInterpreter(),
       blinkDetector =
           blinkDetector ??
           BlinkDetector(
             openThreshold: 0.52,
             closedThreshold: 0.42,
             relativeDropThreshold: 0.22,
             minFaceConfidence: 0.35,
             minFaceWidthFraction: 0.04,
             minClosureDuration: const Duration(milliseconds: 20),
             maxClosureDuration: const Duration(milliseconds: 2200),
             triggerOnHoldDuration: const Duration(milliseconds: 1400),
           ),
       portalProcessor = portalProcessor ?? const PortalProcessor(),
       autoCaptureController =
           autoCaptureController ??
           AutoCaptureController(storageService: PhotoStorageService()),
       videoRecordingService =
           videoRecordingService ?? VideoRecordingService(),
       frameScheduler =
           frameScheduler ??
           FrameScheduler(
             minHandInterval: const Duration(milliseconds: 66),
             minFaceInterval: const Duration(milliseconds: 45),
           );

  CameraLifecycleStatus get cameraStatus => _cameraStatus;
  TrackingStatus get trackingStatus => _trackingStatus;
  AutoCaptureStatus get autoCaptureStatus => _autoCaptureStatus;
  BlinkDetectorState get blinkState => blinkDetector.state;
  bool get isBlinkCountdownActive => _isBlinkCountdownActive;
  double get blinkCountdownRemainingSeconds => _blinkCountdownRemainingSeconds;
  bool get isRecordingVideo => videoRecordingService.isRecording;
  bool get isEncodingVideo => videoRecordingService.isEncoding;
  int get recordingElapsedSeconds => videoRecordingService.elapsedSeconds;
  FilterType get activeFilter => _activeFilter;
  PortalRenderMode get portalMode => _portalMode;
  bool get showSkeleton => _showSkeleton;
  bool get hideUiOverlay => _hideUiOverlay;
  List<DetectedHand> get activeHands => _activeHands;
  PortalGeometry get portalGeometry => _portalGeometry;
  ui.Image? get processedPortalPreviewImage => _processedPortalPreviewImage;
  AppError? get fatalCameraError => _fatalCameraError;
  String? get feedbackBannerMessage => _feedbackBannerMessage;
  bool get isFeedbackError => _isFeedbackError;
  bool get showShutterFlash => _showShutterFlash;
  int get fps => _fps;

  bool get autoCaptureEnabled => autoCaptureController.autoCaptureEnabled;
  bool get isCaptureInProgress =>
      autoCaptureController.isBusy ||
      _autoCaptureStatus == AutoCaptureStatus.captureInProgress ||
      _autoCaptureStatus == AutoCaptureStatus.savingPhoto;
  bool get canRetryFailedSave => autoCaptureController.canRetryLastFailedSave;
  List<SavedPhotoItem> get photoHistory => autoCaptureController.history;
  SavedPhotoItem? get latestPhoto =>
      photoHistory.isNotEmpty ? photoHistory.first : null;
  Size get sourcePreviewSize =>
      _latestFramePacket?.orientedSize ?? cameraService.previewSize;

  Future<void> initializeCameraExperience() async {
    if (_cameraStatus == CameraLifecycleStatus.cameraInitializing ||
        _cameraStatus == CameraLifecycleStatus.cameraReady) {
      return;
    }

    _cameraStatus = CameraLifecycleStatus.cameraInitializing;
    _fatalCameraError = null;
    _notifySafely();

    await autoCaptureController.initializeHistory();

    try {
      await cameraService.initialize(onFrame: onCameraFrameReceived);
      _cameraStatus = CameraLifecycleStatus.cameraReady;
      _notifySafely();
    } catch (e) {
      _fatalCameraError = e is AppError
          ? e
          : AppError.fromCode(AppErrorCode.cameraInitializationFailed, cause: e);
      _cameraStatus = CameraLifecycleStatus.cameraError;
      _notifySafely();
      return;
    }

    // Initialize hand tracking (non-fatal if unavailable: manual capture still works)
    try {
      await handTrackingService.initialize();
      _trackingStatus = TrackingStatus.idle;
    } catch (e) {
      _trackingStatus = TrackingStatus.detectorUnavailable;
      final err = e is AppError
          ? e
          : AppError.fromCode(
              AppErrorCode.handDetectorInitializationFailed,
              cause: e,
            );
      _showFeedback(err.message, isError: true);
    }

    if (autoCaptureEnabled) {
      await _ensureFaceDetectorInitialized();
    }

    _notifySafely();
  }

  Future<void> _ensureFaceDetectorInitialized() async {
    if (faceTrackingService.isReady) return;
    try {
      await faceTrackingService.initialize();
    } catch (e) {
      autoCaptureController.setAutoCaptureEnabled(false);
      _autoCaptureStatus = AutoCaptureStatus.autoCaptureDisabled;
      final err = e is AppError
          ? e
          : AppError.fromCode(
              AppErrorCode.faceDetectorInitializationFailed,
              cause: e,
            );
      _showFeedback(err.message, isError: true);
    }
  }

  Future<void> pauseForOrientationOrBackground() async {
    if (_cameraStatus == CameraLifecycleStatus.uninitialized ||
        _cameraStatus == CameraLifecycleStatus.cameraPaused) {
      return;
    }
    _cancelBlinkCountdown();
    frameScheduler.reset();
    gestureInterpreter.reset();
    blinkDetector.reset();
    _activeHands = const [];
    _portalGeometry = PortalGeometry.empty;
    _cameraStatus = CameraLifecycleStatus.cameraPaused;
    await cameraService.disposeCamera();
    _notifySafely();
  }

  void onCameraFrameReceived(NormalizedCameraFramePacket packet) {
    if (_isDisposed || _cameraStatus != CameraLifecycleStatus.cameraReady) {
      return;
    }

    _latestFramePacket = packet;
    if (_fpsCounter.tick()) {
      _fps = _fpsCounter.fps;
    }

    final now = packet.timestamp;

    // Sample composite frame if video recording is active and portal is not currently updating
    if (videoRecordingService.shouldSampleNextFrame(now) &&
        !_portalGeometry.isValid) {
      _sampleFrameForVideoRecording(packet, now);
    }

    // 1. Bounded Hand Detection Job
    if (handTrackingService.isReady && frameScheduler.canScheduleHand(now)) {
      unawaited(
        frameScheduler.runHandTask(now, () async {
          try {
            final hands = await handTrackingService.detectHandsFromFrame(
              packet.rawFrame,
              mirrorHorizontally: packet.mirrorHorizontally,
              timestamp: now,
            );
            _handleHandDetectionOutput(hands, packet, now);
          } catch (_) {}
        }),
      );
    }

    // 2. Bounded Face & Eye-Blink Detection Job (only when Auto Blink Capture is active)
    if (autoCaptureEnabled &&
        faceTrackingService.isReady &&
        frameScheduler.canScheduleFace(now)) {
      unawaited(
        frameScheduler.runFaceTask(now, () async {
          try {
            final faces = await faceTrackingService.detectFacesFromFrame(
              packet.rawFrame,
              mirrorHorizontally: packet.mirrorHorizontally,
            );
            await _handleFaceDetectionOutput(faces, now);
          } catch (_) {}
        }),
      );
    }
  }

  void _sampleFrameForVideoRecording(
    NormalizedCameraFramePacket packet,
    DateTime now,
  ) {
    try {
      final decoded = portalProcessor.decodeCameraFrame(
        packet.rawFrame,
        mirrorHorizontally: packet.mirrorHorizontally,
      );
      final previewSource = decoded.width > 480
          ? img.copyResize(decoded, width: 480)
          : decoded;
      final processed = portalProcessor.processFrame(
        sourceImage: previewSource,
        portal: _portalGeometry,
        primaryFilter: _activeFilter,
        hands: _activeHands,
        includeSkeleton: _showSkeleton,
      );
      videoRecordingService.addProcessedFrame(processed, now);
    } catch (_) {}
  }

  void _handleHandDetectionOutput(
    List<DetectedHand> hands,
    NormalizedCameraFramePacket packet,
    DateTime now,
  ) {
    if (_isDisposed) return;

    final result = gestureInterpreter.interpret(hands, now);
    _activeHands = result.activeHands;

    if (_activeHands.isNotEmpty) {
      _trackingStatus = TrackingStatus.trackingActive;
    } else if (result.triggeredAction == GestureActionType.trackingLost) {
      _trackingStatus = TrackingStatus.trackingLost;
    } else if (_trackingStatus != TrackingStatus.detectorUnavailable) {
      _trackingStatus = TrackingStatus.idle;
    }

    switch (result.triggeredAction) {
      case GestureActionType.nextFilter:
        _activeFilter = _activeFilter.next;
        _showFeedback('Filter: ${_activeFilter.displayName}');
      case GestureActionType.togglePortalMode:
        _portalMode = _portalMode.toggled;
        _showFeedback('Mode: ${_portalMode.label}');
      case GestureActionType.trackingLost:
      case GestureActionType.none:
        break;
    }

    if (result.portalState != PortalTrackingState.none &&
        _activeHands.isNotEmpty) {
      _portalGeometry = PortalGeometry.fromHands(
        _activeHands,
        mode: _portalMode,
      );
      _scheduleLivePortalImageUpdate(packet, _portalGeometry, _activeFilter);
    } else {
      _portalGeometry = PortalGeometry.empty;
    }

    _notifySafely();
  }

  void _scheduleLivePortalImageUpdate(
    NormalizedCameraFramePacket packet,
    PortalGeometry portal,
    FilterType filter,
  ) {
    if (_isUpdatingPortalPreview || !portal.isValid) return;
    _isUpdatingPortalPreview = true;

    Future<void>(() async {
      try {
        final decoded = portalProcessor.decodeCameraFrame(
          packet.rawFrame,
          mirrorHorizontally: packet.mirrorHorizontally,
        );
        // Downscale live overlay image to 480p max width for ultra-fast real-time preview rendering
        final previewSource = decoded.width > 480
            ? img.copyResize(decoded, width: 480)
            : decoded;
        final processed = portalProcessor.processFrame(
          sourceImage: previewSource,
          portal: portal,
          primaryFilter: filter,
          hands: const [],
          includeSkeleton: false,
        );

        final now = DateTime.now();
        if (videoRecordingService.shouldSampleNextFrame(now)) {
          final frameForVideo = _showSkeleton
              ? portalProcessor.processFrame(
                  sourceImage: previewSource,
                  portal: portal,
                  primaryFilter: filter,
                  hands: _activeHands,
                  includeSkeleton: true,
                )
              : processed;
          videoRecordingService.addProcessedFrame(frameForVideo, now);
        }

        final pngBytes = Uint8List.fromList(img.encodePng(processed));
        final codec = await ui.instantiateImageCodec(pngBytes);
        final frameInfo = await codec.getNextFrame();
        if (!_isDisposed) {
          final old = _processedPortalPreviewImage;
          _processedPortalPreviewImage = frameInfo.image;
          old?.dispose();
          _notifySafely();
        } else {
          frameInfo.image.dispose();
        }
      } catch (_) {
      } finally {
        _isUpdatingPortalPreview = false;
      }
    });
  }

  Future<void> _handleFaceDetectionOutput(
    List<FaceEyeObservation> faces,
    DateTime now,
  ) async {
    if (_isDisposed || !autoCaptureEnabled) return;

    if (isCaptureInProgress || _isBlinkCountdownActive) {
      return;
    }

    final eval = blinkDetector.evaluate(faces, now);
    if (eval.selectedFace == null) {
      _autoCaptureStatus = AutoCaptureStatus.waitingForFace;
      _notifySafely();
      return;
    }

    if (eval.blinkTriggered) {
      _triggerBlinkCountdownOrImmediateCapture();
      return;
    }

    switch (eval.state) {
      case BlinkDetectorState.unarmed:
        _autoCaptureStatus = AutoCaptureStatus.waitingForFace;
      case BlinkDetectorState.armedOpen:
      case BlinkDetectorState.eyesClosed:
        _autoCaptureStatus = AutoCaptureStatus.autoCaptureArmed;
      case BlinkDetectorState.cooldown:
        _autoCaptureStatus = AutoCaptureStatus.captureCooldown;
    }
    _notifySafely();
  }

  /// Starts the 1.5-second (1500ms) countdown when 1 blink is detected,
  /// then immediately snaps the photo ("Cekrek!").
  void _triggerBlinkCountdownOrImmediateCapture() {
    if (_isBlinkCountdownActive || isCaptureInProgress) return;

    if (blinkCaptureDelay <= Duration.zero) {
      unawaited(_executeCapture(CaptureTriggerSource.autoBlink));
      return;
    }

    _isBlinkCountdownActive = true;
    final totalMs = blinkCaptureDelay.inMilliseconds;
    var remainingMs = totalMs;
    _blinkCountdownRemainingSeconds = remainingMs / 1000.0;
    _notifySafely();

    _blinkCountdownTimer?.cancel();
    _blinkCountdownTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (timer) {
        if (_isDisposed || !autoCaptureEnabled) {
          _cancelBlinkCountdown();
          return;
        }
        remainingMs -= 100;
        if (remainingMs <= 0) {
          timer.cancel();
          _isBlinkCountdownActive = false;
          _blinkCountdownRemainingSeconds = 0.0;
          unawaited(_executeCapture(CaptureTriggerSource.autoBlink));
        } else {
          _blinkCountdownRemainingSeconds = remainingMs / 1000.0;
          _notifySafely();
        }
      },
    );
  }

  void _cancelBlinkCountdown() {
    _blinkCountdownTimer?.cancel();
    _blinkCountdownTimer = null;
    _isBlinkCountdownActive = false;
    _blinkCountdownRemainingSeconds = 0.0;
  }

  void selectNextFilter() {
    _activeFilter = _activeFilter.next;
    _showFeedback('Filter: ${_activeFilter.displayName}');
    if (_latestFramePacket != null && _portalGeometry.isValid) {
      _scheduleLivePortalImageUpdate(
        _latestFramePacket!,
        _portalGeometry,
        _activeFilter,
      );
    }
    _notifySafely();
  }

  void selectPreviousFilter() {
    _activeFilter = _activeFilter.previous;
    _showFeedback('Filter: ${_activeFilter.displayName}');
    if (_latestFramePacket != null && _portalGeometry.isValid) {
      _scheduleLivePortalImageUpdate(
        _latestFramePacket!,
        _portalGeometry,
        _activeFilter,
      );
    }
    _notifySafely();
  }

  void togglePortalMode() {
    _portalMode = _portalMode.toggled;
    if (_activeHands.isNotEmpty) {
      _portalGeometry = PortalGeometry.fromHands(
        _activeHands,
        mode: _portalMode,
      );
    }
    _showFeedback('Mode: ${_portalMode.label}');
    _notifySafely();
  }

  void toggleSkeletonVisibility() {
    _showSkeleton = !_showSkeleton;
    _showFeedback(
      _showSkeleton
          ? 'Skeleton Tangan Ditampilkan'
          : 'Skeleton Tangan Disembunyikan',
    );
    _notifySafely();
  }

  void toggleCleanView() {
    _hideUiOverlay = !_hideUiOverlay;
    if (!_hideUiOverlay) {
      _showFeedback('Tampilan Kontrol UI Ditampilkan');
    }
    _notifySafely();
  }

  Future<void> toggleAutoBlinkCapture() async {
    final nextState = !autoCaptureEnabled;
    autoCaptureController.setAutoCaptureEnabled(nextState);
    _cancelBlinkCountdown();
    blinkDetector.reset();

    if (nextState) {
      _autoCaptureStatus = AutoCaptureStatus.waitingForFace;
      _showFeedback(AppConstants.autoBlinkCaptureActiveText);
      await _ensureFaceDetectorInitialized();
    } else {
      _autoCaptureStatus = AutoCaptureStatus.autoCaptureDisabled;
      _showFeedback('Auto Blink Capture Dinonaktifkan');
    }
    _notifySafely();
  }

  Future<void> toggleVideoRecording() async {
    if (videoRecordingService.isEncoding) return;

    if (!videoRecordingService.isRecording) {
      final now = DateTime.now();
      videoRecordingService.startRecording(now);
      if (_latestFramePacket != null) {
        _sampleFrameForVideoRecording(_latestFramePacket!, now);
      }
      _recordingUiTimer?.cancel();
      _recordingUiTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _notifySafely(),
      );
      _showFeedback('Merekam Video Portal...');
      _notifySafely();
      return;
    }

    // Stop recording and encode
    _recordingUiTimer?.cancel();
    _recordingUiTimer = null;
    _notifySafely();

    final now = DateTime.now();
    try {
      final artifact = await videoRecordingService.stopAndEncodeRecording(now);
      if (artifact == null) return;

      final savedItem = await autoCaptureController.storageService
          .saveRecordedVideo(
            sourceVideoPath: artifact.videoFilePath,
            thumbnailPngBytes: artifact.thumbnailPngBytes,
            capturedAt: now,
            durationSeconds: artifact.durationSeconds,
            filterName: _activeFilter.displayName,
            portalModeLabel: _portalMode.label,
          );
      autoCaptureController.registerSavedMediaItem(savedItem);
      _showFeedback('Video berhasil disimpan (${savedItem.filename})');
    } catch (e) {
      final err = e is AppError
          ? e
          : AppError.fromCode(
              AppErrorCode.photoSavingFailed,
              cause: e,
              customDetail: 'Gagal menyimpan video',
            );
      _showFeedback(err.message, isError: true);
    }
    _notifySafely();
  }

  Future<void> switchCamera() async {
    if (!cameraService.canSwitchCamera) return;
    _cameraStatus = CameraLifecycleStatus.cameraInitializing;
    _notifySafely();

    try {
      await handTrackingService.resetTracking();
      faceTrackingService.resetTracking();
      gestureInterpreter.reset();
      _cancelBlinkCountdown();
      blinkDetector.reset();
      await cameraService.switchCamera(onFrame: onCameraFrameReceived);
      _cameraStatus = CameraLifecycleStatus.cameraReady;
    } catch (e) {
      final err = e is AppError
          ? e
          : AppError.fromCode(AppErrorCode.cameraInitializationFailed, cause: e);
      _showFeedback(err.message, isError: true);
      _cameraStatus = CameraLifecycleStatus.cameraError;
      _fatalCameraError = err;
    }
    _notifySafely();
  }

  Future<void> triggerManualCapture() async {
    await _executeCapture(CaptureTriggerSource.manual);
  }

  Future<void> retryLastFailedSave() async {
    if (!canRetryFailedSave) return;
    _autoCaptureStatus = AutoCaptureStatus.savingPhoto;
    _notifySafely();

    final outcome = await autoCaptureController.retryLastFailedSave(
      DateTime.now(),
    );
    _applyCaptureOutcome(outcome, CaptureTriggerSource.manual);
  }

  Future<void> _executeCapture(CaptureTriggerSource source) async {
    if (isCaptureInProgress) return;
    if (source == CaptureTriggerSource.autoBlink && !autoCaptureEnabled) {
      return;
    }

    _autoCaptureStatus = AutoCaptureStatus.captureInProgress;
    _showShutterFlash = true;
    _notifySafely();

    Future<void>.delayed(const Duration(milliseconds: 160), () {
      if (!_isDisposed) {
        _showShutterFlash = false;
        _notifySafely();
      }
    });

    final now = DateTime.now();
    try {
      final pngBytes = _buildCurrentProcessedFrameBytes();
      _autoCaptureStatus = AutoCaptureStatus.savingPhoto;
      _notifySafely();

      final outcome = await autoCaptureController.saveGeneratedBytes(
        pngBytes: pngBytes,
        source: source,
        filterName: _activeFilter.displayName,
        portalModeLabel: _portalMode.label,
        now: now,
      );
      _applyCaptureOutcome(outcome, source);
    } catch (e) {
      final err = e is AppError
          ? e
          : AppError.fromCode(AppErrorCode.imageProcessingFailed, cause: e);
      _autoCaptureStatus = AutoCaptureStatus.captureFailed;
      _showFeedback(err.message, isError: true);
      _notifySafely();
    }
  }

  void _applyCaptureOutcome(
    CaptureOperationOutcome outcome,
    CaptureTriggerSource source,
  ) {
    if (outcome.succeeded && outcome.savedItem != null) {
      _autoCaptureStatus = autoCaptureEnabled
          ? AutoCaptureStatus.captureCooldown
          : AutoCaptureStatus.autoCaptureDisabled;
      _showFeedback(
        'Foto berhasil disimpan (${outcome.savedItem!.filename})',
        isError: false,
      );
    } else if (outcome.error != null) {
      _autoCaptureStatus = AutoCaptureStatus.captureFailed;
      _showFeedback(outcome.error!.message, isError: true);
    }
    _notifySafely();
  }

  Uint8List _buildCurrentProcessedFrameBytes() {
    final packet = _latestFramePacket;
    final img.Image baseImage;
    if (packet != null) {
      baseImage = portalProcessor.decodeCameraFrame(
        packet.rawFrame,
        mirrorHorizontally: packet.mirrorHorizontally,
      );
    } else {
      // Fallback synthetic canvas only when invoked in unit/widget tests where no hardware CameraImage stream exists
      baseImage = img.Image(width: 640, height: 360);
      img.fill(baseImage, color: img.ColorRgb8(24, 34, 52));
    }

    return portalProcessor.renderCapturedPhotoBytes(
      sourceImage: baseImage,
      portal: _portalGeometry,
      primaryFilter: _activeFilter,
      hands: _activeHands,
      includeSkeleton: _showSkeleton,
    );
  }

  Future<void> deleteSavedPhoto(SavedPhotoItem item) async {
    await autoCaptureController.deletePhoto(item);
    _notifySafely();
  }

  void _showFeedback(String message, {bool isError = false}) {
    _feedbackBannerMessage = message;
    _isFeedbackError = isError;
    _feedbackClearTimer?.cancel();
    _feedbackClearTimer = Timer(const Duration(seconds: 3), () {
      if (!_isDisposed) {
        _feedbackBannerMessage = null;
        _notifySafely();
      }
    });
  }

  void _notifySafely() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _blinkCountdownTimer?.cancel();
    _recordingUiTimer?.cancel();
    _feedbackClearTimer?.cancel();
    _processedPortalPreviewImage?.dispose();
    unawaited(cameraService.disposeCamera());
    unawaited(handTrackingService.dispose());
    unawaited(faceTrackingService.dispose());
    super.dispose();
  }
}

class CameraScreen extends StatefulWidget {
  final GestureLensSessionController? controller;
  final bool? enforceAndroidLandscapeGateOverride;

  const CameraScreen({
    super.key,
    this.controller,
    this.enforceAndroidLandscapeGateOverride,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  late final GestureLensSessionController _controller;
  late final bool _ownsController;
  final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = GestureLensSessionController();
      _ownsController = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_controller.pauseForOrientationOrBackground());
    } else if (state == AppLifecycleState.resumed) {
      if (_isCurrentlyAllowedToRunCamera(context)) {
        unawaited(_controller.initializeCameraExperience());
      }
    }
  }

  bool _isCurrentlyAllowedToRunCamera(BuildContext context) {
    final enforce = widget.enforceAndroidLandscapeGateOverride ??
        (Theme.of(context).platform == TargetPlatform.android);
    if (!enforce) return true;
    return MediaQuery.orientationOf(context) == Orientation.landscape;
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _controller.selectNextFilter();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _controller.selectPreviousFilter();
    } else if (key == LogicalKeyboardKey.keyM) {
      _controller.togglePortalMode();
    } else if (key == LogicalKeyboardKey.space) {
      unawaited(_controller.triggerManualCapture());
    } else if (key == LogicalKeyboardKey.keyV ||
        key == LogicalKeyboardKey.keyR) {
      unawaited(_controller.toggleVideoRecording());
    } else if (key == LogicalKeyboardKey.keyB) {
      unawaited(_controller.toggleAutoBlinkCapture());
    } else if (key == LogicalKeyboardKey.keyS) {
      _controller.toggleSkeletonVisibility();
    } else if (key == LogicalKeyboardKey.keyH ||
        (key == LogicalKeyboardKey.escape && _controller.hideUiOverlay)) {
      _controller.toggleCleanView();
    }
  }

  Future<void> _openPhotoGallery() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoGalleryScreen(
          photos: _controller.photoHistory,
          onDeletePhoto: _controller.deleteSavedPhoto,
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyboardFocusNode.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AndroidLandscapeOrientationGate(
      enforceGateOverride: widget.enforceAndroidLandscapeGateOverride,
      onEnteredLandscape: () {
        unawaited(_controller.initializeCameraExperience());
      },
      onReturnedToPortrait: () {
        unawaited(_controller.pauseForOrientationOrBackground());
      },
      landscapeChild: _LandscapeCameraViewport(
        controller: _controller,
        keyboardFocusNode: _keyboardFocusNode,
        onKeyEvent: _handleKeyEvent,
        onOpenGallery: _openPhotoGallery,
      ),
    );
  }
}

class _LandscapeCameraViewport extends StatefulWidget {
  final GestureLensSessionController controller;
  final FocusNode keyboardFocusNode;
  final ValueChanged<KeyEvent> onKeyEvent;
  final VoidCallback onOpenGallery;

  const _LandscapeCameraViewport({
    required this.controller,
    required this.keyboardFocusNode,
    required this.onKeyEvent,
    required this.onOpenGallery,
  });

  @override
  State<_LandscapeCameraViewport> createState() =>
      _LandscapeCameraViewportState();
}

class _LandscapeCameraViewportState extends State<_LandscapeCameraViewport> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(widget.controller.initializeCameraExperience());
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: widget.keyboardFocusNode,
      autofocus: true,
      onKeyEvent: widget.onKeyEvent,
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final ctrl = widget.controller;

          return Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Live Camera Feed or Initialization / Error State
                _buildMainCameraLayer(ctrl),

                // 2. Real-Time Hand Skeleton & Portal Effect Overlay
                if (ctrl.cameraStatus == CameraLifecycleStatus.cameraReady)
                  IgnorePointer(
                    child: CustomPaint(
                      key: const Key('hand_tracking_overlay'),
                      painter: HandTrackingPainter(
                        hands: ctrl.activeHands,
                        portal: ctrl.portalGeometry,
                        activeFilter: ctrl.activeFilter,
                        showSkeleton: ctrl.showSkeleton,
                        sourceImageSize: ctrl.sourcePreviewSize,
                        processedPortalImage: ctrl.processedPortalPreviewImage,
                      ),
                    ),
                  ),

                // 3. Center 1.5s Blink Countdown HUD
                if (ctrl.isBlinkCountdownActive)
                  Center(
                    child: IgnorePointer(
                      child: Container(
                        key: const Key('blink_countdown_overlay'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B1021).withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: const Color(0xFF00F5D4),
                            width: 2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.camera_enhance_rounded,
                              color: Color(0xFF00F5D4),
                              size: 26,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Kedipan Terdeteksi! Cekrek dalam ${ctrl.blinkCountdownRemainingSeconds.toStringAsFixed(1)}s',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 4. Brief Shutter Flash Feedback
                if (ctrl.showShutterFlash)
                  IgnorePointer(
                    child: Container(
                      key: const Key('shutter_flash_overlay'),
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),

                // 5. Clean View Mode: only a subtle floating button to unhide UI
                if (ctrl.hideUiOverlay)
                  Positioned(
                    top: 12,
                    right: 14,
                    child: SafeArea(
                      child: Opacity(
                        opacity: 0.48,
                        child: Material(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            key: const Key('restore_ui_button'),
                            borderRadius: BorderRadius.circular(20),
                            onTap: ctrl.toggleCleanView,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.visibility_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Show UI',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // 6. Top Status Overlay (Hidden when Clean View Mode is active)
                if (!ctrl.hideUiOverlay)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: CameraTopStatusBar(
                      activeFilter: ctrl.activeFilter,
                      portalMode: ctrl.portalMode,
                      trackingStatus: ctrl.trackingStatus,
                      detectedHandCount: ctrl.activeHands.length,
                      autoCaptureEnabled: ctrl.autoCaptureEnabled,
                      autoCaptureStatus: ctrl.autoCaptureStatus,
                      blinkState: ctrl.blinkState,
                      isBlinkCountdownActive: ctrl.isBlinkCountdownActive,
                      blinkCountdownRemainingSeconds:
                          ctrl.blinkCountdownRemainingSeconds,
                      isRecordingVideo: ctrl.isRecordingVideo,
                      recordingElapsedSeconds: ctrl.recordingElapsedSeconds,
                      fps: ctrl.fps,
                    ),
                  ),

                // 7. Save / Feedback Toast Banner + Retry Action (Hidden when Clean View Mode is active)
                if (!ctrl.hideUiOverlay && ctrl.feedbackBannerMessage != null)
                  Positioned(
                    top: 56,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        key: const Key('feedback_banner'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: ctrl.isFeedbackError
                              ? const Color(0xFFB71C1C).withValues(alpha: 0.92)
                              : const Color(0xFF0F172A).withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: ctrl.isFeedbackError
                                ? Colors.redAccent
                                : const Color(0xFF00F0FF),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              ctrl.isFeedbackError
                                  ? Icons.error_outline_rounded
                                  : Icons.check_circle_outline_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                ctrl.feedbackBannerMessage!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (ctrl.canRetryFailedSave) ...[
                              const SizedBox(width: 10),
                              TextButton(
                                key: const Key('retry_save_button'),
                                onPressed: ctrl.retryLastFailedSave,
                                child: const Text(
                                  'Coba Simpan Lagi',
                                  style: TextStyle(
                                    color: Colors.amberAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                // 8. Bottom Edge Controls Rail (Hidden when Clean View Mode is active)
                if (!ctrl.hideUiOverlay)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: CameraEdgeControlRail(
                      activeFilter: ctrl.activeFilter,
                      portalMode: ctrl.portalMode,
                      autoCaptureEnabled: ctrl.autoCaptureEnabled,
                      showSkeleton: ctrl.showSkeleton,
                      canSwitchCamera: ctrl.cameraService.canSwitchCamera,
                      isCaptureInProgress: ctrl.isCaptureInProgress,
                      isRecordingVideo: ctrl.isRecordingVideo,
                      isEncodingVideo: ctrl.isEncodingVideo,
                      latestPhoto: ctrl.latestPhoto,
                      totalSavedPhotos: ctrl.photoHistory.length,
                      onPreviousFilter: ctrl.selectPreviousFilter,
                      onNextFilter: ctrl.selectNextFilter,
                      onTogglePortalMode: ctrl.togglePortalMode,
                      onToggleAutoCapture: ctrl.toggleAutoBlinkCapture,
                      onToggleSkeleton: ctrl.toggleSkeletonVisibility,
                      onToggleCleanView: ctrl.toggleCleanView,
                      onSwitchCamera: ctrl.switchCamera,
                      onManualCapture: ctrl.triggerManualCapture,
                      onToggleVideoRecording: ctrl.toggleVideoRecording,
                      onOpenGallery: widget.onOpenGallery,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMainCameraLayer(GestureLensSessionController ctrl) {
    switch (ctrl.cameraStatus) {
      case CameraLifecycleStatus.uninitialized:
      case CameraLifecycleStatus.cameraInitializing:
        return const Center(
          key: Key('camera_initializing_view'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF00F0FF)),
              SizedBox(height: 14),
              Text(
                'Menginisialisasi kamera...',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ],
          ),
        );

      case CameraLifecycleStatus.cameraPaused:
        return const Center(
          child: Text(
            'Kamera dijeda',
            style: TextStyle(color: Colors.white60, fontSize: 15),
          ),
        );

      case CameraLifecycleStatus.cameraError:
        return Center(
          key: const Key('camera_error_view'),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.videocam_off_rounded,
                  color: Colors.redAccent,
                  size: 48,
                ),
                const SizedBox(height: 14),
                Text(
                  ctrl.fatalCameraError?.message ??
                      'Kamera tidak dapat diakses.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  key: const Key('retry_camera_button'),
                  onPressed: ctrl.initializeCameraExperience,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Coba Lagi'),
                ),
              ],
            ),
          ),
        );

      case CameraLifecycleStatus.cameraReady:
        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: ctrl.sourcePreviewSize.width,
              height: ctrl.sourcePreviewSize.height,
              child: ctrl.cameraService.buildPreviewWidget(),
            ),
          ),
        );
    }
  }
}
