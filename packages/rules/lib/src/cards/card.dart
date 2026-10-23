/// Printed cards (CR 200–209, 708–712): what the card database knows about a card.
library;

import 'mana.dart';

enum CardType {
  artifact('Artifact'),
  battle('Battle'),
  creature('Creature'),
  enchantment('Enchantment'),
  instant('Instant'),
  kindred('Kindred'),
  land('Land'),
  planeswalker('Planeswalker'),
  sorcery('Sorcery'),
  // Non-traditional types appear only on special cards; kept so type lines parse.
  conspiracy('Conspiracy'),
  dungeon('Dungeon'),
  emblem('Emblem'),
  phenomenon('Phenomenon'),
  plane('Plane'),
  scheme('Scheme'),
  vanguard('Vanguard');

  const CardType(this.label);
  final String label;

  static CardType? parse(String s) {
    final l = s.toLowerCase();
    if (l == 'tribal') return kindred;
    for (final t in values) {
      if (t.name == l) return t;
    }
    return null;
  }

  bool get isPermanentType => this == artifact || this == battle || this == creature || this == enchantment || this == land || this == planeswalker;
}

enum Supertype {
  basic('Basic'),
  legendary('Legendary'),
  snow('Snow'),
  world('World'),
  ongoing('Ongoing'),
  elite('Elite'),
  host('Host');

  const Supertype(this.label);
  final String label;

  static Supertype? parse(String s) {
    final l = s.toLowerCase();
    for (final t in values) {
      if (t.name == l) return t;
    }
    return null;
  }
}

/// A parsed type line.
class TypeLine {
  const TypeLine({this.supertypes = const {}, this.types = const {}, this.subtypes = const []});
  final Set<Supertype> supertypes;
  final Set<CardType> types;
  final List<String> subtypes;

  static const empty = TypeLine();

  static TypeLine parse(String line) {
    final dash = line.indexOf('—');
    final left = (dash >= 0 ? line.substring(0, dash) : line).trim();
    final right = dash >= 0 ? line.substring(dash + 1).trim() : '';
    final sup = <Supertype>{};
    final types = <CardType>{};
    for (final w in left.split(RegExp(r'\s+'))) {
      if (w.isEmpty) continue;
      final s = Supertype.parse(w);
      if (s != null) {
        sup.add(s);
        continue;
      }
      final t = CardType.parse(w);
      if (t != null) types.add(t);
    }
    // Multi-word subtypes ("Time Lord") are rare; split on spaces like Scryfall's type line.
    final subs = right.isEmpty ? <String>[] : right.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    return TypeLine(supertypes: sup, types: types, subtypes: _joinMultiWord(subs));
  }

  static const _multiWord = {'Time Lord', 'Urza\'s'};

  static List<String> _joinMultiWord(List<String> words) {
    final out = <String>[];
    for (var i = 0; i < words.length; i++) {
      if (i + 1 < words.length && _multiWord.contains('${words[i]} ${words[i + 1]}')) {
        out.add('${words[i]} ${words[i + 1]}');
        i++;
      } else {
        out.add(words[i]);
      }
    }
    return out;
  }

  String get text {
    final l = [...supertypes.map((s) => s.label), ...types.map((t) => t.label)].join(' ');
    return subtypes.isEmpty ? l : '$l — ${subtypes.join(' ')}';
  }
}

/// One face of a card. A normal card has one; split, flip, adventure, transforming, modal
/// double-faced and meld cards have two (CR 708–712).
class Face {
  Face({
    required this.name,
    this.manaCost,
    required this.typeLine,
    this.oracleText = '',
    this.power,
    this.toughness,
    this.loyalty,
    this.defense,
    List<ManaColor>? colors,
    this.colorIndicator,
  })  : type = TypeLine.parse(typeLine),
        colors = colors ?? manaCost?.colors.toList() ?? const [];

  final String name;

  /// Null when the face has no mana cost at all (lands, back faces), as opposed to {0}.
  final ManaCost? manaCost;
  final String typeLine;
  final TypeLine type;
  final String oracleText;

  /// Printed P/T, loyalty and defense as text ("*", "1+*" are possible).
  final String? power, toughness, loyalty, defense;
  final List<ManaColor> colors;
  final List<ManaColor>? colorIndicator;

  bool get isCreature => type.types.contains(CardType.creature);
  bool get isLand => type.types.contains(CardType.land);
  bool get isInstantOrSorcery => type.types.contains(CardType.instant) || type.types.contains(CardType.sorcery);
  bool get isPermanent => type.types.any((t) => t.isPermanentType);
  int get manaValue => manaCost?.manaValue ?? 0;
}

