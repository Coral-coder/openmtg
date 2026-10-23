/// Oracle text → ability IR, with the exact text that isn't understood yet (docs/PLAN.md §2,
/// Coverage). A card is supported only when every paragraph of every face parses completely.
library;

import '../cards/card.dart';
import '../cards/mana.dart';
import '../ir/ir.dart';
import 'phrases.dart';
import 'text.dart';

part 'library_hand.dart';
part 'more_effects.dart';

/// Bump when the parser or engine changes what it supports: the database's stored coverage is
/// recomputed when it was made by another version.
const engineVersion = 2;

class ParsedFace {
  ParsedFace(this.face, this.abilities, this.unsupported);
  final Face face;
  final List<Ability> abilities;
  final List<String> unsupported;
}

class ParsedCard {
  ParsedCard(this.card, this.faces, this.unsupported);
  final CardDef card;
  final List<ParsedFace> faces;

  /// Everything not handled: unparsed paragraphs (as printed) and unsupported card features.
  final List<String> unsupported;
  bool get supported => unsupported.isEmpty;
}

/// Layouts the engine plays today.
const supportedLayouts = {Layout.normal, Layout.token, Layout.split, Layout.adventure, Layout.modalDfc, Layout.transform};

class OracleParser {
  static final Map<String, ParsedCard> _cache = {};

  /// Rethrow parser crashes instead of reporting the paragraph as unsupported (tests).
  static bool strict = false;

  /// When set, collects what failed to parse ("sentence: …", "trigger: …", "static: …"), so
  /// tools can rank the gaps by how many cards each one blocks (bin/gaps.dart).
  static List<String>? diag;

  static ParsedCard parse(CardDef card) => _cache.putIfAbsent(card.name, () => _parse(card));

  static void clearCache() => _cache.clear();

  static ParsedCard _parse(CardDef card) {
    final faces = <ParsedFace>[];
    final unsupported = <String>[];
    if (!supportedLayouts.contains(card.layout)) {
      unsupported.add('Card layout: ${card.layout.scryfall}');
    }
    // Battles need protectors and their own combat rules (CR 310), which aren't in yet.
    if (card.faces.any((f) => f.type.types.contains(CardType.battle))) unsupported.add('Battles (CR 310)');
    for (final f in card.faces) {
      final pf = parseFace(f, cardName: card.name);
      faces.add(pf);
      unsupported.addAll(pf.unsupported);
    }
    return ParsedCard(card, faces, unsupported);
  }

  static ParsedFace parseFace(Face face, {String? cardName}) {
    final p = _FaceParser(face);
    p.run();
    return ParsedFace(face, p.abilities, p.unsupported);
  }

  /// Parses a quoted ability granted by an effect ("gains '{T}: Add {C}.'").
  static Ability? parseGranted(String text, {bool creature = true}) {
    final f = Face(name: '~', typeLine: creature ? 'Creature' : 'Artifact', oracleText: text);
    final p = _FaceParser(f);
    // Inside the quotes, "this creature" is the object that gets the ability.
    final t = text.trim().replaceAll(RegExp(r"\bthis (creature|artifact|enchantment|land|permanent|equipment|vehicle|token)\b"), '~');
    final r = p.paragraph(t);
    if (r == null || r.length != 1) return null;
    return r.first;
  }
}

class _FaceParser {
  _FaceParser(this.face) : isSpell = face.isInstantOrSorcery;
  final Face face;
  final bool isSpell;
  final List<Ability> abilities = [];
  final List<String> unsupported = [];

  /// An instant's or sorcery's effect paragraphs share one body.
  final List<String> _spellParas = [];
  final List<String> _spellRaw = [];

  late final String text;
  late final List<String> _rawParas;

  void run() {
    final legendary = face.type.supertypes.contains(Supertype.legendary);
    text = normalizeOracle(face.oracleText, face.name, legendary: legendary);
    _rawParas = _group(face.oracleText.split('\n'));
    final paras = _group(text.split('\n'));
    for (var i = 0; i < paras.length; i++) {
      final para = paras[i].trim();
      if (para.isEmpty) continue;
      final raw = i < _rawParas.length ? _rawParas[i] : para;
      List<Ability>? r;
      try {
        r = paragraph(para);
      } catch (e) {
        if (OracleParser.strict) rethrow;
        r = null;
      }
      if (r == null) {
        if (isSpell && _isSpellEffect(para)) {
          _spellParas.add(para);
          _spellRaw.add(raw);
          continue;
        }
        unsupported.add(raw.trim());
      } else {
        abilities.addAll(r);
      }
    }
    if (_spellParas.isNotEmpty) {
      final ctx = BodyCtx(selfIsCreature: false);
      final joined = _spellParas.join('. ');
      final modal = _spellParas.length == 1 ? _modal(joined, ctx) : null;
      if (modal != null) {
        abilities.add(SpellAbility(joined, modal));
      } else {
        // Paragraphs share one body (targets, "it"); a paragraph that fails is reported alone.
        final steps = <Effect>[];
        for (var i = 0; i < _spellParas.length; i++) {
          Effect? eff;
          try {
            eff = effects(_spellParas[i], ctx);
          } catch (e) {
            if (OracleParser.strict) rethrow;
          }
          if (eff == null) {
            unsupported.add(_spellRaw[i].trim());
          } else {
            steps.add(eff);
          }
        }
        if (steps.isNotEmpty) abilities.add(SpellAbility(joined, Body(targets: ctx.targets, effect: steps.length == 1 ? steps.first : Seq(steps))));
      }
    }
    // Basic lands keep their mana ability in reminder text, which normalization removes.
    if (face.isLand && !abilities.any((a) => a is ManaAbility)) {
      for (final st in face.type.subtypes) {
        final m = const {'Plains': ManaType.W, 'Island': ManaType.U, 'Swamp': ManaType.B, 'Mountain': ManaType.R, 'Forest': ManaType.G}[st];
        if (m != null) abilities.add(ManaAbility('{T}: Add {${m.name}}.', const Cost(tap: true), ManaProduce(fixed: [m])));
      }
    }
  }

  /// Bullet lines belong to the paragraph before them.
  List<String> _group(List<String> lines) {
    final out = <String>[];
    for (final l in lines) {
      if (l.trimLeft().startsWith('•') && out.isNotEmpty) {
        out[out.length - 1] = '${out.last}\n${l.trim()}';
      } else {
        out.add(l);
      }
    }
    return out;
  }

  bool _isSpellEffect(String p) => !p.startsWith('when') && !p.startsWith('at the beginning') && !RegExp(r'^[^"]*:').hasMatch(p);

  /// One paragraph → abilities, or null if not understood.
  List<Ability>? paragraph(String para) {
    var p = para.trim();
    // Ability words carry no rules meaning.
    final aw = RegExp(r'^([a-z0-9\x27! ]+) — (.+)$', dotAll: true).firstMatch(p);
    if (aw != null && abilityWords.contains(aw.group(1))) p = aw.group(2)!.trim();
    p = p.replaceAll(' — ', ' — ');

    final kws = _keywordLine(p, para);
    if (kws != null) return kws;

    if (isSpell) {
      final spellStatic = _spellStatic(p, para);
      if (spellStatic != null) return spellStatic;
      return null; // collected into the spell ability by run()
    }

    final loyalty = RegExp(r'^([+-]?\d+|[+-]x): (.+)$', dotAll: true).firstMatch(p);
    if (loyalty != null && face.type.types.contains(CardType.planeswalker)) {
      final cost = parseCost(loyalty.group(1)!);
      if (cost == null) return null;
      final ctx = BodyCtx();
      final body = _modal(loyalty.group(2)!, ctx) ?? _bodyOf(loyalty.group(2)!, ctx);
      if (body == null) return null;
      return [ActivatedAbility(para, cost, body, sorcerySpeed: true, oncePerTurn: true)];
    }

    final colon = indexOutsideQuotes(p, ': ');
    if (colon > 0 && !p.startsWith('when') && !p.startsWith('at ')) {
      final costText = p.substring(0, colon);
      final cost = parseCost(costText);
      if (cost != null) return _activated(para, cost, p.substring(colon + 2));
    }

    if (p.startsWith('when') || p.startsWith('at the beginning') || p.startsWith('at end of')) {
      return _triggered(para, p);
    }

    final st = libraryHandStatic(p, para) ?? _spellStatic(p, para) ?? _static(p, para);
    if (st == null) OracleParser.diag?.add('static: $p');
    return st;
  }

  // -------------------------------------------------------------------------------------------
  // Keyword lines
  // -------------------------------------------------------------------------------------------

  List<Ability>? _keywordLine(String p, String raw) {
    if (p.contains('.') && !p.contains('{') && !p.startsWith('ward')) return null;
    final parts = p.endsWith('.') ? [p.substring(0, p.length - 1)] : p.split(RegExp(r', |; '));
    final out = <Ability>[];
    for (final part in parts) {
      // Split-card keywords the casting rules read off the face (CR 702.102, 702.127).
      if (part.trim() == 'fuse' || part.trim() == 'aftermath') {
        out.add(KeywordAbility(raw, Kw(part.trim())));
        continue;
      }
      final k = parseKeyword(part.trim(), part.trim()) ?? _expandKeyword(part.trim());
      if (k == null) return null;
      out.addAll(k);
    }
    return out;
  }

  /// Keywords that are shorthand for abilities the parser already reads: each is rewritten as
  /// its rules text (CR 702) and parsed like any other paragraph.
  static final List<(RegExp, String)> _keywordTexts = [
    (RegExp(r'^exalted$'), 'whenever a creature you control attacks alone, that creature gets +1/+1 until end of turn'),
    (RegExp(r'^bushido (\d+)$'), 'whenever ~ blocks or becomes blocked, ~ gets +\$1/+\$1 until end of turn'),
    (RegExp(r'^persist$'), 'when ~ dies, if it had no -1/-1 counters on it, return it to the battlefield under its owner\'s control with a -1/-1 counter on it'),
    (RegExp(r'^undying$'), 'when ~ dies, if it had no +1/+1 counters on it, return it to the battlefield under its owner\'s control with a +1/+1 counter on it'),
    (RegExp(r'^soulshift (\d+)$'), 'when ~ dies, you may return target spirit card with mana value \$1 or less from your graveyard to your hand'),
    (RegExp(r'^afterlife (\d+)$'), 'when ~ dies, create \$1 1/1 white and black spirit creature tokens with flying'),
    (RegExp(r'^bloodthirst (\d+)$'), 'if an opponent was dealt damage this turn, ~ enters with \$1 +1/+1 counters on it'),
    (RegExp(r'^battle cry$'), 'whenever ~ attacks, each other attacking creature gets +1/+0 until end of turn'),
    (RegExp(r'^afflict (\d+)$'), 'whenever ~ becomes blocked, defending player loses \$1 life'),
    (RegExp(r'^annihilator (\d+)$'), 'whenever ~ attacks, defending player sacrifices \$1 permanents'),
    (RegExp(r'^training$'), 'whenever ~ attacks with another creature with greater power, put a +1/+1 counter on ~'),
    (RegExp(r'^dethrone$'), 'whenever ~ attacks the player with the most life or tied for most life, put a +1/+1 counter on ~'),
    (RegExp(r'^living weapon$'), 'when ~ enters, create a 0/0 black phyrexian germ creature token, then attach ~ to it'),
    (RegExp(r'^extort$'), 'whenever you cast a spell, you may pay {w/b}. if you do, each opponent loses 1 life and you gain that much life'),
    (RegExp(r'^evolve$'), 'whenever another creature you control enters, if that creature\'s power is greater than ~\'s power or that creature\'s toughness is greater than ~\'s toughness, put a +1/+1 counter on ~'),
    (RegExp(r'^modular (\d+)$'), '~ enters with \$1 +1/+1 counters on it'),
    (RegExp(r'^fabricate (\d+)$'), 'when ~ enters, put \$1 +1/+1 counters on it'),
    (RegExp(r'^riot$'), '~ enters with a +1/+1 counter on it'),
  ];

  List<Ability>? _expandKeyword(String k) {
    for (final (re, text) in _keywordTexts) {
      final m = re.firstMatch(k);
      if (m == null) continue;
      final body = text.replaceAllMapped(RegExp(r'\$(\d)'), (x) => m.group(int.parse(x.group(1)!))!);
      final r = paragraph(body);
      if (r == null) return null;
      return [for (final a in r) _relabel(a, k)];
    }
    // Crew N (CR 702.122).
    final crew = rx(k, r'crew (\d+)');
    if (crew != null) {
      final ctx = BodyCtx();
      final body = _bodyOf('~ becomes an artifact creature until end of turn', ctx);
      if (body == null) return null;
      return [ActivatedAbility(k, Cost(parts: [TapCost(const Filter(types: {CardType.creature}, other: true), 0, totalPower: int.parse(crew[1]))]), body)];
    }
    // Typecycling and landcycling (CR 702.29e).
    final tc = rx(k, r'(basic land|plains|island|swamp|mountain|forest|[a-z]+)cycling (\{[^}]+\}(?:\{[^}]+\})*)');
    if (tc != null) {
      final what = tc[1] == 'basic land' ? 'basic land' : tc[1];
      final ctx = BodyCtx();
      final body = _bodyOf('search your library for a $what card, reveal it, put it into your hand, then shuffle', ctx);
      if (body == null) return null;
      return [ActivatedAbility(k, Cost(mana: ManaCost.parse(tc[2].toUpperCase()), parts: const [DiscardCost(Filter.any, self: true)]), body, zone: ZoneKind.hand)];
    }
    return null;
  }

  /// Shows the keyword, not its expansion, as the ability's text.
  Ability _relabel(Ability a, String k) => switch (a) {
        TriggeredAbility() => TriggeredAbility(k, a.trigger, a.body, condition: a.condition, oncePerTurn: a.oncePerTurn, zone: a.zone, optionalCost: a.optionalCost),
        _ => a,
      };

  // -------------------------------------------------------------------------------------------
  // Activated abilities (CR 602) and mana abilities (CR 605)
  // -------------------------------------------------------------------------------------------

