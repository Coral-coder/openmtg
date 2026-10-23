/// A stable sort the engine and the computer player use instead of [List.sort]: the Dart VM and
/// JavaScript sort with different algorithms, so equal elements could end up in a different
/// order in a browser than on a phone, and a game would diverge. A merge sort keeps equal
/// elements in their original order everywhere.
extension StableSort<T> on List<T> {
  void sortStable(int Function(T a, T b) compare) {
    if (length < 2) return;
    final tmp = List<T>.of(this);
    _mergeSort(tmp, this, 0, length, compare);
  }
}

/// Sorts src[lo, hi) into dst[lo, hi) (src and dst start with the same contents).
void _mergeSort<T>(List<T> src, List<T> dst, int lo, int hi, int Function(T, T) compare) {
  if (hi - lo < 2) return;
  final mid = (lo + hi) >> 1;
  _mergeSort(dst, src, lo, mid, compare);
  _mergeSort(dst, src, mid, hi, compare);
  var i = lo, j = mid, k = lo;
  while (i < mid && j < hi) {
    dst[k++] = compare(src[j], src[i]) < 0 ? src[j++] : src[i++];
  }
  while (i < mid) {
    dst[k++] = src[i++];
  }
  while (j < hi) {
    dst[k++] = src[j++];
  }
}
