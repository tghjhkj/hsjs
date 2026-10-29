import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'avatar.dart';
import 'scan.dart';
import 'theme.dart';

const categories = ['Tops', 'Bottoms', 'Dresses', 'Jackets', 'Shoes', 'Accessories'];

/// Paste the address of your Cloudflare Worker here (see worker/SETUP.md).
/// Leave it as is to use Muse without AI.
const aiEndpoint = 'muse-ai.ryuadhikumara.workers.dev';
bool get aiConfigured => !aiEndpoint.startsWith('PASTE');

class ClosetItem {
  final String id, name, category, color, imageBase64;

  ClosetItem({
    required this.id,
    required this.name,
    required this.category,
    required this.color,
    required this.imageBase64,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'color': color,
        'imageBase64': imageBase64,
      };

  factory ClosetItem.fromJson(Map<String, dynamic> j) => ClosetItem(
        id: j['id'],
        name: j['name'],
        category: j['category'],
        color: j['color'],
        imageBase64: j['imageBase64'],
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
    items
      ..clear()
      ..addAll((jsonDecode(raw) as List).map((e) => ClosetItem.fromJson(e as Map<String, dynamic>)));
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items.map((i) => i.toJson()).toList()));
  }

  Future<void> add(ClosetItem item) async {
    items.add(item);
    notifyListeners();
    await _save();
  }

  Future<void> remove(ClosetItem item) async {
    items.remove(item);
    notifyListeners();
    await _save();
  }
}

final closet = ClosetStore();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await closet.load();
  await avatarSettings.load();
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
      body: [const ClosetPage(), const OutfitPage(), const AvatarPage()][_tab],
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
                child: Image.memory(
                  base64Decode(item.imageBase64),
                  gaplessPlayback: true,
                  fit: BoxFit.cover,
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
          return Column(
            children: [
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
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (aiConfigured) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoFill());
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Sends the photo to your Worker, which asks the AI to describe the item.
  Future<void> _autoFill() async {
    if (!aiConfigured) {
      _toast('Add your AI address in main.dart first (see worker/SETUP.md).');
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await http
          .post(
            Uri.parse(aiEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'image': widget.imageBase64}),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception('status ${res.statusCode}');
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        final name = (j['name'] ?? '').toString();
        final color = (j['color'] ?? '').toString();
        if (name.isNotEmpty) _name.text = name;
        if (color.isNotEmpty) _color.text = color;
        if (categories.contains(j['category'])) _category = j['category'] as String;
      });
    } catch (_) {
      if (mounted) _toast('Could not reach the AI. You can fill it in by hand.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    await closet.add(ClosetItem(
      id: widget.id,
      name: _name.text.trim().isEmpty ? 'Untitled' : _name.text.trim(),
      category: _category,
      color: _color.text.trim(),
      imageBase64: widget.imageBase64,
    ));
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
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
              child: Image.memory(base64Decode(widget.imageBase64), fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _autoFill,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(_busy ? 'Looking at your photo' : 'Fill in with AI'),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'The photo is sent to an AI service to suggest a name, category and color.',
              style: TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          TextField(controller: _name, decoration: fieldDecoration('Name')),
          const SizedBox(height: 12),
          TextField(controller: _color, decoration: fieldDecoration('Color')),
          const Label('Category'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in categories)
                ChoiceChip(label: Text(c), selected: _category == c, onSelected: (_) => setState(() => _category = c)),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Save to closet')),
        ],
      ),
    );
  }
}

class OutfitPage extends StatefulWidget {
  const OutfitPage({super.key});

  @override
  State<OutfitPage> createState() => _OutfitPageState();
}

class _OutfitPageState extends State<OutfitPage> {
  final _rng = Random();
  List<ClosetItem> _outfit = [];

  ClosetItem? _pick(String category) {
    final list = closet.items.where((i) => i.category == category).toList();
    return list.isEmpty ? null : list[_rng.nextInt(list.length)];
  }

  void _generate() {
    final dress = _pick('Dresses');
    final base = (dress != null && _rng.nextBool())
        ? <ClosetItem?>[dress]
        : <ClosetItem?>[_pick('Tops'), _pick('Bottoms')];
    setState(() {
      _outfit = [...base, _pick('Jackets'), _pick('Shoes'), _pick('Accessories')]
          .whereType<ClosetItem>()
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: closet.items.isEmpty ? null : _generate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate outfit'),
            ),
          ),
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
        ],
      ),
    );
  }
}
