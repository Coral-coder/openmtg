import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How a theme draws its frames, buttons and panels.
enum ChromeStyle { lcars, classic, crystal, ink, comic }

/// What sits behind the table.
enum Backdrop { starfield, felt, crystal, paper, halftone }

/// The synthesized sound set: a waveform and a base pitch.
class SoundStyle {
  const SoundStyle({this.wave = 'sine', this.base = 880, this.decay = 0.12});
  final String wave; // sine | square | triangle | bell
  final double base;
  final double decay;
}

/// A visual theme for a set or universe (docs/PLAN.md §4): palette, type, chrome, table
/// backdrop and sounds. Each is drawn from scratch and inspired by its setting; no logos, fonts
/// or trade dress are copied.
class GameTheme {
  const GameTheme({
    required this.id,
    required this.name,
    required this.blurb,
    required this.chrome,
    required this.backdrop,
    required this.bg,
    required this.surface,
    required this.panel,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accent2,
    required this.accent3,
    required this.danger,
    required this.ok,
    required this.highlight,
    required this.buttonText,
    required this.decor,
    required this.mana,
    this.brightness = Brightness.dark,
    this.font = 'sans-serif',
    this.titleFont,
    this.fallback = const ['Roboto', 'Arial'],
    this.uppercase = false,
    this.letterSpacing = 0,
    this.radius = 10,
    this.sound = const SoundStyle(),
    this.sets = const [],
    this.universes = const [],
  });

  final String id, name, blurb;
  final ChromeStyle chrome;
  final Backdrop backdrop;
  final Brightness brightness;
  final Color bg, surface, panel, text, muted, accent, accent2, accent3, danger, ok, highlight, buttonText;

  /// Decorative colors (LCARS blocks, crystal glints, element accents).
  final List<Color> decor;

  /// Pip colors for W U B R G C.
  final Map<String, Color> mana;
  final String font;

  /// Font for titles, headings and buttons (defaults to [font]).
  final String? titleFont;
  final List<String> fallback;
  final bool uppercase;
  final double letterSpacing;
  final double radius;
  final SoundStyle sound;

  /// Set codes whose decks pick this theme, and universe names for the picker.
  final List<String> sets;
  final List<String> universes;

  Color manaColor(String s) => mana[s] ?? muted;

  String label(String s) => uppercase ? s.toUpperCase() : s;

  TextStyle style(double size, {FontWeight weight = FontWeight.w600, Color? color, double? height}) =>
      TextStyle(fontSize: size, fontWeight: weight, color: color ?? text, fontFamily: bundledFont(font), fontFamilyFallback: fallback, letterSpacing: letterSpacing, height: height ?? 1.15);

  /// A style in the title font (headings, buttons).
  TextStyle display(double size, {FontWeight weight = FontWeight.w700, Color? color}) =>
      TextStyle(fontSize: size, fontWeight: weight, color: color ?? text, fontFamily: bundledFont(titleFont ?? font), fontFamilyFallback: fallback, letterSpacing: titleFont == 'Bangers' ? 1.0 : letterSpacing, height: 1.12);

  TextStyle get title => display(26, weight: FontWeight.w800, color: accent);
  TextStyle get heading => display(18, weight: FontWeight.w700);
  TextStyle get body => style(15, weight: FontWeight.w500);
  TextStyle get small => style(12, weight: FontWeight.w500, color: muted);

