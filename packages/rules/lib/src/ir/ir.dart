/// The ability IR: oracle text compiles into these data classes, and the game interprets them.
/// Nothing here refers to a game in progress; references are resolved when an ability resolves.
library;

import '../cards/card.dart';
import '../cards/mana.dart';

// ---------------------------------------------------------------------------------------------
// Comparisons and numbers
// ---------------------------------------------------------------------------------------------

enum Cmp {
  eq, le, ge, lt, gt;

  bool test(int a, int b) => switch (this) { eq => a == b, le => a <= b, ge => a >= b, lt => a < b, gt => a > b };
}

/// A quantity in rules text: "three", "X", "that much", "the number of Goblins you control".
sealed class Amount {
  const Amount();
}

class Fixed extends Amount {
  const Fixed(this.n);
  final int n;
  @override
  String toString() => '$n';
}

/// X from the spell's or ability's cost (CR 107.3).
class XValue extends Amount {
  const XValue();
}

/// The number of objects in a set ("for each creature you control").
class CountOf extends Amount {
  const CountOf(this.set);
  final ObjSet set;
}

/// The number of players in a set ("for each opponent").
class PlayerCount extends Amount {
  const PlayerCount(this.players);
  final PlayerRef players;
}

enum Stat { power, toughness, manaValue, loyalty }

class StatOf extends Amount {
  const StatOf(this.stat, this.obj);
  final Stat stat;
  final ObjRef obj;
}

/// Total power of a set ("the total power of creatures you control").
class TotalStat extends Amount {
  const TotalStat(this.stat, this.set);
  final Stat stat;
  final ObjSet set;
}

class CountersOn extends Amount {
  const CountersOn(this.kind, this.obj);
  final String kind;
  final ObjRef obj;
}

class LifeTotal extends Amount {
  const LifeTotal(this.player);
  final PlayerRef player;
}

enum TurnStat { lifeGained, lifeLost, cardsDrawn, spellsCast, damageTaken }

class TurnCount extends Amount {
  const TurnCount(this.stat, this.player);
  final TurnStat stat;
  final PlayerRef player;
}

/// "That much", "that many": the number carried by the trigger event (damage dealt, life gained).
class EventAmount extends Amount {
  const EventAmount();
}

/// "The life lost this way", "the excess damage": a number an earlier step of this resolution
/// recorded.
class ResultAmount extends Amount {
  const ResultAmount(this.slot);
  final String slot;
}

/// Cards in a zone ("cards in your graveyard", "instant and sorcery cards in your graveyard").
class CardsIn extends Amount {
  const CardsIn(this.zone, this.player, this.filter);
  final ZoneKind zone;
  final PlayerRef player;
  final Filter filter;
}

/// Different mana values among a set (Lunar Insight).
class DistinctManaValues extends Amount {
  const DistinctManaValues(this.set);
  final ObjSet set;
}

class Times extends Amount {
  const Times(this.a, this.k);
  final Amount a;
  final int k;
}

class Plus extends Amount {
  const Plus(this.a, this.b);
  final Amount a, b;
}

// ---------------------------------------------------------------------------------------------
// Players
// ---------------------------------------------------------------------------------------------

sealed class PlayerRef {
  const PlayerRef();
}

/// The controller of the ability or spell.
class You extends PlayerRef {
  const You();
}

class EachOpponent extends PlayerRef {
  const EachOpponent();
}

class EachPlayer extends PlayerRef {
  const EachPlayer();
}

/// A player chosen as target [index] of the ability.
class TargetPlayer extends PlayerRef {
  const TargetPlayer(this.index);
  final int index;
}

class ControllerOf extends PlayerRef {
  const ControllerOf(this.obj);
  final ObjRef obj;
}

class OwnerOf extends PlayerRef {
  const OwnerOf(this.obj);
  final ObjRef obj;
}

/// The player named by the trigger event ("that player", "an opponent" who drew).
class EventPlayer extends PlayerRef {
  const EventPlayer();
}

class DefendingPlayer extends PlayerRef {
  const DefendingPlayer();
}

/// The active player ("that player's upkeep", "the player whose turn it is").
class ActivePlayer extends PlayerRef {
  const ActivePlayer();
}

// ---------------------------------------------------------------------------------------------
// Objects
// ---------------------------------------------------------------------------------------------

/// Which zone an object description talks about.
enum ZoneKind { battlefield, hand, library, graveyard, exile, stack, command, anywhere }

enum Who {
  any,
  you,
  opponent,
  notYou,

  /// "That player" (inside a for-each-player effect, or the trigger event's player).
  that,
}

/// An object description (CR 109.2): "nontoken creature you control with power 2 or less".
class Filter {
  const Filter({
    this.types = const {},
    this.allTypes = const {},
    this.notTypes = const {},
    this.subtypes = const {},
    this.notSubtypes = const {},
    this.supertypes = const {},
    this.notSupertypes = const {},
    this.colors = const {},
    this.notColors = const {},
    this.multicolored,
    this.colorless,
    this.controller = Who.any,
    this.owner = Who.any,
    this.other = false,
    this.token,
    this.tapped,
    this.attacking,
    this.blocking,
    this.power,
    this.toughness,
    this.manaValue,
    this.withKeywords = const {},
    this.withoutKeywords = const {},
    this.withCounter,
    this.name,
    this.permanent = false,
    this.spell = false,
    this.card = false,
    this.zone = ZoneKind.battlefield,
    this.putThereThisTurn = false,
    this.chosenType = false,
    this.chosenColor = false,
    this.enteredThisTurn,
    this.historic = false,
    this.notName,
  });

  /// Any of these types (empty: any).
  final Set<CardType> types;

  /// All of these types ("artifact creature").
  final Set<CardType> allTypes;
  final Set<CardType> notTypes;

  /// Any of these subtypes.
  final Set<String> subtypes;
  final Set<String> notSubtypes;
  final Set<Supertype> supertypes, notSupertypes;
  final Set<ManaColor> colors, notColors;
  final bool? multicolored, colorless;
  final Who controller, owner;

  /// "Other", "another": not the source.
  final bool other;
  final bool? token, tapped, attacking, blocking;
  final (Cmp, Amount)? power, toughness, manaValue;
  final Set<String> withKeywords, withoutKeywords;
  final String? withCounter;
  final String? name, notName;

  /// "Permanent": any permanent type (on the battlefield every object is a permanent).
  final bool permanent;
  final bool spell;
  final bool card;
  final ZoneKind zone;

  /// "Put there this turn" (Abyssal Harvester).
  final bool putThereThisTurn;

  /// "Of the chosen type/color" (the source's choice as it entered).
  final bool chosenType, chosenColor;
  final bool? enteredThisTurn;
  final bool historic;

  static const any = Filter();
  static const creature = Filter(types: {CardType.creature});

