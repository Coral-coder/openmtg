part of 'game.dart';

/// Things that happen, for triggered abilities (CR 603) and the table's animations.
sealed class GameEvent {
  const GameEvent();
}

/// An object moved between zones. [oldId]/[oldZcc] name it before, [zcc] after; [lki] is its
/// last known information before it left (CR 603.10).
class ZoneEvent extends GameEvent {
  const ZoneEvent(this.id, this.oldZcc, this.zcc, this.from, this.to, this.lki, {this.counters = const {}, this.sacrificed = false});
  final ObjId id;
  final int oldZcc, zcc;
  final Zone from, to;
  final Chars lki;
  final Map<String, int> counters;
  final bool sacrificed;
}

class CastEvent extends GameEvent {
  const CastEvent(this.item, this.obj, this.player);
  final int item;
  final ObjId obj;
  final PlayerId player;
}

class AttackEvent extends GameEvent {
  const AttackEvent(this.player, this.attackers);
  final PlayerId player;
  final List<ObjId> attackers;
}

class BlockEvent extends GameEvent {
  const BlockEvent(this.blocker, this.attacker);
  final ObjId blocker, attacker;
}

class DamageEvent extends GameEvent {
  const DamageEvent(this.source, this.target, this.amount, {required this.combat, required this.sourceController, required this.sourceChars});
  final ObjId source;
  final int target; // entity
  final int amount;
  final bool combat;
  final PlayerId sourceController;
  final Chars sourceChars;
}

class LifeEvent extends GameEvent {
  const LifeEvent(this.player, this.amount, {required this.gain, this.nth = 0});
  final PlayerId player;
  final int amount;
  final bool gain;
  final int nth;
}

class DrawEvent extends GameEvent {
  const DrawEvent(this.player, this.nth, this.card);
  final PlayerId player;
  final int nth;
  final ObjId card;
}

class DiscardEvent extends GameEvent {
  const DiscardEvent(this.player, this.card);
  final PlayerId player;
  final ObjId card;
}

class CountersEvent extends GameEvent {
  const CountersEvent(this.obj, this.kind, this.n, this.by);
  final ObjId obj;
  final String kind;
  final int n;
  final PlayerId by;
}

class StepEvent extends GameEvent {
  const StepEvent(this.step, this.active);
  final TurnStep step;
  final PlayerId active;
}

class UntapEvent extends GameEvent {
  const UntapEvent(this.obj);
  final ObjId obj;
}

class TargetedEvent extends GameEvent {
  const TargetedEvent(this.obj, this.by, this.item);
  final ObjId obj;
  final PlayerId by;
  final int item;
}

extension GameEvents on Game {
  /// Checks every triggered ability against [e] (CR 603.2) and queues those that trigger.
  void _emit(GameEvent e) {
    _dirty();
    // Look-back triggers (leaving the battlefield) use the object's last known abilities.
    final lkiSources = <(ObjId, int, Chars)>[];
    if (e is ZoneEvent && e.from == Zone.battlefield) lkiSources.add((e.id, e.oldZcc, e.lki));
    if (e is CountersEvent) _dirty();

    for (final id in List.of(state.battlefield)) {
      final o = state.obj(id);
      if (o.phasedOut) continue;
      if (e is ZoneEvent && e.id == id && e.from == Zone.battlefield) continue;
      final c = chars(id);
      _checkAbilities(c.abilities, id, o.zcc, c.controller, c, e, ZoneKind.battlefield);
    }
    for (final (id, zcc, c) in lkiSources) {
      _checkAbilities(c.abilities, id, zcc, c.controller, c, e, ZoneKind.battlefield, lki: true);
    }
    // Graveyard abilities ("return this card from your graveyard").
    for (final p in state.apnap()) {
      for (final id in List.of(state.player(p).graveyard)) {
        final o = state.obj(id);
        final def = db[o.cardName];
        if (def == null) continue;
        final abs = OracleParser.parse(def).faces.first.abilities;
        if (!abs.any((a) => a is TriggeredAbility && a.zone == ZoneKind.graveyard)) continue;
        final c = chars(id);
        _checkAbilities(abs, id, o.zcc, o.owner, c, e, ZoneKind.graveyard);
      }
    }
    for (final em in state.emblems) {
      _checkAbilities(em.abilities, -em.id, 0, em.owner, null, e, ZoneKind.command);
    }
    // Delayed triggers (CR 603.7).
    for (final d in List.of(state.delayed)) {
      final info = _triggerMatches(d.ability.trigger, null, d.sourceId, 0, d.controller, e);
      if (info == null) continue;
      state.pendingTriggers.add(PendingTrigger(controller: d.controller, sourceId: d.sourceId, sourceZcc: 0, ability: d.ability, event: EventInfo(obj: d.objects.isEmpty ? null : d.objects.first.$1, objZcc: d.objects.isEmpty ? null : d.objects.first.$2, player: info.player), sourceName: 'Delayed', delayed: true));
      if (d.oneShot) state.delayed.remove(d);
    }
  }

