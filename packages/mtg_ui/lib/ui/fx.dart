import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rules/rules.dart';

import 'package:tcg_app/tcg_app.dart';
import '../app/store.dart';
import 'card_view.dart';
import 'table_controller.dart';

/// Table animations and their sounds. The engine only hands over states, so this layer keeps
/// a picture of the last one and animates the difference: cards fly between hand, stack and
/// battlefield ([Tracked]), the dead fade into their owner's graveyard, damage and life changes
/// float up, attacks streak across the table and a banner marks each new turn. It never feeds
/// anything back to the game, so it can't affect determinism.
class TableFx extends StatefulWidget {
  const TableFx({super.key, required this.ctl, required this.child});
  final TableController ctl;
  final Widget child;

  static TableFxState? of(BuildContext context) => context.getInheritedWidgetOfExactType<_FxScope>()?.fx;

  @override
  State<TableFx> createState() => TableFxState();
}

class _FxScope extends InheritedWidget {
  const _FxScope({required this.fx, required super.child});
  final TableFxState fx;
  @override
  bool updateShouldNotify(_FxScope old) => false;
}

/// What the table looked like after the last change.
class _Snap {
  _Snap(this.key, this.turn, this.active, this.step, this.over, this.life, this.zones, this.objs, this.stackSources, this.hands);
  final String key;
  final int turn, active;
  final TurnStep step;
  final bool over;
  final List<int> life;
  final Map<int, Zone> zones; // battlefield, hands, spells on the stack
  final Map<int, _ObjSnap> objs;
  final List<int> stackSources; // the object each stack item came from, bottom first
  final List<List<int>> hands;
}

class _ObjSnap {
  _ObjSnap(this.owner, this.controller, this.damage, this.attacking, this.blocking, this.plus, this.cardName, this.token, this.land);
  final int owner, controller, damage, plus;
  final int? attacking;
  final bool blocking, token, land;
  final String cardName;
}

class TableFxState extends State<TableFx> {
  final _overlay = GlobalKey();
  final List<Widget> _effects = [];
  int _effectSeq = 0;
  _Snap? _prev;

  /// Where each card was last drawn, in global coordinates (kept after it leaves, so the next
  /// place it appears can fly in from there).
  final Map<int, Rect> rects = {};

  /// Each player's bar (their library and graveyard live there).
  final Map<int, Rect> bars = {};

  /// Grouped lands ("player|name"), when lands aren't shown as cards.
  final Map<String, Rect> landGroups = {};

  /// Where a card that's about to appear should fly in from, when that isn't its last rect.
  final Map<int, Rect> _origin = {};

  /// Cards that just arrived, to be popped in when they have nowhere to fly from.
  final Set<int> _born = {};

  /// Hits per card, so its widget can shake once per hit.
  final Map<int, int> hits = {};

  /// Animations on (Settings, and the system's reduce-motion switch); set on every build.
  bool enabled = true;

  /// Cards to ring with a burst once they've landed.
  final Set<int> _burst = {};

  /// Where [id] should fly in from, if anywhere (consumed).
  Rect? takeOrigin(int id) => _origin.remove(id) ?? rects[id];

  bool takeBorn(int id) => _born.remove(id);

  @override
  Widget build(BuildContext context) {
    enabled = AppStore.shared.animations && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    _diff(context);
    return _FxScope(
      fx: this,
      child: Stack(key: _overlay, children: [
        Positioned.fill(child: widget.child),
        Positioned.fill(child: IgnorePointer(child: Stack(clipBehavior: Clip.none, children: List.of(_effects)))),
      ]),
    );
  }

