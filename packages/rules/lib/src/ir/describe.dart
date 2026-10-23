/// A compact text rendering of the ability IR, for auditing what the parser understood.
library;

import 'ir.dart';

String describeAbility(Ability a) => switch (a) {
      SpellAbility(:final body) => 'SPELL ${_body(body)}',
      ActivatedAbility(:final cost, :final body) => 'ACT[${_cost(cost)}${a.sorcerySpeed ? ' sorc' : ''}${a.oncePerTurn ? ' 1/turn' : ''}${a.onlyOnce ? ' once' : ''}] ${_body(body)}',
      ManaAbility(:final cost, :final produce) => 'MANA[${_cost(cost)}] ${_produce(produce)}',
      TriggeredAbility(:final trigger, :final body, :final condition) => 'TRIG ${_trig(trigger)}${condition == null ? '' : ' IF ${_cond(condition)}'}${a.oncePerTurn ? ' 1/turn' : ''}${a.optionalCost != null ? ' pay ${a.optionalCost}' : ''}${a.zone != ZoneKind.battlefield ? ' from ${a.zone.name}' : ''} → ${_body(body)}',
      StaticAbility(:final set, :final mods, :final condition) => 'STATIC ${_set(set)} ${mods.map(_mod).join(', ')}${condition == null ? '' : ' WHILE ${_cond(condition)}'}',
      ReplacementAbility(:final replacement) => 'REPL ${_repl(replacement)}',
      RuleAbility(:final rule) => 'RULE ${_rule(rule)}',
      KeywordAbility(:final kw) => 'KW ${kw.key}',
      EnchantAbility(:final filter) => 'ENCHANT ${_filter(filter)}',
      CastOptionAbility(:final option) => 'CASTOPT ${option.kind.name}${option.cost == null ? '' : ' ${option.cost}'}${option.extra.isEmpty ? '' : ' +${option.extra.map(_part).join(',')}'}${option.condition == null ? '' : ' if ${_cond(option.condition!)}'}',
      InfoAbility() => 'INFO',
    };

String _body(Body b) {
  if (b.isModal) return 'MODES(${b.minModes}-${b.maxModes}) ${[for (final m in b.modes) '{${_body(m)}}'].join(' | ')}';
  final t = b.targets.isEmpty ? '' : 'T[${[for (var i = 0; i < b.targets.length; i++) '$i:${_spec(b.targets[i])}'].join('; ')}] ';
  return '$t${eff(b.effect)}';
}

String _spec(TargetSpec s) => '${s.kind.name}${s.min != 1 || s.max != 1 ? '(${s.min}-${s.max})' : ''} ${s.kind == TargetKind.player ? s.who.name : _filter(s.filter)}${s.when == null ? '' : ' when ${_cond(s.when!)}'}';

String _cost(Cost c) => [
      if (c.mana != null) c.mana!.text,
      if (c.tap) 'T',
      if (c.untap) 'Q',
      if (c.loyalty != null) 'loy${c.loyalty! >= 0 ? '+' : ''}${c.loyalty}',
      ...c.parts.map(_part),
    ].join(',');

String _part(CostPart p) => switch (p) {
      SacrificeCost(:final self, :final filter, :final n) => self ? 'sac self' : 'sac $n ${_filter(filter)}',
      DiscardCost(:final self, :final n, :final hand) => self ? 'discard self' : (hand ? 'discard hand' : 'discard $n'),
      PayLifeCost(:final amount) => 'life ${_amt(amount)}',
      ExileFromGraveyardCost(:final n, :final self) => self ? 'exile self from gy' : 'exile $n from gy',
      RemoveCountersCost(:final kind, :final n) => 'remove $n $kind',
      TapCost(:final totalPower) when totalPower > 0 => 'crew $totalPower',
      TapCost(:final n, :final filter) => n == 0 ? 'tap self' : 'tap $n ${_filter(filter)}',
      ReturnCost(:final filter) => 'return ${_filter(filter)}',
      AddCountersCost(:final kind, :final n) => 'add $n $kind',
      EnergyCost(:final n) => 'energy $n',
    };

String _produce(ManaProduce p) => '${p.fixed.isNotEmpty ? p.fixed.map((m) => m.name).join() : ''}${p.choice.isNotEmpty ? p.choice.map((m) => m.name).join('/') : ''}${p.anyColor ? 'any' : ''}${p.chosenColor ? 'chosen' : ''} x${_amt(p.amount)}${p.restriction != null ? ' only ${_filter(p.restriction!)}' : ''}';

