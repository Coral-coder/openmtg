import 'dart:convert';
import 'dart:io';

import 'package:rules/rules.dart';

CardDatabase? _db;

/// The Foundations fixture (built from Scryfall by bin/build_db.dart --sets fdn).
CardDatabase fdn() => _db ??= CardDatabase.fromJson(jsonDecode(File('test/fixtures/fdn.json').readAsStringSync()) as Map<String, dynamic>);

/// Starts a two-player game with [a] and [b] as decks (padded with basic lands to 40).
Game newGame(List<String> a, List<String> b, {int seed = 1, RulesOptions rules = RulesOptions.standard}) {
  final g = Game(fdn(), players: ['Alice', 'Bob'], seed: seed);
  g.apply(StartAction([a, b], rules: rules));
  return g;
}

/// Replays [g]'s actions in a fresh game and returns the fingerprint.
String replay(Game g) {
  final r = Game(g.db, players: [for (final p in g.state.players) p.name], seed: g.state.seed);
  for (final a in g.actions) {
    r.apply(a);
  }
  return r.fingerprint;
}
