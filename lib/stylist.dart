import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'avatar.dart';
import 'main.dart';
import 'theme.dart';
import 'weather.dart';

const _skinNames = ['very light', 'light', 'medium', 'tan', 'brown', 'deep brown'];

/// A colour picked in the colour square, in words (by how light it is).
String _skinWord(Color c) {
  final l = c.computeLuminance();
  return l > 0.6 ? 'very light' : l > 0.45 ? 'light' : l > 0.3 ? 'medium' : l > 0.18 ? 'tan' : l > 0.09 ? 'brown' : 'deep brown';
}

/// The model's settings in words. Only what the user picked; no photos are used.
String looksText() {
  final s = avatarSettings;
  const avg = [106.0, 92.0, 88.0, 100.0, 48.0];
  String rel(int i) => (s.m[i] / avg[i] * 100).round().toString();
  final height = s.height < 0.9 ? 'shorter' : (s.height > 0.96 ? 'taller' : 'average height');
  return 'relative measurements (100 = average): shoulders ${rel(0)}, bust or chest ${rel(1)}, '
      'waist ${rel(2)}, hips ${rel(3)}, thighs ${rel(4)}; skin tone: ${s.skinCustom == null ? _skinNames[s.skin] : _skinWord(s.skinTone)}; height: $height';
}

List<Map<String, String>> _json(Iterable<ClosetItem> items) => [
      for (final i in items) {'id': i.id, 'name': i.name, 'category': i.category, 'color': i.color}
    ];

/// The closet pieces the AI stylist may choose from (without the samples when
/// [useSamples] is off).
List<ClosetItem> stylistChoices({required bool useSamples}) => [
      for (final i in closet.items)
        if (useSamples || !i.id.startsWith('sample-')) i
    ];

class StylistPanel extends StatefulWidget {
  final VoidCallback onChanged;
  const StylistPanel({super.key, required this.onChanged});

  @override
  State<StylistPanel> createState() => _StylistPanelState();
}

