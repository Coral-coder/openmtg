/// Game state (CR 100–123, 400–408): players, objects, zones, the stack, and what the game is
/// waiting for. Everything here is plain data with a deep [GameState.clone] and a canonical
/// [GameState.digest]. Maps and sets are Dart's default insertion-ordered ones, so iteration
/// order is the same on every device.
library;

import '../cards/card.dart';
import '../cards/mana.dart';
import '../ir/ir.dart';
import '../util/rng.dart';
import 'chars.dart';
import 'rules_options.dart';

typedef PlayerId = int;
typedef ObjId = int;

/// Players and objects share one id space for targets and attack targets: players are negative.
int playerEntity(PlayerId p) => -1 - p;
bool isPlayerEntity(int e) => e < 0;
PlayerId entityPlayer(int e) => -1 - e;

enum Zone { library, hand, battlefield, graveyard, exile, stack, command, none }

ZoneKind zoneKindOf(Zone z) => switch (z) {
      Zone.library => ZoneKind.library,
      Zone.hand => ZoneKind.hand,
      Zone.battlefield => ZoneKind.battlefield,
      Zone.graveyard => ZoneKind.graveyard,
      Zone.exile => ZoneKind.exile,
      Zone.stack => ZoneKind.stack,
      Zone.command => ZoneKind.command,
      Zone.none => ZoneKind.anywhere,
    };

Zone zoneOfKind(ZoneKind k) => switch (k) {
      ZoneKind.library => Zone.library,
      ZoneKind.hand => Zone.hand,
      ZoneKind.battlefield => Zone.battlefield,
      ZoneKind.graveyard => Zone.graveyard,
      ZoneKind.exile => Zone.exile,
      ZoneKind.stack => Zone.stack,
      ZoneKind.command => Zone.command,
      ZoneKind.anywhere => Zone.none,
    };

/// A card or token in the game. The id stays with the physical card; [zcc] counts zone changes,
/// so a reference made before a zone change (CR 400.7) can tell it is now a new object.
class GameObject {
  GameObject({required this.id, required this.cardName, required this.owner, required this.zone, this.token}) : controller = owner;

  final ObjId id;
  int zcc = 0;

  /// Database name of the card; for tokens, the token's name.
  String cardName;

  /// Token characteristics (null for cards).
  TokenSpec? token;

  /// A token created as a copy of a card or token: copiable values from here (CR 707).
  String? copyOfCard;
  TokenSpec? copyOfToken;
  int? copyOfFace;
  List<Mod> copyExtra = [];

  final PlayerId owner;
  PlayerId controller;
  Zone zone;

  bool tapped = false;
  bool faceDown = false;
  bool phasedOut = false;

  /// For double-faced cards: the back face is up. For split/adventure on the stack: which half.
  int face = 0;

  Map<String, int> counters = {};
  int damage = 0;
  bool deathtouched = false;
  ObjId? attachedTo;
  int timestamp = 0;

  /// The turn its controller last gained control of it (summoning sickness, CR 302.6).
  int controlSince = 0;
  int enteredTurn = -1;
  bool wasCast = false;
  bool kicked = false;
  int x = 0;
  String? chosenColor, chosenType;

  /// Activated abilities used this turn (by ability text) and ever (for "activate only once").
  Map<String, int> activations = {};
  Set<String> activatedEver = {};

  /// May be played by [playableBy] until the end of turn [playableUntil] (impulse draw etc.).
  PlayerId? playableBy;
  int playableUntil = 0;
  bool playFree = false;

  bool sacrificeAtEnd = false;
  bool exileIfDies = false;

  /// Cast with flashback: exile it instead of anywhere else it would go from the stack.
  bool exileOnResolve = false;

  /// Put into its current zone this turn (for "put there this turn").
  int arrivedTurn = 0;

  // Combat (CR 506.4): what it attacks (an entity) and what it blocks / is blocked by.
  int? attacking;
  List<ObjId> blocking = [];
  List<ObjId> blockedBy = [];
  bool blocked = false;
  bool dealtFirstStrikeDamage = false;

  /// For an Aura or a copy: extra types granted as it moved ("it's a Demon in addition").
  List<String> extraTypes = [];

  /// Objects exiled "until ~ leaves the battlefield".
  List<ObjId> exiledUntilLeaves = [];

  /// Creatures that dealt damage to it this turn.
  List<ObjId> damagedBy = [];

