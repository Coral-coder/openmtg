/// Noun-phrase parsers shared by the oracle parser: object descriptions (filters), object and
/// player references, amounts, costs and keywords.
library;

import '../cards/card.dart';
import '../cards/mana.dart';
import '../ir/ir.dart';
import 'text.dart';

/// What a body being parsed has introduced so far: its targets and the antecedents of "it",
/// "that creature", "that player".
class BodyCtx {
  BodyCtx({this.trigger = false, this.selfIsCreature = true});
  final List<TargetSpec> targets = [];
  final bool trigger;
  final bool selfIsCreature;
  ObjRef? it;
  ObjSet? them;
  PlayerRef? thatPlayer;

  /// The player subject of the previous clause ("each player discards their hand, then draws
  /// seven cards": the second clause has the same subject).
  PlayerRef? lastSubject;

  /// The previous clause's verb, for references like "that creature's toughness" after a
  /// sacrifice.
  String? lastVerb;

  /// The trigger's subject, if not the source ("whenever another creature dies" → that creature).
  ObjRef? eventObj;

  /// Condition under which targets added now are chosen (kicked / not kicked).
  Condition? targetWhen;
  int _slot = 0;
  String newSlot() => 's${_slot++}';
  String? lastRemembered;

  (int, ObjRef?, ObjSet?, PlayerRef?, String?) mark() => (targets.length, it, them, thatPlayer, lastRemembered);
  void reset((int, ObjRef?, ObjSet?, PlayerRef?, String?) m) {
    targets.removeRange(m.$1, targets.length);
    it = m.$2;
    them = m.$3;
    thatPlayer = m.$4;
    lastRemembered = m.$5;
  }

  int addTarget(TargetSpec t) {
    targets.add(targetWhen == null ? t : TargetSpec(t.kind, filter: t.filter, who: t.who, min: t.min, max: t.max, differentControllers: t.differentControllers, sameZoneOwner: t.sameZoneOwner, distinctFrom: t.distinctFrom, when: targetWhen));
    return targets.length - 1;
  }
}

// ---------------------------------------------------------------------------------------------
// Amounts
// ---------------------------------------------------------------------------------------------

Amount? parseAmount(String s) {
  final t = s.trim();
  if (t == 'x') return const XValue();
  final n = numberWord(t);
  if (n != null) return Fixed(n);
  if (t == 'that many' || t == 'that much') return const EventAmount();
  return null;
}

/// "where X is ...", "equal to ...", "for each ..." quantities.
Amount? parseQuantity(String s, BodyCtx ctx) {
  var t = s.trim();
  if (t.startsWith('the ')) t = t.substring(4);
  final simple = parseAmount(t);
  if (simple != null) return simple;
  final sac = rx(t, r"that creature's (power|toughness)");
  if (sac != null && ctx.lastVerb == 'sacrifice') return ResultAmount(sac[1] == 'power' ? 'sacPower' : 'sacToughness');
  final m1 = rx(t, r"(?:its|~'s|that creature's) (power|toughness|mana value)");
  if (m1 != null) {
    final stat = Stat.values.firstWhere((s) => s.name == (m1[1] == 'mana value' ? 'manaValue' : m1[1]));
    return StatOf(stat, t.startsWith('~') ? const SelfRef() : (ctx.it ?? const SelfRef()));
  }
  if (t == "this creature's power" || t == "~'s power") return const StatOf(Stat.power, SelfRef());
  final m2 = rx(t, r'number of (.+)');
  if (m2 != null) return countPhrase(m2[1], ctx);
  if (t == 'amount of life you gained this turn' || t == 'life you gained this turn') return const TurnCount(TurnStat.lifeGained, You());
  if (t == 'life lost this way') return const ResultAmount('lifeLost');
  if (t == 'your life total') return const LifeTotal(You());
  final m3 = rx(t, r'total power of (.+)');
  if (m3 != null) {
    final f = parseGroup(m3[1], ctx);
    if (f != null) return TotalStat(Stat.power, f);
  }
  final m4 = rx(t, r'number of (\+1/\+1|loyalty|soul|charge|[a-z]+) counters on (~|it)');
  if (m4 != null) return CountersOn(m4[1], m4[2] == '~' ? const SelfRef() : (ctx.it ?? const SelfRef()));
  final m5 = rx(t, r'number of different mana values among (.+)');
  if (m5 != null) {
    final g = parseGroup(m5[1], ctx);
    if (g != null) return DistinctManaValues(g);
  }
  return null;
}

