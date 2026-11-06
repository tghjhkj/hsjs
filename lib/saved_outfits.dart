import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'avatar.dart';
import 'main.dart';
import 'theme.dart';

/// An outfit you saved: a name and the pieces in it (by id).
class SavedOutfit {
  final String id;
  String name;
  final List<String> pieceIds;
  final DateTime created;
  SavedOutfit(this.id, this.name, this.pieceIds, this.created);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'pieces': pieceIds, 'created': created.toIso8601String()};

  factory SavedOutfit.fromJson(Map<String, dynamic> j) => SavedOutfit(
        j['id'] as String,
        j['name'] as String? ?? 'Outfit',
        [for (final p in (j['pieces'] as List? ?? [])) p.toString()],
        DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime.now(),
      );

  /// The pieces still in the closet (removed pieces are skipped).
  List<ClosetItem> get pieces => [
        for (final id in pieceIds)
          if (closet.items.where((i) => i.id == id).firstOrNull case final piece?) piece
      ];
}

/// Saved outfits, kept on the phone.
class SavedOutfitsStore extends ChangeNotifier {
  final List<SavedOutfit> outfits = [];
  static const _key = 'saved_outfits';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    outfits
      ..clear()
      ..addAll([for (final e in jsonDecode(raw) as List) SavedOutfit.fromJson(Map<String, dynamic>.from(e as Map))]);
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final o in outfits) o.toJson()]));
  }

  /// The saved outfit with exactly these pieces, if there is one.
  SavedOutfit? find(List<ClosetItem> pieces) {
    final ids = {for (final p in pieces) p.id};
    for (final o in outfits) {
      final other = o.pieceIds.toSet();
      if (other.length == ids.length && other.containsAll(ids)) return o;
    }
    return null;
  }

  Future<void> add(String name, List<ClosetItem> pieces) async {
    outfits.insert(0, SavedOutfit(DateTime.now().microsecondsSinceEpoch.toString(), name, [for (final p in pieces) p.id], DateTime.now()));
    notifyListeners();
    await _save();
  }

  Future<void> rename(SavedOutfit o, String name) async {
    o.name = name;
    notifyListeners();
    await _save();
  }

  Future<void> remove(SavedOutfit o) async {
    outfits.remove(o);
    notifyListeners();
    await _save();
  }
}

final savedOutfits = SavedOutfitsStore();

/// What the model is wearing now, as a list (a dress replaces the top and bottoms).
List<ClosetItem> currentModelOutfit() {
  final hasDress = avatarOutfit['Dresses'] != null;
  return [
    for (final slot in outfitSlots)
      if (avatarOutfit[slot] != null && !(hasDress && (slot == 'Tops' || slot == 'Bottoms'))) avatarOutfit[slot]!
  ];
}

/// Dresses the model in [pieces] (anything that isn't worn on the model, like
/// accessories, is skipped).
void putOnModel(List<ClosetItem> pieces) {
  for (final slot in outfitSlots) {
    avatarOutfit[slot] = null;
  }
  for (final p in pieces) {
    if (outfitSlots.contains(p.category)) wearPiece(p.category, p);
  }
}

/// A name to start with: the main pieces, for example "Breton tee & Straight jeans".
String _suggestedName(List<ClosetItem> pieces) {
  final main = [
    for (final cat in ['Dresses', 'Tops', 'Bottoms'])
      ...pieces.where((p) => p.category == cat).map((p) => p.name),
  ];
  final name = (main.isEmpty ? pieces.map((p) => p.name) : main).take(2).join(' & ');
  return name.isEmpty ? 'Outfit ${savedOutfits.outfits.length + 1}' : name;
}

/// Asks for a name and saves the outfit. Tells you if it was already saved.
Future<void> saveOutfit(BuildContext context, List<ClosetItem> pieces) async {
  final messenger = ScaffoldMessenger.of(context);
  // A new message replaces the one showing, instead of waiting behind it.
  messenger.hideCurrentSnackBar();
  if (pieces.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('There’s nothing to save yet. Put some pieces together first.')));
    return;
  }
  final already = savedOutfits.find(pieces);
  if (already != null) {
    messenger.showSnackBar(SnackBar(content: Text('This outfit is already saved as “${already.name}”.')));
    return;
  }
  final name = await _askName(context, 'Save outfit', _suggestedName(pieces), 'Save');
  if (name == null) return;
  await savedOutfits.add(name, pieces);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text('Saved “$name”. Find it under Saved outfits on the Outfits tab.')));
}

Future<String?> _askName(BuildContext context, String title, String start, String action) {
  final field = TextEditingController(text: start);
  return showDialog<String>(
    context: context,
    builder: (dialog) {
      void done() {
        final t = field.text.trim();
        Navigator.pop(dialog, t.isEmpty ? start : t);
      }

      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: field,
          autofocus: true,
          maxLength: 40,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => done(),
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: done, child: Text(action)),
        ],
      );
    },
  );
}

/// The list of saved outfits, for the Outfits tab.
class SavedOutfitsSection extends StatelessWidget {
  /// Called after an outfit is put on the model (to show the Model tab).
  final VoidCallback? onWear;
  const SavedOutfitsSection({super.key, this.onWear});

  void _open(BuildContext context, SavedOutfit o) {
    final pieces = o.pieces;
    showModalBottomSheet(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(o.name, style: Theme.of(context).textTheme.titleMedium), subtitle: Text(_when(o.created))),
          if (pieces.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Put it on the model'),
              onTap: () {
                Navigator.pop(sheet);
                putOnModel(pieces);
                onWear?.call();
              },
            ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () async {
              Navigator.pop(sheet);
              final name = await _askName(context, 'Rename outfit', o.name, 'Rename');
              if (name != null) await savedOutfits.rename(o, name);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
            title: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () {
              Navigator.pop(sheet);
              savedOutfits.remove(o);
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Deleted “${o.name}”.'),
                action: SnackBarAction(label: 'Undo', onPressed: () => savedOutfits.add(o.name, pieces)),
              ));
            },
          ),
        ]),
      ),
    );
  }

  static String _when(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return 'Saved ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([savedOutfits, closet]),
      builder: (context, _) {
        final list = savedOutfits.outfits;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 8),
            child: Text('Saved outfits${list.isEmpty ? '' : ' (${list.length})'}', style: t.titleMedium),
          ),
          if (list.isEmpty)
            const Text('Outfits you save here or on the Model tab show up in this list.')
          else
            for (final o in list)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                color: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _open(context, o),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(o.name, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const Icon(Icons.more_horiz, size: 20),
                      ]),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 64,
                        child: o.pieces.isEmpty
                            ? const Align(alignment: Alignment.centerLeft, child: Text('These pieces are no longer in your closet.'))
                            : ListView(scrollDirection: Axis.horizontal, children: [
                                for (final p in o.pieces)
                                  Container(
                                    width: 52,
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: paper,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Image.memory(base64Decode(p.imageBase64), fit: BoxFit.contain, gaplessPlayback: true),
                                  ),
                              ]),
                      ),
                    ]),
                  ),
                ),
              ),
        ]);
      },
    );
  }
}
