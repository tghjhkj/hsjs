import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Palette: cool paper, ink, aubergine, lilac tint, one gold accent.
const paper = Color(0xFFF6F4F9);
const ink = Color(0xFF1D1A24);
const aubergine = Color(0xFF5B2C83);
const lilac = Color(0xFFE7DDF3);
const gold = Color(0xFFE8B04A);
const _hairline = Color(0x1F1D1A24);

ThemeData museTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: aubergine).copyWith(
    primary: aubergine,
    onPrimary: Colors.white,
    surface: paper,
    onSurface: ink,
    secondaryContainer: lilac,
    onSecondaryContainer: aubergine,
    tertiary: gold,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final body = GoogleFonts.dmSansTextTheme(base.textTheme).apply(bodyColor: ink, displayColor: ink);
  TextStyle serif(TextStyle? s, {double? size}) => GoogleFonts.fraunces(
      textStyle: s, fontSize: size, fontWeight: FontWeight.w600, color: ink);

  return base.copyWith(
    scaffoldBackgroundColor: paper,
    textTheme: body.copyWith(
      headlineSmall: serif(body.headlineSmall),
      titleLarge: serif(body.titleLarge),
      titleMedium: serif(body.titleMedium, size: 18),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.fraunces(fontSize: 28, fontWeight: FontWeight.w600, color: ink),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
      indicatorColor: lilac,
      elevation: 0,
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: lilac,
      shape: StadiumBorder(side: BorderSide(color: _hairline)),
      showCheckmark: false,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: aubergine,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: StadiumBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        side: const BorderSide(color: _hairline),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? lilac : Colors.white),
        foregroundColor: WidgetStateProperty.all(ink),
        side: WidgetStateProperty.all(const BorderSide(color: _hairline)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
  );
}

InputDecoration fieldDecoration(String label) => InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide.none,
      ),
    );

/// A small heading above a group of controls.
class Label extends StatelessWidget {
  final String text;
  const Label(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: lilac, shape: BoxShape.circle),
              child: Icon(icon, size: 32, color: aubergine),
            ),
            const SizedBox(height: 16),
            Text(title, style: t.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, style: t.bodyMedium, textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
