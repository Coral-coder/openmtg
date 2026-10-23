/// The game: applies actions to the state by the Comprehensive Rules. Deterministic: the same
/// seed and actions give the same [GameState.digest] on every device.
///
/// Turn structure (CR 500–514) and priority (CR 117) live here; casting (601–602), effects
/// (608, 700–701), triggers (603), state-based actions (704), combat (506–511), layers (613) and
/// replacement effects (614–616) are in the part files.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../cards/card.dart';
import '../cards/card_db.dart';
import '../cards/mana.dart';
import '../ir/ir.dart';
import '../oracle/parser.dart';
import 'actions.dart';
import 'chars.dart';
import 'state.dart';
import '../util/sort.dart';

part 'layers.dart';
part 'query.dart';
part 'cast.dart';
part 'effects.dart';
part 'events.dart';
part 'combat.dart';
part 'sba.dart';
part 'shields.dart';
part 'more_effects.dart';
part 'testing.dart';

/// Answers for the decisions of one task run; throws [NeedDecision] when they run out.
class _Choices {
  _Choices(this.answers, {this.auto = false});
  final List<List<int>> answers;
  int next = 0;

  /// Probing legality: answer every decision with its first legal option.
  final bool auto;
}

class Game {
  Game(this.db, {required List<String> players, required int seed}) : state = GameState(seed: seed, names: players);

  final CardDatabase db;
  GameState state;

  /// Every action applied so far (the replay log).
  final List<GameAction> actions = [];

  _Choices? _choices;

  // Characteristics cache (layers.dart), valid while state.version doesn't change.
  Map<ObjId, Chars> _charCache = {};
  int _charVersion = -1;
  GameState? _charState;
  bool _computing = false;
  Map<ObjId, Chars> _passChars = {};

  /// Fingerprint of the state, for lockstep comparison.
  String get fingerprint => sha256.convert(utf8.encode(state.digest())).toString().substring(0, 24);

  // -------------------------------------------------------------------------------------------
  // Applying actions
  // -------------------------------------------------------------------------------------------

  /// Applies [a]; throws [GameError] if it isn't legal now.
  void apply(GameAction a) {
    if (state.over && a is! ConcedeAction) throw GameError('The game is over');
    switch (a) {
      case StartAction():
        if (state.started) throw GameError('Already started');
        _start(a);
      case AnswerAction():
        final pd = state.pending;
        if (pd == null) throw GameError('Nothing to answer');
        if (pd.decision.player != a.player) throw GameError('Not your decision');
        _validateAnswer(pd.decision, a.answer);
        final partial = state;
        state = pd.snapshot.clone();
        try {
          _run(pd.task, [...pd.answers, a.answer]);
        } on GameError {
          state = partial;
          rethrow;
        }
      case CancelAction():
        final pd = state.pending;
        if (pd == null || !pd.decision.cancellable || pd.decision.player != a.player) throw GameError('Nothing to cancel');
        state = pd.snapshot.clone();
        state.pending = null;
      case ConcedeAction():
        _concede(a.player);
      case StopsAction():
        state.player(a.player).stops = a.stops;
      case PassTurnAction():
        _requireNoPending();
        state.player(a.player).stops.passUntilTurnEnds = state.turn;
        if (state.priority == a.player) _pass(a.player);
      case PassAction():
        _requirePriority(a.player);
        _pass(a.player);
      case PlayLandAction():
        _requirePriority(a.player);
        _playLand(a.player, a.id, a.face);
      case CastAction():
        _requirePriority(a.player);
        _run(CastTask(a.player, a.id, face: a.face, option: a.option));
      case ActivateAbilityAction():
        _requirePriority(a.player);
        _run(ActivateTask(a.player, a.id, a.index));
      case ManaAction():
        _requirePriority(a.player);
        _activateManaAbility(a.player, a.id, a.index, a.type);
    }
    actions.add(a);
    _advance();
  }

  void _requireNoPending() {
    if (state.pending != null) throw GameError('A decision is pending');
  }

  void _requirePriority(PlayerId p) {
    _requireNoPending();
    if (!state.inProgress) throw GameError('The game has not begun');
    if (state.priority != p) throw GameError('${state.player(p).name} does not have priority');
  }

