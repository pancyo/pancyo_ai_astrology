import 'quantized_event_bracket.dart';

enum EventDayRelation { before, within, after, unresolved }
enum VoidMembership { outside, certain, unresolved }

/// Closed numerical time bounds, not independently verified celestial accuracy.
class LunarEventTimeRange {
  LunarEventTimeRange({required this.lowerUtc, required this.upperUtc,
    required this.source}) {
    if (!lowerUtc.isUtc || !upperUtc.isUtc || !lowerUtc.isBefore(upperUtc) ||
        source.trim().isEmpty) {
      throw ArgumentError('Positive UTC range and source required');
    }
  }
  factory LunarEventTimeRange.fromBracket(QuantizedEventBracket bracket) =>
      LunarEventTimeRange(lowerUtc: bracket.lowerUtc,
        upperUtc: bracket.upperUtc, source: bracket.before.source);
  final DateTime lowerUtc, upperUtc;
  final String source;

  bool strictlyBefore(LunarEventTimeRange other) {
    if (source != other.source) throw StateError('incomparable_sources');
    return upperUtc.isBefore(other.lowerUtc);
  }

  EventDayRelation relationToDay(DateTime startUtc, DateTime endUtc) {
    _checkDay(startUtc, endUtc);
    if (upperUtc.isBefore(startUtc)) return EventDayRelation.before;
    if (!lowerUtc.isBefore(endUtc)) return EventDayRelation.after;
    if (!lowerUtc.isBefore(startUtc) && upperUtc.isBefore(endUtc)) {
      return EventDayRelation.within;
    }
    return EventDayRelation.unresolved;
  }

  Map<String, Object?> toJson() => {
    'lower_utc': lowerUtc.toIso8601String(),
    'upper_utc': upperUtc.toIso8601String(),
    'bounds_inclusive': true,
    'source': source,
    'exact_instant_claimed': false,
  };
}

/// A ready interval has a definite positive core and uncertain edges. It is
/// conditional on the caller declaring complete major-aspect coverage for the
/// entire sign stay. Missing coverage never means there were no aspects.
class LunarVoidUncertainty {
  LunarVoidUncertainty._(this.status, this.reason, this.start, this.end);
  final String status, reason;
  final LunarEventTimeRange? start, end;
  bool get isReady => status == 'ready_under_declared_coverage';

  VoidMembership membership(DateTime instant) {
    if (!isReady) return VoidMembership.unresolved;
    final utc = instant.toUtc();
    if (utc.isBefore(start!.lowerUtc) || !utc.isBefore(end!.upperUtc)) {
      return VoidMembership.outside;
    }
    if (!utc.isBefore(start!.upperUtc) && utc.isBefore(end!.lowerUtc)) {
      return VoidMembership.certain;
    }
    return VoidMembership.unresolved;
  }

  Map<String, Object?> clipToDay(DateTime startUtc, DateTime endUtc) {
    _checkDay(startUtc, endUtc);
    if (!isReady) return {'status': status, 'reason': reason};
    DateTime later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
    DateTime earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
    final possibleStart = later(start!.lowerUtc, startUtc);
    final possibleEnd = earlier(end!.upperUtc, endUtc);
    final certainStart = later(start!.upperUtc, startUtc);
    final certainEnd = earlier(end!.lowerUtc, endUtc);
    final possible = possibleStart.isBefore(possibleEnd);
    final certain = certainStart.isBefore(certainEnd);
    return {
      'status': possible ? 'possible_overlap' : 'outside',
      'possible_start_utc': possible ? possibleStart.toIso8601String() : null,
      'possible_end_utc': possible ? possibleEnd.toIso8601String() : null,
      'certain_start_utc': certain ? certainStart.toIso8601String() : null,
      'certain_end_utc': certain ? certainEnd.toIso8601String() : null,
      'end_inclusive': false,
    };
  }

  Map<String, Object?> toJson() => {
    'artifact_type': 'pancyo_lunar_void_uncertainty_experiment_v1',
    'active_runtime_model': false,
    'status': status,
    'reason': reason,
    'start_range': start?.toJson(),
    'end_range': end?.toJson(),
    'coverage_verification': 'caller_declared_not_independently_verified',
    'membership_certainty_scope': 'numerical_bounds_under_caller_assumptions',
    'independent_astronomical_accuracy_verified': false,
  };
}

LunarVoidUncertainty resolveLunarVoidUncertainty({
  required LunarEventTimeRange signEntry,
  required LunarEventTimeRange signExit,
  required List<LunarEventTimeRange> majorAspects,
  required bool completeAspectCoverage,
}) {
  final ranges = List<LunarEventTimeRange>.of(majorAspects);
  if (signEntry.source != signExit.source ||
      ranges.any((range) => range.source != signEntry.source)) {
    throw StateError('incomparable_sources');
  }
  LunarVoidUncertainty unresolved(String reason) =>
      LunarVoidUncertainty._('unresolved', reason, null, null);
  if (!completeAspectCoverage) return unresolved('aspect_coverage_unconfirmed');
  if (!signEntry.strictlyBefore(signExit)) {
    return unresolved('sign_boundary_order_unconfirmed');
  }
  for (final aspect in ranges) {
    if (!signEntry.strictlyBefore(aspect) || !aspect.strictlyBefore(signExit)) {
      return unresolved('aspect_sign_membership_unconfirmed');
    }
  }
  var start = signEntry;
  if (ranges.isNotEmpty) {
    // A unique last event must be strictly after every other aspect. Earlier
    // ambiguous pairs do not matter if both are definitely before this one.
    final candidates = ranges.where((candidate) => ranges.every((other) =>
      identical(candidate, other) || other.strictlyBefore(candidate))).toList();
    if (candidates.length != 1) return unresolved('last_aspect_order_unconfirmed');
    start = candidates.single;
  }
  return LunarVoidUncertainty._('ready_under_declared_coverage',
      ranges.isEmpty ? 'no_major_aspect_in_sign' : 'last_major_aspect',
      start, signExit);
}

void _checkDay(DateTime start, DateTime end) {
  if (!start.isUtc || !end.isUtc || !start.isBefore(end)) {
    throw ArgumentError('Positive half-open UTC day required');
  }
}
