part of 'game.dart';

/// What an ability's text refers to while it is checked or resolves: its source, controller,
/// targets, X, the trigger event, and what earlier steps remembered.
class EvalCtx {
  EvalCtx(this.game, {required this.controller, this.source, this.sourceZcc = 0, this.targets = const [], this.targetZcc = const [], this.x = 0, this.kicked = false, this.event, this.item, this.sourceLki, this.wasCast = false});
  final Game game;
  PlayerId controller;
  final ObjId? source;
  final int sourceZcc;
  List<List<int>> targets;
  List<List<int>> targetZcc;
  int x;
  bool kicked;
  bool wasCast;
  final EventInfo? event;
  final StackItem? item;

  /// The source's characteristics as it last existed (CR 113.7a, 608.2h).
  Chars? sourceLki;
  final Map<String, List<(ObjId, int)>> remembered = {};
  final Map<String, int> results = {};
  bool didIt = false;

  /// "That player" inside a for-each-player loop.
  PlayerId? thatPlayer;

  EvalCtx withThatPlayer(PlayerId p) => EvalCtx(game, controller: controller, source: source, sourceZcc: sourceZcc, targets: targets, targetZcc: targetZcc, x: x, kicked: kicked, event: event, item: item, sourceLki: sourceLki, wasCast: wasCast)
    ..remembered.addAll(remembered)
    ..results.addAll(results)
    ..didIt = didIt
    ..thatPlayer = p;
}

/// Queries: filters, references, amounts, conditions, legal actions.
extension GameQuery on Game {
  // -------------------------------------------------------------------------------------------
  // Filters (CR 109.2 object descriptions)
  // -------------------------------------------------------------------------------------------

  bool matchesFilter(Filter f, ObjId id, EvalCtx ctx, {Chars? ch}) {
    final o = state.objOrNull(id);
    if (o == null) return false;
    final c = ch ?? chars(id);
    switch (f.zone) {
      case ZoneKind.battlefield:
        if (o.zone != Zone.battlefield || o.phasedOut) return false;
      case ZoneKind.stack:
        if (o.zone != Zone.stack) return false;
      case ZoneKind.anywhere:
        break;
      default:
        if (o.zone != zoneOfKind(f.zone)) return false;
    }
    if (f.card && o.isToken) return false;
    if (f.spell && o.zone != Zone.stack) return false;
    if (f.types.isNotEmpty && !f.types.any(c.types.contains)) {
      // "Permanent" plus type list is handled by types; plain "permanent" by f.permanent.
      return false;
    }
    if (f.allTypes.isNotEmpty && !f.allTypes.every(c.types.contains)) return false;
    if (f.notTypes.any(c.types.contains)) return false;
    if (f.subtypes.isNotEmpty && !f.subtypes.any(c.hasSubtype)) return false;
    if (f.notSubtypes.any(c.hasSubtype)) return false;
    if (f.supertypes.isNotEmpty && !f.supertypes.every(c.supertypes.contains)) return false;
    if (f.notSupertypes.any(c.supertypes.contains)) return false;
    if (f.colors.isNotEmpty && !f.colors.any(c.colors.contains)) return false;
    if (f.notColors.any(c.colors.contains)) return false;
    if (f.multicolored == true && c.colors.length < 2) return false;
    if (f.multicolored == false && c.colors.length >= 2) return false;
    if (f.colorless == true && c.colors.isNotEmpty) return false;
    if (f.colorless == false && c.colors.isEmpty) return false;
    final ctl = o.zone == Zone.battlefield || o.zone == Zone.stack ? c.controller : o.owner;
    if (!_who(f.controller, ctl, ctx)) return false;
    if (!_who(f.owner, o.owner, ctx)) return false;
    if (f.other && id == ctx.source) return false;
    if (f.token != null && o.isToken != f.token) return false;
    if (f.tapped != null && o.tapped != f.tapped) return false;
    if (f.attacking == true && f.blocking == true) {
      if (o.attacking == null && o.blocking.isEmpty) return false;
    } else {
      if (f.attacking != null && (o.attacking != null) != f.attacking) return false;
      if (f.blocking != null && o.blocking.isNotEmpty != f.blocking) return false;
    }
    if (f.power != null && !(c.power != null && f.power!.$1.test(c.power!, evalAmount(f.power!.$2, ctx)))) return false;
    if (f.toughness != null && !(c.toughness != null && f.toughness!.$1.test(c.toughness!, evalAmount(f.toughness!.$2, ctx)))) return false;
    if (f.manaValue != null && !f.manaValue!.$1.test(c.manaValue + (o.zone == Zone.stack ? o.x * (c.manaCost?.xCount ?? 0) : 0), evalAmount(f.manaValue!.$2, ctx))) return false;
    for (final k in f.withKeywords) {
      if (!c.hasName(k)) return false;
    }
    for (final k in f.withoutKeywords) {
      if (c.hasName(k)) return false;
    }
    if (f.withCounter != null && (o.counters[f.withCounter!] ?? 0) <= 0) return false;
    if (f.name != null) {
      final want = f.name == '~' ? (ctx.sourceLki?.name ?? (ctx.source != null && state.objOrNull(ctx.source) != null ? chars(ctx.source!).name : '')) : f.name!;
      if (c.name.toLowerCase() != want.toLowerCase()) return false;
    }
    if (f.notName != null && c.name.toLowerCase() == f.notName!.toLowerCase()) return false;
    if (f.permanent && o.zone != Zone.battlefield && !c.isPermanentCard) return false;
    if (f.putThereThisTurn && o.arrivedTurn != state.turn) return false;
    if (f.chosenType) {
      final src = state.objOrNull(ctx.source);
      if (src?.chosenType == null || !c.hasSubtype(src!.chosenType!)) return false;
    }
    if (f.chosenColor) {
      final src = state.objOrNull(ctx.source);
      final col = src?.chosenColor == null ? null : ManaColor.fromWord(src!.chosenColor!);
      if (col == null || !c.colors.contains(col)) return false;
    }
    if (f.historic && !(c.isLegendary || c.isArtifact || c.subtypes.contains('Saga'))) return false;
    if (f.enteredThisTurn != null && (o.enteredTurn == state.turn) != f.enteredThisTurn) return false;
    return true;
  }

