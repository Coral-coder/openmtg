/// Colors and mana symbols (CR 105, 106, 107.4).
library;

enum ManaColor {
  white('W', 'white'),
  blue('U', 'blue'),
  black('B', 'black'),
  red('R', 'red'),
  green('G', 'green');

  const ManaColor(this.symbol, this.word);
  final String symbol;
  final String word;

  static ManaColor? fromSymbol(String s) {
    for (final c in values) {
      if (c.symbol == s) return c;
    }
    return null;
  }

  static ManaColor? fromWord(String w) {
    for (final c in values) {
      if (c.word == w) return c;
    }
    return null;
  }
}

/// A kind of mana: one of the five colors or colorless (CR 106.1).
enum ManaType {
  W, U, B, R, G, C;

  static ManaType? fromSymbol(String s) {
    for (final m in values) {
      if (m.name == s) return m;
    }
    return null;
  }

  ManaColor? get color => this == C ? null : ManaColor.fromSymbol(name);
  static ManaType of(ManaColor c) => fromSymbol(c.symbol)!;
}

/// One symbol of a mana cost.
sealed class ManaSymbol {
  const ManaSymbol();
  int get manaValue;
  String get text;

  @override
  String toString() => text;
}

class GenericSymbol extends ManaSymbol {
  const GenericSymbol(this.amount);
  final int amount;
  @override
  int get manaValue => amount;
  @override
  String get text => '{$amount}';
  @override
  bool operator ==(Object o) => o is GenericSymbol && o.amount == amount;
  @override
  int get hashCode => amount;
}

/// {W} ... {G}, {C}.
class ColoredSymbol extends ManaSymbol {
  const ColoredSymbol(this.type);
  final ManaType type;
  @override
  int get manaValue => 1;
  @override
  String get text => '{${type.name}}';
  @override
  bool operator ==(Object o) => o is ColoredSymbol && o.type == type;
  @override
  int get hashCode => type.hashCode;
}

/// {X} (CR 107.3). Mana value 0 except on the stack.
class XSymbol extends ManaSymbol {
  const XSymbol();
  @override
  int get manaValue => 0;
  @override
  String get text => '{X}';
}

/// {W/U}, {2/W}: either half may be paid (CR 107.4e).
class HybridSymbol extends ManaSymbol {
  const HybridSymbol(this.a, this.b, {this.generic = 0});
  final ManaType? a; // null when the left half is generic
  final ManaType b;
  final int generic;
  @override
  int get manaValue => generic > 0 ? generic : 1;
  @override
  String get text => generic > 0 ? '{$generic/${b.name}}' : '{${a!.name}/${b.name}}';
}

/// {W/P}: one colored mana or 2 life (CR 107.4f).
class PhyrexianSymbol extends ManaSymbol {
  const PhyrexianSymbol(this.type);
  final ManaType type;
  @override
  int get manaValue => 1;
  @override
  String get text => '{${type.name}/P}';
}

/// {S}: snow mana.
class SnowSymbol extends ManaSymbol {
  const SnowSymbol();
  @override
  int get manaValue => 1;
  @override
  String get text => '{S}';
}

/// A mana cost: an ordered list of symbols. `null` cost (no symbols at all, like a land) is
/// different from {0}.
class ManaCost {
  const ManaCost(this.symbols);
  final List<ManaSymbol> symbols;

  static const empty = ManaCost([]);

  static final _sym = RegExp(r'\{([^}]+)\}');

  static ManaCost parse(String text) {
    final out = <ManaSymbol>[];
    for (final m in _sym.allMatches(text)) {
      final s = m.group(1)!;
      final n = int.tryParse(s);
      if (n != null) {
        out.add(GenericSymbol(n));
      } else if (s == 'X' || s == 'Y' || s == 'Z') {
        out.add(const XSymbol());
      } else if (s == 'S') {
        out.add(const SnowSymbol());
      } else if (s.contains('/')) {
        final parts = s.split('/');
        if (parts.length == 2 && parts[1] == 'P') {
          out.add(PhyrexianSymbol(ManaType.fromSymbol(parts[0]) ?? ManaType.C));
        } else if (parts.length == 2) {
          final g = int.tryParse(parts[0]);
          out.add(HybridSymbol(g == null ? ManaType.fromSymbol(parts[0]) : null, ManaType.fromSymbol(parts[1]) ?? ManaType.C, generic: g ?? 0));
        } else {
          // {W/U/P} and other rarities: treat as Phyrexian of the first color.
          out.add(PhyrexianSymbol(ManaType.fromSymbol(parts[0]) ?? ManaType.C));
        }
      } else {
        final t = ManaType.fromSymbol(s);
        if (t != null) out.add(ColoredSymbol(t));
      }
    }
    return ManaCost(out);
  }

  int get manaValue => symbols.fold(0, (a, s) => a + s.manaValue);
  int get xCount => symbols.whereType<XSymbol>().length;
  bool get hasX => xCount > 0;
  bool get isEmpty => symbols.isEmpty;
  int get generic => symbols.whereType<GenericSymbol>().fold(0, (a, s) => a + s.amount);

  Set<ManaColor> get colors {
    final out = <ManaColor>{};
    for (final s in symbols) {
      switch (s) {
        case ColoredSymbol(:final type):
          if (type.color != null) out.add(type.color!);
        case HybridSymbol(:final a, :final b):
          if (a?.color != null) out.add(a!.color!);
          if (b.color != null) out.add(b.color!);
        case PhyrexianSymbol(:final type):
          if (type.color != null) out.add(type.color!);
        default:
      }
    }
    return out;
  }

  /// Adds [n] generic (n may be negative for reductions, which never reduce colored parts).
  ManaCost plusGeneric(int n) {
    if (n == 0) return this;
    final g = generic + n;
    final rest = symbols.where((s) => s is! GenericSymbol).toList();
    return ManaCost([if (g > 0) GenericSymbol(g), ...rest]);
  }

  ManaCost operator +(ManaCost other) => ManaCost([...symbols, ...other.symbols]).normalized();

  /// Generic merged into one symbol at the front.
  ManaCost normalized() {
    final g = generic;
    final rest = symbols.where((s) => s is! GenericSymbol).toList();
    return ManaCost([if (g > 0) GenericSymbol(g), ...rest]);
  }

  /// X replaced by generic [x] (CR 107.3a).
  ManaCost withX(int x) {
    final xs = xCount;
    if (xs == 0) return this;
    return ManaCost([...symbols.where((s) => s is! XSymbol), if (x * xs > 0) GenericSymbol(x * xs)]).normalized();
  }

  String get text => symbols.map((s) => s.text).join();

  @override
  String toString() => text;
}
