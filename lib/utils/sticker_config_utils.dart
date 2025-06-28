import 'package:flutter/services.dart';
import 'package:nerds/utils/logger.dart';

Future<void> regenerateStickerConfigFile() async {
  const platform = MethodChannel('whatsapp_stickers_handler');
  try {
    log.i("📣 Invoking platform method: regenerateConfigFile");
    final result = await platform.invokeMethod('regenerateConfigFile');
    log.i("✅ Platform responded: $result");
  } on PlatformException catch (e) {
    log.e("❌ PlatformException: ${e.message}");
  } catch (e) {
    log.e("❌ Unknown error during config regeneration: $e");
  }
}
