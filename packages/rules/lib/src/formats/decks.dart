/// Deck legality per format (CR 100.2, 903) and starter decks built from supported cards.
library;

import '../cards/card.dart';
import '../cards/card_db.dart';
import '../cards/mana.dart';
import '../oracle/parser.dart';

enum DeckFormat {
  standard('Standard', Format.standard, 60),
  pioneer('Pioneer', Format.pioneer, 60),
  modern('Modern', Format.modern, 60),
  legacy('Legacy', Format.legacy, 60),
  vintage('Vintage', Format.vintage, 60),
  pauper('Pauper', Format.pauper, 60),
  commander('Commander', Format.commander, 100),
  limited('Limited / cube', null, 40),
  casual('Casual', null, 40);

  const DeckFormat(this.label, this.format, this.minSize);
  final String label;
  final Format? format;
  final int minSize;
}

class DeckProblem {
  const DeckProblem(this.message, {this.card});
  final String message;
  final String? card;
  @override
  String toString() => message;
}

/// Checks a deck (card names, with repeats) for [f]. With [requireSupported] (rated and online
/// play) every card must be fully supported by the engine.
List<DeckProblem> validateDeck(CardDatabase db, List<String> deck, DeckFormat f, {bool requireSupported = false, String? commander}) {
  final out = <DeckProblem>[];
  final counts = <String, int>{};
  for (final n in deck) {
    counts[n] = (counts[n] ?? 0) + 1;
  }
  final size = deck.length + (commander != null ? 1 : 0);
  if (f == DeckFormat.commander) {
    if (size != 100) out.add(DeckProblem('A Commander deck has exactly 100 cards (this one has $size).'));
  } else if (size < f.minSize) {
    out.add(DeckProblem('${f.label} decks need at least ${f.minSize} cards (this one has $size).'));
  }
  final maxCopies = f == DeckFormat.commander ? 1 : (f == DeckFormat.limited ? 1 << 20 : 4);
  Set<Color>? identity;
  if (commander != null) identity = db[commander]?.colorIdentity.toSet();
  for (final e in counts.entries) {
    final c = db[e.key];
    if (c == null) {
      out.add(DeckProblem('Unknown card: ${e.key}', card: e.key));
      continue;
    }
    final anyNumber = c.isBasicLand || c.oracleText.contains('A deck can have any number of cards named');
    if (!anyNumber && e.value > maxCopies) out.add(DeckProblem('${c.name}: at most $maxCopies ${maxCopies == 1 ? 'copy' : 'copies'}.', card: c.name));
    if (f.format != null) {
      final l = c.legality(f.format!);
      if (l == Legality.banned) out.add(DeckProblem('${c.name} is banned in ${f.label}.', card: c.name));
      if (l == Legality.notLegal) out.add(DeckProblem('${c.name} is not legal in ${f.label}.', card: c.name));
      if (l == Legality.restricted && e.value > 1) out.add(DeckProblem('${c.name} is restricted to one copy in ${f.label}.', card: c.name));
    }
    if (identity != null && !c.colorIdentity.every(identity.contains)) out.add(DeckProblem("${c.name} is outside the commander's color identity.", card: c.name));
    if (requireSupported && !OracleParser.parse(c).supported) out.add(DeckProblem('${c.name} isn\'t fully supported yet, so it can\'t be played in rated or online games.', card: c.name));
  }
  return out;
}

const basicLandFor = {Color.white: 'Plains', Color.blue: 'Island', Color.black: 'Swamp', Color.red: 'Mountain', Color.green: 'Forest'};

/// A 40-card two-color deck from the fully supported cards of [set]: about 16 creatures, 7 other
/// spells and 17 basic lands split by the deck's color needs. Deterministic.
List<String> starterDeck(CardDatabase db, Set<Color> colors, {String set = 'fdn', int spells = 23, int lands = 17}) {
  final pool = <CardDef>[];
  for (final c in db.cards) {
    if (!c.sets.contains(set) || c.isBasicLand) continue;
    if (c.front.isLand) continue;
    if (c.colorIdentity.isEmpty || !c.colorIdentity.every(colors.contains)) continue;
    if (c.manaValue > 6 || c.manaValue == 0) continue;
    if (!OracleParser.parse(c).supported) continue;
    pool.add(c);
  }
  int rank(CardDef c) {
    var v = switch (c.rarity) { 'mythic' => 40, 'rare' => 30, 'uncommon' => 20, _ => 10 };
    if (c.front.isCreature) v += 8;
    if (c.colorIdentity.length == colors.length && colors.length > 1) v += 6;
    return v - (c.manaValue - 3).abs();
  }

  pool.sort((a, b) {
    final r = rank(b) - rank(a);
    return r != 0 ? r : a.name.compareTo(b.name);
  });
  final creatures = pool.where((c) => c.front.isCreature).toList();
  final others = pool.where((c) => !c.front.isCreature).toList();
  final deck = <String>[];
  void take(List<CardDef> from, int n) {
    var added = 0;
    for (final c in from) {
      if (added >= n) break;
      final copies = c.rarity == 'common' ? 2 : 1;
      for (var i = 0; i < copies && added < n; i++) {
        deck.add(c.name);
        added++;
      }
    }
  }

  take(creatures, 16);
  take(others, spells - deck.length);
  if (deck.length < spells) take(creatures.skip(8).toList(), spells - deck.length);
  // Lands in proportion to colored symbols.
  final weight = {for (final c in colors) c: 0};
  for (final n in deck) {
    for (final s in db[n]!.front.manaCost?.symbols ?? const <ManaSymbol>[]) {
      if (s is ColoredSymbol && s.type.color != null && weight.containsKey(s.type.color)) weight[s.type.color!] = weight[s.type.color]! + 1;
    }
  }
  final total = weight.values.fold<int>(0, (a, b) => a + b);
  final order = colors.toList()..sort((a, b) => a.index - b.index);
  var left = lands;
  for (var i = 0; i < order.length; i++) {
    final c = order[i];
    final n = i == order.length - 1 ? left : (total == 0 ? lands ~/ order.length : (lands * weight[c]! / total).round().clamp(5, lands - 5));
    for (var k = 0; k < n; k++) {
      deck.add(basicLandFor[c]!);
    }
    left -= n;
  }
  return deck;
}

/// The ten two-color pairs, named.
const colorPairs = <String, Set<Color>>{
  'Azorius (WU)': {Color.white, Color.blue},
  'Dimir (UB)': {Color.blue, Color.black},
  'Rakdos (BR)': {Color.black, Color.red},
  'Gruul (RG)': {Color.red, Color.green},
  'Selesnya (GW)': {Color.green, Color.white},
  'Orzhov (WB)': {Color.white, Color.black},
  'Izzet (UR)': {Color.blue, Color.red},
  'Golgari (BG)': {Color.black, Color.green},
  'Boros (RW)': {Color.red, Color.white},
  'Simic (GU)': {Color.green, Color.blue},
};
