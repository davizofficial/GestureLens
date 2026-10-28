import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../capture/domain/capture_event.dart';
import '../../effects/domain/filter_type.dart';
import '../../face_tracking/domain/blink_detector.dart';
import '../domain/camera_frame.dart';

class CameraTopStatusBar extends StatelessWidget {
  final FilterType activeFilter;
  final PortalRenderMode portalMode;
  final TrackingStatus trackingStatus;
  final int detectedHandCount;
  final bool autoCaptureEnabled;
  final AutoCaptureStatus autoCaptureStatus;
  final BlinkDetectorState blinkState;
  final int fps;

  const CameraTopStatusBar({
    super.key,
    required this.activeFilter,
    required this.portalMode,
    required this.trackingStatus,
    required this.detectedHandCount,
    required this.autoCaptureEnabled,
    required this.autoCaptureStatus,
    this.blinkState = BlinkDetectorState.unarmed,
    required this.fps,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Active Filter & 2D/3D Mode badges
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusBadge(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Filter: ${activeFilter.displayName}',
                  accentColor: const Color(0xFF00F0FF),
                ),
                const SizedBox(width: 8),
                _StatusBadge(
                  icon: portalMode == PortalRenderMode.mode3D
                      ? Icons.view_in_ar_rounded
                      : Icons.crop_original_rounded,
                  label: portalMode.label,
                  accentColor: portalMode == PortalRenderMode.mode3D
                      ? const Color(0xFFFF46DC)
                      : const Color(0xFF3CFF82),
                ),
              ],
            ),

