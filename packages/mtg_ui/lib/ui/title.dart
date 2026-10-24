import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tcg_app/tcg_app.dart';
import '../app/store.dart';
import 'card_view.dart';
import 'menu.dart';

/// The entry screen: the name, a fan of cards dealt onto the table, drifting motes in the
/// theme's colors and the themes to pick from. A tap anywhere goes on to the menu (on the web
/// that first tap is also what lets the browser play sound).
class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key});

  /// One card of each color for the fan, all in the bundled pool.
  static const showcase = ['Serra Angel', 'Kiora, the Rising Tide', 'Liliana, Dreadhorde General', 'Shivan Dragon', 'Ghalta, Primal Hunger'];

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..forward();
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 14));
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    // The idle motion only starts once the cards are dealt; reduced motion keeps it still.
    _intro.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted && AppStore.shared.animations && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) _loop.repeat();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  void _begin() {
    if (_leaving) return;
    _leaving = true;
    Console.shared.play(Fx.title);
    _loop.stop();
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 650),
      pageBuilder: (_, _, _) => const UpdateCheck(child: MainMenuScreen()),
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: ScaleTransition(scale: Tween(begin: 1.06, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final store = AppStore.shared;
    final cards = [for (final n in TitleScreen.showcase) if (store.db[n] != null) store.db[n]!];
    return Scaffold(
      backgroundColor: t.bg,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _begin,
        child: Stack(children: [
          Positioned.fill(child: TableBackdrop(theme: t)),
          Positioned.fill(child: IgnorePointer(child: AnimatedBuilder(animation: _loop, builder: (context, _) => CustomPaint(painter: _Motes(t, _loop.value))))),
          SafeArea(
            child: LayoutBuilder(builder: (context, box) {
              // Landscape: the name on the left, the fan on the right.
              final side = box.maxWidth > box.maxHeight * 1.3;
              final fanW = side ? box.maxWidth * 0.5 : box.maxWidth;
              final cardW = math.min(fanW / 4.1, math.min(box.maxHeight * (side ? 0.5 : 0.3) * 63 / 88, 210.0));
              final titleSize = math.min(76.0, math.min((side ? box.maxWidth * 0.5 : box.maxWidth) / 5.2, box.maxHeight / 6));
              return AnimatedBuilder(
                animation: Listenable.merge([_intro, _loop]),
                builder: (context, _) {
                  final v = _intro.value;
                  final titleIn = Curves.easeOutCubic.transform((v / 0.45).clamp(0, 1));
                  final promptIn = ((v - 0.75) / 0.25).clamp(0.0, 1.0);
                  final pulse = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(_loop.value * math.pi * 2 * 7));
                  final title = Opacity(
                    opacity: titleIn,
                    child: Transform.translate(
                      offset: Offset(0, -30 * (1 - titleIn)),
                      child: _Shimmer(phase: _loop.value, theme: t, child: Text('OpenMTG', style: t.display(titleSize, weight: FontWeight.w900, color: Colors.white))),
                    ),
                  );
                  final tagline = Opacity(
                    opacity: titleIn,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(t.label('Every card. The full rules. A theme for every world.'), textAlign: TextAlign.center, style: t.style(15, weight: FontWeight.w600, color: t.muted)),
                    ),
                  );
                  final fan = SizedBox(height: cardW * 88 / 63 + 50, width: fanW, child: _Fan(cards: cards, width: cardW, deal: v, sway: _loop.value));
                  final prompt = Opacity(
                    opacity: promptIn * pulse,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      decoration: BoxDecoration(
                        color: t.accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(40),
                        border: Border.all(color: t.accent, width: 2),
                        boxShadow: [BoxShadow(color: t.accent.withValues(alpha: 0.35 * pulse), blurRadius: 18)],
                      ),
                      child: Text(t.label('Tap to begin'), style: t.display(22, weight: FontWeight.w800, color: t.accent)),
                    ),
                  );
                  final picker = Opacity(opacity: promptIn, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _ThemePicker(onPick: (id) => store.setThemeOverride(id))));
                  final notice = Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Free and fan-made. Unofficial Fan Content permitted under the Fan Content Policy; not approved or endorsed by Wizards of the Coast. Card images courtesy of Scryfall.',
                      textAlign: TextAlign.center,
                      style: t.style(10.5, weight: FontWeight.w400, color: t.muted.withValues(alpha: 0.8)),
                    ),
                  );
                  if (side) {
                    return Row(children: [
                      // Shrinks to fit short screens rather than overflowing.
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: box.maxWidth - fanW,
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                title,
                                const SizedBox(height: 4),
                                tagline,
                                const SizedBox(height: 20),
                                prompt,
                                const SizedBox(height: 12),
                                picker,
                                const SizedBox(height: 14),
                                notice,
                              ]),
                            ),
                          ),
                        ),
                      ),
                      Center(child: fan),
                    ]);
                  }
                  return Column(children: [
                    const Spacer(flex: 2),
                    title,
                    const SizedBox(height: 6),
                    tagline,
                    const Spacer(),
                    fan,
                    const Spacer(),
                    prompt,
                    const SizedBox(height: 18),
                    picker,
                    const Spacer(),
                    notice,
                  ]);
                },
              );
            }),
          ),
        ]),
      ),
    );
  }
}

