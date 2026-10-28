import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
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

  Future<Directory> _resolveStorageDirectory() async {
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
      final dir = await _resolveStorageDirectory();
      final filename = PhotoFilenameGenerator.generate(
        capturedAt,
        source: triggerSource,
      );
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(pngBytes, flush: true);

      // On Android / iOS, also export to the system gallery album when enabled
      if (enableDeviceGallerySync &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        try {
          await Gal.putImageBytes(
            pngBytes,
            name: filename.replaceAll('.png', ''),
            album: 'GestureLens',
          );
        } catch (_) {
          // Local file in GestureLens_Captures succeeded; do not fail if gallery album permission is restricted
        }
      }

      return SavedPhotoItem(
        id: filename,
        filePath: file.path,
        filename: filename,
        capturedAt: capturedAt,
        triggerSource: triggerSource,
        filterName: filterName,
        portalModeLabel: portalModeLabel,
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
  Future<List<SavedPhotoItem>> loadPhotoHistory() async {
    try {
      final dir = await _resolveStorageDirectory();
      if (!await dir.exists()) return const [];

      final entities = await dir.list().toList();
      final items = <SavedPhotoItem>[];
      final seenPaths = <String>{};

      for (final entity in entities) {
        if (entity is! File) continue;
        final path = entity.path;
        if (!path.toLowerCase().endsWith('.png')) continue;
        if (!seenPaths.add(path)) continue;

        final filename = path.split(Platform.pathSeparator).last;
        final stat = await entity.stat();
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
          ),
        );
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
  }
}
