import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rules/rules.dart';

import 'package:tcg_app/tcg_app.dart';

enum SessionMode { solo, hotseat, linked }

/// One game being played on this device: drives the engine, runs the computer player, keeps the
/// action log for saving, or defers to a LockstepMatch when the opponent is on another device.
class GameSession extends ChangeNotifier {
  GameSession.local({required this.mode, required List<String> playerNames, required this.seed, required this.decks, required this.db, this.rules = RulesOptions.standard})
      : playerNames = List.of(playerNames),
        match = null,
        game = Game(db, players: playerNames, seed: seed) {
    localSeat = 0;
    if (mode == SessionMode.solo) {
      for (var p = 1; p < playerNames.length; p++) {
        bots[p] = Bot(p, seed: seed + p);
      }
    }
  }

  /// Linked (LAN, Bluetooth or relay): the LockstepMatch owns the game.
  GameSession.linked({required LockstepMatch match, required this.db})
      : mode = SessionMode.linked,
        seed = 0,
        rules = RulesOptions.standard,
        match = match,
        playerNames = [for (final p in (match.game! as Game).state.players) p.name],
        decks = const [],
        game = match.game! as Game {
    localSeat = match.localSeat;
    _lastLog = game.state.log.length;
    _matchSub = match.events.listen((e) {
      if (e == 'action') _afterChange(remote: true);
      if (e == 'rewind' || e == 'start') _followMatch();
      if (e == 'desync' || e == 'error') {
        lastError = match.error;
        notifyListeners();
      }
    });
  }

  final SessionMode mode;
  final int seed;
  final RulesOptions rules;
  final List<String> playerNames;
  final List<List<String>> decks;
  final CardDatabase db;
  final LockstepMatch? match;
  Game game;
  final Map<int, Bot> bots = {};
  String? lastError;

  /// Something the table should say once (a rewind after reconnecting).
  String? notice;

  /// Bumped when the game is replaced under the table, so half-made choices are dropped.
  int resets = 0;

  /// Log entries added by the last change, for animations and sounds.
  List<LogEntry> recent = [];
  bool thinking = false;
  late PlayerId localSeat;
  int _lastLog = 0;
  Timer? _botTimer;
  bool _botRunning = false;
  StreamSubscription<String>? _matchSub;
  void Function(Map<String, dynamic> saved)? onSave;
  void Function()? onFinished;
  bool appInForeground = true;

  /// Milliseconds between the computer's moves (Settings → speed).
  int botDelay = 450;

  GameState get state => game.state;
  bool get isLinked => mode == SessionMode.linked;
  List<GameAction> get actions => game.actions;

  /// The player who must act now: the pending decision's owner, or who has priority.
  PlayerId? get toAct => state.pending?.decision.player ?? state.priority;
  bool get isLocalTurn => toAct == localSeat;
  PlayerId get opponentSeat => state.opponents(localSeat).firstOrNull ?? (1 - localSeat);

  void start() => perform(StartAction(decks, rules: rules));

  /// Resumes a saved local game by replaying its actions.
  void replay(List<GameAction> saved) {
    for (final a in saved) {
      try {
        game.apply(a);
      } catch (_) {
        break;
      }
    }
    _lastLog = state.log.length;
    if (mode == SessionMode.hotseat) localSeat = toAct ?? 0;
    _runBotIfNeeded();
    notifyListeners();
  }

  /// Applies an action for the local player, then lets the bot (or the link) respond.
  bool perform(GameAction action) {
    try {
      final m = match;
      if (m != null && action is! StartAction) {
        m.perform(action);
      } else {
        game.apply(action);
      }
      lastError = null;
      notice = null;
      _afterChange();
      return true;
    } on GameError catch (e) {
      lastError = e.message;
      Console.shared.play(Fx.deny);
      notifyListeners();
      return false;
    }
  }

  /// Why [action] isn't possible right now, or null if it is.
  String? whyNot(GameAction action) => game.whyNot(action);

  void _followMatch() {
    final m = match!;
    game = m.game! as Game;
    localSeat = m.localSeat;
    playerNames
      ..clear()
      ..addAll([for (final p in game.state.players) p.name]);
    _lastLog = state.log.length;
    recent = [];
    notice = m.notice;
    lastError = null;
    resets++;
    notifyListeners();
  }

  void _afterChange({bool remote = false}) {
    final fresh = state.log.length >= _lastLog ? state.log.sublist(_lastLog) : state.log.toList();
    _lastLog = state.log.length;
    recent = fresh;
    for (final e in fresh) {
      _sound(e);
    }
    if (mode == SessionMode.hotseat) {
      final p = toAct;
      if (p != null) localSeat = p;
    }
    _save();
    if (remote && !appInForeground && isLocalTurn) {
      Notifications.shared.yourMove(title: 'Your move, ${playerNames[localSeat]}', body: 'Turn ${state.turn} against ${playerNames[opponentSeat]}.');
    }
    if (state.over) onFinished?.call();
    notifyListeners();
    _runBotIfNeeded();
  }

  void _sound(LogEntry e) {
    // The table's effects layer (ui/fx.dart) plays the sounds for what happens on the table.
    switch (e.kind) {
      case 'lose':
        Console.shared.play(e.player == localSeat ? Fx.defeat : Fx.victory);
    }
  }

  void _runBotIfNeeded() {
    if (mode != SessionMode.solo || state.over || _botRunning) return;
    final p = toAct;
    if (p == null || !bots.containsKey(p)) return;
    _botRunning = true;
    thinking = true;
    notifyListeners();
    _botTimer = Timer(Duration(milliseconds: botDelay), _botStep);
  }

  void _botStep() {
    final p = toAct;
    if (state.over || p == null || !bots.containsKey(p)) {
      _finishBot();
      return;
    }
    final before = game.actions.length;
    try {
      bots[p]!.step(game);
    } catch (e) {
      debugPrint('Computer move failed: $e');
      _finishBot();
      return;
    }
    final last = game.actions.length > before ? game.actions.last : null;
    final fresh = state.log.length >= _lastLog ? state.log.sublist(_lastLog) : state.log.toList();
    _lastLog = state.log.length;
    recent = fresh;
    for (final e in fresh) {
      _sound(e);
    }
    notifyListeners();
    final pause = switch (last) {
      CastAction() || PlayLandAction() || ActivateAbilityAction() => botDelay + 300,
      AnswerAction() => botDelay ~/ 2,
      _ => botDelay ~/ 3,
    };
    _botTimer = Timer(Duration(milliseconds: pause), _botStep);
  }

  void _finishBot() {
    _botRunning = false;
    thinking = false;
    _save();
    if (state.over) onFinished?.call();
    if (!appInForeground && !state.over) {
      Notifications.shared.yourMove(title: 'Your move, ${playerNames[localSeat]}', body: 'Turn ${state.turn}: the computer has finished.');
    }
    notifyListeners();
  }

  void _save() {
    if (mode == SessionMode.linked || state.over) return;
    onSave?.call(toJson());
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'seed': seed,
        'names': playerNames,
        'decks': decks,
        'actions': [for (final a in game.actions) a.toJson()],
        'turn': state.turn,
      };

  String get saveJson => jsonEncode(toJson());

  void concede() => perform(ConcedeAction(localSeat));

  @override
  void dispose() {
    _botTimer?.cancel();
    _matchSub?.cancel();
    super.dispose();
  }
}