  bool _who(Who w, PlayerId p, EvalCtx ctx) => switch (w) {
        Who.any => true,
        Who.you => p == ctx.controller,
        Who.opponent => p != ctx.controller,
        Who.notYou => p != ctx.controller,
        Who.that => p == (ctx.thatPlayer ?? ctx.event?.player),
      };

  // -------------------------------------------------------------------------------------------
  // References
  // -------------------------------------------------------------------------------------------

  /// The objects a set refers to now. Stale references (the object changed zones) are dropped.
  List<ObjId> resolveObjs(ObjSet s, EvalCtx ctx) {
    switch (s) {
      case One(:final ref):
        return _ref(ref, ctx);
      case All(:final filter):
        return [for (final id in _candidates(filter, ctx)) if (matchesFilter(filter, id, ctx)) id];
    }
  }

  List<ObjId> _ref(ObjRef r, EvalCtx ctx) {
    switch (r) {
      case SelfRef():
        final src = ctx.source;
        if (src == null) return const [];
        final o = state.objOrNull(src);
        if (o == null) return const [];
        // The source itself, or the new object it became through the zone change that
        // triggered this ability ("when ~ dies, return it").
        if (o.zcc == ctx.sourceZcc || o.zcc == ctx.sourceZcc + 1 && ctx.event?.obj == src) return [src];
        if (ctx.item == null) return [src];
        return const [];
      case TargetObj(:final index):
        if (index >= ctx.targets.length) return const [];
        final out = <ObjId>[];
        for (var i = 0; i < ctx.targets[index].length; i++) {
          final e = ctx.targets[index][i];
          if (isPlayerEntity(e)) continue;
          final o = state.objOrNull(e);
          final z = index < ctx.targetZcc.length && i < ctx.targetZcc[index].length ? ctx.targetZcc[index][i] : null;
          if (o != null && (z == null || o.zcc == z)) out.add(e);
        }
        return out;
      case EventObj():
        final ev = ctx.event;
        if (ev?.obj == null) return const [];
        final o = state.objOrNull(ev!.obj);
        if (o == null || (ev.objZcc != null && o.zcc != ev.objZcc)) return const [];
        return [o.id];
      case AttachedTo():
        final src = state.objOrNull(ctx.source);
        if (src?.attachedTo == null) return const [];
        return [src!.attachedTo!];
      case Remembered(:final slot):
        return [
          for (final (id, zcc) in ctx.remembered[slot] ?? const <(ObjId, int)>[])
            if (state.objOrNull(id)?.zcc == zcc) id,
        ];
    }
  }