            // Tracking & Auto Blink Capture status indicators
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusBadge(
                  icon: Icons.back_hand_outlined,
                  label: _trackingStatusText(),
                  accentColor: trackingStatus == TrackingStatus.trackingActive
                      ? const Color(0xFF3CFF82)
                      : Colors.amberAccent,
                ),
                if (autoCaptureEnabled) ...[
                  const SizedBox(width: 8),
                  _StatusBadge(
                    icon: Icons.visibility_rounded,
                    label: AppConstants.autoBlinkCaptureActiveText,
                    accentColor: const Color(0xFF00E676),
                  ),
                  const SizedBox(width: 8),
                  _buildBlinkGuidanceBadge(),
                ],
                if (fps > 0) ...[
                  const SizedBox(width: 8),
                  _StatusBadge(
                    icon: Icons.speed_rounded,
                    label: '$fps FPS',
                    accentColor: Colors.white70,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlinkGuidanceBadge() {
    if (autoCaptureStatus == AutoCaptureStatus.waitingForFace) {
      return const _StatusBadge(
        icon: Icons.face_retouching_natural_rounded,
        label: AppConstants.noFaceGuidanceText,
        accentColor: Colors.orangeAccent,
      );
    }
    switch (blinkState) {
      case BlinkDetectorState.armedOpen:
        return const _StatusBadge(
          icon: Icons.remove_red_eye_outlined,
          label: 'Wajah Terdeteksi • Kedipkan Mata',
          accentColor: Color(0xFF00F0FF),
        );
      case BlinkDetectorState.eyesClosed:
        return const _StatusBadge(
          icon: Icons.camera_enhance_rounded,
          label: 'Kedipan Terdeteksi!',
          accentColor: Color(0xFFFFD700),
        );
      case BlinkDetectorState.cooldown:
        return const _StatusBadge(
          icon: Icons.timer_outlined,
          label: 'Cooldown Kedipan...',
          accentColor: Colors.white70,
        );
      case BlinkDetectorState.unarmed:
        return const _StatusBadge(
          icon: Icons.face_retouching_natural_rounded,
          label: AppConstants.noFaceGuidanceText,
          accentColor: Colors.orangeAccent,
        );
    }
  }

  String _trackingStatusText() {
    switch (trackingStatus) {
      case TrackingStatus.trackingActive:
        return 'Tracking Aktif ($detectedHandCount Tangan)';
      case TrackingStatus.trackingLost:
        return 'Tracking Hilang';
      case TrackingStatus.detectorUnavailable:
        return 'Detektor Tangan Nonaktif';
      case TrackingStatus.idle:
        return 'Menunggu Tangan';
    }
  }
}

class CameraEdgeControlRail extends StatelessWidget {
  final FilterType activeFilter;
  final PortalRenderMode portalMode;
  final bool autoCaptureEnabled;
  final bool showSkeleton;
  final bool canSwitchCamera;
  final bool isCaptureInProgress;
  final SavedPhotoItem? latestPhoto;
  final int totalSavedPhotos;
  final VoidCallback onPreviousFilter;
  final VoidCallback onNextFilter;
  final VoidCallback onTogglePortalMode;
  final VoidCallback onToggleAutoCapture;
  final VoidCallback onToggleSkeleton;
  final VoidCallback onToggleCleanView;
  final VoidCallback onSwitchCamera;
  final VoidCallback onManualCapture;
  final VoidCallback onOpenGallery;

  const CameraEdgeControlRail({
    super.key,
    required this.activeFilter,
    required this.portalMode,
    required this.autoCaptureEnabled,
    required this.showSkeleton,
    required this.canSwitchCamera,
    required this.isCaptureInProgress,
    required this.latestPhoto,
    required this.totalSavedPhotos,
    required this.onPreviousFilter,
    required this.onNextFilter,
    required this.onTogglePortalMode,
    required this.onToggleAutoCapture,
    required this.onToggleSkeleton,
    required this.onToggleCleanView,
    required this.onSwitchCamera,
    required this.onManualCapture,
    required this.onOpenGallery,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Left cluster: Filter switcher + 2D/3D mode toggle + Skeleton toggle + Hide UI (Clean View)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('prev_filter_button'),
                    tooltip: 'Filter Sebelumnya',
                    onPressed: onPreviousFilter,
                    icon: const Icon(
                      Icons.chevron_left_rounded,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    activeFilter.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  IconButton(
                    key: const Key('next_filter_button'),
                    tooltip: 'Filter Berikutnya',
                    onPressed: onNextFilter,
                    icon: const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  OutlinedButton.icon(
                    key: const Key('mode_toggle_button'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF00F0FF)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    onPressed: onTogglePortalMode,
                    icon: const Icon(Icons.layers_rounded, size: 16),
                    label: Text(
                      portalMode == PortalRenderMode.mode2D ? '2D' : '3D',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: const Key('skeleton_toggle_button'),
                    tooltip: showSkeleton
                        ? 'Sembunyikan Skeleton Tangan (S)'
                        : 'Tampilkan Skeleton Tangan (S)',
                    onPressed: onToggleSkeleton,
                    icon: Icon(
                      showSkeleton
                          ? Icons.grain_rounded
                          : Icons.blur_off_rounded,
                      color: showSkeleton
                          ? const Color(0xFF3CFF82)
                          : Colors.white54,
                    ),
                  ),
                  const SizedBox(width: 2),
                  OutlinedButton.icon(
                    key: const Key('hide_ui_button'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    onPressed: onToggleCleanView,
                    icon: const Icon(
                      Icons.visibility_off_outlined,
                      size: 16,
                      color: Color(0xFF00F0FF),
                    ),
                    label: const Text(
                      'Hide UI',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Right cluster: Auto Blink Capture toggle, Camera Switch, Manual Shutter, Recent Thumbnail
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilterChip(
                    key: const Key('auto_capture_toggle'),
                    selected: autoCaptureEnabled,
                    onSelected: (_) => onToggleAutoCapture(),
                    selectedColor: const Color(0xFF00C853).withValues(alpha: 0.35),
                    backgroundColor: Colors.white10,
                    checkmarkColor: const Color(0xFF3CFF82),
                    label: Text(
                      autoCaptureEnabled ? 'Auto Blink: ON' : 'Auto Blink: OFF',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (canSwitchCamera) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      key: const Key('switch_camera_button'),
                      tooltip: 'Ganti Kamera',
                      onPressed: onSwitchCamera,
                      icon: const Icon(
                        Icons.cameraswitch_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  // Manual Capture Shutter Button
                  GestureDetector(
                    key: const Key('manual_capture_button'),
                    onTap: isCaptureInProgress ? null : onManualCapture,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF00F0FF),
                          width: 3,
                        ),
                        color: isCaptureInProgress
                            ? Colors.white24
                            : Colors.white.withValues(alpha: 0.9),
                      ),
                      child: Center(
                        child: isCaptureInProgress
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  key: Key('capture_progress_indicator'),
                                  strokeWidth: 2.5,
                                  color: Color(0xFF00F0FF),
                                ),
                              )
                            : const Icon(
                                Icons.camera_alt_rounded,
                                color: Color(0xFF0B0F19),
                                size: 24,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Recent capture thumbnail / gallery button
                  InkWell(
                    key: const Key('open_gallery_button'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: onOpenGallery,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white38),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (latestPhoto != null &&
                              File(latestPhoto!.filePath).existsSync())
                            ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child: Image.file(
                                File(latestPhoto!.filePath),
                                fit: BoxFit.cover,
                              ),
                            )
                          else
                            const Icon(
                              Icons.photo_library_outlined,
                              color: Colors.white70,
                              size: 20,
                            ),
                          if (totalSavedPhotos > 0)
                            Positioned(
                              right: 2,
                              bottom: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$totalSavedPhotos',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accentColor;

  const _StatusBadge({
    required this.icon,
    required this.label,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accentColor, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
