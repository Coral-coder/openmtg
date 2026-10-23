/// The computer player: heuristic and deterministic (its only randomness is its own seeded
/// generator). It plays lands by color need, casts its best spells, attacks when it's safe or
/// lethal, blocks to trade well or survive, and aims removal at the biggest threat.
library;

import '../cards/card.dart';
import '../ir/ir.dart';
import '../game/actions.dart';
import '../game/chars.dart';
import '../game/game.dart';
import '../game/state.dart';
import '../util/rng.dart';

class Bot {
  Bot(this.player, {int seed = 1}) : _rng = SeededRng(seed);
  final PlayerId player;
  final SeededRng _rng;

  /// Actions that failed in the current priority window (so it doesn't retry them).
  final Set<String> _failed = {};
  int _window = -1;

  /// The next action this player should take in [g], or null if it isn't theirs to take.
  GameAction? next(Game g) {
    final s = g.state;
    if (s.over) return null;
    final pd = s.pending;
    if (pd != null) {
      if (pd.decision.player != player) return null;
      return AnswerAction(player, answer(g, pd.decision));
    }
    if (s.priority != player) return null;
    final window = s.turn * 1000 + s.step.index * 10 + s.stack.length;
    if (window != _window) {
      _window = window;
      _failed.clear();
    }
    final a = _choose(g);
    return a;
  }

  /// Applies this bot's next action to [g]. Returns false if it had nothing to do.
  bool step(Game g) {
    final a = next(g);
    if (a == null) return false;
    try {
      g.apply(a);
    } on GameError {
      _failed.add(a.toString());
      if (a is AnswerAction) {
        // Fall back to the first legal answer, then to backing out.
        final d = g.state.pending!.decision;
        try {
          g.apply(AnswerAction(player, g.defaultAnswer(d)));
        } on GameError {
          if (d.cancellable) {
            g.apply(CancelAction(player));
          } else {
            rethrow;
          }
        }
      } else {
        if (g.state.pending?.decision.cancellable == true) g.apply(CancelAction(player));
      }
    }
    return true;
  }

  // -------------------------------------------------------------------------------------------
  // Priority actions
  // -------------------------------------------------------------------------------------------

  GameAction _choose(Game g) {
    final s = g.state;
    final legal = g.legalActions(player).where((a) => !_failed.contains(a.toString())).toList();
    final myTurn = s.active == player;
    final main = s.step == Step.main1 || s.step == Step.main2;

    // Respond to an opponent's spell with a counterspell.
    if (s.stack.isNotEmpty && s.stack.last.controller != player) {
      for (final a in legal.whereType<CastAction>()) {
        final t = _text(g, a.id);
        if (t.contains('counter target')) return a;
      }
      return PassAction(player);
    }
    if (myTurn && main && s.stack.isEmpty) {
      final lands = legal.whereType<PlayLandAction>().toList();
      if (lands.isNotEmpty) return _bestLand(g, lands);
      final casts = legal.whereType<CastAction>().toList()..sort((a, b) => _castValue(g, b) - _castValue(g, a));
      for (final c in casts) {
        if (_worthCasting(g, c)) return c;
      }
      for (final a in legal.whereType<ActivateAction>()) {
        if (_worthActivating(g, a)) return a;
      }
    }
    // Combat tricks: pump a blocked or blocking creature of ours.
    if (s.step == Step.declareBlockers && s.stack.isEmpty) {
      for (final c in legal.whereType<CastAction>()) {
        final t = _text(g, c.id);
        if (RegExp(r'target creature (you control )?gets \+').hasMatch(t) && _hasCombatCreature(g)) return c;
      }
    }
    // At the opponent's end step, use instant-speed card draw and removal.
    if (!myTurn && s.step == Step.end && s.stack.isEmpty) {
      for (final c in legal.whereType<CastAction>()) {
        final t = _text(g, c.id);
        if (g.chars(c.id).isInstant && !t.contains('counter target') && !t.contains('gets +')) return c;
      }
    }
    return PassAction(player);
  }

  String _text(Game g, ObjId id) => g.chars(id).abilities.map((a) => a.text).join(' ').toLowerCase();

  bool _hasCombatCreature(Game g) {
    for (final id in g.state.battlefield) {
      final o = g.state.obj(id);
      if (g.chars(id).controller == player && (o.blocked || o.blocking.isNotEmpty)) return true;
    }
    return false;
  }