  /// What it was attached to when that object left the battlefield (for look-back triggers).
  ObjId? lastAttached;

  bool get isToken => token != null || copyOfToken != null || (copyOfCard != null && tokenCopy);
  bool tokenCopy = false;

  GameObject clone() => GameObject(id: id, cardName: cardName, owner: owner, zone: zone, token: token)
    ..zcc = zcc
    ..copyOfCard = copyOfCard
    ..copyOfToken = copyOfToken
    ..copyOfFace = copyOfFace
    ..copyExtra = List.of(copyExtra)
    ..controller = controller
    ..tapped = tapped
    ..faceDown = faceDown
    ..phasedOut = phasedOut
    ..face = face
    ..counters = Map.of(counters)
    ..damage = damage
    ..deathtouched = deathtouched
    ..attachedTo = attachedTo
    ..timestamp = timestamp
    ..controlSince = controlSince
    ..enteredTurn = enteredTurn
    ..wasCast = wasCast
    ..kicked = kicked
    ..x = x
    ..chosenColor = chosenColor
    ..chosenType = chosenType
    ..activations = Map.of(activations)
    ..activatedEver = Set.of(activatedEver)
    ..playableBy = playableBy
    ..playableUntil = playableUntil
    ..playFree = playFree
    ..sacrificeAtEnd = sacrificeAtEnd
    ..exileIfDies = exileIfDies
    ..exileOnResolve = exileOnResolve
    ..arrivedTurn = arrivedTurn
    ..attacking = attacking
    ..blocking = List.of(blocking)
    ..blockedBy = List.of(blockedBy)
    ..blocked = blocked
    ..dealtFirstStrikeDamage = dealtFirstStrikeDamage
    ..extraTypes = List.of(extraTypes)
    ..exiledUntilLeaves = List.of(exiledUntilLeaves)
    ..damagedBy = List.of(damagedBy)
    ..lastAttached = lastAttached
    ..tokenCopy = tokenCopy;

  /// Resets what doesn't survive a zone change (CR 400.7).
  void resetForNewZone() {
    zcc++;
    tapped = false;
    faceDown = false;
    phasedOut = false;
    face = 0;
    counters = {};
    damage = 0;
    deathtouched = false;
    attachedTo = null;
    wasCast = false;
    kicked = false;
    x = 0;
    chosenColor = null;
    chosenType = null;
    activations = {};
    activatedEver = {};
    playableBy = null;
    playableUntil = 0;
    playFree = false;
    sacrificeAtEnd = false;
    exileIfDies = false;
    exileOnResolve = false;
    attacking = null;
    blocking = [];
    blockedBy = [];
    blocked = false;
    dealtFirstStrikeDamage = false;
    extraTypes = [];
    exiledUntilLeaves = [];
  }

  String digest() {
    final c = (counters.entries.where((e) => e.value != 0).map((e) => '${e.key}=${e.value}').toList()..sort()).join(',');
    final a = (activations.entries.map((e) => '${e.key}=${e.value}').toList()..sort()).join(';');
    return '$id.$zcc|$cardName|${token?.key ?? ''}|${copyOfCard ?? ''}|${copyOfToken?.key ?? ''}|$owner|$controller|${zone.index}|$tapped|$faceDown|$phasedOut|$face|$c|$damage|$deathtouched|$attachedTo|$timestamp|$controlSince|$enteredTurn|$wasCast|$kicked|$x|$chosenColor|$chosenType|$a|${(activatedEver.toList()..sort()).join(';')}|$playableBy|$playableUntil|$playFree|$sacrificeAtEnd|$exileIfDies|$exileOnResolve|$arrivedTurn|$attacking|${blocking.join(',')}|${blockedBy.join(',')}|$blocked|$dealtFirstStrikeDamage|${extraTypes.join(',')}|${exiledUntilLeaves.join(',')}|$tokenCopy|${copyExtra.length}|${damagedBy.join(',')}';
  }
}

/// A unit of mana in a pool, with an optional spending restriction (CR 106.4, 106.6).
class ManaUnit {
  const ManaUnit(this.type, {this.restriction, this.sourceId, this.keep = false});
  final ManaType type;
  final Filter? restriction;
  final ObjId? sourceId;

  /// Doesn't empty between steps this turn.
  final bool keep;
  String digest() => '${type.name}${restriction == null ? '' : 'r'}${keep ? 'k' : ''}';
}

