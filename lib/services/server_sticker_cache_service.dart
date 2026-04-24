import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:nerds/constants/constants.dart';
import 'package:nerds/models/sticker_data.dart';
import 'package:nerds/utils/logger.dart';

/// Caches server sticker assets locally for offline selection in the editor.
///
/// Refresh strategy: attempt a full refresh once per app launch.
class ServerStickerCacheService {
  ServerStickerCacheService._();
  static final ServerStickerCacheService instance = ServerStickerCacheService._();

  static const String _rootDirName = 'server_sticker_cache';
  static const String _metaFileName = 'sticker_packs.json';

  bool _refreshing = false;

  Future<Directory> _rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, _rootDirName));
  }

  Future<File> _metaFile() async {
    final root = await _rootDir();
    return File(p.join(root.path, _metaFileName));
  }

  /// Reads cached server manifest and returns parsed sticker data (or null if absent/corrupt).
  Future<StickerData?> loadCachedStickerData() async {
    try {
      final file = await _metaFile();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return StickerData.fromJson(decoded);
    } catch (e) {
      log.e('ServerStickerCacheService.loadCachedStickerData: $e');
      return null;
    }
  }

  /// Absolute local path for a cached server sticker/tray image.
  Future<String> localAssetPath(String packId, String fileName) async {
    final root = await _rootDir();
    return p.join(root.path, 'packs', packId, fileName);
  }

  /// Pulls latest manifest and assets from server and replaces local cache atomically.
  ///
  /// If refresh fails, existing cache remains untouched.
  Future<void> refreshFromServer() async {
    if (_refreshing) return;
    _refreshing = true;
    final root = await _rootDir();
    final temp = Directory('${root.path}_tmp');
    try {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
      await temp.create(recursive: true);

      final dio = Dio();
      final res = await dio.get<Map<String, dynamic>>('$baseURL/json/sticker_packs.json');
      final payload = res.data;
      if (payload == null) {
        throw StateError('Empty server sticker manifest');
      }
      final data = StickerData.fromJson(payload);

      for (final pack in data.stickerPacks ?? <StickerPacks>[]) {
        final id = pack.identifier;
        if (id == null || id.isEmpty || _unsafeSegment(id)) continue;
        final packDir = Directory(p.join(temp.path, 'packs', id));
        await packDir.create(recursive: true);

        final tray = pack.trayImageFile;
        if (tray != null && tray.isNotEmpty && !_unsafeSegment(tray)) {
          final trayOut = p.join(packDir.path, tray);
          await Directory(p.dirname(trayOut)).create(recursive: true);
          await dio.download('$baseURL/sticker-packs/$id/$tray', trayOut);
        }

        for (final s in pack.stickers ?? <Stickers>[]) {
          final file = s.imageFile;
          if (file == null || file.isEmpty || _unsafeSegment(file)) continue;
          final out = p.join(packDir.path, file);
          await Directory(p.dirname(out)).create(recursive: true);
          await dio.download('$baseURL/sticker-packs/$id/$file', out);
        }
      }

      await File(p.join(temp.path, _metaFileName)).writeAsString(jsonEncode(payload));

      if (await root.exists()) {
        await root.delete(recursive: true);
      }
      await temp.rename(root.path);
      log.i('✅ Server sticker cache refreshed');
    } catch (e) {
      log.e('❌ Server sticker cache refresh failed: $e');
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    } finally {
      _refreshing = false;
    }
  }

  bool _unsafeSegment(String s) =>
      s.contains('..') || s.startsWith('/') || s.startsWith(r'\');
}

