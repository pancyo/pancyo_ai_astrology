import 'quantized_event_bracket.dart';

/// Experimental enumeration of an already unwrapped increasing scalar.
/// Endpoint checks cannot prove continuity/monotonicity between reads. The
/// caller's maximum travel and input-time bound remain explicit assumptions.
class QuantizedScannedEvent {
  QuantizedScannedEvent(this.targetDegrees, this.bracket);
  final double targetDegrees;
  final QuantizedEventBracket bracket;
}

class QuantizedEventScanResult {
  QuantizedEventScanResult._(this.startUtc, this.endUtc, this.source,
      List<QuantizedScannedEvent> events, List<double> unresolved,
      List<QuantizedEventObservation> witnesses, this.evaluationCount,
      this.scanStep, this.maximumInputTimeRadius, this.periodDegrees,
      this.maximumStepTravelDegrees, List<double> offsets)
      : events = List.unmodifiable(events),
        unresolvedBoundaryTargets = List.unmodifiable(unresolved),
        scanWitnesses = List.unmodifiable(witnesses),
        targetOffsetsDegrees = List.unmodifiable(offsets);
  final DateTime startUtc, endUtc;
  final String source;
  final List<QuantizedScannedEvent> events;
  final List<double> unresolvedBoundaryTargets;
  final List<QuantizedEventObservation> scanWitnesses;
  final int evaluationCount;
  final Duration scanStep, maximumInputTimeRadius;
  final double periodDegrees, maximumStepTravelDegrees;
  final List<double> targetOffsetsDegrees;
  bool get completeMeasuredSpanUnderAssumptions => unresolvedBoundaryTargets.isEmpty;
  Map<String, Object?> toJson() => {
    'artifact_type': 'pancyo_quantized_event_scan_experiment_v1',
    'active_runtime_model': false,
    'start_utc': startUtc.toIso8601String(),
    'end_utc': endUtc.toIso8601String(),
    'source': source,
    'complete_measured_span_under_caller_assumptions': completeMeasuredSpanUnderAssumptions,
    'coverage_scope': 'measured_scalar_span_not_full_utc_interval',
    'scan_step_microseconds': scanStep.inMicroseconds,
    'maximum_input_time_radius_microseconds': maximumInputTimeRadius.inMicroseconds,
    'period_degrees': periodDegrees,
    'target_offsets_degrees': targetOffsetsDegrees,
    'maximum_step_travel_degrees': maximumStepTravelDegrees,
    'input_time_bound_and_interread_monotonicity_verification': 'caller_assumptions',
    'independent_coverage_verified': false,
    'independent_astronomical_accuracy_verified': false,
    'unresolved_boundary_targets': unresolvedBoundaryTargets,
    'evaluation_count': evaluationCount,
    'scan_witnesses': [for (final w in scanWitnesses) {
      'utc': w.utc.toIso8601String(), 'coordinate': w.coordinate,
      'unwrapped_degrees': w.residual,
    }],
    'events': [for (final event in events) {
      'target_degrees': event.targetDegrees, 'bracket': event.bracket.toJson(),
    }],
  };
}