/// Per-turn tallies used by conditions and triggers ("for the first time each turn").
class TurnStats {
  int lifeGained = 0;
  int lifeLost = 0;
  int cardsDrawn = 0;
  int spellsCast = 0;
  int noncreatureSpellsCast = 0;
  int instantSorceryCast = 0;
  int creaturesAttackedWith = 0;
  bool attacked = false;
  int landsPlayed = 0;
  int gainLifeEvents = 0;

  /// Permanent types cast from the graveyard this turn (Muldrotha).
  Set<String> graveyardPlays = {};

  TurnStats clone() => TurnStats()
    ..lifeGained = lifeGained
    ..lifeLost = lifeLost
    ..cardsDrawn = cardsDrawn
    ..spellsCast = spellsCast
    ..noncreatureSpellsCast = noncreatureSpellsCast
    ..instantSorceryCast = instantSorceryCast
    ..creaturesAttackedWith = creaturesAttackedWith
    ..attacked = attacked
    ..landsPlayed = landsPlayed
    ..gainLifeEvents = gainLifeEvents
    ..graveyardPlays = Set.of(graveyardPlays);

  String digest() => '$lifeGained,$lifeLost,$cardsDrawn,$spellsCast,$noncreatureSpellsCast,$instantSorceryCast,$creaturesAttackedWith,$attacked,$landsPlayed,$gainLifeEvents,${(graveyardPlays.toList()..sort()).join('+')}';
}

/// When a player wants the game to stop and give them priority instead of passing for them.
class Stops {
  Stops({Set<TurnStep>? mine, Set<TurnStep>? theirs, this.respond = true}) : mine = mine ?? {TurnStep.main1, TurnStep.main2, TurnStep.declareBlockers}, theirs = theirs ?? {TurnStep.declareBlockers};

  /// Steps of their own turn and of opponents' turns where they get priority.
  Set<TurnStep> mine, theirs;

  /// Stop when an opponent's spell or ability is on the stack and they could respond.
  bool respond;

  /// Pass everything until this turn's end (or until something they can respond to).
  int passUntilTurnEnds = -1;

  Stops clone() => Stops(mine: Set.of(mine), theirs: Set.of(theirs), respond: respond)..passUntilTurnEnds = passUntilTurnEnds;

  String digest() => '${mine.map((s) => s.index).toList()..sort()}/${theirs.map((s) => s.index).toList()..sort()}/$respond/$passUntilTurnEnds';

  Map<String, dynamic> toJson() => {'m': [for (final s in mine) s.index], 't': [for (final s in theirs) s.index], 'r': respond};

  static Stops fromJson(Map<String, dynamic> j) => Stops(
        mine: {for (final i in (j['m'] as List)) TurnStep.values[i as int]},
        theirs: {for (final i in (j['t'] as List)) TurnStep.values[i as int]},
        respond: j['r'] as bool? ?? true,
      );
}

class Player {
  Player(this.id, this.name);
  final PlayerId id;
  String name;
  int life = 20;
  int startingLife = 20;
  int poison = 0;
  List<ObjId> library = []; // index 0 is the top
  List<ObjId> hand = [];
  List<ObjId> graveyard = [];
  List<ObjId> exile = [];
  List<ManaUnit> pool = [];
  bool lost = false;
  bool won = false;
  String? lossReason;
  int mulligans = 0;
  bool kept = false;
  bool drewFromEmpty = false;
  TurnStats stats = TurnStats();
  Stops stops = Stops();

  /// Opening-hand card choices still owed (London mulligan bottoms).
  int toBottom = 0;

  Player clone() => Player(id, name)
    ..life = life
    ..startingLife = startingLife
    ..poison = poison
    ..library = List.of(library)
    ..hand = List.of(hand)
    ..graveyard = List.of(graveyard)
    ..exile = List.of(exile)
    ..pool = List.of(pool)
    ..lost = lost
    ..won = won
    ..lossReason = lossReason
    ..mulligans = mulligans
    ..kept = kept
    ..drewFromEmpty = drewFromEmpty
    ..stats = stats.clone()
    ..stops = stops.clone()
    ..toBottom = toBottom;

  List<ObjId> zoneList(Zone z) => switch (z) {
        Zone.library => library,
        Zone.hand => hand,
        Zone.graveyard => graveyard,
        Zone.exile => exile,
        _ => const [],
      };

