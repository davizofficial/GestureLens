import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/errors/app_error.dart';
import '../domain/capture_event.dart';

abstract class PhotoStorageGateway {
  Future<SavedPhotoItem> saveProcessedPhoto({
    required Uint8List pngBytes,
    required DateTime capturedAt,
    required CaptureTriggerSource triggerSource,
    required String filterName,
    required String portalModeLabel,
  });

  Future<SavedPhotoItem> saveRecordedVideo({
    required String sourceVideoPath,
    Uint8List? thumbnailPngBytes,
    required DateTime capturedAt,
    required int durationSeconds,
    required String filterName,
    required String portalModeLabel,
  }) {
    throw UnimplementedError();
  }

  Future<List<SavedPhotoItem>> loadPhotoHistory();

  Future<void> deletePhoto(SavedPhotoItem item);
}

class PhotoStorageService implements PhotoStorageGateway {
  final Directory? customBaseDirectory;
  final bool enableDeviceGallerySync;

  PhotoStorageService({
    this.customBaseDirectory,
    this.enableDeviceGallerySync = true,
  });

  Future<Directory> resolveStorageDirectory() async {
    if (customBaseDirectory != null) {
      if (!await customBaseDirectory!.exists()) {
        await customBaseDirectory!.create(recursive: true);
      }
      return customBaseDirectory!;
    }
    final appDocDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${appDocDir.path}/GestureLens_Captures');
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    return photosDir;
  }

  @override
  Future<SavedPhotoItem> saveProcessedPhoto({
    required Uint8List pngBytes,
    required DateTime capturedAt,
    required CaptureTriggerSource triggerSource,
    required String filterName,
    required String portalModeLabel,
  }) async {
    if (pngBytes.isEmpty) {
      throw AppError.fromCode(
        AppErrorCode.photoSavingFailed,
        customDetail: 'Empty image buffer',
      );
    }

    try {
      final dir = await resolveStorageDirectory();
      final filename = PhotoFilenameGenerator.generate(
        capturedAt,
        source: triggerSource,
      );
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(pngBytes, flush: true);

      if (enableDeviceGallerySync &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        try {
          await Gal.putImageBytes(
            pngBytes,
            name: filename.replaceAll('.png', ''),
            album: 'GestureLens',
          );
        } catch (_) {}
      }

      return SavedPhotoItem(
        id: filename,
        filePath: file.path,
        filename: filename,
        capturedAt: capturedAt,
        triggerSource: triggerSource,
        filterName: filterName,
        portalModeLabel: portalModeLabel,
        mediaType: CaptureMediaType.photo,
      );
    } catch (e) {
      if (e is AppError) rethrow;
      throw AppError.fromCode(
        AppErrorCode.photoSavingFailed,
        cause: e,
      );
    }
  }

  @override
  Future<SavedPhotoItem> saveRecordedVideo({
    required String sourceVideoPath,
    Uint8List? thumbnailPngBytes,
    required DateTime capturedAt,
    required int durationSeconds,
    required String filterName,
    required String portalModeLabel,
  }) async {
    try {
      final dir = await resolveStorageDirectory();
      final ext = sourceVideoPath.toLowerCase().endsWith('.gif') ? 'gif' : 'mp4';
      final filename = PhotoFilenameGenerator.generateVideo(
        capturedAt,
        durationSeconds: durationSeconds,
        extension: ext,
      );
      final targetPath = '${dir.path}/$filename';
      final sourceFile = File(sourceVideoPath);
      if (sourceFile.path != targetPath) {
        await sourceFile.copy(targetPath);
        try {
          await sourceFile.delete();
        } catch (_) {}
      }

      String? thumbPath;
      if (thumbnailPngBytes != null && thumbnailPngBytes.isNotEmpty) {
        thumbPath = '$targetPath.thumb.png';
        await File(thumbPath).writeAsBytes(thumbnailPngBytes, flush: true);
      }

      if (enableDeviceGallerySync &&
          ext == 'mp4' &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        try {
          await Gal.putVideo(targetPath, album: 'GestureLens');
        } catch (_) {}
      }

      return SavedPhotoItem(
        id: filename,
        filePath: targetPath,
        filename: filename,
        capturedAt: capturedAt,
        triggerSource: CaptureTriggerSource.videoRecording,
        filterName: filterName,
        portalModeLabel: portalModeLabel,
        mediaType: CaptureMediaType.video,
        durationSeconds: durationSeconds,
        thumbnailPath: thumbPath,
      );
    } catch (e) {
      if (e is AppError) rethrow;
      throw AppError.fromCode(
        AppErrorCode.photoSavingFailed,
        cause: e,
        customDetail: 'Gagal menyimpan video rekaman',
      );
    }
  }

  @override
  Future<List<SavedPhotoItem>> loadPhotoHistory() async {
    try {
      final dir = await resolveStorageDirectory();
      if (!await dir.exists()) return const [];

      final entities = await dir.list().toList();
      final items = <SavedPhotoItem>[];
      final seenPaths = <String>{};

      for (final entity in entities) {
        if (entity is! File) continue;
        final path = entity.path;
        final lower = path.toLowerCase();
        // Skip internal video thumbnail files
        if (lower.endsWith('.thumb.png')) continue;

        final isPhoto = lower.endsWith('.png');
        final isVideo = lower.endsWith('.mp4') || lower.endsWith('.gif');
        if (!isPhoto && !isVideo) continue;
        if (!seenPaths.add(path)) continue;

        final filename = path.split(Platform.pathSeparator).last;
        final stat = await entity.stat();

        if (isVideo) {
          final durMatch = RegExp(r'_VIDEO_(\d+)s_').firstMatch(filename);
          final dur = durMatch != null
              ? int.tryParse(durMatch.group(1) ?? '')
              : null;
          final thumbCandidate = '$path.thumb.png';
          final hasThumb = await File(thumbCandidate).exists();
          items.add(
            SavedPhotoItem(
              id: filename,
              filePath: path,
              filename: filename,
              capturedAt: stat.modified,
              triggerSource: CaptureTriggerSource.videoRecording,
              filterName: 'Portal Filter',
              portalModeLabel: 'Video',
              mediaType: CaptureMediaType.video,
              durationSeconds: dur ?? 1,
              thumbnailPath: hasThumb ? thumbCandidate : null,
            ),
          );
        } else {
          final isBlink = filename.contains('_BLINK_');
          items.add(
            SavedPhotoItem(
              id: filename,
              filePath: path,
              filename: filename,
              capturedAt: stat.modified,
              triggerSource: isBlink
                  ? CaptureTriggerSource.autoBlink
                  : CaptureTriggerSource.manual,
              filterName: 'Portal Filter',
              portalModeLabel: 'Portal',
              mediaType: CaptureMediaType.photo,
            ),
          );
        }
      }

      items.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      return items;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> deletePhoto(SavedPhotoItem item) async {
    final file = File(item.filePath);
    if (await file.exists()) {
      await file.delete();
    }
    if (item.thumbnailPath != null) {
      final thumb = File(item.thumbnailPath!);
      if (await thumb.exists()) {
        await thumb.delete();
      }
    }
  }
}
