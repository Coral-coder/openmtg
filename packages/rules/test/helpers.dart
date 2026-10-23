import 'dart:convert';
import 'dart:io';

import 'package:rules/rules.dart';

CardDatabase? _db;

/// The Foundations fixture (built from Scryfall by bin/build_db.dart --sets fdn).
CardDatabase fdn() => _db ??= CardDatabase.fromJson(jsonDecode(File('test/fixtures/fdn.json').readAsStringSync()) as Map<String, dynamic>);

CardDatabase? _extra;

/// Cards from outside Foundations for rules tests (test/fixtures/extra-names.txt, cut from the
/// full database by tools/make_fixture.py).
CardDatabase extra() => _extra ??= CardDatabase.fromJson(jsonDecode(File('test/fixtures/extra.json').readAsStringSync()) as Map<String, dynamic>);

/// A fixture cut by tools/make_fixture.py.
CardDatabase loadFixture(String path) => CardDatabase.fromJson(jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>);

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

Game empty({int active = 0, CardDatabase? db}) => Game(db ?? fdn(), players: ['Alice', 'Bob'], seed: 1)..startEmpty(active: active);

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
void passTo(Game g, TurnStep step) {
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

