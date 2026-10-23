/// Plays seeded bot games and prints each game's fingerprint, one per line. The same program
/// runs on the Dart VM and compiled to JavaScript (tool/xplat_check.sh compares the two): a
/// browser and a phone in the same match must agree on every state.
///
///     dart run tool/xplat.dart <cards.json> [games] [--random-decks]
library;

import 'dart:convert';

import 'package:rules/rules.dart';

import 'xplat_io.dart' if (dart.library.js_interop) 'xplat_js.dart';

void main(List<String> argv) {
  final args = programArgs(argv);
  final db = CardDatabase.fromJson(jsonDecode(readText(args[0])) as Map<String, dynamic>);
  final games = args.length > 1 ? int.parse(args[1]) : 20;
  final random = args.contains('--random-decks');
  final pairs = colorPairs.keys.toList();
  final pool = [
    for (final c in db.cards)
      if (!c.front.isLand && c.manaValue > 0 && c.manaValue <= 6 && c.colorIdentity.isNotEmpty && OracleParser.parse(c).supported) c,
  ];
  final rng = SeededRng(7);
  for (var n = 0; n < games; n++) {
    final seed = rng.nextInt(1 << 30);
    final picks = [pairs[rng.nextInt(pairs.length)], pairs[rng.nextInt(pairs.length)]];
    final decks = [
      for (final p in picks)
        random ? _deck(pool, colorPairs[p]!, rng) : starterDeck(db, colorPairs[p]!),
    ];
    final g = Game(db, players: ['A', 'B'], seed: seed);
    final probe = args.indexOf('--probe');
    if (probe >= 0 && int.parse(args[probe + 1]) == n) {
      g.apply(StartAction(decks));
      final bots = [Bot(0, seed: seed), Bot(1, seed: seed + 1)];
      for (var i = 0; i < int.parse(args[probe + 2]); i++) {
        final d = g.state.pending?.decision;
        final p = d?.player ?? g.state.priority!;
        bots[p].step(g);
      }
      final d = g.state.pending!.decision;
      writeLine('decision ${d.kind} ${d.prompt} min ${d.min} max ${d.max}');
      for (final id in d.options) {
        final c = g.chars(id);
        writeLine('  $id ${c.name} land=${c.isLand} mv=${c.manaValue}');
      }
      writeLine('digest ${g.fingerprint}');
      writeLine('bot answers ${bots[d.player].answer(g, d)}');
      continue;
    }
    try {
      g.apply(StartAction(decks));
      runBots(g, [Bot(0, seed: seed), Bot(1, seed: seed + 1)], maxActions: 3000);
      writeLine('$n ${g.state.turn} ${g.actions.length} ${g.fingerprint}');
      if (args.contains('--digest')) writeLine(g.state.digest());
      if (args.contains('--actions')) {
        for (final a in g.actions) {
          writeLine(jsonEncode(a.toJson()));
        }
      }
    } catch (e) {
      writeLine('$n error after ${g.actions.length} actions: ${e.runtimeType}');
    }
  }
}

List<String> _deck(List<CardDef> pool, Set<ManaColor> colors, SeededRng rng) {
  final fits = [for (final c in pool) if (c.colorIdentity.every(colors.contains)) c.name];
  const basics = {ManaColor.white: 'Plains', ManaColor.blue: 'Island', ManaColor.black: 'Swamp', ManaColor.red: 'Mountain', ManaColor.green: 'Forest'};
  final cs = colors.toList()..sort((a, b) => a.index - b.index);
  return [
    for (var i = 0; i < 23; i++) fits[rng.nextInt(fits.length)],
    for (var i = 0; i < 17; i++) basics[cs[i % cs.length]]!,
  ];
}