  /// Runs [t] from the current state with [answers]; parks it if it needs another decision.
  void _run(Task t, [List<List<int>> answers = const []]) {
    final snap = state.clone();
    final prev = _choices;
    _choices = _Choices(answers);
    try {
      _execTask(t);
      state.pending = null;
    } on NeedDecision catch (d) {
      state.pending = Pending(t, answers, d.decision, snap);
    } on GameError {
      state = snap;
      rethrow;
    } finally {
      _choices = prev;
    }
  }

  void _execTask(Task t) {
    switch (t) {
      case CastTask():
        _castSpell(t.player, t.obj, t.face, t.option);
        _afterPlayerAction(t.player);
      case ActivateTask():
        _activate(t.player, t.obj, t.ability);
        _afterPlayerAction(t.player);
      case ResolveTask():
        _resolveTop();
      case TriggersTask():
        _putTriggersOnStack();
      case AttackTask():
        _declareAttackers();
        state.stepDone = true;
      case BlockTask():
        _declareBlockers();
        state.stepDone = true;
      case DamageTask():
        _combatDamage(t.firstStrike);
        state.stepDone = true;
      case CleanupTask():
        _cleanup();
      case MulliganTask():
        _mulligans();
      case SbaTask():
        _legendRule();
      case StepTask():
        break;
    }
  }

  /// Asks the pending decision's player, or returns the recorded answer.
  List<int> ask(Decision d) {
    // Forced choices aren't asked.
    if ((d.kind == DecisionKind.targets || d.kind == DecisionKind.cards) && d.options.length == d.min && d.min == d.max) return List.of(d.options);
    if ((d.kind == DecisionKind.targets || d.kind == DecisionKind.cards) && d.max == 0) return const [];
    if (d.kind == DecisionKind.option && d.labels.length == 1) return const [0];
    if (d.kind == DecisionKind.order && d.options.length <= 1) return List.of(d.options);
    final c = _choices;
    if (c == null) throw StateError('Decision outside a task: ${d.prompt}');
    if (c.next < c.answers.length) return c.answers[c.next++];
    if (c.auto) return defaultAnswer(d);
    throw NeedDecision(d);
  }

  void _validateAnswer(Decision d, List<int> a) {
    switch (d.kind) {
      case DecisionKind.targets || DecisionKind.cards:
        if (a.length < d.min || a.length > d.max) throw GameError('Choose ${d.min == d.max ? d.min : '${d.min}–${d.max}'}');
        if (a.toSet().length != a.length) throw GameError('Duplicate choice');
        for (final x in a) {
          if (!d.options.contains(x)) throw GameError('Not a legal choice');
        }
      case DecisionKind.modes:
        if (a.length < d.min || a.length > d.max || a.toSet().length != a.length) throw GameError('Choose ${d.min}–${d.max} modes');
        for (final x in a) {
          if (!d.options.contains(x)) throw GameError('Not a legal mode');
        }
      case DecisionKind.number:
        if (a.length != 1 || a.first < d.min || a.first > d.max) throw GameError('Choose a number from ${d.min} to ${d.max}');
      case DecisionKind.yesNo || DecisionKind.mulligan:
        if (a.length != 1 || (a.first != 0 && a.first != 1)) throw GameError('Answer yes or no');
      case DecisionKind.option:
        if (a.length != 1 || a.first < 0 || a.first >= d.labels.length) throw GameError('Pick an option');
      case DecisionKind.order:
        if (a.length != d.options.length || !a.toSet().containsAll(d.options)) throw GameError('Order all of them');
      case DecisionKind.attackers || DecisionKind.blockers || DecisionKind.damage || DecisionKind.divide || DecisionKind.payMana:
        if (a.length.isOdd && d.kind != DecisionKind.payMana) throw GameError('Malformed answer');
    }
  }

  void _afterPlayerAction(PlayerId p) {
    state.passes = 0;
    state.priority = p;
  }

  // -------------------------------------------------------------------------------------------
  // Starting the game (CR 103)
  // -------------------------------------------------------------------------------------------