class _StylistPanelState extends State<StylistPanel> {
  final _note = TextEditingController();
  bool _busy = false;
  String? _reason;
  bool _useSamples = true; // let the AI pick from the sample pieces too
  String _accessories = 'auto'; // 'auto' (AI decides), 'include' (always some) or 'none'

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final v = p.getBool('ai_use_samples');
      final a = p.getString('ai_accessories');
      if (mounted) {
        setState(() {
          if (v != null) _useSamples = v;
          if (const ['auto', 'include', 'none'].contains(a)) _accessories = a!;
        });
      }
    });
  }

  Future<void> _setAccessories(String v) async {
    setState(() => _accessories = v);
    final p = await SharedPreferences.getInstance();
    await p.setString('ai_accessories', v);
  }

  /// What to tell the AI about accessories (empty when it decides).
  String _accessoryNote({required bool forMatches}) => switch (_accessories) {
        'include' => forMatches
            ? 'Include accessories in the suggestions.'
            : 'Include one to three accessories (hat, glasses, jewelry, scarf, belt, watch or bag).',
        'none' => forMatches ? 'Do not suggest accessories.' : 'No accessories.',
        _ => '',
      };

  Future<void> _setUseSamples(bool v) async {
    setState(() => _useSamples = v);
    final p = await SharedPreferences.getInstance();
    await p.setBool('ai_use_samples', v);
  }

  List<ClosetItem> get _choices => stylistChoices(useSamples: _useSamples);

  /// What to tell the AI: the accessories choice and your note. (Not the weather:
  /// the stylist dresses for your note, not the forecast.)
  String _noteWithWeather({bool forMatches = false}) => [_accessoryNote(forMatches: forMatches), _note.text.trim()]
          .where((t) => t.isNotEmpty)
          .join(' ');

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<Map<String, dynamic>?> _ask(Map<String, dynamic> body) async {
    if (!aiConfigured) {
      _toast('Add your AI address in main.dart first (see worker/SETUP.md).');
      return null;
    }
    setState(() => _busy = true);
    try {
      final res = await http
          .post(Uri.parse(aiEndpoint), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 45));
      if (res.statusCode != 200) throw Exception('${res.statusCode} ${res.body}');
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      if (mounted) _toast('AI problem: ${aiWhy(e)}');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _styleMe() async {
    final choices = [
      for (final i in _choices)
        if (_accessories != 'none' || i.category != 'Accessories') i
    ];
    if (choices.isEmpty) {
      _toast(closet.items.isEmpty
          ? 'Add some clothes to your closet first.'
          : 'You haven’t added any clothes of your own yet. Add some, or let the AI use the sample pieces.');
      return;
    }
    final data = await _ask({
      'mode': 'style',
      'looks': looksText(),
      'note': _noteWithWeather(),
      'items': _json(choices),
    });
    if (data == null || !mounted) return;
    final ids = (data['ids'] as List? ?? []).map((e) => e.toString()).toSet();
    final chosen = closet.items.where((i) => ids.contains(i.id)).toList();
    if (chosen.isEmpty) {
      // Keep the current outfit rather than undressing the model.
      _toast('The AI didn’t pick an outfit this time. Try again.');
      return;
    }
    for (final slot in outfitSlots) {
      avatarOutfit[slot] = chosen.where((i) => i.category == slot).firstOrNull;
    }
    avatarAccessories.clear();
    var picked = chosen.where((i) => i.category == 'Accessories').toList();
    if (_accessories == 'none') picked = [];
    // Asked for accessories but the AI left them out: add one or two that suit the day.
    final added = _accessories == 'include' && picked.isEmpty
        ? pickAccessoriesFor(choices, null, Random())
        : <ClosetItem>[];
    for (final a in [...picked, ...added]) {
      wearPiece('Accessories', a);
    }
    setState(() {
      final names = [...chosen.where((i) => i.category != 'Accessories'), ...picked].map((i) => i.name).join(', ');
      final extra = added.isEmpty ? '' : '\nAdded: ${added.map((i) => i.name).join(', ')}';
      _reason = '${data['reason'] ?? ''}${names.isEmpty ? '' : '\nOutfit: $names'}$extra'.trim();
    });
    widget.onChanged();
  }

  Future<void> _findMatches() async {
    final worn = avatarOutfit.values.whereType<ClosetItem>().toList();
    if (worn.isEmpty) {
      _toast('Put something on your model first.');
      return;
    }
    final wornIds = worn.map((i) => i.id).toSet();
    var data = await _ask({
      'mode': 'match',
      'looks': looksText(),
      'note': _noteWithWeather(forMatches: true),
      'worn': _json(worn),
      'items': _json(_choices.where((i) => !wornIds.contains(i.id) && (_accessories != 'none' || i.category != 'Accessories'))),
    });
    if (data == null || !mounted) return;
    if (_accessories == 'none') {
      // Leave out any accessory ideas the AI still suggests.
      const words = ['accessor', 'hat', 'cap', 'glasses', 'necklace', 'jewel', 'scarf', 'belt', 'watch', 'bag', 'earring', 'bracelet'];
      final buy = (data['to_buy'] as List? ?? []).where((t) {
        final text = '${(t as Map)['category']} ${t['item']}'.toLowerCase();
        return !words.any(text.contains);
      }).toList();
      data = {...data, 'to_buy': buy};
    }
    _showMatches(data);
  }

  void _showMatches(Map<String, dynamic> data) {
    final ids = (data['closet_ids'] as List? ?? []).map((e) => e.toString()).toSet();
    final mine = closet.items.where((i) => ids.contains(i.id)).toList();
    final buy = (data['to_buy'] as List? ?? []).cast<dynamic>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          shrinkWrap: true,
          children: [
            if (mine.isNotEmpty) ...[
              Text('From your closet (tap to wear)', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final it in mine)
                      GestureDetector(
                        onTap: () {
                          if (outfitSlots.contains(it.category) || it.category == 'Accessories') {
                            wearPiece(it.category, it);
                            widget.onChanged();
                          }
                          Navigator.pop(sheet);
                        },
                        child: Container(
                          width: 74,
                          margin: const EdgeInsets.only(right: 8),
                          child: Column(children: [
                            Expanded(child: Image.memory(base64Decode(it.imageBase64), fit: BoxFit.cover)),
                            Text(it.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (buy.isNotEmpty) ...[
              Text('Worth looking for', style: Theme.of(context).textTheme.titleSmall),
              for (final t in buy)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t['item'].toString()),
                  subtitle: Text(t['why'].toString()),
                  trailing: IconButton(
                    tooltip: 'Search online',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => launchUrl(
                      Uri.https('www.google.com', '/search', {'tbm': 'shop', 'q': t['search'].toString()}),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ),
            ],
            if (mine.isEmpty && buy.isEmpty) const Text('No suggestions this time. Try again.'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A Material (not a coloured box) so the switch's tap ripple shows on the card.
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AI stylist', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Occasion or what you want (optional)',
                  hintText: 'e.g. dinner date, or shoes and jewelry',
                  filled: true,
                  fillColor: paper,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _styleMe,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Style me'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _findMatches,
                  icon: const Icon(Icons.search),
                  label: const Text('Find matching pieces'),
                ),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Use the sample pieces'),
                subtitle: Text(_useSamples
                    ? 'The AI can pick samples as well as your own clothes.'
                    : 'The AI only picks from clothes you added.'),
                value: _useSamples,
                onChanged: _setUseSamples,
              ),
              const SizedBox(height: 4),
              Text('Accessories', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'auto', label: Text('AI decides')),
                    ButtonSegment(value: 'include', label: Text('Wear some')),
                    ButtonSegment(value: 'none', label: Text('None')),
                  ],
                  selected: {_accessories},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => _setAccessories(v.first),
                ),
              ),
              if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
              if (_reason != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_reason!)),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Sends your model settings and item names (no photos) to an AI service.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
