part of 'game.dart';

/// Combat (CR 506–511): declaring attackers and blockers, and combat damage.
extension GameCombat on Game {
  List<ObjId> _attackers() => [for (final id in state.battlefield) if (state.obj(id).attacking != null) id];
  List<ObjId> _blockers() => [for (final id in state.battlefield) if (state.obj(id).blocking.isNotEmpty) id];
  List<ObjId> _combatants() => [..._attackers(), ..._blockers()];

  /// Creatures [p] could attack with now (CR 508.1a).
  List<ObjId> attackCandidates(PlayerId p) {
    final out = <ObjId>[];
    for (final id in state.battlefield) {
      final o = state.obj(id);
      final c = chars(id);
      if (c.controller != p || !c.isCreature || o.tapped || o.phasedOut) continue;
      if (_summoningSick(id)) continue;
      if (c.has(Kw.defender) || c.has(Kw.cantAttack) || c.has(Kw.cantAttackOrBlock)) continue;
      out.add(id);
    }
    return out;
  }

  /// Players and planeswalkers [p]'s creatures may attack.
  List<int> attackableBy(PlayerId p) => [
        for (final q in state.opponents(p)) playerEntity(q),
        for (final id in state.battlefield)
          if (chars(id).controller != p && (chars(id).isPlaneswalker || chars(id).isBattle)) id,
      ];

  void _declareAttackers() {
    final p = state.active;
    final cands = attackCandidates(p);
    if (cands.isEmpty) return;
    final targets = attackableBy(p);
    if (targets.isEmpty) return;
    // What each creature may attack ("can't attack unless defending player controls an Island").
    final per = <ObjId, List<int>>{};
    for (final id in cands) {
      final only = chars(id).kws('attacks only if defender controls').toList();
      per[id] = [
        for (final t in targets)
          if (only.every((k) => _defenderControls(t, k.filter!))) t,
      ];
    }
    final able = [for (final id in cands) if (per[id]!.isNotEmpty) id];
    if (able.isEmpty) return;
    final must = [for (final id in able) if (chars(id).has(Kw.attacksEachCombat)) id];
    final answer = ask(Decision(
      kind: DecisionKind.attackers,
      player: p,
      prompt: 'Declare attackers',
      options: able,
      max: able.length,
      extra: {for (final id in able) '$id': per[id]!, 'must': must},
    ));
    final chosen = <ObjId, int>{};
    for (var i = 0; i + 1 < answer.length; i += 2) {
      final a = answer[i], t = answer[i + 1];
      if (!able.contains(a) || !per[a]!.contains(t) || chosen.containsKey(a)) throw GameError('Illegal attack');
      chosen[a] = t;
    }
    for (final m in must) {
      if (!chosen.containsKey(m)) throw GameError('${chars(m).name} attacks each combat if able');
    }
    if (chosen.length == 1 && chars(chosen.keys.first).has(Kw.cantAttackAlone)) throw GameError("${chars(chosen.keys.first).name} can't attack alone");
    if (chosen.isEmpty) return;
    for (final e in chosen.entries) {
      final o = state.obj(e.key);
      if (!chars(e.key).has(Kw.vigilance)) _tap(e.key);
      o.attacking = e.value;
    }
    final st = state.player(p).stats;
    st.attacked = true;
    st.creaturesAttackedWith += chosen.length;
    _log('${state.player(p).name} attacks with ${chosen.keys.map(nameOf).join(', ')}.', player: p, kind: 'attack');
    _emit(AttackEvent(p, chosen.keys.toList()));
    _dirty();
  }

  /// Does the player (or the controller of the planeswalker or battle) [entity] control a
  /// permanent matching [f]?
  bool _defenderControls(int entity, Filter f) {
    final p = entity < 0 ? entityPlayer(entity) : chars(entity).controller;
    final ctx = EvalCtx(this, controller: p);
    return state.battlefield.any((id) => chars(id).controller == p && matchesFilter(f, id, ctx));
  }

