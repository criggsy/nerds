import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:nerds/models/sticker_data.dart';
import 'package:nerds/services/server_sticker_cache_service.dart';
import 'package:nerds/services/user_pack_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ImageStickerEditorScreen extends StatefulWidget {
  const ImageStickerEditorScreen({super.key});

  @override
  State<ImageStickerEditorScreen> createState() => _ImageStickerEditorScreenState();
}

class _ImageStickerEditorScreenState extends State<ImageStickerEditorScreen> {
  final ImagePicker _picker = ImagePicker();
  final GlobalKey _captureKey = GlobalKey();

  XFile? _selectedImage;
  Size? _selectedImagePixelSize;
  Size? _stageSize;
  Size? _displayedImageSize;
  final List<_PlacedSticker> _placedStickers = <_PlacedSticker>[];
  String? _selectedStickerUid;
  bool _loadingServer = false;
  bool _busy = false;
  bool _hideSelectionChromeForExport = false;

  @override
  void dispose() {
    _clearPlacedStickers();
    super.dispose();
  }

  void _clearPlacedStickers() {
    for (final s in _placedStickers) {
      s.controller.dispose();
    }
    _placedStickers.clear();
    _selectedStickerUid = null;
  }

  Future<void> _pickBaseImage() async {
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    final pixelSize = await _readImagePixelSize(image);
    if (!mounted) return;
    setState(() {
      _selectedImage = image;
      _selectedImagePixelSize = pixelSize;
      _clearPlacedStickers();
    });
  }