  Filter copyWith({
    Set<CardType>? types,
    Set<CardType>? allTypes,
    Set<CardType>? notTypes,
    Set<String>? subtypes,
    Set<String>? notSubtypes,
    Set<Supertype>? supertypes,
    Set<Supertype>? notSupertypes,
    Set<ManaColor>? colors,
    Set<ManaColor>? notColors,
    bool? multicolored,
    bool? colorless,
    Who? controller,
    Who? owner,
    bool? other,
    bool? token,
    bool? tapped,
    bool? attacking,
    bool? blocking,
    (Cmp, Amount)? power,
    (Cmp, Amount)? toughness,
    (Cmp, Amount)? manaValue,
    Set<String>? withKeywords,
    Set<String>? withoutKeywords,
    String? withCounter,
    String? name,
    bool? permanent,
    bool? spell,
    bool? card,
    ZoneKind? zone,
    bool? putThereThisTurn,
    bool? chosenType,
    bool? chosenColor,
    bool? enteredThisTurn,
    bool? historic,
    String? notName,
  }) =>
      Filter(
        types: types ?? this.types,
        allTypes: allTypes ?? this.allTypes,
        notTypes: notTypes ?? this.notTypes,
        subtypes: subtypes ?? this.subtypes,
        notSubtypes: notSubtypes ?? this.notSubtypes,
        supertypes: supertypes ?? this.supertypes,
        notSupertypes: notSupertypes ?? this.notSupertypes,
        colors: colors ?? this.colors,
        notColors: notColors ?? this.notColors,
        multicolored: multicolored ?? this.multicolored,
        colorless: colorless ?? this.colorless,
        controller: controller ?? this.controller,
        owner: owner ?? this.owner,
        other: other ?? this.other,
        token: token ?? this.token,
        tapped: tapped ?? this.tapped,
        attacking: attacking ?? this.attacking,
        blocking: blocking ?? this.blocking,
        power: power ?? this.power,
        toughness: toughness ?? this.toughness,
        manaValue: manaValue ?? this.manaValue,
        withKeywords: withKeywords ?? this.withKeywords,
        withoutKeywords: withoutKeywords ?? this.withoutKeywords,
        withCounter: withCounter ?? this.withCounter,
        name: name ?? this.name,
        permanent: permanent ?? this.permanent,
        spell: spell ?? this.spell,
        card: card ?? this.card,
        zone: zone ?? this.zone,
        putThereThisTurn: putThereThisTurn ?? this.putThereThisTurn,
        chosenType: chosenType ?? this.chosenType,
        chosenColor: chosenColor ?? this.chosenColor,
        enteredThisTurn: enteredThisTurn ?? this.enteredThisTurn,
        historic: historic ?? this.historic,
        notName: notName ?? this.notName,
      );
}

/// One object an ability talks about.
sealed class ObjRef {
  const ObjRef();
}

/// The source itself ("~", "this creature").
class SelfRef extends ObjRef {
  const SelfRef();
}

/// The object(s) chosen for target spec [index].
class TargetObj extends ObjRef {
  const TargetObj(this.index);
  final int index;
}

/// The object the trigger event is about ("that creature", "it" in "whenever a creature dies").
class EventObj extends ObjRef {
  const EventObj();
}

/// The creature this Aura or Equipment is attached to.
class AttachedTo extends ObjRef {
  const AttachedTo();
}

/// Objects remembered earlier in this resolution under [slot] ("the exiled card", "those tokens").
class Remembered extends ObjRef {
  const Remembered(this.slot);
  final String slot;
}

/// A set of objects: one reference, or everything matching a filter.
sealed class ObjSet {
  const ObjSet();
}

class One extends ObjSet {
  const One(this.ref);
  final ObjRef ref;
}

/// Every object matching [filter] in its zone ("creatures you control", "each creature").
class All extends ObjSet {
  const All(this.filter);
  final Filter filter;
}

// ---------------------------------------------------------------------------------------------
// Targets (CR 115)
// ---------------------------------------------------------------------------------------------

enum TargetKind {
  /// A permanent or card matching the filter.
  object,

  /// A player matching [TargetSpec.who].
  player,

  /// "Any target": creature, player, planeswalker or battle (CR 115.4).
  any,

  /// A spell (or ability) on the stack.
  spell,
}

class TargetSpec {
  const TargetSpec(this.kind, {this.filter = Filter.any, this.who = Who.any, this.min = 1, this.max = 1, this.differentControllers = false, this.sameZoneOwner = false, this.distinctFrom = const [], this.when});
  final TargetKind kind;
  final Filter filter;
  final Who who;
  final int min, max;

  /// "Two target creatures controlled by different players".
  final bool differentControllers;

  /// "From a single graveyard".
  final bool sameZoneOwner;

  /// "Another target": must differ from these earlier target indices.
  final List<int> distinctFrom;

  /// Only chosen when this holds as the spell is cast (kicked / not kicked).
  final Condition? when;

  bool get upTo => min == 0;
}

// ---------------------------------------------------------------------------------------------
// Keywords (CR 702) and rule flags
// ---------------------------------------------------------------------------------------------

/// A keyword ability or rules flag an object can have. Parameterised ones carry [cost],
/// [filter] or [n].
class Kw {
  const Kw(this.name, {this.cost, this.filter, this.n = 0, this.lifeCost = 0});
  final String name;
  final ManaCost? cost;
  final Filter? filter;
  final int n;
  final int lifeCost;

  // Evergreen and common keywords, plus flags that act like abilities in layer 6.
  static const flying = Kw('flying');
  static const firstStrike = Kw('first strike');
  static const doubleStrike = Kw('double strike');
  static const deathtouch = Kw('deathtouch');
  static const defender = Kw('defender');
  static const flash = Kw('flash');
  static const haste = Kw('haste');
  static const hexproof = Kw('hexproof');
  static const indestructible = Kw('indestructible');
  static const lifelink = Kw('lifelink');
  static const menace = Kw('menace');
  static const reach = Kw('reach');
  static const trample = Kw('trample');
  static const vigilance = Kw('vigilance');
  static const shroud = Kw('shroud');
  static const prowess = Kw('prowess');
  static const cantBlock = Kw('can\'t block');
  static const cantAttack = Kw('can\'t attack');
  static const cantAttackOrBlock = Kw('can\'t attack or block');
  static const unblockable = Kw('can\'t be blocked');
  static const attacksEachCombat = Kw('attacks each combat if able');
  static const doesntUntap = Kw('doesn\'t untap');
  static const cantBeCountered = Kw('can\'t be countered');
  static const allCreatureTypes = Kw('all creature types');

  String get key {
    final b = StringBuffer(name);
    if (cost != null) b.write(' ${cost!.text}');
    if (lifeCost > 0) b.write(' life$lifeCost');
    if (n != 0) b.write(' $n');
    if (filter != null) b.write(' f${_filterKey(filter!)}');
    return b.toString();
  }

  static String _filterKey(Filter f) =>
      '${f.types.map((t) => t.name).join('|')}/${f.subtypes.join('|')}/${f.colors.map((c) => c.symbol).join()}/${f.notTypes.map((t) => t.name).join('|')}/${f.spell}/${f.card}';

  @override
  bool operator ==(Object o) => o is Kw && o.key == key;
  @override
  int get hashCode => key.hashCode;
  @override
  String toString() => key;
}

// ---------------------------------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------------------------------

sealed class Condition {
  const Condition();
}

class Not extends Condition {
  const Not(this.c);
  final Condition c;
}

class AllOf extends Condition {
  const AllOf(this.cs);
  final List<Condition> cs;
}

/// All the non-null conditions, or null if none.
Condition? allOf(List<Condition?> cs) {
  final l = [for (final c in cs) ?c];
  return l.isEmpty ? null : (l.length == 1 ? l.first : AllOf(l));
}

