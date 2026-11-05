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

  // 1) Free and instant: works when the background is one plain color.
  try {
    final quick = await _floodCutout(photo);
    if (quick != null) return quick;
  } catch (_) {
    // try the AI next
  }

  // 2) Busy background: ask the AI for the outline.
  if (!aiConfigured) return null;
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
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final b = (data['box'] as List).map((n) => (n as num).toDouble()).toList();
    final mask = base64Decode(data['mask'] as String);
    final png = await _applyMask(photo, Rect.fromLTRB(b[0], b[1], b[2], b[3]), mask);
    return base64Encode(png);
  } catch (_) {
    return null;
  }
}

/// Crops the photo to the item's box and removes everything outside the AI's mask.
Future<Uint8List> _applyMask(Uint8List photo, Rect box, Uint8List maskPng) async {
  final img = await decodeImageFromList(photo);
  final mask = await decodeImageFromList(maskPng);
  final src = Rect.fromLTRB(box.left * img.width, box.top * img.height,
      box.right * img.width, box.bottom * img.height);
  // Keep files small: the longest side is at most 400 pixels.
  final scale = min(1.0, 400 / max(src.width, src.height));
  final w = max(1, (src.width * scale).round()), h = max(1, (src.height * scale).round());
  final dst = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());

  Future<Uint8List> pixels(ui.Image image, Rect from) async {
    final rec = ui.PictureRecorder();
    ui.Canvas(rec, dst).drawImageRect(image, from, dst, ui.Paint()..filterQuality = ui.FilterQuality.medium);
    final out = await rec.endRecording().toImage(w, h);
    final d = (await out.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
  }

  final px = await pixels(img, src);
  final mp = await pixels(mask, Rect.fromLTWH(0, 0, mask.width.toDouble(), mask.height.toDouble()));
  // The mask is a gray map (white = item). Dark pixels are background.
  final bg = Uint8List(w * h);
  for (var p = 0; p < w * h; p++) {
    final lum = mp[p * 4] * 0.3 + mp[p * 4 + 1] * 0.59 + mp[p * 4 + 2] * 0.11;
    bg[p] = lum < 128 ? 1 : 0;
  }
  final kept = _cleanBg(bg, w, h);
  // All-white or all-black means the AI's outline failed.
  if (kept < 0.06 || kept > 0.97) throw Exception('bad mask');
  return _cropAndEncode(px, w, h, bg);
}

/// Tidies a background map: keeps only the biggest piece of clothing, fills
/// small holes inside it, and returns the share of the picture that is clothing.
double _cleanBg(Uint8List bg, int w, int h) {
  final n = w * h;
  final mark = Int32List(n);
  var touchesEdge = false;

  /// Collects the connected pixels around [start] whose value is [value].
  List<int> region(int start, int value, int id) {
    final cells = <int>[];
    final stack = <int>[start];
    mark[start] = id;
    touchesEdge = false;
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      cells.add(p);
      final x = p % w, y = p ~/ w;
      if (x == 0 || y == 0 || x == w - 1 || y == h - 1) touchesEdge = true;
      void visit(int q) {
        if (mark[q] == 0 && bg[q] == value) {
          mark[q] = id;
          stack.add(q);
        }
      }

      if (x > 0) visit(p - 1);
      if (x < w - 1) visit(p + 1);
      if (y > 0) visit(p - w);
      if (y < h - 1) visit(p + w);
    }
    return cells;
  }

  var id = 0;
  List<int> best = [];
  for (var p = 0; p < n; p++) {
    if (bg[p] == 0 && mark[p] == 0) {
      final cells = region(p, 0, ++id);
      if (cells.length > best.length) best = cells;
    }
  }
  if (best.isEmpty) return 0;
  final keep = Uint8List(n);
  for (final p in best) {
    keep[p] = 1;
  }
  for (var p = 0; p < n; p++) {
    bg[p] = keep[p] == 1 ? 0 : 1;
  }

  // Fill small holes that are not connected to the outside.
  mark.fillRange(0, n, 0);
  for (var p = 0; p < n; p++) {
    if (bg[p] == 1 && mark[p] == 0) {
      final cells = region(p, 1, ++id);
      if (!touchesEdge && cells.length < n * 0.015) {
        for (final q in cells) {
          bg[q] = 0;
        }
      }
    }
  }
  return best.length / n;
}

/// Asks the image AI for a front-facing photo of the clothing item, posed like
/// the model (standing straight, arms down), on a green background (magenta when
/// [green] is true, so green clothes survive), then makes the background
/// transparent. Needs billing on your Google key.
Future<({String? image, String? error})> flattenClothing(String imageBase64,
    {String category = 'Tops', bool green = false}) async {
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
            'category': category,
            'bg': green ? 'magenta' : 'green',
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
    final png = await _keyOutGreen(base64Decode(data['image'] as String), magenta: green);
    return (image: base64Encode(png), error: null);
  } catch (_) {
    return (image: null, error: 'Could not make a flat photo. Try again.');
  }
}

/// Turns the green (or magenta) background transparent, starting from the edges
/// so the same colour inside the clothing is kept, then crops to the item.
Future<Uint8List> _keyOutGreen(Uint8List bytes, {bool magenta = false}) async {
  final img = await decodeImageFromList(bytes);
  final w = img.width, h = img.height;
  final bd = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final px = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);

  bool greenish(int p, int margin) {
    final r = px[p * 4], g = px[p * 4 + 1], b = px[p * 4 + 2];
    if (magenta) return r > 120 && b > 120 && r - g > margin && b - g > margin;
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
  if (dev / c > 24) return null; // edges are busy, so leave it to the AI
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

  final kept = _cleanBg(bg, w, h);
  if (kept < 0.08 || kept > 0.92) return null; // nothing to cut, or it ate the clothes
  return base64Encode(await _cropAndEncode(px, w, h, bg));
}
