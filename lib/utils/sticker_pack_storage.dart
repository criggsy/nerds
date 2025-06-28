import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:nerds/utils/logger.dart';

Future<Map<String, dynamic>?> getInstalledStickerPackInfo(
    String identifier) async {
  final dir =
      await getApplicationSupportDirectory(); // Or getApplicationDocumentsDirectory()
  final file = File(
      '${dir.path}/content.json'); // 👈 this should match your native ConfigFileManager

  if (!await file.exists()) {
    log.w("⚠️ content.json not found at ${file.path}");
    return null;
  }

  final jsonString = await file.readAsString();
  final jsonMap = json.decode(jsonString);

  final packs = jsonMap['sticker_packs'] as List<dynamic>;
  for (final pack in packs) {
    if (pack['identifier'] == identifier) {
      return Map<String, dynamic>.from(pack);
    }
  }
  return null;
}
