import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'main.dart';

Color _hex(Object? v, Color fallback) {
  final t = v?.toString() ?? '';
  if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(t)) return fallback;
  return Color(int.parse('FF${t.substring(1)}', radix: 16));
}

String _hexStr(Color c) => '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

// Color words (English and Indonesian) to a typical shade. The longest match
// wins, so "light blue" beats "blue"; specific shades are listed before basic ones.
const _colorWords = <String, String>{
  'light blue': '#9EC3E6', 'sky blue': '#87BCE8', 'baby blue': '#A9CBEA', 'biru muda': '#9EC3E6',
  'dark green': '#2F5233', 'hijau tua': '#2F5233', 'olive': '#6B6B3A', 'army': '#5B5E3A',
  'off white': '#F2EEE3', 'broken white': '#F2EEE3', 'cream': '#EFE3C8', 'krem': '#EFE3C8',
  'beige': '#D8C3A0', 'khaki': '#C3B091', 'tan': '#C8A27A', 'camel': '#BF8F5B', 'mocca': '#9C7A5B',
  'navy': '#22305A', 'denim': '#3F5E8C', 'maroon': '#6E1F2B', 'burgundy': '#7A2234', 'marun': '#6E1F2B',
  'charcoal': '#3A3B3F', 'abu': '#9A9A9E', 'grey': '#9A9A9E', 'gray': '#9A9A9E', 'silver': '#C0C0C4',
  'black': '#222222', 'hitam': '#222222', 'white': '#F7F7F5', 'putih': '#F7F7F5',
  'blue': '#3B6FB6', 'biru': '#3B6FB6', 'green': '#4E8A4E', 'hijau': '#4E8A4E', 'mint': '#A8DCC4',
  'red': '#C94040', 'merah': '#C94040', 'pink': '#EBA3B8', 'merah muda': '#EBA3B8', 'purple': '#7B5BA6',
  'ungu': '#7B5BA6', 'lilac': '#C3A9DB', 'lavender': '#C3A9DB', 'yellow': '#E8C547', 'kuning': '#E8C547',
  'mustard': '#C9A227', 'orange': '#E07B39', 'oranye': '#E07B39', 'brown': '#7A5233', 'coklat': '#7A5233',
  'cokelat': '#7A5233', 'gold': '#C9A445', 'emas': '#C9A445', 'teal': '#2E7F7F', 'tosca': '#3AA6A0',
};

String _pick(Object? v, List<String> allowed, String fallback) =>
    allowed.contains(v) ? v as String : fallback;

/// What the AI saw in the photo: just enough to draw a clean flat picture of it.
class FlatSpec {
  final String category, pattern, sleeves, length, neckline, bottomType;
  final Color main, second;

  const FlatSpec({
    required this.category,
    required this.main,
    required this.second,
    required this.pattern,
    required this.sleeves,
    required this.length,
    required this.neckline,
    required this.bottomType,
  });

  factory FlatSpec.fromJson(Map<dynamic, dynamic> j, String category) {
    final main = _hex(j['hex'], const Color(0xFF9E9AA8));
    return FlatSpec(
      category: category,
      main: main,
      second: _hex(j['hex2'], main),
      pattern: _pick(j['pattern'], ['solid', 'stripes', 'checks', 'dots'], 'solid'),
      sleeves: _pick(j['sleeves'], ['none', 'short', 'long'], 'short'),
      length: _pick(j['length'], ['short', 'regular', 'long'], 'regular'),
      neckline: _pick(j['neckline'], ['round', 'v', 'collar'], 'round'),
      bottomType: _pick(j['bottomType'] ?? j['bottom_type'], ['pants', 'shorts', 'skirt'], 'pants'),
    );
  }

  Map<String, dynamic> toJson() => {
        'hex': _hexStr(main),
        'hex2': _hexStr(second),
        'pattern': pattern,
        'sleeves': sleeves,
        'length': length,
        'neckline': neckline,
        'bottomType': bottomType,
      };

