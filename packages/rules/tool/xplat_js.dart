import 'dart:js_interop';

@JS('require')
external JSObject _require(String module);

extension type _Fs(JSObject _) implements JSObject {
  external String readFileSync(String path, String encoding);
}

@JS('console.log')
external void _log(String s);

String readText(String path) => _Fs(_require('fs')).readFileSync(path, 'utf8');
void writeLine(String s) => _log(s);

@JS('process.argv')
external JSArray<JSString> get _argv;

/// Node passes the arguments in process.argv (after "node" and the script).
List<String> programArgs(List<String> args) => [for (final a in _argv.toDart.skip(2)) a.toDart];
