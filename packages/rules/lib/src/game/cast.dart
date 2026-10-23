part of 'game.dart';

/// Casting spells (CR 601), activating abilities (CR 602), mana abilities and paying costs
/// (CR 106, 118, 605).
extension GameCast on Game {
  /// Cast options an ability list offers (kicker, alternative costs, flashback...), in order.
  List<CastOption> _castOptionList(Chars c) => [for (final a in c.abilities) if (a is CastOptionAbility) a.option];

  /// How [p] could cast [id]: -1 is the normal way; i ≥ 0 is the i-th cast option
  /// (alternative cost, flashback, cast from graveyard).
  List<int> castOptions(PlayerId p, ObjId id) {
    final o = state.obj(id);
    final c = chars(id);
    final opts = _castOptionList(c);
    final out = <int>[];
    final ctx = EvalCtx(this, controller: p, source: id, sourceZcc: o.zcc);
    if ((o.zone == Zone.hand && o.owner == p) || o.playableBy == p || (o.zone == Zone.graveyard && _graveyardPermission(p, o)) || _adventurePermission(p, o) || _aftermathPermission(p, o)) out.add(-1);
    for (var i = 0; i < opts.length; i++) {
      final opt = opts[i];
      switch (opt.kind) {
        case CastKind.alternative:
          if (o.zone == Zone.hand && o.owner == p && (opt.condition == null || evalCondition(opt.condition!, ctx))) out.add(i);
        case CastKind.flashback || CastKind.fromGraveyard:
          if (o.zone == Zone.graveyard && o.owner == p) out.add(i);
        default:
      }
    }
    return out;
  }

  /// A card that went on an Adventure: its caster may cast the creature from exile (CR 715.4).
  bool _adventurePermission(PlayerId p, GameObject o) => o.zone == Zone.exile && o.adventureBy == p;

  /// Aftermath: the second half is cast from its owner's graveyard (CR 702.127).
  bool _aftermathPermission(PlayerId p, GameObject o) => o.zone == Zone.graveyard && o.owner == p && _faceHasKw(o, 1, 'aftermath');

  bool _faceHasKw(GameObject o, int face, String kw) {
    final def = o.isToken ? null : db[o.cardName];
    if (def == null || face >= def.faces.length) return false;
    final parsed = OracleParser.parse(def);
    return face < parsed.faces.length && parsed.faces[face].abilities.any((a) => a is KeywordAbility && a.kw.name == kw);
  }

  /// The faces [p] could cast [id] as (CR 709.3, 712.11, 715.3), not counting timing or cost:
  /// 0 and 1 are the halves or faces, 2 is a fused split spell.
  List<int> castFaces(PlayerId p, ObjId id) {
    final o = state.obj(id);
    final def = o.isToken ? null : db[o.copyOfCard ?? o.cardName];
    if (def == null || def.faces.length < 2) return const [0];
    final fromGraveyardByAftermath = _aftermathPermission(p, o) && !(o.playableBy == p) && !_graveyardPermission(p, o);
    switch (def.layout) {
      case Layout.split:
        final aftermath = _faceHasKw(o, 1, 'aftermath');
        if (fromGraveyardByAftermath) return const [1];
        if (aftermath) return const [0];
        final fuse = o.zone == Zone.hand && o.owner == p && (_faceHasKw(o, 0, 'fuse') || _faceHasKw(o, 1, 'fuse')) && _fusedAbility(def) != null;
        return [0, 1, if (fuse) 2];
      case Layout.adventure:
        return _adventurePermission(p, o) ? const [0] : const [0, 1];
      case Layout.modalDfc:
        return [for (var i = 0; i < 2; i++) if (!def.faces[i].isLand) i];
      default:
        return const [0];
    }
  }

  /// The faces of [id] that are lands [p] could play (a modal double-faced card's either side).
  List<int> landFaces(ObjId id) {
    final o = state.obj(id);
    final def = o.isToken ? null : db[o.cardName];
    if (def == null || def.layout != Layout.modalDfc) return [if (chars(id).isLand) 0];
    return [for (var i = 0; i < def.faces.length && i < 2; i++) if (def.faces[i].isLand) i];
  }

  /// Both halves of a fused split spell as one two-mode spell: each half keeps its own targets
  /// and they resolve left to right (CR 702.102d). Null when a half is itself modal.
  SpellAbility? _fusedAbility(CardDef def) {
    final parsed = OracleParser.parse(def);
    final halves = [for (final f in parsed.faces) f.abilities.whereType<SpellAbility>().firstOrNull];
    if (halves.length < 2 || halves.any((h) => h == null || h.body.isModal)) return null;
    return SpellAbility(halves.map((h) => h!.text).join(' // '), Body(modes: [halves[0]!.body, halves[1]!.body], minModes: 2, maxModes: 2, modeLabels: [def.faces[0].name, def.faces[1].name]));
  }

  /// [id]'s characteristics as the face it's being cast as.
  Chars _castChars(GameObject o, int face) {
    final def = db[o.copyOfCard ?? o.cardName];
    if (def == null || def.faces.length < 2) return chars(o.id);
    final c = face >= 2 ? _combinedChars(def, o) : _faceChars(def, face, o);
    _applySelfCda(o.id, c);
    for (final a in c.abilities) {
      if (a is KeywordAbility) c.keywords.add(a.kw);
    }
    return c;
  }

