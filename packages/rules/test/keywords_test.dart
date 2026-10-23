// Keyword abilities (CR 702), on cards from outside Foundations (test/fixtures/extra.json).
import 'package:rules/rules.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Game game() => empty(db: extra());

/// Declares [attacker] at Bob and goes to the blockers decision (or past it, if none).
void attack(Game g, int attacker) {
  g.setStep(TurnStep.beginCombat);
  g.apply(PassAction(0));
  g.apply(PassAction(1));
  answer(g, [attacker, playerEntity(1)]);
}

void main() {
  group('evasion', () {
    test('landwalk: unblockable while the defender controls that land type (CR 702.14)', () {
      final g = game();
      final snake = g.addCard('Anaconda', 0, Zone.battlefield);
      final bears = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      expect(g.canBlock(bears, snake), isTrue);
      g.addCard('Swamp', 1, Zone.battlefield);
      expect(g.canBlock(bears, snake), isFalse);
    });

    test('shadow blocks and is blocked only by shadow (CR 702.28)', () {
      final g = game();
      final dauthi = g.addCard('Dauthi Cutthroat', 0, Zone.battlefield);
      final bears = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      final other = g.addCard('Dauthi Cutthroat', 1, Zone.battlefield);
      expect(g.canBlock(bears, dauthi), isFalse);
      expect(g.canBlock(other, dauthi), isTrue);
      final bears0 = g.addCard('Grizzly Bears', 0, Zone.battlefield);
      expect(g.canBlock(other, bears0), isFalse, reason: 'shadow can only block shadow');
    });

    test('fear, intimidate, horsemanship, skulk', () {
      final g = game();
      final greven = g.addCard('Commander Greven il-Vec', 0, Zone.battlefield); // fear
      final raider = g.addCard('Academy Raider', 0, Zone.battlefield); // intimidate, red
      final general = g.addCard('Barbarian General', 0, Zone.battlefield); // horsemanship
      final revenant = g.addCard('Farbog Revenant', 0, Zone.battlefield); // skulk, 1/3
      final bears = g.addCard('Grizzly Bears', 1, Zone.battlefield); // green 2/2
      final drone = g.addCard('Blinding Drone', 1, Zone.battlefield); // colorless 1/3
      final ogre = g.addCard('Blood Ogre', 1, Zone.battlefield); // red 2/2
      expect(g.canBlock(bears, greven), isFalse);
      expect(g.canBlock(bears, raider), isFalse);
      expect(g.canBlock(ogre, raider), isTrue, reason: 'shares a color');
      expect(g.canBlock(bears, general), isFalse);
      expect(g.canBlock(bears, revenant), isFalse, reason: 'greater power');
      expect(g.canBlock(drone, revenant), isTrue);
    });
  });

  group('damage', () {
    test('infect deals damage to players as poison counters (CR 702.90)', () {
      final g = game();
      final goblin = g.addCard('Blackcleave Goblin', 0, Zone.battlefield);
      attack(g, goblin);
      passTo(g, TurnStep.endCombat);
      expect(life(g, 1), 20);
      expect(g.state.player(1).poison, 2);
    });

    test('wither deals damage to creatures as -1/-1 counters (CR 702.80)', () {
      final g = game();
      final gang = g.addCard('Boggart Ram-Gang', 0, Zone.battlefield); // 3/3
      final giant = g.addCard('Hill Giant', 1, Zone.battlefield); // 3/3
      attack(g, gang);
      passToDecision(g, DecisionKind.blockers);
      answer(g, [giant, gang]);
      passTo(g, TurnStep.endCombat);
      expect(zoneOf(g, giant), Zone.graveyard);
      expect(g.state.obj(giant).counters['-1/-1'] ?? 0, 0, reason: 'counters leave with it');
      expect(zoneOf(g, gang), Zone.graveyard);
    });

    test('toxic adds poison counters on top of combat damage (CR 702.164)', () {
      final g = game();
      final sentry = g.addCard('Annex Sentry', 0, Zone.battlefield);
      final toxic = g.chars(sentry).kws('toxic').first.n;
      final power = g.chars(sentry).power!;
      attack(g, sentry);
      passTo(g, TurnStep.endCombat);
      expect(life(g, 1), 20 - power);
      expect(g.state.player(1).poison, toxic);
    });
  });

  group('characteristics', () {
    test('changeling is every creature type (CR 702.73)', () {
      final g = game();
      final c = g.addCard('Avian Changeling', 0, Zone.battlefield);
      expect(g.chars(c).hasSubtype('Goblin'), isTrue);
      expect(g.chars(c).hasSubtype('Forest'), isFalse);
    });

    test('characteristic-defining abilities that count each other settle (CR 604.3)', () {
      final g = game();
      final a = g.addCard('Boneyard Wurm', 0, Zone.graveyard);
      final b = g.addCard('Boneyard Wurm', 0, Zone.graveyard);
      // Power and toughness: creature cards in your graveyard.
      expect(g.chars(a).power, 2);
      expect(g.chars(b).toughness, 2);
    });

    test('devoid: colorless despite its cost (CR 702.114)', () {
      final g = game();
      final c = g.addCard('Blinding Drone', 0, Zone.hand);
      expect(g.chars(c).colors, isEmpty);
    });
  });

  group('triggered keywords', () {
    test('exalted: a creature attacking alone gets +1/+1 (CR 702.83)', () {
      final g = game();
      g.addCard('Akrasan Squire', 0, Zone.battlefield);
      final bears = g.addCard('Grizzly Bears', 0, Zone.battlefield);
      attack(g, bears);
      resolveAll(g);
      expect(g.chars(bears).power, 3);
    });

    test('bushido: +N/+N when it blocks or becomes blocked (CR 702.45)', () {
      final g = empty(db: extra(), active: 1);
      final moth = g.addCard('Araba Mothrider', 0, Zone.battlefield);
      final bears = g.addCard('Grizzly Bears', 1, Zone.battlefield);
      final base = g.chars(moth).power!;
      g.setStep(TurnStep.beginCombat);
      g.apply(PassAction(1));
      g.apply(PassAction(0));
      answer(g, [bears, playerEntity(0)]);
      passToDecision(g, DecisionKind.blockers);
      answer(g, [moth, bears]);
      resolveAll(g);
      expect(g.chars(moth).power, base + 1);
    });

    test('persist returns it once with a -1/-1 counter (CR 702.79)', () {
      final g = game();
      g.addCard('Mountain', 0, Zone.battlefield);
      final ouphes = g.addCard('Aerie Ouphes', 0, Zone.battlefield);
      g.destroyForTest(ouphes);
      resolveAll(g);
      expect(zoneOf(g, ouphes), Zone.battlefield);
      expect(g.state.obj(ouphes).counters['-1/-1'], 1);
      g.destroyForTest(ouphes);
      resolveAll(g);
      expect(zoneOf(g, ouphes), Zone.graveyard, reason: 'it had a -1/-1 counter');
    });

    test('undying returns it once with a +1/+1 counter (CR 702.93)', () {
      final g = game();
      final ghoul = g.addCard('Butcher Ghoul', 0, Zone.battlefield);
      g.destroyForTest(ghoul);
      resolveAll(g);
      expect(zoneOf(g, ghoul), Zone.battlefield);
      expect(g.state.obj(ghoul).counters['+1/+1'], 1);
      g.destroyForTest(ghoul);
      resolveAll(g);
      expect(zoneOf(g, ghoul), Zone.graveyard);
    });

    test('bloodthirst: enters with counters if an opponent was dealt damage this turn (CR 702.54)', () {
      final g = game();
      for (var i = 0; i < 3; i++) {
        g.addCard('Mountain', 0, Zone.battlefield);
      }
      final first = g.addCard('Blood Ogre', 0, Zone.hand);
      g.apply(CastAction(0, first));
      pay(g);
      resolveAll(g);
      expect(g.state.obj(first).counters['+1/+1'] ?? 0, 0);
      g.state.player(1).stats.damageTaken = 1;
      final second = g.addCard('Blood Ogre', 0, Zone.hand);
      for (var i = 0; i < 3; i++) {
        g.addCard('Mountain', 0, Zone.battlefield);
      }
      g.apply(CastAction(0, second));
      pay(g);
      resolveAll(g);
      expect(g.state.obj(second).counters['+1/+1'], 1);
    });
  });

  group('activated keywords', () {
    test('crew: tap creatures with enough total power; the Vehicle becomes a creature (CR 702.122)', () {
      final g = game();
      final ship = g.addCard("Adventurer's Airship", 0, Zone.battlefield);
      final bears = g.addCard('Grizzly Bears', 0, Zone.battlefield);
      expect(g.chars(ship).isCreature, isFalse);
      final crew = g.chars(ship).abilities.indexWhere((a) => a is ActivatedAbility && a.text.startsWith('crew'));
      g.apply(ActivateAbilityAction(0, ship, crew));
      if (g.state.pending?.decision.kind == DecisionKind.cards) answer(g, [bears]);
      resolveAll(g);
      expect(g.state.obj(bears).tapped, isTrue);
      expect(g.chars(ship).isCreature, isTrue);
    });

    test("crew can't be paid without enough power", () {
      final g = game();
      final ship = g.addCard("Adventurer's Airship", 0, Zone.battlefield);
      g.addCard('Akrasan Squire', 0, Zone.battlefield); // power 1, crew 2
      final crew = g.chars(ship).abilities.indexWhere((a) => a is ActivatedAbility && a.text.startsWith('crew'));
      expect(g.whyNot(ActivateAbilityAction(0, ship, crew)), isNotNull);
    });

    test('landcycling searches for a basic land from hand (CR 702.29)', () {
      final g = game();
      g.addCard('Forest', 0, Zone.battlefield);
      g.addCard('Forest', 0, Zone.battlefield);
      final witch = g.addCard('Apex Witchstalker', 0, Zone.hand);
      final plains = g.addCard('Plains', 0, Zone.library);
      final cyc = g.chars(witch).abilities.indexWhere((a) => a is ActivatedAbility && a.text.contains('landcycling'));
      g.apply(ActivateAbilityAction(0, witch, cyc));
      pay(g);
      resolveAll(g);
      if (g.state.pending != null) answer(g, [plains]);
      expect(zoneOf(g, witch), Zone.graveyard);
      expect(zoneOf(g, plains), Zone.hand);
    });
  });

  group('modes', () {
    test('"choose up to one" with no legal mode chooses none, without asking (CR 700.2)', () {
      final g = game();
      for (var i = 0; i < 4; i++) {
        g.addCard('Forest', 0, Zone.battlefield);
      }
      final slinger = g.addCard('Sawblade Slinger', 0, Zone.hand);
      g.apply(CastAction(0, slinger));
      pay(g);
      resolveAll(g);
      expect(g.state.pending, isNull, reason: 'no artifact or Zombie to target');
      expect(g.state.stack, isEmpty);
      expect(zoneOf(g, slinger), Zone.battlefield);
    });
  });
}
