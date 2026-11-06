import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'flat_art.dart';
import 'main.dart';
import 'saved_outfits.dart';
import 'stylist.dart';
import 'theme.dart';

part 'model3d.dart';

// Starting points. Order: shoulders, bust or chest, waist, hips, thighs.
const bodyTypes = <String, List<double>>{
  'Feminine': [100, 92, 74, 112, 52],
  'Neutral': [106, 92, 88, 100, 48],
  'Masculine': [120, 108, 100, 98, 46],
};
const measureLabels = ['Shoulders', 'Bust or chest', 'Waist', 'Hips', 'Thighs'];
const measureMin = [84.0, 70.0, 56.0, 76.0, 36.0];
const measureMax = [140.0, 130.0, 120.0, 140.0, 66.0];

const skinTones = [
  Color(0xFFFFDFC4),
  Color(0xFFF0C8A0),
  Color(0xFFD9A066),
  Color(0xFFB07A4F),
  Color(0xFF8A5A3B),
  Color(0xFF5C3A24),
];

const outfitSlots = ['Jackets', 'Tops', 'Dresses', 'Bottoms', 'Shoes'];

const hairStyles = ['Short', 'Long', 'Bun', 'Buzz', 'Bald'];
const hairColors = [
  Color(0xFF1F1A17),
  Color(0xFF3B2A1E),
  Color(0xFF6B4A2F),
  Color(0xFFA0522D),
  Color(0xFFD9B870),
  Color(0xFFB9B9BE),
  Color(0xFFD66BA0),
];
const eyeColors = [Color(0xFF4A2E1C), Color(0xFF8A6A2F), Color(0xFF4F7F5A), Color(0xFF4A78B5), Color(0xFF7A8088)];

/// What the model is currently wearing, by category.
final avatarOutfit = <String, ClosetItem?>{};

/// Accessories the model wears, one of each kind (a hat, a bag and so on).
final avatarAccessories = <String, ClosetItem?>{};
const accessoryKinds = ['hat', 'glasses', 'necklace', 'scarf', 'belt', 'watch', 'bag'];

/// What kind of accessory a piece is: from its saved type, or else from its name.
String accessoryKind(ClosetItem item) {
  final k = item.spec?['kind'];
  if (accessoryKinds.contains(k)) return k as String;
  final n = item.name.toLowerCase();
  bool has(List<String> words) => words.any(n.contains);
  if (has(['hat', 'cap', 'beanie', 'beret', 'bucket'])) return 'hat';
  if (has(['glasses', 'sunglasses', 'shades', 'specs'])) return 'glasses';
  if (has(['necklace', 'chain', 'pendant', 'pearl', 'choker'])) return 'necklace';
  if (has(['scarf', 'shawl', 'bandana'])) return 'scarf';
  if (has(['belt'])) return 'belt';
  if (has(['watch', 'bracelet', 'bangle'])) return 'watch';
  return 'bag';
}

/// Puts on or takes off an accessory.
void toggleAccessory(ClosetItem item) {
  final k = accessoryKind(item);
  avatarAccessories[k] = avatarAccessories[k]?.id == item.id ? null : item;
}

/// Puts a piece on the model. A dress replaces the top and bottoms, and the other way round.
void wearPiece(String slot, ClosetItem? item) {
  if (slot == 'Accessories') {
    if (item != null) avatarAccessories[accessoryKind(item)] = item;
    return;
  }
  avatarOutfit[slot] = item;
  if (item == null) return;
  if (slot == 'Dresses') {
    avatarOutfit['Tops'] = null;
    avatarOutfit['Bottoms'] = null;
  }
  if (slot == 'Tops' || slot == 'Bottoms') avatarOutfit['Dresses'] = null;
}

class AvatarSettings extends ChangeNotifier {
  String body = 'Neutral';
  List<double> m = List.of(bodyTypes['Neutral']!);
  double height = 0.95;
  int skin = 1;
  int hair = 0, hairColor = 1, eyes = 0;
  double head = 1.0, arms = 1.0;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    body = p.getString('av_body') ?? body;
    if (!bodyTypes.containsKey(body)) body = 'Neutral';
    final saved = p.getStringList('av_m');
    if (saved != null && saved.length == 5) {
      m = [
        for (var i = 0; i < 5; i++)
          (double.tryParse(saved[i]) ?? bodyTypes[body]![i]).clamp(measureMin[i], measureMax[i]),
      ];
    } else {
      m = List.of(bodyTypes[body]!);
    }
    height = (p.getDouble('av_height') ?? height).clamp(0.85, 1.0);
    skin = (p.getInt('av_skin') ?? skin).clamp(0, skinTones.length - 1);
    hair = (p.getInt('av_hair') ?? hair).clamp(0, hairStyles.length - 1);
    hairColor = (p.getInt('av_haircolor') ?? hairColor).clamp(0, hairColors.length - 1);
    eyes = (p.getInt('av_eyes') ?? eyes).clamp(0, eyeColors.length - 1);
    head = (p.getDouble('av_head') ?? head).clamp(0.9, 1.15);
    arms = (p.getDouble('av_arms') ?? arms).clamp(0.8, 1.5);
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('av_body', body);
    await p.setStringList('av_m', m.map((v) => v.toString()).toList());
    await p.setDouble('av_height', height);
    await p.setInt('av_skin', skin);
    await p.setInt('av_hair', hair);
    await p.setInt('av_haircolor', hairColor);
    await p.setInt('av_eyes', eyes);
    await p.setDouble('av_head', head);
    await p.setDouble('av_arms', arms);
  }

  /// Picking a body type resets every measurement to that starting point.
  void setBody(String name) {
    body = name;
    m = List.of(bodyTypes[name]!);
    notifyListeners();
    _save();
  }

  void setMeasure(int i, double v) {
    m[i] = v;
    notifyListeners();
    _save();
  }

  void setHeight(double v) {
    height = v;
    notifyListeners();
    _save();
  }

  void setSkin(int i) {
    skin = i;
    notifyListeners();
    _save();
  }

  void setHair(int i) {
    hair = i;
    notifyListeners();
    _save();
  }

  void setHairColor(int i) {
    hairColor = i;
    notifyListeners();
    _save();
  }

  void setEyes(int i) {
    eyes = i;
    notifyListeners();
    _save();
  }

  void setHead(double v) {
    head = v;
    notifyListeners();
    _save();
  }

  void setArms(double v) {
    arms = v;
    notifyListeners();
    _save();
  }
}

final avatarSettings = AvatarSettings();

class _BodyPainter extends CustomPainter {
  final AvatarSettings s;
  _BodyPainter(this.s);

