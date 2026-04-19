import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:nerds/models/user_pack.dart';
import 'package:nerds/services/local_storage_service.dart';
import 'package:nerds/utils/sticker_config_utils.dart';
import 'package:nerds/utils/sticker_webp_utils.dart';

class UserPackService extends ChangeNotifier {
  UserPackService._();
  static final UserPackService instance = UserPackService._();

  static const int minStickers = 3;
  static const int maxStickers = 30;
  static const String _idPrefix = 'user_local_';

  List<UserPack> _packs = [];

  List<UserPack> get packs => List.unmodifiable(_packs);

  Future<void> load() async {
    _packs = await LocalStorageService.instance.getUserPacks();
    var migrated = await _migratePacksToWebpIfNeeded();
    migrated = await _migrateTrayDimensionsIfNeeded() || migrated;
    migrated = await _migrateStickerCanvas512IfNeeded() || migrated;
    if (migrated) {
      await LocalStorageService.instance.saveUserPacks(_packs);
    }
    if (!kIsWeb &&
        Platform.isAndroid &&
        _packs.any((p) => p.id.startsWith(_idPrefix))) {
      await repairStickerPackConfigForUserPacks();
    }
    notifyListeners();
  }

  UserPack? getById(String id) {
    for (final pack in _packs) {
      if (pack.id == id) return pack;
    }
    return null;
  }

  Future<Directory> _packDirectory(String id) async {
    final root = await getApplicationDocumentsDirectory();
    return Directory(p.join(root.path, 'user_packs', id));
  }

