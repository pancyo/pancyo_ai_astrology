/// Independent numerical experiment; no connection to the legacy lunar solver.
/// The caller must supply an unwrapped increasing scalar and a justified upper
/// bound on input-time displacement. JD spacing alone does not justify that
/// bound. Continuity/monotonicity between reads and astronomical errors are
/// outside this contract; observed violations are rejected.
class QuantizedEventObservation {
  const QuantizedEventObservation({
    required this.utc,
    required this.coordinate,
    required this.residual,
    required this.source,
    required this.inputTimeRadius,
  });
  final DateTime utc;
  final double coordinate, residual;
  final String source;
  final Duration inputTimeRadius;
}

typedef QuantizedEventReader = QuantizedEventObservation Function(DateTime utc);

enum EventRangeOrder { before, after, unresolved }

class QuantizedEventBracket {
  QuantizedEventBracket._(this.before, this.after, this.radius,
      this.evaluationCount, this.requestedTolerance);
  final QuantizedEventObservation before, after;
  final Duration radius, requestedTolerance;
  final int evaluationCount;
  DateTime get lowerUtc => before.utc.subtract(radius);
  DateTime get upperUtc => after.utc.add(radius);
  Duration get width => upperUtc.difference(lowerUtc);

  /// Closed uncertainty ranges: even touching ranges do not prove an order.
  EventRangeOrder orderAgainst(QuantizedEventBracket other) {
    if (before.source != other.before.source) {
      throw StateError('incomparable_sources');
    }
    if (upperUtc.isBefore(other.lowerUtc)) return EventRangeOrder.before;
    if (lowerUtc.isAfter(other.upperUtc)) return EventRangeOrder.after;
    return EventRangeOrder.unresolved;
  }

  Map<String, Object?> toJson() => {
    'artifact_type': 'pancyo_quantized_event_bracket_experiment_v1',
    'active_runtime_model': false,
    'lower_utc': lowerUtc.toIso8601String(),
    'upper_utc': upperUtc.toIso8601String(),
    'bounds_inclusive': true,
    'width_microseconds': width.inMicroseconds,
    'input_time_radius_microseconds': radius.inMicroseconds,
    'input_time_radius_verification': 'caller_bound_not_independently_verified',
    'source': before.source,
    'evaluation_count': evaluationCount,
    'requested_tolerance_microseconds': requestedTolerance.inMicroseconds,
    'exact_instant_claimed': false,
    'independent_astronomical_accuracy_verified': false,
    'continuity_and_monotonicity_between_reads_verified': false,
  };
}

/// Refines strict before/after witnesses without turning a quantized zero into
/// an exact root. The grid floor limits the numerical witness width; the final
/// range additionally expands by the caller's input-time bound on both sides.
QuantizedEventBracket searchQuantizedEventBracket({
  required QuantizedEventReader read,
  required DateTime startUtc,
  required DateTime endUtc,
  required Duration maximumInputTimeRadius,
  Duration tolerance = const Duration(microseconds: 1),
  int maximumEvaluations = 256,
}) {
  if (!startUtc.isUtc || !endUtc.isUtc || !startUtc.isBefore(endUtc) ||
      maximumInputTimeRadius.inMicroseconds < 1 ||
      tolerance.inMicroseconds < 1 || maximumEvaluations < 2) {
    throw ArgumentError('Invalid UTC interval, bounds or evaluation budget');
  }
  final observations = <QuantizedEventObservation>[];
  String? identity;
  QuantizedEventObservation evaluate(DateTime utc) {
    for (final previous in observations) {
      if (previous.utc == utc) return previous;
    }
    if (observations.length >= maximumEvaluations) {
      throw StateError('evaluation_budget_exhausted');
    }
    final value = read(utc); // Acquisition errors propagate, with no fallback.
    if (!value.utc.isUtc || value.utc != utc ||
        !value.coordinate.isFinite || !value.residual.isFinite ||
        value.source.trim().isEmpty || value.inputTimeRadius.inMicroseconds < 1 ||
        value.inputTimeRadius > maximumInputTimeRadius) {
      throw StateError('invalid_observation');
    }
    if (identity != null && identity != value.source) {
      throw StateError('source_changed');
    }
    for (final previous in observations) {
      final earlier = previous.utc.isBefore(utc) ? previous : value;
      final later = previous.utc.isBefore(utc) ? value : previous;
      if (earlier.coordinate > later.coordinate ||
          earlier.residual > later.residual ||
          (earlier.coordinate == later.coordinate &&
              earlier.residual != later.residual)) {
        throw StateError('nonmonotonic_or_inconsistent_observation');
      }
    }
    identity = value.source;
    observations.add(value);
    return value;
  }

  var before = evaluate(startUtc);
  var after = evaluate(endUtc);
  if (before.residual >= 0 || after.residual <= 0) {
    throw StateError('strict_before_and_after_required');
  }
  final gridFloor = 4 * maximumInputTimeRadius.inMicroseconds + 4;
  final stopWidth = tolerance.inMicroseconds > gridFloor
      ? tolerance.inMicroseconds : gridFloor;
  while (after.utc.difference(before.utc).inMicroseconds > stopWidth) {
    final oldWidth = after.utc.difference(before.utc).inMicroseconds;
    final middle = before.utc.add(Duration(microseconds: oldWidth ~/ 2));
    final value = evaluate(middle);
    if (value.residual < 0) {
      before = value;
    } else if (value.residual > 0) {
      after = value;
    } else {
      // Search both sides of a zero plateau. Never collapse to the zero read.
      final left = evaluate(before.utc.add(Duration(microseconds: oldWidth ~/ 4)));
      final right = evaluate(before.utc.add(Duration(microseconds: 3 * oldWidth ~/ 4)));
      if (left.residual < 0) before = left;
      if (right.residual > 0) after = right;
    }
    if (after.utc.difference(before.utc).inMicroseconds == oldWidth) {
      throw StateError('zero_plateau_unresolved');
    }
  }
  return QuantizedEventBracket._(before, after, maximumInputTimeRadius,
      observations.length, tolerance);
}
