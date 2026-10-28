class AppConstants {
  const AppConstants._();

  static const String appName = 'GestureLens';
  static const String orientationGateMessage =
      'Putar HP ke posisi landscape untuk memulai.';
  static const String orientationAutoRotateHint =
      'Jika tampilan belum berubah, pastikan fitur Putar Otomatis (Auto-Rotate) aktif di pengaturan perangkat.';
  static const String autoBlinkCaptureActiveText = 'Auto Blink Capture Aktif';
  static const String noFaceGuidanceText = 'Arahkan wajah ke kamera';

  // Blink detection tunable initial defaults (PRD Section A.7)
  static const double defaultEyesOpenProbability = 0.65;
  static const double defaultEyesClosedProbability = 0.25;
  static const int requiredInitialOpenFrames = 2;
  static const Duration minBlinkClosureDuration = Duration(milliseconds: 80);
  static const Duration maxBlinkClosureDuration = Duration(milliseconds: 600);
  static const Duration captureCooldownDuration = Duration(seconds: 2);

  // Hand & Gesture detection defaults (PRD Section A.5 & C.7)
  static const double minHandConfidence = 0.50;
  static const double pinchNormalizedDistanceThreshold = 0.28;
  static const double pinchReleaseNormalizedThreshold = 0.38;
  static const Duration gestureCooldownDuration = Duration(milliseconds: 900);
  static const Duration trackingGracePeriod = Duration(milliseconds: 350);

  // Frame scheduler target ~15 FPS (PRD Section C.7)
  static const Duration defaultHandAnalysisInterval = Duration(milliseconds: 66);
  static const Duration defaultFaceAnalysisInterval = Duration(milliseconds: 66);

  // Target camera processing resolution (PRD Section A.8)
  static const int targetCameraWidth = 1280;
  static const int targetCameraHeight = 720;
}