  void _start(StartAction a) {
    if (a.decks.length != state.players.length) throw GameError('One deck per player');
    state.rules = a.rules;
    state.started = true;
    for (var p = 0; p < a.decks.length; p++) {
      final pl = state.player(p);
      pl.life = a.rules.startingLife;
      pl.startingLife = a.rules.startingLife;
      for (final name in a.decks[p]) {
        final def = db[name];
        if (def == null) throw GameError('Unknown card $name');
        final o = GameObject(id: state.nextId++, cardName: def.name, owner: p, zone: Zone.library);
        state.objects[o.id] = o;
        pl.library.add(o.id);
      }
      state.rng.shuffle(pl.library);
    }
    state.active = state.rng.nextInt(state.players.length);
    state.firstPlayer = state.active;
    for (final p in state.playerIds) {
      _drawN(p, a.rules.handSize, silent: true);
    }
    _log('${state.player(state.active).name} goes first.');
    _dirty();
  }

  void _mulligans() {
    final rules = state.rules;
    final order = state.apnap(state.firstPlayer);
    var guard = 0;
    while (order.any((p) => !state.player(p).kept)) {
      if (guard++ > 200) throw StateError('mulligan loop');
      for (final p in order) {
        final pl = state.player(p);
        if (pl.kept) continue;
        final handSize = rules.londonMulligan ? rules.handSize : rules.handSize - _chargedMulligans(pl);
        if (pl.hand.isEmpty || handSize <= 0) {
          pl.kept = true;
          continue;
        }
        final keep = ask(Decision(kind: DecisionKind.mulligan, player: p, prompt: pl.mulligans == 0 ? 'Keep this hand?' : 'Keep this hand? (mulligan ${pl.mulligans})', labels: const ['Mulligan', 'Keep']));
        if (keep.first == 1) {
          pl.kept = true;
        } else {
          pl.mulligans++;
          for (final id in List.of(pl.hand)) {
            _moveTo(id, Zone.library);
          }
          state.rng.shuffle(pl.library);
          final n = rules.londonMulligan ? rules.handSize : rules.handSize - _chargedMulligans(pl);
          _drawN(p, n, silent: true);
          _log('${pl.name} mulligans.');
        }
      }
    }
    // London mulligan: put one card per (charged) mulligan on the bottom.
    if (rules.londonMulligan) {
      for (final p in order) {
        final pl = state.player(p);
        final n = _chargedMulligans(pl);
        if (n <= 0) continue;
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Put $n card${n == 1 ? '' : 's'} on the bottom of your library', options: List.of(pl.hand), min: n, max: n));
        for (final id in pick) {
          _moveTo(id, Zone.library, bottom: true);
        }
      }
    }
    // Leyline-style "begin the game with it on the battlefield".
    for (final p in order) {
      final pl = state.player(p);
      for (final id in List.of(pl.hand)) {
        final o = state.obj(id);
        final def = db[o.cardName];
        if (def == null) continue;
        final abs = OracleParser.parse(def).faces.first.abilities;
        if (abs.any((a) => a is InfoAbility && a.openingHandBattlefield)) {
          final y = ask(Decision(kind: DecisionKind.yesNo, player: p, prompt: 'Begin the game with ${def.name} on the battlefield?', source: id, labels: const ['No', 'Yes']));
          if (y.first == 1) _putOntoBattlefield(id, p);
        }
      }
    }
    state.inProgress = true;
    state.turn = 1;
    _beginTurn(state.firstPlayer);
  }

  int _chargedMulligans(Player pl) => (pl.mulligans - (state.rules.freeMulligan ? 1 : 0)).clamp(0, 99);

  // -------------------------------------------------------------------------------------------
  // The loop: state-based actions, triggers, turn steps, priority
  // -------------------------------------------------------------------------------------------

  void _advance() {
    for (var guard = 0; guard < 20000; guard++) {
      if (state.over || state.pending != null || !state.started) return;
      if (!state.inProgress) {
        _run(const MulliganTask());
        continue;
      }
      if (_stateBasedActions()) continue;
      if (state.pending != null) return;
      if (state.pendingTriggers.isNotEmpty) {
        _run(const TriggersTask());
        continue;
      }
      final p = state.priority;
      if (p == null) {
        if (!state.stepDone) {
          _turnBasedActions();
          continue;
        }
        if (_stepHasPriority()) {
          _givePriority(state.active);
          continue;
        }
        _nextStep();
        continue;
      }
      if (_autoPass(p)) {
        _pass(p);
        continue;
      }
      return;
    }
    throw StateError('The game loop did not settle');
  }