  bool _canCastNow(PlayerId p, Chars c) {
    if (c.isInstant || c.has(Kw.flash)) return true;
    for (final r in _rules<CastAsThoughFlash>(p)) {
      if (identical(r.filter, Filter.any) || r.filter.types.isEmpty || r.filter.types.any(c.types.contains)) return true;
    }
    return state.active == p && (state.step == TurnStep.main1 || state.step == TurnStep.main2) && state.stack.isEmpty;
  }

  void _castSpell(PlayerId p, ObjId id, int face, int option) {
    final o = state.objOrNull(id);
    if (o == null) throw GameError('No such card');
    if (!castFaces(p, id).contains(face)) throw GameError("Can't cast that half or face now");
    // Alternative costs and flashback belong to the card's front face (or the whole split card).
    if (face != 0 && option != -1) throw GameError("Can't cast that half that way");
    final c0 = face == 0 && (db[o.cardName]?.layout != Layout.split || o.isToken) ? chars(id) : _castChars(o, face);
    if (c0.isLand) throw GameError('Lands are played, not cast');
    final options = castOptions(p, id);
    if (!options.contains(option)) throw GameError("Can't cast ${c0.name} that way now");
    if (!_canCastNow(p, c0)) throw GameError("Can't cast ${c0.name} now");
    final optList = _castOptionList(c0);
    final chosen = option >= 0 ? optList[option] : null;
    final fromZone = o.zone;
    final wasPlayable = o.playableBy == p;
    final free = o.playFree || (fromZone == Zone.hand && _rules<CastWithoutPaying>(p).isNotEmpty);

    // Additional costs (CR 601.2b): mandatory ones, with a choice when there are alternatives.
    final additional = optList.where((x) => x.kind == CastKind.additional).toList();
    CastOption? addChoice;
    if (additional.length == 1) {
      addChoice = additional.first;
    } else if (additional.length > 1) {
      final pick = ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Choose an additional cost', labels: [for (final a in additional) a.label], source: id, cancellable: true));
      addChoice = additional[pick.first];
    }
    final kicker = optList.where((x) => x.kind == CastKind.kicker).toList();
    var kicked = false;
    if (kicker.isNotEmpty) {
      final k = ask(Decision(kind: DecisionKind.yesNo, player: p, prompt: 'Pay kicker ${kicker.first.cost?.text ?? ''}?', labels: const ['No', 'Kick it'], source: id, cancellable: true));
      kicked = k.first == 1;
    }

    // 601.2a: the card moves to the stack.
    _moveTo(id, Zone.stack, controller: p);
    o.face = face;
    _dirty();
    final def = o.isToken ? null : db[o.cardName];
    final spellAb = face == 2 && def != null ? _fusedAbility(def) : c0.abilities.whereType<SpellAbility>().firstOrNull;
    // Aftermath: the second half is exiled whenever it leaves the stack (CR 702.127a).
    if (face == 1 && def?.layout == Layout.split && _faceHasKw(o, 1, 'aftermath')) o.exileOnResolve = true;
    final item = StackItem(id: state.nextId++, kind: StackKind.spell, controller: p, sourceId: id, sourceZcc: o.zcc, ability: spellAb, objId: id, sourceName: c0.name, kicked: kicked);
    state.stack.add(item);
    o.kicked = kicked;
    if (chosen?.kind == CastKind.flashback) o.exileOnResolve = true;
    if (fromZone == Zone.graveyard && !wasPlayable && chosen == null) state.player(p).stats.graveyardPlays.addAll([for (final t in c0.types) if (t.isPermanentType) t.name]);

    // X (601.2b).
    final baseCost = free ? ManaCost.empty : (chosen?.cost ?? c0.manaCost ?? ManaCost.empty);
    if (baseCost.hasX) {
      final maxX = _maxAffordableX(p, baseCost);
      final x = ask(Decision(kind: DecisionKind.number, player: p, prompt: 'Choose X', min: 0, max: maxX, source: id, cancellable: true));
      item.x = x.first;
      o.x = x.first;
    }
    final ctx = EvalCtx(this, controller: p, source: id, sourceZcc: o.zcc, x: item.x, kicked: kicked, item: item);

    // Modes and targets (601.2b–c).
    if (spellAb != null) _chooseModesAndTargets(p, item, spellAb.body, ctx, spell: id);
    // Auras target what they'll enchant (CR 303.4a).
    final enchant = c0.abilities.whereType<EnchantAbility>().firstOrNull;
    if (enchant != null && c0.isAura) {
      final spec = TargetSpec(enchant.player ? TargetKind.player : TargetKind.object, filter: enchant.filter);
      final legal = legalTargets(spec, ctx, spell: id);
      if (legal.isEmpty) throw GameError('Nothing to enchant');
      final t = ask(Decision(kind: DecisionKind.targets, player: p, prompt: 'Choose what ${c0.name} enchants', options: legal, min: 1, max: 1, source: id, cancellable: true));
      item.targets = [t];
      item.targetZcc = [
        [for (final e in t) isPlayerEntity(e) ? 0 : state.obj(e).zcc],
      ];
    }

    // Total cost (601.2f) and payment (601.2g–h).
    var cost = baseCost.withX(item.x);
    if (kicked) cost = cost + kicker.first.cost!;
    if (addChoice?.cost != null) cost = cost + addChoice!.cost!;
    cost = _applyCostChanges(p, id, c0, cost, item, ctx);
    for (final part in addChoice?.extra ?? const <CostPart>[]) {
      _payCostPart(p, part, id, item, ctx);
    }
    for (final part in chosen?.extra ?? const <CostPart>[]) {
      _payCostPart(p, part, id, item, ctx);
    }
    _payMana(p, cost, forSpell: id, prompt: 'Pay for ${c0.name}');

    // 601.2i: the spell becomes cast.
    o.wasCast = true;
    o.playableBy = null;
    final pl = state.player(p);
    pl.stats.spellsCast++;
    if (!c0.isCreature) pl.stats.noncreatureSpellsCast++;
    if (c0.isInstant || c0.isSorcery) pl.stats.instantSorceryCast++;
    _log('${pl.name} casts ${c0.name}${kicked ? ' (kicked)' : ''}${item.x > 0 ? ' (X=${item.x})' : ''}.', player: p, obj: id, kind: 'cast');
    _emit(CastEvent(item.id, id, p));
    _targetedEvents(item);
    _dirty();
  }