  ThemeData material() => ThemeData(
        brightness: brightness,
        scaffoldBackgroundColor: bg,
        colorScheme: brightness == Brightness.dark
            ? ColorScheme.dark(primary: accent, secondary: accent2, surface: surface, error: danger, onPrimary: buttonText, onSurface: text)
            : ColorScheme.light(primary: accent, secondary: accent2, surface: surface, error: danger, onPrimary: buttonText, onSurface: text),
        useMaterial3: true,
        fontFamily: bundledFont(font),
        fontFamilyFallback: fallback,
        textTheme: TextTheme(bodyMedium: style(14, weight: FontWeight.w500), bodyLarge: style(16, weight: FontWeight.w500), titleLarge: style(22, weight: FontWeight.w700)),
        appBarTheme: AppBarTheme(backgroundColor: bg, foregroundColor: accent),
        dialogTheme: DialogThemeData(backgroundColor: panel, titleTextStyle: heading, contentTextStyle: body),
        bottomSheetTheme: BottomSheetThemeData(backgroundColor: panel),
        snackBarTheme: SnackBarThemeData(backgroundColor: accent, contentTextStyle: style(14, color: buttonText)),
        switchTheme: SwitchThemeData(thumbColor: WidgetStatePropertyAll(accent)),
        sliderTheme: SliderThemeData(activeTrackColor: accent, thumbColor: accent),
        dividerColor: muted.withValues(alpha: 0.3),
      );

  static GameTheme of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ThemeScope>()?.theme ?? Themes.classic;
}

class ThemeScope extends InheritedWidget {
  const ThemeScope({super.key, required this.theme, required super.child});
  final GameTheme theme;
  @override
  bool updateShouldNotify(ThemeScope old) => old.theme.id != theme.id;
}

/// The themes. Star Trek ports MagicTrek's LCARS look; the Universes Beyond themes are inspired
/// by their worlds and drawn from scratch.
class Themes {
  static const lcars = GameTheme(
    id: 'starship',
    name: 'Starship console',
    blurb: 'Rounded elbows, colored blocks and a starfield, for the final frontier.',
    chrome: ChromeStyle.lcars,
    backdrop: Backdrop.starfield,
    bg: Colors.black,
    surface: Color(0xFF111118),
    panel: Color(0xFF15151F),
    text: Color(0xFFFFCC99),
    muted: Color(0xFF8888AA),
    accent: Color(0xFFFF9900),
    accent2: Color(0xFFCC99CC),
    accent3: Color(0xFF9999FF),
    danger: Color(0xFFCC6666),
    ok: Color(0xFF66CC99),
    highlight: Color(0xFFFFCC66),
    buttonText: Colors.black,
    decor: [Color(0xFFFF9900), Color(0xFFFFCC99), Color(0xFFCC99CC), Color(0xFF9999FF), Color(0xFFFF9966), Color(0xFFFFCC66), Color(0xFF6688CC), Color(0xFF9966CC)],
    mana: {'W': Color(0xFFFFCC99), 'U': Color(0xFF9999FF), 'B': Color(0xFF9966CC), 'R': Color(0xFFFF9966), 'G': Color(0xFF66CC99), 'C': Color(0xFF888899)},
    font: 'Antonio',
    fallback: ['Arial Narrow', 'Roboto'],
    uppercase: true,
    letterSpacing: 0.6,
    radius: 22,
    sound: SoundStyle(wave: 'sine', base: 1320, decay: 0.08),
    sets: ['trk', 'trc', 'ttrk', 'strk'],
    universes: ['Star Trek'],
  );

  static const classic = GameTheme(
    id: 'classic',
    name: 'Classic',
    blurb: 'Dark wood, parchment and brass, with the five colors of mana.',
    chrome: ChromeStyle.classic,
    backdrop: Backdrop.felt,
    bg: Color(0xFF16110D),
    surface: Color(0xFF241B14),
    panel: Color(0xFF2C2219),
    text: Color(0xFFF1E6D2),
    muted: Color(0xFFB5A58C),
    accent: Color(0xFFD9A441),
    accent2: Color(0xFF8FB3D9),
    accent3: Color(0xFFB87D4B),
    danger: Color(0xFFD25A4A),
    ok: Color(0xFF7FB069),
    highlight: Color(0xFFFFD36B),
    buttonText: Color(0xFF1B140E),
    decor: [Color(0xFFD9A441), Color(0xFF8C6239), Color(0xFF5E4027)],
    mana: {'W': Color(0xFFF8F1D8), 'U': Color(0xFF6FA8DC), 'B': Color(0xFF8E7F86), 'R': Color(0xFFE0674F), 'G': Color(0xFF5FA35C), 'C': Color(0xFFBDB3A3)},
    font: 'Alegreya',
    fallback: ['Georgia', 'serif'],
    radius: 8,
    sound: SoundStyle(wave: 'bell', base: 660, decay: 0.2),
  );

