import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rules/rules.dart';
import 'package:share_plus/share_plus.dart';

import '../app/sound.dart';
import '../app/store.dart';
import '../net/ble.dart';
import '../net/lan.dart';
import '../net/protocol.dart';
import '../net/relay.dart';
import '../net/transport.dart';
import '../theme/theme.dart';

/// Color pips for a deck's colors.
String deckColors(Deck d, CardDatabase db) {
  final cs = <ManaColor>{};
  for (final n in d.cards) {
    cs.addAll(db[n]?.colorIdentity ?? const []);
  }
  final order = ManaColor.values.where(cs.contains);
  return order.map((c) => '{${c.symbol}}').join();
}

/// A row of deck choices.
class DeckPicker extends StatelessWidget {
  const DeckPicker({super.key, required this.selected, required this.onSelect});
  final Deck? selected;
  final void Function(Deck) onSelect;
  @override
  Widget build(BuildContext context) {
    final store = AppStore.shared;
    final t = GameTheme.of(context);
    final decks = store.playableDecks;
    return SizedBox(
      height: 74,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final d in decks)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 160,
              child: InkWell(
                onTap: () {
                  Console.shared.play(Fx.tap);
                  onSelect(d);
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: selected?.id == d.id ? t.accent.withValues(alpha: 0.22) : t.panel,
                    borderRadius: BorderRadius.circular(t.radius),
                    border: Border.all(color: selected?.id == d.id ? t.accent : t.muted.withValues(alpha: 0.4), width: selected?.id == d.id ? 3 : 1),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(d.name, style: t.style(14, weight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(children: [ManaPips(deckColors(d, store.db), size: 14), const Spacer(), Text('${d.cards.length}', style: t.small)]),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Pick decks for a game against the computer or on one device.
class NewGameScreen extends StatefulWidget {
  const NewGameScreen({super.key, required this.hotseat});
  final bool hotseat;
  @override
  State<NewGameScreen> createState() => _NewGameScreenState();
}

class _NewGameScreenState extends State<NewGameScreen> {
  Deck? deck, opponentDeck;

  @override
  void initState() {
    super.initState();
    final decks = AppStore.shared.playableDecks;
    deck = decks.isNotEmpty ? decks.first : null;
    opponentDeck = decks.length > 1 ? decks[decks.length ~/ 2] : deck;
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.shared;
    final t = GameTheme.of(context);
    return ThemedScreen(
      title: widget.hotseat ? 'Two players, one device' : 'Play the computer',
      subtitle: 'Choose decks',
      child: ListView(children: [
        if (store.savedGame != null)
          ThemedPanel(
            title: 'Saved game',
            color: t.highlight,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('A game is in progress on this device. Starting a new one replaces it.', style: t.body),
              const SizedBox(height: 8),
              ThemedButton('Resume it', icon: Icons.play_arrow, onPressed: () {
                if (store.resumeLocalGame() != null) Navigator.pushReplacementNamed(context, '/game');
              }),
            ]),
          ),
        const SizedBox(height: 8),
        ThemedHeader(widget.hotseat ? 'Player 1' : 'Your deck'),
        DeckPicker(selected: deck, onSelect: (d) => setState(() => deck = d)),
        const SizedBox(height: 8),
        ThemedHeader(widget.hotseat ? 'Player 2' : "The computer's deck", color: t.accent2),
        DeckPicker(selected: opponentDeck, onSelect: (d) => setState(() => opponentDeck = d)),
        const SizedBox(height: 16),
        ThemedButton('Start the game', tall: true, icon: Icons.play_arrow, onPressed: deck == null || opponentDeck == null
            ? null
            : () {
                Console.shared.play(Fx.confirm);
                store.startLocalGame(deck: deck!, opponentDeck: opponentDeck!, hotseat: widget.hotseat);
                Navigator.pushReplacementNamed(context, '/game');
              }),
        const SizedBox(height: 8),
        Text('Rules: ${store.rules.summary} (Settings → Rules).', style: t.small),
      ]),
    );
  }
}

/// Nearby play on phones: host over Wi‑Fi or Bluetooth, or find a host and join.
class LocalLobbyScreen extends StatefulWidget {
  const LocalLobbyScreen({super.key});
  @override
  State<LocalLobbyScreen> createState() => _LocalLobbyScreenState();
}

class _LocalLobbyScreenState extends State<LocalLobbyScreen> {
  Deck? deck;
  LinkKind kind = LinkKind.lan;
  HostLink? host;
  GuestLink? guest;
  List<PeerInfo> peers = [];
  String status = '';
  bool hosting = false, scanning = false, busy = false;
  final List<StreamSubscription<dynamic>> _subs = [];
  final addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    deck = AppStore.shared.playableDecks.firstOrNull;
  }

  @override
  void dispose() {
    _stopAll();
    addressController.dispose();
    super.dispose();
  }

  Future<void> _stopAll() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await host?.stop();
    await guest?.stopScan();
    host = null;
    guest = null;
  }

  Future<void> startHosting() async {
    await _stopAll();
    final store = AppStore.shared;
    final h = kind == LinkKind.lan ? LanHost() : BleHost();
    setState(() {
      hosting = true;
      scanning = false;
      status = 'Starting…';
    });
    try {
      await h.start(name: store.playerName, id: store.deviceId);
      host = h;
      _subs.add(h.connections.listen(_onConnected));
      if (h is LanHost) {
        final addresses = await localAddresses();
        final where = addresses.map((a) => h.port == lanGamePort ? a : '$a:${h.port}').join(' or ');
        setState(() => status = 'Hosting on Wi‑Fi as ${store.playerName}. Waiting for a player…${where.isEmpty ? '' : '\nThey can also join by typing: $where'}');
      } else {
        setState(() => status = 'Hosting over Bluetooth as ${store.playerName}. Waiting for a player…');
      }
    } catch (e) {
      setState(() {
        hosting = false;
        status = 'Could not host: $e';
      });
    }
  }

  Future<void> startScanning() async {
    await _stopAll();
    final g = kind == LinkKind.lan ? LanGuest() : BleGuest();
    setState(() {
      scanning = true;
      hosting = false;
      peers = [];
      status = 'Looking for hosts…';
    });
    try {
      await g.startScan();
      guest = g;
      _subs.add(g.peers.listen((p) => setState(() => peers = p)));
    } catch (e) {
      setState(() {
        scanning = false;
        status = 'Could not scan: $e';
      });
    }
  }

  Future<void> join(PeerInfo peer) async {
    final g = guest;
    if (g == null || busy) return;
    setState(() {
      busy = true;
      status = 'Connecting to ${peer.name}…';
    });
    try {
      final t = await g.connect(peer);
      await g.stopScan();
      _begin(t, isHost: false);
    } catch (e) {
      setState(() {
        busy = false;
        status = 'Could not connect: $e';
      });
    }
  }

  Future<void> joinAddress() async {
    final text = addressController.text.trim();
    final parts = text.contains(':') ? text.split(':') : [text, '$lanGamePort'];
    if (parts.length != 2 || parts[0].isEmpty || int.tryParse(parts[1]) == null) {
      setState(() => status = "Type the host's IP address, e.g. 192.168.1.20 (or 192.168.1.20:$lanGamePort)");
      return;
    }
    setState(() {
      busy = true;
      status = 'Connecting to $text…';
    });
    try {
      final t = await LanGuest().connectTo(parts[0], int.parse(parts[1]));
      _begin(t, isHost: false);
    } catch (e) {
      setState(() {
        busy = false;
        status = 'Could not connect: $e';
      });
    }
  }

  void _onConnected(Transport t) {
    setState(() => status = 'A player connected. Linking…');
    _begin(t, isHost: true);
  }

  void _begin(Transport t, {required bool isHost}) {
    final store = AppStore.shared;
    final d = deck;
    if (d == null) return;
    final match = LockstepMatch(transport: t, db: store.db, localName: store.playerName, localId: store.deviceId, localDeck: d.cards, isHost: isHost, rules: store.rules, archive: store);
    late StreamSubscription<String> sub;
    void go() {
      sub.cancel();
      _subs.remove(sub);
      host?.stop();
      host = null;
      store.startLinkedGame(match);
      Console.shared.play(Fx.confirm);
      if (mounted) Navigator.pushReplacementNamed(context, '/game');
    }

    sub = match.events.listen((e) {
      if (e == 'start' || (e == 'hello' && match.game != null)) {
        if (match.game != null) go();
      } else if (e == 'error') {
        setState(() {
          busy = false;
          status = match.error ?? 'Link failed';
        });
      }
    });
    _subs.add(sub);
    match.begin();
    Timer(const Duration(milliseconds: 300), () {
      if (match.game != null && mounted && store.session?.match != match) go();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    return ThemedScreen(
      title: 'Nearby',
      subtitle: 'Wi‑Fi or Bluetooth, no server',
      child: ListView(children: [
        Text('Both devices on the same Wi‑Fi, or Bluetooth with no network at all. One player hosts, the other joins.', style: t.body),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: ThemedButton('Wi‑Fi', icon: Icons.wifi, outlined: kind != LinkKind.lan, onPressed: () => setState(() => kind = LinkKind.lan))),
          const SizedBox(width: 8),
          Expanded(child: ThemedButton('Bluetooth', icon: Icons.bluetooth, outlined: kind != LinkKind.bluetooth, onPressed: () => setState(() => kind = LinkKind.bluetooth))),
        ]),
        const ThemedHeader('Your deck'),
        DeckPicker(selected: deck, onSelect: (d) => setState(() => deck = d)),
        const SizedBox(height: 8),
        ThemedButton(hosting ? 'Hosting… (tap to stop)' : 'Host a game', tall: true, icon: Icons.cell_tower, onPressed: deck == null
            ? null
            : () async {
                if (hosting) {
                  await _stopAll();
                  setState(() {
                    hosting = false;
                    status = '';
                  });
                } else {
                  startHosting();
                }
              }),
        const SizedBox(height: 8),
        ThemedButton(scanning ? 'Searching… (tap to stop)' : 'Find hosts nearby', tall: true, icon: Icons.search, color: t.accent2, onPressed: deck == null
            ? null
            : () async {
                if (scanning) {
                  await _stopAll();
                  setState(() {
                    scanning = false;
                    status = '';
                  });
                } else {
                  startScanning();
                }
              }),
        for (final p in peers) Padding(padding: const EdgeInsets.only(top: 6), child: ThemedButton('${p.name} · ${p.kind == LinkKind.lan ? p.address : 'Bluetooth'}', icon: Icons.login, onPressed: busy ? null : () => join(p))),
        if (kind == LinkKind.lan) ...[
          const ThemedHeader('Join by IP address'),
          Text("If the host doesn't show up above, type the address shown on their screen.", style: t.small),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: addressController,
                style: t.body,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(filled: true, fillColor: t.panel, border: const OutlineInputBorder(), hintText: '192.168.1.20'),
                onSubmitted: (_) => busy || deck == null ? null : joinAddress(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 100, child: ThemedButton('Join', onPressed: busy || deck == null ? null : joinAddress)),
          ]),
        ],
        if (status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(status, style: t.style(14, color: t.highlight))),
      ]),
    );
  }
}