  Iterable<ObjId> _candidates(Filter f, EvalCtx ctx) sync* {
    switch (f.zone) {
      case ZoneKind.battlefield:
        yield* state.battlefield;
      case ZoneKind.graveyard:
        for (final p in state.apnap(ctx.controller)) {
          yield* state.player(p).graveyard;
        }
      case ZoneKind.hand:
        for (final p in state.apnap(ctx.controller)) {
          yield* state.player(p).hand;
        }
      case ZoneKind.exile:
        for (final p in state.apnap(ctx.controller)) {
          yield* state.player(p).exile;
        }
      case ZoneKind.library:
        for (final p in state.apnap(ctx.controller)) {
          yield* state.player(p).library;
        }
      case ZoneKind.stack:
        for (final i in state.stack.reversed) {
          if (i.objId != null) yield i.objId!;
        }
      case ZoneKind.command:
        yield* state.command;
      case ZoneKind.anywhere:
        yield* state.battlefield;
        for (final p in state.apnap(ctx.controller)) {
          yield* state.player(p).graveyard;
          yield* state.player(p).exile;
        }
    }
  }

  List<PlayerId> resolvePlayers(PlayerRef r, EvalCtx ctx) {
    switch (r) {
      case You():
        return [ctx.controller];
      case EachOpponent():
        return state.opponents(ctx.controller);
      case EachPlayer():
        return state.apnap();
      case TargetPlayer(:final index):
        if (index >= ctx.targets.length) return const [];
        return [for (final e in ctx.targets[index]) if (isPlayerEntity(e) && !state.player(entityPlayer(e)).lost) entityPlayer(e)];
      case ControllerOf(:final obj):
        final ids = _ref(obj, ctx);
        if (ids.isNotEmpty) {
          final o = state.obj(ids.first);
          return [o.zone == Zone.battlefield || o.zone == Zone.stack ? chars(o.id).controller : o.owner];
        }
        // Last known information for targets that left.
        if (obj is TargetObj && obj.index < ctx.targets.length && ctx.targets[obj.index].isNotEmpty) {
          final o = state.objOrNull(ctx.targets[obj.index].first);
          if (o != null) return [o.controller];
        }
        return const [];
      case OwnerOf(:final obj):
        final ids = _ref(obj, ctx);
        if (ids.isNotEmpty) return [state.obj(ids.first).owner];
        if (obj is TargetObj && obj.index < ctx.targets.length && ctx.targets[obj.index].isNotEmpty) {
          final o = state.objOrNull(ctx.targets[obj.index].first);
          if (o != null) return [o.owner];
        }
        return const [];
      case EventPlayer():
        final p = ctx.thatPlayer ?? ctx.event?.player;
        return p == null ? const [] : [p];
      case DefendingPlayer():
        final src = state.objOrNull(ctx.source);
        final a = src?.attacking;
        if (a == null) return state.opponents(ctx.controller).take(1).toList();
        if (isPlayerEntity(a)) return [entityPlayer(a)];
        return [state.obj(a).controller];
      case ActivePlayer():
        return [state.active];
    }
  }

  // -------------------------------------------------------------------------------------------
  // Amounts and conditions
  // -------------------------------------------------------------------------------------------

