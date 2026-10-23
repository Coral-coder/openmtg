/// The card database: every card by name, loaded from the compact JSON the data pipeline builds
/// from Scryfall's bulk data (see bin/build_db.dart and docs/PLAN.md §3).
library;

import 'card.dart';
import 'mana.dart';

class SetInfo {
  const SetInfo({required this.code, required this.name, this.released = '', this.type = '', this.cards = 0});
  final String code, name, released, type;
  final int cards;

  List<Object> toJson() => [code, name, released, type, cards];
  static SetInfo fromJson(List j) => SetInfo(code: j[0] as String, name: j[1] as String, released: j.length > 2 ? j[2] as String : '', type: j.length > 3 ? j[3] as String : '', cards: j.length > 4 ? j[4] as int : 0);
}

class CardDatabase {
  CardDatabase(Iterable<CardDef> cards, {this.sets = const [], this.version = '', this.engineVersion = 0}) {
    for (final c in cards) {
      _byName[c.name] = c;
      // Faces are findable by their own name too ("Fire" finds "Fire // Ice").
      if (c.faces.length > 1) {
        for (final f in c.faces) {
          _byFaceName.putIfAbsent(f.name, () => c);
        }
      }
    }
  }

  final Map<String, CardDef> _byName = {};
  final Map<String, CardDef> _byFaceName = {};
  final List<SetInfo> sets;

  /// Data version (Scryfall's bulk timestamp) and the engine version that computed coverage.
  final String version;
  final int engineVersion;

  Iterable<CardDef> get cards => _byName.values;
  int get length => _byName.length;

  CardDef? operator [](String name) => _byName[name] ?? _byFaceName[name];

  CardDef get(String name) {
    final c = this[name];
    if (c == null) throw ArgumentError('Unknown card: $name');
    return c;
  }

  SetInfo? set(String code) {
    for (final s in sets) {
      if (s.code == code) return s;
    }
    return null;
  }

  // ---- Compact JSON ----

  Map<String, dynamic> toJson() => {
        'v': 1,
        'version': version,
        'engine': engineVersion,
        'formats': [for (final f in Format.values) f.name],
        'sets': [for (final s in sets) s.toJson()],
        'cards': [for (final c in cards) encodeCard(c)],
      };

  static CardDatabase fromJson(Map<String, dynamic> j) {
    final cards = [for (final row in j['cards'] as List) decodeCard(row as List)];
    return CardDatabase(cards,
        sets: [for (final s in (j['sets'] as List? ?? const [])) SetInfo.fromJson(s as List)],
        version: j['version'] as String? ?? '',
        engineVersion: j['engine'] as int? ?? 0);
  }

  static String _colors(List<ManaColor> cs) => cs.map((c) => c.symbol).join();
  static List<ManaColor> _parseColors(Object? s) => s == null ? const [] : [for (final ch in (s as String).split('')) ?ManaColor.fromSymbol(ch)];

  static List<Object?> _trim(List<Object?> row) {
    while (row.isNotEmpty && (row.last == null || row.last == '' || (row.last is List && (row.last as List).isEmpty) || row.last == false)) {
      row.removeLast();
    }
    return row;
  }

  static List<Object?> encodeFace(Face f) => _trim([
        f.name,
        f.manaCost?.text,
        f.typeLine,
        f.oracleText,
        f.power,
        f.toughness,
        f.loyalty,
        f.defense,
        _colors(f.colors),
        f.colorIndicator == null ? null : _colors(f.colorIndicator!),
      ]);

  static Face decodeFace(List r) {
    Object? at(int i) => i < r.length ? r[i] : null;
    final cost = at(1) as String?;
    return Face(
      name: r[0] as String,
      manaCost: cost == null ? null : ManaCost.parse(cost),
      typeLine: at(2) as String? ?? '',
      oracleText: at(3) as String? ?? '',
      power: at(4) as String?,
      toughness: at(5) as String?,
      loyalty: at(6) as String?,
      defense: at(7) as String?,
      colors: _parseColors(at(8) ?? ''),
      colorIndicator: at(9) == null ? null : _parseColors(at(9)),
    );
  }

  static List<Object?> encodeCard(CardDef c) => _trim([
        c.name,
        c.layout.scryfall,
        [for (final f in c.faces) encodeFace(f)],
        _colors(c.colorIdentity),
        c.keywords,
        c.legalities,
        c.producedMana.join(),
        c.sets.join(' '),
        c.imageId,
        c.imageSet,
        c.imageNumber,
        c.rarity,
        c.artist,
        c.backImage ? 1 : null,
        c.unsupported,
      ]);

