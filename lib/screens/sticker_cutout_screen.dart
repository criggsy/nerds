import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:nerds/utils/sticker_cutout/mask_image_ops.dart';
import 'package:nerds/widgets/rotatable_interactive_viewer.dart';

enum _EditorMode {
  /// Flood-fill from tap (color-connected regions).
  tapFill,

  /// Paint mask on / off freehand.
  brush,
}

enum _TapVariant { add, remove }

enum _BrushVariant { add, remove }

/// On-device cutout: tap-connected flood fill from seed color, then brush refine.
/// Draft quality depends on photo (similar colors bleed); refinement fixes edges.
class StickerCutoutScreen extends StatefulWidget {
  final String imagePath;

  const StickerCutoutScreen({super.key, required this.imagePath});

  @override
  State<StickerCutoutScreen> createState() => _StickerCutoutScreenState();
}

class _StickerCutoutScreenState extends State<StickerCutoutScreen> {
  /// Set to `true` locally to trace match tolerance (canvas drag + slider).
  /// Run `flutter logs` or filter Logcat by `StickerCutout` while reproducing.
  static const bool _debugMatchTolerance = false;

  /// Moves in current pointer gesture (reset on down); only used when [_debugMatchTolerance].
  int _debugTolMoveCount = 0;

  img.Image? _image;
  Uint8List? _mask;

  /// Engine [ui.Image] for the photo — painted with [paintImage] to avoid hairline gaps.
  ui.Image? _sourceUiImage;

  /// Bumps whenever the mask overlay should repaint ([CustomPaint] vs async [Image.memory]).
  int _highlightSeq = 0;
  bool _loading = true;
  String? _loadError;

  _EditorMode _mode = _EditorMode.tapFill;
  _TapVariant _tapVariant = _TapVariant.add;
  _BrushVariant _brushVariant = _BrushVariant.add;
  double _tolerance = 36;
  double _brushRadius = 18;

  /// Local position within the image area while brushing (for cursor ring).
  Offset? _brushCursorLocal;

  /// Tap-fill: seed position; slide horizontally before release to change tolerance.
  Offset? _tapFillSeedLocal;
  double _tapPanBaselineTolerance = 36;
  double _tapPanAccumDx = 0;

  /// Mask copy before the current tap-fill gesture (restore + refill for live preview).
  Uint8List? _tapFillMaskBeforeGesture;

  /// [LayoutBuilder] size for the fitted image during an active tap-fill gesture (slider + drag).
  Size? _tapFillGestureRenderSize;

  static const double _toleranceMin = 8;
  static const double _toleranceMax = 80;

  /// Logical pixels of horizontal drag per +1 match tolerance (slider units).
  static const double _tapToleranceDragPixelsPerUnit = 3.5;

  /// When true, [RotatableInteractiveViewer] receives gestures (pinch zoom / pan / rotate). When false, mask gestures are active.
  bool _viewAdjustMode = false;

  /// Snapshots of the mask before each discrete edit (tap fill or brush stroke).
  final List<Uint8List> _maskUndoStack = [];
  static const int _maxUndoDepth = 15;