  void _checkAbilities(List<Ability> abilities, ObjId id, int zcc, PlayerId controller, Chars? c, GameEvent e, ZoneKind zone, {bool lki = false}) {
    for (final a in abilities) {
      if (a is! TriggeredAbility) continue;
      if (a.zone != zone) continue;
      // Leaves-the-battlefield abilities trigger from last known information; others don't.
      final ltb = a.trigger is DiesTrigger || a.trigger is LeavesTrigger || (a.trigger is PutIntoGraveyardTrigger);
      if (lki && !ltb) continue;
      if (zone == ZoneKind.graveyard && !(e is! ZoneEvent || e.id != id)) continue;
      final info = _triggerMatches(a.trigger, c, id, zcc, controller, e);
      if (info == null) continue;
      if (a.oncePerTurn) {
        final o = state.objOrNull(id);
        final key = 'trig:${a.text}';
        if (o != null && (o.activations[key] ?? 0) > 0) continue;
        o?.activations[key] = 1;
      }
      final ctx = EvalCtx(this, controller: controller, source: id, sourceZcc: zcc, event: info, sourceLki: c);
      if (a.condition != null && !evalCondition(a.condition!, ctx)) continue;
      state.pendingTriggers.add(PendingTrigger(controller: controller, sourceId: id, sourceZcc: zcc, ability: a, event: info, sourceName: c?.name ?? 'Emblem'));
    }
  }

