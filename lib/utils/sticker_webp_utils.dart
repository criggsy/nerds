import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

/// WhatsApp requires each static sticker to be exactly this many pixels per side.
const int kWhatsAppStickerCanvasSize = 512;

/// WhatsApp sticker assets must be WebP ([ContentFileParser] enforces `.webp`).
///
/// Output is **exactly** [kWhatsAppStickerCanvasSize]×[kWhatsAppStickerCanvasSize] px.
/// (Using [FlutterImageCompress.compressWithList] with only `minWidth`/`minHeight` keeps aspect
/// ratio and produced tall/wide images; WhatsApp then fails in preview with errors such as
/// `handleStickerPackPreviewResult/failed`.)
Future<Uint8List> encodeImageBytesToStickerWebP(Uint8List bytes) async {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('Could not decode image for sticker');
  }
  final square = _composeSquareSticker512(decoded);
  final png = Uint8List.fromList(img.encodePng(square));
  const maxBytes = 100 * 1024;
  var quality = 90;
  Uint8List out = await FlutterImageCompress.compressWithList(
    png,
    minWidth: kWhatsAppStickerCanvasSize,
    minHeight: kWhatsAppStickerCanvasSize,
    quality: quality,
    format: CompressFormat.webp,
  );
  while (out.length > maxBytes && quality > 30) {
    quality -= 10;
    out = await FlutterImageCompress.compressWithList(
      png,
      minWidth: kWhatsAppStickerCanvasSize,
      minHeight: kWhatsAppStickerCanvasSize,
      quality: quality,
      format: CompressFormat.webp,
    );
  }
  return out;
}

/// `true` if the image is missing or not exactly 512×512 (needs re-export for WhatsApp).
bool stickerWebpNeeds512SquareCanvas(Uint8List bytes) {
  final im = img.decodeImage(bytes);
  if (im == null) return true;
  return im.width != kWhatsAppStickerCanvasSize ||
      im.height != kWhatsAppStickerCanvasSize;
}

/// Letterboxes (transparent) so the sticker fits in a 512×512 square.
img.Image _composeSquareSticker512(img.Image src) {
  const s = kWhatsAppStickerCanvasSize;
  final scale = math.min(s / src.width, s / src.height);
  final nw = math.max(1, (src.width * scale).round());
  final nh = math.max(1, (src.height * scale).round());
  final resized = img.copyResize(
    src,
    width: nw,
    height: nh,
    interpolation: img.Interpolation.linear,
  );
  final dest = img.Image(width: s, height: s, numChannels: 4);
  img.fill(dest, color: img.ColorUint8.rgba(0, 0, 0, 0));
  final ox = (s - resized.width) ~/ 2;
  final oy = (s - resized.height) ~/ 2;
  img.compositeImage(dest, resized, dstX: ox, dstY: oy);
  return dest;
}

/// True if [webpBytes] is missing, over 50 KB, or outside WhatsApp’s tray rules (24–512 px per side).
bool trayWebpExceedsWhatsappLimits(Uint8List webpBytes) {
  if (webpBytes.length > 50 * 1024) return true;
  final im = img.decodeImage(webpBytes);
  if (im == null) return true;
  return im.width < 24 ||
      im.width > 512 ||
      im.height < 24 ||
      im.height > 512;
}

/// Packs tray icon: each side in \[24, 512\] px, file ≤ 50 KB ([StickerPackValidator] on Android).
Future<Uint8List> encodeStickerBytesToTrayWebP(Uint8List stickerWebpBytes) async {
  final decoded = img.decodeImage(stickerWebpBytes);
  if (decoded == null) {
    throw StateError('Could not decode sticker for tray image');
  }
  final fitted = _fitTrayImageDimensions(decoded);
  final png = Uint8List.fromList(img.encodePng(fitted));
  const maxBytes = 50 * 1024;
  var quality = 85;
  Uint8List out = await FlutterImageCompress.compressWithList(
    png,
    minWidth: fitted.width,
    minHeight: fitted.height,
    quality: quality,
    format: CompressFormat.webp,
  );
  while (out.length > maxBytes && quality > 25) {
    quality -= 15;
    out = await FlutterImageCompress.compressWithList(
      png,
      minWidth: fitted.width,
      minHeight: fitted.height,
      quality: quality,
      format: CompressFormat.webp,
    );
  }
  return out;
}

/// Scales so width and height are within WhatsApp’s tray limits (24–512 px each).
img.Image _fitTrayImageDimensions(img.Image src) {
  const minSide = 24;
  const maxSide = 512;
  var w = src.width;
  var h = src.height;
  if (w < 1 || h < 1) return src;

  if (w > maxSide || h > maxSide) {
    final scale = math.min(maxSide / w, maxSide / h);
    w = (w * scale).round().clamp(1, maxSide);
    h = (h * scale).round().clamp(1, maxSide);
  }
  if (w < minSide || h < minSide) {
    final scale = math.max(minSide / w, minSide / h);
    w = (w * scale).ceil().clamp(minSide, maxSide);
    h = (h * scale).ceil().clamp(minSide, maxSide);
  }

  if (w == src.width && h == src.height) return src;
  return img.copyResize(
    src,
    width: w,
    height: h,
    interpolation: img.Interpolation.linear,
  );
}
