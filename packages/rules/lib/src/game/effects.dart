part of 'game.dart';

/// Resolving spells and abilities (CR 608) and the effect interpreter (CR 700–701), with zone
/// changes, damage and token creation through replacement effects (CR 614–616).
extension GameEffects on Game {
  // -------------------------------------------------------------------------------------------
  // Resolution (CR 608)
  // -------------------------------------------------------------------------------------------

  void _resolveTop() {
    if (state.stack.isEmpty) return;
    final item = state.stack.removeLast();
    final src = state.objOrNull(item.sourceId);
    final ctx = EvalCtx(this,
        controller: item.controller,
        source: item.sourceId,
        sourceZcc: item.sourceZcc,
        targets: [for (final t in item.targets) List.of(t)],
        targetZcc: [for (final t in item.targetZcc) List.of(t)],
        x: item.x,
        kicked: item.kicked,
        event: item.event,
        item: item,
        sourceLki: item.sourceLki ?? (src != null && src.zcc == item.sourceZcc ? chars(item.sourceId).copy() : null),
        wasCast: src?.wasCast ?? false);
    final ab = item.ability;
    final body = switch (ab) { SpellAbility(:final body) => body, ActivatedAbility(:final body) => body, TriggeredAbility(:final body) => body, _ => const Body() };

    // 608.2b: targets that became illegal are ignored; with no legal target left it fizzles.
    final specs = <TargetSpec>[];
    for (final mi in item.modes) {
      specs.addAll(body.isModal ? (mi < body.modes.length ? body.modes[mi].targets : const []) : body.targets);
    }
    if (item.kind == StackKind.spell && ab == null && item.targets.isNotEmpty) {
      // An Aura spell's target.
      final enchant = src == null ? null : chars(src.id).abilities.whereType<EnchantAbility>().firstOrNull;
      if (enchant != null) specs.add(TargetSpec(enchant.player ? TargetKind.player : TargetKind.object, filter: enchant.filter));
    }
    var anyTargets = false, anyLegal = false;
    for (var i = 0; i < ctx.targets.length && i < specs.length; i++) {
      for (var j = 0; j < ctx.targets[i].length; j++) {
        anyTargets = true;
        final e = ctx.targets[i][j];
        if (_stillLegalTarget(specs[i], e, i < ctx.targetZcc.length && j < ctx.targetZcc[i].length ? ctx.targetZcc[i][j] : 0, ctx, spell: item.objId)) {
          anyLegal = true;
        } else {
          ctx.targets[i][j] = 0x7fffffff; // never resolves to an object
        }
      }
    }
    if (anyTargets && !anyLegal) {
      _log('${item.sourceName} has no legal targets and does nothing.', obj: item.objId);
      if (item.objId != null) _finishSpell(item, countered: true);
      _dirty();
      return;
    }

    if (item.kind == StackKind.spell && item.objId != null && src != null && chars(src.id).isPermanentCard) {
      _log('${item.sourceName} resolves.', obj: item.objId, kind: 'resolve');
      final auraTarget = item.targets.isNotEmpty && item.targets.first.isNotEmpty && chars(src.id).isAura ? item.targets.first.first : null;
      _putOntoBattlefield(src.id, item.controller, attachTo: auraTarget);
      _dirty();
      return;
    }
    if (ab is TriggeredAbility && ab.condition != null && !evalCondition(ab.condition!, ctx)) {
      // The intervening "if" is checked again (CR 603.4).
      return;
    }
    if (ab is TriggeredAbility && ab.optionalCost != null) {
      final can = canAfford(item.controller, ab.optionalCost!);
      final pay = can ? ask(Decision(kind: DecisionKind.yesNo, player: item.controller, prompt: '${item.sourceName}: pay ${ab.optionalCost!.text}?', labels: const ['No', 'Pay'], source: item.sourceId)).first == 1 : false;
      if (!pay) return;
      _payMana(item.controller, ab.optionalCost!, prompt: item.sourceName);
    }
    if (item.kind != StackKind.spell) _log('${item.sourceName}: ${_short(ab?.text ?? '')}', obj: item.sourceId, kind: 'ability');
    // Modes run in order, each with its own slice of the targets.
    if (body.isModal) {
      var offset = 0;
      final all = ctx.targets, allZ = ctx.targetZcc;
      for (final mi in item.modes) {
        final m = body.modes[mi];
        ctx.targets = all.sublist(offset.clamp(0, all.length), (offset + m.targets.length).clamp(0, all.length));
        ctx.targetZcc = allZ.sublist(offset.clamp(0, allZ.length), (offset + m.targets.length).clamp(0, allZ.length));
        offset += m.targets.length;
        _exec(m.effect, ctx);
      }
    } else {
      _exec(body.effect, ctx);
    }
    if (item.objId != null) _finishSpell(item);
    _dirty();
  }

  String _short(String t) => t.length > 80 ? '${t.substring(0, 77)}…' : t;

  bool _stillLegalTarget(TargetSpec spec, int e, int zcc, EvalCtx ctx, {ObjId? spell}) {
    if (isPlayerEntity(e)) return !state.player(entityPlayer(e)).lost;
    final o = state.objOrNull(e);
    if (o == null || o.zcc != zcc) return false;
    return legalTargets(spec, ctx, spell: spell).contains(e);
  }