  static const _warm = Color(0xFF4A2A1C);
  List<double> get m => s.m;
  Color get skin => skinTones[s.skin];
  Color get hair => hairColors[s.hairColor];
  Color get line => Color.lerp(skin, const Color(0xFF3A2015), 0.42)!;
  Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  /// Skin: soft shading across each part, darker at the edges, a light ridge just
  /// off centre, and a thin warm outline ([stroke], or the fill's own edge).
  void _part(Canvas c, Path fill, {Path? stroke, bool outline = true}) {
    final r = fill.getBounds();
    c.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(r.left, 0),
          Offset(r.right, 0),
          [_mix(skin, _warm, 0.2), skin, _mix(skin, Colors.white, 0.1), _mix(skin, _warm, 0.24)],
          [0, 0.3, 0.55, 1],
        ),
    );
    if (outline) {
      c.drawPath(
        stroke ?? fill,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = line,
      );
    }
  }

  void _hairFill(Canvas c, Path p, {double opacity = 1}) {
    final r = p.getBounds();
    c.drawPath(
      p,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, r.top),
          Offset(0, r.bottom),
          [
            _mix(hair, Colors.white, 0.16).withValues(alpha: opacity),
            hair.withValues(alpha: opacity),
            _mix(hair, Colors.black, 0.18).withValues(alpha: opacity),
          ],
          [0, 0.45, 1],
        ),
    );
    c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = _mix(hair, Colors.black, 0.35).withValues(alpha: opacity),
    );
  }

  void _headSpace(Canvas canvas, void Function() draw) {
    canvas.save();
    canvas.translate(120, 50);
    canvas.scale(s.head);
    canvas.translate(-120, -50);
    draw();
    canvas.restore();
  }

  Paint _soft(Color color, double width, [double opacity = 1]) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..color = color.withValues(alpha: opacity);

  /// Plain fitted base layer (a strapless one-piece) so the model looks dressed
  /// before any clothes are added.
  void _base(Canvas c, Path clip, void Function(Paint) draw) {
    c.save();
    c.clipPath(clip);
    final hi = m[3];
    draw(
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(120 - hi / 2 - 10, 0),
          Offset(120 + hi / 2 + 10, 0),
          const [Color(0xFFA79DB4), Color(0xFFCFC7D9), Color(0xFFA096AE)],
          const [0, 0.45, 1],
        ),
    );
    c.restore();
  }

  void _face(Canvas c) {
    const cx = 120.0;
    // Cheeks
    for (final side in [-1.0, 1.0]) {
      final o = Offset(cx + side * 14, 62);
      c.drawCircle(o, 7, Paint()..shader = ui.Gradient.radial(o, 7, const [Color(0x33E16E6E), Color(0x00E16E6E)]));
    }
    // Eyes: white, iris, pupil, a catchlight, an upper lid and a small lash flick.
    for (final side in [-1.0, 1.0]) {
      final x = cx + side * 9.5;
      final eye = Path()
        ..moveTo(x - 4.6, 52)
        ..quadraticBezierTo(x, 47.4, x + 4.6, 52)
        ..quadraticBezierTo(x, 55.6, x - 4.6, 52)
        ..close();
      c.drawPath(eye, Paint()..color = const Color(0xFFFBFAF8));
      c.save();
      c.clipPath(eye);
      c.drawCircle(Offset(x, 52), 2.5, Paint()..color = eyeColors[s.eyes]);
      c.drawCircle(Offset(x, 52), 1.2, Paint()..color = const Color(0xFF16100D));
      c.drawCircle(Offset(x + 0.9, 51.1), 0.75, Paint()..color = const Color(0xE6FFFFFF));
      c.restore();
      c.drawPath(
        Path()
          ..moveTo(x - 4.8, 52.1)
          ..quadraticBezierTo(x, 47, x + 4.8, 52.1),
        _soft(const Color(0xFF2A1A14), 1.1),
      );
      c.drawLine(Offset(x + side * 4.7, 51.9), Offset(x + side * 5.7, 51), _soft(const Color(0xFF2A1A14), 0.9));
      // Brow: a gentle arch, slightly raised toward the middle.
      c.drawPath(
        Path()
          ..moveTo(x - side * 4.6, 45.6)
          ..quadraticBezierTo(x - side * 0.5, 42.6, x + side * 5.4, 45.6)
          ..quadraticBezierTo(x, 43.9, x - side * 4.6, 46.6)
          ..close(),
        Paint()..color = _mix(hair, Colors.black, 0.1),
      );
    }
    // Nose: a soft shadow line and a hint of nostrils.
    final nose = _soft(_mix(skin, _warm, 0.45), 1.1, 0.75);
    c.drawPath(
      Path()
        ..moveTo(cx + 0.5, 54)
        ..quadraticBezierTo(cx - 1.8, 60, cx - 0.6, 62.2),
      nose,
    );
    c.drawPath(
      Path()
        ..moveTo(cx - 3, 62.4)
        ..quadraticBezierTo(cx, 63.6, cx + 3, 62.4),
      nose,
    );
    // Lips and a slight smile.
    final lip = _mix(skin, const Color(0xFFB04A50), 0.5);
    c.drawPath(
      Path()
        ..moveTo(cx - 5.4, 66.6)
        ..quadraticBezierTo(cx - 2.4, 65.4, cx, 66.4)
        ..quadraticBezierTo(cx + 2.4, 65.4, cx + 5.4, 66.6)
        ..quadraticBezierTo(cx, 68.4, cx - 5.4, 66.6),
      Paint()..color = _mix(lip, skin, 0.25),
    );
    c.drawPath(
      Path()
        ..moveTo(cx - 4.8, 67.1)
        ..quadraticBezierTo(cx, 71.6, cx + 4.8, 67.1)
        ..quadraticBezierTo(cx, 68.8, cx - 4.8, 67.1),
      Paint()..color = lip,
    );
    final corner = _soft(_mix(lip, skin, 0.3), 0.7);
    c.drawLine(const Offset(cx - 5.4, 66.6), const Offset(cx - 6.2, 65.8), corner);
    c.drawLine(const Offset(cx + 5.4, 66.6), const Offset(cx + 6.2, 65.8), corner);
  }

  void _hairFront(Canvas c) {
    if (s.hair == 4) return;
    if (s.hair == 3) {
      _hairFill(
        c,
        Path()
          ..moveTo(96, 47)
          ..cubicTo(96, 28, 107, 21, 120, 21)
          ..cubicTo(133, 21, 144, 28, 144, 47)
          ..cubicTo(139, 37, 131, 33, 120, 33)
          ..cubicTo(109, 33, 101, 37, 96, 47)
          ..close(),
        opacity: 0.82,
      );
      return;
    }
    if (s.hair == 1) {
      _hairFill(
        c,
        Path()
          ..moveTo(96.5, 76)
          ..cubicTo(90, 50, 95, 19, 120, 18)
          ..cubicTo(145, 19, 150, 50, 143.5, 76)
          ..cubicTo(143, 60, 142, 48, 137, 41)
          ..cubicTo(129, 32, 111, 32, 104, 40)
          ..cubicTo(99, 46, 97, 58, 96.5, 76)
          ..close(),
      );
    } else {
      // Short (and the base of the bun): a side part with a soft sweep across the forehead.
      _hairFill(
        c,
        Path()
          ..moveTo(95, 58)
          ..cubicTo(91, 34, 102, 18, 120, 18)
          ..cubicTo(138, 18, 149, 34, 145, 58)
          ..cubicTo(144, 49, 142, 42, 138, 38)
          ..cubicTo(131, 32, 120, 33, 112, 37)
          ..cubicTo(105, 40, 99, 46, 95, 58)
          ..close(),
      );
      c.drawPath(
        Path()
          ..moveTo(112, 37)
          ..quadraticBezierTo(122, 27, 136, 26)
          ..moveTo(105, 42)
          ..quadraticBezierTo(110, 30, 124, 23)
          ..moveTo(140, 40)
          ..quadraticBezierTo(143, 33, 141, 27),
        _soft(_mix(hair, Colors.black, 0.3), 0.8, 0.6),
      );
    }
    // A soft shine.
    c.drawPath(
      Path()
        ..moveTo(108, 25)
        ..quadraticBezierTo(120, 21, 132, 25),
      _soft(Colors.white, 2, 0.22),
    );
    if (s.hair == 2) {
      _hairFill(c, Path()..addOval(Rect.fromCenter(center: const Offset(120, 12), width: 23, height: 20)));
      c.drawRect(const Rect.fromLTWH(114, 20, 12, 2.4), Paint()..color = _mix(hair, Colors.black, 0.3));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sh = m[0], bu = m[1], wa = m[2], hi = m[3], th = m[4];
    final k = s.arms;
    const cx = 120.0;

    // Soft shadow on the floor.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(cx, 466), width: hi * 1.7, height: 12),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Long hair falls behind the shoulders.
    if (s.hair == 1) {
      _headSpace(
        canvas,
        () => _hairFill(
          canvas,
          Path()
            ..moveTo(96, 40)
            ..cubicTo(84, 78, 86, 118, 91, 142)
            ..quadraticBezierTo(120, 152, 149, 142)
            ..cubicTo(154, 118, 156, 78, 144, 40)
            ..close(),
        ),
      );
    }

    // Legs (with a hint of the knee) and feet seen from the front.
    final legs = <Path>[];
    for (final side in [-1.0, 1.0]) {
      final c = cx + side * (2 + th / 2), ck = c - side, ca = c - 2 * side;
      final ht = th / 2, hk = th * 0.36, ha = th * 0.22;
      final oT = c + side * ht, iT = c - side * ht;
      final oK = ck + side * hk, iK = ck - side * hk;
      final oA = ca + side * ha, iA = ca - side * ha;
      final leg = Path()
        ..moveTo(oT, 210)
        ..cubicTo(oT, 270, oK, 300, oK, 328)
        ..cubicTo(oK, 360, oA, 400, oA, 438)
        ..lineTo(iA, 438)
        ..cubicTo(iA, 400, iK, 360, iK, 328)
        ..cubicTo(iK, 300, iT, 270, iT, 210)
        ..close();
      legs.add(leg);
      _part(canvas, leg);
      canvas.drawPath(
        Path()
          ..moveTo(ck - hk * 0.45, 322)
          ..quadraticBezierTo(ck, 327, ck + hk * 0.45, 322),
        _soft(_mix(skin, _warm, 0.3), 1, 0.35),
      );
      final fx = ca, a = ha, f = ha + 1.5;
      Path foot() => Path()
        ..moveTo(fx - a, 434)
        ..cubicTo(fx - a - 1, 444, fx - f - 1, 450, fx - f, 455)
        ..quadraticBezierTo(fx - f + 1, 460, fx - 3, 460)
        ..lineTo(fx + 3, 460)
        ..quadraticBezierTo(fx + f - 1, 460, fx + f, 455)
        ..cubicTo(fx + f + 1, 450, fx + a + 1, 444, fx + a, 434);
      _part(canvas, foot()..close(), stroke: foot());
    }

    // Arms: a round shoulder, a slimmer elbow, forearm and wrist, then a relaxed hand.
    for (final side in [-1.0, 1.0]) {
      final xt = cx + side * (sh / 2 + 3), xw = cx + side * (sh / 2 + 15);
      double at(double y) => xt + (xw - xt) * (y - 100) / 126;
      double half(double y) =>
          k *
          _interp([
            [100, 10.2],
            [114, 10.8],
            [152, 8.4],
            [162, 8.1],
            [180, 8.6],
            [222, 5.4],
            [229, 5.4],
          ], y);
      double inner(double y) => at(y) - side * half(y);
      double outer(double y) => at(y) + side * half(y);
      final ys = [for (var y = 110.0; y <= 229; y += 3) y];
      final arm = Path()..moveTo(inner(110), 110);
      for (final y in ys) {
        arm.lineTo(inner(y), y);
      }
      for (final y in ys.reversed) {
        arm.lineTo(outer(y), y);
      }
      // Round shoulder that runs into the top of the torso.
      arm
        ..cubicTo(outer(110), 100, cx + side * (sh / 2), 95.5, cx + side * (sh / 2 - 7), 95)
        ..close();
      _part(canvas, arm);
      final hx = at(236), w = 6 * k;
      Path hand() => Path()
        ..moveTo(hx - w * 0.9, 226)
        ..cubicTo(hx - w * 1.3, 234, hx - w * 1.2, 246, hx - w * 0.55, 251)
        ..quadraticBezierTo(hx, 255, hx + w * 0.55, 251)
        ..cubicTo(hx + w * 1.2, 246, hx + w * 1.3, 234, hx + w * 0.9, 226);
      _part(canvas, hand()..close(), stroke: hand());
      final tx = hx - side * w * 1.05;
      canvas.drawPath(
        Path()
          ..moveTo(tx, 230)
          ..quadraticBezierTo(tx - side * 2.6, 238, tx + side * 0.5, 244),
        _soft(line, 1),
      );
    }

    // Torso: smooth curves through shoulders, bust, waist and hips.
    final torso = Path()
      ..moveTo(cx - 9, 92)
      ..cubicTo(cx - sh * 0.26, 93, cx - sh / 2 - 1, 95, cx - sh / 2 - 1, 107)
      ..cubicTo(cx - sh / 2 - 1, 121, cx - bu / 2, 124, cx - bu / 2, 134)
      ..cubicTo(cx - bu / 2, 148, cx - wa / 2, 154, cx - wa / 2, 168)
      ..cubicTo(cx - wa / 2, 184, cx - hi / 2, 196, cx - hi / 2, 216)
      ..lineTo(cx + hi / 2, 216)
      ..cubicTo(cx + hi / 2, 196, cx + wa / 2, 184, cx + wa / 2, 168)
      ..cubicTo(cx + wa / 2, 154, cx + bu / 2, 148, cx + bu / 2, 134)
      ..cubicTo(cx + bu / 2, 124, cx + sh / 2 + 1, 121, cx + sh / 2 + 1, 107)
      ..cubicTo(cx + sh / 2 + 1, 95, cx + sh * 0.26, 93, cx + 9, 92)
      ..close();
    _part(canvas, torso, outline: false);

    // Base layer: strapless one-piece, running on into the tops of the legs.
    const topY = 136.0;
    final top = Path()
      ..moveTo(cx - 80, topY - 2)
      ..quadraticBezierTo(cx, topY + 4, cx + 80, topY - 2);
    _base(
      canvas,
      torso,
      (p) => canvas.drawPath(
        Path.from(top)
          ..lineTo(cx + 80, 224)
          ..lineTo(cx - 80, 224)
          ..close(),
        p,
      ),
    );
    _base(
      canvas,
      Path()
        ..moveTo(cx - 6, 208)
        ..lineTo(cx + 6, 208)
        ..lineTo(cx + 3, 241)
        ..lineTo(cx - 3, 241)
        ..close(),
      (p) => canvas.drawRect(const Rect.fromLTWH(cx - 8, 206, 16, 38), p),
    );
    for (var i = 0; i < 2; i++) {
      final side = i == 0 ? -1.0 : 1.0;
      _base(
        canvas,
        legs[i],
        (p) => canvas.drawPath(
          Path()
            ..moveTo(cx - side * 4, 200)
            ..lineTo(cx + side * 80, 200)
            ..lineTo(cx + side * 80, 222)
            ..quadraticBezierTo(cx + side * (th * 0.6), 228, cx + side * 2, 240)
            ..close(),
          p,
        ),
      );
    }
    final seam = _soft(const Color(0xFF3C324B), 0.9, 0.35);
    canvas.save();
    canvas.clipPath(torso);
    canvas.drawPath(top, seam);
    canvas.restore();
    // Outline the torso, but not its bottom edge (the base layer runs on into the legs).
    canvas.save();
    canvas.clipRect(const Rect.fromLTWH(0, 0, 240, 214));
    canvas.drawPath(torso, _soft(line, 1));
    canvas.restore();
    for (var i = 0; i < 2; i++) {
      final side = i == 0 ? -1.0 : 1.0;
      canvas.save();
      canvas.clipPath(legs[i]);
      canvas.drawPath(
        Path()
          ..moveTo(cx + side * 80, 222)
          ..quadraticBezierTo(cx + side * (th * 0.6), 228, cx + side * 2, 240),
        seam,
      );
      canvas.restore();
    }

    // Neck, with a soft shadow under the chin, and collarbones.
    final neck = Path()
      ..moveTo(cx - 9, 66)
      ..lineTo(cx - 9, 92)
      ..quadraticBezierTo(cx - 9, 98, cx - 15, 99)
      ..lineTo(cx + 15, 99)
      ..quadraticBezierTo(cx + 9, 98, cx + 9, 92)
      ..lineTo(cx + 9, 66)
      ..close();
    _part(
      canvas,
      neck,
      stroke: Path()
        ..moveTo(cx - 9, 70)
        ..lineTo(cx - 9, 91)
        ..moveTo(cx + 9, 70)
        ..lineTo(cx + 9, 91),
    );
    canvas.drawRect(
      const Rect.fromLTWH(cx - 9, 70, 18, 16),
      Paint()
        ..shader = ui.Gradient.linear(const Offset(0, 70), const Offset(0, 86), const [
          Color(0x474A2A1C),
          Color(0x004A2A1C),
        ]),
    );
    final bone = _soft(_mix(skin, _warm, 0.35), 0.9, 0.45);
    canvas.drawPath(
      Path()
        ..moveTo(cx - 5, 101.5)
        ..quadraticBezierTo(cx - 14, 99, cx - 23, 100.5)
        ..moveTo(cx + 5, 101.5)
        ..quadraticBezierTo(cx + 14, 99, cx + 23, 100.5),
      bone,
    );

    // Ears, head (rounded skull, narrower jaw, soft chin), face and hair,
    // scaled together by the Head size slider.
    _headSpace(canvas, () {
      for (final side in [-1.0, 1.0]) {
        final ex = cx + side * 24;
        _part(canvas, Path()..addOval(Rect.fromCenter(center: Offset(ex, 53), width: 7, height: 12)));
        canvas.drawPath(
          Path()
            ..moveTo(ex + side * 0.5, 49)
            ..quadraticBezierTo(ex + side * 2, 53, ex + side * 0.3, 57),
          _soft(_mix(skin, _warm, 0.35), 0.8),
        );
      }
      _part(
        canvas,
        Path()
          ..moveTo(cx, 21)
          ..cubicTo(cx + 16, 21, cx + 25, 33, cx + 25, 48)
          ..cubicTo(cx + 25, 62, cx + 19, 72, cx + 11, 77.5)
          ..cubicTo(cx + 7, 80.5, cx + 3, 81.5, cx, 81.5)
          ..cubicTo(cx - 3, 81.5, cx - 7, 80.5, cx - 11, 77.5)
          ..cubicTo(cx - 19, 72, cx - 25, 62, cx - 25, 48)
          ..cubicTo(cx - 25, 33, cx - 16, 21, cx, 21)
          ..close(),
      );
      _face(canvas);
      _hairFront(canvas);
    });
  }

  @override
  bool shouldRepaint(covariant _BodyPainter old) => true;
}

