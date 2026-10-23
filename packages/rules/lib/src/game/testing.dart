part of 'game.dart';

/// Setting up positions directly, for tests and puzzles. Not used by normal play.
extension GameTesting on Game {
  /// Starts an empty game (no decks, no mulligans) at [player]'s first main phase.
  void startEmpty({PlayerId active = 0, int life = 20}) {
    state.started = true;
    state.inProgress = true;
    for (final p in state.players) {
      p.life = life;
      p.startingLife = life;
      p.kept = true;
    }
    state.turn = 2;
    state.active = active;
    state.firstPlayer = active;
    state.step = TurnStep.main1;
    state.stepDone = true;
    state.priority = active;
    // Stop everywhere so tests see every priority.
    for (final p in state.players) {
      p.stops = Stops(mine: TurnStep.values.toSet(), theirs: TurnStep.values.toSet());
    }
    state.rules = state.rules.copyWith(autoPassWhenNothingToDo: false);
    _dirty();
  }

  /// Puts a card into a zone. On the battlefield it enters without triggers and isn't summoning
  /// sick unless [sick].
  ObjId addCard(String name, PlayerId owner, Zone zone, {bool sick = false, bool tapped = false}) {
    final def = db[name];
    if (def == null) throw ArgumentError('Unknown card $name');
    final o = GameObject(id: state.nextId++, cardName: def.name, owner: owner, zone: Zone.none);
    state.objects[o.id] = o;
    _moveTo(o.id, zone);
    if (zone == Zone.battlefield) {
      o.controlSince = sick ? state.turn : 0;
      o.tapped = tapped;
      final c = chars(o.id);
      if (c.isPlaneswalker) o.counters['loyalty'] = int.tryParse(def.front.loyalty ?? '') ?? 0;
    }
    _dirty();
    return o.id;
  }

  /// Adds library cards on top (index 0 = top).
  void stackLibrary(PlayerId p, List<String> names) {
    for (final n in names.reversed) {
      addCard(n, p, Zone.library);
    }
  }

  void setStep(TurnStep s, {PlayerId? priority}) {
    state.step = s;
    state.stepDone = true;
    state.priority = priority ?? state.active;
    state.passes = 0;
    _dirty();
  }

  /// Settles the game after manual setup (state-based actions, triggers).
  void settle() => _advance();
}
