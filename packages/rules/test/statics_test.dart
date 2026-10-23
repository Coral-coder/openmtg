// Static abilities, restrictions and casting mechanics, on cards from test/fixtures/statics.json
// (test/fixtures/statics-names.txt, cut from the full database by tools/make_fixture.py).
import 'dart:convert';
import 'dart:io';

import 'package:rules/rules.dart';
import 'package:test/test.dart';

import 'helpers.dart';

CardDatabase? _db;
CardDatabase statics() => _db ??= CardDatabase.fromJson(jsonDecode(File('test/fixtures/statics.json').readAsStringSync()) as Map<String, dynamic>);

Game game({int active = 0}) => empty(db: statics(), active: active);

void lands(Game g, String name, int n, {int owner = 0}) {
  for (var i = 0; i < n; i++) {
    g.addCard(name, owner, Zone.battlefield);
  }
}

/// Answers whatever is pending for its player with [a] while it's of [kind].
void answerIf(Game g, DecisionKind kind, List<int> a) {
  if (g.state.pending?.decision.kind == kind) answer(g, a);
}

void main() {
  group('restrictions (CR 508–509)', () {
    test("an Aura's \"doesn't untap\" reaches the enchanted creature", () {
      final g = game();
      final bears = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      final bonds = g.addCard('Bonds of Quicksilver', 0, Zone.battlefield);
      g.state.obj(bonds).attachedTo = bears;
      g.settle();
      expect(g.chars(bears).has(Kw.doesntUntap), isTrue);
    });

    test('can block only creatures with flying', () {
      final g = game();
      final percher = g.addCard('Battlefield Percher', 1, Zone.battlefield);
      final bears = g.addCard('Grizzly Bears', 0, Zone.battlefield);
      final hawk = g.addCard('Suntail Hawk', 0, Zone.battlefield);
      expect(g.canBlock(percher, bears), isFalse);
      expect(g.canBlock(percher, hawk), isTrue);
    });

    test('a control-changing Aura gives its controller the creature (layer 2)', () {
      final g = game();
      final bears = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      final abduction = g.addCard('Abduction', 0, Zone.battlefield);
      g.state.obj(abduction).attachedTo = bears;
      g.settle();
      expect(g.chars(bears).controller, 0);
    });

    test("can't attack unless the defending player controls an Island", () {
      final g = game();
      g.addCard('Armored Galleon', 0, Zone.battlefield);
      g.setStep(TurnStep.beginCombat);
      g.apply(PassAction(0));
      g.apply(PassAction(1));
      expect(g.state.pending?.decision.kind == DecisionKind.attackers, isFalse, reason: 'nothing can attack');
      final g2 = game();
      final galleon2 = g2.addCard('Armored Galleon', 0, Zone.battlefield);
      g2.addCard('Island', 1, Zone.battlefield);
      g2.setStep(TurnStep.beginCombat);
      g2.apply(PassAction(0));
      g2.apply(PassAction(1));
      expect(g2.state.pending!.decision.options, contains(galleon2));
    });

    test("can't attack alone", () {
      final g = game();
      final construct = g.addCard('Bonded Construct', 0, Zone.battlefield);
      final bears = g.addCard('Grizzly Bears', 0, Zone.battlefield);
      g.setStep(TurnStep.beginCombat);
      g.apply(PassAction(0));
      g.apply(PassAction(1));
      expect(() => answer(g, [construct, playerEntity(1)]), throwsA(isA<GameError>()));
      answer(g, [construct, playerEntity(1), bears, playerEntity(1)]);
      expect(g.state.obj(construct).attacking, isNotNull);
    });

    test("can't be blocked by more than one creature", () {
      final g = game();
      final boar = g.addCard('Bristling Boar', 0, Zone.battlefield);
      final b1 = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      final b2 = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      g.setStep(TurnStep.beginCombat);
      g.apply(PassAction(0));
      g.apply(PassAction(1));
      answer(g, [boar, playerEntity(1)]);
      passToDecision(g, DecisionKind.blockers);
      expect(() => answer(g, [b1, boar, b2, boar]), throwsA(isA<GameError>()));
      answer(g, [b1, boar]);
      expect(g.state.obj(b1).blocking, [boar]);
    });

    test("has first strike as long as it's attacking", () {
      final g = game();
      final celebrant = g.addCard('Blood Petal Celebrant', 0, Zone.battlefield);
      expect(g.chars(celebrant).has(Kw.firstStrike), isFalse);
      g.setStep(TurnStep.beginCombat);
      g.apply(PassAction(0));
      g.apply(PassAction(1));
      answer(g, [celebrant, playerEntity(1)]);
      expect(g.chars(celebrant).has(Kw.firstStrike), isTrue);
    });
  });

  group('lands entering', () {
    test('shockland: pay 2 life or it enters tapped', () {
      final g = game();
      final a = g.addCard('Blood Crypt', 0, Zone.hand);
      g.apply(PlayLandAction(0, a));
      expect(g.state.pending!.decision.kind, DecisionKind.yesNo);
      answer(g, [1]);
      expect(life(g, 0), 18);
      expect(g.state.obj(a).tapped, isFalse);
      final g2 = game();
      final b = g2.addCard('Blood Crypt', 0, Zone.hand);
      g2.apply(PlayLandAction(0, b));
      answer(g2, [0]);
      expect(life(g2, 0), 20);
      expect(g2.state.obj(b).tapped, isTrue);
    });

    test('enters tapped unless you control two or more other lands', () {
      final g = game();
      final a = g.addCard('Deathcap Glade', 0, Zone.hand);
      g.apply(PlayLandAction(0, a));
      expect(g.state.obj(a).tapped, isTrue);
      final g2 = game();
      lands(g2, 'Forest', 2);
      final b = g2.addCard('Deathcap Glade', 0, Zone.hand);
      g2.apply(PlayLandAction(0, b));
      expect(g2.state.obj(b).tapped, isFalse);
    });

    test('enters tapped with two charge counters', () {
      final g = game();
      final crag = g.addCard('Vivid Crag', 0, Zone.hand);
      g.apply(PlayLandAction(0, crag));
      expect(g.state.obj(crag).tapped, isTrue);
      expect(g.state.obj(crag).counters['charge'], 2);
    });
  });

  test('activate only during your turn, before attackers are declared', () {
    final g = game();
    final vet = g.addCard('Alaborn Veteran', 0, Zone.battlefield);
    g.addCard('Grizzly Bears', 0, Zone.battlefield);
    final act = ActivateAbilityAction(0, vet, 0);
    expect(g.whyNot(act), isNull);
    g.setStep(TurnStep.declareAttackers);
    expect(g.whyNot(act), isNotNull);
    final g2 = game(active: 1);
    final vet2 = g2.addCard('Alaborn Veteran', 0, Zone.battlefield);
    g2.setStep(TurnStep.main1, priority: 0);
    expect(g2.whyNot(ActivateAbilityAction(0, vet2, 0)), isNotNull, reason: "not on an opponent's turn");
  });

  group('casting help (CR 702.51, 702.66)', () {
    test('convoke: creatures pay for the rest automatically', () {
      final g = game();
      lands(g, 'Forest', 4);
      final creatures = [for (var i = 0; i < 5; i++) g.addCard(i < 2 ? 'Grizzly Bears' : 'Hill Giant', 0, Zone.battlefield)];
      final el = g.addCard('Arboretum Elemental', 0, Zone.hand);
      expect(g.whyNot(CastAction(0, el)), isNull);
      g.apply(CastAction(0, el));
      answerIf(g, DecisionKind.cards, []);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, el), Zone.battlefield);
      expect(creatures.every((c) => g.state.obj(c).tapped), isTrue);
    });

    test('convoke: only as many as needed', () {
      final g = game();
      lands(g, 'Forest', 8);
      final bears = g.addCard('Grizzly Bears', 0, Zone.battlefield);
      final el = g.addCard('Arboretum Elemental', 0, Zone.hand);
      g.apply(CastAction(0, el));
      answerIf(g, DecisionKind.cards, []);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, el), Zone.battlefield);
      expect(g.state.obj(bears).tapped, isTrue, reason: 'eight Forests pay eight of nine');
    });

    test('delve: exiling graveyard cards pays generic mana', () {
      final g = game();
      g.addCard('Swamp', 0, Zone.battlefield);
      final gy = [for (var i = 0; i < 6; i++) g.addCard('Grizzly Bears', 0, Zone.graveyard)];
      final angler = g.addCard('Gurmag Angler', 0, Zone.hand);
      expect(g.whyNot(CastAction(0, angler)), isNull);
      g.apply(CastAction(0, angler));
      answerIf(g, DecisionKind.cards, []);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, angler), Zone.battlefield);
      expect(gy.every((c) => zoneOf(g, c) == Zone.exile), isTrue);
    });
  });

  group('spell keywords', () {
    test('storm copies the spell once per earlier spell this turn (CR 702.40)', () {
      final g = game();
      lands(g, 'Mountain', 1);
      lands(g, 'Plains', 3);
      final bears = g.addCard('Grizzly Bears', 0, Zone.battlefield);
      final shock = g.addCard('Shock', 0, Zone.hand);
      final giant = g.addCard('Hill Giant', 1, Zone.battlefield);
      g.apply(CastAction(0, shock));
      target(g, [giant]);
      pay(g);
      resolveAll(g);
      final steel = g.addCard('Astral Steel', 0, Zone.hand);
      g.apply(CastAction(0, steel));
      target(g, [bears]);
      pay(g);
      resolveAll(g);
      expect(g.chars(bears).power, 4, reason: 'the spell and one copy: +2/+4');
      expect(g.chars(bears).toughness, 6);
    });

    test('cascade casts the first cheaper nonland card free (CR 702.85)', () {
      final g = game();
      lands(g, 'Forest', 7);
      final giant = g.addCard('Hill Giant', 0, Zone.library);
      final forest = g.addCard('Forest', 0, Zone.library);
      // Library top is index 0: Forest, then Hill Giant.
      g.state.player(0).library
        ..remove(forest)
        ..insert(0, forest);
      final alt = g.addCard('Annoyed Altisaur', 0, Zone.hand);
      g.apply(CastAction(0, alt));
      pay(g);
      for (var i = 0; i < 20 && zoneOf(g, giant) != Zone.battlefield; i++) {
        if (g.state.pending != null) {
          answer(g, g.state.pending!.decision.kind == DecisionKind.yesNo ? [1] : g.defaultAnswer(g.state.pending!.decision));
        } else if (g.state.stack.isNotEmpty) {
          g.apply(PassAction(g.state.priority!));
        }
      }
      resolveAll(g);
      expect(zoneOf(g, giant), Zone.battlefield);
      expect(zoneOf(g, alt), Zone.battlefield);
      expect(zoneOf(g, forest), Zone.library, reason: 'the rest go to the bottom');
    });

    test('rebound: exiled, then cast free at the next upkeep (CR 702.88)', () {
      final g = game();
      lands(g, 'Plains', 2);
      final bears = g.addCard('Grizzly Bears', 0, Zone.battlefield);
      final m = g.addCard('Artful Maneuver', 0, Zone.hand);
      for (var i = 0; i < 3; i++) {
        g.addCard('Plains', 0, Zone.library);
        g.addCard('Plains', 1, Zone.library);
      }
      g.apply(CastAction(0, m));
      target(g, [bears]);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, m), Zone.exile);
      // Through Bob's turn to Alice's next upkeep.
      passTo(g, TurnStep.cleanup);
      for (var i = 0; i < 400 && zoneOf(g, m) == Zone.exile; i++) {
        final pd = g.state.pending;
        if (pd != null) {
          answer(g, pd.decision.kind == DecisionKind.yesNo ? [1] : (pd.decision.kind == DecisionKind.targets ? [bears] : g.defaultAnswer(pd.decision)));
        } else {
          g.apply(PassAction(g.state.priority!));
        }
      }
      expect(g.state.active, 0);
      expect(g.state.step, TurnStep.upkeep);
      resolveAll(g);
      expect(zoneOf(g, m), Zone.graveyard, reason: 'cast from exile, so no second rebound');
      expect(g.chars(bears).power, 4);
    });

    test('buyback returns the spell to hand (CR 702.27)', () {
      final g = game();
      lands(g, 'Plains', 5);
      final bonds = g.addCard('Bonds of Quicksilver', 1, Zone.battlefield);
      g.state.obj(bonds).attachedTo = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      final allay = g.addCard('Allay', 0, Zone.hand);
      g.apply(CastAction(0, allay));
      expect(g.state.pending!.decision.prompt, startsWith('Pay buyback'));
      answer(g, [1]); // pay buyback
      target(g, [bonds]);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, bonds), Zone.graveyard);
      expect(zoneOf(g, allay), Zone.hand);
    });
  });

  test('flanking: a blocker without flanking gets -1/-1 (CR 702.25)', () {
    final g = game();
    final cav = g.addCard('Benalish Cavalry', 0, Zone.battlefield);
    final giant = g.addCard('Hill Giant', 1, Zone.battlefield);
    g.setStep(TurnStep.beginCombat);
    g.apply(PassAction(0));
    g.apply(PassAction(1));
    answer(g, [cav, playerEntity(1)]);
    passToDecision(g, DecisionKind.blockers);
    answer(g, [giant, cav]);
    resolveAll(g);
    expect(g.chars(giant).power, 2);
    expect(g.chars(giant).toughness, 2);
  });

  group('upkeep costs', () {
    /// Starts on Bob's turn and passes to Alice's upkeep, answering [yes] to payment questions.
    void toMyUpkeep(Game g, {int yes = 1}) {
      for (var i = 0; i < 400; i++) {
        final pd = g.state.pending;
        if (pd != null) {
          answer(g, pd.decision.kind == DecisionKind.yesNo ? [yes] : g.defaultAnswer(pd.decision));
          continue;
        }
        // Stop once Alice's upkeep triggers have resolved (before her draw: no library here).
        if (g.state.active == 0 && g.state.step == TurnStep.upkeep && g.state.stack.isEmpty) return;
        g.apply(PassAction(g.state.priority!));
      }
    }

    test('echo: pay or sacrifice at the first upkeep (CR 702.30)', () {
      final g = game(active: 1);
      final riders = g.addCard('Avalanche Riders', 0, Zone.battlefield);
      g.state.obj(riders).echoDue = true;
      toMyUpkeep(g);
      expect(zoneOf(g, riders), Zone.graveyard, reason: "can't pay {3}{R}");
      final g2 = game(active: 1);
      lands(g2, 'Mountain', 4);
      final r2 = g2.addCard('Avalanche Riders', 0, Zone.battlefield);
      g2.state.obj(r2).echoDue = true;
      toMyUpkeep(g2);
      expect(zoneOf(g2, r2), Zone.battlefield);
      expect(g2.state.obj(r2).echoDue, isFalse);
    });

    test('fading and vanishing remove counters; the last one sacrifices', () {
      final g = game(active: 1);
      final hydra = g.addCard('Ancient Hydra', 0, Zone.battlefield);
      g.state.obj(hydra).counters['fade'] = 2;
      final calc = g.addCard('Calciderm', 0, Zone.battlefield);
      g.state.obj(calc).counters['time'] = 1;
      toMyUpkeep(g);
      expect(g.state.obj(hydra).counters['fade'], 1);
      expect(zoneOf(g, calc), Zone.graveyard);
    });

    test('cumulative upkeep: an age counter, then pay for each (CR 702.24)', () {
      final g = game(active: 1);
      lands(g, 'Forest', 2);
      final wolves = g.addCard('Arctic Wolves', 0, Zone.battlefield);
      toMyUpkeep(g);
      expect(zoneOf(g, wolves), Zone.battlefield);
      expect(g.state.obj(wolves).counters['age'], 1);
      final g2 = game(active: 1);
      final w2 = g2.addCard('Arctic Wolves', 0, Zone.battlefield);
      toMyUpkeep(g2);
      expect(zoneOf(g2, w2), Zone.graveyard);
    });

    test('a creature that enters with echo is due', () {
      final g = game();
      lands(g, 'Mountain', 4);
      final riders = g.addCard('Avalanche Riders', 0, Zone.hand);
      g.apply(CastAction(0, riders));
      pay(g);
      resolveAll(g);
      expect(g.state.obj(riders).echoDue, isTrue);
    });
  });
}