  static const crystal = GameTheme(
    id: 'crystal',
    name: 'Crystal',
    blurb: 'Deep-blue menu windows with bright borders and crystal glints, for a world of summons and crystals.',
    chrome: ChromeStyle.crystal,
    backdrop: Backdrop.crystal,
    bg: Color(0xFF050A1E),
    surface: Color(0xFF0E1B4D),
    panel: Color(0xFF13246A),
    text: Colors.white,
    muted: Color(0xFFB8C4F0),
    accent: Color(0xFF8FD3FF),
    accent2: Color(0xFFE6C979),
    accent3: Color(0xFFC59BFF),
    danger: Color(0xFFFF7A8A),
    ok: Color(0xFF8BF0C0),
    highlight: Color(0xFFFFF2A8),
    buttonText: Color(0xFF071034),
    decor: [Color(0xFF8FD3FF), Color(0xFFC59BFF), Color(0xFFE6C979)],
    mana: {'W': Color(0xFFFFF6D9), 'U': Color(0xFF7FC4FF), 'B': Color(0xFFA493C8), 'R': Color(0xFFFF8A73), 'G': Color(0xFF86E3A1), 'C': Color(0xFFC9D2F2)},
    font: 'Philosopher',
    fallback: ['Verdana', 'Roboto'],
    radius: 6,
    sound: SoundStyle(wave: 'triangle', base: 988, decay: 0.15),
    sets: ['fin', 'fic', 'fca'],
    universes: ['Final Fantasy'],
  );

  static const elements = GameTheme(
    id: 'elements',
    name: 'Four elements',
    blurb: 'Ink-wash paper and brush strokes, with water, earth, fire and air accents.',
    chrome: ChromeStyle.ink,
    backdrop: Backdrop.paper,
    brightness: Brightness.light,
    bg: Color(0xFFF1E7D0),
    surface: Color(0xFFF7F0DE),
    panel: Color(0xFFEADBB8),
    text: Color(0xFF2B2118),
    muted: Color(0xFF7A6A55),
    accent: Color(0xFFB8442C),
    accent2: Color(0xFF2F6E9E),
    accent3: Color(0xFF4F7A3A),
    danger: Color(0xFFA8301E),
    ok: Color(0xFF4F7A3A),
    highlight: Color(0xFFD9A400),
    buttonText: Color(0xFFFBF5E6),
    decor: [Color(0xFF2F6E9E), Color(0xFF4F7A3A), Color(0xFFB8442C), Color(0xFFC9B26B)],
    mana: {'W': Color(0xFFFFFBEA), 'U': Color(0xFF2F6E9E), 'B': Color(0xFF3C3530), 'R': Color(0xFFB8442C), 'G': Color(0xFF4F7A3A), 'C': Color(0xFFA89E8C)},
    font: 'Alegreya',
    fallback: ['Georgia', 'serif'],
    radius: 4,
    sound: SoundStyle(wave: 'bell', base: 523, decay: 0.3),
    sets: ['tla', 'tle'],
    universes: ['Avatar: The Last Airbender'],
  );

