import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'main.dart';
import 'theme.dart';

class Detection {
  final String name, category, color;
  final Rect box; // each side is 0..1 of the photo
  bool selected = false;
  Detection(this.name, this.category, this.color, this.box);
}

/// Crops part of a photo (box sides are 0..1) and returns it as PNG bytes.
Future<Uint8List> cropPhoto(Uint8List bytes, Rect box) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final img = (await codec.getNextFrame()).image;
  final src = Rect.fromLTRB(box.left * img.width, box.top * img.height,
      box.right * img.width, box.bottom * img.height);
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
      img, src, Rect.fromLTWH(0, 0, src.width, src.height), ui.Paint());
  final out =
      await recorder.endRecording().toImage(src.width.round(), src.height.round());
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

class ScanPage extends StatefulWidget {
  final Uint8List bytes;
  const ScanPage({super.key, required this.bytes});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  double _aspect = 1;
  List<Detection> _found = [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (!aiConfigured) {
      setState(() {
        _busy = false;
        _error = 'Add your AI address in main.dart first (see worker/SETUP.md).';
      });
      return;
    }
    try {
      final img = await decodeImageFromList(widget.bytes);
      final res = await http
          .post(
            Uri.parse(aiEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'mode': 'detect', 'image': base64Encode(widget.bytes)}),
          )
          .timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) throw Exception('status ${res.statusCode}');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final found = <Detection>[];
      for (final e in (data['items'] as List? ?? [])) {
        final b = (e['box'] as List).map((n) => (n as num).toDouble()).toList();
        final c = e['category'];
        found.add(Detection(
          (e['name'] ?? 'Item').toString(),
          categories.contains(c) ? c as String : 'Tops',
          (e['color'] ?? '').toString(),
          Rect.fromLTRB(b[0], b[1], b[2], b[3]),
        ));
      }
      if (!mounted) return;
      setState(() {
        _aspect = img.width / img.height;
        _found = found;
        _busy = false;
        if (found.isEmpty) _error = 'No clothing found. Try a clearer photo.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not reach the AI. Check your Worker address and try again.';
        });
      }
    }
  }

  Future<void> _add() async {
    setState(() => _busy = true);
    for (final d in _found.where((d) => d.selected)) {
      final png = await cropPhoto(widget.bytes, d.box);
      await closet.add(ClosetItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: d.name,
        category: d.category,
        color: d.color,
        imageBase64: base64Encode(png),
      ));
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final count = _found.where((d) => d.selected).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Tap the items to add')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: _aspect,
                          child: LayoutBuilder(builder: (context, c) {
                            final w = c.maxWidth, h = c.maxHeight;
                            return Stack(children: [
                              Positioned.fill(child: Image.memory(widget.bytes, fit: BoxFit.fill)),
                              for (final d in _found)
                                Positioned(
                                  left: d.box.left * w,
                                  top: d.box.top * h,
                                  width: d.box.width * w,
                                  height: d.box.height * h,
                                  child: GestureDetector(
                                    onTap: () => setState(() => d.selected = !d.selected),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: d.selected ? const Color(0x555B2C83) : const Color(0x11FFFFFF),
                                        border: Border.all(
                                          color: d.selected ? aubergine : Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                      alignment: Alignment.topLeft,
                                      child: Text(d.name,
                                          style: const TextStyle(
                                              backgroundColor: Colors.black54,
                                              color: Colors.white,
                                              fontSize: 11)),
                                    ),
                                  ),
                                ),
                            ]);
                          }),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton(
                        onPressed: count == 0 ? null : _add,
                        child: Text(count == 0 ? 'Tap an item to select it' : 'Add $count to my closet'),
                      ),
                    ),
                  ],
                ),
    );
  }
}