  GameAction _bestLand(Game g, List<PlayLandAction> lands) {
    // Prefer lands that make colors our hand needs and that enter untapped.
    final need = <String>{};
    for (final id in g.state.player(player).hand) {
      final c = g.chars(id);
      for (final s in c.manaCost?.symbols ?? const []) {
        need.add(s.text);
      }
    }
    int score(PlayLandAction a) {
      final c = g.chars(a.id);
      var v = 0;
      for (final ab in c.abilities) {
        if (ab is ManaAbility) {
          for (final t in ab.produce.possible) {
            if (need.contains('{${t.name}}')) v += 3;
          }
        }
        if (ab is ReplacementAbility && ab.replacement is EntersTapped) v -= 1;
      }
      return v;
    }

    lands.sort((a, b) => score(b) - score(a));
    return lands.first;
  }

  int _castValue(Game g, CastAction a) {
    final c = g.chars(a.id);
    var v = c.manaValue * 10;
    if (c.isCreature) v += 5;
    if (a.option >= 0) v -= 3;
    return v;
  }

  bool _worthCasting(Game g, CastAction a) {
    final c = g.chars(a.id);
    final t = _text(g, a.id);
    // Don't waste removal or tricks with nothing to hit.
    final oppCreatures = g.state.battlefield.where((id) => g.chars(id).controller != player && g.chars(id).isCreature).length;
    final myCreatures = g.state.battlefield.where((id) => g.chars(id).controller == player && g.chars(id).isCreature).length;
    if (t.contains('counter target')) return false;
    if (!c.isPermanentCard) {
      if ((t.contains('destroy target creature') || t.contains('damage to target creature') || t.contains('-2/-2')) && oppCreatures == 0) return false;
      if (RegExp(r'target creature( you control)? gets \+').hasMatch(t) || t.contains('gains indestructible') || t.contains('gains hexproof')) return false;
      if (t.contains('creatures you control get +') && myCreatures == 0) return false;
      if (t.contains('destroy all creatures') && myCreatures >= oppCreatures) return false;
    }
    return true;
  }

  bool _worthActivating(Game g, ActivateAction a) {
    final c = g.chars(a.id);
    final ab = c.abilities[a.index];
    if (ab is! ActivatedAbility) return false;
    if (ab.isEquip) {
      final eq = g.state.obj(a.id);
      return eq.attachedTo == null;
    }
    if (ab.isLoyalty) return (ab.cost.loyalty ?? 0) >= 0 || (g.state.obj(a.id).counters['loyalty'] ?? 0) + ab.cost.loyalty! > 0;
    for (final p in ab.cost.parts) {
      if (p is SacrificeCost) {
        if (!p.self) return false;
        // Food and similar: only when it helps.
        if (ab.text.toLowerCase().contains('gain') && g.state.player(player).life > 10) return false;
        if (c.isCreature) return false;
      }
      if (p is DiscardCost || p is PayLifeCost || p is ExileFromGraveyardCost || p is RemoveCountersCost || p is ReturnCost) return false;
    }
    // Repeatable mana sinks (Shivan Dragon's firebreathing) only once a turn.
    if (!ab.cost.tap && (g.state.obj(a.id).activations[ab.text] ?? 0) > 0) return false;
    return true;
  }

  // -------------------------------------------------------------------------------------------
  // Decisions
  // -------------------------------------------------------------------------------------------

  List<int> answer(Game g, Decision d) {
    switch (d.kind) {
      case DecisionKind.mulligan:
        final hand = g.state.player(player).hand;
        final lands = hand.where((id) => g.chars(id).isLand).length;
        final ok = (lands >= 2 && lands <= 5) || g.state.player(player).mulligans >= 2 || hand.length <= 5;
        return [ok ? 1 : 0];
      case DecisionKind.cards:
        return _chooseCards(g, d);
      case DecisionKind.targets:
        return _chooseTargets(g, d);
      case DecisionKind.modes:
        final opts = List.of(d.options);
        _rng.shuffle(opts);
        return (opts.take(d.min.clamp(1, d.max)).toList()..sort());
      case DecisionKind.number:
        return [d.max];
      case DecisionKind.yesNo:
        if (d.prompt.startsWith('Pay kicker')) return [_canKick(g, d) ? 1 : 0];
        return const [1];
      case DecisionKind.option:
        if (d.prompt.contains('pay to avoid')) return [d.labels.length > 1 ? 1 : 0];
        if (d.prompt.contains('top or bottom')) {
          final src = d.source;
          final mine = src != null && g.state.objOrNull(src)?.owner == player;
          return [mine ? 0 : 1];
        }
        return const [0];
      case DecisionKind.order:
        return List.of(d.options);
      case DecisionKind.payMana:
        return const [];
      case DecisionKind.attackers:
        return _attack(g, d);
      case DecisionKind.blockers:
        return _block(g, d);
      case DecisionKind.damage || DecisionKind.divide:
        return const [];
    }
  }

