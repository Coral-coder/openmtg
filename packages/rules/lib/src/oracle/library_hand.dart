part of 'parser.dart';

/// Regeneration, prevention shields, hands, the top of the library, coins and dice: clauses,
/// effects that run over several sentences, and the conditions and statics that go with them.
extension _LibraryHand on _FaceParser {
  /// One clause, or null.
  Effect? libraryHandClause(String t, BodyCtx ctx) {
    // Regenerate (CR 701.15).
    var m = rx(t, r'regenerate (.+)');
    if (m != null) {
      final set = parseObjects(_selfWords(m[1]), ctx);
      return set == null ? null : Regenerate(set);
    }
    m = rx(t, r'(.+) explores');
    if (m != null) {
      final set = parseObjects(_selfWords(m[1]), ctx);
      return set == null ? null : Explore(set);
    }
    m = rx(t, r'look at the top (\w+) cards of your library(?:,|\.) then put them back in any order');
    if (m != null) {
      final n = parseAmount(m[1]);
      return n == null ? null : LookAndPick(n, const Filter(card: true), const Fixed(0), ZoneKind.library, rest: RestGoes.topAnyOrder, mayPick: false, reveal: false);
    }
    if (t == 'investigate') return _createTokens('clue token', const Fixed(1), ctx);
    m = rx(t, r'investigate (twice|three times|(\w+) times)');
    if (m != null) {
      final n = switch (m[1]) { 'twice' => const Fixed(2), 'three times' => const Fixed(3), _ => parseAmount(m[2]) };
      if (n == null) return null;
      return _createTokens('clue tokens', n, ctx);
    }

    // Prevention shields (CR 615.7).
    m = rx(t, r'prevent the next (\w+) damage that would be dealt to (.+?) this turn');
    if (m != null) {
      final n = parseAmount(m[1]);
      if (n == null) return null;
      return _preventTo(m[2], n, ctx, combatOnly: false);
    }
    m = rx(t, r'prevent all (combat )?damage that would be dealt(?: this turn| to (.+?) this turn| by (.+?) this turn| this turn by (.+))');
    if (m != null) {
      final combat = m[1].isNotEmpty;
      if (m[2].isNotEmpty) {
        final both = rx(m[2], r'and dealt by (.+)');
        if (both != null) return null;
        return _preventTo(m[2], null, ctx, combatOnly: combat);
      }
      final by = m[3].isNotEmpty ? m[3] : m[4];
      if (by.isNotEmpty) {
        final set = parseObjects(_selfWords(by), ctx);
        return set == null ? null : PreventNext(by: set, combatOnly: combat);
      }
      return PreventNext(combatOnly: combat);
    }
    m = rx(t, r'prevent all combat damage that would be dealt to and dealt by (.+?) this turn');
    if (m != null) {
      final set = parseObjects(_selfWords(m[1]), ctx);
      if (set == null) return null;
      return Seq([PreventNext(set: set, combatOnly: true), PreventNext(by: set, combatOnly: true)]);
    }

    // Hands (CR 701.20).
    m = rx(t, r'(target player|target opponent|each opponent|each player|that player) reveals (?:their|his or her) hand');
    if (m != null) {
      final who = _who(m[1], ctx);
      return who == null ? null : RevealHand(who);
    }
    m = rx(t, r"look at (target player|target opponent|that player|each opponent)(?:'s|') hand");
    if (m != null) {
      final who = _who(m[1], ctx);
      return who == null ? null : RevealHand(who);
    }

    // Coins and dice (CR 705, 706), from the game's seeded generator.
    if (t == 'flip a coin') return const FlipCoin();
    m = rx(t, r'roll (a|two|three) (four|six|eight|ten|twelve|twenty)-sided (?:die|dice)');
    if (m != null) {
      const sides = {'four': 4, 'six': 6, 'eight': 8, 'ten': 10, 'twelve': 12, 'twenty': 20};
      return RollDie(sides[m[2]]!, count: m[1] == 'a' ? 1 : numberWord(m[1])!);
    }
    m = rx(t, r'roll a d(\d+)');
    if (m != null) return RollDie(int.parse(m[1]));

    // Delayed draws and returning this card.
    m = rx(t, r"draw (a card|two cards) at the beginning of the next turn's upkeep");
    if (m != null) return Delayed(const StepTrigger(TurnStep.upkeep, Who.any), Draw(Fixed(m[1] == 'a card' ? 1 : 2)));
    if (t == 'return ~ from your graveyard to your hand') return const MoveTo(One(SelfRef()), ZoneKind.hand);
    return null;
  }

