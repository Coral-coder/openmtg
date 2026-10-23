import 'package:flutter/foundation.dart';
import 'package:rules/rules.dart';

import '../app/session.dart';
import '../app/sound.dart';

/// What the local player is in the middle of choosing on the table: targets, attackers,
/// blockers, mana sources. Turned into one answer when they confirm.
class TableController extends ChangeNotifier {
  TableController(this.session);
  final GameSession session;

  Game get game => session.game;
  GameState get state => session.state;
  PlayerId get me => session.localSeat;

  /// Selected entities for a targets/cards decision.
  final List<int> selected = [];

  /// Attacker → what it attacks.
  final Map<int, int> attacks = {};

  /// Blocker → attacker.
  final Map<int, int> blocks = {};
  int? pickedBlocker;

  /// Manual mana payment: (source, ability index, mana type index).
  final List<(int, int, int)> payment = [];

  String? _decisionKey;

  bool get isLocalPriority => state.pending == null && state.priority == me && !state.over;

  Set<int>? _legal;
  int _legalVersion = -1;
  GameState? _legalState;

  /// Cards the local player can do something with now (lit on the table).
  Set<int> get legalCards {
    if (_legal != null && _legalVersion == state.version && identical(_legalState, state)) return _legal!;
    final out = <int>{};
    if (isLocalPriority) {
      for (final a in game.legalActions(me)) {
        switch (a) {
          case PlayLandAction(:final id) || CastAction(:final id) || ActivateAbilityAction(:final id):
            out.add(id);
          default:
        }
      }
    }
    _legal = out;
    _legalVersion = state.version;
    _legalState = state;
    return out;
  }

  Decision? get decision {
    final pd = state.pending;
    if (pd == null || pd.decision.player != me) return null;
    return pd.decision;
  }

  /// Clears half-made choices when the decision changes.
  void sync() {
    final d = state.pending?.decision;
    final key = d == null ? null : '${session.resets}|${state.pending!.answers.length}|${d.digest()}';
    if (key == _decisionKey) return;
    _decisionKey = key;
    selected.clear();
    attacks.clear();
    blocks.clear();
    pickedBlocker = null;
    payment.clear();
    if (d != null && d.kind == DecisionKind.attackers) {
      // Creatures that must attack start selected.
      for (final id in ((d.extra['must'] as List?) ?? const []).cast<int>()) {
        attacks[id] = defaultAttackTarget(d, id);
      }
    }
  }

  int defaultAttackTarget(Decision d, int attacker) {
    final opts = (d.extra['$attacker'] as List).cast<int>();
    return opts.firstWhere(isPlayerEntity, orElse: () => opts.first);
  }

  /// Whether tapping [entity] does something for the current decision.
  bool isChoosable(int entity) {
    final d = decision;
    if (d == null) return false;
    switch (d.kind) {
      case DecisionKind.targets || DecisionKind.cards:
        return d.options.contains(entity);
      case DecisionKind.attackers:
        return d.options.contains(entity);
      case DecisionKind.blockers:
        if (d.options.contains(entity)) return true;
        final b = pickedBlocker;
        return b != null && ((d.extra['$b'] as List?)?.contains(entity) ?? false);
      case DecisionKind.payMana:
        return _manaSourceIndex(entity) != null;
      default:
        return false;
    }
  }

  bool isSelected(int entity) => selected.contains(entity) || attacks.containsKey(entity) || blocks.containsKey(entity) || pickedBlocker == entity || payment.any((p) => p.$1 == entity);