  int evalAmount(Amount a, EvalCtx ctx) {
    switch (a) {
      case Fixed(:final n):
        return n;
      case XValue():
        return ctx.x;
      case RollResult():
        return ctx.results['roll'] ?? 0;
      case EnergyOf(:final player):
        return resolvePlayers(player, ctx).fold(0, (a, p) => a + state.player(p).energy);
      case CountOf(:final set):
        return resolveObjs(set, ctx).length;
      case PlayerCount(:final players):
        return resolvePlayers(players, ctx).length;
      case StatOf(:final stat, :final obj):
        final ids = _ref(obj, ctx);
        Chars? c;
        if (ids.isNotEmpty) {
          c = chars(ids.first);
        } else if (obj is SelfRef) {
          c = ctx.sourceLki;
        } else if (obj is EventObj && ctx.event != null) {
          return stat == Stat.power ? ctx.event!.objPower : 0;
        }
        if (c == null) return 0;
        return switch (stat) { Stat.power => c.power ?? 0, Stat.toughness => c.toughness ?? 0, Stat.manaValue => c.manaValue, Stat.loyalty => c.loyalty ?? 0 };
      case TotalStat(:final stat, :final set):
        var t = 0;
        for (final id in resolveObjs(set, ctx)) {
          final c = chars(id);
          t += stat == Stat.power ? (c.power ?? 0) : (c.toughness ?? 0);
        }
        return t;
      case CountersOn(:final kind, :final obj):
        final ids = _ref(obj, ctx);
        if (ids.isEmpty) {
          if (obj is SelfRef && ctx.event?.obj == ctx.source) return ctx.event!.objCounters[kind] ?? 0;
          return 0;
        }
        return state.obj(ids.first).counters[kind] ?? 0;
      case LifeTotal(:final player):
        final ps = resolvePlayers(player, ctx);
        return ps.isEmpty ? 0 : state.player(ps.first).life;
      case StartingLife(:final player):
        final ps = resolvePlayers(player, ctx);
        return ps.isEmpty ? 0 : state.player(ps.first).startingLife;
      case TurnCount(:final stat, :final player):
        var t = 0;
        for (final p in resolvePlayers(player, ctx)) {
          final s = state.player(p).stats;
          t += switch (stat) { TurnStat.lifeGained => s.lifeGained, TurnStat.lifeLost => s.lifeLost, TurnStat.cardsDrawn => s.cardsDrawn, TurnStat.spellsCast => s.spellsCast, TurnStat.damageTaken => s.damageTaken };
        }
        return t;
      case EventAmount():
        return ctx.event?.amount ?? 0;
      case ResultAmount(:final slot):
        return ctx.results[slot] ?? 0;
      case CardsIn(:final zone, :final player, :final filter):
        var t = 0;
        for (final p in resolvePlayers(player, ctx)) {
          final pl = state.player(p);
          final list = switch (zone) { ZoneKind.graveyard => pl.graveyard, ZoneKind.hand => pl.hand, ZoneKind.library => pl.library, ZoneKind.exile => pl.exile, _ => const <ObjId>[] };
          for (final id in list) {
            if (matchesFilter(filter.copyWith(zone: zone, controller: Who.any, owner: Who.any), id, ctx)) t++;
          }
        }
        return t;
      case DistinctManaValues(:final set):
        return {for (final id in resolveObjs(set, ctx)) chars(id).manaValue}.length;
      case Times(:final a, :final k):
        return evalAmount(a, ctx) * k;
      case Plus(:final a, :final b):
        return evalAmount(a, ctx) + evalAmount(b, ctx);
    }
  }

