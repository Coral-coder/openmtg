/// The contract between a card game's rules and everything else (networking, saves, sessions,
/// the computer player's pacing). A match is its seed plus its ordered moves: every device that
/// applies the same moves to the same seed reaches the same state, and the fingerprint proves it.
library;

/// A move in a match: what a player did, or the deal that starts the match.
abstract class TcgMove {
  const TcgMove();

  /// The seat making the move, or -1 for the deal.
  int get seat;

  /// The move as JSON, the same on every device (it's what peers exchange and saves keep).
  Map<String, dynamic> toJson();
}

/// One match in progress.
abstract class TcgMatch {
  /// Applies [move]; throws [TcgError] if it isn't legal now (and leaves the match unchanged).
  void apply(covariant TcgMove move);

  /// A short hash of everything that matters for the rules, equal on every platform for the same
  /// seed and moves.
  String get fingerprint;

  /// The match is finished.
  bool get over;

  /// The seat that has to act now (a decision or priority), or null if nobody can.
  int? get toAct;

  /// The moves applied so far, the deal first.
  List<TcgMove> get moves;

  /// The turn number (for saves and notifications).
  int get turn;
}

/// A card game's rules: makes matches and reads moves.
abstract class TcgRuleset {
  /// Short id carried in saves and network hellos ("mtg", "lorcana").
  String get id;

  /// Bumped whenever the same moves could lead to a different game; peers must agree on it.
  int get engineVersion;

  /// A new, not yet dealt match.
  TcgMatch newMatch(List<String> playerNames, int seed);

  /// The move that deals the match: one deck (card names) per seat, plus the game's options.
  TcgMove deal(List<List<String>> decks, Map<String, dynamic>? options);

  TcgMove moveFromJson(Map<String, dynamic> json);

  /// [seat] concedes the match.
  TcgMove concede(int seat);

  /// A computer player for [seat].
  TcgBot bot(int seat, int seed);
}

/// A computer player: deterministic given its seed.
abstract class TcgBot {
  /// Makes this bot's next move in [match]; returns false if it had nothing to do.
  bool step(covariant TcgMatch match);
}

/// An illegal move or an impossible request.
class TcgError implements Exception {
  TcgError(this.message);
  final String message;
  @override
  String toString() => message;
}