  bool _stepHasPriority() => state.step != TurnStep.untap && !(state.step == TurnStep.cleanup && !state.cleanupPriority);

  void _givePriority(PlayerId p) {
    state.priority = p;
    state.passes = 0;
  }

  void _pass(PlayerId p) {
    state.passes++;
    final alive = state.apnap();
    if (state.passes >= alive.length) {
      state.passes = 0;
      if (state.stack.isNotEmpty) {
        state.priority = null;
        _run(const ResolveTask());
        if (state.pending == null && !state.over) _givePriority(state.active);
      } else {
        state.priority = null;
        _nextStep();
      }
      return;
    }
    // Next player in turn order who is still in the game.
    var q = p;
    for (var i = 0; i < state.players.length; i++) {
      q = (q + 1) % state.players.length;
      if (!state.player(q).lost) break;
    }
    state.priority = q;
  }

  void _turnBasedActions() {
    switch (state.step) {
      case TurnStep.untap:
        _untapStep();
        state.stepDone = true;
      case TurnStep.draw:
        final skip = state.turn == 1 && state.active == state.firstPlayer && !state.rules.firstPlayerDraws;
        if (!skip) _drawN(state.active, 1);
        state.stepDone = true;
      case TurnStep.declareAttackers:
        _run(const AttackTask());
      case TurnStep.declareBlockers:
        _run(BlockTask(state.active));
      case TurnStep.firstStrikeDamage:
        _run(const DamageTask(true));
      case TurnStep.combatDamage:
        _run(const DamageTask(false));
      case TurnStep.cleanup:
        _run(const CleanupTask());
      default:
        state.stepDone = true;
    }
  }

  void _beginStep(TurnStep s) {
    state.step = s;
    state.stepDone = false;
    state.priority = null;
    state.passes = 0;
    state.cleanupPriority = false;
    _emit(StepEvent(s, state.active));
  }

  void _nextStep() {
    for (final pl in state.players) {
      pl.pool.removeWhere((m) => !m.keep);
    }
    final s = state.step;
    switch (s) {
      case TurnStep.untap:
        _beginStep(TurnStep.upkeep);
      case TurnStep.upkeep:
        _beginStep(TurnStep.draw);
      case TurnStep.draw:
        _beginStep(TurnStep.main1);
      case TurnStep.main1:
        _beginStep(TurnStep.beginCombat);
      case TurnStep.beginCombat:
        _beginStep(TurnStep.declareAttackers);
      case TurnStep.declareAttackers:
        if (_attackers().isEmpty) {
          _beginStep(TurnStep.endCombat);
        } else {
          _beginStep(TurnStep.declareBlockers);
        }
      case TurnStep.declareBlockers:
        state.combatHasFirstStrike = _combatants().any((id) {
          final c = chars(id);
          return c.has(Kw.firstStrike) || c.has(Kw.doubleStrike);
        });
        _beginStep(state.combatHasFirstStrike ? TurnStep.firstStrikeDamage : TurnStep.combatDamage);
      case TurnStep.firstStrikeDamage:
        _beginStep(TurnStep.combatDamage);
      case TurnStep.combatDamage:
        _beginStep(TurnStep.endCombat);
      case TurnStep.endCombat:
        _endCombat();
        _beginStep(TurnStep.main2);
      case TurnStep.main2:
        _beginStep(TurnStep.end);
      case TurnStep.end:
        _beginStep(TurnStep.cleanup);
      case TurnStep.cleanup:
        if (state.cleanupPriority) {
          // Another cleanup step follows (CR 514.3a).
          _beginStep(TurnStep.cleanup);
          return;
        }
        _endTurn();
    }
  }

  void _beginTurn(PlayerId p) {
    state.active = p;
    for (final pl in state.players) {
      pl.stats = TurnStats();
      if (pl.stops.passUntilTurnEnds < state.turn) pl.stops.passUntilTurnEnds = -1;
    }
    state.creaturesDiedThisTurn = 0;
    for (final o in state.objects.values) {
      o.activations = {};
      o.damagedBy = [];
    }
    // "Until your next turn" effects end (CR 611.2b).
    state.effects.removeWhere((e) => e.duration == EffectDuration.untilYourNextTurn && e.controller == p);
    for (final id in state.battlefield) {
      final o = state.obj(id);
      if (o.controller == p) o.controlSince = o.controlSince; // summoning sickness is checked against controlSince < turn
    }
    _log('Turn ${state.turn}: ${state.player(p).name}.', kind: 'turn');
    _beginStep(TurnStep.untap);
  }