  static const comic = GameTheme(
    id: 'comic',
    name: 'Web-slinger',
    blurb: 'Halftone comic panels, bold outlines and city-night red and blue.',
    chrome: ChromeStyle.comic,
    backdrop: Backdrop.halftone,
    bg: Color(0xFF0E1630),
    surface: Color(0xFFFFFFFF),
    panel: Color(0xFFFFF8E7),
    text: Color(0xFF111111),
    muted: Color(0xFF555566),
    accent: Color(0xFFE23636),
    accent2: Color(0xFF1F5BD6),
    accent3: Color(0xFFFFD23F),
    danger: Color(0xFFE23636),
    ok: Color(0xFF2DBE6C),
    highlight: Color(0xFFFFD23F),
    buttonText: Colors.white,
    decor: [Color(0xFFE23636), Color(0xFF1F5BD6), Color(0xFFFFD23F)],
    mana: {'W': Color(0xFFFFFDF0), 'U': Color(0xFF1F5BD6), 'B': Color(0xFF333344), 'R': Color(0xFFE23636), 'G': Color(0xFF2DBE6C), 'C': Color(0xFFBBBBBB)},
    brightness: Brightness.light,
    font: 'Roboto',
    titleFont: 'Bangers',
    fallback: ['Arial', 'sans-serif'],
    uppercase: true,
    letterSpacing: 0.4,
    radius: 2,
    sound: SoundStyle(wave: 'square', base: 740, decay: 0.07),
    sets: ['spm', 'spe', 'msh', 'mar'],
    universes: ["Marvel's Spider-Man"],
  );

  static const all = [classic, lcars, crystal, elements, comic];

  static GameTheme byId(String? id) => all.firstWhere((t) => t.id == id, orElse: () => classic);

  /// The theme a deck's main set picks.
  static GameTheme forSets(Iterable<String> sets) {
    final counts = <String, int>{};
    for (final s in sets) {
      for (final t in all) {
        if (t.sets.contains(s)) counts[t.id] = (counts[t.id] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return classic;
    final best = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
    return byId(best.key);
  }
}

// ---------------------------------------------------------------------------------------------
// Themed widgets
// ---------------------------------------------------------------------------------------------

/// A screen with the theme's frame: title, back button, actions, and the backdrop.
class ThemedScreen extends StatelessWidget {
  const ThemedScreen({super.key, required this.title, this.subtitle = '', required this.child, this.onBack, this.actions = const [], this.backdrop = false, this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 12)});
  final String title, subtitle;
  final Widget child;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool backdrop;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final back = onBack ?? (Navigator.of(context).canPop() ? () => Navigator.of(context).maybePop() : null);
    final bar = _TitleBar(title: title, subtitle: subtitle, onBack: back, actions: actions);
    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(children: [
        if (backdrop) Positioned.fill(child: TableBackdrop(theme: t)),
        SafeArea(
          child: Column(children: [
            bar,
            Expanded(child: Padding(padding: padding, child: child)),
          ]),
        ),
      ]),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.title, required this.subtitle, this.onBack, required this.actions});
  final String title, subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final backBtn = onBack == null
        ? const SizedBox(width: 8)
        : IconButton(onPressed: onBack, icon: Icon(Icons.arrow_back, color: t.chrome == ChromeStyle.lcars ? Colors.black : t.accent), tooltip: 'Back');
    final titleText = Text(t.label(title), style: t.display(22, weight: FontWeight.w800, color: t.chrome == ChromeStyle.lcars ? t.accent : (t.chrome == ChromeStyle.comic ? Colors.white : t.accent)), maxLines: 1, overflow: TextOverflow.ellipsis);
    final sub = subtitle.isEmpty ? null : Text(t.label(subtitle), style: t.style(12, color: t.chrome == ChromeStyle.comic ? Colors.white70 : t.muted), maxLines: 1, overflow: TextOverflow.ellipsis);
    switch (t.chrome) {
      case ChromeStyle.lcars:
        return SizedBox(
          height: 64,
          child: Row(children: [
            Container(
              width: 72,
              height: 64,
              decoration: BoxDecoration(color: t.accent, borderRadius: const BorderRadius.only(topLeft: Radius.circular(36))),
              alignment: Alignment.bottomLeft,
              child: onBack == null ? null : backBtn,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: Row(children: [Expanded(child: Align(alignment: Alignment.centerLeft, child: titleText)), ...actions])),
                Container(height: 18, decoration: BoxDecoration(color: t.accent, borderRadius: const BorderRadius.only(topRight: Radius.circular(9), bottomRight: Radius.circular(9))), alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 12), child: sub == null ? null : DefaultTextStyle.merge(style: const TextStyle(color: Colors.black), child: Text(t.label(subtitle), style: t.style(11, color: Colors.black)))),
              ]),
            ),
          ]),
        );
      case ChromeStyle.comic:
        return Container(
          height: 60,
          margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          decoration: BoxDecoration(color: t.accent, border: Border.all(color: Colors.black, width: 3), boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(4, 4))]),
          child: Row(children: [
            if (onBack != null) IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back, color: Colors.white)) else const SizedBox(width: 12),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [titleText, ?sub])),
            ...actions,
          ]),
        );
      case ChromeStyle.crystal:
        return Container(
          height: 58,
          margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          decoration: crystalWindow(t),
          child: Row(children: [
            backBtn,
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [titleText, ?sub])),
            ...actions,
          ]),
        );
      case ChromeStyle.ink:
        return Container(
          height: 60,
          padding: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.text.withValues(alpha: 0.75), width: 2))),
          child: Row(children: [
            backBtn,
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [titleText, ?sub])),
            ...actions,
          ]),
        );
      case ChromeStyle.classic:
        return Container(
          height: 58,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF3A2A1C), Color(0xFF241A11)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            border: Border(bottom: BorderSide(color: t.accent, width: 2)),
          ),
          child: Row(children: [
            backBtn,
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [titleText, ?sub])),
            ...actions,
          ]),
        );
    }
  }
}

