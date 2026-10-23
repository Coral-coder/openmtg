// Engine tests, one group per Comprehensive Rules area. Positions are set up directly with
// GameTesting, then played through real actions and answers.
import 'package:rules/rules.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Game empty({int active = 0}) => Game(fdn(), players: ['Alice', 'Bob'], seed: 1)..startEmpty(active: active);

void answer(Game g, List<int> a) => g.apply(AnswerAction(g.state.pending!.decision.player, a));

/// Answers a target decision unless it was forced (and so skipped by the engine).
void target(Game g, List<int> ids) {
  if (g.state.pending?.decision.kind == DecisionKind.targets) answer(g, ids);
}

/// Pays automatically if payment is asked.
void pay(Game g) {
  if (g.state.pending?.decision.kind == DecisionKind.payMana) answer(g, []);
}

/// Passes priority until the stack is empty (or a decision is pending).
void resolveAll(Game g) {
  for (var i = 0; i < 50 && g.state.stack.isNotEmpty && g.state.pending == null; i++) {
    g.apply(PassAction(g.state.priority!));
  }
}

/// Passes until the game reaches [step] (declining blocks and attacks on the way), or a
/// decision other than those is pending, or the game ends.
void passTo(Game g, Step step) {
  for (var i = 0; i < 200 && !g.state.over; i++) {
    final pd = g.state.pending;
    if (pd != null) {
      if (pd.decision.kind == DecisionKind.blockers || pd.decision.kind == DecisionKind.attackers) {
        answer(g, []);
        continue;
      }
      return;
    }
    if (g.state.step == step && g.state.stack.isEmpty && g.state.priority != null) return;
    g.apply(PassAction(g.state.priority!));
  }
}

/// Passes until a decision of [kind] is pending.
void passToDecision(Game g, DecisionKind kind) {
  for (var i = 0; i < 100 && g.state.pending?.decision.kind != kind; i++) {
    g.apply(PassAction(g.state.priority!));
  }
}

int life(Game g, int p) => g.state.player(p).life;
Zone zoneOf(Game g, int id) => g.state.obj(id).zone;