  String digest() =>
      '$id|$name|$life|$startingLife|$poison|${library.join(',')}|${hand.join(',')}|${graveyard.join(',')}|${exile.join(',')}|${pool.map((m) => m.digest()).join()}|$lost|$won|$mulligans|$kept|$drewFromEmpty|${stats.digest()}|${stops.digest()}|$toBottom';
}

enum StackKind { spell, activated, triggered }

/// Something on the stack (CR 405): a spell (a card or copy, [objId]) or an ability.
class StackItem {
  StackItem({
    required this.id,
    required this.kind,
    required this.controller,
    required this.sourceId,
    required this.sourceZcc,
    required this.ability,
    this.objId,
    this.modes = const [0],
    this.targets = const [],
    this.x = 0,
    this.kicked = false,
    this.event,
    this.sourceName = '',
    this.isCopy = false,
    Map<String, int>? paidCost,
  }) : paidCost = paidCost ?? {};

  final int id;
  final StackKind kind;
  final PlayerId controller;
  final ObjId sourceId;
  final int sourceZcc;

  /// The ability (or spell ability) this item will resolve. Null for a permanent spell.
  final Ability? ability;

  /// The card (or copy) for a spell.
  final ObjId? objId;
  List<int> modes;

  /// Chosen targets per target spec (entities; objects carry their zcc in [targetZcc]).
  List<List<int>> targets;
  List<List<int>> targetZcc = [];
  int x;
  bool kicked;
  final EventInfo? event;
  final String sourceName;
  final bool isCopy;

  /// Values paid as costs that effects refer to (sacrificed creature's power, ...).
  final Map<String, int> paidCost;

  /// The source's characteristics as the ability was put on the stack (CR 113.7a).
  Chars? sourceLki;

  StackItem clone() => StackItem(
        id: id,
        kind: kind,
        controller: controller,
        sourceId: sourceId,
        sourceZcc: sourceZcc,
        ability: ability,
        objId: objId,
        modes: List.of(modes),
        targets: [for (final t in targets) List.of(t)],
        x: x,
        kicked: kicked,
        event: event,
        sourceName: sourceName,
        isCopy: isCopy,
        paidCost: Map.of(paidCost),
      )
        ..targetZcc = [for (final t in targetZcc) List.of(t)]
        ..sourceLki = sourceLki;

  String digest() => '$id|${kind.index}|$controller|$sourceId.$sourceZcc|${ability?.text.hashCode ?? 0}|$objId|${modes.join(',')}|${targets.map((t) => t.join(',')).join(';')}|${targetZcc.map((t) => t.join(',')).join(';')}|$x|$kicked|${event?.digest() ?? ''}|$isCopy';
}

/// What a trigger event was about, kept with the triggered ability (CR 603.10 look-back data).
class EventInfo {
  const EventInfo({this.obj, this.objZcc, this.player, this.amount = 0, this.objName = '', this.objPower = 0, this.objTypes = const {}, this.objSubtypes = const [], this.objCounters = const {}, this.other});
  final ObjId? obj;
  final int? objZcc;
  final PlayerId? player;
  final int amount;
  final String objName;
  final int objPower;
  final Set<CardType> objTypes;
  final List<String> objSubtypes;
  final Map<String, int> objCounters;

  /// A second object (the spell cast, the damage source...).
  final ObjId? other;

  String digest() => '$obj.$objZcc|$player|$amount|$objName|$objPower|$other';
}

/// A triggered ability that triggered and waits to be put on the stack (CR 603.3).
class PendingTrigger {
  PendingTrigger({required this.controller, required this.sourceId, required this.sourceZcc, required this.ability, required this.event, required this.sourceName, this.delayed = false});
  final PlayerId controller;
  final ObjId sourceId;
  final int sourceZcc;
  final TriggeredAbility ability;
  final EventInfo event;
  final String sourceName;
  final bool delayed;

  String digest() => '$controller|$sourceId.$sourceZcc|${ability.text.hashCode}|${event.digest()}|$delayed';
}

/// A continuous effect from a resolved spell or ability (CR 611.2).
class ActiveEffect {
  ActiveEffect({required this.timestamp, required this.sourceId, required this.controller, required this.affected, required this.mods, required this.duration, required this.turn, this.affectsPlayersOf = false, this.rule, this.amounts = const {}});
  final int timestamp;
  final ObjId sourceId;
  final PlayerId controller;

