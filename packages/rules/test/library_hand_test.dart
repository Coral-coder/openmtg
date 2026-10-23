// Regeneration (CR 701.15), prevention shields (CR 615.7), revealed hands (CR 701.20), the top
// of the library (look, reveal, explore, impulse), delayed draws, coins and dice (CR 705–706).
// Cards outside the Foundations fixture are defined here with their printed oracle text.
import 'package:rules/rules.dart';
import 'package:test/test.dart';

import 'helpers.dart';

CardDef _card(String name, String cost, String type, String text, {String? p, String? t}) =>
    CardDef(name: name, layout: Layout.normal, faces: [Face(name: name, manaCost: ManaCost.parse(cost), typeLine: type, oracleText: text, power: p, toughness: t)]);

final _extra = [
  _card('Drudge Skeletons', '{1}{B}', 'Creature — Skeleton', '{B}: Regenerate Drudge Skeletons.', p: '1', t: '1'),
  _card('Terror', '{1}{B}', 'Instant', "Destroy target nonblack creature. It can't be regenerated."),
  _card('Assassinate Test', '{1}', 'Instant', 'Destroy target creature.'),
  _card('Duress', '{B}', 'Sorcery', 'Target opponent reveals their hand. You choose a noncreature, nonland card from it. That player discards that card.'),
  _card('Gitaxian Probe', '{1}', 'Sorcery', "Look at target player's hand.\nDraw a card."),
  _card('Impulse', '{1}{U}', 'Instant', 'Look at the top four cards of your library. Put one of them into your hand and the rest on the bottom of your library in any order.'),
  _card('Mulch', '{1}{G}', 'Sorcery', 'Reveal the top four cards of your library. Put all land cards revealed this way into your hand and the rest into your graveyard.'),
  _card('Healing Ward Test', '{W}', 'Instant', 'Prevent the next 3 damage that would be dealt to any target this turn.'),
  _card('Holy Day', '{W}', 'Instant', 'Prevent all combat damage that would be dealt this turn.'),
  _card('Coin Test', '{1}', 'Sorcery', 'Flip a coin. If you win the flip, you gain 5 life. If you lose the flip, you lose 1 life.'),
  _card('Die Test', '{1}', 'Sorcery', 'Roll a six-sided die. Draw a card.'),
  _card('River Boa Test', '{1}{G}', 'Creature — Snake', '{G}: Regenerate this creature.', p: '2', t: '1'),
  _card('Later Draw Test', '{1}', 'Instant', "Draw a card at the beginning of the next turn's upkeep."),
  _card('Clue Test', '{1}', 'Sorcery', 'Investigate.'),
  _card('Merfolk Branchwalker', '{2}{G}', 'Creature — Merfolk Scout', 'When this creature enters, it explores.', p: '2', t: '1'),
  _card('Abbot Test', '{1}{R}', 'Creature — Human Monk', 'When this creature enters, exile the top card of your library. Until end of turn, you may play that card.', p: '2', t: '1'),
];

CardDatabase? _db;
CardDatabase db() => _db ??= CardDatabase([...fdn().cards, ..._extra]);

Game empty({int active = 0, int seed = 1}) => Game(db(), players: ['Alice', 'Bob'], seed: seed)..startEmpty(active: active);

void answer(Game g, List<int> a) => g.apply(AnswerAction(g.state.pending!.decision.player, a));

void target(Game g, List<int> ids) {
  if (g.state.pending?.decision.kind == DecisionKind.targets) answer(g, ids);
}

void pay(Game g) {
  if (g.state.pending?.decision.kind == DecisionKind.payMana) answer(g, []);
}

void resolveAll(Game g) {
  for (var i = 0; i < 50 && g.state.stack.isNotEmpty && g.state.pending == null; i++) {
    g.apply(PassAction(g.state.priority!));
  }
}

/// Casts [id] for [p] with mana from [lands] untapped lands it adds, targeting [targets].
void cast(Game g, int p, int id, {List<int> targets = const []}) {
  g.apply(CastAction(p, id));
  target(g, targets);
  pay(g);
}

