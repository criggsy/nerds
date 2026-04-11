import 'package:dio/dio.dart';
import 'package:nerds/constants/constants.dart';
import 'package:nerds/models/repo_item.dart';
import 'package:nerds/utils/logger.dart';

class RepoService {
  static final RepoService _instance = RepoService._internal();
  static RepoService get instance => _instance;

  late Dio dio;
  Response? data;
  late List<RepoItem> repoItems;

  RepoService._internal();

  Future<List<RepoItem>> getStickerPacks() async {
    return repoItems;
  }

  /// 📦 Loads sticker data from remote source
  Future<void> loadStickers() async {
    try {
      dio = Dio();
      data = await dio.get("$baseURL/json/file_list.json");

      if (data?.data != null) {
        final Map<String, dynamic> fileList = data!.data;
        repoItems = fileList.entries.map((entry) {
          final folderName = entry.key;
          final imageFiles = List<String>.from(entry.value);

          return RepoItem(
            name: folderName,
            path: "stickers/$folderName",
            packVersion: "1.0",
            isFolder: true,
            children: imageFiles
                .map((fileName) => RepoItem(
                      name: fileName,
                      path: "stickers/$folderName/$fileName",
                      packVersion: "1.0",
                      isFolder: false,
                    ))
                .toList(),
          );
        }).toList();

        log.i("✅ File list data loaded successfully");
      } else {
        log.w("⚠️ Data is null");
      }
    } catch (e) {
      log.e("❌ Error loading file list: $e");
    }
  }
}
