import 'package:flutter/material.dart';
import 'package:rules/rules.dart';

import '../app/store.dart';
import 'package:tcg_app/tcg_app.dart';
import 'card_detail.dart';
import 'decks.dart';

/// Every card, with what the engine supports: per set and per format coverage, and the texts
/// that block the most cards.
class CardDatabaseScreen extends StatefulWidget {
  const CardDatabaseScreen({super.key});
  @override
  State<CardDatabaseScreen> createState() => _CardDatabaseScreenState();
}

class _CardDatabaseScreenState extends State<CardDatabaseScreen> {
  String query = '';
  String? set;
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final store = AppStore.shared;
    final t = GameTheme.of(context);
    return ListenableBuilder(
      listenable: store.data,
      builder: (context, _) => ThemedScreen(
        title: 'Cards',
        subtitle: '${store.db.length} cards${store.data.hasFull ? '' : ' (bundled pool)'}',
        child: Column(children: [
          Row(children: [
            Expanded(child: ThemedButton('Browse', outlined: tab != 0, onPressed: () => setState(() => tab = 0))),
            const SizedBox(width: 8),
            Expanded(child: ThemedButton('Coverage', outlined: tab != 1, onPressed: () => setState(() => tab = 1))),
          ]),
          const SizedBox(height: 8),
          if (!store.data.hasFull)
            Row(children: [
              Expanded(child: Text('Showing the bundled cards. The full database has every card ever printed.', style: t.small)),
              TextButton(onPressed: store.data.downloading ? null : store.data.downloadFull, child: Text(store.data.downloading ? 'Downloading…' : 'Download')),
            ]),
          Expanded(child: tab == 0 ? _browse(context) : _coverage(context)),
        ]),
      ),
    );
  }

  Widget _browse(BuildContext context) {
    final store = AppStore.shared;
    final t = GameTheme.of(context);
    final db = store.db;
    final q = query.toLowerCase();
    final sets = db.sets.where((s) => store.data.hasFull ? true : s.code == store.data.poolSet).toList().reversed.toList();
    final cards = [
      for (final c in db.cards)
        if ((set == null || c.sets.contains(set)) && (q.isEmpty || c.name.toLowerCase().contains(q) || c.oracleText.toLowerCase().contains(q))) c,
    ];
    return Column(children: [
      Row(children: [
        Expanded(child: TextField(style: t.body, decoration: InputDecoration(hintText: 'Search names and rules text', filled: true, fillColor: t.panel, prefixIcon: const Icon(Icons.search)), onChanged: (v) => setState(() => query = v))),
        const SizedBox(width: 8),
        DropdownButton<String?>(
          value: set,
          hint: const Text('All sets'),
          items: [const DropdownMenuItem<String?>(value: null, child: Text('All sets')), for (final s in sets.take(400)) DropdownMenuItem<String?>(value: s.code, child: Text('${s.name} (${s.code.toUpperCase()})', overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => set = v),
        ),
      ]),
      const SizedBox(height: 6),
      Text('${cards.length} cards · ${cards.where((c) => OracleParser.parse(c).supported).length} fully supported', style: t.small),
      const SizedBox(height: 6),
      Expanded(
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 140, childAspectRatio: 63 / 88, mainAxisSpacing: 6, crossAxisSpacing: 6),
          itemCount: cards.length.clamp(0, 600),
          itemBuilder: (context, i) => CardTile(card: cards[i], onTap: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => CardDetailView(def: cards[i]))),
        ),
      ),
    ]);
  }

  Widget _coverage(BuildContext context) {
    final store = AppStore.shared;
    final t = GameTheme.of(context);
    final cov = store.data.coverage;
    final formats = (cov['formats'] as Map?)?.cast<String, dynamic>() ?? const {};
    final sets = (cov['sets'] as Map?)?.cast<String, dynamic>() ?? const {};
    final missing = (cov['missing'] as List?) ?? const [];
    final setNames = {for (final s in store.db.sets) s.code: s.name};
    Widget bar(String label, int ok, int total) {
      final f = total == 0 ? 0.0 : ok / total;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 150, child: Text(label, style: t.style(13, weight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: f, minHeight: 10, color: t.ok, backgroundColor: t.muted.withValues(alpha: 0.25)))),
          SizedBox(width: 90, child: Text('$ok/$total', textAlign: TextAlign.right, style: t.small)),
        ]),
      );
    }

    final setRows = sets.entries.toList()..sort((a, b) => ((b.value as List)[1] as int) - ((a.value as List)[1] as int));
    return ListView(children: [
      Text('${cov['supported'] ?? 0} of ${cov['total'] ?? 0} cards fully supported. Only those can be played online or in rated games; the rest can be viewed.', style: t.body),
      const ThemedHeader('By format'),
      for (final f in Format.values)
        if (formats[f.name] != null) bar(f.label, (formats[f.name] as List)[0] as int, (formats[f.name] as List)[1] as int),
      const ThemedHeader('By set (newest Standard sets first)'),
      for (final e in setRows.where((e) => store.db.set(e.key)?.type == 'expansion' || store.db.set(e.key)?.type == 'core').toList()
        ..sort((a, b) => (store.db.set(b.key)?.released ?? '').compareTo(store.db.set(a.key)?.released ?? '')))
        bar(setNames[e.key] ?? e.key.toUpperCase(), (e.value as List)[0] as int, (e.value as List)[1] as int),
      const ThemedHeader('What blocks the most cards'),
      for (final m in missing.take(80))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 50, child: Text('${(m as List)[0]}', style: t.style(13, weight: FontWeight.w800, color: t.accent))),
            Expanded(child: Text('${m[1]}', style: t.style(12, weight: FontWeight.w500))),
          ]),
        ),
    ]);
  }
}