  /// Can [blocker] block [attacker] (CR 509.1b)?
  bool canBlock(ObjId blocker, ObjId attacker) {
    final b = chars(blocker), a = chars(attacker);
    if (!b.isCreature || state.obj(blocker).tapped) return false;
    if (b.has(Kw.cantBlock) || b.has(Kw.cantAttackOrBlock)) return false;
    if (a.has(Kw.unblockable)) return false;
    if (a.has(Kw.flying) && !b.has(Kw.flying) && !b.has(Kw.reach)) return false;
    if (b.has(Kw.blocksOnlyFlying) && !a.has(Kw.flying)) return false;
    // Evasion keywords (CR 702.14, 702.28, 702.36, 702.13, 702.31, 702.118).
    if (b.hasName('shadow') != a.hasName('shadow')) return false;
    if (a.hasName('horsemanship') && !b.hasName('horsemanship')) return false;
    if (a.hasName('fear') && !b.isArtifact && !b.colors.contains(ManaColor.black)) return false;
    if (a.hasName('intimidate') && !b.isArtifact && !b.colors.any(a.colors.contains)) return false;
    if (a.hasName('skulk') && (b.power ?? 0) > (a.power ?? 0)) return false;
    for (final k in a.kws('landwalk')) {
      final ctx = EvalCtx(this, controller: b.controller);
      if (state.battlefield.any((id) => chars(id).controller == b.controller && matchesFilter(k.filter!, id, ctx))) return false;
    }
    for (final k in a.kws("can't be blocked by")) {
      if (_qualityMatches(k.filter!, b)) return false;
    }
    for (final k in a.kws('protection')) {
      if (_qualityMatches(k.filter!, b)) return false;
    }
    return true;
  }

  void _declareBlockers() {
    final attackers = _attackers();
    if (attackers.isEmpty) return;
    final defenders = <PlayerId>{};
    for (final a in attackers) {
      final d = _defenderOf(a);
      if (d != null) defenders.add(d);
    }
    for (final d in state.apnap()) {
      if (!defenders.contains(d)) continue;
      final mine = [for (final a in attackers) if (_defenderOf(a) == d) a];
      final cands = <ObjId>[];
      final extra = <String, Object>{};
      for (final id in state.battlefield) {
        if (chars(id).controller != d) continue;
        final can = [for (final a in mine) if (canBlock(id, a)) a];
        if (can.isEmpty) continue;
        cands.add(id);
        extra['$id'] = can;
      }
      if (cands.isEmpty) continue;
      final answer = ask(Decision(kind: DecisionKind.blockers, player: d, prompt: 'Declare blockers', options: cands, max: cands.length, extra: extra));
      final blocks = <ObjId, ObjId>{};
      for (var i = 0; i + 1 < answer.length; i += 2) {
        final b = answer[i], a = answer[i + 1];
        if (!cands.contains(b) || !(extra['$b'] as List).contains(a) || blocks.containsKey(b)) throw GameError('Illegal block');
        blocks[b] = a;
      }
      // Menace (CR 702.111b): blocked by two or more, or not at all.
      for (final a in mine) {
        final n = blocks.values.where((x) => x == a).length;
        if (n == 1 && chars(a).has(Kw.menace)) throw GameError('${chars(a).name} has menace: block it with two or more creatures');
        if (n > 1 && chars(a).has(Kw.maxOneBlocker)) throw GameError("${chars(a).name} can't be blocked by more than one creature");
      }
      if (blocks.length == 1 && chars(blocks.keys.first).has(Kw.cantBlockAlone)) throw GameError("${chars(blocks.keys.first).name} can't block alone");
      for (final e in blocks.entries) {
        final bo = state.obj(e.key), ao = state.obj(e.value);
        bo.blocking = [e.value];
        ao.blockedBy.add(e.key);
        ao.blocked = true;
      }
      if (blocks.isNotEmpty) _log('${state.player(d).name} blocks: ${blocks.entries.map((e) => '${nameOf(e.key)} → ${nameOf(e.value)}').join(', ')}.', player: d, kind: 'block');
      // Flanking (CR 702.25): each blocker without flanking gets -1/-1 until end of turn.
      for (final e in blocks.entries) {
        final a = chars(e.value), b = chars(e.key);
        if (b.hasName('flanking')) continue;
        for (final _ in a.kws('flanking')) {
          state.pendingTriggers.add(PendingTrigger(
            controller: a.controller,
            sourceId: e.value,
            sourceZcc: state.obj(e.value).zcc,
            ability: const TriggeredAbility('flanking', BecomesBlockedTrigger(One(SelfRef())), Body(effect: Grant(One(EventObj()), [ModPT(Fixed(-1), Fixed(-1))]))),
            event: EventInfo(obj: e.key, objZcc: state.obj(e.key).zcc, player: b.controller),
            sourceName: a.name,
          ));
        }
      }
      for (final e in blocks.entries) {
        _emit(BlockEvent(e.key, e.value));
      }
    }
    _dirty();
  }

  bool _dealsDamageThisStep(ObjId id, bool firstStrike) {
    final c = chars(id);
    final fs = c.has(Kw.firstStrike) || c.has(Kw.doubleStrike);
    if (firstStrike) return fs;
    if (c.has(Kw.doubleStrike)) return true;
    return !fs && !state.obj(id).dealtFirstStrikeDamage;
  }

