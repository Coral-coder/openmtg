import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:rules/rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tcg_app/tcg_app.dart';
import 'card_data.dart';
import 'session.dart';

class Deck {
  Deck({required this.id, required this.name, required this.cards, this.format = DeckFormat.casual, this.starter = false, this.commander});
  final String id;
  String name;
  List<String> cards;
  DeckFormat format;
  bool starter;
  String? commander;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'cards': cards, 'format': format.name, 'starter': starter, if (commander != null) 'commander': commander};

  static Deck fromJson(Map<String, dynamic> j) => Deck(
        id: j['id'] as String,
        name: j['name'] as String,
        cards: (j['cards'] as List).cast<String>(),
        format: DeckFormat.values.where((f) => f.name == j['format']).firstOrNull ?? DeckFormat.casual,
        starter: j['starter'] as bool? ?? false,
        commander: j['commander'] as String?,
      );

  Deck copy({String? name}) => Deck(id: newId(), name: name ?? this.name, cards: List.of(cards), format: format, commander: commander);

  static String newId() => newMatchCode(12);

  /// The most common set among the deck's cards (it picks the theme).
  List<String> sets(CardDatabase db) => [for (final n in cards) ?db[n]?.imageSet];
}

/// App-wide state: settings, decks, the saved local game, the current session.
class AppStore extends ChangeNotifier implements MatchArchive {
  AppStore._();
  static final AppStore shared = AppStore._();

  final CardData data = CardData();
  CardDatabase get db => data.db;
  late SharedPreferences _prefs;
  List<Deck> decks = [];
  Map<String, dynamic>? savedGame;
  GameSession? session;
  String playerName = 'Planeswalker';
  bool soundOn = true, hapticsOn = true;

  /// Tapping a card opens it large with what it can do; off, a tap acts at once.
  bool tapToInspect = true;

  /// A line on the table saying what you can do now.
  bool coachOn = true;

  /// Lands on the table as cards (true) or grouped into labels by name.
  bool landsAsCards = false;

  /// Pay mana automatically (off: choose the lands to tap).
  bool autoPay = true;

  /// Cards fly, numbers float and banners sweep across the table (off: changes show at once).
  bool animations = true;

  /// The table tour has been shown or skipped.
  bool tourSeen = false;

  /// A forced theme id, or null to pick from the deck's set.
  String? themeOverride;
  int botDelay = 450;
  RulesOptions rules = RulesOptions.standard;
  String deviceId = '';
  String relayIdentity = '';
  List<String> relays = List.of(defaultRelays);
  List<Map<String, dynamic>> remoteMatches = [];
  bool ready = false;