  bool _canKick(Game g, Decision d) {
    final src = d.source;
    if (src == null) return false;
    final c = g.chars(src);
    final kicker = c.abilities.whereType<CastOptionAbility>().where((a) => a.option.kind == CastKind.kicker).firstOrNull;
    if (kicker == null || c.manaCost == null) return false;
    return g.canAfford(player, c.manaCost! + kicker.option.cost!);
  }

  int value(Game g, ObjId id) {
    final c = g.chars(id);
    var v = c.manaValue * 2;
    if (c.isCreature) v += (c.power ?? 0) * 3 + (c.toughness ?? 0) * 2;
    if (c.isPlaneswalker) v += 12 + (c.loyalty ?? 0);
    v += c.keywords.length * 2;
    if (c.isLand) v -= 4;
    if (g.state.obj(id).isToken) v -= 1;
    return v;
  }

  List<int> _chooseCards(Game g, Decision d) {
    final opts = List.of(d.options);
    final p = d.prompt.toLowerCase();
    // Things we lose: least valuable first. Things we get: most valuable first.
    final losing = p.contains('discard') || p.contains('sacrifice') || p.contains('bottom') || p.contains('exile') || p.contains('graveyard') || p.contains('tap ') || p.contains('remove');
    int v(int id) {
      if (p.contains('bottom of your library') && !p.contains('scry')) {
        // Opening hand: keep lands we need.
        final c = g.chars(id);
        final lands = opts.where((x) => g.chars(x).isLand).length;
        return c.isLand ? (lands > 3 ? 1 : 50) : 30 - c.manaValue;
      }
      return value(g, id);
    }

    if (p.startsWith('scry') || p.startsWith('surveil')) {
      // Bottom/bin lands when we have enough, keep spells.
      final lands = g.state.battlefield.where((x) => g.chars(x).controller == player && g.chars(x).isLand).length;
      return [for (final id in opts) if (g.chars(id).isLand == (lands >= 5)) id].take(d.max).toList();
    }
    if (p.contains('legend rule')) {
      opts.sort((a, b) => v(b) - v(a));
      return opts.take(1).toList();
    }
    if (p.contains('face-down pile')) return opts.take(opts.length ~/ 2).toList();
    opts.sort((a, b) => losing ? v(a) - v(b) : v(b) - v(a));
    final n = losing ? d.min : d.max;
    return opts.take(n.clamp(d.min, d.max)).toList();
  }

  bool _harmful(Game g, Decision d) {
    final src = d.source;
    var text = '';
    final st = g.state.stack.isNotEmpty ? g.state.stack.last : null;
    if (st != null && (st.objId == src || st.sourceId == src)) text = st.ability?.text.toLowerCase() ?? '';
    if (text.isEmpty && src != null && g.state.objOrNull(src) != null) text = g.chars(src).abilities.map((a) => a.text).join(' ').toLowerCase();
    final m = RegExp(r'(destroy|damage|exile|-\d|tap target|return target|counter target|fight|can.t block|discards|loses|sacrifice|its owner|gain control)').hasMatch(text);
    final good = RegExp(r'(gets \+|gains|put (a|an|two|three) \+1/\+1|untap|you control)').hasMatch(text);
    if (m && !good) return true;
    if (good && !m) return false;
    return d.prompt.contains('opponent') || d.prompt.contains("don't control");
  }

