import 'package:rules/rules.dart';
import 'package:tcg_app/tcg_app.dart';

export 'package:tcg_app/tcg_app.dart' show SessionMode;

/// A Magic game on this device: the shared [MatchSession] (modes, computer pacing, saving, the
/// link) plus what the Magic table needs — the log entries each change added (for animations),
/// the end-of-game sound, and reasons a move isn't possible.
class GameSession extends MatchSession<Game> {
  GameSession.local({required super.mode, required super.playerNames, required super.seed, required super.decks, required this.db, this.rules = RulesOptions.standard})
      : super.local(ruleset: MtgRuleset(db), options: rules.toJson());

  /// Linked (Wi‑Fi, Bluetooth or relay): the LockstepMatch owns the game.
  GameSession.linked({required LockstepMatch match, required this.db})
      : rules = RulesOptions.standard,
        super.linked(link: match, playerNames: [for (final p in (match.game! as Game).state.players) p.name]) {
    _lastLog = game.state.log.length;
  }

  final RulesOptions rules;
  final CardDatabase db;

  /// Log entries added by the last change, for animations and sounds.
  List<LogEntry> recent = [];
  int _lastLog = 0;

  Game get game => match;
  GameState get state => match.state;
  List<GameAction> get actions => match.actions;

  @override
  int get opponentSeat => state.opponents(localSeat).firstOrNull ?? (1 - localSeat);

  /// Why [action] isn't possible right now, or null if it is.
  String? whyNot(GameAction action) => game.whyNot(action);

  @override
  void afterMoves({required bool remote, bool reset = false}) {
    if (reset) {
      // A replaced game (rewind, resume): its history isn't news.
      if (isLinked) {
        playerNames
          ..clear()
          ..addAll([for (final p in state.players) p.name]);
      }
      _lastLog = state.log.length;
      recent = [];
      return;
    }
    final fresh = state.log.length >= _lastLog ? state.log.sublist(_lastLog) : state.log.toList();
    _lastLog = state.log.length;
    recent = fresh;
    for (final e in fresh) {
      // The table's effects layer (ui/fx.dart) plays the sounds for what happens on the table.
      if (e.kind == 'lose') Console.shared.play(e.player == localSeat ? Fx.defeat : Fx.victory);
    }
  }

  @override
  int pauseAfter(TcgMove? move) => switch (move) {
        CastAction() || PlayLandAction() || ActivateAbilityAction() => botDelay + 300,
        AnswerAction() => botDelay ~/ 2,
        _ => botDelay ~/ 3,
      };
}