  /// The theme currently shown (forced, or picked from the current game's decks).
  GameTheme theme = Themes.classic;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await data.loadBundled(rootBundle);
    unawaited(data.checkForUpdate(_prefs));
    playerName = _prefs.getString('playerName') ?? 'Planeswalker';
    soundOn = _prefs.getBool('soundOn') ?? true;
    hapticsOn = _prefs.getBool('hapticsOn') ?? true;
    tapToInspect = _prefs.getBool('tapToInspect') ?? true;
    coachOn = _prefs.getBool('coachOn') ?? true;
    landsAsCards = _prefs.getBool('landsAsCards') ?? false;
    autoPay = _prefs.getBool('autoPay') ?? true;
    tourSeen = _prefs.getBool('tourSeen') ?? false;
    animations = _prefs.getBool('animations') ?? true;
    themeOverride = _prefs.getString('theme');
    botDelay = _prefs.getInt('botDelay') ?? 450;
    final rulesJson = _prefs.getString('rules');
    if (rulesJson != null) {
      try {
        rules = RulesOptions.fromJson(jsonDecode(rulesJson) as Map<String, dynamic>);
      } catch (_) {}
    }
    deviceId = _prefs.getString('deviceId') ?? '';
    if (deviceId.isEmpty) {
      deviceId = newMatchCode(10);
      await _prefs.setString('deviceId', deviceId);
    }
    relayIdentity = _prefs.getString('relayIdentity') ?? '';
    if (relayIdentity.isEmpty) {
      relayIdentity = newRelayIdentity();
      await _prefs.setString('relayIdentity', relayIdentity);
    }
    relays = _prefs.getStringList('relays') ?? List.of(defaultRelays);
    final deckJson = _prefs.getString('decks');
    if (deckJson != null) {
      try {
        decks = [for (final e in jsonDecode(deckJson) as List) Deck.fromJson(e as Map<String, dynamic>)];
      } catch (_) {}
    }
    if (!decks.any((d) => d.starter)) {
      decks.insertAll(0, starterDecks());
      await _persistDecks();
    }
    final saved = _prefs.getString('savedGame');
    if (saved != null) {
      try {
        savedGame = jsonDecode(saved) as Map<String, dynamic>;
      } catch (_) {}
    }
    final rm = _prefs.getString('remoteMatches');
    if (rm != null) {
      try {
        remoteMatches = (jsonDecode(rm) as List).cast<Map<String, dynamic>>();
      } catch (_) {}
    }
    theme = Themes.byId(themeOverride);
    Console.shared.soundOn = soundOn;
    Console.shared.hapticsOn = hapticsOn;
    Console.shared.setStyle(theme.sound);
    await Console.shared.init();
    await Notifications.shared.init();
    ready = true;
    notifyListeners();
  }

  /// One starter deck per two-color pair, from the fully supported cards of the bundled pool.
  List<Deck> starterDecks() => [
        for (final e in colorPairs.entries) Deck(id: 'starter-${e.key.split(' ').first.toLowerCase()}', name: e.key, cards: starterDeck(db, e.value, set: data.poolSet), starter: true, format: DeckFormat.limited),
      ];

  // ---- Settings -------------------------------------------------------------------------------

  Future<void> setPlayerName(String n) async {
    playerName = n.trim().isEmpty ? 'Planeswalker' : n.trim();
    await _prefs.setString('playerName', playerName);
    notifyListeners();
  }

  Future<void> setBool(String key, bool v) async {
    switch (key) {
      case 'soundOn':
        soundOn = v;
        Console.shared.soundOn = v;
      case 'hapticsOn':
        hapticsOn = v;
        Console.shared.hapticsOn = v;
      case 'tapToInspect':
        tapToInspect = v;
      case 'coachOn':
        coachOn = v;
      case 'landsAsCards':
        landsAsCards = v;
      case 'autoPay':
        autoPay = v;
      case 'tourSeen':
        tourSeen = v;
      case 'animations':
        animations = v;
    }
    await _prefs.setBool(key, v);
    notifyListeners();
  }

  /// Redraws listeners after a setting kept elsewhere changed (the updater's).
  void refresh() => notifyListeners();

  Future<void> setBotDelay(int ms) async {
    botDelay = ms;
    session?.botDelay = ms;
    await _prefs.setInt('botDelay', ms);
    notifyListeners();
  }

  Future<void> setThemeOverride(String? id) async {
    themeOverride = id;
    if (id == null) {
      await _prefs.remove('theme');
    } else {
      await _prefs.setString('theme', id);
    }
    applyTheme(id == null ? (session == null ? Themes.classic : themeForGame(session!)) : Themes.byId(id));
  }

  /// Shows [t] (unless the player forced a theme in Settings).
  void applyTheme(GameTheme t) {
    final next = themeOverride != null ? Themes.byId(themeOverride) : t;
    if (next.id == theme.id) return;
    theme = next;
    Console.shared.setStyle(theme.sound);
    notifyListeners();
  }

  /// The local player's deck picks the theme.
  GameTheme themeForGame(GameSession s) {
    final deck = s.decks.isNotEmpty ? s.decks[s.localSeat.clamp(0, s.decks.length - 1)] : <String>[];
    return Themes.forSets([for (final n in deck) if (!(db[n]?.isBasicLand ?? true)) ?db[n]?.imageSet]);
  }

  Future<void> setRules(RulesOptions r) async {
    rules = r;
    await _prefs.setString('rules', jsonEncode(r.toJson()));
    notifyListeners();
  }

  Future<void> setRelays(List<String> list) async {
    relays = [for (final s in list) if (s.trim().isNotEmpty) s.trim()];
    if (relays.isEmpty) relays = List.of(defaultRelays);
    await _prefs.setStringList('relays', relays);
    notifyListeners();
  }

  // ---- Decks ----------------------------------------------------------------------------------

  Deck? deck(String id) => decks.where((d) => d.id == id).firstOrNull;

  /// Decks playable in a game: legal for their format, all cards known.
  List<Deck> get playableDecks => [for (final d in decks) if (d.cards.isNotEmpty && d.cards.every((n) => db[n] != null)) d];

  Future<void> saveDeck(Deck d) async {
    final i = decks.indexWhere((x) => x.id == d.id);
    if (i >= 0) {
      decks[i] = d;
    } else {
      decks.add(d);
    }
    await _persistDecks();
    notifyListeners();
  }

  Future<void> deleteDeck(Deck d) async {
    decks.removeWhere((x) => x.id == d.id);
    await _persistDecks();
    notifyListeners();
  }

  Future<void> restoreStarterDecks() async {
    decks.removeWhere((d) => d.starter);
    decks.insertAll(0, starterDecks());
    await _persistDecks();
    notifyListeners();
  }

  Future<void> _persistDecks() => _prefs.setString('decks', jsonEncode([for (final d in decks) d.toJson()]));

  // ---- Games ----------------------------------------------------------------------------------

  GameSession startLocalGame({required Deck deck, required Deck opponentDeck, required bool hotseat}) {
    final seed = Random().nextInt(1 << 31);
    final names = hotseat ? ['Player 1', 'Player 2'] : [playerName, 'Computer'];
    final s = GameSession.local(mode: hotseat ? SessionMode.hotseat : SessionMode.solo, playerNames: names, seed: seed, decks: [deck.cards, opponentDeck.cards], db: db, rules: rules);
    _attach(s);
    s.start();
    return s;
  }

  GameSession? resumeLocalGame() {
    final saved = savedGame;
    if (saved == null) return null;
    try {
      final mode = SessionMode.values.byName(saved['mode'] as String);
      final s = GameSession.local(mode: mode, playerNames: (saved['names'] as List).cast<String>(), seed: saved['seed'] as int, decks: [for (final d in saved['decks'] as List) (d as List).cast<String>()], db: db);
      _attach(s);
      s.replay([for (final a in saved['actions'] as List) GameAction.fromJson((a as Map).cast<String, dynamic>())]);
      return s;
    } catch (_) {
      clearSavedGame();
      return null;
    }
  }

  GameSession startLinkedGame(LockstepMatch match) {
    final s = GameSession.linked(match: match, db: db);
    _attach(s);
    return s;
  }

  void _attach(GameSession s) {
    session?.dispose();
    session = s;
    s.botDelay = botDelay;
    s.onSave = (map) {
      savedGame = map;
      _prefs.setString('savedGame', jsonEncode(map));
    };
    s.onFinished = () {
      if (s.mode != SessionMode.linked) clearSavedGame();
    };
    applyTheme(themeForGame(s));
    notifyListeners();
  }

  void endSession() {
    session?.dispose();
    session = null;
    applyTheme(Themes.classic);
    notifyListeners();
  }

  void clearSavedGame() {
    savedGame = null;
    _prefs.remove('savedGame');
    notifyListeners();
  }

  Future<void> rememberRemoteMatch({required String code, required bool host, String? opponent}) async {
    remoteMatches.removeWhere((m) => m['code'] == code);
    remoteMatches.insert(0, {'code': code, 'host': host, 'opponent': opponent, 'date': DateTime.now().toIso8601String()});
    if (remoteMatches.length > 20) remoteMatches = remoteMatches.sublist(0, 20);
    await _prefs.setString('remoteMatches', jsonEncode(remoteMatches));
    notifyListeners();
  }

  Future<void> forgetRemoteMatch(String code) async {
    final s = session, link = s?.match;
    if (s != null && link != null && link.transport is RelayTransport && (link.transport as RelayTransport).code == code) {
      session = null;
      s.dispose();
      unawaited(link.dispose());
    }
    remoteMatches.removeWhere((m) => m['code'] == code);
    await _prefs.setString('remoteMatches', jsonEncode(remoteMatches));
    await _prefs.remove('match:relay:$code');
    notifyListeners();
  }

  // Linked games' move logs, saved after every move (see LockstepMatch).

  @override
  Map<String, dynamic>? load(String key) {
    final raw = _prefs.getString('match:$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  void save(String key, Map<String, dynamic> log) {
    _prefs.setString('match:$key', jsonEncode(log));
    final keys = (_prefs.getStringList('matchLogs') ?? [])
      ..remove(key)
      ..insert(0, key);
    for (final old in keys.skip(30)) {
      _prefs.remove('match:$old');
    }
    _prefs.setStringList('matchLogs', keys.take(30).toList());
  }
}
