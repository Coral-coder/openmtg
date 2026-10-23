/// Oracle text preparation: reminder text out, self-references to "~", sentences and clauses.
library;

import 'subtypes.dart';
import '../util/sort.dart';

const numberWords = {
  'a': 1,
  'an': 1,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'thirteen': 13,
  'fourteen': 14,
  'fifteen': 15,
  'sixteen': 16,
  'twenty': 20,
};

/// Regex fragment for a written number.
const numRe = r'(?:a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|twenty|\d+|x)';

int? numberWord(String w) {
  final t = w.trim();
  return int.tryParse(t) ?? numberWords[t];
}

/// Lowercase subtype → canonical subtype, including plurals ("elves" → "Elf").
final Map<String, String> subtypeWords = _buildSubtypes();

/// Subtypes that are creature types.
final Set<String> creatureTypeSet = {for (final t in creatureTypes) t};

Map<String, String> _buildSubtypes() {
  final out = <String, String>{};
  void add(String t) {
    final l = t.toLowerCase();
    out[l] = t;
    final plurals = <String>{
      '${l}s',
      '${l}es',
      if (l.endsWith('f')) '${l.substring(0, l.length - 1)}ves',
      if (l.endsWith('fe')) '${l.substring(0, l.length - 2)}ves',
      if (l.endsWith('y')) '${l.substring(0, l.length - 1)}ies',
      if (l.endsWith('man')) '${l.substring(0, l.length - 3)}men',
      if (l.endsWith('us')) '${l.substring(0, l.length - 2)}i',
    };
    for (final p in plurals) {
      out.putIfAbsent(p, () => t);
    }
  }

  for (final set in [creatureTypes, landTypes, artifactTypes, enchantmentTypes, planeswalkerTypes, spellTypes, battleTypes]) {
    for (final t in set) {
      add(t);
    }
  }
  // Irregular plurals and words that are also ordinary English.
  out['merfolk'] = 'Merfolk';
  out['sphinxes'] = 'Sphinx';
  out['mice'] = 'Mouse';
  out['dwarves'] = 'Dwarf';
  out['elves'] = 'Elf';
  out['wolves'] = 'Wolf';
  out['fish'] = 'Fish';
  out['sheep'] = 'Sheep';
  for (final w in const ['equipment', 'aura', 'auras', 'vehicle', 'vehicles', 'food', 'foods', 'treasure', 'treasures', 'clue', 'clues', 'saga', 'sagas', 'gate', 'gates', 'shrine', 'shrines', 'cave', 'caves', 'desert', 'deserts', 'town', 'towns', 'blood']) {
    out.putIfAbsent(w, () => w[0].toUpperCase() + w.substring(1));
  }
  // Common English words that happen to be subtypes and would confuse phrase parsing.
  for (final w in const ['will', 'mount', 'bear', 'bears', 'role', 'case', 'class', 'lesson', 'adventure', 'trap', 'arcane', 'curse', 'cartouche', 'room', 'rooms']) {
    if (out[w] != null && !const {'bear', 'bears'}.contains(w)) out.remove(w);
  }
  return out;
}

/// Prepares one face's oracle text: lowercase, reminder text removed, self-references as "~".
String normalizeOracle(String text, String name, {bool legendary = false}) {
  var t = text;
  // Reminder text (it never has rules meaning). Nested quotes inside parentheses are fine.
  t = t.replaceAll(RegExp(r'\s*\([^()]*\)'), '');
  t = t.replaceAll('’', "'").replaceAll('−', '-').replaceAll('–', '-').replaceAll('“', '"').replaceAll('”', '"');
  final names = <String>{name};
  final comma = name.indexOf(',');
  if (comma > 0) names.add(name.substring(0, comma));
  // "Kellan, Planar Trailblazer" → "Kellan"; "Arahbo, the First Fang" → "Arahbo".
  if (legendary) {
    final first = name.split(RegExp(r'[ ,]')).first;
    if (first.length > 2 && !const {'The', 'A', 'An', 'Lord', 'Lady', 'King', 'Queen', 'General', 'Captain', 'Sir'}.contains(first)) names.add(first);
  }
  final sorted = names.toList()..sortStable((a, b) => b.length - a.length);
  for (final n in sorted) {
    t = t.replaceAll(n, '~');
  }
  t = t.toLowerCase();
  t = t.replaceAll(RegExp(r"\bthis (creature|spell|artifact|enchantment|land|permanent|card|token|equipment|aura|vehicle|saga|planeswalker|battle|class|case|room|siege|spacecraft|object)\b"), '~');
  t = t.replaceAll(RegExp(r'[ \t]+'), ' ');
  return t.trim();
}

/// Splits a paragraph into sentences on ". " outside quotes; drops the final period.
List<String> sentences(String s) {
  final out = <String>[];
  final b = StringBuffer();
  var inQuote = false;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == '"') inQuote = !inQuote;
    if (ch == '.' && !inQuote && (i + 1 == s.length || s[i + 1] == ' ' || s[i + 1] == '\n')) {
      final t = b.toString().trim();
      if (t.isNotEmpty) out.add(t);
      b.clear();
      continue;
    }
    b.write(ch);
  }
  final t = b.toString().trim();
  if (t.isNotEmpty) out.add(t);
  return out;
}

/// Index of the first [sep] outside double quotes, or -1.
int indexOutsideQuotes(String s, String sep, [int start = 0]) {
  var inQuote = false;
  for (var i = 0; i < s.length; i++) {
    if (s[i] == '"') inQuote = !inQuote;
    if (i >= start && !inQuote && s.startsWith(sep, i)) return i;
  }
  return -1;
}

/// Anchored, full match; returns groups (empty string for unmatched optional groups) or null.
List<String>? rx(String text, String pattern) {
  final m = RegExp('^(?:$pattern)\$').firstMatch(text);
  if (m == null) return null;
  return List.generate(m.groupCount + 1, (i) => m.group(i) ?? '');
}

/// Ability words (CR 207.2c): italic labels with no rules meaning.
const abilityWords = {
  'landfall', 'raid', 'morbid', 'threshold', 'ferocious', 'delirium', 'metalcraft', 'revolt', 'spell mastery', 'hellbent', 'heroic', 'constellation',
  'magecraft', 'alliance', 'coven', 'domain', 'enrage', 'formidable', 'battalion', 'bloodrush', 'channel', 'chroma', 'cohort', 'council\'s dilemma',
  'eminence', 'fateful hour', 'grandeur', 'imprint', 'inspired', 'join forces', 'kinship', 'lieutenant', 'parley', 'radiance', 'rally', 'strive',
  'sweep', 'tempting offer', 'undergrowth', 'will of the council', 'adamant', 'addendum', 'pack tactics', 'celebration', 'corrupted', 'descend 4',
  'descend 8', 'eerie', 'survival', 'valiant', 'flurry', 'void', 'start your engines!', 'max speed', 'secret council', 'fathomless descent',
  'paradox', 'gift', 'bargain', 'renew', 'teamwork', 'outlaw', 'opening hand',
};
