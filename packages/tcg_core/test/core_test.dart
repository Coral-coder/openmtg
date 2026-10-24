import 'package:tcg_core/tcg_core.dart';
import 'package:test/test.dart';

void main() {
  test('the seeded generator repeats exactly for a seed', () {
    final a = SeededRng(42), b = SeededRng(42);
    expect([for (var i = 0; i < 20; i++) a.nextInt(1000)], [for (var i = 0; i < 20; i++) b.nextInt(1000)]);
  });

  test('a generator resumes from its saved state', () {
    final a = SeededRng(7)..nextInt(10);
    final b = SeededRng.fromState(a.state);
    expect(a.nextInt(1 << 30), b.nextInt(1 << 30));
  });

  test('sortStable keeps ties in order', () {
    final xs = [(1, 'a'), (0, 'b'), (1, 'c'), (0, 'd')]..sortStable((x, y) => x.$1 - y.$1);
    expect(xs.map((x) => x.$2).join(), 'bdac');
  });
}