  void _endTurn() {
    state.turn++;
    final next = state.extraTurns.isNotEmpty ? state.extraTurns.removeLast() : _nextPlayer(state.active);
    _beginTurn(next);
  }

  PlayerId _nextPlayer(PlayerId p) {
    var q = p;
    for (var i = 0; i < state.players.length; i++) {
      q = (q + 1) % state.players.length;
      if (!state.player(q).lost) return q;
    }
    return p;
  }

  void _untapStep() {
    final p = state.active;
    for (final id in List.of(state.battlefield)) {
      final o = state.obj(id);
      if (o.controller != p) continue;
      o.phasedOut = false;
      if (o.skipUntap > 0) {
        o.skipUntap--;
        continue;
      }
      if (!o.tapped) continue;
      final c = chars(id);
      if (c.has(Kw.doesntUntap)) continue;
      _untap(id);
    }
    _dirty();
  }

  /// Cleanup (CR 514): discard to hand size, damage wears off, "until end of turn" ends.
  void _cleanup() {
    final p = state.active;
    final pl = state.player(p);
    final max = state.rules.maxHandSize && !_hasRule<NoMaxHandSize>(p) ? state.rules.handSize : 1 << 30;
    if (pl.hand.length > max) {
      final n = pl.hand.length - max;
      final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Discard $n card${n == 1 ? '' : 's'} (hand size)', options: List.of(pl.hand), min: n, max: n));
      for (final id in pick) {
        _discard(p, id);
      }
    }
    for (final id in state.battlefield) {
      final o = state.obj(id);
      o.damage = 0;
      o.deathtouched = false;
    }
    state.shields.clear();
    state.effects.removeWhere((e) => e.duration == EffectDuration.endOfTurn || e.duration == EffectDuration.thisTurn);
    for (final o in state.objects.values) {
      if (o.playableBy != null && o.playableUntil <= state.turn && o.playableUntil >= 0) {
        o.playableBy = null;
      }
    }
    _dirty();
    state.stepDone = true;
    // If anything triggered or SBAs apply, players get priority and cleanup repeats.
    if (state.pendingTriggers.isNotEmpty || _sbaWouldApply()) state.cleanupPriority = true;
  }

  // -------------------------------------------------------------------------------------------
  // Automatic passing (deterministic: depends only on the state)
  // -------------------------------------------------------------------------------------------

  bool _autoPass(PlayerId p) {
    final pl = state.player(p);
    final st = pl.stops;
    final myTurn = p == state.active;
    if (state.stack.isNotEmpty) {
      final top = state.stack.last;
      if (top.controller == p) return true; // let your own spells resolve
      if (!st.respond) return true;
      return !_canAct(p, instantSpeedOnly: true);
    }
    if (st.passUntilTurnEnds == state.turn) return true;
    final stops = myTurn ? st.mine : st.theirs;
    if (!stops.contains(state.step)) return true;
    if (state.rules.autoPassWhenNothingToDo && !_canAct(p, instantSpeedOnly: false)) return true;
    return false;
  }

  /// Whether [p] has anything they could do now besides passing.
  bool _canAct(PlayerId p, {required bool instantSpeedOnly}) => legalActions(p).any((a) => a is! PassAction && a is! ManaAction && a is! PassTurnAction);

  // -------------------------------------------------------------------------------------------
  // Leaving the game
  // -------------------------------------------------------------------------------------------

  void _concede(PlayerId p) {
    final pl = state.player(p);
    if (pl.lost) return;
    final pd = state.pending;
    if (pd != null && pd.decision.player == p) {
      state = pd.snapshot.clone();
      state.pending = null;
    }
    _lose(p, 'conceded');
  }

