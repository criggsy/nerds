import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:nerds/constants/constants.dart';
import 'package:nerds/models/sticker_data.dart';
import 'package:nerds/utils/sticker_config_utils.dart';
import 'package:nerds/utils/sticker_pack_status.dart';
import 'package:whatsapp_stickers_handler/exceptions.dart';
import 'package:whatsapp_stickers_handler/whatsapp_stickers_handler.dart';
import 'package:nerds/utils/app_messaging.dart';
import 'package:nerds/utils/logger.dart';
import 'package:go_router/go_router.dart';

class StickerPackItem extends StatefulWidget {
  final StickerPacks stickerPack;

  const StickerPackItem({
    super.key,
    required this.stickerPack,
  });

  @override
  State<StickerPackItem> createState() => _StickerPackItemState();
}

class _StickerPackItemState extends State<StickerPackItem> {
  final WhatsappStickersHandler _handler = WhatsappStickersHandler();
  late Future<StickerPackStatus> _packStatus;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  void _refreshStatus() {
    _packStatus = getStickerPackStatus(widget.stickerPack);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        onTap: () async {
          final updated = await context.push(
            '/sticker-pack-info',
            extra: {'stickerPack': widget.stickerPack},
          );
          if (updated == true && mounted) {
            setState(_refreshStatus);
          }
        },
        title: Text(widget.stickerPack.name ?? ""),
        leading: FadeInImage(
          placeholder: const AssetImage("assets/images/logo.png"),
          image: NetworkImage(
            "$baseURL/sticker-packs/${widget.stickerPack.identifier}/${widget.stickerPack.trayImageFile}",
          ),
          height: 48,
          width: 48,
        ),
        trailing: FutureBuilder<StickerPackStatus>(
          key: ValueKey(_packStatus),
          future: _packStatus,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Icon(Icons.hourglass_empty);
            return _buildIconButton(snapshot.data!);
          },
        ),
      ),
    );
  }

  Widget _buildIconButton(StickerPackStatus status) {
    final bool isInstalled = status.isInstalled;
    final bool hasUpdate = status.hasUpdate;

    IconData icon = Icons.check;
    String tooltip = "Up to date";

    if (!isInstalled) {
      icon = Icons.add;
      tooltip = "Add to WhatsApp";
    } else if (hasUpdate) {
      icon = Icons.refresh;
      tooltip = "Update available";
    }

    return IconButton(
      icon: _isProcessing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      color: hasUpdate ? Colors.deepPurple : Colors.teal,
      tooltip: tooltip,
      onPressed: (!isInstalled || hasUpdate)
          ? () async {
              setState(() => _isProcessing = true); // 🌀 start spinner

              final (stickers, trayImage) =
                  await downloadStickersAndTrayImage(widget.stickerPack);

              String? result;

              try {
                result = await _handler.addStickerPack(
                  widget.stickerPack.identifier ?? 'unknown',
                  widget.stickerPack.name ?? '',
                  widget.stickerPack.publisher ?? '',
                  trayImage,
                  widget.stickerPack.publisherWebsite,
                  widget.stickerPack.privacyPolicyWebsite,
                  widget.stickerPack.licenseAgreementWebsite,
                  widget.stickerPack.animatedStickerPack ?? false,
                  stickers,
                  imageDataVersion:
                      widget.stickerPack.imageDataVersion ?? '1.0',
                );
              } on WhatsappStickersException catch (e) {
                if (e.cause?.toLowerCase() == 'sticker pack already added') {
                  log.i(
                      "ℹ️ WhatsApp says 'already added' — treating as success.");
                  result = 'already_added';
                } else {
                  log.e("❌ WhatsApp error: ${e.cause}");
                  if (mounted) {
                    await showAppErrorDialog(
                      context,
                      e.cause ?? 'Unknown error',
                      title: 'Couldn’t add to WhatsApp',
                    );
                  }
                  if (mounted) {
                    setState(() => _isProcessing = false);
                  }
                  return;
                }
              }

              if (result == 'add_successful' ||
                  result == 'success' ||
                  result == 'already_added') {
                log.i(
                    "✅ WhatsApp accepted/added ${widget.stickerPack.identifier}");
                await regenerateStickerConfigFile();
                await Future.delayed(const Duration(milliseconds: 500));

                Fluttertoast.showToast(
                  msg: hasUpdate
                      ? "✅ Sticker pack updated"
                      : "✅ Sticker pack added",
                  gravity: ToastGravity.BOTTOM,
                );

                if (mounted) {
                  setState(() {
                    _refreshStatus(); // refresh the icon
                    _isProcessing = false; // stop the spinner
                  });
                }
              } else {
                log.e("❌ WhatsApp did not accept the pack: $result");
                if (mounted) {
                  setState(() => _isProcessing = false);
                }
              }
            }
          : null,
    );
  }
}
