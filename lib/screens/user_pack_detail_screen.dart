import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:whatsapp_stickers_handler/exceptions.dart';
import 'package:whatsapp_stickers_handler/whatsapp_stickers_handler.dart';

import 'package:nerds/Widgets/drawer.dart';
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
        key: ValueKey(_statusEpoch),
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
                          child: thumbPath != null && File(thumbPath).existsSync()
                              ? Image.file(
                                  File(thumbPath),
                                  height: 72,
                                  width: 72,
                                  fit: BoxFit.cover,
                                )
                              : const Icon(Icons.image_not_supported, size: 72),
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
                            ],
                          ),
                        ),
                        actionWidget,
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
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
                        child: File(path).existsSync()
                            ? Image.file(
                                File(path),
                                fit: BoxFit.cover,
                              )
                            : const ColoredBox(
                                color: Colors.black26,
                                child: Icon(Icons.broken_image),
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
  }
}