/// A light sweeping across the title, in the theme's accents.
class _Shimmer extends StatelessWidget {
  const _Shimmer({required this.phase, required this.theme, required this.child});
  final double phase;
  final GameTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final x = -1.5 + 3.5 * ((phase * 3) % 1);
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => LinearGradient(
        begin: Alignment(x - 1, -0.3),
        end: Alignment(x + 1, 0.3),
        colors: [theme.accent, Color.lerp(theme.accent, Colors.white, 0.85)!, theme.accent2],
        stops: const [0.25, 0.5, 0.75],
      ).createShader(r),
      child: DecoratedBox(
        decoration: BoxDecoration(boxShadow: [BoxShadow(color: theme.accent.withValues(alpha: 0.25), blurRadius: 40, spreadRadius: -10)]),
        child: child,
      ),
    );
  }
}

/// Five cards dealt from below into a fan, then breathing gently.
class _Fan extends StatelessWidget {
  const _Fan({required this.cards, required this.width, required this.deal, required this.sway});
  final List cards;
  final double width, deal, sway;

  @override
  Widget build(BuildContext context) {
    final n = cards.length;
    if (n == 0) return const SizedBox.shrink();
    final h = width * 88 / 63;
    final breathe = math.sin(sway * math.pi * 2) * 0.03;
    return LayoutBuilder(builder: (context, box) {
      final cx = box.maxWidth / 2;
      return Stack(clipBehavior: Clip.none, children: [
        for (var i = 0; i < n; i++)
          Builder(builder: (context) {
            final k = i - (n - 1) / 2;
            // Each card is dealt a little after the last.
            final start = 0.15 + i * 0.09;
            final u = Curves.easeOutBack.transform(((deal - start) / 0.4).clamp(0, 1));
            final angle = k * (0.16 + breathe) * u;
            final x = cx - width / 2 + k * width * 0.46 * u;
            final y = 18 + (k * k) * 6 * u + (1 - u) * (box.maxHeight + 80);
            return Positioned(
              left: x,
              top: y,
              width: width,
              height: h,
              child: Transform.rotate(
                angle: angle + (1 - u) * 0.6,
                alignment: Alignment.bottomCenter,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(width * 0.05),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, 6))],
                  ),
                  child: ClipRRect(borderRadius: BorderRadius.circular(width * 0.05), child: CardPicture(def: cards[i], size: width > 150 ? 'normal' : 'small')),
                ),
              ),
            );
          }),
      ]);
    });
  }
}

/// The themes as small swatches; picking one switches at once (and is kept, as in Settings).
class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.onPick});
  final void Function(String id) onPick;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
      for (final th in Themes.all)
        Semantics(
          button: true,
          label: 'Theme: ${th.name}',
          child: GestureDetector(
            onTap: () {
              Console.shared.play(Fx.chirp);
              onPick(th.id);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: th.panel.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: th.id == t.id ? th.accent : th.muted.withValues(alpha: 0.4), width: th.id == t.id ? 2.5 : 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final c in [th.accent, th.accent2, th.accent3]) Container(width: 9, height: 9, margin: const EdgeInsets.only(right: 3), decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                const SizedBox(width: 3),
                Text(th.name, style: th.style(12, weight: FontWeight.w700, color: th.text)),
              ]),
            ),
          ),
        ),
    ]);
  }
}

/// Slow motes of light drifting upward.
class _Motes extends CustomPainter {
  _Motes(this.t, this.v);
  final GameTheme t;
  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(7);
    final colors = [...t.decor, t.accent, t.accent2];
    for (var i = 0; i < 46; i++) {
      final x0 = rng.nextDouble(), y0 = rng.nextDouble(), speed = 0.4 + rng.nextDouble(), r = 1 + rng.nextDouble() * 2.6;
      final y = (y0 - v * speed) % 1.0;
      final x = x0 + math.sin((v * 2 + x0) * math.pi * 2) * 0.015;
      final fade = math.sin(y * math.pi);
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        r,
        Paint()
          ..color = colors[i % colors.length].withValues(alpha: 0.5 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(_Motes old) => old.v != v || old.t.id != t.id;
}