  _Snap _snap() {
    final ctl = widget.ctl;
    final g = ctl.game;
    final s = g.state;
    final zones = <int, Zone>{};
    final objs = <int, _ObjSnap>{};
    void add(int id, Zone z) {
      final o = s.objOrNull(id);
      if (o == null) return;
      zones[id] = z;
      final c = g.chars(id);
      objs[id] = _ObjSnap(o.owner, c.controller, o.damage, o.attacking, o.blocking.isNotEmpty, o.counters['+1/+1'] ?? 0, o.cardName, o.isToken, c.isLand);
    }

    for (final id in s.battlefield) {
      add(id, Zone.battlefield);
    }
    for (final p in s.players) {
      for (final id in p.hand) {
        add(id, Zone.hand);
      }
    }
    for (final item in s.stack) {
      if (item.objId != null) add(item.objId!, Zone.stack);
    }
    return _Snap(
      '${ctl.session.resets}|${identityHashCode(ctl.game)}',
      s.turn,
      s.active,
      s.step,
      s.over,
      [for (final p in s.players) p.life],
      zones,
      objs,
      [for (final i in s.stack) i.objId ?? i.sourceId],
      [for (final p in s.players) List.of(p.hand)],
    );
  }

  void _diff(BuildContext context) {
    final now = _snap();
    final prev = _prev;
    _prev = now;
    if (prev == null || prev.key != now.key) return;
    final ctl = widget.ctl;
    final me = ctl.me;
    final anim = enabled;
    final sounds = <Fx>{};

    // Cards arriving.
    for (final e in now.zones.entries) {
      final id = e.key;
      final was = prev.zones[id];
      if (was == e.value) continue;
      final o = now.objs[id]!;
      switch (e.value) {
        case Zone.battlefield:
          sounds.add(o.land ? Fx.land : Fx.summon);
          final group = landGroups['${o.controller}|${o.cardName}'];
          if (anim && o.land && !AppStore.shared.landsAsCards && rects[id] != null && group != null) {
            _ghost(o, rects[id]!, group, dying: false, into: true);
          }
          if (rects[id] == null) {
            final bar = bars[o.controller];
            if (bar != null && !o.token) {
              _origin[id] = Rect.fromCenter(center: bar.center, width: 40, height: 56);
            } else {
              _born.add(id);
            }
          }
          if (anim && !o.land) _burst.add(id);
        case Zone.hand:
          if (was == null && o.owner == me) {
            sounds.add(Fx.draw);
            final bar = bars[o.owner];
            if (bar != null) _origin[id] = Rect.fromCenter(center: bar.centerRight - const Offset(90, 0), width: 30, height: 42);
          }
        case Zone.stack:
          sounds.add(Fx.cast);
          if (rects[id] == null) {
            final bar = bars[o.controller];
            if (bar != null) _origin[id] = Rect.fromCenter(center: bar.center, width: 40, height: 56);
          }
          if (anim && o.controller != me && ctl.session.mode != SessionMode.hotseat) _spotlight(o);
        default:
      }
    }

    // Cards leaving the battlefield, the stack or a hand for a graveyard, exile or library.
    for (final e in prev.zones.entries) {
      final id = e.key;
      if (now.zones.containsKey(id)) continue;
      final o = prev.objs[id]!;
      final st = ctl.state.objOrNull(id);
      final to = st?.zone;
      if (e.value == Zone.battlefield) sounds.add(to == Zone.graveyard && !o.land ? Fx.dies : Fx.draw);
      if (e.value == Zone.hand && to == Zone.graveyard) sounds.add(Fx.dies);
      if (anim && rects[id] != null && (e.value != Zone.hand || o.owner == me)) {
        final target = bars[o.owner];
        _ghost(o, rects[id]!, target, dying: e.value == Zone.battlefield && to == Zone.graveyard, quiet: e.value == Zone.stack);
      }
    }

    // Where damage came from: what just resolved, else the attackers in a damage step.
    final resolved = [for (final id in prev.stackSources) if (!now.stackSources.contains(id)) id];
    final combat = now.step == TurnStep.combatDamage || now.step == TurnStep.firstStrikeDamage || now.step == TurnStep.endCombat;
    List<int> sourcesFor(int entity) {
      if (resolved.isNotEmpty) return resolved.take(1).toList();
      if (!combat) return const [];
      return [for (final e in prev.objs.entries) if (e.value.attacking == entity) e.key];
    }

    // Life.
    for (var p = 0; p < now.life.length && p < prev.life.length; p++) {
      final d = now.life[p] - prev.life[p];
      if (d == 0) continue;
      sounds.add(d < 0 ? Fx.hit : Fx.heal);
      final bar = bars[p];
      if (!anim || bar == null) continue;
      if (d < 0) {
        for (final src in sourcesFor(playerEntity(p)).take(4)) {
          final from = rects[src];
          if (from != null) _streak(from.center, bar.center, _theme.danger);
        }
      }
      _float(d > 0 ? '+$d' : '$d', Offset(bar.center.dx, bar.top), d < 0 ? _theme.danger : _theme.ok, big: true);
    }

    // Damage and +1/+1 counters on permanents; attacks and blocks.
    var attacked = false, blocked = false;
    for (final e in now.objs.entries) {
      final was = prev.objs[e.key];
      if (was == null || now.zones[e.key] != Zone.battlefield || prev.zones[e.key] != Zone.battlefield) continue;
      final o = e.value;
      if (o.attacking != null && was.attacking == null) attacked = true;
      if (o.blocking && !was.blocking) blocked = true;
      final r = rects[e.key];
      if (o.damage > was.damage) {
        sounds.add(Fx.damage);
        hits[e.key] = (hits[e.key] ?? 0) + 1;
        if (anim && r != null) {
          if (resolved.isNotEmpty && rects[resolved.first] != null) _streak(rects[resolved.first]!.center, r.center, _theme.danger);
          _float('−${o.damage - was.damage}', r.center, _theme.danger);
        }
      }
      if (o.plus != was.plus && anim && r != null) {
        final d = o.plus - was.plus;
        _float(d > 0 ? '+$d/+$d' : '$d/$d', r.topCenter + const Offset(0, 12), d > 0 ? _theme.ok : _theme.danger);
      }
    }
    if (attacked) sounds.add(Fx.attack);
    if (blocked) sounds.add(Fx.block);

    // A new turn.
    if (now.turn != prev.turn && !now.over) {
      sounds.add(Fx.turn);
      if (anim) {
        final mine = now.active == me;
        _banner(mine ? _theme.label('Your turn') : _theme.label("${ctl.state.player(now.active).name}'s turn"), mine ? _theme.accent : _theme.accent2, 'Turn ${now.turn}');
      }
    }

    // Sounds, a little apart so a burst doesn't turn into one blip.
    const order = [Fx.turn, Fx.cast, Fx.land, Fx.summon, Fx.attack, Fx.block, Fx.draw, Fx.damage, Fx.hit, Fx.heal, Fx.dies];
    var delay = 0;
    for (final fx in order) {
      if (!sounds.contains(fx)) continue;
      Console.shared.playAfter(fx, delay);
      delay += 110;
    }
  }