  void _lose(PlayerId p, String why) {
    final pl = state.player(p);
    if (pl.lost) return;
    pl.lost = true;
    pl.lossReason = why;
    _log('${pl.name} loses ($why).', player: p, kind: 'lose');
    // CR 800.4a: their objects leave the game.
    for (final id in List.of(state.battlefield)) {
      final o = state.obj(id);
      if (o.owner == p) {
        state.battlefield.remove(id);
        o.zone = Zone.none;
      } else if (o.controller == p) {
        o.controller = o.owner;
      }
    }
    state.stack.removeWhere((i) => i.controller == p);
    final alive = state.apnap();
    if (alive.length <= 1) {
      state.over = true;
      state.winner = alive.isEmpty ? null : alive.first;
      if (state.winner != null) state.player(state.winner!).won = true;
      state.priority = null;
    } else {
      if (state.priority == p) state.priority = _nextPlayer(p);
      if (state.active == p) {
        state.stack.clear();
        _endTurn();
      }
    }
    _dirty();
  }

  // -------------------------------------------------------------------------------------------
  // Basic game operations used everywhere
  // -------------------------------------------------------------------------------------------

  void _dirty() => state.version++;

  void _log(String text, {PlayerId? player, ObjId? obj, String kind = 'info'}) {
    state.log.add(LogEntry(text, player: player, obj: obj, kind: kind));
    if (state.log.length > 400) state.log.removeRange(0, state.log.length - 400);
  }

  String nameOf(ObjId id) {
    final o = state.objOrNull(id);
    if (o == null) return '?';
    if (o.faceDown) return 'a face-down card';
    return o.zone == Zone.battlefield || o.zone == Zone.stack ? chars(id).name : o.cardName;
  }

  /// Draws [n] cards; drawing from an empty library loses at the next SBA check (CR 704.5b).
  void _drawN(PlayerId p, int n, {bool silent = false}) {
    for (var i = 0; i < n; i++) {
      final pl = state.player(p);
      if (pl.library.isEmpty) {
        pl.drewFromEmpty = true;
        continue;
      }
      final id = pl.library.first;
      _moveTo(id, Zone.hand);
      pl.stats.cardsDrawn++;
      if (!silent) _emit(DrawEvent(p, pl.stats.cardsDrawn, id));
    }
    if (!silent && n > 0) _log('${state.player(p).name} draws ${n == 1 ? 'a card' : '$n cards'}.', player: p);
  }

  void _discard(PlayerId p, ObjId id) {
    _log('${state.player(p).name} discards ${nameOf(id)}.', player: p, obj: id);
    _move(id, Zone.graveyard);
    _emit(DiscardEvent(p, id));
  }

  void _gainLife(PlayerId p, int n) {
    if (n <= 0) return;
    final pl = state.player(p);
    pl.life += n;
    pl.stats.lifeGained += n;
    pl.stats.gainLifeEvents++;
    _emit(LifeEvent(p, n, gain: true, nth: pl.stats.gainLifeEvents));
    _dirty();
  }

  void _loseLife(PlayerId p, int n) {
    if (n <= 0) return;
    final pl = state.player(p);
    pl.life -= n;
    pl.stats.lifeLost += n;
    _emit(LifeEvent(p, n, gain: false));
    _dirty();
  }

  void _tap(ObjId id) {
    final o = state.obj(id);
    if (o.tapped) return;
    o.tapped = true;
    _dirty();
  }

  void _untap(ObjId id) {
    final o = state.obj(id);
    if (!o.tapped) return;
    if ((o.counters['stun'] ?? 0) > 0) {
      o.counters['stun'] = o.counters['stun']! - 1;
      _dirty();
      return;
    }
    o.tapped = false;
    _emit(UntapEvent(id));
    _dirty();
  }

  /// Puts counters on a permanent, through replacement effects (Doubling Season).
  void _addCounters(ObjId id, String kind, int n, {PlayerId? by}) {
    if (n <= 0) return;
    final o = state.obj(id);
    var amount = n;
    for (final r in _replacements<DoubleCountersReplacement>()) {
      if (r.$2 == o.controller) amount *= 2;
    }
    o.counters[kind] = (o.counters[kind] ?? 0) + amount;
    _emit(CountersEvent(id, kind, amount, by ?? o.controller));
    _dirty();
  }

  void _removeCounters(ObjId id, String kind, int n) {
    final o = state.obj(id);
    final have = o.counters[kind] ?? 0;
    o.counters[kind] = (have - n).clamp(0, 1 << 30);
    if (o.counters[kind] == 0) o.counters.remove(kind);
    _dirty();
  }

