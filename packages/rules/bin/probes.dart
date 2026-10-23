/// Parses many "type line|oracle text" lines from a file (one card per line, "\n" for new
/// paragraphs) and prints which parse and what failed.
///
///     dart run bin/probes.dart probes.txt
library;

import 'dart:io';

import 'package:rules/rules.dart';

void main(List<String> args) {
  for (final line in File(args[0]).readAsLinesSync()) {
    if (line.trim().isEmpty || line.startsWith('#')) continue;
    final i = line.indexOf('|');
    final type = line.substring(0, i), text = line.substring(i + 1).replaceAll(r'\n', '\n');
    OracleParser.diag = [];
    final f = Face(name: 'Probe', typeLine: type, oracleText: text, power: '2', toughness: '2', manaCost: ManaCost.parse('{2}'));
    final p = OracleParser.parseFace(f, cardName: 'Probe');
    if (p.unsupported.isEmpty) {
      stdout.writeln('ok   $text\n     ${p.abilities.map(describeAbility).join(' ;; ')}');
    } else {
      stdout.writeln('FAIL $text\n     ${OracleParser.diag!.join(' ;; ')}');
    }
  }
}
