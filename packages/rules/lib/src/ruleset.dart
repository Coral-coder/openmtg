/// Magic as one ruleset of the shared card-game core (package:tcg_core).
library;

import 'package:tcg_core/tcg_core.dart';

import 'ai/bot.dart';
import 'cards/card_db.dart';
import 'game/actions.dart';
import 'game/game.dart';
import 'game/rules_options.dart';
import 'oracle/parser.dart';

class MtgRuleset implements TcgRuleset {
  const MtgRuleset(this.db);
  final CardDatabase db;

  @override
  String get id => 'mtg';

  @override
  int get engineVersion => rulesEngineVersion;

  @override
  Game newMatch(List<String> playerNames, int seed) => Game(db, players: playerNames, seed: seed);

  @override
  StartAction deal(List<List<String>> decks, Map<String, dynamic>? options) => StartAction(decks, rules: RulesOptions.fromJson(options));

  @override
  GameAction moveFromJson(Map<String, dynamic> json) => GameAction.fromJson(json);

  @override
  ConcedeAction concede(int seat) => ConcedeAction(seat);

  @override
  Bot bot(int seat, int seed) => Bot(seat, seed: seed);
}
