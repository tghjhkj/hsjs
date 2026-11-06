import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';
import 'theme.dart';

// Weather from Open-Meteo (free, no key needed). The city is typed once and saved.

/// Today's weather for the saved city.
class WeatherToday {
  final String place;
  final double now, high, low;
  final int code, rainChance;
  const WeatherToday(this.place, this.now, this.high, this.low, this.code, this.rainChance);

  static bool _rainCode(int c) => (c >= 51 && c <= 67) || (c >= 80 && c <= 82) || c >= 95;

  bool get rainy => rainChance >= 50 || _rainCode(code);

  /// How warm the day feels, leaning toward the afternoon high.
  double get feel => high * 0.6 + low * 0.4;

  /// hot, warm, mild, cool or cold.
  String get band => feel >= 26
      ? 'hot'
      : feel >= 20
          ? 'warm'
          : feel >= 14
              ? 'mild'
              : feel >= 8
                  ? 'cool'
                  : 'cold';

  String get label {
    final c = code;
    if (c == 0) return 'Clear';
    if (c <= 2) return 'Partly cloudy';
    if (c == 3) return 'Cloudy';
    if (c == 45 || c == 48) return 'Fog';
    if (c >= 51 && c <= 57) return 'Drizzle';
    if (c >= 61 && c <= 67) return 'Rain';
    if (c >= 71 && c <= 77) return 'Snow';
    if (c >= 80 && c <= 82) return 'Showers';
    if (c == 85 || c == 86) return 'Snow showers';
    if (c >= 95) return 'Thunderstorms';
    return 'Mixed';
  }

  IconData get icon {
    if (code >= 95) return Icons.thunderstorm_outlined;
    if (code >= 71 && code <= 86 && !(code >= 80 && code <= 82)) return Icons.ac_unit;
    if (rainy) return Icons.umbrella_outlined;
    if (code == 0) return Icons.wb_sunny_outlined;
    if (code <= 2) return Icons.wb_cloudy_outlined;
    return Icons.cloud_outlined;
  }

  String get summary => '$place · ${now.round()}° · $label';
  String get range => 'Today ${low.round()}° to ${high.round()}°${rainChance > 0 ? ', $rainChance% chance of rain' : ''}';

  /// A short line for the AI stylist.
  String get forStylist =>
      'Weather today: ${low.round()} to ${high.round()} C, ${label.toLowerCase()}${rainy ? ', rain likely' : ''}.';
}

