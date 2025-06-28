import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'exceptions.dart';

class WhatsappStickersHandler {
  static const consumerWhatsAppPackageName = 'com.whatsapp';
  static const businessWhatsAppPackageName = 'com.whatsapp.w4b';
  static const MethodChannel _channel =
      MethodChannel('whatsapp_stickers_handler');

  /// Get the platform version
  static Future<String?> get platformVersion async {
    final String? version = await _channel.invokeMethod('platformVersion');
    return version;
  }

  static Future<int> getInstalledImageDataVersion(String identifier) async {
    try {
      final String? version =
          await _channel.invokeMethod('getInstalledImageDataVersion', {
        "identifier": identifier,
      });

      return int.tryParse(version ?? '0') ?? 0;
    } catch (e) {
      debugPrint("⚠️ Failed to fetch installed image data version: $e");
      return 0;
    }
  }

  /// Check it whatsapp is installed or not
  static Future<bool> get isWhatsAppInstalled async {
    return await _channel.invokeMethod("isWhatsAppInstalled");
  }

  /// Check if the WhatsApp consumer package is installed
  static Future<bool> get isWhatsAppConsumerAppInstalled async {
    return await _channel.invokeMethod("isWhatsAppConsumerAppInstalled");
  }

  /// Check if the WhatsApp business package is installed
  static Future<bool> get isWhatsAppSmbAppInstalled async {
    return await _channel.invokeMethod("isWhatsAppSmbAppInstalled");
  }

  /// Launch WhatsApp
  static void launchWhatsApp() {
    _channel.invokeMethod("launchWhatsApp");
  }

  /// Check if a sticker pack is installed on WhatsApp
  ///
  /// [stickerPackIdentifier] The sticker pack identifier
  Future<bool> isStickerPackInstalled(String stickerPackIdentifier) async {
    final bool result = await _channel.invokeMethod(
        "isStickerPackInstalled", {"identifier": stickerPackIdentifier});
    return result;
  }

  /// Add a sticker pack to whatsapp.
  Future<dynamic> addStickerPack(
      String identifier,
      String name,
      String publisher,
      String trayImageFileName,
      String? publisherWebsite,
      String? privacyPolicyWebsite,
      String? licenseAgreementWebsite,
      bool? animatedStickerPack,
      Map<String, List<String>> stickers,
      {String imageDataVersion = '1.0'} // <-- add this optional parameter
      ) async {
    try {
      final payload = <String, dynamic>{
        'identifier': identifier,
        'name': name,
        'publisher': publisher,
        'trayImageFileName': trayImageFileName,
        'publisherWebsite': publisherWebsite,
        'privacyPolicyWebsite': privacyPolicyWebsite,
        'licenseAgreementWebsite': licenseAgreementWebsite,
        'animatedStickerPack': animatedStickerPack,
        'stickers': stickers,
        'imageDataVersion': imageDataVersion, // <-- send this to native
      };

      return await _channel.invokeMethod('addStickerPack', payload);
    } on PlatformException catch (e) {
      switch (e.code) {
        case WhatsappStickersFileNotFoundException.code:
          throw WhatsappStickersFileNotFoundException(e.message);
        case WhatsappStickersNumOutsideAllowableRangeException.code:
          throw WhatsappStickersNumOutsideAllowableRangeException(e.message);
        case WhatsappStickersUnsupportedImageFormatException.code:
          throw WhatsappStickersUnsupportedImageFormatException(e.message);
        case WhatsappStickersImageTooBigException.code:
          throw WhatsappStickersImageTooBigException(e.message);
        case WhatsappStickersIncorrectImageSizeException.code:
          throw WhatsappStickersIncorrectImageSizeException(e.message);
        case WhatsappStickersAnimatedImagesNotSupportedException.code:
          throw WhatsappStickersAnimatedImagesNotSupportedException(e.message);
        case WhatsappStickersTooManyEmojisException.code:
          throw WhatsappStickersTooManyEmojisException(e.message);
        case WhatsappStickersEmptyStringException.code:
          throw WhatsappStickersEmptyStringException(e.message);
        case WhatsappStickersStringTooLongException.code:
          throw WhatsappStickersStringTooLongException(e.message);
        default:
          throw WhatsappStickersException(e.message);
      }
    }
  }
}

class WhatsappStickerImageHandler {
  final String path;

  WhatsappStickerImageHandler._internal(this.path);

  factory WhatsappStickerImageHandler.fromAsset(String asset) {
    return WhatsappStickerImageHandler._internal('assets://$asset');
  }

  factory WhatsappStickerImageHandler.fromFile(String file) {
    return WhatsappStickerImageHandler._internal('file://$file');
  }
}
