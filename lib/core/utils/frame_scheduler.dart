import '../constants/app_constants.dart';

class FrameScheduler {
  final Duration minHandInterval;
  final Duration minFaceInterval;

  bool _isHandJobRunning = false;
  bool _isFaceJobRunning = false;

  DateTime? _lastHandStartedAt;
  DateTime? _lastFaceStartedAt;

  int _processedHandFrames = 0;
  int _droppedHandFrames = 0;
  int _processedFaceFrames = 0;
  int _droppedFaceFrames = 0;

  FrameScheduler({
    this.minHandInterval = AppConstants.defaultHandAnalysisInterval,
    this.minFaceInterval = AppConstants.defaultFaceAnalysisInterval,
  });

  bool get isHandBusy => _isHandJobRunning;
  bool get isFaceBusy => _isFaceJobRunning;

  int get processedHandFrames => _processedHandFrames;
  int get droppedHandFrames => _droppedHandFrames;
  int get processedFaceFrames => _processedFaceFrames;
  int get droppedFaceFrames => _droppedFaceFrames;

  bool canScheduleHand(DateTime now) {
    if (_isHandJobRunning) {
      return false;
    }
    if (_lastHandStartedAt != null &&
        now.difference(_lastHandStartedAt!) < minHandInterval) {
      return false;
    }
    return true;
  }

  bool canScheduleFace(DateTime now) {
    if (_isFaceJobRunning) {
      return false;
    }
    if (_lastFaceStartedAt != null &&
        now.difference(_lastFaceStartedAt!) < minFaceInterval) {
      return false;
    }
    return true;
  }

  Future<T?> runHandTask<T>(
    DateTime frameTimestamp,
    Future<T> Function() task,
  ) async {
    if (!canScheduleHand(frameTimestamp)) {
      _droppedHandFrames++;
      return null;
    }
    _isHandJobRunning = true;
    _lastHandStartedAt = frameTimestamp;
    try {
      final result = await task();
      _processedHandFrames++;
      return result;
    } finally {
      _isHandJobRunning = false;
    }
  }

  Future<T?> runFaceTask<T>(
    DateTime frameTimestamp,
    Future<T> Function() task,
  ) async {
    if (!canScheduleFace(frameTimestamp)) {
      _droppedFaceFrames++;
      return null;
    }
    _isFaceJobRunning = true;
    _lastFaceStartedAt = frameTimestamp;
    try {
      final result = await task();
      _processedFaceFrames++;
      return result;
    } finally {
      _isFaceJobRunning = false;
    }
  }

  void reset() {
    _isHandJobRunning = false;
    _isFaceJobRunning = false;
    _lastHandStartedAt = null;
    _lastFaceStartedAt = null;
    _processedHandFrames = 0;
    _droppedHandFrames = 0;
    _processedFaceFrames = 0;
    _droppedFaceFrames = 0;
  }
}
