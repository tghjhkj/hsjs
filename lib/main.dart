import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'avatar.dart';
import 'cutout.dart';
import 'flat_art.dart';
import 'samples.dart';
import 'scan.dart';
import 'theme.dart';
import 'weather.dart';

const categories = ['Tops', 'Bottoms', 'Dresses', 'Jackets', 'Shoes', 'Accessories'];

/// Paste the address of your Cloudflare Worker here (see worker/SETUP.md).
/// Leave it as is to use Muse without AI.
const aiEndpoint = 'https://muse-ai.ryuadhikumara.workers.dev';
bool get aiConfigured => !aiEndpoint.startsWith('PASTE');

/// Short, readable reason for a failed AI request (shown in error messages).
String aiWhy(Object e) {
  final t = e.toString().replaceFirst('Exception: ', '');
  if (t.contains('Failed to fetch') || t.contains('ClientException')) {
    return 'the browser could not reach your Worker (check its address and the ALLOWED_ORIGIN setting)';
  }
  if (t.contains('TimeoutException')) return 'the AI took too long';
  return t.length > 160 ? t.substring(0, 160) : t;
}

class ClosetItem {
  final String id, name, category, color, imageBase64;
  final Map<String, dynamic>? spec; // how the AI says it looks (its shape on the model)
  /// True when [imageBase64] is a front-facing photo made to fit the model;
  /// false when it is a flat drawing (or an old plain photo, if [spec] is null).
  final bool fitted;

  ClosetItem({
    required this.id,
    required this.name,
    required this.category,
    required this.color,
    required this.imageBase64,
    this.spec,
    this.fitted = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'color': color,
        'imageBase64': imageBase64,
        'spec': spec,
        'fitted': fitted,
      };

  factory ClosetItem.fromJson(Map<String, dynamic> j) => ClosetItem(
        id: j['id'],
        name: j['name'],
        category: j['category'],
        color: j['color'],
        imageBase64: j['imageBase64'],
        spec: j['spec'] == null ? null : Map<String, dynamic>.from(j['spec'] as Map),
        fitted: j['fitted'] == true,
      );

  String get meta => color.isEmpty ? category : '$color, ${category.toLowerCase()}';
}

/// Holds the closet and saves it on the device.
class ClosetStore extends ChangeNotifier {
  final List<ClosetItem> items = [];
  static const _key = 'closet';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    items.clear();
    for (final e in jsonDecode(raw) as List) {
      final j = Map<String, dynamic>.from(e as Map);
      // Sample pieces are saved without their picture; it comes from the app itself.
      final builtIn = samplePicture(j['id'] as String);
      if (builtIn != null) j['imageBase64'] = builtIn;
      if ((j['imageBase64'] as String? ?? '').isEmpty) continue;
      items.add(ClosetItem.fromJson(j));
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key,
        jsonEncode([
          for (final i in items) {...i.toJson(), if (samplePicture(i.id) != null) 'imageBase64': ''}
        ]));
  }

  Future<void> add(ClosetItem item) async {
    items.add(item);
    notifyListeners();
    await _save();
  }

  /// Adds several pieces and saves once.
  Future<void> addAll(List<ClosetItem> list) async {
    items.addAll(list);
    notifyListeners();
    await _save();
  }

  Future<void> remove(ClosetItem item) async {
    items.remove(item);
    notifyListeners();
    await _save();
  }

  /// Swaps the picture. The saved look ([spec]) is kept only if one is given.
  Future<void> replaceImage(ClosetItem item, String imageBase64, {Map<String, dynamic>? spec, bool fitted = false}) async {
    final i = items.indexOf(item);
    if (i < 0) return;
    items[i] = ClosetItem(
      id: item.id,
      name: item.name,
      category: item.category,
      color: item.color,
      imageBase64: imageBase64,
      spec: spec,
      fitted: fitted,
    );
    notifyListeners();
    await _save();
  }
}

