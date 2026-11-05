import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'main.dart';

/// Asks the AI for the outline of the clothing item, then makes everything
/// outside that outline transparent. Returns a new base64 PNG, or null if
/// anything goes wrong (the caller keeps the original photo).
Future<String?> removeBackground(String imageBase64) async {
  final photo = base64Decode(imageBase64);

  // 1) Ask the AI for the outline (best for busy backgrounds).
  if (aiConfigured) {
    try {
      final isPng = photo.length > 3 && photo[0] == 0x89 && photo[1] == 0x50;
      final res = await http
          .post(
            Uri.parse(aiEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'mode': 'cutout',
              'image': imageBase64,
              'mime': isPng ? 'image/png' : 'image/jpeg',
            }),
          )
          .timeout(const Duration(seconds: 40));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final b = (data['box'] as List).map((n) => (n as num).toDouble()).toList();
        final mask = base64Decode(data['mask'] as String);
        final png = await _applyMask(photo, Rect.fromLTRB(b[0], b[1], b[2], b[3]), mask);
        return base64Encode(png);
      }
    } catch (_) {
      // fall through to the free method below
    }
  }

  // 2) No AI (or it failed): remove the plain background around the edges.
  try {
    return await _floodCutout(photo);
  } catch (_) {
    return null;
  }
}

/// Crops the photo to the item's box and keeps only the pixels inside the mask.
Future<Uint8List> _applyMask(Uint8List photo, Rect box, Uint8List maskPng) async {
  final img = await decodeImageFromList(photo);
  final mask = await decodeImageFromList(maskPng);
  // A good mask is partly white and partly black. All-white or all-black means it failed.
  final md = (await mask.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  var on = 0;
  for (var i = 0; i < md.lengthInBytes; i += 4) {
    if (md.getUint8(i) > 127) on++;
  }
  final frac = on / (mask.width * mask.height);
  if (frac < 0.06 || frac > 0.97) throw Exception('bad mask');
  final src = Rect.fromLTRB(box.left * img.width, box.top * img.height,
      box.right * img.width, box.bottom * img.height);
  // Keep files small: the longest side is at most 400 pixels.
  final scale = min(1.0, 400 / max(src.width, src.height));
  final dst = Rect.fromLTWH(0, 0, src.width * scale, src.height * scale);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, dst);
  canvas.saveLayer(dst, ui.Paint());
  canvas.drawImageRect(img, src, dst, ui.Paint());
  // The mask is a gray map (white = item). Turn brightness into transparency,
  // with a fairly sharp edge, and keep only what it covers.
  canvas.drawImageRect(
    mask,
    Rect.fromLTWH(0, 0, mask.width.toDouble(), mask.height.toDouble()),
    dst,
    ui.Paint()
      ..blendMode = ui.BlendMode.dstIn
      ..colorFilter = const ColorFilter.matrix(<double>[
        0, 0, 0, 0, 0,
        0, 0, 0, 0, 0,
        0, 0, 0, 0, 0,
        0.85, 2.86, 0.29, 0, -480,
      ]),
  );
  canvas.restore();

  final out = await recorder.endRecording().toImage(dst.width.round(), dst.height.round());
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Asks the image AI for a clean flat photo of the clothing item (on a green
/// background), then makes the green transparent. Needs billing on your Google key.
Future<({String? image, String? error})> flattenClothing(String imageBase64) async {
  if (!aiConfigured) return (image: null, error: 'Add your AI address first.');
  try {
    final photo = base64Decode(imageBase64);
    final isPng = photo.length > 3 && photo[0] == 0x89 && photo[1] == 0x50;
    final res = await http
        .post(
          Uri.parse(aiEndpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'mode': 'flatten',
            'image': imageBase64,
            'mime': isPng ? 'image/png' : 'image/jpeg',
          }),
        )
        .timeout(const Duration(seconds: 90));
    if (res.statusCode == 403) {
      return (image: null, error: 'Flat photos are turned off. See worker/SETUP.md.');
    }
    if (res.statusCode != 200) {
      return (image: null, error: 'The image AI said no. It may need billing turned on.');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final png = await _keyOutGreen(base64Decode(data['image'] as String));
    return (image: base64Encode(png), error: null);
  } catch (_) {
    return (image: null, error: 'Could not make a flat photo. Try again.');
  }
}

/// Turns the green background transparent (starting from the edges, so green
/// inside the clothing is kept), then crops to the item and shrinks it.
Future<Uint8List> _keyOutGreen(Uint8List bytes) async {
  final img = await decodeImageFromList(bytes);
  final w = img.width, h = img.height;
  final bd = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final px = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);

  bool greenish(int p, int margin) {
    final r = px[p * 4], g = px[p * 4 + 1], b = px[p * 4 + 2];
    return g > 120 && g - r > margin && g - b > margin;
  }

  final bg = Uint8List(w * h);
  final stack = <int>[];
  void push(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final p = y * w + x;
    if (bg[p] == 1 || !greenish(p, 60)) return;
    bg[p] = 1;
    stack.add(p);
  }

  for (var x = 0; x < w; x++) {
    push(x, 0);
    push(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    push(0, y);
    push(w - 1, y);
  }
  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    final x = p % w, y = p ~/ w;
    push(x + 1, y);
    push(x - 1, y);
    push(x, y + 1);
    push(x, y - 1);
  }

  // Also clear a one-pixel green fringe along the edge of the item.
  final fringe = <int>[];
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final p = y * w + x;
      if (bg[p] == 0 &&
          greenish(p, 25) &&
          (bg[p - 1] == 1 || bg[p + 1] == 1 || bg[p - w] == 1 || bg[p + w] == 1)) {
        fringe.add(p);
      }
    }
  }
  for (final p in fringe) {
    bg[p] = 1;
  }

  return _cropAndEncode(px, w, h, bg);
}