  GameTheme get _theme => GameTheme.of(context);

  /// Global → this layer's coordinates.
  Offset _local(Offset global) {
    final box = _overlay.currentContext?.findRenderObject() as RenderBox?;
    return box == null || !box.hasSize ? global : box.globalToLocal(global);
  }

  Rect _localRect(Rect r) => _local(r.topLeft) & r.size;

  void _add(Widget Function(Key key, VoidCallback done) make) {
    final key = ValueKey(_effectSeq++);
    late Widget w;
    w = make(key, () {
      if (!mounted) return;
      setState(() => _effects.remove(w));
    });
    _effects.add(w);
    if (_effects.length > 40) _effects.removeAt(0);
  }

  void _float(String text, Offset at, Color color, {bool big = false}) {
    final p = _local(at);
    _add((key, done) => _FloatText(key: key, text: text, at: p, color: color, size: big ? 34 : 24, onDone: done));
  }

  void _streak(Offset from, Offset to, Color color) {
    final a = _local(from), b = _local(to);
    _add((key, done) => _Streak(key: key, from: a, to: b, color: color, onDone: done));
  }

  /// Rings [id] if it was waiting for one (called by its [Tracked] once it has landed).
  void landed(int id, Rect at) {
    if (!_burst.remove(id) || !mounted) return;
    final lr = _localRect(at);
    setState(() => _add((key, done) => _Burst(key: key, rect: lr, color: _theme.highlight, onDone: done)));
  }