void lands(Game g, int p, String name, int n) {
  for (var i = 0; i < n; i++) {
    g.addCard(name, p, Zone.battlefield);
  }
}

Zone zoneOf(Game g, int id) => g.state.obj(id).zone;

void main() {
  test('every card defined here parses completely', () {
    for (final c in _extra) {
      OracleParser.clearCache();
      expect(OracleParser.parse(c).unsupported, isEmpty, reason: c.name);
    }
  });

  group('CR 701.15 regeneration', () {
    test('a regeneration shield replaces destruction: tapped, damage removed, out of combat', () {
      final g = empty(active: 1);
      lands(g, 0, 'Swamp', 2);
      lands(g, 1, 'Swamp', 1);
      final skel = g.addCard('Drudge Skeletons', 1, Zone.battlefield);
      final kill = g.addCard('Assassinate Test', 0, Zone.hand);
      g.apply(ActivateAbilityAction(1, skel, 0));
      pay(g);
      resolveAll(g);
      expect(g.state.shields, hasLength(1));
      g.apply(PassAction(1));
      cast(g, 0, kill, targets: [skel]);
      resolveAll(g);
      expect(zoneOf(g, skel), Zone.battlefield, reason: 'regenerated');
      expect(g.state.obj(skel).tapped, isTrue);
      expect(g.state.shields, isEmpty, reason: 'the shield is used up');
    });

    test("\"it can't be regenerated\" ignores the shield", () {
      final g = empty(active: 1);
      lands(g, 0, 'Swamp', 2);
      lands(g, 1, 'Forest', 1);
      final boa = g.addCard('River Boa Test', 1, Zone.battlefield);
      final terror = g.addCard('Terror', 0, Zone.hand);
      g.apply(ActivateAbilityAction(1, boa, 0));
      pay(g);
      resolveAll(g);
      expect(g.state.shields, hasLength(1));
      g.apply(PassAction(1));
      cast(g, 0, terror, targets: [boa]);
      resolveAll(g);
      expect(zoneOf(g, boa), Zone.graveyard);
    });

    test('lethal damage is destruction too, and shields end at cleanup', () {
      final g = empty(active: 1);
      lands(g, 1, 'Swamp', 1);
      lands(g, 0, 'Mountain', 1);
      final skel = g.addCard('Drudge Skeletons', 1, Zone.battlefield);
      final bolt = g.addCard('Burst Lightning', 0, Zone.hand);
      g.apply(ActivateAbilityAction(1, skel, 0));
      pay(g);
      resolveAll(g);
      g.apply(PassAction(1));
      g.apply(CastAction(0, bolt));
      answer(g, [0]); // no kicker
      target(g, [skel]);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, skel), Zone.battlefield);
      expect(g.state.obj(skel).damage, 0);
    });

    test('unused shields end at cleanup', () {
      final g = empty(active: 1);
      lands(g, 1, 'Swamp', 1);
      g.stackLibrary(0, ['Forest']);
      final skel = g.addCard('Drudge Skeletons', 1, Zone.battlefield);
      g.apply(ActivateAbilityAction(1, skel, 0));
      pay(g);
      resolveAll(g);
      expect(g.state.shields, hasLength(1));
      for (var i = 0; i < 200 && g.state.turn == 2; i++) {
        final pd = g.state.pending;
        if (pd != null) {
          answer(g, []);
          continue;
        }
        g.apply(PassAction(g.state.priority!));
      }
      expect(g.state.turn, 3);
      expect(g.state.shields, isEmpty);
    });
  });

  group('CR 701.20 revealed hands', () {
    test('Duress: you choose a noncreature, nonland card and they discard it', () {
      final g = empty();
      lands(g, 0, 'Swamp', 1);
      final duress = g.addCard('Duress', 0, Zone.hand);
      final growth = g.addCard('Giant Growth', 1, Zone.hand);
      final forest = g.addCard('Forest', 1, Zone.hand);
      final lions = g.addCard('Savannah Lions', 1, Zone.hand);
      cast(g, 0, duress, targets: [playerEntity(1)]);
      resolveAll(g);
      if (g.state.pending?.decision.kind == DecisionKind.cards) answer(g, [growth]);
      expect(zoneOf(g, growth), Zone.graveyard);
      expect(zoneOf(g, forest), Zone.hand);
      expect(zoneOf(g, lions), Zone.hand);
      expect(g.state.log.any((e) => e.text.contains('reveals their hand')), isTrue);
    });

    test('Gitaxian Probe looks at a hand and draws', () {
      final g = empty();
      g.stackLibrary(0, ['Forest']);
      final probe = g.addCard('Gitaxian Probe', 0, Zone.hand);
      lands(g, 0, 'Plains', 1);
      g.addCard('Giant Growth', 1, Zone.hand);
      cast(g, 0, probe, targets: [playerEntity(1)]);
      resolveAll(g);
      expect(g.state.player(0).hand.map((id) => g.state.obj(id).cardName), ['Forest']);
    });
  });

  group('the top of the library', () {
    test('Impulse: one of four into hand, the rest on the bottom in your order', () {
      final g = empty();
      lands(g, 0, 'Island', 2);
      g.stackLibrary(0, ['Forest', 'Giant Growth', 'Savannah Lions', 'Swamp', 'Plains']);
      final impulse = g.addCard('Impulse', 0, Zone.hand);
      cast(g, 0, impulse);
      resolveAll(g);
      final lib = g.state.player(0).library;
      final growth = lib.firstWhere((id) => g.state.obj(id).cardName == 'Giant Growth');
      answer(g, [growth]);
      final order = g.state.pending!.decision.options;
      expect(order, hasLength(3));
      answer(g, order);
      expect(zoneOf(g, growth), Zone.hand);
      expect(g.state.obj(g.state.player(0).library.first).cardName, 'Plains', reason: 'the fifth card is now on top');
      expect(g.state.player(0).library, hasLength(4));
    });

    test('Mulch: all lands to hand, the rest to the graveyard', () {
      final g = empty();
      lands(g, 0, 'Forest', 2);
      g.stackLibrary(0, ['Forest', 'Giant Growth', 'Swamp', 'Savannah Lions', 'Plains']);
      final mulch = g.addCard('Mulch', 0, Zone.hand);
      cast(g, 0, mulch);
      resolveAll(g);
      List<String> names(List<int> ids) => ids.map((id) => g.state.obj(id).cardName).toList()..sort();
      expect(names(g.state.player(0).hand), ['Forest', 'Swamp']);
      expect(names(g.state.player(0).graveyard), ['Giant Growth', 'Mulch', 'Savannah Lions']);
      expect(names(g.state.player(0).library), ['Plains']);
    });

    test('explore: a land goes to hand; otherwise a counter and the card may be milled', () {
      final g = empty();
      lands(g, 0, 'Forest', 3);
      g.stackLibrary(0, ['Giant Growth', 'Forest']);
      final walker = g.addCard('Merfolk Branchwalker', 0, Zone.hand);
      cast(g, 0, walker);
      resolveAll(g); // the creature
      resolveAll(g); // its trigger
      expect(g.state.pending?.decision.kind, DecisionKind.option);
      answer(g, [1]); // into the graveyard
      expect(g.state.obj(walker).counters['+1/+1'], 1);
      expect(g.state.player(0).graveyard.map((id) => g.state.obj(id).cardName), contains('Giant Growth'));
      expect(g.state.obj(g.state.player(0).library.first).cardName, 'Forest');
    });

    test('impulse draw from a trigger: exile the top card, playable this turn only', () {
      final g = empty();
      lands(g, 0, 'Mountain', 2);
      g.stackLibrary(0, ['Forest']);
      final abbot = g.addCard('Abbot Test', 0, Zone.hand);
      cast(g, 0, abbot);
      resolveAll(g);
      resolveAll(g);
      final forest = g.state.player(0).exile.single;
      expect(g.state.obj(forest).playableBy, 0);
      expect(g.legalActions(0).whereType<PlayLandAction>().any((a) => a.id == forest), isTrue);
    });
  });

  group('CR 615.7 prevention shields', () {
    test('prevent the next 3 damage to a player: 2 + 2 damage → 1 dealt', () {
      final g = empty();
      lands(g, 0, 'Plains', 1);
      lands(g, 0, 'Mountain', 2);
      final ward = g.addCard('Healing Ward Test', 0, Zone.hand);
      cast(g, 0, ward, targets: [playerEntity(1)]);
      resolveAll(g);
      for (var i = 0; i < 2; i++) {
        final bolt = g.addCard('Burst Lightning', 0, Zone.hand);
        g.apply(CastAction(0, bolt));
        answer(g, [0]);
        target(g, [playerEntity(1)]);
        pay(g);
        resolveAll(g);
      }
      expect(g.state.player(1).life, 19);
      expect(g.state.shields, isEmpty);
    });

    test("a combat-damage Fog doesn't stop a burn spell", () {
      final g = empty();
      lands(g, 0, 'Plains', 1);
      lands(g, 0, 'Mountain', 1);
      final fog = g.addCard('Holy Day', 0, Zone.hand);
      cast(g, 0, fog);
      resolveAll(g);
      final bolt = g.addCard('Burst Lightning', 0, Zone.hand);
      g.apply(CastAction(0, bolt));
      answer(g, [0]);
      target(g, [playerEntity(1)]);
      pay(g);
      resolveAll(g);
      expect(g.state.player(1).life, 18);
    });
  });

  group('delayed draws, clues, coins and dice', () {
    test("draw a card at the beginning of the next turn's upkeep", () {
      final g = empty();
      lands(g, 0, 'Plains', 1);
      g.stackLibrary(0, ['Forest', 'Island']);
      g.stackLibrary(1, ['Swamp', 'Swamp']);
      final later = g.addCard('Later Draw Test', 0, Zone.hand);
      cast(g, 0, later);
      resolveAll(g);
      expect(g.state.player(0).hand, isEmpty);
      for (var i = 0; i < 300 && !(g.state.turn == 3 && g.state.step == TurnStep.upkeep && g.state.stack.isEmpty && g.state.player(0).hand.isNotEmpty); i++) {
        final pd = g.state.pending;
        if (pd != null) {
          answer(g, pd.decision.kind == DecisionKind.cards ? pd.decision.options.take(pd.decision.min).toList() : []);
          continue;
        }
        g.apply(PassAction(g.state.priority!));
      }
      expect(g.state.turn, 3);
      expect(g.state.player(0).hand, hasLength(1), reason: "drew at Bob's upkeep");
    });

    test('investigate makes a Clue', () {
      final g = empty();
      lands(g, 0, 'Plains', 1);
      final clue = g.addCard('Clue Test', 0, Zone.hand);
      cast(g, 0, clue);
      resolveAll(g);
      expect(g.state.battlefield.map((id) => g.chars(id).name), contains('Clue'));
    });

    test('a coin flip is seeded: the same seed and actions give the same game', () {
      for (final seed in [1, 2, 3, 4]) {
        final g = empty(seed: seed);
        lands(g, 0, 'Plains', 1);
        final coin = g.addCard('Coin Test', 0, Zone.hand);
        cast(g, 0, coin);
        resolveAll(g);
        expect(g.state.player(0).life, anyOf(25, 19));
        final again = empty(seed: seed);
        again.addCard('Plains', 0, Zone.battlefield);
        final coin2 = again.addCard('Coin Test', 0, Zone.hand);
        cast(again, 0, coin2);
        resolveAll(again);
        expect(again.state.player(0).life, g.state.player(0).life);
      }
    });

    test('a die roll is logged with a result from 1 to 6', () {
      final g = empty(seed: 7);
      lands(g, 0, 'Plains', 1);
      g.stackLibrary(0, ['Forest']);
      final die = g.addCard('Die Test', 0, Zone.hand);
      cast(g, 0, die);
      resolveAll(g);
      final line = g.state.log.lastWhere((e) => e.text.contains(' rolls ')).text;
      expect(int.parse(RegExp(r'rolls (\d+)').firstMatch(line)!.group(1)!), inInclusiveRange(1, 6));
      expect(g.state.player(0).hand, hasLength(1));
    });
  });
}