String _trig(Trigger t) => switch (t) {
      EntersTrigger(:final set) => 'enters(${_set(set)})',
      DiesTrigger(:final set, :final damagedBySelf) => 'dies(${_set(set)}${damagedBySelf ? ' damaged by ~' : ''})',
      LeavesTrigger(:final set) => 'leaves(${_set(set)})',
      PutIntoGraveyardTrigger(:final set) => 'toGy(${_set(set)})',
      AttacksTrigger(:final set, :final condition, :final alone, :final minAttackers, :final attacksYou) =>
        'attacks(${_set(set)}${alone ? ' alone' : ''}${minAttackers > 0 ? ' with >=$minAttackers' : ''}${attacksYou ? ' you' : ''})${condition == null ? '' : ' while ${_cond(condition)}'}',
      YouAttackTrigger(:final min) => 'youAttack(>=$min)',
      BlocksTrigger(:final set, :final other) => 'blocks(${_set(set)}${other == null ? '' : ' each ${_filter(other)}'})',
      BecomesBlockedTrigger(:final set, :final other) => 'blocked(${_set(set)}${other == null ? '' : ' by each ${_filter(other)}'})',
      DealsDamageTrigger(:final set, :final toPlayer, :final toOpponent, :final combat) => 'deals${combat == true ? 'Combat' : (combat == false ? 'Noncombat' : '')}Damage(${_set(set)}${toPlayer ? ' →player' : ''}${toOpponent ? ' →opp' : ''})',
      IsDealtDamageTrigger(:final set) => 'isDealtDamage(${_set(set)})',
      CastTrigger(:final who, :final filter, :final self, :final nth, :final orCopy, :final targets, :final kicked) =>
        'cast${orCopy ? 'OrCopy' : ''}(${self ? '~' : '${who.name}: ${_filter(filter)}'}${nth > 0 ? ' #$nth' : ''}${targets == null ? '' : ' targeting ${_set(targets)}'}${kicked ? ' kicked' : ''})',
      StepTrigger(:final step, :final whose, :final ofAttached) => 'step(${step.name}, ${ofAttached ? 'attached' : whose.name})',
      GainLifeTrigger(:final who, :final firstTimeEachTurn) => 'gainLife(${who.name}${firstTimeEachTurn ? ' first' : ''})',
      LoseLifeTrigger(:final who) => 'loseLife(${who.name})',
      DrawTrigger(:final who, :final nth) => 'draw(${who.name}${nth > 0 ? ' #$nth' : ''})',
      DiscardTrigger(:final who) => 'discard(${who.name})',
      CountersPutTrigger(:final set, :final kind) => 'counters($kind on ${_set(set)})',
      BecomesTargetTrigger(:final set) => 'targeted(${_set(set)})',
      BecomesUntappedTrigger(:final set) => 'untapped(${_set(set)})',
      SacrificedTrigger(:final set) => 'sacrificed(${_set(set)})',
      TokenCreatedTrigger() => 'tokenCreated',
      UnblockedTrigger(:final set) => 'unblocked(${_set(set)})',
      TappedTrigger(:final set) => 'tapped(${_set(set)})',
      CycleTrigger(:final who, :final self) => 'cycle(${self ? '~' : who.name})',
      CrimeTrigger() => 'crime',
      ScryTrigger(:final who, :final scry, :final surveil) => '${scry ? 'scry' : ''}${scry && surveil ? '/' : ''}${surveil ? 'surveil' : ''}(${who.name})',
      TransformedTrigger(:final set) => 'transformed(${_set(set)})',
    };

