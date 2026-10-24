import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tcg_core/tcg_core.dart';

import '../net/protocol.dart';
import 'notifications.dart';
import 'sound.dart';

enum SessionMode { solo, hotseat, linked }

/// One match being played on this device, for any card game: applies moves, runs the computer
/// players at a readable pace, keeps the move log for saving, or defers to a [LockstepMatch]
/// when the opponent is on another device. A game's app subclasses it for its own extras (what
/// changed for animations, the table's sounds) through [afterMoves].
class MatchSession<M extends TcgMatch> extends ChangeNotifier {
  MatchSession.local({
    required this.ruleset,
    required this.mode,
    required List<String> playerNames,
    required this.seed,
    required this.decks,
    this.options,
  })  : playerNames = List.of(playerNames),
        link = null,
        match = ruleset.newMatch(playerNames, seed) as M {
    localSeat = 0;
    if (mode == SessionMode.solo) {
      for (var p = 1; p < playerNames.length; p++) {
        bots[p] = ruleset.bot(p, seed + p);
      }
    }
  }

  /// Linked (Wi‑Fi, Bluetooth or relay): the LockstepMatch owns the match.
  MatchSession.linked({required LockstepMatch link, required List<String> playerNames})
      : link = link,
        ruleset = link.ruleset,
        mode = SessionMode.linked,
        seed = 0,
        options = link.options,
        playerNames = List.of(playerNames),
        decks = const [],
        match = link.game! as M {
    localSeat = link.localSeat;
    _linkSub = link.events.listen((e) {
      if (e == 'action') _changed(remote: true);
      if (e == 'rewind' || e == 'start') _followLink();
      if (e == 'desync' || e == 'error') {
        lastError = link.error;
        notifyListeners();
      }
    });
  }

  final TcgRuleset ruleset;
  final SessionMode mode;
  final int seed;
  final Map<String, dynamic>? options;
  final List<String> playerNames;
  final List<List<String>> decks;
  final LockstepMatch? link;
  M match;
  final Map<int, TcgBot> bots = {};
  String? lastError;

  /// Something the table should say once (a rewind after reconnecting).
  String? notice;

  /// Bumped when the match is replaced under the table, so half-made choices are dropped.
  int resets = 0;
  bool thinking = false;
  late int localSeat;
  Timer? _botTimer;
  bool _botRunning = false;
  StreamSubscription<String>? _linkSub;
  void Function(Map<String, dynamic> saved)? onSave;
  void Function()? onFinished;
  bool appInForeground = true;

  /// Milliseconds between the computer's moves (Settings → speed).
  int botDelay = 450;

  bool get isLinked => mode == SessionMode.linked;
  int? get toAct => match.toAct;
  bool get isLocalTurn => toAct == localSeat;
  int get opponentSeat => playerNames.length > 1 ? (localSeat + 1) % playerNames.length : 0;

  /// Deals the match.
  void start() => perform(ruleset.deal(decks, options));

  /// Resumes a saved local match by replaying its moves.
  void replay(List<TcgMove> saved) {
    for (final a in saved) {
      try {
        match.apply(a);
      } catch (_) {
        break;
      }
    }
    afterMoves(remote: false, reset: true);
    if (mode == SessionMode.hotseat) localSeat = toAct ?? 0;
    _runBotIfNeeded();
    notifyListeners();
  }

  /// Applies a move for the local player, then lets the computer (or the link) respond.
  bool perform(TcgMove move) {
    try {
      final l = link;
      if (l != null && move.seat >= 0) {
        l.perform(move);
      } else {
        match.apply(move);
      }
      lastError = null;
      notice = null;
      _changed();
      return true;
    } on TcgError catch (e) {
      lastError = e.message;
      Console.shared.play(Fx.deny);
      notifyListeners();
      return false;
    }
  }

  void concede() => perform(ruleset.concede(localSeat));

  /// Called after moves were applied (by anyone) or the match was replaced ([reset]). A game's
  /// subclass works out what changed here, for its animations and sounds.
  @protected
  void afterMoves({required bool remote, bool reset = false}) {}

  /// How long the computer waits after making [move] before its next one.
  @protected
  int pauseAfter(TcgMove? move) => botDelay ~/ 2;

  /// What a saved game shows in the menu besides the move log.
  @protected
  Map<String, dynamic> saveExtras() => const {};

  void _followLink() {
    final l = link!;
    match = l.game! as M;
    localSeat = l.localSeat;
    notice = l.notice;
    lastError = null;
    resets++;
    afterMoves(remote: true, reset: true);
    notifyListeners();
  }

  void _changed({bool remote = false}) {
    afterMoves(remote: remote);
    if (mode == SessionMode.hotseat) {
      final p = toAct;
      if (p != null) localSeat = p;
    }
    _save();
    if (remote && !appInForeground && isLocalTurn) {
      Notifications.shared.yourMove(title: 'Your move, ${playerNames[localSeat]}', body: 'Turn ${match.turn} against ${playerNames[opponentSeat]}.');
    }
    if (match.over) onFinished?.call();
    notifyListeners();
    _runBotIfNeeded();
  }

  void _runBotIfNeeded() {
    if (mode != SessionMode.solo || match.over || _botRunning) return;
    final p = toAct;
    if (p == null || !bots.containsKey(p)) return;
    _botRunning = true;
    thinking = true;
    notifyListeners();
    _botTimer = Timer(Duration(milliseconds: botDelay), _botStep);
  }

  void _botStep() {
    final p = toAct;
    if (match.over || p == null || !bots.containsKey(p)) {
      _finishBot();
      return;
    }
    final before = match.moves.length;
    try {
      bots[p]!.step(match);
    } catch (e) {
      debugPrint('Computer move failed: $e');
      _finishBot();
      return;
    }
    final last = match.moves.length > before ? match.moves.last : null;
    afterMoves(remote: false);
    notifyListeners();
    _botTimer = Timer(Duration(milliseconds: pauseAfter(last)), _botStep);
  }

  void _finishBot() {
    _botRunning = false;
    thinking = false;
    _save();
    if (match.over) onFinished?.call();
    if (!appInForeground && !match.over) {
      Notifications.shared.yourMove(title: 'Your move, ${playerNames[localSeat]}', body: 'Turn ${match.turn}: the computer has finished.');
    }
    notifyListeners();
  }

  void _save() {
    if (mode == SessionMode.linked || match.over) return;
    onSave?.call(toJson());
  }

  Map<String, dynamic> toJson() => {
        'game': ruleset.id,
        'mode': mode.name,
        'seed': seed,
        'names': playerNames,
        'decks': decks,
        'actions': [for (final a in match.moves) a.toJson()],
        'turn': match.turn,
        ...saveExtras(),
      };

  String get saveJson => jsonEncode(toJson());

  @override
  void dispose() {
    _botTimer?.cancel();
    _linkSub?.cancel();
    super.dispose();
  }
}