  /// Whether [t] triggers on [e] for an ability of [src] (controlled by [you]).
  EventInfo? _triggerMatches(Trigger t, Chars? src, ObjId srcId, int srcZcc, PlayerId you, GameEvent e) {
    final ctx = EvalCtx(this, controller: you, source: srcId, sourceZcc: srcZcc);
    bool inSet(ObjSet set, ObjId id, Chars ch, {int? zcc}) {
      switch (set) {
        case One(:final ref):
          if (ref is SelfRef) return id == srcId;
          if (ref is AttachedTo) {
            final so = state.objOrNull(srcId);
            return so != null && so.attachedTo == id;
          }
          return false;
        case All(:final filter):
          // Zone-agnostic: the event already established where the object is.
          return matchesFilter(filter.copyWith(zone: ZoneKind.anywhere), id, ctx, ch: ch) && (!filter.other || id != srcId);
      }
    }

    EventInfo objInfo(ObjId id, int? zcc, Chars ch, {PlayerId? player, int amount = 0, Map<String, int> counters = const {}}) =>
        EventInfo(obj: id, objZcc: zcc, player: player ?? ch.controller, amount: amount, objName: ch.name, objPower: ch.power ?? 0, objTypes: ch.types, objSubtypes: ch.subtypes, objCounters: counters);

    switch (t) {
      case EntersTrigger(:final set):
        if (e is! ZoneEvent || e.to != Zone.battlefield) return null;
        final ch = chars(e.id);
        if (!inSet(set, e.id, ch)) return null;
        return objInfo(e.id, e.zcc, ch);
      case DiesTrigger(:final set):
        if (e is! ZoneEvent || e.from != Zone.battlefield || e.to != Zone.graveyard || !e.lki.isCreature) return null;
        if (!_inSetLki(set, e.id, e.lki, srcId, ctx)) return null;
        return objInfo(e.id, e.zcc, e.lki, counters: e.counters);
      case LeavesTrigger(:final set):
        if (e is! ZoneEvent || e.from != Zone.battlefield) return null;
        if (!_inSetLki(set, e.id, e.lki, srcId, ctx)) return null;
        return objInfo(e.id, e.zcc, e.lki, counters: e.counters);
      case PutIntoGraveyardTrigger(:final set, :final fromBattlefield):
        if (e is! ZoneEvent || e.to != Zone.graveyard) return null;
        if (fromBattlefield && e.from != Zone.battlefield) return null;
        if (!_inSetLki(set, e.id, e.lki, srcId, ctx)) return null;
        return objInfo(e.id, e.zcc, e.lki);
      case SacrificedTrigger(:final set):
        if (e is! ZoneEvent || !e.sacrificed) return null;
        if (!_inSetLki(set, e.id, e.lki, srcId, ctx)) return null;
        return objInfo(e.id, e.zcc, e.lki);
      case AttacksTrigger(:final set, :final condition):
        if (e is! AttackEvent) return null;
        for (final a in e.attackers) {
          if (inSet(set, a, chars(a))) {
            if (condition != null && !evalCondition(condition, ctx)) return null;
            return objInfo(a, state.obj(a).zcc, chars(a), player: _defenderOf(a));
          }
        }
        return null;
      case YouAttackTrigger(:final min):
        if (e is! AttackEvent || e.player != you || e.attackers.length < min) return null;
        return EventInfo(player: you, amount: e.attackers.length);
      case BlocksTrigger(:final set):
        if (e is! BlockEvent || !inSet(set, e.blocker, chars(e.blocker))) return null;
        return objInfo(e.blocker, state.obj(e.blocker).zcc, chars(e.blocker), amount: 0);
      case BecomesBlockedTrigger(:final set):
        if (e is! BlockEvent || !inSet(set, e.attacker, chars(e.attacker))) return null;
        // Once per combat: only for the first blocker.
        if (state.obj(e.attacker).blockedBy.length > 1) return null;
        return objInfo(e.attacker, state.obj(e.attacker).zcc, chars(e.attacker));
      case DealsDamageTrigger(:final set, :final toPlayer, :final toOpponent, :final toCreature, :final combat, :final duringYourTurn):
        if (e is! DamageEvent) return null;
        if (combat != null && e.combat != combat) return null;
        if (duringYourTurn && state.active != you) return null;
        final toP = isPlayerEntity(e.target);
        if (toPlayer && !toP) return null;
        if (toOpponent && (!toP || entityPlayer(e.target) == you)) return null;
        if (toCreature && (toP || !chars(e.target).isCreature)) return null;
        final srcObj = state.objOrNull(e.source);
        if (srcObj == null) return null;
        if (set is All) {
          final f = set.filter;
          if (f.controller == Who.you && e.sourceController != you) return null;
          if (f.types.isNotEmpty && !f.types.any(e.sourceChars.types.contains)) return null;
          if (f.withKeywords.isNotEmpty && !f.withKeywords.every(e.sourceChars.hasName)) return null;
          if (f.other && e.source == srcId) return null;
        } else if (!inSet(set, e.source, e.sourceChars)) {
          return null;
        }
        return EventInfo(obj: e.source, objZcc: srcObj.zcc, player: toP ? entityPlayer(e.target) : state.obj(e.target).controller, amount: e.amount, objName: e.sourceChars.name, objPower: e.sourceChars.power ?? 0, other: toP ? null : e.target);
      case IsDealtDamageTrigger(:final set):
        if (e is! DamageEvent || isPlayerEntity(e.target)) return null;
        if (!inSet(set, e.target, chars(e.target))) return null;
        return objInfo(e.target, state.obj(e.target).zcc, chars(e.target), amount: e.amount);
      case CastTrigger(:final who, :final filter, :final duringOpponentsTurn):
        if (e is! CastEvent) return null;
        if (!_whoOk(who, e.player, you)) return null;
        if (duringOpponentsTurn && state.active == you) return null;
        if (!matchesFilter(filter.copyWith(zone: ZoneKind.stack, controller: Who.any), e.obj, ctx)) return null;
        final ch = chars(e.obj);
        return EventInfo(obj: e.obj, objZcc: state.obj(e.obj).zcc, player: e.player, amount: ch.manaValue, objName: ch.name, other: e.item);
      case StepTrigger(:final step, :final whose):
        if (e is! StepEvent || e.step != step) return null;
        if (!_whoOk(whose, e.active, you)) return null;
        return EventInfo(player: e.active);
      case GainLifeTrigger(:final who, :final firstTimeEachTurn, :final onlyYourTurn):
        if (e is! LifeEvent || !e.gain || !_whoOk(who, e.player, you)) return null;
        if (firstTimeEachTurn && e.nth != 1) return null;
        if (onlyYourTurn && state.active != you) return null;
        return EventInfo(player: e.player, amount: e.amount);
      case LoseLifeTrigger(:final who):
        if (e is! LifeEvent || e.gain || !_whoOk(who, e.player, you)) return null;
        return EventInfo(player: e.player, amount: e.amount);
      case DrawTrigger(:final who, :final nth):
        if (e is! DrawEvent || !_whoOk(who, e.player, you)) return null;
        if (nth > 0 && e.nth != nth) return null;
        return EventInfo(player: e.player, obj: e.card);
      case DiscardTrigger(:final who):
        if (e is! DiscardEvent || !_whoOk(who, e.player, you)) return null;
        return EventInfo(player: e.player, obj: e.card, objZcc: state.obj(e.card).zcc);
      case CountersPutTrigger(:final set, :final kind):
        if (e is! CountersEvent || e.kind != kind) return null;
        if (!inSet(set, e.obj, chars(e.obj))) return null;
        return EventInfo(obj: e.obj, objZcc: state.obj(e.obj).zcc, amount: e.n, player: e.by);
      case BecomesTargetTrigger(:final set, :final byOpponent):
        if (e is! TargetedEvent) return null;
        if (byOpponent && e.by == you) return null;
        if (!inSet(set, e.obj, chars(e.obj))) return null;
        return EventInfo(obj: e.obj, player: e.by, other: e.item);
      case BecomesUntappedTrigger(:final set):
        if (e is! UntapEvent || !inSet(set, e.obj, chars(e.obj))) return null;
        return EventInfo(obj: e.obj);
      case TokenCreatedTrigger():
        return null;
    }
  }

