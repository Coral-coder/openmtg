// Cards with more than one face: split cards and fuse (CR 709, 702.102), aftermath (702.127),
// adventurers and Omens (715), modal double-faced cards (712.12–14) and transforming
// double-faced cards (701.28, 712.18).
import 'dart:convert';
import 'dart:io';

import 'package:rules/rules.dart';
import 'package:test/test.dart';

CardDatabase? _db;
CardDatabase layouts() => _db ??= CardDatabase.fromJson(jsonDecode(File('test/fixtures/layouts.json').readAsStringSync()) as Map<String, dynamic>);

Game empty() => Game(layouts(), players: ['Alice', 'Bob'], seed: 1)..startEmpty();

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

void lands(Game g, String name, int n, {int p = 0}) {
  for (var i = 0; i < n; i++) {
    g.addCard(name, p, Zone.battlefield);
  }
}

Zone zoneOf(Game g, int id) => g.state.obj(id).zone;

void main() {
  group('CR 715 adventurers', () {
    test('the Adventure is cast, exiled on resolution, and the creature is cast later from exile', () {
      final g = empty();
      lands(g, 'Mountain', 3);
      final orn = g.addCard('Ornithopter', 1, Zone.battlefield);
      final card = g.addCard('Embereth Shieldbreaker // Battle Display', 0, Zone.hand);
      expect(g.castFaces(0, card), [0, 1]);
      expect(g.legalActions(0).whereType<CastAction>().where((a) => a.id == card).map((a) => a.face), containsAll([0, 1]));
      g.apply(CastAction(0, card, face: 1));
      target(g, [orn]);
      // On the stack it's the Adventure: a sorcery with its own name.
      expect(g.chars(card).name, 'Battle Display');
      expect(g.chars(card).isSorcery, isTrue);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, orn), Zone.graveyard);
      expect(zoneOf(g, card), Zone.exile);
      expect(g.state.obj(card).adventureBy, 0);
      // From exile only the creature may be cast.
      expect(g.castFaces(0, card), [0]);
      expect(() => g.apply(CastAction(0, card, face: 1)), throwsA(isA<GameError>()));
      g.apply(CastAction(0, card));
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, card), Zone.battlefield);
      expect(g.chars(card).name, 'Embereth Shieldbreaker');
      expect(g.chars(card).isCreature, isTrue);
      expect(g.state.obj(card).adventureBy, isNull);
    });

    test('a countered Adventure goes to the graveyard, and can\'t be cast from there', () {
      final g = empty();
      lands(g, 'Mountain', 1);
      lands(g, 'Island', 2, p: 1);
      final orn = g.addCard('Ornithopter', 1, Zone.battlefield);
      final card = g.addCard('Embereth Shieldbreaker // Battle Display', 0, Zone.hand);
      final cs = g.addCard('Counterspell', 1, Zone.hand);
      g.apply(CastAction(0, card, face: 1));
      target(g, [orn]);
      pay(g);
      // Alice's own spell: she passes automatically, so Bob has priority.
      g.apply(CastAction(1, cs));
      target(g, [g.state.stack.first.objId!]);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, card), Zone.graveyard);
      expect(zoneOf(g, orn), Zone.battlefield);
      expect(g.legalActions(0).whereType<CastAction>().where((a) => a.id == card), isEmpty);
    });

    test('a creature card with an Adventure is only the creature outside the stack', () {
      final g = empty();
      final card = g.addCard('Embereth Shieldbreaker // Battle Display', 0, Zone.hand);
      final c = g.chars(card);
      expect(c.name, 'Embereth Shieldbreaker');
      expect(c.manaValue, 2);
    });

    test('an Omen is shuffled into its owner\'s library when it resolves', () {
      final g = empty();
      lands(g, 'Swamp', 2);
      final bears = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      final card = g.addCard('Disruptive Stormbrood // Petty Revenge', 0, Zone.hand);
      final before = g.state.player(0).library.length;
      g.apply(CastAction(0, card, face: 1));
      target(g, [bears]);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, bears), Zone.graveyard);
      expect(zoneOf(g, card), Zone.library);
      expect(g.state.player(0).library.length, before + 1);
    });
  });

  group('CR 709 split cards, 702.102 fuse, 702.127 aftermath', () {
    test('a split card has both halves\' characteristics until one half is cast', () {
      final g = empty();
      lands(g, 'Mountain', 1);
      final bears = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      final card = g.addCard('Dead // Gone', 0, Zone.hand);
      final c = g.chars(card);
      expect(c.name, 'Dead // Gone');
      expect(c.manaValue, 4); // {R} + {2}{R}
      expect(g.castFaces(0, card), [0, 1]);
      g.apply(CastAction(0, card));
      target(g, [bears]);
      expect(g.chars(card).name, 'Dead');
      expect(g.chars(card).manaValue, 1);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, bears), Zone.graveyard);
      expect(zoneOf(g, card), Zone.graveyard);
      expect(g.chars(card).manaValue, 4);
    });

    test('the other half has its own cost and effect', () {
      final g = empty();
      lands(g, 'Mountain', 2);
      final bears = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      final card = g.addCard('Dead // Gone', 0, Zone.hand);
      expect(g.whyNot(CastAction(0, card, face: 1)), isNotNull, reason: 'Gone costs {2}{R}');
      g.addCard('Mountain', 0, Zone.battlefield);
      g.apply(CastAction(0, card, face: 1));
      target(g, [bears]);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, bears), Zone.hand);
    });

    test('fuse casts both halves from the hand, paying both costs, left half first', () {
      final g = empty();
      lands(g, 'Mountain', 2);
      lands(g, 'Plains', 1);
      final orn = g.addCard('Ornithopter', 1, Zone.battlefield);
      final anthem = g.addCard('Glorious Anthem', 1, Zone.battlefield);
      final card = g.addCard('Wear // Tear', 0, Zone.hand);
      expect(g.castFaces(0, card), [0, 1, 2]);
      g.apply(CastAction(0, card, face: 2));
      target(g, [orn]);
      target(g, [anthem]);
      expect(g.chars(card).name, 'Wear // Tear');
      expect(g.chars(card).manaValue, 3);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, orn), Zone.graveyard);
      expect(zoneOf(g, anthem), Zone.graveyard);
      expect(zoneOf(g, card), Zone.graveyard);
    });

    test('fuse needs both costs, and only works from the hand', () {
      final g = empty();
      lands(g, 'Mountain', 2);
      g.addCard('Ornithopter', 1, Zone.battlefield);
      g.addCard('Glorious Anthem', 1, Zone.battlefield);
      final card = g.addCard('Wear // Tear', 0, Zone.hand);
      expect(g.legalActions(0).whereType<CastAction>().where((a) => a.id == card && a.face == 2), isEmpty);
      final g2 = empty();
      final inYard = g2.addCard('Wear // Tear', 0, Zone.graveyard);
      expect(g2.castFaces(0, inYard), isNot(contains(2)));
    });

    test('aftermath: the first half from the hand, the second only from the graveyard, then exiled', () {
      final g = empty();
      lands(g, 'Mountain', 2);
      lands(g, 'Swamp', 4);
      final bears = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      final card = g.addCard('Cut // Ribbons', 0, Zone.hand);
      expect(g.castFaces(0, card), [0]);
      expect(() => g.apply(CastAction(0, card, face: 1)), throwsA(isA<GameError>()));
      g.apply(CastAction(0, card));
      target(g, [bears]);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, bears), Zone.graveyard);
      expect(zoneOf(g, card), Zone.graveyard);
      expect(g.castFaces(0, card), [1]);
      final casts = g.legalActions(0).whereType<CastAction>().where((a) => a.id == card).toList();
      expect(casts.map((a) => a.face), [1]);
      g.apply(CastAction(0, card, face: 1));
      answer(g, [2]); // X = 2
      pay(g);
      resolveAll(g);
      expect(g.state.player(1).life, 18);
      expect(zoneOf(g, card), Zone.exile);
    });
  });

  group('CR 712 modal double-faced cards', () {
    test('the back face can be played as a land, entering as that face', () {
      final g = empty();
      final card = g.addCard('Akoum Warrior // Akoum Teeth', 0, Zone.hand);
      expect(g.legalActions(0).whereType<PlayLandAction>().where((a) => a.id == card).map((a) => a.face), [1]);
      g.apply(PlayLandAction(0, card, face: 1));
      expect(zoneOf(g, card), Zone.battlefield);
      expect(g.chars(card).name, 'Akoum Teeth');
      expect(g.chars(card).isLand, isTrue);
      expect(g.state.obj(card).tapped, isTrue, reason: 'its back face enters tapped');
      expect(() => g.apply(PlayLandAction(0, g.addCard('Akoum Warrior // Akoum Teeth', 0, Zone.hand))), throwsA(isA<GameError>()), reason: 'the front is a creature');
    });

    test('the front face is cast as a spell and enters front face up; a pathway plays either side', () {
      final g = empty();
      lands(g, 'Mountain', 6);
      final card = g.addCard('Akoum Warrior // Akoum Teeth', 0, Zone.hand);
      expect(g.castFaces(0, card), [0]);
      g.apply(CastAction(0, card));
      pay(g);
      resolveAll(g);
      expect(g.chars(card).name, 'Akoum Warrior');
      expect(g.chars(card).isCreature, isTrue);
      final path = g.addCard('Barkchannel Pathway // Tidechannel Pathway', 0, Zone.hand);
      expect(g.legalActions(0).whereType<PlayLandAction>().where((a) => a.id == path).map((a) => a.face), [0, 1]);
      g.apply(PlayLandAction(0, path, face: 1));
      expect(g.chars(path).name, 'Tidechannel Pathway');
      expect(g.state.obj(path).tapped, isFalse);
    });

    test('a double-faced card in the hand has only its front face\'s characteristics', () {
      final g = empty();
      final card = g.addCard('Kazandu Mammoth // Kazandu Valley', 0, Zone.hand);
      expect(g.chars(card).name, 'Kazandu Mammoth');
      expect(g.chars(card).manaValue, 3);
    });
  });

  group('CR 701.28 transform', () {
    test('a transformed permanent is the same object with its back face, and its front\'s mana value', () {
      final g = empty();
      final heir = g.addCard('Heir of Falkenrath // Heir to the Night', 0, Zone.battlefield);
      g.addCard('Grizzly Bears', 0, Zone.hand);
      g.state.obj(heir).counters['+1/+1'] = 1;
      final act = g.legalActions(0).whereType<ActivateAbilityAction>().firstWhere((a) => a.id == heir);
      g.apply(act);
      resolveAll(g);
      final c = g.chars(heir);
      expect(c.name, 'Heir to the Night');
      expect(c.has(Kw.flying), isTrue);
      expect(c.power, 4); // 3/2 plus its +1/+1 counter, which stays
      expect(c.manaValue, 2);
      expect(g.state.obj(heir).zone, Zone.battlefield);
    });

    test('a transformed permanent that leaves the battlefield is its front face again', () {
      final g = empty();
      lands(g, 'Mountain', 1);
      final heir = g.addCard('Heir of Falkenrath // Heir to the Night', 0, Zone.battlefield);
      g.addCard('Grizzly Bears', 0, Zone.hand);
      g.apply(g.legalActions(0).whereType<ActivateAbilityAction>().firstWhere((a) => a.id == heir));
      resolveAll(g);
      expect(g.chars(heir).name, 'Heir to the Night');
      final shock = g.addCard('Shock', 0, Zone.hand);
      g.apply(CastAction(0, shock));
      target(g, [heir]);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, heir), Zone.graveyard);
      expect(g.chars(heir).name, 'Heir of Falkenrath');
    });

    test('only transforming double-faced cards transform', () {
      final g = empty();
      final card = g.addCard('Kazandu Mammoth // Kazandu Valley', 0, Zone.battlefield);
      final parsed = OracleParser.parse(layouts()['Heir of Falkenrath // Heir to the Night']!);
      expect(parsed.supported, isTrue);
      expect(g.state.obj(card).face, 0);
      expect(g.castFaces(0, card), [0]);
    });
  });

  test('bots play decks of multi-faced cards to the end, and the replay matches', () {
    final db = layouts();
    List<String> deck(List<String> spells, String land) => [for (var i = 0; i < 2; i++) ...spells, for (var i = 0; i < 40 - spells.length * 2; i++) land];
    final a = deck(['Embereth Shieldbreaker // Battle Display', 'Dead // Gone', 'Cut // Ribbons', 'Akoum Warrior // Akoum Teeth', 'Heir of Falkenrath // Heir to the Night', 'Shock', 'Vampire Nighthawk', 'Disruptive Stormbrood // Petty Revenge'], 'Mountain');
    final b = deck(['Wear // Tear', 'Far // Away', 'Kazandu Mammoth // Kazandu Valley', 'Barkchannel Pathway // Tidechannel Pathway', 'Curious Pair // Treats to Share', 'Grizzly Bears', 'Cloistered Youth // Unholy Fiend', 'Ornithopter'], 'Forest');
    var otherFaces = 0;
    for (final seed in [3, 4, 5]) {
      final g = Game(db, players: ['Alice', 'Bob'], seed: seed);
      g.apply(StartAction([a, b]));
      final done = runBots(g, [Bot(0, seed: seed), Bot(1, seed: seed + 10)]);
      expect(done, isTrue, reason: 'seed $seed should finish');
      final r = Game(db, players: ['Alice', 'Bob'], seed: seed);
      for (final x in g.actions) {
        r.apply(x);
      }
      expect(r.fingerprint, g.fingerprint);
      final j = Game(db, players: ['Alice', 'Bob'], seed: seed);
      for (final x in g.actions) {
        j.apply(GameAction.fromJson(jsonDecode(jsonEncode(x.toJson())) as Map<String, dynamic>));
      }
      expect(j.fingerprint, g.fingerprint);
      otherFaces += g.actions.where((x) => (x is CastAction && x.face != 0) || (x is PlayLandAction && x.face != 0)).length;
    }
    expect(otherFaces, greaterThan(0), reason: 'the bots should use second faces and halves');
  });
}
