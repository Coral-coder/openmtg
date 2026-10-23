/// Prints, for each card name in a names file, whether it parses fully and what blocks it.
///
///     dart run bin/supported.dart <cards.json> <names.txt>
library;

import 'dart:convert';
import 'dart:io';

import 'package:rules/rules.dart';

void main(List<String> args) {
  final db = CardDatabase.fromJson(jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>);
  for (final name in File(args[1]).readAsLinesSync()) {
    if (name.trim().isEmpty || name.startsWith('#')) continue;
    final c = db[name.trim()];
    if (c == null) {
      stdout.writeln('MISSING $name');
      continue;
    }
    final p = OracleParser.parse(c);
    stdout.writeln(p.supported ? 'ok   $name' : 'FAIL $name: ${p.unsupported.join(' | ').replaceAll('\n', ' / ')}');
  }
}