class AnyOf extends Condition {
  const AnyOf(this.cs);
  final List<Condition> cs;
}

/// "If you attacked this turn" (raid).
class AttackedThisTurn extends Condition {
  const AttackedThisTurn();
}

/// "If a creature died this turn" (morbid).
class CreatureDiedThisTurn extends Condition {
  const CreatureDiedThisTurn();
}

/// "If an opponent lost life this turn" and the like.
class TurnStatCondition extends Condition {
  const TurnStatCondition(this.stat, this.player, this.cmp, this.n);
  final TurnStat stat;
  final PlayerRef player;
  final Cmp cmp;
  final int n;
}

/// "If you control a creature with power 4 or greater", "as long as you control three or more
/// artifacts": count of a set compared with a number.
class CountCondition extends Condition {
  const CountCondition(this.amount, this.cmp, this.n);
  final Amount amount;
  final Cmp cmp;
  final int n;
}

/// "If this spell was kicked".
class Kicked extends Condition {
  const Kicked();
}

/// "During your turn".
class YourTurn extends Condition {
  const YourTurn();
}

/// "If it was cast" / "if you cast it".
class WasCast extends Condition {
  const WasCast();
}

/// An object matches a filter ("if it wasn't a Demon", "if it's a creature card").
class ObjMatches extends Condition {
  const ObjMatches(this.obj, this.filter);
  final ObjRef obj;
  final Filter filter;
}

/// "If at least one creature card was exiled this way": remembered set non-empty and matching.
class RememberedAny extends Condition {
  const RememberedAny(this.slot, this.filter);
  final String slot;
  final Filter filter;
}

/// "If you do" after an optional action; set by [May] / [PayOrElse].
class DidIt extends Condition {
  const DidIt();
}

/// Compare two amounts ("your life total is greater than your starting life total").
class AmountCompare extends Condition {
  const AmountCompare(this.a, this.cmp, this.b);
  final Amount a;
  final Cmp cmp;
  final Amount b;
}

class StartingLife extends Amount {
  const StartingLife(this.player);
  final PlayerRef player;
}

// ---------------------------------------------------------------------------------------------
// Costs (CR 118, 601.2f–h, 602.2)
// ---------------------------------------------------------------------------------------------

sealed class CostPart {
  const CostPart();
}

class SacrificeCost extends CostPart {
  const SacrificeCost(this.filter, {this.n = 1, this.self = false});
  final Filter filter;
  final int n;
  final bool self;
}

class DiscardCost extends CostPart {
  const DiscardCost(this.filter, {this.n = 1, this.random = false, this.hand = false, this.self = false});
  final Filter filter;
  final int n;
  final bool random;

  /// Discard this card (cycling).
  final bool self;

  /// "Discard your hand".
  final bool hand;
}

class PayLifeCost extends CostPart {
  const PayLifeCost(this.amount);
  final Amount amount;
}

class ExileFromGraveyardCost extends CostPart {
  const ExileFromGraveyardCost(this.filter, {this.n = 1, this.self = false});
  final Filter filter;
  final int n;
  final bool self;
}

class RemoveCountersCost extends CostPart {
  const RemoveCountersCost(this.kind, this.n, {this.fromAmong});
  final String kind;
  final int n;

  /// "Remove six counters from among creatures you control": any kind, from any matching object.
  final Filter? fromAmong;
}

/// "Tap an untapped creature you control", "tap ten untapped Elves you control".
class TapCost extends CostPart {
  const TapCost(this.filter, this.n, {this.totalPower = 0});
  final Filter filter;
  final int n;

  /// Crew: any number of them with total power at least this.
  final int totalPower;
}

/// "Return a land you control to its owner's hand".
class ReturnCost extends CostPart {
  const ReturnCost(this.filter);
  final Filter filter;
}

/// "Put a counter on ~" as a cost (rare outside loyalty).
class AddCountersCost extends CostPart {
  const AddCountersCost(this.kind, this.n);
  final String kind;
  final int n;
}

class Cost {
  const Cost({this.mana, this.tap = false, this.untap = false, this.parts = const [], this.loyalty});
  final ManaCost? mana;
  final bool tap, untap;
  final List<CostPart> parts;

  /// Loyalty change of a planeswalker ability (+1, −2, 0).
  final int? loyalty;

  static const free = Cost();
  bool get isFree => (mana == null || mana!.isEmpty) && !tap && !untap && parts.isEmpty && (loyalty ?? 0) >= 0;
}

/// An alternative or additional way to cast (CR 118.9, 601.2b).
class CastOption {
  const CastOption(this.kind, {this.cost, this.extra = const [], this.zone = ZoneKind.hand, this.condition, this.label = ''});
  final CastKind kind;

  /// Replaces the mana cost (alternative) or adds to it (additional, kicker).
  final ManaCost? cost;
  final List<CostPart> extra;
  final ZoneKind zone;
  final Condition? condition;
  final String label;
}

enum CastKind {
  /// Optional additional cost: kicker, the "or pay" option of an additional cost.
  kicker,

  /// Mandatory additional cost ("as an additional cost to cast this spell, sacrifice a creature").
  additional,

  /// Alternative cost ("you may pay {B} rather than pay this spell's mana cost").
  alternative,

  /// Cast from the graveyard and exile (CR 702.34).
  flashback,

  /// Cast from the graveyard with an extra cost (Quilled Greatwurm).
  fromGraveyard,
}

// ---------------------------------------------------------------------------------------------
// Durations and continuous modifications (CR 611–613)
// ---------------------------------------------------------------------------------------------

enum EffectDuration { endOfTurn, permanent, untilYourNextTurn, whileSourceOnBattlefield, whileControl, thisTurn }

/// One modification a continuous effect makes. The layer it applies in follows from its type.
sealed class Mod {
  const Mod();
  int get layer;
}

/// Layer 1: becomes a copy (copiable values) of another object.
class CopyOf extends Mod {
  const CopyOf(this.obj);
  final ObjRef obj;
  @override
  int get layer => 1;
}

/// Layer 2.
class ControlBy extends Mod {
  const ControlBy(this.player);
  final PlayerRef player;
  @override
  int get layer => 2;
}

/// Layer 3: name change (Witness Protection).
class SetName extends Mod {
  const SetName(this.name);
  final String name;
  @override
  int get layer => 3;
}

/// Layer 4: add types/subtypes; [replace] loses the others ("is a colorless land").
class TypeMod extends Mod {
  const TypeMod({this.types = const {}, this.subtypes = const [], this.supertypes = const {}, this.replaceTypes = false, this.replaceSubtypes = false, this.loseSupertypes = const {}});
  final Set<CardType> types;
  final List<String> subtypes;
  final Set<Supertype> supertypes;
  final bool replaceTypes, replaceSubtypes;
  final Set<Supertype> loseSupertypes;
  @override
  int get layer => 4;
}

/// Layer 5.
class ColorMod extends Mod {
  const ColorMod(this.colors, {this.add = false});
  final Set<ManaColor> colors;
  final bool add;
  @override
  int get layer => 5;
}

/// Layer 6: gains a keyword or rule flag.
class AddKw extends Mod {
  const AddKw(this.kw);
  final Kw kw;
  @override
  int get layer => 6;
}

class LoseKw extends Mod {
  const LoseKw(this.kw);
  final Kw kw;
  @override
  int get layer => 6;
}