BoxDecoration crystalWindow(GameTheme t, {Color? border}) => BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF2A47B8), Color(0xFF0E1B4D)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
      borderRadius: BorderRadius.circular(t.radius),
      border: Border.all(color: border ?? Colors.white, width: 2),
      boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 6, offset: Offset(0, 2))],
    );

/// The theme's big, clearly labeled button.
class ThemedButton extends StatelessWidget {
  const ThemedButton(this.label, {super.key, required this.onPressed, this.icon, this.color, this.tall = false, this.outlined = false, this.expand = true, this.subtitle});
  final String label;
  final String? subtitle;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final bool tall, outlined, expand;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final c = color ?? t.accent;
    final h = tall ? 58.0 : 46.0;
    final enabled = onPressed != null;
    final fg = outlined ? (t.chrome == ChromeStyle.comic ? Colors.black : c) : (t.chrome == ChromeStyle.crystal ? Colors.white : _onColor(c, t));
    BoxDecoration deco;
    switch (t.chrome) {
      case ChromeStyle.lcars:
        deco = BoxDecoration(color: outlined ? c.withValues(alpha: 0.12) : c, borderRadius: BorderRadius.circular(h / 2), border: outlined ? Border.all(color: c, width: 2) : null);
      case ChromeStyle.comic:
        deco = BoxDecoration(color: outlined ? Colors.white : c, border: Border.all(color: Colors.black, width: 3), boxShadow: enabled ? const [BoxShadow(color: Colors.black, offset: Offset(3, 3))] : null);
      case ChromeStyle.crystal:
        deco = outlined ? BoxDecoration(color: const Color(0x33000000), borderRadius: BorderRadius.circular(t.radius), border: Border.all(color: c, width: 2)) : crystalWindow(t, border: c);
      case ChromeStyle.ink:
        deco = BoxDecoration(color: outlined ? Colors.transparent : c, borderRadius: BorderRadius.circular(t.radius), border: Border.all(color: outlined ? c : t.text.withValues(alpha: 0.6), width: outlined ? 2 : 1.5));
      case ChromeStyle.classic:
        deco = BoxDecoration(
          gradient: outlined ? null : LinearGradient(colors: [Color.lerp(c, Colors.white, 0.18)!, Color.lerp(c, Colors.black, 0.18)!], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          color: outlined ? Colors.transparent : null,
          borderRadius: BorderRadius.circular(t.radius),
          border: Border.all(color: outlined ? c : const Color(0xFF6B4E2E), width: outlined ? 2 : 1.5),
        );
    }
    final content = Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
      if (icon != null) ...[Icon(icon, color: fg, size: tall ? 22 : 18), const SizedBox(width: 8)],
      Flexible(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(t.label(label), style: t.display(tall ? 17 : 15, weight: FontWeight.w800, color: fg), maxLines: 1)),
          if (subtitle != null) FittedBox(fit: BoxFit.scaleDown, child: Text(subtitle!, style: t.style(11, weight: FontWeight.w500, color: fg.withValues(alpha: 0.8)), maxLines: 1)),
        ]),
      ),
    ]);
    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(t.chrome == ChromeStyle.lcars ? h / 2 : t.radius),
            child: Container(constraints: BoxConstraints(minHeight: h), padding: EdgeInsets.symmetric(horizontal: tall ? 18 : 14, vertical: 6), decoration: deco, child: content),
          ),
        ),
      ),
    );
  }

  static Color _onColor(Color c, GameTheme t) => c.computeLuminance() > 0.33 ? const Color(0xFF111111) : Colors.white;
}

