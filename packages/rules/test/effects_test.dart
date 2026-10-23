// Effect sentences: energy (CR 122.1), paying while resolving, clash (CR 701.23), amass
// (CR 701.47), bolster (CR 701.39), learn (CR 701.48), adapt (CR 701.46), extra turns (CR 500.7),
// untap skipping, end-step delayed effects (CR 603.7), activation windows (CR 602.5d), tokens with
// abilities, chosen creature types, and filter grammar ("nonartifact, nonblack").
// Cards are real ones from test/fixtures/effects.json (tools/make_fixture.py).
import 'dart:convert';
import 'dart:io';

import 'package:rules/rules.dart';
import 'package:test/test.dart';

import 'helpers.dart';

CardDatabase? _db;
CardDatabase effectsDb() => _db ??= CardDatabase.fromJson(jsonDecode(File('test/fixtures/effects.json').readAsStringSync()) as Map<String, dynamic>);

/// An empty game whose libraries have a few lands, so turns can pass without decking.
Game game({int active = 0}) {
  final g = empty(db: effectsDb(), active: active);
  for (var p = 0; p < 2; p++) {
    for (var i = 0; i < 8; i++) {
      g.addCard('Island', p, Zone.library);
    }
  }
  return g;
}

void lands(Game g, int p, String name, int n) {
  for (var i = 0; i < n; i++) {
    g.addCard(name, p, Zone.battlefield);
  }
}

/// Passes priority until the stack is empty, answering decisions with [answers] (by kind; the
/// default answer otherwise).
void settle(Game g, {Map<DecisionKind, List<int>> answers = const {}}) {
  for (var i = 0; i < 100; i++) {
    final pd = g.state.pending;
    if (pd != null) {
      answer(g, answers[pd.decision.kind] ?? g.defaultAnswer(pd.decision));
      continue;
    }
    if (g.state.stack.isEmpty) return;
    g.apply(PassAction(g.state.priority!));
  }
}

/// Passes (declining attacks and blocks, answering other decisions by default) to [step].
void advanceTo(Game g, TurnStep step, {int? turn}) {
  for (var i = 0; i < 400 && !g.state.over; i++) {
    final pd = g.state.pending;
    if (pd != null) {
      answer(g, g.defaultAnswer(pd.decision));
      continue;
    }
    if (g.state.step == step && (turn == null || g.state.turn == turn) && g.state.stack.isEmpty) return;
    g.apply(PassAction(g.state.priority!));
  }
}

int abilityIndex(Game g, int id, String startsWith) => g.chars(id).abilities.indexWhere((a) => a.text.toLowerCase().startsWith(startsWith));

