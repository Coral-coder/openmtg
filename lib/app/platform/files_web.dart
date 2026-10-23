/// On the web the browser's HTTP cache keeps downloads; nothing is stored separately.
Future<String?> readCache(String name) async => null;
Future<void> writeCache(String name, String data) async {}
Future<List<int>?> readCacheBytes(String name) async => null;
Future<void> writeCacheBytes(String name, List<int> data) async {}
