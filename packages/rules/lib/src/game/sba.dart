part of 'game.dart';

/// State-based actions (CR 704).
extension GameSba on Game {
  /// Performs state-based actions until none apply. True if any were performed.
  bool _stateBasedActions() {
    var any = false;
    for (var round = 0; round < 50; round++) {
      if (state.over) return any;
      final acts = _pendingSbas();
      if (acts.isEmpty) {
        if (_legendRuleApplies()) {
          _run(const SbaTask());
          return true;
        }
        return any;
      }
      any = true;
      for (final a in acts) {
        a();
      }
    }
    return any;
  }

  bool _sbaWouldApply() => _pendingSbas().isNotEmpty || _legendRuleApplies();

  List<void Function()> _pendingSbas() {
    final out = <void Function()>[];
    for (final pl in state.players) {
      if (pl.lost) continue;
      final cantLose = _hasRule<CantLoseGame>(pl.id);
      final opponentsCantWin = state.opponents(pl.id).any((q) => _hasRule<OpponentsCantWin>(q));
      if (cantLose || opponentsCantWin) continue;
      if (pl.life <= 0) out.add(() => _lose(pl.id, 'life total 0'));
      if (pl.drewFromEmpty) out.add(() => _lose(pl.id, 'drew from an empty library'));
      if (pl.poison >= 10) out.add(() => _lose(pl.id, 'ten poison counters'));
    }
    // 704.5d: tokens outside the battlefield cease to exist.
    for (final o in state.objects.values) {
      if (o.isToken && o.zone != Zone.battlefield && o.zone != Zone.stack) {
        final id = o.id;
        out.add(() {
          final x = state.objOrNull(id);
          if (x == null) return;
          _removeFromZone(x);
          state.objects.remove(id);
          _dirty();
        });
      }
    }
    for (final id in state.battlefield) {
      final o = state.obj(id);
      if (o.phasedOut) continue;
      final c = chars(id);
      if (c.isCreature) {
        final t = c.toughness ?? 0;
        if (t <= 0) {
          out.add(() => _move(id, Zone.graveyard));
          continue;
        }
        if ((o.damage >= t || (o.deathtouched && o.damage > 0)) && !c.has(Kw.indestructible)) {
          out.add(() => _destroy(id));
          continue;
        }
      }
      if (c.isPlaneswalker && (o.counters['loyalty'] ?? 0) <= 0) {
        out.add(() => _move(id, Zone.graveyard));
        continue;
      }
      if (c.isBattle && (o.counters['defense'] ?? 0) <= 0 && o.enteredTurn >= 0) {
        out.add(() => _move(id, Zone.graveyard));
        continue;
      }
      if (c.isAura) {
        final ok = o.attachedTo != null && state.objOrNull(o.attachedTo)?.zone == Zone.battlefield && _auraCanEnchant(id, o.attachedTo!);
        if (!ok) {
          out.add(() => _move(id, Zone.graveyard));
          continue;
        }
      }
      if (c.isEquipment && o.attachedTo != null) {
        final t = state.objOrNull(o.attachedTo);
        if (t == null || t.zone != Zone.battlefield || !chars(t.id).isCreature) out.add(() => o.attachedTo = null);
      }
      final plus = o.counters['+1/+1'] ?? 0, minus = o.counters['-1/-1'] ?? 0;
      if (plus > 0 && minus > 0) {
        out.add(() {
          final k = plus < minus ? plus : minus;
          _removeCounters(id, '+1/+1', k);
          _removeCounters(id, '-1/-1', k);
        });
      }
    }
    return out;
  }

  bool _auraCanEnchant(ObjId aura, ObjId target) {
    final enchant = chars(aura).abilities.whereType<EnchantAbility>().firstOrNull;
    if (enchant == null) return true;
    final tc = chars(target);
    for (final k in tc.kws('protection')) {
      if (_qualityMatches(k.filter!, chars(aura))) return false;
    }
    return matchesFilter(enchant.filter, target, EvalCtx(this, controller: chars(aura).controller, source: aura, sourceZcc: state.obj(aura).zcc));
  }

  /// Legendary permanents with the same name under one controller (CR 704.5j).
  Map<(PlayerId, String), List<ObjId>> _legendGroups() {
    final groups = <(PlayerId, String), List<ObjId>>{};
    for (final id in state.battlefield) {
      final c = chars(id);
      if (!c.isLegendary || state.obj(id).phasedOut) continue;
      groups.putIfAbsent((c.controller, c.name), () => []).add(id);
    }
    groups.removeWhere((_, v) => v.length < 2);
    return groups;
  }

  bool _legendRuleApplies() => _legendGroups().isNotEmpty;

  void _legendRule() {
    for (final e in _legendGroups().entries) {
      final keep = ask(Decision(kind: DecisionKind.cards, player: e.key.$1, prompt: 'Legend rule: choose the ${e.key.$2} to keep', options: e.value, min: 1, max: 1));
      for (final id in e.value) {
        if (id != keep.first) _move(id, Zone.graveyard);
      }
    }
  }
}