  /// A plain flat look built from the category and the color name only.
  /// Used when the AI is not available, so every piece can still be drawn flat.
  factory FlatSpec.guess(String category, String colorName) {
    final words = colorName.toLowerCase();
    String? hex;
    var best = 0;
    for (final e in _colorWords.entries) {
      // Longest match wins; on a tie the word listed first (the more specific shade) stays.
      if (e.key.length > best && words.contains(e.key)) {
        best = e.key.length;
        hex = e.value;
      }
    }
    return FlatSpec.fromJson({
      'hex': hex,
      'sleeves': category == 'Jackets' ? 'long' : 'short',
      'length': 'regular',
      'bottomType': 'pants',
    }, category);
  }

  /// The look saved with [spec], or a guess from [category] and [colorName].
  static FlatSpec of(Map<String, dynamic>? spec, String category, String colorName) =>
      spec == null ? FlatSpec.guess(category, colorName) : FlatSpec.fromJson(spec, category);

  /// True when the piece is mostly green (the image AI then uses a magenta background).
  bool get isGreen => [main, second].any((c) {
        final h = HSVColor.fromColor(c);
        return h.hue > 65 && h.hue < 170 && h.saturation > 0.25 && h.value > 0.2;
      });

  FlatSpec withCategory(String c) => FlatSpec(
        category: c,
        main: main,
        second: second,
        pattern: pattern,
        sleeves: sleeves,
        length: length,
        neckline: neckline,
        bottomType: bottomType,
      );
}

// All shapes are drawn on a 100 x 100 grid, front view, centered on x = 50.

Path _top(FlatSpec s, {required bool jacket}) {
  final hem = switch (s.length) { 'short' => 72.0, 'long' => 100.0, _ => 86.0 };
  final w = jacket ? 3.0 : 0.0;
  final sleeves = (jacket && s.sleeves == 'none') ? 'long' : s.sleeves;
  final left = <Offset>[const Offset(40, 20), Offset(27 - w, 24)];
  switch (sleeves) {
    case 'long':
      left.addAll([Offset(7 - w, 68), Offset(19 - w, 72), Offset(29 - w, 42)]);
    case 'short':
      left.addAll([Offset(8 - w, 40), Offset(17 - w, 49), Offset(29 - w, 41)]);
    default:
      left.addAll([Offset(25 - w, 32), Offset(29 - w, 40)]);
  }
  left.add(Offset(30 - w, hem));
  final p = Path()..moveTo(left.first.dx, left.first.dy);
  for (final o in left.skip(1)) {
    p.lineTo(o.dx, o.dy);
  }
  for (final o in left.reversed) {
    p.lineTo(100 - o.dx, o.dy);
  }
  switch (s.neckline) {
    case 'v':
      p
        ..lineTo(50, jacket ? 40 : 36)
        ..lineTo(40, 20);
    case 'collar':
      p.quadraticBezierTo(50, 27, 40, 20);
    default:
      p.quadraticBezierTo(50, 33, 40, 20);
  }
  return p..close();
}

Path _bottoms(FlatSpec s) {
  if (s.bottomType == 'skirt') {
    final hem = switch (s.length) { 'short' => 48.0, 'long' => 94.0, _ => 70.0 };
    final flare = 12 + (hem - 10) * 0.18;
    return Path()
      ..moveTo(32, 10)
      ..lineTo(68, 10)
      ..lineTo(68 + flare, hem)
      ..lineTo(32 - flare, hem)
      ..close();
  }
  final shorts = s.bottomType == 'shorts';
  final hem = shorts ? 54.0 : (s.length == 'short' ? 74.0 : 96.0);
  final out = shorts ? 2.0 : 0.0;
  return Path()
    ..moveTo(30, 10)
    ..lineTo(70, 10)
    ..lineTo(72 + out, hem)
    ..lineTo(53, hem)
    ..lineTo(50, 40)
    ..lineTo(47, hem)
    ..lineTo(28 - out, hem)
    ..close();
}