String _cond(Condition c) => switch (c) {
      Not(:final c) => 'not ${_cond(c)}',
      AllOf(:final cs) => cs.map(_cond).join(' & '),
      AnyOf(:final cs) => cs.map(_cond).join(' | '),
      AttackedThisTurn() => 'raid',
      CreatureDiedThisTurn() => 'morbid',
      TurnStatCondition(:final stat, :final player, :final cmp, :final n) => '${stat.name}(${_pl(player)}) ${cmp.name} $n',
      CountCondition(:final amount, :final cmp, :final n) => '${_amt(amount)} ${cmp.name} $n',
      Kicked() => 'kicked',
      YourTurn() => 'yourTurn',
      DuringSteps(:final steps) => 'during ${steps.map((s) => s.name).join('/')}',
      WasCast() => 'wasCast',
      ObjMatches(:final obj, :final filter) => '${_ref(obj)} is ${_filter(filter)}',
      RememberedAny(:final slot, :final filter) => '$slot has ${_filter(filter)}',
      DidIt() => 'didIt',
      AmountCompare(:final a, :final cmp, :final b) => '${_amt(a)} ${cmp.name} ${_amt(b)}',
      WonFlip(:final won) => won ? 'wonFlip' : 'lostFlip',
      WonClash() => 'wonClash',
      StepIn(:final steps) => 'during ${steps.map((s) => s.name).join('/')}',
    };

String _repl(Replacement r) => switch (r) {
      EntersTapped(:final set, :final unless, :final payLife) =>
        'entersTapped(${_set(set)}${unless == null ? '' : ' unless ${_cond(unless)}'}${payLife > 0 ? ' or pay $payLife life' : ''})',
      EntersWithCounters(:final set, :final kind, :final amount, :final condition) => 'entersWith(${_set(set)} ${_amt(amount)} $kind${condition == null ? '' : ' if ${_cond(condition)}'})',
      ChooseOnEnter(:final what) => 'chooseOnEnter($what)',
      PreventDamage(:final set, :final combat, :final toYou) => 'prevent(${toYou ? 'you' : _set(set)}${combat == null ? '' : (combat ? ' combat' : ' noncombat')})',
      DoubleDamage() => 'doubleDamage',
      DoubleTokens() => 'doubleTokens',
      DoubleCountersReplacement() => 'doubleCounters',
      InsteadOfGraveyard(:final to) => 'insteadOfGy(${to.name})',
      ExtraCountersOnEnter(:final set, :final kind, :final amount) => 'extraCounters(${_set(set)} ${_amt(amount)} $kind)',
    };

String _rule(RuleMod r) => switch (r) {
      CostChange(:final filter, :final delta, :final amount, :final selfOnly, :final condition, :final targetsFilter) =>
        'cost${selfOnly ? '(self)' : ' ${_filter(filter)}'} ${amount == null ? delta : '-${_amt(amount)}'}${condition == null ? '' : ' if ${_cond(condition)}'}${targetsFilter == null ? '' : ' if targets ${_filter(targetsFilter)}'}',
      NoMaxHandSize() => 'noMaxHandSize',
      ExtraLandPerTurn(:final n) => 'extraLand $n',
      CastAsThoughFlash(:final filter) => 'flash ${_filter(filter)}',
      CantLoseGame() => 'cantLose',
      OpponentsCantWin() => 'opponentsCantWin',
      PlayerHexproof() => 'playerHexproof',
      CastWithoutPaying(:final filter) => 'free ${_filter(filter)}',
      PlayFromGraveyard(:final filter, :final oncePerTypeEachTurn) => 'fromGraveyard ${_filter(filter)}${oncePerTypeEachTurn ? ' oncePerType' : ''}',
      LookAtTopAnyTime() => 'lookAtTop',
    };

/// Stable text for a continuous effect's modification (also used in game digests, where class
/// names can't be: release JavaScript minifies them).
String describeMod(Mod m) => _mod(m);

/// Stable text for a rule change (see [describeMod]).
String describeRuleMod(RuleMod r) => _rule(r);

String _mod(Mod m) => switch (m) {
      ModPT(:final power, :final toughness) => '+${_amt(power)}/+${_amt(toughness)}',
      SetPT(:final power, :final toughness, :final cda) => '${cda ? 'CDA ' : ''}=${power == null ? '_' : _amt(power)}/${toughness == null ? '_' : _amt(toughness)}',
      AddKw(:final kw) => '+${kw.key}',
      LoseKw(:final kw) => '-${kw.key}',
      AddAbility(:final ability) => '+"${ability.text}"',
      LoseAllAbilities() => 'loseAll',
      TypeMod(:final types, :final subtypes, :final replaceTypes) => 'type${replaceTypes ? '=' : '+'}${types.map((t) => t.name).join(',')}${subtypes.join(',')}',
      ColorMod(:final colors) => 'color=${colors.map((c) => c.symbol).join()}',
      SetName(:final name) => 'name=$name',
      ControlBy() => 'control',
      CopyOf() => 'copy',
      SwitchPT() => 'switch',
    };