  List<Ability>? _activated(String raw, Cost cost, String rest) {
    var r = rest.trim();
    var sorcery = false, once = false, onlyOnce = false, yourTurn = false;
    Condition? cond;
    // "Choose one. Activate only as a sorcery.\n• …": the restriction comes before the modes.
    final midRestriction = RegExp(r'^(choose (?:one|two|three|one or more|one or both))\. (activate only [^.\n]+)\.?\n').firstMatch(r);
    if (midRestriction != null) {
      r = '${midRestriction.group(1)} —\n${r.substring(midRestriction.end)}. ${midRestriction.group(2)}';
    }
    // Activation windows (CR 602.5d).
    for (final (suffix, steps) in const [
      ('. activate only during your turn, before attackers are declared', {TurnStep.untap, TurnStep.upkeep, TurnStep.draw, TurnStep.main1, TurnStep.beginCombat}),
      ('. activate only during your upkeep', {TurnStep.upkeep}),
      ('. activate only during your end step', {TurnStep.end}),
    ]) {
      for (final s in [suffix, '$suffix.']) {
        if (r.endsWith(s)) {
          r = r.substring(0, r.length - s.length);
          yourTurn = true;
          cond = StepIn(steps);
        }
      }
    }
    for (final (suffix, steps) in const [
      ('. activate only during combat', {TurnStep.beginCombat, TurnStep.declareAttackers, TurnStep.declareBlockers, TurnStep.firstStrikeDamage, TurnStep.combatDamage, TurnStep.endCombat}),
      ('. activate only before blockers are declared', {TurnStep.untap, TurnStep.upkeep, TurnStep.draw, TurnStep.main1, TurnStep.beginCombat, TurnStep.declareAttackers, TurnStep.main2, TurnStep.end, TurnStep.cleanup}),
      ('. activate only during any upkeep step', {TurnStep.upkeep}),
      ('. activate only during an upkeep step', {TurnStep.upkeep}),
    ]) {
      for (final s in [suffix, '$suffix.']) {
        if (r.endsWith(s)) {
          r = r.substring(0, r.length - s.length);
          cond = StepIn(steps);
        }
      }
    }
    var changed = true;
    while (changed) {
      changed = false;
      for (final (suffix, kind) in const [
        ('. activate only as a sorcery.', 1),
        ('. activate only as a sorcery', 1),
        ('. activate only once each turn.', 2),
        ('. activate only once each turn', 2),
        ('. activate only once.', 3),
        ('. activate only once', 3),
        ('. activate only during your turn.', 4),
        ('. activate only during your turn', 4),
      ]) {
        if (r.endsWith(suffix)) {
          r = r.substring(0, r.length - suffix.length);
          switch (kind) {
            case 1:
              sorcery = true;
            case 2:
              once = true;
            case 3:
              onlyOnce = true;
            case 4:
              yourTurn = true;
          }
          changed = true;
        }
      }
      final cm = RegExp(r'^(.+)\. activate only if (.+?)\.?$').firstMatch(r);
      if (cm != null) {
        final c = condition(cm.group(2)!, BodyCtx());
        if (c != null) {
          cond = c;
          r = cm.group(1)!;
          changed = true;
        }
      }
    }
    // Mana abilities: "Add {G}.", "Add {R} or {G}.", "Add one mana of any color."
    final mana = _manaEffect(r.endsWith('.') ? r.substring(0, r.length - 1) : r);
    if (mana != null && !cost.parts.any((p) => p is TapCost && p.n > 0) && cost.loyalty == null) {
      return [ManaAbility(raw, cost, mana)];
    }
    final ctx = BodyCtx();
    final body = _modal(r, ctx) ?? _bodyOf(r, ctx);
    if (body == null) return null;
    final fromGraveyard = r.contains('~ from your graveyard') || cost.parts.any((p) => p is ExileFromGraveyardCost && p.self);
    return [
      ActivatedAbility(raw, cost, body, sorcerySpeed: sorcery, oncePerTurn: once, onlyOnce: onlyOnce, yourTurnOnly: yourTurn, condition: cond, zone: fromGraveyard ? ZoneKind.graveyard : ZoneKind.battlefield),
    ];
  }

  ManaProduce? _manaEffect(String s) {
    final t = s.trim();
    final m = rx(t, r'add ((?:\{[wubrgc]\})+)');
    if (m != null) return ManaProduce(fixed: _manaTypes(m[1]));
    final m2 = rx(t, r'add \{([wubrgc])\} or \{([wubrgc])\}');
    if (m2 != null) return ManaProduce(choice: [ManaType.fromSymbol(m2[1].toUpperCase())!, ManaType.fromSymbol(m2[2].toUpperCase())!]);
    final m3 = rx(t, r'add \{([wubrgc])\}, \{([wubrgc])\}, or \{([wubrgc])\}');
    if (m3 != null) return ManaProduce(choice: [for (final i in [1, 2, 3]) ManaType.fromSymbol(m3[i].toUpperCase())!]);
    if (t == 'add one mana of any color') return const ManaProduce(anyColor: true);
    if (t == 'add one mana of the chosen color') return const ManaProduce(chosenColor: true);
    final m4 = rx(t, r'add (two|three) mana of any one color');
    if (m4 != null) return ManaProduce(anyColor: true, amount: Fixed(numberWord(m4[1])!));
    final m5 = rx(t, r'add \{([wubrgc])\} for each (.+)');
    if (m5 != null) {
      final a = countPhrase(m5[2], BodyCtx());
      if (a == null) return null;
      return ManaProduce(fixed: [ManaType.fromSymbol(m5[1].toUpperCase())!], amount: a);
    }
    final m6 = rx(t, r'add one mana of any color\. spend this mana only to cast (?:an? )?(.+?) spells?');
    if (m6 != null) {
      final f = parseFilterCore(m6[1]);
      if (f == null) return null;
      return ManaProduce(anyColor: true, restriction: f);
    }
    final m7 = rx(t, r'add \{([wubrgc])\}\. spend this mana only to cast (?:an? )?(.+?) spells?');
    if (m7 != null) {
      final f = parseFilterCore(m7[2]);
      if (f == null) return null;
      return ManaProduce(fixed: [ManaType.fromSymbol(m7[1].toUpperCase())!], restriction: f);
    }
    return null;
  }

  List<ManaType> _manaTypes(String s) => [for (final m in RegExp(r'\{([wubrgc])\}').allMatches(s)) ManaType.fromSymbol(m.group(1)!.toUpperCase())!];

  // -------------------------------------------------------------------------------------------
  // Triggered abilities (CR 603)
  // -------------------------------------------------------------------------------------------

  List<Ability>? _triggered(String raw, String p) {
    // Split "trigger condition, effect" at the first comma that leaves a parseable trigger.
    var idx = indexOutsideQuotes(p, ', ');
    while (idx > 0) {
      final head = p.substring(0, idx);
      var rest = p.substring(idx + 2);
      final ctx = BodyCtx(trigger: true);
      final trig = _trigger(head, ctx);
      if (trig != null) {
        Condition? cond;
        var optionalCost = false;
        ManaCost? payCost;
        // Intervening if (CR 603.4).
        final ifm = RegExp(r'^if (.+?), (.+)$', dotAll: true).firstMatch(rest);
        if (ifm != null) {
          final c = condition(ifm.group(1)!, ctx);
          if (c != null) {
            cond = c;
            rest = ifm.group(2)!;
          }
        }
        // "you may pay {R}. if you do, ..."
        // Mana only: energy ({E}) is paid by the effect itself.
        final pay = RegExp(r'^you may pay ((?:\{[^}e]+\})+)\. if you do, (.+)$', dotAll: true).firstMatch(rest);
        if (pay != null) {
          payCost = ManaCost.parse(pay.group(1)!.toUpperCase());
          rest = pay.group(2)!;
          optionalCost = true;
        }
        final once = rest.endsWith('. this ability triggers only once each turn.') || rest.endsWith('. this ability triggers only once each turn');
        if (once) rest = rest.substring(0, rest.lastIndexOf('. this ability triggers only once each turn'));
        final out = <Ability>[];
        for (final t in trig) {
          final c2 = BodyCtx(trigger: true)
            ..eventObj = ctx.eventObj
            ..it = ctx.it
            ..thatPlayer = ctx.thatPlayer;
          final body = _modal(rest, c2) ?? _bodyOf(rest, c2);
          if (body == null) return null;
          final zone = _triggerZone(t, rest);
          out.add(TriggeredAbility(raw, t.$1, body, condition: allOf([cond, t.$2]), oncePerTurn: once, zone: zone, optionalCost: optionalCost ? payCost : null));
        }
        return out;
      }
      idx = indexOutsideQuotes(p, ', ', idx + 1);
    }
    final c = indexOutsideQuotes(p, ', ');
    OracleParser.diag?.add('trigger: ${c > 0 ? p.substring(0, c) : p}');
    return null;
  }

  /// Dies/"return this card from your graveyard" triggers work from the graveyard.
  ZoneKind _triggerZone((Trigger, Condition?) t, String rest) {
    // "When you cast ~" triggers from the stack; "when you cycle ~" from the graveyard (the card
    // is discarded as the cost).
    if (t.$1 case CastTrigger(self: true)) return ZoneKind.stack;
    if (t.$1 case CycleTrigger(self: true)) return ZoneKind.graveyard;
    if (rest.contains('return this card from your graveyard') || rest.contains('return ~ from your graveyard')) return ZoneKind.graveyard;
    return ZoneKind.battlefield;
  }