/// Remote play through public relays: share a code, no account, no server of ours.
class RemoteLobbyScreen extends StatefulWidget {
  const RemoteLobbyScreen({super.key});
  @override
  State<RemoteLobbyScreen> createState() => _RemoteLobbyScreenState();
}

class _RemoteLobbyScreenState extends State<RemoteLobbyScreen> {
  Deck? deck;
  final codeController = TextEditingController();
  String status = '';
  String? hostedCode;
  RelayTransport? transport;
  LockstepMatch? match;
  StreamSubscription<String>? sub;
  StreamSubscription<Map<String, bool>>? relaySub;
  int relaysUp = 0;

  @override
  void initState() {
    super.initState();
    deck = AppStore.shared.playableDecks.firstOrNull;
  }

  @override
  void dispose() {
    sub?.cancel();
    relaySub?.cancel();
    if (AppStore.shared.session?.match != match) match?.dispose();
    codeController.dispose();
    super.dispose();
  }

  Future<void> forget(String code) async {
    if (transport?.code == code && AppStore.shared.session?.match != match) {
      await sub?.cancel();
      await relaySub?.cancel();
      sub = null;
      relaySub = null;
      await match?.dispose();
      match = null;
      transport = null;
      hostedCode = null;
      relaysUp = 0;
      status = '';
    }
    await AppStore.shared.forgetRemoteMatch(code);
    if (mounted) setState(() {});
  }