/// Layer 6: gains an ability ("has '{T}: Add {C}'").
class AddAbility extends Mod {
  const AddAbility(this.ability);
  final Ability ability;
  @override
  int get layer => 6;
}

/// Layer 6: loses all abilities.
class LoseAllAbilities extends Mod {
  const LoseAllAbilities();
  @override
  int get layer => 6;
}

/// Layer 7a (characteristic-defining) or 7b: power and toughness set to values.
class SetPT extends Mod {
  const SetPT(this.power, this.toughness, {this.cda = false});
  final Amount? power, toughness;
  final bool cda;
  @override
  int get layer => cda ? 70 : 71;
}

/// Layer 7c: +N/+N.
class ModPT extends Mod {
  const ModPT(this.power, this.toughness);
  final Amount power, toughness;
  @override
  int get layer => 72;
}

/// Layer 7d.
class SwitchPT extends Mod {
  const SwitchPT();
  @override
  int get layer => 73;
}

// ---------------------------------------------------------------------------------------------
// Effects (CR 608, 700–701)
// ---------------------------------------------------------------------------------------------

sealed class Effect {
  const Effect();
}

class Seq extends Effect {
  const Seq(this.steps);
  final List<Effect> steps;
}

/// "You may <effect>" — the controller (or [who]) chooses; sets "if you do".
class May extends Effect {
  const May(this.effect, {this.who = const You()});
  final Effect effect;
  final PlayerRef who;
}

class If extends Effect {
  const If(this.cond, this.then, [this.otherwise]);
  final Condition cond;
  final Effect then;
  final Effect? otherwise;
}

/// "<player> <effect> unless they <cost/action>" (Painful Quandary, ward).
class Unless extends Effect {
  const Unless(this.effect, this.payer, {this.mana, this.life, this.alternative});
  final Effect effect;
  final PlayerRef payer;
  final ManaCost? mana;
  final int? life;

  /// An action the payer may take instead ("unless that player sacrifices a nonland permanent").
  final Effect? alternative;
}

/// Repeat for each player in [players], with "that player" bound to each.
class ForEachPlayer extends Effect {
  const ForEachPlayer(this.players, this.effect);
  final PlayerRef players;
  final Effect effect;
}

class DealDamage extends Effect {
  const DealDamage(this.amount, this.to, {this.source = const SelfRef(), this.toPlayers, this.divided = false, this.excessSlot});
  final Amount amount;
  final ObjSet? to;
  final PlayerRef? toPlayers;
  final ObjRef source;
  final bool divided;

  /// Records the excess damage dealt to a creature (Goblin Negotiation).
  final String? excessSlot;
}

/// Damage to "any target" chosen as target [index] (object or player).
class DamageTarget extends Effect {
  const DamageTarget(this.amount, this.index, {this.source = const SelfRef(), this.divided = false});
  final Amount amount;
  final int index;
  final ObjRef source;
  final bool divided;
}

class Fight extends Effect {
  const Fight(this.a, this.b);
  final ObjRef a, b;
}

class Draw extends Effect {
  const Draw(this.amount, {this.who = const You()});
  final Amount amount;
  final PlayerRef who;
}

class Discard extends Effect {
  const Discard(this.amount, {this.who = const You(), this.random = false, this.chooser, this.filter = Filter.any, this.hand = false});
  final Amount amount;
  final PlayerRef who;
  final bool random;

  /// Who chooses the discarded card (Pilfer: you choose from their revealed hand).
  final PlayerRef? chooser;
  final Filter filter;
  final bool hand;
}

class GainLife extends Effect {
  const GainLife(this.amount, {this.who = const You()});
  final Amount amount;
  final PlayerRef who;
}

class LoseLife extends Effect {
  const LoseLife(this.amount, {this.who = const You(), this.slot});
  final Amount amount;
  final PlayerRef who;

  /// Records the total life lost (Exsanguinate's "the life lost this way").
  final String? slot;
}

class Mill extends Effect {
  const Mill(this.amount, {this.who = const You()});
  final Amount amount;
  final PlayerRef who;
}

class Scry extends Effect {
  const Scry(this.amount);
  final Amount amount;
}

class Surveil extends Effect {
  const Surveil(this.amount);
  final Amount amount;
}

class Destroy extends Effect {
  const Destroy(this.set, {this.noRegen = false});
  final ObjSet set;
  final bool noRegen;
}

/// Moves objects to a zone: exile, return to hand, put on top/bottom of library, return to the
/// battlefield, put into graveyard.
class MoveTo extends Effect {
  const MoveTo(this.set, this.zone,
      {this.tapped = false,
      this.underYourControl = false,
      this.libraryBottom = false,
      this.ownerChoosesTopOrBottom = false,
      this.counters = const {},
      this.remember,
      this.untilSourceLeaves = false,
      this.facedown = false,
      this.attacking = false,
      this.extraTypes = const [],
      this.libraryPosition});
  final ObjSet set;
  final ZoneKind zone;
  final bool tapped, underYourControl, libraryBottom, ownerChoosesTopOrBottom;
  final Map<String, int> counters;
  final String? remember;
  final bool untilSourceLeaves;
  final bool facedown;
  final bool attacking;

  /// "It's a Demon in addition to its other types."
  final List<String> extraTypes;
  final int? libraryPosition;
}

class Sacrifice extends Effect {
  const Sacrifice(this.who, this.filter, this.amount, {this.self = false});
  final PlayerRef who;
  final Filter filter;
  final Amount amount;
  final bool self;
}

class Tap extends Effect {
  const Tap(this.set);
  final ObjSet set;
}

class Untap extends Effect {
  const Untap(this.set);
  final ObjSet set;
}

/// Turns a transforming double-faced permanent to its other face (CR 701.28).
class TransformPermanents extends Effect {
  const TransformPermanents(this.set);
  final ObjSet set;
}

class PutCounters extends Effect {
  const PutCounters(this.set, this.kind, this.amount);
  final ObjSet set;
  final String kind;
  final Amount amount;
}

class RemoveCounters extends Effect {
  const RemoveCounters(this.set, this.kind, this.amount, {this.slot});
  final ObjSet set;
  final String kind;
  final Amount amount;
  final String? slot;
}

/// "Double the number of +1/+1 counters on ~" / "each kind of counter".
class DoubleCounters extends Effect {
  const DoubleCounters(this.set, {this.kind});
  final ObjSet set;
  final String? kind;
}

class Proliferate extends Effect {
  const Proliferate();
}

/// A token's characteristics (CR 111).
class TokenSpec {
  const TokenSpec({
    required this.name,
    this.power,
    this.toughness,
    this.colors = const {},
    this.types = const {CardType.creature},
    this.subtypes = const [],
    this.supertypes = const {},
    this.keywords = const [],
    this.abilities = const [],
    this.text = '',
  });
  final String name;
  final int? power, toughness;
  final Set<ManaColor> colors;
  final Set<CardType> types;
  final List<String> subtypes;
  final Set<Supertype> supertypes;
  final List<Kw> keywords;
  final List<Ability> abilities;
  final String text;

  String get key => '$name|$power/$toughness|${colors.map((c) => c.symbol).join()}|${types.map((t) => t.name).join(',')}|${subtypes.join(',')}|${keywords.map((k) => k.key).join(',')}|$text';
}

