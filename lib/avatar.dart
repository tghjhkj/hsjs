import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';
import 'stylist.dart';
import 'theme.dart';

// shoulder, waist, hip widths
const bodyTypes = <String, List<double>>{
  'Feminine': [100, 76, 110],
  'Neutral': [106, 90, 100],
  'Masculine': [118, 100, 98],
};

const skinTones = [
  Color(0xFFFFDFC4),
  Color(0xFFF0C8A0),
  Color(0xFFD9A066),
  Color(0xFFB07A4F),
  Color(0xFF8A5A3B),
  Color(0xFF5C3A24),
];

const outfitSlots = ['Jackets', 'Tops', 'Dresses', 'Bottoms', 'Shoes'];

/// What the model is currently wearing, by category.
final avatarOutfit = <String, ClosetItem?>{};

class AvatarSettings extends ChangeNotifier {
  String body = 'Neutral';
  double height = 0.95, build = 1.0;
  int skin = 1;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    body = p.getString('av_body') ?? body;
    if (!bodyTypes.containsKey(body)) body = 'Neutral';
    height = (p.getDouble('av_height') ?? height).clamp(0.85, 1.0);
    build = (p.getDouble('av_build') ?? build).clamp(0.8, 1.3);
    skin = (p.getInt('av_skin') ?? skin).clamp(0, skinTones.length - 1);
  }

  Future<void> update({String? body, double? height, double? build, int? skin}) async {
    this.body = body ?? this.body;
    this.height = height ?? this.height;
    this.build = build ?? this.build;
    this.skin = skin ?? this.skin;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('av_body', this.body);
    await p.setDouble('av_height', this.height);
    await p.setDouble('av_build', this.build);
    await p.setInt('av_skin', this.skin);
  }
}

final avatarSettings = AvatarSettings();

class _BodyPainter extends CustomPainter {
  final double sh, wa, hi;
  final Color skin;
  _BodyPainter(this.sh, this.wa, this.hi, this.skin);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = skin;
    const cx = 120.0;
    canvas.drawCircle(const Offset(cx, 52), 28, p);
    canvas.drawRect(Rect.fromLTWH(cx - 9, 76, 18, 22), p);
    final torso = Path()
      ..moveTo(cx - sh / 2, 96)
      ..lineTo(cx + sh / 2, 96)
      ..lineTo(cx + wa / 2, 156)
      ..lineTo(cx + hi / 2, 214)
      ..lineTo(cx - hi / 2, 214)
      ..lineTo(cx - wa / 2, 156)
      ..close();
    canvas.drawPath(torso, p);
    for (final side in [-1.0, 1.0]) {
      final armX = cx + side * (sh / 2 + 2) - 9;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(armX, 98, 18, 125), const Radius.circular(9)), p);
      final legX = side < 0 ? cx - hi / 2 + 2 : cx + 2;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(legX, 210, hi / 2 - 4, 235), const Radius.circular(12)), p);
    }
  }

  @override
  bool shouldRepaint(covariant _BodyPainter old) => true;
}

class AvatarView extends StatelessWidget {
  const AvatarView({super.key});

  @override
  Widget build(BuildContext context) {
    final s = avatarSettings;
    final m = bodyTypes[s.body]!;
    final sh = m[0] * s.build, wa = m[1] * s.build, hi = m[2] * s.build;
    const cx = 120.0;
    final dress = avatarOutfit['Dresses'] != null;
    final wide = max(sh, hi);

    Widget piece(String slot, double left, double top, double w, double h) {
      final it = avatarOutfit[slot];
      if (it == null) return const SizedBox.shrink();
      return Positioned(
        left: left,
        top: top,
        width: w,
        height: h,
        child: Image.memory(base64Decode(it.imageBase64), fit: BoxFit.fill, gaplessPlayback: true),
      );
    }

    return FittedBox(
      child: SizedBox(
        width: 240,
        height: 480,
        child: Transform.scale(
          scale: s.height,
          alignment: Alignment.bottomCenter,
          child: Stack(children: [
            CustomPaint(size: const Size(240, 480), painter: _BodyPainter(sh, wa, hi, skinTones[s.skin])),
            if (!dress) piece('Bottoms', cx - hi / 2 - 2, 205, hi + 4, 228),
            piece('Shoes', cx - hi / 2 - 10, 428, hi + 20, 44),
            if (!dress) piece('Tops', cx - sh / 2 - 16, 90, sh + 32, 138),
            if (dress) piece('Dresses', cx - wide / 2 - 10, 90, wide + 20, 300),
            piece('Jackets', cx - sh / 2 - 20, 88, sh + 40, 150),
          ]),
        ),
      ),
    );
  }
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
        Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(slot, style: Theme.of(context).textTheme.titleSmall)),
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
              child: const AvatarView(),
            ),
            const Label('Body type'),
            SegmentedButton<String>(
              segments: [for (final b in bodyTypes.keys) ButtonSegment(value: b, label: Text(b))],
              selected: {s.body},
              onSelectionChanged: (v) => s.update(body: v.first),
            ),
            Row(children: [
              const SizedBox(width: 56, child: Text('Height')),
              Expanded(child: Slider(min: 0.85, max: 1.0, value: s.height, onChanged: (v) => s.update(height: v))),
            ]),
            Row(children: [
              const SizedBox(width: 56, child: Text('Build')),
              Expanded(child: Slider(min: 0.8, max: 1.3, value: s.build, onChanged: (v) => s.update(build: v))),
            ]),
            const Label('Skin tone'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < skinTones.length; i++)
                  GestureDetector(
                    onTap: () => s.update(skin: i),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: skinTones[i],
                      child: s.skin == i ? const Icon(Icons.check, size: 16, color: Colors.black54) : null,
                    ),
                  ),
              ],
            ),
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