/// "creatures you control", "cards in your graveyard", "goblins you control", "opponents".
Amount? countPhrase(String s, BodyCtx ctx) {
  final t = s.trim();
  if (t == 'opponents you have' || t == 'opponent') return const PlayerCount(EachOpponent());
  final m = rx(t, r"(.+?) cards? in (your|target player's|that player's|your opponents'|all) graveyards?");
  if (m != null) {
    final f = parseFilterCore(m[1]) ?? (m[1] == 'card' || m[1] == 'cards' ? Filter.any : null);
    if (f == null) return null;
    final who = switch (m[2]) { 'your' => const You(), "your opponents'" => const EachOpponent(), 'all' => const EachPlayer(), _ => const EventPlayer() };
    return CardsIn(ZoneKind.graveyard, who, f.copyWith(card: true, zone: ZoneKind.graveyard));
  }
  final m2 = rx(t, r'cards in (your|your opponents\x27|all) graveyards?');
  if (m2 != null) {
    final who = switch (m2[1]) { 'your' => const You(), 'all' => const EachPlayer(), _ => const EachOpponent() };
    return CardsIn(ZoneKind.graveyard, who, const Filter(card: true, zone: ZoneKind.graveyard));
  }
  final m3 = rx(t, r'cards in (your|that player\x27s) hand');
  if (m3 != null) return CardsIn(ZoneKind.hand, m3[1] == 'your' ? const You() : const EventPlayer(), const Filter(card: true, zone: ZoneKind.hand));
  final g = parseGroup(t, ctx);
  if (g != null) return CountOf(g);
  return null;
}

// ---------------------------------------------------------------------------------------------
// Object descriptions (filters)
// ---------------------------------------------------------------------------------------------

const _typeWords = {
  'artifact': CardType.artifact,
  'artifacts': CardType.artifact,
  'creature': CardType.creature,
  'creatures': CardType.creature,
  'enchantment': CardType.enchantment,
  'enchantments': CardType.enchantment,
  'land': CardType.land,
  'lands': CardType.land,
  'planeswalker': CardType.planeswalker,
  'planeswalkers': CardType.planeswalker,
  'instant': CardType.instant,
  'instants': CardType.instant,
  'sorcery': CardType.sorcery,
  'sorceries': CardType.sorcery,
  'battle': CardType.battle,
  'battles': CardType.battle,
  'kindred': CardType.kindred,
};

const _colorWords = {'white': ManaColor.white, 'blue': ManaColor.blue, 'black': ManaColor.black, 'red': ManaColor.red, 'green': ManaColor.green};

