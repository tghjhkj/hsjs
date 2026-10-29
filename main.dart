import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const categories = ['Tops', 'Bottoms', 'Dresses', 'Jackets', 'Shoes', 'Accessories'];

class ClosetItem {
  final String id, name, category, color, imagePath;

  ClosetItem({
    required this.id,
    required this.name,
    required this.category,
    required this.color,
    required this.imagePath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'color': color,
        'imagePath': imagePath,
      };

  factory ClosetItem.fromJson(Map<String, dynamic> j) => ClosetItem(
        id: j['id'],
        name: j['name'],
        category: j['category'],
        color: j['color'],
        imagePath: j['imagePath'],
      );
}

/// Holds the closet and saves it on the phone.
class ClosetStore extends ChangeNotifier {
  final List<ClosetItem> items = [];
  static const _key = 'closet';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    items
      ..clear()
      ..addAll((jsonDecode(raw) as List)
          .map((e) => ClosetItem.fromJson(e as Map<String, dynamic>)));
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
    try {
      await File(item.imagePath).delete();
    } catch (_) {}
  }
}

final closet = ClosetStore();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await closet.load();
  runApp(const MuseApp());
}

class MuseApp extends StatelessWidget {
  const MuseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Muse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
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
      appBar: AppBar(title: Text(_tab == 0 ? 'My Closet' : 'Outfits')),
      body: _tab == 0 ? const ClosetPage() : const OutfitPage(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.checkroom), label: 'Closet'),
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'Outfits'),
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
    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Image.file(
                File(item.imagePath),
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => const Icon(Icons.broken_image),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
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
  Future<void> _pick(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1024);
    if (picked == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final saved = await File(picked.path).copy('${dir.path}/$id.jpg');
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddItemPage(id: id, imagePath: saved.path)),
    );
  }

  void _chooseSource() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pick(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showItem(ClosetItem item) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item.name),
        content: Text('${item.category} · ${item.color}'),
        actions: [
          TextButton(
            onPressed: () {
              closet.remove(item);
              Navigator.pop(dialogContext);
            },
            child: const Text('Delete'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _chooseSource,
        icon: const Icon(Icons.add_a_photo),
        label: const Text('Add item'),
      ),
      body: ListenableBuilder(
        listenable: closet,
        builder: (context, _) {
          if (closet.items.isEmpty) {
            return const Center(child: Text('Your closet is empty.\nTap "Add item" to start.', textAlign: TextAlign.center));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.75,
            ),
            itemCount: closet.items.length,
            itemBuilder: (context, i) {
              final item = closet.items[i];
              return ItemTile(item, onTap: () => _showItem(item));
            },
          );
        },
      ),
    );
  }
}

class AddItemPage extends StatefulWidget {
  final String id, imagePath;
  const AddItemPage({super.key, required this.id, required this.imagePath});

  @override
  State<AddItemPage> createState() => _AddItemPageState();
}

class _AddItemPageState extends State<AddItemPage> {
  final _name = TextEditingController();
  final _color = TextEditingController();
  String _category = categories.first;

  Future<void> _save() async {
    await closet.add(ClosetItem(
      id: widget.id,
      name: _name.text.trim().isEmpty ? 'Untitled' : _name.text.trim(),
      category: _category,
      color: _color.text.trim(),
      imagePath: widget.imagePath,
    ));
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New item')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(height: 280, child: Image.file(File(widget.imagePath), fit: BoxFit.contain)),
          const SizedBox(height: 16),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _color, decoration: const InputDecoration(labelText: 'Color', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          DropdownButton<String>(
            isExpanded: true,
            value: _category,
            items: [for (final c in categories) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: 16),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          FilledButton.icon(
            onPressed: closet.items.isEmpty ? null : _generate,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generate outfit'),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _outfit.isEmpty
                ? const Center(child: Text('Add items to your closet, then generate an outfit.', textAlign: TextAlign.center))
                : GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.8,
                    children: [for (final i in _outfit) ItemTile(i)],
                  ),
          ),
        ],
      ),
    );
  }
}
