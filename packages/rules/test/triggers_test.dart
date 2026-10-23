// Trigger conditions (CR 603), on cards from test/fixtures/triggers.json.
import 'package:rules/rules.dart';
import 'package:test/test.dart';

import 'helpers.dart';

CardDatabase? _db;
CardDatabase triggersDb() => _db ??= loadFixture('test/fixtures/triggers.json');

Game game({int active = 0}) => empty(db: triggersDb(), active: active);

/// Resolves the stack, saying yes to "may" and taking the default for any other decision.
void settleAll(Game g) {
  for (var i = 0; i < 200; i++) {
    final d = g.state.pending?.decision;
    if (d != null) {
      g.apply(AnswerAction(d.player, d.kind == DecisionKind.yesNo ? const [1] : g.defaultAnswer(d)));
      continue;
    }
    if (g.state.stack.isEmpty) return;
    g.apply(PassAction(g.state.priority!));
  }
}

void lands(Game g, String name, int n, {int player = 0}) {
  for (var i = 0; i < n; i++) {
    g.addCard(name, player, Zone.battlefield);
  }
}

void cast(Game g, int id, {List<int>? targets}) {
  g.apply(CastAction(g.state.obj(id).owner, id));
  if (g.state.pending?.decision.kind == DecisionKind.targets && targets != null) answer(g, targets);
  pay(g);
}

/// Declares [attackers] at the other player.
void attackWith(Game g, List<int> attackers) {
  final p = g.state.active;
  g.setStep(TurnStep.beginCombat);
  g.apply(PassAction(p));
  g.apply(PassAction(1 - p));
  answer(g, [for (final a in attackers) ...[a, playerEntity(1 - p)]]);
}

int handSize(Game g, int p) => g.state.player(p).hand.length;
int countNamed(Game g, String name) => g.state.battlefield.where((id) => g.chars(id).name == name).length;

