// How the parser reads specific Foundations cards: regressions found by auditing the IR dump
// (dart run bin/cards.dart test/fixtures/fdn.json fdn --dump).
import 'package:rules/rules.dart';
import 'package:test/test.dart';

import 'helpers.dart';

List<String> read(String name) => [for (final a in OracleParser.parse(fdn().get(name)).faces.first.abilities) describeAbility(a)];

void main() {
  test('a subject carries over "then": each player discards, then draws seven', () {
    expect(read('Dragon Mage').last, contains('draw 7 all'));
  });

  test("the sacrificed creature's toughness (Tribute to Hunger)", () {
    expect(read('Tribute to Hunger').last, contains('gain result:sacToughness'));
  });

  test('abilities that return a card from the graveyard work from the graveyard', () {
    final a = OracleParser.parse(fdn().get('Reassembling Skeleton')).faces.first.abilities.whereType<ActivatedAbility>().single;
    expect(a.zone, ZoneKind.graveyard);
  });

  test('"if it was a creature card" refers to the exiled card', () {
    expect(read('Scavenging Ooze').last, contains('IF s0 has creature card'));
  });

  test('returning cards to hand only from your own graveyard', () {
    expect(read('Macabre Waltz').single, contains('own:you in graveyard'));
    expect(read('Shipwreck Dowser').last, contains('own:you in graveyard'));
  });

  test("exiling target player's graveyard", () {
    expect(read('Angel of Finality').last, contains('own:that'));
  });

  test('token names keep their capitals', () {
    expect(read('Koma, World-Eater').last, contains("Koma's Coil"));
    expect(read('Witness Protection').last, contains('name=Legitimate Businessperson'));
  });

  test('cards named like the source', () {
    expect(read('Hare Apparent').first, contains('named ~'));
  });

  test('effects the engine cannot do correctly yet are flagged, not misread', () {
    expect(OracleParser.parse(fdn().get('Abyssal Harvester')).supported, isFalse);
  });
}
