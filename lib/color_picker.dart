import 'package:flutter/material.dart';

/// A colour square (hue from left to right, strength from top to bottom) with a
/// slider on its right to make the colour lighter or darker, like most apps.
class ColorSquarePicker extends StatefulWidget {
  final Color initial;
  final ValueChanged<Color> onChanged;
  const ColorSquarePicker({super.key, required this.initial, required this.onChanged});

  @override
  State<ColorSquarePicker> createState() => _ColorSquarePickerState();
}

class _ColorSquarePickerState extends State<ColorSquarePicker> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  void _set(HSVColor v) {
    setState(() => _hsv = v);
    widget.onChanged(v.toColor());
  }

  void _pickSquare(Offset p, Size size) {
    final x = (p.dx / size.width).clamp(0.0, 1.0), y = (p.dy / size.height).clamp(0.0, 1.0);
    // Keep the brightness; if the colour was black, lift it so the change shows.
    _set(_hsv.withHue(x * 359.9).withSaturation(1 - y).withValue(_hsv.value < 0.05 ? 0.8 : _hsv.value));
  }

  void _pickSlider(Offset p, Size size) {
    _set(_hsv.withValue(1 - (p.dy / size.height).clamp(0.0, 1.0)));
  }

  @override
  Widget build(BuildContext context) {
    const h = 220.0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: h,
        child: Row(children: [
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final size = Size(c.maxWidth, h);
              return Semantics(
                label: 'Colour square',
                child: GestureDetector(
                  onPanDown: (d) => _pickSquare(d.localPosition, size),
                  onPanUpdate: (d) => _pickSquare(d.localPosition, size),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: CustomPaint(size: size, painter: _SquarePainter(_hsv)),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 34,
            child: LayoutBuilder(builder: (context, c) {
              final size = Size(34, h);
              return Semantics(
                label: 'Lighter or darker',
                slider: true,
                value: '${(_hsv.value * 100).round()}%',
                increasedValue: '${((_hsv.value + 0.1).clamp(0.0, 1.0) * 100).round()}%',
                decreasedValue: '${((_hsv.value - 0.1).clamp(0.0, 1.0) * 100).round()}%',
                onIncrease: () => _set(_hsv.withValue((_hsv.value + 0.1).clamp(0.0, 1.0))),
                onDecrease: () => _set(_hsv.withValue((_hsv.value - 0.1).clamp(0.0, 1.0))),
                child: GestureDetector(
                  onPanDown: (d) => _pickSlider(d.localPosition, size),
                  onPanUpdate: (d) => _pickSlider(d.localPosition, size),
                  child: CustomPaint(size: size, painter: _SliderPainter(_hsv)),
                ),
              );
            }),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _hsv.toColor(),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black12),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '#${(_hsv.toColor().toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ]),
    ]);
  }
}

class _SquarePainter extends CustomPainter {
  final HSVColor hsv;
  _SquarePainter(this.hsv);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    // Hue across...
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(colors: [
          for (var i = 0; i <= 6; i++) HSVColor.fromAHSV(1, i * 60.0 % 360, 1, 1).toColor(),
        ]).createShader(r),
    );
    // ...strength fading to grey toward the bottom...
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF)],
        ).createShader(r),
    );
    // ...shown at the slider's lightness.
    canvas.drawRect(r, Paint()..color = Colors.black.withValues(alpha: 1 - hsv.value));
    // Where the colour is.
    final p = Offset(hsv.hue / 360 * size.width, (1 - hsv.saturation) * size.height);
    canvas.drawCircle(p, 10, Paint()..color = hsv.toColor());
    canvas.drawCircle(p, 10, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.white);
    canvas.drawCircle(p, 11.5, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.black38);
  }

  @override
  bool shouldRepaint(covariant _SquarePainter old) => old.hsv != hsv;
}

class _SliderPainter extends CustomPainter {
  final HSVColor hsv;
  _SliderPainter(this.hsv);

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(17));
    canvas.drawRRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [hsv.withValue(1).toColor(), Colors.black],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(r, Paint()..style = PaintingStyle.stroke..color = Colors.black12);
    final y = (1 - hsv.value) * size.height;
    final thumb = Rect.fromCenter(center: Offset(size.width / 2, y.clamp(6.0, size.height - 6)), width: size.width + 6, height: 12);
    canvas.drawRRect(RRect.fromRectAndRadius(thumb, const Radius.circular(6)), Paint()..color = Colors.white);
    canvas.drawRRect(
      RRect.fromRectAndRadius(thumb, const Radius.circular(6)),
      Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.black38,
    );
  }

  @override
  bool shouldRepaint(covariant _SliderPainter old) => old.hsv != hsv;
}

/// Opens the colour picker in a sheet. Changes show live; Cancel puts the old colour back.
Future<void> pickColor(
  BuildContext context, {
  required String title,
  required Color current,
  required ValueChanged<Color> onChanged,
  required VoidCallback onCancel,
}) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          ColorSquarePicker(initial: current, onChanged: onChanged),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(sheet, false), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => Navigator.pop(sheet, true), child: const Text('Done')),
          ]),
        ]),
      ),
    ),
  );
  if (done != true) onCancel();
}