  /// Chooses modes (601.2b) and targets (601.2c) for a spell or ability on the stack.
  void _chooseModesAndTargets(PlayerId p, StackItem item, Body body, EvalCtx ctx, {ObjId? spell, bool cancellable = true}) {
    var modes = const [0];
    if (body.isModal) {
      // Modes with no legal targets can't be chosen.
      final ok = <int>[];
      for (var i = 0; i < body.modes.length; i++) {
        final m = body.modes[i];
        if (m.targets.every((t) => t.min == 0 || legalTargets(t, ctx, spell: spell).length >= t.min)) ok.add(i);
      }
      if (ok.length < body.minModes) throw GameError('No legal mode');
      // No choice to make: exactly as many legal modes as must be chosen (a fused split spell).
      if (ok.length == body.minModes && body.maxModes == body.minModes) {
        item.modes = ok;
        return _chooseTargetsFor(p, item, body, ok, ctx, spell: spell, cancellable: cancellable);
      }
      modes = ask(Decision(
        kind: DecisionKind.modes,
        player: p,
        prompt: body.maxModes == 1 ? 'Choose one' : 'Choose ${body.minModes == body.maxModes ? body.minModes : '${body.minModes}–${body.maxModes}'}',
        options: ok,
        min: body.minModes,
        max: body.maxModes.clamp(0, ok.length),
        labels: body.modeLabels,
        source: item.objId ?? item.sourceId,
        cancellable: cancellable,
      ))
        ..sort();
    }
    item.modes = modes;
    _chooseTargetsFor(p, item, body, modes, ctx, spell: spell, cancellable: cancellable);
  }

  void _chooseTargetsFor(PlayerId p, StackItem item, Body body, List<int> modes, EvalCtx ctx, {ObjId? spell, bool cancellable = true}) {
    final specs = <TargetSpec>[];
    for (final mi in modes) {
      final b = body.isModal ? body.modes[mi] : body;
      specs.addAll(b.targets);
    }
    final targets = <List<int>>[];
    final zccs = <List<int>>[];
    ctx.targets = targets;
    ctx.targetZcc = zccs;
    for (var i = 0; i < specs.length; i++) {
      final spec = specs[i];
      if (spec.when != null && !evalCondition(spec.when!, ctx)) {
        targets.add(const []);
        zccs.add(const []);
        continue;
      }
      var legal = legalTargets(spec, ctx, spell: spell);
      // "Another target": not one chosen for the specs it must differ from.
      for (final j in spec.distinctFrom) {
        if (j < targets.length) legal = [for (final e in legal) if (!targets[j].contains(e)) e];
      }
      if (legal.length < spec.min) throw GameError('Not enough legal targets');
      final chosen = ask(Decision(
        kind: DecisionKind.targets,
        player: p,
        prompt: _targetPrompt(spec),
        options: legal,
        min: spec.min,
        max: spec.max.clamp(0, legal.length),
        source: item.objId ?? item.sourceId,
        cancellable: cancellable,
      ));
      if (spec.differentControllers) {
        final ctls = {for (final e in chosen) state.obj(e).controller};
        if (ctls.length != chosen.length) throw GameError('Choose creatures controlled by different players');
      }
      if (spec.sameZoneOwner && chosen.isNotEmpty) {
        final owners = {for (final e in chosen) state.obj(e).owner};
        if (owners.length > 1) throw GameError('Choose cards from a single graveyard');
      }
      targets.add(chosen);
      zccs.add([for (final e in chosen) isPlayerEntity(e) ? 0 : state.obj(e).zcc]);
    }
    item.targets = targets;
    item.targetZcc = zccs;
  }