  /// Lethal damage for assignment purposes (CR 510.1c–d).
  int _lethalFor(ObjId blocker, Chars attacker) {
    final c = chars(blocker);
    final left = (c.toughness ?? 0) - state.obj(blocker).damage;
    if (attacker.has(Kw.deathtouch)) return left > 0 ? 1 : 0;
    return left.clamp(0, 1 << 30);
  }

  void _combatDamage(bool firstStrike) {
    final assignments = <(ObjId, int, int)>[]; // source, target entity, amount
    for (final a in _attackers()) {
      if (!_dealsDamageThisStep(a, firstStrike)) continue;
      final ac = chars(a);
      final power = ac.power ?? 0;
      if (power <= 0) continue;
      final ao = state.obj(a);
      final defender = ao.attacking!;
      final defenderOk = isPlayerEntity(defender) ? !state.player(entityPlayer(defender)).lost : state.objOrNull(defender)?.zone == Zone.battlefield;
      if (!ao.blocked) {
        if (defenderOk) assignments.add((a, defender, power));
        continue;
      }
      final blockers = [for (final b in ao.blockedBy) if (state.objOrNull(b)?.zone == Zone.battlefield && state.obj(b).blocking.contains(a)) b];
      final trample = ac.has(Kw.trample);
      if (blockers.isEmpty) {
        if (trample && defenderOk) assignments.add((a, defender, power));
        continue;
      }
      if (blockers.length == 1 && !trample) {
        assignments.add((a, blockers.first, power));
        continue;
      }
      final lethal = {for (final b in blockers) b: _lethalFor(b, ac)};
      final answer = ask(Decision(
        kind: DecisionKind.damage,
        player: ac.controller,
        prompt: 'Assign ${ac.name}\'s $power combat damage',
        options: [...blockers, if (trample && defenderOk) defender],
        source: a,
        extra: {'power': power, 'trample': trample, 'defender': defender, for (final b in blockers) 'lethal$b': lethal[b]!},
      ));
      final split = answer.isEmpty ? _autoAssign(blockers, lethal, power, trample && defenderOk ? defender : null) : _validateAssignment(answer, blockers, lethal, power, trample && defenderOk ? defender : null);
      for (final e in split.entries) {
        if (e.value > 0) assignments.add((a, e.key, e.value));
      }
    }
    for (final b in _blockers()) {
      if (!_dealsDamageThisStep(b, firstStrike)) continue;
      final bc = chars(b);
      final power = bc.power ?? 0;
      if (power <= 0) continue;
      final target = state.obj(b).blocking.first;
      if (state.objOrNull(target)?.zone != Zone.battlefield) continue;
      assignments.add((b, target, power));
    }
    // All combat damage is dealt at once (CR 510.2).
    final srcChars = {for (final (s, _, _) in assignments) s: chars(s).copy()};
    for (final (s, t, n) in assignments) {
      _dealDamage(s, srcChars[s]!, t, n, combat: true);
    }
    if (firstStrike) {
      for (final (s, _, _) in assignments) {
        state.objOrNull(s)?.dealtFirstStrikeDamage = true;
      }
    }
    _dirty();
  }

  Map<int, int> _autoAssign(List<ObjId> blockers, Map<ObjId, int> lethal, int power, int? defender) {
    final out = <int, int>{};
    var left = power;
    for (final b in blockers) {
      final k = left < lethal[b]! ? left : lethal[b]!;
      out[b] = k;
      left -= k;
    }
    if (left > 0) {
      if (defender != null) {
        out[defender] = left;
      } else {
        out[blockers.last] = (out[blockers.last] ?? 0) + left;
      }
    }
    return out;
  }

  Map<int, int> _validateAssignment(List<int> answer, List<ObjId> blockers, Map<ObjId, int> lethal, int power, int? defender) {
    final out = <int, int>{};
    var total = 0;
    for (var i = 0; i + 1 < answer.length; i += 2) {
      final t = answer[i], n = answer[i + 1];
      if (n < 0 || !(blockers.contains(t) || t == defender)) throw GameError('Illegal damage assignment');
      out[t] = (out[t] ?? 0) + n;
      total += n;
    }
    if (total != power) throw GameError('Assign exactly $power damage');
    if (defender != null && (out[defender] ?? 0) > 0) {
      for (final b in blockers) {
        if ((out[b] ?? 0) < lethal[b]!) throw GameError('Assign lethal damage to every blocker before trampling over');
      }
    }
    return out;
  }

  void _endCombat() {
    for (final id in state.battlefield) {
      final o = state.obj(id);
      o.attacking = null;
      o.blocking = [];
      o.blockedBy = [];
      o.blocked = false;
      o.dealtFirstStrikeDamage = false;
    }
    state.combatHasFirstStrike = false;
    _dirty();
  }
}
