/// Coverage: which cards the engine fully supports, per set and per format, and which unhandled
/// texts block the most cards (so coverage grows mechanic by mechanic).
library;

import 'cards/card.dart';
import 'cards/card_db.dart';
import 'util/sort.dart';

class Coverage {
  int total = 0;
  int supported = 0;
  final Map<String, (int, int)> bySet = {};
  final Map<Format, (int, int)> byFormat = {};

  /// Unhandled paragraph (with the card's name replaced) → number of cards it blocks.
  final Map<String, int> missing = {};

  void add(CardDef c, List<String> unsupported) {
    final ok = unsupported.isEmpty;
    total++;
    if (ok) supported++;
    for (final s in c.sets) {
      final v = bySet[s] ?? (0, 0);
      bySet[s] = (v.$1 + (ok ? 1 : 0), v.$2 + 1);
    }
    for (final f in Format.values) {
      final l = c.legality(f);
      if (l == Legality.legal || l == Legality.restricted) {
        final v = byFormat[f] ?? (0, 0);
        byFormat[f] = (v.$1 + (ok ? 1 : 0), v.$2 + 1);
      }
    }
    for (final u in unsupported) {
      final key = u.replaceAll(c.name, '~').replaceAll(RegExp(r'\d+'), 'N');
      missing[key] = (missing[key] ?? 0) + 1;
    }
  }

  Map<String, dynamic> toJson(List<SetInfo> sets) {
    final top = missing.entries.toList()..sortStable((a, b) => b.value != a.value ? b.value - a.value : a.key.compareTo(b.key));
    return {
      'total': total,
      'supported': supported,
      'formats': {for (final e in byFormat.entries) e.key.name: [e.value.$1, e.value.$2]},
      'sets': {
        for (final s in sets)
          if (bySet.containsKey(s.code)) s.code: [bySet[s.code]!.$1, bySet[s.code]!.$2],
      },
      'missing': [for (final e in top.take(300)) [e.value, e.key]],
    };
  }
}
