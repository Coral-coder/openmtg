part of 'parser.dart';

/// Effect sentences for energy, paying while resolving, clash, amass, bolster, populate, learn,
/// extra turns, untap skipping, end-step returns and sacrifices, and choosing objects that aren't
/// targets. Tried before the main clause grammar (see `_clause2`).
extension _MoreEffects on _FaceParser {
  /// One clause, or null (and then nothing it tried is left in [ctx]).
  Effect? moreClause(String t, BodyCtx ctx) {
    final mark = ctx.mark();
    final r = _moreClause(t, ctx);
    if (r == null) ctx.reset(mark);
    return r;
  }

  Effect? _moreClause(String t, BodyCtx ctx) {
    // Energy (CR 122.1): "you get {E}{E}", "you get {E} for each …", "pay {E}{E}".
    var m = rx(t, r'you get ((?:\{e\})+)');
    if (m != null) return GetEnergy(Fixed('{e}'.allMatches(m[1]).length));
    m = rx(t, r'you get ((?:\{e\})+) for each (.+)');
    if (m != null) {
      final c = countPhrase(m[2], ctx);
      if (c == null) return null;
      final n = '{e}'.allMatches(m[1]).length;
      return GetEnergy(n == 1 ? c : Times(c, n));
    }
    m = rx(t, r'you get an amount of \{e\} equal to (.+)');
    if (m != null) {
      final q = parseQuantity(m[1], ctx);
      return q == null ? null : GetEnergy(q);
    }
    // Paying while resolving: "pay {2}", "pay 3 life", "pay {E}{E}" (the "you may" and "if you
    // do" around it are read by `sentence` and `effects`).
    m = rx(t, r'pay ((?:\{e\})+)');
    if (m != null) return PayEffect(energy: '{e}'.allMatches(m[1]).length);
    m = rx(t, r'pay ((?:\{(?:\d+|[wubrgcx]|[wubrg]/[wubrgp])\})+)');
    if (m != null && !m[1].contains('{x}')) return PayEffect(mana: ManaCost.parse(m[1].toUpperCase()));
    m = rx(t, r'pay (\w+) life');
    if (m != null) {
      final n = numberWord(m[1]);
      return n == null ? null : PayEffect(life: n);
    }

    if (t == 'clash with an opponent') return const Clash();
    if (t == 'choose a color') return const ChooseValue('color');
    if (t == 'choose a creature type') return const ChooseValue('creature type');
    m = rx(t, r'amass (\w+) (\w+)');
    if (m != null) {
      final sub = subtypeWords[m[1]];
      final a = parseAmount(m[2]);
      if (sub == null || a == null) return null;
      return Amass(sub, a);
    }
    m = rx(t, r'bolster (\w+)');
    if (m != null) {
      final a = parseAmount(m[1]);
      return a == null ? null : Bolster(a);
    }
    if (t == 'populate') return const Populate();
    // Learn (CR 701.48): with no sideboard, the choice left is to discard a card and draw one.
    if (t == 'learn') return const Seq([May(Discard(Fixed(1))), If(DidIt(), Draw(Fixed(1)))]);
    if (t == 'take an extra turn after this one') return const ExtraTurn();
    m = rx(t, r'(target player|target opponent) takes an extra turn after this one');
    if (m != null) {
      final p = parsePlayer(m[1], ctx);
      return p == null ? null : ExtraTurn(who: p);
    }

    // Adapt (CR 701.46): counters only if it has none.
    m = rx(t, r'adapt (\w+)');
    if (m != null) {
      final a = parseAmount(m[1]);
      if (a == null) return null;
      return If(const Not(ObjMatches(SelfRef(), Filter(withCounter: '+1/+1'))), PutCounters(const One(SelfRef()), '+1/+1', a));
    }
    // Endure (CR 701.63): counters on it, or a Spirit token that big.
    m = rx(t, r'(?:it|~|they) endures? (\w+)');
    if (m != null) {
      final n = numberWord(m[1]);
      if (n == null) return null;
      final who = ctx.it ?? const SelfRef();
      return ChooseEffect([
        PutCounters(One(who), '+1/+1', Fixed(n)),
        CreateToken(TokenSpec(name: 'Spirit', power: n, toughness: n, colors: const {ManaColor.white}, subtypes: const ['Spirit']), const Fixed(1)),
      ], labels: ['Put $n +1/+1 counters on it', 'Create a $n/$n Spirit token']);
    }
    // Support (CR 701.33).
    m = rx(t, r'support (\w+)');
    if (m != null) {
      final n = m[1];
      return _clause2('put a +1/+1 counter on each of up to $n other target creatures', ctx, null);
    }

    // "Doesn't untap during its controller's next untap step."
    m = rx(t, r"(.+?) (?:doesn't|don't|does not|do not) untap during (?:its controller's|their controllers'|their controller's|your) next untap step");
    if (m != null) {
      final set = _subject(m[1], ctx);
      return set == null ? null : SkipNextUntap(set);
    }
    m = rx(t, r"tap (.+?)\. (?:it|that creature|those creatures) (?:doesn't|don't) untap during (?:its|their) controllers?'s? next untap step");
    if (m != null) {
      final set = _subject(m[1], ctx);
      return set == null ? null : Seq([Tap(set), SkipNextUntap(set)]);
    }

    // End-step delayed effects.
    m = rx(t, r'sacrifice (it|them|that creature|that token|those tokens|those creatures|~) at the beginning of the next end step');
    if (m != null) {
      final set = _subject(m[1], ctx);
      return set == null ? null : AtNextEndStep(set, sacrifice: true);
    }
    m = rx(t, r'sacrifice (it|them|that creature|that token|those tokens|those creatures|~) at end of combat');
    if (m != null) {
      final set = _subject(m[1], ctx);
      return set == null ? null : AtNextEndStep(set, sacrifice: true, step: TurnStep.endCombat);
    }
    // "At the beginning of the next end step, return that creature to its owner's hand."
    m = rx(t, r"at the beginning of the next end step, (sacrifice|exile|return) (it|them|that creature|that card|that token|those tokens|those creatures|~)(?: to (?:its|their) owner'?s'? hands?| to the battlefield under (its owner's|their owners'|your) control)?");
    if (m != null) {
      final set = _subject(m[2], ctx);
      if (set == null) return null;
      return switch (m[1]) {
        'sacrifice' => AtNextEndStep(set, sacrifice: true),
        'exile' => AtNextEndStep(set, exile: true),
        _ => t.contains('to the battlefield') ? AtNextEndStep(set, returnIt: true, underYourControl: m[3] == 'your') : (t.contains('hand') ? AtNextEndStep(set, toHand: true) : null),
      };
    }
    m = rx(t, r"return (it|them|that creature|that card|~) to (?:its|their) owner'?s'? hands? at the beginning of the next end step");
    if (m != null) {
      final set = _subject(m[1], ctx);
      return set == null ? null : AtNextEndStep(set, toHand: true);
    }
    m = rx(t, r'exile (it|them|that creature|that token|those tokens|those creatures|~) at the beginning of the next end step');
    if (m != null) {
      final set = _subject(m[1], ctx);
      return set == null ? null : AtNextEndStep(set, exile: true);
    }
    m = rx(t, r"return (it|them|that card|those cards|the exiled card|the exiled cards|that creature|~) to the battlefield under (its owner's|their owners'|your) control at the beginning of the next end step");
    if (m != null) {
      final set = _subject(m[1], ctx);
      return set == null ? null : AtNextEndStep(set, returnIt: true, underYourControl: m[2] == 'your');
    }

    // Choosing objects that aren't targets.
    m = rx(t, r"return (a|an|one|two) (.+?) you control to its owner's hand");
    m ??= rx(t, r"return (a|an|one|two) (.+?) you control to their owner's hand");
    if (m != null) {
      final f = parseFilterCore(m[2]);
      final a = parseAmount(m[1]);
      if (f == null || a == null) return null;
      return ChooseAndMove(f, ZoneKind.battlefield, ZoneKind.hand, amount: a);
    }
    m = rx(t, r'put (a|an|one|two) (.+?) cards? from your hand onto the battlefield( tapped)?');
    if (m != null) {
      final f = parseFilterCore('${m[2]} card');
      final a = parseAmount(m[1]);
      if (f == null || a == null) return null;
      return ChooseAndMove(f, ZoneKind.hand, ZoneKind.battlefield, amount: a, tapped: m[3].isNotEmpty);
    }

    // "Switch target creature's power and toughness until end of turn."
    m = rx(t, r"switch (.+?)(?:'s)? power and toughness until end of turn");
    if (m != null) {
      final set = _subject(m[1].replaceAll(RegExp(r"'s$"), ''), ctx);
      return set == null ? null : Grant(set, const [SwitchPT()]);
    }
    // "Up to two target creatures each get +1/+1 until end of turn."
    m = rx(t, r'(.+?) each (get|gain|have) (.+)');
    if (m != null) return _clause2('${m[1]} ${m[2]} ${m[3]}', ctx, null);
    // "They gain haste until end of turn."
    if (t.startsWith('they ') && ctx.them != null) return _clause2('those creatures ${t.substring(5)}', ctx, null);
    // "It gains haste." (no duration: for as long as it stays).
    m = rx(t, r'(it|that creature|those creatures|they) (gains?) ((?:[a-z]+)(?:(?:, | and |, and )[a-z ]+)*)');
    if (m != null && !m[3].contains('until') && !m[3].contains('this turn')) {
      final set = _subject(m[1] == 'they' ? 'those creatures' : m[1], ctx);
      final kws = _kwList(m[3]);
      if (set == null || kws == null) return null;
      return Grant(set, [for (final k in kws) AddKw(k)], duration: EffectDuration.permanent);
    }
    // "Lose 2 life" after "you draw a card and".
    m = rx(t, r'lose (\w+) life');
    if (m != null) {
      final a = parseAmount(m[1]);
      return a == null ? null : LoseLife(a, who: const You(), slot: 'lifeLost');
    }
    // "Sacrifice ~ unless you pay {2}" / "… unless you discard a card" (upkeep costs).
    m = rx(t, r'sacrifice (~|it) unless you (.+)');
    if (m != null) {
      final self = m[1] == '~' || ctx.it is SelfRef || (ctx.it == null && ctx.eventObj == null);
      if (!self) return null;
      const sac = Sacrifice(You(), Filter.any, Fixed(1), self: true);
      final pay = rx(m[2], r'pay ((?:\{(?:\d+|[wubrgc]|[wubrg]/[wubrgp])\})+)');
      if (pay != null) return Unless(sac, const You(), mana: ManaCost.parse(pay[1].toUpperCase()));
      final life = rx(m[2], r'pay (\w+) life');
      if (life != null) {
        final n = numberWord(life[1]);
        return n == null ? null : Unless(sac, const You(), life: n);
      }
      // Any other action: "discard a card", "return a land you control to its owner's hand",
      // "sacrifice a forest".
      final alt = _clause2(m[2].startsWith('sacrifice ') || m[2].startsWith('discard ') || m[2].startsWith('return ') ? m[2] : 'you ${m[2]}', ctx, null);
      if (alt == null || !(alt is Discard || alt is Sacrifice || alt is ChooseAndMove)) return null;
      return Unless(sac, const You(), alternative: alt);
    }
    // "… damage to each creature and each planeswalker", "… to each of up to two target creatures".
    if (t.contains(' damage to each creature and each planeswalker')) return _clause2(t.replaceFirst('each creature and each planeswalker', 'each creature and planeswalker'), ctx, null);
    m = rx(t, r'(.+? deals \w+ damage to) each of (up to \w+ target .+)');
    if (m != null) return _clause2('${m[1]} ${m[2]}', ctx, null);
    // Poison (CR 122.1f): "each opponent gets a poison counter", "target player gets two poison counters".
    m = rx(t, r'(.+?) gets? (a|an|one|two|three|four|five|\d+) poison counters?');
    if (m != null) {
      final p = parsePlayer(m[1], ctx);
      final n = parseAmount(m[2]);
      if (p == null || n == null) return null;
      return GetEnergy(n, who: p, poison: true);
    }
    // "You gain 2 life for each creature destroyed this way."
    m = rx(t, r'(?:you )?gain (\w+) life for each (?:creature|permanent|artifact|enchantment|land|nonland permanent)s? destroyed this way');
    if (m != null) {
      final n = numberWord(m[1]);
      if (n == null) return null;
      return GainLife(n == 1 ? const ResultAmount('destroyed') : Times(const ResultAmount('destroyed'), n));
    }
    // "~ deals 1 damage to any target and 1 damage to you", "… 3 damage to target creature and 3
    // damage to target player or planeswalker".
    m = rx(t, r'(.+? deals \w+ damage to .+?) and (\w+) damage to (.+)');
    if (m != null) {
      final first = _clause2(m[1], ctx, null);
      final a = parseAmount(m[2]);
      if (first == null || a == null) return null;
      final src = first is DamageTarget ? first.source : (first is DealDamage ? first.source : null);
      if (src == null) return null;
      final second = m[3] == 'you' ? DealDamage(a, null, toPlayers: const You(), source: src) : _damageTo(m[3], a, src, ctx);
      if (second == null) return null;
      return Seq([first, second]);
    }
    // "~ deals damage equal to the number of lands you control to target creature".
    m = rx(t, r'(~|it|that creature|target creature you control|target creature) deals damage equal to (.+?) to (.+)');
    m ??= rx(t, r'(~|it|that creature) deals damage to (.+?) equal to (.+)');
    if (m != null) {
      final swapped = t.contains(' deals damage to ');
      final qText = swapped ? m[3] : m[2];
      final toText = swapped ? m[2] : m[3];
      final src = m[1] == '~' ? const SelfRef() : (m[1] == 'it' || m[1] == 'that creature' ? (ctx.it ?? const SelfRef()) : null);
      ObjRef source;
      if (src != null) {
        source = src;
      } else {
        final s = parseObjects(m[1], ctx, allowGroup: false);
        if (s is! One) return null;
        source = s.ref;
      }
      final q = qText == 'its power' || qText == "~'s power" ? StatOf(Stat.power, source) : parseQuantity(qText, ctx);
      if (q == null) return null;
      return _damageTo(toText, q, source, ctx);
    }
    // "You may have ~ deal 2 damage to target player", "you may have target creature get -2/-2".
    m = rx(t, r'have (.+?) (deal|get|gain|fight|explore|connive) (.+)');
    if (m != null) {
      final verb = switch (m[2]) { 'deal' => 'deals', 'get' => 'gets', 'gain' => 'gains', 'fight' => 'fights', 'explore' => 'explores', _ => 'connives' };
      return _clause2('${m[1]} $verb ${m[3]}', ctx, null);
    }
    // "~ gets +2/+0 until end of turn and can't be blocked this turn": one duration for both.
    if (t.contains(' until end of turn and ') && (t.endsWith(' this turn') || t.endsWith(' until end of turn'))) {
      return _clause2(t.replaceFirst(' until end of turn and ', ' and '), ctx, null);
    }
    if (t == 'you may play an additional land this turn' || t == 'play an additional land this turn') return const RuleChange(ExtraLandPerTurn(1));
    if (t == 'exile all graveyards' || t == 'exile all cards from all graveyards') return const ForEachPlayer(EachPlayer(), MoveTo(All(Filter(card: true, zone: ZoneKind.graveyard, owner: Who.that)), ZoneKind.exile));
    m = rx(t, r'(target player|each player|you) shuffles? (?:their|your) graveyard into (?:their|your) library');
    if (m != null) {
      final p = parsePlayer(m[1], ctx);
      if (p == null) return null;
      return ForEachPlayer(p, const Seq([MoveTo(All(Filter(card: true, zone: ZoneKind.graveyard, owner: Who.that)), ZoneKind.library), Shuffle(who: EventPlayer())]));
    }
    // Divided damage (CR 601.2d): "~ deals 4 damage divided as you choose among one or two targets".
    m = rx(t, r'(~|it) deals (\w+) damage divided as you choose among (one or two|one, two, or three|any number of|up to (?:two|three|four|five)) (targets|target creatures|target creatures and/or planeswalkers|target creatures and/or players|target creatures your opponents control|target creatures an opponent controls)');
    if (m != null) {
      final a = parseAmount(m[2]);
      if (a == null) return null;
      final max = switch (m[3]) { 'one or two' => 2, 'one, two, or three' => 3, 'up to two' => 2, 'up to three' => 3, 'up to four' => 4, 'up to five' => 5, _ => a is Fixed ? a.n : 20 };
      final TargetSpec spec = switch (m[4]) {
        'targets' => TargetSpec(TargetKind.any, max: max),
        'target creatures and/or planeswalkers' => TargetSpec(TargetKind.object, filter: const Filter(types: {CardType.creature, CardType.planeswalker}), max: max),
        'target creatures and/or players' => TargetSpec(TargetKind.any, filter: const Filter(types: {CardType.creature}), max: max),
        'target creatures your opponents control' || 'target creatures an opponent controls' => TargetSpec(TargetKind.object, filter: const Filter(types: {CardType.creature}, controller: Who.opponent), max: max),
        _ => TargetSpec(TargetKind.object, filter: const Filter(types: {CardType.creature}), max: max),
      };
      final i = ctx.addTarget(spec);
      return DamageTarget(a, i, source: m[1] == '~' ? const SelfRef() : (ctx.it ?? const SelfRef()), divided: true);
    }
    // "Target creature deals damage to itself equal to its power."
    m = rx(t, r'(target creature|it|that creature) deals damage to itself equal to its power');
    if (m != null) {
      final set = _subject(m[1], ctx);
      if (set is! One) return null;
      return DealDamage(StatOf(Stat.power, set.ref), set, source: set.ref);
    }
    // "You may tap or untap target creature."
    m = rx(t, r'tap or untap (.+)');
    if (m != null) {
      final set = parseObjects(m[1], ctx);
      if (set == null) return null;
      return ChooseEffect([Tap(set), Untap(set)], labels: const ['Tap it', 'Untap it']);
    }
    return null;
  }

  /// "It", "them", "~", "that creature", "target creature" → the objects.
  ObjSet? _subject(String s, BodyCtx ctx) {
    final t = s.trim();
    if (t == '~') return const One(SelfRef());
    if (t == 'them' || t == 'they' || t == 'those cards' || t == 'those creatures' || t == 'those tokens' || t == 'the exiled cards') return ctx.them ?? (ctx.it == null ? null : One(ctx.it!));
    if (t == 'it' || t == 'that card' || t == 'that creature' || t == 'that token' || t == 'the exiled card') {
      // After "exile …", the card is a new object in exile (CR 400.7): follow it there.
      if (ctx.lastVerb == 'exile' && ctx.lastRemembered != null) return One(Remembered(ctx.lastRemembered!));
      final r = ctx.it ?? ctx.eventObj;
      return r == null ? null : One(r);
    }
    return parseObjects(t, ctx);
  }
}