/// Parses the core of an object description: "nontoken creature you control with power 2 or
/// less", "instant or sorcery card", "artifact, enchantment, or creature with flying".
/// Returns null if any word isn't understood.
Filter? parseFilterCore(String phrase) {
  var t = phrase.trim();
  if (t.isEmpty) return null;
  var f = const Filter();
  // Trailing qualifiers.
  var changed = true;
  while (changed) {
    changed = false;
    final ctl = [
      (' you control', Who.you),
      (' you don\'t control', Who.notYou),
      (' an opponent controls', Who.opponent),
      (' your opponents control', Who.opponent),
      (' target opponent controls', Who.opponent),
      (' that player controls', Who.opponent),
      (' you own', Who.you),
    ];
    for (final (suffix, who) in ctl) {
      if (t.endsWith(suffix)) {
        t = t.substring(0, t.length - suffix.length).trim();
        f = suffix == ' you own' ? f.copyWith(owner: who) : f.copyWith(controller: who);
        changed = true;
      }
    }
    final w = RegExp(r'^(.+?) (with|without) (.+)$').firstMatch(t);
    if (w != null) {
      final q = _withClause(w.group(3)!, f, without: w.group(2) == 'without');
      if (q != null) {
        f = q;
        t = w.group(1)!;
        changed = true;
      }
    }
    final named = RegExp(r'^(.+?) named (.+)$').firstMatch(t);
    if (named != null) {
      f = f.copyWith(name: named.group(2)!);
      t = named.group(1)!;
      changed = true;
    }
    for (final z in const [
      (' from your graveyard', ZoneKind.graveyard, Who.you),
      (' in your graveyard', ZoneKind.graveyard, Who.you),
      (' from a graveyard', ZoneKind.graveyard, Who.any),
      (' in a graveyard', ZoneKind.graveyard, Who.any),
      (' from all graveyards', ZoneKind.graveyard, Who.any),
      (' in all graveyards', ZoneKind.graveyard, Who.any),
      (' from an opponent\'s graveyard', ZoneKind.graveyard, Who.opponent),
      (' in an opponent\'s graveyard', ZoneKind.graveyard, Who.opponent),
      (' in your hand', ZoneKind.hand, Who.you),
      (' from your hand', ZoneKind.hand, Who.you),
      (' from exile', ZoneKind.exile, Who.any),
      (' you own in exile', ZoneKind.exile, Who.you),
      (' on the battlefield', ZoneKind.battlefield, Who.any),
      (' that was put there this turn', ZoneKind.graveyard, Who.any),
    ]) {
      if (t.endsWith(z.$1)) {
        t = t.substring(0, t.length - z.$1.length).trim();
        f = f.copyWith(zone: z.$2, owner: z.$3 == Who.any ? f.owner : z.$3, card: true, putThereThisTurn: z.$1.contains('this turn') ? true : null);
        changed = true;
      }
    }
    if (t.endsWith(' of the chosen type')) {
      t = t.substring(0, t.length - 19);
      f = f.copyWith(chosenType: true);
      changed = true;
    }
    if (t.endsWith(' of the chosen color')) {
      t = t.substring(0, t.length - 20);
      f = f.copyWith(chosenColor: true);
      changed = true;
    }
  }
  // Leading qualifiers.
  final words = t.split(' ');
  var i = 0;
  while (i < words.length) {
    final w = words[i];
    if (w == 'other' || w == 'another') {
      f = f.copyWith(other: true);
    } else if (w == 'nontoken') {
      f = f.copyWith(token: false);
    } else if (w == 'token' && i + 1 < words.length) {
      f = f.copyWith(token: true);
    } else if (w == 'tapped') {
      f = f.copyWith(tapped: true);
    } else if (w == 'untapped') {
      f = f.copyWith(tapped: false);
    } else if (w == 'attacking' && i + 2 < words.length && words[i + 1] == 'or' && words[i + 2] == 'blocking') {
      f = f.copyWith(attacking: true, blocking: true);
      i += 2;
    } else if (w == 'attacking') {
      f = f.copyWith(attacking: true);
    } else if (w == 'blocking') {
      f = f.copyWith(blocking: true);
    } else if (w == 'legendary') {
      f = f.copyWith(supertypes: {...f.supertypes, Supertype.legendary});
    } else if (w == 'nonlegendary') {
      f = f.copyWith(notSupertypes: {...f.notSupertypes, Supertype.legendary});
    } else if (w == 'basic') {
      f = f.copyWith(supertypes: {...f.supertypes, Supertype.basic});
    } else if (w == 'nonbasic') {
      f = f.copyWith(notSupertypes: {...f.notSupertypes, Supertype.basic});
    } else if (w == 'snow') {
      f = f.copyWith(supertypes: {...f.supertypes, Supertype.snow});
    } else if (w == 'multicolored') {
      f = f.copyWith(multicolored: true);
    } else if (w == 'monocolored') {
      f = f.copyWith(multicolored: false, colorless: false);
    } else if (w == 'colorless') {
      f = f.copyWith(colorless: true);
    } else if (w == 'historic') {
      f = f.copyWith(historic: true);
    } else if (_colorWords.containsKey(w)) {
      // "white", "black and green", "red or white"
      final cs = {...f.colors, _colorWords[w]!};
      while (i + 2 < words.length && (words[i + 1] == 'and' || words[i + 1] == 'or') && _colorWords.containsKey(words[i + 2])) {
        cs.add(_colorWords[words[i + 2]]!);
        i += 2;
      }
      f = f.copyWith(colors: cs);
    } else if (w.startsWith('non') && _colorWords.containsKey(w.substring(3))) {
      f = f.copyWith(notColors: {...f.notColors, _colorWords[w.substring(3)]!});
    } else if (w.startsWith('non-') && subtypeWords.containsKey(w.substring(4))) {
      f = f.copyWith(notSubtypes: {...f.notSubtypes, subtypeWords[w.substring(4)]!});
    } else if (w.startsWith('non') && _typeWords.containsKey(w.substring(3))) {
      f = f.copyWith(notTypes: {...f.notTypes, _typeWords[w.substring(3)]!});
    } else {
      break;
    }
    i++;
  }
  final rest = words.sublist(i).join(' ');
  return _typeList(rest, f);
}

