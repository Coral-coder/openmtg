import 'package:rules/rules.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('two bots play a whole game and the replay matches', () {
    final db = fdn();
    final a = starterDeck(db, colorPairs['Boros (RW)']!);
    final b = starterDeck(db, colorPairs['Golgari (BG)']!);
    expect(a.length, 40);
    final g = Game(db, players: ['Alice', 'Bob'], seed: 42);
    g.apply(StartAction([a, b]));
    final bots = [Bot(0, seed: 1), Bot(1, seed: 2)];
    final done = runBots(g, bots);
    expect(done, isTrue, reason: 'game should finish');
    expect(replay(g), g.fingerprint);
  });
}