class CreateToken extends Effect {
  const CreateToken(this.spec, this.amount, {this.controller = const You(), this.tapped = false, this.attacking = false, this.remember = 'created'});
  final TokenSpec spec;
  final Amount amount;
  final PlayerRef controller;
  final bool tapped, attacking;
  final String remember;
}

/// "Create a token that's a copy of <obj>, except ..."
class CreateCopy extends Effect {
  const CreateCopy(this.of, {this.amount = const Fixed(1), this.extraMods = const [], this.sacrificeAtEnd = false, this.remember = 'created', this.controller = const You()});
  final ObjRef of;
  final Amount amount;
  final List<Mod> extraMods;
  final bool sacrificeAtEnd;
  final String remember;
  final PlayerRef controller;
}

/// A continuous effect from a resolving spell or ability (CR 611.2): [mods] apply to [set] for
/// [duration]. For a filter set, the affected objects are locked in as it resolves (611.2c).
class Grant extends Effect {
  const Grant(this.set, this.mods, {this.duration = EffectDuration.endOfTurn});
  final ObjSet set;
  final List<Mod> mods;
  final EffectDuration duration;
}

/// "Double target creature's power".
class DoublePower extends Effect {
  const DoublePower(this.obj);
  final ObjRef obj;
}

class CounterSpell extends Effect {
  const CounterSpell(this.obj, {this.exileInstead = false});
  final ObjRef obj;
  final bool exileInstead;
}

/// Counters the spell or ability the trigger event names (ward, CR 702.21).
class CounterEventItem extends Effect {
  const CounterEventItem();
}

class GainControl extends Effect {
  const GainControl(this.set, {this.duration = EffectDuration.permanent});
  final ObjSet set;
  final EffectDuration duration;
}

/// "Search your library for up to N <filter> cards, put them <zone>, then shuffle."
class Search extends Effect {
  const Search(this.filter, this.amount, this.zone, {this.tapped = false, this.reveal = false, this.upTo = true, this.thenShuffle = true, this.onTop = false});
  final Filter filter;
  final Amount amount;
  final ZoneKind zone;
  final bool tapped, reveal, upTo, thenShuffle;

  /// "Shuffle and put that card on top".
  final bool onTop;
}

/// "Look at the top N cards of your library. You may reveal a <filter> card from among them and
/// put it into <zone>. Put the rest on the bottom in a random order / into your graveyard."
class LookAndPick extends Effect {
  const LookAndPick(this.n, this.filter, this.pick, this.zone, {this.rest = RestGoes.bottomRandom, this.mayPick = true, this.reveal = true, this.tapped = false});
  final Amount n;
  final Filter filter;
  final Amount pick;
  final ZoneKind zone;
  final RestGoes rest;
  final bool mayPick, reveal, tapped;
}

enum RestGoes { bottomRandom, bottomAnyOrder, graveyard, top, exile, topAnyOrder }

/// Reveal cards from the top until a matching card; it goes to [zone], the rest to [rest].
class RevealUntil extends Effect {
  const RevealUntil(this.filter, this.zone, {this.rest = RestGoes.bottomRandom, this.who = const You()});
  final Filter filter;
  final ZoneKind zone;
  final RestGoes rest;
  final PlayerRef who;
}

/// Exile the top N cards; you may play them until [until] (impulse draw).
class ExileTopMayPlay extends Effect {
  const ExileTopMayPlay(this.n, {this.chooseOne = false, this.untilEndOfNextTurn = false, this.who = const You()});
  final Amount n;
  final bool chooseOne;
  final bool untilEndOfNextTurn;
  final PlayerRef who;
}

class AddMana extends Effect {
  const AddMana(this.produce);
  final ManaProduce produce;
}

class Shuffle extends Effect {
  const Shuffle({this.who = const You()});
  final PlayerRef who;
}

/// "Attach it to target creature you control" / equip.
class Attach extends Effect {
  const Attach(this.what, this.to);
  final ObjRef what;
  final ObjRef to;
}

/// "Exile target ... until ~ leaves the battlefield" return handled through [MoveTo.untilSourceLeaves].
/// A delayed trigger created by a resolving effect (CR 603.7).
class Delayed extends Effect {
  const Delayed(this.trigger, this.effect, {this.oneShot = true});
  final Trigger trigger;
  final Effect effect;
  final bool oneShot;
}

/// You get an emblem with these abilities (CR 114).
class Emblem extends Effect {
  const Emblem(this.abilities, this.text);
  final List<Ability> abilities;
  final String text;
}

/// "End the turn" (CR 723).
class EndTurn extends Effect {
  const EndTurn();
}

/// A choice of one of several effects at resolution ("choose one" on a triggered ability is
/// chosen when it's put on the stack; this is for "choose one. you may play that card").
class Noop extends Effect {
  const Noop();
}

/// Copy a spell on the stack (Thousand-Year Storm).
class CopySpell extends Effect {
  const CopySpell(this.obj, {this.amount = const Fixed(1), this.newTargets = true});
  final ObjRef obj;
  final Amount amount;
  final bool newTargets;
}

/// "You may cast target card from your graveyard this turn" and similar permissions.
class AllowPlay extends Effect {
  const AllowPlay(this.set, {this.duration = EffectDuration.endOfTurn, this.free = false});
  final ObjSet set;
  final EffectDuration duration;
  final bool free;
}

/// Rules-changing effects with a duration ("you can't lose the game" from a spell, "players can't
/// gain life this turn"). Most come from statics instead.
class RuleChange extends Effect {
  const RuleChange(this.rule, {this.duration = EffectDuration.endOfTurn});
  final RuleMod rule;
  final EffectDuration duration;
}

/// Reveal top X, put permanents with MV ≤ X onto battlefield, rest into graveyard (Genesis Wave).
class RevealPutPermanents extends Effect {
  const RevealPutPermanents(this.n);
  final Amount n;
}

/// Curator of Destinies: look at five, split into face-down and face-up piles, an opponent
/// chooses one for your hand, the other goes to the graveyard.
class PilesChoice extends Effect {
  const PilesChoice(this.n);
  final Amount n;
}

/// Pick cards from one revealed/looked-at set of remembered cards.
class ChooseFromRemembered extends Effect {
  const ChooseFromRemembered(this.slot, this.n, this.then);
  final String slot;
  final int n;
  final Effect then;
}

/// Choose a mode at resolution (Sylvan Scavenging's "choose one" happens on stack placement; this
/// is for in-resolution choices).
class ChooseEffect extends Effect {
  const ChooseEffect(this.options, {this.chooser = const You(), this.labels = const []});
  final List<Effect> options;
  final PlayerRef chooser;
  final List<String> labels;
}

/// Each opponent chooses a permanent of each permanent type and sacrifices the rest (Liliana).
class KeepOneOfEachType extends Effect {
  const KeepOneOfEachType(this.who);
  final PlayerRef who;
}

/// Exile, then return to the battlefield under its owner's control (blink) — modeled as moves.

// ---------------------------------------------------------------------------------------------
// Mana production (CR 106, 605)
// ---------------------------------------------------------------------------------------------

class ManaProduce {
  const ManaProduce({this.fixed = const [], this.choice = const [], this.anyColor = false, this.amount = const Fixed(1), this.chosenColor = false, this.restriction});

