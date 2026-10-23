part of 'game.dart';

/// Energy (CR 122.1), paying while resolving, clash (CR 701.23), amass (CR 701.47), bolster
/// (CR 701.39), populate (CR 701.30), untap skipping, extra turns, and choosing objects that
/// aren't targets ("return a land you control to its owner's hand").
extension GameMoreEffects on Game {
  void _execMore(Effect e, EvalCtx ctx) {
    switch (e) {
      case GetEnergy(:final amount, :final who, :final poison):
        final n = evalAmount(amount, ctx);
        if (n <= 0) return;
        for (final p in resolvePlayers(who, ctx)) {
          if (poison) {
            state.player(p).poison += n;
            _log('${state.player(p).name} gets $n poison counter${n == 1 ? '' : 's'}.', player: p);
          } else {
            state.player(p).energy += n;
            _log('${state.player(p).name} gets $n energy.', player: p);
          }
        }
      case PayEffect(:final mana, :final life, :final energy):
        final p = ctx.controller;
        final pl = state.player(p);
        final can = (mana == null || canAfford(p, mana)) && pl.life >= life && pl.energy >= energy;
        if (!can) {
          ctx.results['did'] = 0;
          return;
        }
        if (mana != null) _payMana(p, mana, prompt: 'Pay ${mana.text}');
        if (life > 0) _loseLife(p, life);
        pl.energy -= energy;
        ctx.results['did'] = 1;
      case Clash():
        _clash(ctx);
      case Amass(:final subtype, :final amount):
        final p = ctx.controller;
        bool isArmy(ObjId id) => chars(id).controller == p && chars(id).hasSubtype('Army');
        if (!state.battlefield.any(isArmy)) {
          _createToken(TokenSpec(name: '$subtype Army', power: 0, toughness: 0, colors: const {ManaColor.black}, subtypes: [subtype, 'Army']), p, ctx: ctx);
        }
        final armies = [for (final id in state.battlefield) if (isArmy(id)) id];
        if (armies.isEmpty) return;
        final pick = armies.length == 1 ? armies : ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Amass: choose an Army', options: armies, min: 1, max: 1, source: ctx.source));
        final army = pick.first;
        final o = state.obj(army);
        if (!chars(army).hasSubtype(subtype) && !o.extraTypes.contains(subtype)) o.extraTypes.add(subtype);
        _addCounters(army, '+1/+1', evalAmount(amount, ctx), by: p);
        ctx.remembered['amassed'] = [(army, o.zcc)];
      case Bolster(:final amount):
        final p = ctx.controller;
        final mine = [for (final id in state.battlefield) if (chars(id).controller == p && chars(id).isCreature) id];
        if (mine.isEmpty) return;
        int toughness(ObjId id) => (chars(id).toughness ?? 0) - state.obj(id).damage;
        final least = mine.map(toughness).reduce((a, b) => a < b ? a : b);
        final options = [for (final id in mine) if (toughness(id) == least) id];
        final pick = options.length == 1 ? options : ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Bolster: choose a creature with the least toughness', options: options, min: 1, max: 1, source: ctx.source));
        _addCounters(pick.first, '+1/+1', evalAmount(amount, ctx), by: p);
      case SkipNextUntap(:final set):
        for (final id in resolveObjs(set, ctx)) {
          if (state.obj(id).zone == Zone.battlefield) state.obj(id).skipUntap++;
        }
      case ExtraTurn(:final who):
        for (final p in resolvePlayers(who, ctx)) {
          state.extraTurns.add(p);
          _log('${state.player(p).name} will take an extra turn.', player: p);
        }
      case ChooseAndMove(:final filter, :final from, :final to, :final who, :final amount, :final tapped):
        var did = 0;
        for (final p in resolvePlayers(who, ctx)) {
          final pctx = ctx.withThatPlayer(p)..controller = p;
          final List<ObjId> pool = switch (from) {
            ZoneKind.battlefield => [for (final id in state.battlefield) if (chars(id).controller == p) id],
            ZoneKind.hand => state.player(p).hand,
            ZoneKind.graveyard => state.player(p).graveyard,
            _ => const [],
          };
          final options = [for (final id in pool) if (matchesFilter(filter.copyWith(controller: Who.any, owner: Who.any, zone: ZoneKind.anywhere), id, pctx)) id];
          final n = evalAmount(amount, ctx).clamp(0, options.length);
          if (n == 0) continue;
          final pick = ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Choose ${n == 1 ? 'a' : n} ${_describeFilter(filter)}', options: options, min: n, max: n, source: ctx.source));
          for (final id in pick) {
            switch (to) {
              case ZoneKind.battlefield:
                _putOntoBattlefield(id, p, tapped: tapped);
              default:
                _move(id, zoneOfKind(to));
            }
            did++;
          }
        }
        ctx.results['did'] = did;
      case Populate():
        final p = ctx.controller;
        final options = [for (final id in state.battlefield) if (chars(id).controller == p && chars(id).isCreature && state.obj(id).isToken) id];
        if (options.isEmpty) return;
        final pick = options.length == 1 ? options : ask(Decision(kind: DecisionKind.cards, player: p, prompt: 'Populate: choose a creature token to copy', options: options, min: 1, max: 1, source: ctx.source));
        ctx.remembered['populate'] = [(pick.first, state.obj(pick.first).zcc)];
        _exec(const CreateCopy(Remembered('populate')), ctx);
      case AtNextEndStep(:final set, :final sacrifice, :final exile, :final toHand, :final underYourControl, :final step):
        for (final id in resolveObjs(set, ctx)) {
          final o = state.obj(id);
          // The delayed trigger follows this object (CR 603.7c), so it can name it as itself.
          final Effect effect = sacrifice
              ? const Sacrifice(You(), Filter.any, Fixed(1), self: true)
              : (exile
                  ? const MoveTo(One(EventObj()), ZoneKind.exile)
                  : (toHand ? const MoveTo(One(EventObj()), ZoneKind.hand) : MoveTo(const One(EventObj()), ZoneKind.battlefield, underYourControl: underYourControl)));
          final text = sacrifice ? 'Sacrifice it' : (exile ? 'Exile it' : (toHand ? "Return it to its owner's hand" : 'Return it to the battlefield'));
          state.delayed.add(DelayedTrigger(
            controller: ctx.controller,
            sourceId: sacrifice ? id : (ctx.source ?? id),
            ability: TriggeredAbility('$text ${step == TurnStep.end ? 'at the beginning of the next end step' : 'at end of combat'}.', StepTrigger(step, Who.any), Body(effect: effect)),
            objects: [(id, o.zcc)],
            createdTurn: state.turn,
          ));
        }
      case ChooseValue(:final what):
        final src = state.objOrNull(ctx.source);
        if (src == null) return;
        if (what == 'color') {
          final pick = ask(Decision(kind: DecisionKind.option, player: ctx.controller, prompt: 'Choose a color', labels: [for (final c in ManaColor.values) c.word], source: ctx.source));
          src.chosenColor = ManaColor.values[pick.first].word;
          _log('${state.player(ctx.controller).name} chooses ${src.chosenColor}.', player: ctx.controller);
        } else {
          final types = _commonCreatureTypes(ctx.controller);
          final pick = ask(Decision(kind: DecisionKind.option, player: ctx.controller, prompt: 'Choose a creature type', labels: types, source: ctx.source));
          src.chosenType = types[pick.first];
          _log('${state.player(ctx.controller).name} chooses ${src.chosenType}.', player: ctx.controller);
        }
      default:
        throw StateError('Not a more-effect: $e');
    }
  }

