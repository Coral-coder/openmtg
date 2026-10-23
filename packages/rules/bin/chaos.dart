/// Chaos harness: plays many bot games from random seeds and decks, then replays each one from
/// its action log and checks that every fingerprint matches (determinism). Runs in CI and before
/// every push.
///
///     dart run rules:chaos [--db test/fixtures/fdn.json] [--games 200] [--seed 1] [--verbose]
///         [--random-decks]   seeded random two-color decks from every supported card in the db
library;

import 'dart:convert';
import 'dart:io';

import 'package:rules/rules.dart';

void main(List<String> args) {
  var dbPath = 'test/fixtures/fdn.json';
  var games = 200;
  var seed = 1;
  var verbose = false;
  var players = 2;
  var randomDecks = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--db':
        dbPath = args[++i];
      case '--games':
        games = int.parse(args[++i]);
      case '--seed':
        seed = int.parse(args[++i]);
      case '--players':
        players = int.parse(args[++i]);
      case '--verbose':
        verbose = true;
      case '--random-decks':
        randomDecks = true;
    }
  }
  final db = CardDatabase.fromJson(jsonDecode(File(dbPath).readAsStringSync()) as Map<String, dynamic>);
  final decks = {for (final e in colorPairs.entries) e.key: starterDeck(db, e.value)};
  final names = decks.keys.toList();
  // Every supported spell, for random decks.
  final pool = randomDecks
      ? [
          for (final c in db.cards)
            if (!c.front.isLand && c.manaValue > 0 && c.manaValue <= 6 && c.colorIdentity.isNotEmpty && OracleParser.parse(c).supported) c,
        ]
      : const <CardDef>[];
  final rng = SeededRng(seed);
  var finished = 0, failures = 0, totalTurns = 0, totalActions = 0;
  final wins = <String, int>{};
  final sw = Stopwatch()..start();
  for (var n = 0; n < games; n++) {
    final gameSeed = rng.nextInt(1 << 30);
    final picks = [for (var p = 0; p < players; p++) names[rng.nextInt(names.length)]];
    final lists = [for (final p in picks) randomDecks ? _randomDeck(pool, colorPairs[p]!, rng) : decks[p]!];
    final g = Game(db, players: [for (var p = 0; p < players; p++) 'P$p ${picks[p]}'], seed: gameSeed);
    final bots = [for (var p = 0; p < players; p++) Bot(p, seed: gameSeed + p)];
    try {
      g.apply(StartAction(lists));
      final done = runBots(g, bots, maxActions: 6000);
      final fp = g.fingerprint;
      final r = Game(db, players: [for (final p in g.state.players) p.name], seed: gameSeed);
      for (final a in g.actions) {
        r.apply(a);
      }
      if (r.fingerprint != fp) throw StateError('Replay fingerprint differs');
      // A JSON round trip of the log must replay identically too (what peers exchange).
      final r2 = Game(db, players: [for (final p in g.state.players) p.name], seed: gameSeed);
      for (final a in g.actions) {
        r2.apply(GameAction.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>));
      }
      if (r2.fingerprint != fp) throw StateError('JSON replay fingerprint differs');
      if (done) {
        finished++;
        final w = g.state.winner;
        if (w != null) wins[picks[w]] = (wins[picks[w]] ?? 0) + 1;
      }
      totalTurns += g.state.turn;
      totalActions += g.actions.length;
      if (verbose) stdout.writeln('game $n seed $gameSeed ${picks.join(' vs ')}: ${done ? 'won by ${g.state.winner == null ? 'nobody' : picks[g.state.winner!]}' : 'unfinished'} on turn ${g.state.turn}, ${g.actions.length} actions');
    } catch (e, st) {
      failures++;
      stderr.writeln('FAIL game $n seed $gameSeed ${picks.join(' vs ')} after ${g.actions.length} actions, turn ${g.state.turn}: $e');
      if (verbose || failures <= 3) {
        stderr.writeln(st.toString().split('\n').take(12).join('\n'));
        final log = g.state.log;
        stderr.writeln(log.skip(log.length > 15 ? log.length - 15 : 0).map((l) => '   | ${l.text}').join('\n'));
      }
    }
  }
  stdout.writeln('$games games: $finished finished, $failures failed, avg ${(totalTurns / games).toStringAsFixed(1)} turns, ${(totalActions / games).toStringAsFixed(0)} actions, ${sw.elapsedMilliseconds} ms');
  stdout.writeln('wins: ${wins.entries.map((e) => '${e.key} ${e.value}').join(', ')}');
  if (failures > 0) exitCode = 1;
}

/// 23 random supported spells in [colors] (seeded), with basic lands split between the colors.
List<String> _randomDeck(List<CardDef> pool, Set<ManaColor> colors, SeededRng rng) {
  final fits = [for (final c in pool) if (c.colorIdentity.every(colors.contains)) c.name];
  final deck = <String>[];
  for (var i = 0; i < 23 && fits.isNotEmpty; i++) {
    deck.add(fits[rng.nextInt(fits.length)]);
  }
  const basics = {ManaColor.white: 'Plains', ManaColor.blue: 'Island', ManaColor.black: 'Swamp', ManaColor.red: 'Mountain', ManaColor.green: 'Forest'};
  final cs = colors.toList()..sort((a, b) => a.index - b.index);
  for (var i = 0; i < 17; i++) {
    deck.add(basics[cs[i % cs.length]]!);
  }
  return deck;
}