  Future<void> _pickSticker() async {
    setState(() => _loadingServer = true);
    List<StickerPackGroup> serverGroups = [];
    String? serverError;
    try {
      StickerData? stickerData =
          await ServerStickerCacheService.instance.loadCachedStickerData();
      // Startup refresh runs in background; if user opens picker before it
      // completes, force a one-shot sync here so the menu can populate now.
      if (stickerData == null) {
        await ServerStickerCacheService.instance.refreshFromServer();
        stickerData = await ServerStickerCacheService.instance.loadCachedStickerData();
      }
      if (stickerData != null) {
        serverGroups = await _serverStickerGroups(stickerData);
        if (serverGroups.isEmpty) {
          // Manifest exists but files may be missing/incomplete; retry once.
          await ServerStickerCacheService.instance.refreshFromServer();
          final retryData =
              await ServerStickerCacheService.instance.loadCachedStickerData();
          if (retryData != null) {
            serverGroups = await _serverStickerGroups(retryData);
          }
        }
        if (serverGroups.isEmpty) {
          serverError =
              'Offline server cache is empty. Connect to internet and reopen the app to sync.';
        }
      } else {
        serverError =
            'No offline server stickers yet. Connect to internet and reopen the app to sync.';
      }
    } catch (e) {
      serverError = '$e';
    } finally {
      if (mounted) {
        setState(() => _loadingServer = false);
      }
    }

    if (!mounted) return;
    final localGroups = _localStickerGroups();

    final picked = await showModalBottomSheet<StickerChoice>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _StickerPickerSheet(
          serverGroups: serverGroups,
          localGroups: localGroups,
          serverError: serverError,
        );
      },
    );

    if (picked == null || !mounted) return;
    setState(() {
      final stage = _stageSize;
      final offsetX = ((stage?.width ?? 280) / 2) - 70;
      final offsetY = ((stage?.height ?? 280) / 2) - 70;
      final controller = TransformationController();
      controller.value = Matrix4.identity()
        ..translateByDouble(offsetX, offsetY, 0.0, 1.0)
        ..scaleByDouble(1.0, 1.0, 1.0, 1.0);
      _placedStickers.add(
        _PlacedSticker(
          uid: '${DateTime.now().microsecondsSinceEpoch}_${_placedStickers.length}',
          sticker: picked,
          controller: controller,
        ),
      );
      _selectedStickerUid = _placedStickers.last.uid;
    });
  }

  Future<List<StickerPackGroup>> _serverStickerGroups(StickerData data) async {
    final resolved = <StickerPackGroup>[];
    for (final pack in data.stickerPacks ?? <StickerPacks>[]) {
      final id = pack.identifier;
      if (id == null || id.isEmpty) continue;
      final picks = <StickerChoice>[];
      for (final sticker in pack.stickers ?? <Stickers>[]) {
        final file = sticker.imageFile;
        if (file == null || file.isEmpty) continue;
        final localPath =
            await ServerStickerCacheService.instance.localAssetPath(id, file);
        if (!File(localPath).existsSync()) continue;
        picks.add(StickerChoice(
          id: '$id::$file',
          label: pack.name ?? 'Server sticker',
          imagePath: localPath,
          isNetwork: false,
        ));
      }
      if (picks.isNotEmpty) {
        resolved.add(StickerPackGroup(
          title: pack.name ?? 'Server pack',
          stickers: picks,
        ));
      }
    }
    return resolved;
  }

  List<StickerPackGroup> _localStickerGroups() {
    final groups = <StickerPackGroup>[];
    for (final pack in UserPackService.instance.packs) {
      final picks = <StickerChoice>[];
      for (var i = 0; i < pack.stickerPaths.length; i++) {
        final path = pack.stickerPaths[i];
        picks.add(StickerChoice(
          id: '${pack.id}::$i',
          label: pack.name,
          imagePath: path,
          isNetwork: false,
        ));
      }
      if (picks.isNotEmpty) {
        groups.add(StickerPackGroup(
          title: pack.name,
          stickers: picks,
        ));
      }
    }
    return groups;
  }

  int _indexByUid(String uid) {
    for (var i = 0; i < _placedStickers.length; i++) {
      if (_placedStickers[i].uid == uid) return i;
    }
    return -1;
  }

  void _selectStickerByUid(String uid, {bool bringToFront = true}) {
    final index = _indexByUid(uid);
    if (index < 0) return;
    setState(() {
      if (bringToFront && index != _placedStickers.length - 1) {
        final s = _placedStickers.removeAt(index);
        _placedStickers.add(s);
      }
      _selectedStickerUid = uid;
    });
  }

  void _flipStickerByUid(String uid) {
    final index = _indexByUid(uid);
    if (index < 0) return;
    setState(() => _placedStickers[index].flipped = !_placedStickers[index].flipped);
  }

  Future<File?> _exportToTemp() async {
    final devicePixelRatio = View.of(context).devicePixelRatio;
    if (mounted) {
      setState(() => _hideSelectionChromeForExport = true);
      await WidgetsBinding.instance.endOfFrame;
    }
    try {
    final boundary = _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final sourceSize = _selectedImagePixelSize;
    final displayed = _displayedImageSize;
    final exportPixelRatio =
        (sourceSize == null ||
                displayed == null ||
                displayed.width == 0 ||
                displayed.height == 0)
            ? devicePixelRatio
            : math.max(
                devicePixelRatio,
                math.min(
                  sourceSize.width / displayed.width,
                  sourceSize.height / displayed.height,
                ),
              );
    final image = await boundary.toImage(pixelRatio: exportPixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;
    var png = bytes.buffer.asUint8List();

    // Crop letterbox padding (from BoxFit.contain in full-stage editor) so the
    // exported image matches the visible photo area without black borders.
    final stage = _stageSize;
    if (stage != null &&
        displayed != null &&
        displayed.width > 0 &&
        displayed.height > 0 &&
        stage.width > 0 &&
        stage.height > 0) {
      final decoded = img.decodePng(png);
      if (decoded != null) {
        final scaleX = decoded.width / stage.width;
        final scaleY = decoded.height / stage.height;
        final left = ((stage.width - displayed.width) / 2 * scaleX).round();
        final top = ((stage.height - displayed.height) / 2 * scaleY).round();
        final cropW = (displayed.width * scaleX).round();
        final cropH = (displayed.height * scaleY).round();
        final safeLeft = left.clamp(0, decoded.width - 1);
        final safeTop = top.clamp(0, decoded.height - 1);
        final safeW = cropW.clamp(1, decoded.width - safeLeft);
        final safeH = cropH.clamp(1, decoded.height - safeTop);
        final cropped = img.copyCrop(
          decoded,
          x: safeLeft,
          y: safeTop,
          width: safeW,
          height: safeH,
        );
        png = img.encodePng(cropped);
      }
    }

    final tempDir = await getTemporaryDirectory();
    final file = File(
      p.join(tempDir.path, 'sticker_edit_${DateTime.now().millisecondsSinceEpoch}.png'),
    );
    await file.writeAsBytes(png);
    return file;
    } finally {
      if (mounted) {
        setState(() => _hideSelectionChromeForExport = false);
      }
    }
  }

  Future<Size?> _readImagePixelSize(XFile image) async {
    try {
      final bytes = await image.readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      return Size(decoded.width.toDouble(), decoded.height.toDouble());
    } catch (_) {
      return null;
    }
  }

  Size _fitContainSize(Size source, Size box) {
    if (source.width <= 0 ||
        source.height <= 0 ||
        box.width <= 0 ||
        box.height <= 0) {
      return const Size(1, 1);
    }
    final scale = math.min(box.width / source.width, box.height / source.height);
    return Size(source.width * scale, source.height * scale);
  }

  Future<void> _saveToGallery() async {
    if (_selectedImage == null) return;
    setState(() => _busy = true);
    try {
      final file = await _exportToTemp();
      if (file == null) throw StateError('Could not create image');
      await Gal.putImage(file.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to gallery')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareImage() async {
    if (_selectedImage == null) return;
    setState(() => _busy = true);
    try {
      final file = await _exportToTemp();
      if (file == null) throw StateError('Could not create image');
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasBase = _selectedImage != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Sticker photo editor')),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: hasBase
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        // Use the full editor area as the interaction stage so
                        // pinch/rotate can continue even when fingers move outside
                        // the visible image bounds.
                        final stageSize = constraints.biggest;
                        final sourceSize = _selectedImagePixelSize;
                        final displayed = (sourceSize == null)
                            ? stageSize
                            : _fitContainSize(sourceSize, stageSize);
                        if (_stageSize != stageSize) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() => _stageSize = stageSize);
                          });
                        }
                        if (_displayedImageSize != displayed) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() => _displayedImageSize = displayed);
                          });
                        }
                        return Center(
                          child: SizedBox(
                            width: stageSize.width,
                            height: stageSize.height,
                            child: RepaintBoundary(
                              key: _captureKey,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: Image.file(
                                        File(_selectedImage!.path),
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    for (var i = 0; i < _placedStickers.length; i++)
                                      Positioned.fill(
                                        child: _InteractiveSticker(
                                          key: ValueKey(_placedStickers[i].uid),
                                          controller: _placedStickers[i].controller,
                                          sticker: _placedStickers[i].sticker,
                                          isFlipped: _placedStickers[i].flipped,
                                          isSelected:
                                              !_hideSelectionChromeForExport &&
                                              _placedStickers[i].uid == _selectedStickerUid,
                                          onSelectSticker: () =>
                                              _selectStickerByUid(_placedStickers[i].uid),
                                          onFlipSticker: () =>
                                              _flipStickerByUid(_placedStickers[i].uid),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    )
                  : Center(
                      child: Text(
                        'Pick a photo from your gallery to start.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _pickBaseImage,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose photo'),
                ),
                FilledButton.tonalIcon(
                  onPressed: (!hasBase || _busy || _loadingServer) ? null : _pickSticker,
                  icon: _loadingServer
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.emoji_emotions_outlined),
                  label: const Text('Add sticker'),
                ),
                FilledButton.icon(
                  onPressed: (!hasBase || _busy) ? null : _saveToGallery,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Save'),
                ),
                FilledButton.icon(
                  onPressed: (!hasBase || _busy) ? null : _shareImage,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InteractiveSticker extends StatefulWidget {
  const _InteractiveSticker({
    super.key,
    required this.controller,
    required this.sticker,
    required this.isFlipped,
    required this.isSelected,
    required this.onSelectSticker,
    required this.onFlipSticker,
  });

  final TransformationController controller;
  final StickerChoice sticker;
  final bool isFlipped;
  final bool isSelected;
  final VoidCallback onSelectSticker;
  final VoidCallback onFlipSticker;

  @override
  State<_InteractiveSticker> createState() => _InteractiveStickerState();
}

class _InteractiveStickerState extends State<_InteractiveSticker> {
  Matrix4 _start = Matrix4.identity();
  Offset _startFocal = Offset.zero;
  bool _gestureActive = false;
  final Set<int> _activePointers = <int>{};
  Offset? _firstTouchDown;
  static const double _minScale = 0.35;
  static const double _maxScale = 6.0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (_activePointers.isEmpty) {
          _firstTouchDown = event.localPosition;
        }
        _activePointers.add(event.pointer);
      },
      onPointerUp: (event) {
        _activePointers.remove(event.pointer);
        if (_activePointers.isEmpty) {
          _firstTouchDown = null;
        }
      },
      onPointerCancel: (event) {
        _activePointers.remove(event.pointer);
        if (_activePointers.isEmpty) {
          _firstTouchDown = null;
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onScaleStart: (details) {
          final anchor = _firstTouchDown ?? details.localFocalPoint;
          _gestureActive = _isPointOnSticker(anchor);
          if (!_gestureActive) return;
          widget.onSelectSticker();
          _start = widget.controller.value.clone();
          _startFocal = details.localFocalPoint;
        },
        onScaleUpdate: (details) {
          if (!_gestureActive) return;
          final pointerCount = _activePointers.length;
          if (pointerCount <= 1) {
            // One-finger gesture = drag.
            final delta = details.localFocalPoint - _startFocal;
            widget.controller.value = _start.clone()
              ..translateByDouble(delta.dx, delta.dy, 0.0, 1.0);
            return;
          }

          // Multi-touch gesture = scale/rotate around the sticker center so it
          // stays anchored instead of drifting across the canvas.
          const centerLocal = Offset(70, 70); // center of the 140x140 sticker box
          final centerWorld = MatrixUtils.transformPoint(_start, centerLocal);
          final startScale = _currentScaleFromMatrix(_start);
          final targetScale =
              (startScale * details.scale).clamp(_minScale, _maxScale).toDouble();
          final relativeScale = targetScale / startScale;

          final delta = Matrix4.identity()
            ..translateByDouble(centerWorld.dx, centerWorld.dy, 0.0, 1.0)
            ..rotateZ(details.rotation)
            ..scaleByDouble(relativeScale, relativeScale, 1.0, 1.0)
            ..translateByDouble(-centerWorld.dx, -centerWorld.dy, 0.0, 1.0);

          widget.controller.value = delta * _start;
        },
        onScaleEnd: (_) {
          _gestureActive = false;
          if (_activePointers.isEmpty) {
            _firstTouchDown = null;
          }
        },
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            return Transform(
              transform: widget.controller.value,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (widget.isSelected) {
                        widget.onFlipSticker();
                      } else {
                        widget.onSelectSticker();
                      }
                    },
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.diagonal3Values(
                        widget.isFlipped ? -1 : 1,
                        1,
                        1,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: widget.isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: widget.sticker.isNetwork
                              ? Image.network(
                                  widget.sticker.imagePath,
                                  fit: BoxFit.contain,
                                )
                              : Image.file(
                                  File(widget.sticker.imagePath),
                                  fit: BoxFit.contain,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  double _currentScaleFromMatrix(Matrix4 m) {
    final sx =
        math.sqrt((m.storage[0] * m.storage[0]) + (m.storage[1] * m.storage[1]));
    if (sx == 0) return 1.0;
    return sx;
  }

  bool _isPointOnSticker(Offset point) {
    final m = widget.controller.value;
    final p1 = MatrixUtils.transformPoint(m, Offset.zero);
    final p2 = MatrixUtils.transformPoint(m, const Offset(140, 0));
    final p3 = MatrixUtils.transformPoint(m, const Offset(0, 140));
    final p4 = MatrixUtils.transformPoint(
      m,
      const Offset(140, 140),
    );
    final bounds = Rect.fromLTRB(
      math.min(math.min(p1.dx, p2.dx), math.min(p3.dx, p4.dx)),
      math.min(math.min(p1.dy, p2.dy), math.min(p3.dy, p4.dy)),
      math.max(math.max(p1.dx, p2.dx), math.max(p3.dx, p4.dx)),
      math.max(math.max(p1.dy, p2.dy), math.max(p3.dy, p4.dy)),
    );
    return bounds.contains(point);
  }
}

class _StickerPickerSheet extends StatelessWidget {
  const _StickerPickerSheet({
    required this.serverGroups,
    required this.localGroups,
    required this.serverError,
  });

  final List<StickerPackGroup> serverGroups;
  final List<StickerPackGroup> localGroups;
  final String? serverError;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const SizedBox(height: 8),
            const TabBar(
              tabs: [
                Tab(text: 'Server'),
                Tab(text: 'My packs'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _StickerPackList(
                    groups: serverGroups,
                    emptyText: serverError ?? 'No server stickers available.',
                  ),
                  _StickerPackList(
                    groups: localGroups,
                    emptyText: 'You have no local stickers yet.',
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

class _StickerPackList extends StatefulWidget {
  const _StickerPackList({
    required this.groups,
    required this.emptyText,
  });

  final List<StickerPackGroup> groups;
  final String emptyText;

  @override
  State<_StickerPackList> createState() => _StickerPackListState();
}

class _StickerPackListState extends State<_StickerPackList> {
  StickerPackGroup? _openGroup;

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) {
      return Center(child: Text(widget.emptyText));
    }
    if (_openGroup == null) {
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: widget.groups.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final group = widget.groups[index];
          final thumb = group.stickers.first;
          return Card(
            child: ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: thumb.isNetwork
                      ? Image.network(thumb.imagePath, fit: BoxFit.cover)
                      : Image.file(File(thumb.imagePath), fit: BoxFit.cover),
                ),
              ),
              title: Text(group.title),
              subtitle: Text('${group.stickers.length} stickers'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => _openGroup = group),
            ),
          );
        },
      );
    }

    final group = _openGroup!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _openGroup = null),
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to packs',
              ),
              Expanded(
                child: Text(
                  group.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: group.stickers.length,
            itemBuilder: (context, stickerIndex) {
              final sticker = group.stickers[stickerIndex];
              return InkWell(
                onTap: () => Navigator.of(context).pop(sticker),
                borderRadius: BorderRadius.circular(8),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: sticker.isNetwork
                        ? Image.network(sticker.imagePath, fit: BoxFit.contain)
                        : Image.file(File(sticker.imagePath),
                            fit: BoxFit.contain),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class StickerChoice {
  const StickerChoice({
    required this.id,
    required this.label,
    required this.imagePath,
    required this.isNetwork,
  });

  final String id;
  final String label;
  final String imagePath;
  final bool isNetwork;
}

class StickerPackGroup {
  const StickerPackGroup({
    required this.title,
    required this.stickers,
  });

  final String title;
  final List<StickerChoice> stickers;
}

class _PlacedSticker {
  _PlacedSticker({
    required this.uid,
    required this.sticker,
    required this.controller,
  });

  final String uid;
  final StickerChoice sticker;
  final TransformationController controller;
  bool flipped = false;
}