  void _ghost(_ObjSnap o, Rect from, Rect? to, {required bool dying, bool quiet = false, bool into = false}) {
    final def = o.token ? null : widget.ctl.game.db[o.cardName];
    final a = _localRect(from);
    final b = to == null ? a.shift(const Offset(0, 40)) : Rect.fromCenter(center: _local(to.center), width: from.width * (into ? 0.45 : 0.3), height: from.height * (into ? 0.45 : 0.3));
    _add((key, done) => _Ghost(key: key, def: def, from: a, to: b, dying: dying, quiet: quiet, onDone: done));
  }

  void _spotlight(_ObjSnap o) {
    final def = widget.ctl.game.db[o.cardName];
    if (def == null) return;
    _add((key, done) => _Spotlight(key: key, def: def, onDone: done));
  }

  void _banner(String text, Color color, String sub) {
    _add((key, done) => _Banner(key: key, text: text, sub: sub, color: color, onDone: done));
  }
}

/// A card on the table that remembers where it is, flies in from where it last was (or from
/// its player's bar), pops in when it's new, and shakes when it's hit.
class Tracked extends StatefulWidget {
  Tracked({required int id, required this.child})
      : _id = id,
        super(key: ValueKey(id));
  final int _id;
  final Widget child;

  @override
  State<Tracked> createState() => _TrackedState();
}

class _TrackedState extends State<Tracked> with TickerProviderStateMixin {
  TableFxState? _fx;
  AnimationController? _fly, _shake;
  Rect? _from, _to;
  bool _pop = false, _measured = false;
  int _hits = 0;

  @override
  void initState() {
    super.initState();
    _fx = TableFx.of(context);
    final fx = _fx;
    if (fx == null) return;
    _hits = fx.hits[widget._id] ?? 0;
    if (!fx.enabled) {
      fx.takeBorn(widget._id);
      return;
    }
    _from = fx.takeOrigin(widget._id);
    _pop = fx.takeBorn(widget._id) && _from == null;
    if (_from != null || _pop) {
      _fly = AnimationController(vsync: this, duration: Duration(milliseconds: _pop ? 520 : 460));
    }
  }

  @override
  void dispose() {
    _fly?.dispose();
    _shake?.dispose();
    super.dispose();
  }

