import 'package:flutter/material.dart';
import 'package:rules/rules.dart';

import '../app/store.dart';
import 'package:tcg_app/tcg_app.dart';
import 'card_detail.dart';
import 'card_view.dart';
import 'lobbies.dart';

class DeckListScreen extends StatelessWidget {
  const DeckListScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = AppStore.shared;
    final t = GameTheme.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => ThemedScreen(
        title: 'Decks',
        actions: [IconButton(icon: Icon(Icons.add, color: t.accent), tooltip: 'New deck', onPressed: () => _new(context))],
        child: ListView(children: [
          ThemedButton('New deck', icon: Icons.add, onPressed: () => _new(context)),
          const SizedBox(height: 10),
          for (final d in store.decks)
            Card(
              color: t.panel,
              child: ListTile(
                title: Text(d.name, style: t.style(15, weight: FontWeight.w700)),
                subtitle: Row(children: [
                  ManaPips(deckColors(d, store.db), size: 14),
                  const SizedBox(width: 8),
                  Text('${d.cards.length} cards · ${d.format.label}${d.starter ? ' · starter' : ''}', style: t.small),
                ]),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pushNamed(context, '/deck', arguments: d.id),
              ),
            ),
          const SizedBox(height: 10),
          TextButton(onPressed: store.restoreStarterDecks, child: const Text('Rebuild the starter decks')),
        ]),
      ),
    );
  }

  Future<void> _new(BuildContext context) async {
    final d = Deck(id: Deck.newId(), name: 'New deck', cards: [], format: DeckFormat.casual);
    await AppStore.shared.saveDeck(d);
    if (context.mounted) Navigator.pushNamed(context, '/deck', arguments: d.id);
  }
}

class DeckEditorScreen extends StatefulWidget {
  const DeckEditorScreen({super.key, required this.deckId});
  final String deckId;
  @override
  State<DeckEditorScreen> createState() => _DeckEditorScreenState();
}

class _DeckEditorScreenState extends State<DeckEditorScreen> {
  late Deck deck;
  String query = '';
  bool supportedOnly = true;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    final d = AppStore.shared.deck(widget.deckId);
    deck = d == null ? Deck(id: widget.deckId, name: 'Deck', cards: []) : Deck.fromJson(d.toJson());
  }

  void _save() {
    deck.starter = false;
    AppStore.shared.saveDeck(deck);
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.shared;
    final t = GameTheme.of(context);
    final db = store.db;
    final counts = <String, int>{};
    for (final n in deck.cards) {
      counts[n] = (counts[n] ?? 0) + 1;
    }
    final problems = validateDeck(db, deck.cards, deck.format, commander: deck.commander);
    final online = validateDeck(db, deck.cards, DeckFormat.casual, requireSupported: true).where((p) => p.message.contains('supported'));
    final q = query.toLowerCase();
    final results = q.length < 2
        ? <CardDef>[]
        : [
            for (final c in db.cards)
              if (c.name.toLowerCase().contains(q) || c.typeLine.toLowerCase().contains(q))
                if (!supportedOnly || OracleParser.parse(c).supported)
                  if (deck.format.format == null || c.legality(deck.format.format!) != Legality.notLegal) c,
          ].take(60).toList();
    final names = counts.keys.toList()..sort((a, b) => (db[a]?.manaValue ?? 0) - (db[b]?.manaValue ?? 0));
    return ThemedScreen(
      title: deck.name,
      subtitle: '${deck.cards.length} cards · ${deck.format.label}',
      actions: [
        IconButton(
          icon: Icon(Icons.delete_outline, color: t.danger),
          tooltip: 'Delete deck',
          onPressed: () async {
            await store.deleteDeck(deck);
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ],
      child: ListView(children: [
        Row(children: [
          Expanded(
            child: TextFormField(
              initialValue: deck.name,
              style: t.body,
              decoration: InputDecoration(labelText: 'Name', filled: true, fillColor: t.panel),
              onChanged: (v) {
                deck.name = v;
                _save();
              },
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<DeckFormat>(
            value: deck.format,
            items: [for (final f in DeckFormat.values) DropdownMenuItem(value: f, child: Text(f.label))],
            onChanged: (f) => setState(() {
              deck.format = f!;
              _save();
            }),
          ),
        ]),
        const SizedBox(height: 8),
        if (problems.isEmpty) Text('Legal in ${deck.format.label}.', style: t.style(13, color: t.ok)) else for (final p in problems.take(6)) Text('• ${p.message}', style: t.style(13, color: t.danger)),
        if (online.isNotEmpty) Text('Online and rated play need every card fully supported.', style: t.small),
        const ThemedHeader('Add cards'),
        Row(children: [
          Expanded(
            child: TextField(
              style: t.body,
              decoration: InputDecoration(hintText: 'Search by name or type', filled: true, fillColor: t.panel, prefixIcon: const Icon(Icons.search)),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(label: const Text('Supported only'), selected: supportedOnly, onSelected: (v) => setState(() => supportedOnly = v)),
        ]),
        if (!store.data.hasFull)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Expanded(child: Text('Searching the bundled ${store.data.pool.length} cards.', style: t.small)),
              TextButton(onPressed: store.data.downloading ? null : () => store.data.downloadFull().then((_) => setState(() {})), child: Text(store.data.downloading ? 'Downloading…' : 'Get every card')),
            ]),
          ),
        for (final c in results)
          ListTile(
            dense: true,
            leading: ManaPips(c.front.manaCost?.text ?? '', size: 13),
            title: Text(c.name, style: t.style(14, weight: FontWeight.w600)),
            subtitle: Text(c.typeLine, style: t.small),
            trailing: IconButton(
              icon: Icon(Icons.add_circle, color: t.accent),
              onPressed: () => setState(() {
                deck.cards.add(c.name);
                _save();
              }),
            ),
            onTap: () => _show(context, c),
          ),
        ThemedHeader('In the deck (${deck.cards.length})'),
        for (final n in names)
          ListTile(
            dense: true,
            leading: SizedBox(width: 30, child: Text('${counts[n]}×', style: t.style(15, weight: FontWeight.w800, color: t.accent))),
            title: Text(n, style: t.style(14, weight: FontWeight.w600)),
            subtitle: Text(db[n]?.typeLine ?? 'Unknown card', style: t.small),
            onTap: db[n] == null ? null : () => _show(context, db[n]!),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => setState(() {
                  deck.cards.remove(n);
                  _save();
                }),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() {
                  deck.cards.add(n);
                  _save();
                }),
              ),
            ]),
          ),
      ]),
    );
  }

  void _show(BuildContext context, CardDef c) {
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => CardDetailView(def: c));
  }
}

/// A small card tile for grids.
class CardTile extends StatelessWidget {
  const CardTile({super.key, required this.card, this.onTap});
  final CardDef card;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final t = GameTheme.of(context);
    final ok = OracleParser.parse(card).supported;
    return GestureDetector(
      onTap: onTap,
      child: Stack(children: [
        Positioned.fill(child: CardPicture(def: card, size: 'small')),
        if (!ok)
          Positioned(
            right: 4,
            top: 4,
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: t.danger, borderRadius: BorderRadius.circular(4)), child: const Text('NOT YET', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900))),
          ),
      ]),
    );
  }
}