  /// "this creature" and friends mean the source.
  String _selfWords(String s) {
    final t = s.trim();
    return const {'this creature', 'this artifact', 'this permanent', 'this enchantment', 'this land'}.contains(t) ? '~' : t;
  }

  PlayerRef? _who(String s, BodyCtx ctx) => s == 'that player' ? (ctx.thatPlayer ?? const EventPlayer()) : parsePlayer(s, ctx);

  Effect? _preventTo(String to, Amount? n, BodyCtx ctx, {required bool combatOnly}) {
    final t = _selfWords(to);
    if (t == 'you') return PreventNext(amount: n, toYou: true, combatOnly: combatOnly);
    final any = parseAnyTarget(t, ctx);
    if (any != null) return PreventNext(amount: n, target: any, combatOnly: combatOnly);
    final mark = ctx.mark();
    final p = parsePlayer(t, ctx);
    if (p is TargetPlayer) return PreventNext(amount: n, target: p.index, combatOnly: combatOnly);
    ctx.reset(mark);
    if (p != null) return null;
    final set = parseObjects(t, ctx);
    if (set == null) return null;
    if (set case One(ref: TargetObj(:final index))) return PreventNext(amount: n, target: index, combatOnly: combatOnly);
    return PreventNext(amount: n, set: set, combatOnly: combatOnly);
  }

  /// Effects that run over several sentences, starting at sentence [i]: the effect and how many
  /// sentences it used.
  (Effect, int)? libraryHandMulti(List<String> ss, int i, BodyCtx ctx) {
    for (var k = ss.length - i < 4 ? ss.length - i : 4; k >= 2; k--) {
      // "the top card" reads as "the top one card" for the counted patterns.
      final joined = ss.sublist(i, i + k).join('. ').replaceFirst(RegExp(r'^exile the top card of'), 'exile the top one card of');
      final mark = ctx.mark();
      final e = _lookTop(joined, ctx) ?? _revealHandChoose(joined, ctx) ?? _look(joined, ctx);
      if (e != null) return (e, k);
      ctx.reset(mark);
    }
    return null;
  }

  /// "Look at the top N cards of your library" with what happens to them.
  Effect? _lookTop(String t, BodyCtx ctx) {
    final m = rx(t, r'(look at|reveal) the top (\w+) cards of your library\. (.+)');
    if (m == null) return null;
    final n = parseAmount(m[2]);
    if (n == null) return null;
    final revealed = m[1] == 'reveal';
    var rest = m[3];
    if (rest.startsWith('then ')) rest = rest.substring(5);
    // What happens to the rest, said last.
    RestGoes? restGoes;
    const tails = [
      (' on the bottom of your library in a random order', RestGoes.bottomRandom),
      (' on the bottom of your library in any order', RestGoes.bottomAnyOrder),
      (' on the bottom of your library', RestGoes.bottomAnyOrder),
      (' into your graveyard', RestGoes.graveyard),
    ];
    for (final (tail, goes) in tails) {
      for (final lead in const ['. put the rest', '. then put the rest', ' and the rest', ' and the other', '. put the other']) {
        if (rest.endsWith('$lead$tail')) {
          restGoes = goes;
          rest = rest.substring(0, rest.length - lead.length - tail.length);
          break;
        }
      }
      if (restGoes != null) break;
    }
    // The pick.
    var p = rx(rest, r'you may reveal (?:a|an) (.+?) card(?: with (.+?))? from among them and put (?:it|that card) (into your hand|onto the battlefield(?: tapped)?)');
    if (p != null) {
      final f = _pickFilter(p[1], p[2]);
      if (f == null) return null;
      return LookAndPick(n, f, const Fixed(1), p[3].contains('hand') ? ZoneKind.hand : ZoneKind.battlefield, rest: restGoes ?? RestGoes.bottomRandom, tapped: p[3].endsWith('tapped'));
    }
    p = rx(rest, r'you may put (?:a|an) (.+?) card(?: with (.+?))? from among them (into your hand|onto the battlefield(?: tapped)?)');
    if (p != null) {
      final f = _pickFilter(p[1], p[2]);
      if (f == null) return null;
      return LookAndPick(n, f, const Fixed(1), p[3].contains('hand') ? ZoneKind.hand : ZoneKind.battlefield, rest: restGoes ?? RestGoes.bottomRandom, reveal: revealed, tapped: p[3].endsWith('tapped'));
    }
    // "Put all land cards revealed this way into your hand and the rest into your graveyard."
    p = rx(rest, r'put all (.+?) cards(?: with (.+?))? (?:revealed this way|from among them) (into your hand|onto the battlefield(?: tapped)?)');
    if (p != null && restGoes != null) {
      final f = _pickFilter(p[1], p[2]);
      if (f == null) return null;
      return LookAndPick(n, f, const Fixed(99), p[3].contains('hand') ? ZoneKind.hand : ZoneKind.battlefield, rest: restGoes, mayPick: false, reveal: revealed, tapped: p[3].endsWith('tapped'));
    }
    p = rx(rest, r'put (one|two|three|up to (one|two|three)) (?:of them |of those cards )?(into your hand|into your graveyard)');
    if (p != null) {
      final upTo = p[2].isNotEmpty;
      final k = numberWord(upTo ? p[2] : p[1]);
      if (k == null) return null;
      final zone = p[3].contains('hand') ? ZoneKind.hand : ZoneKind.graveyard;
      return LookAndPick(n, const Filter(card: true), Fixed(k), zone, rest: restGoes ?? RestGoes.top, mayPick: upTo, reveal: false);
    }
    p = rx(rest, r'you may put one of (?:those|them) (?:cards )?back on top of your library');
    if (p != null && restGoes == RestGoes.graveyard) return LookAndPick(n, const Filter(card: true), const Fixed(1), ZoneKind.library, rest: RestGoes.graveyard, reveal: false);
    return null;
  }