  Future<void> open(String code, {required bool isHost}) async {
    final store = AppStore.shared;
    final d = deck;
    if (d == null || code.length < 4) return;
    // Online games use only fully supported cards.
    final problems = validateDeck(store.db, d.cards, DeckFormat.casual, requireSupported: true);
    if (problems.isNotEmpty) {
      setState(() => status = problems.first.message);
      return;
    }
    await sub?.cancel();
    if (store.session?.match != match) await match?.dispose();
    final t = RelayTransport(code: code, secretKey: store.relayIdentity, relays: store.relays);
    transport = t;
    await relaySub?.cancel();
    relaySub = t.relayStatus.listen((m) => setState(() => relaysUp = m.values.where((v) => v).length));
    final m = LockstepMatch(transport: t, db: store.db, localName: store.playerName, localId: store.deviceId, localDeck: d.cards, isHost: isHost, rules: store.rules, matchKey: 'relay:$code', archive: store);
    match = m;
    setState(() {
      hostedCode = isHost ? code : null;
      status = isHost ? 'Share the code. The game starts when your opponent joins.' : 'Joining $code…';
    });
    store.rememberRemoteMatch(code: code, host: isHost);
    sub = m.events.listen((e) {
      if ((e == 'start' || e == 'hello' || e == 'action') && m.game != null) {
        if (store.session?.match == m) return;
        store.rememberRemoteMatch(code: code, host: isHost, opponent: m.remoteName);
        store.startLinkedGame(m);
        Console.shared.play(Fx.confirm);
        if (mounted) Navigator.pushReplacementNamed(context, '/game');
      } else if (e == 'error') {
        setState(() => status = m.error ?? 'Link failed');
      } else if (e == 'hello') {
        setState(() => status = 'Linked with ${m.remoteName}…');
      }
    });
    m.begin();
    if (m.game != null) {
      store.startLinkedGame(m);
      Console.shared.play(Fx.confirm);
      if (mounted) Navigator.pushReplacementNamed(context, '/game');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.shared;
    final t = GameTheme.of(context);
    return ThemedScreen(
      title: 'Play online',
      subtitle: 'With a match code',
      child: ListView(children: [
        Text('Play someone anywhere: in a browser or on a phone. Moves travel encrypted through public relays, so nobody runs a server and a match can continue days later.', style: t.body),
        const ThemedHeader('Your deck'),
        DeckPicker(selected: deck, onSelect: (d) => setState(() => deck = d)),
        const SizedBox(height: 8),
        ThemedButton('Create a match code', tall: true, icon: Icons.add, onPressed: deck == null ? null : () => open(newMatchCode(), isHost: true)),
        if (hostedCode != null) ...[
          const SizedBox(height: 8),
          ThemedPanel(
            title: 'Match code',
            color: t.highlight,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SelectableText(hostedCode!, style: t.style(40, weight: FontWeight.w900, color: t.accent), textAlign: TextAlign.center),
              Row(children: [
                if (!kIsWeb) Expanded(child: ThemedButton('Share', icon: Icons.share, onPressed: () => SharePlus.instance.share(ShareParams(text: 'Join my OpenMTG game with the code $hostedCode')))),
                if (!kIsWeb) const SizedBox(width: 8),
                Expanded(child: ThemedButton('Copy', icon: Icons.copy, outlined: true, onPressed: () => Clipboard.setData(ClipboardData(text: hostedCode!)))),
              ]),
            ]),
          ),
        ],
        const ThemedHeader('Join a match'),
        Row(children: [
          Expanded(
            child: TextField(
              controller: codeController,
              style: t.style(22, weight: FontWeight.w800),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(isDense: true, filled: true, fillColor: t.panel, border: const OutlineInputBorder(), hintText: 'CODE'),
              onSubmitted: (_) => deck == null ? null : open(codeController.text.trim().toUpperCase(), isHost: false),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 100, child: ThemedButton('Join', onPressed: deck == null ? null : () => open(codeController.text.trim().toUpperCase(), isHost: false))),
        ]),
        if (store.remoteMatches.isNotEmpty) const ThemedHeader('Your matches'),
        for (final m in store.remoteMatches)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(child: ThemedButton('${m['code']} · ${m['host'] == true ? 'hosted' : 'joined'}${m['opponent'] != null ? ' · vs ${m['opponent']}' : ''}', outlined: true, onPressed: deck == null ? null : () => open(m['code'] as String, isHost: m['host'] as bool))),
              IconButton(icon: Icon(Icons.close, color: t.muted), tooltip: 'Remove this match', onPressed: () => forget(m['code'] as String)),
            ]),
          ),
        if (status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('$status${transport != null ? '  ($relaysUp relays connected)' : ''}', style: t.style(14, color: t.highlight))),
      ]),
    );
  }
}