/// The saved city and its weather.
class WeatherStore extends ChangeNotifier {
  String? city; // as the place was found, e.g. "Jakarta, Indonesia"
  double? lat, lon;
  WeatherToday? today;
  DateTime? _fetched;
  bool loading = false;
  String? error;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    city = p.getString('weather_city');
    lat = p.getDouble('weather_lat');
    lon = p.getDouble('weather_lon');
    if (city != null) refresh(); // in the background
  }

  /// Looks up the city and saves it. Returns a message if it can't be found.
  Future<String?> setCity(String name) async {
    final q = name.trim();
    if (q.isEmpty) return 'Type a city first.';
    loading = true;
    error = null;
    notifyListeners();
    try {
      final res = await http
          .get(Uri.https('geocoding-api.open-meteo.com', '/v1/search', {'name': q, 'count': '1', 'language': 'en'}))
          .timeout(const Duration(seconds: 12));
      final list = (jsonDecode(res.body)['results'] as List?) ?? [];
      if (res.statusCode != 200 || list.isEmpty) {
        loading = false;
        notifyListeners();
        return 'Couldn’t find “$q”. Check the spelling, or add the country (for example “Paris, France”).';
      }
      final r = list.first as Map<String, dynamic>;
      city = [r['name'], r['country']].whereType<String>().join(', ');
      lat = (r['latitude'] as num).toDouble();
      lon = (r['longitude'] as num).toDouble();
      final p = await SharedPreferences.getInstance();
      await p.setString('weather_city', city!);
      await p.setDouble('weather_lat', lat!);
      await p.setDouble('weather_lon', lon!);
      today = null;
      _fetched = null;
      await refresh();
      return null;
    } catch (_) {
      loading = false;
      notifyListeners();
      return 'Couldn’t look up the city right now. Check your connection and try again.';
    }
  }

  /// Gets today's weather (at most once an hour unless [force]).
  Future<void> refresh({bool force = false}) async {
    if (lat == null || lon == null) return;
    if (!force && today != null && _fetched != null && DateTime.now().difference(_fetched!).inMinutes < 60) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final res = await http
          .get(Uri.https('api.open-meteo.com', '/v1/forecast', {
            'latitude': '$lat',
            'longitude': '$lon',
            'current': 'temperature_2m,weather_code',
            'daily': 'temperature_2m_max,temperature_2m_min,precipitation_probability_max',
            'timezone': 'auto',
            'forecast_days': '1',
          }))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) throw Exception(res.statusCode);
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final cur = j['current'] as Map<String, dynamic>;
      final day = j['daily'] as Map<String, dynamic>;
      double first(String k) => ((day[k] as List).first as num?)?.toDouble() ?? 0;
      today = WeatherToday(
        (city ?? '').split(',').first,
        (cur['temperature_2m'] as num).toDouble(),
        first('temperature_2m_max'),
        first('temperature_2m_min'),
        (cur['weather_code'] as num).toInt(),
        first('precipitation_probability_max').round(),
      );
      _fetched = DateTime.now();
    } catch (_) {
      error = 'Couldn’t get the weather right now, so outfits are picked without it.';
    }
    loading = false;
    notifyListeners();
  }
}

final weather = WeatherStore();

/// How warm a piece is, from 0 (very light) to 3 (warm), going by its shape and name.
double warmth(ClosetItem i) {
  final s = i.spec ?? const {};
  final n = i.name.toLowerCase();
  bool named(List<String> words) => words.any(n.contains);
  switch (i.category) {
    case 'Tops':
      if (named(['sweater', 'hoodie', 'knit', 'fleece', 'wool', 'jumper', 'cardigan', 'turtleneck', 'sweatshirt'])) return 3;
      return switch (s['sleeves']) { 'none' => 0, 'long' => 2, _ => 1 };
    case 'Dresses':
      final sleeves = s['sleeves'] == 'long' ? 1.0 : (s['sleeves'] == 'short' ? 0.4 : 0.0);
      final length = s['length'] == 'long' ? 1.0 : (s['length'] == 'short' ? 0.0 : 0.5);
      return sleeves + length;
    case 'Bottoms':
      final type = s['bottomType'];
      if (type == 'shorts' || named(['shorts'])) return 0;
      if (type == 'skirt' || named(['skirt'])) {
        return s['length'] == 'long' ? 1.5 : (s['length'] == 'short' ? 0 : 1);
      }
      return 2;
    case 'Jackets':
      return named(['coat', 'puffer', 'parka', 'wool', 'down', 'fleece']) ? 3 : 2;
    case 'Shoes':
      if (s['style'] == 'boots' || named(['boot'])) return 2.5;
      if (s['style'] == 'low' || named(['sandal', 'flip', 'flat', 'slide'])) return 0.3;
      return 1;
  }
  return 1;
}

const _target = {'hot': 0.0, 'warm': 0.8, 'mild': 1.5, 'cool': 2.2, 'cold': 3.0};
const _dressChance = {'hot': 0.6, 'warm': 0.5, 'mild': 0.35, 'cool': 0.2, 'cold': 0.1};