/// Straight-line lookup: points are [y, value] pairs sorted by y.
double _interp(List<List<double>> pts, double y) {
  if (y <= pts.first[0]) return pts.first[1];
  for (var i = 1; i < pts.length; i++) {
    if (y <= pts[i][0]) {
      final a = pts[i - 1], b = pts[i];
      return a[1] + (b[1] - a[1]) * (y - a[0]) / (b[0] - a[0]);
    }
  }
  return pts.last[1];
}

class AvatarView extends StatefulWidget {
  const AvatarView({super.key});

  @override
  State<AvatarView> createState() => _AvatarViewState();
}

/// A front-facing photo of a piece, and where the clothing is in each row of it.
class _Photo {
  final ui.Image img;

  /// For each sampled row (top to bottom), the stretches of clothing in that row
  /// as [left, right] pairs (0..1 of the width), left to right.
  final List<List<double>> rows;
  _Photo(this.img, this.rows);

  static const n = 160; // rows sampled from top to bottom

  static Future<_Photo> of(ui.Image img) async {
    final bd = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final w = img.width, h = img.height;
    final minRun = max(2, (w * 0.03).round()); // ignore specks
    final maxGap = max(1, (w * 0.02).round()); // close tiny holes
    final rows = <List<double>>[];
    for (var j = 0; j < n; j++) {
      final y = (j * (h - 1) / (n - 1)).round();
      final raw = <int>[];
      var start = -1;
      for (var x = 0; x <= w; x++) {
        final solid = x < w && bd.getUint8((y * w + x) * 4 + 3) > 60;
        if (solid && start < 0) start = x;
        if (!solid && start >= 0) {
          if (raw.isNotEmpty && start - raw.last <= maxGap) {
            raw.last = x; // join with the previous stretch
          } else {
            raw.addAll([start, x]);
          }
          start = -1;
        }
      }
      final runs = <double>[];
      for (var k = 0; k < raw.length; k += 2) {
        if (raw[k + 1] - raw[k] >= minRun) runs.addAll([raw[k] / w, raw[k + 1] / w]);
      }
      rows.add(runs);
    }
    return _Photo(img, rows);
  }