  bool _inSetLki(ObjSet set, ObjId id, Chars lki, ObjId srcId, EvalCtx ctx) {
    switch (set) {
      case One(:final ref):
        if (ref is SelfRef) return id == srcId;
        if (ref is AttachedTo) {
          final so = state.objOrNull(srcId);
          return so != null && so.lastAttached == id;
        }
        return false;
      case All(:final filter):
        if (filter.other && id == srcId) return false;
        final f = filter.copyWith(zone: ZoneKind.anywhere, other: false);
        return matchesFilter(f, id, ctx, ch: lki);
    }
  }

  bool _whoOk(Who w, PlayerId p, PlayerId you) => switch (w) { Who.any => true, Who.you => p == you, Who.opponent || Who.notYou => p != you };

  PlayerId? _defenderOf(ObjId attacker) {
    final a = state.obj(attacker).attacking;
    if (a == null) return null;
    return isPlayerEntity(a) ? entityPlayer(a) : state.obj(a).controller;
  }

  /// Ward and other "becomes the target" triggers.
  void _targetedEvents(StackItem item) {
    final seen = <ObjId>{};
    for (final list in item.targets) {
      for (final e in list) {
        if (isPlayerEntity(e) || !seen.add(e)) continue;
        final o = state.objOrNull(e);
        if (o == null || o.zone != Zone.battlefield) continue;
        _emit(TargetedEvent(e, item.controller, item.id));
        // Ward (CR 702.21): counter it unless that player pays.
        final c = chars(e);
        if (c.controller != item.controller) {
          for (final k in c.kws('ward')) {
            final ward = TriggeredAbility(
              'Ward',
              const BecomesTargetTrigger(One(SelfRef())),
              Body(effect: Unless(const CounterEventItem(), const EventPlayer(), mana: k.cost, life: k.lifeCost > 0 ? k.lifeCost : null)),
            );
            state.pendingTriggers.add(PendingTrigger(controller: c.controller, sourceId: e, sourceZcc: o.zcc, ability: ward, event: EventInfo(obj: e, player: item.controller, other: item.id), sourceName: c.name));
          }
        }
      }
    }
  }

  /// Puts waiting triggered abilities on the stack (CR 603.3b): APNAP, each player ordering
  /// their own, choosing modes and targets.
  void _putTriggersOnStack() {
    final waiting = List.of(state.pendingTriggers);
    state.pendingTriggers.clear();
    for (final p in state.apnap()) {
      var mine = [for (final t in waiting) if (t.controller == p) t];
      if (mine.isEmpty) continue;
      if (mine.length > 1 && mine.map((t) => t.ability.text).toSet().length > 1) {
        final order = ask(Decision(
          kind: DecisionKind.order,
          player: p,
          prompt: 'Order your triggered abilities (last resolves first)',
          options: List.generate(mine.length, (i) => i),
          labels: [for (final t in mine) '${t.sourceName}: ${t.ability.text}'],
        ));
        mine = [for (final i in order) mine[i]];
      }
      for (final t in mine) {
        final item = StackItem(id: state.nextId++, kind: StackKind.triggered, controller: p, sourceId: t.sourceId, sourceZcc: t.sourceZcc, ability: t.ability, event: t.event, sourceName: t.sourceName);
        final ctx = EvalCtx(this, controller: p, source: t.sourceId, sourceZcc: t.sourceZcc, event: t.event, item: item);
        // A triggered ability with no legal targets is removed (CR 603.3d).
        try {
          state.stack.add(item);
          _chooseModesAndTargets(p, item, t.ability.body, ctx, cancellable: false);
          final src = state.objOrNull(t.sourceId);
          if (src != null && t.sourceZcc == src.zcc) item.sourceLki = chars(t.sourceId).copy();
          _targetedEvents(item);
        } on GameError {
          state.stack.remove(item);
        }
      }
    }
    _dirty();
  }
}