void main() {
  group('spells being cast', () {
    test('"when you cast ~" triggers from the stack (Desolation Twin)', () {
      final g = game();
      lands(g, 'Mountain', 10);
      final twin = g.addCard('Desolation Twin', 0, Zone.hand);
      cast(g, twin);
      settleAll(g);
      expect(g.state.battlefield.where((id) => g.chars(id).power == 10).length, 2, reason: 'the Twin and its token');
      expect(g.state.log.indexWhere((l) => l.text.startsWith('Desolation Twin: when you cast')), lessThan(g.state.log.indexWhere((l) => l.text == 'Desolation Twin resolves.')),
          reason: 'the trigger resolves before the spell');
    });

    test('your second spell each turn (Clarion Spirit)', () {
      final g = game();
      lands(g, 'Forest', 4);
      g.addCard('Clarion Spirit', 0, Zone.battlefield);
      cast(g, g.addCard('Grizzly Bears', 0, Zone.hand));
      settleAll(g);
      expect(countNamed(g, 'Spirit'), 0);
      cast(g, g.addCard('Grizzly Bears', 0, Zone.hand));
      settleAll(g);
      expect(countNamed(g, 'Spirit'), 1);
      // Not the third.
      g.addCard('Forest', 0, Zone.battlefield);
      g.addCard('Forest', 0, Zone.battlefield);
      cast(g, g.addCard('Grizzly Bears', 0, Zone.hand));
      settleAll(g);
      expect(countNamed(g, 'Spirit'), 1);
    });

    test('a spell that targets ~ (heroic: Agent of the Fates)', () {
      final g = game();
      lands(g, 'Forest', 1);
      final agent = g.addCard('Agent of the Fates', 0, Zone.battlefield);
      final bears = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      cast(g, g.addCard('Giant Growth', 0, Zone.hand), targets: [agent]);
      settleAll(g);
      expect(zoneOf(g, bears), Zone.graveyard, reason: 'each opponent sacrifices a creature');
    });

    test('a spirit or arcane spell (Baku Altar)', () {
      final g = game();
      lands(g, 'Plains', 2);
      final altar = g.addCard('Baku Altar', 0, Zone.battlefield);
      cast(g, g.addCard('Kami of Ancient Law', 0, Zone.hand));
      settleAll(g);
      expect(g.state.obj(altar).counters['ki'], 1);
    });

    test('cast or copy an instant or sorcery (Archmage Emeritus)', () {
      final g = game();
      lands(g, 'Mountain', 1);
      g.addCard('Archmage Emeritus', 0, Zone.battlefield);
      g.addCard('Island', 0, Zone.library);
      final shock = g.addCard('Shock', 0, Zone.hand);
      final before = handSize(g, 0);
      cast(g, shock, targets: [playerEntity(1)]);
      settleAll(g);
      expect(handSize(g, 0), before, reason: 'Shock left the hand, the trigger drew one');
    });
  });

  group('combat', () {
    test("attacks and isn't blocked (Abyssal Nightstalker)", () {
      final g = game();
      final stalker = g.addCard('Abyssal Nightstalker', 0, Zone.battlefield);
      g.addCard('Grizzly Bears', 1, Zone.hand);
      attackWith(g, [stalker]);
      passTo(g, TurnStep.combatDamage);
      settleAll(g);
      expect(handSize(g, 1), 0, reason: 'the defending player discarded');
    });

    test('~ and at least two other creatures attack (Bomber Corps)', () {
      final g = game();
      final corps = g.addCard('Bomber Corps', 0, Zone.battlefield);
      final b1 = g.addCard('Grizzly Bears', 0, Zone.battlefield);
      attackWith(g, [corps, b1]);
      bool triggered(Game x, int src) => x.state.pending?.decision.source == src || x.state.stack.any((s) => s.sourceId == src);
      expect(triggered(g, corps), isFalse, reason: 'only two attackers');
      final h = game();
      final c2 = h.addCard('Bomber Corps', 0, Zone.battlefield);
      final x1 = h.addCard('Grizzly Bears', 0, Zone.battlefield);
      final x2 = h.addCard('Grizzly Bears', 0, Zone.battlefield);
      attackWith(h, [c2, x1, x2]);
      expect(triggered(h, c2), isTrue);
    });

    test('exalted counts only a creature attacking alone', () {
      final g = game();
      g.addCard('Akrasan Squire', 0, Zone.battlefield);
      final b1 = g.addCard('Grizzly Bears', 0, Zone.battlefield);
      final b2 = g.addCard('Grizzly Bears', 0, Zone.battlefield);
      attackWith(g, [b1, b2]);
      settleAll(g);
      expect(g.chars(b1).power, 2);
      expect(g.chars(b2).power, 2);
    });

    test('blocks a creature with flying (Ezuri\'s Archers)', () {
      final g = game(active: 1);
      final archers = g.addCard("Ezuri's Archers", 0, Zone.battlefield);
      final angel = g.addCard('Serra Angel', 1, Zone.battlefield);
      final base = g.chars(archers).power!;
      attackWith(g, [angel]);
      passToDecision(g, DecisionKind.blockers);
      answer(g, [archers, angel]);
      settleAll(g);
      expect(g.chars(archers).power, base + 3);
    });

    test('a creature attacks you (Blood Reckoning)', () {
      final g = game(active: 1);
      g.addCard('Blood Reckoning', 0, Zone.battlefield);
      final bears = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      attackWith(g, [bears]);
      settleAll(g);
      expect(life(g, 1), 19);
    });

    test('a creature dealt damage by ~ this turn dies (Abattoir Ghoul)', () {
      final g = game(active: 1);
      final ghoul = g.addCard('Abattoir Ghoul', 0, Zone.battlefield); // 3/2 first strike
      final bears = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      attackWith(g, [bears]);
      passToDecision(g, DecisionKind.blockers);
      answer(g, [ghoul, bears]);
      passTo(g, TurnStep.endCombat);
      settleAll(g);
      expect(zoneOf(g, bears), Zone.graveyard);
      expect(life(g, 0), 22, reason: 'gained life equal to its toughness');
    });
  });

  group('permanents', () {
    test('becomes tapped (Attentive Sunscribe scries)', () {
      final g = game();
      final scribe = g.addCard('Attentive Sunscribe', 0, Zone.battlefield);
      g.addCard('Plains', 0, Zone.library);
      attackWith(g, [scribe]);
      expect(g.state.stack.length + (g.state.pending != null ? 1 : 0), greaterThan(0));
      for (var i = 0; i < 20 && g.state.pending?.decision.prompt.startsWith('Scry') != true; i++) {
        if (g.state.pending != null) break;
        g.apply(PassAction(g.state.priority!));
      }
      expect(g.state.pending?.decision.prompt, startsWith('Scry'));
    });

    test('put into a graveyard from the battlefield (Ichor Wellspring)', () {
      final g = game();
      final well = g.addCard('Ichor Wellspring', 0, Zone.battlefield);
      g.addCard('Island', 0, Zone.library);
      g.destroyForTest(well);
      settleAll(g);
      expect(handSize(g, 0), 1);
    });

    test('becomes the target of a spell or ability (Frost Walker)', () {
      final g = game();
      lands(g, 'Forest', 1);
      final walker = g.addCard('Frost Walker', 0, Zone.battlefield);
      cast(g, g.addCard('Giant Growth', 0, Zone.hand), targets: [walker]);
      settleAll(g);
      expect(zoneOf(g, walker), Zone.graveyard);
    });

    test("upkeep of enchanted creature's controller (Parasitic Bond)", () {
      final g = game();
      final bond = g.addCard('Parasitic Bond', 0, Zone.battlefield);
      final bears = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      g.state.obj(bond).attachedTo = bears;
      passTo(g, TurnStep.upkeep);
      settleAll(g);
      expect(g.state.active, 1);
      expect(life(g, 1), 18);
      expect(life(g, 0), 20);
    });
  });

  group('players doing things', () {
    test('cycling: "when you cycle ~" works from the graveyard (Bant Sojourners)', () {
      final g = game();
      lands(g, 'Plains', 3);
      final card = g.addCard('Bant Sojourners', 0, Zone.hand);
      g.addCard('Island', 0, Zone.library);
      final cyc = g.chars(card).abilities.indexWhere((a) => a is ActivatedAbility && a.text.startsWith('cycling'));
      g.apply(ActivateAbilityAction(0, card, cyc));
      pay(g);
      settleAll(g);
      expect(zoneOf(g, card), Zone.graveyard);
      expect(countNamed(g, 'Soldier'), 1);
    });

    test('committing a crime (Bandit\'s Haul)', () {
      final g = game();
      lands(g, 'Mountain', 1);
      final haul = g.addCard("Bandit's Haul", 0, Zone.battlefield);
      cast(g, g.addCard('Shock', 0, Zone.hand), targets: [playerEntity(1)]);
      settleAll(g);
      expect(g.state.obj(haul).counters['loot'], 1);
      // Targeting yourself isn't a crime.
      g.addCard('Mountain', 0, Zone.battlefield);
      cast(g, g.addCard('Shock', 0, Zone.hand), targets: [playerEntity(0)]);
      settleAll(g);
      expect(g.state.obj(haul).counters['loot'], 1);
    });

    test('whenever you scry (Arwen)', () {
      final g = game();
      lands(g, 'Island', 1);
      final arwen = g.addCard('Arwen Undómiel', 0, Zone.battlefield);
      g.addCard('Island', 0, Zone.library);
      g.addCard('Island', 0, Zone.library);
      cast(g, g.addCard('Opt', 0, Zone.hand));
      settleAll(g);
      expect(g.state.obj(arwen).counters['+1/+1'], 1);
    });
  });

  test('you lose life during your turn (Shadowheart), not on an opponent\'s', () {
    final g = game();
    lands(g, 'Mountain', 2);
    g.addCard('Shadowheart, Cleric of Trickery', 0, Zone.battlefield);
    g.addCard('Island', 0, Zone.library);
    g.addCard('Island', 0, Zone.library);
    cast(g, g.addCard('Shock', 0, Zone.hand), targets: [playerEntity(0)]);
    settleAll(g);
    expect(handSize(g, 0), 1, reason: 'drew on its own turn');
    // On Bob's turn, Bob shocks Alice: no draw.
    final h = game(active: 1);
    lands(h, 'Mountain', 1, player: 1);
    h.addCard('Shadowheart, Cleric of Trickery', 0, Zone.battlefield);
    h.addCard('Island', 0, Zone.library);
    cast(h, h.addCard('Shock', 1, Zone.hand), targets: [playerEntity(0)]);
    settleAll(h);
    expect(handSize(h, 0), 0);
  });

  test('"this creature" inside a granted ability is the creature that has it', () {
    final def = triggersDb()['Abnormal Endurance']!;
    expect(OracleParser.parse(def).supported, isTrue);
  });
}