/// A content panel in the theme's style, with an optional heading.
class ThemedPanel extends StatelessWidget {
  const ThemedPanel({super.key, this.title, required this.child, this.color, this.padding = const EdgeInsets.all(12)});
  final String? title;
  final Widget child;
  final Color? color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final c = color ?? t.accent2;
    final head = title == null ? null : ThemedHeader(title!, color: c);
    switch (t.chrome) {
      case ChromeStyle.lcars:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ?head,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 6, height: 28, margin: const EdgeInsets.only(top: 2), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 10),
            Expanded(child: child),
          ]),
        ]);
      case ChromeStyle.comic:
        return Container(
          padding: padding,
          decoration: BoxDecoration(color: t.panel, border: Border.all(color: Colors.black, width: 3), boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(4, 4))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [?head, child]),
        );
      case ChromeStyle.crystal:
        return Container(padding: padding, decoration: crystalWindow(t), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [?head, child]));
      case ChromeStyle.ink:
        return Container(
          padding: padding,
          decoration: BoxDecoration(color: t.panel.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(t.radius), border: Border(left: BorderSide(color: c, width: 4))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [?head, child]),
        );
      case ChromeStyle.classic:
        return Container(
          padding: padding,
          decoration: BoxDecoration(color: t.panel, borderRadius: BorderRadius.circular(t.radius), border: Border.all(color: const Color(0xFF5E4027), width: 1.5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [?head, child]),
        );
    }
  }
}

class ThemedHeader extends StatelessWidget {
  const ThemedHeader(this.title, {super.key, this.color});
  final String title;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final c = color ?? t.accent;
    final text = Text(t.label(title), style: t.display(17, weight: FontWeight.w800, color: t.chrome == ChromeStyle.comic ? Colors.black : c), maxLines: 1, overflow: TextOverflow.ellipsis);
    if (t.chrome == ChromeStyle.lcars) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(width: 30, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6))),
          const SizedBox(width: 6),
          Flexible(child: text),
          const SizedBox(width: 6),
          Expanded(child: Container(height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)))),
        ]),
      );
    }
    return Padding(padding: const EdgeInsets.only(bottom: 8, top: 2), child: text);
  }
}

