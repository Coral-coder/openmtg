/// Card tool: coverage of a set from a built database, or one card's parse.
///
///     dart run rules:cards build/data/cards.json fdn        # unsupported text per card in FDN
///     dart run rules:cards build/data/cards.json "Llanowar Elves"
library;

import 'dart:convert';
import 'dart:io';

import 'package:rules/rules.dart';

void main(List<String> args) {
  final db = CardDatabase.fromJson(jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>);
  final q = args.length > 1 ? args[1] : '';
  final card = db[q];
  if (card != null) {
    OracleParser.strict = args.contains('--strict');
    final p = OracleParser.parse(card);
    stdout.writeln('${card.name} — ${card.typeLine}\n${card.oracleText}\n');
    for (final f in p.faces) {
      for (final a in f.abilities) {
        stdout.writeln('  ${a.text.replaceAll('\n', ' / ')}\n    = ${describeAbility(a)}');
      }
    }
    stdout.writeln(p.supported ? 'SUPPORTED' : 'UNSUPPORTED:\n  ${p.unsupported.join('\n  ')}');
    return;
  }
  if (args.contains('--dump')) {
    for (final c in db.cards.where((c) => q.isEmpty || c.sets.contains(q))) {
      final p = OracleParser.parse(c);
      if (!p.supported) continue;
      stdout.writeln('## ${c.name}');
      for (final f in p.faces) {
        for (final a in f.abilities) {
          if (a is KeywordAbility || a is InfoAbility) continue;
          stdout.writeln('  ${a.text.replaceAll('\n', ' / ')}\n    = ${describeAbility(a)}');
        }
      }
    }
    return;
  }
  var ok = 0, n = 0;
  final cards = db.cards.where((c) => q.isEmpty || c.sets.contains(q)).toList();
  for (final c in cards) {
    n++;
    final p = OracleParser.parse(c);
    if (p.supported) {
      ok++;
    } else if (!args.contains('--quiet')) {
      stdout.writeln('${c.name}: ${p.unsupported.join(' | ').replaceAll('\n', ' / ')}');
    }
  }
  stdout.writeln('$ok/$n supported');
}
