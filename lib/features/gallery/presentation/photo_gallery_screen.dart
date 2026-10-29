import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../capture/domain/capture_event.dart';

enum _GalleryMediaFilter {
  all('Semua'),
  photos('Foto'),
  videos('Video');

  final String label;
  const _GalleryMediaFilter(this.label);
}

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
  late List<SavedPhotoItem> _allItems;
  _GalleryMediaFilter _activeFilter = _GalleryMediaFilter.all;
  int? _fullscreenIndex;
  PageController? _pageController;
  bool _isSelectionMode = false;
  final Set<String> _selectedItemIds = {};

  @override
  void initState() {
    super.initState();
    _allItems = List<SavedPhotoItem>.from(widget.photos);
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  List<SavedPhotoItem> get _filteredItems {
    switch (_activeFilter) {
      case _GalleryMediaFilter.all:
        return _allItems;
      case _GalleryMediaFilter.photos:
        return _allItems.where((e) => !e.isVideo).toList();
      case _GalleryMediaFilter.videos:
        return _allItems.where((e) => e.isVideo).toList();
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedItemIds.clear();
    });
  }

  void _toggleItemSelection(String id) {
    setState(() {
      if (_selectedItemIds.contains(id)) {
        _selectedItemIds.remove(id);
      } else {
        _selectedItemIds.add(id);
      }
    });
  }

  void _toggleSelectAll(List<SavedPhotoItem> items) {
    setState(() {
      if (_selectedItemIds.length == items.length) {
        _selectedItemIds.clear();
      } else {
        _selectedItemIds.addAll(items.map((e) => e.id));
      }
    });
  }

  String _formatDateShort(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    final m = months[(dt.month - 1).clamp(0, 11)];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} $m ${dt.year} • $hh:$mm';
  }

  String _formatDuration(int? seconds) {
    final total = (seconds ?? 1).clamp(0, 3599);
    final mm = (total ~/ 60).toString();
    final ss = (total % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  void _openFullscreen(int index) {
    _pageController?.dispose();
    _pageController = PageController(initialPage: index);
    setState(() {
      _fullscreenIndex = index;
    });
  }

  void _closeFullscreen() {
    setState(() {
      _fullscreenIndex = null;
    });
  }

  Future<void> _confirmAndDelete(SavedPhotoItem item) async {
    final isVideo = item.isVideo;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(isVideo ? 'Hapus Video?' : 'Hapus Foto?'),
        content: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${isVideo ? "Video" : "Foto"} ini akan dihapus secara permanen dari galeri GestureLens.',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
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
      _allItems.removeWhere(
        (e) => e.id == item.id || e.filePath == item.filePath,
      );
      _selectedItemIds.remove(item.id);
      final remaining = _filteredItems;
      if (remaining.isEmpty) {
        _fullscreenIndex = null;
        _isSelectionMode = false;
      } else if (_fullscreenIndex != null &&
          _fullscreenIndex! >= remaining.length) {
        _fullscreenIndex = remaining.length - 1;
      }
    });
  }

  Future<void> _confirmAndDeleteSelected(List<SavedPhotoItem> items) async {
    final selectedItems =
        items.where((e) => _selectedItemIds.contains(e.id)).toList();
    if (selectedItems.isEmpty) return;

    final count = selectedItems.length;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('Hapus $count Item?'),
        content: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Item yang dipilih ($count foto/video) akan dihapus secara permanen dari galeri GestureLens.',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    for (final item in selectedItems) {
      await widget.onDeletePhoto(item);
    }
    if (!mounted) return;

    setState(() {
      _allItems.removeWhere((e) => _selectedItemIds.contains(e.id));
      _selectedItemIds.clear();
      _isSelectionMode = false;
      final remaining = _filteredItems;
      if (remaining.isEmpty) {
        _fullscreenIndex = null;
      }
    });
  }

  Future<void> _shareMedia(SavedPhotoItem item) async {
    final file = File(item.filePath);
    if (!await file.exists()) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(item.filePath)],
          text: 'GestureLens (${item.filterName})',
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

  Future<void> _openVideoExternally(SavedPhotoItem item) async {
    final path = item.filePath;
    if (!await File(path).exists()) return;
    try {
      if (Platform.isLinux) {
        await Process.start('xdg-open', [path]);
        return;
      } else if (Platform.isMacOS) {
        await Process.start('open', [path]);
        return;
      } else if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', path]);
        return;
      }
    } catch (_) {}
    await _shareMedia(item);
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    final isDetailOpen =
        _fullscreenIndex != null &&
        _fullscreenIndex! >= 0 &&
        _fullscreenIndex! < items.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main Content: either iOS Clean Grid or iOS Fullscreen Paged Viewer
          Positioned.fill(
            child: isDetailOpen
                ? _buildFullscreenViewer(items)
                : _buildIosGridContent(items),
          ),

          // Top Frosted Glass Navigation Bar (iOS style)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildIosTopBar(items, isDetailOpen: isDetailOpen),
          ),

          // Bottom Frosted Action Bar in Fullscreen Detail View
          if (isDetailOpen)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildIosBottomToolbar(items[_fullscreenIndex!]),
            ),

          // Bottom Frosted Action Bar in Multi-Select Mode
          if (!isDetailOpen && _isSelectionMode)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildIosSelectionBottomBar(items),
            ),
        ],
      ),
    );
  }

  Widget _buildIosSelectionBottomBar(List<SavedPhotoItem> items) {
    final selectedCount = _selectedItemIds.length;
    final hasSelection = selectedCount > 0;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
            top: 10,
            bottom: MediaQuery.of(context).padding.bottom + 12,
            left: 20,
            right: 20,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF121214).withValues(alpha: 0.85),
            border: const Border(
              top: BorderSide(color: Colors.white12, width: 0.5),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                hasSelection
                    ? '$selectedCount item dipilih'
                    : 'Pilih item untuk dihapus',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              CupertinoButton(
                key: const Key('gallery_batch_delete_button'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: hasSelection
                    ? const Color(0xFFFF453A).withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                minimumSize: Size.zero,
                onPressed:
                    hasSelection ? () => _confirmAndDeleteSelected(items) : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.trash,
                      color: hasSelection
                          ? const Color(0xFFFF453A)
                          : Colors.white24,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasSelection ? 'Hapus ($selectedCount)' : 'Hapus',
                      style: TextStyle(
                        color: hasSelection
                            ? const Color(0xFFFF453A)
                            : Colors.white24,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIosTopBar(
    List<SavedPhotoItem> items, {
    required bool isDetailOpen,
  }) {
    final activeItem = isDetailOpen ? items[_fullscreenIndex!] : null;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8,
            bottom: 10,
            left: 12,
            right: 16,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF121214).withValues(alpha: 0.78),
            border: const Border(
              bottom: BorderSide(color: Colors.white12, width: 0.5),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left button: Back to Camera or Back to Grid, or Cancel in Selection Mode
              if (_isSelectionMode && !isDetailOpen)
                CupertinoButton(
                  key: const Key('gallery_cancel_selection_button'),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  minimumSize: Size.zero,
                  onPressed: _toggleSelectionMode,
                  child: const Text(
                    'Batal',
                    style: TextStyle(
                      color: Color(0xFF0A84FF),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              else
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  minimumSize: Size.zero,
                  onPressed: isDetailOpen
                      ? _closeFullscreen
                      : () => Navigator.of(context).pop(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        CupertinoIcons.chevron_back,
                        color: Color(0xFF0A84FF),
                        size: 22,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        isDetailOpen ? 'Galeri' : 'Kamera',
                        style: const TextStyle(
                          color: Color(0xFF0A84FF),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              // Center:
              // - Selection Mode: "X Dipilih"
              // - Grid Mode: Segmented Filter Control
              // - Detail Mode: Media Name & Date
              if (_isSelectionMode && !isDetailOpen)
                Text(
                  _selectedItemIds.isEmpty
                      ? 'Pilih Item'
                      : '${_selectedItemIds.length} Dipilih',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (!isDetailOpen)
                CupertinoSlidingSegmentedControl<_GalleryMediaFilter>(
                  groupValue: _activeFilter,
                  backgroundColor: const Color(0xFF2C2C2E),
                  thumbColor: const Color(0xFF48484A),
                  children: {
                    for (final filter in _GalleryMediaFilter.values)
                      filter: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 5,
                        ),
                        child: Text(
                          filter.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  },
                  onValueChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _activeFilter = val;
                        _fullscreenIndex = null;
                        _selectedItemIds.clear();
                      });
                    }
                  },
                )
              else if (activeItem != null)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      activeItem.isVideo ? 'Video Portal' : activeItem.filterName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDateShort(activeItem.capturedAt),
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),

              // Right button / info:
              // - Selection Mode: "Pilih Semua" / "Batal Semua"
              // - Grid Mode: "Pilih" button if items > 0, else "0 Item"
              // - Detail Mode: Index counter "X dari Y"
              if (_isSelectionMode && !isDetailOpen)
                CupertinoButton(
                  key: const Key('gallery_select_all_button'),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  minimumSize: Size.zero,
                  onPressed: () => _toggleSelectAll(items),
                  child: Text(
                    _selectedItemIds.length == items.length && items.isNotEmpty
                        ? 'Batal Semua'
                        : 'Pilih Semua',
                    style: const TextStyle(
                      color: Color(0xFF0A84FF),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              else if (!isDetailOpen)
                if (items.isNotEmpty)
                  CupertinoButton(
                    key: const Key('gallery_select_mode_button'),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    minimumSize: Size.zero,
                    onPressed: _toggleSelectionMode,
                    child: const Text(
                      'Pilih',
                      style: TextStyle(
                        color: Color(0xFF0A84FF),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                else
                  const Text(
                    '0 Item',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  )
              else
                Text(
                  '${_fullscreenIndex! + 1} dari ${items.length}',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIosGridContent(List<SavedPhotoItem> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.photo_on_rectangle,
              color: Colors.white24,
              size: 54,
            ),
            const SizedBox(height: 14),
            Text(
              _activeFilter == _GalleryMediaFilter.videos
                  ? 'Belum Ada Video'
                  : 'Belum Ada Foto atau Video',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Foto dan video yang Anda ambil akan tampil di sini.',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final topPadding = MediaQuery.of(context).padding.top + 64;
    final bottomPadding = _isSelectionMode
        ? MediaQuery.of(context).padding.bottom + 84
        : 24.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth >= 900
        ? 5
        : (screenWidth >= 600 ? 4 : 3);

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(12, topPadding, 12, bottomPadding),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1.25,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildIosGridTile(item, index);
      },
    );
  }

  Widget _buildIosGridTile(SavedPhotoItem item, int index) {
    final previewPath = item.thumbnailPath ?? item.filePath;
    final previewFile = File(previewPath);
    final canRenderImage =
        previewFile.existsSync() &&
        (previewPath.toLowerCase().endsWith('.png') ||
            previewPath.toLowerCase().endsWith('.gif') ||
            previewPath.toLowerCase().endsWith('.jpg'));
    final isSelected = _selectedItemIds.contains(item.id);

    return GestureDetector(
      key: Key('gallery_tile_${item.id}'),
      onTap: () {
        if (_isSelectionMode) {
          _toggleItemSelection(item.id);
        } else {
          _openFullscreen(index);
        }
      },
      onLongPress: () {
        if (!_isSelectionMode) {
          setState(() {
            _isSelectionMode = true;
            _selectedItemIds.add(item.id);
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: _isSelectionMode && isSelected
              ? Border.all(color: const Color(0xFF0A84FF), width: 2.5)
              : null,
        ),
        child: ClipRRect(
          borderRadius:
              BorderRadius.circular(_isSelectionMode && isSelected ? 7.5 : 10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: const Color(0xFF1C1C1E),
                child: canRenderImage
                    ? Image.file(
                        previewFile,
                        fit: BoxFit.cover,
                      )
                    : const Center(
                        child: Icon(
                          CupertinoIcons.videocam_fill,
                          color: Colors.white38,
                          size: 32,
                        ),
                      ),
              ),

              // Selection tint overlay
              if (_isSelectionMode && isSelected)
                Container(
                  color: const Color(0xFF0A84FF).withValues(alpha: 0.22),
                ),

              // Subtle bottom gradient for badges (iOS Photos style)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 32,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.68),
                      ],
                    ),
                  ),
                ),
              ),

              // Video indicator + duration (bottom-left, iOS style)
              if (item.isVideo)
                Positioned(
                  left: 7,
                  right: 32,
                  bottom: 5,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        CupertinoIcons.play_fill,
                        color: Colors.white,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(item.durationSeconds),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              else if (item.triggerSource == CaptureTriggerSource.autoBlink)
                const Positioned(
                  left: 7,
                  bottom: 5,
                  child: Icon(
                    CupertinoIcons.eye_fill,
                    color: Color(0xFF00F5D4),
                    size: 13,
                  ),
                ),

              // Top-Right: Quick Delete Trash Button (Normal Mode) OR Selection Checkmark (Selection Mode)
              if (!_isSelectionMode)
                Positioned(
                  top: 5,
                  right: 5,
                  child: GestureDetector(
                    key: Key('delete_tile_${item.id}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _confirmAndDelete(item),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.62),
                        border: Border.all(
                          color: Colors.white24,
                          width: 0.8,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          CupertinoIcons.trash,
                          color: Color(0xFFFF453A),
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                )
              else
                Positioned(
                  top: 6,
                  right: 6,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? const Color(0xFF0A84FF)
                          : Colors.black.withValues(alpha: 0.45),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF0A84FF)
                            : Colors.white70,
                        width: isSelected ? 0 : 1.5,
                      ),
                    ),
                    child: isSelected
                        ? const Center(
                            child: Icon(
                              CupertinoIcons.checkmark,
                              color: Colors.white,
                              size: 14,
                            ),
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullscreenViewer(List<SavedPhotoItem> items) {
    return PageView.builder(
      controller: _pageController,
      itemCount: items.length,
      onPageChanged: (idx) {
        setState(() {
          _fullscreenIndex = idx;
        });
      },
      itemBuilder: (context, index) {
        final item = items[index];
        final file = File(item.filePath);
        final isPlayableImage =
            file.existsSync() &&
            (item.filePath.toLowerCase().endsWith('.png') ||
                item.filePath.toLowerCase().endsWith('.gif'));

        return Padding(
          padding: const EdgeInsets.only(top: 64, bottom: 72),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isPlayableImage)
                InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Image.file(
                    file,
                    fit: BoxFit.contain,
                  ),
                )
              else if (item.thumbnailPath != null &&
                  File(item.thumbnailPath!).existsSync())
                Image.file(
                  File(item.thumbnailPath!),
                  fit: BoxFit.contain,
                )
              else
                const Icon(
                  CupertinoIcons.videocam_circle_fill,
                  color: Colors.white38,
                  size: 84,
                ),

              // If this is an MP4 video, show an iOS-style frosted Play pill
              if (item.isVideo && item.filePath.toLowerCase().endsWith('.mp4'))
                GestureDetector(
                  onTap: () => _openVideoExternally(item),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(color: Colors.white30),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              CupertinoIcons.play_circle_fill,
                              color: Colors.white,
                              size: 28,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Putar Video (${_formatDuration(item.durationSeconds)})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIosBottomToolbar(SavedPhotoItem item) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
            top: 10,
            bottom: MediaQuery.of(context).padding.bottom + 12,
            left: 24,
            right: 24,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF121214).withValues(alpha: 0.78),
            border: const Border(
              top: BorderSide(color: Colors.white12, width: 0.5),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Share Button
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () => _shareMedia(item),
                child: const Icon(
                  CupertinoIcons.share,
                  color: Color(0xFF0A84FF),
                  size: 23,
                ),
              ),

              // Center Tag Pill
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.isVideo
                          ? CupertinoIcons.videocam_fill
                          : (item.triggerSource ==
                                    CaptureTriggerSource.autoBlink
                                ? CupertinoIcons.eye_fill
                                : CupertinoIcons.camera_fill),
                      color: const Color(0xFF00F5D4),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${item.triggerSource.label} • ${item.portalModeLabel}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Delete Button
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () => _confirmAndDelete(item),
                child: const Icon(
                  CupertinoIcons.trash,
                  color: Color(0xFFFF453A),
                  size: 23,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