  String _targetPrompt(TargetSpec s) {
    final n = s.max > 1 ? (s.min == 0 ? 'up to ${s.max} targets' : '${s.max} targets') : (s.min == 0 ? 'up to one target' : 'a target');
    final what = switch (s.kind) {
      TargetKind.player => s.who == Who.opponent ? 'opponent' : 'player',
      TargetKind.any => 'any target',
      TargetKind.spell => 'spell',
      TargetKind.object => _describeFilter(s.filter),
    };
    return 'Choose $n: $what';
  }

  String _describeFilter(Filter f) {
    final parts = <String>[];
    if (f.other) parts.add('other');
    if (f.token == false) parts.add('nontoken');
    if (f.tapped == true) parts.add('tapped');
    if (f.attacking == true && f.blocking == true) {
      parts.add('attacking or blocking');
    } else if (f.attacking == true) {
      parts.add('attacking');
    }
    for (final c in f.colors) {
      parts.add(c.word);
    }
    for (final t in f.notTypes) {
      parts.add('non${t.name}');
    }
    final types = [...f.subtypes, ...f.types.map((t) => t.name)];
    parts.add(types.isEmpty ? (f.card ? 'card' : 'permanent') : types.join(' or '));
    if (f.card && types.isNotEmpty) parts.add('card');
    if (f.controller == Who.you) parts.add('you control');
    if (f.controller == Who.opponent) parts.add('an opponent controls');
    if (f.controller == Who.notYou) parts.add("you don't control");
    if (f.zone == ZoneKind.graveyard) parts.add('in a graveyard');
    return parts.join(' ');
  }

  /// Cost increases and reductions (CR 601.2f). Reductions only reduce generic mana.
  ManaCost _applyCostChanges(PlayerId p, ObjId spell, Chars c, ManaCost cost, StackItem item, EvalCtx ctx) {
    var delta = 0;
    final sources = <(CostChange, PlayerId, ObjId?)>[];
    for (final id in state.battlefield) {
      final pc = chars(id);
      for (final a in pc.abilities) {
        if (a is RuleAbility && a.rule is CostChange && !(a.rule as CostChange).selfOnly) sources.add((a.rule as CostChange, pc.controller, id));
      }
    }
    for (final a in c.abilities) {
      if (a is RuleAbility && a.rule is CostChange && (a.rule as CostChange).selfOnly) sources.add((a.rule as CostChange, p, spell));
    }
    for (final (r, owner, src) in sources) {
      final rctx = EvalCtx(this, controller: owner, source: src, sourceZcc: src == null ? 0 : state.obj(src).zcc, targets: item.targets, targetZcc: item.targetZcc);
      if (r.who == Who.you && owner != p) continue;
      if (r.who == Who.opponent && owner == p) continue;
      if (!r.selfOnly && !matchesFilter(r.filter.copyWith(zone: ZoneKind.stack), spell, EvalCtx(this, controller: p, source: src))) continue;
      if (r.condition != null && !evalCondition(r.condition!, rctx)) continue;
      if (r.targetsFilter != null) {
        final hits = item.targets.expand((t) => t).where((e) => !isPlayerEntity(e) && matchesFilter(r.targetsFilter!, e, rctx));
        if (hits.isEmpty) continue;
      }
      if (r.amount != null) {
        delta -= evalAmount(r.amount!, rctx);
      } else {
        delta += r.delta;
      }
    }
    if (delta == 0) return cost;
    final g = cost.generic + delta;
    final rest = cost.symbols.where((s) => s is! GenericSymbol).toList();
    return ManaCost([if (g > 0) GenericSymbol(g), ...rest]);
  }

  /// The largest X [p] could pay for [cost] with their untapped sources.
  int _maxAffordableX(PlayerId p, ManaCost cost) {
    final total = _availableManaCount(p);
    final fixed = cost.withX(0).manaValue;
    final xs = cost.xCount;
    if (xs == 0) return 0;
    return ((total - fixed) ~/ xs).clamp(0, 99);
  }

  int _availableManaCount(PlayerId p) {
    var n = state.player(p).pool.length;
    for (final s in _manaSources(p)) {
      n += s.amount;
    }
    return n;
  }

  // -------------------------------------------------------------------------------------------
  // Activated abilities (CR 602)
  // -------------------------------------------------------------------------------------------

