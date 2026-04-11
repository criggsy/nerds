import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:nerds/constants/constants.dart';
import 'package:nerds/models/sticker_data.dart';

class _StickerPick {
  final StickerPacks pack;
  final Stickers sticker;

  const _StickerPick({required this.pack, required this.sticker});
}

/// Browse server [StickerPacks], multi-select stickers, download to temp files, pop [List<XFile>].
class ServerStickerPickerScreen extends StatefulWidget {
  /// Max stickers the user may add in this session (room left in the pack being built).
  final int remainingSlots;

  const ServerStickerPickerScreen({
    super.key,
    required this.remainingSlots,
  });

  @override
  State<ServerStickerPickerScreen> createState() =>
      _ServerStickerPickerScreenState();
}

class _ServerStickerPickerScreenState extends State<ServerStickerPickerScreen> {
  final List<_StickerPick> _selection = [];
  StickerPacks? _openPack;
  bool _downloading = false;

  late Future<StickerData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadStickerData();
  }

  Future<StickerData> _loadStickerData() async {
    final dio = Dio();
    final res = await dio.get<Map<String, dynamic>>(
      '$baseURL/json/sticker_packs.json',
    );
    final data = res.data;
    if (data == null) {
      throw StateError('Empty sticker list');
    }
    return StickerData.fromJson(data);
  }

  bool _contains(_StickerPick pick) {
    return _selection.any(
      (e) =>
          e.pack.identifier == pick.pack.identifier &&
          e.sticker.imageFile == pick.sticker.imageFile,
    );
  }

  void _toggle(_StickerPick pick) {
    if (_contains(pick)) {
      setState(() {
        _selection.removeWhere(
          (e) =>
              e.pack.identifier == pick.pack.identifier &&
              e.sticker.imageFile == pick.sticker.imageFile,
        );
      });
      return;
    }
    if (_selection.length >= widget.remainingSlots) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You can add at most ${widget.remainingSlots} sticker(s) here.',
          ),
        ),
      );
      return;
    }
    setState(() => _selection.add(pick));
  }

  Future<void> _confirm() async {
    if (_selection.isEmpty) return;
    setState(() => _downloading = true);
    try {
      final tmp = await getTemporaryDirectory();
      final dio = Dio();
      final out = <XFile>[];
      for (var i = 0; i < _selection.length; i++) {
        final pick = _selection[i];
        final id = pick.pack.identifier ?? 'pack';
        final file = pick.sticker.imageFile ?? 'sticker';
        final url = '$baseURL/sticker-packs/$id/$file';
        var ext = p.extension(file);
        if (ext.isEmpty) ext = '.webp';
        final path = p.join(
          tmp.path,
          'srv_${DateTime.now().millisecondsSinceEpoch}_${i}_$id$ext',
        );
        await dio.download(url, path);
        out.add(XFile(path));
      }
      if (mounted) {
        context.pop<List<XFile>>(out);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_openPack == null
            ? 'Server sticker packs'
            : (_openPack!.name ?? 'Pack')),
        leading: _openPack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _openPack = null),
              )
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => context.pop<List<XFile>?>(null),
              ),
        actions: [
          if (_selection.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _downloading ? null : _confirm,
                child: _downloading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Add (${_selection.length})'),
              ),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_selection.isNotEmpty)
            Material(
              color: Colors.teal.withValues(alpha: 0.12),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.collections, color: Colors.teal.shade800),
                title: Text(
                  '${_selection.length} / ${widget.remainingSlots} selected',
                ),
                subtitle: const Text(
                  'Open other packs to add more, then tap Add.',
                ),
              ),
            ),
          Expanded(
            child: FutureBuilder<StickerData>(
              future: _dataFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError || !snap.hasData) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Could not load packs: ${snap.error}'),
                    ),
                  );
                }
                final data = snap.data!;
                final packs = data.stickerPacks ?? [];

                if (_openPack != null) {
                  return _buildStickerGrid(_openPack!);
                }

                if (packs.isEmpty) {
                  return const Center(
                    child: Text('No sticker packs on the server.'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: packs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final pack = packs[index];
                    final count = pack.stickers?.length ?? 0;
                    return Card(
                      child: ListTile(
                        leading: pack.trayImageFile != null &&
                                pack.identifier != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  '$baseURL/sticker-packs/${pack.identifier}/${pack.trayImageFile}',
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.image_not_supported),
                                ),
                              )
                            : const Icon(Icons.folder_special),
                        title: Text(pack.name ?? 'Pack'),
                        subtitle: Text('$count stickers'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => setState(() => _openPack = pack),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickerGrid(StickerPacks pack) {
    final stickers = pack.stickers ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            'Tap to select up to ${widget.remainingSlots} sticker(s). '
            'Selected: ${_selection.length}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: stickers.length,
            itemBuilder: (context, index) {
              final s = stickers[index];
              final pick = _StickerPick(pack: pack, sticker: s);
              final sel = _contains(pick);
              final url =
                  '$baseURL/sticker-packs/${pack.identifier}/${s.imageFile}';
              return GestureDetector(
                onTap: () => _toggle(pick),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: sel ? Colors.teal : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const ColoredBox(color: Colors.black26),
                        ),
                        if (sel)
                          const Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.check_circle,
                                color: Colors.teal,
                                size: 20,
                              ),
                            ),
                          ),
                      ],
                    ),
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