/// Makes the pixels marked in [bg] transparent, crops to what is left and
/// shrinks it to at most 400 pixels. Returns PNG bytes.
Future<Uint8List> _cropAndEncode(Uint8List px, int w, int h, Uint8List bg) async {
  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var p = 0; p < w * h; p++) {
    if (bg[p] == 1) {
      px[p * 4] = 0;
      px[p * 4 + 1] = 0;
      px[p * 4 + 2] = 0;
      px[p * 4 + 3] = 0;
    } else {
      final x = p % w, y = p ~/ w;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) throw Exception('nothing left');

  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, done.complete);
  final clean = await done.future;

  final src = Rect.fromLTRB(minX.toDouble(), minY.toDouble(), maxX + 1.0, maxY + 1.0);
  final scale = min(1.0, 400 / max(src.width, src.height));
  final dst = Rect.fromLTWH(0, 0, src.width * scale, src.height * scale);
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder, dst).drawImageRect(clean, src, dst, ui.Paint());
  final out = await recorder.endRecording().toImage(dst.width.round(), dst.height.round());
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Free fallback that needs no AI: the colour around the edge of the photo is
/// treated as the background, and everything connected to it is removed.
/// Works best on clothes laid on a plain floor, bed or wall.
Future<String?> _floodCutout(Uint8List photo) async {
  final img = await decodeImageFromList(photo);
  final w = img.width, h = img.height;
  final bd = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final px = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);

  // Average colour of the edge pixels is the background colour.
  var r = 0, g = 0, b = 0, n = 0;
  void sample(int x, int y) {
    final i = (y * w + x) * 4;
    r += px[i];
    g += px[i + 1];
    b += px[i + 2];
    n++;
  }

  for (var x = 0; x < w; x += 2) {
    sample(x, 0);
    sample(x, h - 1);
  }
  for (var y = 0; y < h; y += 2) {
    sample(0, y);
    sample(w - 1, y);
  }
  final br = r / n, bgG = g / n, bb = b / n;
  double dist(int p) {
    final i = p * 4;
    final dr = px[i] - br, dg = px[i + 1] - bgG, db = px[i + 2] - bb;
    return sqrt(dr * dr + dg * dg + db * db);
  }

  // The more uneven the edge, the more forgiving we are.
  var dev = 0.0, c = 0;
  for (var x = 0; x < w; x += 2) {
    dev += dist(x) + dist((h - 1) * w + x);
    c += 2;
  }
  for (var y = 0; y < h; y += 2) {
    dev += dist(y * w) + dist(y * w + w - 1);
    c += 2;
  }
  final tol = (dev / c * 2.5).clamp(34.0, 75.0);

  final bg = Uint8List(w * h);
  final stack = <int>[];
  void push(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final p = y * w + x;
    if (bg[p] == 1 || dist(p) > tol) return;
    bg[p] = 1;
    stack.add(p);
  }

  for (var x = 0; x < w; x++) {
    push(x, 0);
    push(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    push(0, y);
    push(w - 1, y);
  }
  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    final x = p % w, y = p ~/ w;
    push(x + 1, y);
    push(x - 1, y);
    push(x, y + 1);
    push(x, y - 1);
  }

  var removed = 0;
  for (var p = 0; p < w * h; p++) {
    removed += bg[p];
  }
  final share = removed / (w * h);
  if (share < 0.08 || share > 0.9) return null; // nothing to cut, or it ate the clothes
  return base64Encode(await _cropAndEncode(px, w, h, bg));
}