String _set(ObjSet s) => switch (s) { One(:final ref) => _ref(ref), All(:final filter) => 'all ${_filter(filter)}' };

String _ref(ObjRef r) => switch (r) {
      SelfRef() => '~',
      TargetObj(:final index) => 'T$index',
      EventObj() => 'eventObj',
      AttachedTo() => 'attached',
      Remembered(:final slot) => '@$slot',
    };

String _pl(PlayerRef p) => switch (p) {
      You() => 'you',
      EachOpponent() => 'opps',
      EachPlayer() => 'all',
      TargetPlayer(:final index) => 'T$index',
      ControllerOf(:final obj) => 'ctl(${_ref(obj)})',
      OwnerOf(:final obj) => 'owner(${_ref(obj)})',
      EventPlayer() => 'eventPlayer',
      DefendingPlayer() => 'defender',
      ActivePlayer() => 'active',
    };

String _amt(Amount a) => switch (a) {
      Fixed(:final n) => '$n',
      XValue() => 'X',
      RollResult() => 'roll',
      EnergyOf(:final player) => 'energy(${_pl(player)})',
      CountOf(:final set) => '#(${_set(set)})',
      PlayerCount(:final players) => '#${_pl(players)}',
      StatOf(:final stat, :final obj) => '${stat.name}(${_ref(obj)})',
      TotalStat(:final stat, :final set) => 'total${stat.name}(${_set(set)})',
      CountersOn(:final kind, :final obj) => '#$kind(${_ref(obj)})',
      LifeTotal(:final player) => 'life(${_pl(player)})',
      StartingLife(:final player) => 'startLife(${_pl(player)})',
      TurnCount(:final stat, :final player) => '${stat.name}(${_pl(player)})',
      EventAmount() => 'eventAmt',
      ResultAmount(:final slot) => 'result:$slot',
      CardsIn(:final zone, :final player, :final filter) => '#${zone.name}(${_pl(player)}: ${_filter(filter)})',
      DistinctManaValues(:final set) => 'distinctMV(${_set(set)})',
      Times(:final a, :final k) => '${_amt(a)}*$k',
      Plus(:final a, :final b) => '${_amt(a)}+${_amt(b)}',
    };

String _filter(Filter f) {
  final p = <String>[];
  if (f.other) p.add('other');
  if (f.token == true) p.add('token');
  if (f.token == false) p.add('nontoken');
  if (f.tapped != null) p.add(f.tapped! ? 'tapped' : 'untapped');
  if (f.attacking == true) p.add('attacking');
  if (f.blocking == true) p.add('blocking');
  for (final c in f.colors) {
    p.add(c.word);
  }
  for (final c in f.notColors) {
    p.add('non${c.word}');
  }
  for (final t in f.notTypes) {
    p.add('non${t.name}');
  }
  for (final t in f.notSubtypes) {
    p.add('non-$t');
  }
  for (final s in f.supertypes) {
    p.add(s.name);
  }
  if (f.allTypes.isNotEmpty) p.add(f.allTypes.map((t) => t.name).join('+'));
  if (f.types.isNotEmpty) p.add(f.types.map((t) => t.name).join('|'));
  if (f.subtypes.isNotEmpty) p.add(f.subtypes.join('|'));
  if (f.permanent) p.add('permanent');
  if (f.card) p.add('card');
  if (f.spell) p.add('spell');
  if (f.controller != Who.any) p.add('ctl:${f.controller.name}');
  if (f.owner != Who.any) p.add('own:${f.owner.name}');
  if (f.power != null) p.add('pow${f.power!.$1.name}${_amt(f.power!.$2)}');
  if (f.toughness != null) p.add('tou${f.toughness!.$1.name}${_amt(f.toughness!.$2)}');
  if (f.manaValue != null) p.add('mv${f.manaValue!.$1.name}${_amt(f.manaValue!.$2)}');
  for (final k in f.withKeywords) {
    p.add('with $k');
  }
  for (final k in f.withoutKeywords) {
    p.add('without $k');
  }
  if (f.withCounter != null) p.add('with ${f.withCounter} counter');
  if (f.name != null) p.add('named ${f.name}');
  if (f.zone != ZoneKind.battlefield) p.add('in ${f.zone.name}');
  if (f.putThereThisTurn) p.add('thisTurn');
  if (f.chosenType) p.add('chosenType');
  return p.isEmpty ? 'any' : p.join(' ');
}