enum Layout {
  normal, split, flip, transform, modalDfc, meld, leveler, clazz, case_, saga, adventure, mutate, prototype, battle, planar, scheme,
  vanguard, token, doubleFacedToken, emblem, augment, host, artSeries, reversibleCard, prepare, other;

  static Layout parse(String s) {
    switch (s) {
      case 'modal_dfc':
        return modalDfc;
      case 'class':
        return clazz;
      case 'case':
        return case_;
      case 'double_faced_token':
        return doubleFacedToken;
      case 'art_series':
        return artSeries;
      case 'reversible_card':
        return reversibleCard;
    }
    for (final l in values) {
      if (l.name == s) return l;
    }
    return other;
  }

  String get scryfall => switch (this) {
        modalDfc => 'modal_dfc',
        clazz => 'class',
        case_ => 'case',
        doubleFacedToken => 'double_faced_token',
        artSeries => 'art_series',
        reversibleCard => 'reversible_card',
        _ => name,
      };

  /// Two faces on different sides of the card.
  bool get isDoubleFaced => this == transform || this == modalDfc || this == meld || this == doubleFacedToken || this == reversibleCard;
}

/// The formats the database tracks legality for, in the order of the compact legality string.
enum Format {
  standard('Standard'),
  pioneer('Pioneer'),
  modern('Modern'),
  legacy('Legacy'),
  vintage('Vintage'),
  commander('Commander'),
  pauper('Pauper'),
  historic('Historic'),
  brawl('Brawl'),
  alchemy('Alchemy'),
  explorer('Explorer'),
  timeless('Timeless'),
  oathbreaker('Oathbreaker'),
  premodern('Premodern'),
  oldschool('Old School');

  const Format(this.label);
  final String label;
}

enum Legality { legal, notLegal, banned, restricted }

/// A card as the database knows it: its oracle characteristics plus where it was printed.
class CardDef {
  CardDef({
    required this.name,
    required this.layout,
    required this.faces,
    this.colorIdentity = const [],
    this.keywords = const [],
    this.legalities = '',
    this.producedMana = const [],
    this.sets = const [],
    this.imageId = '',
    this.imageSet = '',
    this.imageNumber = '',
    this.rarity = 'common',
    this.artist = '',
    this.backImage = false,
    this.unsupported,
  });

  /// The full name; two-faced cards use "Front // Back" like Scryfall.
  final String name;
  final Layout layout;
  final List<Face> faces;
  final List<ManaColor> colorIdentity;
  final List<String> keywords;

  /// One letter per [Format]: l legal, n not legal, b banned, r restricted.
  final String legalities;
  final List<String> producedMana;

  /// Set codes this card was printed in, oldest first.
  final List<String> sets;

  /// The default printing's Scryfall id (for the image), its set, collector number and artist.
  final String imageId, imageSet, imageNumber, rarity, artist;

  /// Whether the default printing has a back image (transform / modal DFC).
  final bool backImage;

  /// Unsupported text as recorded by the database build (null when it wasn't computed).
  final List<String>? unsupported;

  Face get front => faces.first;

  Legality legality(Format f) {
    final i = f.index;
    if (i >= legalities.length) return Legality.notLegal;
    return switch (legalities[i]) {
      'l' => Legality.legal,
      'b' => Legality.banned,
      'r' => Legality.restricted,
      _ => Legality.notLegal,
    };
  }

  bool get isBasicLand => front.type.supertypes.contains(Supertype.basic) && front.isLand;
  bool get isToken => layout == Layout.token || layout == Layout.doubleFacedToken;

  /// Mana value of the card in a non-stack zone (CR 202.3; a split card adds both halves).
  int get manaValue {
    if (layout == Layout.split) return faces.fold(0, (a, f) => a + f.manaValue);
    if (layout.isDoubleFaced) return front.manaValue;
    return front.manaValue;
  }

  String get oracleText => faces.map((f) => f.oracleText).join('\n//\n');
  String get typeLine => faces.map((f) => f.typeLine).join(' // ');

  /// Scryfall image URL for this card's default printing. [size]: small, normal, large, png.
  String imageUrl({String size = 'normal', bool back = false}) {
    if (imageId.length < 2) return '';
    return 'https://cards.scryfall.io/$size/${back ? 'back' : 'front'}/${imageId[0]}/${imageId[1]}/$imageId.jpg';
  }

  @override
  String toString() => name;
}
