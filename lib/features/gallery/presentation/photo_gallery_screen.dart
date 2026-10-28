import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../capture/domain/capture_event.dart';

class PhotoGalleryScreen extends StatefulWidget {
  final List<SavedPhotoItem> photos;
  final Future<void> Function(SavedPhotoItem item) onDeletePhoto;

  const PhotoGalleryScreen({
    super.key,
    required this.photos,
    required this.onDeletePhoto,
  });

  @override
  State<PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen> {
  late List<SavedPhotoItem> _items;
  SavedPhotoItem? _selectedItem;

  @override
  void initState() {
    super.initState();
    _items = List<SavedPhotoItem>.from(widget.photos);
    if (_items.isNotEmpty) {
      _selectedItem = _items.first;
    }
  }

  String _formatTimestamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm:$ss';
  }

  Future<void> _confirmAndDelete(SavedPhotoItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141B2D),
        title: const Text(
          'Hapus Foto?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Foto "${item.filename}" akan dihapus dari riwayat lokal.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await widget.onDeletePhoto(item);
    if (!mounted) return;

    setState(() {
      _items.removeWhere((e) => e.id == item.id || e.filePath == item.filePath);
      if (_selectedItem?.id == item.id) {
        _selectedItem = _items.isNotEmpty ? _items.first : null;
      }
    });
  }

  Future<void> _sharePhoto(SavedPhotoItem item) async {
    final file = File(item.filePath);
    if (!await file.exists()) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(item.filePath)],
          text: 'GestureLens (${item.filterName} - ${item.portalModeLabel})',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fitur berbagi tidak tersedia pada platform ini.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
        title: Text('Riwayat Foto (${_items.length})'),
        actions: [
          if (_selectedItem != null) ...[
            IconButton(
              tooltip: 'Bagikan Foto',
              onPressed: () => _sharePhoto(_selectedItem!),
              icon: const Icon(Icons.share_rounded),
            ),
            IconButton(
              tooltip: 'Hapus Foto',
              onPressed: () => _confirmAndDelete(_selectedItem!),
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            ),
          ],
        ],
      ),
      body: _items.isEmpty
          ? const Center(
              child: Text(
                'Belum ada foto yang disimpan.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            )
          : Row(
              children: [
                // Thumbnail list sidebar for landscape ergonomics
                SizedBox(
                  width: 240,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final isSelected = _selectedItem?.id == item.id;
                      final file = File(item.filePath);
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _selectedItem = item),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF1E293B)
                                : const Color(0xFF111827),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF00F0FF)
                                  : Colors.white12,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 60,
                                  height: 44,
                                  child: file.existsSync()
                                      ? Image.file(
                                          file,
                                          fit: BoxFit.cover,
                                        )
                                      : const ColoredBox(
                                          color: Colors.black26,
                                          child: Icon(
                                            Icons.broken_image_outlined,
                                            color: Colors.white38,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.triggerSource.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatTimestamp(item.capturedAt),
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const VerticalDivider(width: 1, color: Colors.white12),
                // Full-size image viewer
                Expanded(
                  child: _selectedItem == null
                      ? const SizedBox.shrink()
                      : Column(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: InteractiveViewer(
                                  child: File(_selectedItem!.filePath).existsSync()
                                      ? Image.file(
                                          File(_selectedItem!.filePath),
                                          fit: BoxFit.contain,
                                        )
                                      : const Center(
                                          child: Text(
                                            'File gambar tidak ditemukan',
                                            style: TextStyle(color: Colors.white54),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              color: const Color(0xFF111827),
                              child: Text(
                                '${_selectedItem!.filename} • ${_formatTimestamp(_selectedItem!.capturedAt)}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}