  /// An instant or sorcery leaves the stack: to the graveyard, or exile (flashback), or gone (copy).
  void _finishSpell(StackItem item, {bool countered = false}) {
    final id = item.objId!;
    final o = state.objOrNull(id);
    if (o == null || o.zone != Zone.stack) return;
    if (item.isCopy) {
      o.zone = Zone.none;
      state.objects.remove(id);
      return;
    }
    if (o.exileOnResolve) {
      _move(id, Zone.exile);
    } else if (!countered && o.face == 1 && db[o.cardName]?.layout == Layout.adventure && chars(id).subtypes.contains('Omen')) {
      // A resolved Omen is shuffled into its owner's library instead.
      if (_move(id, Zone.library) == Zone.library) _shuffle(o.owner);
    } else if (!countered && o.face == 1 && db[o.cardName]?.layout == Layout.adventure) {
      // A resolved Adventure is exiled, and its caster may cast the creature later (CR 715.4).
      if (_move(id, Zone.exile) == Zone.exile) {
        o.adventureBy = item.controller;
        _log('${state.player(item.controller).name} may cast ${o.cardName.split(' // ').first} from exile.', obj: id);
      }
    } else {
      _move(id, Zone.graveyard);
    }
  }

  // -------------------------------------------------------------------------------------------
  // Moving objects (CR 400.7, 614 replacements, 603.6 zone-change triggers)
  // -------------------------------------------------------------------------------------------

  /// Moves an object with replacement effects and zone-change triggers. Returns its new zone.
  Zone _move(ObjId id, Zone to, {bool bottom = false, PlayerId? controller, bool sacrificed = false, int? libraryIndex}) {
    final o = state.objOrNull(id);
    if (o == null) return Zone.none;
    final from = o.zone;
    final lki = chars(id).copy();
    final counters = Map.of(o.counters);
    final damagedBy = List.of(o.damagedBy);
    final oldZcc = o.zcc;
    var dest = to;
    var shuffle = false;
    if (dest == Zone.graveyard) {
      if (from == Zone.battlefield && o.exileIfDies && lki.isCreature) dest = Zone.exile;
      for (final a in lki.abilities) {
        if (a is ReplacementAbility && a.replacement is InsteadOfGraveyard) {
          final r = a.replacement as InsteadOfGraveyard;
          if (r.set is One && (r.set as One).ref is SelfRef && (!r.onlyFromBattlefield || from == Zone.battlefield)) {
            dest = zoneOfKind(r.to);
            shuffle = r.shuffleIntoLibrary;
          }
        }
      }
    }
    final untilLeaves = from == Zone.battlefield ? List.of(o.exiledUntilLeaves) : const <ObjId>[];
    _moveTo(id, dest, bottom: bottom, controller: dest == Zone.battlefield ? controller : null, libraryIndex: libraryIndex);
    if (shuffle) _shuffle(o.owner);
    if (from == Zone.battlefield && dest == Zone.graveyard && lki.isCreature) state.creaturesDiedThisTurn++;
    if (from == Zone.battlefield) {
      final what = dest == Zone.graveyard ? (sacrificed ? 'is sacrificed' : (lki.isCreature ? 'dies' : 'goes to the graveyard')) : (dest == Zone.exile ? 'is exiled' : (dest == Zone.hand ? 'returns to its owner\'s hand' : 'leaves the battlefield'));
      _log('${lki.name} $what.', obj: id, kind: 'leave');
    }
    _emit(ZoneEvent(id, oldZcc, o.zcc, from, dest, lki, counters: counters, sacrificed: sacrificed, damagedBy: damagedBy));
    for (final x in untilLeaves) {
      final xo = state.objOrNull(x);
      if (xo != null && xo.zone == Zone.exile) _putOntoBattlefield(x, xo.owner);
    }
    return dest;
  }

  void _sacrifice(ObjId id) {
    final o = state.obj(id);
    if (o.zone != Zone.battlefield) return;
    _move(id, Zone.graveyard, sacrificed: true);
  }

  /// Destroys a permanent unless it's indestructible (CR 701.8) or regenerates (CR 701.15).
  bool _destroy(ObjId id, {bool noRegen = false}) {
    final o = state.objOrNull(id);
    if (o == null || o.zone != Zone.battlefield) return false;
    if (chars(id).has(Kw.indestructible)) return false;
    if (!noRegen && _regenerate(id)) return false;
    _move(id, Zone.graveyard);
    return true;
  }

  /// Puts a card or token onto the battlefield with entering replacement effects (CR 614.1c–d).
  void _putOntoBattlefield(ObjId id, PlayerId controller, {int face = 0, bool tapped = false, Map<String, int> counters = const {}, ObjId? attachTo, bool attacking = false, List<String> extraTypes = const []}) {
    final o = state.obj(id);
    final wasCast = o.zone == Zone.stack && o.wasCast;
    final kicked = o.zone == Zone.stack && o.kicked;
    final x = o.zone == Zone.stack ? o.x : 0;
    final from = o.zone;
    final lki = chars(id).copy();
    // A modal double-faced spell enters with the face it was cast as up (CR 712.14); anything
    // else enters front face up unless told otherwise.
    final mdfc = !o.isToken && db[o.cardName]?.layout == Layout.modalDfc;
    final enterFace = from == Zone.stack && mdfc ? o.face : face;
    o.face = enterFace;
    final oldZcc = o.zcc;
    // What it will be on the battlefield (its own abilities apply to how it enters).
    final ctxSelf = EvalCtx(this, controller: controller, source: id, sourceZcc: o.zcc + 1, x: x, kicked: kicked, wasCast: wasCast);
    var entersTapped = tapped;
    final extra = <String, int>{...counters};
    String? chooseColor, chooseType;
    final self = _baseChars(o);
    for (final a in self.abilities) {
      if (a is! ReplacementAbility) continue;
      switch (a.replacement) {
        case EntersTapped(:final set) when set is One:
          entersTapped = true;
        case EntersWithCounters(:final set, :final kind, :final amount, :final condition) when set is One:
          if (condition == null || evalCondition(condition, ctxSelf)) extra[kind] = (extra[kind] ?? 0) + evalAmount(amount, ctxSelf);
        case ChooseOnEnter(:final what):
          if (what == 'color') chooseColor = what;
          if (what == 'creature type') chooseType = what;
        default:
      }
    }
    // Other permanents' replacements ("creatures your opponents control enter tapped").
    for (final pid in state.battlefield) {
      final pc = chars(pid);
      for (final a in pc.abilities) {
        if (a is! ReplacementAbility) continue;
        final r = a.replacement;
        final rctx = EvalCtx(this, controller: pc.controller, source: pid, sourceZcc: state.obj(pid).zcc);
        final ch = self..controller = controller;
        if (r is EntersTapped && r.set is All && _filterMatchesEntering((r.set as All).filter, ch, rctx, id)) entersTapped = true;
        if (r is ExtraCountersOnEnter && r.set is All && _filterMatchesEntering((r.set as All).filter, ch, rctx, id)) {
          extra[r.kind] = (extra[r.kind] ?? 0) + evalAmount(r.amount, rctx);
        }
      }
    }
    if (chooseColor != null) {
      final pick = ask(Decision(kind: DecisionKind.option, player: controller, prompt: 'Choose a color for ${self.name}', labels: [for (final c in ManaColor.values) c.word], source: id));
      chooseColor = ManaColor.values[pick.first].word;
    }
    if (chooseType != null) {
      final types = _commonCreatureTypes(controller);
      final pick = ask(Decision(kind: DecisionKind.option, player: controller, prompt: 'Choose a creature type for ${self.name}', labels: types, source: id));
      chooseType = types[pick.first];
    }
    _moveTo(id, Zone.battlefield, controller: controller);
    o.face = enterFace;
    o.wasCast = wasCast;
    o.kicked = kicked;
    o.x = x;
    o.tapped = entersTapped;
    o.extraTypes = List.of(extraTypes);
    if (chooseColor != null) o.chosenColor = chooseColor;
    if (chooseType != null) o.chosenType = chooseType;
    if (attacking) {
      o.attacking = _defaultAttackTarget(controller);
    }
    final c = chars(id);
    if (c.isPlaneswalker && (c.loyalty ?? 0) == 0) {
      final def = db[o.cardName];
      final printed = int.tryParse(def?.front.loyalty ?? '') ?? 0;
      if (printed > 0) extra['loyalty'] = (extra['loyalty'] ?? 0) + printed;
    }
    if (c.isBattle) {
      final def = db[o.cardName];
      final printed = int.tryParse(def?.front.defense ?? '') ?? 0;
      if (printed > 0) extra['defense'] = printed;
    }
    if (attachTo != null && state.objOrNull(attachTo)?.zone == Zone.battlefield) o.attachedTo = attachTo;
    _log('${c.name} enters${entersTapped ? ' tapped' : ''}.', obj: id, kind: 'enter');
    _emit(ZoneEvent(id, oldZcc, o.zcc, from, Zone.battlefield, lki));
    for (final e in extra.entries) {
      _addCounters(id, e.key, e.value, by: controller);
    }
    _dirty();
  }

  bool _filterMatchesEntering(Filter f, Chars ch, EvalCtx ctx, ObjId id) {
    if (f.other && id == ctx.source) return false;
    if (f.types.isNotEmpty && !f.types.any(ch.types.contains)) return false;
    if (f.subtypes.isNotEmpty && !f.subtypes.any(ch.hasSubtype)) return false;
    if (f.controller == Who.you && ch.controller != ctx.controller) return false;
    if (f.controller == Who.opponent && ch.controller == ctx.controller) return false;
    return true;
  }

  List<String> _commonCreatureTypes(PlayerId p) {
    final counts = <String, int>{};
    for (final id in [...state.player(p).library, ...state.player(p).hand, ...state.battlefield]) {
      final o = state.obj(id);
      if (o.owner != p) continue;
      for (final s in chars(id).isCreature ? chars(id).subtypes : const <String>[]) {
        counts[s] = (counts[s] ?? 0) + 1;
      }
    }
    final list = counts.keys.toList()..sortStable((a, b) => counts[b]! != counts[a]! ? counts[b]! - counts[a]! : a.compareTo(b));
    for (final t in const ['Human', 'Elf', 'Goblin', 'Zombie', 'Cat', 'Angel', 'Dragon', 'Wizard', 'Soldier', 'Knight']) {
      if (!list.contains(t)) list.add(t);
    }
    return list;
  }

  int? _defaultAttackTarget(PlayerId controller) {
    final opp = state.opponents(controller);
    return opp.isEmpty ? null : playerEntity(opp.first);
  }

  // -------------------------------------------------------------------------------------------
  // Damage (CR 120), with prevention (615) and doubling
  // -------------------------------------------------------------------------------------------

  /// Deals damage; returns the amount actually dealt.
  int _dealDamage(ObjId source, Chars src, int target, int amount, {bool combat = false}) {
    if (amount <= 0) return 0;
    var n = amount;
    final toPlayer = isPlayerEntity(target);
    final targetController = toPlayer ? entityPlayer(target) : state.obj(target).controller;
    // Doubling (Twinflame Tyrant) — the affected player or controller's choice of order is
    // moot for doubling, so they apply in timestamp order.
    for (final (r, ctl, _) in _replacements<DoubleDamage>()) {
      if (src.controller == ctl && (!r.toOpponentsOnly || targetController != ctl)) n *= 2;
    }
    // Prevention.
    if (!toPlayer) {
      final tc = chars(target);
      for (final k in tc.kws('protection')) {
        if (_qualityMatches(k.filter!, src)) return 0;
      }
    }
    for (final (r, ctl, pid) in _replacements<PreventDamage>()) {
      if (r.combat != null && r.combat != combat) continue;
      final rctx = EvalCtx(this, controller: ctl, source: pid, sourceZcc: state.obj(pid).zcc);
      if (r.toYou) {
        if (toPlayer && entityPlayer(target) == ctl) return 0;
        continue;
      }
      if (!toPlayer && resolveObjs(r.set, rctx).contains(target)) return 0;
    }
    n = _shieldPrevent(source, target, n, combat);
    if (n <= 0) return 0;
    if (toPlayer) {
      final p = entityPlayer(target);
      state.player(p).stats.damageTaken += n;
      if (src.hasName('infect')) {
        state.player(p).poison += n;
      } else {
        _loseLife(p, n);
      }
      // Toxic (CR 702.164): combat damage to a player also gives poison counters.
      if (combat) {
        for (final k in src.kws('toxic')) {
          state.player(p).poison += k.n;
        }
      }
    } else {
      final o = state.obj(target);
      final tc = chars(target);
      if (tc.isCreature) {
        if (src.hasName('infect') || src.hasName('wither')) {
          o.counters['-1/-1'] = (o.counters['-1/-1'] ?? 0) + n;
        } else {
          o.damage += n;
        }
        if (src.has(Kw.deathtouch)) o.deathtouched = true;
        if (!o.damagedBy.contains(source)) o.damagedBy.add(source);
      }
      if (tc.isPlaneswalker) _removeCounters(target, 'loyalty', n);
      if (tc.isBattle) _removeCounters(target, 'defense', n);
    }
    if (src.has(Kw.lifelink)) _gainLife(src.controller, n);
    _emit(DamageEvent(source, target, n, combat: combat, sourceController: src.controller, sourceChars: src));
    _dirty();
    return n;
  }

  Chars _sourceChars(EvalCtx ctx, ObjRef ref) {
    final ids = _ref(ref, ctx);
    if (ids.isNotEmpty) return chars(ids.first);
    if (ref is SelfRef && ctx.sourceLki != null) return ctx.sourceLki!;
    if (ctx.source != null && state.objOrNull(ctx.source) != null) return chars(ctx.source!);
    return Chars(name: 'Effect', types: {}, subtypes: [], supertypes: {}, colors: {}, manaCost: null, power: 0, toughness: 0, loyalty: null, defense: null, abilities: [], controller: ctx.controller, owner: ctx.controller);
  }

  ObjId _sourceId(EvalCtx ctx, ObjRef ref) {
    final ids = _ref(ref, ctx);
    return ids.isNotEmpty ? ids.first : (ctx.source ?? 0);
  }

  // -------------------------------------------------------------------------------------------
  // The interpreter
  // -------------------------------------------------------------------------------------------

  void _exec(Effect e, EvalCtx ctx) {
    _dirty();
    switch (e) {
      case Seq(:final steps):
        for (final s in steps) {
          _exec(s, ctx);
        }
      case May(:final effect, :final who):
        final ps = resolvePlayers(who, ctx);
        final p = ps.isEmpty ? ctx.controller : ps.first;
        final yes = ask(Decision(kind: DecisionKind.yesNo, player: p, prompt: _mayPrompt(effect, ctx), labels: const ['No', 'Yes'], source: ctx.source));
        ctx.didIt = yes.first == 1;
        if (ctx.didIt) {
          final before = state.version;
          _exec(effect, ctx);
          // "If you do" depends on having actually done it (sacrificed, discarded...).
          if (effect is Sacrifice || effect is Discard) ctx.didIt = ctx.results['did'] != 0 && state.version != before;
        }
      case If(:final cond, :final then, :final otherwise):
        if (evalCondition(cond, ctx)) {
          _exec(then, ctx);
        } else if (otherwise != null) {
          _exec(otherwise, ctx);
        }
      case Unless(:final effect, :final payer, :final mana, :final life, :final alternative):
        for (final p in resolvePlayers(payer, ctx)) {
          var paid = false;
          final canMana = mana != null && canAfford(p, mana);
          final canLife = life != null && state.player(p).life >= life;
          if (canMana || canLife || alternative != null) {
            final labels = ['Decline', if (canMana) 'Pay ${mana.text}', if (canLife) 'Pay $life life', if (alternative != null) 'Do the alternative'];
            final pick = ask(Decision(kind: DecisionKind.option, player: p, prompt: '${ctx.sourceLki?.name ?? 'Effect'}: pay to avoid it?', labels: labels, source: ctx.source));
            final choice = labels[pick.first];
            if (choice.startsWith('Pay ') && choice.endsWith('life')) {
              _loseLife(p, life!);
              paid = true;
            } else if (choice.startsWith('Pay ')) {
              _payMana(p, mana!, prompt: 'Pay');
              paid = true;
            } else if (choice == 'Do the alternative') {
              final sub = ctx.withThatPlayer(p);
              _exec(alternative!, sub);
              paid = sub.results['did'] != 0;
            }
          }
          if (!paid) _exec(effect, ctx.withThatPlayer(p));
        }
      case ForEachPlayer(:final players, :final effect):
        for (final p in resolvePlayers(players, ctx)) {
          _exec(effect, ctx.withThatPlayer(p));
        }
      case DealDamage(:final amount, :final to, :final toPlayers, :final source, :final excessSlot):
        final n = evalAmount(amount, ctx);
        final src = _sourceChars(ctx, source);
        final sid = _sourceId(ctx, source);
        if (to != null) {
          for (final id in resolveObjs(to, ctx)) {
            final before = chars(id);
            final lethal = before.isCreature ? ((before.toughness ?? 0) - state.obj(id).damage).clamp(0, 1 << 30) : 0;
            final dealt = _dealDamage(sid, src, id, n);
            if (excessSlot != null) ctx.results[excessSlot] = (dealt - lethal).clamp(0, 1 << 30);
          }
        }
        if (toPlayers != null) {
          for (final p in resolvePlayers(toPlayers, ctx)) {
            _dealDamage(sid, src, playerEntity(p), n);
          }
        }
      case DamageTarget(:final amount, :final index, :final source):
        final n = evalAmount(amount, ctx);
        final src = _sourceChars(ctx, source);
        final sid = _sourceId(ctx, source);
        if (index < ctx.targets.length) {
          for (var i = 0; i < ctx.targets[index].length; i++) {
            final t = ctx.targets[index][i];
            if (isPlayerEntity(t)) {
              if (!state.player(entityPlayer(t)).lost) _dealDamage(sid, src, t, n);
            } else if (state.objOrNull(t)?.zone == Zone.battlefield) {
              _dealDamage(sid, src, t, n);
            }
          }
        }
      case Fight(:final a, :final b):
        final x = _ref(a, ctx), y = _ref(b, ctx);
        if (x.isEmpty || y.isEmpty) return;
        final ca = chars(x.first), cb = chars(y.first);
        if (!ca.isCreature || !cb.isCreature || state.obj(x.first).zone != Zone.battlefield || state.obj(y.first).zone != Zone.battlefield) return;
        _dealDamage(x.first, ca, y.first, ca.power ?? 0);
        _dealDamage(y.first, cb, x.first, cb.power ?? 0);
      case Draw(:final amount, :final who):
        final n = evalAmount(amount, ctx);
        for (final p in resolvePlayers(who, ctx)) {
          _drawN(p, n);
        }
      case Discard(:final amount, :final who, :final random, :final chooser, :final filter, :final hand):
        var did = 0;
        for (final p in resolvePlayers(who, ctx)) {
          final pl = state.player(p);
          if (hand) {
            for (final id in List.of(pl.hand)) {
              _discard(p, id);
              did++;
            }
            continue;
          }
          final n = evalAmount(amount, ctx).clamp(0, pl.hand.length);
          if (n == 0) continue;
          List<int> pick;
          if (random) {
            final h = List.of(pl.hand);
            state.rng.shuffle(h);
            pick = h.take(n).toList();
          } else {
            final chooserP = chooser == null ? p : resolvePlayers(chooser, ctx).first;
            final options = [for (final id in pl.hand) if (matchesFilter(filter.copyWith(zone: ZoneKind.hand), id, ctx)) id];
            final k = n.clamp(0, options.length);
            pick = ask(Decision(kind: DecisionKind.cards, player: chooserP, prompt: 'Discard ${k == 1 ? 'a card' : '$k cards'}', options: options, min: k, max: k, source: ctx.source));
          }
          for (final id in pick) {
            _discard(p, id);
            did++;
          }
        }
        ctx.results['did'] = did;
      case GainLife(:final amount, :final who):
        final n = evalAmount(amount, ctx);
        for (final p in resolvePlayers(who, ctx)) {
          _gainLife(p, n);
        }
      case LoseLife(:final amount, :final who, :final slot):
        final n = evalAmount(amount, ctx);
        var total = 0;
        for (final p in resolvePlayers(who, ctx)) {
          final before = state.player(p).life;
          _loseLife(p, n);
          total += before - state.player(p).life;
        }
        if (slot != null) ctx.results[slot] = (ctx.results[slot] ?? 0) + total;
      case Mill(:final amount, :final who):
        final n = evalAmount(amount, ctx);
        for (final p in resolvePlayers(who, ctx)) {
          final pl = state.player(p);
          for (var i = 0; i < n && pl.library.isNotEmpty; i++) {
            _move(pl.library.first, Zone.graveyard);
          }
        }
      case Scry(:final amount):
        _scry(ctx.controller, evalAmount(amount, ctx));
      case Surveil(:final amount):
        _surveil(ctx.controller, evalAmount(amount, ctx));
      case Destroy(:final set, :final noRegen):
        var n = 0;
        for (final id in resolveObjs(set, ctx)) {
          if (_destroy(id, noRegen: noRegen)) n++;
        }
        ctx.results['destroyed'] = n;
      case MoveTo():
        _execMove(e, ctx);
      case Sacrifice(:final who, :final filter, :final amount, :final self):
        if (self) {
          final ids = _ref(const SelfRef(), ctx);
          if (ids.isNotEmpty && state.obj(ids.first).zone == Zone.battlefield) _sacrifice(ids.first);
          ctx.results['did'] = ids.isEmpty ? 0 : 1;
          return;
        }
        var did = 0;
        for (final p in resolvePlayers(who, ctx)) {
          final pctx = ctx.withThatPlayer(p)..controller = p;
          final options = [for (final id in state.battlefield) if (chars(id).controller == p && matchesFilter(filter.copyWith(controller: Who.any), id, pctx)) id];
          final n = evalAmount(amount, ctx).clamp(0, options.length);
          if (n == 0) continue;
          final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Sacrifice ${n == 1 ? 'a' : n} ${_describeFilter(filter)}', options: options, min: n, max: n, source: ctx.source));
          for (final id in pick) {
            ctx.results['sacPower'] = chars(id).power ?? 0;
            ctx.results['sacToughness'] = chars(id).toughness ?? 0;
            _sacrifice(id);
            did++;
          }
        }
        ctx.results['did'] = did;
      case Tap(:final set):
        for (final id in resolveObjs(set, ctx)) {
          _tap(id);
        }
      case Untap(:final set):
        for (final id in resolveObjs(set, ctx)) {
          _untap(id);
        }
      case TransformPermanents(:final set):
        for (final id in resolveObjs(set, ctx)) {
          _transform(id);
        }
      case PutCounters(:final set, :final kind, :final amount):
        final n = evalAmount(amount, ctx);
        for (final id in resolveObjs(set, ctx)) {
          if (state.obj(id).zone == Zone.battlefield) _addCounters(id, kind, n, by: ctx.controller);
        }
      case RemoveCounters(:final set, :final kind, :final amount, :final slot):
        final n = evalAmount(amount, ctx);
        var removed = 0;
        for (final id in resolveObjs(set, ctx)) {
          final have = state.obj(id).counters[kind] ?? 0;
          final k = n < have ? n : have;
          _removeCounters(id, kind, k);
          removed += k;
        }
        if (slot != null) ctx.results[slot] = removed;
        ctx.didIt = removed > 0;
      case DoubleCounters(:final set, :final kind):
        for (final id in resolveObjs(set, ctx)) {
          final o = state.obj(id);
          for (final k in kind == null ? o.counters.keys.toList() : [kind]) {
            final have = o.counters[k] ?? 0;
            if (have > 0) _addCounters(id, k, have, by: ctx.controller);
          }
        }
      case Proliferate():
        final options = [for (final id in state.battlefield) if (state.obj(id).counters.values.any((v) => v > 0)) id];
        final pick = ask(Decision(kind: DecisionKind.cards, player: ctx.controller, prompt: 'Proliferate: choose permanents', options: options, min: 0, max: options.length, source: ctx.source));
        for (final id in pick) {
          for (final k in state.obj(id).counters.keys.toList()) {
            _addCounters(id, k, 1, by: ctx.controller);
          }
        }
      case CreateToken(:final spec, :final amount, :final controller, :final tapped, :final attacking, :final remember):
        final n = evalAmount(amount, ctx);
        final ps = resolvePlayers(controller, ctx);
        if (ps.isEmpty) return;
        final created = <(ObjId, int)>[];
        for (var i = 0; i < _tokenCount(ps.first, n); i++) {
          created.add(_createToken(spec, ps.first, tapped: tapped, attacking: attacking, ctx: ctx));
        }
        ctx.remembered[remember] = created;
      case CreateCopy(:final of, :final amount, :final extraMods, :final sacrificeAtEnd, :final remember, :final controller):
        final ids = _ref(of, ctx);
        if (ids.isEmpty) return;
        final orig = state.obj(ids.first);
        final ps = resolvePlayers(controller, ctx);
        final created = <(ObjId, int)>[];
        for (var i = 0; i < _tokenCount(ps.first, evalAmount(amount, ctx)); i++) {
          final t = GameObject(id: state.nextId++, cardName: orig.copyOfCard ?? orig.cardName, owner: ps.first, zone: Zone.none)
            ..copyOfCard = orig.token == null && orig.copyOfToken == null ? (orig.copyOfCard ?? orig.cardName) : orig.copyOfCard
            ..copyOfToken = orig.copyOfToken ?? orig.token
            ..copyOfFace = orig.face
            ..copyExtra = [...orig.copyExtra, ...extraMods]
            ..tokenCopy = true;
          state.objects[t.id] = t;
          _putOntoBattlefield(t.id, ps.first);
          created.add((t.id, t.zcc));
          if (sacrificeAtEnd) {
            state.delayed.add(DelayedTrigger(
              controller: ps.first,
              sourceId: t.id,
              ability: const TriggeredAbility('Sacrifice this token at the beginning of the end step.', StepTrigger(TurnStep.end, Who.any), Body(effect: Sacrifice(You(), Filter.any, Fixed(1), self: true))),
              objects: [(t.id, t.zcc)],
              createdTurn: state.turn,
            ));
          }
        }
        ctx.remembered[remember] = created;
      case Grant(:final set, :final mods, :final duration):
        final affected = [for (final id in resolveObjs(set, ctx)) (id, state.obj(id).zcc)];
        if (affected.isEmpty) return;
        final locked = <int, (int, int)>{};
        for (var i = 0; i < mods.length; i++) {
          final m = mods[i];
          if (m is ModPT) locked[i] = (evalAmount(m.power, ctx), evalAmount(m.toughness, ctx));
          if (m is SetPT) locked[i] = (m.power == null ? 0 : evalAmount(m.power!, ctx), m.toughness == null ? 0 : evalAmount(m.toughness!, ctx));
        }
        state.effects.add(ActiveEffect(timestamp: state.nextTimestamp++, sourceId: ctx.source ?? 0, controller: ctx.controller, affected: affected, mods: mods, duration: duration, turn: state.turn, amounts: locked));
      case DoublePower(:final obj):
        final ids = _ref(obj, ctx);
        if (ids.isEmpty) return;
        final p = chars(ids.first).power ?? 0;
        state.effects.add(ActiveEffect(timestamp: state.nextTimestamp++, sourceId: ctx.source ?? 0, controller: ctx.controller, affected: [(ids.first, state.obj(ids.first).zcc)], mods: const [ModPT(Fixed(0), Fixed(0))], duration: EffectDuration.endOfTurn, turn: state.turn, amounts: {0: (p, 0)}));
      case CounterSpell(:final obj, :final exileInstead):
        final ids = _ref(obj, ctx);
        if (ids.isEmpty) return;
        _counterSpellObj(ids.first, exile: exileInstead);
      case CounterEventItem():
        final itemId = ctx.event?.other;
        if (itemId == null) return;
        final i = state.stack.indexWhere((s) => s.id == itemId);
        if (i < 0) return;
        final it = state.stack[i];
        if (it.objId != null) {
          _counterSpellObj(it.objId!);
        } else {
          state.stack.removeAt(i);
          _log('${it.sourceName}\'s ability is countered.');
        }
      case GainControl(:final set, :final duration):
        final affected = [for (final id in resolveObjs(set, ctx)) (id, state.obj(id).zcc)];
        if (affected.isEmpty) return;
        state.effects.add(ActiveEffect(timestamp: state.nextTimestamp++, sourceId: ctx.source ?? 0, controller: ctx.controller, affected: affected, mods: const [ControlBy(You())], duration: duration, turn: state.turn));
        for (final (id, _) in affected) {
          state.obj(id).controlSince = state.turn;
          state.obj(id).controller = ctx.controller;
        }
      case Search():
        _execSearch(e, ctx);
      case LookAndPick():
        _execLook(e, ctx);
      case RevealUntil(:final filter, :final zone, :final rest, :final who):
        for (final p in resolvePlayers(who, ctx)) {
          final pl = state.player(p);
          final revealed = <ObjId>[];
          ObjId? hit;
          for (final id in List.of(pl.library)) {
            if (matchesFilter(filter.copyWith(zone: ZoneKind.library, owner: Who.any, controller: Who.any), id, ctx)) {
              hit = id;
              break;
            }
            revealed.add(id);
          }
          if (hit != null) {
            _log('${pl.name} reveals ${nameOf(hit)}.', obj: hit);
            _placeFound(hit, zone, ctx.controller);
          }
          _putRest(p, revealed, rest);
        }
      case ExileTopMayPlay(:final n, :final chooseOne, :final untilEndOfNextTurn, :final who):
        for (final p in resolvePlayers(who, ctx)) {
          final pl = state.player(p);
          final count = evalAmount(n, ctx);
          final exiled = <ObjId>[];
          for (var i = 0; i < count && pl.library.isNotEmpty; i++) {
            final id = pl.library.first;
            _move(id, Zone.exile);
            exiled.add(id);
          }
          var playable = exiled;
          if (chooseOne && exiled.length > 1) {
            playable = ask(Decision(kind: DecisionKind.cards, player: ctx.controller, prompt: 'Choose a card you may play', options: exiled, min: 1, max: 1, source: ctx.source));
          }
          for (final id in playable) {
            final o = state.obj(id);
            o.playableBy = ctx.controller;
            o.playableUntil = untilEndOfNextTurn ? state.turn + state.apnap().length : state.turn;
          }
        }
      case AddMana(:final produce):
        final ps = produce.possible;
        final n = evalAmount(produce.amount, ctx);
        final units = <ManaUnit>[];
        if (produce.fixed.isNotEmpty) {
          if (produce.fixed.length == 1) {
            for (var i = 0; i < n; i++) {
              units.add(ManaUnit(produce.fixed.first, restriction: produce.restriction));
            }
          } else {
            for (final t in produce.fixed) {
              units.add(ManaUnit(t, restriction: produce.restriction));
            }
          }
        } else {
          final pick = ask(Decision(kind: DecisionKind.option, player: ctx.controller, prompt: 'Choose a color of mana', labels: [for (final t in ps) t.name], source: ctx.source));
          for (var i = 0; i < n; i++) {
            units.add(ManaUnit(ps[pick.first], restriction: produce.restriction));
          }
        }
        state.player(ctx.controller).pool.addAll(units);
      case Shuffle(:final who):
        for (final p in resolvePlayers(who, ctx)) {
          _shuffle(p);
        }
      case Attach(:final what, :final to):
        final a = _ref(what, ctx), b = _ref(to, ctx);
        if (a.isEmpty || b.isEmpty) return;
        final eq = state.obj(a.first);
        if (eq.zone != Zone.battlefield || state.obj(b.first).zone != Zone.battlefield) return;
        if (!chars(b.first).isCreature && chars(a.first).isEquipment) return;
        eq.attachedTo = b.first;
        eq.timestamp = state.nextTimestamp++;
      case Delayed(:final trigger, :final effect, :final oneShot):
        final objs = [for (final id in [..._ref(const TargetObj(0), ctx), ..._ref(const EventObj(), ctx)]) (id, state.obj(id).zcc)];
        state.delayed.add(DelayedTrigger(controller: ctx.controller, sourceId: ctx.source ?? 0, ability: TriggeredAbility('Delayed', trigger, Body(effect: effect)), objects: objs, createdTurn: state.turn, oneShot: oneShot));
      case Emblem(:final abilities, :final text):
        state.emblems.add(EmblemObj(ctx.controller, abilities, text, state.nextId++));
        _log('${state.player(ctx.controller).name} gets an emblem.', player: ctx.controller);
      case EndTurn():
        _endTheTurn();
      case Noop():
        break;
      case Regenerate() || PreventNext() || RevealHand() || FlipCoin() || RollDie() || Explore():
        _execShieldsAndChance(e, ctx);
      case CopySpell(:final obj, :final amount):
        final ids = _ref(obj, ctx);
        if (ids.isEmpty) return;
        final orig = state.stack.where((s) => s.objId == ids.first).firstOrNull;
        if (orig == null) return;
        for (var i = 0; i < evalAmount(amount, ctx); i++) {
          final o = state.obj(ids.first);
          final copy = GameObject(id: state.nextId++, cardName: o.cardName, owner: ctx.controller, zone: Zone.stack)..controller = ctx.controller;
          state.objects[copy.id] = copy;
          final it = orig.clone();
          final copyItem = StackItem(id: state.nextId++, kind: StackKind.spell, controller: ctx.controller, sourceId: copy.id, sourceZcc: copy.zcc, ability: orig.ability, objId: copy.id, modes: it.modes, targets: it.targets, x: it.x, kicked: it.kicked, sourceName: orig.sourceName, isCopy: true)..targetZcc = it.targetZcc;
          state.stack.add(copyItem);
          _emit(CopyEvent(copyItem.id, copy.id, ctx.controller));
        }
      case AllowPlay(:final set, :final duration, :final free):
        for (final id in resolveObjs(set, ctx)) {
          final o = state.obj(id);
          o.playableBy = ctx.controller;
          o.playableUntil = duration == EffectDuration.endOfTurn ? state.turn : state.turn + 99;
          o.playFree = free;
        }
      case RuleChange(:final rule, :final duration):
        state.effects.add(ActiveEffect(timestamp: state.nextTimestamp++, sourceId: ctx.source ?? 0, controller: ctx.controller, affected: const [], mods: const [], duration: duration, turn: state.turn, rule: rule));
      case RevealPutPermanents(:final n):
        final pl = state.player(ctx.controller);
        final x = evalAmount(n, ctx);
        final revealed = pl.library.take(x).toList();
        final ok = [for (final id in revealed) if (chars(id).isPermanentCard && chars(id).manaValue <= x) id];
        final pick = ask(Decision(kind: DecisionKind.cards, player: ctx.controller, prompt: 'Put any number onto the battlefield', options: ok, min: 0, max: ok.length, source: ctx.source));
        for (final id in pick) {
          _putOntoBattlefield(id, ctx.controller);
        }
        for (final id in revealed) {
          if (!pick.contains(id)) _move(id, Zone.graveyard);
        }
      case PilesChoice(:final n):
        final pl = state.player(ctx.controller);
        final cards = pl.library.take(evalAmount(n, ctx)).toList();
        if (cards.isEmpty) return;
        final faceDown = ask(Decision(kind: DecisionKind.cards, player: ctx.controller, prompt: 'Choose the face-down pile (the rest are face up)', options: cards, min: 0, max: cards.length, source: ctx.source));
        final faceUp = [for (final c in cards) if (!faceDown.contains(c)) c];
        final opp = state.opponents(ctx.controller).first;
        final pick = ask(Decision(kind: DecisionKind.option, player: opp, prompt: 'Choose a pile for your opponent\'s hand', labels: ['Face-down pile (${faceDown.length})', 'Face-up pile (${faceUp.length})'], source: ctx.source));
        final toHand = pick.first == 0 ? faceDown : faceUp;
        for (final id in cards) {
          _move(id, toHand.contains(id) ? Zone.hand : Zone.graveyard);
        }
      case ChooseFromRemembered(:final slot, :final n, :final then):
        final opts = [for (final r in ctx.remembered[slot] ?? const <(ObjId, int)>[]) if (state.objOrNull(r.$1)?.zcc == r.$2) r.$1];
        final pick = ask(Decision(kind: DecisionKind.cards, player: ctx.controller, prompt: 'Choose', options: opts, min: n.clamp(0, opts.length), max: n.clamp(0, opts.length), source: ctx.source));
        ctx.remembered['chosen'] = [for (final id in pick) (id, state.obj(id).zcc)];
        _exec(then, ctx);
      case ChooseEffect(:final options, :final chooser, :final labels):
        final ps = resolvePlayers(chooser, ctx);
        final pick = ask(Decision(kind: DecisionKind.option, player: ps.isEmpty ? ctx.controller : ps.first, prompt: 'Choose one', labels: labels.isEmpty ? [for (var i = 0; i < options.length; i++) 'Option ${i + 1}'] : labels, source: ctx.source));
        _exec(options[pick.first], ctx);
      case KeepOneOfEachType(:final who):
        for (final p in resolvePlayers(who, ctx)) {
          final keep = <ObjId>{};
          for (final t in const [CardType.artifact, CardType.creature, CardType.enchantment, CardType.land, CardType.planeswalker, CardType.battle]) {
            final opts = [for (final id in state.battlefield) if (chars(id).controller == p && chars(id).types.contains(t)) id];
            if (opts.isEmpty) continue;
            final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose a ${t.name} to keep', options: opts, min: 1, max: 1, source: ctx.source));
            keep.addAll(pick);
          }
          for (final id in List.of(state.battlefield)) {
            if (chars(id).controller == p && !keep.contains(id)) _sacrifice(id);
          }
        }
    }
  }

  String _mayPrompt(Effect e, EvalCtx ctx) {
    final src = ctx.sourceLki?.name ?? (ctx.source != null ? nameOf(ctx.source!) : 'Effect');
    final ab = ctx.item?.ability?.text ?? '';
    final m = RegExp(r'you may ([^.]+)', caseSensitive: false).firstMatch(ab);
    return '$src: ${m != null ? 'do you want to ${m.group(1)}?' : 'do it?'}';
  }

  int _tokenCount(PlayerId p, int n) {
    var count = n;
    for (final (_, ctl, _) in _replacements<DoubleTokens>()) {
      if (ctl == p) count *= 2;
    }
    return count;
  }

  (ObjId, int) _createToken(TokenSpec spec, PlayerId controller, {bool tapped = false, bool attacking = false, EvalCtx? ctx}) {
    var s = spec;
    if ((spec.power == null || spec.toughness == null) && spec.types.contains(CardType.creature) && ctx != null) {
      s = TokenSpec(name: spec.name, power: spec.power ?? ctx.x, toughness: spec.toughness ?? ctx.x, colors: spec.colors, types: spec.types, subtypes: spec.subtypes, supertypes: spec.supertypes, keywords: spec.keywords, abilities: spec.abilities, text: spec.text);
    }
    final t = GameObject(id: state.nextId++, cardName: s.name, owner: controller, zone: Zone.none, token: s);
    state.objects[t.id] = t;
    _putOntoBattlefield(t.id, controller, tapped: tapped, attacking: attacking);
    return (t.id, t.zcc);
  }

  void _counterSpellObj(ObjId id, {bool exile = false}) {
    final i = state.stack.indexWhere((s) => s.objId == id);
    if (i < 0) return;
    final c = chars(id);
    if (c.has(Kw.cantBeCountered)) {
      _log('${c.name} can\'t be countered.', obj: id);
      return;
    }
    final item = state.stack.removeAt(i);
    _log('${c.name} is countered.', obj: id, kind: 'counter');
    if (item.isCopy) {
      state.objects.remove(id);
      return;
    }
    _move(id, exile || state.obj(id).exileOnResolve ? Zone.exile : Zone.graveyard);
  }

  /// Transforms a permanent: only a transforming double-faced card does (CR 701.28c). It stays
  /// the same object, with its counters, damage and attachments (CR 712.18).
  void _transform(ObjId id) {
    final o = state.objOrNull(id);
    if (o == null || o.zone != Zone.battlefield || o.isToken || o.faceDown) return;
    final def = db[o.cardName];
    if (def == null || def.layout != Layout.transform || def.faces.length < 2) return;
    final before = chars(id).name;
    o.face = o.face == 0 ? 1 : 0;
    _dirty();
    _log('$before transforms into ${chars(id).name}.', obj: id, kind: 'info');
    _emit(TransformEvent(id));
  }

  /// "End the turn" (CR 723).
  void _endTheTurn() {
    for (final it in List.of(state.stack)) {
      if (it.objId != null) {
        final o = state.objOrNull(it.objId!);
        if (o != null && o.zone == Zone.stack) _moveTo(o.id, Zone.exile);
      }
    }
    state.stack.clear();
    _endCombat();
    state.pendingTriggers.clear();
    _beginStep(TurnStep.cleanup);
    state.stepDone = false;
  }

  void _execMove(MoveTo e, EvalCtx ctx) {
    final ids = resolveObjs(e.set, ctx);
    final moved = <(ObjId, int)>[];
    for (final id in ids) {
      final o = state.obj(id);
      switch (e.zone) {
        case ZoneKind.battlefield:
          final ctl = e.underYourControl ? ctx.controller : o.owner;
          _putOntoBattlefield(id, ctl, tapped: e.tapped, counters: e.counters, attacking: e.attacking, extraTypes: e.extraTypes);
        case ZoneKind.library:
          if (e.ownerChoosesTopOrBottom) {
            final pick = ask(Decision(kind: DecisionKind.option, player: o.owner, prompt: 'Put ${nameOf(id)} on the top or bottom of your library?', labels: const ['Top', 'Bottom'], source: ctx.source));
            _move(id, Zone.library, bottom: pick.first == 1);
          } else {
            _move(id, Zone.library, bottom: e.libraryBottom, libraryIndex: e.libraryPosition);
          }
        default:
          _move(id, zoneOfKind(e.zone));
      }
      moved.add((id, state.obj(id).zcc));
      if (e.untilSourceLeaves && ctx.source != null) {
        final src = state.objOrNull(ctx.source);
        if (src != null && src.zone == Zone.battlefield && src.zcc == ctx.sourceZcc) {
          src.exiledUntilLeaves.add(id);
        } else if (src != null) {
          // The source already left: the card comes back at once (CR 610.3c).
          _putOntoBattlefield(id, state.obj(id).owner);
        }
      }
    }
    if (e.remember != null) ctx.remembered[e.remember!] = moved;
  }

  void _placeFound(ObjId id, ZoneKind zone, PlayerId controller, {bool tapped = false}) {
    switch (zone) {
      case ZoneKind.battlefield:
        _putOntoBattlefield(id, controller, tapped: tapped);
      case ZoneKind.hand:
        _move(id, Zone.hand);
      case ZoneKind.graveyard:
        _move(id, Zone.graveyard);
      case ZoneKind.library:
        _move(id, Zone.library);
      default:
        _move(id, zoneOfKind(zone));
    }
  }

  void _putRest(PlayerId p, List<ObjId> rest, RestGoes where) {
    switch (where) {
      case RestGoes.bottomRandom:
        final l = List.of(rest);
        state.rng.shuffle(l);
        for (final id in l) {
          _move(id, Zone.library, bottom: true);
        }
      case RestGoes.bottomAnyOrder:
        final order = ask(Decision(kind: DecisionKind.order, player: p, prompt: 'Order the cards going to the bottom (first is deepest last)', options: rest));
        for (final id in order) {
          _move(id, Zone.library, bottom: true);
        }
      case RestGoes.graveyard:
        for (final id in rest) {
          _move(id, Zone.graveyard);
        }
      case RestGoes.exile:
        for (final id in rest) {
          _move(id, Zone.exile);
        }
      case RestGoes.top:
        for (final id in rest.reversed) {
          _move(id, Zone.library);
        }
      case RestGoes.topAnyOrder:
        final order = rest.length > 1 ? ask(Decision(kind: DecisionKind.order, player: p, prompt: 'Order the cards on top (first is the top card)', options: rest)) : rest;
        final pl = state.player(p);
        for (final id in order) {
          pl.library.remove(id);
        }
        pl.library.insertAll(0, order);
        _dirty();
    }
  }

  void _execSearch(Search e, EvalCtx ctx) {
    final p = ctx.controller;
    final pl = state.player(p);
    final n = evalAmount(e.amount, ctx);
    final options = [for (final id in pl.library) if (matchesFilter(e.filter.copyWith(zone: ZoneKind.library, card: false), id, ctx)) id]..sort();
    final k = n.clamp(0, options.length);
    final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Search your library: choose ${e.upTo ? 'up to ' : ''}$n', options: options, min: e.upTo ? 0 : k, max: k, source: ctx.source));
    for (final id in pick) {
      if (e.reveal) _log('${pl.name} reveals ${nameOf(id)}.', obj: id);
      if (e.onTop) continue;
      _placeFound(id, e.zone, p, tapped: e.tapped);
    }
    if (e.thenShuffle) _shuffle(p);
    if (e.onTop) {
      for (final id in pick) {
        _move(id, Zone.library);
      }
    }
  }

  void _execLook(LookAndPick e, EvalCtx ctx) {
    final p = ctx.controller;
    final pl = state.player(p);
    final top = pl.library.take(evalAmount(e.n, ctx)).toList();
    final options = [for (final id in top) if (matchesFilter(e.filter.copyWith(zone: ZoneKind.library, card: false), id, ctx)) id];
    final k = evalAmount(e.pick, ctx).clamp(0, options.length);
    final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: e.mayPick ? 'You may choose up to $k' : 'Choose $k', options: options, min: e.mayPick ? 0 : k, max: k, source: ctx.source));
    for (final id in pick) {
      if (e.reveal) _log('${pl.name} reveals ${nameOf(id)}.', obj: id);
      if (e.zone == ZoneKind.library) continue;
      _placeFound(id, e.zone, p, tapped: e.tapped);
    }
    final rest = [for (final id in top) if (!pick.contains(id)) id];
    _putRest(p, rest, e.rest);
  }

  void _scry(PlayerId p, int n) {
    if (n > 0) _emit(ScryEvent(p, surveil: false));
    final pl = state.player(p);
    final top = pl.library.take(n).toList();
    if (top.isEmpty) return;
    final bottom = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Scry $n: choose cards to put on the bottom', options: top, min: 0, max: top.length));
    final keep = [for (final id in top) if (!bottom.contains(id)) id];
    final order = keep.length > 1 ? ask(Decision(kind: DecisionKind.order, player: p, prompt: 'Order the cards on top (first is the top card)', options: keep)) : keep;
    for (final id in bottom) {
      pl.library.remove(id);
      pl.library.add(id);
    }
    for (final id in order) {
      pl.library.remove(id);
    }
    pl.library.insertAll(0, order);
    _dirty();
  }

  void _surveil(PlayerId p, int n) {
    if (n > 0) _emit(ScryEvent(p, surveil: true));
    final pl = state.player(p);
    final top = pl.library.take(n).toList();
    if (top.isEmpty) return;
    final gy = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Surveil $n: choose cards to put into your graveyard', options: top, min: 0, max: top.length));
    for (final id in gy) {
      _move(id, Zone.graveyard);
    }
    final keep = [for (final id in top) if (!gy.contains(id)) id];
    if (keep.length > 1) {
      final order = ask(Decision(kind: DecisionKind.order, player: p, prompt: 'Order the cards on top (first is the top card)', options: keep));
      for (final id in order) {
        pl.library.remove(id);
      }
      pl.library.insertAll(0, order);
    }
    _dirty();
  }
}