/// The type part: "creature", "artifact or enchantment", "artifact, enchantment, or creature",
/// "cat", "elf creature", "instant and sorcery spells", "permanent", "card", "spell".
Filter? _typeList(String s, Filter f) {
  var t = s.trim();
  if (t.isEmpty) return null;
  // Nouns that end the phrase.
  for (final noun in const ['cards', 'card', 'spells', 'spell', 'permanents', 'permanent', 'tokens', 'token', 'sources', 'source', 'objects', 'object']) {
    if (t == noun || t.endsWith(' $noun')) {
      t = t == noun ? '' : t.substring(0, t.length - noun.length - 1);
      switch (noun) {
        case 'cards' || 'card':
          f = f.copyWith(card: true, zone: f.zone == ZoneKind.battlefield ? ZoneKind.anywhere : f.zone);
        case 'spells' || 'spell':
          f = f.copyWith(spell: true, zone: ZoneKind.stack);
        case 'permanents' || 'permanent':
          f = f.copyWith(permanent: true);
        case 'tokens' || 'token':
          f = f.copyWith(token: true);
      }
      break;
    }
  }
  if (t.isEmpty) return f;
  // "artifact, enchantment, or creature" / "creature or planeswalker" / "instant and sorcery"
  final parts = t.replaceAll(', and/or ', ', ').replaceAll(' and/or ', ', ').replaceAll(', or ', ', ').replaceAll(' or ', ', ').replaceAll(', and ', ', ').replaceAll(' and ', ', ').split(', ');
  final types = <CardType>{};
  final subtypes = <String>{};
  final allTypes = <CardType>{};
  for (final p in parts) {
    final ws = p.trim().split(' ');
    if (ws.isEmpty) return null;
    // "artifact creature" (all of), "elf creature" (subtype + type), "elf warrior" (two subtypes?)
    final pTypes = <CardType>{};
    final pSubs = <String>{};
    for (final w in ws) {
      if (_typeWords.containsKey(w)) {
        pTypes.add(_typeWords[w]!);
      } else if (subtypeWords.containsKey(w)) {
        pSubs.add(subtypeWords[w]!);
      } else {
        return null;
      }
    }
    if (pTypes.length > 1 && parts.length == 1) {
      allTypes.addAll(pTypes);
    } else {
      types.addAll(pTypes);
    }
    subtypes.addAll(pSubs);
    if (pSubs.isNotEmpty && pTypes.isNotEmpty && parts.length > 1) {
      // "Elf creature or Goblin" is rare; keep it simple.
      return null;
    }
  }
  return f.copyWith(types: types.isEmpty ? f.types : types, allTypes: allTypes.isEmpty ? f.allTypes : allTypes, subtypes: subtypes.isEmpty ? f.subtypes : subtypes);
}

Filter? _withClause(String s, Filter f, {required bool without}) {
  final t = s.trim();
  final kw = parseKeywordName(t);
  if (kw != null) {
    return without ? f.copyWith(withoutKeywords: {...f.withoutKeywords, kw}) : f.copyWith(withKeywords: {...f.withKeywords, kw});
  }
  if (without) return null;
  final m = rx(t, r'(power|toughness|mana value) (\d+|x) or (greater|less)');
  if (m != null) {
    final cmp = m[3] == 'greater' ? Cmp.ge : Cmp.le;
    final a = parseAmount(m[2])!;
    return switch (m[1]) { 'power' => f.copyWith(power: (cmp, a)), 'toughness' => f.copyWith(toughness: (cmp, a)), _ => f.copyWith(manaValue: (cmp, a)) };
  }
  final m2 = rx(t, r'(power|toughness|mana value) (\d+|x)');
  if (m2 != null) {
    final a = parseAmount(m2[2])!;
    return switch (m2[1]) { 'power' => f.copyWith(power: (Cmp.eq, a)), 'toughness' => f.copyWith(toughness: (Cmp.eq, a)), _ => f.copyWith(manaValue: (Cmp.eq, a)) };
  }
  final m3 = rx(t, r'(power|mana value) less than or equal to (.+)');
  if (m3 != null) {
    final q = parseQuantity(m3[2], BodyCtx());
    if (q == null) return null;
    return m3[1] == 'power' ? f.copyWith(power: (Cmp.le, q)) : f.copyWith(manaValue: (Cmp.le, q));
  }
  final m4 = rx(t, r'(?:a|an|one or more) (\+1/\+1|-1/-1|[a-z]+) counters? on (?:it|them)');
  if (m4 != null) return f.copyWith(withCounter: m4[1]);
  final m5 = rx(t, r'(\+1/\+1|-1/-1|[a-z]+) counters on (?:it|them)');
  if (m5 != null) return f.copyWith(withCounter: m5[1]);
  return null;
}

/// Keyword names usable in "with flying", "has trample".
String? parseKeywordName(String s) {
  const names = {
    'flying', 'first strike', 'double strike', 'deathtouch', 'defender', 'flash', 'haste', 'hexproof', 'indestructible', 'lifelink', 'menace',
    'reach', 'trample', 'vigilance', 'shroud', 'prowess', 'ward', 'flanking', 'shadow', 'fear', 'intimidate', 'horsemanship', 'skulk',
    'infect', 'wither', 'devoid', 'toxic', 'landwalk',
  };
  return names.contains(s) ? s : null;
}