  /// Moves an object to [to], resetting it as a new object (CR 400.7). Returns its id.
  ObjId _moveTo(ObjId id, Zone to, {bool bottom = false, PlayerId? controller, int? libraryIndex}) {
    final o = state.obj(id);
    final from = o.zone;
    _removeFromZone(o);
    if (from != to || from == Zone.library) o.resetForNewZone();
    o.zone = to;
    o.controller = controller ?? o.owner;
    o.arrivedTurn = state.turn;
    final pl = state.player(o.owner);
    switch (to) {
      case Zone.library:
        if (libraryIndex != null) {
          pl.library.insert(libraryIndex.clamp(0, pl.library.length), id);
        } else if (bottom) {
          pl.library.add(id);
        } else {
          pl.library.insert(0, id);
        }
      case Zone.hand:
        pl.hand.add(id);
      case Zone.graveyard:
        pl.graveyard.add(id);
      case Zone.exile:
        pl.exile.add(id);
      case Zone.battlefield:
        state.battlefield.add(id);
        o.timestamp = state.nextTimestamp++;
        o.controlSince = state.turn;
        o.enteredTurn = state.turn;
      case Zone.command:
        state.command.add(id);
      case Zone.stack || Zone.none:
        break;
    }
    _dirty();
    return id;
  }

  void _removeFromZone(GameObject o) {
    final pl = state.player(o.owner);
    switch (o.zone) {
      case Zone.library:
        pl.library.remove(o.id);
      case Zone.hand:
        pl.hand.remove(o.id);
      case Zone.graveyard:
        pl.graveyard.remove(o.id);
      case Zone.exile:
        pl.exile.remove(o.id);
      case Zone.battlefield:
        state.battlefield.remove(o.id);
        // Leaving the battlefield: attachments fall off, things attached to it become unattached.
        for (final other in state.battlefield) {
          final x = state.obj(other);
          if (x.attachedTo == o.id) {
            x.attachedTo = null;
            x.lastAttached = o.id;
          }
        }
      case Zone.command:
        state.command.remove(o.id);
      case Zone.stack || Zone.none:
        break;
    }
  }

  void _shuffle(PlayerId p) {
    state.rng.shuffle(state.player(p).library);
    _dirty();
  }

  // -------------------------------------------------------------------------------------------
  // Playing lands (CR 305, 116.2a)
  // -------------------------------------------------------------------------------------------

  int landsAllowed(PlayerId p) => 1 + _rules<ExtraLandPerTurn>(p).fold<int>(0, (a, r) => a + r.n);

  /// Whether [p] may play [id] as a land now, as its face [face] (a modal double-faced card's
  /// back can be the land, CR 712.12).
  bool canPlayLand(PlayerId p, ObjId id, {int face = 0}) {
    if (state.priority != p || state.pending != null) return false;
    if (state.active != p || !(state.step == TurnStep.main1 || state.step == TurnStep.main2) || state.stack.isNotEmpty) return false;
    if (state.player(p).stats.landsPlayed >= landsAllowed(p)) return false;
    final o = state.objOrNull(id);
    if (o == null) return false;
    if (face != 0 && !landFaces(id).contains(face)) return false;
    final c = face == 0 ? chars(id) : _castChars(o, face);
    if (!c.isLand) return false;
    if (o.zone == Zone.hand && o.owner == p) return true;
    if (o.playableBy == p && (o.zone == Zone.exile || o.zone == Zone.graveyard)) return true;
    if (o.zone == Zone.graveyard && o.owner == p && _graveyardPermission(p, o, landPlay: true)) return true;
    return false;
  }

  void _playLand(PlayerId p, ObjId id, int face) {
    if (!canPlayLand(p, id, face: face)) throw GameError("Can't play that land now");
    final o = state.obj(id);
    if (o.zone == Zone.graveyard && o.playableBy != p) state.player(p).stats.graveyardPlays.add('land');
    state.player(p).stats.landsPlayed++;
    _log('${state.player(p).name} plays ${o.cardName}.', player: p, obj: id, kind: 'land');
    _putOntoBattlefield(id, p, face: face);
    _afterPlayerAction(p);
  }
}

/// The digest of a game, hashed (what lockstep peers compare).
String gameFingerprint(GameState s) => sha256.convert(utf8.encode(s.digest())).toString().substring(0, 24);