final closet = ClosetStore();

/// The picture saved for a piece: a front-facing photo that fits the model when
/// the image AI can make one, otherwise a flat drawing of [spec].
/// [why] says why the photo could not be made (null when it worked).
Future<({String image, bool fitted, String? why})> fittedLook(String photoBase64, FlatSpec spec) async {
  if (aiConfigured) {
    final r = await flattenClothing(photoBase64, category: spec.category, green: spec.isGreen);
    if (r.image != null) return (image: r.image!, fitted: true, why: null);
    return (image: await renderFlat(spec), fitted: false, why: r.error);
  }
  return (image: await renderFlat(spec), fitted: false, why: 'Add your AI address first.');
}

/// Turns a piece that is still a plain photo into one that fits the model:
/// the AI describes its shape, then makes the front-facing photo (or a drawing).
/// Returns false when the AI could not describe it and a plain drawing was used.
Future<bool> makeFlat(ClosetItem item) async {
  final ai = await flatIllustrationFor(item.imageBase64, item.category);
  final spec = ai == null ? FlatSpec.guess(item.category, item.color) : FlatSpec.fromJson(ai.spec, item.category);
  final look = ai == null
      ? (image: await renderFlat(spec), fitted: false, why: null)
      : await fittedLook(item.imageBase64, spec);
  await closet.replaceImage(item, look.image, spec: spec.toJson(), fitted: look.fitted);
  return ai != null;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await closet.load();
  // Every sample piece is in the closet from the first launch.
  await ensureSamplePieces();
  // Start the model in something simple, so the Model tab isn't empty.
  for (final (slot, id) in [('Tops', 'sample-tee'), ('Bottoms', 'sample-jeans'), ('Shoes', 'sample-sneakers')]) {
    final piece = closet.items.where((i) => i.id == id).firstOrNull;
    if (piece != null) wearPiece(slot, piece);
  }
  await avatarSettings.load();
  await weather.load();
  runApp(const MuseApp());
}

class MuseApp extends StatelessWidget {
  const MuseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Muse',
      debugShowCheckedModeBanner: false,
      theme: museTheme(),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(['My closet', 'Outfits', 'Model'][_tab])),
      body: [const ClosetPage(), OutfitPage(onWear: () => setState(() => _tab = 2)), const AvatarPage()][_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.checkroom_outlined), selectedIcon: Icon(Icons.checkroom), label: 'Closet'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Outfits'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Model'),
        ],
      ),
    );
  }
}

class ItemTile extends StatelessWidget {
  final ClosetItem item;
  final VoidCallback? onTap;
  const ItemTile(this.item, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: Image.memory(
                  base64Decode(item.imageBase64),
                  gaplessPlayback: true,
                  fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => const Icon(Icons.broken_image),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
          Text(item.meta, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: t.bodySmall?.copyWith(color: ink.withAlpha(150))),
        ],
      ),
    );
  }
}

class ClosetPage extends StatefulWidget {
  const ClosetPage({super.key});

  @override
  State<ClosetPage> createState() => _ClosetPageState();
}

class _ClosetPageState extends State<ClosetPage> {
  String _filter = 'All';
  int? _flatLeft; // pieces still being turned flat (null when not running)

  /// Turns every piece that is still a plain photo into one that fits the model.
  Future<void> _flattenAll() async {
    final todo = closet.items.where((i) => i.spec == null).toList();
    var plain = 0;
    setState(() => _flatLeft = todo.length);
    for (final item in todo) {
      if (!await makeFlat(item)) plain++;
      if (mounted) setState(() => _flatLeft = _flatLeft! - 1);
    }
    if (!mounted) return;
    setState(() => _flatLeft = null);
    if (plain > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$plain piece${plain == 1 ? ' was' : 's were'} drawn plain because the AI could not see them.')));
    }
  }

