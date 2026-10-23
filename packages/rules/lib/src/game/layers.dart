part of 'game.dart';

/// One continuous effect to apply while computing characteristics (CR 613).
class _LayerEffect {
  _LayerEffect(this.mod, this.timestamp, this.order, this.affects, this.ctx, {this.locked});
  final Mod mod;
  final int timestamp, order;
  final bool Function(ObjId id, Chars c) affects;
  final EvalCtx ctx;

  /// Amounts locked in when a resolved effect was created.
  final (int, int)? locked;

  int get layer => mod.layer;
  bool get cda => mod is SetPT && (mod as SetPT).cda;
}

/// Characteristics (CR 109.3) through the layer system (CR 613).
extension GameLayers on Game {
  /// The current characteristics of an object in any zone.
  Chars chars(ObjId id) {
    if (_computing) {
      final c = _passChars[id];
      if (c != null) return c;
      return _baseChars(state.obj(id));
    }
    _ensureChars();
    final c = _charCache[id];
    if (c != null) return c;
    final o = state.obj(id);
    final b = _baseChars(o);
    _applySelfCda(id, b);
    _charCache[id] = b;
    return b;
  }

  void _ensureChars() {
    if (_charVersion == state.version && identical(_charState, state)) return;
    _charCache = _computeAll();
    _charVersion = state.version;
    _charState = state;
  }

  /// Copiable values plus status: the card face, token, copy, or face-down 2/2 (CR 707, 708).
  Chars _baseChars(GameObject o) {
    if (o.faceDown) {
      return Chars(name: '', types: {CardType.creature}, subtypes: [], supertypes: {}, colors: {}, manaCost: null, power: 2, toughness: 2, loyalty: null, defense: null, abilities: [], controller: o.controller, owner: o.owner);
    }
    final spec = o.copyOfToken ?? o.token;
    Chars c;
    if (spec != null && o.copyOfCard == null) {
      c = _tokenChars(spec, o);
    } else {
      final def = db[o.copyOfCard ?? o.cardName];
      if (def == null) {
        c = Chars(name: o.cardName, types: {}, subtypes: [], supertypes: {}, colors: {}, manaCost: null, power: null, toughness: null, loyalty: null, defense: null, abilities: [], controller: o.controller, owner: o.owner);
      } else {
        final face = o.copyOfCard != null ? (o.copyOfFace ?? 0) : o.face;
        // A split card has both halves' characteristics combined except as a spell cast as one
        // half (CR 709.4); fused on the stack, it has both too (CR 702.102c).
        if (def.layout == Layout.split && def.faces.length > 1 && (o.zone != Zone.stack || face >= 2)) {
          c = _combinedChars(def, o);
        } else {
          c = _faceChars(def, face.clamp(0, def.faces.length - 1), o);
        }
      }
    }
    // Copy exceptions are part of the copiable values (CR 707.9b).
    for (final m in o.copyExtra) {
      _applyMod(c, m, EvalCtx(this, controller: o.controller, source: o.id, sourceZcc: o.zcc), o.id, null);
    }
    for (final t in o.extraTypes) {
      if (!c.subtypes.contains(t)) c.subtypes.add(t);
    }
    for (final a in c.abilities) {
      if (a is KeywordAbility) {
        c.keywords.add(a.kw);
        if (a.kw == Kw.allCreatureTypes) c.allCreatureTypes = true;
      }
    }
    return c;
  }

  /// One face of a card (CR 711–712, 715).
  Chars _faceChars(CardDef def, int faceIndex, GameObject o) {
    final f = def.faces[faceIndex];
    final parsed = OracleParser.parse(def);
    final abilities = faceIndex < parsed.faces.length ? parsed.faces[faceIndex].abilities : const <Ability>[];
    final c = Chars(
      name: f.name,
      types: Set.of(f.type.types),
      subtypes: List.of(f.type.subtypes),
      supertypes: Set.of(f.type.supertypes),
      colors: (f.colorIndicator ?? f.colors).toSet(),
      manaCost: f.manaCost,
      power: _ptValue(f.power),
      toughness: _ptValue(f.toughness),
      loyalty: f.loyalty == null ? null : int.tryParse(f.loyalty!) ?? 0,
      defense: f.defense == null ? null : int.tryParse(f.defense!) ?? 0,
      abilities: List.of(abilities),
      controller: o.controller,
      owner: o.owner,
    );
    // A transforming card's back face has its front face's mana value (CR 712.8e).
    if (faceIndex > 0 && (def.layout == Layout.transform || def.layout == Layout.meld)) c.mvOverride = def.front.manaValue;
    return c;
  }

  /// Both halves of a split card at once: both names, the sum of the costs, every type and
  /// color (CR 709.4).
  Chars _combinedChars(CardDef def, GameObject o) {
    final parsed = OracleParser.parse(def);
    var cost = ManaCost.empty;
    for (final f in def.faces) {
      if (f.manaCost != null) cost = cost + f.manaCost!;
    }
    return Chars(
      name: def.name,
      types: {for (final f in def.faces) ...f.type.types},
      subtypes: [for (final f in def.faces) ...f.type.subtypes],
      supertypes: {for (final f in def.faces) ...f.type.supertypes},
      colors: {for (final f in def.faces) ...(f.colorIndicator ?? f.colors)},
      manaCost: cost,
      power: null,
      toughness: null,
      loyalty: null,
      defense: null,
      abilities: [for (final pf in parsed.faces) ...pf.abilities],
      controller: o.controller,
      owner: o.owner,
    );
  }