/// A plural or "each/all" group: "creatures you control", "each creature without flying",
/// "all creature cards with mana value 2 or less from your graveyard".
ObjSet? parseGroup(String phrase, BodyCtx ctx) {
  var t = phrase.trim();
  for (final p in const ['each of ', 'all ', 'each ']) {
    if (t.startsWith(p)) {
      t = t.substring(p.length);
      break;
    }
  }
  if (t == 'them' || t == 'those creatures' || t == 'those cards' || t == 'those tokens' || t == 'those permanents') return ctx.them;
  final f = parseFilterCore(t);
  if (f == null) return null;
  return All(f);
}

// ---------------------------------------------------------------------------------------------
// Object references: targets, self, pronouns, groups
// ---------------------------------------------------------------------------------------------

/// Parses a reference to objects. Targets are added to [ctx]; on failure nothing is added.
/// [allowGroup]: plural/each/all phrases are acceptable.
ObjSet? parseObjects(String phrase, BodyCtx ctx, {bool allowGroup = true, TargetKind kind = TargetKind.object}) {
  final t = phrase.trim();
  final m = ctx.mark();
  final r = _parseObjects(t, ctx, allowGroup: allowGroup, kind: kind);
  if (r == null) ctx.reset(m);
  return r;
}

ObjSet? _parseObjects(String t, BodyCtx ctx, {required bool allowGroup, required TargetKind kind}) {
  if (t == '~' || t == 'itself') {
    ctx.it = const SelfRef();
    return const One(SelfRef());
  }
  if (const {'it', 'that creature', 'that permanent', 'that card', 'that token', 'the creature', 'that land', 'that artifact', 'that spell', 'the token', 'that planeswalker', 'the exiled card', 'that equipment'}.contains(t)) {
    final r = ctx.it ?? ctx.eventObj;
    if (r == null) return null;
    return One(r);
  }
  if (const {'them', 'those creatures', 'those cards', 'those tokens', 'those permanents', 'each of them'}.contains(t)) {
    return ctx.them;
  }
  if (t == 'enchanted creature' || t == 'enchanted permanent' || t == 'enchanted land' || t == 'equipped creature' || t == 'enchanted artifact') {
    ctx.it = const AttachedTo();
    return const One(AttachedTo());
  }
  // Targets.
  final tm = RegExp(r'^(up to (one|two|three|four|five|x) |any number of |one or two |(two|three|four) |another |)(other )?targets?(?: (.+))?$').firstMatch(t);
  if (tm != null) {
    final quant = tm.group(1)!;
    var noun = tm.group(5) ?? '';
    var min = 1, max = 1;
    if (quant.startsWith('up to')) {
      min = 0;
      max = numberWord(tm.group(2)!) ?? 1;
    } else if (quant.startsWith('any number')) {
      min = 0;
      max = 99;
    } else if (quant.startsWith('one or two')) {
      min = 1;
      max = 2;
    } else if (tm.group(3) != null) {
      min = max = numberWord(tm.group(3)!)!;
    }
    final other = quant.startsWith('another') || tm.group(4) != null;
    var differentControllers = false;
    if (noun.endsWith(' controlled by different players')) {
      noun = noun.substring(0, noun.length - 31);
      differentControllers = true;
    }
    var sameOwner = false;
    if (noun.endsWith(' from a single graveyard')) {
      noun = noun.substring(0, noun.length - 24) + ' from a graveyard';
      sameOwner = true;
    }
    if (noun == '' || noun == 'any target') return null;
    if (noun == 'player' || noun == 'players') {
      final i = ctx.addTarget(TargetSpec(TargetKind.player, min: min, max: max));
      ctx.thatPlayer = TargetPlayer(i);
      return null; // a player is not an object; callers use parsePlayer for this
    }
    if (noun == 'opponent' || noun == 'opponents') return null;
    var f = parseFilterCore(noun);
    if (f == null) return null;
    if (other) f = f.copyWith(other: true);
    final isSpell = f.spell;
    final i = ctx.addTarget(TargetSpec(isSpell ? TargetKind.spell : kind, filter: f, min: min, max: max, differentControllers: differentControllers, sameZoneOwner: sameOwner, distinctFrom: quant.startsWith('another') && ctx.targets.isNotEmpty ? [ctx.targets.length - 1] : const []));
    ctx.it = TargetObj(i);
    ctx.them = One(TargetObj(i));
    return One(TargetObj(i));
  }
  if (!allowGroup) return null;
  final g = parseGroup(t, ctx);
  if (g != null) ctx.them = g;
  return g;
}

