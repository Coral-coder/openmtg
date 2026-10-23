/// Parses one oracle text with a type line and prints the abilities, or what failed.
///
///     dart run bin/probe.dart "Sorcery" "Look at the top four cards of your library. ..."
library;

import 'dart:io';

import 'package:rules/rules.dart';
import 'package:rules/src/oracle/text.dart' show normalizeOracle;

void main(List<String> args) {
  OracleParser.diag = [];
  final f = Face(name: 'Probe', typeLine: args[0], oracleText: args[1], power: '2', toughness: '2', manaCost: ManaCost.parse('{2}'));
  final p = OracleParser.parseFace(f, cardName: 'Probe');
  for (final a in p.abilities) {
    stdout.writeln('${a.text.replaceAll('\n', ' / ')}\n  = ${describeAbility(a)}');
  }
  stdout.writeln(p.unsupported.isEmpty ? 'SUPPORTED' : 'UNSUPPORTED: ${p.unsupported.join(' | ')}');
  for (final d in OracleParser.diag!) {
    stdout.writeln('  diag $d');
  }
  if (args.contains('--norm')) stdout.writeln(normalizeOracle(f.oracleText, f.name));
}