  /// "nonland" / "noncreature, nonland" / "creature or land" (the words before "card").
  Filter? _cardFilter(String what) => parseFilterCore('$what card') ?? parseFilterCore('${what.replaceAll(', ', ' ')} card') ?? parseFilterCore(what);

  Filter? _pickFilter(String what, String with_) {
    var f = _cardFilter(what);
    if (f == null) return null;
    if (with_.isNotEmpty) {
      final w = rx(with_, r'(power|toughness|mana value) (\d+|x) or (less|greater)');
      if (w == null) return null;
      final a = parseAmount(w[2])!;
      final cmp = w[3] == 'less' ? Cmp.le : Cmp.ge;
      f = switch (w[1]) { 'power' => f.copyWith(power: (cmp, a)), 'toughness' => f.copyWith(toughness: (cmp, a)), _ => f.copyWith(manaValue: (cmp, a)) };
    }
    return f.copyWith(card: true);
  }

  /// Duress and friends: "target opponent reveals their hand. you choose a nonland card from it.
  /// that player discards that card."
  Effect? _revealHandChoose(String t, BodyCtx ctx) {
    final m = rx(t,
        r'(target player|target opponent|each opponent|that player) reveals (?:their|his or her) hand\. you (may )?choose (?:(?:a|an) (.+?) card|a card) from it(?:\. | and )(?:if you do, )?(that player discards (?:that card|it)|they discard (?:that card|it)|exile (?:that card|it))');
    if (m == null) return null;
    final who = _who(m[1], ctx);
    if (who == null) return null;
    final f = m[3].isEmpty ? Filter.any : _cardFilter(m[3]);
    if (f == null) return null;
    return RevealHand(who, filter: f, exile: m[4].startsWith('exile'), optional: m[2].isNotEmpty);
  }

  /// "It can't be regenerated" after a destroy: the destroy ignores regeneration shields.
  Effect? noRegen(Effect e) => switch (e) {
        Destroy(:final set) => Destroy(set, noRegen: true),
        Seq(:final steps) when steps.isNotEmpty => () {
            final last = noRegen(steps.last);
            return last == null ? null : Seq([...steps.take(steps.length - 1), last]);
          }(),
        May(:final effect) => () {
            final inner = noRegen(effect);
            return inner == null ? null : May(inner);
          }(),
        If(:final cond, :final then, :final otherwise) => () {
            final inner = noRegen(then);
            return inner == null ? null : If(cond, inner, otherwise);
          }(),
        _ => null,
      };

  static final _cantRegen = RegExp(r"^(?:it|they|that creature|those creatures|the creature|creatures destroyed this way|a creature destroyed this way) can't be regenerated$");

  bool isCantRegenerate(String s) => _cantRegen.hasMatch(s.trim());

  Condition? libraryHandCondition(String s) => switch (s.trim()) {
        'you win the flip' => const WonFlip(true),
        'you lose the flip' => const WonFlip(false),
        _ => null,
      };

  List<Ability>? libraryHandStatic(String p, String raw) {
    if (p == 'you may look at the top card of your library any time' || p == 'you may look at the top card of your library any time.') {
      return [RuleAbility(raw, const LookAtTopAnyTime())];
    }
    return null;
  }
}