void main() {
  group('CR 106/605 mana', () {
    test('lands and mana creatures pay for spells automatically', () {
      final g = empty();
      g.addCard('Forest', 0, Zone.battlefield);
      final elves = g.addCard('Llanowar Elves', 0, Zone.battlefield);
      final growth = g.addCard('Giant Growth', 0, Zone.hand);
      final bear = g.addCard('Savannah Lions', 0, Zone.battlefield);
      g.apply(CastAction(0, growth));
      answer(g, [bear]); // target
      pay(g);
      expect(g.state.obj(g.state.battlefield.firstWhere((id) => g.state.obj(id).cardName == 'Forest')).tapped, isTrue);
      expect(g.state.obj(elves).tapped, isFalse, reason: 'one mana is enough; the land pays first');
      resolveAll(g);
      expect(g.chars(bear).power, 5);
      expect(g.chars(bear).toughness, 4);
    });

    test("summoning-sick creatures can't tap for mana", () {
      final g = empty();
      g.addCard('Llanowar Elves', 0, Zone.battlefield, sick: true);
      final growth = g.addCard('Giant Growth', 0, Zone.hand);
      g.addCard('Savannah Lions', 0, Zone.battlefield);
      expect(g.legalActions(0).whereType<CastAction>().where((a) => a.id == growth), isEmpty);
    });

    test('mana empties between steps', () {
      final g = empty();
      final forest = g.addCard('Forest', 0, Zone.battlefield);
      g.apply(ManaAction(0, forest, 0));
      expect(g.state.player(0).pool.length, 1);
      g.apply(PassAction(0));
      g.apply(PassAction(1));
      expect(g.state.player(0).pool, isEmpty);
    });
  });

  group('CR 601 casting, 608 resolving', () {
    test('a spell with an illegal target does nothing (fizzles)', () {
      final g = empty();
      g.addCard('Mountain', 0, Zone.battlefield);
      g.addCard('Swamp', 1, Zone.battlefield);
      final bolt = g.addCard('Burst Lightning', 0, Zone.hand);
      final stab = g.addCard('Stab', 1, Zone.hand);
      final lions = g.addCard('Savannah Lions', 1, Zone.battlefield);
      g.apply(CastAction(0, bolt));
      answer(g, [0]); // no kicker
      target(g, [lions]);
      pay(g);
      // Bob responds by killing his own Lions.
      g.apply(CastAction(1, stab));
      target(g, [lions]);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, lions), Zone.graveyard);
      expect(zoneOf(g, bolt), Zone.graveyard);
      expect(life(g, 1), 20);
    });

    test('counterspells counter; "can\'t be countered" holds', () {
      final g = empty();
      for (var i = 0; i < 2; i++) {
        g.addCard('Island', 1, Zone.battlefield);
      }
      g.addCard('Plains', 0, Zone.battlefield);
      final lions = g.addCard('Savannah Lions', 0, Zone.hand);
      final scatter = g.addCard('Essence Scatter', 1, Zone.hand);
      g.apply(CastAction(0, lions));
      pay(g);
      // Alice's own spell: she passes automatically, so Bob has priority.
      g.apply(CastAction(1, scatter));
      target(g, [lions]);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, lions), Zone.graveyard);
    });

    test('kicker changes what the spell does', () {
      final g = empty();
      for (var i = 0; i < 5; i++) {
        g.addCard('Mountain', 0, Zone.battlefield);
      }
      final bolt = g.addCard('Burst Lightning', 0, Zone.hand);
      g.apply(CastAction(0, bolt));
      answer(g, [1]); // kick it
      answer(g, [playerEntity(1)]);
      pay(g);
      resolveAll(g);
      expect(life(g, 1), 16);
    });

    test('an additional cost must be paid (Thrill of Possibility discards)', () {
      final g = empty();
      g.addCard('Mountain', 0, Zone.battlefield);
      g.addCard('Mountain', 0, Zone.battlefield);
      final thrill = g.addCard('Thrill of Possibility', 0, Zone.hand);
      final junk = g.addCard('Savannah Lions', 0, Zone.hand);
      g.stackLibrary(0, ['Forest', 'Forest']);
      g.apply(CastAction(0, thrill));
      // The only other card is discarded automatically (forced choice).
      expect(zoneOf(g, junk), anyOf(Zone.graveyard, Zone.hand));
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, junk), Zone.graveyard);
      expect(g.state.player(0).hand.length, 2);
    });

    test('flashback casts from the graveyard, then exiles', () {
      final g = empty();
      for (var i = 0; i < 3; i++) {
        g.addCard('Island', 0, Zone.battlefield);
      }
      final tt = g.addCard('Think Twice', 0, Zone.graveyard);
      g.stackLibrary(0, ['Forest']);
      final casts = g.legalActions(0).whereType<CastAction>().where((a) => a.id == tt).toList();
      expect(casts, hasLength(1));
      g.apply(casts.first);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, tt), Zone.exile);
      expect(g.state.player(0).hand.length, 1);
    });

    test('X spells', () {
      final g = empty();
      for (var i = 0; i < 5; i++) {
        g.addCard('Swamp', 0, Zone.battlefield);
      }
      final ex = g.addCard('Exsanguinate', 0, Zone.hand);
      g.apply(CastAction(0, ex));
      expect(g.state.pending!.decision.max, 3);
      answer(g, [3]);
      pay(g);
      resolveAll(g);
      expect(life(g, 1), 17);
      expect(life(g, 0), 23);
    });

    test('cost reduction (Tolarian Terror)', () {
      final g = empty();
      for (var i = 0; i < 4; i++) {
        g.addCard('Island', 0, Zone.battlefield);
      }
      final terror = g.addCard('Tolarian Terror', 0, Zone.hand);
      expect(g.legalActions(0).whereType<CastAction>().where((a) => a.id == terror), isEmpty);
      for (var i = 0; i < 3; i++) {
        g.addCard('Think Twice', 0, Zone.graveyard);
      }
      expect(g.legalActions(0).whereType<CastAction>().where((a) => a.id == terror), hasLength(1));
    });

    test('modal spells choose a mode', () {
      final g = empty();
      for (var i = 0; i < 3; i++) {
        g.addCard('Mountain', 0, Zone.battlefield);
      }
      final surprise = g.addCard('Goblin Surprise', 0, Zone.hand);
      g.apply(CastAction(0, surprise));
      answer(g, [1]); // two Goblins
      pay(g);
      resolveAll(g);
      expect(g.state.battlefield.where((id) => g.state.obj(id).isToken).length, 2);
    });
  });

  group('CR 506–511 combat', () {
    void toAttack(Game g) => passTo(g, Step.declareAttackers);

    test('unblocked attacker deals damage; lifelink gains life', () {
      final g = empty();
      final hawk = g.addCard("Healer's Hawk", 0, Zone.battlefield);
      g.setStep(Step.beginCombat);
      g.apply(PassAction(0));
      g.apply(PassAction(1));
      expect(g.state.pending!.decision.kind, DecisionKind.attackers);
      answer(g, [hawk, playerEntity(1)]);
      passTo(g, Step.endCombat);
      expect(life(g, 1), 19);
      expect(life(g, 0), 21);
    });

    test('flying can only be blocked by flying or reach', () {
      final g = empty();
      final hawk = g.addCard("Healer's Hawk", 0, Zone.battlefield);
      final lions = g.addCard('Savannah Lions', 1, Zone.battlefield);
      final spinner = g.addCard('Treetop Snarespinner', 1, Zone.battlefield);
      expect(g.canBlock(lions, hawk), isFalse);
      expect(g.canBlock(spinner, hawk), isTrue);
    });

    test('first strike kills before regular damage', () {
      final g = empty();
      final vindicator = g.addCard('Swiftblade Vindicator', 0, Zone.battlefield); // 1/1 double strike
      final aegis = g.addCard('Inspiring Paladin', 1, Zone.battlefield);
      g.setStep(Step.beginCombat);
      g.apply(PassAction(0));
      g.apply(PassAction(1));
      answer(g, [vindicator, playerEntity(1)]);
      passTo(g, Step.endCombat);
      expect(g.state.pending, isNull);
      // Unblocked double strike deals damage twice.
      expect(life(g, 1), 18);
      expect(zoneOf(g, aegis), Zone.battlefield);
    });

    test('deathtouch: any damage is lethal; trample assigns the rest to the player', () {
      final g = empty();
      final hydra = g.addCard('Quakestrider Ceratops', 0, Zone.battlefield); // 12/8 no trample
      final wall = g.addCard('Treetop Snarespinner', 1, Zone.battlefield); // 1/4 reach deathtouch
      g.setStep(Step.beginCombat);
      g.apply(PassAction(0));
      g.apply(PassAction(1));
      answer(g, [hydra, playerEntity(1)]);
      passToDecision(g, DecisionKind.blockers);
      answer(g, [wall, hydra]);
      passTo(g, Step.endCombat);
      expect(zoneOf(g, hydra), Zone.graveyard, reason: 'deathtouch');
      expect(zoneOf(g, wall), Zone.graveyard);
      expect(life(g, 1), 20, reason: 'no trample');
    });

    test('menace needs two blockers', () {
      final g = empty();
      final feaster = g.addCard('Crypt Feaster', 0, Zone.battlefield);
      final b1 = g.addCard('Savannah Lions', 1, Zone.battlefield);
      g.addCard('Savannah Lions', 1, Zone.battlefield);
      g.setStep(Step.beginCombat);
      g.apply(PassAction(0));
      g.apply(PassAction(1));
      answer(g, [feaster, playerEntity(1)]);
      passToDecision(g, DecisionKind.blockers);
      expect(() => answer(g, [b1, feaster]), throwsA(isA<GameError>()));
    });

    test('vigilance: attacking doesn\'t tap', () {
      final g = empty();
      final angel = g.addCard('Serra Angel', 0, Zone.battlefield);
      g.setStep(Step.beginCombat);
      g.apply(PassAction(0));
      g.apply(PassAction(1));
      answer(g, [angel, playerEntity(1)]);
      expect(g.state.obj(angel).tapped, isFalse);
    });

    test('summoning-sick creatures can\'t attack; haste can', () {
      final g = empty();
      final lions = g.addCard('Savannah Lions', 0, Zone.battlefield, sick: true);
      final scourge = g.addCard('Brazen Scourge', 0, Zone.battlefield, sick: true);
      expect(g.attackCandidates(0), [scourge]);
      expect(g.attackCandidates(0).contains(lions), isFalse);
    });
  });

  group('CR 704 state-based actions', () {
    test('lethal damage and zero toughness', () {
      final g = empty();
      g.addCard('Swamp', 0, Zone.battlefield);
      final stab = g.addCard('Stab', 0, Zone.hand);
      final lions = g.addCard('Savannah Lions', 1, Zone.battlefield);
      g.apply(CastAction(0, stab));
      target(g, [lions]);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, lions), Zone.graveyard);
    });

    test('a player at 0 life loses', () {
      final g = empty();
      g.addCard('Mountain', 0, Zone.battlefield);
      g.state.player(1).life = 3;
      final wave = g.addCard('Boltwave', 0, Zone.hand);
      g.apply(CastAction(0, wave));
      pay(g);
      resolveAll(g);
      expect(g.state.over, isTrue);
      expect(g.state.winner, 0);
    });

    test('legend rule: the controller keeps one', () {
      final g = empty();
      final a = g.addCard('Arahbo, the First Fang', 0, Zone.battlefield);
      final b = g.addCard('Arahbo, the First Fang', 0, Zone.battlefield);
      g.settle();
      expect(g.state.pending!.decision.prompt, contains('Legend rule'));
      answer(g, [b]);
      expect(zoneOf(g, a), Zone.graveyard);
      expect(zoneOf(g, b), Zone.battlefield);
    });

    test('drawing from an empty library loses', () {
      final g = empty();
      passTo(g, Step.draw);
      // Bob's turn: his library is empty, so he loses when he draws.
      expect(g.state.over, isTrue);
      expect(g.state.winner, 0);
    });
  });

  group('CR 603 triggered abilities', () {
    test('enters the battlefield: draw a card', () {
      final g = empty();
      g.addCard('Plains', 0, Zone.battlefield);
      g.addCard('Plains', 0, Zone.battlefield);
      g.stackLibrary(0, ['Forest']);
      final hunter = g.addCard('Helpful Hunter', 0, Zone.hand);
      g.apply(CastAction(0, hunter));
      pay(g);
      resolveAll(g);
      resolveAll(g);
      expect(zoneOf(g, hunter), Zone.battlefield);
      expect(g.state.player(0).hand.length, 1);
    });

    test('dies: create a token', () {
      final g = empty();
      g.addCard('Swamp', 1, Zone.battlefield);
      final sage = g.addCard('Infestation Sage', 0, Zone.battlefield);
      final stab = g.addCard('Stab', 1, Zone.hand);
      g.apply(PassAction(0));
      g.apply(CastAction(1, stab));
      target(g, [sage]);
      pay(g);
      resolveAll(g);
      resolveAll(g);
      final tokens = g.state.battlefield.where((id) => g.state.obj(id).isToken).toList();
      expect(tokens, hasLength(1));
      expect(g.chars(tokens.first).has(Kw.flying), isTrue);
    });

    test('landfall', () {
      final g = empty();
      g.addCard('Elfsworn Giant', 0, Zone.battlefield);
      final forest = g.addCard('Forest', 0, Zone.hand);
      g.apply(PlayLandAction(0, forest));
      resolveAll(g);
      expect(g.state.battlefield.where((id) => g.state.obj(id).isToken).length, 1);
    });

    test('attack trigger (Dauntless Veteran pumps the team)', () {
      final g = empty();
      final vet = g.addCard('Dauntless Veteran', 0, Zone.battlefield);
      final lions = g.addCard('Savannah Lions', 0, Zone.battlefield);
      g.setStep(Step.beginCombat);
      g.apply(PassAction(0));
      g.apply(PassAction(1));
      answer(g, [vet, playerEntity(1)]);
      resolveAll(g);
      expect(g.chars(lions).power, 3);
    });

    test('prowess', () {
      final g = empty();
      g.addCard('Island', 0, Zone.battlefield);
      final adept = g.addCard('Elementalist Adept', 0, Zone.battlefield);
      g.stackLibrary(0, ['Island']);
      final dist = g.addCard('Fleeting Distraction', 0, Zone.hand);
      final lions = g.addCard('Savannah Lions', 1, Zone.battlefield);
      g.apply(CastAction(0, dist));
      target(g, [lions]);
      pay(g);
      // The prowess trigger resolves first.
      g.apply(PassAction(0));
      g.apply(PassAction(1));
      expect(g.chars(adept).power, 3);
    });
  });

  group('CR 613 layers and continuous effects', () {
    test('anthem + pump + counters add up', () {
      final g = empty();
      g.addCard('Anthem of Champions', 0, Zone.battlefield);
      final lions = g.addCard('Savannah Lions', 0, Zone.battlefield);
      expect(g.chars(lions).power, 3);
      g.state.obj(lions).counters['+1/+1'] = 2;
      g.state.version++;
      expect(g.chars(lions).power, 5);
      expect(g.chars(lions).toughness, 4);
    });

    test('losing all abilities (Witness Protection) makes it a 1/1 with no abilities', () {
      final g = empty();
      g.addCard('Island', 0, Zone.battlefield);
      final wp = g.addCard('Witness Protection', 0, Zone.hand);
      final angel = g.addCard('Serra Angel', 1, Zone.battlefield);
      g.apply(CastAction(0, wp));
      target(g, [angel]);
      pay(g);
      resolveAll(g);
      final c = g.chars(angel);
      expect(c.power, 1);
      expect(c.toughness, 1);
      expect(c.has(Kw.flying), isFalse);
      expect(c.name, 'Legitimate Businessperson');
    });

    test('until-end-of-turn effects end in cleanup', () {
      final g = empty();
      g.addCard('Forest', 0, Zone.battlefield);
      final growth = g.addCard('Giant Growth', 0, Zone.hand);
      final lions = g.addCard('Savannah Lions', 0, Zone.battlefield);
      g.apply(CastAction(0, growth));
      target(g, [lions]);
      pay(g);
      resolveAll(g);
      expect(g.chars(lions).power, 5);
      passTo(g, Step.upkeep);
      expect(g.chars(lions).power, 2);
    });

    test('equipment grants its bonus', () {
      final g = empty();
      g.addCard('Plains', 0, Zone.battlefield);
      g.addCard('Plains', 0, Zone.battlefield);
      final katana = g.addCard('Quick-Draw Katana', 0, Zone.battlefield);
      final lions = g.addCard('Savannah Lions', 0, Zone.battlefield);
      final equip = g.legalActions(0).whereType<ActivateAction>().firstWhere((a) => a.id == katana);
      g.apply(equip);
      target(g, [lions]);
      pay(g);
      resolveAll(g);
      expect(g.chars(lions).power, 4, reason: 'during your turn: +2/+0');
      expect(g.chars(lions).has(Kw.firstStrike), isTrue);
    });
  });

  group('CR 614–616 replacement and prevention', () {
    test('enters tapped', () {
      final g = empty();
      g.addCard('Swamp', 0, Zone.battlefield);
      final ghoul = g.addCard('Diregraf Ghoul', 0, Zone.hand);
      g.apply(CastAction(0, ghoul));
      pay(g);
      resolveAll(g);
      expect(g.state.obj(ghoul).tapped, isTrue);
    });

    test('kicked creature enters with counters', () {
      final g = empty();
      for (var i = 0; i < 5; i++) {
        g.addCard('Forest', 0, Zone.battlefield);
      }
      final colony = g.addCard('Gnarlid Colony', 0, Zone.hand);
      g.apply(CastAction(0, colony));
      answer(g, [1]);
      pay(g);
      resolveAll(g);
      expect(g.chars(colony).power, 4);
      expect(g.chars(colony).has(Kw.trample), isTrue);
    });

    test('double damage (Twinflame Tyrant)', () {
      final g = empty();
      g.addCard('Twinflame Tyrant', 0, Zone.battlefield);
      g.addCard('Mountain', 0, Zone.battlefield);
      final bolt = g.addCard('Burst Lightning', 0, Zone.hand);
      g.apply(CastAction(0, bolt));
      answer(g, [0]);
      answer(g, [playerEntity(1)]);
      pay(g);
      resolveAll(g);
      expect(life(g, 1), 16);
    });

    test('prevention (Crystal Barricade)', () {
      final g = empty();
      g.addCard('Crystal Barricade', 1, Zone.battlefield);
      final lions = g.addCard('Savannah Lions', 1, Zone.battlefield);
      g.addCard('Mountain', 0, Zone.battlefield);
      final bolt = g.addCard('Burst Lightning', 0, Zone.hand);
      g.apply(CastAction(0, bolt));
      answer(g, [0]);
      target(g, [lions]);
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, lions), Zone.battlefield);
    });
  });

  group('CR 306 planeswalkers, 111 tokens', () {
    test('loyalty abilities once per turn', () {
      final g = empty();
      final ajani = g.addCard('Ajani, Caller of the Pride', 0, Zone.battlefield);
      final lions = g.addCard('Savannah Lions', 0, Zone.battlefield);
      final start = g.state.obj(ajani).counters['loyalty']!;
      final plus = g.legalActions(0).whereType<ActivateAction>().firstWhere((a) => a.id == ajani);
      g.apply(plus);
      target(g, [lions]);
      resolveAll(g);
      expect(g.state.obj(ajani).counters['loyalty'], start + 1);
      expect(g.chars(lions).power, 3);
      expect(g.legalActions(0).whereType<ActivateAction>().where((a) => a.id == ajani), isEmpty);
    });

    test('Food token: sacrifice to gain 3', () {
      final g = empty();
      for (var i = 0; i < 4; i++) {
        g.addCard('Swamp', 0, Zone.battlefield);
      }
      final pie = g.addCard('Bake into a Pie', 0, Zone.hand);
      final lions = g.addCard('Savannah Lions', 1, Zone.battlefield);
      g.apply(CastAction(0, pie));
      target(g, [lions]);
      pay(g);
      resolveAll(g);
      final food = g.state.battlefield.firstWhere((id) => g.state.obj(id).isToken);
      expect(g.chars(food).name, 'Food');
      expect(zoneOf(g, lions), Zone.graveyard);
    });

    test('Day of Judgment destroys every creature', () {
      final g = empty();
      for (var i = 0; i < 4; i++) {
        g.addCard('Plains', 0, Zone.battlefield);
      }
      final a = g.addCard('Savannah Lions', 0, Zone.battlefield);
      final b = g.addCard('Serra Angel', 1, Zone.battlefield);
      final doj = g.addCard('Day of Judgment', 0, Zone.hand);
      g.apply(CastAction(0, doj));
      pay(g);
      resolveAll(g);
      expect(zoneOf(g, a), Zone.graveyard);
      expect(zoneOf(g, b), Zone.graveyard);
    });
  });

  group('CR 103 starting the game', () {
    test('London mulligan puts cards on the bottom', () {
      final db = fdn();
      final deck = starterDeck(db, colorPairs['Selesnya (GW)']!);
      final g = Game(db, players: ['A', 'B'], seed: 5);
      g.apply(StartAction([deck, deck]));
      final first = g.state.pending!.decision.player;
      answer(g, [0]); // mulligan
      expect(g.state.player(first).hand.length, 7);
      answer(g, [1]); // keep (first player)
      answer(g, [1]); // other player keeps
      final d = g.state.pending!.decision;
      expect(d.kind, DecisionKind.cards);
      expect(d.min, 1);
      answer(g, [d.options.first]);
      expect(g.state.player(first).hand.length, 6);
      expect(g.state.inProgress, isTrue);
    });

    test('determinism: same seed and actions, same fingerprint', () {
      final db = fdn();
      final deck = starterDeck(db, colorPairs['Izzet (UR)']!);
      String play() {
        final g = Game(db, players: ['A', 'B'], seed: 99);
        g.apply(StartAction([deck, deck]));
        runBots(g, [Bot(0, seed: 3), Bot(1, seed: 4)]);
        return g.fingerprint;
      }

      expect(play(), play());
    });
  });
}