  void _activate(PlayerId p, ObjId id, int index) {
    final o = state.objOrNull(id);
    if (o == null) throw GameError('No such object');
    final c = chars(id);
    if (index < 0 || index >= c.abilities.length) throw GameError('No such ability');
    final a = c.abilities[index];
    if (a is ManaAbility) throw GameError('Use a mana action');
    if (a is! ActivatedAbility) throw GameError('Not an activated ability');
    if (zoneOfKind(a.zone) != o.zone) throw GameError("Can't activate that from there");
    if (o.zone == Zone.battlefield ? c.controller != p : o.owner != p) throw GameError('Not yours');
    if (o.phasedOut) throw GameError('Phased out');
    final sorcery = a.sorcerySpeed || a.isLoyalty;
    if (sorcery && !(state.active == p && (state.step == TurnStep.main1 || state.step == TurnStep.main2) && state.stack.isEmpty)) throw GameError('Only as a sorcery');
    if (a.yourTurnOnly && state.active != p) throw GameError('Only during your turn');
    final key = a.text;
    if (a.isLoyalty && (o.activations['loyalty'] ?? 0) > 0) throw GameError('One loyalty ability per turn');
    if (a.oncePerTurn && !a.isLoyalty && (o.activations[key] ?? 0) > 0) throw GameError('Only once each turn');
    if (a.onlyOnce && o.activatedEver.contains(key)) throw GameError('Only once');
    final ctx = EvalCtx(this, controller: p, source: id, sourceZcc: o.zcc);
    if (a.condition != null && !evalCondition(a.condition!, ctx)) throw GameError('Condition not met');
    if (a.cost.tap || a.cost.untap) {
      if (a.cost.tap && o.tapped) throw GameError('Already tapped');
      if (a.cost.untap && !o.tapped) throw GameError('Not tapped');
      if (c.isCreature && _summoningSick(id)) throw GameError('Summoning sick');
    }
    if (a.cost.loyalty != null && a.cost.loyalty! < 0 && (o.counters['loyalty'] ?? 0) < -a.cost.loyalty!) throw GameError('Not enough loyalty');

    final item = StackItem(id: state.nextId++, kind: StackKind.activated, controller: p, sourceId: id, sourceZcc: o.zcc, ability: a, sourceName: c.name);
    item.paidCost['lkiPower'] = c.power ?? 0;
    final cost = a.cost.mana;
    if (cost != null && cost.hasX) {
      final x = ask(Decision(kind: DecisionKind.number, player: p, prompt: 'Choose X', min: 0, max: _maxAffordableX(p, cost), source: id, cancellable: true));
      item.x = x.first;
    }
    ctx.x = item.x;
    state.stack.add(item);
    _chooseModesAndTargets(p, item, a.body, ctx, cancellable: true);

    // Costs (602.2b, 601.2g–h).
    if (a.cost.tap) _tap(id);
    if (a.cost.untap) _untap(id);
    if (a.cost.loyalty != null) {
      if (a.cost.loyalty! > 0) _addCounters(id, 'loyalty', a.cost.loyalty!);
      if (a.cost.loyalty! < 0) _removeCounters(id, 'loyalty', -a.cost.loyalty!);
      o.activations['loyalty'] = (o.activations['loyalty'] ?? 0) + 1;
    }
    final lki = c.copy();
    for (final part in a.cost.parts) {
      _payCostPart(p, part, id, item, ctx);
    }
    if (cost != null) _payMana(p, cost.withX(item.x), prompt: 'Pay for ${c.name}');
    o.activations[key] = (o.activations[key] ?? 0) + 1;
    o.activatedEver.add(key);
    item.sourceLki = lki;
    _log('${state.player(p).name} activates ${c.name}.', player: p, obj: id, kind: 'activate');
    _targetedEvents(item);
    _dirty();
  }

