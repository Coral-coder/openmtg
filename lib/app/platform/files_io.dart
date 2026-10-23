import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<Directory> _dir() async {
  final base = await getApplicationCacheDirectory();
  final d = Directory('${base.path}/openmtg');
  if (!d.existsSync()) d.createSync(recursive: true);
  return d;
}

Future<String?> readCache(String name) async {
  final f = File('${(await _dir()).path}/$name');
  return f.existsSync() ? f.readAsString() : null;
}

Future<void> writeCache(String name, String data) async {
  await File('${(await _dir()).path}/$name').writeAsString(data);
}

Future<List<int>?> readCacheBytes(String name) async {
  final f = File('${(await _dir()).path}/$name');
  return f.existsSync() ? f.readAsBytes() : null;
}

Future<void> writeCacheBytes(String name, List<int> data) async {
  final f = File('${(await _dir()).path}/$name');
  await f.parent.create(recursive: true);
  await f.writeAsBytes(data);
}
