/// Prints what isn't supported yet on each named card, with the deepest failure.
///
///     dart run bin/show.dart ../../build/data/cards.json "Name" "Other name" ...
library;

import 'dart:convert';
import 'dart:io';

import 'package:rules/rules.dart';

void main(List<String> args) {
  final db = CardDatabase.fromJson(jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>);
  for (final name in args.skip(1)) {
    final c = db[name];
    if (c == null) {
      stdout.writeln('?? $name');
      continue;
    }
    OracleParser.clearCache();
    OracleParser.diag = [];
    final p = OracleParser.parse(c);
    stdout.writeln('== ${c.name}${p.supported ? ': SUPPORTED' : ''}');
    for (final u in p.unsupported) {
      stdout.writeln('  ${u.replaceAll('\n', ' / ')}');
    }
    for (final d in OracleParser.diag!.toSet()) {
      if (!p.supported) stdout.writeln('    diag $d');
    }
    OracleParser.diag = null;
  }
}