  bool evalCondition(Condition c, EvalCtx ctx) {
    switch (c) {
      case Not(:final c):
        return !evalCondition(c, ctx);
      case AllOf(:final cs):
        return cs.every((x) => evalCondition(x, ctx));
      case AnyOf(:final cs):
        return cs.any((x) => evalCondition(x, ctx));
      case AttackedThisTurn():
        return state.player(ctx.controller).stats.attacked;
      case CreatureDiedThisTurn():
        return state.creaturesDiedThisTurn > 0;
      case TurnStatCondition(:final stat, :final player, :final cmp, :final n):
        return resolvePlayers(player, ctx).any((p) {
          final s = state.player(p).stats;
          final v = switch (stat) { TurnStat.lifeGained => s.lifeGained, TurnStat.lifeLost => s.lifeLost, TurnStat.cardsDrawn => s.cardsDrawn, TurnStat.spellsCast => s.spellsCast, TurnStat.damageTaken => s.damageTaken };
          return cmp.test(v, n);
        });
      case CountCondition(:final amount, :final cmp, :final n):
        return cmp.test(evalAmount(amount, ctx), n);
      case Kicked():
        return ctx.kicked;
      case YourTurn():
        return state.active == ctx.controller;
      case DuringSteps(:final steps):
        return steps.contains(state.step);
      case WasCast():
        return ctx.wasCast;
      case ObjMatches(:final obj, :final filter):
        // "If it had no -1/-1 counters on it": the counters it had as the event happened.
        if (obj is EventObj && filter.withCounter != null && ctx.event != null) return (ctx.event!.objCounters[filter.withCounter!] ?? 0) > 0;
        final ids = _ref(obj, ctx);
        if (ids.isEmpty) {
          // Look back at the object as it last existed.
          final lki = obj is SelfRef ? ctx.sourceLki : null;
          if (lki == null) return false;
          if (filter.subtypes.isNotEmpty && !filter.subtypes.any(lki.hasSubtype)) return false;
          if (filter.types.isNotEmpty && !filter.types.any(lki.types.contains)) return false;
          if (filter.withCounter != null) return (ctx.event?.objCounters[filter.withCounter!] ?? 0) > 0;
          return true;
        }
        return matchesFilter(filter.copyWith(zone: ZoneKind.anywhere), ids.first, ctx);
      case RememberedAny(:final slot, :final filter):
        return (ctx.remembered[slot] ?? const []).any((r) => matchesFilter(filter.copyWith(zone: ZoneKind.anywhere), r.$1, ctx));
      case DidIt():
        return ctx.didIt;
      case AmountCompare(:final a, :final cmp, :final b):
        return cmp.test(evalAmount(a, ctx), evalAmount(b, ctx));
      case WonFlip(:final won):
        return ctx.results.containsKey('flip') && (ctx.results['flip'] == 1) == won;
      case WonClash():
        return ctx.results['clash'] == 1;
      case StepIn(:final steps):
        return steps.contains(state.step);
    }
  }

  // -------------------------------------------------------------------------------------------
  // Rules modifications from static abilities
  // -------------------------------------------------------------------------------------------

  /// Rule abilities that apply to [p] (from permanents they control, emblems, and resolved
  /// effects).
  List<T> _rules<T extends RuleMod>(PlayerId p) {
    final out = <T>[];
    for (final id in state.battlefield) {
      final c = chars(id);
      if (c.controller != p) continue;
      for (final a in c.abilities) {
        if (a is RuleAbility && a.rule is T && a.zone == ZoneKind.battlefield) {
          if (a.condition == null || evalCondition(a.condition!, EvalCtx(this, controller: p, source: id, sourceZcc: state.obj(id).zcc))) out.add(a.rule as T);
        }
      }
    }
    for (final e in state.emblems) {
      if (e.owner != p) continue;
      for (final a in e.abilities) {
        if (a is RuleAbility && a.rule is T) out.add(a.rule as T);
      }
    }
    for (final e in state.effects) {
      if (e.rule is T && e.controller == p) out.add(e.rule as T);
    }
    return out;
  }

  bool _hasRule<T extends RuleMod>(PlayerId p) => _rules<T>(p).isNotEmpty;

  /// Replacement abilities of permanents on the battlefield, with their controllers.
  List<(T, PlayerId, ObjId)> _replacements<T extends Replacement>() {
    final out = <(T, PlayerId, ObjId)>[];
    for (final id in state.battlefield) {
      final c = chars(id);
      for (final a in c.abilities) {
        if (a is ReplacementAbility && a.replacement is T) out.add((a.replacement as T, c.controller, id));
      }
    }
    return out;
  }