  List<int> _chooseTargets(Game g, Decision d) {
    final harmful = _harmful(g, d);
    final opts = List.of(d.options);
    int score(int e) {
      if (isPlayerEntity(e)) {
        final p = entityPlayer(e);
        return harmful ? (p == player ? -100 : 20) : (p == player ? 20 : -100);
      }
      final c = g.chars(e);
      final mine = c.controller == player;
      final v = value(g, e);
      return harmful ? (mine ? -v - 50 : v) : (mine ? v : -v - 50);
    }

    opts.sort((a, b) => score(b) - score(a));
    final good = opts.where((e) => score(e) > -50).toList();
    final n = d.max == 1 ? 1 : (good.length.clamp(d.min, d.max));
    final pick = (good.length >= d.min ? good : opts).take(n.clamp(d.min, d.max)).toList();
    return pick;
  }

  List<int> _attack(Game g, Decision d) {
    final s = g.state;
    final opp = s.opponents(player);
    if (opp.isEmpty) return const [];
    final target = playerEntity(opp.first);
    final blockers = [for (final id in s.battlefield) if (g.chars(id).controller == opp.first && g.chars(id).isCreature && !s.obj(id).tapped) id];
    final oppLife = s.player(opp.first).life;
    final must = (d.extra['must'] as List?)?.cast<int>() ?? const <int>[];
    final out = <int>[];
    var totalPower = 0;
    for (final id in d.options) {
      totalPower += g.chars(id).power ?? 0;
    }
    final lethal = totalPower >= oppLife && blockers.isEmpty;
    for (final id in d.options) {
      final c = g.chars(id);
      if ((c.power ?? 0) <= 0 && !must.contains(id)) continue;
      var safe = true;
      for (final b in blockers) {
        if (!g.canBlock(b, id)) continue;
        final bc = g.chars(b);
        final kills = (bc.power ?? 0) >= (c.toughness ?? 0) || bc.has(Kw.deathtouch);
        final dies = (c.power ?? 0) >= (bc.toughness ?? 0) || c.has(Kw.deathtouch);
        if (kills && !(dies && value(g, b) >= value(g, id))) {
          safe = false;
          break;
        }
      }
      if (safe || lethal || must.contains(id)) {
        out
          ..add(id)
          ..add(target);
      }
    }
    return out;
  }

  List<int> _block(Game g, Decision d) {
    final s = g.state;
    final out = <int>[];
    final used = <int>{};
    final attackers = <int>{for (final id in d.options) ...((d.extra['$id'] as List).cast<int>())}.toList();
    var incoming = 0;
    for (final a in attackers) {
      incoming += g.chars(a).power ?? 0;
    }
    final life = s.player(player).life;
    attackers.sort((a, b) => (g.chars(b).power ?? 0) - (g.chars(a).power ?? 0));
    for (final a in attackers) {
      final ac = g.chars(a);
      final can = [for (final b in d.options) if (!used.contains(b) && (d.extra['$b'] as List).contains(a)) b];
      if (can.isEmpty) continue;
      if (ac.has(Kw.menace)) continue;
      // A blocker that kills it and survives, or trades up.
      int? best;
      for (final b in can) {
        final bc = g.chars(b);
        final kills = (bc.power ?? 0) >= (ac.toughness ?? 0) || bc.has(Kw.deathtouch);
        final survives = (ac.power ?? 0) < (bc.toughness ?? 0) && !ac.has(Kw.deathtouch);
        if (survives || (kills && value(g, b) <= value(g, a))) {
          best = b;
          if (survives && kills) break;
        }
      }
      // Chump when the damage would be lethal.
      if (best == null && incoming >= life) {
        can.sort((x, y) => value(g, x) - value(g, y));
        best = can.first;
      }
      if (best != null) {
        used.add(best);
        incoming -= ac.power ?? 0;
        out
          ..add(best)
          ..add(a);
      }
    }
    return out;
  }
}

/// Plays a game to the end with bots in every seat. Returns false if it hit [maxActions].
bool runBots(Game g, List<Bot> bots, {int maxActions = 5000}) {
  for (var i = 0; i < maxActions; i++) {
    if (g.state.over) return true;
    var acted = false;
    for (final b in bots) {
      if (b.step(g)) {
        acted = true;
        break;
      }
    }
    if (!acted) throw StateError('No bot could act (priority ${g.state.priority}, pending ${g.state.pending?.decision.prompt})');
  }
  return g.state.over;
}

/// A typed alias so callers needn't import chars.dart for [Bot.value].
typedef BotChars = Chars;