  /// Locked set of affected objects as (id, zcc) pairs.
  final List<(ObjId, int)> affected;
  final List<Mod> mods;
  final EffectDuration duration;

  /// The turn it was created (for "until your next turn").
  final int turn;
  final bool affectsPlayersOf;
  final RuleMod? rule;

  /// Amounts locked in at resolution (CR 608.2h), by mod index.
  final Map<int, (int, int)> amounts;

  String digest() => '$timestamp|$sourceId|$controller|${affected.map((a) => '${a.$1}.${a.$2}').join(',')}|${mods.length}|${mods.map((m) => m.runtimeType).join(',')}|${duration.index}|$turn|${rule?.runtimeType}|${amounts.entries.map((e) => '${e.key}:${e.value.$1}/${e.value.$2}').join(',')}';
}

/// A delayed triggered ability created by a resolving effect (CR 603.7).
class DelayedTrigger {
  DelayedTrigger({required this.controller, required this.sourceId, required this.ability, required this.objects, required this.createdTurn, this.oneShot = true});
  final PlayerId controller;
  final ObjId sourceId;
  final TriggeredAbility ability;

  /// Objects the effect refers to ("return that card"), as (id, zcc).
  final List<(ObjId, int)> objects;
  final int createdTurn;
  final bool oneShot;

  String digest() => '$controller|$sourceId|${ability.text.hashCode}|${objects.map((o) => '${o.$1}.${o.$2}').join(',')}|$createdTurn|$oneShot';
}

/// A one-turn shield (immutable; using part of it replaces the entry): a regeneration shield on
/// an object (CR 701.15), or a prevention shield (CR 615.7) for an entity (a player or an
/// object), for everything ([entity] null), or against damage dealt by an object ([by]).
class Shield {
  const Shield.regen(int obj, this.zcc)
      : regen = true,
        entity = obj,
        amount = 1,
        by = false,
        combatOnly = false;
  const Shield.prevent(this.entity, this.zcc, this.amount, {this.by = false, this.combatOnly = false}) : regen = false;
  final bool regen;
  final int? entity;

  /// The object's zone-change count when the shield was made (0 for players and everything).
  final int zcc;

  /// Damage still to prevent; -1 for all of it.
  final int amount;
  final bool by, combatOnly;

  Shield withAmount(int n) => Shield.prevent(entity, zcc, n, by: by, combatOnly: combatOnly);

  String digest() => '${regen ? 'R' : 'P'}|$entity.$zcc|$amount|$by|$combatOnly';
}

class EmblemObj {
  EmblemObj(this.owner, this.abilities, this.text, this.id);
  final PlayerId owner;
  final List<Ability> abilities;
  final String text;
  final int id;
  String digest() => '$owner|$id|${text.hashCode}';
}

enum DecisionKind {
  /// Choose targets: [Decision.options] are entities.
  targets,

  /// Choose modes (indices).
  modes,

  /// Choose a number in [min, max] (X, how many).
  number,

  /// Choose objects from [options] (discard, sacrifice, search, cards to keep...).
  cards,

  /// Put [options] in an order (answer: a permutation of them).
  order,

  /// Yes (1) or no (0).
  yesNo,

  /// Pay a mana cost: answer [] for automatic payment, or triples (source, ability index,
  /// mana type index).
  payMana,

  /// Declare attackers: answer pairs (attacker, attacked entity).
  attackers,

  /// Declare blockers: answer pairs (blocker, attacker).
  blockers,

  /// Assign combat damage: answer pairs (recipient entity, amount).
  damage,

  /// Pick one of [Decision.labels] (index).
  option,

  /// Keep (1) or mulligan (0) the opening hand.
  mulligan,

  /// Split a pile / divide damage: answer pairs (entity, amount).
  divide,
}

class Decision {
  const Decision({
    required this.kind,
    required this.player,
    required this.prompt,
    this.options = const [],
    this.min = 0,
    this.max = 1,
    this.labels = const [],
    this.source,
    this.extra = const {},
    this.cancellable = false,
  });
  final DecisionKind kind;
  final PlayerId player;
  final String prompt;
  final List<int> options;
  final int min, max;
  final List<String> labels;

  /// The object the decision is about (the spell being cast, the triggered ability's source).
  final ObjId? source;