/// "Any target" (CR 115.4) → a target spec.
int? parseAnyTarget(String t, BodyCtx ctx) {
  if (t == 'any target') return ctx.addTarget(const TargetSpec(TargetKind.any));
  if (t == 'any other target') return ctx.addTarget(const TargetSpec(TargetKind.any, filter: Filter(other: true)));
  if (t == 'target player or planeswalker') return ctx.addTarget(const TargetSpec(TargetKind.any, filter: Filter(types: {CardType.planeswalker})));
  if (t == 'target opponent or planeswalker' || t == 'target opponent or planeswalker an opponent controls') {
    return ctx.addTarget(const TargetSpec(TargetKind.any, who: Who.opponent, filter: Filter(types: {CardType.planeswalker})));
  }
  if (t == 'target creature or player') return ctx.addTarget(const TargetSpec(TargetKind.any, filter: Filter(types: {CardType.creature})));
  return null;
}

// ---------------------------------------------------------------------------------------------
// Players
// ---------------------------------------------------------------------------------------------

PlayerRef? parsePlayer(String phrase, BodyCtx ctx) {
  final t = phrase.trim();
  switch (t) {
    case 'you':
      return const You();
    case 'each opponent' || 'your opponents' || 'opponents' || 'each of your opponents':
      return const EachOpponent();
    case 'each player' || 'all players' || 'players':
      return const EachPlayer();
    case 'target player':
      final i = ctx.addTarget(const TargetSpec(TargetKind.player));
      ctx.thatPlayer = TargetPlayer(i);
      return TargetPlayer(i);
    case 'target opponent' || 'an opponent':
      if (t == 'an opponent' && !ctx.trigger) {
        // "An opponent chooses" outside triggers: in two-player games, the opponent.
        return const EachOpponent();
      }
      if (t == 'an opponent') return const EachOpponent();
      final i = ctx.addTarget(const TargetSpec(TargetKind.player, who: Who.opponent));
      ctx.thatPlayer = TargetPlayer(i);
      return TargetPlayer(i);
    case 'that player' || 'they' || 'the player':
      return ctx.thatPlayer ?? const EventPlayer();
    case 'its controller' || "that creature's controller" || "that permanent's controller" || "that spell's controller":
      final r = ctx.it;
      if (r == null) return null;
      return ControllerOf(r);
    case 'its owner' || "that card's owner" || "that creature's owner":
      final r = ctx.it;
      if (r == null) return null;
      return OwnerOf(r);
    case 'defending player':
      return const DefendingPlayer();
  }
  return null;
}

// ---------------------------------------------------------------------------------------------
// Costs
// ---------------------------------------------------------------------------------------------

/// Parses an activation cost: "{2}{W}, {T}, Sacrifice ~", "{T}, Tap ten untapped Elves you
/// control", "Remove three incubation counters from ~", "+1", "-2".
Cost? parseCost(String s) {
  final t = s.trim();
  final loyalty = rx(t, r'([+-]?)(\d+|x)');
  if (loyalty != null && (loyalty[1].isNotEmpty || loyalty[2] == '0')) {
    final n = loyalty[2] == 'x' ? 0 : int.parse(loyalty[2]);
    return Cost(loyalty: loyalty[1] == '-' ? -n : n);
  }
  ManaCost? mana;
  var tap = false, untap = false;
  final parts = <CostPart>[];
  for (final raw in _splitCost(t)) {
    final p = raw.trim();
    if (p.isEmpty) return null;
    if (RegExp(r'^(\{[^}]+\})+$').hasMatch(p)) {
      if (p == '{t}') {
        tap = true;
      } else if (p == '{q}') {
        untap = true;
      } else {
        mana = ManaCost.parse(p.toUpperCase());
      }
      continue;
    }
    final c = parseCostPart(p);
    if (c == null) return null;
    parts.add(c);
  }
  return Cost(mana: mana, tap: tap, untap: untap, parts: parts);
}

List<String> _splitCost(String t) {
  final out = <String>[];
  var depth = 0;
  final b = StringBuffer();
  for (var i = 0; i < t.length; i++) {
    final ch = t[i];
    if (ch == '"') depth = 1 - depth;
    if (ch == ',' && depth == 0) {
      out.add(b.toString());
      b.clear();
      continue;
    }
    b.write(ch);
  }
  out.add(b.toString());
  return out;
}

