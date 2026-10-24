import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:rules/rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tcg_app/tcg_app.dart';

/// Where the generated card data is published (with the website, docs/PLAN.md §3).
const siteUrl = 'https://coral-coder.github.io/openmtg/';

/// The card database the app plays with. The bundled pool (the milestone's fully supported
/// cards) is always there; the full database of every card is downloaded on demand and cached,
/// and refreshed when the site publishes a newer one.
class CardData extends ChangeNotifier {
  late CardDatabase _pool;
  CardDatabase? _full;

  /// Per-set and per-format coverage from the last database build.
  Map<String, dynamic> coverage = const {};
  String poolSet = 'fdn';
  bool downloading = false;
  String? error;
  String? remoteVersion;

  CardDatabase get db => _full ?? _pool;
  CardDatabase get pool => _pool;
  bool get hasFull => _full != null;

  Future<void> loadBundled(AssetBundle bundle) async {
    final raw = await bundle.loadString('assets/data/pool.json');
    _pool = CardDatabase.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    try {
      coverage = jsonDecode(await bundle.loadString('assets/data/coverage.json')) as Map<String, dynamic>;
    } catch (_) {}
    // A previously downloaded full database (phones keep it in their cache directory).
    try {
      final cached = await readCache('cards.json');
      if (cached != null) _full = _decode(cached);
    } catch (_) {}
  }

  static Uri dataUri(String file) => kIsWeb ? Uri.base.resolve('../data/$file') : Uri.parse('${siteUrl}data/$file');

  CardDatabase _decode(String raw) => CardDatabase.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  /// Downloads the full card database.
  Future<bool> downloadFull() async {
    if (downloading) return false;
    downloading = true;
    error = null;
    notifyListeners();
    try {
      final r = await http.get(dataUri('cards.json'));
      if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode}');
      final raw = utf8.decode(r.bodyBytes);
      _full = await compute(_parseDb, raw);
      await writeCache('cards.json', raw);
      downloading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = 'Could not download the card database: $e';
      downloading = false;
      notifyListeners();
      return false;
    }
  }

  static CardDatabase _parseDb(String raw) => CardDatabase.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  /// Reads the site's manifest; downloads a newer full database if one was downloaded before.
  Future<void> checkForUpdate(SharedPreferences prefs) async {
    try {
      final r = await http.get(dataUri('manifest.json')).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      remoteVersion = m['version'] as String?;
      final cov = await http.get(dataUri('coverage.json')).timeout(const Duration(seconds: 8));
      if (cov.statusCode == 200) coverage = jsonDecode(cov.body) as Map<String, dynamic>;
      if (_full != null && remoteVersion != null && remoteVersion != _full!.version) await downloadFull();
      notifyListeners();
    } catch (_) {}
  }
}
