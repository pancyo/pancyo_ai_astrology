/// Memoizes only identical search intervals; never rounds or joins boundaries.
/// Each owner (and isolate) has its own bounded FIFO, including null results.
class MoonVoidSegmentMemo {
  MoonVoidSegmentMemo({this.maximumEntries = 64}) {
    if (maximumEntries < 1) throw ArgumentError.value(maximumEntries);
  }

  final int maximumEntries;
  final _entries = <(int, bool, int, bool), DateTime?>{};
  int hits = 0;
  int misses = 0;

  int get length => _entries.length;

  DateTime? resolve(
    DateTime start,
    DateTime end,
    DateTime? Function() compute, {
    bool Function()? shouldRetain,
  }) {
    // Include representation as well as the exact microsecond instant, so a
    // cached local DateTime can never substitute for a UTC result or vice versa.
    final key = (
      start.microsecondsSinceEpoch,
      start.isUtc,
      end.microsecondsSinceEpoch,
      end.isUtc,
    );
    if (_entries.containsKey(key)) {
      hits++;
      return _entries[key];
    }
    misses++;
    final result = compute(); // Exceptions are deliberately not retained.
    if (shouldRetain != null && !shouldRetain()) return result;
    if (_entries.length == maximumEntries) _entries.remove(_entries.keys.first);
    _entries[key] = result;
    return result;
  }

  void clear() {
    _entries.clear();
    hits = 0;
    misses = 0;
  }
}