QuantizedEventScanResult scanQuantizedEvents({
  required QuantizedEventReader readUnwrapped,
  required DateTime startUtc,
  required DateTime endUtc,
  required Duration scanStep,
  required Duration maximumInputTimeRadius,
  required double periodDegrees,
  required List<double> targetOffsetsDegrees,
  required double maximumStepTravelDegrees,
  int maximumEvaluations = 10000,
  int maximumEvents = 1000,
  bool Function()? isCancelled,
}) {
  final offsets = List<double>.of(targetOffsetsDegrees)..sort();
  if (!startUtc.isUtc || !endUtc.isUtc || !startUtc.isBefore(endUtc) ||
      scanStep.inMicroseconds <= 0 || maximumInputTimeRadius.inMicroseconds < 1 ||
      !periodDegrees.isFinite || periodDegrees <= 0 ||
      !maximumStepTravelDegrees.isFinite || maximumStepTravelDegrees <= 0 ||
      offsets.isEmpty || offsets.any((o) => !o.isFinite || o < 0 || o >= periodDegrees) ||
      offsets.toSet().length != offsets.length ||
      maximumEvaluations < 2 || maximumEvents < 1) {
    throw ArgumentError('Invalid scan contract');
  }
  final cache = <DateTime, QuantizedEventObservation>{};
  String? source;
  QuantizedEventObservation evaluate(DateTime utc) {
    if (isCancelled?.call() == true) throw StateError('scan_cancelled');
    if (cache.containsKey(utc)) return cache[utc]!;
    if (cache.length >= maximumEvaluations) throw StateError('scan_budget_exhausted');
    final value = readUnwrapped(utc);
    if (!value.utc.isUtc || value.utc != utc || !value.coordinate.isFinite ||
        !value.residual.isFinite || value.source.trim().isEmpty ||
        value.inputTimeRadius.inMicroseconds < 1 ||
        value.inputTimeRadius > maximumInputTimeRadius) {
      throw StateError('invalid_scan_observation');
    }
    if (source != null && value.source != source) throw StateError('source_changed');
    for (final old in cache.values) {
      final a = old.utc.isBefore(utc) ? old : value;
      final b = old.utc.isBefore(utc) ? value : old;
      if (a.coordinate > b.coordinate || a.residual > b.residual ||
          (a.coordinate == b.coordinate && a.residual != b.residual)) {
        throw StateError('nonmonotonic_or_inconsistent_scan');
      }
    }
    source = value.source;
    cache[utc] = value;
    return value;
  }

  final witnesses = <QuantizedEventObservation>[evaluate(startUtc)];
  var cursor = startUtc;
  while (cursor.isBefore(endUtc)) {
    final remaining = endUtc.difference(cursor);
    cursor = cursor.add(remaining < scanStep ? remaining : scanStep);
    final next = evaluate(cursor);
    final travel = next.residual - witnesses.last.residual;
    if (travel > maximumStepTravelDegrees) throw StateError('step_travel_exceeded');
    witnesses.add(next);
  }
  final first = witnesses.first.residual;
  final last = witnesses.last.residual;
  final targets = <double>[];
  for (final offset in offsets) {
    var index = ((first - offset) / periodDegrees).ceil();
    while (true) {
      final target = index * periodDegrees + offset;
      if (!target.isFinite) throw StateError('target_overflow');
      if (target > last) break;
      if (targets.length >= maximumEvents) throw StateError('event_budget_exhausted');
      targets.add(target);
      final following = (index + 1) * periodDegrees + offset;
      if (following <= target) throw StateError('target_resolution_exhausted');
      index++;
    }
  }
  targets.sort();
  final events = <QuantizedScannedEvent>[];
  final unresolved = <double>[];
  for (final target in targets) {
    if (target <= first || target >= last) {
      unresolved.add(target); // Exterior witnesses must be acquired separately.
      continue;
    }
    // Locate strict witnesses, skipping equal/flat scan nodes on both sides.
    final before = witnesses.lastWhere((w) => w.residual < target);
    final after = witnesses.firstWhere((w) => w.residual > target);
    final bracket = searchQuantizedEventBracket(
      startUtc: before.utc, endUtc: after.utc,
      maximumInputTimeRadius: maximumInputTimeRadius,
      read: (utc) {
        final w = evaluate(utc);
        return QuantizedEventObservation(utc: utc, coordinate: w.coordinate,
          residual: w.residual - target, source: w.source,
          inputTimeRadius: w.inputTimeRadius);
      });
    events.add(QuantizedScannedEvent(target, bracket));
  }
  return QuantizedEventScanResult._(startUtc, endUtc, source!, events,
      unresolved, witnesses, cache.length, scanStep, maximumInputTimeRadius,
      periodDegrees, maximumStepTravelDegrees, offsets);
}
