import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:exif/exif.dart';
import 'package:image/image.dart' as img;

/// On-device draft segmentation: flood-fill from a tap using color similarity to the seed pixel.
/// This is a heuristic (not ML); users refine with brushes afterward.
void floodFillFromTap({
  required img.Image image,
  required Uint8List mask,
  required int startX,
  required int startY,
  required int tolerance,
  required bool addToMask,
}) {
  final w = image.width;
  final h = image.height;
  if (startX < 0 ||
      startY < 0 ||
      startX >= w ||
      startY >= h ||
      tolerance < 0) {
    return;
  }

  final seed = image.getPixel(startX, startY);
  final sr = seed.r.toInt();
  final sg = seed.g.toInt();
  final sb = seed.b.toInt();

  bool matches(int x, int y) {
    final p = image.getPixel(x, y);
    return (p.r.toInt() - sr).abs() <= tolerance &&
        (p.g.toInt() - sg).abs() <= tolerance &&
        (p.b.toInt() - sb).abs() <= tolerance;
  }

  if (!matches(startX, startY)) {
    return;
  }

  final visited = Uint8List(w * h);
  final stack = <int>[startY * w + startX];

  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    if (visited[i] != 0) continue;
    visited[i] = 1;
    final x = i % w;
    final y = i ~/ w;

    if (addToMask) {
      mask[i] = 255;
    } else {
      mask[i] = 0;
    }

    if (x > 0) {
      final j = i - 1;
      if (visited[j] == 0 && matches(x - 1, y)) stack.add(j);
    }
    if (x + 1 < w) {
      final j = i + 1;
      if (visited[j] == 0 && matches(x + 1, y)) stack.add(j);
    }
    if (y > 0) {
      final j = i - w;
      if (visited[j] == 0 && matches(x, y - 1)) stack.add(j);
    }
    if (y + 1 < h) {
      final j = i + w;
      if (visited[j] == 0 && matches(x, y + 1)) stack.add(j);
    }
  }
}

/// Paint a solid circle on [mask] (values 0–255).
void paintBrushCircle({
  required int width,
  required int height,
  required Uint8List mask,
  required double cx,
  required double cy,
  required double radius,
  required bool foreground,
}) {
  final r = radius.ceil();
  final value = foreground ? 255 : 0;
  final x0 = (cx - r).floor().clamp(0, width - 1);
  final x1 = (cx + r).ceil().clamp(0, width - 1);
  final y0 = (cy - r).floor().clamp(0, height - 1);
  final y1 = (cy + r).ceil().clamp(0, height - 1);
  final r2 = radius * radius;

  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final dx = x - cx;
      final dy = y - cy;
      if (dx * dx + dy * dy <= r2) {
        mask[y * width + x] = value;
      }
    }
  }
}

/// Semi-transparent dark grey overlay where [mask] > 0 so the original photo stays visible while editing.
Uint8List? buildMaskHighlightPng(img.Image image, Uint8List mask) {
  var any = false;
  for (var i = 0; i < mask.length; i++) {
    if (mask[i] > 0) {
      any = true;
      break;
    }
  }
  if (!any) return null;

  final w = image.width;
  final h = image.height;
  final ov = img.Image(width: w, height: h, numChannels: 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final a = mask[i];
      if (a == 0) {
        ov.setPixelRgba(x, y, 0, 0, 0, 0);
      } else {
        final alpha = (a * 0.62).round().clamp(40, 235);
        ov.setPixelRgba(x, y, 6, 6, 10, alpha);
      }
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (mask[i] == 0) continue;
      var edge = false;
      if (x > 0 && mask[i - 1] == 0) edge = true;
      if (x + 1 < w && mask[i + 1] == 0) edge = true;
      if (y > 0 && mask[i - w] == 0) edge = true;
      if (y + 1 < h && mask[i + w] == 0) edge = true;
      if (!edge) continue;
      final ba = (mask[i] * 0.5).round().clamp(90, 255);
      ov.setPixelRgba(x, y, 245, 245, 250, ba);
    }
  }
  return Uint8List.fromList(img.encodePng(ov));
}