/// Picks an outfit from [items]: random, or suited to [w] when there is weather.
List<ClosetItem> pickOutfit(List<ClosetItem> items, WeatherToday? w, Random rng) {
  ClosetItem? pick(String category, [double? target]) {
    final list = items.where((i) => i.category == category).toList();
    if (list.isEmpty) return null;
    if (target == null) return list[rng.nextInt(list.length)];
    // The pieces closest to the weather, then one of those at random.
    final best = list.map((i) => (warmth(i) - target).abs()).reduce(min);
    final close = list.where((i) => (warmth(i) - target).abs() <= best + 0.6).toList();
    return close[rng.nextInt(close.length)];
  }

  if (w == null) {
    final dress = pick('Dresses');
    final base = (dress != null && rng.nextBool()) ? [dress] : [pick('Tops'), pick('Bottoms')];
    return [...base, pick('Jackets'), pick('Shoes'), pick('Accessories')].whereType<ClosetItem>().toList();
  }
  final t = _target[w.band]!;
  final dress = pick('Dresses', t);
  final base = (dress != null && rng.nextDouble() < _dressChance[w.band]!) ? [dress] : [pick('Tops', t), pick('Bottoms', t)];
  final wantJacket = w.rainy || w.band == 'cool' || w.band == 'cold' || (w.band == 'mild' && rng.nextBool());
  final jacket = wantJacket ? pick('Jackets', t) : null;
  final shoes = pick('Shoes', w.rainy ? max(t, 2.5) : t);
  return [...base, jacket, shoes, pick('Accessories')].whereType<ClosetItem>().toList();
}

/// One line saying why this outfit suits the weather.
String outfitReason(WeatherToday w, List<ClosetItem> outfit) {
  final hasJacket = outfit.any((i) => i.category == 'Jackets');
  final boots = outfit.any((i) => i.category == 'Shoes' && warmth(i) >= 2.5);
  final what = switch (w.band) {
    'hot' => 'light pieces to stay cool',
    'warm' => 'short sleeves and light layers',
    'mild' => hasJacket ? 'a light layer you can take off' : 'easy layers',
    'cool' => 'long sleeves${hasJacket ? ' and a jacket' : ''}',
    _ => 'warm layers${hasJacket ? ' and a jacket' : ''}',
  };
  final rain = w.rainy ? (boots ? ', with boots for the rain' : (hasJacket ? ', with a jacket for the rain' : '')) : '';
  return 'Picked for ${w.feel.round()}° and ${w.label.toLowerCase()}: $what$rain.';
}

/// The weather card on the Outfits tab: type a city once, then today's weather.
class WeatherCard extends StatefulWidget {
  const WeatherCard({super.key});

  @override
  State<WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends State<WeatherCard> {
  final _city = TextEditingController();
  bool _editing = false;
  String? _message;

  Future<void> _save() async {
    final msg = await weather.setCity(_city.text);
    if (!mounted) return;
    setState(() {
      _message = msg;
      if (msg == null) _editing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: weather,
      builder: (context, _) {
        final w = weather.today;
        final asking = _editing || weather.city == null;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: asking
              ? Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Outfits for the weather', style: t.titleMedium),
                      const SizedBox(height: 4),
                      const Text('Type your city once, and generated outfits will suit today’s weather.'),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _city,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _save(),
                            decoration: fieldDecoration('City').copyWith(fillColor: paper),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(onPressed: weather.loading ? null : _save, child: const Text('Save')),
                      ]),
                      if (weather.loading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
                      if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!)),
                      if (_editing)
                        TextButton(onPressed: () => setState(() => _editing = false), child: const Text('Cancel')),
                    ],
                  ),
                )
              : Row(children: [
                  Icon(w?.icon ?? Icons.cloud_outlined, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(w?.summary ?? weather.city!.split(',').first, style: t.titleSmall),
                      Text(
                        weather.loading
                            ? 'Getting today’s weather…'
                            : (w?.range ?? weather.error ?? ''),
                        style: t.bodySmall,
                      ),
                    ]),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _editing = true;
                      _message = null;
                      _city.text = weather.city ?? '';
                    }),
                    child: const Text('Change'),
                  ),
                ]),
        );
      },
    );
  }
}