CostPart? parseCostPart(String p) {
  if (p == 'sacrifice ~') return const SacrificeCost(Filter.any, self: true);
  final sac = rx(p, r'sacrifice (a|an|another|two|three|x) (.+)');
  if (sac != null) {
    var f = parseFilterCore(sac[2]);
    if (f == null) return null;
    if (sac[1] == 'another') f = f.copyWith(other: true);
    return SacrificeCost(f.copyWith(controller: Who.you), n: numberWord(sac[1]) ?? 1);
  }
  final disc = rx(p, r'discard (a|an|two|three) (.+)');
  if (disc != null) {
    final f = disc[2] == 'card' || disc[2] == 'cards' ? Filter.any : parseFilterCore(disc[2]);
    if (f == null) return null;
    return DiscardCost(f, n: numberWord(disc[1]) ?? 1);
  }
  if (p == 'discard your hand') return const DiscardCost(Filter.any, hand: true);
  final life = rx(p, r'pay (\d+|x) life');
  if (life != null) return PayLifeCost(parseAmount(life[1])!);
  final rem = rx(p, r'remove (a|an|one|two|three|four|five|six|seven|eight|nine|ten|x|\d+) ([a-z+/0-9-]+) counters? from ~');
  if (rem != null) return RemoveCountersCost(rem[2], numberWord(rem[1]) ?? 0);
  final remAmong = rx(p, r'remove (\w+) counters from among (.+)');
  if (remAmong != null) {
    final f = parseFilterCore(remAmong[2]);
    if (f == null) return null;
    return RemoveCountersCost('', numberWord(remAmong[1]) ?? 0, fromAmong: f);
  }
  final tapU = rx(p, r'tap (an|a|two|three|four|five|ten|x|\d+) untapped (.+)');
  if (tapU != null) {
    final f = parseFilterCore(tapU[2]);
    if (f == null) return null;
    return TapCost(f.copyWith(tapped: false), numberWord(tapU[1]) ?? 1);
  }
  if (p == 'tap ~') return const TapCost(Filter(other: false), 0);
  final ex = rx(p, r'exile (a|an|two|three|x) (.+) from your graveyard');
  if (ex != null) {
    final f = ex[2] == 'card' || ex[2] == 'cards' ? Filter.any : parseFilterCore(ex[2]);
    if (f == null) return null;
    return ExileFromGraveyardCost(f, n: numberWord(ex[1]) ?? 1);
  }
  if (p == 'exile ~ from your graveyard') return const ExileFromGraveyardCost(Filter.any, self: true);
  final ret = rx(p, r"return (a|an) (.+) you control to its owner's hand");
  if (ret != null) {
    final f = parseFilterCore(ret[2]);
    if (f == null) return null;
    return ReturnCost(f.copyWith(controller: Who.you));
  }
  return null;
}

// ---------------------------------------------------------------------------------------------
// Keywords
// ---------------------------------------------------------------------------------------------