  double t(int j) => j / (n - 1);
  double width(int j) => rows[j].isEmpty ? 0 : rows[j].last - rows[j].first;

  /// How wide the top rows are next to the shoulders (1 at and below the first
  /// row that is nearly full width), so the collar and shoulder slope stay narrow.
  double shoulderTaper(int j) {
    final k = _shoulderRow();
    return j >= k ? 1 : (width(j) / width(k)).clamp(0.3, 1.0);
  }

  /// Where the shoulders reach full width (0..1 from the top).
  double shoulderT() => t(_shoulderRow());

  int _shoulderRow() {
    var widest = 0.0;
    for (var k = 0; k < n && t(k) < 0.35; k++) {
      widest = max(widest, width(k));
    }
    for (var k = 0; k < n && t(k) < 0.35; k++) {
      if (widest > 0 && width(k) >= widest * 0.92) return k;
    }
    return 0;
  }

  /// Where the sleeves end (0..1 from the top), or null if there are none:
  /// the last row where sleeves stand apart from the body, or else the row
  /// where the piece suddenly gets narrower.
  double? sleeveEnd() {
    var last = -1, count = 0;
    for (var j = 0; j < n; j++) {
      if (t(j) <= 0.97 && rows[j].length >= 6) {
        count++;
        last = j;
      }
    }
    if (count >= 3) return t(min(last + 1, n - 1));
    var widest = 0.0;
    for (var j = 0; j < n - 2; j++) {
      final w = width(j);
      if (t(j) > 0.12 && widest > 0 && [0, 1, 2].every((d) => width(j + d) < widest * 0.82)) return t(j);
      widest = max(widest, w);
    }
    return null;
  }

  /// Where the legs split (0..1 from the top), or null for a skirt.
  double? crotch() {
    for (var j = 0; j < n - 2; j++) {
      if (t(j) > 0.06 && t(j) < 0.8 && [0, 1, 2].every((d) => rows[j + d].length >= 4)) return t(j);
    }
    return null;
  }
}

/// Front-facing photos, prepared once and kept for drawing on the model.
final _photos = <String, _Photo>{};
final _decoding = <String>{};

/// The prepared photo of [it], or null while it is still being read (then
/// [onReady] is called once it is ready).
_Photo? _photoFor(ClosetItem? it, VoidCallback onReady) {
  if (it == null || !it.fitted) return null;
  final key = '${it.id}:${it.imageBase64.length}';
  final hit = _photos[key];
  if (hit != null) return hit;
  if (_decoding.add(key)) {
    decodeImageFromList(base64Decode(it.imageBase64))
        .then(_Photo.of)
        .then(
          (p) {
            _photos[key] = p;
            _decoding.remove(key);
            onReady();
          },
          onError: (_) {
            _decoding.remove(key);
          },
        );
  }
  return null;
}

final _accPictures = <String, ui.Image>{};

/// The decoded picture of an accessory, or null while it is still being read.
ui.Image? _accPictureFor(ClosetItem? it, VoidCallback onReady) {
  if (it == null) return null;
  final key = 'acc:${it.id}:${it.imageBase64.length}';
  final hit = _accPictures[key];
  if (hit != null) return hit;
  if (_decoding.add(key)) {
    decodeImageFromList(base64Decode(it.imageBase64)).then(
      (img) {
        _accPictures[key] = img;
        _decoding.remove(key);
        onReady();
      },
      onError: (_) {
        _decoding.remove(key);
      },
    );
  }
  return null;
}

/// What the model is wearing: each piece's shape, and its photo when it has one.
/// Pieces without a saved look (older photo items) get a plain shape from their
/// category and color.
({Map<String, FlatSpec?> specs, Map<String, _Photo?> photos, Map<String, ui.Image?> accessories}) _wornLooks(
  VoidCallback onReady,
) => (
  specs: {
    for (final slot in outfitSlots)
      slot: avatarOutfit[slot] == null
          ? null
          : FlatSpec.of(avatarOutfit[slot]!.spec, avatarOutfit[slot]!.category, avatarOutfit[slot]!.color),
  },
  photos: {for (final slot in outfitSlots) slot: _photoFor(avatarOutfit[slot], onReady)},
  accessories: {for (final k in accessoryKinds) k: _accPictureFor(avatarAccessories[k], onReady)},
);