  static CardDef decodeCard(List r) {
    Object? at(int i) => i < r.length ? r[i] : null;
    final produced = at(6) as String? ?? '';
    final sets = at(7) as String? ?? '';
    return CardDef(
      name: r[0] as String,
      layout: Layout.parse(r[1] as String),
      faces: [for (final f in r[2] as List) decodeFace(f as List)],
      colorIdentity: _parseColors(at(3) ?? ''),
      keywords: (at(4) as List?)?.cast<String>() ?? const [],
      legalities: at(5) as String? ?? '',
      producedMana: produced.isEmpty ? const [] : produced.split(''),
      sets: sets.isEmpty ? const [] : sets.split(' '),
      imageId: at(8) as String? ?? '',
      imageSet: at(9) as String? ?? '',
      imageNumber: at(10) as String? ?? '',
      rarity: at(11) as String? ?? 'common',
      artist: at(12) as String? ?? '',
      backImage: at(13) == 1,
      unsupported: (at(14) as List?)?.cast<String>(),
    );
  }

  // ---- Scryfall card objects (used by the build tool and tests) ----

  static const _formatKeys = {
    Format.standard: 'standard',
    Format.pioneer: 'pioneer',
    Format.modern: 'modern',
    Format.legacy: 'legacy',
    Format.vintage: 'vintage',
    Format.commander: 'commander',
    Format.pauper: 'pauper',
    Format.historic: 'historic',
    Format.brawl: 'brawl',
    Format.alchemy: 'alchemy',
    Format.explorer: 'explorer',
    Format.timeless: 'timeless',
    Format.oathbreaker: 'oathbreaker',
    Format.premodern: 'premodern',
    Format.oldschool: 'oldschool',
  };

  static String legalityString(Map<String, dynamic>? legal) {
    final b = StringBuffer();
    for (final f in Format.values) {
      final v = legal?[_formatKeys[f]] as String?;
      b.write(switch (v) { 'legal' => 'l', 'banned' => 'b', 'restricted' => 'r', _ => 'n' });
    }
    return b.toString();
  }

  static Face _faceFromScryfall(Map<String, dynamic> f, {List<ManaColor>? cardColors}) {
    final cost = f['mana_cost'] as String?;
    final colors = (f['colors'] as List?)?.cast<String>();
    final indicator = (f['color_indicator'] as List?)?.cast<String>();
    return Face(
      name: f['name'] as String,
      manaCost: cost == null || cost.isEmpty ? null : ManaCost.parse(cost),
      typeLine: f['type_line'] as String? ?? '',
      oracleText: f['oracle_text'] as String? ?? '',
      power: f['power'] as String?,
      toughness: f['toughness'] as String?,
      loyalty: f['loyalty'] as String?,
      defense: f['defense'] as String?,
      colors: colors == null ? cardColors : [for (final c in colors) ?ManaColor.fromSymbol(c)],
      colorIndicator: indicator == null ? null : [for (final c in indicator) ?ManaColor.fromSymbol(c)],
    );
  }

  /// Builds a card from a Scryfall card object (one printing).
  static CardDef fromScryfall(Map<String, dynamic> j, {List<String> sets = const [], List<String>? unsupported}) {
    final layout = Layout.parse(j['layout'] as String? ?? 'normal');
    final cardColors = [for (final c in (j['colors'] as List? ?? const [])) ?ManaColor.fromSymbol(c as String)];
    final rawFaces = j['card_faces'] as List?;
    final faces = <Face>[];
    if (rawFaces != null && rawFaces.isNotEmpty) {
      for (final f in rawFaces) {
        faces.add(_faceFromScryfall((f as Map).cast<String, dynamic>(), cardColors: cardColors));
      }
    } else {
      faces.add(_faceFromScryfall(j, cardColors: cardColors));
    }
    final imageUris = j['image_uris'] as Map?;
    return CardDef(
      name: j['name'] as String,
      layout: layout,
      faces: faces,
      colorIdentity: [for (final c in (j['color_identity'] as List? ?? const [])) ?ManaColor.fromSymbol(c as String)],
      keywords: (j['keywords'] as List?)?.cast<String>() ?? const [],
      legalities: legalityString((j['legalities'] as Map?)?.cast<String, dynamic>()),
      producedMana: (j['produced_mana'] as List?)?.cast<String>() ?? const [],
      sets: sets.isEmpty ? [j['set'] as String? ?? ''] : sets,
      imageId: j['id'] as String? ?? '',
      imageSet: j['set'] as String? ?? '',
      imageNumber: j['collector_number'] as String? ?? '',
      rarity: j['rarity'] as String? ?? 'common',
      artist: j['artist'] as String? ?? '',
      backImage: imageUris == null && rawFaces != null && layout.isDoubleFaced,
      unsupported: unsupported,
    );
  }
}
