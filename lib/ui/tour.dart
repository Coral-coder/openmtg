import 'package:flutter/material.dart';

import '../app/store.dart';
import 'package:tcg_app/tcg_app.dart';

/// One stop on a guided tour: the part of the screen to light up (none for a centered note)
/// and what to say about it.
class TourStep {
  const TourStep(this.title, this.text, {this.target});
  final String title;
  final String text;
  final GlobalKey? target;
}

/// Dims the screen except one region and explains it, step by step. Sits over the whole
/// screen; [onNext] advances, [onClose] ends the tour.
class TourOverlay extends StatelessWidget {
  const TourOverlay({super.key, required this.steps, required this.index, required this.onNext, required this.onClose});
  final List<TourStep> steps;
  final int index;
  final VoidCallback onNext;
  final VoidCallback onClose;

  Rect? _holeIn(BuildContext context) {
    final target = steps[index].target?.currentContext?.findRenderObject();
    final me = context.findRenderObject();
    if (target is! RenderBox || me is! RenderBox || !target.hasSize || !target.attached) return null;
    final topLeft = me.globalToLocal(target.localToGlobal(Offset.zero));
    return (topLeft & target.size).inflate(4);
  }

  @override
  Widget build(BuildContext context) {
    final step = steps[index];
    final last = index == steps.length - 1;
    final t = GameTheme.of(context);
    // The tour sits above the Scaffold, so it brings its own Material for text and ink.
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, box) {
          final hole = _holeIn(context);
          final card = Container(
            constraints: const BoxConstraints(maxWidth: 420),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: t.panel,
              borderRadius: BorderRadius.circular(t.radius + 6),
              border: Border.all(color: t.highlight, width: 2),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 16)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(t.label(step.title), style: t.style(18, weight: FontWeight.w800, color: t.accent)),
                    ),
                    Text('${index + 1} / ${steps.length}', style: t.small),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  step.text,
                  style: t.style(16, weight: FontWeight.w500, height: 1.3),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (!last)
                      Expanded(
                        child: ThemedButton('Skip tour', outlined: true, onPressed: onClose),
                      ),
                    if (!last) const SizedBox(width: 10),
                    Expanded(
                      child: ThemedButton(last ? 'Got it' : 'Next', onPressed: last ? onClose : onNext),
                    ),
                  ],
                ),
              ],
            ),
          );
          // The note goes on the side of the screen away from the highlighted region.
          final below = hole == null ? null : hole.center.dy < box.maxHeight / 2;
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {},
                  child: CustomPaint(painter: _DimPainter(hole)),
                ),
              ),
              if (hole == null)
                Center(child: card)
              else if (below!)
                Positioned(
                  left: 0,
                  right: 0,
                  top: (hole.bottom + 12).clamp(0.0, box.maxHeight - 220),
                  child: Center(child: card),
                )
              else
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: (box.maxHeight - hole.top + 12).clamp(0.0, box.maxHeight - 220),
                  child: Center(child: card),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DimPainter extends CustomPainter {
  _DimPainter(this.hole);
  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = const Color(0xCC000000);
    final all = Path()..addRect(Offset.zero & size);
    final h = hole;
    if (h == null) {
      canvas.drawPath(all, dim);
      return;
    }
    final cut = Path()..addRRect(RRect.fromRectAndRadius(h, const Radius.circular(12)));
    canvas.drawPath(Path.combine(PathOperation.difference, all, cut), dim);
    canvas.drawRRect(
      RRect.fromRectAndRadius(h, const Radius.circular(12)),
      Paint()
        ..color = const Color(0xFFFFD36B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.hole != hole;
}


/// The table's parts the tour points at.
class TourKeys {
  final hand = GlobalKey();
  final battlefield = GlobalKey();
  final life = GlobalKey();
  final steps = GlobalKey();
  final prompt = GlobalKey();
}

/// The optional guided tour of the table, shown once (and from the help button).
void showTableTour(BuildContext context, TourKeys keys) {
  final steps = [
    const TourStep('Welcome to the table', 'This is the game table. The tour shows where things are; skip it now and take it again any time from the ? button.'),
    TourStep('Your hand', 'Your cards. Lit cards can be played now. Tap any card to see it large, with what it can do and why not.', target: keys.hand),
    TourStep('Your side', 'Your permanents: creatures in front, lands behind. Tap a creature to see its abilities. Lands can show as cards or grouped labels (Settings).', target: keys.battlefield),
    TourStep('Life and zones', 'Your life total, cards in hand and library, graveyard and exile. Tap the graveyard to look through it.', target: keys.life),
    TourStep('The turn', 'Where the turn is: upkeep, draw, main phase, combat, end. The game stops wherever you can act.', target: keys.steps),
    TourStep('What to do now', 'This bar says what you can do and holds the big buttons: pass priority, move to combat, attack, confirm a choice. The coach line can be turned off in Settings.', target: keys.prompt),
  ];
  var index = 0;
  late OverlayEntry entry;
  void close() {
    entry.remove();
    AppStore.shared.setBool('tourSeen', true);
  }

  entry = OverlayEntry(
    builder: (ctx) => ThemeScope(
      theme: AppStore.shared.theme,
      child: StatefulBuilder(
        builder: (ctx, setState) => TourOverlay(steps: steps, index: index, onNext: () => setState(() => index++), onClose: close),
      ),
    ),
  );
  Overlay.of(context).insert(entry);
}