class _AvatarViewState extends State<AvatarView> {
  void _ready() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = avatarSettings;
    final looks = _wornLooks(_ready);
    final specs = looks.specs, photos = looks.photos, accessories = looks.accessories;
    return FittedBox(
      child: SizedBox(
        width: 240,
        height: 480,
        child: Transform.scale(
          scale: s.height,
          alignment: Alignment.bottomCenter,
          child: Stack(
            children: [
              CustomPaint(size: const Size(240, 480), painter: _BodyPainter(s)),
              CustomPaint(
                size: const Size(240, 480),
                painter: _ClothesPainter(s, specs, photos, accessories: accessories),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Body measurements used to fit clothes (same numbers the body is drawn with).
class _Geo {
  final double sh, bu, wa, hi, th, k;
  _Geo(List<double> m, this.k) : sh = m[0], bu = m[1], wa = m[2], hi = m[3], th = m[4];

  double body(double y) => _interp([
    [96.0, sh / 2],
    [108.0, sh / 2],
    [134.0, bu / 2],
    [168.0, wa / 2],
    [216.0, hi / 2],
  ], y);

  double _legX(double side, double y, bool outer) {
    final c = 120 + side * (2 + th / 2), ck = c - side, ca = c - 2 * side;
    final sg = outer ? side : -side;
    return _interp([
      [212.0, c + sg * th / 2],
      [328.0, ck + sg * th * 0.36],
      [438.0, ca + sg * th * 0.22],
    ], y);
  }

  double legOuter(double side, double y) => _legX(side, y, true);
  double legInner(double side, double y) => _legX(side, y, false);

  double armCx(double side, double y) {
    final xt = 120 + side * (sh / 2 + 3), xw = 120 + side * (sh / 2 + 15);
    return xt + (xw - xt) * (y - 100) / 126;
  }

  double armHalf(double y) => (11 - 5 * (y - 100) / 126) * k;
}

/// Torso-shaped garment (top, jacket, dress, skirt) that follows the body outline.
Path _bodyPath(
  _Geo g, {
  required double top,
  required double hem,
  required double ease,
  String? neck,
  double flare = 0,
}) {
  const cx = 120.0;
  double hw(double y) => y <= 216 ? g.body(y) + ease : g.body(216) + ease + (y - 216) * flare;
  final y0 = neck != null ? top + 4 : top;
  final ys = [for (var i = 0; i <= 24; i++) y0 + (hem - y0) * i / 24];
  final p = Path();
  if (neck != null) {
    p.moveTo(cx - 14, top);
    p.lineTo(cx - g.sh / 2 - ease * 0.4, top + 4);
  } else {
    p.moveTo(cx - hw(top), top);
  }
  for (final y in ys) {
    p.lineTo(cx - hw(y), y);
  }
  for (final y in ys.reversed) {
    p.lineTo(cx + hw(y), y);
  }
  if (neck != null) {
    p.lineTo(cx + g.sh / 2 + ease * 0.4, top + 4);
    p.lineTo(cx + 14, top);
    final depth = switch (neck) {
      'v' => 26.0,
      'collar' => 8.0,
      _ => 13.0,
    };
    if (neck == 'v') {
      p
        ..lineTo(cx, top + depth)
        ..lineTo(cx - 14, top);
    } else {
      p.quadraticBezierTo(cx, top + depth * 1.6, cx - 14, top);
    }
  }
  return p..close();
}

/// A sleeve that wraps the model's arm (so it matches the arm slider).
Path _sleevePath(_Geo g, double side, double end, double ease) {
  final ys = [for (var i = 0; i <= 8; i++) 96 + (end - 96) * i / 8];
  double a(double y) => g.armCx(side, y) - g.armHalf(y) - ease;
  double b(double y) => g.armCx(side, y) + g.armHalf(y) + ease;
  final p = Path()..moveTo(a(96), 96);
  for (final y in ys) {
    p.lineTo(a(y), y);
  }
  for (final y in ys.reversed) {
    p.lineTo(b(y), y);
  }
  return p..close();
}

/// One trouser leg that follows the model's leg.
Path _legPath(_Geo g, double side, double top, double hem, double ease) {
  double outer(double y) => y < 212 ? 120 + side * (g.body(y) + ease) : g.legOuter(side, y) + side * ease;
  double inner(double y) => y < 236 ? 120.0 : g.legInner(side, y) - side * ease;
  final ys = [for (var i = 0; i <= 22; i++) top + (hem - top) * i / 22];
  final p = Path()..moveTo(outer(top), top);
  for (final y in ys) {
    p.lineTo(outer(y), y);
  }
  for (final y in ys.reversed) {
    p.lineTo(inner(y), y);
  }
  return p..close();
}

/// Draws the model's clothes. Each piece has a shape fitted to the body. A piece
/// with a front-facing photo has that photo stretched onto the body row by row,
/// so it follows the shoulders, waist, hips, arms and legs; the others are drawn flat.
class _ClothesPainter extends CustomPainter {
  final AvatarSettings s;
  final Map<String, FlatSpec?> specs;
  final Map<String, _Photo?> photos;

  /// False for the 3D view's texture: no outline or shadow, since the clothes
  /// are wrapped around the body there.
  final bool edges;

  /// Accessory pictures by kind (hat, glasses, necklace, scarf, belt, watch, bag).
  final Map<String, ui.Image?> accessories;
  _ClothesPainter(this.s, this.specs, this.photos, {this.edges = true, this.accessories = const {}});

  /// Where an accessory goes: a box in model units.
  static Rect accessoryBox(_Geo g, String kind, ui.Image img) {
    final a = img.height / img.width;
    Rect box(double cx, double y, double w, String anchor) {
      final h = w * a;
      final top = anchor == 'top' ? y : (anchor == 'bottom' ? y - h : y - h / 2);
      return Rect.fromLTWH(cx - w / 2, top, w, h);
    }

    return switch (kind) {
      'hat' => box(120, 41, a < 0.62 ? 92 : 64, 'bottom'),
      'glasses' => box(120, 52, 50, 'middle'),
      'necklace' => box(120, 96, 38, 'top'),
      'scarf' => box(120, 84, 52, 'top'),
      'belt' => box(120, 181, 2 * (g.body(181) + 6), 'middle'),
      'watch' => box(g.armCx(1, 214), 214, 15 * g.k, 'middle'),
      _ => box(g.armCx(-1, 236), 232, 46, 'top'),
    };
  }

  /// Draws accessories of these kinds (whole pictures, placed rather than stretched).
  void _accessories(Canvas c, _Geo g, List<String> kinds) {
    for (final k in kinds) {
      final img = accessories[k];
      if (img == null) continue;
      final r = accessoryBox(g, k, img);
      c.save();
      if (k == 'hat' || k == 'glasses') {
        c.translate(120, 50);
        c.scale(s.head);
        c.translate(-120, -50);
      }
      final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
      if (edges) {
        c.saveLayer(
          r.inflate(6).translate(0, 1.2),
          Paint()
            ..colorFilter = const ColorFilter.mode(Color(0x40000000), BlendMode.srcIn)
            ..imageFilter = ui.ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
        );
        c.drawImageRect(img, src, r.translate(0, 1.2), Paint());
        c.restore();
      }
      c.drawImageRect(img, src, r, Paint()..filterQuality = FilterQuality.medium);
      c.restore();
    }
  }

  /// Straight lines through the points ([t, y] pairs, t from 0 at the top of the
  /// photo to 1 at the bottom) that say where each row of the photo lands on the model.
  static double Function(double) _rows(List<List<double>> pts) =>
      (t) => _interp(pts, t);

  /// Joins spans that touch or overlap; spans are [left, right] on the model.
  static List<List<double>> _merge(List<List<double>> spans) {
    spans.sort((a, b) => a[0].compareTo(b[0]));
    final out = <List<double>>[];
    for (final sp in spans) {
      if (out.isNotEmpty && sp[0] <= out.last[1] + 1) {
        out.last[1] = max(out.last[1], sp[1]);
      } else {
        out.add([sp[0], sp[1]]);
      }
    }
    return out;
  }

  /// Stretches [p] onto the body. [yAt] says where each row of the photo goes
  /// (top to bottom), [partsAt] which parts of the model the clothing covers at
  /// that height, left to right (for example left sleeve, body, right sleeve).
  /// When a row of the photo has one stretch of clothing per part, each stretch
  /// goes onto its own part (a sleeve onto its arm); otherwise the whole row is
  /// spread across all the parts. The piece gets a thin dark edge like the body's
  /// outline and a soft shadow, so it sits on the model instead of looking pasted on.
  ///
  /// [taper] (optional) narrows the parts toward the middle for a row (1 = full
  /// width), so the collar and sloping shoulders keep their shape.
  void _fit(
    Canvas c,
    _Photo p,
    double Function(double) yAt,
    List<List<double>> Function(double) partsAt, {
    double Function(int row)? taper,
  }) {
    const n = _Photo.n;
    final img = p.img;
    final w = img.width.toDouble(), h = img.height.toDouble();

    // For each row: strips of [photo left, photo right, model left, model right].
    final strips = List<List<List<double>>?>.filled(n, null);
    final split = List<bool>.filled(n, false);
    for (var j = 0; j < n; j++) {
      final runs = p.rows[j];
      if (runs.isEmpty) continue;
      var parts = partsAt(yAt(p.t(j)));
      if (parts.isEmpty) continue;
      final r = taper?.call(j) ?? 1.0;
      if (r < 1)
        parts = [
          for (final sp in parts) [120 + (sp[0] - 120) * r, 120 + (sp[1] - 120) * r],
        ];
      if (runs.length == parts.length * 2) {
        strips[j] = [
          for (var k = 0; k < parts.length; k++) [runs[2 * k], runs[2 * k + 1], parts[k][0], parts[k][1]],
        ];
      } else if (runs.length == 2 && parts.length > 1) {
        // Sleeves that touch the body in the photo: share the stretch out between the
        // parts by their widths, so each sleeve still lands on its own arm.
        final total = parts.fold(0.0, (a, e) => a + (e[1] - e[0]));
        var at = runs[0];
        strips[j] = [
          for (final e in parts)
            () {
              final w = (runs[1] - runs[0]) * (e[1] - e[0]) / total;
              final st = [at, at + w, e[0], e[1]];
              at += w;
              return st;
            }(),
        ];
        split[j] = parts.length == 3;
      } else {
        strips[j] = [
          [runs.first, runs.last, parts.map((e) => e[0]).reduce(min), parts.map((e) => e[1]).reduce(max)],
        ];
      }
    }
    final first = strips.indexWhere((e) => e != null);
    if (first < 0) return;
    for (var j = 0; j < n; j++) {
      if (strips[j] == null) {
        strips[j] = j < first ? strips[first] : strips[j - 1];
        split[j] = j < first ? split[first] : split[j - 1];
      }
    }

    final pos = <Offset>[], tex = <Offset>[], idx = <int>[];
    var box = Rect.zero;
    var hasBox = false;
    for (var j = 0; j < n - 1; j++) {
      final y0 = yAt(p.t(j)), y1 = yAt(p.t(j + 1));
      if (y1 <= y0) continue;
      final ty0 = p.t(j) * h, ty1 = p.t(j + 1) * h;
      // Widest strip last, so the body sits over the inner edge of the sleeves.
      final row = [...strips[j]!]..sort((a, b) => (a[3] - a[2]).compareTo(b[3] - b[2]));
      for (final st in row) {
        if (st[1] - st[0] < 1e-4 || st[3] - st[2] < 0.3) continue;
        final base = pos.length;
        // A hair of overlap between rows hides seams.
        pos.addAll([Offset(st[2], y0), Offset(st[3], y0), Offset(st[2], y1 + 0.6), Offset(st[3], y1 + 0.6)]);
        tex.addAll([Offset(st[0] * w, ty0), Offset(st[1] * w, ty0), Offset(st[0] * w, ty1), Offset(st[1] * w, ty1)]);
        idx.addAll([base, base + 1, base + 2, base + 1, base + 3, base + 2]);
        final r = Rect.fromLTRB(st[2], y0, st[3], y1);
        box = hasBox ? box.expandToInclude(r) : r;
        hasBox = true;
      }
    }
    if (!hasBox) return;

    final vertices = ui.Vertices(ui.VertexMode.triangles, pos, textureCoordinates: tex, indices: idx);
    Paint photoPaint() => Paint()
      ..shader = ui.ImageShader(
        img,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
        filterQuality: FilterQuality.medium,
      );
    final area = box.inflate(8);

    // Soft shadow, then a thin dark edge (both are the piece's own shape, darkened and blurred).
    for (final (color, blur, dy)
        in edges
            ? [(const Color(0x47000000), 3.0, 1.5), (const Color(0x80231914), 0.7, 0.0)]
            : const <(Color, double, double)>[]) {
      c.saveLayer(
        area.translate(0, dy),
        Paint()
          ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn)
          ..imageFilter = ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      );
      c.translate(0, dy);
      c.drawVertices(vertices, BlendMode.srcOver, photoPaint());
      c.restore();
    }

    // The piece itself, with a soft shade toward the sides so it looks rounded.
    c.saveLayer(area, Paint());
    c.drawVertices(vertices, BlendMode.srcOver, photoPaint());
    c.drawRect(
      area,
      Paint()
        ..blendMode = BlendMode.srcATop
        ..shader = ui.Gradient.linear(
          Offset(box.left, 0),
          Offset(box.right, 0),
          const [Color(0x38000000), Color(0x00000000), Color(0x00000000), Color(0x29000000)],
          const [0, 0.38, 0.55, 1],
        ),
    );
    // Where a sleeve that touched the body was split off, a soft seam so it reads
    // as its own part.
    final seam = Paint()
      ..blendMode = BlendMode.srcATop
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0x52140F0A);
    for (final side in [0, 1]) {
      final line = Path();
      var open = false;
      for (var j = 0; j < n - 1; j++) {
        final row = strips[j]!;
        if (split[j] && row.length == 3) {
          final x = side == 0 ? row[1][2] : row[1][3], y = yAt(p.t(j));
          if (open) {
            line.lineTo(x, y);
          } else {
            line.moveTo(x, y);
            open = true;
          }
        } else {
          open = false;
        }
      }
      c.drawPath(line, seam);
    }
    c.restore();
  }

  List<Path> _sleeves(_Geo g, String sleeves, double ease) {
    final end = sleeves == 'long' ? 224.0 : (sleeves == 'short' ? 150.0 : 0.0);
    if (end == 0) return [];
    return [
      for (final side in [-1.0, 1.0]) _sleevePath(g, side, end, ease),
    ];
  }

  /// Settings for a top, jacket or dress: hem, room around the body and sleeves.
  ({double hem, double ease, double sleeveEase, String sleeves, String neck, double flare}) _torsoOptions(
    FlatSpec sp,
    String slot,
    bool photo,
  ) {
    if (slot == 'Dresses') {
      return (
        hem: switch (sp.length) {
          'short' => 300.0,
          'long' => 430.0,
          _ => 360.0,
        },
        ease: 6.0,
        sleeveEase: 2.5,
        sleeves: sp.sleeves,
        neck: sp.neckline,
        flare: 0.26,
      );
    }
    final jacket = slot == 'Jackets';
    return (
      hem: switch (sp.length) {
        'short' => jacket ? 214.0 : 190.0,
        'long' => jacket ? 280.0 : 258.0,
        _ => jacket ? 244.0 : 226.0,
      },
      ease: photo ? (jacket ? 7.0 : 4.0) : (jacket ? 13.0 : 6.0),
      sleeveEase: photo ? (jacket ? 7.0 : 3.0) : (jacket ? 5.0 : 2.5),
      sleeves: (jacket && sp.sleeves == 'none') ? 'long' : sp.sleeves,
      neck: (jacket && sp.neckline == 'round') ? 'v' : sp.neckline,
      flare: 0.0,
    );
  }

  /// Where each row of a top, jacket or dress photo goes on the model, and which
  /// parts it covers at each height. [cover] (optional) gives the parts of the
  /// layer underneath, which a jacket must always cover.
  ({double Function(double) yAt, List<List<double>> Function(double) partsAt}) _torsoLayout(
    _Geo g,
    _Photo photo,
    String slot,
    FlatSpec sp, {
    List<List<double>> Function(double)? cover,
  }) {
    final o = _torsoOptions(sp, slot, true);
    final jacket = slot == 'Jackets';
    final hem = o.hem, ease = o.ease, sleeveEase = o.sleeveEase, flare = o.flare;
    final ts = photo.sleeveEnd();
    // The photo decides the sleeve length when it shows sleeves (sleeves that end
    // past 60% of the way down are long), so a long-sleeve top is never squashed
    // into short sleeves even if its saved details say otherwise.
    final armEnd = ts != null
        ? (ts > 0.6 ? 224.0 : 150.0)
        : (o.sleeves == 'long' ? 224.0 : (o.sleeves == 'short' ? 150.0 : null));
    // The collar sits just above the shoulders and the shoulder seam on them; a
    // jacket a little higher and wider than what is under it.
    final tk = photo.shoulderT();
    final top = tk > 0.01 && (ts == null || tk < ts - 0.02)
        ? (jacket
              ? [
                  [0.0, 86.0],
                  [tk, 101.0],
                ]
              : [
                  [0.0, 89.0],
                  [tk, 104.0],
                ])
        : [
            [0.0, jacket ? 90.0 : 92.0],
          ];
    late final double Function(double) yAt;
    double? sleeveTo; // where sleeves end on the model
    if (ts == null && armEnd == null) {
      // Sleeveless (straps): starts on top of the shoulders, not up at the neck.
      yAt = _rows([
        [0, 97],
        [1, hem],
      ]);
    } else if (ts != null && armEnd != null && ts < 0.95 && armEnd < hem - 6) {
      yAt = _rows([
        ...top,
        [ts, armEnd],
        [1, hem],
      ]);
      sleeveTo = armEnd;
    } else if (ts != null && ts >= 0.95) {
      // Sleeves reach the bottom of the photo (a cropped top with long sleeves).
      yAt = _rows([
        ...top,
        [1, max(hem, armEnd ?? 224)],
      ]);
      sleeveTo = yAt(1);
    } else {
      yAt = _rows([
        ...top,
        [1, hem],
      ]);
      sleeveTo = ts != null ? yAt(ts) : armEnd;
    }

    // Clothes hang from the chest down instead of pulling in at the waist (not
    // from the shoulders: that width belongs to the sleeves, and would make a box).
    double hang(double y) {
      if (y < 134) return g.body(y);
      var widest = g.body(min(y, 216));
      for (final k in [134.0, 168.0, 216.0]) {
        if (k <= y) widest = max(widest, g.body(k));
      }
      return widest;
    }

    List<List<double>> partsAt(double y) {
      // Halfway between hanging straight and following the waist: relaxed, not a box.
      final b = hang(y) * 0.55 + g.body(min(y, 216)) * 0.45 + ease + (y > 216 ? (y - 216) * flare : 0);
      // Sleeveless pieces (straps) sit inside the shoulders, not out on them.
      final bb = sleeveTo == null && y < 112 ? min(b, g.sh / 2 - 4) : b;
      final spans = [
        [120 - bb, 120 + bb],
      ];
      final end = sleeveTo;
      // Sleeves start a little above the arm so the round of the shoulder is covered.
      if (end != null && y >= 92 && y <= end + 1) {
        final along = ((y - 96) / max(1.0, end - 96)).clamp(0.0, 1.0);
        for (final side in [-1.0, 1.0]) {
          // Sleeves open up toward the hem and sit slightly out from the arm. Near the
          // armpit a sleeve meets the body; a jacket sleeve then hangs free with the arm.
          final cx = g.armCx(side, y) + side * along * (jacket ? 4.5 : 2.5);
          final half = g.armHalf(y) + sleeveEase + along * 3.5;
          final meet = !jacket || along < 0.35;
          spans.add(
            side < 0
                ? [cx - half, meet ? max(cx + half, 120 - bb + 1) : cx + half]
                : [meet ? min(cx - half, 120 + bb - 1) : cx - half, cx + half],
          );
        }
      }
      // Kept separate (left sleeve, body, right sleeve) so each sleeve lands on its arm.
      spans.sort((a, c) => a[0].compareTo(c[0]));
      // Always cover the layer underneath (below the shoulders), with a little room.
      if (cover != null && y >= 104) {
        for (final u in cover(y)) {
          List<double>? best;
          var most = double.negativeInfinity;
          for (final sp in spans) {
            final o = min(sp[1], u[1]) - max(sp[0], u[0]);
            if (o > most) {
              most = o;
              best = sp;
            }
          }
          if (best != null) {
            best[0] = min(best[0], u[0] - 1.5);
            best[1] = max(best[1], u[1] + 1.5);
          }
        }
      }
      return spans;
    }

    return (yAt: yAt, partsAt: partsAt);
  }

  /// A top, jacket or dress. With a photo, the sleeves in the photo are put on the
  /// arms (ending where the sleeve length says) and the rest on the torso. A jacket
  /// is sized to cover the top or dress under it.
  void _torsoPiece(Canvas c, _Geo g, FlatSpec sp, String slot) {
    final photo = photos[slot];
    if (photo == null) {
      final o = _torsoOptions(sp, slot, false);
      for (final p in [
        ..._sleeves(g, o.sleeves, o.sleeveEase),
        _bodyPath(g, top: 92, hem: o.hem, ease: o.ease, neck: o.neck, flare: o.flare),
      ]) {
        paintGarmentPath(c, p, sp, outline: 1.4);
      }
      if (slot == 'Jackets') {
        c.drawLine(
          const Offset(120, 118),
          Offset(120, o.hem),
          Paint()
            ..color = const Color(0x66000000)
            ..strokeWidth = 1.2,
        );
      }
      return;
    }
    List<List<double>> Function(double)? cover;
    if (slot == 'Jackets') {
      final underSlot = avatarOutfit['Dresses'] != null ? 'Dresses' : 'Tops';
      final underPhoto = photos[underSlot], underSpec = specs[underSlot];
      if (underPhoto != null && underSpec != null) {
        cover = _torsoLayout(g, underPhoto, underSlot, underSpec).partsAt;
      }
    }
    final layout = _torsoLayout(g, photo, slot, sp, cover: cover);
    // The collar stays narrow, but by the shoulders the piece is full width, so the
    // top of the arms never shows through.
    _fit(
      c,
      photo,
      layout.yAt,
      layout.partsAt,
      taper: (j) => max(photo.shoulderTaper(j), ((layout.yAt(photo.t(j)) - 89) / 7).clamp(0.0, 1.0)),
    );
  }

  void _upper(Canvas c, _Geo g, FlatSpec sp, String slot) => _torsoPiece(c, g, sp, slot);

  void _dress(Canvas c, _Geo g, FlatSpec sp) => _torsoPiece(c, g, sp, 'Dresses');

  void _bottoms(Canvas c, _Geo g, FlatSpec sp) {
    final photo = photos['Bottoms'];
    final skirt = photo != null ? photo.crotch() == null : sp.bottomType == 'skirt';
    // How tall the photo is for its width tells short from long.
    final tall = photo == null ? null : photo.img.height / photo.img.width;
    if (skirt) {
      final hem = tall != null && tall < 0.8
          ? 286.0 // a mini skirt
          : switch (sp.length) {
              'short' => 286.0,
              'long' => 410.0,
              _ => 340.0,
            };
      if (photo == null) {
        paintGarmentPath(c, _bodyPath(g, top: 176, hem: hem, ease: 4, flare: 0.3), sp, outline: 1.4);
        return;
      }
      _fit(
        c,
        photo,
        _rows([
          [0, 176],
          [1, hem],
        ]),
        (y) {
          final b = y <= 216 ? g.body(y) + 4 : g.body(216) + 4 + (y - 216) * 0.3;
          return [
            [120 - b, 120 + b],
          ];
        },
      );
      return;
    }
    final hem = sp.bottomType == 'shorts' || (tall != null && tall < 1.4)
        ? 292.0 // shorts (a shorts photo is about as tall as it is wide)
        : (sp.length == 'short' ? 372.0 : 436.0);
    if (photo == null) {
      for (final side in [-1.0, 1.0]) {
        paintGarmentPath(c, _legPath(g, side, 176, hem, 3.5), sp, outline: 1.4);
      }
      return;
    }
    // Waist at the top, the split between the legs where the model's legs part.
    final tc = photo.crotch()!;
    const ease = 3.5;
    double outer(double side, double y) =>
        y < 212 ? 120 + side * (g.body(y) + ease) : g.legOuter(side, y) + side * ease;
    double inner(double side, double y) => g.legInner(side, y) - side * ease;
    _fit(
      c,
      photo,
      _rows(
        hem > 246
            ? [
                [0, 176],
                [tc, 236],
                [1, hem],
              ]
            : [
                [0, 176],
                [1, hem],
              ],
      ),
      (y) {
        if (y < 236) {
          return [
            [outer(-1, y), outer(1, y)],
          ];
        }
        return _merge([
          [outer(-1, y), inner(-1, y)],
          [inner(1, y), outer(1, y)],
        ]);
      },
    );
  }

  void _shoes(Canvas c, _Geo g, FlatSpec sp) {
    double centre(double side) => 120 + side * (2 + g.th / 2) - 2 * side + side * 7;
    final photo = photos['Shoes'];
    if (photo == null) {
      for (final side in [-1.0, 1.0]) {
        final p = Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(centre(side), 448), width: 36, height: 24),
              const Radius.circular(11),
            ),
          );
        paintGarmentPath(c, p, sp, outline: 1.4);
      }
      return;
    }
    // One shoe on each foot. Boots also go up the shin; flats sit low.
    List<List<double>> feet() => _merge([
      for (final side in [-1.0, 1.0]) [centre(side) - 19, centre(side) + 19],
    ]);
    final style = avatarOutfit['Shoes']?.spec?['style'];
    if (style == 'boots') {
      const ease = 3.0;
      _fit(
        c,
        photo,
        _rows([
          [0, 384],
          [0.68, 438],
          [1, 462],
        ]),
        (y) {
          if (y >= 438) return feet();
          return _merge([
            for (final side in [-1.0, 1.0])
              () {
                final a = g.legOuter(side, y) + side * ease, b = g.legInner(side, y) - side * ease;
                return [min(a, b), max(a, b)];
              }(),
          ]);
        },
      );
      return;
    }
    if (style == 'ankle') {
      // High-tops and hiking boots: up over the ankle, then the foot.
      const ease = 3.0;
      _fit(
        c,
        photo,
        _rows([
          [0, 414],
          [0.6, 440],
          [1, 462],
        ]),
        (y) {
          if (y >= 438) return feet();
          return _merge([
            for (final side in [-1.0, 1.0])
              () {
                final a = g.legOuter(side, y) + side * ease, b = g.legInner(side, y) - side * ease;
                return [min(a, b), max(a, b)];
              }(),
          ]);
        },
      );
      return;
    }
    _fit(
      c,
      photo,
      _rows(
        style == 'low'
            ? [
                [0, 444],
                [1, 462],
              ]
            : [
                [0, 432],
                [1, 462],
              ],
      ),
      (y) => feet(),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geo(s.m, s.arms);
    final hasDress = avatarOutfit['Dresses'] != null;

    // Shoes first, so skirts, dresses and trouser hems fall over them.
    final shoes = specs['Shoes'];
    if (shoes != null) _shoes(canvas, g, shoes);

    // Bottoms (not under a dress)
    final bottoms = specs['Bottoms'];
    if (!hasDress && bottoms != null) _bottoms(canvas, g, bottoms);

    // Top, or a dress instead
    if (!hasDress) {
      final top = specs['Tops'];
      if (top != null) _upper(canvas, g, top, 'Tops');
    } else {
      final dress = specs['Dresses'];
      if (dress != null) _dress(canvas, g, dress);
    }

    // Necklace and belt over the top, under a jacket
    _accessories(canvas, g, const ['necklace', 'belt']);

    // Jacket on top
    final jacket = specs['Jackets'];
    if (jacket != null) _upper(canvas, g, jacket, 'Jackets');

    // Then scarf, watch, glasses, hat, and a bag held at the hand
    _accessories(canvas, g, const ['scarf', 'watch', 'glasses', 'hat', 'bag']);
  }

  @override
  bool shouldRepaint(covariant _ClothesPainter old) => true;
}

class AvatarPage extends StatefulWidget {
  const AvatarPage({super.key});

  @override
  State<AvatarPage> createState() => _AvatarPageState();
}

class _AvatarPageState extends State<AvatarPage> {
  static const slots = outfitSlots;
  final _rng = Random();
  bool _in3d = false;

  // The small model in the corner, shown once the big one has scrolled away.
  final _scroll = ScrollController();
  final _showMini = ValueNotifier(false);
  bool _miniLeft = false; // dragged to the bottom left
  double _miniDrag = 0;
  static const _stageBottom = 470.0; // where the big model ends (2D/3D switch + model)

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final show = _scroll.hasClients && _scroll.offset > _stageBottom - 60;
      if (show != _showMini.value) _showMini.value = show;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _showMini.dispose();
    super.dispose();
  }

  Widget _miniModel() {
    return ValueListenableBuilder<bool>(
      valueListenable: _showMini,
      builder: (context, show, _) => AnimatedPositioned(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        bottom: 12,
        left: _miniLeft ? 12 : null,
        right: _miniLeft ? null : 12,
        child: IgnorePointer(
          ignoring: !show,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: show ? 1 : 0,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 180),
              scale: show ? 1 : 0.85,
              child: Semantics(
                button: true,
                label: 'Your model. Tap to go back up to it.',
                child: GestureDetector(
                  onTap: () =>
                      _scroll.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic),
                  // Drag sideways to move it to the other corner.
                  onHorizontalDragStart: (_) => _miniDrag = 0,
                  onHorizontalDragUpdate: (d) => _miniDrag += d.delta.dx,
                  onHorizontalDragEnd: (_) {
                    if (_miniDrag < -30 && !_miniLeft) setState(() => _miniLeft = true);
                    if (_miniDrag > 30 && _miniLeft) setState(() => _miniLeft = false);
                  },
                  child: Container(
                    width: 84,
                    height: 150,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: lilac,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 4))],
                    ),
                    // Always the 2D model: light enough to draw small, and it updates instantly.
                    child: AvatarView(key: const ValueKey('mini')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _shuffle() {
    setState(() {
      for (final slot in slots) {
        final list = closet.items.where((i) => i.category == slot).toList();
        avatarOutfit[slot] = list.isEmpty ? null : list[_rng.nextInt(list.length)];
      }
      if (_rng.nextBool()) avatarOutfit['Jackets'] = null;
      // Up to two accessories.
      avatarAccessories.clear();
      final acc = closet.items.where((i) => i.category == 'Accessories').toList();
      for (var n = _rng.nextInt(3); n > 0 && acc.isNotEmpty; n--) {
        final a = acc[_rng.nextInt(acc.length)];
        avatarAccessories[accessoryKind(a)] = a;
      }
      // Either a dress, or a top with bottoms.
      if (avatarOutfit['Dresses'] != null &&
          (_rng.nextBool() || (avatarOutfit['Tops'] == null && avatarOutfit['Bottoms'] == null))) {
        avatarOutfit['Tops'] = null;
        avatarOutfit['Bottoms'] = null;
      } else {
        avatarOutfit['Dresses'] = null;
      }
    });
  }

  Widget _slotRow(String slot) {
    final list = closet.items.where((i) => i.category == slot).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(slot, style: Theme.of(context).textTheme.titleSmall),
        ),
        SizedBox(
          height: 72,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('None'),
                  selected: avatarOutfit[slot] == null,
                  onSelected: (_) => setState(() => avatarOutfit[slot] = null),
                ),
              ),
              for (final it in list)
                GestureDetector(
                  onTap: () => setState(() => wearPiece(slot, it)),
                  child: Container(
                    width: 56,
                    margin: const EdgeInsets.only(right: 8),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: avatarOutfit[slot] == it ? aubergine : Colors.black12,
                        width: avatarOutfit[slot] == it ? 3 : 1,
                      ),
                    ),
                    child: Image.memory(base64Decode(it.imageBase64), fit: BoxFit.cover),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Accessories: wear several at once (one of each kind).
  Widget _accessoryRow() {
    final list = closet.items.where((i) => i.category == 'Accessories').toList();
    if (list.isEmpty) return const SizedBox.shrink();
    final worn = {
      for (final a in avatarAccessories.values)
        if (a != null) a.id,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text('Accessories (wear several: one of each kind)', style: Theme.of(context).textTheme.titleSmall),
        ),
        SizedBox(
          height: 72,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('None'),
                  selected: worn.isEmpty,
                  onSelected: (_) => setState(avatarAccessories.clear),
                ),
              ),
              for (final it in list)
                GestureDetector(
                  onTap: () => setState(() => toggleAccessory(it)),
                  child: Container(
                    width: 56,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: worn.contains(it.id) ? aubergine : Colors.black12,
                        width: worn.contains(it.id) ? 3 : 1,
                      ),
                    ),
                    child: Image.memory(base64Decode(it.imageBase64), fit: BoxFit.contain, gaplessPlayback: true),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _swatches(List<Color> colors, int selected, ValueChanged<int> onTap) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var i = 0; i < colors.length; i++)
          GestureDetector(
            onTap: () => onTap(i),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: colors[i],
              child: selected == i ? const Icon(Icons.check, size: 16, color: Colors.white70) : null,
            ),
          ),
      ],
    );
  }

  Widget _slider(String label, double min, double max, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 104, child: Text(label)),
        Expanded(
          child: Slider(min: min, max: max, value: value, onChanged: onChanged),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([closet, avatarSettings]),
      builder: (context, _) {
        final s = avatarSettings;
        return Stack(
          children: [
            ListView(
              controller: _scroll,
              // Room at the bottom so the small model never covers the last row.
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 180),
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('2D')),
                    ButtonSegment(value: true, label: Text('3D')),
                  ],
                  selected: {_in3d},
                  onSelectionChanged: (v) => setState(() => _in3d = v.first),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 400,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(color: lilac, borderRadius: BorderRadius.circular(24)),
                  // Not const on purpose: a const widget is never rebuilt, so the model would ignore the sliders.
                  // Only one of the two views exists at a time.
                  child: _in3d ? Model3DView(key: const ValueKey('3d')) : AvatarView(key: const ValueKey('2d')),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: currentModelOutfit().isEmpty ? null : () => saveOutfit(context, currentModelOutfit()),
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Save outfit'),
                  ),
                ),
                const Label('Body type'),
                SegmentedButton<String>(
                  segments: [for (final b in bodyTypes.keys) ButtonSegment(value: b, label: Text(b))],
                  selected: {s.body},
                  onSelectionChanged: (v) => s.setBody(v.first),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'A starting point. Fine-tune it below. Picking another type resets your changes.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Label('Measurements'),
                _slider('Height', 0.85, 1.0, s.height, s.setHeight),
                for (var i = 0; i < measureLabels.length; i++)
                  _slider(measureLabels[i], measureMin[i], measureMax[i], s.m[i], (v) => s.setMeasure(i, v)),
                const Label('Skin tone'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < skinTones.length; i++)
                      GestureDetector(
                        onTap: () => s.setSkin(i),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: skinTones[i],
                          child: s.skin == i ? const Icon(Icons.check, size: 16, color: Colors.black54) : null,
                        ),
                      ),
                  ],
                ),
                const Label('Hair'),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < hairStyles.length; i++)
                      ChoiceChip(label: Text(hairStyles[i]), selected: s.hair == i, onSelected: (_) => s.setHair(i)),
                  ],
                ),
                const SizedBox(height: 12),
                _swatches(hairColors, s.hairColor, s.setHairColor),
                const Label('Eyes'),
                _swatches(eyeColors, s.eyes, s.setEyes),
                const Label('Head and arms'),
                _slider('Head size', 0.9, 1.15, s.head, s.setHead),
                _slider('Arms', 0.8, 1.5, s.arms, s.setArms),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: closet.items.isEmpty ? null : _shuffle,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Shuffle outfit'),
                ),
                StylistPanel(onChanged: () => setState(() {})),
                if (closet.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('Add clothes to your closet to dress your model.', textAlign: TextAlign.center),
                  ),
                for (final slot in slots) _slotRow(slot),
                _accessoryRow(),
              ],
            ),
            _miniModel(),
          ],
        );
      },
    );
  }
}
