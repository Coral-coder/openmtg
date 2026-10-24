/// Everything a player can do (CR 116, 117, 601, 602, 605): the unit of replay and of lockstep
/// sync. A game is its seed plus its ordered actions. Each action names the player making it.
library;

import 'package:tcg_core/tcg_core.dart';

import 'rules_options.dart';
import 'state.dart';

sealed class GameAction extends TcgMove {
  const GameAction(this.player);

  /// Who acts (-1 for the start action).
  final PlayerId player;

  @override
  int get seat => player;

  @override
  Map<String, dynamic> toJson();

  static GameAction fromJson(Map<String, dynamic> j) {
    final p = j['p'] as int? ?? -1;
    switch (j['t'] as String) {
      case 'start':
        return StartAction([for (final d in j['decks'] as List) (d as List).cast<String>()], rules: RulesOptions.fromJson(j['rules'] as Map<String, dynamic>?));
      case 'answer':
        return AnswerAction(p, (j['a'] as List).cast<int>());
      case 'cancel':
        return CancelAction(p);
      case 'land':
        return PlayLandAction(p, j['id'] as int, face: j['f'] as int? ?? 0);
      case 'cast':
        return CastAction(p, j['id'] as int, face: j['f'] as int? ?? 0, option: j['o'] as int? ?? -1);
      case 'activate':
        return ActivateAbilityAction(p, j['id'] as int, j['i'] as int);
      case 'mana':
        return ManaAction(p, j['id'] as int, j['i'] as int, j['m'] as int? ?? -1);
      case 'pass':
        return PassAction(p);
      case 'concede':
        return ConcedeAction(p);
      case 'stops':
        return StopsAction(p, Stops.fromJson((j['s'] as Map).cast<String, dynamic>()));
      case 'passTurn':
        return PassTurnAction(p);
    }
    throw ArgumentError('Unknown action ${j['t']}');
  }

  @override
  bool operator ==(Object other) => other is GameAction && other.runtimeType == runtimeType && _eq(toJson(), other.toJson());

  @override
  int get hashCode => toJson().toString().hashCode;

  static bool _eq(Object? a, Object? b) => a.toString() == b.toString();

  @override
  String toString() => toJson().toString();
}

/// Starts the game: one deck (card names) per seat, and the rules.
class StartAction extends GameAction {
  const StartAction(this.decks, {this.rules = RulesOptions.standard}) : super(-1);
  final List<List<String>> decks;
  final RulesOptions rules;
  @override
  Map<String, dynamic> toJson() => {'t': 'start', 'decks': decks, if (!rules.isStandard) 'rules': rules.toJson()};
}

/// Answers the pending decision.
class AnswerAction extends GameAction {
  const AnswerAction(super.player, this.answer);
  final List<int> answer;
  @override
  Map<String, dynamic> toJson() => {'t': 'answer', 'p': player, 'a': answer};
}

/// Backs out of casting a spell or activating an ability (before costs are paid).
class CancelAction extends GameAction {
  const CancelAction(super.player);
  @override
  Map<String, dynamic> toJson() => {'t': 'cancel', 'p': player};
}

class PlayLandAction extends GameAction {
  const PlayLandAction(super.player, this.id, {this.face = 0});
  final ObjId id;
  final int face;
  @override
  Map<String, dynamic> toJson() => {'t': 'land', 'p': player, 'id': id, if (face != 0) 'f': face};
}

class CastAction extends GameAction {
  const CastAction(super.player, this.id, {this.face = 0, this.option = -1});
  final ObjId id;
  final int face;

  /// A cast option (flashback, alternative cost) chosen up front, or -1.
  final int option;
  @override
  Map<String, dynamic> toJson() => {'t': 'cast', 'p': player, 'id': id, if (face != 0) 'f': face, if (option != -1) 'o': option};
}

/// Activates the [index]th ability of an object (index into its current abilities).
class ActivateAbilityAction extends GameAction {
  const ActivateAbilityAction(super.player, this.id, this.index);
  final ObjId id;
  final int index;
  @override
  Map<String, dynamic> toJson() => {'t': 'activate', 'p': player, 'id': id, 'i': index};
}

/// Activates a mana ability outside of paying a cost (CR 605.3a), choosing mana type [type]
/// (ManaType index) when it has a choice.
class ManaAction extends GameAction {
  const ManaAction(super.player, this.id, this.index, [this.type = -1]);
  final ObjId id;
  final int index;
  final int type;
  @override
  Map<String, dynamic> toJson() => {'t': 'mana', 'p': player, 'id': id, 'i': index, if (type != -1) 'm': type};
}

class PassAction extends GameAction {
  const PassAction(super.player);
  @override
  Map<String, dynamic> toJson() => {'t': 'pass', 'p': player};
}

/// Pass priority until the end of the turn unless something needs a response.
class PassTurnAction extends GameAction {
  const PassTurnAction(super.player);
  @override
  Map<String, dynamic> toJson() => {'t': 'passTurn', 'p': player};
}

/// A player leaves the game (CR 104.3a), at any time.
class ConcedeAction extends GameAction {
  const ConcedeAction(super.player);
  @override
  Map<String, dynamic> toJson() => {'t': 'concede', 'p': player};
}

/// Sets where the game stops to give this player priority.
class StopsAction extends GameAction {
  const StopsAction(super.player, this.stops);
  final Stops stops;
  @override
  Map<String, dynamic> toJson() => {'t': 'stops', 'p': player, 's': stops.toJson()};
}