Path _dress(FlatSpec s) {
  final hem = switch (s.length) { 'short' => 74.0, 'long' => 102.0, _ => 90.0 };
  final left = <Offset>[const Offset(42, 8), const Offset(34, 10)];
  if (s.sleeves == 'none') {
    left.add(const Offset(31, 22));
  } else {
    left.addAll([const Offset(20, 24), const Offset(30, 30)]);
  }
  left.addAll([const Offset(36, 36), const Offset(38, 48), Offset(14, hem)]);
  final p = Path()..moveTo(left.first.dx, left.first.dy);
  for (final o in left.skip(1)) {
    p.lineTo(o.dx, o.dy);
  }
  for (final o in left.reversed) {
    p.lineTo(100 - o.dx, o.dy);
  }
  switch (s.neckline) {
    case 'v':
      p
        ..lineTo(50, 26)
        ..lineTo(42, 8);
    case 'collar':
      p.quadraticBezierTo(50, 16, 42, 8);
    default:
      p.quadraticBezierTo(50, 22, 42, 8);
  }
  return p..close();
}

Path _shoes() {
  final left = Path()
    ..moveTo(6, 72)
    ..cubicTo(6, 44, 22, 38, 34, 40)
    ..cubicTo(46, 42, 48, 58, 48, 72)
    ..lineTo(48, 80)
    ..lineTo(6, 80)
    ..close();
  final right = Path()
    ..moveTo(94, 72)
    ..cubicTo(94, 44, 78, 38, 66, 40)
    ..cubicTo(54, 42, 52, 58, 52, 72)
    ..lineTo(52, 80)
    ..lineTo(94, 80)
    ..close();
  return Path()
    ..addPath(left, Offset.zero)
    ..addPath(right, Offset.zero);
}

Path _rings() {
  final p = Path()..fillType = PathFillType.evenOdd;
  for (final x in [30.0, 70.0]) {
    p
      ..addOval(Rect.fromCircle(center: Offset(x, 50), radius: 17))
      ..addOval(Rect.fromCircle(center: Offset(x, 50), radius: 10));
  }
  return p;
}

Path _silhouette(FlatSpec s) {
  switch (s.category) {
    case 'Bottoms':
      return _bottoms(s);
    case 'Dresses':
      return _dress(s);
    case 'Shoes':
      return _shoes();
    case 'Accessories':
      return _rings();
    default:
      return _top(s, jacket: s.category == 'Jackets');
  }
}

void _pattern(Canvas c, FlatSpec s, Rect b) {
  if (s.pattern == 'solid') return;
  final sec = s.second == s.main ? Color.lerp(s.main, Colors.black, 0.25)! : s.second;
  final paint = Paint()..color = sec;
  switch (s.pattern) {
    case 'stripes':
      for (var y = b.top; y < b.bottom; y += 9) {
        c.drawRect(Rect.fromLTWH(b.left, y, b.width, 4.5), paint);
      }
    case 'checks':
      paint.color = sec.withAlpha(110);
      for (var y = b.top; y < b.bottom; y += 10) {
        c.drawRect(Rect.fromLTWH(b.left, y, b.width, 4), paint);
      }
      for (var x = b.left; x < b.right; x += 10) {
        c.drawRect(Rect.fromLTWH(x, b.top, 4, b.height), paint);
      }
    default:
      for (var y = b.top + 4; y < b.bottom; y += 10) {
        for (var x = b.left + 4; x < b.right; x += 10) {
          c.drawCircle(Offset(x, y), 1.8, paint);
        }
      }
  }
}