  /// Each clashing player reveals their top card and puts it on the top or bottom; you win if
  /// yours has the greater mana value (CR 701.23). The result is in `results['clash']`.
  void _clash(EvalCtx ctx) {
    final you = ctx.controller;
    final opps = [for (final p in state.players) if (p.id != you && !p.lost) p.id];
    if (opps.isEmpty) return;
    final opp = opps.length == 1 ? opps.first : opps[ask(Decision(kind: DecisionKind.option, player: you, prompt: 'Clash with which opponent?', labels: [for (final p in opps) state.player(p).name], source: ctx.source)).first];
    int? mv(PlayerId p) {
      final lib = state.player(p).library;
      if (lib.isEmpty) return null;
      final top = lib.first;
      final v = chars(top).manaValue;
      _log('${state.player(p).name} reveals ${nameOf(top)} (mana value $v).', player: p, obj: top);
      return v;
    }

    final mine = mv(you), theirs = mv(opp);
    for (final p in [you, opp]) {
      final lib = state.player(p).library;
      if (lib.isEmpty) continue;
      final top = lib.first;
      final pick = ask(Decision(kind: DecisionKind.option, player: p, prompt: 'Clash: put ${nameOf(top)} on the top or bottom of your library?', labels: const ['Top', 'Bottom'], source: ctx.source));
      if (pick.first == 1) _move(top, Zone.library, bottom: true);
    }
    final won = mine != null && (theirs == null || mine > theirs);
    ctx.results['clash'] = won ? 1 : 0;
    _log('${state.player(you).name} ${won ? 'wins' : 'loses'} the clash.', player: you);
  }
}