/// The table's backdrop for a theme.
class TableBackdrop extends StatelessWidget {
  const TableBackdrop({super.key, required this.theme});
  final GameTheme theme;
  @override
  Widget build(BuildContext context) => IgnorePointer(child: CustomPaint(painter: _BackdropPainter(theme), size: Size.infinite));
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.t);
  final GameTheme t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rng = math.Random(47);
    switch (t.backdrop) {
      case Backdrop.starfield:
        canvas.drawRect(rect, Paint()..color = Colors.black);
        final p = Paint();
        for (var i = 0; i < 140; i++) {
          p.color = Colors.white.withValues(alpha: 0.2 + 0.5 * rng.nextDouble());
          canvas.drawCircle(Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height), rng.nextDouble() * 1.3 + 0.3, p);
        }
      case Backdrop.felt:
        canvas.drawRect(rect, Paint()..shader = const RadialGradient(colors: [Color(0xFF2B3A2A), Color(0xFF141C14)], radius: 1.1).createShader(rect));
        final p = Paint()..color = Colors.white.withValues(alpha: 0.015);
        for (var i = 0; i < 400; i++) {
          canvas.drawCircle(Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height), 1.2, p);
        }
      case Backdrop.crystal:
        canvas.drawRect(rect, Paint()..shader = const LinearGradient(colors: [Color(0xFF0B1650), Color(0xFF030716)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(rect));
        for (var i = 0; i < 26; i++) {
          final c = Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height);
          final r = 6 + rng.nextDouble() * 16;
          final path = Path()
            ..moveTo(c.dx, c.dy - r)
            ..lineTo(c.dx + r * 0.45, c.dy)
            ..lineTo(c.dx, c.dy + r)
            ..lineTo(c.dx - r * 0.45, c.dy)
            ..close();
          canvas.drawPath(path, Paint()..color = t.decor[i % t.decor.length].withValues(alpha: 0.10 + 0.08 * rng.nextDouble()));
        }
      case Backdrop.paper:
        canvas.drawRect(rect, Paint()..color = t.bg);
        for (var i = 0; i < 4; i++) {
          final y = size.height * (0.15 + 0.23 * i);
          final path = Path()..moveTo(0, y);
          for (var x = 0.0; x <= size.width; x += 24) {
            path.lineTo(x, y + math.sin(x / 70 + i) * 10);
          }
          canvas.drawPath(path, Paint()
            ..color = t.decor[i % t.decor.length].withValues(alpha: 0.10)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 18
            ..strokeCap = StrokeCap.round);
        }
      case Backdrop.halftone:
        canvas.drawRect(rect, Paint()..shader = const LinearGradient(colors: [Color(0xFF1F2A5C), Color(0xFF0A0F24)], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(rect));
        final p = Paint()..color = const Color(0xFFE23636).withValues(alpha: 0.18);
        for (var y = 0.0; y < size.height; y += 14) {
          for (var x = (y ~/ 14).isEven ? 0.0 : 7.0; x < size.width; x += 14) {
            final r = 1.0 + 3.0 * (x / (size.width + 1));
            canvas.drawCircle(Offset(x, y), r, p);
          }
        }
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.t.id != t.id;
}

/// Mana symbols as pips in the theme's mana colors.
class ManaPips extends StatelessWidget {
  const ManaPips(this.cost, {super.key, this.size = 15});
  final String cost;
  final double size;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final symbols = [for (final m in RegExp(r'\{([^}]+)\}').allMatches(cost)) m.group(1)!];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final s in symbols)
        Container(
          width: size,
          height: size,
          margin: const EdgeInsets.only(right: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: t.manaColor(s.length == 1 ? s : 'C'), shape: BoxShape.circle, border: Border.all(color: Colors.black26)),
          child: Text(s.replaceAll('/', ''), style: TextStyle(fontSize: size * (s.length > 1 ? 0.45 : 0.62), fontWeight: FontWeight.w900, color: const Color(0xFF111111))),
        ),
    ]);
  }
}

/// The theme fonts ship inside this package (OFL licensed, see fonts/), so apps refer to them
/// with the package prefix; system fonts pass through unchanged.
String bundledFont(String family) => const {'Antonio', 'Alegreya', 'Philosopher', 'Bangers'}.contains(family) ? 'packages/tcg_app/$family' : family;