  /// Fixed mana ({C}{C}, {R}{G}).
  final List<ManaType> fixed;

  /// One mana of a type from this list ("{R} or {G}").
  final List<ManaType> choice;

  /// One mana of any color.
  final bool anyColor;

  /// For [choice]/[anyColor]: how many ("Add {G} for each Elf you control" puts the count here
  /// with fixed = [G]).
  final Amount amount;
  final bool chosenColor;

  /// "Spend this mana only to cast an Angel spell."
  final Filter? restriction;

  /// Mana types this ability can produce.
  List<ManaType> get possible {
    if (anyColor || chosenColor) return const [ManaType.W, ManaType.U, ManaType.B, ManaType.R, ManaType.G];
    if (choice.isNotEmpty) return choice;
    return fixed.toSet().toList();
  }
}

// ---------------------------------------------------------------------------------------------
// Triggers (CR 603)
// ---------------------------------------------------------------------------------------------

enum TurnStep { untap, upkeep, draw, main1, beginCombat, declareAttackers, declareBlockers, firstStrikeDamage, combatDamage, endCombat, main2, end, cleanup }

sealed class Trigger {
  const Trigger();
}

/// An object matching [set] enters (self: "when ~ enters").
class EntersTrigger extends Trigger {
  const EntersTrigger(this.set, {this.cast});
  final ObjSet set;

  /// "Enters, if you cast it" handled by condition; this is for "whenever you cast" + enters.
  final bool? cast;
}

class DiesTrigger extends Trigger {
  const DiesTrigger(this.set, {this.damagedBySelf = false});
  final ObjSet set;

  /// "Whenever a creature dealt damage by ~ this turn dies."
  final bool damagedBySelf;
}

/// Leaves the battlefield (any zone).
class LeavesTrigger extends Trigger {
  const LeavesTrigger(this.set);
  final ObjSet set;
}

/// An object goes to a graveyard from anywhere ("put into a graveyard").
class PutIntoGraveyardTrigger extends Trigger {
  const PutIntoGraveyardTrigger(this.set, {this.fromBattlefield = false});
  final ObjSet set;
  final bool fromBattlefield;
}

class AttacksTrigger extends Trigger {
  const AttacksTrigger(this.set, {this.alone = false, this.condition, this.minAttackers = 0, this.attacksYou = false});
  final ObjSet set;
  final bool alone;

  /// "Whenever ~ and at least two other creatures attack": at least this many attackers.
  final int minAttackers;

  /// "Whenever a creature attacks you or a planeswalker you control."
  final bool attacksYou;

  /// "Whenever ~ attacks while you control ..." (checked as the trigger event happens).
  final Condition? condition;
}

/// "Whenever you attack" (with [min] creatures).
class YouAttackTrigger extends Trigger {
  const YouAttackTrigger({this.min = 1});
  final int min;
}

/// [other]: "blocks a creature (with flying)": triggers once per blocked creature, which is
/// the event's object ("that creature").
class BlocksTrigger extends Trigger {
  const BlocksTrigger(this.set, {this.other});
  final ObjSet set;
  final Filter? other;
}

/// [other]: "becomes blocked by a creature": once per blocker, which is "that creature".
class BecomesBlockedTrigger extends Trigger {
  const BecomesBlockedTrigger(this.set, {this.other});
  final ObjSet set;
  final Filter? other;
}

/// "Whenever ~ attacks and isn't blocked" (checked once blockers are declared).
class UnblockedTrigger extends Trigger {
  const UnblockedTrigger(this.set);
  final ObjSet set;
}

/// "Whenever ~ becomes tapped".
class TappedTrigger extends Trigger {
  const TappedTrigger(this.set);
  final ObjSet set;
}

/// "When you cycle ~" ([self]) / "whenever you/a player cycles a card" (CR 702.29).
class CycleTrigger extends Trigger {
  const CycleTrigger(this.who, {this.self = false});
  final Who who;
  final bool self;
}

/// "Whenever you commit a crime" (targeting an opponent, their permanents or spells, or cards
/// in their graveyard).
class CrimeTrigger extends Trigger {
  const CrimeTrigger();
}

/// "Whenever you scry" / "whenever you surveil" / "whenever you scry or surveil".
class ScryTrigger extends Trigger {
  const ScryTrigger(this.who, {this.scry = true, this.surveil = false});
  final Who who;
  final bool scry, surveil;
}

/// "When ~ transforms (into …)".
class TransformedTrigger extends Trigger {
  const TransformedTrigger(this.set);
  final ObjSet set;
}

/// A source in [set] deals damage. [toPlayer]/[toOpponent]: only to a player; [combat]: only
/// combat damage (true) or only noncombat (false).
class DealsDamageTrigger extends Trigger {
  const DealsDamageTrigger(this.set, {this.toPlayer = false, this.toOpponent = false, this.combat, this.toCreature = false, this.duringYourTurn = false, this.orTypes = const {}});
  final ObjSet set;
  final bool toPlayer, toOpponent, toCreature;

  /// "to a player or planeswalker": with [toPlayer], permanents of these types count too.
  final Set<CardType> orTypes;
  final bool? combat;
  final bool duringYourTurn;
}

class IsDealtDamageTrigger extends Trigger {
  const IsDealtDamageTrigger(this.set);
  final ObjSet set;
}

/// A player in [who] casts a spell matching [filter].
class CastTrigger extends Trigger {
  const CastTrigger(this.who, this.filter, {this.duringOpponentsTurn = false, this.self = false, this.nth = 0, this.orCopy = false, this.targets, this.kicked = false});
  final Who who;
  final Filter filter;
  final bool duringOpponentsTurn;

  /// "When you cast ~": the spell's own ability, from the stack.
  final bool self;

  /// "Your second spell each turn" (counting the caster's spells this turn).
  final int nth;

  /// "Whenever you cast or copy …".
  final bool orCopy;

  /// "A spell that targets ~": the spell must target something in this set.
  final ObjSet? targets;

  /// "A kicked spell".
  final bool kicked;
}

/// The beginning of [step] of [whose] turn.
class StepTrigger extends Trigger {
  const StepTrigger(this.step, this.whose, {this.ofAttached = false});
  final TurnStep step;
  final Who whose;

  /// "Enchanted creature's controller's upkeep" / "enchanted player's upkeep".
  final bool ofAttached;
}

class GainLifeTrigger extends Trigger {
  const GainLifeTrigger(this.who, {this.firstTimeEachTurn = false, this.onlyYourTurn = false});
  final Who who;
  final bool firstTimeEachTurn, onlyYourTurn;
}

class LoseLifeTrigger extends Trigger {
  const LoseLifeTrigger(this.who);
  final Who who;
}

/// A player draws a card; [nth] = 2 for "your second card each turn".
class DrawTrigger extends Trigger {
  const DrawTrigger(this.who, {this.nth = 0});
  final Who who;
  final int nth;
}

class DiscardTrigger extends Trigger {
  const DiscardTrigger(this.who);
  final Who who;
}

/// Counters of [kind] are put on an object in [set].
class CountersPutTrigger extends Trigger {
  const CountersPutTrigger(this.set, this.kind);
  final ObjSet set;
  final String kind;
}

class BecomesTargetTrigger extends Trigger {
  const BecomesTargetTrigger(this.set, {this.byOpponent = true});
  final ObjSet set;
  final bool byOpponent;
}