  /// Per-kind data: for attackers {attacker: [entities]}, for blockers {blocker: [attackers]},
  /// for damage the amount to assign, for payMana the cost text.
  final Map<String, Object> extra;

  /// Whether the player may back out (casting and activating, CR 601.2 rewinds).
  final bool cancellable;

  String digest() => '${kind.index}|$player|$prompt|${options.join(',')}|$min|$max|${labels.join(';')}|$source|$cancellable';
}

/// A unit of engine work that may stop for decisions: re-run from the snapshot with [answers].
sealed class Task {
  const Task();
  String digest();
}

class CastTask extends Task {
  const CastTask(this.player, this.obj, {this.face = 0, this.option = -1});
  final PlayerId player;
  final ObjId obj;
  final int face;

  /// Index of a cast option (kicker / alternative / flashback) chosen up front, or -1.
  final int option;
  @override
  String digest() => 'cast$player.$obj.$face.$option';
}

class ActivateTask extends Task {
  const ActivateTask(this.player, this.obj, this.ability);
  final PlayerId player;
  final ObjId obj;
  final int ability;
  @override
  String digest() => 'act$player.$obj.$ability';
}

class ResolveTask extends Task {
  const ResolveTask();
  @override
  String digest() => 'resolve';
}

class TriggersTask extends Task {
  const TriggersTask();
  @override
  String digest() => 'triggers';
}

class AttackTask extends Task {
  const AttackTask();
  @override
  String digest() => 'attack';
}

class BlockTask extends Task {
  const BlockTask(this.defender);
  final PlayerId defender;
  @override
  String digest() => 'block$defender';
}

class DamageTask extends Task {
  const DamageTask(this.firstStrike);
  final bool firstStrike;
  @override
  String digest() => 'damage$firstStrike';
}

class CleanupTask extends Task {
  const CleanupTask();
  @override
  String digest() => 'cleanup';
}

class MulliganTask extends Task {
  const MulliganTask();
  @override
  String digest() => 'mulligan';
}

class StepTask extends Task {
  const StepTask();
  @override
  String digest() => 'step';
}

class SbaTask extends Task {
  const SbaTask();
  @override
  String digest() => 'sba';
}

class Pending {
  Pending(this.task, this.answers, this.decision, this.snapshot);
  final Task task;
  final List<List<int>> answers;
  final Decision decision;

  /// The state before the task began: answering re-runs the task from here. The live state shows
  /// the task as far as it got, so the player sees what they're deciding about.
  final GameState snapshot;
  String digest() => '${task.digest()}|${answers.map((a) => a.join(',')).join(';')}|${decision.digest()}';
}

/// A line in the game log, for the table's history and the UI's animations.
class LogEntry {
  const LogEntry(this.text, {this.player, this.obj, this.kind = 'info'});
  final String text;
  final PlayerId? player;
  final ObjId? obj;
  final String kind;
}

class GameState {
  GameState({required this.seed, required List<String> names, this.rules = const RulesOptions()}) : rng = SeededRng(seed) {
    for (var i = 0; i < names.length; i++) {
      players.add(Player(i, names[i]));
    }
  }

  GameState._raw(this.seed, this.rng, this.rules);

  final int seed;
  SeededRng rng;
  RulesOptions rules;
  final List<Player> players = [];
  final Map<ObjId, GameObject> objects = {};

  /// Permanents in the order they entered (timestamp order).
  List<ObjId> battlefield = [];
  List<StackItem> stack = []; // last is the top
  List<ObjId> command = [];
  int nextId = 1;
  int nextTimestamp = 1;

  int turn = 0;
  PlayerId active = 0;
  PlayerId firstPlayer = 0;

  /// The current step's turn-based actions are done.
  bool stepDone = false;

  /// Players get priority in this cleanup step (CR 514.3a).
  bool cleanupPriority = false;
  TurnStep step = TurnStep.untap;
  PlayerId? priority;

  /// Players who passed in succession since the last action (CR 117.4).
  int passes = 0;
  bool started = false;

  /// Mulligans are done and turn 1 has begun.
  bool inProgress = false;
  bool combatHasFirstStrike = false;
  List<PendingTrigger> pendingTriggers = [];
  List<ActiveEffect> effects = [];
  List<DelayedTrigger> delayed = [];
  List<EmblemObj> emblems = [];