/// Composed RGBA image: [mask] applied as straight alpha (same size as [source]).
img.Image composeMaskedImage(img.Image source, Uint8List mask) {
  final w = source.width;
  final h = source.height;
  final out = img.Image(width: w, height: h, numChannels: 4);

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final m = mask[i];
      final p = source.getPixel(x, y);
      final origA = p.a.toInt();
      if (m == 0) {
        out.setPixelRgba(x, y, 0, 0, 0, 0);
      } else {
        final a = (m * origA) ~/ 255;
        out.setPixelRgba(
          x,
          y,
          p.r.toInt(),
          p.g.toInt(),
          p.b.toInt(),
          a.clamp(0, 255),
        );
      }
    }
  }

  return out;
}

/// Applies [mask] as alpha, **crops to the tight bounding box of the visible (masked) area**,
/// then returns PNG bytes. Downstream sticker export letterboxes into 512×512.
Uint8List composeMaskedPng(img.Image source, Uint8List mask) {
  final composed = composeMaskedImage(source, mask);
  final trimmed = img.trim(composed, mode: img.TrimMode.transparent);
  return Uint8List.fromList(img.encodePng(trimmed));
}

/// Downscale large photos so tap-fill stays responsive on phones.
img.Image maybeDownscale(img.Image src, {int maxSide = 900}) {
  final sw = src.width;
  final sh = src.height;
  if (sw <= maxSide && sh <= maxSide) return src;
  final scale = maxSide / (sw > sh ? sw : sh);
  final nw = (sw * scale).round();
  final nh = (sh * scale).round();
  return img.copyResize(src, width: nw, height: nh, interpolation: img.Interpolation.linear);
}

/// True when [bytes] are JPEG (SOI marker). Used to avoid double-applying EXIF rotation.
bool isJpegFileBytes(Uint8List bytes) =>
    bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xd8;

/// Decodes via Flutter’s [ui.instantiateImageCodec] first (same engine as [Image.file] /
/// gallery previews), then converts to [img.Image]. That matches phone JPEG orientation
/// reliably; [package:image]’s pure-Dart JPEG path can disagree with the platform on some files.
///
/// Falls back to [img.decodeImage] and EXIF handling when the engine cannot decode the bytes.
Future<img.Image?> decodeImageWithBakedOrientation(Uint8List bytes) async {
  final viaEngine = await _decodeImageViaFlutterUi(bytes);
  if (viaEngine != null) {
    return viaEngine;
  }

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  if (isJpegFileBytes(bytes)) {
    return decoded;
  }
  if (decoded.exif.imageIfd.hasOrientation) {
    return img.bakeOrientation(decoded);
  }

  final orient = await readExifOrientationFromBytes(bytes);
  if (orient != null && orient >= 1 && orient <= 8) {
    decoded.exif.imageIfd.orientation = orient;
  }
  return img.bakeOrientation(decoded);
}

Future<img.Image?> _decodeImageViaFlutterUi(Uint8List bytes) async {
  ui.Codec? codec;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final uiImage = frame.image;
    try {
      final w = uiImage.width;
      final h = uiImage.height;
      final bd = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) return null;
      final rgba = bd.buffer.asUint8List();
      if (rgba.length < w * h * 4) return null;
      return img.Image.fromBytes(
        width: w,
        height: h,
        bytes: rgba.buffer,
        bytesOffset: rgba.offsetInBytes,
        numChannels: 4,
      );
    } finally {
      uiImage.dispose();
    }
  } catch (_) {
    return null;
  } finally {
    codec?.dispose();
  }
}

/// EXIF Orientation tag (1–8), or null if missing / unreadable.
Future<int?> readExifOrientationFromBytes(Uint8List bytes) async {
  try {
    final tags = await readExifFromBytes(bytes);
    return _orientationFromExifTags(tags);
  } catch (_) {
    return null;
  }
}

int? _orientationFromExifTags(Map<String, IfdTag> tags) {
  for (final key in ['Image Orientation', 'EXIF Orientation']) {
    final t = tags[key];
    if (t != null) {
      final v = t.values.firstAsInt();
      if (v >= 1 && v <= 8) return v;
    }
  }
  for (final e in tags.entries) {
    if (e.key.endsWith(' Orientation')) {
      final v = e.value.values.firstAsInt();
      if (v >= 1 && v <= 8) return v;
    }
  }
  return null;
}