class BecomesUntappedTrigger extends Trigger {
  const BecomesUntappedTrigger(this.set);
  final ObjSet set;
}

class SacrificedTrigger extends Trigger {
  const SacrificedTrigger(this.set);
  final ObjSet set;
}

/// A token is created / cards leave the graveyard / etc. are added as cards need them.
class TokenCreatedTrigger extends Trigger {
  const TokenCreatedTrigger(this.who);
  final Who who;
}

// ---------------------------------------------------------------------------------------------
// Replacement effects (CR 614–616) and other rule modifications
// ---------------------------------------------------------------------------------------------

sealed class Replacement {
  const Replacement();
}

/// "~ enters tapped", "creatures your opponents control enter tapped".
class EntersTapped extends Replacement {
  const EntersTapped(this.set, {this.unless});
  final ObjSet set;
  final Condition? unless;
}

/// "~ enters with N counters on it" (optionally "if ...").
class EntersWithCounters extends Replacement {
  const EntersWithCounters(this.set, this.kind, this.amount, {this.condition});
  final ObjSet set;
  final String kind;
  final Amount amount;
  final Condition? condition;
}

/// "As ~ enters, choose a color / creature type."
class ChooseOnEnter extends Replacement {
  const ChooseOnEnter(this.what);
  final String what; // 'color' | 'creature type' | 'opponent'
}

/// "Prevent all (non)combat damage that would be dealt to <set>".
class PreventDamage extends Replacement {
  const PreventDamage(this.set, {this.combat, this.toYou = false});
  final ObjSet set;
  final bool? combat;
  final bool toYou;
}

/// "If a source you control would deal damage to an opponent or a permanent an opponent controls,
/// it deals double that damage instead."
class DoubleDamage extends Replacement {
  const DoubleDamage({this.sourceFilter = Filter.any, this.toOpponentsOnly = true});
  final Filter sourceFilter;
  final bool toOpponentsOnly;
}

/// Doubling Season's halves.
class DoubleTokens extends Replacement {
  const DoubleTokens();
}

class DoubleCountersReplacement extends Replacement {
  const DoubleCountersReplacement();
}

/// "If ~ would be put into a graveyard from anywhere, <instead>" (Progenitus) and "if it would
/// die, exile it instead".
class InsteadOfGraveyard extends Replacement {
  const InsteadOfGraveyard(this.set, this.to, {this.shuffleIntoLibrary = false, this.onlyFromBattlefield = false});
  final ObjSet set;
  final ZoneKind to;
  final bool shuffleIntoLibrary;
  final bool onlyFromBattlefield;
}

/// "Each other Angel you control enters with an additional +1/+1 counter for each Angel you
/// already control."
class ExtraCountersOnEnter extends Replacement {
  const ExtraCountersOnEnter(this.set, this.kind, this.amount);
  final ObjSet set;
  final String kind;
  final Amount amount;
}

/// Static rules changes that aren't layer effects.
sealed class RuleMod {
  const RuleMod();
}

class NoMaxHandSize extends RuleMod {
  const NoMaxHandSize();
}

class ExtraLandPerTurn extends RuleMod {
  const ExtraLandPerTurn(this.n);
  final int n;
}

/// "You may cast spells as though they had flash" (filter on the spells).
class CastAsThoughFlash extends RuleMod {
  const CastAsThoughFlash(this.filter);
  final Filter filter;
}

class CantLoseGame extends RuleMod {
  const CantLoseGame();
}

class OpponentsCantWin extends RuleMod {
  const OpponentsCantWin();
}

/// "You have hexproof."
class PlayerHexproof extends RuleMod {
  const PlayerHexproof();
}

/// "You may cast spells from your hand without paying their mana costs."
class CastWithoutPaying extends RuleMod {
  const CastWithoutPaying(this.filter);
  final Filter filter;
}

/// Spells matching [filter] that [who] casts cost [delta] more (negative: less). [amount]
/// overrides delta with a per-count reduction ("{1} less for each Cat you control").
class CostChange extends RuleMod {
  const CostChange(this.filter, this.delta, {this.who = Who.you, this.amount, this.selfOnly = false, this.condition, this.targetsFilter});
  final Filter filter;
  final int delta;
  final Who who;
  final Amount? amount;

  /// "This spell costs ..." on the spell itself (applies from the hand/stack).
  final bool selfOnly;
  final Condition? condition;

  /// "If it targets a tapped creature".
  final Filter? targetsFilter;
}

/// "You may play lands and cast permanent spells from your graveyard" (Muldrotha) and the like.
class PlayFromGraveyard extends RuleMod {
  const PlayFromGraveyard(this.filter, {this.oncePerTypeEachTurn = false});
  final Filter filter;
  final bool oncePerTypeEachTurn;
}

// ---------------------------------------------------------------------------------------------
// Abilities (CR 113)
// ---------------------------------------------------------------------------------------------

/// What an ability does when it resolves: its targets and effect. Modal abilities have [modes].
class Body {
  const Body({this.targets = const [], this.effect = const Noop(), this.modes = const [], this.minModes = 1, this.maxModes = 1, this.modeLabels = const []});
  final List<TargetSpec> targets;
  final Effect effect;
  final List<Body> modes;
  final int minModes, maxModes;
  final List<String> modeLabels;

  bool get isModal => modes.isNotEmpty;
}

sealed class Ability {
  const Ability(this.text);

  /// The oracle text this ability came from.
  final String text;
}

/// The effect of an instant or sorcery (CR 113.3a).
class SpellAbility extends Ability {
  const SpellAbility(super.text, this.body);
  final Body body;
}

class ActivatedAbility extends Ability {
  const ActivatedAbility(super.text, this.cost, this.body, {this.sorcerySpeed = false, this.oncePerTurn = false, this.onlyOnce = false, this.zone = ZoneKind.battlefield, this.yourTurnOnly = false, this.condition, this.isEquip = false});
  final Cost cost;
  final Body body;
  final bool sorcerySpeed, oncePerTurn, onlyOnce, yourTurnOnly;
  final ZoneKind zone;
  final Condition? condition;
  final bool isEquip;
  bool get isLoyalty => cost.loyalty != null;
}

class ManaAbility extends Ability {
  const ManaAbility(super.text, this.cost, this.produce);
  final Cost cost;
  final ManaProduce produce;
}

class TriggeredAbility extends Ability {
  const TriggeredAbility(super.text, this.trigger, this.body, {this.condition, this.oncePerTurn = false, this.zone = ZoneKind.battlefield, this.optionalCost});
  final Trigger trigger;
  final Body body;

  /// Intervening "if" clause (CR 603.4): checked when it triggers and on resolution.
  final Condition? condition;
  final bool oncePerTurn;
  final ZoneKind zone;
  final ManaCost? optionalCost;
}

/// A static ability with continuous effects on [set] (CR 604, 611.3), while [condition] holds.
class StaticAbility extends Ability {
  const StaticAbility(super.text, this.set, this.mods, {this.condition, this.zone = ZoneKind.battlefield});
  final ObjSet set;
  final List<Mod> mods;
  final Condition? condition;
  final ZoneKind zone;
}

class ReplacementAbility extends Ability {
  const ReplacementAbility(super.text, this.replacement, {this.zone = ZoneKind.battlefield});
  final Replacement replacement;
  final ZoneKind zone;
}

