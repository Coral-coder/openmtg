// The engine's sort must give the same order on the Dart VM and in JavaScript (lockstep).
import 'package:rules/rules.dart';
import 'package:test/test.dart';

void main() {
  test('sortStable keeps equal elements in their original order', () {
    final items = [for (var i = 0; i < 200; i++) (key: (i * 7919) % 5, at: i)];
    items.sortStable((a, b) => a.key - b.key);
    for (var i = 1; i < items.length; i++) {
      final a = items[i - 1], b = items[i];
      expect(a.key <= b.key, isTrue);
      if (a.key == b.key) expect(a.at < b.at, isTrue, reason: 'stable');
    }
  });

  test('sortStable sorts short and empty lists', () {
    final empty = <int>[]..sortStable((a, b) => a - b);
    expect(empty, isEmpty);
    expect([3, 1, 2]..sortStable((a, b) => a - b), [1, 2, 3]);
  });
}
