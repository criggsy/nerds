import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:whatsapp_stickers_handler/exceptions.dart';
import 'package:whatsapp_stickers_handler/whatsapp_stickers_handler.dart';

import 'package:nerds/widgets/drawer.dart';
import 'package:nerds/models/user_pack.dart';
import 'package:nerds/services/user_pack_service.dart';
import 'package:nerds/utils/sticker_config_utils.dart';
import 'package:nerds/utils/sticker_pack_status.dart';
import 'package:nerds/utils/app_messaging.dart';
import 'package:nerds/utils/logger.dart';

class UserPackDetailScreen extends StatefulWidget {
  final UserPack pack;

  const UserPackDetailScreen({
    super.key,
    required this.pack,
  });

  @override
  State<UserPackDetailScreen> createState() => _UserPackDetailScreenState();
}

class _UserPackDetailScreenState extends State<UserPackDetailScreen> {
  bool _isInstalling = false;
  bool _addingStickers = false;
  int _statusEpoch = 0;

  UserPack get _pack =>
      UserPackService.instance.getById(widget.pack.id) ?? widget.pack;

  Future<void> _addToWhatsApp(UserPack pack) async {
    setState(() => _isInstalling = true);

    final handler = WhatsappStickersHandler();
    final (stickers, trayImage) = userPackFilesForWhatsapp(pack);

    String? result;
    try {
      result = await handler.addStickerPack(
        pack.id,
        pack.name,
        'My stickers',
        trayImage,
        null,
        null,
        null,
        false,
        stickers,
        imageDataVersion: pack.packVersion ?? '1',
      );
    } on WhatsappStickersException catch (e) {
      final cause = e.cause?.toLowerCase() ?? '';
      if (cause.contains('already added')) {
        result = 'already_added';
        log.i("ℹ️ Treated 'already_added' as success.");
      } else {
        result = null;
        if (mounted) {
          await showAppErrorDialog(
            context,
            e.cause ?? 'Unknown error',
            title: 'Couldn’t add to WhatsApp',
          );
        }
      }
    }

    if (result == 'add_successful' ||
        result == 'success' ||
        result == 'already_added') {
      await regenerateStickerConfigFile();
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) {
        setState(() {
          _statusEpoch++;
          _isInstalling = false;
        });
        Fluttertoast.showToast(
          msg: '✅ Sticker pack added to WhatsApp',
          gravity: ToastGravity.BOTTOM,
        );
      }
    } else if (mounted) {
      setState(() => _isInstalling = false);
    }
  }

  Future<void> _pickAndAddStickers(UserPack pack) async {
    final remaining = UserPackService.maxStickers - pack.stickerPaths.length;
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

    final picker = ImagePicker();
    final list = await picker.pickMultiImage();
    if (list.isEmpty || !mounted) return;

    final capped = list.length <= remaining ? list : list.sublist(0, remaining);

    setState(() => _addingStickers = true);
    try {
      var added = 0;
      for (final x in capped) {
        if (!mounted) return;
        final editedPath = await context.push<String>(
          '/user-packs/cutout',
          extra: <String, dynamic>{'imagePath': x.path},
        );
        if (!mounted) return;
        if (editedPath == null || editedPath.isEmpty) {
          continue;
        }
        await UserPackService.instance
            .addStickerFromXFile(pack.id, XFile(editedPath));
        added++;
      }
      if (!mounted) return;
      if (list.length > remaining) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Only $remaining slot${remaining == 1 ? '' : 's'} left — '
              'processed up to ${capped.length} photo(s).',
            ),
          ),
        );
      }
      if (added > 0) {
        setState(() => _statusEpoch++);
        Fluttertoast.showToast(
          msg: added == 1
              ? 'Sticker added — use Update Pack in WhatsApp if the pack is already installed'
              : '$added stickers added — use Update Pack in WhatsApp if needed',
          gravity: ToastGravity.BOTTOM,
        );
      }
    } catch (e) {
      if (mounted) {
        await showAppErrorDialog(
          context,
          '$e',
          title: 'Couldn’t add sticker',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _addingStickers = false);
      }
    }
  }

  Future<void> _onStickerLongPress(UserPack pack, int index) async {
    if (pack.stickerPaths.length <= UserPackService.minStickers) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'WhatsApp packs need at least ${UserPackService.minStickers} stickers. '
            'Delete the whole pack from the menu if you want to remove it.',
          ),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove sticker?'),
        content: const Text(
          'This removes the sticker from this pack. If the pack is already in WhatsApp, tap Update Pack there afterward.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await UserPackService.instance.removeStickerAt(pack.id, index);
      if (mounted) {
        setState(() => _statusEpoch++);
        Fluttertoast.showToast(
          msg:
              'Sticker removed — use Update Pack in WhatsApp if the pack is installed',
          gravity: ToastGravity.BOTTOM,
        );
      }
    } catch (e) {
      if (mounted) {
        await showAppErrorDialog(
          context,
          '$e',
          title: 'Couldn’t remove sticker',
        );
      }
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete pack?'),
        content: const Text(
            'This removes the pack from the app and deletes its files from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await UserPackService.instance.deletePack(widget.pack.id);
    if (mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserPackService.instance,
      builder: (context, _) {
        final pack = _pack;
        return Scaffold(
          appBar: AppBar(
            title: Text(pack.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _confirmDelete,
                tooltip: 'Delete pack',
              ),
            ],
          ),
          drawer: const Drawer(child: MyDrawer()),
          body: FutureBuilder<StickerPackStatus>(
            key: ValueKey(
                '${_statusEpoch}_${pack.stickerPaths.length}_${pack.packVersion}'),
            future: getUserPackStatus(pack),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.hasError) {
                return const Center(child: Text('Failed to load status'));
              }

              final status = snapshot.data!;
              final isInstalled = status.isInstalled;
              final updateAvailable = status.hasUpdate;
              final canAddMore =
                  pack.stickerPaths.length < UserPackService.maxStickers;

              final actionWidget = ElevatedButton.icon(
                onPressed: (!isInstalled || updateAvailable) && !_isInstalling
                    ? () => _addToWhatsApp(pack)
                    : null,
                icon: _isInstalling
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(updateAvailable ? Icons.refresh : Icons.add),
                label: Text(
                  updateAvailable
                      ? 'Update Pack'
                      : isInstalled
                          ? 'Installed'
                          : 'Add Pack',
                ),
              );

              final thumbPath = pack.thumbnailPath;

              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      color: Theme.of(context).cardColor,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: thumbPath != null &&
                                      File(thumbPath).existsSync()
                                  ? Image.file(
                                      File(thumbPath),
                                      height: 72,
                                      width: 72,
                                      fit: BoxFit.cover,
                                    )
                                  : const Icon(Icons.image_not_supported,
                                      size: 72),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pack.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${pack.stickerPaths.length} stickers · '
                                    'v${pack.packVersion ?? '1'}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            actionWidget,
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (canAddMore)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _addingStickers
                                ? null
                                : () => _pickAndAddStickers(pack),
                            icon: _addingStickers
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(
                                    Icons.add_photo_alternate_outlined),
                            label: Text(
                              _addingStickers ? 'Adding…' : 'Add sticker',
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: pack.stickerPaths.length,
                        itemBuilder: (context, index) {
                          final path = pack.stickerPaths[index];
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: GestureDetector(
                              onLongPress: () =>
                                  _onStickerLongPress(pack, index),
                              child: File(path).existsSync()
                                  ? Image.file(
                                      File(path),
                                      fit: BoxFit.cover,
                                    )
                                  : const ColoredBox(
                                      color: Colors.black26,
                                      child: Icon(Icons.broken_image),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
