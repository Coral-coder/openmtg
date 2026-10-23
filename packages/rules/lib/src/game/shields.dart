part of 'game.dart';

/// Regeneration (CR 701.15) and prevention shields (CR 615.7), revealed hands (CR 701.20), coin
/// flips (CR 705) and dice (CR 706). Coins and dice use the game's seeded generator, so they
/// replay identically.
extension GameShields on Game {
  void _execShieldsAndChance(Effect e, EvalCtx ctx) {
    switch (e) {
      case Regenerate(:final set):
        for (final id in resolveObjs(set, ctx)) {
          final o = state.obj(id);
          if (o.zone != Zone.battlefield) continue;
          state.shields.add(Shield.regen(id, o.zcc));
        }
      case PreventNext(:final amount, :final target, :final set, :final toYou, :final by, :final combatOnly):
        final n = amount == null ? -1 : evalAmount(amount, ctx);
        if (n == 0) return;
        void shieldObj(ObjId id, {bool isBy = false}) => state.shields.add(Shield.prevent(id, state.obj(id).zcc, n, by: isBy, combatOnly: combatOnly));
        if (by != null) {
          for (final id in resolveObjs(by, ctx)) {
            shieldObj(id, isBy: true);
          }
        } else if (target != null) {
          if (target >= ctx.targets.length) return;
          for (final t in ctx.targets[target]) {
            if (isPlayerEntity(t)) {
              state.shields.add(Shield.prevent(t, 0, n, combatOnly: combatOnly));
            } else if (state.objOrNull(t) != null) {
              shieldObj(t);
            }
          }
        } else if (set != null) {
          for (final id in resolveObjs(set, ctx)) {
            shieldObj(id);
          }
        } else if (toYou) {
          state.shields.add(Shield.prevent(playerEntity(ctx.controller), 0, n, combatOnly: combatOnly));
        } else {
          state.shields.add(Shield.prevent(null, 0, n, combatOnly: combatOnly));
        }
      case RevealHand(:final who, :final filter, :final exile, :final optional):
        for (final p in resolvePlayers(who, ctx)) {
          final pl = state.player(p);
          _log('${pl.name} reveals their hand: ${pl.hand.isEmpty ? 'no cards' : pl.hand.map(nameOf).join(', ')}.', player: p);
          if (filter == null) continue;
          final options = [for (final id in pl.hand) if (matchesFilter(filter.copyWith(zone: ZoneKind.hand, owner: Who.any, controller: Who.any), id, ctx)) id];
          if (options.isEmpty) continue;
          final pick = ask(Decision(
              kind: DecisionKind.cards,
              player: ctx.controller,
              prompt: '${optional ? 'You may choose' : 'Choose'} a card for ${pl.name} to ${exile ? 'exile' : 'discard'}',
              options: options,
              min: optional ? 0 : 1,
              max: 1,
              source: ctx.source));
          ctx.results['did'] = pick.length;
          for (final id in pick) {
            if (exile) {
              _move(id, Zone.exile);
            } else {
              _discard(p, id);
            }
          }
        }
      case FlipCoin():
        final won = state.rng.nextInt(2) == 1;
        ctx.results['flip'] = won ? 1 : 0;
        _log('${state.player(ctx.controller).name} ${won ? 'wins' : 'loses'} the coin flip.', player: ctx.controller);
      case RollDie(:final sides, :final count):
        var total = 0;
        final rolls = <int>[];
        for (var i = 0; i < count; i++) {
          final r = state.rng.nextInt(sides) + 1;
          rolls.add(r);
          total += r;
        }
        ctx.results['roll'] = total;
        _log('${state.player(ctx.controller).name} rolls ${rolls.join(' and ')}.', player: ctx.controller);
      case Explore(:final set):
        for (final id in resolveObjs(set, ctx)) {
          final o = state.obj(id);
          final p = o.controller;
          final pl = state.player(p);
          if (pl.library.isEmpty) {
            if (o.zone == Zone.battlefield) _addCounters(id, '+1/+1', 1, by: p);
            continue;
          }
          final top = pl.library.first;
          _log('${pl.name} reveals ${nameOf(top)} (explore).', player: p, obj: top);
          if (chars(top).isLand) {
            _move(top, Zone.hand);
            continue;
          }
          if (state.obj(id).zone == Zone.battlefield) _addCounters(id, '+1/+1', 1, by: p);
          final pick = ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Explore: ${nameOf(top)}', labels: const ['Keep it on top', 'Put it into your graveyard'], source: ctx.source));
          if (pick.isNotEmpty && pick.first == 1) _move(top, Zone.graveyard);
        }
      default:
        break;
    }
    _dirty();
  }

  /// Uses a regeneration shield on [id] if it has one: tapped, damage removed, out of combat.
  bool _regenerate(ObjId id) {
    final o = state.obj(id);
    final i = state.shields.indexWhere((s) => s.regen && s.entity == id && s.zcc == o.zcc);
    if (i < 0) return false;
    state.shields.removeAt(i);
    _tap(id);
    o.damage = 0;
    o.deathtouched = false;
    _removeFromCombat(id);
    _log('${nameOf(id)} regenerates.', obj: id);
    _dirty();
    return true;
  }

  void _removeFromCombat(ObjId id) {
    final o = state.obj(id);
    o.attacking = null;
    for (final b in o.blockedBy) {
      state.objOrNull(b)?.blocking.remove(id);
    }
    for (final a in o.blocking) {
      state.objOrNull(a)?.blockedBy.remove(id);
    }
    o.blocking = [];
    o.blockedBy = [];
  }

  /// Applies prevention shields to [n] damage from [source] to [target]; returns what's left.
  int _shieldPrevent(ObjId source, int target, int n, bool combat) {
    if (state.shields.isEmpty) return n;
    final targetZcc = isPlayerEntity(target) ? 0 : state.obj(target).zcc;
    final sourceZcc = state.objOrNull(source)?.zcc;
    var left = n;
    for (var i = 0; i < state.shields.length && left > 0; i++) {
      final s = state.shields[i];
      if (s.regen || (s.combatOnly && !combat)) continue;
      final applies = s.by ? (s.entity == source && s.zcc == sourceZcc) : (s.entity == null || (s.entity == target && s.zcc == targetZcc));
      if (!applies) continue;
      if (s.amount < 0) return 0;
      final used = s.amount < left ? s.amount : left;
      left -= used;
      state.shields[i] = s.withAmount(s.amount - used);
    }
    state.shields.removeWhere((s) => !s.regen && s.amount == 0);
    return left;
  }
}
