import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'avatar.dart';
import 'main.dart';
import 'theme.dart';

const _skinNames = ['very light', 'light', 'medium', 'tan', 'brown', 'deep brown'];

/// The model's settings in words. Only what the user picked; no photos are used.
String looksText() {
  final s = avatarSettings;
  final build = s.build < 0.95 ? 'slim' : (s.build > 1.1 ? 'fuller' : 'average');
  final height = s.height < 0.9 ? 'shorter' : (s.height > 0.96 ? 'taller' : 'average height');
  return 'body shape: ${s.body}; skin tone: ${_skinNames[s.skin]}; build: $build; height: $height';
}

List<Map<String, String>> _json(Iterable<ClosetItem> items) => [
      for (final i in items) {'id': i.id, 'name': i.name, 'category': i.category, 'color': i.color}
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

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<Map<String, dynamic>?> _ask(Map<String, dynamic> body) async {
    if (!aiConfigured) {
      _toast('Add your AI address in main.dart first (see worker/SETUP.md).');
      return null;
    }
    setState(() => _busy = true);
    try {
      final res = await http
          .post(Uri.parse(aiEndpoint),
              headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 45));
      if (res.statusCode != 200) throw Exception('status ${res.statusCode}');
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      if (mounted) _toast('Could not reach the AI. Try again.');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _styleMe() async {
    if (closet.items.isEmpty) {
      _toast('Add some clothes to your closet first.');
      return;
    }
    final data = await _ask({
      'mode': 'style',
      'looks': looksText(),
      'note': _note.text.trim(),
      'items': _json(closet.items),
    });
    if (data == null || !mounted) return;
    final ids = (data['ids'] as List? ?? []).map((e) => e.toString()).toSet();
    final chosen = closet.items.where((i) => ids.contains(i.id)).toList();
    for (final slot in outfitSlots) {
      avatarOutfit[slot] = chosen.where((i) => i.category == slot).firstOrNull;
    }
    setState(() {
      final names = chosen.map((i) => i.name).join(', ');
      _reason = '${data['reason'] ?? ''}${names.isEmpty ? '' : '\nOutfit: $names'}'.trim();
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
    final data = await _ask({
      'mode': 'match',
      'looks': looksText(),
      'note': _note.text.trim(),
      'worn': _json(worn),
      'items': _json(closet.items.where((i) => !wornIds.contains(i.id))),
    });
    if (data == null || !mounted) return;
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
                          if (outfitSlots.contains(it.category)) {
                            avatarOutfit[it.category] = it;
                            widget.onChanged();
                          }
                          Navigator.pop(sheet);
                        },
                        child: Container(
                          width: 74,
                          margin: const EdgeInsets.only(right: 8),
                          child: Column(children: [
                            Expanded(child: Image.memory(base64Decode(it.imageBase64), fit: BoxFit.cover)),
                            Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
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
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
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
    );
  }
}