  Future<void> _pick(ImageSource source) async {
    // Small + compressed so many items fit in the browser's storage.
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 600, imageQuality: 70);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddItemPage(id: id, imageBase64: base64Encode(bytes))),
    );
  }

  Future<void> _scan(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1000, imageQuality: 75);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ScanPage(bytes: bytes)));
  }

  void _chooseSource() {
    showModalBottomSheet(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(sheet);
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(sheet);
                _pick(ImageSource.gallery);
              },
            ),
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Scan a wardrobe with the camera'),
              subtitle: const Text('AI finds each piece. You tap the ones to add.'),
              onTap: () {
                Navigator.pop(sheet);
                _scan(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_mosaic_outlined),
              title: const Text('Scan a wardrobe photo from gallery'),
              onTap: () {
                Navigator.pop(sheet);
                _scan(ImageSource.gallery);
              },
            ),
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.checkroom_outlined),
              title: const Text('Add sample pieces'),
              subtitle: const Text('Ready-made pieces to try on the model.'),
              onTap: () async {
                Navigator.pop(sheet);
                final messenger = ScaffoldMessenger.of(context);
                final added = await addSamplePieces();
                messenger.showSnackBar(SnackBar(
                    content: Text(added == 0
                        ? 'The sample pieces are already in your closet.'
                        : 'Added $added sample pieces. Dress the model in the Model tab.')));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showItem(ClosetItem item) {
    showModalBottomSheet(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 240,
                  width: double.infinity,
                  color: Colors.white,
                  child: Image.memory(base64Decode(item.imageBase64), fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 16),
              Text(item.name, style: Theme.of(context).textTheme.headlineSmall),
              Text(item.meta),
              const SizedBox(height: 12),
              // Older pieces saved as photos can be turned flat here.
              if (item.spec == null) ...[
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(sheet);
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.showSnackBar(const SnackBar(content: Text('Making it fit the model...')));
                  final ok = await makeFlat(item);
                  messenger.hideCurrentSnackBar();
                  if (!ok) {
                    messenger.showSnackBar(const SnackBar(content: Text('The AI could not see it, so a plain flat version was drawn. Try again later.')));
                  }
                },
                icon: const Icon(Icons.draw_outlined),
                label: const Text('Make it fit the model (AI)'),
              ),
              const SizedBox(height: 8),
              ],
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                onPressed: () {
                  closet.remove(item);
                  Navigator.pop(sheet);
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove from closet'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _chooseSource,
        icon: const Icon(Icons.add),
        label: const Text('Add piece'),
      ),
      body: ListenableBuilder(
        listenable: closet,
        builder: (context, _) {
          if (closet.items.isEmpty) {
            return EmptyState(
              icon: Icons.checkroom,
              title: 'Your closet is empty',
              message: 'Add a photo of something you own, or scan a whole wardrobe at once.',
              actionLabel: 'Add a piece',
              onAction: _chooseSource,
            );
          }
          final shown = _filter == 'All'
              ? closet.items
              : closet.items.where((i) => i.category == _filter).toList();
          final photos = closet.items.where((i) => i.spec == null).length;
          return Column(
            children: [
              if (photos > 0 || _flatLeft != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: _flatLeft != null
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.draw_outlined),
                      title: Text(_flatLeft != null
                          ? 'Making pieces fit the model... $_flatLeft left'
                          : '$photos piece${photos == 1 ? ' is' : 's are'} still a photo'),
                      subtitle: _flatLeft != null ? null : const Text('Turn them into front-facing pieces that fit the model.'),
                      trailing: _flatLeft != null
                          ? null
                          : FilledButton(onPressed: _flattenAll, child: const Text('Fix them')),
                    ),
                  ),
                ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final c in ['All', ...categories])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c),
                          selected: _filter == c,
                          onSelected: (_) => setState(() => _filter = c),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? Center(child: Text('Nothing in $_filter yet.'))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.72,
                        ),
                        itemCount: shown.length,
                        itemBuilder: (context, i) => ItemTile(shown[i], onTap: () => _showItem(shown[i])),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class AddItemPage extends StatefulWidget {
  final String id, imageBase64;
  const AddItemPage({super.key, required this.id, required this.imageBase64});

  @override
  State<AddItemPage> createState() => _AddItemPageState();
}

