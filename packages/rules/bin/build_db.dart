/// Builds the card database from Scryfall's bulk data (docs/PLAN.md §3).
///
///     dart run rules:build_db --oracle oracle-cards.jsonl.gz --default default-cards.jsonl.gz --out build/data
///
/// Writes cards.json (one row per oracle card, with coverage), printings.json (every printing),
/// sets.json, coverage.json (per set and format) and manifest.json. The bulk files come from
/// https://api.scryfall.com/bulk-data (tools/fetch_scryfall.sh downloads them politely).
library;

import 'dart:convert';
import 'dart:io';

import 'package:rules/rules.dart';
import 'package:rules/src/coverage.dart';

/// Layouts that aren't cards you put in a deck.
const _skipLayouts = {'art_series', 'vanguard', 'scheme', 'planar', 'emblem', 'token', 'double_faced_token', 'reversible_card'};
const _skipSetTypes = {'memorabilia', 'minigame', 'token'};

Future<void> main(List<String> args) async {
  String? oracle, defaults;
  var out = 'build/data';
  String? only;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--oracle':
        oracle = args[++i];
      case '--default':
        defaults = args[++i];
      case '--out':
        out = args[++i];
      case '--sets':
        only = args[++i];
    }
  }
  if (oracle == null || defaults == null) {
    stderr.writeln('usage: build_db --oracle <oracle-cards.jsonl.gz> --default <default-cards.jsonl.gz> [--out dir] [--sets fdn,blb]');
    exit(64);
  }
  final onlySets = only?.split(',').toSet();

  // Every printing: sets per oracle id, and set info.
  final printings = <String, List<List<Object?>>>{}; // oracle id -> [set, number, id, rarity, artist, released]
  final setInfo = <String, Map<String, Object>>{};
  var bulkDate = '';
  await for (final j in _jsonl(defaults)) {
    final oid = j['oracle_id'] as String? ?? ((j['card_faces'] as List?)?.first as Map?)?['oracle_id'] as String?;
    if (oid == null) continue;
    final set = j['set'] as String;
    final setType = j['set_type'] as String? ?? '';
    if (_skipLayouts.contains(j['layout']) || _skipSetTypes.contains(setType)) continue;
    printings.putIfAbsent(oid, () => []).add([set, j['collector_number'], j['id'], j['rarity'], j['artist'] ?? '', j['released_at'] ?? '']);
    final s = setInfo.putIfAbsent(set, () => {'name': j['set_name'] as String, 'released': j['released_at'] as String? ?? '', 'type': setType, 'cards': 0});
    s['cards'] = (s['cards'] as int) + 1;
  }

  final cards = <CardDef>[];
  final oidOf = <String, String>{};
  final coverage = Coverage();
  await for (final j in _jsonl(oracle)) {
    if (_skipLayouts.contains(j['layout'])) continue;
    final oid = j['oracle_id'] as String? ?? ((j['card_faces'] as List?)?.first as Map?)?['oracle_id'] as String?;
    final prints = printings[oid] ?? const [];
    if (prints.isEmpty) continue;
    prints.sort((a, b) => (a[5] as String).compareTo(b[5] as String));
    final sets = <String>[];
    for (final p in prints) {
      if (!sets.contains(p[0])) sets.add(p[0] as String);
    }
    if (onlySets != null && !sets.any(onlySets.contains)) continue;
    final base = CardDatabase.fromScryfall(j, sets: sets);
    final parsed = OracleParser.parse(base);
    final card = CardDatabase.fromScryfall(j, sets: sets, unsupported: parsed.unsupported);
    cards.add(card);
    oidOf[card.name] = oid!;
    coverage.add(card, parsed.unsupported);
    final updated = j['updated_at'] as String?;
    if (updated != null && updated.compareTo(bulkDate) > 0) bulkDate = updated;
  }
  cards.sort((a, b) => a.name.compareTo(b.name));

  final sets = [
    for (final e in setInfo.entries) SetInfo(code: e.key, name: e.value['name'] as String, released: e.value['released'] as String, type: e.value['type'] as String, cards: e.value['cards'] as int),
  ]..sort((a, b) => a.released.compareTo(b.released));
  final version = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  final db = CardDatabase(cards, sets: sets, version: version, engineVersion: engineVersion);

  final dir = Directory(out)..createSync(recursive: true);
  File('${dir.path}/cards.json').writeAsStringSync(jsonEncode(db.toJson()));
  final printOut = <String, Object>{};
  for (final c in cards) {
    printOut[c.name] = [for (final p in printings[oidOf[c.name]] ?? const <List<Object?>>[]) p.sublist(0, 5)];
  }
  File('${dir.path}/printings.json').writeAsStringSync(jsonEncode(printOut));
  File('${dir.path}/coverage.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(coverage.toJson(sets)));
  File('${dir.path}/manifest.json').writeAsStringSync(jsonEncode({'version': version, 'engine': engineVersion, 'cards': cards.length, 'supported': coverage.supported, 'printings': printings.values.fold<int>(0, (a, p) => a + p.length)}));
  stdout.writeln('${cards.length} cards, ${coverage.supported} fully supported (${(100 * coverage.supported / cards.length).toStringAsFixed(1)}%), ${sets.length} sets → ${dir.path}');
}

Stream<Map<String, dynamic>> _jsonl(String path) async* {
  Stream<List<int>> bytes = File(path).openRead();
  if (path.endsWith('.gz')) bytes = bytes.transform(gzip.decoder);
  final lines = bytes.transform(utf8.decoder).transform(const LineSplitter());
  await for (final l in lines) {
    final t = l.trim();
    if (t.isEmpty || t == '[' || t == ']') continue;
    yield jsonDecode(t.endsWith(',') ? t.substring(0, t.length - 1) : t) as Map<String, dynamic>;
  }
}
