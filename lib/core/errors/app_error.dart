enum AppErrorCode {
  cameraPermissionDenied,
  cameraUnavailable,
  cameraInitializationFailed,
  unsupportedCameraStreamFormat,
  handDetectorInitializationFailed,
  faceDetectorInitializationFailed,
  noFaceDetected,
  noHandDetected,
  lowTrackingConfidence,
  imageProcessingFailed,
  photoSavingFailed,
  applicationBackgrounded,
  deviceOrientationInvalid,
  modelInferenceFailed,
}

class AppError implements Exception {
  final AppErrorCode code;
  final String message;
  final Object? cause;
  final bool isFatal;

  const AppError({
    required this.code,
    required this.message,
    this.cause,
    required this.isFatal,
  });

  factory AppError.fromCode(AppErrorCode code, {Object? cause, String? customDetail}) {
    final baseMessage = mapErrorCodeToMessage(code);
    final fullMessage = customDetail != null && customDetail.isNotEmpty
        ? '$baseMessage ($customDetail)'
        : baseMessage;
    return AppError(
      code: code,
      message: fullMessage,
      cause: cause,
      isFatal: isFatalErrorCode(code),
    );
  }

  bool get isOptionalFeatureError => !isFatal;

  static bool isFatalErrorCode(AppErrorCode code) {
    switch (code) {
      case AppErrorCode.cameraPermissionDenied:
      case AppErrorCode.cameraUnavailable:
      case AppErrorCode.cameraInitializationFailed:
      case AppErrorCode.deviceOrientationInvalid:
        return true;
      case AppErrorCode.unsupportedCameraStreamFormat:
      case AppErrorCode.handDetectorInitializationFailed:
      case AppErrorCode.faceDetectorInitializationFailed:
      case AppErrorCode.noFaceDetected:
      case AppErrorCode.noHandDetected:
      case AppErrorCode.lowTrackingConfidence:
      case AppErrorCode.imageProcessingFailed:
      case AppErrorCode.photoSavingFailed:
      case AppErrorCode.applicationBackgrounded:
      case AppErrorCode.modelInferenceFailed:
        return false;
    }
  }

  static String mapErrorCodeToMessage(AppErrorCode code) {
    switch (code) {
      case AppErrorCode.cameraPermissionDenied:
        return 'Izin kamera ditolak. Berikan izin kamera di pengaturan untuk memulai.';
      case AppErrorCode.cameraUnavailable:
        return 'Kamera tidak tersedia pada perangkat ini.';
      case AppErrorCode.cameraInitializationFailed:
        return 'Gagal menginisialisasi kamera. Silakan coba lagi.';
      case AppErrorCode.unsupportedCameraStreamFormat:
        return 'Format stream kamera tidak didukung untuk pemrosesan real-time.';
      case AppErrorCode.handDetectorInitializationFailed:
        return 'Detektor tangan gagal dimuat. Anda tetap dapat mengambil foto secara manual.';
      case AppErrorCode.faceDetectorInitializationFailed:
        return 'Detektor wajah gagal dimuat. Fitur Auto Blink Capture dinonaktifkan.';
      case AppErrorCode.noFaceDetected:
        return 'Arahkan wajah ke kamera';
      case AppErrorCode.noHandDetected:
        return 'Arahkan satu atau dua tangan ke kamera untuk membuka portal.';
      case AppErrorCode.lowTrackingConfidence:
        return 'Pelacakan kurang stabil. Pastikan pencahayaan cukup.';
      case AppErrorCode.imageProcessingFailed:
        return 'Gagal memproses efek gambar pada frame saat ini.';
      case AppErrorCode.photoSavingFailed:
        return 'Gagal menyimpan foto. Silakan coba simpan ulang.';
      case AppErrorCode.applicationBackgrounded:
        return 'Aplikasi dijeda saat berada di latar belakang.';
      case AppErrorCode.deviceOrientationInvalid:
        return 'Putar HP ke posisi landscape untuk memulai.';
      case AppErrorCode.modelInferenceFailed:
        return 'Terjadi kendala saat menjalankan inferensi model visi komputer.';
    }
  }

  @override
  String toString() => 'AppError(${code.name}: $message)';
}
