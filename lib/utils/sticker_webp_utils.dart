import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// WhatsApp sticker assets must be WebP ([ContentFileParser] enforces `.webp`).
Future<Uint8List> encodeImageBytesToStickerWebP(Uint8List bytes) {
  return FlutterImageCompress.compressWithList(
    bytes,
    minWidth: 512,
    minHeight: 512,
    quality: 90,
    format: CompressFormat.webp,
  );
}