/// One keyword from a keyword line: "flying", "ward {2}", "ward-pay 2 life", "protection from
/// red", "hexproof from instants", "kicker {2}{w}", "equip {1}", "enchant creature".
/// Returns the ability (and, for costed keywords, the extra abilities they imply) or null.
List<Ability>? parseKeyword(String raw, String text) {
  final t = raw.trim();
  const simple = {
    'flying': Kw.flying,
    'first strike': Kw.firstStrike,
    'double strike': Kw.doubleStrike,
    'deathtouch': Kw.deathtouch,
    'defender': Kw.defender,
    'flash': Kw.flash,
    'haste': Kw.haste,
    'hexproof': Kw.hexproof,
    'indestructible': Kw.indestructible,
    'lifelink': Kw.lifelink,
    'menace': Kw.menace,
    'reach': Kw.reach,
    'trample': Kw.trample,
    'vigilance': Kw.vigilance,
    'shroud': Kw.shroud,
    'prowess': Kw.prowess,
  };
  // Keywords the engine checks by name (combat, damage, characteristics).
  const named = {'infect', 'wither', 'fear', 'intimidate', 'shadow', 'horsemanship', 'skulk', 'devoid'};
  if (named.contains(t)) return [KeywordAbility(text, Kw(t))];
  if (t == 'changeling') return [KeywordAbility(text, Kw.allCreatureTypes)];
  final toxic = rx(t, r'toxic (\d+)');
  if (toxic != null) return [KeywordAbility(text, Kw('toxic', n: int.parse(toxic[1])))];
  // Landwalk (CR 702.14): "swampwalk", "nonbasic landwalk", "legendary landwalk".
  final walk = rx(t, r'(plains|island|swamp|mountain|forest|desert)walk');
  if (walk != null) return [KeywordAbility(text, Kw('landwalk', filter: Filter(types: const {CardType.land}, subtypes: {subtypeWords[walk[1]]!})))];
  if (t == 'nonbasic landwalk') return [KeywordAbility(text, const Kw('landwalk', filter: Filter(types: {CardType.land}, notSupertypes: {Supertype.basic})))];
  if (t == 'legendary landwalk') return [KeywordAbility(text, const Kw('landwalk', filter: Filter(types: {CardType.land}, supertypes: {Supertype.legendary})))];
  final s = simple[t];
  if (s != null) {
    if (s == Kw.prowess) {
      return [
        KeywordAbility(text, s),
        TriggeredAbility('prowess', const CastTrigger(Who.you, Filter(notTypes: {CardType.creature}, spell: true)),
            const Body(effect: Grant(One(SelfRef()), [ModPT(Fixed(1), Fixed(1))]))),
      ];
    }
    return [KeywordAbility(text, s)];
  }
  final ward = rx(t, r'ward ?(\{[^}]+\}(?:\{[^}]+\})*)');
  if (ward != null) return [KeywordAbility(text, Kw('ward', cost: ManaCost.parse(ward[1].toUpperCase())))];
  final wardLife = rx(t, r'ward ?- ?pay (\d+) life');
  if (wardLife != null) return [KeywordAbility(text, Kw('ward', lifeCost: int.parse(wardLife[1])))];
  final prot = rx(t, r'protection from (.+)');
  if (prot != null) {
    final what = prot[1];
    if (what == 'everything') return [KeywordAbility(text, const Kw('protection', filter: Filter.any))];
    final c = _colorWords[what];
    if (c != null) return [KeywordAbility(text, Kw('protection', filter: Filter(colors: {c})))];
    final cs = rx(what, r'(white|blue|black|red|green) and from (white|blue|black|red|green)');
    if (cs != null) {
      return [
        KeywordAbility(text, Kw('protection', filter: Filter(colors: {_colorWords[cs[1]]!}))),
        KeywordAbility(text, Kw('protection', filter: Filter(colors: {_colorWords[cs[2]]!}))),
      ];
    }
    final f = parseFilterCore(what.endsWith('s') ? what : what);
    if (f != null) return [KeywordAbility(text, Kw('protection', filter: f))];
    return null;
  }
  final hfrom = rx(t, r'hexproof from (.+)');
  if (hfrom != null) {
    final c = _colorWords[hfrom[1]];
    final f = c != null ? Filter(colors: {c}) : parseFilterCore(hfrom[1]);
    if (f == null) return null;
    return [KeywordAbility(text, Kw('hexproof from', filter: f))];
  }
  final kicker = rx(t, r'kicker (\{[^}]+\}(?:\{[^}]+\})*)');
  if (kicker != null) {
    return [CastOptionAbility(text, CastOption(CastKind.kicker, cost: ManaCost.parse(kicker[1].toUpperCase()), label: 'Kicker'))];
  }
  final fb = rx(t, r'flashback (\{[^}]+\}(?:\{[^}]+\})*)');
  if (fb != null) {
    return [CastOptionAbility(text, CastOption(CastKind.flashback, cost: ManaCost.parse(fb[1].toUpperCase()), zone: ZoneKind.graveyard, label: 'Flashback'))];
  }
  final equip = rx(t, r'equip (\{[^}]+\}(?:\{[^}]+\})*)');
  if (equip != null) {
    return [
      ActivatedAbility(text, Cost(mana: ManaCost.parse(equip[1].toUpperCase())),
          const Body(targets: [TargetSpec(TargetKind.object, filter: Filter(types: {CardType.creature}, controller: Who.you))], effect: Attach(SelfRef(), TargetObj(0))),
          sorcerySpeed: true, isEquip: true),
    ];
  }
  final enchant = rx(t, r'enchant (.+)');
  if (enchant != null) {
    if (enchant[1] == 'player' || enchant[1] == 'opponent') return [EnchantAbility(text, Filter.any, player: true)];
    final f = parseFilterCore(enchant[1]);
    if (f == null) return null;
    return [EnchantAbility(text, f)];
  }
  final aff = rx(t, r'affinity for (.+)');
  if (aff != null) {
    final f = parseFilterCore(aff[1]);
    if (f == null) return null;
    return [RuleAbility(text, CostChange(Filter.any, 0, amount: CountOf(All(f.copyWith(controller: Who.you))), selfOnly: true), zone: ZoneKind.hand)];
  }
  final cycling = rx(t, r'cycling (\{[^}]+\}(?:\{[^}]+\})*)');
  if (cycling != null) {
    return [
      ActivatedAbility(text, Cost(mana: ManaCost.parse(cycling[1].toUpperCase()), parts: const [DiscardCost(Filter.any, self: true)]), const Body(effect: Draw(Fixed(1))), zone: ZoneKind.hand),
    ];
  }
  return null;
}