  // -------------------------------------------------------------------------------------------
  // Legal actions (for the table and the computer player)
  // -------------------------------------------------------------------------------------------

  /// Everything [p] may do right now. Casts and activations are checked by trying them with
  /// default choices on a copy of the state.
  List<GameAction> legalActions(PlayerId p) {
    final out = <GameAction>[];
    if (state.over || state.pending != null || state.priority != p || !state.inProgress) return out;
    out.add(PassAction(p));
    final pl = state.player(p);
    for (final id in pl.hand) {
      for (final f in landFaces(id)) {
        if (canPlayLand(p, id, face: f)) out.add(PlayLandAction(p, id, face: f));
      }
    }
    for (final id in _castCandidates(p)) {
      final o = state.obj(id);
      final c = chars(id);
      if (c.isLand) {
        if (o.zone != Zone.hand && canPlayLand(p, id)) out.add(PlayLandAction(p, id));
        continue;
      }
      final opts = castOptions(p, id);
      for (final face in castFaces(p, id)) {
        for (final opt in opts) {
          if (face != 0 && opt != -1) continue;
          if (_probe(() => _castSpell(p, id, face, opt))) out.add(CastAction(p, id, face: face, option: opt));
        }
      }
    }
    for (final id in [...state.battlefield, ...pl.hand, ...pl.graveyard]) {
      final o = state.obj(id);
      final c = chars(id);
      if (o.zone == Zone.battlefield && c.controller != p) continue;
      if (o.zone != Zone.battlefield && o.owner != p) continue;
      for (var i = 0; i < c.abilities.length; i++) {
        final a = c.abilities[i];
        if (a is ActivatedAbility && zoneOfKind(a.zone) == o.zone) {
          if (_probe(() => _activate(p, id, i))) out.add(ActivateAbilityAction(p, id, i));
        } else if (a is ManaAbility && o.zone == Zone.battlefield) {
          if (_canPayManaAbilityCost(p, id, a)) out.add(ManaAction(p, id, i));
        }
      }
    }
    return out;
  }

  /// Cards [p] might cast: hand, plus graveyard/exile cards with a permission or cast option.
  List<ObjId> _castCandidates(PlayerId p) {
    final pl = state.player(p);
    final out = <ObjId>[...pl.hand];
    for (final id in [...pl.graveyard, ...pl.exile]) {
      final o = state.obj(id);
      if (o.playableBy == p) {
        out.add(id);
        continue;
      }
      if (o.zone == Zone.graveyard && (castOptions(p, id).any((i) => i >= 0) || _graveyardPermission(p, o) || _aftermathPermission(p, o))) out.add(id);
      if (_adventurePermission(p, o)) out.add(id);
    }
    for (final q in state.opponents(p)) {
      for (final id in state.player(q).exile) {
        if (state.obj(id).playableBy == p) out.add(id);
      }
    }
    return out;
  }

  /// Runs [f] on a copy of the state with default answers; true if it completes.
  bool _probe(void Function() f) {
    final snap = state;
    final prevChoices = _choices;
    final prevCache = (_charCache, _charVersion, _charState);
    state = state.clone();
    _choices = _Choices(const [], auto: true);
    try {
      f();
      return true;
    } on GameError {
      return false;
    } on NeedDecision {
      return false;
    } finally {
      state = snap;
      _choices = prevChoices;
      _charCache = prevCache.$1;
      _charVersion = prevCache.$2;
      _charState = prevCache.$3;
    }
  }