  /// A tap on a card or player while a decision is open. Returns true if it was used.
  bool tap(int entity) {
    final d = decision;
    if (d == null) return false;
    switch (d.kind) {
      case DecisionKind.targets || DecisionKind.cards:
        if (!d.options.contains(entity)) return false;
        if (selected.contains(entity)) {
          selected.remove(entity);
        } else {
          if (selected.length >= d.max) {
            if (d.max == 1) {
              selected.clear();
            } else {
              return true;
            }
          }
          selected.add(entity);
        }
        Console.shared.play(Fx.tap);
        // A single required choice answers at once.
        if (d.min == 1 && d.max == 1 && selected.length == 1) {
          confirm();
          return true;
        }
        notifyListeners();
        return true;
      case DecisionKind.attackers:
        if (!d.options.contains(entity)) return false;
        if (attacks.containsKey(entity)) {
          attacks.remove(entity);
        } else {
          attacks[entity] = defaultAttackTarget(d, entity);
        }
        Console.shared.play(Fx.tap);
        notifyListeners();
        return true;
      case DecisionKind.blockers:
        if (d.options.contains(entity)) {
          if (blocks.containsKey(entity)) {
            blocks.remove(entity);
            pickedBlocker = null;
          } else {
            pickedBlocker = pickedBlocker == entity ? null : entity;
            // Only one attacker it can block: assign it at once.
            final can = (d.extra['$entity'] as List).cast<int>();
            if (pickedBlocker != null && can.length == 1) {
              blocks[entity] = can.first;
              pickedBlocker = null;
            }
          }
          Console.shared.play(Fx.tap);
          notifyListeners();
          return true;
        }
        final b = pickedBlocker;
        if (b != null && ((d.extra['$b'] as List).contains(entity))) {
          blocks[b] = entity;
          pickedBlocker = null;
          Console.shared.play(Fx.tap);
          notifyListeners();
          return true;
        }
        return false;
      case DecisionKind.payMana:
        final idx = _manaSourceIndex(entity);
        if (idx == null) return false;
        final existing = payment.indexWhere((p) => p.$1 == entity);
        if (existing >= 0) {
          payment.removeAt(existing);
        } else {
          final ab = game.chars(entity).abilities[idx] as ManaAbility;
          payment.add((entity, idx, ab.produce.possible.first.index));
        }
        Console.shared.play(Fx.tap);
        notifyListeners();
        return true;
      default:
        return false;
    }
  }

  /// Sets the mana type a chosen source makes (for "{R} or {G}" lands).
  void setPaymentType(int source, int type) {
    final i = payment.indexWhere((p) => p.$1 == source);
    if (i < 0) return;
    payment[i] = (source, payment[i].$2, type);
    notifyListeners();
  }

  int? _manaSourceIndex(int entity) {
    if (isPlayerEntity(entity)) return null;
    final o = state.objOrNull(entity);
    if (o == null || o.zone != Zone.battlefield || o.tapped) return null;
    final c = game.chars(entity);
    if (c.controller != me) return null;
    for (var i = 0; i < c.abilities.length; i++) {
      if (c.abilities[i] is ManaAbility) return i;
    }
    return null;
  }

  /// Whether the current selection is a complete answer.
  bool get canConfirm {
    final d = decision;
    if (d == null) return false;
    switch (d.kind) {
      case DecisionKind.targets || DecisionKind.cards:
        return selected.length >= d.min && selected.length <= d.max;
      default:
        return true;
    }
  }

  void confirm() {
    final d = decision;
    if (d == null) return;
    switch (d.kind) {
      case DecisionKind.targets || DecisionKind.cards:
        answer(List.of(selected));
      case DecisionKind.attackers:
        answer([for (final e in attacks.entries) ...[e.key, e.value]]);
      case DecisionKind.blockers:
        answer([for (final e in blocks.entries) ...[e.key, e.value]]);
      case DecisionKind.payMana:
        answer([for (final p in payment) ...[p.$1, p.$2, p.$3]]);
      default:
        answer(const []);
    }
  }

  void answer(List<int> a) {
    final ok = session.perform(AnswerAction(me, a));
    if (ok) Console.shared.play(Fx.confirm);
    notifyListeners();
  }

  void cancel() {
    session.perform(CancelAction(me));
    notifyListeners();
  }

  void perform(GameAction a) {
    session.perform(a);
    notifyListeners();
  }
}