  void _record() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final fx = _fx;
    if (box == null || !box.hasSize || !box.attached || fx == null) return;
    final r = box.localToGlobal(Offset.zero) & box.size;
    if (!_measured) {
      _measured = true;
      _to = r;
      final from = _from;
      if (from != null && (from.center - r.center).distance < 4 && (from.width - r.width).abs() < 4) {
        _from = null;
        _fly?.value = 1;
        fx.landed(widget._id, r);
      } else if (_fly != null) {
        _fly!.forward().whenCompleteOrCancel(() {
          if (mounted) fx.landed(widget._id, r);
        });
        setState(() {});
      } else {
        fx.landed(widget._id, r);
      }
    }
    // Keep the resting position, not one mid-flight.
    if (_fly == null || _fly!.isCompleted) fx.rects[widget._id] = r;
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _record());
    final fx = _fx;
    if (fx == null) return widget.child;
    final hits = fx.hits[widget._id] ?? 0;
    if (hits != _hits) {
      _hits = hits;
      if (fx.enabled) {
        _shake ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _shake!.forward(from: 0);
        });
      }
    }
    Widget child = widget.child;
    if (_shake != null) {
      final shake = _shake!;
      child = AnimatedBuilder(
        animation: shake,
        child: child,
        builder: (context, c) {
          final v = shake.value;
          final dx = v == 0 || v == 1 ? 0.0 : math.sin(v * math.pi * 6) * 7 * (1 - v);
          return Transform.translate(offset: Offset(dx, 0), child: c);
        },
      );
    }
    final fly = _fly;
    if (fly == null) return child;
    if (!_measured) return Opacity(opacity: 0, child: child);
    return AnimatedBuilder(
      animation: fly,
      child: child,
      builder: (context, c) {
        final from = _from, to = _to;
        if (_pop || from == null || to == null) {
          final v = Curves.elasticOut.transform(fly.value.clamp(0, 1));
          return Opacity(opacity: fly.value.clamp(0.0, 1.0), child: Transform.scale(scale: 0.3 + 0.7 * v, child: c));
        }
        final t = Curves.easeOutCubic.transform(fly.value);
        final dx = (from.center - to.center) * (1 - t);
        final scale = from.width / math.max(1, to.width);
        // A little arc on the way, so cards don't just slide.
        final lift = math.sin(t * math.pi) * -18;
        return Transform.translate(
          offset: dx + Offset(0, lift),
          child: Transform.scale(scale: scale + (1 - scale) * t, child: c),
        );
      },
    );
  }
}

/// Reports where its child is drawn after each build (for things that aren't cards).
class RectProbe extends StatelessWidget {
  const RectProbe({super.key, required this.onRect, required this.child});
  final void Function(TableFxState fx, Rect rect) onRect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fx = TableFx.of(context);
    if (fx == null) return child;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && box.attached) onRect(fx, box.localToGlobal(Offset.zero) & box.size);
    });
    return child;
  }
}

// ---------------------------------------------------------------------------------------------
// One-shot effects on the overlay
// ---------------------------------------------------------------------------------------------