  /// Why [a] can't be done now, in words for the table, or null if it can.
  String? whyNot(GameAction a) {
    if (state.over) return 'The game is over.';
    if (!state.inProgress) return 'The game has not begun.';
    if (state.pending != null) return 'Answer the question first.';
    final p = a.player;
    if (state.priority != p) return state.active == p ? 'Wait: your opponent can respond.' : "It's not your turn.";
    switch (a) {
      case PlayLandAction(:final id):
        if (canPlayLand(p, id)) return null;
        if (state.active != p) return 'Lands are played on your own turn.';
        if (!(state.step == TurnStep.main1 || state.step == TurnStep.main2)) return 'Lands are played in a main phase.';
        if (state.stack.isNotEmpty) return 'Wait until the stack is empty.';
        if (state.player(p).stats.landsPlayed >= landsAllowed(p)) return 'You already played a land this turn.';
        return "You can't play that land now.";
      case CastAction(:final id, :final option, :final face):
        return _probeError(() => _castSpell(p, id, face, option));
      case ActivateAbilityAction(:final id, :final index):
        return _probeError(() => _activate(p, id, index));
      case ManaAction(:final id, :final index):
        final c = chars(id);
        if (index >= c.abilities.length || c.abilities[index] is! ManaAbility) return 'Not a mana ability.';
        return _canPayManaAbilityCost(p, id, c.abilities[index] as ManaAbility) ? null : (state.obj(id).tapped ? 'It is tapped.' : 'Summoning sick.');
      default:
        return null;
    }
  }

  String? _probeError(void Function() f) {
    final snap = state;
    final prevChoices = _choices;
    final prevCache = (_charCache, _charVersion, _charState);
    state = state.clone();
    _choices = _Choices(const [], auto: true);
    try {
      f();
      return null;
    } on GameError catch (e) {
      return '${e.message}${e.message.endsWith('.') ? '' : '.'}';
    } on NeedDecision {
      return null;
    } finally {
      state = snap;
      _choices = prevChoices;
      _charCache = prevCache.$1;
      _charVersion = prevCache.$2;
      _charState = prevCache.$3;
    }
  }

  /// The first legal answer to a decision (used for legality probes and as a fallback).
  List<int> defaultAnswer(Decision d) {
    switch (d.kind) {
      case DecisionKind.targets || DecisionKind.cards:
        if (d.options.length < d.min) throw GameError('Not enough legal choices');
        return d.options.take(d.min).toList();
      case DecisionKind.modes:
        if (d.options.length < d.min) throw GameError('Not enough modes');
        return d.options.take(d.min).toList();
      case DecisionKind.number:
        return [d.min];
      case DecisionKind.yesNo:
        return const [0];
      case DecisionKind.mulligan:
        return const [1];
      case DecisionKind.option:
        return const [0];
      case DecisionKind.order:
        return List.of(d.options);
      case DecisionKind.payMana || DecisionKind.attackers || DecisionKind.blockers || DecisionKind.damage || DecisionKind.divide:
        return const [];
    }
  }

  /// Can the costs of a mana ability be paid (it's untapped, etc.)?
  bool _canPayManaAbilityCost(PlayerId p, ObjId id, ManaAbility a) {
    final o = state.obj(id);
    if (a.cost.tap && (o.tapped || (_summoningSick(id) && chars(id).isCreature))) return false;
    if (a.cost.mana != null && !a.cost.mana!.isEmpty) return false;
    for (final part in a.cost.parts) {
      if (part is SacrificeCost && part.self) continue;
      return false;
    }
    return true;
  }

  bool _summoningSick(ObjId id) {
    final o = state.obj(id);
    if (o.controlSince < state.turn) return false;
    return !chars(id).has(Kw.haste);
  }

  /// Whether [p] may play/cast [o] from their graveyard by a static permission (Muldrotha).
  bool _graveyardPermission(PlayerId p, GameObject o, {bool landPlay = false}) {
    if (o.owner != p || state.active != p) return false;
    for (final r in _rules<PlayFromGraveyard>(p)) {
      final c = chars(o.id);
      if (landPlay && !c.isLand) continue;
      if (!matchesFilter(r.filter.copyWith(zone: ZoneKind.graveyard), o.id, EvalCtx(this, controller: p))) continue;
      if (r.oncePerTypeEachTurn) {
        final used = state.player(p).stats.graveyardPlays;
        final types = [for (final t in c.types) if (t.isPermanentType) t.name];
        if (types.every(used.contains)) continue;
      }
      return true;
    }
    return false;
  }