  late final TransformationController _viewerController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sourceUiImage?.dispose();
    _viewerController.dispose();
    super.dispose();
  }

  /// Builds [ui.Image] from the same [img.Image] pixels (no PNG round-trip).
  /// PNG encode/decode can yield a [ui.Image] whose width/height differ by 1px from
  /// [img.Image], which breaks aspect layout vs [Canvas.drawImageRect] and shows checker
  /// inside the fitted rect.
  static Future<ui.Image> _imgToUiImage(img.Image image) async {
    final w = image.width;
    final h = image.height;
    final rgba = Uint8List(w * h * 4);
    var o = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        rgba[o++] = p.r.toInt();
        rgba[o++] = p.g.toInt();
        rgba[o++] = p.b.toInt();
        rgba[o++] = p.a.toInt();
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      w,
      h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final decoded = await decodeImageWithBakedOrientation(bytes);
      if (decoded == null) {
        setState(() {
          _loading = false;
          _loadError = 'Could not decode image';
        });
        return;
      }
      final work = maybeDownscale(decoded, maxSide: 900);
      final w = work.width;
      final h = work.height;
      final mask = Uint8List(w * h);
      final srcUi = await _imgToUiImage(work);
      if (!mounted) {
        srcUi.dispose();
        return;
      }
      setState(() {
        _clearTapFillSliderPreviewContext();
        _image = work;
        _mask = mask;
        _maskUndoStack.clear();
        _sourceUiImage?.dispose();
        _sourceUiImage = srcUi;
        _highlightSeq++;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  void _refreshPreview() {
    final im = _image;
    final m = _mask;
    if (im == null || m == null) return;
    setState(() {
      _highlightSeq++;
    });
  }

  void _pushUndoSnapshot() {
    final m = _mask;
    if (m == null) return;
    _maskUndoStack.add(Uint8List.fromList(m));
    while (_maskUndoStack.length > _maxUndoDepth) {
      _maskUndoStack.removeAt(0);
    }
  }

  void _undoLastEdit() {
    if (_maskUndoStack.isEmpty || _image == null) return;
    setState(() {
      _mask = _maskUndoStack.removeLast();
      _highlightSeq++;
    });
  }

  /// Sets every mask pixel to foreground (full sticker / no hole).
  void _maskEntireImage() {
    if (_viewAdjustMode) return;
    final m = _mask;
    if (m == null || _image == null) return;
    _abortTapFillGesture(restoreMask: true);
    _pushUndoSnapshot();
    m.fillRange(0, m.length, 255);
    setState(() => _highlightSeq++);
  }

  /// Brush: undo snapshot is pushed on pointer down (see [Listener]).
  void _onBrushPointerDown(PointerDownEvent e) {
    if (_viewAdjustMode || _mode != _EditorMode.brush) return;
    _abortTapFillGesture(restoreMask: true);
    _pushUndoSnapshot();
  }

  /// Clears in-memory tap-fill gesture locals (no [setState]). Used when replacing the image/mask.
  void _clearTapFillSliderPreviewContext() {
    _tapFillSeedLocal = null;
    _tapFillGestureRenderSize = null;
    _tapFillMaskBeforeGesture = null;
  }

  void _tolD(String message) {
    if (!_debugMatchTolerance) return;
    // ignore: avoid_print — intentional for adb/logcat (debugPrint is throttled).
    print('[StickerCutout/tolerance] $message');
  }

  /// [imageLocal] is inside the fitted image rect (0…[renderSize]).
  void _onTapFillPointerDownAt(Offset imageLocal, Size renderSize) {
    if (_viewAdjustMode || _mode != _EditorMode.tapFill) return;
    final m = _mask;
    setState(() {
      _debugTolMoveCount = 0;
      _tapPanBaselineTolerance = _tolerance;
      _tapPanAccumDx = 0;
      _tapFillSeedLocal = imageLocal;
      _tapFillGestureRenderSize = renderSize;
      _tapFillMaskBeforeGesture = m == null ? null : Uint8List.fromList(m);
    });
    _tolD(
      'pointerDown accepted seed=$imageLocal baselineTol=$_tapPanBaselineTolerance '
      'maskSnapshot=${_tapFillMaskBeforeGesture != null}',
    );
  }

  void _onTapFillPointerMove(PointerMoveEvent e, Size renderSize) {
    if (_viewAdjustMode || _mode != _EditorMode.tapFill) return;
    if (_tapFillSeedLocal == null) return;
    _tapPanAccumDx += e.delta.dx;
    final next = (_tapPanBaselineTolerance +
            _tapPanAccumDx / _tapToleranceDragPixelsPerUnit)
        .clamp(_toleranceMin, _toleranceMax);
    final backup = _tapFillMaskBeforeGesture;
    final seed = _tapFillSeedLocal;
    final im = _image;
    final mask = _mask;
    if (backup == null || seed == null || im == null || mask == null) {
      return;
    }
    mask.setAll(0, backup);
    _runFloodFillAt(seed, renderSize, tolerance: next.round());
    _debugTolMoveCount++;
    if (_debugTolMoveCount == 1) {
      _tolD(
        'firstPointerMove delta=${e.delta.dx.toStringAsFixed(2)},'
        ' nextTol=$next renderSize=$renderSize',
      );
    }
    setState(() {
      _tolerance = next;
      _highlightSeq++;
    });
  }

  void _onTapFillPointerUp(Size renderSize) {
    _tolD('pointerUp moves=$_debugTolMoveCount');
    if (_mode != _EditorMode.tapFill) return;
    _finishTapFillGesture(renderSize);
  }

  void _onTapFillPointerCancel() {
    _tolD('pointerCancel moves=$_debugTolMoveCount');
    if (_mode != _EditorMode.tapFill) return;
    _abortTapFillGesture(restoreMask: true);
  }

  /// Same [BoxFit.contain] sizing as [AspectRatio] / [RenderAspectRatio] (width-first, then clamp height).
  Size _boxFitContainSize(Size max, double iw, double ih) {
    final ar = iw / ih;
    var w = max.width;
    var h = w / ar;
    if (h > max.height) {
      h = max.height;
      w = h * ar;
    }
    return Size(w, h);
  }

  /// [local] is in the fitted display rect (same aspect as the bitmap).
  /// [dispSize] is that rect’s size. Gestures must live inside [RotatableInteractiveViewer]'s child.
  ///
  /// Mutates [_mask] in place. Does not touch undo history.
  void _runFloodFillAt(Offset local, Size dispSize, {int? tolerance}) {
    final im = _image;
    final mask = _mask;
    if (im == null || mask == null) return;
    final ix =
        (local.dx / dispSize.width * im.width).floor().clamp(0, im.width - 1);
    final iy = (local.dy / dispSize.height * im.height)
        .floor()
        .clamp(0, im.height - 1);

    final add = _tapVariant == _TapVariant.add;
    floodFillFromTap(
      image: im,
      mask: mask,
      startX: ix,
      startY: iy,
      tolerance: tolerance ?? _tolerance.round(),
      addToMask: add,
    );
  }

  void _applyBrush(Offset local, Size dispSize) {
    final im = _image;
    final mask = _mask;
    if (im == null || mask == null) return;
    final cx = local.dx / dispSize.width * im.width;
    final cy = local.dy / dispSize.height * im.height;
    final scale = im.width / dispSize.width;
    final rImage = _brushRadius * scale;

    final fg = _brushVariant == _BrushVariant.add;
    paintBrushCircle(
      width: im.width,
      height: im.height,
      mask: mask,
      cx: cx,
      cy: cy,
      radius: rImage,
      foreground: fg,
    );
    _refreshPreview();
  }

  void _finishTapFillGesture(Size renderSize) {
    final seed = _tapFillSeedLocal;
    final backup = _tapFillMaskBeforeGesture;
    final im = _image;
    final mask = _mask;
    if (seed == null || backup == null || im == null || mask == null) {
      setState(() {
        _tapFillSeedLocal = null;
        _tapFillGestureRenderSize = null;
        _tapFillMaskBeforeGesture = null;
      });
      return;
    }

    mask.setAll(0, backup);
    _runFloodFillAt(seed, renderSize);
    _maskUndoStack.add(Uint8List.fromList(backup));
    while (_maskUndoStack.length > _maxUndoDepth) {
      _maskUndoStack.removeAt(0);
    }
    setState(() {
      _tapFillSeedLocal = null;
      _tapFillGestureRenderSize = null;
      _tapFillMaskBeforeGesture = null;
      _highlightSeq++;
    });
  }

  void _abortTapFillGesture({required bool restoreMask}) {
    final backup = _tapFillMaskBeforeGesture;
    if (!restoreMask || backup == null || _mask == null || _image == null) {
      setState(() {
        _tapFillSeedLocal = null;
        _tapFillGestureRenderSize = null;
        _tapFillMaskBeforeGesture = null;
      });
      return;
    }
    _mask!.setAll(0, backup);
    setState(() {
      _tapFillSeedLocal = null;
      _tapFillGestureRenderSize = null;
      _tapFillMaskBeforeGesture = null;
      _highlightSeq++;
    });
  }

  bool get _hasForeground => _mask != null && _mask!.any((b) => b > 8);

  Future<void> _save() async {
    if (!_hasForeground || _image == null || _mask == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mark the subject first (tap regions or brush with add mode).',
          ),
        ),
      );
      return;
    }
    final bytes = composeMaskedPng(_image!, _mask!);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.5;
        return AlertDialog(
          title: const Text('Preview'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Transparent areas will stay transparent in your pack (checker '
                  'is only for preview).',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: maxH,
                  width: double.infinity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(painter: _PreviewCheckerPainter()),
                        Center(
                          child: Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back to edit'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Use sticker'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final dir = await getTemporaryDirectory();
    final outPath = p.join(
      dir.path,
      'sticker_cutout_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await File(outPath).writeAsBytes(bytes);
    if (mounted) Navigator.of(context).pop<String>(outPath);
  }

  /// Selected state for compact toolbar icon buttons.
  ButtonStyle _toolbarIconStyle(
    BuildContext context, {
    required bool selected,
  }) {
    final cs = Theme.of(context).colorScheme;
    return IconButton.styleFrom(
      backgroundColor: selected ? cs.primaryContainer : Colors.transparent,
      foregroundColor: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
    );
  }

  /// Add vs remove: one control; [remove] uses [errorContainer] so mode is obvious.
  ButtonStyle _addRemoveToggleStyle(BuildContext context, {required bool remove}) {
    final cs = Theme.of(context).colorScheme;
    if (remove) {
      return IconButton.styleFrom(
        backgroundColor: cs.errorContainer,
        foregroundColor: cs.onErrorContainer,
      );
    }
    return IconButton.styleFrom(
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
    );
  }

  Widget _buildCutoutBottomToolbar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 12,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(28),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.94),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Undo last edit',
                    onPressed: _maskUndoStack.isEmpty ? null : _undoLastEdit,
                    icon: const Icon(Icons.undo),
                  ),
                  IconButton(
                    tooltip: 'Mask entire image',
                    onPressed: _viewAdjustMode || _mask == null
                        ? null
                        : _maskEntireImage,
                    icon: const Icon(Icons.select_all),
                  ),
                  IconButton(
                    tooltip: _mode == _EditorMode.tapFill
                        ? 'Tap regions — tap to use brush'
                        : 'Brush — tap to use tap regions',
                    style: _toolbarIconStyle(context, selected: true),
                    onPressed: () {
                      setState(() {
                        _mode = _mode == _EditorMode.tapFill
                            ? _EditorMode.brush
                            : _EditorMode.tapFill;
                        _brushCursorLocal = null;
                      });
                      _abortTapFillGesture(restoreMask: true);
                    },
                    icon: Icon(
                      _mode == _EditorMode.tapFill
                          ? Icons.touch_app_outlined
                          : Icons.brush_outlined,
                    ),
                  ),
                  if (_mode == _EditorMode.tapFill)
                    IconButton(
                      tooltip: _tapVariant == _TapVariant.add
                          ? 'Adding to mask — tap to remove instead'
                          : 'Removing from mask — tap to add instead',
                      style: _addRemoveToggleStyle(
                        context,
                        remove: _tapVariant == _TapVariant.remove,
                      ),
                      onPressed: () {
                        setState(() {
                          _tapVariant = _tapVariant == _TapVariant.add
                              ? _TapVariant.remove
                              : _TapVariant.add;
                        });
                        _abortTapFillGesture(restoreMask: true);
                      },
                      icon: Icon(
                        _tapVariant == _TapVariant.add
                            ? Icons.add_circle_outline
                            : Icons.remove_circle_outline,
                      ),
                    ),
                  if (_mode == _EditorMode.brush)
                    IconButton(
                      tooltip: _brushVariant == _BrushVariant.add
                          ? 'Brush adds to mask — tap to erase instead'
                          : 'Brush removes from mask — tap to add instead',
                      style: _addRemoveToggleStyle(
                        context,
                        remove: _brushVariant == _BrushVariant.remove,
                      ),
                      onPressed: () {
                        setState(() {
                          _brushVariant = _brushVariant == _BrushVariant.add
                              ? _BrushVariant.remove
                              : _BrushVariant.add;
                        });
                      },
                      icon: Icon(
                        _brushVariant == _BrushVariant.add
                            ? Icons.add_circle_outline
                            : Icons.remove_circle_outline,
                      ),
                    ),
                  IconButton(
                    tooltip: _viewAdjustMode ? 'Edit mask' : 'Pan & zoom',
                    onPressed: () {
                      setState(() {
                        _viewAdjustMode = !_viewAdjustMode;
                        _brushCursorLocal = null;
                      });
                      _abortTapFillGesture(restoreMask: true);
                    },
                    icon: Icon(
                      _viewAdjustMode
                          ? Icons.brush_outlined
                          : Icons.zoom_out_map,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reset view',
                    onPressed: () {
                      _viewerController.value = Matrix4.identity();
                    },
                    icon: const Icon(Icons.fit_screen_outlined),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(
                      Icons.chevron_right,
                      size: 22,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop<String>(null),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(12),
                        minimumSize: const Size(48, 48),
                        shape: const CircleBorder(),
                      ),
                      child: const Icon(Icons.check),
                    ),
                  ),
                ],
              ),
            ),
            if (_mode == _EditorMode.tapFill && _tapFillSeedLocal != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                child: Row(
                  children: [
                    Icon(Icons.tune, size: 20, color: cs.onSurfaceVariant),
                    Expanded(
                      child: Slider(
                        value: _tolerance,
                        min: _toleranceMin,
                        max: _toleranceMax,
                        divisions: 72,
                        label: _tolerance.round().toString(),
                        onChanged: (v) {
                          setState(() {
                            _tolerance = v;
                            final seed = _tapFillSeedLocal;
                            final rs = _tapFillGestureRenderSize;
                            final base = _tapFillMaskBeforeGesture;
                            final im = _image;
                            final mask = _mask;
                            final canPreview = seed != null &&
                                rs != null &&
                                base != null &&
                                im != null &&
                                mask != null;
                            _tolD(
                              'slider value=$v canLivePreview=$canPreview '
                              '(seed=${seed != null} base=${base != null} rs=$rs)',
                            );
                            if (canPreview) {
                              mask.setAll(0, base);
                              _runFloodFillAt(
                                seed,
                                rs,
                                tolerance: v.round(),
                              );
                              _highlightSeq++;
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            if (_mode == _EditorMode.brush)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                child: Row(
                  children: [
                    Icon(Icons.fiber_manual_record,
                        size: 18, color: cs.onSurfaceVariant),
                    Expanded(
                      child: Slider(
                        value: _brushRadius,
                        min: 4,
                        max: 64,
                        divisions: 30,
                        label: _brushRadius.round().toString(),
                        onChanged: (v) => setState(() => _brushRadius = v),
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cut out sticker')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cut out sticker')),
        body: Center(child: Text(_loadError!)),
      );
    }

    return Scaffold(
      extendBody: true,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerLowest,
                    ),
                  ),
                  Positioned.fill(
                    child: _sourceUiImage == null
                        ? const SizedBox.shrink()
                        : RotatableInteractiveViewer(
                            transformationController: _viewerController,
                            minScale: 0.2,
                            maxScale: 8,
                            boundaryMargin: const EdgeInsets.all(96),
                            // While editing the mask, disable IV's scale/pan/rotate so the
                            // viewer omits its scale [GestureDetector] and raw pointer
                            // handlers on the child get move events (live tolerance preview).
                            panEnabled: _viewAdjustMode,
                            scaleEnabled: _viewAdjustMode,
                            rotateEnabled: _viewAdjustMode,
                            trackpadScrollCausesScale: _viewAdjustMode,
                            clipBehavior: Clip.none,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                // [_boxFitContainSize] matches [AspectRatio]/[RenderAspectRatio] sizing
                                // (same as BoxFit.contain) so the layout box matches the bitmap aspect.
                                final maxSize = constraints.biggest;
                                // Use [_sourceUiImage] dimensions (same as [_image] after [_imgToUiImage]).
                                final iw = _sourceUiImage!.width.toDouble();
                                final ih = _sourceUiImage!.height.toDouble();
                                if (iw <= 0 || ih <= 0 || maxSize.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                final renderSize =
                                    _boxFitContainSize(maxSize, iw, ih);
                                final imgLeft =
                                    (maxSize.width - renderSize.width) / 2;
                                final imgTop =
                                    (maxSize.height - renderSize.height) / 2;
                                final photoRect = Rect.fromLTWH(
                                  imgLeft,
                                  imgTop,
                                  renderSize.width,
                                  renderSize.height,
                                );

                                return SizedBox(
                                  width: maxSize.width,
                                  height: maxSize.height,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      // Transparent letterbox; checker + image only in [photoRect] (see painter).
                                      Positioned.fill(
                                        child: CustomPaint(
                                          painter: _ViewportCheckerPhotoPainter(
                                            source: _sourceUiImage!,
                                            photoDst: photoRect,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left: imgLeft,
                                        top: imgTop,
                                        width: renderSize.width,
                                        height: renderSize.height,
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            if (_image != null && _mask != null)
                                              Positioned.fill(
                                                child: CustomPaint(
                                                  key: ValueKey(_highlightSeq),
                                                  painter:
                                                      _MaskHighlightPainter(
                                                    mask: _mask!,
                                                    imageWidth:
                                                        _sourceUiImage!.width,
                                                    imageHeight:
                                                        _sourceUiImage!.height,
                                                    generation: _highlightSeq,
                                                  ),
                                                ),
                                              ),
                                            if (!_viewAdjustMode &&
                                                _mode == _EditorMode.brush)
                                              Positioned.fill(
                                                child: Listener(
                                                  onPointerDown:
                                                      _onBrushPointerDown,
                                                  child: GestureDetector(
                                                    behavior:
                                                        HitTestBehavior.opaque,
                                                    onTapUp: (d) {
                                                      if (_viewAdjustMode) {
                                                        return;
                                                      }
                                                      setState(
                                                        () =>
                                                            _brushCursorLocal =
                                                                d.localPosition,
                                                      );
                                                      _applyBrush(
                                                        d.localPosition,
                                                        renderSize,
                                                      );
                                                    },
                                                    onPanDown: (d) {
                                                      setState(
                                                        () =>
                                                            _brushCursorLocal =
                                                                d.localPosition,
                                                      );
                                                      _applyBrush(
                                                        d.localPosition,
                                                        renderSize,
                                                      );
                                                    },
                                                    onPanUpdate: (d) {
                                                      setState(
                                                        () =>
                                                            _brushCursorLocal =
                                                                d.localPosition,
                                                      );
                                                      _applyBrush(
                                                        d.localPosition,
                                                        renderSize,
                                                      );
                                                    },
                                                    onPanEnd: (_) {
                                                      setState(() =>
                                                          _brushCursorLocal =
                                                              null);
                                                    },
                                                    onPanCancel: () {
                                                      setState(() =>
                                                          _brushCursorLocal =
                                                              null);
                                                    },
                                                    child:
                                                        const SizedBox.expand(),
                                                  ),
                                                ),
                                              ),
                                            if (!_viewAdjustMode &&
                                                _mode == _EditorMode.brush &&
                                                _brushCursorLocal != null)
                                              Positioned.fill(
                                                child: IgnorePointer(
                                                  child: CustomPaint(
                                                    painter:
                                                        _BrushCursorPainter(
                                                      center:
                                                          _brushCursorLocal!,
                                                      radius: _brushRadius,
                                                      subtracting:
                                                          _brushVariant ==
                                                              _BrushVariant
                                                                  .remove,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (!_viewAdjustMode &&
                                          _mode == _EditorMode.tapFill)
                                        Positioned.fill(
                                          child: Listener(
                                            behavior: HitTestBehavior.opaque,
                                            onPointerDown: (e) {
                                              final lp = e.localPosition;
                                              if (!photoRect.contains(lp)) {
                                                _tolD(
                                                  'pointerDown IGNORED (outside image) '
                                                  'local=$lp photoRect=$photoRect '
                                                  'viewAdjust=$_viewAdjustMode',
                                                );
                                                return;
                                              }
                                              final imgLocal = Offset(
                                                lp.dx - imgLeft,
                                                lp.dy - imgTop,
                                              );
                                              final clamped = Offset(
                                                imgLocal.dx.clamp(
                                                  0.0,
                                                  math.max(0.0,
                                                      renderSize.width - 1e-6),
                                                ),
                                                imgLocal.dy.clamp(
                                                  0.0,
                                                  math.max(0.0,
                                                      renderSize.height - 1e-6),
                                                ),
                                              );
                                              _onTapFillPointerDownAt(
                                                clamped,
                                                renderSize,
                                              );
                                            },
                                            onPointerMove: (e) =>
                                                _onTapFillPointerMove(
                                                    e, renderSize),
                                            onPointerUp: (_) =>
                                                _onTapFillPointerUp(renderSize),
                                            onPointerCancel: (_) =>
                                                _onTapFillPointerCancel(),
                                            child: const SizedBox.expand(),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: _buildCutoutBottomToolbar(context),
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

class _BrushCursorPainter extends CustomPainter {
  _BrushCursorPainter({
    required this.center,
    required this.radius,
    required this.subtracting,
  });

  final Offset center;
  final double radius;
  final bool subtracting;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = subtracting
          ? Colors.redAccent
          : const Color(0xFF6C6C70);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _BrushCursorPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.radius != radius ||
        oldDelegate.subtracting != subtracting;
  }
}

/// Semi-transparent dark grey where [mask] > 0. Paints synchronously on the GPU so
/// drag previews update every frame. ([Image.memory] + PNG was async and only
/// the last frame appeared during fast drags.)
///
/// Uses horizontal spans so thin gaps match the real mask (coarse blocks hid slivers).
/// Draws a light edge on mask/unmasked boundaries so holes and cut lines read clearly.
class _MaskHighlightPainter extends CustomPainter {
  _MaskHighlightPainter({
    required this.mask,
    required this.imageWidth,
    required this.imageHeight,
    required this.generation,
  });

  final Uint8List mask;
  final int imageWidth;
  final int imageHeight;

  /// Bumped when [mask] bytes change ([_highlightSeq]).
  final int generation;

  static const Color _maskFill = Color.fromRGBO(6, 6, 10, 0.82);
  static const Color _maskEdge = Color.fromRGBO(245, 245, 250, 0.45);

  /// Skip per-pixel edge pass on huge bitmaps to avoid jank (fill spans still exact).
  static const int _maxPixelsForEdgePass = 3500000;

  @override
  void paint(Canvas canvas, Size size) {
    final w = imageWidth;
    final h = imageHeight;
    if (w <= 0 || h <= 0 || mask.length < w * h) {
      return;
    }
    var any = false;
    for (var i = 0; i < w * h; i++) {
      if (mask[i] > 0) {
        any = true;
        break;
      }
    }
    if (!any) {
      return;
    }

    final sw = size.width;
    final sh = size.height;
    final fillPaint = Paint()..color = _maskFill;

    for (var iy = 0; iy < h; iy++) {
      final row = iy * w;
      var ix = 0;
      while (ix < w) {
        if (mask[row + ix] == 0) {
          ix++;
          continue;
        }
        final xStart = ix;
        while (ix < w && mask[row + ix] > 0) {
          ix++;
        }
        final xEnd = ix;
        final x0 = xStart / w * sw;
        final x1 = xEnd / w * sw;
        final y0 = iy / h * sh;
        final y1 = (iy + 1) / h * sh;
        canvas.drawRect(Rect.fromLTRB(x0, y0, x1, y1), fillPaint);
      }
    }

    if (w * h > _maxPixelsForEdgePass) {
      return;
    }
    final edgePaint = Paint()..color = _maskEdge;
    for (var iy = 0; iy < h; iy++) {
      final row = iy * w;
      for (var ix = 0; ix < w; ix++) {
        final i = row + ix;
        if (mask[i] == 0) continue;
        if (!_maskHasUnmaskedNeighbor(mask, ix, iy, w, h)) continue;
        final x0 = ix / w * sw;
        final x1 = (ix + 1) / w * sw;
        final y0 = iy / h * sh;
        final y1 = (iy + 1) / h * sh;
        canvas.drawRect(Rect.fromLTRB(x0, y0, x1, y1), edgePaint);
      }
    }
  }

  static bool _maskHasUnmaskedNeighbor(
    Uint8List mask,
    int ix,
    int iy,
    int w,
    int h,
  ) {
    final i = iy * w + ix;
    if (ix > 0 && mask[i - 1] == 0) return true;
    if (ix < w - 1 && mask[i + 1] == 0) return true;
    if (iy > 0 && mask[i - w] == 0) return true;
    if (iy < h - 1 && mask[i + w] == 0) return true;
    return false;
  }

  @override
  bool shouldRepaint(covariant _MaskHighlightPainter oldDelegate) {
    return oldDelegate.generation != generation ||
        !identical(oldDelegate.mask, mask) ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
  }
}

/// Letterbox outside [photoDst] is left unpainted (transparent) so the parent
/// [Stack]’s surface shows through. The tiled checker is drawn only inside
/// [photoDst], under the bitmap.
class _ViewportCheckerPhotoPainter extends CustomPainter {
  _ViewportCheckerPhotoPainter({
    required this.source,
    required this.photoDst,
  });

  final ui.Image source;
  final Rect photoDst;

  @override
  void paint(Canvas canvas, Size size) {
    const s = 12.0;
    final light = Paint()..color = const Color(0xFF2a2a2a);
    final dark = Paint()..color = const Color(0xFF1a1a1a);
    canvas.save();
    canvas.clipRect(photoDst);
    final nx = (size.width / s).ceil() + 1;
    final ny = (size.height / s).ceil() + 1;
    for (var y = 0; y < ny; y++) {
      for (var x = 0; x < nx; x++) {
        final tilePaint = ((x + y) & 1) == 0 ? light : dark;
        canvas.drawRect(
          Rect.fromLTWH(x * s, y * s, s, s),
          tilePaint,
        );
      }
    }
    canvas.restore();
    final src = Rect.fromLTWH(
      0,
      0,
      source.width.toDouble(),
      source.height.toDouble(),
    );
    canvas.drawImageRect(
      source,
      src,
      photoDst,
      Paint()
        ..filterQuality = FilterQuality.low
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _ViewportCheckerPhotoPainter oldDelegate) {
    return !identical(oldDelegate.source, source) ||
        oldDelegate.photoDst != photoDst;
  }
}

/// Same tile pattern as [_ViewportCheckerPhotoPainter] for save-preview parity.
class _PreviewCheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const s = 12.0;
    final light = Paint()..color = const Color(0xFF2a2a2a);
    final dark = Paint()..color = const Color(0xFF1a1a1a);
    final nx = (size.width / s).ceil() + 1;
    final ny = (size.height / s).ceil() + 1;
    for (var y = 0; y < ny; y++) {
      for (var x = 0; x < nx; x++) {
        final tilePaint = ((x + y) & 1) == 0 ? light : dark;
        canvas.drawRect(
          Rect.fromLTWH(x * s, y * s, s, s),
          tilePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