class _AddItemPageState extends State<AddItemPage> {
  final _name = TextEditingController();
  final _color = TextEditingController();
  String _category = categories.first;
  bool _busy = false; // the AI is reading the photo
  bool _fitting = false; // the image AI is making the front-facing version
  FlatSpec? _spec; // the piece's shape on the model
  bool _fromAi = false; // true when the AI described the photo (not a guess from the color name)
  String? _drawn; // flat drawing (always made, used when there is no fitted photo)
  String? _fitted; // front-facing photo that fits the model
  String? _fitNote; // why there is no fitted photo
  bool _useFitted = true;

  String? get _result => (_useFitted && _fitted != null) ? _fitted : _drawn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (aiConfigured) {
        _autoFill();
      } else {
        _guessDrawn();
      }
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Sends the photo to your Worker: the AI names the piece and describes its
  /// shape, then the image AI makes the front-facing version.
  Future<void> _autoFill() async {
    if (!aiConfigured) {
      _toast('Add your AI address in main.dart first (see worker/SETUP.md).');
      return;
    }
    setState(() => _busy = true);
    try {
      final photo = base64Decode(widget.imageBase64);
      final isPng = photo.length > 3 && photo[0] == 0x89 && photo[1] == 0x50;
      final res = await http
          .post(
            Uri.parse(aiEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'image': widget.imageBase64, 'mime': isPng ? 'image/png' : 'image/jpeg'}),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception('${res.statusCode} ${res.body}');
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        final name = (j['name'] ?? '').toString();
        final color = (j['color'] ?? '').toString();
        if (name.isNotEmpty) _name.text = name;
        if (color.isNotEmpty) _color.text = color;
        if (categories.contains(j['category'])) _category = j['category'] as String;
      });
      _spec = FlatSpec.fromJson(j, _category);
      _fromAi = true;
      final drawn = await renderFlat(_spec!);
      if (mounted) setState(() => _drawn = drawn);
    } catch (e) {
      if (mounted) _toast('AI problem: ${aiWhy(e)}. A plain flat version is drawn from the color instead.');
      await _guessDrawn();
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _fit();
  }

  /// Asks the image AI for the front-facing version that fits the model.
  Future<void> _fit() async {
    final spec = _spec;
    if (spec == null || !mounted) return;
    setState(() {
      _fitting = true;
      _fitNote = null;
    });
    final r = await flattenClothing(widget.imageBase64, category: spec.category, green: spec.isGreen);
    if (!mounted) return;
    setState(() {
      _fitting = false;
      if (r.image != null) {
        _fitted = r.image;
        _useFitted = true;
      } else {
        _fitNote = r.error;
      }
    });
  }

  /// Without the AI: draws a plain flat version from the category and color name.
  Future<void> _guessDrawn() async {
    _fromAi = false;
    _spec = FlatSpec.guess(_category, _color.text);
    final drawn = await renderFlat(_spec!);
    if (mounted) setState(() => _drawn = drawn);
  }

  /// Redraws after the category (or, for a guessed look, the color) changes.
  /// The fitted photo stays as it is.
  Future<void> _redraw() async {
    if (!_fromAi) return _guessDrawn();
    final spec = _spec;
    if (spec == null) return;
    _spec = spec.withCategory(_category);
    final img = await renderFlat(_spec!);
    if (mounted) setState(() => _drawn = img);
  }

  Future<void> _save() async {
    if (_spec == null || _drawn == null) await _guessDrawn();
    final spec = _spec!.withCategory(_category);
    final fitted = _useFitted && _fitted != null;
    await closet.add(ClosetItem(
      id: widget.id,
      name: _name.text.trim().isEmpty ? 'Untitled' : _name.text.trim(),
      category: _category,
      color: _color.text.trim(),
      imageBase64: fitted ? _fitted! : await renderFlat(spec),
      spec: spec.toJson(),
      fitted: fitted,
    ));
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final working = _busy || _fitting;
    final status = _busy ? 'Looking at your photo...' : 'Making a front-facing version...';
    return Scaffold(
      appBar: AppBar(title: const Text('New piece')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              height: 300,
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(base64Decode(_result ?? widget.imageBase64), fit: BoxFit.contain, gaplessPlayback: true),
                  if (working || _result == null)
                    Container(
                      color: Colors.white.withAlpha(170),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(working ? status : 'Drawing a flat version...'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_fitted != null && _drawn != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Real look')),
                  ButtonSegment(value: false, label: Text('Drawing')),
                ],
                selected: {_useFitted},
                onSelectionChanged: (v) => setState(() => _useFitted = v.first),
              ),
            ),
          if (_fitNote != null && !working)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'No front-facing photo, so the drawing is used: $_fitNote',
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          FilledButton.tonalIcon(
            onPressed: working ? null : _autoFill,
            icon: working
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(working ? status : (_fromAi ? 'Try the AI again' : 'Fill in with AI')),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'The photo is sent to an AI service to name the piece and turn it into a front-facing version that fits your model. Only that version is saved.',
              style: TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          TextField(controller: _name, decoration: fieldDecoration('Name')),
          const SizedBox(height: 12),
          TextField(
            controller: _color,
            decoration: fieldDecoration('Color'),
            onChanged: (_) {
              if (!_fromAi) _redraw();
            },
          ),
          const Label('Category'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in categories)
                ChoiceChip(
                  label: Text(c),
                  selected: _category == c,
                  onSelected: (_) {
                    setState(() => _category = c);
                    _redraw();
                  },
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: working ? null : _save, child: const Text('Save to closet')),
        ],
      ),
    );
  }
}