  /// Pays a non-mana cost part (CR 118).
  void _payCostPart(PlayerId p, CostPart part, ObjId source, StackItem item, EvalCtx ctx) {
    switch (part) {
      case SacrificeCost(:final self, :final filter, :final n):
        if (self) {
          final so = state.obj(source);
          if (so.zone != Zone.battlefield) throw GameError('Must be on the battlefield');
          item.paidCost['sacPower'] = chars(source).power ?? 0;
          _sacrifice(source);
          return;
        }
        final options = [for (final id in state.battlefield) if (chars(id).controller == p && matchesFilter(filter.copyWith(controller: Who.you), id, ctx)) id];
        if (options.length < n) throw GameError('Nothing to sacrifice');
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Sacrifice ${n == 1 ? 'a' : n} ${_describeFilter(filter)}', options: options, min: n, max: n, source: source, cancellable: true));
        for (final id in pick) {
          item.paidCost['sacPower'] = chars(id).power ?? 0;
          item.paidCost['sacToughness'] = chars(id).toughness ?? 0;
          _sacrifice(id);
        }
      case DiscardCost(:final self, :final hand, :final filter, :final n):
        if (self) {
          if (state.obj(source).zone != Zone.hand) throw GameError('Must be in your hand');
          _discard(p, source);
          return;
        }
        final pl = state.player(p);
        if (hand) {
          for (final id in List.of(pl.hand)) {
            _discard(p, id);
          }
          return;
        }
        final options = [for (final id in pl.hand) if (id != source && matchesFilter(filter.copyWith(zone: ZoneKind.hand), id, ctx)) id];
        if (options.length < n) throw GameError('Not enough cards to discard');
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Discard ${n == 1 ? 'a card' : '$n cards'}', options: options, min: n, max: n, source: source, cancellable: true));
        for (final id in pick) {
          _discard(p, id);
        }
      case PayLifeCost(:final amount):
        final n = evalAmount(amount, ctx);
        if (state.player(p).life < n) throw GameError('Not enough life');
        _loseLife(p, n);
      case ExileFromGraveyardCost(:final self, :final filter, :final n):
        if (self) {
          _moveTo(source, Zone.exile);
          return;
        }
        final options = [for (final id in state.player(p).graveyard) if (id != source && matchesFilter(filter.copyWith(zone: ZoneKind.graveyard), id, ctx)) id];
        if (options.length < n) throw GameError('Not enough cards in your graveyard');
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Exile ${n == 1 ? 'a card' : '$n cards'} from your graveyard', options: options, min: n, max: n, source: source, cancellable: true));
        for (final id in pick) {
          _moveTo(id, Zone.exile);
        }
      case RemoveCountersCost(:final kind, :final n, :final fromAmong):
        if (fromAmong == null) {
          final have = state.obj(source).counters[kind] ?? 0;
          if (have < n) throw GameError('Not enough counters');
          _removeCounters(source, kind, n);
          return;
        }
        for (var i = 0; i < n; i++) {
          final options = [
            for (final id in state.battlefield)
              if (chars(id).controller == p && matchesFilter(fromAmong.copyWith(controller: Who.you), id, ctx) && state.obj(id).counters.values.any((v) => v > 0)) id,
          ];
          if (options.isEmpty) throw GameError('Not enough counters');
          final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Remove a counter (${i + 1} of $n)', options: options, min: 1, max: 1, source: source, cancellable: true));
          final o = state.obj(pick.first);
          final kinds = [for (final e in o.counters.entries) if (e.value > 0) e.key];
          final k = kinds.length == 1 ? 0 : ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Which counter?', labels: kinds, source: source, cancellable: true)).first;
          _removeCounters(o.id, kinds[k], 1);
        }
      case TapCost(:final filter, :final totalPower) when totalPower > 0:
        // Crew (CR 702.122): tap any number of other untapped creatures with enough total power.
        // Strongest first, and the fewest that are enough as the minimum, so the default
        // answer is a legal one.
        final options = [
          for (final id in state.battlefield)
            if (id != source && !state.obj(id).tapped && chars(id).controller == p && matchesFilter(filter.copyWith(controller: Who.you, tapped: false), id, ctx)) id,
        ]..sortStable((a, b) {
            final d = (chars(b).power ?? 0) - (chars(a).power ?? 0);
            return d != 0 ? d : a - b;
          });
        var need = 0, sum = 0;
        while (need < options.length && sum < totalPower) {
          sum += chars(options[need]).power ?? 0;
          need++;
        }
        if (sum < totalPower) throw GameError('Not enough untapped creatures to crew $totalPower');
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Crew $totalPower: tap creatures with total power $totalPower or more', options: options, min: need, max: options.length, source: source, cancellable: true));
        if (pick.fold<int>(0, (a, id) => a + (chars(id).power ?? 0)) < totalPower) throw GameError('Not enough total power to crew $totalPower');
        for (final id in pick) {
          _tap(id);
        }
      case TapCost(:final filter, :final n):
        if (n == 0) {
          if (state.obj(source).tapped) throw GameError('Already tapped');
          _tap(source);
          return;
        }
        final options = [for (final id in state.battlefield) if (!state.obj(id).tapped && chars(id).controller == p && matchesFilter(filter.copyWith(controller: Who.you, tapped: false), id, ctx)) id];
        if (options.length < n) throw GameError('Not enough untapped ${_describeFilter(filter)}');
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Tap $n untapped ${_describeFilter(filter)}', options: options, min: n, max: n, source: source, cancellable: true));
        for (final id in pick) {
          _tap(id);
        }
      case ReturnCost(:final filter):
        final options = [for (final id in state.battlefield) if (chars(id).controller == p && matchesFilter(filter, id, ctx)) id];
        if (options.isEmpty) throw GameError('Nothing to return');
        final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Return a ${_describeFilter(filter)} to your hand', options: options, min: 1, max: 1, source: source, cancellable: true));
        _moveTo(pick.first, Zone.hand);
      case AddCountersCost(:final kind, :final n):
        _addCounters(source, kind, n);
    }
  }

  // -------------------------------------------------------------------------------------------
  // Mana (CR 106, 605)
  // -------------------------------------------------------------------------------------------

  /// Untapped permanents [p] could tap for mana, best-to-use-first order.
  List<_ManaSource> _manaSources(PlayerId p) {
    final out = <_ManaSource>[];
    for (final id in state.battlefield) {
      final o = state.obj(id);
      final c = chars(id);
      if (c.controller != p || o.phasedOut) continue;
      for (var i = 0; i < c.abilities.length; i++) {
        final a = c.abilities[i];
        if (a is! ManaAbility) continue;
        if (!_canPayManaAbilityCost(p, id, a)) continue;
        final ctx = EvalCtx(this, controller: p, source: id, sourceZcc: o.zcc);
        final amount = a.produce.fixed.isNotEmpty && a.produce.fixed.length == 1 ? evalAmount(a.produce.amount, ctx) : (a.produce.fixed.isNotEmpty ? a.produce.fixed.length : evalAmount(a.produce.amount, ctx));
        if (amount <= 0) continue;
        final sac = a.cost.parts.any((x) => x is SacrificeCost);
        out.add(_ManaSource(id, i, a.produce.possible, amount, priority: (sac ? 3 : (c.isCreature ? 1 : 0)) * 10 + (a.produce.possible.length > 1 ? 1 : 0), restricted: a.produce.restriction != null, fixed: a.produce.fixed.length > 1 ? a.produce.fixed : null));
        break; // one mana ability per permanent for automatic payment
      }
    }
    out.sortStable((a, b) => a.priority != b.priority ? a.priority - b.priority : a.id - b.id);
    return out;
  }