  Chars _tokenChars(TokenSpec s, GameObject o) {
    final c = Chars(
      name: s.name,
      types: Set.of(s.types),
      subtypes: List.of(s.subtypes),
      supertypes: Set.of(s.supertypes),
      colors: Set.of(s.colors),
      manaCost: null,
      power: s.power,
      toughness: s.toughness,
      loyalty: null,
      defense: null,
      abilities: [...s.abilities, for (final k in s.keywords) KeywordAbility(k.name, k)],
      controller: o.controller,
      owner: o.owner,
    );
    if (s.types.contains(CardType.creature)) {
      c.power ??= 0;
      c.toughness ??= 0;
    }
    return c;
  }

  int? _ptValue(String? s) {
    if (s == null) return null;
    final n = int.tryParse(s);
    if (n != null) return n;
    final m = RegExp(r'^(\d+)\+\*$').firstMatch(s);
    if (m != null) return int.parse(m.group(1)!);
    return 0;
  }

  /// Characteristic-defining abilities work in every zone (CR 604.3).
  void _applySelfCda(ObjId id, Chars c) {
    for (final a in c.abilities) {
      if (a is StaticAbility && a.zone == ZoneKind.anywhere && a.set is One && (a.set as One).ref is SelfRef) {
        for (final m in a.mods) {
          _applyMod(c, m, EvalCtx(this, controller: c.controller, source: id, sourceZcc: state.obj(id).zcc), id, null);
        }
      }
    }
  }

  Map<ObjId, Chars> _computeAll() {
    _computing = true;
    try {
      _passChars = {};
      var result = _computePass();
      // Second pass: conditions and amounts that look at other objects see first-pass results.
      _passChars = result;
      result = _computePass();
      return result;
    } finally {
      _computing = false;
      _passChars = {};
    }
  }

  Map<ObjId, Chars> _computePass() {
    final ids = [...state.battlefield, for (final i in state.stack) ?i.objId];
    final base = <ObjId, Chars>{for (final id in ids) id: _baseChars(state.obj(id))};
    final effects = <_LayerEffect>[];
    var order = 0;

    // Objects that lose all abilities don't contribute their static abilities (approximation of
    // CR 613.6 for the common cases).
    final stripped = <ObjId>{};
    for (final e in state.effects) {
      if (e.mods.any((m) => m is LoseAllAbilities)) {
        for (final (id, zcc) in e.affected) {
          if (state.objOrNull(id)?.zcc == zcc) stripped.add(id);
        }
      }
    }
    for (final id in state.battlefield) {
      if (state.obj(id).phasedOut) continue;
      for (final a in base[id]!.abilities) {
        if (a is StaticAbility && a.mods.any((m) => m is LoseAllAbilities)) {
          final ctx = EvalCtx(this, controller: base[id]!.controller, source: id, sourceZcc: state.obj(id).zcc);
          for (final t in state.battlefield) {
            if (_inSetForLayers(a.set, t, base[t]!, ctx)) stripped.add(t);
          }
        }
      }
    }

    // Static abilities of permanents (and emblems).
    for (final id in state.battlefield) {
      final o = state.obj(id);
      if (o.phasedOut || stripped.contains(id)) continue;
      final b = base[id]!;
      for (final a in b.abilities) {
        if (a is! StaticAbility || a.zone == ZoneKind.anywhere) continue;
        final ctx = EvalCtx(this, controller: b.controller, source: id, sourceZcc: o.zcc);
        if (a.condition != null && !evalCondition(a.condition!, ctx)) continue;
        for (final m in a.mods) {
          effects.add(_LayerEffect(m, o.timestamp, order++, (t, c) => _inSetForLayers(a.set, t, c, ctx), ctx));
        }
      }
    }
    for (final em in state.emblems) {
      for (final a in em.abilities) {
        if (a is! StaticAbility) continue;
        final ctx = EvalCtx(this, controller: em.owner, source: null, sourceZcc: 0);
        for (final m in a.mods) {
          effects.add(_LayerEffect(m, 0, order++, (t, c) => _inSetForLayers(a.set, t, c, ctx), ctx));
        }
      }
    }
    // Effects from resolved spells and abilities, with their locked affected sets.
    for (final e in state.effects) {
      if (e.rule != null) continue;
      final affected = {for (final (id, zcc) in e.affected) if (state.objOrNull(id)?.zcc == zcc) id};
      final ctx = EvalCtx(this, controller: e.controller, source: e.sourceId, sourceZcc: state.objOrNull(e.sourceId)?.zcc ?? 0);
      for (var i = 0; i < e.mods.length; i++) {
        effects.add(_LayerEffect(e.mods[i], e.timestamp, order++, (t, c) => affected.contains(t), ctx, locked: e.amounts[i]));
      }
    }
    effects.sort((a, b) {
      if (a.layer != b.layer) return a.layer - b.layer;
      if (a.cda != b.cda) return a.cda ? -1 : 1;
      if (a.timestamp != b.timestamp) return a.timestamp - b.timestamp;
      return a.order - b.order;
    });

    final out = <ObjId, Chars>{};
    for (final id in ids) {
      final c = base[id]!.copy();
      _applySelfCda(id, c);
      out[id] = c;
    }
    for (final e in effects) {
      for (final id in ids) {
        final c = out[id]!;
        if (state.obj(id).zone != Zone.battlefield && e.mod is! SetPT) continue;
        if (!e.affects(id, c)) continue;
        _applyMod(c, e.mod, e.ctx, id, e.locked);
      }
    }
    // Counters (CR 613.4c) and finishing touches.
    for (final id in ids) {
      final c = out[id]!;
      final o = state.obj(id);
      if (c.power != null) {
        final plus = o.counters['+1/+1'] ?? 0, minus = o.counters['-1/-1'] ?? 0;
        c.power = c.power! + plus - minus;
        c.toughness = (c.toughness ?? 0) + plus - minus;
      }
      if (c.isPlaneswalker) c.loyalty = o.counters['loyalty'] ?? 0;
      if (c.isBattle) c.defense = o.counters['defense'] ?? 0;
    }
    return out;
  }

