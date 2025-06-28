import 'package:flutter/material.dart';
import 'package:nerds/Widgets/drawer.dart';
import 'package:nerds/constants/constants.dart';
import 'package:nerds/models/sticker_data.dart';
import 'package:nerds/utils/sticker_config_utils.dart';
import 'package:nerds/utils/sticker_pack_status.dart';
import 'package:whatsapp_stickers_handler/exceptions.dart';
import 'package:whatsapp_stickers_handler/whatsapp_stickers_handler.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:nerds/utils/logger.dart';

class StickerPackInfoScreen extends StatefulWidget {
  static const routeName = '/sticker-pack-info';
  const StickerPackInfoScreen({super.key});

  @override
  State<StickerPackInfoScreen> createState() => _StickerPackInfoScreenState();
}

class _StickerPackInfoScreenState extends State<StickerPackInfoScreen> {
  bool _isInstalling = false;

  Future<void> addStickerPack(StickerPacks stickerPack) async {
    setState(() => _isInstalling = true);

    final handler = WhatsappStickersHandler();
    final (stickers, trayImage) =
        await downloadStickersAndTrayImage(stickerPack);

    String? result;

    try {
      result = await handler.addStickerPack(
        stickerPack.identifier ?? 'unknown',
        stickerPack.name ?? '',
        stickerPack.publisher ?? '',
        trayImage,
        stickerPack.publisherWebsite,
        stickerPack.privacyPolicyWebsite,
        stickerPack.licenseAgreementWebsite,
        stickerPack.animatedStickerPack ?? false,
        stickers,
        imageDataVersion: stickerPack.imageDataVersion ?? '1.0',
      );
    } on WhatsappStickersException catch (e) {
      if (e.cause == 'Sticker pack already added') {
        result = 'already_added';
        log.i("ℹ️ Treated 'already_added' as success.");
      } else {
        result = null;
        Fluttertoast.showToast(
          msg: "❌ Failed: ${e.cause ?? 'Unknown error'}",
          gravity: ToastGravity.BOTTOM,
        );
      }
    }

    if (result == 'add_successful' ||
        result == 'success' ||
        result == 'already_added') {
      await regenerateStickerConfigFile();
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) Navigator.pop(context, true);
    }

    setState(() => _isInstalling = false);
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final stickerPack = args?['stickerPack'] as StickerPacks?;

    if (stickerPack == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sticker Pack Info')),
        body: const Center(child: Text('❌ No sticker pack info available')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${stickerPack.name} Stickers'),
      ),
      drawer: const Drawer(child: MyDrawer()),
      body: FutureBuilder<StickerPackStatus>(
        future: getStickerPackStatus(stickerPack),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.hasError) {
            return const Center(child: Text('❌ Failed to load status'));
          }

          final status = snapshot.data!;
          final bool isInstalled = status.isInstalled;
          final bool updateAvailable = status.hasUpdate;

          final actionWidget = ElevatedButton.icon(
            onPressed: (!isInstalled || updateAvailable) && !_isInstalling
                ? () => addStickerPack(stickerPack)
                : null,
            icon: _isInstalling
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(updateAvailable ? Icons.refresh : Icons.add),
            label: Text(updateAvailable
                ? 'Update Pack'
                : isInstalled
                    ? 'Installed'
                    : 'Add Pack'),
          );

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
                          child: FadeInImage(
                            placeholder:
                                const AssetImage("assets/images/logo.png"),
                            image: NetworkImage(
                              "$baseURL/sticker-packs/${stickerPack.identifier}/${stickerPack.trayImageFile}",
                            ),
                            height: 72,
                            width: 72,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stickerPack.name ?? '',
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
                    itemCount: stickerPack.stickers?.length ?? 0,
                    itemBuilder: (context, index) {
                      final sticker = stickerPack.stickers![index];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: FadeInImage(
                          placeholder:
                              const AssetImage("assets/images/logo.png"),
                          image: NetworkImage(
                            "$baseURL/sticker-packs/${stickerPack.identifier}/${sticker.imageFile}",
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
  }
}
