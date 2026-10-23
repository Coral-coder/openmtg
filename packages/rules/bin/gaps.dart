/// Ranks what the parser can't read yet by how many cards it blocks, counting only cards held
/// back by that one gap (so each line is a measure of what fixing it would unlock).
///
///     dart run bin/gaps.dart ../../build/data/cards.json [limit] [filter]
library;

import 'dart:convert';
import 'dart:io';

import 'package:rules/rules.dart';

void main(List<String> args) {
  final db = CardDatabase.fromJson(jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>);
  final limit = args.length > 1 ? int.parse(args[1]) : 80;
  final filter = args.length > 2 ? args[2] : '';
  final only = <String, int>{};
  final examples = <String, String>{};
  final any = <String, int>{};
  var ok = 0;
  for (final c in db.cards) {
    OracleParser.clearCache();
    OracleParser.diag = [];
    final p = OracleParser.parse(c);
    final d = OracleParser.diag!;
    OracleParser.diag = null;
    if (p.supported) {
      ok++;
      continue;
    }
    String norm(String s) => s.replaceAll(RegExp(r'\d+'), 'N');
    final keys = <String>{
      for (final u in p.unsupported)
        if (u.startsWith('Card layout')) u,
      // The last diagnostic per paragraph is the deepest failure.
      ...d.map(norm),
    };
    if (keys.isEmpty) keys.addAll(p.unsupported.map((u) => 'paragraph: ${norm(u)}'));
    for (final k in keys) {
      any[k] = (any[k] ?? 0) + 1;
    }
    final blocking = keys.where((k) => !k.startsWith('static: ') || !d.any((x) => x.startsWith('sentence: '))).toSet();
    if (p.unsupported.length == 1) {
      for (final k in blocking) {
        only[k] = (only[k] ?? 0) + 1;
        examples.putIfAbsent(k, () => c.name);
      }
    }
  }
  stdout.writeln('$ok/${db.cards.length} supported\n');
  final top = only.entries.where((e) => filter.isEmpty || e.key.contains(filter)).toList()..sort((a, b) => b.value - a.value);
  for (final e in top.take(limit)) {
    stdout.writeln('${e.value.toString().padLeft(5)} ${e.key}   [${examples[e.key]}]');
  }
}