void main() {
  group('energy', () {
    test('"you get {E}{E}" gives energy; "you may pay {E}{E}. If you do" spends it', () {
      final g = game();
      lands(g, 0, 'Mountain', 2);
      final chaser = g.addCard('Aether Chaser', 0, Zone.hand);
      g.apply(CastAction(0, chaser));
      pay(g);
      settle(g);
      expect(g.state.player(0).energy, 2);
      g.state.obj(chaser).controlSince = 0; // no longer summoning sick
      g.setStep(TurnStep.beginCombat);
      g.apply(PassAction(0));
      g.apply(PassAction(1));
      answer(g, [chaser, playerEntity(1)]);
      settle(g, answers: {DecisionKind.yesNo: [1]});
      expect(g.state.player(0).energy, 0);
      expect(g.state.battlefield.where((id) => g.chars(id).name == 'Servo'), hasLength(1));
    });

    test('without enough energy, "if you do" does nothing', () {
      final g = game();
      final chaser = g.addCard('Aether Chaser', 0, Zone.battlefield);
      g.state.player(0).energy = 1;
      g.setStep(TurnStep.beginCombat);
      g.apply(PassAction(0));
      g.apply(PassAction(1));
      answer(g, [chaser, playerEntity(1)]);
      settle(g, answers: {DecisionKind.yesNo: [1]});
      expect(g.state.player(0).energy, 1);
      expect(g.state.battlefield.where((id) => g.chars(id).name == 'Servo'), isEmpty);
    });
  });

  group('clash', () {
    test('you win with the greater mana value and get the reward', () {
      final g = game();
      lands(g, 0, 'Mountain', 2);
      g.addCard('Hill Giant', 0, Zone.library); // mana value 4
      g.addCard('Grizzly Bears', 1, Zone.library); // mana value 2
      final boggart = g.addCard('Adder-Staff Boggart', 0, Zone.hand);
      g.apply(CastAction(0, boggart));
      pay(g);
      settle(g, answers: {DecisionKind.option: [0]});
      expect(g.state.obj(boggart).counters['+1/+1'], 1);
    });

    test('a lower or equal mana value loses; a card may go to the bottom', () {
      final g = game();
      lands(g, 0, 'Mountain', 2);
      final bears = g.addCard('Grizzly Bears', 0, Zone.library);
      g.addCard('Mountain', 0, Zone.library);
      g.addCard('Hill Giant', 1, Zone.library);
      final boggart = g.addCard('Adder-Staff Boggart', 0, Zone.hand);
      final top = g.state.player(0).library.first;
      g.apply(CastAction(0, boggart));
      pay(g);
      settle(g, answers: {DecisionKind.option: [1]});
      expect(g.state.obj(boggart).counters['+1/+1'] ?? 0, 0);
      expect(g.state.player(0).library.last, top, reason: 'put on the bottom');
      expect(g.state.player(0).library, contains(bears));
    });
  });

  group('amass and bolster', () {
    test('amass creates a 0/0 Army once, then grows it', () {
      final g = game();
      final corsairs = g.addCard('Corsairs of Umbar', 0, Zone.battlefield);
      for (var turn = 0; turn < 2; turn++) {
        g.setStep(TurnStep.beginCombat);
        g.apply(PassAction(0));
        g.apply(PassAction(1));
        answer(g, [corsairs, playerEntity(1)]);
        advanceTo(g, TurnStep.endCombat);
        settle(g);
        for (final id in g.state.battlefield) {
          g.state.obj(id).tapped = false;
        }
      }
      final armies = [for (final id in g.state.battlefield) if (g.chars(id).hasSubtype('Army')) id];
      expect(armies, hasLength(1));
      expect(g.state.obj(armies.first).counters['+1/+1'], 6);
      expect(g.chars(armies.first).hasSubtype('Orc'), isTrue);
    });

    test('bolster puts counters on the creature with the least toughness', () {
      final g = game();
      lands(g, 0, 'Plains', 2);
      final giant = g.addCard('Hill Giant', 0, Zone.battlefield);
      final bears = g.addCard('Grizzly Bears', 0, Zone.battlefield);
      final spell = g.addCard('Abzan Advantage', 0, Zone.hand);
      g.apply(CastAction(0, spell));
      target(g, [playerEntity(1)]);
      pay(g);
      settle(g);
      expect(g.state.obj(bears).counters['+1/+1'], 1);
      expect(g.state.obj(giant).counters['+1/+1'] ?? 0, 0);
    });
  });

  group('choosing without targeting', () {
    test('"you may put a land card from your hand onto the battlefield"', () {
      final g = game();
      lands(g, 0, 'Forest', 2);
      final orni = g.addCard('Ornithopter', 1, Zone.battlefield);
      final forest = g.addCard('Forest', 0, Zone.hand);
      final bond = g.addCard('Broken Bond', 0, Zone.hand);
      g.apply(CastAction(0, bond));
      target(g, [orni]);
      pay(g);
      settle(g, answers: {DecisionKind.yesNo: [1]});
      expect(zoneOf(g, orni), Zone.graveyard);
      expect(zoneOf(g, forest), Zone.battlefield);
    });

    test('a chosen creature type: "creatures you control of the chosen type"', () {
      final g = game();
      lands(g, 0, 'Plains', 2);
      final bears = g.addCard('Grizzly Bears', 0, Zone.battlefield);
      final giant = g.addCard('Hill Giant', 0, Zone.battlefield);
      final spell = g.addCard('And They Shall Know No Fear', 0, Zone.hand);
      g.apply(CastAction(0, spell));
      pay(g);
      final d = g.state.pending?.decision;
      if (d == null) settle(g);
      final pd = g.state.pending!.decision;
      expect(pd.kind, DecisionKind.option);
      answer(g, [pd.labels.indexOf('Bear')]);
      settle(g);
      expect(g.chars(bears).power, 3);
      expect(g.chars(bears).has(Kw.indestructible), isTrue);
      expect(g.chars(giant).power, 3, reason: 'not a Bear');
    });
  });

  group('untap and turns', () {
    test("doesn't untap during your next untap step", () {
      final g = game();
      lands(g, 0, 'Plains', 3);
      final elite = g.addCard('Arbalest Elite', 0, Zone.battlefield);
      // No attacking or blocking creature to target yet.
      expect(g.whyNot(ActivateAbilityAction(0, elite, abilityIndex(g, elite, '{2}{w}'))), isNotNull);
      final g2 = game(active: 1);
      lands(g2, 0, 'Plains', 3);
      final elite2 = g2.addCard('Arbalest Elite', 0, Zone.battlefield);
      final bears = g2.addCard('Grizzly Bears', 1, Zone.battlefield);
      g2.setStep(TurnStep.beginCombat);
      g2.apply(PassAction(1));
      g2.apply(PassAction(0));
      answer(g2, [bears, playerEntity(0)]);
      advanceTo(g2, TurnStep.declareAttackers);
      g2.apply(PassAction(1));
      g2.apply(ActivateAbilityAction(0, elite2, abilityIndex(g2, elite2, '{2}{w}')));
      target(g2, [bears]);
      pay(g2);
      settle(g2);
      expect(zoneOf(g2, bears), Zone.graveyard);
      expect(g2.state.obj(elite2).tapped, isTrue);
      advanceTo(g2, TurnStep.main1, turn: 3);
      expect(g2.state.active, 0);
      expect(g2.state.obj(elite2).tapped, isTrue, reason: 'skipped this untap step');
      advanceTo(g2, TurnStep.main1, turn: 5);
      expect(g2.state.obj(elite2).tapped, isFalse, reason: 'only the next one');
    });

    test('take an extra turn after this one', () {
      final g = game();
      lands(g, 0, 'Island', 5);
      final spell = g.addCard('Capture of Jingzhou', 0, Zone.hand);
      g.apply(CastAction(0, spell));
      pay(g);
      settle(g);
      advanceTo(g, TurnStep.main1, turn: 3);
      expect(g.state.active, 0, reason: 'the extra turn');
      advanceTo(g, TurnStep.main1, turn: 4);
      expect(g.state.active, 1);
    });
  });

  group('end-step delayed effects', () {
    test('a token with "sacrifice it at the beginning of the next end step"', () {
      final g = game();
      lands(g, 0, 'Mountain', 3);
      final dead = g.addCard('Balduvian Dead', 0, Zone.battlefield);
      g.addCard('Grizzly Bears', 0, Zone.graveyard);
      g.apply(ActivateAbilityAction(0, dead, abilityIndex(g, dead, '{2}{r}')));
      settle(g);
      final token = g.state.battlefield.firstWhere((id) => g.chars(id).name.contains('Graveborn'));
      expect(g.chars(token).has(Kw.haste), isTrue);
      advanceTo(g, TurnStep.end);
      settle(g);
      expect(g.state.objOrNull(token)?.zone == Zone.battlefield, isFalse);
    });

    test('Flickerwisp: the exiled card returns at the next end step', () {
      final g = game();
      lands(g, 0, 'Plains', 3);
      final bears = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      final wisp = g.addCard('Flickerwisp', 0, Zone.hand);
      g.apply(CastAction(0, wisp));
      pay(g);
      settle(g, answers: {DecisionKind.targets: [bears]});
      expect(zoneOf(g, bears), Zone.exile);
      advanceTo(g, TurnStep.end);
      settle(g);
      expect(zoneOf(g, bears), Zone.battlefield);
      expect(g.chars(bears).controller, 1);
    });

    test('Daring Piracy: the Pirate is exiled at the next end step', () {
      final g = game();
      g.addCard('Daring Piracy', 0, Zone.battlefield);
      g.setStep(TurnStep.main1);
      advanceTo(g, TurnStep.beginCombat);
      settle(g);
      final pirate = g.state.battlefield.firstWhere((id) => g.chars(id).name == 'Pirate');
      advanceTo(g, TurnStep.end);
      settle(g);
      expect(g.state.objOrNull(pirate)?.zone == Zone.battlefield, isFalse);
    });
  });

  group('activation windows', () {
    test('"during your turn, before attackers are declared"', () {
      final g = game();
      final vet = g.addCard('Alaborn Veteran', 0, Zone.battlefield);
      final i = abilityIndex(g, vet, '{t}');
      expect(g.whyNot(ActivateAbilityAction(0, vet, i)), isNull);
      g.setStep(TurnStep.declareBlockers);
      expect(g.whyNot(ActivateAbilityAction(0, vet, i)), isNotNull);
      final g2 = game(active: 1);
      final vet2 = g2.addCard('Alaborn Veteran', 0, Zone.battlefield);
      g2.setStep(TurnStep.main1, priority: 0);
      expect(g2.whyNot(ActivateAbilityAction(0, vet2, i)), isNotNull, reason: "opponent's turn");
    });
  });

  group('tokens', () {
    test('a token with a quoted ability ("This token can\'t block.")', () {
      final g = game();
      lands(g, 0, 'Mountain', 4);
      final pack = g.addCard('Edgewall Pack', 0, Zone.hand);
      g.apply(CastAction(0, pack));
      pay(g);
      settle(g);
      final rat = g.state.battlefield.firstWhere((id) => g.chars(id).name == 'Rat');
      final bears = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      expect(g.canBlock(rat, bears), isFalse);
    });

    test('"It has …" adds the ability to the created token (Eldrazi Scion)', () {
      final g = game();
      lands(g, 1, 'Island', 3);
      lands(g, 0, 'Forest', 2);
      final bears = g.addCard('Grizzly Bears', 0, Zone.hand);
      final spell = g.addCard('Abstruse Interference', 1, Zone.hand);
      g.apply(CastAction(0, bears));
      pay(g);
      g.apply(CastAction(1, spell));
      target(g, [bears]);
      pay(g);
      settle(g, answers: {DecisionKind.option: [0]});
      expect(zoneOf(g, bears), Zone.graveyard, reason: "Alice didn't pay {1}");
      final scion = g.state.battlefield.firstWhere((id) => g.chars(id).name == 'Eldrazi Scion');
      expect(g.chars(scion).controller, 1);
      expect(g.chars(scion).abilities.whereType<ManaAbility>(), hasLength(1));
    });

    test('a Lander token fetches a basic land tapped', () {
      final g = game();
      lands(g, 0, 'Swamp', 2);
      final prospector = g.addCard('Beamsaw Prospector', 0, Zone.battlefield);
      final forest = g.addCard('Forest', 0, Zone.library);
      g.destroyForTest(prospector);
      settle(g);
      final lander = g.state.battlefield.firstWhere((id) => g.chars(id).name == 'Lander');
      g.apply(ActivateAbilityAction(0, lander, 0));
      pay(g);
      settle(g, answers: {DecisionKind.cards: [forest]});
      expect(zoneOf(g, forest), Zone.battlefield);
      expect(g.state.obj(forest).tapped, isTrue);
      expect(g.state.objOrNull(lander)?.zone == Zone.battlefield, isFalse);
    });
  });

  group('spells', () {
    test('countered and exiled ("exile it instead of putting it into its owner\'s graveyard")', () {
      final g = game();
      lands(g, 1, 'Island', 7);
      lands(g, 0, 'Forest', 2);
      final bears = g.addCard('Grizzly Bears', 0, Zone.hand);
      final spell = g.addCard('Assert Authority', 1, Zone.hand);
      g.apply(CastAction(0, bears));
      pay(g);
      g.apply(CastAction(1, spell));
      target(g, [bears]);
      pay(g);
      settle(g);
      expect(zoneOf(g, bears), Zone.exile);
    });

    test('learn: discard a card to draw a card', () {
      final g = game();
      lands(g, 0, 'Island', 2);
      final bears = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      final junk = g.addCard('Hill Giant', 0, Zone.hand);
      final drawn = g.addCard('Mountain', 0, Zone.library);
      final spell = g.addCard('Arcane Subtraction', 0, Zone.hand);
      g.apply(CastAction(0, spell));
      target(g, [bears]);
      pay(g);
      settle(g, answers: {DecisionKind.yesNo: [1], DecisionKind.cards: [junk]});
      expect(zoneOf(g, junk), Zone.graveyard);
      expect(zoneOf(g, drawn), Zone.hand);
      expect(g.chars(bears).power, -2);
    });

    test('Terror: "nonartifact, nonblack creature"', () {
      final g = game();
      lands(g, 0, 'Swamp', 2);
      final orni = g.addCard('Ornithopter', 1, Zone.battlefield);
      final bears = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      final terror = g.addCard('Terror', 0, Zone.hand);
      g.apply(CastAction(0, terror));
      // The Ornithopter isn't a legal target, so the Bears are chosen without asking.
      expect(g.state.pending?.decision.kind, isNot(DecisionKind.targets));
      pay(g);
      settle(g);
      expect(zoneOf(g, bears), Zone.graveyard);
      expect(zoneOf(g, orni), Zone.battlefield);
    });

    test('adapt adds counters only while it has none', () {
      final g = game();
      lands(g, 0, 'Forest', 4);
      lands(g, 0, 'Island', 4);
      final m = g.addCard('Aeromunculus', 0, Zone.battlefield);
      final i = abilityIndex(g, m, '{2}{g}{u}');
      for (var k = 0; k < 2; k++) {
        g.apply(ActivateAbilityAction(0, m, i));
        pay(g);
        settle(g);
      }
      expect(g.state.obj(m).counters['+1/+1'], 1);
    });
  });

  test('a sliver grants its quoted ability ("This creature gets +0/+1")', () {
    final g = game();
    final sliver = g.addCard('Armor Sliver', 0, Zone.battlefield);
    expect(g.chars(sliver).abilities.whereType<ActivatedAbility>(), isNotEmpty);
  });

  test('every card in the fixture parses but Brokers Confluence (phasing)', () {
    for (final c in effectsDb().cards) {
      final p = OracleParser.parse(c);
      expect(p.supported, c.name != 'Brokers Confluence', reason: '${c.name}: ${p.unsupported}');
    }
  });
}