mixin _OneShot<T extends StatefulWidget> on State<T>, SingleTickerProviderStateMixin<T> {
  late final AnimationController c;
  Duration get duration;
  VoidCallback get onDone;

  @override
  void initState() {
    super.initState();
    c = AnimationController(vsync: this, duration: duration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }
}

class _FloatText extends StatefulWidget {
  const _FloatText({super.key, required this.text, required this.at, required this.color, required this.size, required this.onDone});
  final String text;
  final Offset at;
  final Color color;
  final double size;
  final VoidCallback onDone;
  @override
  State<_FloatText> createState() => _FloatTextState();
}

class _FloatTextState extends State<_FloatText> with SingleTickerProviderStateMixin, _OneShot {
  @override
  Duration get duration => const Duration(milliseconds: 1100);
  @override
  VoidCallback get onDone => widget.onDone;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final v = c.value;
        final pop = v < 0.2 ? Curves.easeOutBack.transform(v / 0.2) : 1.0;
        return Positioned(
          left: widget.at.dx - 60,
          top: widget.at.dy - 20 - 46 * Curves.easeOut.transform(v),
          width: 120,
          child: Opacity(
            opacity: v < 0.7 ? 1 : (1 - (v - 0.7) / 0.3).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.4 + 0.6 * pop,
              child: Text(
                widget.text,
                textAlign: TextAlign.center,
                style: t.display(widget.size, weight: FontWeight.w900, color: widget.color).copyWith(shadows: const [Shadow(blurRadius: 6), Shadow(blurRadius: 2)]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Streak extends StatefulWidget {
  const _Streak({super.key, required this.from, required this.to, required this.color, required this.onDone});
  final Offset from, to;
  final Color color;
  final VoidCallback onDone;
  @override
  State<_Streak> createState() => _StreakState();
}

class _StreakState extends State<_Streak> with SingleTickerProviderStateMixin, _OneShot {
  @override
  Duration get duration => const Duration(milliseconds: 520);
  @override
  VoidCallback get onDone => widget.onDone;
  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: AnimatedBuilder(animation: c, builder: (context, _) => CustomPaint(painter: _StreakPainter(widget.from, widget.to, widget.color, c.value))),
      );
}

class _StreakPainter extends CustomPainter {
  _StreakPainter(this.a, this.b, this.color, this.v);
  final Offset a, b;
  final Color color;
  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    final head = Curves.easeIn.transform((v / 0.55).clamp(0, 1));
    final tail = Curves.easeIn.transform(((v - 0.25) / 0.45).clamp(0, 1));
    final p1 = Offset.lerp(a, b, tail)!, p2 = Offset.lerp(a, b, head)!;
    if (head > tail) {
      canvas.drawLine(p1, p2, Paint()
        ..color = color.withValues(alpha: 0.5)
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawLine(p1, p2, Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round);
    }
    if (v > 0.5) {
      final u = (v - 0.5) / 0.5;
      canvas.drawCircle(b, 10 + 40 * u, Paint()
        ..color = color.withValues(alpha: (1 - u) * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * (1 - u) + 1);
      canvas.drawCircle(b, 18 * (1 - u), Paint()..color = Colors.white.withValues(alpha: (1 - u) * 0.7));
    }
  }

  @override
  bool shouldRepaint(_StreakPainter old) => old.v != v;
}

class _Burst extends StatefulWidget {
  const _Burst({super.key, required this.rect, required this.color, required this.onDone});
  final Rect rect;
  final Color color;
  final VoidCallback onDone;
  @override
  State<_Burst> createState() => _BurstState();
}

class _BurstState extends State<_Burst> with SingleTickerProviderStateMixin, _OneShot {
  @override
  Duration get duration => const Duration(milliseconds: 700);
  @override
  VoidCallback get onDone => widget.onDone;
  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: AnimatedBuilder(animation: c, builder: (context, _) => CustomPaint(painter: _BurstPainter(widget.rect, widget.color, c.value))),
      );
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.r, this.color, this.v);
  final Rect r;
  final Color color;
  final double v;
  @override
  void paint(Canvas canvas, Size size) {
    final u = Curves.easeOut.transform(v);
    final rr = RRect.fromRectAndRadius(r.inflate(4 + 18 * u), Radius.circular(8 + 10 * u));
    canvas.drawRRect(rr, Paint()
      ..color = color.withValues(alpha: (1 - v) * 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * (1 - v) + 1
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    // Sparks rising off the card.
    final rng = math.Random(r.left.toInt() * 31 + r.top.toInt());
    final spark = Paint()..color = color.withValues(alpha: (1 - v) * 0.9);
    for (var i = 0; i < 14; i++) {
      final x = r.left + rng.nextDouble() * r.width;
      final y = r.bottom - rng.nextDouble() * r.height * 0.3 - u * (40 + rng.nextDouble() * 60);
      canvas.drawCircle(Offset(x, y), 1.5 + rng.nextDouble() * 2, spark);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.v != v;
}

class _Ghost extends StatefulWidget {
  const _Ghost({super.key, required this.def, required this.from, required this.to, required this.dying, required this.quiet, required this.onDone});
  final CardDef? def;
  final Rect from, to;
  final bool dying, quiet;
  final VoidCallback onDone;
  @override
  State<_Ghost> createState() => _GhostState();
}

class _GhostState extends State<_Ghost> with SingleTickerProviderStateMixin, _OneShot {
  @override
  Duration get duration => Duration(milliseconds: widget.dying ? 900 : 600);
  @override
  VoidCallback get onDone => widget.onDone;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final v = c.value;
        // The dead linger a beat, flash red and crumble; everything else just drifts away.
        final hold = widget.dying ? 0.3 : 0.0;
        final m = Curves.easeInCubic.transform(((v - hold) / (1 - hold)).clamp(0, 1));
        final r = Rect.lerp(widget.from, widget.to, m)!;
        final tint = widget.dying ? (v < hold ? v / hold : 1.0) : 0.0;
        return Positioned.fromRect(
          rect: r,
          child: Opacity(
            opacity: ((1 - m) * (widget.quiet ? 0.6 : 1)).clamp(0, 1),
            child: Transform.rotate(
              angle: (widget.dying ? 0.5 : 0.15) * m,
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(t.danger.withValues(alpha: 0.55 * tint), BlendMode.srcATop),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(r.width * 0.05),
                  child: widget.def == null ? ColoredBox(color: t.panel, child: const SizedBox.expand()) : CardPicture(def: widget.def, size: 'small'),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Spotlight extends StatefulWidget {
  const _Spotlight({super.key, required this.def, required this.onDone});
  final CardDef def;
  final VoidCallback onDone;
  @override
  State<_Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<_Spotlight> with SingleTickerProviderStateMixin, _OneShot {
  @override
  Duration get duration => const Duration(milliseconds: 1300);
  @override
  VoidCallback get onDone => widget.onDone;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return Positioned.fill(
      child: LayoutBuilder(builder: (context, box) {
        final w = math.min(box.maxWidth * 0.42, 230.0);
        return AnimatedBuilder(
          animation: c,
          builder: (context, _) {
            final v = c.value;
            final inn = Curves.easeOutBack.transform((v / 0.22).clamp(0, 1));
            final out = Curves.easeIn.transform(((v - 0.75) / 0.25).clamp(0, 1));
            return Opacity(
              opacity: (1 - out).clamp(0, 1),
              child: Center(
                child: Transform.translate(
                  offset: Offset(0, -40 * out),
                  child: Transform.scale(
                    scale: (0.5 + 0.5 * inn) * (1 - 0.4 * out),
                    child: Container(
                      width: w,
                      height: w * 88 / 63,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(w * 0.05),
                        boxShadow: [BoxShadow(color: t.accent3.withValues(alpha: 0.7), blurRadius: 30, spreadRadius: 4)],
                      ),
                      child: ClipRRect(borderRadius: BorderRadius.circular(w * 0.05), child: CardPicture(def: widget.def)),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

class _Banner extends StatefulWidget {
  const _Banner({super.key, required this.text, required this.sub, required this.color, required this.onDone});
  final String text, sub;
  final Color color;
  final VoidCallback onDone;
  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with SingleTickerProviderStateMixin, _OneShot {
  @override
  Duration get duration => const Duration(milliseconds: 1500);
  @override
  VoidCallback get onDone => widget.onDone;

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return Positioned.fill(
      child: LayoutBuilder(builder: (context, box) {
        return AnimatedBuilder(
          animation: c,
          builder: (context, _) {
            final v = c.value;
            final inn = Curves.easeOutCubic.transform((v / 0.25).clamp(0, 1));
            final out = Curves.easeInCubic.transform(((v - 0.72) / 0.28).clamp(0, 1));
            final x = (1 - inn) * -box.maxWidth + out * box.maxWidth;
            return Align(
              alignment: const Alignment(0, -0.1),
              child: Transform.translate(
                offset: Offset(x, 0),
                child: Container(
                  width: box.maxWidth,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.transparent, widget.color.withValues(alpha: 0.88), widget.color.withValues(alpha: 0.88), Colors.transparent], stops: const [0, 0.2, 0.8, 1]),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(widget.text, style: t.display(30, weight: FontWeight.w900, color: t.buttonText).copyWith(shadows: const [Shadow(blurRadius: 4, color: Colors.black45)])),
                    Text(t.label(widget.sub), style: t.style(13, weight: FontWeight.w700, color: t.buttonText.withValues(alpha: 0.85))),
                  ]),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
