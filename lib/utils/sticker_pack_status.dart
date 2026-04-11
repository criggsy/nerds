import 'package:whatsapp_stickers_handler/whatsapp_stickers_handler.dart';
import '../models/sticker_data.dart';
import '../models/user_pack.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nerds/constants/constants.dart';

class StickerPackStatus {
  final bool isInstalled;
  final bool hasUpdate;
  final int? savedVersion;

  StickerPackStatus({
    required this.isInstalled,
    required this.hasUpdate,
    required this.savedVersion,
  });
}

Future<StickerPackStatus> getStickerPackStatus(StickerPacks pack) async {
  final isInstalled =
      await WhatsappStickersHandler().isStickerPackInstalled(pack.identifier!);
  final installedVersion =
      await WhatsappStickersHandler.getInstalledImageDataVersion(
          pack.identifier!);
  final currentVersion = int.tryParse(pack.imageDataVersion ?? '0') ?? 0;
  final hasUpdate = isInstalled && installedVersion != currentVersion;

  return StickerPackStatus(
    isInstalled: isInstalled,
    hasUpdate: hasUpdate,
    savedVersion: installedVersion,
  );
}

Future<StickerPackStatus> getUserPackStatus(UserPack pack) async {
  final isInstalled =
      await WhatsappStickersHandler().isStickerPackInstalled(pack.id);
  final installedVersion =
      await WhatsappStickersHandler.getInstalledImageDataVersion(pack.id);
  final currentVersion = int.tryParse(pack.packVersion ?? '1') ?? 1;
  final hasUpdate = isInstalled && installedVersion != currentVersion;

  return StickerPackStatus(
    isInstalled: isInstalled,
    hasUpdate: hasUpdate,
    savedVersion: installedVersion,
  );
}

/// Local sticker files for [WhatsappStickersHandler.addStickerPack].
(Map<String, List<String>>, String) userPackFilesForWhatsapp(UserPack pack) {
  const defaultEmojis = ['😀'];
  final stickers = <String, List<String>>{};
  for (final path in pack.stickerPaths) {
    stickers[WhatsappStickerImageHandler.fromFile(path).path] = defaultEmojis;
  }
  final thumb = pack.thumbnailPath;
  if (thumb == null || thumb.isEmpty) {
    throw StateError('User pack missing tray image');
  }
  final tray = WhatsappStickerImageHandler.fromFile(thumb).path;
  return (stickers, tray);
}

Future<(Map<String, List<String>>, String)> downloadStickersAndTrayImage(
    StickerPacks stickerPack) async {
  final Map<String, List<String>> stickers = {};
  final dio = Dio();

  final appDir = await getApplicationDocumentsDirectory();
  final stickersDir = Directory('${appDir.path}/${stickerPack.identifier}');
  await stickersDir.create(recursive: true);

  // Tray image
  final trayPath =
      "${stickersDir.path}/${stickerPack.trayImageFile!.toLowerCase()}";
  await dio.download(
    "$baseURL/sticker-packs/${stickerPack.identifier}/${stickerPack.trayImageFile}",
    trayPath,
  );
  final trayImage = WhatsappStickerImageHandler.fromFile(trayPath).path;

  // Stickers
  for (var e in stickerPack.stickers!) {
    final fileName = e.imageFile as String;
    final url = "$baseURL/sticker-packs/${stickerPack.identifier}/$fileName";
    final localPath = "${stickersDir.path}/$fileName";

    await dio.download(url, localPath);
    stickers[WhatsappStickerImageHandler.fromFile(localPath).path] =
        e.emojis as List<String>;
  }

  return (stickers, trayImage);
}