  /// Activates a mana ability and adds its mana to the pool.
  void _activateManaAbility(PlayerId p, ObjId id, int index, int type) {
    final o = state.objOrNull(id);
    if (o == null || o.zone != Zone.battlefield) throw GameError('Not on the battlefield');
    final c = chars(id);
    if (c.controller != p) throw GameError('Not yours');
    if (index < 0 || index >= c.abilities.length || c.abilities[index] is! ManaAbility) throw GameError('Not a mana ability');
    final a = c.abilities[index] as ManaAbility;
    if (!_canPayManaAbilityCost(p, id, a)) throw GameError("Can't activate");
    final ctx = EvalCtx(this, controller: p, source: id, sourceZcc: o.zcc);
    if (a.cost.tap) _tap(id);
    final produce = a.produce;
    final possible = produce.chosenColor && o.chosenColor != null ? [ManaType.of(ManaColor.fromWord(o.chosenColor!)!)] : produce.possible;
    final units = <ManaUnit>[];
    if (produce.fixed.isNotEmpty) {
      if (produce.fixed.length == 1) {
        final n = evalAmount(produce.amount, ctx);
        for (var i = 0; i < n; i++) {
          units.add(ManaUnit(produce.fixed.first, restriction: produce.restriction, sourceId: id));
        }
      } else {
        for (final t in produce.fixed) {
          units.add(ManaUnit(t, restriction: produce.restriction, sourceId: id));
        }
      }
    } else {
      final t = type >= 0 && type < ManaType.values.length && possible.contains(ManaType.values[type]) ? ManaType.values[type] : possible.first;
      final n = evalAmount(produce.amount, ctx);
      for (var i = 0; i < n; i++) {
        units.add(ManaUnit(t, restriction: produce.restriction, sourceId: id));
      }
    }
    for (final part in a.cost.parts) {
      if (part is SacrificeCost && part.self) _sacrifice(id);
    }
    state.player(p).pool.addAll(units);
    _dirty();
  }

  /// Pays [cost]: asks how (automatic, or chosen sources), taps them, spends the pool.
  void _payMana(PlayerId p, ManaCost cost, {ObjId? forSpell, String prompt = 'Pay mana'}) {
    final need = cost.normalized();
    if (need.isEmpty || (need.symbols.length == 1 && need.symbols.first is GenericSymbol && (need.symbols.first as GenericSymbol).amount == 0)) return;
    final answer = ask(Decision(kind: DecisionKind.payMana, player: p, prompt: '$prompt: ${need.text}', extra: {'cost': need.text}, source: forSpell, cancellable: true));
    if (answer.isEmpty) {
      final plan = _autoPayPlan(p, need, forSpell);
      if (plan == null) throw GameError('Not enough mana for ${need.text}');
      for (final (id, idx, t) in plan) {
        _activateManaAbility(p, id, idx, t);
      }
    } else {
      if (answer.length % 3 != 0) throw GameError('Malformed payment');
      for (var i = 0; i < answer.length; i += 3) {
        _activateManaAbility(p, answer[i], answer[i + 1], answer[i + 2]);
      }
    }
    _spendPool(p, need, forSpell);
  }

  /// Spends pool mana on [cost]; throws if it can't. Phyrexian symbols fall back to 2 life.
  void _spendPool(PlayerId p, ManaCost cost, ObjId? forSpell) {
    final pl = state.player(p);
    final pool = List.of(pl.pool);
    bool usable(ManaUnit u) => u.restriction == null || (forSpell != null && matchesFilter(u.restriction!.copyWith(zone: ZoneKind.stack), forSpell, EvalCtx(this, controller: p)));
    int take(bool Function(ManaUnit) ok) {
      for (var i = 0; i < pool.length; i++) {
        if (usable(pool[i]) && ok(pool[i])) {
          pool.removeAt(i);
          return 1;
        }
      }
      return 0;
    }

    var lifeToPay = 0;
    final generic = <int>[];
    // Colored first, then hybrid, then Phyrexian, then generic.
    final order = [...cost.symbols.whereType<ColoredSymbol>(), ...cost.symbols.whereType<HybridSymbol>(), ...cost.symbols.whereType<PhyrexianSymbol>(), ...cost.symbols.whereType<SnowSymbol>()];
    for (final s in order) {
      switch (s) {
        case ColoredSymbol(:final type):
          if (take((u) => u.type == type) == 0) throw GameError('Missing {${type.name}}');
        case HybridSymbol(:final a, :final b, :final generic):
          if (take((u) => u.type == b || (a != null && u.type == a)) == 0) {
            if (generic > 0) {
              for (var i = 0; i < generic; i++) {
                if (take((_) => true) == 0) throw GameError('Not enough mana');
              }
            } else {
              throw GameError('Missing hybrid mana');
            }
          }
        case PhyrexianSymbol(:final type):
          if (take((u) => u.type == type) == 0) lifeToPay += 2;
        case SnowSymbol():
          if (take((_) => true) == 0) throw GameError('Not enough mana');
        default:
      }
    }
    for (final s in cost.symbols) {
      if (s is GenericSymbol) generic.add(s.amount);
    }
    final g = generic.fold<int>(0, (a, b) => a + b);
    for (var i = 0; i < g; i++) {
      // Spend colorless first, then the colors least likely to be needed.
      if (take((u) => u.type == ManaType.C) == 1) continue;
      if (take((_) => true) == 0) throw GameError('Not enough mana');
    }
    if (lifeToPay > 0) {
      if (pl.life < lifeToPay) throw GameError('Not enough life for Phyrexian mana');
      _loseLife(p, lifeToPay);
    }
    pl.pool = pool;
    _dirty();
  }