  Future<void> createPack(String name, List<XFile> images) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Enter a pack name');
    }
    if (images.length < minStickers || images.length > maxStickers) {
      throw ArgumentError(
          'Choose between $minStickers and $maxStickers images (WhatsApp limit).');
    }

    final id =
        '$_idPrefix${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(0x7fffffff)}';
    final dir = await _packDirectory(id);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);

    final stickerPaths = <String>[];
    for (var i = 0; i < images.length; i++) {
      final destPath = p.join(dir.path, 'sticker_${i + 1}.webp');
      final raw = await images[i].readAsBytes();
      final webp = await encodeImageBytesToStickerWebP(raw);
      await File(destPath).writeAsBytes(webp);
      stickerPaths.add(destPath);
    }

    final trayPath = p.join(dir.path, 'tray.webp');
    final trayBytes = await encodeStickerBytesToTrayWebP(
      await File(stickerPaths.first).readAsBytes(),
    );
    await File(trayPath).writeAsBytes(trayBytes);

    final pack = UserPack(
      id: id,
      name: trimmed,
      createdAt: DateTime.now(),
      stickerPaths: stickerPaths,
      thumbnailPath: trayPath,
      packVersion: '1',
    );

    _packs = [..._packs, pack];
    await LocalStorageService.instance.saveUserPacks(_packs);
    notifyListeners();
  }

  /// Downloads [imageUrl] into an existing pack folder and appends to [stickerPaths].
  /// Bumps [UserPack.packVersion] by 1 (same scheme as server [imageDataVersion] — integer string).
  Future<void> addStickerFromUrl(
    String packId,
    String imageUrl, {
    String? fileNameHint,
  }) async {
    final dio = Dio();
    final response = await dio.get<Uint8List>(
      imageUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    final raw = response.data;
    if (raw == null || raw.isEmpty) {
      throw StateError('Empty image download');
    }
    await addStickerFromImageBytes(packId, raw);
  }

  /// Adds one photo from the device (gallery/camera) to an existing pack.
  /// Increments [UserPack.packVersion] by 1 so WhatsApp can show an update like server packs.
  Future<void> addStickerFromXFile(String packId, XFile file) async {
    final raw = await file.readAsBytes();
    if (raw.isEmpty) {
      throw StateError('Empty image');
    }
    await addStickerFromImageBytes(packId, raw);
  }

  /// Appends one encoded sticker; bumps pack version by 1.
  Future<void> addStickerFromImageBytes(String packId, Uint8List raw) async {
    final pack = getById(packId);
    if (pack == null) {
      throw ArgumentError('Pack not found');
    }
    if (pack.stickerPaths.length >= maxStickers) {
      throw ArgumentError(
          'This pack already has $maxStickers stickers (WhatsApp maximum).');
    }

    final dir = await _packDirectory(packId);
    if (!await dir.exists()) {
      throw StateError('Pack folder is missing on disk');
    }

    final nextIndex = pack.stickerPaths.length + 1;
    final destPath = p.join(dir.path, 'sticker_$nextIndex.webp');

    final webp = await encodeImageBytesToStickerWebP(raw);
    await File(destPath).writeAsBytes(webp);

    final newPaths = [...pack.stickerPaths, destPath];
    final newVersion = (_parsePackVersion(pack.packVersion) + 1).toString();

    final updated = UserPack(
      id: pack.id,
      name: pack.name,
      createdAt: pack.createdAt,
      stickerPaths: newPaths,
      thumbnailPath: pack.thumbnailPath,
      packVersion: newVersion,
    );

    _packs = _packs.map((e) => e.id == packId ? updated : e).toList();
    await LocalStorageService.instance.saveUserPacks(_packs);
    notifyListeners();
  }

  /// Removes the sticker at [index], deletes its file, and bumps [UserPack.packVersion] by 1.
  /// WhatsApp allows 3–30 stickers per pack; removal is blocked if it would leave fewer than
  /// [minStickers].
  /// If the first sticker is removed, [thumbnailPath] is regenerated from the new first sticker.
  Future<void> removeStickerAt(String packId, int index) async {
    final pack = getById(packId);
    if (pack == null) {
      throw ArgumentError('Pack not found');
    }
    if (index < 0 || index >= pack.stickerPaths.length) {
      throw ArgumentError('Invalid sticker index');
    }
    if (pack.stickerPaths.length <= minStickers) {
      throw ArgumentError(
        'A pack must keep at least $minStickers stickers for WhatsApp. '
        'Delete the whole pack if you want to remove it.',
      );
    }

    final removedPath = pack.stickerPaths[index];
    final newPaths = List<String>.from(pack.stickerPaths)..removeAt(index);

    try {
      final f = File(removedPath);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (e, st) {
      debugPrint('removeStickerAt: could not delete file: $e\n$st');
    }

    var thumb = pack.thumbnailPath;
    if (index == 0 && newPaths.isNotEmpty && thumb != null && thumb.isNotEmpty) {
      final firstFile = File(newPaths.first);
      if (await firstFile.exists()) {
        final trayBytes = await encodeStickerBytesToTrayWebP(
          await firstFile.readAsBytes(),
        );
        await File(thumb).writeAsBytes(trayBytes);
      }
    }

    final newVersion = (_parsePackVersion(pack.packVersion) + 1).toString();
    final updated = UserPack(
      id: pack.id,
      name: pack.name,
      createdAt: pack.createdAt,
      stickerPaths: newPaths,
      thumbnailPath: thumb,
      packVersion: newVersion,
    );

    _packs = _packs.map((e) => e.id == packId ? updated : e).toList();
    await LocalStorageService.instance.saveUserPacks(_packs);
    notifyListeners();
  }

  int _parsePackVersion(String? v) => int.tryParse(v ?? '1') ?? 1;

  /// Older builds stored picker files as PNG/JPEG; WhatsApp's config parser requires `.webp`.
  Future<bool> _migratePacksToWebpIfNeeded() async {
    var changed = false;
    final next = <UserPack>[];
    for (final pack in _packs) {
      final dir = await _packDirectory(pack.id);
      if (!await dir.exists()) {
        next.add(pack);
        continue;
      }
      final newPaths = <String>[];
      for (final path in pack.stickerPaths) {
        final updated = await _ensureStickerFileWebp(path);
        if (updated != path) changed = true;
        newPaths.add(updated);
      }
      String? thumb = pack.thumbnailPath;
      if (thumb != null && thumb.isNotEmpty) {
        final t = await _ensureStickerFileWebp(thumb);
        if (t != thumb) changed = true;
        thumb = t;
      }
      next.add(UserPack(
        id: pack.id,
        name: pack.name,
        createdAt: pack.createdAt,
        stickerPaths: newPaths,
        thumbnailPath: thumb,
        packVersion: pack.packVersion,
      ));
    }
    if (changed) {
      _packs = next;
    }
    return changed;
  }

  /// Older builds set [tray.webp] by copying a full sticker (often > 512 px). WhatsApp requires
  /// tray width/height in \[24, 512\] and ≤ 50 KB ([StickerPackValidator]).
  Future<bool> _migrateTrayDimensionsIfNeeded() async {
    var changed = false;
    for (final pack in _packs) {
      final thumb = pack.thumbnailPath;
      final stickers = pack.stickerPaths;
      if (thumb == null || thumb.isEmpty || stickers.isEmpty) continue;
      final thumbFile = File(thumb);
      final sticker0 = File(stickers.first);
      if (!await thumbFile.exists() || !await sticker0.exists()) continue;
      final trayBytes = await thumbFile.readAsBytes();
      if (!trayWebpExceedsWhatsappLimits(trayBytes)) continue;
      final fixed =
          await encodeStickerBytesToTrayWebP(await sticker0.readAsBytes());
      await thumbFile.writeAsBytes(fixed);
      changed = true;
    }
    return changed;
  }

  /// Older builds encoded stickers with min 512×512 but non-square dimensions; WhatsApp rejects those.
  Future<bool> _migrateStickerCanvas512IfNeeded() async {
    var any = false;
    final next = <UserPack>[];
    for (final pack in _packs) {
      var packTouched = false;
      for (final path in pack.stickerPaths) {
        final file = File(path);
        if (!await file.exists()) continue;
        if (p.extension(path).toLowerCase() != '.webp') continue;
        final bytes = await file.readAsBytes();
        if (!stickerWebpNeeds512SquareCanvas(bytes)) continue;
        final fixed = await encodeImageBytesToStickerWebP(bytes);
        await file.writeAsBytes(fixed);
        packTouched = true;
        any = true;
      }
      if (packTouched) {
        next.add(UserPack(
          id: pack.id,
          name: pack.name,
          createdAt: pack.createdAt,
          stickerPaths: pack.stickerPaths,
          thumbnailPath: pack.thumbnailPath,
          packVersion: (_parsePackVersion(pack.packVersion) + 1).toString(),
        ));
      } else {
        next.add(pack);
      }
    }
    if (any) {
      _packs = next;
    }
    return any;
  }

  /// If [absolutePath] is not `.webp`, replaces it with a WebP file next to it and removes the original.
  Future<String> _ensureStickerFileWebp(String absolutePath) async {
    if (p.extension(absolutePath).toLowerCase() == '.webp') {
      return absolutePath;
    }
    final file = File(absolutePath);
    if (!await file.exists()) {
      return absolutePath;
    }
    final bytes = await file.readAsBytes();
    final webp = await encodeImageBytesToStickerWebP(bytes);
    final newPath =
        p.join(p.dirname(absolutePath), '${p.basenameWithoutExtension(absolutePath)}.webp');
    await File(newPath).writeAsBytes(webp);
    if (newPath != absolutePath) {
      await file.delete();
    }
    return newPath;
  }

  Future<void> deletePack(String id) async {
    _packs = _packs.where((p) => p.id != id).toList();
    await LocalStorageService.instance.saveUserPacks(_packs);
    notifyListeners();

    final dir = await _packDirectory(id);
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e, st) {
      debugPrint('UserPackService.deletePack cleanup: $e\n$st');
    }
  }
}
