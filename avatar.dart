import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';
import 'stylist.dart';
import 'theme.dart';

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
const eyeColors = [
  Color(0xFF4A2E1C),
  Color(0xFF8A6A2F),
  Color(0xFF4F7F5A),
  Color(0xFF4A78B5),
  Color(0xFF7A8088),
];

/// What the model is currently wearing, by category.
final avatarOutfit = <String, ClosetItem?>{};

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

  List<double> get m => s.m;
  Color get skin => skinTones[s.skin];

  /// Fill with a left-to-right gradient so every limb looks rounded, not flat.
  Paint _shaded(Rect r) {
    final dark = Color.lerp(skin, Colors.black, 0.2)!;
    final light = Color.lerp(skin, Colors.white, 0.1)!;
    return Paint()
      ..shader = ui.Gradient.linear(
        Offset(r.left, 0),
        Offset(r.right, 0),
        [dark, skin, light, dark],
        [0, 0.35, 0.65, 1],
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

  void _hairBack(Canvas canvas) {
    if (s.hair != 1) return;
    _headSpace(canvas, () {
      final path = Path()
        ..moveTo(93, 40)
        ..cubicTo(86, 80, 88, 115, 94, 135)
        ..lineTo(146, 135)
        ..cubicTo(152, 115, 154, 80, 147, 40)
        ..close();
      canvas.drawPath(path, Paint()..color = hairColors[s.hairColor]);
    });
  }

  void _face(Canvas canvas) {
    final white = Paint()..color = Colors.white;
    final iris = Paint()..color = eyeColors[s.eyes];
    for (final x in [111.0, 129.0]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(x, 52), width: 8.4, height: 5.2), white);
      canvas.drawCircle(Offset(x, 52), 2.1, iris);
    }
    final brow = Paint()
      ..color = hairColors[s.hairColor]
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(106, 45)
        ..quadraticBezierTo(111, 42, 116, 45)
        ..moveTo(124, 45)
        ..quadraticBezierTo(129, 42, 134, 45),
      brow,
    );
    canvas.drawPath(
      Path()
        ..moveTo(114, 66)
        ..quadraticBezierTo(120, 70, 126, 66),
      Paint()
        ..color = const Color(0xFFB5545C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  void _hairFront(Canvas canvas) {
    if (s.hair == 4) return;
    final paint = Paint()..color = hairColors[s.hairColor];
    if (s.hair == 3) {
      paint.color = paint.color.withAlpha(217);
      canvas.drawPath(
        Path()
          ..moveTo(96, 46)
          ..cubicTo(97, 28, 108, 22, 120, 22)
          ..cubicTo(132, 22, 143, 28, 144, 46)
          ..cubicTo(138, 34, 130, 30, 120, 30)
          ..cubicTo(110, 30, 102, 34, 96, 46)
          ..close(),
        paint,
      );
      return;
    }
    canvas.drawPath(
      Path()
        ..moveTo(94, 54)
        ..cubicTo(92, 20, 108, 14, 120, 14)
        ..cubicTo(132, 14, 148, 20, 146, 54)
        ..cubicTo(140, 36, 130, 30, 120, 30)
        ..cubicTo(110, 30, 100, 36, 94, 54)
        ..close(),
      paint,
    );
    if (s.hair == 2) canvas.drawCircle(const Offset(120, 12), 11, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sh = m[0], bu = m[1], wa = m[2], hi = m[3], th = m[4];
    final k = s.arms;
    const cx = 120.0;

    void part(Path path, {bool edge = false}) {
      final r = path.getBounds();
      canvas.drawPath(path, _shaded(r));
      if (edge) {
        canvas.drawPath(
          path,
          _shaded(r)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }

    // Soft shadow on the floor.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(cx, 470), width: hi * 1.8, height: 14),
      Paint()
        ..color = const Color(0x2E000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    _hairBack(canvas);

    for (final side in [-1.0, 1.0]) {
      // Leg: thigh, knee and ankle widths, then a foot.
      final c = cx + side * (2 + th / 2), ck = c - side, ca = c - 2 * side;
      final ht = th / 2, hk = th * 0.36, ha = th * 0.22;
      final oT = c + side * ht, iT = c - side * ht;
      final oK = ck + side * hk, iK = ck - side * hk;
      final oA = ca + side * ha, iA = ca - side * ha;
      final leg = Path()
        ..moveTo(oT, 212)
        ..cubicTo(oT, 270, oK, 300, oK, 328)
        ..cubicTo(oK, 360, oA, 400, oA, 438)
        ..lineTo(iA, 438)
        ..cubicTo(iA, 400, iK, 360, iK, 328)
        ..cubicTo(iK, 300, iT, 270, iT, 212)
        ..close();
      part(leg, edge: true);
      part(Path()..addOval(Rect.fromCenter(center: Offset(ca + side * 6, 448), width: 28, height: 16)));

      // Arm and hand (the Arms slider makes them thinner or thicker).
      final xt = cx + side * (sh / 2 - 1), xw = cx + side * (sh / 2 + 8);
      final arm = Path()
        ..moveTo(xt - 11 * k, 100)
        ..lineTo(xt + 11 * k, 100)
        ..lineTo(xw + 6 * k, 226)
        ..lineTo(xw - 6 * k, 226)
        ..close();
      part(arm, edge: true);
      part(Path()..addOval(Rect.fromCenter(center: Offset(xw, 236), width: 16 * k, height: 22)));
    }

    // Torso: smooth curves through shoulders, bust, waist and hips.
    final torso = Path()
      ..moveTo(cx - 14, 92)
      ..cubicTo(cx - sh * 0.3, 94, cx - sh / 2, 96, cx - sh / 2, 108)
      ..cubicTo(cx - sh / 2, 122, cx - bu / 2, 124, cx - bu / 2, 134)
      ..cubicTo(cx - bu / 2, 148, cx - wa / 2, 154, cx - wa / 2, 168)
      ..cubicTo(cx - wa / 2, 184, cx - hi / 2, 196, cx - hi / 2, 216)
      ..lineTo(cx + hi / 2, 216)
      ..cubicTo(cx + hi / 2, 196, cx + wa / 2, 184, cx + wa / 2, 168)
      ..cubicTo(cx + wa / 2, 154, cx + bu / 2, 148, cx + bu / 2, 134)
      ..cubicTo(cx + bu / 2, 124, cx + sh / 2, 122, cx + sh / 2, 108)
      ..cubicTo(cx + sh / 2, 96, cx + sh * 0.3, 94, cx + 14, 92)
      ..close();
    part(torso, edge: true);

    // Neck.
    part(Path()
      ..moveTo(cx - 10, 74)
      ..lineTo(cx + 10, 74)
      ..lineTo(cx + 14, 98)
      ..lineTo(cx - 14, 98)
      ..close());

    // Head, face and hair (scaled together by the Head size slider).
    _headSpace(canvas, () {
      part(Path()..addOval(Rect.fromCenter(center: const Offset(cx, 50), width: 48, height: 58)));
      _face(canvas);
      _hairFront(canvas);
    });
  }

  @override
  bool shouldRepaint(covariant _BodyPainter old) => true;
}

final _decoded = <String, ui.Image>{};
final _pending = <String>{};

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

class _AvatarViewState extends State<AvatarView> {
  ui.Image? _image(ClosetItem? it) {
    if (it == null) return null;
    final key = '${it.id}:${it.imageBase64.length}';
    final hit = _decoded[key];
    if (hit != null) return hit;
    if (_pending.add(key)) {
      decodeImageFromList(base64Decode(it.imageBase64)).then((img) {
        _decoded[key] = img;
        _pending.remove(key);
        if (mounted) setState(() {});
      });
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = avatarSettings;
    final worn = {for (final slot in outfitSlots) slot: _image(avatarOutfit[slot])};
    return FittedBox(
      child: SizedBox(
        width: 240,
        height: 480,
        child: Transform.scale(
          scale: s.height,
          alignment: Alignment.bottomCenter,
          child: Stack(children: [
            CustomPaint(size: const Size(240, 480), painter: _BodyPainter(s)),
            CustomPaint(size: const Size(240, 480), painter: _ClothesPainter(s.m, worn)),
          ]),
        ),
      ),
    );
  }
}

/// Draws each garment photo bent to follow the body: the photo is cut into
/// thin horizontal strips and every strip is stretched to the body's width at
/// that height (shoulders, bust, waist, hips, thighs).
class _ClothesPainter extends CustomPainter {
  final List<double> m;
  final Map<String, ui.Image?> worn;
  _ClothesPainter(this.m, this.worn);

  void _warp(Canvas canvas, ui.Image img, double top, double bottom, double Function(double) halfWidth) {
    const cx = 120.0, bands = 28;
    final pos = <Offset>[], tex = <Offset>[], idx = <int>[];
    var maxHalf = 0.0;
    for (var i = 0; i <= bands; i++) {
      final t = i / bands, y = top + (bottom - top) * t, h = halfWidth(y);
      if (h > maxHalf) maxHalf = h;
      pos
        ..add(Offset(cx - h, y))
        ..add(Offset(cx + h, y));
      tex
        ..add(Offset(0, img.height * t))
        ..add(Offset(img.width.toDouble(), img.height * t));
      if (i > 0) {
        final a = (i - 1) * 2;
        idx.addAll([a, a + 1, a + 2, a + 1, a + 3, a + 2]);
      }
    }
    final rect = Rect.fromLTRB(cx - maxHalf, top, cx + maxHalf, bottom);
    canvas.saveLayer(rect, Paint());
    canvas.drawVertices(
      ui.Vertices(ui.VertexMode.triangles, pos, textureCoordinates: tex, indices: idx),
      BlendMode.srcOver,
      Paint()..shader = ui.ImageShader(img, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage),
    );
    // Light shade across the garment so it looks rounded.
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.modulate
        ..shader = ui.Gradient.linear(
          Offset(rect.left, 0),
          Offset(rect.right, 0),
          const [Color(0xFFB8B8B8), Colors.white, Color(0xFFD2D2D2)],
          const [0, 0.45, 1],
        ),
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sh = m[0], bu = m[1], wa = m[2], hi = m[3], th = m[4];
    final torso = [
      [96.0, sh / 2],
      [108.0, sh / 2],
      [134.0, bu / 2],
      [168.0, wa / 2],
      [216.0, hi / 2],
    ];
    final legs = [
      [212.0, 2 + th],
      [328.0, 1 + 0.86 * th],
      [438.0, 0.72 * th],
    ];
    double body(double y) => _interp(torso, y);
    double leg(double y) => _interp(legs, y);
    double smooth(double t) {
      final c = t.clamp(0.0, 1.0);
      return c * c * (3 - 2 * c);
    }

    // Wide at the shoulders (sleeves), then following the body down.
    double Function(double) upper(double ease, double sleeve) => (y) {
          final t = smooth((y - 118) / 50);
          return (sh / 2 + sleeve) * (1 - t) + (body(y) + ease) * t;
        };

    final dress = worn['Dresses'];
    final bottoms = worn['Bottoms'];
    if (dress == null && bottoms != null) {
      _warp(canvas, bottoms, 205, 438, (y) => max(leg(y) + 4, y < 225 ? hi / 2 + 3 : 0.0));
    }
    final shoes = worn['Shoes'];
    if (shoes != null) {
      final w = max(hi, 2 * th + 4) + 20;
      canvas.drawImageRect(
        shoes,
        Rect.fromLTWH(0, 0, shoes.width.toDouble(), shoes.height.toDouble()),
        Rect.fromLTWH(120 - w / 2, 428, w, 44),
        Paint(),
      );
    }
    final tops = worn['Tops'];
    if (dress == null && tops != null) _warp(canvas, tops, 92, 228, upper(7, 18));
    if (dress != null) {
      final u = upper(7, 8);
      _warp(canvas, dress, 92, 330, (y) => y <= 216 ? u(y) : u(216) + (y - 216) * 0.22);
    }
    final jacket = worn['Jackets'];
    if (jacket != null) _warp(canvas, jacket, 90, 240, upper(13, 22));
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

  void _shuffle() {
    setState(() {
      for (final slot in slots) {
        final list = closet.items.where((i) => i.category == slot).toList();
        avatarOutfit[slot] = list.isEmpty ? null : list[_rng.nextInt(list.length)];
      }
      if (_rng.nextBool()) avatarOutfit['Dresses'] = null;
      if (_rng.nextBool()) avatarOutfit['Jackets'] = null;
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
            child: Text(slot, style: Theme.of(context).textTheme.titleSmall)),
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
                  onTap: () => setState(() => avatarOutfit[slot] = it),
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
    return Row(children: [
      SizedBox(width: 104, child: Text(label)),
      Expanded(child: Slider(min: min, max: max, value: value, onChanged: onChanged)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([closet, avatarSettings]),
      builder: (context, _) {
        final s = avatarSettings;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              height: 400,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(color: lilac, borderRadius: BorderRadius.circular(24)),
              // Not const on purpose: a const widget is never rebuilt, so the model would ignore the sliders.
              child: AvatarView(),
            ),
            const Label('Body type'),
            SegmentedButton<String>(
              segments: [for (final b in bodyTypes.keys) ButtonSegment(value: b, label: Text(b))],
              selected: {s.body},
              onSelectionChanged: (v) => s.setBody(v.first),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('A starting point. Fine-tune it below. Picking another type resets your changes.',
                  style: Theme.of(context).textTheme.bodySmall),
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
          ],
        );
      },
    );
  }
}