String eff(Effect e) => switch (e) {
      Seq(:final steps) => steps.map(eff).join('; '),
      May(:final effect) => 'MAY(${eff(effect)})',
      If(:final cond, :final then, :final otherwise) => 'IF ${_cond(cond)} THEN (${eff(then)})${otherwise == null ? '' : ' ELSE (${eff(otherwise)})'}',
      Unless(:final effect, :final payer, :final mana, :final life, :final alternative) => 'UNLESS ${_pl(payer)} pays ${mana ?? ''}${life ?? ''}${alternative == null ? '' : ' or ${eff(alternative)}'}: (${eff(effect)})',
      ForEachPlayer(:final players, :final effect) => 'FOREACH ${_pl(players)}: (${eff(effect)})',
      DealDamage(:final amount, :final to, :final toPlayers, :final source) => 'dmg ${_amt(amount)} from ${_ref(source)} to ${to == null ? '' : _set(to)}${toPlayers == null ? '' : _pl(toPlayers)}',
      DamageTarget(:final amount, :final index, :final source) => 'dmg ${_amt(amount)} from ${_ref(source)} to anyT$index',
      Fight(:final a, :final b) => 'fight ${_ref(a)} ${_ref(b)}',
      Draw(:final amount, :final who) => 'draw ${_amt(amount)} ${_pl(who)}',
      Discard(:final amount, :final who, :final random) => 'discard ${_amt(amount)} ${_pl(who)}${random ? ' random' : ''}',
      GainLife(:final amount, :final who) => 'gain ${_amt(amount)} ${_pl(who)}',
      LoseLife(:final amount, :final who) => 'lose ${_amt(amount)} ${_pl(who)}',
      Mill(:final amount, :final who) => 'mill ${_amt(amount)} ${_pl(who)}',
      Scry(:final amount) => 'scry ${_amt(amount)}',
      Surveil(:final amount) => 'surveil ${_amt(amount)}',
      Destroy(:final set, :final noRegen) => 'destroy ${_set(set)}${noRegen ? ' (no regen)' : ''}',
      MoveTo(:final set, :final zone, :final tapped, :final underYourControl, :final counters) => 'move ${_set(set)} → ${zone.name}${tapped ? ' tapped' : ''}${underYourControl ? ' yours' : ''}${counters.isEmpty ? '' : ' $counters'}${e.untilSourceLeaves ? ' untilLeaves' : ''}${e.ownerChoosesTopOrBottom ? ' top/bottom' : ''}',
      Sacrifice(:final who, :final filter, :final amount, :final self) => self ? 'sac self' : 'sac ${_pl(who)} ${_amt(amount)} ${_filter(filter)}',
      Tap(:final set) => 'tap ${_set(set)}',
      Untap(:final set) => 'untap ${_set(set)}',
      TransformPermanents(:final set) => 'transform ${_set(set)}',
      PutCounters(:final set, :final kind, :final amount) => 'counters ${_amt(amount)} $kind on ${_set(set)}',
      RemoveCounters(:final set, :final kind, :final amount) => 'remove ${_amt(amount)} $kind from ${_set(set)}',
      DoubleCounters(:final set, :final kind) => 'doubleCounters ${kind ?? 'all'} on ${_set(set)}',
      Proliferate() => 'proliferate',
      CreateToken(:final spec, :final amount, :final controller, :final tapped) => 'token ${_amt(amount)}x ${spec.power}/${spec.toughness} ${spec.colors.map((c) => c.symbol).join()} ${spec.name}${spec.keywords.isEmpty ? '' : ' [${spec.keywords.join(',')}]'}${tapped ? ' tapped' : ''} for ${_pl(controller)}',
      CreateCopy(:final of, :final extraMods, :final sacrificeAtEnd) => 'copyToken of ${_ref(of)}${extraMods.isEmpty ? '' : ' +${extraMods.map(_mod).join(',')}'}${sacrificeAtEnd ? ' sacAtEnd' : ''}',
      Grant(:final set, :final mods, :final duration) => 'grant ${_set(set)} ${mods.map(_mod).join(',')} (${duration.name})',
      DoublePower(:final obj) => 'doublePower ${_ref(obj)}',
      CounterSpell(:final obj) => 'counter ${_ref(obj)}',
      CounterEventItem() => 'counterEventItem',
      GainControl(:final set, :final duration) => 'control ${_set(set)} (${duration.name})',
      Search(:final filter, :final amount, :final zone, :final tapped) => 'search ${_amt(amount)} ${_filter(filter)} → ${zone.name}${tapped ? ' tapped' : ''}',
      LookAndPick(:final n, :final filter, :final pick, :final zone, :final rest) => 'look ${_amt(n)} pick ${_amt(pick)} ${_filter(filter)} → ${zone.name}, rest ${rest.name}',
      RevealUntil(:final filter, :final zone) => 'revealUntil ${_filter(filter)} → ${zone.name}',
      ExileTopMayPlay(:final n, :final chooseOne) => 'impulse ${_amt(n)}${chooseOne ? ' choose1' : ''}',
      AddMana(:final produce) => 'addMana ${_produce(produce)}',
      Shuffle() => 'shuffle',
      Attach(:final what, :final to) => 'attach ${_ref(what)} to ${_ref(to)}',
      Delayed(:final trigger, :final effect) => 'delayed ${_trig(trigger)} → ${eff(effect)}',
      Emblem(:final text) => 'emblem "$text"',
      EndTurn() => 'endTurn',
      Noop() => 'noop',
      CopySpell(:final obj, :final amount) => 'copySpell ${_ref(obj)} x${_amt(amount)}',
      CastFreeNow(:final set) => 'castFree ${_set(set)}',
      UpkeepCost(:final kind, :final cost) => 'upkeep $kind${cost == null ? '' : ' ${cost.text}'}',
      CascadeEffect(:final mv) => 'cascade <$mv',
      AllowPlay(:final set) => 'allowPlay ${_set(set)}',
      RuleChange(:final rule) => 'rule ${_rule(rule)}',
      RevealPutPermanents(:final n) => 'genesisWave ${_amt(n)}',
      PilesChoice(:final n) => 'piles ${_amt(n)}',
      ChooseFromRemembered(:final slot, :final then) => 'choose from $slot → ${eff(then)}',
      ChooseEffect(:final options) => 'choose(${options.map(eff).join(' | ')})',
      KeepOneOfEachType(:final who) => 'keepOneOfEach ${_pl(who)}',
      Regenerate(:final set) => 'regenerate ${_set(set)}',
      PreventNext(:final amount, :final target, :final set, :final toYou, :final by, :final combatOnly) =>
        'prevent${combatOnly ? ' combat' : ''} ${amount == null ? 'all' : _amt(amount)}${target != null ? ' to T$target' : ''}${set != null ? ' to ${_set(set)}' : ''}${toYou ? ' to you' : ''}${by != null ? ' by ${_set(by)}' : ''}',
      RevealHand(:final who, :final filter, :final exile, :final optional) =>
        'revealHand ${_pl(who)}${filter == null ? '' : ' → ${optional ? 'may ' : ''}${exile ? 'exile' : 'discard'} ${_filter(filter)}'}',
      FlipCoin() => 'flipCoin',
      GetEnergy(:final amount, :final who, :final poison) => '${poison ? 'poison' : 'energy'} +${_amt(amount)} ${_pl(who)}',
      PayEffect(:final mana, :final life, :final energy) => 'pay${mana == null ? '' : ' ${mana.text}'}${life > 0 ? ' $life life' : ''}${energy > 0 ? ' $energy energy' : ''}',
      Clash() => 'clash',
      Amass(:final subtype, :final amount) => 'amass $subtype ${_amt(amount)}',
      Bolster(:final amount) => 'bolster ${_amt(amount)}',
      SkipNextUntap(:final set) => 'skipUntap ${_set(set)}',
      ExtraTurn(:final who) => 'extraTurn ${_pl(who)}',
      ChooseAndMove(:final filter, :final from, :final to, :final who, :final amount, :final tapped) => 'choose ${_amt(amount)} ${_filter(filter)} in ${from.name} (${_pl(who)}) → ${to.name}${tapped ? ' tapped' : ''}',
      Populate() => 'populate',
      ChooseValue(:final what) => 'choose $what',
      AtNextEndStep(:final set, :final sacrifice) => '${sacrifice ? 'sacrifice' : 'return'} ${_set(set)} at next end step',
      Explore(:final set) => 'explore ${_set(set)}',
      RollDie(:final sides, :final count) => 'roll ${count}d$sides',
    };