/// Fills [path] with the garment's color and pattern, shades it like fabric and
/// outlines it. Used for the closet picture and for dressing the model.
void paintGarmentPath(Canvas c, Path path, FlatSpec s, {double outline = 0.9}) {
  final b = path.getBounds();
  c.drawPath(path, Paint()..color = s.main);
  c.save();
  c.clipPath(path);
  _pattern(c, s, b);
  c.restore();
  c.drawPath(
    path,
    Paint()
      ..shader = ui.Gradient.linear(
        b.centerLeft,
        b.centerRight,
        const [Color(0x40000000), Color(0x00000000), Color(0x2E000000)],
        const [0, 0.5, 1],
      ),
  );
  c.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = outline
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xE62B2118),
  );
}

void _details(Canvas c, FlatSpec s, Rect b) {
  final line = Paint()
    ..color = const Color(0x55000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.7
    ..strokeCap = StrokeCap.round;
  switch (s.category) {
    case 'Jackets':
      c.drawLine(Offset(50, 38), Offset(50, b.bottom), line);
      for (final y in [50.0, 63.0, 76.0]) {
        if (y < b.bottom - 4) c.drawCircle(Offset(50, y), 1.3, Paint()..color = const Color(0x66000000));
      }
    case 'Bottoms':
      if (s.bottomType == 'skirt') {
        c.drawLine(const Offset(32, 16), const Offset(68, 16), line);
      } else {
        c.drawLine(const Offset(30, 16), const Offset(70, 16), line);
        c.drawLine(const Offset(50, 16), const Offset(50, 36), line);
      }
    case 'Dresses':
      c.drawLine(const Offset(38, 48), const Offset(62, 48), line);
    case 'Shoes':
      c.drawLine(const Offset(6, 74), const Offset(48, 74), line);
      c.drawLine(const Offset(52, 74), const Offset(94, 74), line);
  }
  if (s.neckline == 'collar' && (s.category == 'Tops' || s.category == 'Jackets')) {
    final flap = Paint()..color = Color.lerp(s.main, Colors.white, 0.28)!;
    for (final m in [1.0, -1.0]) {
      double x(double v) => m > 0 ? v : 100 - v;
      final p = Path()
        ..moveTo(x(40), 20)
        ..lineTo(x(50), 32)
        ..lineTo(x(42), 37)
        ..lineTo(x(35), 24)
        ..close();
      c.drawPath(p, flap);
      c.drawPath(p, line);
    }
  }
}

/// Draws a clean flat picture of the garment and returns it as a base64 PNG
/// with a transparent background, cropped tightly to the garment.
Future<String> renderFlat(FlatSpec s) async {
  final path = _silhouette(s);
  final b = path.getBounds();
  const w = 360.0;
  final sc = w / b.width;
  final h = b.height * sc;

  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec, Rect.fromLTWH(0, 0, w + 8, h + 8));
  c.translate(4, 4);
  c.scale(sc);
  c.translate(-b.left, -b.top);

  paintGarmentPath(c, path, s);
  _details(c, s, b);

  final img = await rec.endRecording().toImage((w + 8).round(), (h + 8).round());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return base64Encode(data!.buffer.asUint8List());
}

/// Asks the AI what the item in this photo looks like, then draws it flat.
/// Returns null if the AI is unavailable.
Future<({String image, Map<String, dynamic> spec})?> flatIllustrationFor(String imageBase64, String category) async {
  if (!aiConfigured) return null;
  try {
    final photo = base64Decode(imageBase64);
    final isPng = photo.length > 3 && photo[0] == 0x89 && photo[1] == 0x50;
    final res = await http
        .post(
          Uri.parse(aiEndpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'image': imageBase64, 'mime': isPng ? 'image/png' : 'image/jpeg'}),
        )
        .timeout(const Duration(seconds: 40));
    if (res.statusCode != 200) return null;
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final spec = FlatSpec.fromJson(j, category);
    return (image: await renderFlat(spec), spec: spec.toJson());
  } catch (_) {
    return null;
  }
}