class RuleAbility extends Ability {
  const RuleAbility(super.text, this.rule, {this.condition, this.zone = ZoneKind.battlefield});
  final RuleMod rule;
  final Condition? condition;
  final ZoneKind zone;
}

/// A keyword the object has (flying, ward, ...). Costed keywords are compiled into other
/// abilities too (equip → activated; kicker → cast option; flashback → cast option).
class KeywordAbility extends Ability {
  const KeywordAbility(super.text, this.kw);
  final Kw kw;
}

/// Enchant (CR 702.5): what an Aura can enchant.
class EnchantAbility extends Ability {
  const EnchantAbility(super.text, this.filter, {this.player = false});
  final Filter filter;
  final bool player;
}

/// Cast options granted by the card itself (kicker, flashback, additional/alternative costs).
class CastOptionAbility extends Ability {
  const CastOptionAbility(super.text, this.option);
  final CastOption option;
}

/// Text with no game effect ("A deck can have any number of cards named ~").
class InfoAbility extends Ability {
  const InfoAbility(super.text, {this.anyNumber = false, this.openingHandBattlefield = false});
  final bool anyNumber;
  final bool openingHandBattlefield;
}

// ---------------------------------------------------------------------------------------------
// Regeneration, prevention shields, hands and chance (CR 701.15, 615.7, 701.20, 705, 706)
// ---------------------------------------------------------------------------------------------

/// "Regenerate ~" (CR 701.15): the next time it would be destroyed this turn, instead tap it,
/// remove all damage from it and remove it from combat.
class Regenerate extends Effect {
  const Regenerate(this.set);
  final ObjSet set;
}

/// A prevention shield until end of turn (CR 615.7): "prevent the next 3 damage that would be
/// dealt to any target", "prevent all combat damage that would be dealt this turn".
/// One of [target] (a target index: player or object), [set] or [toYou] says what's protected;
/// none of them protects everything (Fog). [by] instead stops damage dealt by those objects.
class PreventNext extends Effect {
  const PreventNext({this.amount, this.target, this.set, this.toYou = false, this.by, this.combatOnly = false});

  /// Null: all of it.
  final Amount? amount;
  final int? target;
  final ObjSet? set;
  final bool toYou;
  final ObjSet? by;
  final bool combatOnly;
}

/// "Target opponent reveals their hand" / "look at target player's hand"; with [filter], you
/// then choose a card from it that's discarded (or exiled): Duress (CR 701.20).
class RevealHand extends Effect {
  const RevealHand(this.who, {this.filter, this.exile = false, this.optional = false});
  final PlayerRef who;
  final Filter? filter;
  final bool exile;

  /// "You may choose …. If you do, …".
  final bool optional;
}

/// "It explores" (CR 701.44): reveal the top card; a land goes to hand, otherwise a +1/+1
/// counter on the creature and the card may go to the graveyard.
class Explore extends Effect {
  const Explore(this.set);
  final ObjSet set;
}

/// "Flip a coin" (CR 705); [WonFlip] reads the result.
class FlipCoin extends Effect {
  const FlipCoin();
}

/// "Roll a six-sided die" (CR 706); [RollResult] reads the total.
class RollDie extends Effect {
  const RollDie(this.sides, {this.count = 1});
  final int sides;
  final int count;
}

/// "If you win the flip" / "if you lose the flip".
class WonFlip extends Condition {
  const WonFlip(this.won);
  final bool won;
}

/// The total of the last die roll in this resolution.
class RollResult extends Amount {
  const RollResult();
}

/// "You may look at the top card of your library any time" (an exception to CR 401.2): the
/// table shows that player their top card.
class LookAtTopAnyTime extends RuleMod {
  const LookAtTopAnyTime();
}

// ---------------------------------------------------------------------------------------------
// More effects: energy, paying during resolution, clash, amass, bolster, untap skipping...
// ---------------------------------------------------------------------------------------------

/// "You get {E}{E}" (CR 122.1): energy counters on a player.
class GetEnergy extends Effect {
  const GetEnergy(this.amount, {this.who = const You(), this.poison = false});
  final Amount amount;
  final PlayerRef who;

  /// Poison counters instead (CR 122.1f; ten or more and a player loses, CR 704.5c).
  final bool poison;
}

/// "Pay {E}{E}" as a cost.
class EnergyCost extends CostPart {
  const EnergyCost(this.n);
  final int n;
}

/// The energy a player has ("the amount of {E} you have").
class EnergyOf extends Amount {
  const EnergyOf(this.player);
  final PlayerRef player;
}

/// "You may pay {2}" / "pay 3 life" / "pay {E}{E}" while resolving; "if you do" follows.
class PayEffect extends Effect {
  const PayEffect({this.mana, this.life = 0, this.energy = 0});
  final ManaCost? mana;
  final int life, energy;
}

/// "Clash with an opponent" (CR 701.23); "if you win" reads [WonClash].
class Clash extends Effect {
  const Clash();
}

class WonClash extends Condition {
  const WonClash();
}

/// "Amass Zombies 2" (CR 701.47).
class Amass extends Effect {
  const Amass(this.subtype, this.amount);
  final String subtype;
  final Amount amount;
}

/// "Bolster 2" (CR 701.39): counters on the creature you control with the least toughness.
class Bolster extends Effect {
  const Bolster(this.amount);
  final Amount amount;
}

/// "… doesn't untap during its controller's next untap step".
class SkipNextUntap extends Effect {
  const SkipNextUntap(this.set);
  final ObjSet set;
}

/// "Take an extra turn after this one" (CR 500.7).
class ExtraTurn extends Effect {
  const ExtraTurn({this.who = const You()});
  final PlayerRef who;
}

/// A player chooses [amount] objects matching [filter] in [from] (not targeted) and moves them
/// to [to]: "return a land you control to its owner's hand", "you may put a land card from your
/// hand onto the battlefield tapped".
class ChooseAndMove extends Effect {
  const ChooseAndMove(this.filter, this.from, this.to, {this.who = const You(), this.amount = const Fixed(1), this.tapped = false});
  final Filter filter;
  final ZoneKind from, to;
  final PlayerRef who;
  final Amount amount;
  final bool tapped;
}

/// "Sacrifice it at the beginning of the next end step" ([sacrifice]) or "return it to the
/// battlefield under its owner's control at the beginning of the next end step" ([returnIt]).
class AtNextEndStep extends Effect {
  const AtNextEndStep(this.set, {this.sacrifice = false, this.returnIt = false, this.exile = false, this.toHand = false, this.underYourControl = false, this.step = TurnStep.end});
  final ObjSet set;
  final bool sacrifice, returnIt, exile, toHand, underYourControl;

  /// The next end step, or end of combat ("sacrifice it at end of combat").
  final TurnStep step;
}

/// "Choose a color" / "choose a creature type" while resolving: kept on the source, where "of
/// the chosen color/type" reads it.
class ChooseValue extends Effect {
  const ChooseValue(this.what);
  final String what; // 'color' | 'creature type'
}

/// "Populate" (CR 701.30): copy a creature token you control.
class Populate extends Effect {
  const Populate();
}

/// Activation windows: "activate only during your upkeep", "… before attackers are declared".
class StepIn extends Condition {
  const StepIn(this.steps);
  final Set<TurnStep> steps;
}
