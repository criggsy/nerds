import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:nerds/widgets/drawer.dart';
import 'package:nerds/services/user_pack_service.dart';

class CreateUserPackScreen extends StatefulWidget {
  /// When set (e.g. long-press from a server pack), downloaded and pre-filled as the first sticker.
  final String? seedStickerUrl;

  const CreateUserPackScreen({
    super.key,
    this.seedStickerUrl,
  });

  @override
  State<CreateUserPackScreen> createState() => _CreateUserPackScreenState();
}

class _CreateUserPackScreenState extends State<CreateUserPackScreen> {
  final _nameController = TextEditingController();
  final List<XFile> _images = [];
  bool _saving = false;
  bool _seedLoading = false;

  /// True while opening the cutout editor after gallery/server picks.
  bool _cutoutChainBusy = false;

  bool get _seedMode => widget.seedStickerUrl != null;

  @override
  void initState() {
    super.initState();
    _maybeLoadSeed();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _maybeLoadSeed() async {
    final url = widget.seedStickerUrl;
    if (url == null || url.isEmpty) return;

    setState(() => _seedLoading = true);
    try {
      final dir = await getTemporaryDirectory();
      var ext = p.extension(Uri.tryParse(url)?.path ?? '');
      if (ext.isEmpty) ext = '.webp';
      final path = p.join(
        dir.path,
        'seed_${DateTime.now().millisecondsSinceEpoch}$ext',
      );
      await Dio().download(url, path);
      if (!mounted) return;
      setState(() {
        _images.add(XFile(path));
        _seedLoading = false;
      });
      await _openCutoutForIndex(_images.length - 1);
    } catch (e) {
      if (!mounted) return;
      setState(() => _seedLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load sticker: $e')),
      );
    }
  }

  /// Opens the cutout editor for each [source] file and appends saved PNGs to [_images].
  /// Skips sources when the user cancels the editor or there is no room left.
  Future<int> _appendEachThroughCutout(Iterable<XFile> sources) async {
    var added = 0;
    for (final x in sources) {
      if (!mounted) return added;
      if (_remainingSlots <= 0) break;
      final result = await context.push<String>(
        '/user-packs/cutout',
        extra: <String, dynamic>{'imagePath': x.path},
      );
      if (!mounted) return added;
      if (result == null || result.isEmpty) continue;
      setState(() {
        _images.add(XFile(result));
        added++;
      });
    }
    return added;
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final list = await picker.pickMultiImage();
    if (list.isEmpty) return;

    final remaining = _remainingSlots;
    if (remaining <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This pack already has ${UserPackService.maxStickers} stickers '
            '(WhatsApp maximum).',
          ),
        ),
      );
      return;
    }

    final capped = list.length <= remaining ? list : list.sublist(0, remaining);

    setState(() => _cutoutChainBusy = true);
    try {
      await _appendEachThroughCutout(capped);
    } finally {
      if (mounted) {
        setState(() => _cutoutChainBusy = false);
      }
    }

    if (!mounted) return;
    if (list.length > remaining) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Only $remaining slot${remaining == 1 ? '' : 's'} left — '
            'opened the editor for up to ${capped.length} photo(s).',
          ),
        ),
      );
    }
  }

  int get _remainingSlots => UserPackService.maxStickers - _images.length;

  /// Opens the cutout editor for a single pack image; updates that slot on success.
  Future<void> _openCutoutForIndex(int index) async {
    if (_seedLoading || index < 0 || index >= _images.length) return;
    final result = await context.push<String>(
      '/user-packs/cutout',
      extra: <String, dynamic>{'imagePath': _images[index].path},
    );
    if (!mounted) return;
    if (result == null) return;
    setState(() => _images[index] = XFile(result));
  }

  void _removeImageAt(int index) {
    if (_seedLoading || index < 0 || index >= _images.length) return;
    final removed = _images[index];
    setState(() => _images.removeAt(index));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Removed from pack'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!mounted) return;
            setState(
                () => _images.insert(index.clamp(0, _images.length), removed));
          },
        ),
      ),
    );
  }

  Future<void> _pickFromServer() async {
    final remaining = _remainingSlots;
    if (remaining <= 0) return;
    final picked = await context.push<List<XFile>?>(
      '/pick-server-stickers',
      extra: <String, dynamic>{'remainingSlots': remaining},
    );
    if (!mounted) return;
    if (picked == null || picked.isEmpty) return;

    setState(() => _cutoutChainBusy = true);
    try {
      await _appendEachThroughCutout(picked);
    } finally {
      if (mounted) {
        setState(() => _cutoutChainBusy = false);
      }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await UserPackService.instance
          .createPack(_nameController.text, List<XFile>.from(_images));
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        final msg = e is ArgumentError ? (e.message?.toString() ?? '$e') : '$e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _nameController.text.trim().isNotEmpty &&
        _images.length >= UserPackService.minStickers &&
        _images.length <= UserPackService.maxStickers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create sticker pack'),
      ),
      drawer: const Drawer(child: MyDrawer()),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_seedLoading) const LinearProgressIndicator(),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Pack name',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text(
            'Choose ${UserPackService.minStickers}–${UserPackService.maxStickers} stickers (WhatsApp limit). '
            'Each photo opens in the editor before it is added. '
            'Currently: ${_images.length}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (_seedMode) ...[
            const SizedBox(height: 8),
            Text(
              'The long-pressed sticker is included. Add more from your gallery or from server packs.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _seedLoading || _cutoutChainBusy ? null : _pickImages,
            icon: _cutoutChainBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_library_outlined),
            label: Text(
              _cutoutChainBusy
                  ? 'Editing…'
                  : _seedMode
                      ? 'Add more from gallery'
                      : (_images.isEmpty ? 'Choose images' : 'Add more images'),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _seedLoading || _cutoutChainBusy || _remainingSlots <= 0
                ? null
                : _pickFromServer,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Add from server packs'),
          ),
          const SizedBox(height: 16),
          if (_images.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List<Widget>.generate(
                _images.length,
                (i) => SizedBox(
                  width: 72,
                  height: 72,
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _seedLoading ? null : () => _openCutoutForIndex(i),
                      onLongPress:
                          _seedLoading ? null : () => _removeImageAt(i),
                      child: Image.file(
                        File(_images[i].path),
                        fit: BoxFit.cover,
                        semanticLabel:
                            'Sticker: tap to edit, long press to remove',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: canSave && !_saving && !_seedLoading ? _save : null,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save pack'),
          ),
        ],
      ),
    );
  }
}
