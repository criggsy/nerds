import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:nerds/Widgets/drawer.dart';
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _seedLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load sticker: $e')),
      );
    }
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final list = await picker.pickMultiImage();
    if (list.isEmpty) return;
    setState(() {
      if (!_seedMode) {
        _images.clear();
      }
      _images.addAll(list);
    });
  }

  int get _remainingSlots =>
      UserPackService.maxStickers - _images.length;

  Future<void> _pickFromServer() async {
    final remaining = _remainingSlots;
    if (remaining <= 0) return;
    final picked = await context.push<List<XFile>?>(
      '/pick-server-stickers',
      extra: <String, dynamic>{'remainingSlots': remaining},
    );
    if (!mounted) return;
    if (picked != null && picked.isNotEmpty) {
      setState(() => _images.addAll(picked));
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
        final msg = e is ArgumentError
            ? (e.message?.toString() ?? '$e')
            : '$e';
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
            'Choose ${UserPackService.minStickers}–${UserPackService.maxStickers} images (WhatsApp limit). '
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
            onPressed: _pickImages,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_seedMode ? 'Add more from gallery' : 'Choose images'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _seedLoading || _remainingSlots <= 0
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
              children: _images
                  .map(
                    (f) => SizedBox(
                      width: 72,
                      height: 72,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(f.path),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  )
                  .toList(),
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