class OutfitPage extends StatefulWidget {
  /// Called after the outfit is put on the model (to show the Model tab).
  final VoidCallback? onWear;
  const OutfitPage({super.key, this.onWear});

  @override
  State<OutfitPage> createState() => _OutfitPageState();
}

class _OutfitPageState extends State<OutfitPage> {
  final _rng = Random();
  List<ClosetItem> _outfit = [];
  String? _reason; // why the outfit suits today's weather

  @override
  void initState() {
    super.initState();
    weather.refresh(); // at most once an hour
  }

  /// A random outfit, suited to today's weather when a city is saved.
  void _generate() {
    final w = weather.today;
    final outfit = pickOutfit(closet.items, w, _rng);
    setState(() {
      _outfit = outfit;
      _reason = (w != null && outfit.isNotEmpty) ? outfitReason(w, outfit) : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          const WeatherCard(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: closet.items.isEmpty ? null : _generate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate outfit'),
            ),
          ),
          if (_reason != null)
            Padding(padding: const EdgeInsets.only(top: 10), child: Text(_reason!, textAlign: TextAlign.center)),
          const SizedBox(height: 12),
          Expanded(
            child: _outfit.isEmpty
                ? const EmptyState(
                    icon: Icons.auto_awesome,
                    title: 'No outfit yet',
                    message: 'Add a few pieces to your closet, then generate a combination.',
                  )
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: _outfit.length,
                    itemBuilder: (context, i) => ItemTile(_outfit[i]),
                  ),
          ),
          if (_outfit.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    for (final slot in outfitSlots) {
                      avatarOutfit[slot] = null;
                    }
                    for (final it in _outfit) {
                      if (outfitSlots.contains(it.category)) wearPiece(it.category, it);
                    }
                    widget.onWear?.call();
                  },
                  icon: const Icon(Icons.person_outline),
                  label: const Text('Put it on the model'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