  /// Regeneration and prevention shields; they all end at cleanup.
  List<Shield> shields = [];
  Pending? pending;
  bool over = false;
  PlayerId? winner;
  int creaturesDiedThisTurn = 0;

  /// Extra turns queued (player ids), taken next first-in-last-out (CR 500.7).
  List<PlayerId> extraTurns = [];

  /// The game log (not part of the digest).
  List<LogEntry> log = [];

  /// Bumped on every mutation the layer cache depends on.
  int version = 0;

  Player player(PlayerId p) => players[p];
  GameObject obj(ObjId id) => objects[id]!;
  GameObject? objOrNull(ObjId? id) => id == null ? null : objects[id];

  Iterable<PlayerId> get playerIds => Iterable.generate(players.length);

  /// Players still in the game, in turn order starting with [from] (APNAP order, CR 101.4).
  List<PlayerId> apnap([PlayerId? from]) {
    final start = from ?? active;
    final out = <PlayerId>[];
    for (var i = 0; i < players.length; i++) {
      final p = (start + i) % players.length;
      if (!players[p].lost) out.add(p);
    }
    return out;
  }

  List<PlayerId> opponents(PlayerId p) => [for (final q in apnap(p)) if (q != p) q];

  GameState clone() {
    final s = GameState._raw(seed, rng.clone(), rules);
    for (final p in players) {
      s.players.add(p.clone());
    }
    for (final e in objects.entries) {
      s.objects[e.key] = e.value.clone();
    }
    s.battlefield = List.of(battlefield);
    s.stack = [for (final i in stack) i.clone()];
    s.command = List.of(command);
    s.nextId = nextId;
    s.nextTimestamp = nextTimestamp;
    s.turn = turn;
    s.active = active;
    s.firstPlayer = firstPlayer;
    s.stepDone = stepDone;
    s.cleanupPriority = cleanupPriority;
    s.step = step;
    s.priority = priority;
    s.passes = passes;
    s.started = started;
    s.inProgress = inProgress;
    s.combatHasFirstStrike = combatHasFirstStrike;
    s.pendingTriggers = List.of(pendingTriggers);
    s.effects = List.of(effects);
    s.delayed = List.of(delayed);
    s.emblems = List.of(emblems);
    s.shields = List.of(shields);
    s.pending = pending;
    s.over = over;
    s.winner = winner;
    s.creaturesDiedThisTurn = creaturesDiedThisTurn;
    s.extraTurns = List.of(extraTurns);
    s.log = List.of(log);
    s.version = version + 1;
    return s;
  }

  /// Canonical text of everything that matters for the rules. Equal on every device for the same
  /// seed and actions.
  String digest() {
    final b = StringBuffer()
      ..write('v1|$seed|${rng.state}|${rules.digest()}|$turn|$active|$firstPlayer|$stepDone|$cleanupPriority|${step.index}|$priority|$passes|$started|$inProgress|$combatHasFirstStrike|$over|$winner|$creaturesDiedThisTurn|$nextId|$nextTimestamp|${extraTurns.join(',')}\n');
    for (final p in players) {
      b.writeln(p.digest());
    }
    b.writeln('bf:${battlefield.join(',')}');
    b.writeln('cmd:${command.join(',')}');
    for (final i in stack) {
      b.writeln('st:${i.digest()}');
    }
    final ids = objects.keys.toList()..sort();
    for (final id in ids) {
      b.writeln(objects[id]!.digest());
    }
    for (final t in pendingTriggers) {
      b.writeln('pt:${t.digest()}');
    }
    for (final e in effects) {
      b.writeln('ef:${e.digest()}');
    }
    for (final d in delayed) {
      b.writeln('dl:${d.digest()}');
    }
    for (final e in emblems) {
      b.writeln('em:${e.digest()}');
    }
    for (final s in shields) {
      b.writeln('sh:${s.digest()}');
    }
    if (pending != null) b.writeln('pd:${pending!.digest()}');
    return b.toString();
  }
}

/// A thrown error for illegal actions and answers (from a bug or a misbehaving peer).
class GameError implements Exception {
  GameError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thrown inside a task when it needs a decision it doesn't have an answer for yet.
class NeedDecision implements Exception {
  NeedDecision(this.decision);
  final Decision decision;
}

extension RngClone on SeededRng {
  SeededRng clone() => SeededRng.fromState(state);
}