  /// "When ~ enters" → one or more triggers (with an event condition when needed).
  List<(Trigger, Condition?)>? _trigger(String head, BodyCtx ctx) {
    final h = head.trim();
    // "When you cycle ~ and when ~ dies", "when ~ enters and at the beginning of your upkeep".
    for (final sep in const [' and when ', ' and whenever ', ' and at ']) {
      final i = h.indexOf(sep);
      if (i > 0) {
        final a = _trigger(h.substring(0, i), ctx);
        final b = _trigger(h.substring(i + 5), ctx);
        if (a != null && b != null) return [...a, ...b];
      }
    }
    // "When ~ enters or dies", "when ~ enters or leaves the battlefield", "when ~ enters or is put
    // into a graveyard from the battlefield".
    final both = rx(h, r'(when|whenever) ~ (enters|dies|attacks) or (enters|dies|attacks|blocks|leaves the battlefield|is put into a graveyard from the battlefield)');
    if (both != null) {
      final a = _trigger('${both[1]} ~ ${both[2]}', ctx);
      final b = _trigger('${both[1]} ~ ${both[3]}', ctx);
      if (a == null || b == null) return null;
      return [...a, ...b];
    }
    final more = _moreTriggers(h, ctx);
    if (more != null) return more;
    final st = _stepTrigger(h);
    if (st != null) return [(st, null)];

    if (h == 'when ~ enter' || h == 'whenever ~ enter') return [(const EntersTrigger(One(SelfRef())), null)];
    var m = rx(h, r'(?:when|whenever) (.+?) enters(?: the battlefield)?(?: under your control)?');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      return [(EntersTrigger(set), null)];
    }
    m = rx(h, r'(?:when|whenever) (.+?) dies');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      return [(DiesTrigger(set), null)];
    }
    m = rx(h, r'(?:when|whenever) (.+?) leaves the battlefield');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      return [(LeavesTrigger(set), null)];
    }
    m = rx(h, r'whenever you attack(?: with (two|three|four|five) or more creatures)?');
    if (m != null) return [(YouAttackTrigger(min: m[1].isEmpty ? 1 : numberWord(m[1])!), null)];
    m = rx(h, r'(?:when|whenever) (.+?) attacks alone');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      return [(AttacksTrigger(set, alone: true), null)];
    }
    m = rx(h, r'(?:when|whenever) (.+?) blocks or becomes blocked');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      return [(BlocksTrigger(set), null), (BecomesBlockedTrigger(set), null)];
    }
    m = rx(h, r'(?:when|whenever) (.+?) attacks(?: while (.+))?');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      Condition? c;
      if (m[2].isNotEmpty) {
        c = condition(m[2], ctx);
        if (c == null) return null;
      }
      return [(AttacksTrigger(set, condition: c), null)];
    }
    m = rx(h, r'(?:when|whenever) (.+?) blocks');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      return [(BlocksTrigger(set), null)];
    }
    m = rx(h, r'(?:when|whenever) (.+?) becomes blocked');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      return [(BecomesBlockedTrigger(set), null)];
    }
    m = rx(h, r'(?:when|whenever) (.+?) deals (combat |noncombat |)damage to (a player|an opponent|a creature|you)( or (?:a )?(planeswalker|battle))?(?: during your turn)?');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      ctx.thatPlayer = const EventPlayer();
      final orTypes = switch (m[5]) { 'planeswalker' => const {CardType.planeswalker}, 'battle' => const {CardType.battle}, _ => const <CardType>{} };
      return [
        (
          DealsDamageTrigger(set, toPlayer: m[3] != 'a creature', toOpponent: m[3] == 'an opponent', toCreature: m[3] == 'a creature', combat: m[2] == 'combat ' ? true : (m[2] == 'noncombat ' ? false : null), orTypes: orTypes),
          null
        )
      ];
    }
    // "Whenever ~ deals damage" / "whenever equipped creature deals combat damage".
    m = rx(h, r'(?:when|whenever) (.+?) deals (combat |)damage');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      return [(DealsDamageTrigger(set, combat: m[2].isEmpty ? null : true), null)];
    }
    m = rx(h, r'(?:when|whenever) (.+?) deals combat damage during your turn');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      return [(DealsDamageTrigger(set, combat: true, duringYourTurn: true), null)];
    }
    m = rx(h, r'whenever a source you control deals (noncombat |combat |)damage to an opponent');
    if (m != null) {
      ctx.thatPlayer = const EventPlayer();
      return [(DealsDamageTrigger(const All(Filter(controller: Who.you)), toPlayer: true, toOpponent: true, combat: m[1].isEmpty ? null : m[1] == 'combat '), null)];
    }
    m = rx(h, r'(?:when|whenever) (you|an opponent|a player) casts? (?:a|an) (.+?)(?: during an opponent\x27s turn)?');
    if (m != null) {
      final who = switch (m[1]) { 'you' => Who.you, 'an opponent' => Who.opponent, _ => Who.any };
      final f = m[2] == 'spell' ? const Filter(spell: true, zone: ZoneKind.stack) : (parseFilterCore(m[2]) ?? _spellSubtypes(m[2]));
      if (f == null) return null;
      if (who != Who.you) ctx.thatPlayer = const EventPlayer();
      return [(CastTrigger(who, f, duringOpponentsTurn: h.endsWith("during an opponent's turn")), null)];
    }
    m = rx(h, r'whenever you gain life(?: for the first time (?:each turn|during each of your turns))?');
    if (m != null) {
      return [(GainLifeTrigger(Who.you, firstTimeEachTurn: h.contains('first time'), onlyYourTurn: h.contains('each of your turns')), null)];
    }
    m = rx(h, r'whenever (an opponent|a player|you) loses? life');
    if (m != null) {
      ctx.thatPlayer = const EventPlayer();
      return [(LoseLifeTrigger(m[1] == 'you' ? Who.you : (m[1] == 'an opponent' ? Who.opponent : Who.any)), null)];
    }
    m = rx(h, r'whenever (you|an opponent|a player) draws? (?:a card|your second card each turn)');
    if (m != null) {
      ctx.thatPlayer = const EventPlayer();
      return [(DrawTrigger(m[1] == 'you' ? Who.you : (m[1] == 'an opponent' ? Who.opponent : Who.any), nth: h.contains('second') ? 2 : 0), null)];
    }
    m = rx(h, r'whenever (you|an opponent|a player) discards? a card');
    if (m != null) {
      ctx.thatPlayer = const EventPlayer();
      ctx.eventObj = const EventObj();
      ctx.it = const EventObj();
      return [(DiscardTrigger(m[1] == 'you' ? Who.you : (m[1] == 'an opponent' ? Who.opponent : Who.any)), null)];
    }
    m = rx(h, r'whenever you put one or more (\+1/\+1|[a-z]+) counters on (.+)');
    if (m != null) {
      final set = _triggerSubject(m[2], ctx);
      if (set == null) return null;
      return [(CountersPutTrigger(set, m[1]), null)];
    }
    m = rx(h, r'whenever one or more (\+1/\+1|[a-z]+) counters are put on (.+)');
    if (m != null) {
      final set = _triggerSubject(m[2], ctx);
      if (set == null) return null;
      return [(CountersPutTrigger(set, m[1]), null)];
    }
    m = rx(h, r'whenever (.+?) becomes untapped');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      return [(BecomesUntappedTrigger(set), null)];
    }
    m = rx(h, r'whenever (.+?) becomes the target of a spell or ability an opponent controls');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      return [(BecomesTargetTrigger(set), null)];
    }
    m = rx(h, r'(?:when|whenever) (.+?) becomes the target of a spell or ability');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      return [(BecomesTargetTrigger(set, byOpponent: false), null)];
    }
    m = rx(h, r'whenever (.+?) is dealt damage');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      return [(IsDealtDamageTrigger(set), null)];
    }
    return null;
  }

  /// Trigger heads added for the second coverage round; null when none matches.
  List<(Trigger, Condition?)>? _moreTriggers(String h, BodyCtx ctx) {
    List<(Trigger, Condition?)>? one(Trigger? t) => t == null ? null : [(t, null)];

    // Spells being cast or copied.
    if (h == 'when you cast ~' || h == 'whenever you cast ~') return one(const CastTrigger(Who.you, Filter(spell: true), self: true));
    if (h == 'whenever you cast your second spell each turn') return one(const CastTrigger(Who.you, Filter(spell: true), nth: 2));
    if (h == 'whenever you cast your first spell each turn') return one(const CastTrigger(Who.you, Filter(spell: true), nth: 1));
    if (h == 'whenever you cast your first spell during each opponent\'s turn') return one(const CastTrigger(Who.you, Filter(spell: true), nth: 1, duringOpponentsTurn: true));
    if (h == 'whenever you cast a kicked spell') return one(const CastTrigger(Who.you, Filter(spell: true), kicked: true));
    var m = rx(h, r'whenever you cast or copy (?:a|an) (.+)');
    if (m != null) {
      final f = m[1] == 'spell' ? const Filter(spell: true) : (parseFilterCore(m[1]) ?? _spellSubtypes(m[1]));
      if (f == null) return null;
      return one(CastTrigger(Who.you, f, orCopy: true));
    }
    m = rx(h, r'whenever you cast (?:a|an) (.*?)spell that targets (.+)');
    if (m != null) {
      final sub = BodyCtx(trigger: true);
      final set = _triggerSubject(m[2], sub);
      if (set == null) return null;
      final f = m[1].isEmpty ? const Filter(spell: true) : (parseFilterCore('${m[1]}spell') ?? _spellSubtypes('${m[1]}spell'));
      if (f == null) return null;
      if (set case One(ref: SelfRef())) ctx.it = const SelfRef();
      return one(CastTrigger(Who.you, f, targets: set));
    }

    // Combat.
    m = rx(h, r'(?:when|whenever) (.+?) attacks and isn\x27t blocked');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      ctx.thatPlayer = const EventPlayer();
      return one(UnblockedTrigger(set));
    }
    m = rx(h, r'whenever ~ and at least (one|two|three|four) other creatures? attack');
    if (m != null) {
      ctx.it = const SelfRef();
      return one(AttacksTrigger(const One(SelfRef()), minAttackers: numberWord(m[1])! + 1));
    }
    m = rx(h, r'whenever (?:a|an) (.+?) attacks you(?: or a planeswalker you control)?');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      return one(AttacksTrigger(set, attacksYou: true));
    }
    m = rx(h, r'(?:when|whenever) (.+?) blocks or becomes blocked by (?:a|an) (.+)');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      final other = parseFilterCore(m[2]);
      if (set == null || other == null) return null;
      ctx.it = const EventObj();
      ctx.eventObj = const EventObj();
      return [(BlocksTrigger(set, other: other), null), (BecomesBlockedTrigger(set, other: other), null)];
    }
    m = rx(h, r'(?:when|whenever) (.+?) becomes blocked by (?:a|an) (.+)');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      final other = parseFilterCore(m[2]);
      if (set == null || other == null) return null;
      ctx.it = const EventObj();
      ctx.eventObj = const EventObj();
      return one(BecomesBlockedTrigger(set, other: other));
    }
    m = rx(h, r'(?:when|whenever) (.+?) blocks (?:a|an) (.+)');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      final other = parseFilterCore(m[2]);
      if (set == null || other == null) return null;
      ctx.it = const EventObj();
      ctx.eventObj = const EventObj();
      return one(BlocksTrigger(set, other: other));
    }

    // Dying, graveyards, sacrifice.
    m = rx(h, r'whenever (?:a|an) (.+?) dealt damage by ~ this turn dies');
    if (m != null) {
      final f = parseFilterCore(m[1]);
      if (f == null) return null;
      ctx.it = const EventObj();
      ctx.eventObj = const EventObj();
      return one(DiesTrigger(All(f), damagedBySelf: true));
    }
    m = rx(h, r'(?:when|whenever) (.+?) (?:is|are) put into (?:a|your|an opponent\x27s) graveyard from (the battlefield|anywhere)');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      return one(PutIntoGraveyardTrigger(set, fromBattlefield: m[2] == 'the battlefield'));
    }
    m = rx(h, r'whenever you sacrifice (a|an|another) (.+)');
    if (m != null) {
      final f = parseFilterCore(m[2]);
      if (f == null) return null;
      ctx.it = const EventObj();
      ctx.eventObj = const EventObj();
      return one(SacrificedTrigger(All(f.copyWith(controller: Who.you, other: m[1] == 'another'))));
    }

    // Tapping, transforming, targeting.
    m = rx(h, r'(?:when|whenever) (.+?) becomes tapped');
    if (m != null) {
      final set = _triggerSubject(m[1], ctx);
      if (set == null) return null;
      return one(TappedTrigger(set));
    }
    m = rx(h, r'(?:when|whenever) ~ transforms(?: into ~)?');
    if (m != null) {
      ctx.it = const SelfRef();
      return one(const TransformedTrigger(One(SelfRef())));
    }

    // Cycling, scrying, crimes.
    if (h == 'when you cycle ~' || h == 'whenever you cycle ~') return one(const CycleTrigger(Who.you, self: true));
    m = rx(h, r'whenever (you|a player|an opponent) cycles? (?:a|another) card');
    if (m != null) {
      if (m[1] != 'you') ctx.thatPlayer = const EventPlayer();
      return one(CycleTrigger(m[1] == 'you' ? Who.you : (m[1] == 'an opponent' ? Who.opponent : Who.any)));
    }
    // Cycling discards, so "cycle or discard" is one discard trigger (CR 702.29).
    if (h == 'whenever you cycle or discard a card') {
      ctx.eventObj = const EventObj();
      ctx.it = const EventObj();
      return one(const DiscardTrigger(Who.you));
    }
    if (h == 'whenever you scry') return one(const ScryTrigger(Who.you));
    if (h == 'whenever you surveil') return one(const ScryTrigger(Who.you, scry: false, surveil: true));
    if (h == 'whenever you scry or surveil' || h == 'whenever you surveil or scry') return one(const ScryTrigger(Who.you, surveil: true));
    if (h == 'whenever you gain life during your turn') return one(const GainLifeTrigger(Who.you, onlyYourTurn: true));
    if (h == 'whenever you lose life during your turn') {
      ctx.thatPlayer = const EventPlayer();
      return [(const LoseLifeTrigger(Who.you), const YourTurn())];
    }
    if (h == 'whenever one or more creatures you control attack') return one(const YouAttackTrigger());
    if (h == 'whenever ~ attack' || h == 'when ~ attack') {
      ctx.it = const SelfRef();
      return one(const AttacksTrigger(One(SelfRef())));
    }
    if (h == 'whenever a source deals damage to ~') {
      ctx.it = const SelfRef();
      return one(const IsDealtDamageTrigger(One(SelfRef())));
    }
    if (h == 'whenever you commit a crime') return one(const CrimeTrigger());
    return null;
  }

  /// "Spirit or arcane spell": spell subtypes the filter grammar doesn't know as card words.
  Filter? _spellSubtypes(String s) {
    final m = rx(s, r'([a-z]+(?: or [a-z]+)*) spell');
    if (m == null) return null;
    final subs = <String>{};
    for (final w in m[1].split(' or ')) {
      final st = w == 'arcane' ? 'Arcane' : subtypeWords[w];
      if (st == null) return null;
      subs.add(st);
    }
    return Filter(spell: true, subtypes: subs);
  }

  Trigger? _stepTrigger(String h) {
    if (h == 'at the beginning of the upkeep of enchanted creature\'s controller' || h == 'at the beginning of enchanted player\'s upkeep' || h == 'at the beginning of the upkeep of enchanted permanent\'s controller') {
      return const StepTrigger(TurnStep.upkeep, Who.any, ofAttached: true);
    }
    if (h == 'at the beginning of the end step of enchanted creature\'s controller' || h == 'at the beginning of enchanted player\'s end step') {
      return const StepTrigger(TurnStep.end, Who.any, ofAttached: true);
    }
    if (h == 'at end of combat' || h == 'at the end of combat') return const StepTrigger(TurnStep.endCombat, Who.any);
    if (h == 'at end of combat on your turn') return const StepTrigger(TurnStep.endCombat, Who.you);
    final m = rx(h, r'at the beginning of (your|each|each opponent\x27s|each player\x27s|the next|each of your) (upkeep|end step|draw step|precombat main phase|first main phase|postcombat main phase|combat|second main phase)s?(?: on your turn)?');
    if (m == null) {
      if (h == 'at the beginning of combat on your turn') return const StepTrigger(TurnStep.beginCombat, Who.you);
      if (h == 'at the beginning of each combat') return const StepTrigger(TurnStep.beginCombat, Who.any);
      if (h == 'at the beginning of the end step' || h == 'at end of turn') return const StepTrigger(TurnStep.end, Who.any);
      return null;
    }
    final whose = switch (m[1]) { 'your' || 'each of your' => Who.you, "each opponent's" => Who.opponent, _ => Who.any };
    final step = switch (m[2]) {
      'upkeep' => TurnStep.upkeep,
      'end step' => TurnStep.end,
      'draw step' => TurnStep.draw,
      'precombat main phase' || 'first main phase' => TurnStep.main1,
      'postcombat main phase' || 'second main phase' => TurnStep.main2,
      _ => TurnStep.beginCombat,
    };
    return StepTrigger(step, h.endsWith('on your turn') ? Who.you : whose);
  }

  /// The subject of a trigger: "~", "another creature you control", "~ or another nontoken Cat
  /// you control", "a land you control", "equipped creature".
  ObjSet? _triggerSubject(String s, BodyCtx ctx) {
    final t = s.trim();
    if (t == '~') {
      ctx.it = const SelfRef();
      return const One(SelfRef());
    }
    if (t == 'equipped creature' || t == 'enchanted creature' || t == 'enchanted land' || t == 'enchanted permanent' || t == 'enchanted artifact' || t == 'fortified land') {
      ctx.it = const AttachedTo();
      ctx.eventObj = const EventObj();
      return const One(AttachedTo());
    }
    final orAnother = rx(t, r'~ or (another .+)');
    if (orAnother != null) {
      final f = parseFilterCore(orAnother[1]);
      if (f == null) return null;
      ctx.it = const EventObj();
      ctx.eventObj = const EventObj();
      // "~ or another X": X including self.
      return All(f.copyWith(other: false));
    }
    var u = t;
    for (final a in const ['a ', 'an ', 'one or more ']) {
      if (u.startsWith(a)) {
        u = u.substring(a.length);
        break;
      }
    }
    final f = parseFilterCore(u);
    if (f == null) return null;
    ctx.it = const EventObj();
    ctx.eventObj = const EventObj();
    return All(f);
  }

  // -------------------------------------------------------------------------------------------
  // Conditions
  // -------------------------------------------------------------------------------------------

  Condition? condition(String s, BodyCtx ctx) {
    final t = s.trim();
    // After a clash: "if you win" (CR 701.23).
    if (t == 'you win' || t == 'you won' || t == 'you win the clash') return const WonClash();
    // Persist and undying: "it had no -1/-1 counters on it" (last known information).
    final hadNo = rx(t, r'(?:it|~) had no ([a-z+/0-9-]+) counters on it');
    if (hadNo != null) return Not(ObjMatches(const EventObj(), Filter(withCounter: hadNo[1])));
    final lh = libraryHandCondition(t);
    if (lh != null) return lh;
    switch (t) {
      case 'an opponent was dealt damage this turn' || 'an opponent has been dealt damage this turn':
        return const TurnStatCondition(TurnStat.damageTaken, EachOpponent(), Cmp.gt, 0);
      case 'you attacked this turn' || 'you attacked with a creature this turn':
        return const AttackedThisTurn();
      case 'a creature died this turn':
        return const CreatureDiedThisTurn();
      case 'this spell was kicked' || 'it was kicked' || '~ was kicked':
        return const Kicked();
      case 'it\'s your turn' || 'it is your turn':
        return const YourTurn();
      case 'you cast it' || 'it was cast' || 'you cast ~':
        return const WasCast();
      case 'an opponent lost life this turn':
        return const TurnStatCondition(TurnStat.lifeLost, EachOpponent(), Cmp.ge, 1);
      case 'you gained life this turn':
        return const TurnStatCondition(TurnStat.lifeGained, You(), Cmp.ge, 1);
      case 'your life total is greater than your starting life total':
        return const AmountCompare(LifeTotal(You()), Cmp.gt, StartingLife(You()));
      case 'your life total is at least 10 greater than your starting life total':
        return const AmountCompare(LifeTotal(You()), Cmp.ge, Plus(StartingLife(You()), Fixed(10)));
    }
    var m = rx(t, r'there are (seven|\w+) or more cards in your graveyard');
    if (m != null) return CountCondition(const CardsIn(ZoneKind.graveyard, You(), Filter(card: true, zone: ZoneKind.graveyard)), Cmp.ge, numberWord(m[1])!);
    m = rx(t, r'you control (a|an|another|two or more|three or more|four or more|five or more|seven or more|no) (.+)');
    if (m != null) {
      var f = parseFilterCore(m[2]);
      if (f == null) return null;
      if (m[1] == 'another') f = f.copyWith(other: true);
      final n = switch (m[1]) { 'a' || 'an' || 'another' => 1, 'no' => 0, _ => numberWord(m[1].split(' ').first)! };
      return CountCondition(CountOf(All(f.copyWith(controller: Who.you))), m[1] == 'no' ? Cmp.eq : Cmp.ge, n);
    }
    m = rx(t, r"it (was|is) (?:a|an) (.+)");
    if (m != null && ctx.lastRemembered != null) {
      final f = parseFilterCore(m[2]);
      if (f == null) return null;
      return RememberedAny(ctx.lastRemembered!, f);
    }
    m = rx(t, r"(?:it|~) (wasn't|was not|isn't|is not|was|is) (?:a|an) (.+)");
    if (m != null) {
      final f = parseFilterCore(m[2]);
      if (f == null) return null;
      final neg = m[1].contains("n't") || m[1].contains('not');
      final c = ObjMatches(const SelfRef(), f);
      return neg ? Not(c) : c;
    }
    m = rx(t, r'it had (?:a|an|one or more) ([a-z+/0-9-]+) counters? on it');
    if (m != null) return ObjMatches(const SelfRef(), Filter(withCounter: m[1]));
    m = rx(t, r'~ has (three|two|four|five|\w+) or more ([a-z+/0-9-]+) counters on it');
    if (m != null) return CountCondition(CountersOn(m[2], const SelfRef()), Cmp.ge, numberWord(m[1])!);
    m = rx(t, r'at least one (.+?) was exiled this way');
    if (m != null) {
      final f = parseFilterCore(m[1]);
      if (f == null || ctx.lastRemembered == null) return null;
      return RememberedAny(ctx.lastRemembered!, f);
    }
    m = rx(t, r'(.+) and (.+)');
    if (m != null) {
      final a = condition(m[1], ctx), b = condition(m[2], ctx);
      if (a != null && b != null) return AllOf([a, b]);
    }
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Statics (CR 604) and replacement effects (CR 614)
  // -------------------------------------------------------------------------------------------

  /// Statics that concern casting the card itself.
  List<Ability>? _spellStatic(String p, String raw) {
    final t = p.endsWith('.') ? p.substring(0, p.length - 1) : p;
    if (t == "this spell can't be countered" || t == "~ can't be countered") return [KeywordAbility(raw, Kw.cantBeCountered)];
    var m = rx(t, r'as an additional cost to cast ~, (.+)');
    if (m != null) {
      final orPay = rx(m[1], r'(.+) or pay ((?:\{[^}]+\})+)');
      if (orPay != null) {
        final part = parseCostPart(orPay[1]);
        if (part == null) return null;
        return [
          CastOptionAbility(raw, CastOption(CastKind.additional, extra: [part], label: _cap(orPay[1]))),
          CastOptionAbility(raw, CastOption(CastKind.additional, cost: ManaCost.parse(orPay[2].toUpperCase()), label: 'Pay ${orPay[2].toUpperCase()}')),
        ];
      }
      final part = parseCostPart(m[1]);
      if (part == null) return null;
      return [CastOptionAbility(raw, CastOption(CastKind.additional, extra: [part], label: _cap(m[1])))];
    }
    m = rx(t, r"you may pay ((?:\{[^}]+\})+) rather than pay ~'s mana cost(?: if (.+))?");
    if (m != null) {
      Condition? c;
      if (m[2].isNotEmpty) {
        c = _castCondition(m[2]);
        if (c == null) return null;
      }
      return [CastOptionAbility(raw, CastOption(CastKind.alternative, cost: ManaCost.parse(m[1].toUpperCase()), condition: c, label: 'Pay ${m[1].toUpperCase()}'))];
    }
    m = rx(t, r'~ costs \{(\d+)\} less to cast if (.+)');
    if (m != null) {
      final n = int.parse(m[1]);
      final tg = rx(m[2], r'it targets (?:a|an) (.+)');
      if (tg != null) {
        final f = parseFilterCore(tg[1]);
        if (f == null) return null;
        return [RuleAbility(raw, CostChange(Filter.any, -n, selfOnly: true, targetsFilter: f), zone: ZoneKind.hand)];
      }
      final c = _castCondition(m[2]);
      if (c == null) return null;
      return [RuleAbility(raw, CostChange(Filter.any, -n, selfOnly: true, condition: c), zone: ZoneKind.hand)];
    }
    m = rx(t, r'~ costs \{(\d+)\} less to cast for each (.+)');
    if (m != null) {
      final a = countPhrase(m[2], BodyCtx());
      if (a == null) return null;
      return [RuleAbility(raw, CostChange(Filter.any, 0, amount: int.parse(m[1]) == 1 ? a : Times(a, int.parse(m[1])), selfOnly: true), zone: ZoneKind.hand)];
    }
    m = rx(t, r'~ costs \{x\} less to cast, where x is (.+)');
    if (m != null) {
      final a = parseQuantity(m[1], BodyCtx());
      if (a == null) return null;
      return [RuleAbility(raw, CostChange(Filter.any, 0, amount: a, selfOnly: true), zone: ZoneKind.hand)];
    }
    m = rx(t, r'you may cast ~ from your graveyard by (.+) in addition to paying its other costs');
    if (m != null) {
      final part = parseCostPart(m[1]);
      if (part == null) return null;
      return [CastOptionAbility(raw, CastOption(CastKind.fromGraveyard, extra: [part], zone: ZoneKind.graveyard, label: 'Cast from graveyard'))];
    }
    return null;
  }

  Condition? _castCondition(String s) {
    final ctx = BodyCtx();
    final m = rx(s, r'there are (\w+) or more creatures on the battlefield');
    if (m != null) return CountCondition(const CountOf(All(Filter.creature)), Cmp.ge, numberWord(m[1])!);
    return condition(s, ctx);
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  List<Ability>? _static(String p, String raw) {
    var t = p.endsWith('.') ? p.substring(0, p.length - 1) : p;
    final ctx = BodyCtx();

    // Replacement: enters tapped / with counters.
    if (t == '~ enters tapped') return [ReplacementAbility(raw, const EntersTapped(One(SelfRef())))];
    var m = rx(t, r'(.+) enter tapped');
    if (m != null) {
      final g = parseGroup(m[1], ctx);
      if (g != null) return [ReplacementAbility(raw, EntersTapped(g))];
    }
    final lead = rx(t, r"if (.+?), ~ enters with (.+)");
    if (lead != null && !t.startsWith('if ~ was kicked')) {
      final c = condition(lead[1], ctx);
      final r = c == null ? null : _static('~ enters with ${lead[2]}', raw);
      final rep = r != null && r.length == 1 && r.first is ReplacementAbility ? (r.first as ReplacementAbility).replacement : null;
      if (rep is EntersWithCounters && rep.condition == null) return [ReplacementAbility(raw, EntersWithCounters(rep.set, rep.kind, rep.amount, condition: c))];
    }
    m = rx(t, r"(?:if ~ was kicked, it|~) enters with (a|an|one|two|three|four|five|six|seven|eight|x|\d+) ([a-z+/0-9-]+) counters? on it(?: if (.+))?");
    if (m != null) {
      Condition? c = t.startsWith('if ~ was kicked') ? const Kicked() : null;
      if (m[3].isNotEmpty) {
        final c2 = condition(m[3], ctx);
        if (c2 == null) return null;
        c = c2;
      }
      return [ReplacementAbility(raw, EntersWithCounters(const One(SelfRef()), m[2], parseAmount(m[1])!, condition: c))];
    }
    m = rx(t, r'~ enters with (\w+) ([a-z+/0-9-]+) counters on it if you cast it');
    if (m != null) return [ReplacementAbility(raw, EntersWithCounters(const One(SelfRef()), m[2], parseAmount(m[1])!, condition: const WasCast()))];
    m = rx(t, r'as ~ enters, choose a (color|creature type)');
    if (m != null) return [ReplacementAbility(raw, ChooseOnEnter(m[1]))];
    m = rx(t, r'as ~ enters, choose a (creature type)\. ~ enters with a ([a-z]+) counter on it for each (.+)');
    if (m != null) return null;
    m = rx(t, r'each other (.+?) enters with an additional (\+1/\+1) counter on it for each (.+?) you already control');
    if (m != null) {
      final f = parseFilterCore(m[1]);
      final a = parseFilterCore(m[3]);
      if (f == null || a == null) return null;
      return [ReplacementAbility(raw, ExtraCountersOnEnter(All(f.copyWith(other: true)), m[2], CountOf(All(a.copyWith(controller: Who.you, other: true)))))];
    }

    // Rules modifications.
    switch (t) {
      case 'you have no maximum hand size':
        return [RuleAbility(raw, const NoMaxHandSize())];
      case 'you may play an additional land on each of your turns':
        return [RuleAbility(raw, const ExtraLandPerTurn(1))];
      case 'you may cast spells as though they had flash':
        return [RuleAbility(raw, const CastAsThoughFlash(Filter.any))];
      case "you can't lose the game and your opponents can't win the game":
        return [RuleAbility(raw, const CantLoseGame()), RuleAbility(raw, const OpponentsCantWin())];
      case 'you have hexproof':
        return [RuleAbility(raw, const PlayerHexproof())];
      case 'you may cast spells from your hand without paying their mana costs':
        return [RuleAbility(raw, const CastWithoutPaying(Filter.any))];
      case 'a deck can have any number of cards named ~':
        return [InfoAbility(raw, anyNumber: true)];
      case 'if ~ is in your opening hand, you may begin the game with it on the battlefield':
        return [InfoAbility(raw, openingHandBattlefield: true)];
      case "~ doesn't untap during your untap step":
        return [KeywordAbility(raw, Kw.doesntUntap)];
      case "~ can't block":
        return [KeywordAbility(raw, Kw.cantBlock)];
      case "~ can't attack":
        return [KeywordAbility(raw, Kw.cantAttack)];
      case "~ can't attack or block":
        return [KeywordAbility(raw, Kw.cantAttackOrBlock)];
      case "~ can't be blocked":
        return [KeywordAbility(raw, Kw.unblockable)];
      case '~ attacks each combat if able':
        return [KeywordAbility(raw, Kw.attacksEachCombat)];
    }
    m = rx(t, r"~ can't be blocked by (.+)");
    if (m != null) {
      final f = parseFilterCore(m[1]);
      if (f == null) return null;
      return [KeywordAbility(raw, Kw("can't be blocked by", filter: f))];
    }
    m = rx(t, r'~ can\x27t be blocked except by (two|three) or more creatures');
    if (m != null) return [KeywordAbility(raw, Kw.menace)];
    m = rx(t, r'(instant and sorcery|creature|noncreature|artifact|[a-z ]+?) spells you cast cost \{(\d+)\} less to cast');
    if (m != null) {
      final f = parseFilterCore('${m[1]} spells');
      if (f == null) return null;
      return [RuleAbility(raw, CostChange(f, -int.parse(m[2])))];
    }
    m = rx(t, r'(.+?) spells your opponents cast cost \{(\d+)\} more to cast');
    if (m != null) {
      final f = parseFilterCore('${m[1]} spells');
      if (f == null) return null;
      return [RuleAbility(raw, CostChange(f, int.parse(m[2]), who: Who.opponent))];
    }
    m = rx(t, r'prevent all (combat |noncombat |)damage that would be dealt to (.+)');
    if (m != null) {
      final g = m[2] == 'you' ? null : parseGroup(m[2], ctx);
      if (g == null && m[2] != 'you') return null;
      return [ReplacementAbility(raw, PreventDamage(g ?? const All(Filter.any), combat: m[1].isEmpty ? null : m[1] == 'combat ', toYou: m[2] == 'you'))];
    }
    if (t == 'if a source you control would deal damage to an opponent or a permanent an opponent controls, it deals double that damage instead') {
      return [ReplacementAbility(raw, const DoubleDamage())];
    }
    if (t == 'if an effect would create one or more tokens under your control, it creates twice that many of those tokens instead') {
      return [ReplacementAbility(raw, const DoubleTokens())];
    }
    if (t == 'if an effect would put one or more counters on a permanent you control, it puts twice that many of those counters on that permanent instead') {
      return [ReplacementAbility(raw, const DoubleCountersReplacement())];
    }
    m = rx(t, r'if ~ would be put into a graveyard from anywhere, reveal ~ and shuffle it into its owner\x27s library instead');
    if (m != null) return [ReplacementAbility(raw, const InsteadOfGraveyard(One(SelfRef()), ZoneKind.library, shuffleIntoLibrary: true))];
    m = rx(t, r"~'s power and toughness are each equal to (.+)");
    if (m != null) {
      final a = parseQuantity(m[1], ctx);
      if (a == null) return null;
      return [StaticAbility(raw, const One(SelfRef()), [SetPT(a, a, cda: true)], zone: ZoneKind.anywhere)];
    }
    m = rx(t, r"~'s power is equal to (.+)");
    if (m != null) {
      final a = parseQuantity(m[1], ctx);
      if (a == null) return null;
      return [StaticAbility(raw, const One(SelfRef()), [SetPT(a, null, cda: true)], zone: ZoneKind.anywhere)];
    }

    // Two sentences are two statics ("Elenda gets +1/+1 and has menace. Elenda gets ...").
    final sents = sentences(t);
    if (sents.length > 1) {
      final out = <Ability>[];
      for (final s in sents) {
        final r = _static(s, raw);
        if (r == null) return null;
        out.addAll(r);
      }
      return out;
    }
    // Continuous effects: "<group> get +1/+1 [and have ...]", with "as long as" / "during your turn".
    Condition? cond;
    final asLong = RegExp(r'^as long as (.+?), (.+)$').firstMatch(t);
    final asLong2 = RegExp(r'^(.+?) as long as (.+)$').firstMatch(t);
    if (asLong != null) {
      cond = condition(asLong.group(1)!, ctx);
      if (cond == null) return null;
      t = asLong.group(2)!;
    } else if (asLong2 != null) {
      cond = condition(asLong2.group(2)!, ctx);
      if (cond == null) return null;
      t = asLong2.group(1)!;
    }
    if (t.startsWith('during your turn, ')) {
      cond = allOf([cond, const YourTurn()]);
      t = t.substring(18);
    }
    final cont = _continuous(t, ctx);
    if (cont != null) {
      return [StaticAbility(raw, cont.$1, cont.$2, condition: cond)];
    }
    return null;
  }

  /// "<group> get(s) +N/+N [and has/have <kws>]", "<group> has/have <kws>", "~ is a <type>".
  (ObjSet, List<Mod>)? _continuous(String t, BodyCtx ctx) {
    final m = RegExp(r'^(.+?) (gets|get|has|have|is|are|loses|lose) (.+)$').firstMatch(t);
    if (m == null) return null;
    final subj = m.group(1)!;
    final set = parseObjects(subj, ctx);
    if (set == null) return null;
    final mods = _mods('${m.group(2)} ${m.group(3)}', ctx, static: true);
    if (mods == null) return null;
    return (set, mods);
  }

  /// Predicate of a continuous effect: "get +2/+0 and have flying", "has double strike",
  /// "gets +1/+1 for each Forest you control", "is a Knight in addition to its other types",
  /// "loses all abilities and is a green and white Citizen creature with base power and toughness
  /// 1/1 named ...", "gain trample and get +X/+X".
  List<Mod>? _mods(String s, BodyCtx ctx, {bool static = false}) {
    var t = s.trim();
    final out = <Mod>[];
    // Split on " and " between predicates.
    final parts = _splitPredicates(t);
    for (final part in parts) {
      final r = _mod(part.trim(), ctx, static: static);
      if (r == null) return null;
      out.addAll(r);
    }
    return out;
  }

  List<String> _splitPredicates(String t) {
    final verbs = RegExp(r' and (?=(?:gets?|gains?|has|have|is|are|loses?|can\x27t|becomes?) )');
    return t.split(verbs);
  }

  List<Mod>? _mod(String p, BodyCtx ctx, {bool static = false}) {
    // "Loses flying", "loses flying and first strike".
    final lose = rx(p, r'loses? ((?:[a-z ]+)(?:, [a-z ]+)*(?:,? and [a-z ]+)?)');
    if (lose != null && !p.startsWith('loses all') && !p.startsWith('lose all')) {
      final kws = _kwList(lose[1]);
      if (kws != null) return [for (final k in kws) LoseKw(k)];
    }
    var m = rx(p, r'(?:gets?|has|have) (?:an additional )?([+-]\d+|[+-]x)/([+-]\d+|[+-]x)(?: for each (.+))?(?:, where x is (.+))?');
    if (m != null) {
      Amount pa = _signed(m[1]), ta = _signed(m[2]);
      if (m[3].isNotEmpty) {
        final c = countPhrase(m[3], ctx);
        if (c == null) return null;
        pa = _scale(pa, c);
        ta = _scale(ta, c);
      }
      if (m[4].isNotEmpty) {
        final q = parseQuantity(m[4], ctx);
        if (q == null) return null;
        pa = pa is XValue ? q : pa;
        ta = ta is XValue ? q : ta;
      }
      return [ModPT(pa, ta)];
    }
    m = rx(p, r'(?:gets|get|has|have|gains?) (?:\+1/\+1 and )?((?:[a-z ]+)(?:, [a-z ]+)*(?:,? and [a-z ]+)?)');
    if (m != null) {
      final kws = _kwList(m[1]);
      if (kws != null) return [for (final k in kws) AddKw(k)];
    }
    // Crew: a Vehicle "becomes an artifact creature" with its printed power and toughness.
    if (rx(p, r'becomes? an artifact creature') != null) return const [TypeMod(types: {CardType.artifact, CardType.creature})];
    m = rx(p, r'(?:has|have|gains?) "(.+)"');
    if (m != null) {
      final a = OracleParser.parseGranted(m[1].replaceAll('~', 'this creature'));
      if (a == null) return null;
      return [AddAbility(a)];
    }
    m = rx(p, r"(?:is|are) (?:a|an) (.+?) in addition to (?:its|their) other (?:creature )?types");
    if (m != null) {
      final subs = <String>[];
      final types = <CardType>{};
      for (final w in m[1].split(' ')) {
        final st = subtypeWords[w];
        final ty = CardType.parse(w);
        if (ty != null) {
          types.add(ty);
        } else if (st != null) {
          subs.add(st);
        } else {
          return null;
        }
      }
      return [TypeMod(types: types, subtypes: subs)];
    }
    if (p == "can't block" || p == "can't block this turn") return [const AddKw(Kw.cantBlock)];
    if (p == "can't be blocked" || p == "can't be blocked this turn") return [const AddKw(Kw.unblockable)];
    if (p == "can't attack or block") return [const AddKw(Kw.cantAttackOrBlock)];
    if (p == 'loses all abilities') return [const LoseAllAbilities()];
    m = rx(p, r'is a colorless land with "\{t\}: add \{c\}" and loses all other card types and abilities');
    if (m != null) {
      return [
        const TypeMod(types: {CardType.land}, replaceTypes: true, replaceSubtypes: true),
        const ColorMod({}),
        const LoseAllAbilities(),
        const AddAbility(ManaAbility('{T}: Add {C}.', Cost(tap: true), ManaProduce(fixed: [ManaType.C]))),
      ];
    }
    m = rx(p, r'is a (.+?) creature with base power and toughness (\d+)/(\d+)(?: named (.+))?');
    if (m != null) {
      final words = m[1].split(' ');
      final colors = <ManaColor>{};
      final subs = <String>[];
      for (final w in words) {
        final c = ManaColor.fromWord(w);
        if (c != null) {
          colors.add(c);
        } else if (w == 'and') {
          continue;
        } else if (subtypeWords.containsKey(w)) {
          subs.add(subtypeWords[w]!);
        } else {
          return null;
        }
      }
      return [
        TypeMod(types: const {CardType.creature}, subtypes: subs, replaceTypes: true, replaceSubtypes: true),
        ColorMod(colors),
        SetPT(Fixed(int.parse(m[2])), Fixed(int.parse(m[3]))),
        if (m[4].isNotEmpty) SetName(_orig(m[4])),
      ];
    }
    m = rx(p, r'(?:has|have) base power and toughness (\d+)/(\d+)');
    if (m != null) return [SetPT(Fixed(int.parse(m[1])), Fixed(int.parse(m[2])))];
    return null;
  }

  Amount _signed(String s) {
    final neg = s.startsWith('-');
    final v = s.substring(1);
    if (v == 'x') return neg ? const Times(XValue(), -1) : const XValue();
    final n = int.parse(v);
    return Fixed(neg ? -n : n);
  }

  Amount _scale(Amount per, Amount count) {
    if (per is Fixed) return per.n == 1 ? count : Times(count, per.n);
    return count;
  }

  /// "flying", "flying and first strike", "vigilance, trample, and indestructible", "hexproof".
  List<Kw>? _kwList(String s) {
    final parts = s.replaceAll(', and ', ', ').replaceAll(' and ', ', ').split(', ');
    final out = <Kw>[];
    for (final p in parts) {
      final ab = parseKeyword(p.trim(), p.trim());
      if (ab == null || ab.isEmpty || ab.first is! KeywordAbility) return null;
      out.add((ab.first as KeywordAbility).kw);
    }
    return out;
  }

  // -------------------------------------------------------------------------------------------
  // Bodies: targets + effects
  // -------------------------------------------------------------------------------------------

  Body? _bodyOf(String text, BodyCtx ctx) {
    final eff = effects(text, ctx);
    if (eff == null) return null;
    return Body(targets: List.of(ctx.targets), effect: eff);
  }

  /// "choose one —\n• a\n• b" → a modal body.
  Body? _modal(String text, BodyCtx ctx) {
    // Confluences: "choose three. you may choose the same mode more than once." Each mode is
    // offered as many times as it may be chosen.
    final rep = RegExp(r'^choose (two|three|four)\. you may choose the same mode more than once\.?\n(.+)$', dotAll: true).firstMatch(text.trim());
    if (rep != null) {
      final n = numberWord(rep.group(1)!)!;
      final inner = _modal('choose one —\n${rep.group(2)!}', ctx);
      if (inner == null) return null;
      return Body(
        modes: [for (final b in inner.modes) for (var i = 0; i < n; i++) b],
        minModes: n,
        maxModes: n,
        modeLabels: [for (final l in inner.modeLabels) for (var i = 0; i < n; i++) l],
      );
    }
    final m = RegExp(r'^(?:(.+?)[,.] )?choose (one|two|one or both|one or more|up to one|any number) —\n?(.+)$', dotAll: true).firstMatch(text.trim());
    if (m == null || m.group(1) != null) return null;
    final bullets = m.group(3)!.split(RegExp(r'\n?• ')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final modes = <Body>[];
    for (final b in bullets) {
      final c = BodyCtx(trigger: ctx.trigger)
        ..eventObj = ctx.eventObj
        ..it = ctx.it
        ..thatPlayer = ctx.thatPlayer;
      final body = _bodyOf(b, c);
      if (body == null) return null;
      modes.add(body);
    }
    final (min, max) = switch (m.group(2)!) {
      'one' => (1, 1),
      'two' => (2, 2),
      'one or both' => (1, 2),
      'one or more' => (1, modes.length),
      'up to one' => (0, 1),
      _ => (0, modes.length),
    };
    return Body(modes: modes, minModes: min, maxModes: max, modeLabels: bullets);
  }

  /// A sequence of sentences → one effect.
  Effect? effects(String text, BodyCtx ctx) {
    final ss = sentences(text);
    final steps = <Effect>[];
    for (var i = 0; i < ss.length; i++) {
      var s = ss[i];
      // Effects spanning sentences ("look at the top four cards …. put the rest …").
      final multi = libraryHandMulti(ss, i, ctx);
      if (multi != null) {
        steps.add(multi.$1);
        i += multi.$2 - 1;
        continue;
      }
      // "Destroy target creature. It can't be regenerated."
      if (isCantRegenerate(s) && steps.isNotEmpty) {
        final e = noRegen(steps.last);
        if (e == null) return null;
        steps[steps.length - 1] = e;
        continue;
      }
      // "If you do, X."
      var m = RegExp(r'^if you do, (.+)$').firstMatch(s);
      if (m != null && steps.isNotEmpty) {
        final e = sentence(m.group(1)!, ctx);
        if (e == null) return null;
        steps.add(If(const DidIt(), e));
        continue;
      }
      // "If <cond>, X instead."
      m = RegExp(r'^if (.+?), (.+) instead$').firstMatch(s);
      if (m != null && steps.isNotEmpty) {
        final ctx2 = ctx;
        final c = condition(m.group(1)!, ctx2);
        if (c == null) return null;
        final prev = steps.removeLast();
        final inner = m.group(2)!;
        Effect? e;
        // "it deals 4 damage instead": same recipient, new amount.
        final dm = rx(inner, r'(?:it|~) deals (\w+) damage');
        if (dm != null) {
          final a = parseAmount(dm[1]);
          if (a == null) return null;
          e = _withAmount(prev, a);
        } else if (inner.startsWith('instead ')) {
          return null;
        } else {
          if (c is Kicked) {
            _markTargets(ctx, const Not(Kicked()));
            ctx.targetWhen = const Kicked();
          }
          e = sentence(inner, ctx);
          ctx.targetWhen = null;
        }
        if (e == null) return null;
        steps.add(If(c, e, prev));
        continue;
      }
      m = RegExp(r'^if (.+?), instead (.+)$').firstMatch(s);
      if (m != null && steps.isNotEmpty) {
        final c = condition(m.group(1)!, ctx);
        if (c == null) return null;
        final prev = steps.removeLast();
        if (c is Kicked) {
          _markTargets(ctx, const Not(Kicked()));
          ctx.targetWhen = const Kicked();
        }
        final e = sentence(m.group(2)!, ctx);
        ctx.targetWhen = null;
        if (e == null) return null;
        steps.add(If(c, e, prev));
        continue;
      }
      // "Counter target spell. If that spell is countered this way, exile it instead of putting it
      // into its owner's graveyard."
      if (s == "if that spell is countered this way, exile it instead of putting it into its owner's graveyard" && steps.isNotEmpty) {
        final last = steps.last;
        if (last is CounterSpell) {
          steps[steps.length - 1] = CounterSpell(last.obj, exileInstead: true);
          continue;
        }
        if (last is Unless && last.effect is CounterSpell) {
          steps[steps.length - 1] = Unless(CounterSpell((last.effect as CounterSpell).obj, exileInstead: true), last.payer, mana: last.mana, life: last.life, alternative: last.alternative);
          continue;
        }
      }
      // "Create a 1/1 Eldrazi Scion creature token. It has 'Sacrifice ~: Add {C}.'"
      m = RegExp(r'^(?:it has|they have|they each have) "(.+)"$').firstMatch(s);
      if (m != null && steps.isNotEmpty && steps.last is CreateToken) {
        final a = OracleParser.parseGranted(m.group(1)!);
        if (a == null) return null;
        final c = steps.removeLast() as CreateToken;
        final sp = c.spec;
        steps.add(CreateToken(
            TokenSpec(name: sp.name, power: sp.power, toughness: sp.toughness, colors: sp.colors, types: sp.types, subtypes: sp.subtypes, supertypes: sp.supertypes, keywords: sp.keywords, abilities: [...sp.abilities, a], text: [if (sp.text.isNotEmpty) sp.text, a.text].join('\n')),
            c.amount,
            controller: c.controller,
            tapped: c.tapped,
            attacking: c.attacking,
            remember: c.remember));
        continue;
      }
      m = RegExp(r'^otherwise, (.+)$').firstMatch(s);
      if (m != null && steps.isNotEmpty && steps.last is If) {
        final prev = steps.removeLast() as If;
        final e = sentence(m.group(1)!, ctx);
        if (e == null) return null;
        steps.add(If(prev.cond, prev.then, e));
        continue;
      }
      if (s.startsWith('then ')) s = s.substring(5);
      final e = sentence(s, ctx);
      if (e == null) {
        OracleParser.diag?.add('sentence: $s');
        return null;
      }
      steps.add(e);
    }
    if (steps.isEmpty) return null;
    return steps.length == 1 ? steps.first : Seq(steps);
  }

  void _markTargets(BodyCtx ctx, Condition when) {
    for (var i = 0; i < ctx.targets.length; i++) {
      final t = ctx.targets[i];
      if (t.when == null) {
        ctx.targets[i] = TargetSpec(t.kind, filter: t.filter, who: t.who, min: t.min, max: t.max, differentControllers: t.differentControllers, sameZoneOwner: t.sameZoneOwner, distinctFrom: t.distinctFrom, when: when);
      }
    }
  }

  Effect? _withAmount(Effect e, Amount a) => switch (e) {
        DealDamage() => DealDamage(a, e.to, source: e.source, toPlayers: e.toPlayers, divided: e.divided),
        DamageTarget() => DamageTarget(a, e.index, source: e.source, divided: e.divided),
        _ => null,
      };

  /// One sentence: conditionals, "you may", durations, then clauses joined by "and"/"then".
  Effect? sentence(String s, BodyCtx ctx) {
    var t = s.trim();
    if (t.endsWith('.')) t = t.substring(0, t.length - 1);
    // "Until end of turn, X"
    var m = RegExp(r'^until end of turn, (.+)$').firstMatch(t);
    if (m != null) return _clauses(m.group(1)!, ctx, duration: EffectDuration.endOfTurn);
    m = RegExp(r'^you may (.+)$').firstMatch(t);
    if (m != null && !t.startsWith('you may play') && !t.startsWith('you may cast')) {
      final e = _clauses(m.group(1)!, ctx, mayPrefix: true);
      if (e == null) return null;
      return May(e);
    }
    m = RegExp(r'^if (.+?), (.+)$').firstMatch(t);
    if (m != null) {
      final c = condition(m.group(1)!, ctx) ?? _ifCondition(m.group(1)!, ctx);
      if (c != null) {
        final e = _clauses(m.group(2)!, ctx);
        if (e == null) return null;
        return If(c, e);
      }
    }
    m = RegExp(r'^for each (.+?), (.+)$').firstMatch(t);
    if (m != null) {
      final a = countPhrase(m.group(1)!, ctx);
      if (a != null) {
        final inner = m.group(2)!;
        final tok = rx(inner, r'create (?:a|an) (.+)');
        if (tok != null) return _createTokens(tok[1], a, ctx);
      }
    }
    return _clauses(t, ctx);
  }

  /// "If target player has exactly 10 life" and other target-bearing conditions.
  Condition? _ifCondition(String s, BodyCtx ctx) {
    final m = rx(s, r'(target player|target opponent) has exactly (\d+) life');
    if (m != null) {
      final p = parsePlayer(m[1], ctx);
      if (p == null) return null;
      return AmountCompare(LifeTotal(p), Cmp.eq, Fixed(int.parse(m[2])));
    }
    return null;
  }

  /// Clauses joined by ", then", " and", ", and": try the whole thing first, then split.
  Effect? _clauses(String s, BodyCtx ctx, {EffectDuration? duration, bool mayPrefix = false}) {
    final t = s.trim();
    final mark = ctx.mark();
    final whole = clause(t, ctx, duration: duration);
    if (whole != null) return whole;
    ctx.reset(mark);
    for (final sep in const [', then ', ' and then ', ', and ', ' and ', ', ']) {
      var idx = indexOutsideQuotes(t, sep);
      while (idx > 0) {
        final left = t.substring(0, idx);
        var right = t.substring(idx + sep.length);
        final m2 = ctx.mark();
        final a = clause(left, ctx, duration: duration);
        if (a != null) {
          if (mayPrefix && right.startsWith('you ')) right = right;
          final b = _clauses(right, ctx, duration: duration);
          if (b != null) return Seq([a, b]);
        }
        ctx.reset(m2);
        idx = indexOutsideQuotes(t, sep, idx + 1);
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------------------------
  // Clauses (one action)
  // -------------------------------------------------------------------------------------------

  Effect? clause(String c, BodyCtx ctx, {EffectDuration? duration}) {
    final t = c.trim();
    final mark = ctx.mark();
    final r = _clause(t, ctx, duration);
    if (r == null) ctx.reset(mark);
    return r;
  }

  Effect? _clause(String t, BodyCtx ctx, EffectDuration? duration) {
    // "Return it to the battlefield … with a -1/-1 counter on it."
    final withC = rx(t, r'(return .+ to the battlefield.*?) with (a|an|one|two|three) ([a-z+/0-9-]+) counters? on (?:it|them)');
    if (withC != null) {
      final e = _clause(withC[1], ctx, duration);
      if (e is! MoveTo) return null;
      return MoveTo(e.set, e.zone,
          tapped: e.tapped,
          underYourControl: e.underYourControl,
          counters: {...e.counters, withC[3]: numberWord(withC[2]) ?? 1},
          remember: e.remember,
          attacking: e.attacking,
          extraTypes: e.extraTypes);
    }
    // "…, then draws seven cards": a third-person verb with no subject keeps the last subject.
    final carried = ctx.lastSubject;
    if (carried != null && RegExp(r'^(draws|discards|loses|gains|mills|sacrifices|creates|reveals|shuffles|puts|returns) ').hasMatch(t)) {
      final who = _subjectText(carried);
      if (who != null) {
        final r = _clause2('$who $t', ctx, duration);
        if (r != null) return r;
      }
    }
    final r = _clause2(t, ctx, duration);
    if (r != null) _noteSubject(t, ctx);
    return r;
  }

  String? _subjectText(PlayerRef p) => switch (p) {
        EachPlayer() => 'each player',
        EachOpponent() => 'each opponent',
        You() => 'you',
        TargetPlayer() => 'that player',
        _ => null,
      };

  void _noteSubject(String t, BodyCtx ctx) {
    for (final (prefix, ref) in const [('each player ', EachPlayer()), ('each opponent ', EachOpponent()), ('you ', You())]) {
      if (t.startsWith(prefix)) {
        ctx.lastSubject = ref;
        break;
      }
    }
    // "Target player draws two cards and loses 2 life": "that player" carries on.
    if ((t.startsWith('target player ') || t.startsWith('target opponent ')) && ctx.thatPlayer is TargetPlayer) ctx.lastSubject = ctx.thatPlayer;
    final v = RegExp(r'\b(sacrifices?|destroy|exile|draw)\b').firstMatch(t);
    ctx.lastVerb = v == null ? null : (v.group(1)!.startsWith('sacrifice') ? 'sacrifice' : v.group(1));
  }

  Effect? _clause2(String t, BodyCtx ctx, EffectDuration? duration) {
    List<String>? m;
    final lh = libraryHandClause(t, ctx);
    if (lh != null) return lh;
    final more = moreClause(t, ctx);
    if (more != null) return more;

    // --- Damage -------------------------------------------------------------------------------
    m = rx(t, r'(~|it|that creature|target creature you control|(?:another )?target creature) deals (\w+|damage equal to .+?) damage to (.+)');
    m ??= rx(t, r'(~|it|that creature|target creature you control|(?:another )?target creature) deals (damage equal to (?:its|~\x27s) power) to (.+)');
    if (m != null) {
      final src = m[1] == '~' ? const SelfRef() : (m[1] == 'it' || m[1] == 'that creature' ? ctx.it ?? const SelfRef() : null);
      ObjRef source;
      if (src != null) {
        source = src;
      } else {
        final s = parseObjects(m[1], ctx, allowGroup: false);
        if (s is! One) return null;
        source = s.ref;
      }
      Amount? amount;
      if (m[2].startsWith('damage equal to ')) {
        final q = m[2].substring(16);
        amount = q == "its power" || q == "~'s power" ? StatOf(Stat.power, source) : parseQuantity(q, ctx);
      } else {
        amount = parseAmount(m[2]);
      }
      if (amount == null) return null;
      return _damageTo(m[3], amount, source, ctx);
    }
    m = rx(t, r'~ deals x damage to (.+?), where x is (.+)');
    if (m != null) {
      final q = parseQuantity(m[2], ctx);
      if (q == null) return null;
      return _damageTo(m[1], q, const SelfRef(), ctx);
    }
    m = rx(t, r'(.+?) fights (.+)');
    if (m != null) {
      final a = parseObjects(m[1], ctx, allowGroup: false);
      final b = parseObjects(m[2], ctx, allowGroup: false);
      if (a is! One || b is! One) return null;
      return Fight(a.ref, b.ref);
    }
    m = rx(t, r'have (it|~) fight (.+)');
    if (m != null) {
      final b = parseObjects(m[2], ctx, allowGroup: false);
      if (b is! One) return null;
      return Fight(const SelfRef(), b.ref);
    }

    // --- Cards and life -------------------------------------------------------------------------
    m = rx(t, r'(?:(.+?) )?draws? (a|an|one|two|three|four|five|x|\w+) cards?');
    if (m != null) {
      final who = m[1].isEmpty ? const You() : parsePlayer(m[1], ctx);
      final a = parseAmount(m[2]);
      if (who == null || a == null) return null;
      return Draw(a, who: who);
    }
    m = rx(t, r'(?:(.+?) )?draws? a card for each (.+)');
    if (m != null) {
      final who = m[1].isEmpty ? const You() : parsePlayer(m[1], ctx);
      final a = countPhrase(m[2], ctx);
      if (who == null || a == null) return null;
      return Draw(a, who: who);
    }
    m = rx(t, r'(?:(.+?) )?draws? cards equal to (.+)');
    if (m != null) {
      final who = m[1].isEmpty ? const You() : parsePlayer(m[1], ctx);
      final a = parseQuantity(m[2], ctx);
      if (who == null || a == null) return null;
      return Draw(a, who: who);
    }
    m = rx(t, r'(?:you )?draw that many cards');
    if (m != null) return const Draw(EventAmount());
    m = rx(t, r'(?:(.+?) )?discards? (a|an|one|two|three|x) cards?( at random)?');
    if (m != null) {
      final who = m[1].isEmpty ? const You() : parsePlayer(m[1], ctx);
      final a = parseAmount(m[2]);
      if (who == null || a == null) return null;
      return Discard(a, who: who, random: m[3].isNotEmpty);
    }
    m = rx(t, r'(?:(.+?) )?discards? (?:their|your) hand');
    if (m != null) {
      final who = m[1].isEmpty ? const You() : parsePlayer(m[1], ctx);
      if (who == null) return null;
      return Discard(const Fixed(0), who: who, hand: true);
    }
    m = rx(t, r'(.+?) reveals (?:their|his or her) hand\. you choose a (.+?) card from it\. that player discards that card');
    m ??= rx(t, r'(.+?) reveals (?:their|his or her) hand');
    if (m != null && m.length == 2) return null;
    m = rx(t, r'(?:(.+?) )?gains? (\w+) life');
    if (m != null) {
      final who = m[1].isEmpty ? const You() : parsePlayer(m[1], ctx);
      final a = parseAmount(m[2]);
      if (who == null || a == null) return null;
      return GainLife(a, who: who);
    }
    m = rx(t, r'(?:(.+?) )?gains? (?:that much life|life equal to (.+))');
    if (m != null) {
      final who = m[1].isEmpty ? const You() : parsePlayer(m[1], ctx);
      final a = m[2].isEmpty ? const EventAmount() : parseQuantity(m[2], ctx);
      if (who == null || a == null) return null;
      return GainLife(a, who: who);
    }
    m = rx(t, r'(?:(.+?) )?gains? (\w+) life for each (.+)');
    if (m != null) {
      final who = m[1].isEmpty ? const You() : parsePlayer(m[1], ctx);
      final per = parseAmount(m[2]);
      final c = countPhrase(m[3], ctx);
      if (who == null || per is! Fixed || c == null) return null;
      return GainLife(per.n == 1 ? c : Times(c, per.n), who: who);
    }
    m = rx(t, r'(.+?) loses? (that much|\w+) life');
    if (m != null) {
      final who = parsePlayer(m[1], ctx);
      final a = parseAmount(m[2]);
      if (who == null || a == null) return null;
      return LoseLife(a, who: who, slot: 'lifeLost');
    }
    m = rx(t, r'(.+?) loses? (?:x life, where x is|life equal to) (.+)');
    if (m != null) {
      final who = parsePlayer(m[1], ctx);
      final a = parseQuantity(m[2], ctx);
      if (who == null || a == null) return null;
      return LoseLife(a, who: who, slot: 'lifeLost');
    }
    m = rx(t, r'(?:(.+?) )?mills? (\w+) cards?');
    if (m != null) {
      final who = m[1].isEmpty ? const You() : parsePlayer(m[1], ctx);
      final a = parseAmount(m[2]);
      if (who == null || a == null) return null;
      return Mill(a, who: who);
    }
    m = rx(t, r'scry (\w+)');
    if (m != null) return Scry(parseAmount(m[1]) ?? const Fixed(1));
    m = rx(t, r'surveil (\w+)');
    if (m != null) return Surveil(parseAmount(m[1]) ?? const Fixed(1));

    // --- Tokens -------------------------------------------------------------------------------
    m = rx(t, r'(?:(.+?) )?creates? (a|an|one|two|three|four|five|six|x|\w+) (.+)');
    if (m != null && !m[3].startsWith('token that') && !m[3].startsWith('copy')) {
      final who = m[1].isEmpty ? const You() : parsePlayer(m[1], ctx);
      final a = parseAmount(m[2]);
      if (who != null && a != null) {
        final e = _createTokens(m[3], a, ctx, controller: who);
        if (e != null) return e;
      }
    }
    m = rx(t, r'create a number of (.+?) equal to (.+)');
    if (m != null) {
      final q = parseQuantity(m[2], ctx);
      if (q == null) return null;
      return _createTokens(m[1], q, ctx);
    }
    m = rx(t, r'create (x|that many) (.+?)(?:, where x is (.+))?');
    if (m != null) {
      Amount? q = m[1] == 'that many' ? const EventAmount() : (m[3].isEmpty ? const XValue() : parseQuantity(m[3], ctx));
      if (q == null) return null;
      return _createTokens(m[2], q, ctx);
    }
    m = rx(t, r'create (?:a|an) (tapped )?(.+?) for each (.+)');
    if (m != null) {
      final c = countPhrase(m[3], ctx);
      if (c == null) return null;
      return _createTokens('${m[1]}${m[2]}', c, ctx);
    }
    m = rx(t, r'create a token that\x27s a copy of (.+?)(?:, except (.+))?');
    if (m != null) {
      final o = parseObjects(m[1], ctx, allowGroup: false);
      if (o is! One) return null;
      var extra = <Mod>[];
      var sac = false;
      if (m[2].isNotEmpty) {
        final ex = _copyExcept(m[2], ctx);
        if (ex == null) return null;
        extra = ex.$1;
        sac = ex.$2;
      }
      ctx.it = const Remembered('created');
      return CreateCopy(o.ref, extraMods: extra, sacrificeAtEnd: sac);
    }

    // --- Counters -----------------------------------------------------------------------------
    m = rx(t, r'put (a|an|one|two|three|four|five|x|that many|\w+) ([a-z+/0-9-]+) counters? on (each of )?(.+)');
    if (m != null) {
      final a = parseAmount(m[1]);
      final set = parseObjects(m[4], ctx);
      if (a == null || set == null) return null;
      return PutCounters(set, m[2], a);
    }
    m = rx(t, r'double the number of (\+1/\+1|[a-z]+) counters on (.+)');
    if (m != null) {
      final set = parseObjects(m[2], ctx);
      if (set == null) return null;
      return DoubleCounters(set, kind: m[1]);
    }
    m = rx(t, r'double the number of each kind of counter on (.+)');
    if (m != null) {
      final set = parseObjects(m[1], ctx);
      if (set == null) return null;
      return DoubleCounters(set);
    }
    m = rx(t, r'remove (a|an|one|\w+) ([a-z+/0-9-]+) counters? from (.+)');
    if (m != null) {
      final a = parseAmount(m[1]);
      final set = parseObjects(m[3], ctx);
      if (a == null || set == null) return null;
      return RemoveCounters(set, m[2], a, slot: 'removed');
    }
    if (t == 'proliferate') return const Proliferate();

    // --- Zone changes ----------------------------------------------------------------------------
    m = rx(t, r'destroy (.+)');
    if (m != null) {
      final set = parseObjects(m[1], ctx);
      if (set == null) return null;
      return Destroy(set);
    }
    m = rx(t, r'exile (.+?) until ~ leaves the battlefield');
    if (m != null) {
      final set = parseObjects(m[1], ctx);
      if (set == null) return null;
      return MoveTo(set, ZoneKind.exile, untilSourceLeaves: true);
    }
    m = rx(t, r"exile (target player's|that player's|each opponent's|each player's|your) graveyard");
    if (m != null) {
      final who = switch (m[1]) {
        "target player's" => parsePlayer('target player', ctx),
        "that player's" => parsePlayer('that player', ctx),
        "each opponent's" => const EachOpponent(),
        "each player's" => const EachPlayer(),
        _ => const You(),
      };
      if (who == null) return null;
      return ForEachPlayer(who, const MoveTo(All(Filter(card: true, zone: ZoneKind.graveyard, owner: Who.that)), ZoneKind.exile));
    }
    if (t.startsWith('exile all other ') && ctx.it is Remembered) return null;
    m = rx(t, r'exile (.+?)(?: instead)?');
    if (m != null) {
      final set = parseObjects(m[1], ctx);
      if (set == null) return null;
      final slot = ctx.newSlot();
      ctx.lastRemembered = slot;
      return MoveTo(set, ZoneKind.exile, remember: slot);
    }
    m = rx(t, r"return (.+?) to (?:its|their) owners?'s? hands?");
    m ??= rx(t, r"return (.+?) to (?:its|their) owner's hand");
    if (m != null) {
      final set = parseObjects(m[1], ctx);
      if (set == null) return null;
      return MoveTo(set, ZoneKind.hand);
    }
    m = rx(t, r'return (.+?) (from (?:your|a|all) graveyards? )?to (?:your|its owner\x27s|their owner\x27s) hand');
    if (m != null) {
      final from = m[2].trim();
      final where = from.isEmpty ? '' : ' ${from.replaceFirst('from ', 'in ')}';
      final set = parseObjects('${m[1]}$where', ctx);
      if (set == null) return null;
      return MoveTo(set, ZoneKind.hand);
    }
    m = rx(t, r"return (.+?) to the battlefield( tapped)?(?: under (your|its owner's|their owner's|its owners') control)?( tapped)?(?: with (a|an|one|two|three) ([a-z+/0-9-]+) counters? on it)?");
    if (m != null) {
      final objText = m[1];
      ObjSet? set;
      if (objText == 'this card from your graveyard' || objText == '~ from your graveyard') {
        set = const One(SelfRef());
      } else if (objText == 'that card' || objText == 'it' || objText == 'the exiled card') {
        final r = ctx.it ?? ctx.eventObj;
        if (r == null) return null;
        set = One(r);
      } else {
        final cleaned = objText.replaceAll(' from your graveyard', ' in your graveyard').replaceAll(' from a graveyard', ' in a graveyard').replaceAll(' from all graveyards', ' in all graveyards');
        set = parseObjects(cleaned.contains(' in ') || cleaned.startsWith('target') || cleaned.startsWith('all') || cleaned.startsWith('up to') ? cleaned : cleaned, ctx);
      }
      if (set == null) return null;
      final counters = <String, int>{};
      if (m[5].isNotEmpty) counters[m[6]] = numberWord(m[5])!;
      return MoveTo(set, ZoneKind.battlefield, tapped: m[2].isNotEmpty || m[4].isNotEmpty, underYourControl: m[3] == 'your', counters: counters);
    }
    m = rx(t, r'put (.+?) onto the battlefield under your control');
    if (m != null) {
      final set = parseObjects(m[1].replaceAll(' from all graveyards', ' in all graveyards').replaceAll(' from your graveyard', ' in your graveyard'), ctx);
      if (set == null) return null;
      return MoveTo(set, ZoneKind.battlefield, underYourControl: true);
    }
    m = rx(t, r"(target creature's owner|its owner) puts it on their choice of the top or bottom of their library");
    if (m != null) {
      if (m[1].startsWith('target')) {
        final set = parseObjects('target creature', ctx);
        if (set == null) return null;
        return MoveTo(set, ZoneKind.library, ownerChoosesTopOrBottom: true);
      }
      final r = ctx.it;
      if (r == null) return null;
      return MoveTo(One(r), ZoneKind.library, ownerChoosesTopOrBottom: true);
    }
    m = rx(t, r"put (.+?) on (?:the )?(top|bottom) of (?:its owner's|their owners'|your) library");
    if (m != null) {
      final set = parseObjects(m[1], ctx);
      if (set == null) return null;
      return MoveTo(set, ZoneKind.library, libraryBottom: m[2] == 'bottom');
    }
    m = rx(t, r"shuffle (.+?) into (?:its owner's|their owners'|your) library");
    if (m != null) {
      final set = parseObjects(m[1], ctx);
      if (set == null) return null;
      return Seq([MoveTo(set, ZoneKind.library), const Shuffle()]);
    }
    m = rx(t, r'(.+?) sacrifices? (a|an|one|two|three|thirteen|x|\w+) (.+?)(?: of their choice)?');
    if (m != null) {
      final who = parsePlayer(m[1], ctx);
      final a = parseAmount(m[2]);
      final f = parseFilterCore(m[3]);
      if (who == null || a == null || f == null) return null;
      return Sacrifice(who, f, a);
    }
    m = rx(t, r'sacrifice (~|it|that creature|that token)');
    if (m != null) {
      final r = m[1] == '~' ? const SelfRef() : ctx.it;
      if (r == null) return null;
      return Sacrifice(const You(), Filter.any, const Fixed(1), self: r is SelfRef);
    }
    m = rx(t, r'sacrifice (a|an|another) (.+)');
    if (m != null) {
      var f = parseFilterCore(m[2]);
      if (f == null) return null;
      if (m[1] == 'another') f = f.copyWith(other: true);
      return Sacrifice(const You(), f, const Fixed(1));
    }
    m = rx(t, r'counter (.+?)(?: unless its controller pays ((?:\{[^}]+\})+))?');
    if (m != null) {
      final set = parseObjects(m[1].startsWith('target') || m[1] == 'it' || m[1] == 'that spell' ? m[1] : 'target ${m[1]}', ctx, allowGroup: false);
      if (set is! One) return null;
      if (m[2].isNotEmpty) {
        return Unless(CounterSpell(set.ref), ControllerOf(set.ref), mana: ManaCost.parse(m[2].toUpperCase()));
      }
      return CounterSpell(set.ref);
    }

    // --- Library ------------------------------------------------------------------------------
    final search = _search(t, ctx);
    if (search != null) return search;
    final look = _look(t, ctx);
    if (look != null) return look;
    if (t == 'shuffle' || t == 'then shuffle' || t == 'shuffle your library') return const Shuffle();

    // --- Tap / untap ----------------------------------------------------------------------------
    m = rx(t, r'tap (.+)');
    if (m != null) {
      final set = parseObjects(m[1], ctx);
      if (set == null) return null;
      return Tap(set);
    }
    m = rx(t, r'transform (.+)');
    if (m != null) {
      final set = parseObjects(m[1], ctx);
      if (set == null) return null;
      return TransformPermanents(set);
    }
    m = rx(t, r'untap (.+)');
    if (m != null) {
      final set = parseObjects(m[1], ctx);
      if (set == null) return null;
      return Untap(set);
    }

    // --- Control ------------------------------------------------------------------------------
    m = rx(t, r'gain control of (.+?)( until end of turn)?');
    if (m != null) {
      final set = parseObjects(m[1], ctx);
      if (set == null) return null;
      return GainControl(set, duration: m[2].isEmpty ? EffectDuration.permanent : EffectDuration.endOfTurn);
    }
    m = rx(t, r'attach (?:it|~) to (.+)');
    if (m != null) {
      final set = parseObjects(m[1], ctx, allowGroup: false);
      if (set is! One) return null;
      return Attach(const SelfRef(), set.ref);
    }

    // --- Continuous effects from resolution ------------------------------------------------------
    m = rx(t, r'(.+?) (gets?|gains?|loses?|can\x27t|becomes?|has|have) (.+?)(?: (until end of turn|this turn|until your next turn))?');
    if (m != null) {
      final subj = m[1];
      final rest = '${m[2]} ${m[3]}';
      final dur = switch (m[4]) { 'until end of turn' || 'this turn' => EffectDuration.endOfTurn, 'until your next turn' => EffectDuration.untilYourNextTurn, _ => duration };
      if (dur != null || rest.startsWith('can\'t')) {
        final set = parseObjects(subj, ctx);
        if (set != null) {
          final mods = _mods(rest, ctx);
          if (mods != null) return Grant(set, mods, duration: dur ?? EffectDuration.endOfTurn);
        }
      }
    }
    m = rx(t, r'double (.+?) power');
    if (m != null) {
      final o = parseObjects(m[1].replaceAll("'s", ''), ctx, allowGroup: false);
      if (o is! One) return null;
      return DoublePower(o.ref);
    }
    m = rx(t, r'(?:it|~) becomes a (.+?)(?: until end of turn)?');
    if (m != null) return null;

    // --- Misc --------------------------------------------------------------------------------
    if (t == 'end the turn') return const EndTurn();
    m = rx(t, r'you get an emblem with "(.+)"');
    if (m != null) {
      final inner = m[1];
      final f = Face(name: 'Emblem', typeLine: 'Emblem', oracleText: inner);
      final p = _FaceParser(f);
      final abs = p.paragraph(inner.toLowerCase());
      if (abs == null) return null;
      return Emblem(abs, inner);
    }
    m = rx(t, r'(.+?) can\x27t block this turn');
    if (m != null) {
      final set = parseObjects(m[1], ctx);
      if (set == null) return null;
      return Grant(set, const [AddKw(Kw.cantBlock)]);
    }
    m = rx(t, r'add (.+)');
    if (m != null) {
      final mana = _manaEffect(t);
      if (mana != null) return AddMana(mana);
    }
    m = rx(t, r'look at the top (\w+) cards of your library and separate them into a face-down pile and a face-up pile\. an opponent chooses one of those piles\. put that pile into your hand and the other into your graveyard');
    if (m != null) return PilesChoice(parseAmount(m[1])!);
    return null;
  }

  /// "<recipient>" for damage: any target, target creature, each opponent, each creature...
  Effect? _damageTo(String to, Amount amount, ObjRef source, BodyCtx ctx) {
    final t = to.trim();
    final any = parseAnyTarget(t, ctx);
    if (any != null) return DamageTarget(amount, any, source: source);
    final p = parsePlayer(t, ctx);
    if (p != null) return DealDamage(amount, null, toPlayers: p, source: source);
    if (t == 'that player') return DealDamage(amount, null, toPlayers: ctx.thatPlayer ?? const EventPlayer(), source: source);
    final m = rx(t, r'(.+) and each (opponent|player)');
    if (m != null) {
      final set = parseObjects(m[1], ctx);
      if (set == null) return null;
      return Seq([DealDamage(amount, set, source: source), DealDamage(amount, null, toPlayers: m[2] == 'opponent' ? const EachOpponent() : const EachPlayer(), source: source)]);
    }
    final dm = rx(t, r'(.+?) divided as you choose among (.+)');
    if (dm != null) return null;
    final set = parseObjects(t, ctx);
    if (set == null) return null;
    return DealDamage(amount, set, source: source, excessSlot: 'excess');
  }

  /// Token descriptions: "1/1 white Cat creature token", "two 3/3 white Knight creature tokens",
  /// "Food token", "Treasure tokens", "4/4 red Dragon creature token with flying", "tapped 1/1
  /// black Rat creature token", "legendary 8/8 blue Octopus creature token named ...".
  Effect? _createTokens(String desc, Amount amount, BodyCtx ctx, {PlayerRef controller = const You()}) {
    var d = desc.trim();
    var tapped = false, attacking = false;
    if (d.startsWith('tapped ')) {
      tapped = true;
      d = d.substring(7);
    }
    if (d.endsWith(" that's tapped and attacking")) {
      tapped = attacking = true;
      d = d.substring(0, d.length - 28);
    }
    final pre = predefinedTokens[d.replaceAll(RegExp(r' tokens?$'), '')] ?? _textToken(d.replaceAll(RegExp(r' tokens?$'), ''));
    if (pre != null) {
      ctx.it = const Remembered('created');
      return CreateToken(pre, amount, controller: controller, tapped: tapped);
    }
    final m = rx(d, r'(legendary )?(\d+|x)/(\d+|x) (colorless|(?:white|blue|black|red|green)(?:(?:, | and |, and )(?:white|blue|black|red|green))*) (.+?) (artifact creature|creature|enchantment creature) tokens?(?: with (.+?))?(?: named (.+))?');
    if (m == null) {
      // "Scion of the Deep, a legendary 8/8 blue Octopus creature token"
      final named = rx(d, r'(.+?), a (legendary )?(\d+)/(\d+) (white|blue|black|red|green) (.+?) creature token');
      if (named != null) {
        final subs = _subtypes(named[6]);
        if (subs == null) return null;
        ctx.it = const Remembered('created');
        return CreateToken(
            TokenSpec(name: _orig(named[1]), power: int.parse(named[3]), toughness: int.parse(named[4]), colors: {ManaColor.fromWord(named[5])!}, subtypes: subs, supertypes: named[2].isEmpty ? const {} : const {Supertype.legendary}),
            amount,
            controller: controller);
      }
      return null;
    }
    final colors = m[4] == 'colorless' ? <ManaColor>{} : {for (final w in m[4].split(RegExp(r',? and |, '))) ?ManaColor.fromWord(w)};
    final subs = _subtypes(m[5]);
    if (subs == null) return null;
    final kws = <Kw>[];
    final granted = <Ability>[];
    if (m[7].isNotEmpty) {
      // 'with flying', 'with "~ can't block."', 'with toxic 1 and "~ can't block."'
      var w = m[7];
      for (final q in RegExp(r'"([^"]+)"').allMatches(m[7])) {
        final a = OracleParser.parseGranted(q.group(1)!);
        if (a == null) return null;
        granted.add(a);
        w = w.replaceFirst(q.group(0)!, '');
      }
      w = w.trim().replaceAll(RegExp(r'(,? and|,)$'), '').trim();
      if (w.isNotEmpty) {
        final ks = _kwList(w);
        if (ks != null) {
          kws.addAll(ks);
        } else {
          final k = parseKeyword(w, w);
          if (k == null || k.any((a) => a is! KeywordAbility)) return null;
          kws.addAll([for (final a in k) (a as KeywordAbility).kw]);
        }
      }
    }
    final types = {CardType.creature, if (m[6].startsWith('artifact')) CardType.artifact, if (m[6].startsWith('enchantment')) CardType.enchantment};
    final name = m[8].isNotEmpty ? _orig(m[8]) : subs.join(' ');
    ctx.it = const Remembered('created');
    return CreateToken(
      TokenSpec(
        name: name,
        power: m[2] == 'x' ? null : int.parse(m[2]),
        toughness: m[3] == 'x' ? null : int.parse(m[3]),
        colors: colors,
        types: types,
        subtypes: subs,
        supertypes: m[1].isEmpty ? const {} : const {Supertype.legendary},
        keywords: kws,
        abilities: granted,
        text: granted.map((a) => a.text).join('\n'),
      ),
      amount,
      controller: controller,
      tapped: tapped,
      attacking: attacking,
    );
  }

  /// Artifact tokens defined by their rules text (CR 111.10), parsed like card text.
  static const _tokenTexts = {
    'lander': ('Lander', '{2}, {T}, Sacrifice this token: Search your library for a basic land card, put it onto the battlefield tapped, then shuffle.'),
    'mutagen': ('Mutagen', '{1}, {T}, Sacrifice this token: Put a +1/+1 counter on target creature. Activate only as a sorcery.'),
    'map': ('Map', '{1}, {T}, Sacrifice this artifact: Target creature you control explores. Activate only as a sorcery.'),
    'gold': ('Gold', 'Sacrifice this artifact: Add one mana of any color.'),
    'junk': ('Junk', '{T}, Sacrifice this artifact: Exile the top card of your library. You may play that card this turn. Activate only as a sorcery.'),
  };

  static final Map<String, TokenSpec?> _textTokenCache = {};

  TokenSpec? _textToken(String name) {
    final def = _tokenTexts[name];
    if (def == null) return null;
    return _textTokenCache.putIfAbsent(name, () {
      final f = Face(name: def.$1, typeLine: 'Token Artifact — ${def.$1}', oracleText: def.$2);
      final p = OracleParser.parseFace(f);
      if (p.unsupported.isNotEmpty || p.abilities.isEmpty) return null;
      return TokenSpec(name: def.$1, types: const {CardType.artifact}, subtypes: [def.$1], abilities: p.abilities, text: def.$2);
    });
  }

  List<String>? _subtypes(String s) {
    final out = <String>[];
    for (final w in s.split(' ')) {
      final st = subtypeWords[w];
      if (st == null) return null;
      out.add(st);
    }
    return out;
  }

  /// The original capitalization of a lowercased snippet of this face's text (names).
  String _orig(String lower) {
    final src = face.oracleText.replaceAll('’', "'");
    final i = src.toLowerCase().indexOf(lower);
    if (i >= 0) return src.substring(i, i + lower.length);
    if (lower.contains('~')) {
      final pattern = RegExp(lower.split('~').map(RegExp.escape).join(r'([\w-]+)'), caseSensitive: false);
      final m = pattern.firstMatch(src);
      if (m != null) return m.group(0)!;
    }
    return _titleCase(lower);
  }

  String _titleCase(String s) => s.split(' ').map((w) => w.isEmpty ? w : (const {'of', 'the', 'a'}.contains(w) ? w : w[0].toUpperCase() + w.substring(1))).join(' ').replaceFirst(RegExp(r'^.'), s.isEmpty ? '' : s[0].toUpperCase());

  /// "except it has haste and "at the beginning of the end step, sacrifice this token.""
  (List<Mod>, bool)? _copyExcept(String s, BodyCtx ctx) {
    var t = s.trim();
    var sac = false;
    const sacText = ' and "at the beginning of the end step, sacrifice ~."';
    if (t.endsWith(sacText) || t.endsWith(' and "at the beginning of the end step, sacrifice ~"')) {
      sac = true;
      t = t.substring(0, t.lastIndexOf(' and "at the beginning'));
    }
    final mods = <Mod>[];
    final m = rx(t, r"it(?:'s| is) (?:a|an) (.+?) in addition to its other types");
    if (m != null) {
      final subs = _subtypes(m[1]);
      if (subs == null) return null;
      mods.add(TypeMod(subtypes: subs));
      return (mods, sac);
    }
    final h = rx(t, r'it has (.+)');
    if (h != null) {
      final ks = _kwList(h[1]);
      if (ks == null) return null;
      mods.addAll(ks.map(AddKw.new));
      return (mods, sac);
    }
    return null;
  }

  Effect? _search(String t, BodyCtx ctx) {
    final m = rx(t,
        r'search your library for (a|an|up to (?:one|two|three)|two) (.+?), (?:reveal (?:it|them|that card|those cards), )?(put (?:it|them|that card|those cards) (?:into your hand|onto the battlefield(?: tapped)?)|then shuffle and put that card on top)(?:,? then shuffle)?');
    if (m != null) {
      final n = m[1].startsWith('up to') ? numberWord(m[1].substring(6))! : numberWord(m[1])!;
      // "basic land card", "mercenary permanent card with mana value 3 or less", "card named ~".
      final what = m[2];
      final f = what == 'card' || what == 'cards' ? const Filter(card: true) : parseFilterCore(what.contains(' card') || what.startsWith('card') ? what : '$what card');
      if (f == null) return null;
      final where = m[3];
      if (where.contains('put that card on top')) return Search(f, Fixed(n), ZoneKind.library, onTop: true, reveal: true);
      final bf = where.contains('battlefield');
      return Search(f.copyWith(card: true), Fixed(n), bf ? ZoneKind.battlefield : ZoneKind.hand, tapped: where.contains('tapped'), reveal: t.contains('reveal'));
    }
    final m2 = rx(t, r'search your library for a card, put (?:it|that card) into your hand, then shuffle');
    if (m2 != null) return const Search(Filter(card: true), Fixed(1), ZoneKind.hand);
    final m3 = rx(t, r'search your library for (a|an|up to (?:one|two)|two) (.+?) cards?, reveal (?:it|them), then shuffle and put that card on top');
    if (m3 != null) {
      final f = parseFilterCore(m3[2]);
      if (f == null) return null;
      return Search(f, const Fixed(1), ZoneKind.library, onTop: true, reveal: true);
    }
    return null;
  }

  Effect? _look(String t, BodyCtx ctx) {
    var m = rx(t,
        r'look at the top (\w+) cards of your library\. you may reveal (?:a|an) (.+?) card(?: with (.+?))? from among them and put (?:it|that card) (into your hand|onto the battlefield)\. put the rest on the bottom(?: of your library)? in a random order');
    if (m != null) {
      var f = parseFilterCore(m[2]);
      if (f == null) return null;
      if (m[3].isNotEmpty) {
        final w = rx(m[3], r'(power|mana value) (\d+) or less');
        final w2 = rx(m[3], r'mana value less than or equal to the number of lands you control');
        if (w != null) {
          f = w[1] == 'power' ? f.copyWith(power: (Cmp.le, Fixed(int.parse(w[2])))) : f.copyWith(manaValue: (Cmp.le, Fixed(int.parse(w[2]))));
        } else if (w2 != null) {
          f = f.copyWith(manaValue: (Cmp.le, const CountOf(All(Filter(types: {CardType.land}, controller: Who.you)))));
        } else {
          return null;
        }
      }
      return LookAndPick(parseAmount(m[1])!, f.copyWith(card: true), const Fixed(1), m[4].contains('hand') ? ZoneKind.hand : ZoneKind.battlefield);
    }
    m = rx(t, r'look at the top (\w+) cards of your library\. you may put one of (?:those|them) (?:cards )?back on top of your library\. put the rest into your graveyard');
    if (m != null) return LookAndPick(parseAmount(m[1])!, const Filter(card: true), const Fixed(1), ZoneKind.library, rest: RestGoes.graveyard, reveal: false);
    m = rx(t, r'look at the top (\w+) cards of your library\. put (one|two) of them into your hand and the rest on the bottom of your library in any order');
    if (m != null) return LookAndPick(parseAmount(m[1])!, const Filter(card: true), parseAmount(m[2])!, ZoneKind.hand, rest: RestGoes.bottomAnyOrder, mayPick: false, reveal: false);
    m = rx(t, r'reveal cards from the top of your library until you reveal (?:a|an) (.+?) card\. put (?:that card|it) into your hand and the rest on the bottom of your library in a random order');
    if (m != null) {
      final f = parseFilterCore(m[1]);
      if (f == null) return null;
      return RevealUntil(f.copyWith(card: true), ZoneKind.hand);
    }
    m = rx(t, r'(each opponent|target player|target opponent) reveals cards from the top of their library until they reveal a (.+?) card, then puts those cards into their graveyard');
    if (m != null) {
      final who = parsePlayer(m[1], ctx);
      final f = parseFilterCore(m[2]);
      if (who == null || f == null) return null;
      return ForEachPlayer(who, RevealUntil(f.copyWith(card: true), ZoneKind.graveyard, rest: RestGoes.graveyard, who: const EventPlayer()));
    }
    m = rx(t, r'exile the top (\w+) cards? of your library\. (?:choose one of them\. )?(?:until the end of your next turn|until end of turn|this turn), you may play (?:that card|those cards|it)');
    m ??= rx(t, r'exile the top (\w+) cards? of your library\. (?:choose one of them\. )?you may play (?:that card|those cards|it) (this turn|until the end of your next turn)');
    if (m != null) {
      return ExileTopMayPlay(parseAmount(m[1])!, chooseOne: t.contains('choose one'), untilEndOfNextTurn: t.contains('next turn'));
    }
    return null;
  }
}

/// Predefined tokens (CR 111.10).
final Map<String, TokenSpec> predefinedTokens = {
  'food': TokenSpec(
    name: 'Food',
    types: const {CardType.artifact},
    subtypes: const ['Food'],
    abilities: [
      ActivatedAbility('{2}, {T}, Sacrifice this token: You gain 3 life.', Cost(mana: ManaCost.parse('{2}'), tap: true, parts: const [SacrificeCost(Filter.any, self: true)]), const Body(effect: GainLife(Fixed(3)))),
    ],
    text: '{2}, {T}, Sacrifice this token: You gain 3 life.',
  ),
  'treasure': const TokenSpec(
    name: 'Treasure',
    types: {CardType.artifact},
    subtypes: ['Treasure'],
    abilities: [ManaAbility('{T}, Sacrifice this token: Add one mana of any color.', Cost(tap: true, parts: [SacrificeCost(Filter.any, self: true)]), ManaProduce(anyColor: true))],
    text: '{T}, Sacrifice this token: Add one mana of any color.',
  ),
  'clue': TokenSpec(
    name: 'Clue',
    types: const {CardType.artifact},
    subtypes: const ['Clue'],
    abilities: [ActivatedAbility('{2}, Sacrifice this token: Draw a card.', Cost(mana: ManaCost.parse('{2}'), parts: const [SacrificeCost(Filter.any, self: true)]), const Body(effect: Draw(Fixed(1))))],
    text: '{2}, Sacrifice this token: Draw a card.',
  ),
  'blood': TokenSpec(
    name: 'Blood',
    types: const {CardType.artifact},
    subtypes: const ['Blood'],
    abilities: [
      ActivatedAbility('{1}, {T}, Discard a card, Sacrifice this token: Draw a card.', Cost(mana: ManaCost.parse('{1}'), tap: true, parts: const [DiscardCost(Filter.any), SacrificeCost(Filter.any, self: true)]),
          const Body(effect: Draw(Fixed(1)))),
    ],
    text: '{1}, {T}, Discard a card, Sacrifice this token: Draw a card.',
  ),
};


/// [engineVersion] under a name that doesn't clash with fields called engineVersion.
const rulesEngineVersion = engineVersion;