  bool _inSetForLayers(ObjSet set, ObjId t, Chars c, EvalCtx ctx) {
    final o = state.obj(t);
    if (o.zone != Zone.battlefield || o.phasedOut) return false;
    switch (set) {
      case One(:final ref):
        switch (ref) {
          case SelfRef():
            return t == ctx.source;
          case AttachedTo():
            final src = state.objOrNull(ctx.source);
            return src != null && src.attachedTo == t;
          default:
            return false;
        }
      case All(:final filter):
        return matchesFilter(filter, t, ctx, ch: c);
    }
  }

  void _applyMod(Chars c, Mod m, EvalCtx ctx, ObjId id, (int, int)? locked) {
    switch (m) {
      case CopyOf():
        final targets = resolveObjs(One(m.obj), ctx);
        if (targets.isEmpty) return;
        final src = _baseChars(state.obj(targets.first));
        c
          ..name = src.name
          ..types = src.types
          ..subtypes = src.subtypes
          ..supertypes = src.supertypes
          ..colors = src.colors
          ..manaCost = src.manaCost
          ..power = src.power
          ..toughness = src.toughness
          ..abilities = src.abilities;
        c.keywords
          ..clear()
          ..addAll(src.keywords);
      case ControlBy():
        final ps = resolvePlayers(m.player, ctx);
        if (ps.isNotEmpty) c.controller = ps.first;
      case SetName():
        c.name = m.name;
      case TypeMod():
        if (m.replaceTypes) {
          c.types = Set.of(m.types);
        } else {
          c.types.addAll(m.types);
        }
        if (m.replaceSubtypes) {
          c.subtypes = List.of(m.subtypes);
          c.allCreatureTypes = false;
        } else {
          for (final s in m.subtypes) {
            if (!c.subtypes.contains(s)) c.subtypes.add(s);
          }
        }
        c.supertypes.addAll(m.supertypes);
        c.supertypes.removeAll(m.loseSupertypes);
      case ColorMod():
        if (m.add) {
          c.colors.addAll(m.colors);
        } else {
          c.colors = Set.of(m.colors);
        }
      case AddKw():
        c.keywords.add(m.kw);
        if (m.kw == Kw.allCreatureTypes) c.allCreatureTypes = true;
      case LoseKw():
        c.keywords.removeWhere((k) => k.name == m.kw.name);
        c.abilities.removeWhere((a) => a is KeywordAbility && a.kw.name == m.kw.name);
      case AddAbility():
        c.abilities.add(m.ability);
        if (m.ability is KeywordAbility) c.keywords.add((m.ability as KeywordAbility).kw);
      case LoseAllAbilities():
        c.abilities = [];
        c.keywords.clear();
        c.allCreatureTypes = false;
      case SetPT():
        final selfCtx = ctx.source == null ? ctx : ctx;
        if (locked != null) {
          if (m.power != null) c.power = locked.$1;
          if (m.toughness != null) c.toughness = locked.$2;
        } else {
          if (m.power != null) c.power = evalAmount(m.power!, selfCtx);
          if (m.toughness != null) c.toughness = evalAmount(m.toughness!, selfCtx);
        }
      case ModPT():
        if (c.power == null) return;
        final dp = locked?.$1 ?? evalAmount(m.power, ctx);
        final dt = locked?.$2 ?? evalAmount(m.toughness, ctx);
        c.power = c.power! + dp;
        c.toughness = (c.toughness ?? 0) + dt;
      case SwitchPT():
        final p = c.power;
        c.power = c.toughness;
        c.toughness = p;
    }
  }
}