  /// Which players and objects are legal for a target spec (CR 115).
  List<int> legalTargets(TargetSpec spec, EvalCtx ctx, {ObjId? spell}) {
    final out = <int>[];
    final caster = ctx.controller;
    bool playerOk(PlayerId q) {
      final pl = state.player(q);
      if (pl.lost) return false;
      if (spec.who == Who.opponent && q == caster) return false;
      if (spec.who == Who.you && q != caster) return false;
      if (q != caster && _hasRule<PlayerHexproof>(q)) return false;
      return true;
    }

    switch (spec.kind) {
      case TargetKind.player:
        for (final q in state.apnap(caster)) {
          if (playerOk(q)) out.add(playerEntity(q));
        }
      case TargetKind.any:
        // Creatures, planeswalkers, battles, and players.
        for (final id in state.battlefield) {
          final c = chars(id);
          if (!(c.isCreature || c.isPlaneswalker || c.isBattle)) continue;
          if (spec.filter.types.contains(CardType.planeswalker) && !c.isPlaneswalker && !c.isCreature) continue;
          if (spec.filter.types.contains(CardType.planeswalker) && spec.filter.types.length == 1 && !c.isPlaneswalker) continue;
          if (spec.filter.other && id == ctx.source) continue;
          if (_targetable(id, ctx, spell: spell)) out.add(id);
        }
        for (final q in state.apnap(caster)) {
          if (playerOk(q)) out.add(playerEntity(q));
        }
      case TargetKind.object || TargetKind.spell:
        final f = spec.filter;
        Iterable<ObjId> cands;
        if (spec.kind == TargetKind.spell || f.spell) {
          cands = [for (final i in state.stack.reversed) if (i.objId != null && i.objId != spell) i.objId!];
        } else {
          cands = _candidates(f.zone == ZoneKind.anywhere && f.card ? f.copyWith(zone: ZoneKind.graveyard) : f, ctx);
        }
        final f2 = f.zone == ZoneKind.anywhere && f.card ? f.copyWith(zone: ZoneKind.graveyard) : f;
        for (final id in cands) {
          if (id == spell) continue;
          if (!matchesFilter(f2.spell || spec.kind == TargetKind.spell ? f2.copyWith(zone: ZoneKind.stack) : f2, id, ctx)) continue;
          if (state.obj(id).zone == Zone.battlefield && !_targetable(id, ctx, spell: spell)) continue;
          out.add(id);
        }
    }
    return out;
  }

  /// Hexproof, shroud and protection (CR 702.11, 702.18, 702.16).
  bool _targetable(ObjId id, EvalCtx ctx, {ObjId? spell}) {
    final c = chars(id);
    if (c.has(Kw.shroud)) return false;
    if (c.has(Kw.hexproof) && c.controller != ctx.controller) return false;
    final srcChars = spell != null ? chars(spell) : (ctx.source != null && state.objOrNull(ctx.source) != null ? chars(ctx.source!) : null);
    for (final k in c.kws('hexproof from')) {
      if (c.controller != ctx.controller && srcChars != null && _qualityMatches(k.filter!, srcChars)) return false;
    }
    for (final k in c.kws('protection')) {
      if (srcChars != null && _qualityMatches(k.filter!, srcChars)) return false;
    }
    return true;
  }

  /// Whether a source has a quality (protection from red, hexproof from instants...).
  bool _qualityMatches(Filter f, Chars src) {
    if (identical(f, Filter.any) || (f.types.isEmpty && f.colors.isEmpty && f.subtypes.isEmpty && f.notTypes.isEmpty && !f.spell && !f.card && f.multicolored == null)) return true;
    if (f.colors.isNotEmpty && !f.colors.any(src.colors.contains)) return false;
    if (f.types.isNotEmpty && !f.types.any(src.types.contains)) return false;
    if (f.subtypes.isNotEmpty && !f.subtypes.any(src.hasSubtype)) return false;
    if (f.multicolored == true && src.colors.length < 2) return false;
    return true;
  }
}
