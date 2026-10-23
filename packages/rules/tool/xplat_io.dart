import 'dart:io';

String readText(String path) => File(path).readAsStringSync();
void writeLine(String s) => stdout.writeln(s);
List<String> programArgs(List<String> args) => args;
