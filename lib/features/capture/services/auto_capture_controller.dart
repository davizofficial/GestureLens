import 'dart:typed_data';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_error.dart';
import '../data/photo_storage_service.dart';
import '../domain/capture_event.dart';

class CaptureOperationOutcome {
  final bool succeeded;
  final SavedPhotoItem? savedItem;
  final AppError? error;

  const CaptureOperationOutcome({
    required this.succeeded,
    this.savedItem,
    this.error,
  });
}

class AutoCaptureController {
  final PhotoStorageGateway storageService;
  final Duration captureCooldown;

  bool _autoCaptureEnabled = false;
  bool _isCaptureOrSaveInProgress = false;
  DateTime? _lastCompletedCaptureAt;

  // Retained buffer if the last save failed so the user can retry saving
  Uint8List? _pendingRetryBytes;
  CaptureTriggerSource? _pendingRetrySource;
  String? _pendingRetryFilterName;
  String? _pendingRetryModeLabel;

  final List<SavedPhotoItem> _history = [];

  AutoCaptureController({
    required this.storageService,
    this.captureCooldown = AppConstants.captureCooldownDuration,
  });

  bool get autoCaptureEnabled => _autoCaptureEnabled;
  bool get isBusy => _isCaptureOrSaveInProgress;
  bool get canRetryLastFailedSave =>
      _pendingRetryBytes != null && !_isCaptureOrSaveInProgress;
  List<SavedPhotoItem> get history => List.unmodifiable(_history);

  void setAutoCaptureEnabled(bool enabled) {
    _autoCaptureEnabled = enabled;
  }

  bool isCooldownActive(DateTime now) {
    if (_lastCompletedCaptureAt == null) return false;
    return now.difference(_lastCompletedCaptureAt!) < captureCooldown;
  }

  Future<void> initializeHistory() async {
    final loaded = await storageService.loadPhotoHistory();
    _history
      ..clear()
      ..addAll(loaded);
  }

  Future<CaptureOperationOutcome> triggerCapture({
    required CaptureTriggerSource source,
    required Future<Uint8List> Function() buildProcessedPhotoBytes,
    required String filterName,
    required String portalModeLabel,
    required DateTime now,
  }) async {
    if (source == CaptureTriggerSource.autoBlink && !_autoCaptureEnabled) {
      return const CaptureOperationOutcome(succeeded: false);
    }

    if (_isCaptureOrSaveInProgress) {
      return const CaptureOperationOutcome(succeeded: false);
    }

    if (source == CaptureTriggerSource.autoBlink && isCooldownActive(now)) {
      return const CaptureOperationOutcome(succeeded: false);
    }

    _isCaptureOrSaveInProgress = true;
    try {
      final pngBytes = await buildProcessedPhotoBytes();
      final savedItem = await storageService.saveProcessedPhoto(
        pngBytes: pngBytes,
        capturedAt: now,
        triggerSource: source,
        filterName: filterName,
        portalModeLabel: portalModeLabel,
      );

      _pendingRetryBytes = null;
      _pendingRetrySource = null;
      _pendingRetryFilterName = null;
      _pendingRetryModeLabel = null;
      _lastCompletedCaptureAt = now;

      _insertHistoryItemDeduplicated(savedItem);

      return CaptureOperationOutcome(
        succeeded: true,
        savedItem: savedItem,
      );
    } catch (e) {
      final appErr = e is AppError
          ? e
          : AppError.fromCode(AppErrorCode.photoSavingFailed, cause: e);
      return CaptureOperationOutcome(
        succeeded: false,
        error: appErr,
      );
    } finally {
      _isCaptureOrSaveInProgress = false;
    }
  }

  /// Stores a processed image buffer when saving fails so the user can retry saving without re-capturing.
  Future<CaptureOperationOutcome> saveGeneratedBytes({
    required Uint8List pngBytes,
    required CaptureTriggerSource source,
    required String filterName,
    required String portalModeLabel,
    required DateTime now,
  }) async {
    if (_isCaptureOrSaveInProgress) {
      return const CaptureOperationOutcome(succeeded: false);
    }

    _isCaptureOrSaveInProgress = true;
    try {
      final savedItem = await storageService.saveProcessedPhoto(
        pngBytes: pngBytes,
        capturedAt: now,
        triggerSource: source,
        filterName: filterName,
        portalModeLabel: portalModeLabel,
      );
      _pendingRetryBytes = null;
      _lastCompletedCaptureAt = now;
      _insertHistoryItemDeduplicated(savedItem);
      return CaptureOperationOutcome(
        succeeded: true,
        savedItem: savedItem,
      );
    } catch (e) {
      _pendingRetryBytes = pngBytes;
      _pendingRetrySource = source;
      _pendingRetryFilterName = filterName;
      _pendingRetryModeLabel = portalModeLabel;
      final appErr = e is AppError
          ? e
          : AppError.fromCode(AppErrorCode.photoSavingFailed, cause: e);
      return CaptureOperationOutcome(
        succeeded: false,
        error: appErr,
      );
    } finally {
      _isCaptureOrSaveInProgress = false;
    }
  }

  Future<CaptureOperationOutcome> retryLastFailedSave(DateTime now) async {
    final bytes = _pendingRetryBytes;
    if (bytes == null) {
      return const CaptureOperationOutcome(succeeded: false);
    }
    return saveGeneratedBytes(
      pngBytes: bytes,
      source: _pendingRetrySource ?? CaptureTriggerSource.manual,
      filterName: _pendingRetryFilterName ?? 'Portal Filter',
      portalModeLabel: _pendingRetryModeLabel ?? '2D Portal',
      now: now,
    );
  }

  Future<void> deletePhoto(SavedPhotoItem item) async {
    await storageService.deletePhoto(item);
    _history.removeWhere((e) => e.filePath == item.filePath || e.id == item.id);
  }

  void _insertHistoryItemDeduplicated(SavedPhotoItem item) {
    _history.removeWhere((e) => e.filePath == item.filePath || e.id == item.id);
    _history.insert(0, item);
  }
}