  /// Picks mana abilities to activate for [cost], or null if impossible. Deterministic.
  List<(ObjId, int, int)>? _autoPayPlan(PlayerId p, ManaCost cost, ObjId? forSpell) {
    final sources = _manaSources(p);
    final pool = state.player(p).pool.where((u) => u.restriction == null || (forSpell != null && matchesFilter(u.restriction!.copyWith(zone: ZoneKind.stack), forSpell, EvalCtx(this, controller: p)))).map((u) => u.type).toList();
    // Requirements: colored symbols (as sets of acceptable types) and a generic count.
    final reqs = <Set<ManaType>>[];
    var generic = 0;
    for (final s in cost.symbols) {
      switch (s) {
        case GenericSymbol(:final amount):
          generic += amount;
        case ColoredSymbol(:final type):
          reqs.add({type});
        case HybridSymbol(:final a, :final b, generic: final g):
          if (g > 0) {
            reqs.add({b, ManaType.W, ManaType.U, ManaType.B, ManaType.R, ManaType.G, ManaType.C});
          } else {
            reqs.add({b, ?a});
          }
        case PhyrexianSymbol(:final type):
          reqs.add({type});
        case SnowSymbol():
          generic += 1;
        case XSymbol():
          break;
      }
    }
    // Pool pays first.
    final poolLeft = List.of(pool);
    final remaining = <Set<ManaType>>[];
    for (final r in reqs) {
      final i = poolLeft.indexWhere(r.contains);
      if (i >= 0) {
        poolLeft.removeAt(i);
      } else {
        remaining.add(r);
      }
    }
    final genericAfterPool = (generic - poolLeft.length).clamp(0, 1 << 30);
    // Sort requirements: most constrained first.
    remaining.sortStable((a, b) => a.length - b.length);
    final used = <int>{};
    final assign = <int, ManaType>{};
    // Multi-mana sources (Elvish Archdruid) give several units of their type.
    final unitsLeft = {for (var i = 0; i < sources.length; i++) i: sources[i].amount};

    bool solve(int r) {
      if (r == remaining.length) return true;
      for (var i = 0; i < sources.length; i++) {
        final s = sources[i];
        if ((unitsLeft[i] ?? 0) <= 0) continue;
        if (s.restricted) continue;
        final t = s.fixed != null ? s.fixed!.firstWhere(remaining[r].contains, orElse: () => ManaType.C) : s.types.firstWhere(remaining[r].contains, orElse: () => ManaType.C);
        if (!remaining[r].contains(t)) continue;
        if (assign.containsKey(i) && assign[i] != t && s.fixed == null) continue;
        final wasUsed = used.contains(i);
        used.add(i);
        final prevAssign = assign[i];
        assign[i] = t;
        unitsLeft[i] = unitsLeft[i]! - 1;
        if (solve(r + 1)) return true;
        unitsLeft[i] = unitsLeft[i]! + 1;
        if (prevAssign == null) {
          assign.remove(i);
        } else {
          assign[i] = prevAssign;
        }
        if (!wasUsed) used.remove(i);
      }
      return false;
    }

    if (!solve(0)) {
      // Phyrexian symbols can be paid with life instead.
      final hasPhyrexian = cost.symbols.any((s) => s is PhyrexianSymbol);
      if (!hasPhyrexian) return null;
      return _autoPayPlan(p, ManaCost([for (final s in cost.symbols) if (s is! PhyrexianSymbol) s]), forSpell);
    }
    // Leftover units from sources already tapped pay generic first, then more sources.
    var g = genericAfterPool;
    for (final i in used) {
      final left = unitsLeft[i] ?? 0;
      final take = left < g ? left : g;
      g -= take;
      unitsLeft[i] = left - take;
    }
    for (var i = 0; i < sources.length && g > 0; i++) {
      if (used.contains(i) || sources[i].restricted) continue;
      used.add(i);
      final take = sources[i].amount < g ? sources[i].amount : g;
      g -= take;
      assign[i] = sources[i].fixed?.first ?? sources[i].types.first;
    }
    if (g > 0) return null;
    final plan = <(ObjId, int, int)>[];
    for (var i = 0; i < sources.length; i++) {
      if (!used.contains(i)) continue;
      plan.add((sources[i].id, sources[i].ability, (assign[i] ?? sources[i].types.first).index));
    }
    return plan;
  }

  /// Can [p] pay [cost] now (for the table's hints)?
  bool canAfford(PlayerId p, ManaCost cost) => _autoPayPlan(p, cost.normalized(), null) != null;
}

class _ManaSource {
  _ManaSource(this.id, this.ability, this.types, this.amount, {required this.priority, this.restricted = false, this.fixed});
  final ObjId id;
  final int ability;
  final List<ManaType> types;
  final int amount;
  final int priority;
  final bool restricted;
  final List<ManaType>? fixed;
}
